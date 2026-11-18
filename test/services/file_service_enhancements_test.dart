/// 文件服务增强测试：原子保存、重命名、大文件分级只读。
library services.file_service_enhancements_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/models/note_file.dart';
import 'package:notepad/services/file_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late FileService fileService;
  late Directory tempDir;

  setUp(() {
    fileService = FileService();
    fileService.resetUntitledCounter();
    tempDir = Directory.systemTemp.createTempSync('notepad_enhance_test_');
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {
      // Windows 下临时目录可能被短暂占用，忽略清理失败
    }
  });

  group('原子保存', () {
    test('saveFile 应覆盖已有文件且无临时文件残留', () async {
      final path = '${tempDir.path}/atomic.txt';
      File(path).writeAsStringSync('旧内容');
      var file = fileService.openFile(path);
      file = file.copyWith(content: '新内容', isDirty: true);

      await fileService.saveFile(file);

      expect(File(path).readAsStringSync(), '新内容');
      expect(
        tempDir.listSync().where((e) => e.path.endsWith('.tmp')),
        isEmpty,
      );
    });

    test('saveFile 多次保存目录中应只有目标文件', () async {
      final path = '${tempDir.path}/multi.txt';
      File(path).writeAsStringSync('v0');
      var file = fileService.openFile(path);

      for (var i = 1; i <= 3; i++) {
        file = file.copyWith(content: 'v$i', isDirty: true);
        file = await fileService.saveFile(file);
      }

      expect(File(path).readAsStringSync(), 'v3');
      expect(tempDir.listSync().length, 1);
    });

    test('saveFile 应更新符号链接目标而不替换链接', () async {
      final targetPath = '${tempDir.path}/target.txt';
      final linkPath = '${tempDir.path}/link.txt';
      File(targetPath).writeAsStringSync('旧内容');
      Link(linkPath).createSync(targetPath);
      var file = fileService.openFile(linkPath);
      file = file.copyWith(content: '新内容', isDirty: true);

      await fileService.saveFile(file);

      expect(File(targetPath).readAsStringSync(), '新内容');
      expect(
        FileSystemEntity.typeSync(linkPath, followLinks: false),
        FileSystemEntityType.link,
      );
    }, skip: Platform.isWindows);

    test('saveFile 重命名失败应抛出异常并清理临时文件', () async {
      // 目标路径是目录：写入临时文件成功但重命名必然失败
      final dirPath = '${tempDir.path}/target_dir';
      Directory(dirPath).createSync();
      final file = NoteFile(
        id: 'x',
        title: 'target_dir',
        filePath: dirPath,
        content: '内容',
        lastModified: DateTime.now(),
      );

      await expectLater(
        fileService.saveFile(file),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        tempDir.listSync().where((e) => e.path.endsWith('.tmp')),
        isEmpty,
      );
      expect(Directory(dirPath).existsSync(), true);
    });
  });

  group('renameFile', () {
    test('应重命名磁盘文件并更新路径与标题', () {
      final path = '${tempDir.path}/old.txt';
      File(path).writeAsStringSync('内容');
      final file = fileService.openFile(path);

      final renamed = fileService.renameFile(file, 'new.txt');

      expect(renamed.filePath, p.join(tempDir.path, 'new.txt'));
      expect(renamed.title, 'new.txt');
      expect(File('${tempDir.path}/new.txt').readAsStringSync(), '内容');
      expect(File(path).existsSync(), false);
    });

    test('目标已存在应抛出异常且原文件不变', () {
      final path = '${tempDir.path}/old.txt';
      File(path).writeAsStringSync('原内容');
      File('${tempDir.path}/new.txt').writeAsStringSync('占用');
      final file = fileService.openFile(path);

      expect(
        () => fileService.renameFile(file, 'new.txt'),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(path).readAsStringSync(), '原内容');
    });

    test('名称含路径分隔符应抛出异常', () {
      final path = '${tempDir.path}/old.txt';
      File(path).writeAsStringSync('内容');
      final file = fileService.openFile(path);

      expect(
        () => fileService.renameFile(file, 'a/b.txt'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => fileService.renameFile(file, 'a\\b.txt'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('空名称应抛出异常', () {
      final path = '${tempDir.path}/old.txt';
      File(path).writeAsStringSync('内容');
      final file = fileService.openFile(path);

      expect(
        () => fileService.renameFile(file, '   '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('未保存文件应抛出异常', () {
      final file = fileService.createNewFile();

      expect(
        () => fileService.renameFile(file, 'x.txt'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('同名重命名应返回原文件', () {
      final path = '${tempDir.path}/old.txt';
      File(path).writeAsStringSync('内容');
      final file = fileService.openFile(path);

      final renamed = fileService.renameFile(file, 'old.txt');

      expect(renamed.filePath, path);
      expect(File(path).existsSync(), true);
    });
  });

  group('大文件分级只读', () {
    test('超过只读阈值的文件应标记只读', () {
      final service =
          FileService(readOnlyThresholdBytes: 10, maxFileBytes: 100);
      final path = '${tempDir.path}/big.txt';
      File(path).writeAsStringSync('x' * 20);

      final file = service.openFile(path);

      expect(file.isReadOnly, true);
      expect(file.content, 'x' * 20);
    });

    test('未超过阈值的文件不应只读', () {
      final service =
          FileService(readOnlyThresholdBytes: 10, maxFileBytes: 100);
      final path = '${tempDir.path}/small.txt';
      File(path).writeAsStringSync('x' * 5);

      final file = service.openFile(path);

      expect(file.isReadOnly, false);
    });

    test('超过上限的文件应抛出 FileTooLargeException', () {
      final service = FileService(readOnlyThresholdBytes: 10, maxFileBytes: 50);
      final path = '${tempDir.path}/huge.txt';
      File(path).writeAsStringSync('x' * 60);

      expect(
        () => service.openFile(path),
        throwsA(isA<FileTooLargeException>()),
      );
      try {
        service.openFile(path);
        fail('应抛出 FileTooLargeException');
      } on FileTooLargeException catch (e) {
        expect(e.path, path);
        expect(e.sizeBytes, 60);
        expect(e.maxBytes, 50);
        expect(e.toString(), contains('MB'));
      }
    });

    test('默认阈值应为 10MB 只读 / 50MB 上限', () {
      expect(FileService.defaultReadOnlyThresholdBytes, 10 * 1024 * 1024);
      expect(FileService.defaultMaxFileBytes, 50 * 1024 * 1024);
      expect(fileService.readOnlyThresholdBytes, 10 * 1024 * 1024);
      expect(fileService.maxFileBytes, 50 * 1024 * 1024);
    });

    test('只读文件应仅加载预览部分', () {
      final service = FileService(
        readOnlyThresholdBytes: 5,
        maxFileBytes: 100,
        readOnlyPreviewBytes: 8,
      );
      final path = '${tempDir.path}/preview.txt';
      File(path).writeAsStringSync('0123456789ABCDEF');

      final file = service.openFile(path);

      expect(file.isReadOnly, true);
      expect(file.content, '01234567');
    });

    test('只读预览切断 UTF-8 多字节字符不应误判编码', () {
      final service = FileService(
        readOnlyThresholdBytes: 5,
        maxFileBytes: 100,
        readOnlyPreviewBytes: 8,
      );
      final path = '${tempDir.path}/utf8_cut.txt';
      // '中文测试内容' 共 18 字节，预览 8 字节切断第三个字符
      File(path).writeAsStringSync('中文测试内容');

      final file = service.openFile(path);

      expect(file.encoding, 'UTF-8');
      expect(file.content.startsWith('中文'), true);
    });

    test('只读预览的 GBK 文件应正确检测编码', () {
      final service = FileService(
        readOnlyThresholdBytes: 5,
        maxFileBytes: 100,
        readOnlyPreviewBytes: 7,
      );
      final path = '${tempDir.path}/gbk_cut.txt';
      // '中文测试内容' 的 GBK 字节共 12 字节，预览 7 字节切断末字符
      File(path).writeAsBytesSync([
        0xD6, 0xD0, 0xCE, 0xC4, // 中文
        0xB2, 0xE2, 0xCA, 0xD4, // 测试
        0xC4, 0xDA, 0xC8, 0xDD, // 内容
      ]);

      final file = service.openFile(path);

      expect(file.encoding, 'GBK');
      expect(file.content.startsWith('中文测'), true);
    });
  });
}
