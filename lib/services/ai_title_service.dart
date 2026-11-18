/// AI 标题生成服务。
///
/// 调用 OpenAI 兼容的 chat/completions 接口，
/// 根据文本内容生成简洁标题。
library services.ai_title_service;

import 'package:http/http.dart' as http;

import '../models/ai_config.dart';
import 'ai_chat_client.dart';

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
  AiTitleService({http.Client? client})
      : _chatClient = AiChatClient(client: client);

  final AiChatClient _chatClient;

  /// 请求超时时间。
  static const Duration requestTimeout = AiChatClient.requestTimeout;

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

    String raw;
    try {
      raw = await _chatClient.chatCompletion(
        config: config,
        systemPrompt: '你是一个标题生成助手。为用户提供的文本生成一个简洁的标题，'
            '不超过16字，只输出标题本身，不要输出引号、标点结尾或任何解释。',
        userContent: truncated,
        temperature: 0.3,
        maxTokens: 50,
      );
    } on AiChatException catch (e) {
      throw AiTitleException(e.message);
    }

    final title = _sanitizeTitle(raw);
    if (title.isEmpty) {
      throw const AiTitleException('AI 返回了空标题');
    }
    return title;
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
    _chatClient.dispose();
  }
}
