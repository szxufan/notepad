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

/// 草稿服务类。
class DraftService {
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
      final jsonList = files.map((f) => f.toJson()).toList();
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
        if (draft.filePath != null && File(draft.filePath!).existsSync()) {
          final stat = FileStat.statSync(draft.filePath!);
          final diskModified = stat.modified;
          // 草稿更新则用草稿内容，否则读取磁盘内容
          if (draft.lastModified.isAfter(diskModified) ||
              draft.lastModified.isAtSameMomentAs(diskModified)) {
            result.add(draft);
          } else {
            // 磁盘文件更新，重新读取
            final diskContent = File(draft.filePath!).readAsStringSync();
            result.add(draft.copyWith(
              content: diskContent,
              diskContent: diskContent,
              isDirty: false,
              lastModified: diskModified,
              lastSavedAt: diskModified,
            ));
          }
        } else {
          // 未保存文件或磁盘文件已删除，直接用草稿内容
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
