import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:re_editor/re_editor.dart';
import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:uuid/uuid.dart';
import 'package:window_manager/window_manager.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/models/volume.dart';
import 'package:quick_write/core/models/setting_group.dart';
import 'package:quick_write/core/models/setting_item.dart';
import 'package:quick_write/core/providers/writing_session_tracker.dart';
import 'package:quick_write/core/services/app_paths.dart';
import 'package:quick_write/core/services/database_service.dart';
import 'package:quick_write/core/services/backup_service.dart';
import 'package:quick_write/core/services/cloud_sync/cloud_sync_service.dart';
import 'package:quick_write/core/services/recycle_item_service.dart';
import 'package:quick_write/core/services/cache_services/chapter_cursor_cache_service.dart';
import 'package:quick_write/core/services/multi_window_service.dart';
import 'package:quick_write/core/services/cache_services/window_cache_service.dart';
import 'package:quick_write/core/services/workspace/book_folder_service.dart';
import 'package:quick_write/core/services/workspace/custom_highlight_service.dart';
import 'package:quick_write/core/services/workspace/volume_migration_service.dart';
import 'package:quick_write/core/utils/code_line_selection_utils.dart';
import 'package:quick_write/core/utils/find_replace_target.dart';
import 'package:quick_write/core/utils/re_editor_span_builder.dart';
import 'package:quick_write/core/utils/search_query_parser.dart';
import 'package:quick_write/core/utils/word_count_utils.dart';
import 'package:quick_write/pages/workspace/editor/novel_editor.dart';
import 'package:quick_write/pages/workspace/editor/outline_editor.dart';

part 'workspace/workspace_state_base.dart';
part 'workspace/book_data_mixin.dart';
part 'workspace/editor_mixin.dart';

/// 工作台状态管理 Provider
///
/// 通过组合 [BookDataMixin] 与 [EditorMixin] 实现职责分离，
/// 自身仅负责左右边栏、工具栏、窗口宽度等 UI 布局状态，
/// 以及初始化编排与统一资源释放。
class WorkspaceProvider extends WorkspaceStateBase
    with BookDataMixin, EditorMixin {
  // ================= 左侧边栏状态 =================

  /// 左侧边栏是否展开，从缓存文件读取
  bool _isLeftSidebarExpanded =
      WindowCacheService.instance.workspaceLeftSidebarExpanded;

  /// 左侧边栏当前选中的面板索引（0: 章节目录, 1: 设定）
  int _leftSidebarSelectedIndex = 0;

  /// 左侧边栏宽度，从缓存文件读取
  double _leftSidebarWidth =
      WindowCacheService.instance.workspaceLeftSidebarWidth;

  // ================= 右侧边栏状态 =================

  /// 右侧边栏是否展开（从缓存索引派生：-1 为关闭，否则为展开）
  bool _isRightSidebarExpanded =
      WindowCacheService.instance.workspaceRightSidebarTypeIndex >= 0;

  /// 右侧边栏宽度，从缓存文件读取
  double _rightSidebarWidth =
      WindowCacheService.instance.workspaceRightSidebarWidth;

  /// 右侧边栏当前显示的面板类型（从缓存索引恢复，越界时回退为 layout）
  RightSidebarType _rightSidebarType =
      WindowCacheService.instance.workspaceRightSidebarTypeIndex >= 0 &&
              WindowCacheService.instance.workspaceRightSidebarTypeIndex <
                  RightSidebarType.values.length
          ? RightSidebarType
              .values[WindowCacheService.instance.workspaceRightSidebarTypeIndex]
          : RightSidebarType.layout;

  // ================= 窗口宽度状态 =================

  /// 当前可用宽度（用于按比例限制边栏宽度，避免溢出）
  double _availableWidth = 1080.0;

  // ================= 上方工具栏状态 =================

  /// 上方工具栏是否展开，默认展开
  bool _isToolbarExpanded = true;

  // ================= 自定义高亮配置 =================

  /// 自定义高亮服务（按书籍独立加载，配置持久化到书籍根目录）
  final CustomHighlightService _customHighlightService = CustomHighlightService();

  // ================= Getters =================

  bool get isLeftSidebarExpanded => _isLeftSidebarExpanded;
  int get leftSidebarSelectedIndex => _leftSidebarSelectedIndex;
  double get leftSidebarWidth => _leftSidebarWidth;
  bool get isRightSidebarExpanded => _isRightSidebarExpanded;
  double get rightSidebarWidth => _rightSidebarWidth;
  RightSidebarType get rightSidebarType => _rightSidebarType;
  bool get isToolbarExpanded => _isToolbarExpanded;

  /// 获取自定义高亮服务
  CustomHighlightService get customHighlightService => _customHighlightService;

  // ================= 初始化方法 =================

  /// 初始化工作台
  /// [bookId] 书籍的 UUID
  /// [mainWindowId] 主窗口ID（用于向主窗口发送消息）
  /// [onBookSaved] 同窗口模式下的书籍保存回调（保存章节后通知书架刷新）
  Future<void> initialize(String bookId,
      {String? mainWindowId, VoidCallback? onBookSaved}) async {
    if (_isInitialized) return;

    // 保存主窗口ID和回调
    _mainWindowId = mainWindowId;
    _onBookSaved = onBookSaved;

    // 确保 AppPaths 已初始化
    if (!AppPaths.instance.isInitialized) {
      await AppPaths.instance.initialize();
    }

    // 打开数据库（已打开时复用现有实例）
    _isar = await DatabaseService.instance.open();

    // 初始化分卷数据迁移服务（依赖 Isar 与文件夹路径服务）
    _volumeMigrationService = VolumeMigrationService(_isar, _bookFolderService);

    // 初始化章节回收站服务（工作台窗口需要将删除的章节/设定项移入回收站）
    RecycleItemService.instance.initialize(_isar);

    // 根据 UUID 查询书籍
    _currentBook = await _isar.bookModels
        .where()
        .uuidEqualTo(bookId)
        .findFirst();

    // 设置窗口标题（任务栏显示）
    if (_currentBook != null) {
      final windowTitle = '《${_currentBook!.title}》 - ${GlobalConstants.appTitle}';
      await windowManager.setTitle(windowTitle);
    }

    // 加载书籍数据（章节、分卷、设定分组、设定项）
    await _loadChapters();
    await _loadVolumes();
    await _loadSettingGroups();
    await _loadSettingItems();

    // 首次迁移：将文件系统中的分卷目录迁移为数据库记录
    // 若执行了迁移，需重新加载分卷与章节数据
    if (await _volumeMigrationService.runIfNeeded(
      book: _currentBook!,
      volumes: _volumes,
      chapters: _chapters,
    )) {
      await _loadVolumes();
      await _loadChapters();
    }

    // 确保书籍文件夹结构完整（包括设定文件夹）
    await _bookFolderService.ensureBookFolderStructure(_currentBook!);

    // 加载自定义高亮配置（持久化在书籍根目录下）
    await _customHighlightService.load(bookFolderPath);

    _isInitialized = true;
    notifyListeners();

    // 初始化码字会话追踪器（加载今日码字数据，启动会话计时与时长追踪）
    await _initSessionTracker();

    // 通知主窗口工作台已就绪（多窗口模式下关闭主窗口的加载弹窗）
    if (_mainWindowId != null) {
      await MultiWindowService.instance.notifyWorkspaceReady(_mainWindowId!);
    }
  }

  // ================= 左侧边栏方法 =================

  /// 切换左侧边栏展开/收起
  void toggleLeftSidebar() {
    _isLeftSidebarExpanded = !_isLeftSidebarExpanded;
    _saveLeftSidebarExpandedState();
    notifyListeners();
  }

  /// 设置左侧边栏展开状态
  void setLeftSidebarExpanded(bool expanded) {
    if (_isLeftSidebarExpanded != expanded) {
      _isLeftSidebarExpanded = expanded;
      _saveLeftSidebarExpandedState();
      notifyListeners();
    }
  }

  /// 将左侧边栏展开状态保存到缓存文件
  void _saveLeftSidebarExpandedState() {
    WindowCacheService.instance
        .updateSidebarState(workspaceExpanded: _isLeftSidebarExpanded);
  }

  /// 设置左侧边栏选中的面板
  void setLeftSidebarSelectedIndex(int index) {
    if (_leftSidebarSelectedIndex != index) {
      _leftSidebarSelectedIndex = index;
      notifyListeners();
    }
  }

  /// 设置左侧边栏宽度
  void setLeftSidebarWidth(double width) {
    const minWidth = 240.0;
    final maxWidth = (_availableWidth * 0.4).clamp(minWidth, 500.0);
    final clampedWidth = width.clamp(minWidth, maxWidth);
    if (_leftSidebarWidth != clampedWidth) {
      _leftSidebarWidth = clampedWidth;
      _saveLeftSidebarWidth();
      notifyListeners();
    }
  }

  /// 将左侧边栏宽度保存到缓存文件
  void _saveLeftSidebarWidth() {
    WindowCacheService.instance.updateSidebarWidth(leftWidth: _leftSidebarWidth);
  }

  // ================= 右侧边栏方法 =================

  /// 设置右侧边栏类型并打开
  void openRightSidebar(RightSidebarType type) {
    _rightSidebarType = type;
    _isRightSidebarExpanded = true;
    _saveRightSidebarState();
    notifyListeners();
  }

  /// 关闭右侧边栏
  void closeRightSidebar() {
    _isRightSidebarExpanded = false;
    _saveRightSidebarState();
    notifyListeners();
  }

  /// 切换右侧边栏（如果已打开且类型相同则关闭，否则打开指定类型）
  void toggleRightSidebar(RightSidebarType type) {
    if (_isRightSidebarExpanded && _rightSidebarType == type) {
      // 当前已打开且类型相同，关闭侧边栏
      _isRightSidebarExpanded = false;
    } else {
      // 打开或切换到指定类型
      _rightSidebarType = type;
      _isRightSidebarExpanded = true;
    }
    _saveRightSidebarState();
    notifyListeners();
  }

  /// 将右侧边栏状态保存到缓存文件
  ///
  /// 展开时写入当前面板类型的枚举索引，关闭时写入 -1
  void _saveRightSidebarState() {
    final index = _isRightSidebarExpanded ? _rightSidebarType.index : -1;
    WindowCacheService.instance
        .updateSidebarState(workspaceRightSidebarTypeIndex: index);
  }

  /// 设置右侧边栏宽度
  void setRightSidebarWidth(double width) {
    const minWidth = 240.0;
    final maxWidth = (_availableWidth * 0.4).clamp(minWidth, 600.0);
    final clampedWidth = width.clamp(minWidth, maxWidth);
    if (_rightSidebarWidth != clampedWidth) {
      _rightSidebarWidth = clampedWidth;
      _saveRightSidebarWidth();
      notifyListeners();
    }
  }

  /// 将右侧边栏宽度保存到缓存文件
  void _saveRightSidebarWidth() {
    WindowCacheService.instance
        .updateSidebarWidth(rightWidth: _rightSidebarWidth);
  }

  // ================= 边栏宽度比例限制方法 =================

  /// 更新当前可用宽度，并在边栏超出比例限制时自动调整
  void updateAvailableWidth(double width) {
    if (_availableWidth == width) return;
    _availableWidth = width;
    _clampSidebarsIfNeeded();
  }

  /// 将边栏宽度限制到指定窗口宽度的 40% 以内
  /// 用于窗口取消最大化前，提前将边栏宽度调整到恢复后窗口的安全范围内
  void clampSidebarsToWidth(double windowWidth) {
    final maxSidebarWidth = windowWidth * 0.4;
    bool changed = false;

    _availableWidth = windowWidth;

    if (_leftSidebarWidth > maxSidebarWidth) {
      _leftSidebarWidth = maxSidebarWidth.clamp(240.0, maxSidebarWidth);
      _saveLeftSidebarWidth();
      changed = true;
    }

    if (_rightSidebarWidth > maxSidebarWidth) {
      _rightSidebarWidth = maxSidebarWidth.clamp(240.0, maxSidebarWidth);
      _saveRightSidebarWidth();
      changed = true;
    }

    if (changed) notifyListeners();
  }

  /// 内部方法：根据当前可用宽度检查并调整边栏
  void _clampSidebarsIfNeeded() {
    final maxSidebarWidth = _availableWidth * 0.4;
    bool changed = false;

    if (_leftSidebarWidth > maxSidebarWidth) {
      _leftSidebarWidth = maxSidebarWidth.clamp(240.0, double.infinity);
      _saveLeftSidebarWidth();
      changed = true;
    }

    if (_rightSidebarWidth > maxSidebarWidth) {
      _rightSidebarWidth = maxSidebarWidth.clamp(240.0, double.infinity);
      _saveRightSidebarWidth();
      changed = true;
    }

    if (changed) notifyListeners();
  }

  // ================= 工具栏方法 =================

  /// 切换工具栏展开/收起
  void toggleToolbar() {
    _isToolbarExpanded = !_isToolbarExpanded;
    notifyListeners();
  }

  /// 设置工具栏展开状态
  void setToolbarExpanded(bool expanded) {
    if (_isToolbarExpanded != expanded) {
      _isToolbarExpanded = expanded;
      notifyListeners();
    }
  }

  // ================= 资源释放 =================

  /// 释放资源
  ///
  /// 标记为已释放状态后，统一清理编辑器域持有的资源（自动保存定时器、
  /// 会话追踪器、备份计时器、所有标签页控制器），最后调用父类 dispose。
  @override
  void dispose() {
    // 标记为已释放，防止后续操作
    _isDisposed = true;

    // 释放编辑器域资源（含自动保存定时器、会话追踪器、备份计时器、标签页资源）
    disposeEditorResources();

    // 释放自定义高亮服务
    _customHighlightService.dispose();

    // 调用父类的 dispose 方法
    super.dispose();
  }
}

// ================= 工作台专属辅助类型 =================
//
// 以下类型仅服务于工作台（标签页、右侧边栏面板、全文搜索结果），
// 所有消费方都已 import workspace_provider.dart，故集中在此库内统一导出，
// 避免拆成零散小文件增加导航成本。

/// 编辑器标签页类型定义
///
/// 区分工作台中打开的不同标签页类型，决定标签页对应的编辑器与可执行操作。
enum EditorTabType {
  chapter,       // 章节正文
  settings,       // 设定（大纲、角色、其他设定等）
  backupPreview, // 备份预览（只读）
}

/// 编辑器标签页数据模型
///
/// 描述工作台多标签页中单个标签页的完整状态，包括标识、标题、
/// 编辑器控制器、字数统计、备份预览元数据等。
class EditorTab {
  /// 标签页唯一标识（章节ID或设定ID）
  final String id;

  // 为每个标签页创建一个专属的 GlobalKey
  final GlobalKey editorKey = GlobalKey();

  /// 标签页标题
  String title;

  /// 标签页类型（章节、大纲、角色设定等）
  final EditorTabType type;

  /// 标签页图标
  final IconData? icon;

  /// 是否已修改（用于显示未保存标记）
  bool isModified;

  /// 是否为预览模式标签页
  /// 预览模式下，再次单击其他章节/设定/备份预览会替换当前预览标签页
  /// 双击或编辑内容后退出预览模式，标签页转为固定状态
  bool isPreview;

  /// 是否被鼠标悬停
  bool isHovered;

  /// 光标位置（用于切换标签页时恢复光标）
  TextSelection? cursorPosition;

  /// 滚动位置（用于切换标签页时恢复滚动位置）
  double scrollOffset;

  /// 文本编辑控制器（保存光标位置、文本内容）
  ///
  /// 使用 re_editor 的行编辑控制器；对外交互通过扁平偏移量表示的选区进行，
  /// 由编辑器在选区变化时完成行模型与扁平偏移量之间的换算。
  CodeLineEditingController? textController;

  /// 章节标题编辑控制器
  TextEditingController? chapterTitleController;

  /// 行样式构建器（负责排版注入与高亮着色）
  ///
  /// 与 [textController] 一同创建，编辑器在构建时刷新其缓存并注入查找匹配。
  ReEditorSpanBuilder? spanBuilder;

  /// 当前字数
  int wordCount;

  /// 码字统计基线字数（章节加载完成时的字数，跨天时由工作台重置）
  ///
  /// 用于区分"今日新输入的内容"与"打开章节时已存在的旧内容"：
  /// 删除旧内容不会让今日码字为负，仅删除今日新输入的字才扣减。
  int sessionBaselineWordCount = 0;

  /// 已计入码字统计的 currentNet 值
  ///
  /// currentNet = max(0, wordCount - sessionBaselineWordCount)
  /// 每次编辑事件后同步更新为最新 currentNet，撤销/恢复时也同步以保持基线一致性。
  int recordedSessionWords = 0;

  /// 大纲主题数（仅大纲类型标签页使用，所有节点总数）
  int topicCount;

  /// 选中字数变化通知器
  ///
  /// 独立于 WorkspaceProvider 的全局 notifyListeners，
  /// 选区变化时只通知底部状态栏的字数显示局部重建，避免 EditorContainer 整体重建。
  final ValueNotifier<int> selectedWordCountNotifier = ValueNotifier<int>(0);

  /// 选中字数（读取通知器当前值，保留以兼容弹窗等读取场景）
  int get selectedWordCount => selectedWordCountNotifier.value;

  /// 选区字数统计防抖定时器（拖动选区时高频触发，合并计算避免阻塞 UI）
  Timer? _selectedWordCountTimer;

  /// 备份文件路径（仅备份预览类型使用）
  /// 同时也作为备份预览标签页的唯一标识依据
  final String? backupFilePath;

  /// 备份预览标签页对应的原始章节标题（不含时间后缀）
  final String? originalChapterTitle;

  /// 备份预览标签页对应的原始书籍 UUID
  final String? originalBookUuid;

  /// 备份预览标签页对应的原始分卷名
  final String? originalVolumeName;

  /// 备份预览标签页对应的原始内容是否为设定类型
  /// true 表示原始标签页是设定，false 表示章节
  final bool originalIsSetting;

  EditorTab({
    required this.id,
    required this.title,
    required this.type,
    this.icon,
    this.isModified = false,
    this.isPreview = false,
    this.isHovered = false,
    this.scrollOffset = 0.0,
    this.textController,
    this.chapterTitleController,
    this.spanBuilder,
    this.wordCount = 0,
    this.topicCount = 0,
    this.backupFilePath,
    this.originalChapterTitle,
    this.originalBookUuid,
    this.originalVolumeName,
    this.originalIsSetting = false,
  });

  /// 是否为只读标签页
  bool get isReadOnly => type == EditorTabType.backupPreview;

  /// 是否支持查找替换（只读标签页只支持查找，不支持替换）
  bool get canReplace => type != EditorTabType.backupPreview;

  /// 是否使用大纲编辑器（设定项或大纲备份预览）
  bool get usesOutlineEditor =>
      type == EditorTabType.settings ||
      (type == EditorTabType.backupPreview && originalIsSetting);

  /// 更新字数统计
  void updateWordCount() {
    if (textController != null) {
      wordCount = WordCountUtils.countWords(textController!.text);
    }
  }

  /// 更新选中字数统计（防抖）
  ///
  /// 拖动选区时该回调高频触发，延迟 10ms 合并计算：
  /// 选区在 10ms 内持续变化则不断推迟计算，直至稳定后才执行一次字数统计，
  /// 并通过 [selectedWordCountNotifier] 通知底部状态栏局部刷新。
  void updateSelectedWordCountDebounced() {
    if (textController == null) return;
    _selectedWordCountTimer?.cancel();
    _selectedWordCountTimer = Timer(const Duration(milliseconds: 10), () {
      final controller = textController!;
      final selection = CodeLineSelectionUtils.flatSelectionOf(controller.text, controller.selection);
      if (selection.baseOffset != selection.extentOffset) {
        // 有选中内容：统计选区文本字数
        final selectedText = controller.text.substring(
          selection.start,
          selection.end,
        );
        selectedWordCountNotifier.value = WordCountUtils.countWords(selectedText);
      } else {
        // 没有选中内容：清零
        selectedWordCountNotifier.value = 0;
      }
    });
  }

  /// 获取默认图标
  IconData get defaultIcon {
    switch (type) {
      case EditorTabType.chapter:
        return Icons.description_outlined;
      case EditorTabType.settings:
        return Icons.format_list_bulleted;
      case EditorTabType.backupPreview:
        return Icons.history_outlined;
    }
  }

  /// 释放资源
  void dispose() {
    textController?.dispose();
    chapterTitleController?.dispose();
    _selectedWordCountTimer?.cancel();
    selectedWordCountNotifier.dispose();
  }
}

/// 右侧边栏面板类型定义
///
/// 标识右侧边栏当前展示的面板类型，用于面板切换与缓存恢复。
enum RightSidebarType {
  layout,    // 布局设置
  typeset,   // 排版设置
  other,     // 其他设置
  search,    // 全文搜索
  history,   // 历史版本
  tools,     // 工具
}

/// 全文搜索匹配行信息
class GlobalSearchMatchLine {
  /// 行号（从1开始）
  final int lineNumber;

  /// 行内容
  final String lineContent;

  /// 该行中的匹配次数
  final int matchCount;

  /// 该行在全文中的起始偏移量
  final int startOffset;

  const GlobalSearchMatchLine({
    required this.lineNumber,
    required this.lineContent,
    required this.matchCount,
    required this.startOffset,
  });
}

/// 全文搜索结果（按章节分组）
class GlobalSearchResult {
  /// 章节 UUID
  final String chapterUuid;

  /// 章节标题
  final String chapterTitle;

  /// 卷名
  final String volumeName;

  /// 该章节中的总匹配数
  final int totalMatches;

  /// 匹配行列表
  final List<GlobalSearchMatchLine> matchLines;

  const GlobalSearchResult({
    required this.chapterUuid,
    required this.chapterTitle,
    required this.volumeName,
    required this.totalMatches,
    required this.matchLines,
  });
}