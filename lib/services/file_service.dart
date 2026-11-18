/// 文件读写服务。
///
/// 负责磁盘文件的读取、写入、另存为操作，
/// 以及新建未命名文件的创建。
library services.file_service;

import 'dart:io';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/note_file.dart';
import 'encoding_service.dart';

/// 文件超过可打开上限时抛出。
class FileTooLargeException implements Exception {
  const FileTooLargeException(this.path, this.sizeBytes, this.maxBytes);

  /// 文件路径。
  final String path;

  /// 文件实际字节数。
  final int sizeBytes;

  /// 允许的最大字节数。
  final int maxBytes;

  /// 以 MB 表示的实际大小（一位小数）。
  String get sizeMB => (sizeBytes / 1024 / 1024).toStringAsFixed(1);

  /// 以 MB 表示的上限（整数）。
  String get maxMB => (maxBytes / 1024 / 1024).toStringAsFixed(0);

  @override
  String toString() => '文件过大（$sizeMB MB），超过 $maxMB MB 上限，无法打开';
}

/// 文件服务类。
class FileService {
  FileService({
    EncodingService? encodingService,
    int? readOnlyThresholdBytes,
    int? maxFileBytes,
    int? readOnlyPreviewBytes,
  })  : encodingService = encodingService ?? const EncodingService(),
        readOnlyThresholdBytes =
            readOnlyThresholdBytes ?? defaultReadOnlyThresholdBytes,
        maxFileBytes = maxFileBytes ?? defaultMaxFileBytes,
        readOnlyPreviewBytes =
            readOnlyPreviewBytes ?? defaultReadOnlyPreviewBytes;

  /// 默认只读阈值：超过该大小的文件以只读模式打开（10 MB）。
  static const int defaultReadOnlyThresholdBytes = 10 * 1024 * 1024;

  /// 默认打开上限：超过该大小的文件拒绝打开（50 MB）。
  static const int defaultMaxFileBytes = 50 * 1024 * 1024;

  /// 默认只读预览大小：只读大文件仅加载开头 1 MB 用于显示。
  ///
  /// TextField 全量布局文本，渲染数十 MB 会冻结 UI；
  /// 只读文件禁止编辑/保存，截断显示不会造成数据丢失。
  static const int defaultReadOnlyPreviewBytes = 1024 * 1024;

  final _uuid = const Uuid();

  /// 编码服务（检测/编解码）。
  final EncodingService encodingService;

  /// 只读阈值（字节），超过则以只读模式打开。
  final int readOnlyThresholdBytes;

  /// 打开上限（字节），超过则抛出 [FileTooLargeException]。
  final int maxFileBytes;

  /// 只读预览大小（字节），只读文件仅加载开头部分。
  final int readOnlyPreviewBytes;

  /// 从磁盘读取文件内容，返回 [NoteFile]。
  ///
  /// [path] 为文件绝对路径。自动检测文件编码（BOM/UTF-8/GBK/Windows-1252）。
  /// 超过 [maxFileBytes] 抛出 [FileTooLargeException]；
  /// 超过 [readOnlyThresholdBytes] 的文件标记为只读，且仅加载
  /// [readOnlyPreviewBytes] 大小的开头预览。
  /// 抛出 [FileSystemException] 如果文件不存在或读取失败。
  NoteFile openFile(String path) {
    final file = File(path);
    final size = file.lengthSync();
    if (size > maxFileBytes) {
      throw FileTooLargeException(path, size, maxFileBytes);
    }
    final isReadOnly = size > readOnlyThresholdBytes;
    final bytes = isReadOnly
        ? _readPreview(file, readOnlyPreviewBytes)
        : file.readAsBytesSync();
    // 预览截断可能切断多字节字符，用截断感知检测 + 容错解码
    final detection = isReadOnly && size > bytes.length
        ? encodingService.detectAndDecodeTruncated(bytes)
        : encodingService.detectAndDecode(bytes);
    return NoteFile.fromDisk(
      _uuid.v4(),
      path,
      detection.text,
      encoding: detection.encodingName,
      isReadOnly: isReadOnly,
    );
  }

  /// 读取文件开头至多 [maxBytes] 字节。
  List<int> _readPreview(File file, int maxBytes) {
    final raf = file.openSync();
    try {
      return raf.readSync(maxBytes);
    } finally {
      raf.closeSync();
    }
  }

  /// 按指定编码读取磁盘文件文本（用于手动切换编码）。
  ///
  /// 抛出 [FileSystemException] 如果文件不存在或读取失败。
  String readFileWithEncoding(String path, String encodingName) {
    final bytes = File(path).readAsBytesSync();
    return encodingService.decode(bytes, encodingName);
  }

  /// 将 [file] 的内容写入磁盘。
  ///
  /// 按 [NoteFile.encoding] 编码后写入。
  /// 更新 [filePath]、[diskContent]、[lastSavedAt]，并清除 [isDirty] 和 [isNew]。
  /// 内容包含当前编码无法表示的字符时抛出 [EncodingException]。
  Future<NoteFile> saveFile(NoteFile file) async {
    if (file.filePath == null) {
      throw ArgumentError('filePath 不能为 null，请使用 saveFileAs');
    }
    final bytes = encodingService.encode(file.content, file.encoding);
    await _atomicWrite(file.filePath!, bytes);
    final now = DateTime.now();
    return file.copyWith(
      diskContent: file.content,
      isDirty: false,
      lastSavedAt: now,
      lastModified: now,
      isNew: false,
    );
  }

  /// 打开另存为对话框，将内容写入新路径。
  ///
  /// 沿用 [NoteFile.encoding] 编码（新建文件默认 UTF-8）。
  /// 返回更新后的 [NoteFile]。
  /// 用户取消选择时返回 null。
  /// 内容包含当前编码无法表示的字符时抛出 [EncodingException]。
  Future<NoteFile?> saveFileAs(NoteFile file) async {
    final defaultName = file.isNew ? 'untitled.txt' : file.title;
    final defaultDir = file.filePath != null
        ? p.dirname(file.filePath!)
        : Directory.current.path;
    final path = await file_selector.getSaveLocation(
      suggestedName: defaultName,
      initialDirectory: defaultDir,
      acceptedTypeGroups: [
        const file_selector.XTypeGroup(
          label: '文本文件',
          extensions: ['txt', 'md', 'log', 'csv', 'json', 'yaml', 'yml'],
        ),
        const file_selector.XTypeGroup(label: '所有文件'),
      ],
    );
    if (path == null) return null;
    final actualPath = path.path;
    final bytes = encodingService.encode(file.content, file.encoding);
    await _atomicWrite(actualPath, bytes);
    final now = DateTime.now();
    return file.copyWith(
      filePath: actualPath,
      title: p.basename(actualPath),
      diskContent: file.content,
      isDirty: false,
      lastSavedAt: now,
      lastModified: now,
      isNew: false,
    );
  }

  /// 原子写入：先写同目录临时文件再重命名覆盖目标。
  ///
  /// 同目录保证同卷重命名原子性；临时名含 UUID，避免撞名用户已有文件。
  /// 写入或重命名失败时清理临时文件并抛出原异常，目标文件保持原样。
  Future<void> _atomicWrite(String path, List<int> bytes) async {
    // 读取会跟随符号链接，原子替换也必须作用于链接目标，否则会把
    // 链接目录项本身替换成普通文件。
    var targetPath = path;
    if (FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.link) {
      targetPath = File(path).resolveSymbolicLinksSync();
    }
    final tempPath = p.join(
      p.dirname(targetPath),
      '${p.basename(targetPath)}.${_uuid.v4()}.tmp',
    );
    final tempFile = File(tempPath);
    try {
      await tempFile.writeAsBytes(bytes);
      await tempFile.rename(targetPath);
    } catch (e) {
      try {
        if (tempFile.existsSync()) {
          tempFile.deleteSync();
        }
      } catch (_) {
        // 清理失败不掩盖原始异常
      }
      rethrow;
    }
  }

  /// 创建新的未命名文件。
  NoteFile createNewFile() {
    final now = DateTime.now();
    final id = _uuid.v4();
    final counter = _untitledCounter++;
    return NoteFile(
      id: id,
      title: counter == 0 ? '无标题' : '无标题 $counter',
      content: '',
      isDirty: false,
      lastModified: now,
      isNew: true,
    );
  }

  /// 未命名文件计数器。
  int _untitledCounter = 0;

  /// 重置未命名计数器（用于测试）。
  void resetUntitledCounter() {
    _untitledCounter = 0;
  }

  /// 打开文件选择对话框，返回选中文件的路径。
  ///
  /// 用户取消时返回 null。
  Future<String?> pickFile() async {
    const file_selector.XTypeGroup typeGroup =
        file_selector.XTypeGroup(label: '所有文件');
    final result =
        await file_selector.openFile(acceptedTypeGroups: const [typeGroup]);
    return result?.path;
  }

  /// 打开多选文件选择对话框，返回选中文件的路径列表。
  ///
  /// 用户取消时返回空列表。
  Future<List<String>> pickFiles() async {
    const file_selector.XTypeGroup typeGroup =
        file_selector.XTypeGroup(label: '所有文件');
    final results =
        await file_selector.openFiles(acceptedTypeGroups: const [typeGroup]);
    return results.map((f) => f.path).toList();
  }

  /// 重命名磁盘文件（同目录改名）。
  ///
  /// [newName] 仅为文件名，不能为空或含路径分隔符；目标已存在时抛出
  /// [FileSystemException]。返回更新路径与标题后的 [NoteFile]。
  NoteFile renameFile(NoteFile file, String newName) {
    final oldPath = file.filePath;
    if (oldPath == null) {
      throw ArgumentError('未保存的文件不能重命名磁盘文件');
    }
    final name = newName.trim();
    if (name.isEmpty) {
      throw ArgumentError('文件名不能为空');
    }
    if (name.contains('/') || name.contains('\\')) {
      throw ArgumentError('文件名不能包含路径分隔符');
    }
    final newPath = p.join(p.dirname(oldPath), name);
    if (p.equals(oldPath, newPath)) {
      return file;
    }
    if (File(newPath).existsSync()) {
      throw FileSystemException('目标文件已存在', newPath);
    }
    File(oldPath).renameSync(newPath);
    return file.copyWith(filePath: newPath, title: p.basename(newPath));
  }
}
