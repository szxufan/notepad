/// AI 标题生成服务。
///
/// 调用 OpenAI 兼容的 chat/completions 接口，
/// 根据文本内容生成简洁标题。
library services.ai_title_service;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ai_config.dart';

/// AI 标题生成失败异常。
class AiTitleException implements Exception {
  /// 错误信息。
  final String message;

  /// 创建 [AiTitleException] 实例。
  const AiTitleException(this.message);

  @override
  String toString() => 'AiTitleException: $message';
}

/// AI 标题服务类。
class AiTitleService {
  /// 创建 [AiTitleService] 实例。
  ///
  /// [client] 可注入自定义 HTTP 客户端（用于测试）。
  AiTitleService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 请求超时时间。
  static const Duration requestTimeout = Duration(seconds: 15);

  /// 生成标题的最大长度（防止 AI 输出过长）。
  static const int maxTitleLength = 32;

  /// 根据 [content] 调用 AI 生成标题。
  ///
  /// 内容超过 [AiConfig.maxInputChars] 时先截断再发送。
  /// 失败时抛出 [AiTitleException]。
  Future<String> generateTitle(String content, AiConfig config) async {
    if (!config.isConfigured) {
      throw const AiTitleException('AI 接口未配置，请先在设置中完成配置');
    }
    final truncated = content.length > config.maxInputChars
        ? content.substring(0, config.maxInputChars)
        : content;

    final body = json.encode({
      'model': config.model,
      'messages': [
        {
          'role': 'system',
          'content': '你是一个标题生成助手。为用户提供的文本生成一个简洁的标题，'
              '不超过16字，只输出标题本身，不要输出引号、标点结尾或任何解释。',
        },
        {'role': 'user', 'content': truncated},
      ],
      'temperature': 0.3,
      'max_tokens': 50,
    });

    http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(_resolveEndpoint(config.apiEndpoint)),
            headers: {
              'Authorization': 'Bearer ${config.apiToken}',
              'Content-Type': 'application/json; charset=utf-8',
            },
            // 使用 UTF-8 字节发送，避免中文内容按 latin-1 编码失败
            body: utf8.encode(body),
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const AiTitleException('AI 请求超时');
    } catch (e) {
      throw AiTitleException('AI 请求失败: $e');
    }

    if (response.statusCode != 200) {
      throw AiTitleException('AI 接口返回错误 (${response.statusCode})');
    }

    try {
      final data =
          json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>;
      final message = choices.first['message'] as Map<String, dynamic>;
      final raw = (message['content'] as String).trim();
      final title = _sanitizeTitle(raw);
      if (title.isEmpty) {
        throw const AiTitleException('AI 返回了空标题');
      }
      return title;
    } on AiTitleException {
      rethrow;
    } catch (e) {
      throw AiTitleException('AI 响应解析失败: $e');
    }
  }

  /// 解析 API 端点：若为 base URL（如 `https://host/v1`），
  /// 自动补全 `/chat/completions` 后缀。
  String _resolveEndpoint(String endpoint) {
    var url = endpoint.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (!url.endsWith('/chat/completions')) {
      url = '$url/chat/completions';
    }
    return url;
  }

  /// 清理 AI 输出：取首行、去除引号和结尾标点、截断长度。
  String _sanitizeTitle(String raw) {
    var title = raw.split('\n').first.trim();
    // 去除首尾引号
    title = title.replaceAll(RegExp('^["\'“”‘’]+|["\'“”‘’]+\$'), '').trim();
    // 去除结尾标点
    title = title.replaceAll(RegExp('[。\\.!！?？:：;；]+\$'), '').trim();
    if (title.length > maxTitleLength) {
      title = title.substring(0, maxTitleLength);
    }
    return title;
  }

  /// 释放 HTTP 客户端。
  void dispose() {
    _client.close();
  }
}
