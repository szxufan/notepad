import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notepad/models/ai_config.dart';
import 'package:notepad/services/ai_text_service.dart';

void main() {
  const config = AiConfig(
    apiEndpoint: 'https://example.com/v1/chat/completions',
    apiToken: 'test-token',
    model: 'test-model',
    maxInputChars: 10,
    targetLanguage: '日文',
  );

  /// 返回固定内容的 MockClient，并捕获请求。
  MockClient mockWithContent(String content, {int statusCode = 200}) {
    return MockClient((request) async {
      return http.Response.bytes(
        utf8.encode(json.encode({
          'choices': [
            {'message': {'content': content}}
          ],
        })),
        statusCode,
      );
    });
  }

  /// 捕获请求的 MockClient。
  (MockClient, http.Request Function()) capturingClient(String content) {
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response.bytes(
        utf8.encode(json.encode({
          'choices': [
            {'message': {'content': content}}
          ],
        })),
        200,
      );
    });
    return (client, () => captured!);
  }

  group('AiTextService 请求形状', () {
    test('summarize 应发送摘要提示词与原文', () async {
      final (client, getCaptured) = capturingClient('摘要结果');
      final service = AiTextService(client: client);

      final result = await service.summarize('一段中文', config);

      expect(result, '摘要结果');
      final captured = getCaptured();
      expect(captured.url.toString(), config.apiEndpoint);
      expect(captured.headers['Authorization'], 'Bearer test-token');
      final body = json.decode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'test-model');
      final messages = body['messages'] as List;
      expect(messages.length, 2);
      expect(messages[0]['content'], contains('摘要'));
      expect(messages[1]['content'], '一段中文');
    });

    test('polish 应发送润色提示词与原文', () async {
      final (client, getCaptured) = capturingClient('润色结果');
      final service = AiTextService(client: client);

      final result = await service.polish('一段中文', config);

      expect(result, '润色结果');
      final body = json.decode(getCaptured().body) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      expect(messages[0]['content'], contains('润色'));
      expect(messages[1]['content'], '一段中文');
    });

    test('translate 提示词应包含目标语言', () async {
      final (client, getCaptured) = capturingClient('翻訳結果');
      final service = AiTextService(client: client);

      final result = await service.translate('一段中文', config);

      expect(result, '翻訳結果');
      final body = json.decode(getCaptured().body) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      expect(messages[0]['content'], contains('日文'));
      expect(messages[1]['content'], '一段中文');
    });

    test('中文内容应以 UTF-8 字节发送且结果去空白', () async {
      final (client, getCaptured) = capturingClient('  结果\n');
      final service = AiTextService(client: client);

      final result = await service.summarize('中文内容', config);

      expect(result, '结果');
      // bodyBytes 按 UTF-8 解码应还原中文
      final body =
          json.decode(utf8.decode(getCaptured().bodyBytes)) as Map<String, dynamic>;
      expect((body['messages'] as List)[1]['content'], '中文内容');
    });
  });

  group('AiTextService 校验与错误', () {
    test('未配置时应抛出 AiTextException', () {
      final service = AiTextService(client: mockWithContent('结果'));

      expect(
        () => service.summarize('文本', AiConfig.defaultConfig),
        throwsA(isA<AiTextException>()),
      );
    });

    test('超过 maxInputChars 应拒绝且不发起请求', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response.bytes(
          utf8.encode(json.encode({
            'choices': [
              {'message': {'content': '结果'}}
            ],
          })),
          200,
        );
      });
      final service = AiTextService(client: client);

      expect(
        () => service.polish('字' * 11, config),
        throwsA(isA<AiTextException>()),
      );
      // 等待可能的异步请求发出
      await Future<void>.delayed(Duration.zero);
      expect(requestCount, 0);
    });

    test('恰好等于 maxInputChars 应正常发送', () async {
      final service = AiTextService(client: mockWithContent('结果'));

      final result = await service.translate('字' * 10, config);

      expect(result, '结果');
    });

    test('非 200 应抛出 AiTextException', () {
      final service = AiTextService(client: mockWithContent('', statusCode: 401));

      expect(
        () => service.summarize('文本', config),
        throwsA(isA<AiTextException>()),
      );
    });

    test('空结果应抛出 AiTextException', () {
      final service = AiTextService(client: mockWithContent('   '));

      expect(
        () => service.polish('文本', config),
        throwsA(isA<AiTextException>()),
      );
    });
  });
}