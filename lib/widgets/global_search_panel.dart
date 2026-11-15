/// 全局搜索面板组件。
///
/// 以 Dialog 形式显示，搜索所有打开的文档，
/// 点击结果跳转到对应文件的对应位置。
library widgets.global_search_panel;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/editor_provider.dart';
import '../providers/file_list_provider.dart';

/// 全局搜索面板。
class GlobalSearchPanel extends StatefulWidget {
  const GlobalSearchPanel({super.key});

  @override
  State<GlobalSearchPanel> createState() => _GlobalSearchPanelState();
}

class _GlobalSearchPanelState extends State<GlobalSearchPanel> {
  late TextEditingController _searchController;
  late FocusNode _searchFocusNode;

  @override
  void initState() {
    super.initState();
    final editor = context.read<EditorProvider>();
    _searchController = TextEditingController(text: editor.globalSearchText);
    _searchFocusNode = FocusNode();
    // 自动聚焦搜索框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// 执行搜索。
  void _doSearch(String query) {
    final fileList = context.read<FileListProvider>();
    final editor = context.read<EditorProvider>();
    editor.performGlobalSearch(fileList.files, query);
  }

  /// 跳转到搜索结果。
  void _jumpToResult(GlobalSearchResult result) {
    final fileList = context.read<FileListProvider>();
    final editor = context.read<EditorProvider>();

    // 1. 关闭全局搜索面板
    editor.hideGlobalSearchPanel();
    Navigator.of(context).pop();

    // 2. 切换到目标文件
    fileList.switchToFile(result.fileId);

    // 3. 打开查找栏并设置搜索文本（触发高亮）
    editor.showFind();

    // 延迟设置 findText 和 matchIndex，等待 EditorPanel 同步活动文件
    WidgetsBinding.instance.addPostFrameCallback((_) {
      editor.setFindText(editor.globalSearchText);
      // 4. 跳转到首个匹配
      WidgetsBinding.instance.addPostFrameCallback((_) {
        editor.setCurrentMatchIndex(0);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorProvider>();
    final results = editor.globalSearchResults;
    final isError = editor.useRegex && editor.globalSearchError != null;

    return Dialog(
      child: SizedBox(
        width: 600,
        height: 500,
        child: Column(
          children: [
            // 搜索栏
            Container(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.search,
                      size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      decoration: const InputDecoration(
                        hintText: '在所有打开的文件中搜索',
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                      ),
                      onChanged: _doSearch,
                      onSubmitted: _doSearch,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 正则开关（复用 EditorProvider 的 _useRegex）
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
                    onPressed: () {
                      editor.setUseRegex(!editor.useRegex);
                      _doSearch(_searchController.text);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: '关闭',
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      editor.hideGlobalSearchPanel();
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ),
            // 结果统计
            if (editor.globalSearchText.isNotEmpty && !isError)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                width: double.infinity,
                child: Text(
                  '${results.length} 个文件，共 ${results.fold<int>(0, (sum, r) => sum + r.matchCount)} 处匹配',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (isError)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                width: double.infinity,
                child: Text(
                  '正则错误: ${editor.globalSearchError}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const Divider(height: 1),
            // 结果列表
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Text(
                        editor.globalSearchText.isEmpty
                            ? '输入搜索内容'
                            : '无匹配结果',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final result = results[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.description, size: 18),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  result.fileTitle,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${result.matchCount}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            result.preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color:
                                  Theme.of(context).textTheme.bodySmall?.color,
                            ),
                          ),
                          onTap: () => _jumpToResult(result),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
