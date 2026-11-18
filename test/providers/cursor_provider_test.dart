import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/providers/cursor_provider.dart';

void main() {
  late CursorProvider cursor;

  setUp(() {
    cursor = CursorProvider();
  });

  group('CursorProvider', () {
    test('初始状态应为第 1 行第 1 列无选区', () {
      expect(cursor.line, 1);
      expect(cursor.column, 1);
      expect(cursor.selectionLength, 0);
    });

    test('单行文本光标位置应正确', () {
      cursor.update(const TextSelection.collapsed(offset: 5), 'hello world');

      expect(cursor.line, 1);
      expect(cursor.column, 6);
    });

    test('多行文本光标行列应正确', () {
      // 'ab\ncdef\ngh'，光标在第二行 'cdef' 的 'e' 后（offset 6）
      cursor.update(const TextSelection.collapsed(offset: 6), 'ab\ncdef\ngh');

      expect(cursor.line, 2);
      expect(cursor.column, 4);
    });

    test('行首光标列号应为 1', () {
      cursor.update(const TextSelection.collapsed(offset: 3), 'ab\ncdef');

      expect(cursor.line, 2);
      expect(cursor.column, 1);
    });

    test('选区应统计选中长度', () {
      cursor.update(
        const TextSelection(baseOffset: 4, extentOffset: 7),
        'aaa bbb aaa',
      );

      expect(cursor.selectionLength, 3);
      // 行列以 base 端为准
      expect(cursor.line, 1);
      expect(cursor.column, 5);
    });

    test('反向选区长度应为正', () {
      cursor.update(
        const TextSelection(baseOffset: 7, extentOffset: 4),
        'aaa bbb aaa',
      );

      expect(cursor.selectionLength, 3);
    });

    test('无效选区应回到初始状态', () {
      cursor.update(const TextSelection.collapsed(offset: 5), 'hello');
      cursor.update(const TextSelection.collapsed(offset: -1), 'hello');

      expect(cursor.line, 1);
      expect(cursor.column, 1);
      expect(cursor.selectionLength, 0);
    });

    test('超出文本长度的偏移应被钳制', () {
      cursor.update(const TextSelection.collapsed(offset: 100), 'ab\ncd');

      expect(cursor.line, 2);
      expect(cursor.column, 3);
    });

    test('值未变化时不应通知', () {
      var notifications = 0;
      cursor.addListener(() => notifications++);

      cursor.update(const TextSelection.collapsed(offset: 5), 'hello');
      expect(notifications, 1);

      cursor.update(const TextSelection.collapsed(offset: 5), 'hello');
      expect(notifications, 1);

      cursor.update(const TextSelection.collapsed(offset: 3), 'hello');
      expect(notifications, 2);
    });
  });
}