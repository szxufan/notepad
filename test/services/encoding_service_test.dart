import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/services/encoding_service.dart';

void main() {
  const service = EncodingService();

  group('EncodingService 检测', () {
    test('空字节应视为 UTF-8', () {
      final result = service.detectAndDecode([]);

      expect(result.encodingName, EncodingService.utf8Name);
      expect(result.text, '');
    });

    test('纯 ASCII 应检测为 UTF-8', () {
      final result = service.detectAndDecode(utf8.encode('hello world'));

      expect(result.encodingName, EncodingService.utf8Name);
      expect(result.text, 'hello world');
    });

    test('中文 UTF-8 应检测为 UTF-8', () {
      final result = service.detectAndDecode(utf8.encode('你好，世界'));

      expect(result.encodingName, EncodingService.utf8Name);
      expect(result.text, '你好，世界');
    });

    test('GBK 字节应检测为 GBK', () {
      // '中文' 的 GBK 编码：D6 D0 CE C4
      final result = service.detectAndDecode([0xD6, 0xD0, 0xCE, 0xC4]);

      expect(result.encodingName, EncodingService.gbkName);
      expect(result.text, '中文');
    });

    test('UTF-8 BOM 应检测为 UTF-8 BOM 并剥离 BOM', () {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('带 BOM')];

      final result = service.detectAndDecode(bytes);

      expect(result.encodingName, EncodingService.utf8BomName);
      expect(result.text, '带 BOM');
    });

    test('带 UTF-8 BOM 的损坏内容应容错解码', () {
      final result = service.detectAndDecode([0xEF, 0xBB, 0xBF, 0xFF]);

      expect(result.encodingName, EncodingService.utf8BomName);
      expect(result.text, '\u{FFFD}');
    });

    test('UTF-16 LE BOM 应检测为 UTF-16 LE', () {
      // '中文'：U+4E2D U+6587，小端字节序
      final bytes = [0xFF, 0xFE, 0x2D, 0x4E, 0x87, 0x65];

      final result = service.detectAndDecode(bytes);

      expect(result.encodingName, EncodingService.utf16LeName);
      expect(result.text, '中文');
    });

    test('UTF-16 BE BOM 应检测为 UTF-16 BE', () {
      final bytes = [0xFE, 0xFF, 0x4E, 0x2D, 0x65, 0x87];

      final result = service.detectAndDecode(bytes);

      expect(result.encodingName, EncodingService.utf16BeName);
      expect(result.text, '中文');
    });

    test('非 UTF-8 非 GBK 字节应兜底为 Windows-1252', () {
      // 0xE9 单独出现：不是合法 UTF-8，也不是合法 GBK
      final result = service.detectAndDecode([0xE9]);

      expect(result.encodingName, EncodingService.windows1252Name);
      expect(result.text, 'é');
    });

    test('截断检测不应把完整 GBK 尾字符裁成 ASCII', () {
      final result = service.detectAndDecodeTruncated([0x41, 0xD6, 0xD0]);

      expect(result.encodingName, EncodingService.gbkName);
      expect(result.text, 'A中');
    });

    test('截断检测不应把 Windows-1252 尾字节当作 UTF-8 前缀', () {
      final result = service.detectAndDecodeTruncated([0x41, 0xE9]);

      expect(result.encodingName, EncodingService.windows1252Name);
      expect(result.text, 'Aé');
    });

    test('截断检测应容错解码正文已有字符的 UTF-8 尾部', () {
      final bytes = utf8.encode('中文测试');
      final result = service.detectAndDecodeTruncated(
        bytes.sublist(0, bytes.length - 1),
      );

      expect(result.encodingName, EncodingService.utf8Name);
      expect(result.text, startsWith('中文测'));
    });
  });

  group('EncodingService 编解码往返', () {
    test('各编码应可无损往返 ASCII 文本', () {
      const text = 'hello world 123';
      for (final name in EncodingService.supportedEncodings) {
        final bytes = service.encode(text, name);
        final decoded = service.decode(bytes, name);
        expect(decoded, text, reason: '编码 $name 往返失败');
      }
    });

    test('中文应可在 UTF 变体与 GBK 间无损往返', () {
      const text = '你好，世界 123';
      for (final name in [
        EncodingService.utf8Name,
        EncodingService.utf8BomName,
        EncodingService.utf16LeName,
        EncodingService.utf16BeName,
        EncodingService.gbkName,
      ]) {
        final bytes = service.encode(text, name);
        expect(service.decode(bytes, name), text, reason: '编码 $name');
      }
    });

    test('UTF 变体应支持 emoji（代理对）', () {
      const text = '表情 😀🎉';
      for (final name in [
        EncodingService.utf8Name,
        EncodingService.utf8BomName,
        EncodingService.utf16LeName,
        EncodingService.utf16BeName,
      ]) {
        final bytes = service.encode(text, name);
        expect(service.decode(bytes, name), text, reason: '编码 $name');
      }
    });

    test('BOM 变体编码应重新写入 BOM', () {
      expect(
        service.encode('hi', EncodingService.utf8BomName).sublist(0, 3),
        [0xEF, 0xBB, 0xBF],
      );
      expect(
        service.encode('hi', EncodingService.utf16LeName).sublist(0, 2),
        [0xFF, 0xFE],
      );
      expect(
        service.encode('hi', EncodingService.utf16BeName).sublist(0, 2),
        [0xFE, 0xFF],
      );
    });

    test('GBK 编码 emoji 应抛出 EncodingException', () {
      expect(
        () => service.encode('😀', EncodingService.gbkName),
        throwsA(isA<EncodingException>()),
      );
    });

    test('Windows-1252 编码中文应抛出 EncodingException', () {
      expect(
        () => service.encode('中', EncodingService.windows1252Name),
        throwsA(isA<EncodingException>()),
      );
    });

    test('GBK 可表示的字符不应抛异常', () {
      final bytes = service.encode('中文测试', EncodingService.gbkName);

      expect(service.decode(bytes, EncodingService.gbkName), '中文测试');
    });

    test('容错解码不应抛异常', () {
      // 0xFF 不是合法 GBK 字节
      expect(service.decode([0xFF], EncodingService.gbkName), isNotEmpty);
      expect(service.decode([0xFF], EncodingService.utf8Name), isNotEmpty);
    });

    test('未知编码名应回退 UTF-8', () {
      final bytes = service.encode('文本', '不存在的编码');

      expect(bytes, utf8.encode('文本'));
      expect(service.decode(bytes, '不存在的编码'), '文本');
    });
  });
}
