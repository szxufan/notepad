/// 右侧编辑区域组件。
///
/// 使用多行 [TextField] 显示和编辑纯文本内容，
/// 支持等宽字体和 Ctrl+滚轮调节字体大小。
library widgets.editor_panel;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/cursor_provider.dart';
import '../providers/editor_provider.dart';
import '../providers/file_list_provider.dart';
import 'highlighting_controller.dart';

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
      child: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: TextField(
          controller: _controller,
          // 仅在用户编辑时同步内容（程序化改文本不会触发 onChanged）
          onChanged: (_) {
            _onContentChanged();
          },
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
    );
  }
}
