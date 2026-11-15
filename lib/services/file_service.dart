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

/// 文件服务类。
class FileService {
  final _uuid = const Uuid();

  /// 从磁盘读取文件内容，返回 [NoteFile]。
  ///
  /// [path] 为文件绝对路径。
  /// 抛出 [FileSystemException] 如果文件不存在或读取失败。
  NoteFile openFile(String path) {
    final file = File(path);
    final content = file.readAsStringSync();
    return NoteFile.fromDisk(_uuid.v4(), path, content);
  }

  /// 将 [file] 的内容写入磁盘。
  ///
  /// 更新 [filePath]、[diskContent]、[lastSavedAt]，并清除 [isDirty] 和 [isNew]。
  Future<NoteFile> saveFile(NoteFile file) async {
    if (file.filePath == null) {
      throw ArgumentError('filePath 不能为 null，请使用 saveFileAs');
    }
    final f = File(file.filePath!);
    await f.writeAsString(file.content);
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
  /// 返回更新后的 [NoteFile]。
  /// 用户取消选择时返回 null。
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
    final f = File(actualPath);
    await f.writeAsString(file.content);
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
}
