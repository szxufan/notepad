/// 笔记文件数据模型。
///
/// 表示一个正在编辑的文本文件，可以是已保存到磁盘的文件，
/// 也可以是新建未命名的新文件。支持序列化/反序列化用于草稿持久化。
library models.note_file;

import 'dart:io';

import 'package:path/path.dart' as p;

/// 笔记文件模型类。
class NoteFile {
  /// 唯一标识符（UUID）。
  final String id;

  /// 显示标题（文件名，从路径提取或默认"无标题"）。
  String title;

  /// 关联的磁盘文件路径。null 表示新建未保存文件。
  String? filePath;

  /// 当前文本内容。
  String content;

  /// 上次保存到磁盘时的内容快照。
  ///
  /// 用于恢复时判断草稿是否比磁盘内容新。
  String? diskContent;

  /// 是否有未保存的修改。
  bool isDirty;

  /// 内容最后修改时间。
  DateTime lastModified;

  /// 上次保存到磁盘的时间。
  DateTime? lastSavedAt;

  /// 是否为新建未命名文件。
  bool isNew;

  /// 标题是否已由 AI 生成过（用于"首次超过 64 字"只触发一次）。
  bool hasAiTitle;

  /// 标题是否已锁定（内容超过 64 字后不再跟随首行变化）。
  bool isTitleLocked;

  /// 文件编码名（如 'UTF-8'、'GBK'、'UTF-16 LE'）。
  ///
  /// 打开时自动检测，保存时沿用；新建文件默认 UTF-8。
  String encoding;

  /// 是否为只读文件（超过大小阈值的大文件）。
  ///
  /// 只读文件禁止编辑与保存，草稿不持久化其内容。
  bool isReadOnly;

  /// 创建 [NoteFile] 实例。
  NoteFile({
    required this.id,
    required this.title,
    this.filePath,
    required this.content,
    this.diskContent,
    this.isDirty = false,
    required this.lastModified,
    this.lastSavedAt,
    this.isNew = false,
    this.hasAiTitle = false,
    this.isTitleLocked = false,
    this.encoding = 'UTF-8',
    this.isReadOnly = false,
  });

  /// 从磁盘文件创建 [NoteFile]。
  factory NoteFile.fromDisk(
    String id,
    String path,
    String content, {
    String encoding = 'UTF-8',
    bool isReadOnly = false,
  }) {
    final stat = FileStat.statSync(path);
    return NoteFile(
      id: id,
      title: p.basename(path),
      filePath: path,
      content: content,
      diskContent: content,
      isDirty: false,
      lastModified: stat.modified,
      lastSavedAt: stat.modified,
      isNew: false,
      encoding: encoding,
      isReadOnly: isReadOnly,
    );
  }

  /// 从 JSON 创建 [NoteFile]（用于草稿恢复）。
  factory NoteFile.fromJson(Map<String, dynamic> json) {
    return NoteFile(
      id: json['id'] as String,
      title: json['title'] as String,
      filePath: json['filePath'] as String?,
      content: json['content'] as String? ?? '',
      diskContent: json['diskContent'] as String?,
      isDirty: json['isDirty'] as bool? ?? false,
      lastModified: DateTime.parse(json['lastModified'] as String),
      lastSavedAt: json['lastSavedAt'] != null
          ? DateTime.parse(json['lastSavedAt'] as String)
          : null,
      isNew: json['isNew'] as bool? ?? false,
      encoding: json['encoding'] as String? ?? 'UTF-8',
      isReadOnly: json['isReadOnly'] as bool? ?? false,
    );
  }

  /// 序列化为 JSON（用于草稿持久化）。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'filePath': filePath,
      'content': content,
      'diskContent': diskContent,
      'isDirty': isDirty,
      'lastModified': lastModified.toIso8601String(),
      'lastSavedAt': lastSavedAt?.toIso8601String(),
      'isNew': isNew,
      'encoding': encoding,
      'isReadOnly': isReadOnly,
    };
  }

  /// 创建副本。
  NoteFile copyWith({
    String? id,
    String? title,
    String? filePath,
    String? content,
    String? diskContent,
    bool? isDirty,
    DateTime? lastModified,
    DateTime? lastSavedAt,
    bool? isNew,
    bool? hasAiTitle,
    bool? isTitleLocked,
    String? encoding,
    bool? isReadOnly,
  }) {
    return NoteFile(
      id: id ?? this.id,
      title: title ?? this.title,
      filePath: filePath ?? this.filePath,
      content: content ?? this.content,
      diskContent: diskContent ?? this.diskContent,
      isDirty: isDirty ?? this.isDirty,
      lastModified: lastModified ?? this.lastModified,
      lastSavedAt: lastSavedAt ?? this.lastSavedAt,
      isNew: isNew ?? this.isNew,
      hasAiTitle: hasAiTitle ?? this.hasAiTitle,
      isTitleLocked: isTitleLocked ?? this.isTitleLocked,
      encoding: encoding ?? this.encoding,
      isReadOnly: isReadOnly ?? this.isReadOnly,
    );
  }

  @override
  String toString() {
    return 'NoteFile(id: $id, title: $title, filePath: $filePath, '
        'isDirty: $isDirty, isNew: $isNew, contentLength: ${content.length})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NoteFile && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
