/// 编辑器 AI 文本操作流程测试。
///
/// 验证右键菜单 AI 项、替换选区、保留原文插入（换行边界）、
/// 陈旧守卫与未配置提示。
library widgets.editor_ai_flow_test;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notepad/models/ai_config.dart';
import 'package:notepad/models/note_file.dart';
import 'package:notepad/providers/cursor_provider.dart';
import 'package:notepad/providers/editor_provider.dart';
import 'package:notepad/providers/file_list_provider.dart';
import 'package:notepad/services/ai_config_service.dart';
import 'package:notepad/services/ai_text_service.dart';
import 'package:notepad/services/file_service.dart';
import 'package:notepad/widgets/editor_panel.dart';
import 'package:provider/provider.dart';

void main() {
  late FileListProvider fileList;
  late EditorProvider editor;
  late CursorProvider cursor;
  late AiConfigService aiConfigService;
  late Directory tempDir;
  late String aiResponse;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('notepad_ai_flow_test_');
    fileList = FileListProvider(fileService: FileService());
    editor = EditorProvider();
    cursor = CursorProvider();
    aiConfigService = AiConfigService();
    aiConfigService.testConfigDir = tempDir.path;
    await aiConfigService.save(const AiConfig(
      apiEndpoint: 'https://example.com/v1/chat/completions',
      apiToken: 'token',
      model: 'model',
      maxInputChars: 2000,
      targetLanguage: '英文',
    ));
    aiResponse = 'AI 结果';
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {
      // Windows 下临时目录可能被短暂占用，忽略清理失败
    }
  });

  /// 加载测试文件。
  NoteFile loadFile(String content) {
    final file = NoteFile(
      id: 'test',
      title: 'test.txt',
      content: content,
      diskContent: content,
      lastModified: DateTime.now(),
    );
    fileList.loadFromDrafts([file]);
    return file;
  }

  /// 泵入编辑器（可覆盖 AI 配置服务）。
  Future<void> pumpEditor(
    WidgetTester tester, {
    AiConfigService? configService,
  }) async {
    final aiTextService = AiTextService(
      client: MockClient(
        (request) async => http.Response.bytes(
          utf8.encode(json.encode({
            'choices': [
              {'message': {'content': aiResponse}}
            ],
          })),
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<FileListProvider>.value(value: fileList),
          ChangeNotifierProvider<EditorProvider>.value(value: editor),
          ChangeNotifierProvider<CursorProvider>.value(value: cursor),
          Provider<AiConfigService>.value(
            value: configService ?? aiConfigService,
          ),
          Provider<AiTextService>.value(value: aiTextService),
        ],
        child: const MaterialApp(home: Scaffold(body: EditorPanel())),
      ),
    );
    await tester.pump();
  }

  /// 选中文本并打开上下文菜单。
  ///
  /// 直接调用 [EditableTextState.toggleToolbar]——桌面右键的内部入口，
  /// 手势接线属 Flutter 自身实现，此处验证菜单内容与后续流程。
  Future<void> selectAndRightClick(
    WidgetTester tester,
    int start,
    int end,
  ) async {
    final controller =
        tester.widget<TextField>(find.byType(TextField)).controller!;
    controller.selection = TextSelection(baseOffset: start, extentOffset: end);
    await tester.pump();
    tester.state<EditableTextState>(find.byType(EditableText)).toggleToolbar();
    await tester.pumpAndSettle();
  }

  /// 点击菜单项并等待结果对话框就绪（MockClient 立即返回）。
  Future<void> openAiDialog(WidgetTester tester, String menuItem) async {
    await tester.tap(find.text(menuItem));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('有选区右键应显示 AI 菜单项', (tester) async {
    loadFile('你好世界');
    await pumpEditor(tester);

    await selectAndRightClick(tester, 0, 4);

    expect(find.text('AI 摘要'), findsOneWidget);
    expect(find.text('AI 润色'), findsOneWidget);
    expect(find.text('AI 翻译'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('无选区右键不应显示 AI 菜单项', (tester) async {
    loadFile('你好世界');
    await pumpEditor(tester);

    final controller =
        tester.widget<TextField>(find.byType(TextField)).controller!;
    controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();
    tester.state<EditableTextState>(find.byType(EditableText)).toggleToolbar();
    await tester.pumpAndSettle();

    expect(find.text('AI 摘要'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('AI 摘要替换选区应更新文件内容', (tester) async {
    loadFile('你好世界');
    await pumpEditor(tester);
    aiResponse = '摘要';

    await selectAndRightClick(tester, 0, 4);
    await openAiDialog(tester, 'AI 摘要');
    expect(find.text('摘要'), findsOneWidget);

    await tester.tap(find.text('替换选区'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(fileList.activeFile!.content, '摘要');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('AI 翻译保留原文插入应在行中选区后补换行', (tester) async {
    loadFile('abc你好def');
    await pumpEditor(tester);
    aiResponse = 'hello';

    // 选中 'abc你好'（0..5），插入点在 'def' 之前
    await selectAndRightClick(tester, 0, 5);
    await openAiDialog(tester, 'AI 翻译');

    await tester.tap(find.text('保留原文插入'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(fileList.activeFile!.content, 'abc你好\nhello\ndef');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('AI 翻译保留原文插入在行尾不应产生多余空行', (tester) async {
    loadFile('你好\nworld');
    await pumpEditor(tester);
    aiResponse = 'hello';

    // 选中 '你好'（0..2），插入点已是换行符
    await selectAndRightClick(tester, 0, 2);
    await openAiDialog(tester, 'AI 翻译');

    await tester.tap(find.text('保留原文插入'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(fileList.activeFile!.content, '你好\nhello\nworld');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('AI 翻译保留原文插入应保持 CRLF 换行且不留空行', (tester) async {
    loadFile('你好\r\nworld');
    await pumpEditor(tester);
    aiResponse = 'hello';

    await selectAndRightClick(tester, 0, 2);
    await openAiDialog(tester, 'AI 翻译');

    await tester.tap(find.text('保留原文插入'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(fileList.activeFile!.content, '你好\r\nhello\r\nworld');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('弹窗期间内容变化应拦截应用并提示', (tester) async {
    final file = loadFile('你好世界');
    await pumpEditor(tester);

    await selectAndRightClick(tester, 0, 4);
    await openAiDialog(tester, 'AI 翻译');

    // 模拟弹窗期间外部修改导致内容变化
    fileList.updateContent(file.id, '外部修改后的内容');
    await tester.pump();

    await tester.tap(find.text('替换原文'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('文件内容已变化，无法应用结果'), findsOneWidget);
    expect(fileList.activeFile!.content, '外部修改后的内容');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('AI 未配置应提示并打开设置对话框', (tester) async {
    final unconfigured = AiConfigService();
    unconfigured.testConfigDir = '${tempDir.path}/unconfigured';
    loadFile('你好世界');
    await pumpEditor(tester, configService: unconfigured);

    await selectAndRightClick(tester, 0, 4);
    await tester.tap(find.text('AI 摘要'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('AI 接口未配置，请先在设置中完成配置'), findsOneWidget);
    expect(find.text('AI 设置'), findsOneWidget);

    // 关闭设置对话框，让文件 IO 落定后再清理临时目录
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}