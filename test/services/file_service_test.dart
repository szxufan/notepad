import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/services/file_service.dart';

void main() {
  late FileService fileService;
  late Directory tempDir;

  setUp(() {
    fileService = FileService();
    fileService.resetUntitledCounter();
    tempDir = Directory.systemTemp.createTempSync('notepad_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('FileService', () {
    test('createNewFile 应创建未命名文件', () {
      final file = fileService.createNewFile();

      expect(file.id.isNotEmpty, true);
      expect(file.title, '无标题');
      expect(file.content, '');
      expect(file.isNew, true);
      expect(file.filePath, isNull);
      expect(file.isDirty, false);
    });

    test('createNewFile 多次调用应递增计数', () {
      final file1 = fileService.createNewFile();
      final file2 = fileService.createNewFile();

      expect(file1.title, '无标题');
      expect(file2.title, '无标题 1');
    });

    test('openFile 应读取文件内容', () {
      final path = '${tempDir.path}/test.txt';
      File(path).writeAsStringSync('hello world');

      final file = fileService.openFile(path);

      expect(file.filePath, path);
      expect(file.title, 'test.txt');
      expect(file.content, 'hello world');
      expect(file.isNew, false);
      expect(file.isDirty, false);
      expect(file.diskContent, 'hello world');
    });

    test('openFile 文件不存在应抛出异常', () {
      expect(
        () => fileService.openFile('${tempDir.path}/nonexistent.txt'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('saveFile 应写入磁盘并清除 dirty', () async {
      final path = '${tempDir.path}/save_test.txt';
      File(path).writeAsStringSync('原内容');

      var file = fileService.openFile(path);
      file = file.copyWith(content: '新内容', isDirty: true);

      final saved = await fileService.saveFile(file);

      expect(saved.content, '新内容');
      expect(saved.isDirty, false);
      expect(saved.diskContent, '新内容');
      expect(saved.filePath, path);
      expect(saved.lastSavedAt, isNotNull);

      // 验证磁盘内容
      final diskContent = File(path).readAsStringSync();
      expect(diskContent, '新内容');
    });

    test('saveFile filePath 为 null 应抛出异常', () async {
      final file = fileService.createNewFile();

      expect(
        () => fileService.saveFile(file),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
