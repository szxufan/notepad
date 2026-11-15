/// 查找替换栏组件。
///
/// 提供查找、替换、上一个/下一个、替换/全部替换功能。
library widgets.find_replace_bar;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/editor_provider.dart';
import '../providers/file_list_provider.dart';

/// 查找替换栏。
class FindReplaceBar extends StatefulWidget {
  const FindReplaceBar({super.key});

  @override
  State<FindReplaceBar> createState() => _FindReplaceBarState();
}

class _FindReplaceBarState extends State<FindReplaceBar> {
  late TextEditingController _findController;
  late TextEditingController _replaceController;
  late FocusNode _findFocusNode;

  @override
  void initState() {
    super.initState();
    final editor = context.read<EditorProvider>();
    _findController = TextEditingController(text: editor.findText);
    _replaceController = TextEditingController(text: editor.replaceText);
    _findFocusNode = FocusNode();
    // 自动聚焦查找框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _findFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _findController.dispose();
    _replaceController.dispose();
    _findFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorProvider>();
    // 同步控制器文本
    if (_findController.text != editor.findText) {
      _findController.text = editor.findText;
    }
    if (_replaceController.text != editor.replaceText) {
      _replaceController.text = editor.replaceText;
    }

    final matchCount = editor.matchCount;
    final currentIndex = editor.currentMatchIndex;
    final isRegexError = editor.useRegex && editor.findError != null;
    final matchText = isRegexError
        ? '正则错误'
        : (matchCount > 0
            ? '${currentIndex + 1}/$matchCount'
            : (editor.findText.isNotEmpty ? '无匹配' : ''));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 查找行
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _findController,
                    focusNode: _findFocusNode,
                    decoration: const InputDecoration(
                      hintText: '查找',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      editor.setFindText(value);
                    },
                    onSubmitted: (_) {
                      editor.findNext();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 正则开关
              IconButton(
                icon: const Text(
                  '.*',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                tooltip: '使用正则表达式',
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                padding: EdgeInsets.zero,
                style: editor.useRegex
                    ? IconButton.styleFrom(
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                      )
                    : null,
                onPressed: () => editor.setUseRegex(!editor.useRegex),
              ),
              const SizedBox(width: 4),
              Text(
                matchText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isRegexError
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                tooltip: '上一个匹配',
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                padding: EdgeInsets.zero,
                onPressed: matchCount > 0
                    ? () => editor.findPrevious()
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                tooltip: '下一个匹配',
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                padding: EdgeInsets.zero,
                onPressed: matchCount > 0
                    ? () => editor.findNext()
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: '关闭',
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                padding: EdgeInsets.zero,
                onPressed: () => editor.hideFindReplace(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 替换行
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _replaceController,
                    decoration: const InputDecoration(
                      hintText: '替换',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      editor.setReplaceText(value);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: matchCount > 0
                    ? () {
                        final newContent = editor.replace();
                        _onReplaced(newContent);
                      }
                    : null,
                child: const Text('替换'),
              ),
              TextButton(
                onPressed: editor.findText.isNotEmpty
                    ? () {
                        final newContent = editor.replaceAll();
                        _onReplaced(newContent);
                      }
                    : null,
                child: const Text('全部替换'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 替换后同步文件内容，编辑器面板会响应更新显示。
  void _onReplaced(String newContent) {
    final fileList = context.read<FileListProvider>();
    final activeFile = fileList.activeFile;
    if (activeFile == null) return;
    fileList.updateContent(activeFile.id, newContent);
  }
}
