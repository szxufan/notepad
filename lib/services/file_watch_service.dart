/// 文件外部修改监听服务。
///
/// 定时轮询已打开文件的磁盘内容，检测到外部修改时通过回调通知调用方。
/// 通过独立的磁盘内容快照过滤本应用自身的保存，并避免重复通知同一版本。
library services.file_watch_service;

import 'dart:async';
import 'dart:io';

import '../models/note_file.dart';
import 'encoding_service.dart';
import 'file_service.dart';

/// 上次成功读取的磁盘状态。
class _DiskSnapshot {
  const _DiskSnapshot({required this.modified, required this.content});

  final DateTime? modified;
  final String? content;
}

/// 文件监听服务类。
class FileWatchService {
  FileWatchService({
    required this.encodingService,
    FileService? fileService,
    Future<List<int>> Function(String path)? readBytes,
  })  : _fileService =
            fileService ?? FileService(encodingService: encodingService),
        _readBytes = readBytes ?? ((path) => File(path).readAsBytes());

  /// 编码服务（按文件编码解码磁盘内容用于比对）。
  final EncodingService encodingService;

  /// 大小阈值来源，防止已打开文件增大后仍被全量读取。
  final FileService _fileService;

  /// 磁盘字节读取入口，注入后可模拟临时读取失败。
  final Future<List<int>> Function(String path) _readBytes;

  /// 轮询间隔。
  static const Duration checkInterval = Duration(seconds: 3);

  Timer? _timer;

  /// 是否正在检查（防止异步重叠）。
  bool _checking = false;

  /// 文件被外部修改时的回调（参数为文件快照与磁盘新内容）。
  void Function(NoteFile file, String newDiskContent)? onExternalChange;

  /// 文件被外部删除时的回调（同一次删除只触发一次）。
  void Function(NoteFile file)? onFileDeleted;

  /// 已打开文件增大到只读阈值以上时的回调（连续超限只通知一次）。
  void Function(NoteFile file, int sizeBytes)? onFileTooLarge;

  /// 已连续超限并通知过的文件。
  final Set<String> _oversizedFileIds = {};

  /// 各文件上次成功处理的磁盘快照。
  final Map<String, _DiskSnapshot> _snapshots = {};

  /// 获取当前打开文件列表的回调。
  List<NoteFile> Function()? _getFiles;

  /// 启动监听。
  ///
  /// [getFiles] 回调返回当前需要监听的文件列表。
  /// 启动时按当前文件快照初始化记录，避免草稿恢复的文件误报。
  void start(List<NoteFile> Function() getFiles) {
    stop();
    _getFiles = getFiles;
    for (final file in getFiles()) {
      final path = file.filePath;
      if (path == null) continue;
      DateTime? modified;
      try {
        modified = _statModified(path);
      } catch (e) {
        stderr.writeln('监听文件状态读取失败: $e');
      }
      _snapshots[file.id] = _DiskSnapshot(
        modified: modified,
        content: file.diskContent,
      );
    }
    _timer = Timer.periodic(checkInterval, (_) => checkNow());
  }

  /// 停止监听。
  void stop() {
    _timer?.cancel();
    _timer = null;
    _getFiles = null;
    _snapshots.clear();
    _oversizedFileIds.clear();
  }

  /// 立即执行一次检查（定时器回调调用，测试可直接调用）。
  Future<void> checkNow() async {
    if (_checking) return;
    final getFiles = _getFiles;
    if (getFiles == null) return;
    _checking = true;
    try {
      final files = getFiles();
      // 清理已关闭文件的记录
      final ids = files.map((f) => f.id).toSet();
      _snapshots.removeWhere((id, _) => !ids.contains(id));
      _oversizedFileIds.removeWhere((id) => !ids.contains(id));
      for (final file in files) {
        final path = file.filePath;
        if (path == null) continue;
        // 只读大文件跳过轮询，避免每 3 秒全量读取大文件
        if (file.isReadOnly) continue;
        await _checkFile(file, path);
      }
    } finally {
      _checking = false;
    }
  }

  /// 检查单个文件的磁盘状态。
  Future<void> _checkFile(NoteFile file, String path) async {
    final previous = _snapshots[file.id];
    late FileStat stat;
    try {
      stat = FileStat.statSync(path);
    } catch (e) {
      // 状态读取失败不能当作文件删除，保留快照等待下次重试。
      stderr.writeln('监听文件状态读取失败: $e');
      return;
    }
    if (stat.type == FileSystemEntityType.notFound) {
      // 文件消失：仅此前存在时通知一次
      _oversizedFileIds.remove(file.id);
      _snapshots[file.id] = const _DiskSnapshot(modified: null, content: null);
      if (previous?.modified != null) {
        onFileDeleted?.call(file);
      }
      return;
    }
    final modified = stat.modified;
    if (stat.size > _fileService.readOnlyThresholdBytes) {
      // 初次打开后文件可能增长到数十 MB。保留当前内存内容并暂停
      // 自动重载，由界面提示用户关闭后重新以只读预览打开。
      if (_oversizedFileIds.add(file.id)) {
        onFileTooLarge?.call(file, stat.size);
      }
      return;
    }
    _oversizedFileIds.remove(file.id);

    late String diskText;
    try {
      // 每次均比对内容，覆盖保留 mtime 或同精度时间内连续写入的情况。
      final bytes = await _readBytes(path);
      diskText = encodingService.decode(bytes, file.encoding);
    } catch (e) {
      // 读取失败不推进快照，文件恢复可读后仍会处理这次修改。
      stderr.writeln('监听文件读取失败: $e');
      return;
    }

    // 首次发现新打开的文件时，以其打开时的快照作为比较基线。
    final previousContent = previous?.content ?? file.diskContent;
    _snapshots[file.id] = _DiskSnapshot(
      modified: modified,
      content: diskText,
    );
    if (previousContent == null || diskText == previousContent) return;
    if (diskText != file.diskContent) {
      onExternalChange?.call(file, diskText);
    }
  }

  /// 读取文件修改时间（不存在时返回 null，读取失败时抛出异常）。
  DateTime? _statModified(String path) {
    final stat = FileStat.statSync(path);
    return stat.type == FileSystemEntityType.notFound ? null : stat.modified;
  }
}
