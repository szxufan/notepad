/// 文件列表状态管理。
///
/// 管理所有打开的文件列表、当前活动文件，
/// 以及文件的增删改查操作。
library providers.file_list_provider;

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/ai_config.dart';
import '../models/note_file.dart';
import '../services/ai_title_service.dart';
import '../services/file_service.dart';

/// 文件列表 Provider。
class FileListProvider extends ChangeNotifier {
  FileListProvider({
    required this.fileService,
    this.aiTitleService,
    this.aiConfigGetter,
  });

  /// 文件服务实例。
  final FileService fileService;

  /// AI 标题服务实例（可选，未注入时 AI 功能不可用）。
  final AiTitleService? aiTitleService;

  /// AI 配置读取回调（可选）。
  final AiConfig Function()? aiConfigGetter;

  /// 内容长度阈值：不超过该值时标题取首行，首次超过后调用 AI。
  static const int shortContentThreshold = 64;

  /// 首行标题最大字数。
  static const int firstLineTitleLength = 16;

  /// 正在生成 AI 标题的文件 ID 集合。
  final Set<String> _aiTitlePending = {};

  /// 所有打开的文件列表。
  final List<NoteFile> _files = [];

  /// 获取文件列表（只读）。
  List<NoteFile> get files => List.unmodifiable(_files);

  /// 当前活动文件 ID。
  String? _activeFileId;

  /// 获取当前活动文件 ID。
  String? get activeFileId => _activeFileId;

  /// 获取当前活动文件。
  NoteFile? get activeFile {
    if (_activeFileId == null) return null;
    return _files.cast<NoteFile?>().firstWhere(
          (f) => f?.id == _activeFileId,
          orElse: () => null,
        );
  }

  /// 文件列表是否为空。
  bool get isEmpty => _files.isEmpty;

  /// 获取所有文件（用于草稿保存）。
  List<NoteFile> get allFiles => List.unmodifiable(_files);

  /// 从草稿恢复文件列表。
  ///
  /// [drafts] 为从草稿加载的文件列表。
  void loadFromDrafts(List<NoteFile> drafts) {
    _files.clear();
    _files.addAll(drafts);
    _activeFileId = drafts.isNotEmpty ? drafts.first.id : null;
    notifyListeners();
  }

  /// 新建文件。
  NoteFile addNewFile() {
    final file = fileService.createNewFile();
    _files.add(file);
    _activeFileId = file.id;
    notifyListeners();
    return file;
  }

  /// 打开已有文件。
  ///
  /// [path] 为文件绝对路径。
  /// 如果文件已打开则切换到该文件。
  NoteFile openFile(String path) {
    // 检查是否已打开
    final existingIndex = _files.indexWhere((f) => f.filePath == path);
    if (existingIndex >= 0) {
      _activeFileId = _files[existingIndex].id;
      notifyListeners();
      return _files[existingIndex];
    }
    final file = fileService.openFile(path);
    _files.add(file);
    _activeFileId = file.id;
    notifyListeners();
    return file;
  }

  /// 关闭文件。
  ///
  /// 如果关闭的是活动文件，则切换到相邻文件。
  /// 返回被关闭的文件（如果有未保存修改，调用方应先确认）。
  NoteFile? closeFile(String id) {
    final index = _files.indexWhere((f) => f.id == id);
    if (index < 0) return null;
    final closed = _files.removeAt(index);
    // 调整活动文件
    if (_activeFileId == id) {
      if (_files.isEmpty) {
        _activeFileId = null;
      } else if (index < _files.length) {
        _activeFileId = _files[index].id;
      } else {
        _activeFileId = _files.last.id;
      }
    }
    notifyListeners();
    return closed;
  }

  /// 切换活动文件。
  void switchToFile(String id) {
    if (_activeFileId == id) return;
    if (_files.any((f) => f.id == id)) {
      _activeFileId = id;
      notifyListeners();
    }
  }

  /// 保存文件到磁盘。
  ///
  /// 如果文件未命名（filePath 为 null），应先调用 [saveFileAs]。
  Future<void> saveFile(String id) async {
    final index = _files.indexWhere((f) => f.id == id);
    if (index < 0) return;
    final file = _files[index];
    final saved = await fileService.saveFile(file);
    _files[index] = saved;
    notifyListeners();
  }

  /// 另存为。
  ///
  /// 返回是否成功保存。用户取消时返回 false。
  Future<bool> saveFileAs(String id) async {
    final index = _files.indexWhere((f) => f.id == id);
    if (index < 0) return false;
    final file = _files[index];
    final saved = await fileService.saveFileAs(file);
    if (saved == null) return false;
    _files[index] = saved;
    notifyListeners();
    return true;
  }

  /// 更新文件内容。
  void updateContent(String id, String content) {
    final index = _files.indexWhere((f) => f.id == id);
    if (index < 0) return;
    final file = _files[index];
    if (file.content == content) return;
    var updated = file.copyWith(
      content: content,
      isDirty: content != file.diskContent,
      lastModified: DateTime.now(),
    );
    updated = _applyAutoTitle(updated);
    _files[index] = updated;
    notifyListeners();
  }

  /// 自动标题逻辑（仅新建未保存文件）。
  ///
  /// 内容不超过 [shortContentThreshold] 字时，标题取首行前
  /// [firstLineTitleLength] 字；首次超过后锁定标题并静默触发 AI 生成。
  NoteFile _applyAutoTitle(NoteFile file) {
    if (!file.isNew) return file;
    final content = file.content;
    if (content.trim().isEmpty) return file;

    if (content.length <= shortContentThreshold) {
      if (!file.isTitleLocked) {
        return file.copyWith(title: _firstLineTitle(content));
      }
      return file;
    }

    // 内容超过阈值
    if (!file.isTitleLocked) {
      // 锁定标题为首行截断，作为 AI 失败时的降级标题
      file = file.copyWith(
        title: _firstLineTitle(content),
        isTitleLocked: true,
      );
    }
    if (!file.hasAiTitle && !_aiTitlePending.contains(file.id)) {
      file = file.copyWith(hasAiTitle: true);
      _autoGenerateAiTitle(file.id, content);
    }
    return file;
  }

  /// 取内容首行的前 [firstLineTitleLength] 字作为标题。
  String _firstLineTitle(String content) {
    var firstLine = content.split('\n').first.trim();
    if (firstLine.length > firstLineTitleLength) {
      firstLine = firstLine.substring(0, firstLineTitleLength);
    }
    return firstLine;
  }

  /// 后台静默调用 AI 生成标题（对用户无感）。
  ///
  /// 不 await、无 loading UI；失败时仅记录日志，保留降级标题。
  void _autoGenerateAiTitle(String id, String content) {
    _aiTitlePending.add(id);
    () async {
      try {
        final service = aiTitleService;
        final config = aiConfigGetter?.call();
        if (service != null && config != null && config.isConfigured) {
          final title = await service.generateTitle(content, config);
          final index = _files.indexWhere((f) => f.id == id);
          if (index >= 0) {
            _files[index] = _files[index].copyWith(title: title);
            notifyListeners();
          }
        }
      } catch (e) {
        stderr.writeln('AI 自动生成标题失败: $e');
      } finally {
        _aiTitlePending.remove(id);
      }
    }();
  }

  /// 指定文件是否正在生成 AI 标题。
  bool isAiTitleGenerating(String id) => _aiTitlePending.contains(id);

  /// 手动触发 AI 生成标题（即使内容在 64 字以内）。
  ///
  /// 仅对新建未保存且内容非空的文件生效。
  /// AI 未配置或生成失败时抛出 [AiTitleException]，由 UI 提示用户。
  Future<void> generateTitleManually(String id) async {
    final file = getFile(id);
    if (file == null || !file.isNew || file.content.trim().isEmpty) return;
    if (_aiTitlePending.contains(id)) return;

    final service = aiTitleService;
    final config = aiConfigGetter?.call();
    if (service == null || config == null || !config.isConfigured) {
      throw const AiTitleException('AI 接口未配置，请先在设置中完成配置');
    }

    _aiTitlePending.add(id);
    notifyListeners();
    try {
      final title = await service.generateTitle(file.content, config);
      final index = _files.indexWhere((f) => f.id == id);
      if (index >= 0) {
        _files[index] = _files[index].copyWith(
          title: title,
          hasAiTitle: true,
          isTitleLocked: true,
        );
      }
    } finally {
      _aiTitlePending.remove(id);
      notifyListeners();
    }
  }

  /// 获取指定 ID 的文件。
  NoteFile? getFile(String id) {
    final index = _files.indexWhere((f) => f.id == id);
    return index >= 0 ? _files[index] : null;
  }

  /// 保存所有未保存的文件。
  Future<void> saveAll() async {
    for (var i = 0; i < _files.length; i++) {
      final file = _files[i];
      if (file.isDirty && file.filePath != null) {
        final saved = await fileService.saveFile(file);
        _files[i] = saved;
      }
    }
    notifyListeners();
  }

  /// 用外部修改后的磁盘内容重载文件。
  ///
  /// 更新内容与磁盘快照，清除未保存状态。
  void applyExternalReload(String id, String newDiskContent) {
    final index = _files.indexWhere((f) => f.id == id);
    if (index < 0) return;
    final now = DateTime.now();
    _files[index] = _files[index].copyWith(
      content: newDiskContent,
      diskContent: newDiskContent,
      isDirty: false,
      lastModified: now,
      lastSavedAt: now,
    );
    notifyListeners();
  }

  /// 仅更改文件的保存编码（不重读磁盘内容）。
  ///
  /// 用于保存失败后转为 UTF-8 等场景，保留本地编辑内容。
  void setSaveEncoding(String id, String encodingName) {
    final index = _files.indexWhere((f) => f.id == id);
    if (index < 0) return;
    _files[index] = _files[index].copyWith(encoding: encodingName);
    notifyListeners();
  }

  /// 切换文件编码。
  ///
  /// 有磁盘路径的文件：重读磁盘并按新编码解码，内容与快照同步更新
  /// （会丢弃本地未保存修改，调用方应先确认）。
  /// 未保存的新文件：仅更改保存时的目标编码。
  /// 读取失败时抛出 [FileSystemException]。
  Future<void> switchEncoding(String id, String encodingName) async {
    final index = _files.indexWhere((f) => f.id == id);
    if (index < 0) return;
    final file = _files[index];
    if (file.filePath == null) {
      setSaveEncoding(id, encodingName);
      return;
    }
    final text =
        fileService.readFileWithEncoding(file.filePath!, encodingName);
    final stat = FileStat.statSync(file.filePath!);
    _files[index] = file.copyWith(
      content: text,
      diskContent: text,
      encoding: encodingName,
      isDirty: false,
      lastModified: stat.modified,
      lastSavedAt: stat.modified,
    );
    notifyListeners();
  }
}
