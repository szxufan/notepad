/// 主页面布局。
///
/// 左侧文件列表 + 右侧编辑区 + 底部状态栏，
/// 集成快捷键绑定。
library pages.home_page;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/editor_provider.dart';
import '../providers/file_list_provider.dart';
import '../services/draft_service.dart';
import '../widgets/editor_panel.dart';
import '../widgets/file_list_panel.dart';
import '../widgets/find_replace_bar.dart';
import '../widgets/global_search_panel.dart';
import '../widgets/status_bar.dart';

/// 主页面。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// 草稿服务引用（dispose 阶段无法安全地通过 context 获取）。
  late DraftService _draftService;

  /// 是否正在拖拽文件悬停于窗口上。
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _draftService = context.read<DraftService>();
    // 启动自动保存草稿
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fileList = context.read<FileListProvider>();
      _draftService.startAutoSave(() async => fileList.allFiles);
    });
  }

  @override
  void dispose() {
    // 停止自动保存
    _draftService.stopAutoSave();
    super.dispose();
  }

  /// 新建文件
  void _newFile() {
    context.read<FileListProvider>().addNewFile();
  }

  /// 打开文件
  Future<void> _openFile() async {
    final path = await context.read<FileListProvider>().fileService.pickFile();
    if (path != null && mounted) {
      context.read<FileListProvider>().openFile(path);
    }
  }

  /// 保存文件
  Future<void> _saveFile() async {
    final fileList = context.read<FileListProvider>();
    final active = fileList.activeFile;
    if (active == null) return;
    if (active.filePath != null) {
      await fileList.saveFile(active.id);
    } else {
      await fileList.saveFileAs(active.id);
    }
  }

  /// 另存为
  Future<void> _saveFileAs() async {
    final fileList = context.read<FileListProvider>();
    final active = fileList.activeFile;
    if (active == null) return;
    await fileList.saveFileAs(active.id);
  }

  /// 关闭当前文件
  void _closeFile() {
    final fileList = context.read<FileListProvider>();
    final active = fileList.activeFile;
    if (active == null) return;
    if (active.isDirty) {
      showDialog(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('关闭 ${active.title}'),
            content: const Text('文件有未保存的修改，是否保存？'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  fileList.closeFile(active.id);
                },
                child: const Text('不保存'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  if (active.filePath != null) {
                    await fileList.saveFile(active.id);
                  } else {
                    await fileList.saveFileAs(active.id);
                  }
                  if (mounted) {
                    fileList.closeFile(active.id);
                  }
                },
                child: const Text('保存'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
            ],
          );
        },
      );
    } else {
      fileList.closeFile(active.id);
    }
  }

  /// 显示查找
  void _showFind() {
    context.read<EditorProvider>().showFind();
  }

  /// 切换查找栏显示状态（再次按下关闭）。
  void _toggleFind() {
    context.read<EditorProvider>().toggleFindReplace();
  }

  /// 跳转到下一个匹配。
  void _findNext() {
    context.read<EditorProvider>().findNext();
  }

  /// 跳转到上一个匹配。
  void _findPrevious() {
    context.read<EditorProvider>().findPrevious();
  }

  /// 关闭查找栏/全局搜索。
  void _hideFind() {
    final editor = context.read<EditorProvider>();
    if (editor.showGlobalSearch) {
      editor.hideGlobalSearchPanel();
      Navigator.of(context).pop();
    } else {
      editor.hideFindReplace();
    }
  }

  /// 显示全局搜索面板。
  void _showGlobalSearch() {
    final editor = context.read<EditorProvider>();
    editor.showGlobalSearchPanel();
    showDialog(
      context: context,
      builder: (_) => const GlobalSearchPanel(),
    ).then((_) {
      // Dialog 关闭后确保状态同步
      if (editor.showGlobalSearch) {
        editor.hideGlobalSearchPanel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorProvider>();
    final isMacOS = Theme.of(context).platform == TargetPlatform.macOS;

    // 使用 CallbackShortcuts 绑定快捷键
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        // Ctrl/Cmd + N: 新建
        SingleActivator(
          LogicalKeyboardKey.keyN,
          control: !isMacOS,
          meta: isMacOS,
        ): _newFile,
        // Ctrl/Cmd + O: 打开
        SingleActivator(
          LogicalKeyboardKey.keyO,
          control: !isMacOS,
          meta: isMacOS,
        ): _openFile,
        // Ctrl/Cmd + S: 保存
        SingleActivator(
          LogicalKeyboardKey.keyS,
          control: !isMacOS,
          meta: isMacOS,
        ): _saveFile,
        // Ctrl/Cmd + Shift + S: 另存为
        SingleActivator(
          LogicalKeyboardKey.keyS,
          control: !isMacOS,
          meta: isMacOS,
          shift: true,
        ): _saveFileAs,
        // Ctrl/Cmd + F: 查找（再次按下关闭）
        SingleActivator(
          LogicalKeyboardKey.keyF,
          control: !isMacOS,
          meta: isMacOS,
        ): _toggleFind,
        // Ctrl/Cmd + Shift + F: 全局搜索
        SingleActivator(
          LogicalKeyboardKey.keyF,
          control: !isMacOS,
          meta: isMacOS,
          shift: true,
        ): _showGlobalSearch,
        // Ctrl/Cmd + H: 替换
        SingleActivator(
          LogicalKeyboardKey.keyH,
          control: !isMacOS,
          meta: isMacOS,
        ): _showFind,
        // F3: 下一个匹配
        const SingleActivator(LogicalKeyboardKey.f3): _findNext,
        // Shift + F3: 上一个匹配
        const SingleActivator(LogicalKeyboardKey.f3, shift: true):
            _findPrevious,
        // Esc: 关闭查找栏
        const SingleActivator(LogicalKeyboardKey.escape): _hideFind,
        // Ctrl + F4: 关闭当前文件
        const SingleActivator(LogicalKeyboardKey.f4, control: true): _closeFile,
      },
      child: Focus(
        autofocus: true,
        child: DropTarget(
          onDragEntered: (_) => setState(() => _isDragging = true),
          onDragExited: (_) => setState(() => _isDragging = false),
          onDragDone: (detail) {
            setState(() => _isDragging = false);
            final fileList = context.read<FileListProvider>();
            for (final xFile in detail.files) {
              final path = xFile.path;
              if (path.isNotEmpty) {
                fileList.openFile(path);
              }
            }
          },
          child: Stack(
            children: [
              Scaffold(
                body: Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const FileListPanel(),
                          Expanded(
                            child: Column(
                              children: [
                                // 编辑区域
                                Expanded(
                                  child: Column(
                                    children: [
                                      // 查找替换栏（条件显示）
                                      if (editor.showFindReplace)
                                        const FindReplaceBar(),
                                      // 编辑器
                                      const Expanded(
                                        child: EditorPanel(),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 状态栏
                    const StatusBar(),
                  ],
                ),
              ),
              // 拖拽悬停遮罩
              if (_isDragging)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 20,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.file_download,
                                size: 32,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '松开以打开文件',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
