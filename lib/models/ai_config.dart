/// AI 接口配置模型。
///
/// 保存 OpenAI 兼容接口的连接配置，
/// 支持序列化/反序列化用于本地持久化。
library models.ai_config;

/// AI 配置类。
class AiConfig {
  /// API 端点（OpenAI 兼容 chat/completions 地址）。
  final String apiEndpoint;

  /// API Token。
  final String apiToken;

  /// 模型名称。
  final String model;

  /// 发送给 AI 的最大输入字数（标题超出截断，文本操作超出拒绝）。
  final int maxInputChars;

  /// 翻译目标语言（自由文本，如 '英文'、'中文'、'日文'）。
  final String targetLanguage;

  /// 默认配置。
  static const AiConfig defaultConfig = AiConfig(
    apiEndpoint: 'https://api.openai.com/v1/chat/completions',
    apiToken: '',
    model: 'gpt-4o-mini',
    maxInputChars: 2000,
    targetLanguage: '英文',
  );

  /// 创建 [AiConfig] 实例。
  const AiConfig({
    required this.apiEndpoint,
    required this.apiToken,
    required this.model,
    required this.maxInputChars,
    this.targetLanguage = '英文',
  });

  /// 是否已完成必要配置（端点、Token、模型均非空）。
  bool get isConfigured =>
      apiEndpoint.trim().isNotEmpty &&
      apiToken.trim().isNotEmpty &&
      model.trim().isNotEmpty &&
      maxInputChars > 0;

  /// 从 JSON 创建 [AiConfig]。
  factory AiConfig.fromJson(Map<String, dynamic> json) {
    return AiConfig(
      apiEndpoint:
          json['apiEndpoint'] as String? ?? defaultConfig.apiEndpoint,
      apiToken: json['apiToken'] as String? ?? '',
      model: json['model'] as String? ?? defaultConfig.model,
      maxInputChars:
          json['maxInputChars'] as int? ?? defaultConfig.maxInputChars,
      targetLanguage:
          json['targetLanguage'] as String? ?? defaultConfig.targetLanguage,
    );
  }

  /// 序列化为 JSON。
  Map<String, dynamic> toJson() {
    return {
      'apiEndpoint': apiEndpoint,
      'apiToken': apiToken,
      'model': model,
      'maxInputChars': maxInputChars,
      'targetLanguage': targetLanguage,
    };
  }

  /// 创建副本。
  AiConfig copyWith({
    String? apiEndpoint,
    String? apiToken,
    String? model,
    int? maxInputChars,
    String? targetLanguage,
  }) {
    return AiConfig(
      apiEndpoint: apiEndpoint ?? this.apiEndpoint,
      apiToken: apiToken ?? this.apiToken,
      model: model ?? this.model,
      maxInputChars: maxInputChars ?? this.maxInputChars,
      targetLanguage: targetLanguage ?? this.targetLanguage,
    );
  }
}
