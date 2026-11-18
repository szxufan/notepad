/// 左侧文件列表面板。
///
/// 显示所有打开的文件列表，高亮当前活动文件，
/// 支持点击切换、拖拽排序、右键菜单操作（含批量关闭与重命名）。
library widgets.file_list_panel;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note_file.dart';
import '../providers/file_list_provider.dart';
import '../services/ai_title_service.dart';
import '../services/file_service.dart';
import 'ai_settings_dialog.dart';

/// 保存文件，失败时提示（如编码无法表示内容）。
///
/// 仅在确实写入文件后返回 true；用户取消或保存失败均返回 false。
Future<bool> _saveFile(
  BuildContext context,
  FileListProvider fileList,
  NoteFile file, {
  bool saveAs = false,
}) async {
  try {
    if (saveAs || file.filePath == null) {
      return await fileList.saveFileAs(file.id);
    }
    await fileList.saveFile(file.id);
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    }
    return false;
  }
}

/// 逐个打开给定路径列表，单个失败不阻塞其余，失败以 SnackBar 提示。
///
/// 供打开对话框、拖拽、命令行参数等入口共用。
void openFilePaths(
  BuildContext context,
  FileListProvider fileList,
  List<String> paths,
) {
  for (final path in paths) {
    if (path.isEmpty) continue;
    try {
      fileList.openFile(path);
    } on FileTooLargeException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$path: $e')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开失败 $path: $e')),
        );
      }
    }
  }
}

/// 批量关闭文件，有未保存修改时统一确认。
///
/// [targets] 为待关闭文件列表。选择"全部保存"时逐个保存，任一失败或取消
/// 则中止整批；等待期间新增或重新变脏的文件不会被旧操作误关闭。
Future<void> _closeFilesWithConfirmation(
  BuildContext context,
  FileListProvider fileList,
  List<NoteFile> targets,
) async {
  if (targets.isEmpty) return;
  final targetIds = targets.map((file) => file.id).toList();
  final dirty = targets.where((f) => f.isDirty).toList();
  if (dirty.isEmpty) {
    fileList.closeFiles(targetIds);
    return;
  }
  final action = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('关闭文件'),
        content: Text('${dirty.length} 个文件有未保存的修改，是否保存后关闭？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('discard'),
            child: const Text('不保存'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('save'),
            child: const Text('全部保存'),
          ),
        ],
      );
    },
  );
  if (!context.mounted || action == null || action == 'cancel') return;
  if (action == 'save') {
    for (final file in dirty) {
      // 重取最新状态，避免基于过期快照保存
      final current = fileList.getFile(file.id);
      if (current == null || !current.isDirty) continue;
      final saved = await _saveFile(context, fileList, current);
      if (!saved) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('保存失败或已取消，批量关闭已中止')),
          );
        }
        return;
      }
    }
    // 原本干净的文件可能在等待其他文件保存时被编辑；已保存文件也可能
    // 在异步落盘期间再次变脏。此时整批保留，由用户重新确认。
    final hasNewChanges = targetIds.any(
      (id) => fileList.getFile(id)?.isDirty ?? false,
    );
    if (hasNewChanges) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('关闭期间产生新修改，批量关闭已中止')),
        );
      }
      return;
    }
  }
  if (context.mounted) {
    fileList.closeFiles(targetIds);
  }
}

/// 左侧文件列表面板。
class FileListPanel extends StatelessWidget {
  const FileListPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final fileList = context.watch<FileListProvider>();
    final active = fileList.activeFile;

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // 顶部工具栏
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.note_add, size: 20),
                  tooltip: '新建文件 (Ctrl+N)',
                  onPressed: () {
                    context.read<FileListProvider>().addNewFile();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.folder_open, size: 20),
                  tooltip: '打开文件 (Ctrl+O，可多选)',
                  onPressed: () async {
                    final paths = await context
                        .read<FileListProvider>()
                        .fileService
                        .pickFiles();
                    if (context.mounted) {
                      openFilePaths(
                        context,
                        context.read<FileListProvider>(),
                        paths,
                      );
                    }
                  },
                ),
                const Spacer(),
                // AI 生成标题按钮
                _buildAiTitleButton(context, fileList),
                IconButton(
                  icon: const Icon(Icons.settings, size: 20),
                  tooltip: 'AI 设置',
                  onPressed: () => AiSettingsDialog.show(context),
                ),
                IconButton(
                  icon: const Icon(Icons.save, size: 20),
                  tooltip: '保存 (Ctrl+S)',
                  onPressed: active != null && !active.isReadOnly
                      ? () => _saveFile(context, fileList, active)
                      : null,
                ),
              ],
            ),
          ),
          // 文件列表（可拖拽排序）
          Expanded(
            child: fileList.isEmpty
                ? const Center(
                    child: Text(
                      '无打开文件',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ReorderableListView.builder(
                    itemCount: fileList.files.length,
                    onReorderItem: (oldIndex, newIndex) =>
                        fileList.reorderFiles(oldIndex, newIndex),
                    itemBuilder: (context, index) {
                      final file = fileList.files[index];
                      final isActive = file.id == fileList.activeFileId;
                      return _FileListItem(
                        key: ValueKey(file.id),
                        file: file,
                        isActive: isActive,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 构建 AI 生成标题按钮。
  Widget _buildAiTitleButton(BuildContext context, FileListProvider fileList) {
    final active = fileList.activeFile;
    final canGenerate =
        active != null && active.isNew && active.content.trim().isNotEmpty;
    final generating =
        active != null && fileList.isAiTitleGenerating(active.id);

    if (generating) {
      return const Padding(
        padding: EdgeInsets.all(10),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return IconButton(
      icon: const Icon(Icons.auto_awesome, size: 20),
      tooltip: 'AI 生成标题',
      onPressed: canGenerate
          ? () async {
              try {
                await fileList.generateTitleManually(active.id);
              } on AiTitleException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.message)),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('AI 生成标题失败: $e')),
                  );
                }
              }
            }
          : null,
    );
  }
}

/// 文件列表项。
class _FileListItem extends StatelessWidget {
  const _FileListItem({
    super.key,
    required this.file,
    required this.isActive,
  });

  final NoteFile file;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final fileList = context.read<FileListProvider>();

    return InkWell(
      onTap: () => fileList.switchToFile(file.id),
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, details, fileList),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: isActive
            ? Theme.of(context).colorScheme.primaryContainer.withValues(
                  alpha: 0.3,
                )
            : null,
        child: Row(
          children: [
            // 修改状态指示
            if (file.isDirty)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.circle, size: 8, color: Colors.orange),
              )
            else
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.circle, size: 8, color: Colors.transparent),
              ),
            // 文件图标（只读大文件显示锁形）
            Icon(
              file.isReadOnly
                  ? Icons.lock_outline
                  : file.isNew
                      ? Icons.description
                      : Icons.insert_drive_file,
              size: 16,
              color: isActive
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).iconTheme.color,
            ),
            const SizedBox(width: 6),
            // 文件名
            Expanded(
              child: Text(
                file.title,
                style: TextStyle(
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 关闭按钮
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              padding: EdgeInsets.zero,
              onPressed: () => _closeFile(context, fileList),
            ),
          ],
        ),
      ),
    );
  }

  /// 关闭文件（如有未保存修改则提示）。
  void _closeFile(
    BuildContext context,
    FileListProvider fileList,
  ) {
    if (file.isDirty) {
      showDialog(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('关闭 ${file.title}'),
            content: const Text('文件有未保存的修改，是否保存？'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  fileList.closeFile(file.id);
                },
                child: const Text('不保存'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  final saved = await _saveFile(context, fileList, file);
                  if (saved && context.mounted) {
                    fileList.closeFile(file.id);
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
      fileList.closeFile(file.id);
    }
  }

  /// 显示右键菜单。
  void _showContextMenu(
    BuildContext context,
    TapUpDetails details,
    FileListProvider fileList,
  ) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      details.globalPosition & const Size(1, 1),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      items: <PopupMenuEntry<String>>[
        const PopupMenuItem(
          value: 'close',
          child: Row(
            children: [
              Icon(Icons.close, size: 18),
              SizedBox(width: 8),
              Text('关闭'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'save',
          enabled: file.isDirty && !file.isReadOnly,
          child: const Row(
            children: [
              Icon(Icons.save, size: 18),
              SizedBox(width: 8),
              Text('保存'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'saveAs',
          enabled: !file.isReadOnly,
          child: const Row(
            children: [
              Icon(Icons.save_as, size: 18),
              SizedBox(width: 8),
              Text('另存为'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'rename',
          enabled: file.filePath != null,
          child: const Row(
            children: [
              Icon(Icons.drive_file_rename_outline, size: 18),
              SizedBox(width: 8),
              Text('重命名'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'closeOthers',
          enabled: fileList.files.length > 1,
          child: const Row(
            children: [
              Icon(Icons.filter_center_focus, size: 18),
              SizedBox(width: 8),
              Text('关闭其他'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'closeSaved',
          enabled: fileList.files.any((f) => !f.isDirty),
          child: const Row(
            children: [
              Icon(Icons.playlist_remove, size: 18),
              SizedBox(width: 8),
              Text('关闭已保存'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'closeAll',
          child: Row(
            children: [
              Icon(Icons.clear_all, size: 18),
              SizedBox(width: 8),
              Text('关闭全部'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      if (!context.mounted) return;
      switch (value) {
        case 'close':
          _closeFile(context, fileList);
          break;
        case 'save':
          _saveFile(context, fileList, file);
          break;
        case 'saveAs':
          _saveFile(context, fileList, file, saveAs: true);
          break;
        case 'rename':
          _showRenameDialog(context, fileList);
          break;
        case 'closeOthers':
          _closeFilesWithConfirmation(
            context,
            fileList,
            fileList.files.where((f) => f.id != file.id).toList(),
          );
          break;
        case 'closeSaved':
          _closeFilesWithConfirmation(
            context,
            fileList,
            fileList.files.where((f) => !f.isDirty).toList(),
          );
          break;
        case 'closeAll':
          _closeFilesWithConfirmation(
            context,
            fileList,
            fileList.files,
          );
          break;
      }
    });
  }

  /// 显示重命名对话框（仅磁盘文件）。
  Future<void> _showRenameDialog(
    BuildContext context,
    FileListProvider fileList,
  ) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initialName: file.title),
    );
    if (newName == null || !context.mounted) return;
    try {
      fileList.renameFile(file.id, newName);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重命名失败: $e')),
        );
      }
    }
  }
}

/// 重命名对话框。
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialName});

  /// 预填的当前文件名。
  final String initialName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: '文件名'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('重命名'),
        ),
      ],
    );
  }
}
