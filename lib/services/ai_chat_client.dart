/// AI 聊天接口客户端。
///
/// 封装 OpenAI 兼容 chat/completions 接口的通用请求逻辑：
/// 端点补全、鉴权、UTF-8 编码、超时与响应解析。
/// 供 AiTitleService 与 AiTextService 共用。
library services.ai_chat_client;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ai_config.dart';

/// AI 聊天请求失败异常。
class AiChatException implements Exception {
  /// 错误信息。
  final String message;

  /// 创建 [AiChatException] 实例。
  const AiChatException(this.message);

  @override
  String toString() => 'AiChatException: $message';
}

/// AI 聊天客户端类。
class AiChatClient {
  /// 创建 [AiChatClient] 实例。
  ///
  /// [client] 可注入自定义 HTTP 客户端（用于测试）。
  AiChatClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 请求超时时间。
  static const Duration requestTimeout = Duration(seconds: 15);

  /// 调用 chat/completions 接口，返回模型输出文本（已 trim）。
  ///
  /// 空字符串原样返回，由调用方自行校验。
  /// 失败时抛出 [AiChatException]。
  Future<String> chatCompletion({
    required AiConfig config,
    required String systemPrompt,
    required String userContent,
    double temperature = 0.3,
    int? maxTokens,
  }) async {
    final body = json.encode({
      'model': config.model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userContent},
      ],
      'temperature': temperature,
      if (maxTokens != null) 'max_tokens': maxTokens,
    });

    http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(resolveEndpoint(config.apiEndpoint)),
            headers: {
              'Authorization': 'Bearer ${config.apiToken}',
              'Content-Type': 'application/json; charset=utf-8',
            },
            // 使用 UTF-8 字节发送，避免中文内容按 latin-1 编码失败
            body: utf8.encode(body),
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const AiChatException('AI 请求超时');
    } catch (e) {
      throw AiChatException('AI 请求失败: $e');
    }

    if (response.statusCode != 200) {
      throw AiChatException('AI 接口返回错误 (${response.statusCode})');
    }

    try {
      final data =
          json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>;
      final message = choices.first['message'] as Map<String, dynamic>;
      return (message['content'] as String).trim();
    } catch (e) {
      throw AiChatException('AI 响应解析失败: $e');
    }
  }

  /// 解析 API 端点：若为 base URL（如 `https://host/v1`），
  /// 自动补全 `/chat/completions` 后缀。
  static String resolveEndpoint(String endpoint) {
    var url = endpoint.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (!url.endsWith('/chat/completions')) {
      url = '$url/chat/completions';
    }
    return url;
  }

  /// 释放 HTTP 客户端。
  void dispose() {
    _client.close();
  }
}