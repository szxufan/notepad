/// 状态栏组件。
///
/// 显示当前文件路径、光标位置、字数、编码、修改状态、字体大小等信息。
/// 点击编码名可打开编码切换菜单。
library widgets.status_bar;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note_file.dart';
import '../providers/cursor_provider.dart';
import '../providers/editor_provider.dart';
import '../providers/file_list_provider.dart';
import '../services/encoding_service.dart';

/// 底部状态栏。
class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final fileList = context.watch<FileListProvider>();
    final editor = context.watch<EditorProvider>();
    final cursor = context.watch<CursorProvider>();
    final activeFile = fileList.activeFile;

    final path = activeFile?.filePath ?? activeFile?.title ?? '无打开文件';
    final isDirty = activeFile?.isDirty ?? false;
    final fontSize = editor.fontSize.round();
    final charCount = activeFile?.content.length ?? 0;
    final selectionLength = cursor.selectionLength;
    final countText = selectionLength > 0
        ? '已选 $selectionLength / $charCount 字符'
        : '$charCount 字符';
    final labelStyle = Theme.of(context).textTheme.bodySmall;

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          if (isDirty)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.circle, size: 8, color: Colors.orange),
            ),
          if (activeFile?.isReadOnly ?? false)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                Icons.lock_outline,
                size: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          Expanded(
            child: Text(
              path,
              style: labelStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 16),
          Text('行 ${cursor.line}, 列 ${cursor.column}', style: labelStyle),
          const SizedBox(width: 16),
          Text(countText, style: labelStyle),
          const SizedBox(width: 16),
          _EncodingLabel(file: activeFile),
          const SizedBox(width: 16),
          Text('字号: $fontSize', style: labelStyle),
        ],
      ),
    );
  }
}

/// 编码名标签（点击打开切换菜单）。
class _EncodingLabel extends StatelessWidget {
  const _EncodingLabel({required this.file});

  /// 当前活动文件（无文件时标签不可交互）。
  final NoteFile? file;

  /// 显示编码切换菜单。
  Future<void> _showMenu(BuildContext context, TapUpDetails details) async {
    final activeFile = file;
    if (activeFile == null) return;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      details.globalPosition & const Size(1, 1),
      Offset.zero & overlay.size,
    );
    final selected = await showMenu<String>(
      context: context,
      position: position,
      items: [
        for (final name in EncodingService.supportedEncodings)
          PopupMenuItem(
            value: name,
            child: Row(
              children: [
                Icon(
                  Icons.check,
                  size: 16,
                  color: name == activeFile.encoding
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                ),
                const SizedBox(width: 8),
                Text(name),
              ],
            ),
          ),
      ],
    );
    if (selected == null || selected == activeFile.encoding) return;
    if (!context.mounted) return;
    await _switchEncoding(context, activeFile, selected);
  }

  /// 执行编码切换（脏文件先确认）。
  Future<void> _switchEncoding(
    BuildContext context,
    NoteFile file,
    String name,
  ) async {
    final fileList = context.read<FileListProvider>();
    // 有未保存修改时，重读磁盘会丢弃本地修改，先确认
    if (file.isDirty && file.filePath != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('切换编码为 $name'),
          content: const Text('将按新编码从磁盘重新加载文件，未保存的修改会丢弃。是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('切换'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    try {
      await fileList.switchEncoding(file.id, name);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('切换编码失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = file?.encoding ?? EncodingService.utf8Name;
    // 只读大文件不提供编码切换（切换会重读磁盘，无意义）
    if (file?.isReadOnly ?? false) {
      return Text(name, style: Theme.of(context).textTheme.bodySmall);
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapUp: (details) => _showMenu(context, details),
        child: Tooltip(
          message: '点击切换编码',
          child: Text(
            name,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ),
    );
  }
}