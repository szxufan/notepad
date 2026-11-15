/// 支持查找高亮的自定义 [TextEditingController]。
///
/// 覆写 [buildTextSpan] 方法，将所有匹配项标记为黄色背景，
/// 当前匹配项标记为橙色背景。
library widgets.highlighting_controller;

import 'package:flutter/material.dart';

/// 高亮文本控制器。
class HighlightingController extends TextEditingController {
  /// 所有匹配位置。
  List<TextRange> matches = [];

  /// 当前匹配位置。
  TextRange? currentMatch;

  /// 查找文本（用于判断是否高亮）。
  String findText = '';

  /// 创建 [HighlightingController]。
  HighlightingController({String text = ''}) : super(text: text);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (findText.isEmpty || matches.isEmpty || text.isEmpty) {
      return TextSpan(text: text, style: style);
    }

    final children = <TextSpan>[];
    var lastEnd = 0;

    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      if (match.start < lastEnd) continue; // 跳过重叠

      // 添加匹配前的普通文本
      if (match.start > lastEnd) {
        children.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: style,
        ));
      }

      // 添加匹配文本（高亮）
      final isCurrent = currentMatch != null &&
          match.start == currentMatch!.start &&
          match.end == currentMatch!.end;
      children.add(TextSpan(
        text: text.substring(match.start, match.end),
        style: style?.copyWith(
          backgroundColor: isCurrent
              ? Colors.orange.withValues(alpha: 0.6)
              : Colors.yellow.withValues(alpha: 0.4),
        ),
      ));

      lastEnd = match.end;
    }

    // 添加最后一段普通文本
    if (lastEnd < text.length) {
      children.add(TextSpan(
        text: text.substring(lastEnd),
        style: style,
      ));
    }

    return TextSpan(children: children, style: style);
  }

  /// 更新高亮数据并刷新视图。
  ///
  /// 数据无变化时不通知，避免触发无意义的重建循环。
  void updateHighlights({
    required List<TextRange> newMatches,
    TextRange? newCurrentMatch,
    required String newFindText,
  }) {
    final matchesUnchanged = _sameRanges(matches, newMatches);
    final currentUnchanged = _sameRange(currentMatch, newCurrentMatch);
    if (matchesUnchanged && currentUnchanged && findText == newFindText) {
      return;
    }
    matches = newMatches;
    currentMatch = newCurrentMatch;
    findText = newFindText;
    notifyListeners();
  }

  /// 比较两个匹配列表是否相同。
  static bool _sameRanges(List<TextRange> a, List<TextRange> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].start != b[i].start || a[i].end != b[i].end) return false;
    }
    return true;
  }

  /// 比较两个匹配区间是否相同（均 null 视为相同）。
  static bool _sameRange(TextRange? a, TextRange? b) {
    if (a == null || b == null) return a == b;
    return a.start == b.start && a.end == b.end;
  }
}
