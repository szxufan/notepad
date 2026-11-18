/// 草稿管理服务。
///
/// 负责将所有打开的文件列表和内容持久化为草稿，
/// 支持 30 秒定时自动保存和启动时恢复。
library services.draft_service;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/note_file.dart';
import 'encoding_service.dart';
import 'file_service.dart';

/// 草稿服务类。
class DraftService {
  DraftService({EncodingService? encodingService, this.fileService})
      : encodingService = encodingService ?? const EncodingService();

  /// 编码服务（按草稿记录的编码读取磁盘新内容）。
  final EncodingService encodingService;

  /// 文件服务（可选，用于恢复只读大文件时复用大小/编码逻辑）。
  final FileService? fileService;

  /// 草稿文件名。
  static const String draftFileName = 'drafts.json';

  /// 自动保存间隔（30 秒）。
  static const Duration autoSaveInterval = Duration(seconds: 30);

  Timer? _autoSaveTimer;

  /// 测试用的草稿目录覆盖路径。
  ///
  /// 为 null 时使用 [getApplicationSupportDirectory]。
  /// 测试中可设置此字段以避免依赖平台插件。
  String? testDraftDir;

  /// 获取草稿文件路径。
  Future<String> get _draftPath async {
    if (testDraftDir != null) {
      return p.join(testDraftDir!, draftFileName);
    }
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, draftFileName);
  }

  /// 保存草稿到磁盘。
  ///
  /// 将 [files] 序列化为 JSON 并写入 [draftFileName]。
  /// 调用方应 `await` 此方法确保落盘完成。
  Future<void> saveDrafts(List<NoteFile> files) async {
    try {
      final path = await _draftPath;
      final file = File(path);
      // 确保目录存在
      final dir = file.parent;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final jsonList = files.map((f) {
        final json = f.toJson();
        // 只读大文件不持久化内容，恢复时从磁盘重读，避免草稿膨胀
        if (f.isReadOnly && f.filePath != null) {
          json['content'] = '';
          json['diskContent'] = null;
        }
        return json;
      }).toList();
      final jsonStr = const JsonEncoder().convert(jsonList);
      // 先写入临时文件再重命名，保证原子性
      final tempPath = '$path.tmp';
      final tempFile = File(tempPath);
      await tempFile.writeAsString(jsonStr);
      await tempFile.rename(path);
    } catch (e) {
      // 草稿保存失败不应中断应用
      stderr.writeln('草稿保存失败: $e');
    }
  }

  /// 从磁盘加载草稿。
  ///
  /// 恢复文件列表和内容。对已保存文件比较草稿 [lastModified]
  /// 与磁盘文件修改时间——草稿更新则用草稿内容，否则读取磁盘内容；
  /// 未保存文件直接用草稿内容。
  /// 草稿文件不存在时返回空列表。
  Future<List<NoteFile>> loadDrafts() async {
    try {
      final path = await _draftPath;
      final file = File(path);
      if (!file.existsSync()) {
        return [];
      }
      final jsonStr = await file.readAsString();
      final jsonList = json.decode(jsonStr) as List<dynamic>;
      final drafts = jsonList
          .map((e) => NoteFile.fromJson(e as Map<String, dynamic>))
          .toList();
      // 对每个已保存文件，决定使用草稿内容还是磁盘内容
      final result = <NoteFile>[];
      for (final draft in drafts) {
        try {
          // 只读大文件：草稿不含内容，从磁盘重开（复用大小/编码逻辑）
          if (draft.isReadOnly && draft.filePath != null) {
            final service = fileService;
            if (service != null && File(draft.filePath!).existsSync()) {
              result.add(
                  service.openFile(draft.filePath!).copyWith(id: draft.id));
            } else {
              result.add(draft);
            }
            continue;
          }
          if (draft.filePath != null && File(draft.filePath!).existsSync()) {
            final stat = FileStat.statSync(draft.filePath!);
            final diskModified = stat.modified;
            // 草稿更新则用草稿内容，否则读取磁盘内容
            if (draft.lastModified.isAfter(diskModified) ||
                draft.lastModified.isAtSameMomentAs(diskModified)) {
              result.add(draft);
            } else {
              final service = fileService;
              if (service != null &&
                  stat.size > service.readOnlyThresholdBytes) {
                // 打开后文件可能已增长为大文件，必须复用预览与上限保护，
                // 不能沿普通草稿路径全量读入。
                result.add(
                    service.openFile(draft.filePath!).copyWith(id: draft.id));
              } else {
                // 磁盘文件更新，按草稿记录的编码重新读取。
                final bytes = File(draft.filePath!).readAsBytesSync();
                final diskContent =
                    encodingService.decode(bytes, draft.encoding);
                result.add(draft.copyWith(
                  content: diskContent,
                  diskContent: diskContent,
                  isDirty: false,
                  lastModified: diskModified,
                  lastSavedAt: diskModified,
                ));
              }
            }
          } else {
            // 未保存文件或磁盘文件已删除，直接用草稿内容
            result.add(draft);
          }
        } catch (e) {
          // 单个文件读取失败时保留其草稿，不影响其他文件恢复。
          stderr.writeln('恢复文件草稿失败 (${draft.filePath ?? draft.title}): $e');
          result.add(draft);
        }
      }
      return result;
    } catch (e) {
      stderr.writeln('草稿加载失败: $e');
      return [];
    }
  }

  /// 启动自动保存定时器。
  ///
  /// 每 [autoSaveInterval] 调用一次 [saveDrafts]。
  /// [getFiles] 回调返回当前需要保存的文件列表。
  void startAutoSave(Future<List<NoteFile>> Function() getFiles) {
    stopAutoSave();
    _autoSaveTimer = Timer.periodic(autoSaveInterval, (_) async {
      final files = await getFiles();
      await saveDrafts(files);
    });
  }

  /// 停止自动保存定时器。
  void stopAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
  }

  /// 清除草稿文件。
  Future<void> clearDrafts() async {
    try {
      final path = await _draftPath;
      final file = File(path);
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (e) {
      stderr.writeln('清除草稿失败: $e');
    }
  }
}
