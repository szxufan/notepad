/// 编辑器状态管理。
///
/// 管理字体大小、查找替换功能的状态。
library providers.editor_provider;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../models/note_file.dart';

/// 全局搜索结果项。
class GlobalSearchResult {
  /// 匹配所在文件的 ID。
  final String fileId;

  /// 匹配所在文件的标题。
  final String fileTitle;

  /// 该文件中所有匹配位置。
  final List<TextRange> matches;

  /// 首个匹配周围的文本预览。
  final String preview;

  GlobalSearchResult({
    required this.fileId,
    required this.fileTitle,
    required this.matches,
    required this.preview,
  });

  /// 该文件中的匹配数量。
  int get matchCount => matches.length;
}

/// 编辑器 Provider。
class EditorProvider extends ChangeNotifier {
  EditorProvider();

  /// 默认字体大小。
  static const double defaultFontSize = 14.0;

  /// 最小字体大小。
  static const double minFontSize = 8.0;

  /// 最大字体大小。
  static const double maxFontSize = 48.0;

  /// 字体大小调节步长。
  static const double fontSizeStep = 1.0;

  /// 当前字体大小。
  double _fontSize = defaultFontSize;

  /// 获取当前字体大小。
  double get fontSize => _fontSize;

  /// 是否显示查找替换栏。
  bool _showFindReplace = false;

  /// 获取是否显示查找替换栏。
  bool get showFindReplace => _showFindReplace;

  /// 查找文本。
  String _findText = '';

  /// 获取查找文本。
  String get findText => _findText;

  /// 替换文本。
  String _replaceText = '';

  /// 获取替换文本。
  String get replaceText => _replaceText;

  /// 是否使用正则表达式匹配。
  bool _useRegex = false;

  /// 获取是否使用正则表达式匹配。
  bool get useRegex => _useRegex;

  /// 正则表达式错误信息（null 表示合法）。
  String? _findError;

  /// 获取正则表达式错误信息。
  String? get findError => _findError;

  /// 当前匹配位置列表。
  List<TextRange> _findMatches = [];

  /// 获取当前匹配位置列表。
  List<TextRange> get findMatches => _findMatches;

  /// 当前匹配项索引（-1 表示无匹配）。
  int _currentMatchIndex = -1;

  /// 获取当前匹配项索引。
  int get currentMatchIndex => _currentMatchIndex;

  /// 获取匹配总数。
  int get matchCount => _findMatches.length;

  /// 当前活动文件的内容（用于查找替换）。
  String _currentContent = '';

  /// 获取当前活动文件内容。
  String get currentContent => _currentContent;

  /// 当前活动文件的 ID。
  String? _currentFileId;

  /// 获取当前活动文件的 ID。
  String? get currentFileId => _currentFileId;

  /// 编辑器当前选中的文本（由 EditorPanel 同步）。
  ///
  /// 仅作为打开查找栏时的预填来源；同步时**不触发** [notifyListeners]，
  /// 避免鼠标拖动选区导致的全局重建。
  String _selectedText = '';

  /// 获取编辑器当前选中的文本。
  String get selectedText => _selectedText;

  /// 同步编辑器选中文本。
  ///
  /// 无有效选区时传入空字符串。该方法刻意不通知监听者。
  void setSelectedText(String text) {
    _selectedText = text;
  }

  /// 设置当前活动文件。
  ///
  /// 当活动文件切换时，更新内容并重新计算匹配。
  void setActiveFile(NoteFile? file) {
    _currentFileId = file?.id;
    _currentContent = file?.content ?? '';
    if (_findText.isNotEmpty) {
      _recomputeMatches();
    } else {
      _findMatches = [];
      _currentMatchIndex = -1;
    }
    notifyListeners();
  }

  /// 更新当前内容（编辑时调用）。
  void updateContent(String content) {
    // 内容未变化时不通知，避免无意义的重建
    if (_currentContent == content) return;
    _currentContent = content;
    // 延迟重新计算匹配由调用方防抖处理
    if (_findText.isNotEmpty) {
      _recomputeMatches();
    }
    notifyListeners();
  }

  /// 增大字体大小。
  void increaseFontSize() {
    if (_fontSize < maxFontSize) {
      _fontSize = (_fontSize + fontSizeStep).clamp(minFontSize, maxFontSize);
      notifyListeners();
    }
  }

  /// 减小字体大小。
  void decreaseFontSize() {
    if (_fontSize > minFontSize) {
      _fontSize = (_fontSize - fontSizeStep).clamp(minFontSize, maxFontSize);
      notifyListeners();
    }
  }

  /// 通过滚轮调节字体大小。
  ///
  /// [delta] 为滚轮滚动量，正值放大，负值缩小。
  void adjustFontSize(double delta) {
    final newSize = (_fontSize + delta).clamp(minFontSize, maxFontSize);
    if (newSize != _fontSize) {
      _fontSize = newSize;
      notifyListeners();
    }
  }

  /// 显示查找替换栏。
  ///
  /// 若编辑器存在有效选区，则用选中文本预填查找框（覆盖原有内容）
  /// 并立即重新计算匹配。
  void showFind() {
    final selected = _selectedText;
    if (selected.isNotEmpty) {
      _findText = selected;
      _recomputeMatches();
    }
    _showFindReplace = true;
    notifyListeners();
  }

  /// 隐藏查找替换栏。
  void hideFindReplace() {
    _showFindReplace = false;
    _findText = '';
    _replaceText = '';
    _findMatches = [];
    _currentMatchIndex = -1;
    _findError = null;
    // 保留 _useRegex，下次打开时保持上次模式
    notifyListeners();
  }

  /// 切换查找替换栏显示状态。
  void toggleFindReplace() {
    if (_showFindReplace) {
      hideFindReplace();
    } else {
      showFind();
    }
  }

  /// 设置查找文本并重新计算匹配。
  void setFindText(String text) {
    _findText = text;
    _recomputeMatches();
    notifyListeners();
  }

  /// 设置替换文本。
  void setReplaceText(String text) {
    _replaceText = text;
    notifyListeners();
  }

  /// 设置是否使用正则表达式并重新计算匹配。
  void setUseRegex(bool value) {
    if (_useRegex == value) return;
    _useRegex = value;
    _recomputeMatches();
    notifyListeners();
  }

  /// 重新计算匹配位置。
  void _recomputeMatches() {
    _findError = null;
    if (_findText.isEmpty || _currentContent.isEmpty) {
      _findMatches = [];
      _currentMatchIndex = -1;
      return;
    }
    if (_useRegex) {
      _recomputeRegexMatches();
      return;
    }
    final matches = <TextRange>[];
    var start = 0;
    while (true) {
      final index = _currentContent.indexOf(_findText, start);
      if (index < 0) break;
      matches.add(TextRange(start: index, end: index + _findText.length));
      start = index + _findText.length;
      // 避免空字符串无限循环
      if (_findText.isEmpty) break;
    }
    _applyMatches(matches);
  }

  /// 按正则表达式重新计算匹配位置。
  void _recomputeRegexMatches() {
    final matches = <TextRange>[];
    try {
      final regex = RegExp(_findText);
      for (final match in regex.allMatches(_currentContent)) {
        matches.add(TextRange(start: match.start, end: match.end));
      }
    } on FormatException catch (e) {
      // 正则不合法：视为无匹配，记录错误信息
      _findError = e.message;
      _findMatches = [];
      _currentMatchIndex = -1;
      return;
    }
    _applyMatches(matches);
  }

  /// 应用匹配列表，匹配列表未变化时保留当前索引。
  void _applyMatches(List<TextRange> matches) {
    final matchesUnchanged = _sameRanges(_findMatches, matches);
    _findMatches = matches;
    if (matches.isEmpty) {
      _currentMatchIndex = -1;
    } else if (matchesUnchanged &&
        _currentMatchIndex >= 0 &&
        _currentMatchIndex < matches.length) {
      // 匹配列表未变：保留当前索引
    } else {
      _currentMatchIndex = 0;
    }
  }

  /// 比较两个匹配列表是否相同。
  static bool _sameRanges(List<TextRange> a, List<TextRange> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].start != b[i].start || a[i].end != b[i].end) return false;
    }
    return true;
  }

  /// 跳转到下一个匹配项。
  void findNext() {
    if (_findMatches.isEmpty) return;
    _currentMatchIndex = (_currentMatchIndex + 1) % _findMatches.length;
    notifyListeners();
  }

  /// 跳转到上一个匹配项。
  void findPrevious() {
    if (_findMatches.isEmpty) return;
    _currentMatchIndex =
        (_currentMatchIndex - 1 + _findMatches.length) % _findMatches.length;
    notifyListeners();
  }

  /// 替换当前匹配项。
  ///
  /// 返回替换后的新内容。
  String replace() {
    if (_findMatches.isEmpty || _currentMatchIndex < 0) {
      return _currentContent;
    }
    final match = _findMatches[_currentMatchIndex];
    final newContent = _currentContent.replaceRange(
      match.start,
      match.end,
      _replaceText,
    );
    _currentContent = newContent;
    _recomputeMatches();
    // 调整当前索引
    if (_findMatches.isNotEmpty) {
      if (_currentMatchIndex >= _findMatches.length) {
        _currentMatchIndex = _findMatches.length - 1;
      }
    } else {
      _currentMatchIndex = -1;
    }
    notifyListeners();
    return newContent;
  }

  /// 替换所有匹配项。
  ///
  /// 返回替换后的新内容。
  String replaceAll() {
    if (_findText.isEmpty || _currentContent.isEmpty) {
      return _currentContent;
    }
    if (_useRegex) {
      // 正则不合法时不替换
      if (_findError != null) {
        return _currentContent;
      }
      final newContent = _currentContent.replaceAll(
        RegExp(_findText),
        _replaceText,
      );
      _currentContent = newContent;
      _findMatches = [];
      _currentMatchIndex = -1;
      notifyListeners();
      return newContent;
    }
    final newContent = _currentContent.replaceAll(_findText, _replaceText);
    _currentContent = newContent;
    _findMatches = [];
    _currentMatchIndex = -1;
    notifyListeners();
    return newContent;
  }

  /// 获取当前匹配的 [TextRange]（无匹配时返回 null）。
  TextRange? get currentMatch {
    if (_currentMatchIndex < 0 || _currentMatchIndex >= _findMatches.length) {
      return null;
    }
    return _findMatches[_currentMatchIndex];
  }

  // === 全局搜索 ===

  /// 是否显示全局搜索面板。
  bool _showGlobalSearch = false;

  /// 获取是否显示全局搜索面板。
  bool get showGlobalSearch => _showGlobalSearch;

  /// 全局搜索结果列表。
  List<GlobalSearchResult> _globalSearchResults = [];

  /// 获取全局搜索结果列表。
  List<GlobalSearchResult> get globalSearchResults => _globalSearchResults;

  /// 全局搜索查询文本。
  String _globalSearchText = '';

  /// 获取全局搜索查询文本。
  String get globalSearchText => _globalSearchText;

  /// 全局搜索正则错误信息（null 表示合法）。
  String? _globalSearchError;

  /// 获取全局搜索正则错误信息。
  String? get globalSearchError => _globalSearchError;

  /// 显示全局搜索面板。
  void showGlobalSearchPanel() {
    _showGlobalSearch = true;
    notifyListeners();
  }

  /// 隐藏全局搜索面板。
  void hideGlobalSearchPanel() {
    _showGlobalSearch = false;
    notifyListeners();
  }

  /// 设置当前匹配索引（用于全局搜索跳转）。
  void setCurrentMatchIndex(int index) {
    if (index < 0 || index >= _findMatches.length) return;
    _currentMatchIndex = index;
    notifyListeners();
  }

  /// 执行全局搜索。
  ///
  /// [files] 为所有打开的文件列表，[query] 为搜索文本。
  void performGlobalSearch(List<NoteFile> files, String query) {
    _globalSearchText = query;
    _globalSearchError = null;

    if (query.isEmpty) {
      _globalSearchResults = [];
      notifyListeners();
      return;
    }

    final results = <GlobalSearchResult>[];

    for (final file in files) {
      if (file.content.isEmpty) continue;
      final matches = _searchContent(file.content, query);
      if (matches.isEmpty) continue;
      results.add(GlobalSearchResult(
        fileId: file.id,
        fileTitle: file.title,
        matches: matches,
        preview: _buildPreview(file.content, matches.first),
      ));
    }

    _globalSearchResults = results;
    notifyListeners();
  }

  /// 搜索内容，返回所有匹配位置（复用现有逻辑）。
  List<TextRange> _searchContent(String content, String query) {
    if (query.isEmpty || content.isEmpty) return [];
    if (_useRegex) {
      try {
        final regex = RegExp(query);
        return regex
            .allMatches(content)
            .map((m) => TextRange(start: m.start, end: m.end))
            .toList();
      } on FormatException catch (e) {
        _globalSearchError = e.message;
        return [];
      }
    }
    final matches = <TextRange>[];
    var start = 0;
    while (true) {
      final index = content.indexOf(query, start);
      if (index < 0) break;
      matches.add(TextRange(start: index, end: index + query.length));
      start = index + query.length;
      if (query.isEmpty) break;
    }
    return matches;
  }

  /// 构建匹配预览文本。
  String _buildPreview(String content, TextRange range) {
    const int contextChars = 30;
    final previewStart = (range.start - contextChars).clamp(0, content.length);
    final previewEnd = (range.end + contextChars).clamp(0, content.length);
    var preview = content.substring(previewStart, previewEnd);
    // 替换换行符为空格，使预览单行显示
    preview = preview.replaceAll(RegExp(r'\r?\n'), ' ');
    return preview;
  }
}
