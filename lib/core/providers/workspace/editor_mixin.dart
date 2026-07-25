part of '../workspace_provider.dart';

/// 编辑器域 Mixin
///
/// 管理标签页、查找替换、全文搜索、自动保存、会话追踪、备份恢复等
/// 服务于小说编辑器与大纲编辑器的状态与操作。
///
/// 依赖 [BookDataMixin]：通过 `on WorkspaceStateBase, BookDataMixin` 约束，
/// 直接访问 currentBook / chapters / settingItems / saveChapterContent 等，
/// 并实现 [WorkspaceStateBase] 中声明的 [closeTab] 与
/// [saveChapterCursorPositionIfAny] 协调方法，供 [BookDataMixin] 反向调用。
mixin EditorMixin on WorkspaceStateBase, BookDataMixin {
  // ================= 查找替换状态 =================

  /// 查找替换栏是否可见
  bool _isFindReplaceVisible = false;

  /// 查找文本
  String _findText = '';

  /// 替换文本
  String _replaceText = '';

  /// 大小写敏感
  bool _findCaseSensitive = false;

  /// 是否显示替换区域
  bool _showReplace = false;

  /// 匹配结果列表（存储每个匹配的起始和结束偏移量）
  final List<TextSelection> _findMatches = [];

  /// 当前匹配索引（在 _findMatches 中的位置，-1 表示无选中匹配）
  int _currentMatchIndex = -1;

  // ================= 全文搜索状态 =================

  /// 全文搜索关键词
  String _globalSearchQuery = '';

  /// 全文搜索是否大小写敏感
  bool _globalSearchCaseSensitive = false;

  /// 全文搜索结果列表
  List<GlobalSearchResult> _globalSearchResults = [];

  /// 全文搜索是否正在进行
  bool _isGlobalSearching = false;

  // ================= 多标签页状态 =================

  /// 当前选中的标签页索引
  int _currentTabIndex = -1;

  // ================= 自动保存状态 =================

  /// 自动保存防抖定时器
  Timer? _autoSaveTimer;

  // ================= 码字会话追踪器 =================

  /// 当前会话的码字统计追踪器，工作台初始化时创建
  WritingSessionTracker? _sessionTracker;

  /// 获取码字会话追踪器
  WritingSessionTracker? get sessionTracker => _sessionTracker;

  // ================= Getters =================

  bool get isFindReplaceVisible => _isFindReplaceVisible;
  String get findText => _findText;
  String get replaceText => _replaceText;
  bool get findCaseSensitive => _findCaseSensitive;
  bool get showReplace => _showReplace;
  List<TextSelection> get findMatches => List.unmodifiable(_findMatches);
  int get currentMatchIndex => _currentMatchIndex;
  String get globalSearchQuery => _globalSearchQuery;
  bool get globalSearchCaseSensitive => _globalSearchCaseSensitive;
  List<GlobalSearchResult> get globalSearchResults =>
      List.unmodifiable(_globalSearchResults);
  bool get isGlobalSearching => _isGlobalSearching;

  /// 查找替换栏显示时，编辑器需要预留的顶边距高度
  double get findReplaceBarPadding {
    if (!_isFindReplaceVisible) return 0.0;
    // 替换区域展开时高度更大（两行），收起时仅查找行（单行）
    return _showReplace ? 88.0 : 48.0;
  }

  /// 当前匹配的序号（从1开始，0表示尚未定位，显示为?）
  int get currentMatchDisplayIndex =>
      _findMatches.isEmpty || _currentMatchIndex < 0 ? 0 : _currentMatchIndex + 1;

  /// 总匹配数
  int get totalMatchCount => _findMatches.length;

  List<EditorTab> get openedTabs => List.unmodifiable(_openedTabs);
  int get currentTabIndex => _currentTabIndex;

  /// 获取当前选中的标签页
  EditorTab? get currentTab {
    if (_currentTabIndex >= 0 && _currentTabIndex < _openedTabs.length) {
      return _openedTabs[_currentTabIndex];
    }
    return null;
  }

  /// 是否有打开的标签页
  bool get hasOpenedTabs => _openedTabs.isNotEmpty;

  // ================= 查找替换方法 =================

  /// 获取当前标签页对应的查找替换目标
  ///
  /// 大纲编辑器标签页返回 [OutlineEditorState]（直接实现 [FindReplaceTarget]）；
  /// 小说编辑器标签页返回 [TextControllerFindReplaceTarget]（包装 [TextEditingController]）。
  FindReplaceTarget? get _currentFindReplaceTarget {
    final tab = currentTab;
    if (tab == null) return null;

    // 大纲编辑器标签页：直接使用编辑器状态作为查找替换目标
    if (tab.usesOutlineEditor) {
      final state = tab.editorKey.currentState;
      if (state is OutlineEditorState) return state;
      return null;
    }

    // 小说编辑器标签页：用适配器包装文本控制器
    if (tab.textController == null) return null;
    return TextControllerFindReplaceTarget(
      controller: tab.textController!,
      onScrollToSelection: () {
        final editorState = tab.editorKey.currentState;
        if (editorState is NovelEditorState) editorState.scrollToCursor();
      },
      onRequestFocus: () {
        final editorState = tab.editorKey.currentState;
        if (editorState is NovelEditorState) editorState.requestEditorFocus();
      },
    );
  }

  /// 对小说编辑器标签页应用修改标记和字数统计更新
  ///
  /// 大纲编辑器标签页的修改标记和字数统计由 [OutlineEditorState.notifyContentChanged] 通过回调链处理，
  /// 此方法仅对拥有 textController 的标签页（小说编辑器）生效。
  void _applyTabModificationAndWordCount() {
    final tab = currentTab;
    if (tab == null || tab.textController == null) return;
    if (!tab.isModified) {
      tab.isModified = true;
      notifyTabModified(tab.id);
    }
    tab.updateWordCount();
    notifyWordCountUpdated();
  }

  /// 打开查找替换栏
  /// [initialText] 初始查找文本（可选，如选中文字后打开）
  /// [showReplace] 是否展开替换区域（Ctrl+H 时为 true）
  void openFindReplace({String? initialText, bool showReplace = false}) {
    // 没有打开的标签页时，不打开查找面板
    if (!hasOpenedTabs) return;

    _isFindReplaceVisible = true;
    _showReplace = showReplace;

    final target = _currentFindReplaceTarget;

    // 如果没有显式传入初始文本，尝试从编辑器选中区域获取
    String? searchText = initialText;
    if (target != null && (searchText == null || searchText.isEmpty)) {
      final sel = target.selection;
      if (sel.isValid && !sel.isCollapsed) {
        // 仅处理单行选中（不包含换行符）
        final selectedText = target.text.substring(sel.start, sel.end);
        if (!selectedText.contains('\n')) {
          searchText = selectedText;
        }
      }
    }

    if (searchText != null && searchText.isNotEmpty) {
      _findText = searchText;
      _performFind();
      // 如果是从编辑器选中区域获取的文本，定位到对应的匹配项索引
      if (initialText == null && _findMatches.isNotEmpty && target != null) {
        final sel = target.selection;
        if (sel.isValid && !sel.isCollapsed) {
          for (int i = 0; i < _findMatches.length; i++) {
            if (_findMatches[i].start == sel.start &&
                _findMatches[i].end == sel.end) {
              _currentMatchIndex = i;
              break;
            }
          }
        }
      }
    } else if (_findText.isNotEmpty) {
      _performFind();
    }

    notifyListeners();
  }

  /// 关闭查找替换栏
  void closeFindReplace() {
    _isFindReplaceVisible = false;
    _clearFindMatches();
    // 关闭后将焦点归还给编辑器
    _requestEditorFocus();
    notifyListeners();
  }

  /// 刷新当前标签页的查找结果
  ///
  /// [resetIndex] 为 true 时重置索引为 -1（显示 ?），
  /// 用于标签页切换/打开等场景；false 时保留并校准索引，
  /// 用于文本内容变化（输入、粘贴、撤销等）
  void refreshFindIfVisible({bool resetIndex = false}) {
    if (!_isFindReplaceVisible || _findText.isEmpty) return;
    if (resetIndex) {
      _performFind();
    } else {
      _rebuildMatches();
    }
    notifyListeners();
  }

  /// 切换查找替换栏显示/隐藏
  void toggleFindReplace() {
    if (_isFindReplaceVisible) {
      closeFindReplace();
    } else {
      openFindReplace();
    }
  }

  /// 更新查找文本并执行搜索
  void updateFindText(String text) {
    _findText = text;
    _performFind();
    // 查找输入框内容变化时自动定位到第一个匹配项
    if (_findMatches.isNotEmpty) {
      _currentMatchIndex = 0;
      _selectCurrentMatch();
    }
    notifyListeners();
  }

  /// 更新替换文本
  void updateReplaceText(String text) {
    _replaceText = text;
  }

  /// 设置大小写敏感
  void setFindCaseSensitive(bool value) {
    _findCaseSensitive = value;
    _performFind();
    notifyListeners();
  }

  /// 设置替换区域显示状态
  void setShowReplace(bool value) {
    _showReplace = value;
    notifyListeners();
  }

  /// 根据当前光标位置，找到最近的匹配项索引
  ///
  /// 返回光标位置之后第一个匹配的索引；如果光标在所有匹配之后，则循环回第一个
  int _findNextMatchIndexFromCursor() {
    final target = _currentFindReplaceTarget;
    if (target == null) return 0;

    final cursorEnd = target.selection.extentOffset;

    for (int i = 0; i < _findMatches.length; i++) {
      if (_findMatches[i].baseOffset >= cursorEnd) {
        return i;
      }
    }
    // 光标在所有匹配之后，循环回第一个
    return 0;
  }

  /// 根据当前光标位置，找到之前最近的匹配项索引
  ///
  /// 返回光标位置之前最后一个匹配的索引；如果光标在所有匹配之前，则循环回最后一个
  int _findPreviousMatchIndexFromCursor() {
    final target = _currentFindReplaceTarget;
    if (target == null) return _findMatches.length - 1;

    final cursorStart = target.selection.baseOffset;

    for (int i = _findMatches.length - 1; i >= 0; i--) {
      if (_findMatches[i].extentOffset <= cursorStart) {
        return i;
      }
    }
    // 光标在所有匹配之前，循环回最后一个
    return _findMatches.length - 1;
  }

  /// 查找下一个匹配
  void findNext() {
    if (_findMatches.isEmpty) return;
    _currentMatchIndex = _findNextMatchIndexFromCursor();
    _selectCurrentMatch();
    notifyListeners();
  }

  /// 查找上一个匹配
  void findPrevious() {
    if (_findMatches.isEmpty) return;
    _currentMatchIndex = _findPreviousMatchIndexFromCursor();
    _selectCurrentMatch();
    notifyListeners();
  }

  /// 替换当前匹配项
  ///
  /// 判断当前光标是否正好选中了某个查找匹配项
  /// - 是（selection 非空且与某个 match 完全一致）：直接替换该 match，然后定位到下一个
  /// - 否（selection 为空 / collapsed / 选中的不是查找项）：仅执行"查找下一个"来定位，不替换
  void replaceCurrentMatch() {
    final target = _currentFindReplaceTarget;
    if (target == null) return;

    final sel = target.selection;

    // 判断当前 selection 是否恰好选中了某个查找匹配项
    int? matchedIndex;
    for (int i = 0; i < _findMatches.length; i++) {
      if (sel.baseOffset == _findMatches[i].start &&
          sel.extentOffset == _findMatches[i].end) {
        matchedIndex = i;
        break;
      }
    }

    // 未选中任何查找匹配项，先执行"查找下一个"来定位，不替换
    if (matchedIndex == null) {
      findNext();
      return;
    }

    // 已选中某个匹配项，直接替换它
    _currentMatchIndex = matchedIndex;
    final match = _findMatches[matchedIndex];
    final text = target.text;

    if (match.start < 0 || match.end > text.length) return;

    target.replaceRange(match.start, match.end, _replaceText);

    // 将光标定位到替换文本之后，确保后续 _findNextMatchIndexFromCursor 从正确位置开始查找
    final cursorAfterReplace = match.start + _replaceText.length;
    target.selection = TextSelection.collapsed(offset: cursorAfterReplace);

    // 通知内容变化（大纲编辑器由此触发自动保存和字数统计）
    target.notifyContentChanged();
    // 小说编辑器标签页的修改标记和字数统计由 Provider 处理
    _applyTabModificationAndWordCount();

    // 重新搜索（文本已变化）
    _performFind();

    // 定位到下一个匹配项
    if (_findMatches.isNotEmpty) {
      _currentMatchIndex = _findNextMatchIndexFromCursor();
      _selectCurrentMatch();
    }

    notifyListeners();
  }

  /// 替换所有匹配项
  void replaceAllMatches() {
    final target = _currentFindReplaceTarget;
    if (target == null) return;
    if (_findMatches.isEmpty || _findText.isEmpty) return;

    target.replaceAll(_findMatches, _replaceText);

    // 通知内容变化（大纲编辑器由此触发自动保存和字数统计）
    target.notifyContentChanged();
    // 小说编辑器标签页的修改标记和字数统计由 Provider 处理
    _applyTabModificationAndWordCount();

    // 重新搜索
    _performFind();
    notifyListeners();
  }

  /// 仅重建匹配列表，不重置 _currentMatchIndex
  ///
  /// 用于文本内容变化（输入、粘贴、撤销等）后刷新匹配结果，
  /// 保持用户当前的导航位置不变；仅在索引超出范围时做边界修正
  void _rebuildMatches() {
    if (_findText.isEmpty) {
      _findMatches.clear();
      _currentMatchIndex = -1;
      return;
    }

    final target = _currentFindReplaceTarget;
    if (target == null) {
      _findMatches.clear();
      _currentMatchIndex = -1;
      return;
    }

    final text = target.text;

    // 保存旧索引和旧匹配项位置（用于校准）
    final oldIndex = _currentMatchIndex;
    int? oldMatchStart;

    if (oldIndex >= 0 && oldIndex < _findMatches.length) {
      oldMatchStart = _findMatches[oldIndex].baseOffset;
    }

    _findMatches.clear();

    if (text.isEmpty) {
      _currentMatchIndex = -1;
      return;
    }

    try {
      final searchText =
          _findCaseSensitive ? _findText : _findText.toLowerCase();
      final searchTextLength = _findText.length;
      final sourceText = _findCaseSensitive ? text : text.toLowerCase();

      int startIndex = 0;
      while (startIndex < sourceText.length) {
        final index = sourceText.indexOf(searchText, startIndex);
        if (index == -1) break;
        _findMatches.add(TextSelection(
          baseOffset: index,
          extentOffset: index + searchTextLength,
        ));
        startIndex = index + searchTextLength;
      }
    } catch (e) {
      _findMatches.clear();
      _currentMatchIndex = -1;
      return;
    }

    // 校准索引：尝试在新的匹配列表中找到与旧索引最接近的匹配项
    if (_findMatches.isEmpty) {
      _currentMatchIndex = -1;
    } else if (oldMatchStart != null && oldIndex >= 0) {
      // 优先找到起始位置最接近旧位置的匹配项
      int bestIndex = 0;
      int bestDiff = (_findMatches[0].baseOffset - oldMatchStart).abs();
      for (int i = 1; i < _findMatches.length; i++) {
        final diff = (_findMatches[i].baseOffset - oldMatchStart).abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          bestIndex = i;
        }
      }
      _currentMatchIndex = bestIndex;
    } else if (_currentMatchIndex >= _findMatches.length) {
      _currentMatchIndex = _findMatches.length - 1;
    } else if (_currentMatchIndex < 0) {
      _currentMatchIndex = 0;
    }
  }

  /// 执行查找并重置索引
  ///
  /// 用于用户主动触发查找（输入关键词、切换标签页等），
  /// 会将 _currentMatchIndex 重置为 -1
  void _performFind() {
    _findMatches.clear();
    _currentMatchIndex = -1;

    if (_findText.isEmpty) return;

    final target = _currentFindReplaceTarget;
    if (target == null) return;

    final text = target.text;
    if (text.isEmpty) return;

    try {
      // 普通文本匹配
      final searchText =
          _findCaseSensitive ? _findText : _findText.toLowerCase();
      final searchTextLength = _findText.length;
      final sourceText = _findCaseSensitive ? text : text.toLowerCase();

      int startIndex = 0;
      while (startIndex < sourceText.length) {
        final index = sourceText.indexOf(searchText, startIndex);
        if (index == -1) break;
        _findMatches.add(TextSelection(
          baseOffset: index,
          extentOffset: index + searchTextLength,
        ));
        startIndex = index + searchTextLength;
      }
    } catch (e) {
      // 匹配失败时，清空匹配结果
      _findMatches.clear();
    }
  }

  /// 清空匹配结果
  void _clearFindMatches() {
    _findMatches.clear();
    _currentMatchIndex = -1;
  }

  /// 选中当前匹配项
  void _selectCurrentMatch() {
    final target = _currentFindReplaceTarget;
    if (target == null) return;
    if (_currentMatchIndex < 0 || _currentMatchIndex >= _findMatches.length) {
      return;
    }

    final match = _findMatches[_currentMatchIndex];
    target.selection = match;

    // 通知编辑器滚动到选区位置
    target.scrollToSelection();
  }

  /// 请求编辑器获取焦点
  void _requestEditorFocus() {
    final target = _currentFindReplaceTarget;
    if (target == null) return;
    target.requestFocus();
  }

  // ================= 全文搜索方法 =================

  /// 更新全文搜索关键词并执行搜索
  Future<void> updateGlobalSearchQuery(String query) async {
    _globalSearchQuery = query;
    if (query.isEmpty) {
      _globalSearchResults = [];
      notifyListeners();
      return;
    }
    await _performGlobalSearch();
  }

  /// 设置全文搜索大小写敏感
  Future<void> setGlobalSearchCaseSensitive(bool value) async {
    _globalSearchCaseSensitive = value;
    if (_globalSearchQuery.isNotEmpty) {
      await _performGlobalSearch();
    }
  }

  /// 执行全文搜索
  /// 遍历当前书籍的所有章节文件，搜索关键词
  ///
  /// 支持使用 "&&" 连接多个关键词进行交集搜索：
  /// 章节级筛选要求同时包含所有关键词，行级匹配则展示任意关键词的命中位置，
  /// 便于用户在通过交集筛选的章节内查看每个关键词的具体出现位置。
  Future<void> _performGlobalSearch() async {
    if (_globalSearchQuery.isEmpty || _currentBook == null) return;

    // 解析多关键词，若解析后为空（如仅输入了分隔符）则清空结果
    final keywords = SearchQueryParser.parse(_globalSearchQuery);
    if (keywords.isEmpty) {
      _globalSearchResults = [];
      _isGlobalSearching = false;
      notifyListeners();
      return;
    }

    _isGlobalSearching = true;
    notifyListeners();

    final results = <GlobalSearchResult>[];

    for (final chapter in _chapters) {
      try {
        final content = await readChapterContent(chapter);
        if (content.isEmpty) continue;

        // 章节级交集过滤：必须同时包含所有关键词
        if (!SearchQueryParser.containsAll(
          content,
          keywords,
          caseSensitive: _globalSearchCaseSensitive,
        )) {
          continue;
        }

        // 收集行级匹配（任意关键词命中即记录该行）
        final matchLines = <GlobalSearchMatchLine>[];
        final lines = content.split('\n');
        int lineStartOffset = 0;

        for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
          final line = lines[lineIndex];
          final matchCountInLine = SearchQueryParser.countMatches(
            line,
            keywords,
            caseSensitive: _globalSearchCaseSensitive,
          );

          if (matchCountInLine > 0) {
            matchLines.add(GlobalSearchMatchLine(
              lineNumber: lineIndex + 1,
              lineContent: line,
              matchCount: matchCountInLine,
              startOffset: lineStartOffset,
            ));
          }

          lineStartOffset += line.length + 1;
        }

        if (matchLines.isNotEmpty) {
          results.add(GlobalSearchResult(
            chapterUuid: chapter.uuid,
            chapterTitle: chapter.title,
            volumeName: getVolumeName(chapter.volumeUuid),
            totalMatches: matchLines.fold<int>(0, (sum, m) => sum + m.matchCount),
            matchLines: matchLines,
          ));
        }
      } catch (e) {
        debugPrint('全文搜索读取章节失败: ${chapter.title}, $e');
      }
    }

    _globalSearchResults = results;
    _isGlobalSearching = false;
    notifyListeners();
  }

  /// 点击全文搜索结果，打开对应章节并定位
  Future<void> navigateToGlobalSearchResult(
      GlobalSearchResult result, GlobalSearchMatchLine matchLine) async {
    // 打开对应章节的标签页
    final existingIndex =
        _openedTabs.indexWhere((t) => t.id == result.chapterUuid);
    if (existingIndex != -1) {
      _currentTabIndex = existingIndex;
    } else {
      // 查找章节模型
      final chapter =
          _chapters.where((c) => c.uuid == result.chapterUuid).firstOrNull;
      if (chapter == null) return;

      openTab(
        EditorTab(
          id: chapter.uuid,
          title: chapter.title,
          type: EditorTabType.chapter,
          isPreview: true,
        ),
        isPreview: true,
      );

      // 等待内容加载
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // 定位到匹配行的起始偏移量
    final tab =
        _openedTabs.where((t) => t.id == result.chapterUuid).firstOrNull;
    if (tab?.textController != null) {
      final controller = tab!.textController!;
      final keywords = SearchQueryParser.parse(_globalSearchQuery);
      final sourceText = _globalSearchCaseSensitive
          ? controller.text
          : controller.text.toLowerCase();

      // 在匹配行范围内查找最早出现的关键词位置
      final lineStart = matchLine.startOffset;
      final lineEnd = lineStart + matchLine.lineContent.length;

      final match = SearchQueryParser.findFirstMatch(
        sourceText,
        keywords,
        start: lineStart,
        caseSensitive: _globalSearchCaseSensitive,
      );
      if (match != null && match.start < lineEnd) {
        controller.selection = TextSelection(
          baseOffset: match.start,
          extentOffset: match.start + match.length,
        );
        // 通知小说编辑器滚动到新选区位置
        final editorState = tab.editorKey.currentState;
        if (editorState is NovelEditorState) {
          editorState.scrollToCursor();
        }
      }
    }

    notifyListeners();
  }

  // ================= 标签页管理 =================

  /// 打开新标签页
  /// 如果标签页已存在，则切换到该标签页
  /// [isPreview] 是否以预览模式打开（默认 true）
  /// 预览模式下，已有预览标签页会被替换为新标签页
  void openTab(EditorTab tab, {bool isPreview = true}) {
    // 如果全局设置关闭了预览模式，则始终以固定模式打开
    if (isPreview && !SettingsService.instance.previewModeEnabled) {
      isPreview = false;
      tab.isPreview = false;
    }

    // 检查是否已存在相同ID的标签页
    final existingIndex = _openedTabs.indexWhere((t) => t.id == tab.id);
    if (existingIndex != -1) {
      // 已存在，切换到该标签页
      _currentTabIndex = existingIndex;
      // 切换到已加载过的标签页，尝试刷新查找结果
      refreshFindIfVisible(resetIndex: true);
    } else if (isPreview) {
      // 预览模式：查找当前已有的预览标签页并替换
      final previewIndex = _openedTabs.indexWhere((t) => t.isPreview);
      if (previewIndex != -1) {
        // 释放被替换的预览标签页资源
        final oldTab = _openedTabs[previewIndex];
        _disposeTabResources(oldTab);
        // 替换预览标签页
        _openedTabs[previewIndex] = tab;
        _currentTabIndex = previewIndex;
      } else {
        // 没有预览标签页，添加新标签页
        _openedTabs.add(tab);
        _currentTabIndex = _openedTabs.length - 1;
      }
    } else {
      // 非预览模式，直接添加新标签页
      _openedTabs.add(tab);
      _currentTabIndex = _openedTabs.length - 1;
    }

    notifyListeners();
  }

  /// 打开备份预览标签页
  ///
  /// 如果同一备份文件已打开，则切换到该标签页
  /// 标签页标题格式：章节名 - 备份时间
  /// 备份预览标签页默认以预览模式打开，会替换已有的预览标签页
  void openBackupPreviewTab({
    required String backupFilePath,
    required String chapterTitle,
    required String formattedTime,
    required String bookUuid,
    required String volumeName,
    bool isPreview = true,
    bool originalIsSetting = false,
  }) {
    // 如果全局设置关闭了预览模式，则始终以固定模式打开
    if (isPreview && !SettingsService.instance.previewModeEnabled) {
      isPreview = false;
    }

    // 按 backupFilePath 去重
    final existingIndex = _openedTabs.indexWhere(
      (t) => t.type == EditorTabType.backupPreview && t.backupFilePath == backupFilePath,
    );

    if (existingIndex != -1) {
      _currentTabIndex = existingIndex;
      refreshFindIfVisible(resetIndex: true);
    } else {
      final tab = EditorTab(
        id: 'backup_${DateTime.now().millisecondsSinceEpoch}',
        title: '$chapterTitle - $formattedTime',
        type: EditorTabType.backupPreview,
        isPreview: isPreview,
        backupFilePath: backupFilePath,
        originalChapterTitle: chapterTitle,
        originalBookUuid: bookUuid,
        originalVolumeName: volumeName,
        originalIsSetting: originalIsSetting,
      );

      if (isPreview) {
        // 当前标签页为预览模式的章节/设定时，固定该标签页，
        // 将历史版本预览作为新标签页打开，避免当前文档被替换
        final currentTab = this.currentTab;
        final shouldPinCurrent = currentTab != null &&
            currentTab.isPreview &&
            (currentTab.type == EditorTabType.chapter ||
                currentTab.type == EditorTabType.settings);

        if (shouldPinCurrent) {
          currentTab.isPreview = false;
          _openedTabs.add(tab);
          _currentTabIndex = _openedTabs.length - 1;
        } else {
          // 查找当前已有的预览标签页并替换
          final previewIndex = _openedTabs.indexWhere((t) => t.isPreview);
          if (previewIndex != -1) {
            final oldTab = _openedTabs[previewIndex];
            _disposeTabResources(oldTab);
            _openedTabs[previewIndex] = tab;
            _currentTabIndex = previewIndex;
          } else {
            _openedTabs.add(tab);
            _currentTabIndex = _openedTabs.length - 1;
          }
        }
      } else {
        // 非预览模式，直接添加新标签页
        _openedTabs.add(tab);
        _currentTabIndex = _openedTabs.length - 1;
      }
    }
    notifyListeners();
  }

  /// 释放标签页资源（停止备份计时器、保存光标位置、释放控制器）
  void _disposeTabResources(EditorTab tab) {
    // 停止备份计时器
    BackupService.instance.stopTabBackupTimer(tab.id);

    // 如果是章节标签页，保存光标位置到缓存
    if (tab.type == EditorTabType.chapter &&
        _currentBook != null &&
        tab.cursorPosition != null) {
      _saveChapterCursorPosition(tab);
    }

    // 释放资源
    tab.textController?.dispose();
    tab.chapterTitleController?.dispose();
    tab.undoManager?.dispose();
  }

  /// 关闭标签页
  ///
  /// 实现 [WorkspaceStateBase] 声明的协调方法，
  /// 供 [BookDataMixin] 在删除章节/设定时反向调用。
  @override
  void closeTab(String tabId) {
    final index = _openedTabs.indexWhere((t) => t.id == tabId);
    if (index == -1) return;

    final tab = _openedTabs.removeAt(index);

    // 释放标签页资源
    _disposeTabResources(tab);

    // 调整当前选中的标签页索引
    if (_openedTabs.isEmpty) {
      _currentTabIndex = -1;
    } else if (_currentTabIndex >= _openedTabs.length) {
      _currentTabIndex = _openedTabs.length - 1;
    } else if (_currentTabIndex > index) {
      _currentTabIndex--;
    }

    // 关闭标签页后，如果查找替换栏处于打开状态，在当前激活的标签页上刷新查找结果
    refreshFindIfVisible(resetIndex: true);

    notifyListeners();
  }

  /// 保存章节光标位置到缓存
  ///
  /// 在关闭章节标签页时调用，将当前光标位置保存到缓存文件
  Future<void> _saveChapterCursorPosition(EditorTab tab) async {
    if (_currentBook == null || tab.cursorPosition == null) return;

    try {
      await ChapterCursorCacheService.instance.saveCursorPosition(
        bookUuid: _currentBook!.uuid,
        chapterUuid: tab.id,
        offset: tab.cursorPosition!.baseOffset,
      );
    } catch (e) {
      debugPrint('保存章节光标位置失败: $e');
    }
  }

  /// 保存指定章节对应的标签页光标位置（若该标签页已打开）
  ///
  /// 实现 [WorkspaceStateBase] 声明的协调方法，
  /// 供 [BookDataMixin] 在保存章节内容后反向调用，
  /// 确保无论是手动保存还是自动保存都能持久化光标位置。
  @override
  Future<void> saveChapterCursorPositionIfAny(String chapterUuid) async {
    final tab =
        _openedTabs.where((t) => t.id == chapterUuid).firstOrNull;
    if (tab != null && tab.cursorPosition != null) {
      await _saveChapterCursorPosition(tab);
    }
  }

  /// 切换到指定标签页
  void switchToTab(int index) {
    if (index >= 0 && index < _openedTabs.length && _currentTabIndex != index) {
      // 在切换标签页之前，保存当前标签页的光标位置
      final currentTab = this.currentTab;
      if (currentTab != null &&
          currentTab.type == EditorTabType.chapter &&
          _currentBook != null &&
          currentTab.cursorPosition != null) {
        _saveChapterCursorPosition(currentTab);
      }

      _currentTabIndex = index;

      // 如果查找替换栏处于打开状态，尝试刷新查找结果
      refreshFindIfVisible(resetIndex: true);

      notifyListeners();
    }
  }

  /// 将预览模式的标签页转为固定状态（退出预览模式）
  void pinTab(String tabId) {
    final tab = _openedTabs.where((t) => t.id == tabId).firstOrNull;
    if (tab != null && tab.isPreview) {
      tab.isPreview = false;
      notifyListeners();
    }
  }

  /// 异步保存所有章节光标位置（主要用于应用关闭前）
  Future<void> saveAllCursorPositions() async {
    if (_currentBook == null) return;

    for (final tab in _openedTabs) {
      if (tab.type == EditorTabType.chapter && tab.cursorPosition != null) {
        await _saveChapterCursorPosition(tab);
      }
    }
  }

  /// 关闭所有标签页
  void closeAllTabs() {
    // 停止所有备份计时器
    BackupService.instance.stopAllBackupTimers();

    // 保存所有章节标签页的光标位置
    if (_currentBook != null) {
      for (final tab in _openedTabs) {
        if (tab.type == EditorTabType.chapter && tab.cursorPosition != null) {
          _saveChapterCursorPosition(tab);
        }
      }
    }

    for (final tab in _openedTabs) {
      tab.textController?.dispose();
      tab.undoManager?.dispose();
    }
    _openedTabs.clear();
    _currentTabIndex = -1;
    notifyListeners();
  }

  /// 关闭其他标签页
  void closeOtherTabs(String tabId) {
    final tabsToRemove = _openedTabs.where((t) => t.id != tabId).toList();

    // 停止被关闭标签页的备份计时器
    for (final tab in tabsToRemove) {
      BackupService.instance.stopTabBackupTimer(tab.id);
    }

    // 保存要关闭的章节标签页的光标位置
    if (_currentBook != null) {
      for (final tab in tabsToRemove) {
        if (tab.type == EditorTabType.chapter && tab.cursorPosition != null) {
          _saveChapterCursorPosition(tab);
        }
      }
    }

    for (final tab in tabsToRemove) {
      tab.textController?.dispose();
      tab.undoManager?.dispose();
    }
    _openedTabs.removeWhere((t) => t.id != tabId);
    _currentTabIndex = _openedTabs.isEmpty ? -1 : 0;
    notifyListeners();
  }

  /// 关闭已保存的标签页
  void closeSavedTabs() {
    final tabsToRemove = _openedTabs.where((t) => !t.isModified).toList();

    // 停止被关闭标签页的备份计时器
    for (final tab in tabsToRemove) {
      BackupService.instance.stopTabBackupTimer(tab.id);
    }

    // 保存要关闭的章节标签页的光标位置
    if (_currentBook != null) {
      for (final tab in tabsToRemove) {
        if (tab.type == EditorTabType.chapter && tab.cursorPosition != null) {
          _saveChapterCursorPosition(tab);
        }
      }
    }

    for (final tab in tabsToRemove) {
      tab.textController?.dispose();
      tab.undoManager?.dispose();
    }
    _openedTabs.removeWhere((t) => !t.isModified);
    if (_currentTabIndex >= _openedTabs.length) {
      _currentTabIndex = _openedTabs.isEmpty ? -1 : _openedTabs.length - 1;
    }
    notifyListeners();
  }

  /// 关闭指定标签页右侧的所有标签页
  void closeRightTabs(String tabId) {
    final index = _openedTabs.indexWhere((t) => t.id == tabId);
    if (index == -1) return;

    final tabsToRemove = _openedTabs.sublist(index + 1);

    // 停止被关闭标签页的备份计时器
    for (final tab in tabsToRemove) {
      BackupService.instance.stopTabBackupTimer(tab.id);
    }

    // 保存要关闭的章节标签页的光标位置
    if (_currentBook != null) {
      for (final tab in tabsToRemove) {
        if (tab.type == EditorTabType.chapter && tab.cursorPosition != null) {
          _saveChapterCursorPosition(tab);
        }
      }
    }

    for (final tab in tabsToRemove) {
      tab.textController?.dispose();
      tab.undoManager?.dispose();
    }
    _openedTabs.removeRange(index + 1, _openedTabs.length);
    // 如果当前选中的标签页被关闭了，调整索引
    if (_currentTabIndex > index) {
      _currentTabIndex = index;
    }
    notifyListeners();
  }

  /// 检查是否有未保存的标签页
  bool hasUnsavedTabs() {
    return _openedTabs.any((t) => t.isModified);
  }

  /// 获取未保存标签页的数量
  int unsavedTabsCount() {
    return _openedTabs.where((t) => t.isModified).length;
  }

  /// 重新排序标签页
  void reorderTabs(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final tab = _openedTabs.removeAt(oldIndex);
    _openedTabs.insert(newIndex, tab);

    // 更新当前选中的标签页索引
    if (_currentTabIndex == oldIndex) {
      _currentTabIndex = newIndex;
    } else if (_currentTabIndex > oldIndex && _currentTabIndex <= newIndex) {
      _currentTabIndex--;
    } else if (_currentTabIndex < oldIndex && _currentTabIndex >= newIndex) {
      _currentTabIndex++;
    }

    notifyListeners();
  }

  /// 通知标签页已修改（用于更新 UI）
  void notifyTabModified(String tabId) {
    // 首次修改时启动备份计时器
    _startBackupTimerIfNeeded(tabId);
    // 触发 UI 更新以显示修改标记
    notifyListeners();
  }

  /// 为指定标签页启动备份计时器
  ///
  /// 仅对章节和大纲类型的标签页生效，且仅在自动备份开启时启动
  void _startBackupTimerIfNeeded(String tabId) {
    if (!SettingsService.instance.autoBackupEnabled) return;
    if (_currentBook == null) return;

    final tab = _openedTabs.where((t) => t.id == tabId).firstOrNull;
    if (tab == null) return;

    // 章节类型：通过文本控制器获取内容
    if (tab.type == EditorTabType.chapter) {
      if (tab.textController == null) return;

      // 查找章节的分卷名
      final chapter = _chapters.where((c) => c.uuid == tab.id).firstOrNull;
      final volumeName = getVolumeName(chapter?.volumeUuid ?? '');

      BackupService.instance.startTabBackupTimer(
        tabId: tabId,
        bookUuid: _currentBook!.uuid,
        chapterTitle: tab.title,
        volumeName: volumeName,
        contentGetter: () => tab.textController!.text,
      );
      return;
    }

    // 设定类型：通过大纲编辑器状态获取序列化内容
    if (tab.type == EditorTabType.settings) {
      BackupService.instance.startTabBackupTimer(
        tabId: tabId,
        bookUuid: _currentBook!.uuid,
        chapterTitle: tab.title,
        volumeName: '',
        contentGetter: () {
          final state = tab.editorKey.currentState;
          if (state is OutlineEditorState) {
            return state.serializeToText();
          }
          return '';
        },
        isSetting: true,
      );
    }
  }

  /// 通知字数统计更新
  ///
  /// 当编辑器内容变化时调用，触发 UI 更新底部状态栏的字数显示
  void notifyWordCountUpdated() {
    notifyListeners();
  }

  // ================= 标签页保存方法 =================

  /// 保存当前标签页的内容
  ///
  /// 返回是否保存成功
  Future<bool> saveCurrentTab() async {
    final tab = currentTab;
    if (tab == null) return false;
    // 章节类型需要文本控制器；大纲类型使用编辑器状态，无需文本控制器
    if (tab.type == EditorTabType.chapter && tab.textController == null) {
      return false;
    }

    // 章节类型保存到文件
    if (tab.type == EditorTabType.chapter) {
      final chapter = _chapters.firstWhere(
        (c) => c.uuid == tab.id,
        orElse: () => throw Exception('找不到章节: ${tab.id}'),
      );

      // 更新章节标题
      final titleUpdated = await _updateChapterTitle(chapter, tab.title);
      if (!titleUpdated) return false;

      final content = tab.textController!.text;
      final success = await saveChapterContent(chapter, content);

      if (success) {
        tab.isModified = false;
        notifyListeners();
      }

      return success;
    }

    // 设定项类型保存到文件
    if (tab.type == EditorTabType.settings) {
      final item = _settingItems.firstWhere(
        (i) => i.uuid == tab.id,
        orElse: () => throw Exception('找不到设定项: ${tab.id}'),
      );

      // 从大纲编辑器状态获取序列化后的纯文本内容
      final outlineState = tab.editorKey.currentState;
      if (outlineState == null || outlineState is! OutlineEditorState) {
        return false;
      }
      final content = outlineState.serializeToText();

      // 更新设定项标题
      final titleUpdated =
          await renameSettingItem(itemUuid: item.uuid, newTitle: tab.title);
      if (!titleUpdated) return false;

      final success = await saveSettingItemContent(item, content);

      if (success) {
        tab.isModified = false;
        notifyListeners();
      }

      return success;
    }

    // 其他类型的标签页不支持保存
    return false;
  }

  /// 保存所有已修改的标签页
  ///
  /// 返回保存成功的数量
  Future<int> saveAllTabs() async {
    int savedCount = 0;

    for (final tab in _openedTabs) {
      if (!tab.isModified) continue;

      // 章节类型保存
      if (tab.type == EditorTabType.chapter && tab.textController != null) {
        try {
          final chapter = _chapters.firstWhere((c) => c.uuid == tab.id);

          // 更新章节标题
          final titleUpdated = await _updateChapterTitle(chapter, tab.title);
          if (!titleUpdated) continue;

          final content = tab.textController!.text;
          final success = await saveChapterContent(chapter, content);

          if (success) {
            tab.isModified = false;
            savedCount++;
          }
        } catch (e) {
          debugPrint('保存标签页失败: ${tab.title}, 错误: $e');
        }
      }

      // 大纲类型保存
      if (tab.type == EditorTabType.settings) {
        try {
          final item = _settingItems.firstWhere((i) => i.uuid == tab.id);

          // 从大纲编辑器状态获取序列化后的纯文本内容
          final outlineState = tab.editorKey.currentState;
          if (outlineState == null || outlineState is! OutlineEditorState) {
            continue;
          }
          final content = outlineState.serializeToText();

          // 更新设定项标题
          final titleUpdated =
              await renameSettingItem(itemUuid: item.uuid, newTitle: tab.title);
          if (!titleUpdated) continue;

          final success = await saveSettingItemContent(item, content);
          if (success) {
            tab.isModified = false;
            savedCount++;
          }
        } catch (e) {
          debugPrint('保存大纲标签页失败: ${tab.title}, 错误: $e');
        }
      }
    }

    if (savedCount > 0) {
      notifyListeners();
    }

    return savedCount;
  }

  // ================= 自动保存方法 =================

  /// 触发自动保存
  ///
  /// 在编辑器内容变化时调用，使用防抖机制避免频繁保存：
  /// 每次输入重置定时器，停止输入 1 秒后执行保存
  void triggerAutoSave() {
    // 同步更新会话追踪器的活动时间（用于码字时长活跃判定）
    _sessionTracker?.onActivity();

    if (!SettingsService.instance.autoSaveEnabled) return;

    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 1), () {
      _performAutoSave();
    });
  }

  /// 执行自动保存
  ///
  /// 保存所有已修改的标签页
  Future<void> _performAutoSave() async {
    if (_isDisposed) return;
    if (!SettingsService.instance.autoSaveEnabled) return;

    final modifiedTabs = _openedTabs.where((t) => t.isModified).toList();
    if (modifiedTabs.isEmpty) return;

    for (final tab in modifiedTabs) {
      // 章节类型自动保存
      if (tab.textController != null && tab.type == EditorTabType.chapter) {
        try {
          final chapter = _chapters.firstWhere((c) => c.uuid == tab.id);
          await _updateChapterTitle(chapter, tab.title);
          final content = tab.textController!.text;
          final success = await saveChapterContent(chapter, content);
          if (success) {
            tab.isModified = false;
          }
        } catch (e) {
          debugPrint('自动保存失败: ${tab.title}, 错误: $e');
        }
      }

      // 大纲类型自动保存
      if (tab.type == EditorTabType.settings) {
        try {
          final item = _settingItems.firstWhere((i) => i.uuid == tab.id);

          // 从大纲编辑器状态获取序列化后的纯文本内容
          final outlineState = tab.editorKey.currentState;
          if (outlineState == null || outlineState is! OutlineEditorState) {
            continue;
          }
          final content = outlineState.serializeToText();

          // 更新设定项标题
          await renameSettingItem(itemUuid: item.uuid, newTitle: tab.title);

          final success = await saveSettingItemContent(item, content);
          if (success) {
            tab.isModified = false;
          }
        } catch (e) {
          debugPrint('自动保存大纲失败: ${tab.title}, 错误: $e');
        }
      }
    }

    notifyListeners();
  }

  /// 立即执行自动保存（用于窗口关闭前等场景）
  ///
  /// 取消防抖定时器，直接执行保存
  Future<void> flushAutoSave() async {
    _autoSaveTimer?.cancel();
    await _performAutoSave();
  }

  // ================= 码字会话回调方法 =================

  /// 跨天回调：重置所有章节标签页的码字基线
  ///
  /// 新一天开始后，已打开章节的旧基线失效（昨日内容已成"旧内容"），
  /// 以当前字数重新作为基线，避免删除昨日内容被错误计入今日码字。
  void _onSessionDayChanged() {
    for (final tab in _openedTabs) {
      if (tab.type == EditorTabType.chapter) {
        tab.updateWordCount();
        tab.sessionBaselineWordCount = tab.wordCount;
        tab.recordedSessionWords = 0;
      }
    }
  }

  /// 持久化完成回调：统计写入数据库后通知首页/书架刷新
  ///
  /// 由 WritingSessionTracker 在字数或时长落库后触发。
  void _onSessionFlushed() {
    _notifyBookshelfRefresh();
  }

  /// 初始化码字会话追踪器
  ///
  /// 由 [WorkspaceProvider.initialize] 在书籍加载完成后调用，
  /// 加载今日码字数据并注册跨天与持久化回调。
  Future<void> _initSessionTracker() async {
    if (_currentBook == null) return;

    _sessionTracker = WritingSessionTracker();
    await _sessionTracker!.init(_currentBook!.uuid);
    // 注册跨天与持久化回调
    _sessionTracker!.onDayChanged = _onSessionDayChanged;
    _sessionTracker!.onFlushed = _onSessionFlushed;
  }

  // ================= 备份恢复方法 =================

  /// 从备份内容恢复当前标签页
  ///
  /// 章节类型：将内容写入文本控制器
  /// 大纲类型：将纯文本内容解析为大纲树结构
  /// 标记为已修改
  void restoreFromBackup(String content) {
    final tab = currentTab;
    if (tab == null) return;

    // 章节类型：通过文本控制器恢复
    if (tab.type == EditorTabType.chapter && tab.textController != null) {
      tab.textController!.text = content;
      tab.isModified = true;
      tab.textController!.selection =
          TextSelection.collapsed(offset: content.length);
      tab.updateWordCount();
      notifyListeners();
      return;
    }

    // 大纲类型：通过编辑器状态解析纯文本恢复
    if (tab.type == EditorTabType.settings) {
      final state = tab.editorKey.currentState;
      if (state is OutlineEditorState) {
        state.parseFromText(content);
        tab.isModified = true;
        notifyListeners();
      }
    }
  }

  /// 从备份恢复到指定章节/大纲（用于备份预览标签页的恢复操作）
  ///
  /// 查找原始章节或大纲标签页并替换其内容，如果标签页未打开则不执行操作
  void restoreBackupToChapter(String content, String chapterTitle) {
    // 优先查找匹配标题的章节标签页
    final chapterIndex = _openedTabs.indexWhere(
      (t) => t.type == EditorTabType.chapter && t.title == chapterTitle,
    );

    if (chapterIndex != -1) {
      final chapterTab = _openedTabs[chapterIndex];
      if (chapterTab.textController != null) {
        chapterTab.textController!.text = content;
        chapterTab.isModified = true;
        chapterTab.textController!.selection =
            TextSelection.collapsed(offset: content.length);
        chapterTab.updateWordCount();
      }

      // 如果当前标签页不是被恢复的章节，跳转到该标签页
      if (_currentTabIndex != chapterIndex) {
        _currentTabIndex = chapterIndex;
        refreshFindIfVisible(resetIndex: true);
      }
      notifyListeners();
      return;
    }

    // 未找到章节标签页时，查找匹配标题的大纲标签页
    final outlineIndex = _openedTabs.indexWhere(
      (t) => t.type == EditorTabType.settings && t.title == chapterTitle,
    );

    if (outlineIndex == -1) return;

    final outlineTab = _openedTabs[outlineIndex];
    final state = outlineTab.editorKey.currentState;
    if (state is OutlineEditorState) {
      state.parseFromText(content);
      outlineTab.isModified = true;
    }

    // 如果当前标签页不是被恢复的大纲，跳转到该标签页
    if (_currentTabIndex != outlineIndex) {
      _currentTabIndex = outlineIndex;
      refreshFindIfVisible(resetIndex: true);
    }

    notifyListeners();
  }

  // ================= 资源释放 =================

  /// 释放编辑器域持有的资源
  ///
  /// 由 [WorkspaceProvider.dispose] 调用，释放自动保存定时器、
  /// 会话追踪器、备份计时器与所有标签页资源。
  void disposeEditorResources() {
    // 取消自动保存定时器
    _autoSaveTimer?.cancel();

    // 释放码字会话追踪器（内部会 flush 剩余字数与时长）
    _sessionTracker?.dispose();

    // 停止所有备份计时器
    BackupService.instance.stopAllBackupTimers();

    // 释放所有标签页的资源（文本控制器、撤销管理器等）
    for (final tab in _openedTabs) {
      tab.textController?.dispose();
      tab.undoManager?.dispose();
    }
    _openedTabs.clear();
  }
}
