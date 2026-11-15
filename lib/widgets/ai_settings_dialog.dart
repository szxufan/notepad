/// AI 设置对话框。
///
/// 配置 OpenAI 兼容接口的端点、Token、模型、最大输入字数，
/// 保存后持久化到本地配置文件。
library widgets.ai_settings_dialog;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/ai_config.dart';
import '../services/ai_config_service.dart';

/// AI 设置对话框。
class AiSettingsDialog extends StatefulWidget {
  const AiSettingsDialog({super.key});

  /// 显示 AI 设置对话框。
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const AiSettingsDialog(),
    );
  }

  @override
  State<AiSettingsDialog> createState() => _AiSettingsDialogState();
}

class _AiSettingsDialogState extends State<AiSettingsDialog> {
  final _endpointController = TextEditingController();
  final _tokenController = TextEditingController();
  final _modelController = TextEditingController();
  final _maxCharsController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _tokenController.dispose();
    _modelController.dispose();
    _maxCharsController.dispose();
    super.dispose();
  }

  /// 加载当前配置。
  Future<void> _loadConfig() async {
    final service = context.read<AiConfigService>();
    final config = await service.load();
    if (!mounted) return;
    _endpointController.text = config.apiEndpoint;
    _tokenController.text = config.apiToken;
    _modelController.text = config.model;
    _maxCharsController.text = config.maxInputChars.toString();
    setState(() => _loading = false);
  }

  /// 保存配置。
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final config = AiConfig(
      apiEndpoint: _endpointController.text.trim(),
      apiToken: _tokenController.text.trim(),
      model: _modelController.text.trim(),
      maxInputChars: int.parse(_maxCharsController.text.trim()),
    );
    try {
      await context.read<AiConfigService>().save(config);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI 配置已保存')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('AI 设置'),
      content: SizedBox(
        width: 420,
        child: _loading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _endpointController,
                      decoration: const InputDecoration(
                        labelText: 'API 端点',
                        hintText: 'https://api.openai.com/v1',
                        helperText: '支持 base URL，自动补全 /chat/completions',
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? '请输入 API 端点'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _tokenController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'API Token',
                        hintText: 'sk-...',
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? '请输入 API Token'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _modelController,
                      decoration: const InputDecoration(
                        labelText: '模型',
                        hintText: 'gpt-4o-mini',
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? '请输入模型名称'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _maxCharsController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: '最大输入字数',
                        hintText: '2000',
                      ),
                      validator: (v) {
                        final value = int.tryParse(v?.trim() ?? '');
                        if (value == null || value <= 0) {
                          return '请输入大于 0 的数字';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _loading || _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}
