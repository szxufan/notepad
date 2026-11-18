import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/services/ai_text_service.dart';
import 'package:notepad/widgets/ai_text_result_dialog.dart';

void main() {
  late List<Map<String, dynamic>> clipboardWrites;

  setUp(() {
    clipboardWrites = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardWrites.add(Map<String, dynamic>.from(call.arguments as Map));
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// 泵入宿主页面并打开结果对话框。
  Future<void> pumpDialog(
    WidgetTester tester, {
    required Future<String> Function() task,
    required void Function(String, bool) onApply,
    bool allowKeepOriginal = false,
    String actionLabel = '摘要',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AiTextResultDialog.show(
                context,
                actionLabel: actionLabel,
                task: task,
                onApply: onApply,
                allowKeepOriginal: allowKeepOriginal,
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('加载中应显示进度，完成后显示结果', (tester) async {
    final completer = Completer<String>();
    await pumpDialog(
      tester,
      task: () => completer.future,
      onApply: (_, __) {},
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('替换选区'), findsNothing);

    completer.complete('结果文本');
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('结果文本'), findsOneWidget);
    expect(find.text('替换选区'), findsOneWidget);
  });

  testWidgets('摘要模式替换选区应回调 keepOriginal=false 并关闭', (tester) async {
    final applied = <(String, bool)>[];
    await pumpDialog(
      tester,
      task: () async => '结果文本',
      onApply: (r, k) => applied.add((r, k)),
    );
    await tester.pump();

    expect(find.text('保留原文插入'), findsNothing);
    await tester.tap(find.text('替换选区'));
    await tester.pumpAndSettle();

    expect(applied, [('结果文本', false)]);
    expect(find.byType(AiTextResultDialog), findsNothing);
  });

  testWidgets('翻译模式保留原文插入应回调 keepOriginal=true', (tester) async {
    final applied = <(String, bool)>[];
    await pumpDialog(
      tester,
      task: () async => 'translation',
      onApply: (r, k) => applied.add((r, k)),
      allowKeepOriginal: true,
      actionLabel: '翻译',
    );
    await tester.pump();

    expect(find.text('替换原文'), findsOneWidget);
    expect(find.text('保留原文插入'), findsOneWidget);

    await tester.tap(find.text('保留原文插入'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(applied, [('translation', true)]);
  });

  testWidgets('翻译模式替换原文应回调 keepOriginal=false', (tester) async {
    final applied = <(String, bool)>[];
    await pumpDialog(
      tester,
      task: () async => 'translation',
      onApply: (r, k) => applied.add((r, k)),
      allowKeepOriginal: true,
      actionLabel: '翻译',
    );
    await tester.pump();

    await tester.tap(find.text('替换原文'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(applied, [('translation', false)]);
  });

  testWidgets('失败应显示错误与重试，重试应重跑任务', (tester) async {
    var calls = 0;
    Future<String> task() {
      calls++;
      if (calls == 1) {
        return Future.error(const AiTextException('模拟失败'));
      }
      return Future.value('重试成功');
    }

    await pumpDialog(tester, task: task, onApply: (_, __) {});
    await tester.pump();

    expect(find.text('模拟失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();

    expect(calls, 2);
    expect(find.text('重试成功'), findsOneWidget);
  });

  testWidgets('复制应写入剪贴板并提示', (tester) async {
    await pumpDialog(
      tester,
      task: () async => '复制内容',
      onApply: (_, __) {},
    );
    await tester.pump();

    await tester.tap(find.text('复制'));
    await tester.pump();

    expect(clipboardWrites, hasLength(1));
    expect(clipboardWrites.first['text'], '复制内容');
    expect(find.text('已复制'), findsOneWidget);
    // 复制不应关闭对话框
    expect(find.byType(AiTextResultDialog), findsOneWidget);
  });

  testWidgets('关闭不应触发应用回调', (tester) async {
    final applied = <(String, bool)>[];
    await pumpDialog(
      tester,
      task: () async => '结果',
      onApply: (r, k) => applied.add((r, k)),
    );
    await tester.pump();

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    expect(applied, isEmpty);
    expect(find.byType(AiTextResultDialog), findsNothing);
  });
}