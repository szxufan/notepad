/// 左侧文件列表面板。
///
/// 显示所有打开的文件列表，高亮当前活动文件，
/// 支持点击切换、右键菜单操作。
library widgets.file_list_panel;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note_file.dart';
import '../providers/file_list_provider.dart';
import '../services/ai_title_service.dart';
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

/// 左侧文件列表面板。
class FileListPanel extends StatelessWidget {
  const FileListPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final fileList = context.watch<FileListProvider>();

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
                  tooltip: '打开文件 (Ctrl+O)',
                  onPressed: () async {
                    final path = await context
                        .read<FileListProvider>()
                        .fileService
                        .pickFile();
                    if (path != null && context.mounted) {
                      context.read<FileListProvider>().openFile(path);
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
                  onPressed: fileList.activeFile != null
                      ? () => _saveFile(
                            context,
                            fileList,
                            fileList.activeFile!,
                          )
                      : null,
                ),
              ],
            ),
          ),
          // 文件列表
          Expanded(
            child: fileList.isEmpty
                ? const Center(
                    child: Text(
                      '无打开文件',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: fileList.files.length,
                    itemBuilder: (context, index) {
                      final file = fileList.files[index];
                      final isActive = file.id == fileList.activeFileId;
                      return _FileListItem(
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
            // 文件图标
            Icon(
              file.isNew ? Icons.description : Icons.insert_drive_file,
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

    showMenu(
      context: context,
      position: position,
      items: [
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
          enabled: file.isDirty,
          child: const Row(
            children: [
              Icon(Icons.save, size: 18),
              SizedBox(width: 8),
              Text('保存'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'saveAs',
          child: Row(
            children: [
              Icon(Icons.save_as, size: 18),
              SizedBox(width: 8),
              Text('另存为'),
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
      }
    });
  }
}
