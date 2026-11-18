import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/services/encoding_service.dart';
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

    test('createNewFile 默认编码应为 UTF-8', () {
      final file = fileService.createNewFile();

      expect(file.encoding, EncodingService.utf8Name);
    });

    test('openFile 应检测 GBK 编码', () {
      final path = '${tempDir.path}/gbk.txt';
      // '中文' 的 GBK 字节
      File(path).writeAsBytesSync([0xD6, 0xD0, 0xCE, 0xC4]);

      final file = fileService.openFile(path);

      expect(file.content, '中文');
      expect(file.encoding, EncodingService.gbkName);
    });

    test('openFile 应检测 UTF-8 BOM', () {
      final path = '${tempDir.path}/bom.txt';
      File(path).writeAsBytesSync([
        0xEF, 0xBB, 0xBF, // BOM
        0xE4, 0xBD, 0xA0, 0xE5, 0xA5, 0xBD, // '你好'
      ]);

      final file = fileService.openFile(path);

      expect(file.content, '你好');
      expect(file.encoding, EncodingService.utf8BomName);
    });

    test('openFile 应检测 UTF-16 LE', () {
      final path = '${tempDir.path}/utf16.txt';
      // BOM + '中文'
      File(path).writeAsBytesSync([0xFF, 0xFE, 0x2D, 0x4E, 0x87, 0x65]);

      final file = fileService.openFile(path);

      expect(file.content, '中文');
      expect(file.encoding, EncodingService.utf16LeName);
    });

    test('saveFile 应沿用 GBK 编码写入字节', () async {
      final path = '${tempDir.path}/gbk_save.txt';
      File(path).writeAsBytesSync([0xD6, 0xD0, 0xCE, 0xC4]);

      var file = fileService.openFile(path);
      file = file.copyWith(content: '测试', isDirty: true);
      await fileService.saveFile(file);

      // '测试' 的 GBK 字节：B2 E2 CA D4
      expect(File(path).readAsBytesSync(), [0xB2, 0xE2, 0xCA, 0xD4]);
    });

    test('saveFile 应沿用 UTF-8 BOM 编码', () async {
      final path = '${tempDir.path}/bom_save.txt';
      File(path).writeAsBytesSync([0xEF, 0xBB, 0xBF, 0x61]);

      var file = fileService.openFile(path);
      file = file.copyWith(content: 'ab', isDirty: true);
      await fileService.saveFile(file);

      expect(
        File(path).readAsBytesSync(),
        [0xEF, 0xBB, 0xBF, 0x61, 0x62],
      );
    });

    test('saveFile 内容超出编码表示范围应抛出 EncodingException', () async {
      final path = '${tempDir.path}/gbk_emoji.txt';
      File(path).writeAsBytesSync([0xD6, 0xD0, 0xCE, 0xC4]);

      var file = fileService.openFile(path);
      file = file.copyWith(content: '中文😀', isDirty: true);

      expect(
        () => fileService.saveFile(file),
        throwsA(isA<EncodingException>()),
      );
    });

    test('readFileWithEncoding 应按指定编码解码', () {
      final path = '${tempDir.path}/reread.txt';
      // '中文' 的 GBK 字节
      File(path).writeAsBytesSync([0xD6, 0xD0, 0xCE, 0xC4]);

      expect(
        fileService.readFileWithEncoding(path, EncodingService.gbkName),
        '中文',
      );
      // 按 UTF-8 容错解码不应抛异常（乱码但可显示）
      expect(
        fileService.readFileWithEncoding(path, EncodingService.utf8Name),
        isNotEmpty,
      );
    });
  });
}
