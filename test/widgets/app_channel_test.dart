/// 命令行参数与单实例文件转发通道测试。
///
/// 验证启动参数打开文件、原生侧 openFiles 通道调用、
/// 路径去重与打开失败提示。
library widgets.app_channel_test;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/pages/home_page.dart';
import 'package:notepad/providers/cursor_provider.dart';
import 'package:notepad/providers/editor_provider.dart';
import 'package:notepad/providers/file_list_provider.dart';
import 'package:notepad/services/draft_service.dart';
import 'package:notepad/services/encoding_service.dart';
import 'package:notepad/services/file_service.dart';
import 'package:notepad/services/file_watch_service.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void testWindowsWidgets(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(
    description,
    body,
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

void main() {
  late FileListProvider fileList;
  late EditorProvider editor;
  late CursorProvider cursor;
  late DraftService draftService;
  late FileWatchService fileWatchService;
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('notepad_channel_test_');
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

  Future<void> pumpApp(
    WidgetTester tester, {
    List<String> startupFiles = const [],
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<FileListProvider>.value(value: fileList),
          ChangeNotifierProvider<EditorProvider>.value(value: editor),
          ChangeNotifierProvider<CursorProvider>.value(value: cursor),
          Provider<DraftService>.value(value: draftService),
          Provider<FileWatchService>.value(value: fileWatchService),
        ],
        child: MaterialApp(home: HomePage(startupFiles: startupFiles)),
      ),
    );
    await tester.pump();
  }

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 模拟原生侧向 Dart 发起方法调用。
  Future<void> invokeFromNative(String method, Object? arguments) async {
    const codec = StandardMethodCodec();
    final message = codec.encodeMethodCall(MethodCall(method, arguments));
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage('notepad/app', message, (_) {});
  }

  testWindowsWidgets('启动命令行参数应打开文件', (tester) async {
    final path = '${tempDir.path}/startup.txt';
    File(path).writeAsStringSync('启动内容');

    await pumpApp(tester, startupFiles: [path]);
    await tester.pump();

    expect(fileList.files.length, 1);
    expect(fileList.activeFile!.content, '启动内容');
    expect(fileList.activeFile!.filePath, p.canonicalize(path));

    await disposeApp(tester);
  });

  testWidgets(
    '非 Windows 启动不调用原生通道但仍处理启动参数',
    (tester) async {
      final path = '${tempDir.path}/linux_startup.txt';
      File(path).writeAsStringSync('跨平台启动');

      await pumpApp(tester, startupFiles: [path]);
      await tester.pump();

      expect(fileList.files.single.content, '跨平台启动');

      await disposeApp(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWindowsWidgets('openFiles 通道调用应打开文件', (tester) async {
    final path = '${tempDir.path}/forwarded.txt';
    File(path).writeAsStringSync('转发内容');
    await pumpApp(tester);

    await invokeFromNative('openFiles', [path]);
    await tester.pump();

    expect(fileList.files.length, 1);
    expect(fileList.activeFile!.content, '转发内容');

    await disposeApp(tester);
  });

  testWindowsWidgets('重复转发同一文件应去重', (tester) async {
    final path = '${tempDir.path}/dup.txt';
    File(path).writeAsStringSync('内容');
    await pumpApp(tester);

    await invokeFromNative('openFiles', [path]);
    await tester.pump();
    await invokeFromNative('openFiles', [path]);
    await tester.pump();

    expect(fileList.files.length, 1);

    await disposeApp(tester);
  });

  testWindowsWidgets('空参数转发不应打开文件', (tester) async {
    await pumpApp(tester);

    await invokeFromNative('openFiles', <String>[]);
    await tester.pump();

    expect(fileList.isEmpty, true);

    await disposeApp(tester);
  });

  testWindowsWidgets('超大文件应提示且不阻塞其他文件', (tester) async {
    fileList = FileListProvider(fileService: FileService(maxFileBytes: 10));
    final bigPath = '${tempDir.path}/big.txt';
    File(bigPath).writeAsStringSync('01234567890123456789');
    final okPath = '${tempDir.path}/ok.txt';
    File(okPath).writeAsStringSync('正常');
    await pumpApp(tester);

    await invokeFromNative('openFiles', [bigPath, okPath]);
    await tester.pump();

    expect(fileList.files.length, 1);
    expect(fileList.activeFile!.filePath, p.canonicalize(okPath));
    expect(find.textContaining('文件过大'), findsOneWidget);

    await disposeApp(tester);
  });

  testWindowsWidgets('不存在的文件应提示打开失败', (tester) async {
    await pumpApp(tester);

    await invokeFromNative('openFiles', ['${tempDir.path}/missing.txt']);
    await tester.pump();

    expect(fileList.isEmpty, true);
    expect(find.textContaining('打开失败'), findsOneWidget);

    await disposeApp(tester);
  });
}
