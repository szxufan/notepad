import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/models/note_file.dart';
import 'package:notepad/providers/editor_provider.dart';

void main() {
  late EditorProvider editor;

  setUp(() {
    editor = EditorProvider();
  });

  group('EditorProvider', () {
    test('默认字体大小应为 14.0', () {
      expect(editor.fontSize, 14.0);
    });

    test('increaseFontSize 应增大字体', () {
      editor.increaseFontSize();
      expect(editor.fontSize, 15.0);
    });

    test('decreaseFontSize 应减小字体', () {
      editor.decreaseFontSize();
      expect(editor.fontSize, 13.0);
    });

    test('字体大小不应超过最大值', () {
      for (var i = 0; i < 50; i++) {
        editor.increaseFontSize();
      }
      expect(editor.fontSize, EditorProvider.maxFontSize);
    });

    test('字体大小不应低于最小值', () {
      for (var i = 0; i < 50; i++) {
        editor.decreaseFontSize();
      }
      expect(editor.fontSize, EditorProvider.minFontSize);
    });

    test('adjustFontSize 应调节字体大小', () {
      editor.adjustFontSize(5);
      expect(editor.fontSize, 19.0);

      editor.adjustFontSize(-10);
      expect(editor.fontSize, 9.0);
    });

    test('showFind 应显示查找栏', () {
      editor.showFind();
      expect(editor.showFindReplace, true);
    });

    test('hideFindReplace 应隐藏查找栏并清空状态', () {
      editor.showFind();
      editor.setFindText('test');
      editor.hideFindReplace();

      expect(editor.showFindReplace, false);
      expect(editor.findText, '');
      expect(editor.matchCount, 0);
    });

    test('toggleFindReplace 应切换显示状态', () {
      expect(editor.showFindReplace, false);
      editor.toggleFindReplace();
      expect(editor.showFindReplace, true);
      editor.toggleFindReplace();
      expect(editor.showFindReplace, false);
    });

    test('setFindText 应计算匹配位置', () {
      final file = NoteFile(
        id: 'test',
        title: 'test.txt',
        content: 'hello world hello',
        isDirty: false,
        lastModified: DateTime.now(),
      );
      editor.setActiveFile(file);
      editor.setFindText('hello');

      expect(editor.matchCount, 2);
      expect(editor.currentMatchIndex, 0);
    });

    test('findNext 应跳转到下一个匹配', () {
      final file = NoteFile(
        id: 'test',
        title: 'test.txt',
        content: 'aaa aaa aaa',
        isDirty: false,
        lastModified: DateTime.now(),
      );
      editor.setActiveFile(file);
      editor.setFindText('aaa');

      expect(editor.currentMatchIndex, 0);
      editor.findNext();
      expect(editor.currentMatchIndex, 1);
      editor.findNext();
      expect(editor.currentMatchIndex, 2);
      editor.findNext();
      expect(editor.currentMatchIndex, 0); // 循环
    });

    test('findPrevious 应跳转到上一个匹配', () {
      final file = NoteFile(
        id: 'test',
        title: 'test.txt',
        content: 'aaa aaa aaa',
        isDirty: false,
        lastModified: DateTime.now(),
      );
      editor.setActiveFile(file);
      editor.setFindText('aaa');

      expect(editor.currentMatchIndex, 0);
      editor.findPrevious();
      expect(editor.currentMatchIndex, 2); // 循环到最后
    });

    test('replace 应替换当前匹配项', () {
      final file = NoteFile(
        id: 'test',
        title: 'test.txt',
        content: 'hello world',
        isDirty: false,
        lastModified: DateTime.now(),
      );
      editor.setActiveFile(file);
      editor.setFindText('hello');
      editor.setReplaceText('hi');

      final newContent = editor.replace();
      expect(newContent, 'hi world');
    });

    test('replaceAll 应替换所有匹配项', () {
      final file = NoteFile(
        id: 'test',
        title: 'test.txt',
        content: 'aaa aaa aaa',
        isDirty: false,
        lastModified: DateTime.now(),
      );
      editor.setActiveFile(file);
      editor.setFindText('aaa');
      editor.setReplaceText('bbb');

      final newContent = editor.replaceAll();
      expect(newContent, 'bbb bbb bbb');
      expect(editor.matchCount, 0);
    });

    test('空查找文本应无匹配', () {
      final file = NoteFile(
        id: 'test',
        title: 'test.txt',
        content: 'hello world',
        isDirty: false,
        lastModified: DateTime.now(),
      );
      editor.setActiveFile(file);
      editor.setFindText('');

      expect(editor.matchCount, 0);
      expect(editor.currentMatchIndex, -1);
    });

    test('正则模式应计算匹配位置', () {
      final file = NoteFile(
        id: 'test',
        title: 'test.txt',
        content: 'abc 123 def 456',
        isDirty: false,
        lastModified: DateTime.now(),
      );
      editor.setActiveFile(file);
      editor.setUseRegex(true);
      editor.setFindText(r'\d+');

      expect(editor.matchCount, 2);
      expect(editor.findMatches[0].start, 4);
      expect(editor.findMatches[0].end, 7);
      expect(editor.findMatches[1].start, 12);
      expect(editor.findMatches[1].end, 15);
      expect(editor.findError, isNull);
    });

    test('非法正则应视为无匹配并记录错误', () {
      final file = NoteFile(
        id: 'test',
        title: 'test.txt',
        content: 'hello world',
        isDirty: false,
        lastModified: DateTime.now(),
      );
      editor.setActiveFile(file);
      editor.setUseRegex(true);
      editor.setFindText('[');

      expect(editor.matchCount, 0);
      expect(editor.currentMatchIndex, -1);
      expect(editor.findError, isNotNull);
    });

    test('setUseRegex 切换后应重新计算匹配', () {
      final file = NoteFile(
        id: 'test',
        title: 'test.txt',
        content: 'aaa 123',
        isDirty: false,
        lastModified: DateTime.now(),
      );
      editor.setActiveFile(file);
      // 字面匹配
      editor.setFindText('a');
      expect(editor.matchCount, 3);
      // 切到正则，'a' 仍匹配 3 处
      editor.setUseRegex(true);
      expect(editor.matchCount, 3);
      // 正则模式匹配数字
      editor.setFindText(r'\d+');
      expect(editor.matchCount, 1);
      // 切回字面模式，r'\d+' 不再匹配
      editor.setUseRegex(false);
      expect(editor.matchCount, 0);
    });

    test('正则模式 replaceAll 应按字面替换文本生效', () {
      final file = NoteFile(
        id: 'test',
        title: 'test.txt',
        content: 'a1 b22 c333',
        isDirty: false,
        lastModified: DateTime.now(),
      );
      editor.setActiveFile(file);
      editor.setUseRegex(true);
      editor.setFindText(r'\d+');
      editor.setReplaceText('#');

      final newContent = editor.replaceAll();
      expect(newContent, 'a# b# c#');
      expect(editor.matchCount, 0);
    });

    test('非法正则 replaceAll 应返回原内容', () {
      final file = NoteFile(
        id: 'test',
        title: 'test.txt',
        content: 'hello world',
        isDirty: false,
        lastModified: DateTime.now(),
      );
      editor.setActiveFile(file);
      editor.setUseRegex(true);
      editor.setFindText('[');
      editor.setReplaceText('x');

      final newContent = editor.replaceAll();
      expect(newContent, 'hello world');
    });

    test('setSelectedText 后 showFind 应预填查找文本并计算匹配', () {
      final file = NoteFile(
        id: 'test',
        title: 'test.txt',
        content: 'aaa bbb aaa',
        isDirty: false,
        lastModified: DateTime.now(),
      );
      editor.setActiveFile(file);
      editor.setSelectedText('aaa');
      editor.showFind();

      expect(editor.showFindReplace, true);
      expect(editor.findText, 'aaa');
      expect(editor.matchCount, 2);
      expect(editor.currentMatchIndex, 0);
    });

    test('toggleFindReplace 应同样预填选中文本', () {
      final file = NoteFile(
        id: 'test',
        title: 'test.txt',
        content: 'aaa bbb aaa',
        isDirty: false,
        lastModified: DateTime.now(),
      );
      editor.setActiveFile(file);
      editor.setSelectedText('bbb');
      editor.toggleFindReplace();

      expect(editor.showFindReplace, true);
      expect(editor.findText, 'bbb');
      expect(editor.matchCount, 1);
    });

    test('无选中文本时 showFind 不应改动查找文本', () {
      final file = NoteFile(
        id: 'test',
        title: 'test.txt',
        content: 'aaa bbb aaa',
        isDirty: false,
        lastModified: DateTime.now(),
      );
      editor.setActiveFile(file);
      editor.setSelectedText('');
      editor.showFind();

      expect(editor.showFindReplace, true);
      expect(editor.findText, '');
      expect(editor.matchCount, 0);
    });

    test('选中文本应覆盖已有查找文本', () {
      final file = NoteFile(
        id: 'test',
        title: 'test.txt',
        content: 'aaa bbb aaa',
        isDirty: false,
        lastModified: DateTime.now(),
      );
      editor.setActiveFile(file);
      editor.showFind();
      editor.setFindText('aaa');
      expect(editor.findText, 'aaa');

      editor.setSelectedText('bbb');
      editor.showFind();
      expect(editor.findText, 'bbb');
      expect(editor.matchCount, 1);
    });

    test('跨行选中文本应整段填入并可匹配', () {
      final file = NoteFile(
        id: 'test',
        title: 'test.txt',
        content: 'x\nfoo bar\ny',
        isDirty: false,
        lastModified: DateTime.now(),
      );
      editor.setActiveFile(file);
      editor.setSelectedText('\nfoo ');
      editor.showFind();

      expect(editor.findText, '\nfoo ');
      expect(editor.matchCount, 1);
      expect(editor.findMatches.first.start, 1);
      expect(editor.findMatches.first.end, 6);
    });

    test('setSelectedText 不应触发通知', () {
      var notifications = 0;
      editor.addListener(() => notifications++);

      editor.setSelectedText('aaa');
      editor.setSelectedText('bbb');
      expect(notifications, 0);

      editor.showFind();
      expect(notifications, 1);
    });

    test('hideFindReplace 后 selectedText 应保留', () {
      final file = NoteFile(
        id: 'test',
        title: 'test.txt',
        content: 'aaa bbb aaa',
        isDirty: false,
        lastModified: DateTime.now(),
      );
      editor.setActiveFile(file);
      editor.setSelectedText('aaa');
      editor.showFind();
      editor.hideFindReplace();

      expect(editor.findText, '');
      expect(editor.selectedText, 'aaa');
    });
  });
}
