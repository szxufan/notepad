/// 主页面快捷键绑定测试。
///
/// 验证 Ctrl+F 切换、F3/Shift+F3 跳转、Esc 关闭查找栏，
/// 以及选中文本后 Ctrl+F / Ctrl+H 自动填入查找框。
library widgets.shortcuts_test;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/models/note_file.dart';
import 'package:notepad/pages/home_page.dart';
import 'package:notepad/providers/cursor_provider.dart';
import 'package:notepad/providers/editor_provider.dart';
import 'package:notepad/providers/file_list_provider.dart';
import 'package:notepad/services/draft_service.dart';
import 'package:notepad/services/encoding_service.dart';
import 'package:notepad/services/file_service.dart';
import 'package:notepad/services/file_watch_service.dart';
import 'package:provider/provider.dart';

class _EncodingFailureFileService extends FileService {
  @override
  Future<NoteFile?> saveFileAs(NoteFile file) async {
    throw const EncodingException(EncodingService.gbkName, '模拟编码失败');
  }
}

void main() {
  late FileListProvider fileList;
  late EditorProvider editor;
  late CursorProvider cursor;
  late DraftService draftService;
  late FileWatchService fileWatchService;

  /// 模拟 Ctrl/Cmd + [key] 组合键。
  Future<void> sendCtrlKey(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  setUp(() {
    fileList = FileListProvider(fileService: FileService());
    fileList.loadFromDrafts([
      NoteFile(
        id: 'test',
        title: 'test.txt',
        content: 'aaa bbb aaa',
        isDirty: false,
        lastModified: DateTime.now(),
      ),
    ]);
    editor = EditorProvider();
    cursor = CursorProvider();
    draftService = DraftService();
    fileWatchService =
        FileWatchService(encodingService: const EncodingService());
  });

  tearDown(() {
    // 兜底清理定时器（正常路径由 disposeApp 触发 HomePage.dispose）
    fileWatchService.stop();
    draftService.stopAutoSave();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<FileListProvider>.value(value: fileList),
          ChangeNotifierProvider<EditorProvider>.value(value: editor),
          ChangeNotifierProvider<CursorProvider>.value(value: cursor),
          Provider<DraftService>.value(value: draftService),
          Provider<FileWatchService>.value(value: fileWatchService),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pump();
  }

  /// 卸载组件树，清理自动保存与防抖定时器。
  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('Ctrl+F 应打开查找栏，再次按下应关闭', (tester) async {
    await pumpApp(tester);

    expect(editor.showFindReplace, false);
    await sendCtrlKey(tester, LogicalKeyboardKey.keyF);
    expect(editor.showFindReplace, true);
    await sendCtrlKey(tester, LogicalKeyboardKey.keyF);
    expect(editor.showFindReplace, false);

    await disposeApp(tester);
  });

  testWidgets('F3/Shift+F3 应跳转匹配，Esc 应关闭查找栏', (tester) async {
    await pumpApp(tester);
    await sendCtrlKey(tester, LogicalKeyboardKey.keyF);

    // 在查找框输入文本（查找框是第一个 TextField）
    await tester.enterText(find.byType(TextField).first, 'aaa');
    await tester.pump();
    expect(editor.matchCount, 2);
    expect(editor.currentMatchIndex, 0);

    // F3: 下一个
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pump();
    expect(editor.currentMatchIndex, 1);

    // Shift+F3: 上一个
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(editor.currentMatchIndex, 0);

    // Esc: 关闭查找栏
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(editor.showFindReplace, false);

    // 等待编辑器防抖定时器结束
    await tester.pump(const Duration(milliseconds: 400));
    await disposeApp(tester);
  });

  testWidgets('替换与全部替换应更新文件内容与编辑器显示', (tester) async {
    await pumpApp(tester);
    await sendCtrlKey(tester, LogicalKeyboardKey.keyF);

    // 输入查找与替换文本
    await tester.enterText(find.byType(TextField).at(0), 'aaa');
    await tester.enterText(find.byType(TextField).at(1), 'xxx');
    await tester.pump();

    // 诊断：确认匹配与替换文本状态
    expect(editor.findText, 'aaa');
    expect(editor.replaceText, 'xxx');
    expect(editor.matchCount, 2);
    expect(editor.currentMatchIndex, 0);
    expect(editor.currentContent, 'aaa bbb aaa');

    // 单个替换：替换第一个匹配
    await tester.tap(find.widgetWithText(TextButton, '替换'));
    await tester.pump();
    expect(editor.matchCount, 1);
    expect(fileList.activeFile!.content, 'xxx bbb aaa');
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
      'xxx bbb aaa',
    );

    // 全部替换：替换剩余匹配
    await tester.tap(find.widgetWithText(TextButton, '全部替换'));
    await tester.pump();
    expect(fileList.activeFile!.content, 'xxx bbb xxx');
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
      'xxx bbb xxx',
    );

    // 关闭查找栏后，在编辑器输入仍应同步内容
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pump();
    expect(fileList.activeFile!.content, 'zzz');

    await tester.pump(const Duration(milliseconds: 400));
    await disposeApp(tester);
  });

  testWidgets('选中编辑器文本后 Ctrl+F 应填入查找框', (tester) async {
    await pumpApp(tester);
    await tester.pump();

    // 查找栏未打开时，唯一的 TextField 即编辑器
    final editorController =
        tester.widget<TextField>(find.byType(TextField).first).controller!;
    expect(editorController.text, 'aaa bbb aaa');

    // 选中 'bbb'
    editorController.selection =
        const TextSelection(baseOffset: 4, extentOffset: 7);
    await tester.pump();
    expect(editor.selectedText, 'bbb');

    // Ctrl+F 打开查找栏：应自动填入选中文本
    await sendCtrlKey(tester, LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(editor.showFindReplace, true);
    expect(editor.findText, 'bbb');
    expect(editor.matchCount, 1);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      'bbb',
    );

    // 改选 'aaa' 后按 Ctrl+H：选中文本应覆盖查找框内容
    editorController.selection =
        const TextSelection(baseOffset: 0, extentOffset: 3);
    await tester.pump();
    await sendCtrlKey(tester, LogicalKeyboardKey.keyH);
    await tester.pump();
    expect(editor.findText, 'aaa');
    expect(editor.matchCount, 2);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      'aaa',
    );

    await tester.pump(const Duration(milliseconds: 400));
    await disposeApp(tester);
  });

  testWidgets('Ctrl+Shift+S 编码失败应显示回退对话框', (tester) async {
    fileList = FileListProvider(fileService: _EncodingFailureFileService());
    fileList.loadFromDrafts([
      NoteFile(
        id: 'encoding-error',
        title: 'gbk.txt',
        content: '😀',
        diskContent: '',
        isDirty: true,
        lastModified: DateTime.now(),
        encoding: EncodingService.gbkName,
      ),
    ]);
    await pumpApp(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.text('无法以当前编码保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(fileList.activeFile!.encoding, EncodingService.gbkName);

    await disposeApp(tester);
  });

  testWidgets('无选区时 Ctrl+F 不应改动查找文本', (tester) async {
    await pumpApp(tester);
    await tester.pump();

    final editorController =
        tester.widget<TextField>(find.byType(TextField).first).controller!;
    expect(editorController.text, 'aaa bbb aaa');

    // 仅光标，无有效选区
    editorController.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();
    expect(editor.selectedText, '');

    await sendCtrlKey(tester, LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(editor.showFindReplace, true);
    expect(editor.findText, '');
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      '',
    );

    await tester.pump(const Duration(milliseconds: 400));
    await disposeApp(tester);
  });
}
