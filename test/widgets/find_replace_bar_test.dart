import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/widgets/highlighting_controller.dart';

void main() {
  group('HighlightingController', () {
    testWidgets('无匹配时 buildTextSpan 返回普通文本', (tester) async {
      final controller = HighlightingController(text: 'hello world');

      late TextSpan span;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            span = controller.buildTextSpan(
              context: context,
              style: const TextStyle(),
              withComposing: false,
            );
            return const SizedBox.shrink();
          },
        ),
      );

      expect(span.toPlainText(), 'hello world');
    });

    testWidgets('有匹配时 buildTextSpan 应包含高亮子 span', (tester) async {
      final controller = HighlightingController(text: 'hello world hello');
      controller.updateHighlights(
        newMatches: [
          const TextRange(start: 0, end: 5),
          const TextRange(start: 12, end: 17),
        ],
        newCurrentMatch: const TextRange(start: 0, end: 5),
        newFindText: 'hello',
      );

      late TextSpan span;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            span = controller.buildTextSpan(
              context: context,
              style: const TextStyle(),
              withComposing: false,
            );
            return const SizedBox.shrink();
          },
        ),
      );

      expect(span.children, isNotNull);
      expect(span.children!.length, greaterThan(1));
    });

    test('updateHighlights 应更新匹配数据', () {
      final controller = HighlightingController(text: 'test test');
      controller.updateHighlights(
        newMatches: [const TextRange(start: 0, end: 4)],
        newCurrentMatch: const TextRange(start: 0, end: 4),
        newFindText: 'test',
      );

      expect(controller.matches.length, 1);
      expect(controller.findText, 'test');
      expect(controller.currentMatch?.start, 0);
      expect(controller.currentMatch?.end, 4);
    });
  });
}
