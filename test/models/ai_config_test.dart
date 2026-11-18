import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/models/ai_config.dart';

void main() {
  group('AiConfig', () {
    test('默认目标语言应为英文', () {
      expect(AiConfig.defaultConfig.targetLanguage, '英文');
      const config = AiConfig(
        apiEndpoint: 'https://example.com/v1',
        apiToken: 'token',
        model: 'model',
        maxInputChars: 100,
      );
      expect(config.targetLanguage, '英文');
    });

    test('fromJson/toJson 应可往返转换 targetLanguage', () {
      const original = AiConfig(
        apiEndpoint: 'https://example.com/v1',
        apiToken: 'token',
        model: 'model',
        maxInputChars: 100,
        targetLanguage: '日文',
      );

      final restored = AiConfig.fromJson(original.toJson());

      expect(restored.targetLanguage, '日文');
      expect(restored.apiEndpoint, original.apiEndpoint);
      expect(restored.maxInputChars, original.maxInputChars);
    });

    test('旧配置缺少 targetLanguage 应回退默认值', () {
      final json = {
        'apiEndpoint': 'https://example.com/v1',
        'apiToken': 'token',
        'model': 'model',
        'maxInputChars': 100,
      };

      final config = AiConfig.fromJson(json);

      expect(config.targetLanguage, '英文');
    });

    test('copyWith 应覆盖 targetLanguage', () {
      const config = AiConfig(
        apiEndpoint: 'https://example.com/v1',
        apiToken: 'token',
        model: 'model',
        maxInputChars: 100,
      );

      final copied = config.copyWith(targetLanguage: '法文');

      expect(copied.targetLanguage, '法文');
      expect(config.targetLanguage, '英文');
    });
  });
}