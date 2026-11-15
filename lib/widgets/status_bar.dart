/// 状态栏组件。
///
/// 显示当前文件路径、光标位置、修改状态、字体大小等信息。
library widgets.status_bar;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/editor_provider.dart';
import '../providers/file_list_provider.dart';

/// 底部状态栏。
class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final fileList = context.watch<FileListProvider>();
    final editor = context.watch<EditorProvider>();
    final activeFile = fileList.activeFile;

    final path = activeFile?.filePath ?? activeFile?.title ?? '无打开文件';
    final isDirty = activeFile?.isDirty ?? false;
    final fontSize = editor.fontSize.round();

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
          Expanded(
            child: Text(
              path,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '字号: $fontSize',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
