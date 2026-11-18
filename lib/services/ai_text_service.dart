/// AI 文本操作服务。
///
/// 对选中文本执行摘要、润色、翻译，
/// 调用 OpenAI 兼容的 chat/completions 接口。
library services.ai_text_service;

import 'package:http/http.dart' as http;

import '../models/ai_config.dart';
import 'ai_chat_client.dart';

/// AI 文本操作失败异常。
class AiTextException implements Exception {
  /// 错误信息。
  final String message;

  /// 创建 [AiTextException] 实例。
  const AiTextException(this.message);

  @override
  String toString() => 'AiTextException: $message';
}

/// AI 文本服务类。
class AiTextService {
  /// 创建 [AiTextService] 实例。
  ///
  /// [client] 可注入自定义 HTTP 客户端（用于测试）。
  AiTextService({http.Client? client})
      : _chatClient = AiChatClient(client: client);

  final AiChatClient _chatClient;

  /// 摘要输出 token 上限。
  static const int summarizeMaxTokens = 1024;

  /// 润色/翻译输出 token 上限（输出长度与输入相当）。
  static const int rewriteMaxTokens = 4096;

  /// 生成 [text] 的摘要。
  ///
  /// 失败时抛出 [AiTextException]。
  Future<String> summarize(String text, AiConfig config) {
    return _run(
      text,
      config,
      systemPrompt: '你是一个文本摘要助手。为用户提供的文本生成简洁的摘要，'
          '保留关键信息，只输出摘要本身，不要输出任何解释或前缀。',
      temperature: 0.3,
      maxTokens: summarizeMaxTokens,
    );
  }

  /// 润色 [text]（保持原意与原有语言）。
  ///
  /// 失败时抛出 [AiTextException]。
  Future<String> polish(String text, AiConfig config) {
    return _run(
      text,
      config,
      systemPrompt: '你是一个文本润色助手。改进用户提供文本的表达，'
          '使其更流畅自然，保持原意和原有语言，不增删事实内容。'
          '只输出润色后的文本，不要输出任何解释。',
      temperature: 0.5,
      maxTokens: rewriteMaxTokens,
    );
  }

  /// 将 [text] 翻译为 [AiConfig.targetLanguage]。
  ///
  /// 失败时抛出 [AiTextException]。
  Future<String> translate(String text, AiConfig config) {
    return _run(
      text,
      config,
      systemPrompt: '你是一个翻译助手。将用户提供的文本翻译为'
          '${config.targetLanguage}。保持原文格式与换行，'
          '只输出译文，不要输出任何解释。',
      temperature: 0.3,
      maxTokens: rewriteMaxTokens,
    );
  }

  /// 共用流程：配置校验 → 长度校验 → 请求 → 空结果校验。
  ///
  /// 与标题服务不同，超长文本**拒绝而非截断**，
  /// 避免润色/翻译静默丢失内容。
  Future<String> _run(
    String text,
    AiConfig config, {
    required String systemPrompt,
    required double temperature,
    required int maxTokens,
  }) async {
    if (!config.isConfigured) {
      throw const AiTextException('AI 接口未配置，请先在设置中完成配置');
    }
    if (text.length > config.maxInputChars) {
      throw AiTextException(
        '选中文本超过 ${config.maxInputChars} 字符上限，请在 AI 设置中调大',
      );
    }

    String result;
    try {
      result = await _chatClient.chatCompletion(
        config: config,
        systemPrompt: systemPrompt,
        userContent: text,
        temperature: temperature,
        maxTokens: maxTokens,
      );
    } on AiChatException catch (e) {
      throw AiTextException(e.message);
    }

    if (result.isEmpty) {
      throw const AiTextException('AI 返回了空内容');
    }
    return result;
  }

  /// 释放 HTTP 客户端。
  void dispose() {
    _chatClient.dispose();
  }
}