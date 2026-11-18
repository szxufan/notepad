/// 批量操作与只读模式 widget 测试。
///
/// 验证右键菜单批量关闭确认流、重命名对话框、
/// 拖拽排序与只读大文件横幅。
library widgets.batch_operations_test;

import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
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
import 'package:notepad/widgets/editor_panel.dart';
import 'package:notepad/widgets/file_list_panel.dart';
import 'package:provider/provider.dart';

/// 模拟另存为对话框：直接写入临时目录（不弹真实对话框）。
///
/// 保存用同步写入，避免 widget 测试假异步环境中真实 IO 不及时完成；
/// 原子写入本身由 service 层测试覆盖。
class _AutoSaveAsFileService extends FileService {
  _AutoSaveAsFileService(this.saveDir);

  final String saveDir;
  int counter = 0;

  @override
  Future<NoteFile> saveFile(NoteFile file) async {
    File(file.filePath!).writeAsStringSync(file.content);
    return file.copyWith(
      diskContent: file.content,
      isDirty: false,
      isNew: false,
    );
  }

  @override
  Future<NoteFile?> saveFileAs(NoteFile file) async {
    final name = 'saved_${counter++}.txt';
    final path = '$saveDir/$name';
    File(path).writeAsStringSync(file.content);
    return file.copyWith(
      filePath: path,
      title: name,
      diskContent: file.content,
      isDirty: false,
      isNew: false,
    );
  }
}

/// 模拟另存为对话框被取消。
class _CancelledSaveAsFileService extends FileService {
  @override
  Future<NoteFile?> saveFileAs(NoteFile file) async => null;
}

class _PausedSaveFileService extends FileService {
  late NoteFile pendingFile;
  final completer = Completer<NoteFile>();

  @override
  Future<NoteFile> saveFile(NoteFile file) {
    pendingFile = file;
    return completer.future;
  }

  void completeSave() {
    final now = DateTime.now();
    completer.complete(pendingFile.copyWith(
      diskContent: pendingFile.content,
      isDirty: false,
      lastModified: now,
      lastSavedAt: now,
      isNew: false,
    ));
  }
}

void main() {
  late FileListProvider fileList;
  late EditorProvider editor;
  late CursorProvider cursor;
  late DraftService draftService;
  late FileWatchService fileWatchService;
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('notepad_batch_ui_test_');
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
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {
      // Windows 下临时目录可能被短暂占用，忽略清理失败
    }
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

  NoteFile makeFile(
    String id, {
    bool dirty = false,
    String? path,
    bool readOnly = false,
  }) {
    return NoteFile(
      id: id,
      title: '$id.txt',
      filePath: path,
      content: dirty ? '本地修改' : '内容',
      diskContent: '内容',
      isDirty: dirty,
      lastModified: DateTime.now(),
      isReadOnly: readOnly,
    );
  }

  /// 右键点击指定标题的文件列表项并等待菜单弹出。
  Future<void> openContextMenu(WidgetTester tester, String title) async {
    // 限定在文件列表面板内，避免匹配到状态栏的同名文本
    await tester.tap(
      find.descendant(
        of: find.byType(FileListPanel),
        matching: find.text(title),
      ),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
  }

  group('右键菜单', () {
    testWidgets('应包含重命名与批量关闭项', (tester) async {
      fileList.loadFromDrafts([makeFile('a'), makeFile('b')]);
      await pumpApp(tester);

      await openContextMenu(tester, 'a.txt');

      expect(find.text('重命名'), findsOneWidget);
      expect(find.text('关闭其他'), findsOneWidget);
      expect(find.text('关闭已保存'), findsOneWidget);
      expect(find.text('关闭全部'), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('未保存文件的重命名应禁用', (tester) async {
      fileList.loadFromDrafts([makeFile('a')]);
      await pumpApp(tester);

      await openContextMenu(tester, 'a.txt');

      final item = tester.widget<PopupMenuItem<String>>(
        find.ancestor(
          of: find.text('重命名'),
          matching: find.byType(PopupMenuItem<String>),
        ),
      );
      expect(item.enabled, false);

      await disposeApp(tester);
    });
  });

  group('批量关闭', () {
    testWidgets('关闭其他应仅保留右键的文件', (tester) async {
      fileList.loadFromDrafts([makeFile('a'), makeFile('b'), makeFile('c')]);
      await pumpApp(tester);

      await openContextMenu(tester, 'b.txt');
      await tester.tap(find.text('关闭其他'));
      await tester.pumpAndSettle();

      expect(fileList.files.map((f) => f.id), ['b']);
      expect(fileList.activeFileId, 'b');

      await disposeApp(tester);
    });

    testWidgets('关闭全部有脏文件时应确认，不保存应全部关闭', (tester) async {
      fileList.loadFromDrafts([makeFile('a'), makeFile('b', dirty: true)]);
      await pumpApp(tester);

      await openContextMenu(tester, 'a.txt');
      await tester.tap(find.text('关闭全部'));
      await tester.pumpAndSettle();

      expect(find.text('1 个文件有未保存的修改，是否保存后关闭？'), findsOneWidget);
      await tester.tap(find.text('不保存'));
      await tester.pumpAndSettle();

      expect(fileList.isEmpty, true);

      await disposeApp(tester);
    });

    testWidgets('取消应保留所有文件', (tester) async {
      fileList.loadFromDrafts([makeFile('a', dirty: true)]);
      await pumpApp(tester);

      await openContextMenu(tester, 'a.txt');
      await tester.tap(find.text('关闭全部'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(fileList.files.length, 1);

      await disposeApp(tester);
    });

    testWidgets('全部保存应逐个保存后关闭', (tester) async {
      // 一个有磁盘路径的脏文件 + 一个未命名脏文件（走模拟另存为）
      final diskPath = '${tempDir.path}/disk.txt';
      File(diskPath).writeAsStringSync('旧内容');
      fileList = FileListProvider(
        fileService: _AutoSaveAsFileService(tempDir.path),
      );
      fileList.loadFromDrafts([
        makeFile('a', dirty: true, path: diskPath),
        makeFile('b', dirty: true),
      ]);
      await pumpApp(tester);

      await openContextMenu(tester, 'a.txt');
      await tester.tap(find.text('关闭全部'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部保存'));
      await tester.pumpAndSettle();

      expect(fileList.isEmpty, true);
      expect(File(diskPath).readAsStringSync(), '本地修改');
      expect(File('${tempDir.path}/saved_0.txt').readAsStringSync(), '本地修改');

      await disposeApp(tester);
    });

    testWidgets('保存等待期间其他文件变脏应中止批量关闭', (tester) async {
      final service = _PausedSaveFileService();
      fileList = FileListProvider(fileService: service);
      fileList.loadFromDrafts([
        makeFile('a', dirty: true, path: '${tempDir.path}/a.txt'),
        makeFile('b', path: '${tempDir.path}/b.txt'),
      ]);
      await pumpApp(tester);

      await openContextMenu(tester, 'a.txt');
      await tester.tap(find.text('关闭全部'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部保存'));
      await tester.pump();
      fileList.updateContent('b', '等待期间的新修改');
      service.completeSave();
      await tester.pumpAndSettle();

      expect(fileList.getFile('a')!.isDirty, false);
      expect(fileList.getFile('b')!.content, '等待期间的新修改');
      expect(fileList.getFile('b')!.isDirty, true);
      expect(find.text('关闭期间产生新修改，批量关闭已中止'), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('保存等待期间新建文件不应被旧关闭操作移除', (tester) async {
      final service = _PausedSaveFileService();
      fileList = FileListProvider(fileService: service);
      fileList.loadFromDrafts([
        makeFile('a', dirty: true, path: '${tempDir.path}/a.txt'),
      ]);
      await pumpApp(tester);

      await openContextMenu(tester, 'a.txt');
      await tester.tap(find.text('关闭全部'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部保存'));
      await tester.pump();
      final added = fileList.addNewFile();
      service.completeSave();
      await tester.pumpAndSettle();

      expect(fileList.files.map((file) => file.id), [added.id]);
      expect(fileList.getFile('a'), isNull);

      await disposeApp(tester);
    });

    testWidgets('另存为取消应中止整批关闭', (tester) async {
      fileList = FileListProvider(fileService: _CancelledSaveAsFileService());
      fileList.loadFromDrafts([makeFile('a', dirty: true)]);
      await pumpApp(tester);

      await openContextMenu(tester, 'a.txt');
      await tester.tap(find.text('关闭全部'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部保存'));
      await tester.pumpAndSettle();

      expect(fileList.files.length, 1);
      expect(find.text('保存失败或已取消，批量关闭已中止'), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('关闭已保存应保留脏文件', (tester) async {
      fileList.loadFromDrafts([makeFile('a'), makeFile('b', dirty: true)]);
      await pumpApp(tester);

      await openContextMenu(tester, 'b.txt');
      await tester.tap(find.text('关闭已保存'));
      await tester.pumpAndSettle();

      expect(fileList.files.map((f) => f.id), ['b']);

      await disposeApp(tester);
    });
  });

  group('重命名', () {
    testWidgets('应重命名磁盘文件并更新列表', (tester) async {
      final diskPath = '${tempDir.path}/old.txt';
      File(diskPath).writeAsStringSync('内容');
      fileList.loadFromDrafts([makeFile('a', path: diskPath)]);
      await pumpApp(tester);

      await openContextMenu(tester, 'a.txt');
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();

      // 对话框预填当前文件名
      expect(find.widgetWithText(TextField, 'a.txt'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'new.txt');
      await tester.tap(find.widgetWithText(FilledButton, '重命名'));
      await tester.pumpAndSettle();

      expect(fileList.getFile('a')!.title, 'new.txt');
      expect(File('${tempDir.path}/new.txt').existsSync(), true);
      expect(File(diskPath).existsSync(), false);

      await disposeApp(tester);
    });

    testWidgets('目标已存在应提示失败', (tester) async {
      final diskPath = '${tempDir.path}/old.txt';
      File(diskPath).writeAsStringSync('内容');
      File('${tempDir.path}/new.txt').writeAsStringSync('占用');
      fileList.loadFromDrafts([makeFile('a', path: diskPath)]);
      await pumpApp(tester);

      await openContextMenu(tester, 'a.txt');
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'new.txt');
      await tester.tap(find.widgetWithText(FilledButton, '重命名'));
      await tester.pumpAndSettle();

      expect(find.textContaining('重命名失败'), findsOneWidget);
      expect(fileList.getFile('a')!.title, 'a.txt');

      await disposeApp(tester);
    });
  });

  group('拖拽排序', () {
    testWidgets('列表应为 ReorderableListView 且可拖拽换序', (tester) async {
      fileList.loadFromDrafts([makeFile('a'), makeFile('b'), makeFile('c')]);
      await pumpApp(tester);

      expect(find.byType(ReorderableListView), findsOneWidget);

      // 桌面平台显示拖拽手柄，拖动第一项到列表下方
      final handle = find.byIcon(Icons.drag_handle).first;
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(kLongPressTimeout);
      await gesture.moveBy(const Offset(0, 100));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // 第一项应不再位于首位
      expect(fileList.files.first.id, isNot('a'));
      expect(fileList.files.map((f) => f.id).toSet(), {'a', 'b', 'c'});

      await disposeApp(tester);
    }, variant: TargetPlatformVariant.desktop());
  });

  group('只读大文件', () {
    testWidgets('应显示只读横幅且编辑器只读', (tester) async {
      fileList.loadFromDrafts([makeFile('big', readOnly: true)]);
      await pumpApp(tester);

      expect(find.text('大文件 · 只读模式，仅显示开头部分，不可编辑或保存'), findsOneWidget);
      final textField = tester.widget<TextField>(
        find.descendant(
          of: find.byType(EditorPanel),
          matching: find.byType(TextField),
        ),
      );
      expect(textField.readOnly, true);

      await disposeApp(tester);
    });

    testWidgets('普通文件不应显示只读横幅', (tester) async {
      fileList.loadFromDrafts([makeFile('normal')]);
      await pumpApp(tester);

      expect(find.text('大文件 · 只读模式，仅显示开头部分，不可编辑或保存'), findsNothing);
      final textField = tester.widget<TextField>(
        find.descendant(
          of: find.byType(EditorPanel),
          matching: find.byType(TextField),
        ),
      );
      expect(textField.readOnly, false);

      await disposeApp(tester);
    });

    testWidgets('只读文件的替换按钮应禁用', (tester) async {
      fileList.loadFromDrafts([makeFile('big', readOnly: true)]);
      await pumpApp(tester);

      editor.showFind();
      editor.setFindText('内容');
      await tester.pumpAndSettle();

      final replaceButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '替换'),
      );
      final replaceAllButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '全部替换'),
      );
      expect(replaceButton.onPressed, isNull);
      expect(replaceAllButton.onPressed, isNull);

      await disposeApp(tester);
    });
  });
}
