/// AI 文本操作结果对话框。
///
/// 展示 AI 操作（摘要/润色/翻译）的加载、结果预览与错误状态，
/// 支持替换选区、保留原文插入（翻译）、复制与失败重试。
library widgets.ai_text_result_dialog;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ai_text_service.dart';

/// AI 文本结果对话框。
class AiTextResultDialog extends StatefulWidget {
  const AiTextResultDialog({
    super.key,
    required this.actionLabel,
    required this.task,
    required this.onApply,
    this.allowKeepOriginal = false,
  });

  /// 操作名（用于标题，如 '摘要'）。
  final String actionLabel;

  /// AI 请求任务（重试时重新执行）。
  final Future<String> Function() task;

  /// 应用结果回调：[keepOriginal] 为 true 表示保留原文并插入结果。
  final void Function(String result, bool keepOriginal) onApply;

  /// 是否允许保留原文插入（仅翻译）。
  final bool allowKeepOriginal;

  /// 显示 AI 文本结果对话框。
  static Future<void> show(
    BuildContext context, {
    required String actionLabel,
    required Future<String> Function() task,
    required void Function(String result, bool keepOriginal) onApply,
    bool allowKeepOriginal = false,
  }) {
    return showDialog(
      context: context,
      builder: (_) => AiTextResultDialog(
        actionLabel: actionLabel,
        task: task,
        onApply: onApply,
        allowKeepOriginal: allowKeepOriginal,
      ),
    );
  }

  @override
  State<AiTextResultDialog> createState() => _AiTextResultDialogState();
}

class _AiTextResultDialogState extends State<AiTextResultDialog> {
  bool _loading = true;
  String? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runTask();
  }

  /// 执行 AI 请求。
  Future<void> _runTask() async {
    setState(() {
      _loading = true;
      _result = null;
      _error = null;
    });
    try {
      final result = await widget.task();
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AiTextException ? e.message : '$e';
        _loading = false;
      });
    }
  }

  /// 复制结果到剪贴板。
  Future<void> _copy() async {
    final result = _result;
    if (result == null) return;
    await Clipboard.setData(ClipboardData(text: result));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制')),
    );
  }

  /// 应用结果并关闭对话框。
  void _apply(bool keepOriginal) {
    final result = _result;
    if (result == null) return;
    Navigator.of(context).pop();
    widget.onApply(result, keepOriginal);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('AI ${widget.actionLabel}'),
      content: SizedBox(
        width: 480,
        child: _loading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? SizedBox(
                    height: 120,
                    child: Center(
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  )
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: SingleChildScrollView(
                      child: SelectableText(_result ?? ''),
                    ),
                  ),
      ),
      actions: _buildActions(),
    );
  }

  /// 按状态构建按钮组。
  List<Widget> _buildActions() {
    if (_loading) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ];
    }
    if (_error != null) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: _runTask,
          child: const Text('重试'),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('关闭'),
      ),
      TextButton(
        onPressed: _copy,
        child: const Text('复制'),
      ),
      if (widget.allowKeepOriginal)
        TextButton(
          onPressed: () => _apply(true),
          child: const Text('保留原文插入'),
        ),
      FilledButton(
        onPressed: () => _apply(false),
        child: Text(widget.allowKeepOriginal ? '替换原文' : '替换选区'),
      ),
    ];
  }
}