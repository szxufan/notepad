/// 主页面布局。
///
/// 左侧文件列表 + 右侧编辑区 + 底部状态栏，
/// 集成快捷键绑定。
library pages.home_page;

import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/note_file.dart';
import '../providers/editor_provider.dart';
import '../providers/file_list_provider.dart';
import '../services/draft_service.dart';
import '../services/encoding_service.dart';
import '../services/file_watch_service.dart';
import '../widgets/editor_panel.dart';
import '../widgets/file_list_panel.dart';
import '../widgets/find_replace_bar.dart';
import '../widgets/global_search_panel.dart';
import '../widgets/status_bar.dart';

/// 主页面。
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.startupFiles = const []});

  /// 命令行传入的待打开文件路径（启动时处理）。
  final List<String> startupFiles;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// 草稿服务引用（dispose 阶段无法安全地通过 context 获取）。
  late DraftService _draftService;

  /// 文件监听服务引用。
  late FileWatchService _fileWatchService;

  /// 各文件等待用户处理的外部修改内容，同时用于防止重复弹窗。
  final Map<String, String> _pendingReloadContents = {};

  /// 是否正在拖拽文件悬停于窗口上。
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _draftService = context.read<DraftService>();
    _fileWatchService = context.read<FileWatchService>();
    _fileWatchService.onExternalChange = _onExternalChange;
    _fileWatchService.onFileDeleted = _onFileDeleted;
    _fileWatchService.onFileTooLarge = _onFileTooLarge;
    // 启动自动保存草稿与外部修改监听
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fileList = context.read<FileListProvider>();
      _draftService.startAutoSave(() async => fileList.allFiles);
      _fileWatchService.start(() => fileList.allFiles);
      _registerAppChannel();
      if (widget.startupFiles.isNotEmpty) {
        _openNormalizedPaths(widget.startupFiles);
      }
    });
  }

  @override
  void dispose() {
    // 停止自动保存与监听
    _draftService.stopAutoSave();
    _fileWatchService.stop();
    const MethodChannel('notepad/app').setMethodCallHandler(null);
    super.dispose();
  }

  /// 注册原生侧文件转发通道（Windows 单实例第二次启动时转发路径）。
  void _registerAppChannel() {
    if (defaultTargetPlatform != TargetPlatform.windows) return;
    const channel = MethodChannel('notepad/app');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'openFiles' && mounted) {
        final paths = (call.arguments as List).cast<String>();
        _openNormalizedPaths(paths);
      }
    });
    // 通知原生侧 Dart 处理器已就绪，冲刷排队的转发请求。
    // Widget 测试或未注册原生通道的环境中不应产生未处理异步异常。
    unawaited(
      channel.invokeMethod<void>('ready').onError<MissingPluginException>(
            (error, stack) {},
          ),
    );
  }

  /// 规范化路径（相对转绝对、Windows 大小写归一）后逐个打开。
  void _openNormalizedPaths(List<String> paths) {
    final fileList = context.read<FileListProvider>();
    final normalized = paths
        .where((path) => path.isNotEmpty)
        .map((path) => p.canonicalize(path))
        .toList();
    openFilePaths(context, fileList, normalized);
  }

  /// 文件被外部修改：无本地修改时静默重载，有修改时询问用户。
  void _onExternalChange(NoteFile file, String newDiskContent) {
    if (!mounted) return;
    final fileList = context.read<FileListProvider>();
    // 重取最新状态，避免基于过期快照决策
    final current = fileList.getFile(file.id);
    if (current == null) return;
    // 磁盘内容与当前快照一致：本应用自身保存，忽略
    if (current.diskContent == newDiskContent) return;
    if (!current.isDirty) {
      fileList.applyExternalReload(current.id, newDiskContent);
      return;
    }
    final dialogPending = _pendingReloadContents.containsKey(current.id);
    // 弹窗显示期间仍记录最新磁盘版本，确认时不能加载旧闭包中的内容。
    _pendingReloadContents[current.id] = newDiskContent;
    if (dialogPending) return;
    showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('${current.title} 已被外部修改'),
          content: const Text('该文件已被其他程序修改，且本地有未保存的修改。是否重新加载磁盘内容？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('保留我的修改'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('重新加载'),
            ),
          ],
        );
      },
    ).then((shouldReload) {
      final latestContent = _pendingReloadContents.remove(current.id);
      if (shouldReload != true || !mounted || latestContent == null) return;
      final latestFile = fileList.getFile(current.id);
      if (latestFile == null || latestFile.diskContent == latestContent) return;
      fileList.applyExternalReload(current.id, latestContent);
    });
  }

  /// 已打开文件增长到只读阈值以上：保留当前内容并提示重新打开。
  void _onFileTooLarge(NoteFile file, int sizeBytes) {
    if (!mounted) return;
    final current = context.read<FileListProvider>().getFile(file.id);
    if (current == null) return;
    final sizeMB = (sizeBytes / 1024 / 1024).toStringAsFixed(1);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${current.title} 已增大到 $sizeMB MB，已暂停自动重载；'
          '如需查看新内容，请关闭后重新打开',
        ),
      ),
    );
  }

  /// 文件被外部删除：提示一次，内容保留在内存中。
  void _onFileDeleted(NoteFile file) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('文件已被外部删除: ${file.filePath ?? file.title}'),
      ),
    );
  }

  /// 新建文件
  void _newFile() {
    context.read<FileListProvider>().addNewFile();
  }

  /// 打开文件（支持多选）
  Future<void> _openFile() async {
    final fileList = context.read<FileListProvider>();
    final paths = await fileList.fileService.pickFiles();
    if (mounted) {
      openFilePaths(context, fileList, paths);
    }
  }

  /// 保存文件
  Future<void> _saveFile() async {
    final active = context.read<FileListProvider>().activeFile;
    if (active == null) return;
    await _saveNote(active.id);
  }

  /// 保存指定文件，返回是否确实写入磁盘。
  Future<bool> _saveNote(String id, {bool saveAs = false}) async {
    final fileList = context.read<FileListProvider>();
    final file = fileList.getFile(id);
    if (file == null) return false;
    if (file.isReadOnly) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('只读文件不能保存')),
        );
      }
      return false;
    }
    try {
      if (saveAs || file.filePath == null) {
        return await fileList.saveFileAs(id);
      }
      await fileList.saveFile(id);
      return true;
    } on EncodingException catch (e) {
      if (!mounted) return false;
      return _showEncodingFallbackDialog(id, e, saveAs: saveAs);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
      return false;
    }
  }

  /// 当前编码无法表示内容时，提供转为 UTF-8 保存的选项。
  Future<bool> _showEncodingFallbackDialog(
    String id,
    EncodingException error, {
    bool saveAs = false,
  }) async {
    final fileList = context.read<FileListProvider>();
    final saveAsUtf8 = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('无法以当前编码保存'),
          content: Text('$error。是否转为 UTF-8 保存？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('转为 UTF-8 保存'),
            ),
          ],
        );
      },
    );
    if (saveAsUtf8 != true || !mounted) return false;
    // 仅更改保存编码，保留本地编辑内容
    fileList.setSaveEncoding(id, EncodingService.utf8Name);
    try {
      final file = fileList.getFile(id);
      if (file == null) return false;
      if (saveAs || file.filePath == null) {
        return await fileList.saveFileAs(id);
      }
      await fileList.saveFile(id);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
      return false;
    }
  }

  /// 另存为
  Future<void> _saveFileAs() async {
    final active = context.read<FileListProvider>().activeFile;
    if (active == null) return;
    await _saveNote(active.id, saveAs: true);
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
                  final saved = await _saveNote(active.id);
                  if (saved && mounted) {
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
            openFilePaths(
              context,
              fileList,
              detail.files.map((f) => f.path).toList(),
            );
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
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.1),
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
