/// 文本编码服务。
///
/// 负责字节内容的编码检测、解码与编码。
/// 检测管线：BOM → 严格 UTF-8 → 严格 GBK → Windows-1252 兜底。
/// 纯函数式服务，不做磁盘 IO。
library services.encoding_service;

import 'dart:convert';

import 'package:charset/charset.dart';

/// 编码异常：内容包含目标编码无法表示的字符。
class EncodingException implements Exception {
  /// 目标编码名。
  final String encodingName;

  /// 错误描述。
  final String message;

  const EncodingException(this.encodingName, this.message);

  @override
  String toString() => message;
}

/// 编码检测结果：编码名 + 解码后的文本。
class EncodingDetection {
  /// 检测到的编码名。
  final String encodingName;

  /// 解码后的文本。
  final String text;

  const EncodingDetection(this.encodingName, this.text);
}

/// 编码服务类。
class EncodingService {
  const EncodingService();

  /// UTF-8（无 BOM）。
  static const String utf8Name = 'UTF-8';

  /// UTF-8（带 BOM）。
  static const String utf8BomName = 'UTF-8 BOM';

  /// UTF-16 小端。
  static const String utf16LeName = 'UTF-16 LE';

  /// UTF-16 大端。
  static const String utf16BeName = 'UTF-16 BE';

  /// GBK（兼容 GB2312）。
  static const String gbkName = 'GBK';

  /// Windows-1252（西欧 ANSI）。
  static const String windows1252Name = 'Windows-1252';

  /// 支持的编码列表（用于状态栏切换菜单）。
  static const List<String> supportedEncodings = [
    utf8Name,
    utf8BomName,
    utf16LeName,
    utf16BeName,
    gbkName,
    windows1252Name,
  ];

  static const List<int> _utf8Bom = [0xEF, 0xBB, 0xBF];
  static const List<int> _utf16LeBom = [0xFF, 0xFE];
  static const List<int> _utf16BeBom = [0xFE, 0xFF];

  /// 检测字节内容的编码并解码。
  ///
  /// 检测顺序：UTF-8 BOM → UTF-16 LE/BE BOM → 严格 UTF-8 →
  /// 严格 GBK → Windows-1252 兜底。空内容视为 UTF-8。
  /// 该方法保证不抛异常。
  EncodingDetection detectAndDecode(List<int> bytes) {
    if (bytes.isEmpty) {
      return const EncodingDetection(utf8Name, '');
    }
    if (_startsWith(bytes, _utf8Bom)) {
      return EncodingDetection(
        utf8BomName,
        utf8.decode(bytes.sublist(3), allowMalformed: true),
      );
    }
    if (_startsWith(bytes, _utf16LeBom)) {
      return EncodingDetection(
        utf16LeName,
        _decodeUtf16(bytes.sublist(2), littleEndian: true),
      );
    }
    if (_startsWith(bytes, _utf16BeBom)) {
      return EncodingDetection(
        utf16BeName,
        _decodeUtf16(bytes.sublist(2), littleEndian: false),
      );
    }
    // 严格 UTF-8：合法则几乎可以确定是 UTF-8（纯 ASCII 也归此类）
    try {
      return EncodingDetection(utf8Name, utf8.decode(bytes));
    } catch (_) {
      // 不是合法 UTF-8，继续尝试
    }
    // 严格 GBK：中文 ANSI 文件的主要编码
    try {
      return EncodingDetection(gbkName, gbk.decode(bytes));
    } catch (_) {
      // 不是合法 GBK，兜底
    }
    return EncodingDetection(
      windows1252Name,
      windows1252.decode(bytes, allowInvalid: true),
    );
  }

  /// 检测截断字节流（大文件预览）的编码并解码。
  ///
  /// 仅当尾部确实是不完整的多字节序列，且前文已有对应编码的
  /// 多字节字符时，才按截断字符容错；完整合法的 GBK 不会被裁成
  /// ASCII 而误判为 UTF-8，ASCII + Windows-1252 尾字节也保持原检测。
  EncodingDetection detectAndDecodeTruncated(List<int> bytes) {
    if (bytes.isEmpty) return detectAndDecode(bytes);
    // BOM 是明确依据；各 BOM 解码器本身已支持容错/忽略落单尾字节。
    if (_startsWith(bytes, _utf8Bom) ||
        _startsWith(bytes, _utf16LeBom) ||
        _startsWith(bytes, _utf16BeBom)) {
      return detectAndDecode(bytes);
    }
    try {
      return EncodingDetection(utf8Name, utf8.decode(bytes));
    } catch (_) {
      // 继续检查是否仅末尾的 UTF-8 字符被截断。
    }
    for (var trim = 1; trim <= 3 && trim < bytes.length; trim++) {
      final end = bytes.length - trim;
      if (!_isIncompleteUtf8Tail(bytes.sublist(end))) continue;
      final sample = bytes.sublist(0, end);
      try {
        final prefix = utf8.decode(sample);
        // 纯 ASCII + 一个高位尾字节也可能是 Windows-1252；没有
        // 其他 UTF-8 多字节字符作依据时保留常规检测管线的结果。
        if (prefix.codeUnits.any((unit) => unit > 0x7F)) {
          return EncodingDetection(
            utf8Name,
            utf8.decode(bytes, allowMalformed: true),
          );
        }
      } catch (_) {
        // 截断尾字节之前的正文不是合法 UTF-8。
      }
    }
    // 完整合法的 GBK 必须先于“去掉末尾一字节”的截断判断。
    try {
      return EncodingDetection(gbkName, gbk.decode(bytes));
    } catch (_) {
      // 继续检查 GBK 是否仅切断最后一个双字节字符。
    }
    if (bytes.length > 1 && _isGbkLeadByte(bytes.last)) {
      final sample = bytes.sublist(0, bytes.length - 1);
      // 与 UTF-8 相同，要求前文已有非 ASCII 内容，避免把单个
      // Windows-1252 高位字节误当作 GBK 的首字节。
      if (sample.any((byte) => byte > 0x7F)) {
        try {
          gbk.decode(sample);
          return EncodingDetection(
            gbkName,
            gbk.decode(bytes, allowMalformed: true),
          );
        } catch (_) {
          // 正文不是合法 GBK，走常规兜底。
        }
      }
    }
    return detectAndDecode(bytes);
  }

  /// 判断 [tail] 是否为合法 UTF-8 多字节字符的不完整前缀。
  static bool _isIncompleteUtf8Tail(List<int> tail) {
    if (tail.isEmpty || tail.length > 3) return false;
    final first = tail[0];
    final expectedLength = first >= 0xC2 && first <= 0xDF
        ? 2
        : first >= 0xE0 && first <= 0xEF
            ? 3
            : first >= 0xF0 && first <= 0xF4
                ? 4
                : 0;
    if (expectedLength == 0 || tail.length >= expectedLength) return false;
    for (var i = 1; i < tail.length; i++) {
      final byte = tail[i];
      if (i == 1) {
        final min = first == 0xE0
            ? 0xA0
            : first == 0xF0
                ? 0x90
                : 0x80;
        final max = first == 0xED
            ? 0x9F
            : first == 0xF4
                ? 0x8F
                : 0xBF;
        if (byte < min || byte > max) return false;
      } else if (byte < 0x80 || byte > 0xBF) {
        return false;
      }
    }
    return true;
  }

  /// 是否为 GBK 双字节字符的首字节。
  static bool _isGbkLeadByte(int byte) => byte >= 0x81 && byte <= 0xFE;

  /// 按指定编码解码字节内容。
  ///
  /// 用于手动切换编码与外部修改重载。容错解码：
  /// 非法字节替换为占位符而非抛异常（用户已显式选定编码）。
  /// 带 BOM 的编码会自动剥离 BOM。
  String decode(List<int> bytes, String encodingName) {
    switch (encodingName) {
      case utf8BomName:
        final body = _startsWith(bytes, _utf8Bom) ? bytes.sublist(3) : bytes;
        return utf8.decode(body, allowMalformed: true);
      case utf16LeName:
        final body = _startsWith(bytes, _utf16LeBom) ? bytes.sublist(2) : bytes;
        return _decodeUtf16(body, littleEndian: true);
      case utf16BeName:
        final body = _startsWith(bytes, _utf16BeBom) ? bytes.sublist(2) : bytes;
        return _decodeUtf16(body, littleEndian: false);
      case gbkName:
        return gbk.decode(bytes, allowMalformed: true);
      case windows1252Name:
        return windows1252.decode(bytes, allowInvalid: true);
      case utf8Name:
      default:
        return utf8.decode(bytes, allowMalformed: true);
    }
  }

  /// 按指定编码编码文本。
  ///
  /// BOM 变体会重新写入 BOM。内容包含目标编码无法表示的字符时
  /// 抛出 [EncodingException]（GBK/Windows-1252 先做往返校验，
  /// 防止编解码器静默替换字符导致数据丢失）。
  List<int> encode(String text, String encodingName) {
    switch (encodingName) {
      case utf8BomName:
        return [..._utf8Bom, ...utf8.encode(text)];
      case utf16LeName:
        return [
          ..._utf16LeBom,
          ..._encodeUtf16(text, littleEndian: true),
        ];
      case utf16BeName:
        return [
          ..._utf16BeBom,
          ..._encodeUtf16(text, littleEndian: false),
        ];
      case gbkName:
        _ensureEncodable(text, gbk, encodingName);
        return gbk.encode(text);
      case windows1252Name:
        _ensureEncodable(text, windows1252, encodingName);
        return windows1252.encode(text);
      case utf8Name:
      default:
        return utf8.encode(text);
    }
  }

  /// 校验文本能否被目标编码无损表示。
  ///
  /// 先用 [Charset.canEncode] 快速判断，再做编码→解码往返比对，
  /// 确保编解码器不会静默替换无法表示的字符。
  /// 验证过程中编解码器抛出的任何异常同样视为无法表示。
  void _ensureEncodable(String text, Encoding encoding, String name) {
    if (text.isEmpty) return;
    try {
      if (!Charset.canEncode(encoding, text)) {
        throw EncodingException(name, '内容包含 $name 无法表示的字符');
      }
      final roundTrip = encoding.decode(encoding.encode(text));
      if (roundTrip != text) {
        throw EncodingException(name, '内容包含 $name 无法表示的字符');
      }
    } on EncodingException {
      rethrow;
    } catch (_) {
      throw EncodingException(name, '内容包含 $name 无法表示的字符');
    }
  }

  /// 判断字节序列是否以指定前缀开头。
  static bool _startsWith(List<int> bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  /// 将 UTF-16 字节解码为字符串（显式指定端序，不依赖 BOM）。
  ///
  /// 末尾落单的字节忽略。
  static String _decodeUtf16(List<int> bytes, {required bool littleEndian}) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add(littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(units);
  }

  /// 将字符串编码为 UTF-16 字节（显式指定端序，不含 BOM）。
  static List<int> _encodeUtf16(String text, {required bool littleEndian}) {
    final bytes = <int>[];
    for (final unit in text.codeUnits) {
      if (littleEndian) {
        bytes.add(unit & 0xFF);
        bytes.add(unit >> 8);
      } else {
        bytes.add(unit >> 8);
        bytes.add(unit & 0xFF);
      }
    }
    return bytes;
  }
}
