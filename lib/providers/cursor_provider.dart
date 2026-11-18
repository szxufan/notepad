/// 光标位置状态管理。
///
/// 独立的轻量通知器：光标/选区变化只通知状态栏，
/// 避免编辑器全局重建（EditorProvider 刻意不在选区变化时通知）。
library providers.cursor_provider;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// 光标位置 Provider。
class CursorProvider extends ChangeNotifier {
  /// 当前行号（1-based）。
  int _line = 1;

  /// 当前列号（1-based）。
  int _column = 1;

  /// 选中文本长度（无选区时为 0）。
  int _selectionLength = 0;

  /// 获取当前行号。
  int get line => _line;

  /// 获取当前列号。
  int get column => _column;

  /// 获取选中文本长度。
  int get selectionLength => _selectionLength;

  /// 根据编辑器选区与文本更新光标位置。
  ///
  /// 值未变化时不通知，避免无意义的重建。
  void update(TextSelection selection, String text) {
    var line = 1;
    var column = 1;
    var selectionLength = 0;
    if (selection.isValid) {
      final offset = selection.baseOffset.clamp(0, text.length);
      final before = text.substring(0, offset);
      line = '\n'.allMatches(before).length + 1;
      column = offset - before.lastIndexOf('\n');
      if (!selection.isCollapsed) {
        selectionLength = selection.end - selection.start;
      }
    }
    if (line == _line &&
        column == _column &&
        selectionLength == _selectionLength) {
      return;
    }
    _line = line;
    _column = column;
    _selectionLength = selectionLength;
    notifyListeners();
  }
}