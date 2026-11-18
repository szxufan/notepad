/// 右侧编辑区域组件。
///
/// 使用多行 [TextField] 显示和编辑纯文本内容，
/// 支持等宽字体、Ctrl+滚轮调节字体大小，
/// 右键菜单提供 AI 摘要/润色/翻译选中文本。
library widgets.editor_panel;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/cursor_provider.dart';
import '../providers/editor_provider.dart';
import '../providers/file_list_provider.dart';
import '../services/ai_config_service.dart';
import '../services/ai_text_service.dart';
import 'ai_settings_dialog.dart';
import 'ai_text_result_dialog.dart';
import 'highlighting_controller.dart';

/// AI 文本操作类型。
enum _AiAction { summarize, polish, translate }

/// 右侧编辑区域。
class EditorPanel extends StatefulWidget {
  const EditorPanel({super.key});

  @override
  State<EditorPanel> createState() => _EditorPanelState();
}

class _EditorPanelState extends State<EditorPanel> {
  /// 高亮文本控制器。
  late HighlightingController _controller;

  /// 内容变更防抖定时器。
  Timer? _debounceTimer;

  /// 等宽字体栈。
  static const String _monospaceFontFamily = 'SarasaMonoSC';

  @override
  void initState() {
    super.initState();
    _controller = HighlightingController();
    // 监听选区/文本变化，把选中文本同步给 EditorProvider 供查找栏预填
    _controller.addListener(_syncSelectedText);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.removeListener(_syncSelectedText);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 延迟到帧后同步，避免在 build 阶段设置控制器文本触发 notifyListeners
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncControllerWithActiveFile();
      }
    });
  }

  /// 同步控制器内容与当前活动文件。
  void _syncControllerWithActiveFile() {
    final fileList = context.read<FileListProvider>();
    final editor = context.read<EditorProvider>();
    final activeFile = fileList.activeFile;

    // 仅当活动文件真正变化时才更新 EditorProvider，
    // 避免每次重建都重置当前匹配索引
    final activeFileChanged = editor.currentFileId != activeFile?.id;
    if (activeFileChanged) {
      editor.setActiveFile(activeFile);
    }

    final content = activeFile?.content ?? '';
    if (activeFileChanged) {
      // 即使两个文件内容相同，也要清除上一文件的光标与选区。
      _controller.value = TextEditingValue(
        text: content,
        selection: const TextSelection.collapsed(offset: 0),
      );
    } else if (_controller.text != content) {
      _controller.text = content;
    }

    // 延迟到帧后更新高亮，避免在 build 阶段触发 notifyListeners
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateHighlights();
      }
    });
  }

  /// 将编辑器选中文本同步到 EditorProvider，光标位置同步到 CursorProvider。
  ///
  /// 跨行选区整段同步（含换行符），无有效选区时同步空字符串。
  void _syncSelectedText() {
    if (!mounted) return;
    final selection = _controller.selection;
    final text = selection.isValid && !selection.isCollapsed
        ? selection.textInside(_controller.text)
        : '';
    context.read<EditorProvider>().setSelectedText(text);
    context.read<CursorProvider>().update(selection, _controller.text);
  }

  /// 更新高亮显示。
  void _updateHighlights() {
    final editor = context.read<EditorProvider>();
    _controller.updateHighlights(
      newMatches: editor.findMatches,
      newCurrentMatch: editor.currentMatch,
      newFindText: editor.findText,
    );
  }

  /// 内容变更回调（防抖）。
  void _onContentChanged() {
    final fileList = context.read<FileListProvider>();
    final editor = context.read<EditorProvider>();
    final activeFile = fileList.activeFile;
    if (activeFile == null) return;

    final content = _controller.text;
    // 更新文件列表中的内容
    fileList.updateContent(activeFile.id, content);
    // 更新 EditorProvider 的内容
    editor.updateContent(content);

    // 防抖更新高亮
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _updateHighlights();
    });
  }

  /// 启动 AI 文本操作：捕获选区快照，弹出结果对话框。
  void _startAiAction(EditableTextState editableTextState, _AiAction action) {
    editableTextState.hideToolbar();
    final selection = editableTextState.textEditingValue.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    final content = _controller.text;
    final text = selection.textInside(content);
    final range = TextRange(start: selection.start, end: selection.end);
    final fileId = context.read<FileListProvider>().activeFile?.id;

    final config = context.read<AiConfigService>().config;
    if (!config.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 接口未配置，请先在设置中完成配置')),
      );
      AiSettingsDialog.show(context);
      return;
    }

    final service = context.read<AiTextService>();
    final (label, allowKeepOriginal) = switch (action) {
      _AiAction.summarize => ('摘要', false),
      _AiAction.polish => ('润色', false),
      _AiAction.translate => ('翻译', true),
    };
    AiTextResultDialog.show(
      context,
      actionLabel: label,
      allowKeepOriginal: allowKeepOriginal,
      task: () => switch (action) {
        _AiAction.summarize => service.summarize(text, config),
        _AiAction.polish => service.polish(text, config),
        _AiAction.translate => service.translate(text, config),
      },
      onApply: (result, keepOriginal) =>
          _applyAiResult(fileId, range, content, result, keepOriginal),
    );
  }

  /// 将 AI 结果应用到文件（替换选区或保留原文插入）。
  void _applyAiResult(
    String? fileId,
    TextRange range,
    String contentAtInvocation,
    String result,
    bool keepOriginal,
  ) {
    if (!mounted) return;
    final fileList = context.read<FileListProvider>();
    final editor = context.read<EditorProvider>();
    final activeFile = fileList.activeFile;
    if (activeFile == null || activeFile.id != fileId) return;
    if (activeFile.isReadOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('只读文件不能修改')),
      );
      return;
    }
    // 陈旧守卫：弹窗期间内容若变化（如外部修改自动重载），偏移不再可靠
    if (activeFile.content != contentAtInvocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件内容已变化，无法应用结果')),
      );
      return;
    }
    final content = activeFile.content;
    String newContent;
    if (keepOriginal) {
      // 在选区之后插入译文，沿用文件换行符并避免与相邻文字粘连
      final lineEnding =
          RegExp(r'\r\n|\r|\n').firstMatch(content)?.group(0) ?? '\n';
      final needsLeading = range.end > 0 &&
          content[range.end - 1] != '\n' &&
          content[range.end - 1] != '\r';
      final needsTrailing = range.end < content.length &&
          content[range.end] != '\n' &&
          content[range.end] != '\r';
      final insertion = '${needsLeading ? lineEnding : ''}'
          '$result${needsTrailing ? lineEnding : ''}';
      newContent = content.replaceRange(range.end, range.end, insertion);
    } else {
      newContent = content.replaceRange(range.start, range.end, result);
    }
    fileList.updateContent(activeFile.id, newContent);
    editor.updateContent(newContent);
  }

  /// 构建编辑器右键菜单：默认项 + 有选区时追加 AI 操作。
  Widget _buildContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final buttonItems =
        List<ContextMenuButtonItem>.of(editableTextState.contextMenuButtonItems);
    final selection = editableTextState.textEditingValue.selection;
    if (selection.isValid && !selection.isCollapsed) {
      buttonItems.addAll([
        ContextMenuButtonItem(
          label: 'AI 摘要',
          onPressed: () =>
              _startAiAction(editableTextState, _AiAction.summarize),
        ),
        ContextMenuButtonItem(
          label: 'AI 润色',
          onPressed: () => _startAiAction(editableTextState, _AiAction.polish),
        ),
        ContextMenuButtonItem(
          label: 'AI 翻译',
          onPressed: () =>
              _startAiAction(editableTextState, _AiAction.translate),
        ),
      ]);
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }

  /// 处理 Ctrl/Cmd + 滚轮调节字体大小。
  bool _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final isCtrlDown = HardwareKeyboard.instance.logicalKeysPressed
              .contains(LogicalKeyboardKey.controlLeft) ||
          HardwareKeyboard.instance.logicalKeysPressed
              .contains(LogicalKeyboardKey.controlRight);
      final isCmdDown = HardwareKeyboard.instance.logicalKeysPressed
              .contains(LogicalKeyboardKey.metaLeft) ||
          HardwareKeyboard.instance.logicalKeysPressed
              .contains(LogicalKeyboardKey.metaRight);
      if (isCtrlDown || isCmdDown) {
        final editor = context.read<EditorProvider>();
        // 滚轮向上放大，向下缩小
        final delta = -event.scrollDelta.dy / 50;
        editor.adjustFontSize(delta);
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final fileList = context.watch<FileListProvider>();
    final editor = context.watch<EditorProvider>();
    final activeFile = fileList.activeFile;

    if (activeFile == null) {
      return const Center(
        child: Text(
          '没有打开的文件\n按 Ctrl+N 新建，Ctrl+O 打开',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return Listener(
      onPointerSignal: (event) {
        _handlePointerSignal(event);
      },
      child: Column(
        children: [
          // 只读大文件横幅
          if (activeFile.isReadOnly)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '大文件 · 只读模式，仅显示开头部分，不可编辑或保存',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          Expanded(
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: TextField(
                controller: _controller,
                readOnly: activeFile.isReadOnly,
                // 仅在用户编辑时同步内容（程序化改文本不会触发 onChanged）
                onChanged: (_) {
                  _onContentChanged();
                },
                contextMenuBuilder: _buildContextMenu,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                style: TextStyle(
                  fontFamily: _monospaceFontFamily,
                  fontSize: editor.fontSize,
                  height: 1.5,
                ),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.all(16),
                  border: InputBorder.none,
                  isDense: false,
                ),
                cursorColor: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
