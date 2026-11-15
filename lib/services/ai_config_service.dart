/// AI 配置持久化服务。
///
/// 负责将 AI 接口配置保存到本地 JSON 文件，
/// 存放于应用支持目录，启动时加载。
library services.ai_config_service;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/ai_config.dart';

/// AI 配置服务类。
class AiConfigService {
  /// 配置文件名。
  static const String configFileName = 'ai_config.json';

  /// 测试用的配置目录覆盖路径。
  ///
  /// 为 null 时使用 [getApplicationSupportDirectory]。
  /// 测试中可设置此字段以避免依赖平台插件。
  String? testConfigDir;

  /// 当前内存中的配置。
  AiConfig _config = AiConfig.defaultConfig;

  /// 获取当前配置。
  AiConfig get config => _config;

  /// 获取配置文件路径。
  Future<String> get _configPath async {
    if (testConfigDir != null) {
      return p.join(testConfigDir!, configFileName);
    }
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, configFileName);
  }

  /// 从磁盘加载配置。
  ///
  /// 文件不存在或解析失败时返回默认配置。
  Future<AiConfig> load() async {
    try {
      final path = await _configPath;
      final file = File(path);
      if (!file.existsSync()) {
        _config = AiConfig.defaultConfig;
        return _config;
      }
      final jsonStr = await file.readAsString();
      _config = AiConfig.fromJson(json.decode(jsonStr) as Map<String, dynamic>);
      return _config;
    } catch (e) {
      stderr.writeln('AI 配置加载失败: $e');
      _config = AiConfig.defaultConfig;
      return _config;
    }
  }

  /// 保存配置到磁盘并更新内存配置。
  Future<void> save(AiConfig config) async {
    try {
      final path = await _configPath;
      final file = File(path);
      final dir = file.parent;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final jsonStr = const JsonEncoder().convert(config.toJson());
      // 先写入临时文件再重命名，保证原子性
      final tempPath = '$path.tmp';
      final tempFile = File(tempPath);
      await tempFile.writeAsString(jsonStr);
      await tempFile.rename(path);
      _config = config;
    } catch (e) {
      stderr.writeln('AI 配置保存失败: $e');
      rethrow;
    }
  }
}
