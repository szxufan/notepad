/// 外部修改处理与状态栏编码交互测试。
///
/// 验证外部修改的静默重载/询问对话框分支，
/// 以及状态栏光标信息显示与编码切换菜单。
library widgets.external_change_test;

import 'dart:io';

import 'package:flutter/material.dart';
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

class _CancelledSaveAsFileService extends FileService {
  @override
  Future<NoteFile?> saveFileAs(NoteFile file) async => null;
}

void main() {
  late FileListProvider fileList;
  late EditorProvider editor;
  late CursorProvider cursor;
  late DraftService draftService;
  late FileWatchService fileWatchService;

  setUp(() {
    fileList = FileListProvider(fileService: FileService());
    editor = EditorProvider();
    cursor = CursorProvider();
    draftService = DraftService();
    fileWatchService =
        FileWatchService(encodingService: const EncodingService());
  });

  tearDown(() {
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

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 加载一个无磁盘路径的测试文件。
  NoteFile loadTestFile({required bool dirty}) {
    final file = NoteFile(
      id: 'test',
      title: 'test.txt',
      content: dirty ? '本地修改' : '磁盘内容',
      diskContent: '磁盘内容',
      isDirty: dirty,
      lastModified: DateTime.now(),
    );
    fileList.loadFromDrafts([file]);
    return file;
  }

  group('外部修改处理', () {
    testWidgets('无本地修改时应静默重载', (tester) async {
      final file = loadTestFile(dirty: false);
      await pumpApp(tester);

      fileWatchService.onExternalChange!(file, '外部新内容');
      await tester.pump();

      expect(fileList.activeFile!.content, '外部新内容');
      expect(fileList.activeFile!.diskContent, '外部新内容');
      expect(fileList.activeFile!.isDirty, false);
      expect(find.text('重新加载'), findsNothing);

      await disposeApp(tester);
    });

    testWidgets('有本地修改时应弹对话框，重新加载应更新内容', (tester) async {
      final file = loadTestFile(dirty: true);
      await pumpApp(tester);

      fileWatchService.onExternalChange!(file, '外部新内容');
      await tester.pump();

      expect(find.text('重新加载'), findsOneWidget);
      expect(find.text('保留我的修改'), findsOneWidget);

      await tester.tap(find.text('重新加载'));
      await tester.pump();

      expect(fileList.activeFile!.content, '外部新内容');
      expect(fileList.activeFile!.isDirty, false);

      await disposeApp(tester);
    });

    testWidgets('弹窗期间再次外部修改后应加载最新内容', (tester) async {
      final file = loadTestFile(dirty: true);
      await pumpApp(tester);

      fileWatchService.onExternalChange!(file, '外部版本 A');
      await tester.pump();
      fileWatchService.onExternalChange!(file, '外部版本 B');
      await tester.pump();

      expect(find.text('重新加载'), findsOneWidget);
      await tester.tap(find.text('重新加载'));
      await tester.pump();

      expect(fileList.activeFile!.content, '外部版本 B');
      expect(fileList.activeFile!.diskContent, '外部版本 B');
      expect(fileList.activeFile!.isDirty, false);

      await disposeApp(tester);
    });

    testWidgets('保留我的修改应不改动内容', (tester) async {
      final file = loadTestFile(dirty: true);
      await pumpApp(tester);

      fileWatchService.onExternalChange!(file, '外部新内容');
      await tester.pump();
      await tester.tap(find.text('保留我的修改'));
      await tester.pump();

      expect(fileList.activeFile!.content, '本地修改');
      expect(fileList.activeFile!.isDirty, true);

      await disposeApp(tester);
    });

    testWidgets('磁盘内容与快照一致时应忽略（自身保存）', (tester) async {
      final file = loadTestFile(dirty: false);
      await pumpApp(tester);

      fileWatchService.onExternalChange!(file, '磁盘内容');
      await tester.pump();

      expect(fileList.activeFile!.content, '磁盘内容');
      expect(find.text('重新加载'), findsNothing);

      await disposeApp(tester);
    });
  });

  group('关闭前保存', () {
    testWidgets('取消另存为时不应关闭文件', (tester) async {
      fileList = FileListProvider(fileService: _CancelledSaveAsFileService());
      loadTestFile(dirty: true);
      await pumpApp(tester);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(fileList.getFile('test'), isNotNull);
      expect(fileList.activeFile!.content, '本地修改');
      expect(find.byType(AlertDialog), findsNothing);

      await disposeApp(tester);
    });

    testWidgets('编码保存失败应提示并保留文件', (tester) async {
      final tempDir =
          Directory.systemTemp.createTempSync('notepad_close_save_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final path = '${tempDir.path}/gbk.txt';
      File(path).writeAsBytesSync([0xD6, 0xD0, 0xCE, 0xC4]);
      final file = fileList.openFile(path);
      fileList.updateContent(file.id, '😀');
      await pumpApp(tester);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(fileList.getFile(file.id), isNotNull);
      expect(fileList.activeFile!.isDirty, true);
      expect(find.textContaining('保存失败'), findsOneWidget);

      await disposeApp(tester);
    });
  });

  group('状态栏', () {
    testWidgets('应显示光标行列、字数与编码', (tester) async {
      loadTestFile(dirty: false);
      await pumpApp(tester);

      expect(find.text('行 1, 列 1'), findsOneWidget);
      expect(find.text('4 字符'), findsOneWidget);
      expect(find.text('UTF-8'), findsOneWidget);

      // 移动光标到第二字符后
      final controller =
          tester.widget<TextField>(find.byType(TextField).first).controller!;
      controller.selection = const TextSelection.collapsed(offset: 2);
      await tester.pump();
      expect(find.text('行 1, 列 3'), findsOneWidget);

      // 选中文本应显示选区计数
      controller.selection =
          const TextSelection(baseOffset: 0, extentOffset: 2);
      await tester.pump();
      expect(find.text('已选 2 / 4 字符'), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('切换到相同内容文件时应重置光标与选区', (tester) async {
      final now = DateTime.now();
      fileList.loadFromDrafts([
        NoteFile(
          id: 'first',
          title: 'first.txt',
          content: '相同内容',
          diskContent: '相同内容',
          lastModified: now,
        ),
        NoteFile(
          id: 'second',
          title: 'second.txt',
          content: '相同内容',
          diskContent: '相同内容',
          lastModified: now,
        ),
      ]);
      await pumpApp(tester);
      final controller =
          tester.widget<TextField>(find.byType(TextField).first).controller!;
      controller.selection =
          const TextSelection(baseOffset: 1, extentOffset: 3);
      await tester.pump();
      expect(cursor.line, 1);
      expect(cursor.column, 2);
      expect(cursor.selectionLength, 2);

      fileList.switchToFile('second');
      await tester.pump();
      await tester.pump();

      expect(cursor.line, 1);
      expect(cursor.column, 1);
      expect(cursor.selectionLength, 0);
      expect(controller.selection, const TextSelection.collapsed(offset: 0));

      await disposeApp(tester);
    });

    testWidgets('点击编码应打开菜单并切换（干净文件直接重读）', (tester) async {
      final tempDir =
          Directory.systemTemp.createTempSync('notepad_statusbar_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final path = '${tempDir.path}/gbk.txt';
      // '中文' 的 GBK 字节
      File(path).writeAsBytesSync([0xD6, 0xD0, 0xCE, 0xC4]);
      fileList.openFile(path);
      await pumpApp(tester);

      expect(find.text('GBK'), findsOneWidget);
      expect(fileList.activeFile!.content, '中文');

      await tester.tap(find.text('GBK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('UTF-8'));
      await tester.pump();

      expect(fileList.activeFile!.encoding, 'UTF-8');
      // GBK 字节按 UTF-8 容错解码不再是 '中文'
      expect(fileList.activeFile!.content, isNot('中文'));
      expect(fileList.activeFile!.isDirty, false);

      await disposeApp(tester);
    });

    testWidgets('脏文件切换编码应先确认，取消后不变', (tester) async {
      final tempDir =
          Directory.systemTemp.createTempSync('notepad_statusbar_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final path = '${tempDir.path}/gbk.txt';
      File(path).writeAsBytesSync([0xD6, 0xD0, 0xCE, 0xC4]);
      final file = fileList.openFile(path);
      fileList.updateContent(file.id, '本地修改');
      await pumpApp(tester);

      await tester.tap(find.text('GBK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('UTF-8'));
      await tester.pump();

      expect(find.text('切换编码为 UTF-8'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pump();

      expect(fileList.activeFile!.encoding, 'GBK');
      expect(fileList.activeFile!.content, '本地修改');

      await disposeApp(tester);
    });
  });
}
