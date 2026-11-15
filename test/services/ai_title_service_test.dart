import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notepad/models/ai_config.dart';
import 'package:notepad/services/ai_title_service.dart';

void main() {
  const config = AiConfig(
    apiEndpoint: 'https://example.com/v1/chat/completions',
    apiToken: 'test-token',
    model: 'test-model',
    maxInputChars: 10,
  );

  /// 构造返回指定标题的 MockClient。
  MockClient mockWithTitle(String title, {int statusCode = 200}) {
    return MockClient((request) async {
      return http.Response.bytes(
        utf8.encode(
          json.encode({
            'choices': [
              {
                'message': {'content': title},
              },
            ],
          }),
        ),
        statusCode,
      );
    });
  }

  group('AiTitleService', () {
    test('请求应包含正确的端点、鉴权头与模型', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response.bytes(
          utf8.encode(
            json.encode({
              'choices': [
                {
                  'message': {'content': '标题'},
                },
              ],
            }),
          ),
          200,
        );
      });
      final service = AiTitleService(client: client);

      await service.generateTitle('内容', config);

      expect(captured, isNotNull);
      expect(captured!.url.toString(), config.apiEndpoint);
      expect(captured!.headers['Authorization'], 'Bearer test-token');
      final body = json.decode(captured!.body) as Map<String, dynamic>;
      expect(body['model'], 'test-model');
      expect((body['messages'] as List).length, 2);
    });

    test('内容超过 maxInputChars 时应截断后发送', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response.bytes(
          utf8.encode(
            json.encode({
              'choices': [
                {
                  'message': {'content': '标题'},
                },
              ],
            }),
          ),
          200,
        );
      });
      final service = AiTitleService(client: client);

      await service.generateTitle('一二三四五六七八九十一二三四五', config);

      final body = json.decode(captured!.body) as Map<String, dynamic>;
      final messages = body['messages'] as List<dynamic>;
      final userMessage = messages[1] as Map<String, dynamic>;
      expect(userMessage['content'], '一二三四五六七八九十');
    });

    test('响应解析应去除引号并截断到 32 字', () async {
      final longTitle = '"${'标' * 40}。"';
      final service = AiTitleService(client: mockWithTitle(longTitle));

      final title = await service.generateTitle('内容', config);

      expect(title, '标' * 32);
    });

    test('base URL 端点应自动补全 /chat/completions 后缀', () async {
      Uri? capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        return http.Response.bytes(
          utf8.encode(
            json.encode({
              'choices': [
                {
                  'message': {'content': '标题'},
                },
              ],
            }),
          ),
          200,
        );
      });
      final service = AiTitleService(client: client);
      const baseConfig = AiConfig(
        apiEndpoint: 'https://api.example.com/v1',
        apiToken: 'test-token',
        model: 'test-model',
        maxInputChars: 10,
      );

      await service.generateTitle('内容', baseConfig);

      expect(
        capturedUri.toString(),
        'https://api.example.com/v1/chat/completions',
      );
    });

    test('完整端点不应重复补全后缀', () async {
      Uri? capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        return http.Response.bytes(
          utf8.encode(
            json.encode({
              'choices': [
                {
                  'message': {'content': '标题'},
                },
              ],
            }),
          ),
          200,
        );
      });
      final service = AiTitleService(client: client);

      await service.generateTitle('内容', config);

      expect(capturedUri.toString(), config.apiEndpoint);
    });

    test('非 200 响应应抛出 AiTitleException', () {
      final service = AiTitleService(
        client: mockWithTitle('', statusCode: 401),
      );

      expect(
        () => service.generateTitle('内容', config),
        throwsA(isA<AiTitleException>()),
      );
    });

    test('未配置时应抛出 AiTitleException', () {
      final service = AiTitleService(client: mockWithTitle('标题'));

      expect(
        () => service.generateTitle('内容', AiConfig.defaultConfig),
        throwsA(isA<AiTitleException>()),
      );
    });
  });
}
