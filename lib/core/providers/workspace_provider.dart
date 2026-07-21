import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:uuid/uuid.dart';
import 'package:window_manager/window_manager.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/models/volume.dart';
import 'package:quick_write/core/models/setting_group.dart';
import 'package:quick_write/core/models/setting_item.dart';
import 'package:quick_write/core/models/writing_stat.dart';
import 'package:quick_write/core/models/recycle_item.dart';
import 'package:quick_write/core/providers/writing_session_tracker.dart';
import 'package:quick_write/core/services/app_paths.dart';
import 'package:quick_write/core/services/backup_service.dart';
import 'package:quick_write/core/services/recycle_item_service.dart';
import 'package:quick_write/core/services/cache_services/chapter_cursor_cache_service.dart';
import 'package:quick_write/core/services/multi_window_service.dart';
import 'package:quick_write/core/services/cache_services/window_cache_service.dart';
import 'package:quick_write/core/utils/editor_undo_manager.dart';
import 'package:quick_write/core/utils/find_replace_target.dart';
import 'package:quick_write/core/utils/word_count_utils.dart';
import 'package:quick_write/pages/workspace/editor/novel_editor.dart';
import 'package:quick_write/pages/workspace/editor/outline_editor.dart';

/// 工作台状态管理 Provider
/// 
/// 管理工作台页面的所有状态：书籍数据、书籍状态、侧边栏展开状态、宽度、类型等、标签页、工具栏等
class WorkspaceProvider extends ChangeNotifier {
  // ================= 书籍数据 =================
  
  /// 是否已被释放（防止在 dispose 后继续调用方法导致报错）
  bool _isDisposed = false;
  
  /// Isar 数据库实例
  late Isar _isar;
  
  /// 当前书籍
  BookModel? _currentBook;
  
  /// 是否已初始化
  bool _isInitialized = false;
  
  /// 当前书籍的章节列表
  List<ChapterModel> _chapters = [];
  
  /// 当前书籍的分卷列表
  List<VolumeModel> _volumes = [];
  
  /// 当前书籍的设定分组列表
  List<SettingGroupModel> _settingGroups = [];
  
  /// 当前书籍的设定项列表
  List<SettingItemModel> _settingItems = [];
  
  /// 获取当前书籍
  BookModel? get currentBook => _currentBook;
  
  /// 获取当前书籍标题
  String get bookTitle => _currentBook?.title ?? '未知书籍';
  
  /// 是否已初始化
  bool get isInitialized => _isInitialized;
  
  /// 获取章节列表
  List<ChapterModel> get chapters => List.unmodifiable(_chapters);
  
  /// 获取分卷列表（按 orderIndex 排序）
  List<VolumeModel> get volumes => List.unmodifiable(_volumes);
  
  /// 获取设定分组列表（按 orderIndex 排序）
  List<SettingGroupModel> get settingGroups => List.unmodifiable(_settingGroups);
  
  /// 获取设定项列表
  List<SettingItemModel> get settingItems => List.unmodifiable(_settingItems);
  
  // ================= 左侧边栏状态 =================
  
  /// 左侧边栏是否展开，从缓存文件读取
  bool _isLeftSidebarExpanded = WindowCacheService.instance.workspaceLeftSidebarExpanded;
  
  /// 左侧边栏当前选中的面板索引（0: 章节目录, 1: 设定）
  int _leftSidebarSelectedIndex = 0;
  
  /// 左侧边栏宽度，从缓存文件读取
  double _leftSidebarWidth = WindowCacheService.instance.workspaceLeftSidebarWidth;
  
  // ================= 右侧边栏状态 =================

  /// 右侧边栏是否展开（从缓存索引派生：-1 为关闭，否则为展开）
  bool _isRightSidebarExpanded = WindowCacheService.instance.workspaceRightSidebarTypeIndex >= 0;

  /// 右侧边栏宽度，从缓存文件读取
  double _rightSidebarWidth = WindowCacheService.instance.workspaceRightSidebarWidth;

  /// 右侧边栏当前显示的面板类型（从缓存索引恢复，越界时回退为 layout）
  RightSidebarType _rightSidebarType = WindowCacheService.instance.workspaceRightSidebarTypeIndex >= 0 &&
      WindowCacheService.instance.workspaceRightSidebarTypeIndex < RightSidebarType.values.length
      ? RightSidebarType.values[WindowCacheService.instance.workspaceRightSidebarTypeIndex]
      : RightSidebarType.layout;
  
  // ================= 窗口宽度状态 =================
  
  /// 当前可用宽度（用于按比例限制边栏宽度，避免溢出）
  double _availableWidth = 1080.0;
  
  // ================= 上方工具栏状态 =================
  
  /// 上方工具栏是否展开，默认展开
  bool _isToolbarExpanded = true;

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
  
  /// 主窗口ID（用于向主窗口发送消息）
  String? _mainWindowId;
  
  /// 同窗口模式下的书籍保存回调（保存章节后通知书架刷新）
  VoidCallback? _onBookSaved;
  
  /// 打开的标签页列表
  final List<EditorTab> _openedTabs = [];
  
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
  
  bool get isLeftSidebarExpanded => _isLeftSidebarExpanded;
  int get leftSidebarSelectedIndex => _leftSidebarSelectedIndex;
  double get leftSidebarWidth => _leftSidebarWidth;
  bool get isRightSidebarExpanded => _isRightSidebarExpanded;
  double get rightSidebarWidth => _rightSidebarWidth;
  RightSidebarType get rightSidebarType => _rightSidebarType;
  bool get isToolbarExpanded => _isToolbarExpanded;
  bool get isFindReplaceVisible => _isFindReplaceVisible;
  String get findText => _findText;
  String get replaceText => _replaceText;
  bool get findCaseSensitive => _findCaseSensitive;
  bool get showReplace => _showReplace;
  List<TextSelection> get findMatches => List.unmodifiable(_findMatches);
  int get currentMatchIndex => _currentMatchIndex;
  String get globalSearchQuery => _globalSearchQuery;
  bool get globalSearchCaseSensitive => _globalSearchCaseSensitive;
  List<GlobalSearchResult> get globalSearchResults => List.unmodifiable(_globalSearchResults);
  bool get isGlobalSearching => _isGlobalSearching;

  /// 查找替换栏显示时，编辑器需要预留的顶边距高度
  double get findReplaceBarPadding {
    if (!_isFindReplaceVisible) return 0.0;
    // 替换区域展开时高度更大（两行），收起时仅查找行（单行）
    return _showReplace ? 88.0 : 48.0;
  }

  /// 当前匹配的序号（从1开始，0表示尚未定位，显示为?）
  int get currentMatchDisplayIndex => _findMatches.isEmpty || _currentMatchIndex < 0 ? 0 : _currentMatchIndex + 1;

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
  
  // ================= 初始化方法 =================
  
  /// 初始化工作台
  /// [bookId] 书籍的 UUID
  /// [mainWindowId] 主窗口ID（用于向主窗口发送消息）
  /// [onBookSaved] 同窗口模式下的书籍保存回调（保存章节后通知书架刷新）
  Future<void> initialize(String bookId, {String? mainWindowId, VoidCallback? onBookSaved}) async {
    if (_isInitialized) return;
    
    // 保存主窗口ID和回调
    _mainWindowId = mainWindowId;
    _onBookSaved = onBookSaved;
    
    // 确保 AppPaths 已初始化
    if (!AppPaths.instance.isInitialized) {
      await AppPaths.instance.initialize();
    }
    
    // 打开 Isar 数据库
    // 尝试获取已存在的 Isar 实例，避免重复打开数据库
    _isar = Isar.getInstance(AppPaths.instance.databaseName) ?? await Isar.open(
      [BookModelSchema, ChapterModelSchema, VolumeModelSchema, SettingGroupModelSchema, SettingItemModelSchema, WritingStatModelSchema, RecycleItemModelSchema],
      directory: AppPaths.instance.databaseDirectory,
      name: AppPaths.instance.databaseName,
    );

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
    
    // 加载章节列表
    await _loadChapters();
    
    // 加载分卷列表
    await _loadVolumes();
    
    // 加载设定分组列表
    await _loadSettingGroups();
    
    // 加载设定项列表
    await _loadSettingItems();
    
    // 首次迁移：将文件系统中的分卷目录迁移为数据库记录
    await _migrateVolumesFromFileSystem();
    
    // 确保书籍文件夹结构完整（包括设定文件夹）
    await _ensureBookFolderStructure();
    
    _isInitialized = true;
    notifyListeners();

    // 初始化码字会话追踪器（加载今日码字数据，启动会话计时与时长追踪）
    if (_currentBook != null) {
      _sessionTracker = WritingSessionTracker();
      await _sessionTracker!.init(_currentBook!.uuid);
      // 注册跨天与持久化回调
      _sessionTracker!.onDayChanged = _onSessionDayChanged;
      _sessionTracker!.onFlushed = _onSessionFlushed;
    }

    // 通知主窗口工作台已就绪（多窗口模式下关闭主窗口的加载弹窗）
    if (_mainWindowId != null) {
      await MultiWindowService.instance.notifyWorkspaceReady(_mainWindowId!);
    }
  }
  
  /// 加载当前书籍的章节列表
  Future<void> _loadChapters() async {
    if (_currentBook == null) return;
    
    _chapters = await _isar.chapterModels
        .where()
        .bookUuidEqualTo(_currentBook!.uuid)
        .sortByOrderIndex()
        .findAll();
    
    debugPrint('已加载 ${_chapters.length} 个章节');
  }
  
  /// 加载当前书籍的分卷列表
  Future<void> _loadVolumes() async {
    if (_currentBook == null) return;
    
    _volumes = await _isar.volumeModels
        .where()
        .bookUuidEqualTo(_currentBook!.uuid)
        .sortByOrderIndex()
        .findAll();
    
    debugPrint('已加载 ${_volumes.length} 个分卷');
  }
  
  /// 加载当前书籍的设定分组列表
  Future<void> _loadSettingGroups() async {
    if (_currentBook == null) return;
    
    _settingGroups = await _isar.settingGroupModels
        .where()
        .bookUuidEqualTo(_currentBook!.uuid)
        .sortByOrderIndex()
        .findAll();
    
    debugPrint('已加载 ${_settingGroups.length} 个设定分组');
  }
  
  /// 加载当前书籍的设定项列表
  Future<void> _loadSettingItems() async {
    if (_currentBook == null) return;
    
    _settingItems = await _isar.settingItemModels
        .where()
        .bookUuidEqualTo(_currentBook!.uuid)
        .sortByOrderIndex()
        .findAll();
    
    debugPrint('已加载 ${_settingItems.length} 个设定项');
  }
  
  /// 从文件系统迁移分卷数据到数据库
  /// 仅在数据库中无分卷记录时执行（首次迁移）
  Future<void> _migrateVolumesFromFileSystem() async {
    if (_currentBook == null) return;
    
    // 如果数据库中已有分卷记录，跳过迁移
    if (_volumes.isNotEmpty) return;
    
    // 扫描文件系统中的分卷目录
    final chaptersDir = Directory('$bookFolderPath${Platform.pathSeparator}chapters');
    if (!chaptersDir.existsSync()) return;
    
    final dirNames = <String>[];
    for (final entity in chaptersDir.listSync()) {
      if (entity is Directory) {
        dirNames.add(entity.uri.pathSegments.where((s) => s.isNotEmpty).last);
      }
    }
    
    if (dirNames.isEmpty) return;
    
    // 为每个分卷目录创建数据库记录
    final newVolumes = <VolumeModel>[];
    final volumeNameToUuid = <String, String>{};
    for (int i = 0; i < dirNames.length; i++) {
      final volumeName = dirNames[i];
      final volumeUuid = const Uuid().v4();
      
      final volume = VolumeModel()
        ..uuid = volumeUuid
        ..bookUuid = _currentBook!.uuid
        ..name = volumeName
        ..orderIndex = i
        ..createdAt = DateTime.now()
        ..updatedAt = DateTime.now();
      
      newVolumes.add(volume);
      volumeNameToUuid[volumeName] = volumeUuid;
    }
    
    // 根据章节的 filePath 判断其所属分卷，设置 volumeUuid
    // filePath 格式："分卷名/章节名.txt" 或 "章节名.txt"
    for (final chapter in _chapters) {
      if (chapter.filePath.contains(Platform.pathSeparator)) {
        final pathParts = chapter.filePath.split(Platform.pathSeparator);
        final dirName = pathParts.first;
        if (volumeNameToUuid.containsKey(dirName)) {
          chapter.volumeUuid = volumeNameToUuid[dirName]!;
        }
      }
    }
    
    // 批量写入数据库
    await _isar.writeTxn(() async {
      for (final volume in newVolumes) {
        await _isar.volumeModels.put(volume);
      }
      for (final chapter in _chapters) {
        if (chapter.volumeUuid.isNotEmpty) {
          await _isar.chapterModels.put(chapter);
        }
      }
    });
    
    // 重新加载
    await _loadVolumes();
    await _loadChapters();
    
    debugPrint('已从文件系统迁移 ${newVolumes.length} 个分卷到数据库');
  }
  
  /// 确保书籍文件夹结构完整
  /// - 检查书籍文件夹是否存在
  /// - 检查 chapters 文件夹是否存在
  /// - 检查 settings 文件夹是否存在（如不存在则创建）
  Future<void> _ensureBookFolderStructure() async {
    if (_currentBook == null) return;
    
    try {
      final worksPath = await AppPaths.instance.getBooksPath();
      final bookFolderPath = '$worksPath${Platform.pathSeparator}${_currentBook!.title}';
      
      // 检查书籍文件夹
      final bookDir = Directory(bookFolderPath);
      if (!await bookDir.exists()) {
        await bookDir.create(recursive: true);
        debugPrint('已创建书籍文件夹: $bookFolderPath');
      }
      
      // 检查 chapters 文件夹
      final chaptersPath = '$bookFolderPath${Platform.pathSeparator}chapters';
      final chaptersDir = Directory(chaptersPath);
      if (!await chaptersDir.exists()) {
        await chaptersDir.create(recursive: true);
        debugPrint('已创建章节文件夹: $chaptersPath');
      }
      
      // 检查 settings 文件夹（设定文件夹）
      final settingsPath = '$bookFolderPath${Platform.pathSeparator}settings';
      final settingsDir = Directory(settingsPath);
      if (!await settingsDir.exists()) {
        await settingsDir.create(recursive: true);
        debugPrint('已创建设定文件夹: $settingsPath');
      }
    } catch (e) {
      debugPrint('确保书籍文件夹结构失败: $e');
    }
  }
  
  /// 获取书籍文件夹路径
  String get bookFolderPath {
    if (_currentBook == null) return '';
    // 这里使用同步方式获取路径，因为 AppPaths 已经初始化
    final worksPath = '${AppPaths.instance.appRootPath}${Platform.pathSeparator}works';
    return '$worksPath${Platform.pathSeparator}${_currentBook!.title}';
  }
  
  /// 获取章节文件的完整路径
  String getChapterFilePath(ChapterModel chapter) {
    return '$bookFolderPath${Platform.pathSeparator}chapters${Platform.pathSeparator}${chapter.filePath}';
  }

  /// 获取标签页对应的文件路径
  ///
  /// 仅章节类型和备份预览类型返回有效路径，其他类型返回 null
  String? getTabFilePath(EditorTab tab) {
    switch (tab.type) {
      case EditorTabType.chapter:
        try {
          final chapter = _chapters.firstWhere((c) => c.uuid == tab.id);
          return getChapterFilePath(chapter);
        } catch (_) {
          return null;
        }
      case EditorTabType.settings:
        try {
          final item = _settingItems.firstWhere((i) => i.uuid == tab.id);
          return getSettingItemFilePath(item);
        } catch (_) {
          return null;
        }
      case EditorTabType.backupPreview:
        return tab.backupFilePath;
    }
  }
  
  /// 读取章节文件内容
  Future<String> readChapterContent(ChapterModel chapter) async {
    try {
      final filePath = getChapterFilePath(chapter);
      final file = File(filePath);
      
      if (!await file.exists()) {
        debugPrint('章节文件不存在: $filePath');
        return '';
      }
      
      return await file.readAsString();
    } catch (e) {
      debugPrint('读取章节文件失败: $e');
      return '';
    }
  }
  
  /// 保存章节内容到文件
  /// [chapter] 章节模型
  /// [content] 章节内容
  /// 返回是否保存成功
  Future<bool> saveChapterContent(ChapterModel chapter, String content) async {
    try {
      final filePath = getChapterFilePath(chapter);
      final file = File(filePath);
      
      // 确保父目录存在
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      
      // 写入文件
      await file.writeAsString(content);

      // 计算字数
      final wordCount = WordCountUtils.countWords(content);

      // 更新数据库中的字数和修改时间
      chapter.wordCount = wordCount;
      chapter.updatedAt = DateTime.now();

      await _isar.writeTxn(() async {
        await _isar.chapterModels.put(chapter);

        // 更新书籍总字数
        if (_currentBook != null) {
          // 计算所有章节的总字数
          final allChapters = await _isar.chapterModels
              .where()
              .bookUuidEqualTo(_currentBook!.uuid)
              .findAll();
          final totalWordCount = allChapters.fold<int>(
            0,
            (sum, c) => sum + c.wordCount,
          );

          _currentBook!.wordCount = totalWordCount;
          _currentBook!.updatedAt = DateTime.now();
          await _isar.bookModels.put(_currentBook!);
        }
      });

      // 刷新章节列表
      await _loadChapters();
      
      // 通知刷新书架（更新最近编辑显示）
      // 两种模式二选一：独立窗口走 MultiWindowService 通信，同窗口走回调
      if (_mainWindowId != null) {
        // 独立窗口模式：通过窗口间消息通知主窗口
        await MultiWindowService.instance.notifyBookUpdated(_mainWindowId!);
      } else if (_onBookSaved != null) {
        // 同窗口模式：直接调用回调通知 BookshelfProvider 刷新
        _onBookSaved!();
      }
      
      debugPrint('章节保存成功: ${chapter.title}, 字数: $wordCount');
      
      // 保存当前章节的光标位置到缓存（用于下次打开时恢复）
      final currentTab = _openedTabs.where((t) => t.id == chapter.uuid).firstOrNull;
      if (currentTab != null && currentTab.cursorPosition != null) {
        await _saveChapterCursorPosition(currentTab);
      }
      
      return true;
    } catch (e) {
      debugPrint('保存章节文件失败: $e');
      return false;
    }
  }
  
  
  /// 清理文件名中的非法字符
  String _sanitizeFileName(String fileName) {
    // 移除 Windows 文件名中不允许的字符: \ / : * ? " < > |
    return fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  /// 更新章节标题
  /// 返回是否更新成功
  Future<bool> _updateChapterTitle(ChapterModel chapter, String newTitle) async {
    // 检查章节标题是否发生了变化
    if (chapter.title == newTitle) return true;
    
    // 保存旧的文件路径
    final oldFilePath = getChapterFilePath(chapter);
    
    // 保存旧标题用于重命名备份目录
    final oldTitle = chapter.title;

    // 更新章节标题
    chapter.title = newTitle;
    chapter.updatedAt = DateTime.now();
    
    // 生成新的文件路径
    String newRelativePath;
    final volumeName = getVolumeName(chapter.volumeUuid);
    if (volumeName.isNotEmpty) {
      newRelativePath = '${_sanitizeFileName(volumeName)}${Platform.pathSeparator}${_sanitizeFileName(chapter.title)}${GlobalConstants.chapterFileExtension}';
    } else {
      newRelativePath = '${_sanitizeFileName(chapter.title)}${GlobalConstants.chapterFileExtension}';
    }
    chapter.filePath = newRelativePath;
    
    // 生成新的完整文件路径
    final newFilePath = getChapterFilePath(chapter);
    
    // 重命名文件
    try {
      final oldFile = File(oldFilePath);
      if (await oldFile.exists()) {
        final newFile = File(newFilePath);
        // 确保新文件的父目录存在
        final parentDir = newFile.parent;
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }
        // 重命名文件
        await oldFile.rename(newFilePath);
      }
    } catch (e) {
      debugPrint('重命名章节文件失败: $e');
      return false;
    }

    // 重命名备份目录
    if (_currentBook != null) {
      await BackupService.instance.renameChapterBackupDir(
        bookUuid: _currentBook!.uuid,
        oldChapterTitle: oldTitle,
        newChapterTitle: newTitle,
        volumeName: getVolumeName(chapter.volumeUuid),
      );
    }

    // 更新备份计时器中的章节标题
    BackupService.instance.updateTabBackupInfo(
      tabId: chapter.uuid,
      chapterTitle: newTitle,
    );
    
    // 更新数据库中的章节标题和文件路径
    await _isar.writeTxn(() async {
      await _isar.chapterModels.put(chapter);
    });
    
    // 刷新章节列表
    await _loadChapters();
    
    return true;
  }

  /// 新建章节
  /// [title] 章节标题
  /// [volumeUuid] 分卷 UUID，空字符串表示无分卷
  /// 返回新建的章节模型，失败返回 null
  Future<ChapterModel?> addChapter({
    required String title,
    String volumeUuid = '',
  }) async {
    if (_currentBook == null) return null;

    // 检查同一分卷下是否已存在同名章节
    final existing = _chapters.where(
      (c) => c.title == title && c.volumeUuid == volumeUuid,
    );
    if (existing.isNotEmpty) return null;

    // 计算排序序号
    final globalMaxOrder = _chapters.fold<int>(0, (max, c) => c.orderIndex > max ? c.orderIndex : max);
    final volumeChapters = _chapters.where((c) => c.volumeUuid == volumeUuid).toList();
    final volumeMaxOrder = volumeChapters.fold<int>(0, (max, c) => c.volumeOrderIndex > max ? c.volumeOrderIndex : max);

    // 生成文件路径
    String filePath;
    final volumeName = getVolumeName(volumeUuid);
    if (volumeName.isNotEmpty) {
      filePath = '${_sanitizeFileName(volumeName)}${Platform.pathSeparator}${_sanitizeFileName(title)}${GlobalConstants.chapterFileExtension}';
    } else {
      filePath = '${_sanitizeFileName(title)}${GlobalConstants.chapterFileExtension}';
    }

    // 创建章节模型
    final chapter = ChapterModel()
      ..uuid = const Uuid().v4()
      ..bookUuid = _currentBook!.uuid
      ..title = title
      ..volumeUuid = volumeUuid
      ..orderIndex = globalMaxOrder + 1
      ..volumeOrderIndex = volumeMaxOrder + 1
      ..wordCount = 0
      ..filePath = filePath
      ..createdAt = DateTime.now()
      ..updatedAt = DateTime.now();

    // 创建章节文件
    try {
      final fullPath = getChapterFilePath(chapter);
      final file = File(fullPath);
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      // 根据首行缩进设置写入初始内容
      final initialContent = SettingsService.instance.isFirstLineIndentEnabled ? '\u{3000}\u{3000}' : '';
      await file.writeAsString(initialContent);
    } catch (e) {
      debugPrint('创建章节文件失败: $e');
      return null;
    }

    // 写入数据库
    await _isar.writeTxn(() async {
      await _isar.chapterModels.put(chapter);

      // 更新书籍修改时间
      if (_currentBook != null) {
        _currentBook!.updatedAt = DateTime.now();
        await _isar.bookModels.put(_currentBook!);
      }
    });

    // 刷新章节列表
    await _loadChapters();

    // 通知刷新书架（更新最近编辑显示）
    if (_mainWindowId != null) {
      await MultiWindowService.instance.notifyBookUpdated(_mainWindowId!);
    } else if (_onBookSaved != null) {
      _onBookSaved!();
    }

    notifyListeners();

    return chapter;
  }

  /// 重命名章节
  /// [chapterUuid] 章节UUID
  /// [newTitle] 新标题
  /// 返回是否重命名成功
  Future<bool> renameChapter({
    required String chapterUuid,
    required String newTitle,
  }) async {
    final chapter = _chapters.where((c) => c.uuid == chapterUuid).firstOrNull;
    if (chapter == null) return false;

    // 检查同一分卷下是否已存在同名章节
    final existing = _chapters.where(
      (c) => c.title == newTitle && c.volumeUuid == chapter.volumeUuid && c.uuid != chapterUuid,
    );
    if (existing.isNotEmpty) return false;

    final success = await _updateChapterTitle(chapter, newTitle);
    if (success) {
      // 同步更新已打开标签页的标题和标题输入框
      final tab = _openedTabs.where((t) => t.id == chapterUuid).firstOrNull;
      if (tab != null) {
        tab.title = newTitle;
        if (tab.chapterTitleController != null) {
          tab.chapterTitleController!.text = newTitle;
        }
        notifyListeners();
      }
    }
    return success;
  }

  /// 删除章节
  /// [chapterUuid] 章节UUID
  /// 返回是否删除成功
  Future<bool> deleteChapter({required String chapterUuid}) async {
    if (_currentBook == null) return false;

    final chapter = _chapters.where((c) => c.uuid == chapterUuid).firstOrNull;
    if (chapter == null) return false;

    // 关闭该章节的标签页（如果已打开）
    final tabIndex = _openedTabs.indexWhere((t) => t.id == chapterUuid);
    if (tabIndex != -1) {
      closeTab(chapterUuid);
    }

    // 将章节移入回收站
    final volumeName = getVolumeName(chapter.volumeUuid);
    await RecycleItemService.instance.moveChapterToRecycleBin(
      chapter: chapter,
      bookTitle: _currentBook!.title,
      volumeName: volumeName,
      chapterFilePath: getChapterFilePath(chapter),
    );

    // 删除章节备份目录
    try {
      final backupPath = await AppPaths.instance.getBackupPath();
      final sanitizedChapter = _sanitizeFileName(chapter.title);
      String chapterBackupPath;
      if (volumeName.isNotEmpty) {
        final sanitizedVolume = _sanitizeFileName(volumeName);
        chapterBackupPath = '$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedVolume${Platform.pathSeparator}$sanitizedChapter';
      } else {
        chapterBackupPath = '$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedChapter';
      }
      final backupDir = Directory(chapterBackupPath);
      if (await backupDir.exists()) {
        await backupDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('删除章节备份目录失败: $e');
    }

    // 从数据库中删除章节记录
    await _isar.writeTxn(() async {
      await _isar.chapterModels.delete(chapter.id);

      // 更新书籍总字数
      final allChapters = await _isar.chapterModels
          .where()
          .bookUuidEqualTo(_currentBook!.uuid)
          .findAll();
      final totalWordCount = allChapters.fold<int>(0, (sum, c) => sum + c.wordCount);
      _currentBook!.wordCount = totalWordCount;
      _currentBook!.updatedAt = DateTime.now();
      await _isar.bookModels.put(_currentBook!);
    });

    // 刷新章节列表
    await _loadChapters();

    // 清理章节光标位置缓存
    await ChapterCursorCacheService.instance.removeChapter(
      bookUuid: _currentBook!.uuid,
      chapterUuid: chapterUuid,
    );

    notifyListeners();
    // 同步书架最近编辑与字数显示
    _notifyBookshelfRefresh();

    return true;
  }

  /// 批量删除章节
  /// [chapterUuids] 要删除的章节UUID列表
  /// 返回成功删除的数量
  Future<int> batchDeleteChapters({required List<String> chapterUuids}) async {
    if (_currentBook == null || chapterUuids.isEmpty) return 0;

    // 取出待删除的章节对象
    final chaptersToDelete = _chapters
        .where((c) => chapterUuids.contains(c.uuid))
        .toList();
    if (chaptersToDelete.isEmpty) return 0;

    // 集中关闭已打开的章节标签页
    for (final chapter in chaptersToDelete) {
      if (_openedTabs.any((t) => t.id == chapter.uuid)) {
        closeTab(chapter.uuid);
      }
    }

    // 批量将章节移入回收站
    await RecycleItemService.instance.moveChaptersToRecycleBinBatch(
      chapters: chaptersToDelete,
      bookTitle: _currentBook!.title,
      bookFolderPath: bookFolderPath,
      volumeNameOf: getVolumeName,
    );

    // 集中删除章节备份目录
    final backupPath = await AppPaths.instance.getBackupPath();
    for (final chapter in chaptersToDelete) {
      try {
        final sanitizedChapter = _sanitizeFileName(chapter.title);
        final volumeName = getVolumeName(chapter.volumeUuid);
        String chapterBackupPath;
        if (volumeName.isNotEmpty) {
          final sanitizedVolume = _sanitizeFileName(volumeName);
          chapterBackupPath = '$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedVolume${Platform.pathSeparator}$sanitizedChapter';
        } else {
          chapterBackupPath = '$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedChapter';
        }
        final backupDir = Directory(chapterBackupPath);
        if (await backupDir.exists()) {
          await backupDir.delete(recursive: true);
        }
      } catch (e) {
        debugPrint('删除章节备份目录失败: $e');
      }
    }

    // 删除所有章节记录、重算总字数、更新书籍
    await _isar.writeTxn(() async {
      for (final chapter in chaptersToDelete) {
        await _isar.chapterModels.delete(chapter.id);
      }

      // 重新查询剩余章节并累计总字数
      final remainingChapters = await _isar.chapterModels
          .where()
          .bookUuidEqualTo(_currentBook!.uuid)
          .findAll();
      final totalWordCount = remainingChapters.fold<int>(
        0,
        (sum, c) => sum + c.wordCount,
      );
      _currentBook!.wordCount = totalWordCount;
      _currentBook!.updatedAt = DateTime.now();
      await _isar.bookModels.put(_currentBook!);
    });

    // 刷新章节列表
    await _loadChapters();

    // 集中清理章节光标位置缓存
    for (final chapter in chaptersToDelete) {
      await ChapterCursorCacheService.instance.removeChapter(
        bookUuid: _currentBook!.uuid,
        chapterUuid: chapter.uuid,
      );
    }

    // 通知 UI 刷新并同步书架最近编辑/字数
    notifyListeners();
    _notifyBookshelfRefresh();

    return chaptersToDelete.length;
  }

  /// 批量移动章节到指定分卷
  /// [chapterUuids] 要移动的章节UUID列表
  /// [targetVolumeUuid] 目标分卷UUID，空字符串表示未分卷
  /// 返回成功移动的数量
  Future<int> batchMoveChaptersToVolume({
    required List<String> chapterUuids,
    required String targetVolumeUuid,
  }) async {
    if (_currentBook == null) return 0;

    final targetVolumeName = getVolumeName(targetVolumeUuid);

    // 收集可移动的章节（跳过目标分卷相同和目标分卷下重名的）
    final chaptersToMove = <ChapterModel>[];
    for (final chapterUuid in chapterUuids) {
      final chapter = _chapters.where((c) => c.uuid == chapterUuid).firstOrNull;
      if (chapter == null) continue;
      if (chapter.volumeUuid == targetVolumeUuid) continue;
      // 检查目标分卷下是否已存在同名章节
      final existing = _chapters.where(
        (c) => c.title == chapter.title && c.volumeUuid == targetVolumeUuid,
      );
      if (existing.isNotEmpty) continue;
      chaptersToMove.add(chapter);
    }

    if (chaptersToMove.isEmpty) return 0;

    // 计算目标分卷内的起始排序序号
    final targetVolumeChapters = _chapters.where((c) => c.volumeUuid == targetVolumeUuid).toList();
    int nextVolumeOrderIndex = targetVolumeChapters.fold<int>(
      0, (max, c) => c.volumeOrderIndex > max ? c.volumeOrderIndex : max,
    ) + 1;

    final backupPath = await AppPaths.instance.getBackupPath();
    final bookUuid = _currentBook!.uuid;

    // 逐个移动文件和备份目录（文件系统操作无法批量）
    for (final chapter in chaptersToMove) {
      final oldVolumeName = getVolumeName(chapter.volumeUuid);
      final oldFilePath = getChapterFilePath(chapter);

      // 更新章节的分卷归属和排序
      chapter.volumeUuid = targetVolumeUuid;
      chapter.updatedAt = DateTime.now();
      chapter.volumeOrderIndex = nextVolumeOrderIndex++;

      // 生成新的文件相对路径
      final String newRelativePath = targetVolumeName.isNotEmpty
          ? '${_sanitizeFileName(targetVolumeName)}${Platform.pathSeparator}${_sanitizeFileName(chapter.title)}${GlobalConstants.chapterFileExtension}'
          : '${_sanitizeFileName(chapter.title)}${GlobalConstants.chapterFileExtension}';
      chapter.filePath = newRelativePath;

      // 移动章节文件
      try {
        final oldFile = File(oldFilePath);
        if (await oldFile.exists()) {
          final newFilePath = getChapterFilePath(chapter);
          final parentDir = Directory(newFilePath).parent;
          if (!await parentDir.exists()) {
            await parentDir.create(recursive: true);
          }
          await oldFile.rename(newFilePath);
        }
      } catch (e) {
        debugPrint('移动章节文件失败: $e');
      }

      // 移动备份目录
      try {
        final sanitizedChapter = _sanitizeFileName(chapter.title);
        String oldBackupPath;
        String newBackupPath;

        if (oldVolumeName.isNotEmpty) {
          final sanitizedVolume = _sanitizeFileName(oldVolumeName);
          oldBackupPath = '$backupPath${Platform.pathSeparator}$bookUuid${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedVolume${Platform.pathSeparator}$sanitizedChapter';
        } else {
          oldBackupPath = '$backupPath${Platform.pathSeparator}$bookUuid${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedChapter';
        }

        if (targetVolumeName.isNotEmpty) {
          final sanitizedVolume = _sanitizeFileName(targetVolumeName);
          newBackupPath = '$backupPath${Platform.pathSeparator}$bookUuid${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedVolume${Platform.pathSeparator}$sanitizedChapter';
        } else {
          newBackupPath = '$backupPath${Platform.pathSeparator}$bookUuid${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedChapter';
        }

        final oldBackupDir = Directory(oldBackupPath);
        if (await oldBackupDir.exists()) {
          final newBackupDir = Directory(newBackupPath);
          if (!await newBackupDir.exists()) {
            if (!await newBackupDir.parent.exists()) {
              await newBackupDir.parent.create(recursive: true);
            }
            await oldBackupDir.rename(newBackupPath);
          }
        }
      } catch (e) {
        debugPrint('移动章节备份目录失败: $e');
      }

      // 更新备份服务中的分卷信息
      BackupService.instance.updateTabBackupInfo(
        tabId: chapter.uuid,
        chapterTitle: chapter.title,
        volumeName: targetVolumeName,
      );
    }

    // 单事务批量更新所有章节记录和书籍修改时间
    await _isar.writeTxn(() async {
      await _isar.chapterModels.putAll(chaptersToMove);
      _currentBook!.updatedAt = DateTime.now();
      await _isar.bookModels.put(_currentBook!);
    });

    // 一次性刷新
    await _loadChapters();
    notifyListeners();

    return chaptersToMove.length;
  }

  /// 批量导出章节
  /// [chapterUuids] 要导出的章节UUID列表
  /// [outputDir] 导出目录路径
  /// 返回成功导出的数量
  Future<int> exportChapters({
    required List<String> chapterUuids,
    required String outputDir,
  }) async {
    if (_currentBook == null) return 0;

    int exportedCount = 0;

    // 确保输出目录存在
    final outputDirectory = Directory(outputDir);
    if (!await outputDirectory.exists()) {
      await outputDirectory.create(recursive: true);
    }

    for (final chapterUuid in chapterUuids) {
      final chapter = _chapters.where((c) => c.uuid == chapterUuid).firstOrNull;
      if (chapter == null) continue;

      try {
        // 读取章节内容
        final content = await readChapterContent(chapter);
        // 生成导出文件名（包含分卷名作为子目录）
        final volumeName = getVolumeName(chapter.volumeUuid);
        String exportFilePath;
        if (volumeName.isNotEmpty) {
          final volumeDir = Directory('$outputDir${Platform.pathSeparator}${_sanitizeFileName(volumeName)}');
          if (!await volumeDir.exists()) {
            await volumeDir.create(recursive: true);
          }
          exportFilePath = '$outputDir${Platform.pathSeparator}${_sanitizeFileName(volumeName)}${Platform.pathSeparator}${_sanitizeFileName(chapter.title)}.txt';
        } else {
          exportFilePath = '$outputDir${Platform.pathSeparator}${_sanitizeFileName(chapter.title)}.txt';
        }
        // 写入文件
        final exportFile = File(exportFilePath);
        await exportFile.writeAsString(content);
        exportedCount++;
      } catch (e) {
        debugPrint('导出章节失败: ${chapter.title}, 错误: $e');
      }
    }

    return exportedCount;
  }

  /// 根据分卷 UUID 获取分卷名称
  String getVolumeName(String volumeUuid) {
    if (volumeUuid.isEmpty) return '';
    final volume = _volumes.where((v) => v.uuid == volumeUuid).firstOrNull;
    return volume?.name ?? '';
  }
  
  /// 根据分卷名称获取分卷 UUID
  String getVolumeUuid(String volumeName) {
    if (volumeName.isEmpty) return '';
    final volume = _volumes.where((v) => v.name == volumeName).firstOrNull;
    return volume?.uuid ?? '';
  }

  /// 移动章节到指定分卷
  /// [chapterUuid] 章节UUID
  /// [targetVolumeUuid] 目标分卷UUID，空字符串表示未分卷
  /// 返回是否移动成功
  Future<bool> moveChapterToVolume({
    required String chapterUuid,
    required String targetVolumeUuid,
  }) async {
    if (_currentBook == null) return false;

    final chapter = _chapters.where((c) => c.uuid == chapterUuid).firstOrNull;
    if (chapter == null) return false;

    // 目标分卷与当前分卷相同，无需移动
    if (chapter.volumeUuid == targetVolumeUuid) return false;

    // 检查目标分卷下是否已存在同名章节
    final existing = _chapters.where(
      (c) => c.title == chapter.title && c.volumeUuid == targetVolumeUuid && c.uuid != chapterUuid,
    );
    if (existing.isNotEmpty) return false;

    // 保存旧的文件路径
    final oldFilePath = getChapterFilePath(chapter);
    final oldVolumeName = getVolumeName(chapter.volumeUuid);
    final newVolumeName = getVolumeName(targetVolumeUuid);

    // 更新章节的分卷归属
    chapter.volumeUuid = targetVolumeUuid;
    chapter.updatedAt = DateTime.now();

    // 生成新的文件路径
    String newRelativePath;
    if (newVolumeName.isNotEmpty) {
      newRelativePath = '${_sanitizeFileName(newVolumeName)}${Platform.pathSeparator}${_sanitizeFileName(chapter.title)}${GlobalConstants.chapterFileExtension}';
    } else {
      newRelativePath = '${_sanitizeFileName(chapter.title)}${GlobalConstants.chapterFileExtension}';
    }
    chapter.filePath = newRelativePath;

    // 计算目标分卷内的排序序号
    final targetVolumeChapters = _chapters.where((c) => c.volumeUuid == targetVolumeUuid && c.uuid != chapterUuid).toList();
    final maxVolumeOrder = targetVolumeChapters.fold<int>(0, (max, c) => c.volumeOrderIndex > max ? c.volumeOrderIndex : max);
    chapter.volumeOrderIndex = maxVolumeOrder + 1;

    // 生成新的完整文件路径
    final newFilePath = getChapterFilePath(chapter);

    // 移动章节文件
    try {
      final oldFile = File(oldFilePath);
      if (await oldFile.exists()) {
        final newFile = File(newFilePath);
        // 确保目标目录存在
        final parentDir = newFile.parent;
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }
        await oldFile.rename(newFilePath);
      }
    } catch (e) {
      debugPrint('移动章节文件失败: $e');
      return false;
    }

    // 移动备份目录
    try {
      final backupPath = await AppPaths.instance.getBackupPath();
      final sanitizedChapter = _sanitizeFileName(chapter.title);

      String oldBackupPath;
      String newBackupPath;

      if (oldVolumeName.isNotEmpty) {
        final sanitizedVolume = _sanitizeFileName(oldVolumeName);
        oldBackupPath = '$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedVolume${Platform.pathSeparator}$sanitizedChapter';
      } else {
        oldBackupPath = '$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedChapter';
      }

      if (newVolumeName.isNotEmpty) {
        final sanitizedVolume = _sanitizeFileName(newVolumeName);
        newBackupPath = '$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedVolume${Platform.pathSeparator}$sanitizedChapter';
      } else {
        newBackupPath = '$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedChapter';
      }

      final oldBackupDir = Directory(oldBackupPath);
      if (await oldBackupDir.exists()) {
        final newBackupDir = Directory(newBackupPath);
        if (!await newBackupDir.exists()) {
          // 确保目标父目录存在
          if (!await newBackupDir.parent.exists()) {
            await newBackupDir.parent.create(recursive: true);
          }
          await oldBackupDir.rename(newBackupPath);
        }
      }
    } catch (e) {
      debugPrint('移动章节备份目录失败: $e');
    }

    // 更新备份服务中的分卷信息
    BackupService.instance.updateTabBackupInfo(
      tabId: chapter.uuid,
      chapterTitle: chapter.title,
      volumeName: newVolumeName,
    );

    // 更新数据库
    await _isar.writeTxn(() async {
      await _isar.chapterModels.put(chapter);
    });

    // 刷新章节列表
    await _loadChapters();

    notifyListeners();
    return true;
  }

  /// 新建分卷
  /// [volumeName] 分卷名称
  /// 返回新建分卷的 UUID，失败返回 null
  Future<String?> addVolume({required String volumeName}) async {
    if (_currentBook == null) return null;
    if (volumeName.trim().isEmpty) return null;

    // 检查是否已存在同名分卷
    if (_volumes.any((v) => v.name == volumeName)) return null;

    // 计算排序序号
    final maxOrder = _volumes.fold<int>(0, (max, v) => v.orderIndex > max ? v.orderIndex : max);

    // 创建分卷模型
    final volume = VolumeModel()
      ..uuid = const Uuid().v4()
      ..bookUuid = _currentBook!.uuid
      ..name = volumeName
      ..orderIndex = maxOrder + 1
      ..createdAt = DateTime.now()
      ..updatedAt = DateTime.now();

    // 创建分卷目录
    final chaptersDir = '$bookFolderPath${Platform.pathSeparator}chapters';
    final volumeDir = Directory('$chaptersDir${Platform.pathSeparator}${_sanitizeFileName(volumeName)}');
    try {
      if (!await volumeDir.exists()) {
        await volumeDir.create(recursive: true);
      }
    } catch (e) {
      debugPrint('创建分卷目录失败: $e');
      return null;
    }

    // 写入数据库
    await _isar.writeTxn(() async {
      await _isar.volumeModels.put(volume);
    });

    // 刷新分卷列表
    await _loadVolumes();

    notifyListeners();
    return volume.uuid;
  }

  /// 调整同一分卷内章节的顺序
  /// [volumeUuid] 分卷 UUID
  /// [oldIndex] 原索引
  /// [newIndex] 新索引
  Future<void> reorderChaptersInVolume(String volumeUuid, int oldIndex, int newIndex) async {
    if (_currentBook == null) return;

    // 获取该分卷下的所有章节，并按现有的 volumeOrderIndex 排序
    final volumeChapters = _chapters
        .where((c) => c.volumeUuid == volumeUuid)
        .toList()
      ..sort((a, b) => a.volumeOrderIndex.compareTo(b.volumeOrderIndex));

    if (oldIndex < 0 || oldIndex >= volumeChapters.length) return;
    if (newIndex < 0 || newIndex > volumeChapters.length) return;

    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    
    if (oldIndex == newIndex) return;

    final chapter = volumeChapters.removeAt(oldIndex);
    volumeChapters.insert(newIndex, chapter);

    // 更新所有的 volumeOrderIndex，并更新全局 orderIndex
    // 为了不打乱其他分卷的章节，我们需要重排所有章节的全局 orderIndex
    for (int i = 0; i < volumeChapters.length; i++) {
      volumeChapters[i].volumeOrderIndex = i;
    }

    // 更新 _chapters 列表
    // 分组收集所有分卷及其章节，以便全量更新全局 orderIndex
    final groups = <String, List<ChapterModel>>{};
    for (final v in _volumes) {
      groups[v.uuid] = [];
    }
    // 未分卷组
    groups[''] = [];

    for (final c in _chapters) {
      if (c.volumeUuid == volumeUuid) continue; // 稍后填入排序好的
      groups.putIfAbsent(c.volumeUuid, () => []).add(c);
    }
    
    groups[volumeUuid] = volumeChapters;

    // 按分卷顺序重新组合所有章节
    final newAllChapters = <ChapterModel>[];
    
    // 先加未分卷
    if (groups.containsKey('')) {
      final unassigned = groups['']!..sort((a, b) => a.volumeOrderIndex.compareTo(b.volumeOrderIndex));
      newAllChapters.addAll(unassigned);
    }
    
    // 再加各分卷
    for (final v in _volumes) {
      if (groups.containsKey(v.uuid)) {
        final vc = groups[v.uuid]!..sort((a, b) => a.volumeOrderIndex.compareTo(b.volumeOrderIndex));
        newAllChapters.addAll(vc);
      }
    }

    // 重新赋全局 orderIndex
    for (int i = 0; i < newAllChapters.length; i++) {
      newAllChapters[i].orderIndex = i;
    }

    _chapters = newAllChapters;

    // 写入数据库
    await _isar.writeTxn(() async {
      // 全量更新，因为全局 orderIndex 发生了变化
      await _isar.chapterModels.putAll(newAllChapters);
    });

    notifyListeners();
  }

  /// 切换分卷展开/折叠状态
  /// [volumeUuid] 分卷 UUID
  Future<void> toggleVolumeExpanded({required String volumeUuid}) async {
    final volume = _volumes.where((v) => v.uuid == volumeUuid).firstOrNull;
    if (volume == null) return;

    volume.isExpanded = !volume.isExpanded;

    await _isar.writeTxn(() async {
      await _isar.volumeModels.put(volume);
    });

    notifyListeners();
  }

  /// 重命名分卷
  /// [volumeUuid] 分卷 UUID
  /// [newName] 新分卷名
  /// 返回是否重命名成功
  Future<bool> renameVolume({
    required String volumeUuid,
    required String newName,
  }) async {
    if (_currentBook == null) return false;
    if (newName.trim().isEmpty) return false;

    // 查找分卷
    final volume = _volumes.where((v) => v.uuid == volumeUuid).firstOrNull;
    if (volume == null) return false;
    if (volume.name == newName) return true;

    // 检查是否已存在同名分卷
    if (_volumes.any((v) => v.name == newName && v.uuid != volumeUuid)) return false;

    final oldName = volume.name;

    // 重命名分卷目录
    final chaptersDir = '$bookFolderPath${Platform.pathSeparator}chapters';
    final oldDir = Directory('$chaptersDir${Platform.pathSeparator}${_sanitizeFileName(oldName)}');
    final newDir = Directory('$chaptersDir${Platform.pathSeparator}${_sanitizeFileName(newName)}');

    try {
      if (await oldDir.exists()) {
        if (!await newDir.parent.exists()) {
          await newDir.parent.create(recursive: true);
        }
        await oldDir.rename(newDir.path);
      }
    } catch (e) {
      debugPrint('重命名分卷目录失败: $e');
      return false;
    }

    // 重命名备份目录
    final backupPath = await AppPaths.instance.getBackupPath();
    final oldBackupDir = Directory('$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}${_sanitizeFileName(oldName)}');
    final newBackupDir = Directory('$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}${_sanitizeFileName(newName)}');

    try {
      if (await oldBackupDir.exists()) {
        if (!await newBackupDir.exists()) {
          await oldBackupDir.rename(newBackupDir.path);
        }
      }
    } catch (e) {
      debugPrint('重命名分卷备份目录失败: $e');
    }

    // 获取该分卷下的所有章节
    final volumeChapters = _chapters.where((c) => c.volumeUuid == volumeUuid).toList();

    // 更新所有章节的 filePath（volumeUuid 不变，只需更新路径中的分卷名部分）
    for (final chapter in volumeChapters) {
      chapter.updatedAt = DateTime.now();
      chapter.filePath = '${_sanitizeFileName(newName)}${Platform.pathSeparator}${_sanitizeFileName(chapter.title)}${GlobalConstants.chapterFileExtension}';

      // 更新备份计时器中的分卷名
      BackupService.instance.updateTabBackupInfo(
        tabId: chapter.uuid,
        chapterTitle: chapter.title,
        volumeName: newName,
      );
    }

    // 更新分卷名称
    volume.name = newName;
    volume.updatedAt = DateTime.now();

    // 批量更新数据库
    await _isar.writeTxn(() async {
      await _isar.volumeModels.put(volume);
      for (final chapter in volumeChapters) {
        await _isar.chapterModels.put(chapter);
      }
    });

    // 刷新列表
    await _loadVolumes();
    await _loadChapters();

    // 更新已打开标签页中的分卷信息
    for (final tab in _openedTabs) {
      final chapter = volumeChapters.where((c) => c.uuid == tab.id).firstOrNull;
      if (chapter != null) {
        BackupService.instance.startTabBackupTimer(
          tabId: tab.id,
          bookUuid: _currentBook!.uuid,
          chapterTitle: tab.title,
          volumeName: newName,
          contentGetter: () => tab.textController?.text ?? '',
        );
      }
    }

    notifyListeners();
    return true;
  }

  /// 删除分卷
  /// [volumeUuid] 分卷 UUID
  /// 返回是否删除成功
  Future<bool> deleteVolume({required String volumeUuid}) async {
    if (_currentBook == null) return false;

    // 查找分卷
    final volume = _volumes.where((v) => v.uuid == volumeUuid).firstOrNull;
    if (volume == null) return false;

    final volumeName = volume.name;

    // 获取该分卷下的所有章节
    final volumeChapters = _chapters.where((c) => c.volumeUuid == volumeUuid).toList();

    if (volumeChapters.isNotEmpty) {
      // 集中关闭已打开的章节标签页
      for (final chapter in volumeChapters) {
        if (_openedTabs.any((t) => t.id == chapter.uuid)) {
          closeTab(chapter.uuid);
        }
      }

      // 批量将章节移入回收站
      await RecycleItemService.instance.moveChaptersToRecycleBinBatch(
        chapters: volumeChapters,
        bookTitle: _currentBook!.title,
        bookFolderPath: bookFolderPath,
        volumeNameOf: getVolumeName,
      );

      // 集中删除章节备份目录（同分卷下的章节共享分卷备份子目录）
      final backupPath = await AppPaths.instance.getBackupPath();
      final sanitizedVolume = _sanitizeFileName(volumeName);
      for (final chapter in volumeChapters) {
        try {
          final sanitizedChapter = _sanitizeFileName(chapter.title);
          final chapterBackupPath =
              '$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedVolume${Platform.pathSeparator}$sanitizedChapter';
          final backupDir = Directory(chapterBackupPath);
          if (await backupDir.exists()) {
            await backupDir.delete(recursive: true);
          }
        } catch (e) {
          debugPrint('删除章节备份目录失败: $e');
        }
      }

      // 删除所有章节记录、重算总字数、更新书籍
      await _isar.writeTxn(() async {
        for (final chapter in volumeChapters) {
          await _isar.chapterModels.delete(chapter.id);
        }

        // 重新查询剩余章节并累计总字数
        final remainingChapters = await _isar.chapterModels
            .where()
            .bookUuidEqualTo(_currentBook!.uuid)
            .findAll();
        final totalWordCount = remainingChapters.fold<int>(
          0,
          (sum, c) => sum + c.wordCount,
        );
        _currentBook!.wordCount = totalWordCount;
        _currentBook!.updatedAt = DateTime.now();
        await _isar.bookModels.put(_currentBook!);
      });

      // 集中清理章节光标位置缓存
      for (final chapter in volumeChapters) {
        await ChapterCursorCacheService.instance.removeChapter(
          bookUuid: _currentBook!.uuid,
          chapterUuid: chapter.uuid,
        );
      }
    }

    // 删除分卷目录（如果还有残留）
    final chaptersDir = '$bookFolderPath${Platform.pathSeparator}chapters';
    final volumeDir = Directory('$chaptersDir${Platform.pathSeparator}${_sanitizeFileName(volumeName)}');
    try {
      if (await volumeDir.exists()) {
        await volumeDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('删除分卷目录失败: $e');
    }

    // 删除分卷备份目录
    final backupPath = await AppPaths.instance.getBackupPath();
    final backupDir = Directory('$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}${_sanitizeFileName(volumeName)}');
    try {
      if (await backupDir.exists()) {
        await backupDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('删除分卷备份目录失败: $e');
    }

    // 从数据库中删除分卷记录
    await _isar.writeTxn(() async {
      await _isar.volumeModels.delete(volume.id);
    });

    // 一次性刷新章节和分卷列表
    await _loadChapters();
    await _loadVolumes();

    // 通知 UI 刷新并同步书架最近编辑/字数
    notifyListeners();
    _notifyBookshelfRefresh();
    return true;
  }

  // ================= 设定数据操作 =================

  /// 根据分组 UUID 获取分组名称
  String getSettingGroupName(String groupUuid) {
    if (groupUuid.isEmpty) return '';
    final group = _settingGroups.where((g) => g.uuid == groupUuid).firstOrNull;
    return group?.name ?? '';
  }

  /// 获取设定项文件的完整路径
  String getSettingItemFilePath(SettingItemModel item) {
    return '$bookFolderPath${Platform.pathSeparator}settings${Platform.pathSeparator}${item.filePath}';
  }

  /// 读取设定项文件内容
  Future<String> readSettingItemContent(SettingItemModel item) async {
    try {
      final filePath = getSettingItemFilePath(item);
      final file = File(filePath);

      if (!await file.exists()) {
        debugPrint('设定项文件不存在: $filePath');
        return '';
      }

      return await file.readAsString();
    } catch (e) {
      debugPrint('读取设定项文件失败: $e');
      return '';
    }
  }

  /// 保存设定项内容到文件
  /// [item] 设定项模型
  /// [content] 设定项内容
  /// 返回是否保存成功
  Future<bool> saveSettingItemContent(SettingItemModel item, String content) async {
    try {
      final filePath = getSettingItemFilePath(item);
      final file = File(filePath);

      // 确保父目录存在
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      // 写入文件
      await file.writeAsString(content);

      // 计算字数
      final wordCount = WordCountUtils.countWords(content);

      // 更新数据库中的字数和修改时间
      item.wordCount = wordCount;
      item.updatedAt = DateTime.now();

      await _isar.writeTxn(() async {
        await _isar.settingItemModels.put(item);

        // 更新书籍修改时间
        if (_currentBook != null) {
          _currentBook!.updatedAt = DateTime.now();
          await _isar.bookModels.put(_currentBook!);
        }
      });

      // 刷新设定项列表
      await _loadSettingItems();

      // 通知刷新书架
      if (_mainWindowId != null) {
        await MultiWindowService.instance.notifyBookUpdated(_mainWindowId!);
      } else if (_onBookSaved != null) {
        _onBookSaved!();
      }

      debugPrint('设定项保存成功: ${item.title}, 字数: $wordCount');
      return true;
    } catch (e) {
      debugPrint('保存设定项文件失败: $e');
      return false;
    }
  }

  /// 新建设定分组
  /// [name] 分组名称
  /// 返回新建的设定分组模型，失败返回 null
  Future<SettingGroupModel?> addSettingGroup({required String name}) async {
    if (_currentBook == null) return null;

    // 检查是否已存在同名分组
    if (_settingGroups.any((g) => g.name == name)) return null;

    // 计算排序序号
    final maxOrder = _settingGroups.fold<int>(0, (max, g) => g.orderIndex > max ? g.orderIndex : max);

    final group = SettingGroupModel()
      ..uuid = const Uuid().v4()
      ..bookUuid = _currentBook!.uuid
      ..name = name
      ..orderIndex = maxOrder + 1
      ..isExpanded = true
      ..createdAt = DateTime.now()
      ..updatedAt = DateTime.now();

    await _isar.writeTxn(() async {
      await _isar.settingGroupModels.put(group);

      // 更新书籍修改时间
      if (_currentBook != null) {
        _currentBook!.updatedAt = DateTime.now();
        await _isar.bookModels.put(_currentBook!);
      }
    });

    await _loadSettingGroups();
    notifyListeners();

    return group;
  }

  /// 新建设定项
  /// [title] 设定项标题
  /// [groupUuid] 分组 UUID，空字符串表示未分组
  /// 返回新建的设定项模型，失败返回 null
  Future<SettingItemModel?> addSettingItem({
    required String title,
    String groupUuid = '',
  }) async {
    if (_currentBook == null) return null;

    // 检查同一分组下是否已存在同名设定项
    final existing = _settingItems.where(
      (i) => i.title == title && i.groupUuid == groupUuid,
    );
    if (existing.isNotEmpty) return null;

    // 计算排序序号
    final globalMaxOrder = _settingItems.fold<int>(0, (max, i) => i.orderIndex > max ? i.orderIndex : max);
    final groupItems = _settingItems.where((i) => i.groupUuid == groupUuid).toList();
    final groupMaxOrder = groupItems.fold<int>(0, (max, i) => i.groupOrderIndex > max ? i.groupOrderIndex : max);

    // 生成文件路径
    String filePath;
    final groupName = getSettingGroupName(groupUuid);
    if (groupName.isNotEmpty) {
      filePath = '${_sanitizeFileName(groupName)}${Platform.pathSeparator}${_sanitizeFileName(title)}${GlobalConstants.chapterFileExtension}';
    } else {
      filePath = '${_sanitizeFileName(title)}${GlobalConstants.chapterFileExtension}';
    }

    final item = SettingItemModel()
      ..uuid = const Uuid().v4()
      ..bookUuid = _currentBook!.uuid
      ..title = title
      ..groupUuid = groupUuid
      ..orderIndex = globalMaxOrder + 1
      ..groupOrderIndex = groupMaxOrder + 1
      ..wordCount = 0
      ..filePath = filePath
      ..createdAt = DateTime.now()
      ..updatedAt = DateTime.now();

    // 创建设定项文件
    try {
      final fullPath = getSettingItemFilePath(item);
      final file = File(fullPath);
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      await file.writeAsString('');
    } catch (e) {
      debugPrint('创建设定项文件失败: $e');
      return null;
    }

    // 写入数据库
    await _isar.writeTxn(() async {
      await _isar.settingItemModels.put(item);

      // 更新书籍修改时间
      if (_currentBook != null) {
        _currentBook!.updatedAt = DateTime.now();
        await _isar.bookModels.put(_currentBook!);
      }
    });

    await _loadSettingItems();
    notifyListeners();

    return item;
  }

  /// 重命名设定分组
  /// [groupUuid] 分组 UUID
  /// [newName] 新分组名
  /// 返回是否重命名成功
  Future<bool> renameSettingGroup({
    required String groupUuid,
    required String newName,
  }) async {
    if (_currentBook == null) return false;
    if (newName.trim().isEmpty) return false;

    final group = _settingGroups.where((g) => g.uuid == groupUuid).firstOrNull;
    if (group == null) return false;
    if (group.name == newName) return true;

    // 检查是否已存在同名分组
    if (_settingGroups.any((g) => g.name == newName && g.uuid != groupUuid)) return false;

    final oldName = group.name;

    // 重命名分组目录
    final settingsDir = '$bookFolderPath${Platform.pathSeparator}settings';
    final oldDir = Directory('$settingsDir${Platform.pathSeparator}${_sanitizeFileName(oldName)}');
    final newDir = Directory('$settingsDir${Platform.pathSeparator}${_sanitizeFileName(newName)}');

    try {
      if (await oldDir.exists()) {
        if (!await newDir.parent.exists()) {
          await newDir.parent.create(recursive: true);
        }
        await oldDir.rename(newDir.path);
      }
    } catch (e) {
      debugPrint('重命名设定分组目录失败: $e');
      return false;
    }

    // 获取该分组下的所有设定项
    final groupItems = _settingItems.where((i) => i.groupUuid == groupUuid).toList();

    // 更新所有设定项的 filePath
    for (final item in groupItems) {
      item.updatedAt = DateTime.now();
      item.filePath = '${_sanitizeFileName(newName)}${Platform.pathSeparator}${_sanitizeFileName(item.title)}${GlobalConstants.chapterFileExtension}';
    }

    // 更新分组名称
    group.name = newName;
    group.updatedAt = DateTime.now();

    // 批量更新数据库
    await _isar.writeTxn(() async {
      await _isar.settingGroupModels.put(group);
      for (final item in groupItems) {
        await _isar.settingItemModels.put(item);
      }
    });

    await _loadSettingGroups();
    await _loadSettingItems();

    notifyListeners();
    return true;
  }

  /// 重命名设定项
  /// [itemUuid] 设定项 UUID
  /// [newTitle] 新标题
  /// 返回是否重命名成功
  Future<bool> renameSettingItem({
    required String itemUuid,
    required String newTitle,
  }) async {
    if (_currentBook == null) return false;

    final item = _settingItems.where((i) => i.uuid == itemUuid).firstOrNull;
    if (item == null) return false;
    if (item.title == newTitle) return true;

    // 检查同一分组下是否已存在同名设定项
    if (_settingItems.any((i) => i.title == newTitle && i.groupUuid == item.groupUuid && i.uuid != itemUuid)) return false;

    // 保存旧标题和文件路径，用于后续重命名文件和备份目录
    final oldTitle = item.title;
    final oldFilePath = getSettingItemFilePath(item);

    // 更新标题
    item.title = newTitle;
    item.updatedAt = DateTime.now();

    // 生成新的文件路径
    final groupName = getSettingGroupName(item.groupUuid);
    if (groupName.isNotEmpty) {
      item.filePath = '${_sanitizeFileName(groupName)}${Platform.pathSeparator}${_sanitizeFileName(newTitle)}${GlobalConstants.chapterFileExtension}';
    } else {
      item.filePath = '${_sanitizeFileName(newTitle)}${GlobalConstants.chapterFileExtension}';
    }

    // 重命名文件
    final newFilePath = getSettingItemFilePath(item);
    try {
      final oldFile = File(oldFilePath);
      if (await oldFile.exists()) {
        final newFile = File(newFilePath);
        if (!await newFile.parent.exists()) {
          await newFile.parent.create(recursive: true);
        }
        await oldFile.rename(newFilePath);
      }
    } catch (e) {
      debugPrint('重命名设定项文件失败: $e');
      return false;
    }

    // 重命名备份目录（沿用标题变更后的新目录名）
    await BackupService.instance.renameSettingBackupDir(
      bookUuid: _currentBook!.uuid,
      oldSettingTitle: oldTitle,
      newSettingTitle: newTitle,
    );

    // 更新数据库
    await _isar.writeTxn(() async {
      await _isar.settingItemModels.put(item);

      if (_currentBook != null) {
        _currentBook!.updatedAt = DateTime.now();
        await _isar.bookModels.put(_currentBook!);
      }
    });

    await _loadSettingItems();

    // 更新已打开标签页的标题及备份计时器中的标题
    final tab = _openedTabs.where((t) => t.id == itemUuid).firstOrNull;
    if (tab != null) {
      tab.title = newTitle;
      BackupService.instance.updateTabBackupInfo(tabId: itemUuid, chapterTitle: newTitle);
    }

    notifyListeners();
    return true;
  }

  /// 删除设定分组
  /// [groupUuid] 分组 UUID
  /// 返回是否删除成功
  Future<bool> deleteSettingGroup({required String groupUuid}) async {
    if (_currentBook == null) return false;

    final group = _settingGroups.where((g) => g.uuid == groupUuid).firstOrNull;
    if (group == null) return false;

    final groupName = group.name;

    // 获取该分组下的所有设定项
    final groupItems = _settingItems.where((i) => i.groupUuid == groupUuid).toList();

    if (groupItems.isNotEmpty) {
      // 集中关闭已打开的设定项标签页
      for (final item in groupItems) {
        if (_openedTabs.any((t) => t.id == item.uuid)) {
          closeTab(item.uuid);
        }
      }

      // 批量将设定项移入回收站
      await RecycleItemService.instance.moveSettingItemsToRecycleBinBatch(
        items: groupItems,
        bookTitle: _currentBook!.title,
        bookFolderPath: bookFolderPath,
        groupNameOf: getSettingGroupName,
      );

      // 集中删除设定项备份目录
      for (final item in groupItems) {
        await BackupService.instance.deleteSettingBackups(
          _currentBook!.uuid,
          item.title,
        );
      }

      // 删除所有设定项记录、更新书籍修改时间
      await _isar.writeTxn(() async {
        for (final item in groupItems) {
          await _isar.settingItemModels.delete(item.id);
        }

        _currentBook!.updatedAt = DateTime.now();
        await _isar.bookModels.put(_currentBook!);
      });
    }

    // 删除分组目录
    final settingsDir = '$bookFolderPath${Platform.pathSeparator}settings';
    final groupDir = Directory('$settingsDir${Platform.pathSeparator}${_sanitizeFileName(groupName)}');
    try {
      if (await groupDir.exists()) {
        await groupDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('删除设定分组目录失败: $e');
    }

    // 从数据库中删除分组记录
    await _isar.writeTxn(() async {
      await _isar.settingGroupModels.delete(group.id);
    });

    // 一次性刷新设定项和分组列表
    await _loadSettingItems();
    await _loadSettingGroups();

    // 通知 UI 刷新并同步书架最近编辑/字数
    notifyListeners();
    _notifyBookshelfRefresh();
    return true;
  }

  /// 删除设定项
  /// [itemUuid] 设定项 UUID
  /// 返回是否删除成功
  Future<bool> deleteSettingItem({required String itemUuid}) async {
    if (_currentBook == null) return false;

    final item = _settingItems.where((i) => i.uuid == itemUuid).firstOrNull;
    if (item == null) return false;

    // 保存标题，用于后续删除对应的备份目录
    final itemTitle = item.title;

    // 关闭已打开的标签页
    final tab = _openedTabs.where((t) => t.id == itemUuid).firstOrNull;
    if (tab != null) {
      closeTab(itemUuid);
    }

    // 将设定项移入回收站
    final groupName = getSettingGroupName(item.groupUuid);
    await RecycleItemService.instance.moveSettingItemToRecycleBin(
      item: item,
      bookTitle: _currentBook!.title,
      groupName: groupName,
      itemFilePath: getSettingItemFilePath(item),
    );

    // 删除对应的设定备份目录
    await BackupService.instance.deleteSettingBackups(_currentBook!.uuid, itemTitle);

    // 从数据库中删除设定项记录
    await _isar.writeTxn(() async {
      await _isar.settingItemModels.delete(item.id);

      if (_currentBook != null) {
        _currentBook!.updatedAt = DateTime.now();
        await _isar.bookModels.put(_currentBook!);
      }
    });

    await _loadSettingItems();
    notifyListeners();
    // 同步书架最近编辑与字数显示
    _notifyBookshelfRefresh();
    return true;
  }

  /// 切换设定分组展开/折叠状态
  /// [groupUuid] 分组 UUID
  Future<void> toggleSettingGroupExpanded({required String groupUuid}) async {
    final group = _settingGroups.where((g) => g.uuid == groupUuid).firstOrNull;
    if (group == null) return;

    group.isExpanded = !group.isExpanded;

    await _isar.writeTxn(() async {
      await _isar.settingGroupModels.put(group);
    });

    notifyListeners();
  }

  /// 重新排序指定分组内的设定项
  /// [groupUuid] 分组 UUID，空字符串表示未分组
  /// [oldIndex] 原始位置
  /// [newIndex] 目标位置
  Future<void> reorderSettingItemsInGroup(String groupUuid, int oldIndex, int newIndex) async {
    if (_currentBook == null) return;

    // 获取该分组下的所有设定项，并按现有的 groupOrderIndex 排序
    final groupItems = _settingItems
        .where((i) => i.groupUuid == groupUuid)
        .toList()
      ..sort((a, b) => a.groupOrderIndex.compareTo(b.groupOrderIndex));

    if (oldIndex < 0 || oldIndex >= groupItems.length) return;
    if (newIndex < 0 || newIndex > groupItems.length) return;

    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    if (oldIndex == newIndex) return;

    final item = groupItems.removeAt(oldIndex);
    groupItems.insert(newIndex, item);

    // 更新所有的 groupOrderIndex
    for (int i = 0; i < groupItems.length; i++) {
      groupItems[i].groupOrderIndex = i;
    }

    // 更新 _settingItems 列表
    // 分组收集所有分组及其设定项，以便全量更新全局 orderIndex
    final groups = <String, List<SettingItemModel>>{};
    for (final g in _settingGroups) {
      groups[g.uuid] = [];
    }
    // 未分组
    groups[''] = [];

    for (final i in _settingItems) {
      if (i.groupUuid == groupUuid) continue; // 稍后填入排序好的
      groups.putIfAbsent(i.groupUuid, () => []).add(i);
    }

    groups[groupUuid] = groupItems;

    // 按分组顺序重新组合所有设定项
    final newAllItems = <SettingItemModel>[];

    // 先加未分组
    if (groups.containsKey('')) {
      final unassigned = groups['']!..sort((a, b) => a.groupOrderIndex.compareTo(b.groupOrderIndex));
      newAllItems.addAll(unassigned);
    }

    // 再加各分组
    for (final g in _settingGroups) {
      if (groups.containsKey(g.uuid)) {
        final gi = groups[g.uuid]!..sort((a, b) => a.groupOrderIndex.compareTo(b.groupOrderIndex));
        newAllItems.addAll(gi);
      }
    }

    // 重新赋全局 orderIndex
    for (int i = 0; i < newAllItems.length; i++) {
      newAllItems[i].orderIndex = i;
    }

    _settingItems = newAllItems;

    // 写入数据库
    await _isar.writeTxn(() async {
      await _isar.settingItemModels.putAll(newAllItems);
    });

    notifyListeners();
  }

  /// 移动设定项到指定分组
  /// [itemUuid] 设定项 UUID
  /// [targetGroupUuid] 目标分组 UUID，空字符串表示未分组
  /// 返回是否移动成功
  Future<bool> moveSettingItemToGroup({
    required String itemUuid,
    required String targetGroupUuid,
  }) async {
    if (_currentBook == null) return false;

    final item = _settingItems.where((i) => i.uuid == itemUuid).firstOrNull;
    if (item == null) return false;

    // 目标分组与当前分组相同，无需移动
    if (item.groupUuid == targetGroupUuid) return false;

    // 检查目标分组下是否已存在同名设定项
    final existing = _settingItems.where(
      (i) => i.title == item.title && i.groupUuid == targetGroupUuid && i.uuid != itemUuid,
    );
    if (existing.isNotEmpty) return false;

    // 保存旧的文件路径
    final oldFilePath = getSettingItemFilePath(item);
    final newGroupName = getSettingGroupName(targetGroupUuid);

    // 更新设定项的分组归属
    item.groupUuid = targetGroupUuid;
    item.updatedAt = DateTime.now();

    // 生成新的文件路径
    if (newGroupName.isNotEmpty) {
      item.filePath = '${_sanitizeFileName(newGroupName)}${Platform.pathSeparator}${_sanitizeFileName(item.title)}${GlobalConstants.chapterFileExtension}';
    } else {
      item.filePath = '${_sanitizeFileName(item.title)}${GlobalConstants.chapterFileExtension}';
    }

    // 重命名文件
    final newFilePath = getSettingItemFilePath(item);
    try {
      final oldFile = File(oldFilePath);
      if (await oldFile.exists()) {
        final newFile = File(newFilePath);
        if (!await newFile.parent.exists()) {
          await newFile.parent.create(recursive: true);
        }
        await oldFile.rename(newFilePath);
      }
    } catch (e) {
      debugPrint('移动设定项文件失败: $e');
      return false;
    }

    // 更新组内序号
    final targetGroupItems = _settingItems.where((i) => i.groupUuid == targetGroupUuid && i.uuid != itemUuid).toList();
    item.groupOrderIndex = targetGroupItems.length;

    // 更新数据库
    await _isar.writeTxn(() async {
      await _isar.settingItemModels.put(item);

      if (_currentBook != null) {
        _currentBook!.updatedAt = DateTime.now();
        await _isar.bookModels.put(_currentBook!);
      }
    });

    await _loadSettingItems();
    notifyListeners();
    return true;
  }

  /// 批量删除设定项
  /// [itemUuids] 要删除的设定项UUID列表
  /// 返回成功删除的数量
  Future<int> batchDeleteSettingItems({required List<String> itemUuids}) async {
    if (_currentBook == null || itemUuids.isEmpty) return 0;

    // 取出待删除的设定项对象
    final itemsToDelete = _settingItems
        .where((i) => itemUuids.contains(i.uuid))
        .toList();
    if (itemsToDelete.isEmpty) return 0;

    // 集中关闭已打开的设定项标签页
    for (final item in itemsToDelete) {
      if (_openedTabs.any((t) => t.id == item.uuid)) {
        closeTab(item.uuid);
      }
    }

    // 批量将设定项移入回收站
    await RecycleItemService.instance.moveSettingItemsToRecycleBinBatch(
      items: itemsToDelete,
      bookTitle: _currentBook!.title,
      bookFolderPath: bookFolderPath,
      groupNameOf: getSettingGroupName,
    );

    // 集中删除设定项备份目录
    for (final item in itemsToDelete) {
      await BackupService.instance.deleteSettingBackups(
        _currentBook!.uuid,
        item.title,
      );
    }

    // 删除所有设定项记录、更新书籍修改时间
    await _isar.writeTxn(() async {
      for (final item in itemsToDelete) {
        await _isar.settingItemModels.delete(item.id);
      }

      if (_currentBook != null) {
        _currentBook!.updatedAt = DateTime.now();
        await _isar.bookModels.put(_currentBook!);
      }
    });

    // 一次性刷新设定项列表
    await _loadSettingItems();

    // 通知 UI 刷新并同步书架最近编辑/字数
    notifyListeners();
    _notifyBookshelfRefresh();

    return itemsToDelete.length;
  }

  /// 批量移动设定项到指定分组
  /// [itemUuids] 要移动的设定项UUID列表
  /// [targetGroupUuid] 目标分组UUID，空字符串表示未分组
  /// 返回成功移动的数量
  Future<int> batchMoveSettingItemsToGroup({
    required List<String> itemUuids,
    required String targetGroupUuid,
  }) async {
    if (_currentBook == null) return 0;

    final targetGroupName = getSettingGroupName(targetGroupUuid);

    // 收集可移动的设定项（跳过目标分组相同和目标分组下重名的）
    final itemsToMove = <SettingItemModel>[];
    for (final itemUuid in itemUuids) {
      final item = _settingItems.where((i) => i.uuid == itemUuid).firstOrNull;
      if (item == null) continue;
      if (item.groupUuid == targetGroupUuid) continue;
      // 检查目标分组下是否已存在同名设定项
      final existing = _settingItems.where(
        (i) => i.title == item.title && i.groupUuid == targetGroupUuid,
      );
      if (existing.isNotEmpty) continue;
      itemsToMove.add(item);
    }

    if (itemsToMove.isEmpty) return 0;

    // 计算目标分组内的起始排序序号
    final targetGroupItems = _settingItems.where((i) => i.groupUuid == targetGroupUuid).toList();
    int nextGroupOrderIndex = targetGroupItems.length;

    // 逐个移动文件（文件系统操作无法批量）
    for (final item in itemsToMove) {
      final oldFilePath = getSettingItemFilePath(item);

      // 更新设定项的分组归属和排序
      item.groupUuid = targetGroupUuid;
      item.updatedAt = DateTime.now();
      item.groupOrderIndex = nextGroupOrderIndex++;

      // 生成新的文件相对路径
      final String newRelativePath = targetGroupName.isNotEmpty
          ? '${_sanitizeFileName(targetGroupName)}${Platform.pathSeparator}${_sanitizeFileName(item.title)}${GlobalConstants.chapterFileExtension}'
          : '${_sanitizeFileName(item.title)}${GlobalConstants.chapterFileExtension}';
      item.filePath = newRelativePath;

      // 移动设定项文件
      try {
        final oldFile = File(oldFilePath);
        if (await oldFile.exists()) {
          final newFilePath = getSettingItemFilePath(item);
          final parentDir = Directory(newFilePath).parent;
          if (!await parentDir.exists()) {
            await parentDir.create(recursive: true);
          }
          await oldFile.rename(newFilePath);
        }
      } catch (e) {
        debugPrint('移动设定项文件失败: $e');
      }
    }

    // 单事务批量更新所有设定项记录和书籍修改时间
    await _isar.writeTxn(() async {
      await _isar.settingItemModels.putAll(itemsToMove);
      _currentBook!.updatedAt = DateTime.now();
      await _isar.bookModels.put(_currentBook!);
    });

    // 一次性刷新
    await _loadSettingItems();
    notifyListeners();

    return itemsToMove.length;
  }
  /// 保存当前标签页的内容
  /// 
  /// 返回是否保存成功
  Future<bool> saveCurrentTab() async {
    final tab = currentTab;
    if (tab == null) return false;
    // 章节类型需要文本控制器；大纲类型使用编辑器状态，无需文本控制器
    if (tab.type == EditorTabType.chapter && tab.textController == null) return false;
    
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
      final titleUpdated = await renameSettingItem(itemUuid: item.uuid, newTitle: tab.title);
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
          final titleUpdated = await renameSettingItem(itemUuid: item.uuid, newTitle: tab.title);
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

  /// 通知书架刷新最近编辑与字数显示
  ///
  /// 在书籍内容发生持久化变化（保存章节、删除章节、删除设定项等）后调用。
  /// 独立窗口模式下通过 IPC 通知主窗口；同窗口模式下直接调用书架刷新回调。
  void _notifyBookshelfRefresh() {
    if (_isDisposed) return;
    if (_mainWindowId != null) {
      MultiWindowService.instance.notifyBookUpdated(_mainWindowId!);
    } else if (_onBookSaved != null) {
      _onBookSaved!();
    }
  }

  /// 持久化完成回调：统计写入数据库后通知首页/书架刷新
  ///
  /// 由 WritingSessionTracker 在字数或时长落库后触发。
  void _onSessionFlushed() {
    _notifyBookshelfRefresh();
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
    WindowCacheService.instance.updateSidebarState(workspaceExpanded: _isLeftSidebarExpanded);
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
    WindowCacheService.instance.updateSidebarState(workspaceRightSidebarTypeIndex: index);
  }

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
      tab.textController!.selection = TextSelection.collapsed(offset: content.length);
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
        chapterTab.textController!.selection = TextSelection.collapsed(offset: content.length);
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
    WindowCacheService.instance.updateSidebarWidth(rightWidth: _rightSidebarWidth);
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
            if (_findMatches[i].start == sel.start && _findMatches[i].end == sel.end) {
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
      if (sel.baseOffset == _findMatches[i].start && sel.extentOffset == _findMatches[i].end) {
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
      final searchText = _findCaseSensitive ? _findText : _findText.toLowerCase();
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
      final searchText = _findCaseSensitive ? _findText : _findText.toLowerCase();
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
    if (_currentMatchIndex < 0 || _currentMatchIndex >= _findMatches.length) return;

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
  Future<void> _performGlobalSearch() async {
    if (_globalSearchQuery.isEmpty || _currentBook == null) return;

    _isGlobalSearching = true;
    notifyListeners();

    final results = <GlobalSearchResult>[];
    final searchQuery = _globalSearchCaseSensitive
        ? _globalSearchQuery
        : _globalSearchQuery.toLowerCase();

    for (final chapter in _chapters) {
      try {
        final content = await readChapterContent(chapter);
        if (content.isEmpty) continue;

        // 查找所有匹配位置
        final matchLines = <GlobalSearchMatchLine>[];
        final lines = content.split('\n');
        int lineStartOffset = 0;

        for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
          final line = lines[lineIndex];
          final sourceLine =
              _globalSearchCaseSensitive ? line : line.toLowerCase();

          int searchStart = 0;
          int matchCountInLine = 0;

          while (searchStart < sourceLine.length) {
            final index = sourceLine.indexOf(searchQuery, searchStart);
            if (index == -1) break;
            matchCountInLine++;
            searchStart = index + searchQuery.length;
          }

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
            totalMatches: matchLines.fold<int>(
                0, (sum, m) => sum + m.matchCount),
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

      openTab(EditorTab(
        id: chapter.uuid,
        title: chapter.title,
        type: EditorTabType.chapter,
        isPreview: true,
      ), isPreview: true);

      // 等待内容加载
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // 定位到匹配行的起始偏移量
    final tab = _openedTabs.where((t) => t.id == result.chapterUuid).firstOrNull;
    if (tab?.textController != null) {
      final controller = tab!.textController!;
      final searchQuery = _globalSearchCaseSensitive
          ? _globalSearchQuery
          : _globalSearchQuery.toLowerCase();
      final sourceText = _globalSearchCaseSensitive
          ? controller.text
          : controller.text.toLowerCase();

      // 在匹配行范围内查找第一个匹配位置
      final lineStart = matchLine.startOffset;
      final lineEnd = lineStart + matchLine.lineContent.length;

      int matchOffset = sourceText.indexOf(searchQuery, lineStart);
      if (matchOffset >= 0 && matchOffset < lineEnd) {
        controller.selection = TextSelection(
          baseOffset: matchOffset,
          extentOffset: matchOffset + _globalSearchQuery.length,
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

  // ================= 多标签页方法 =================
  
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
    if (tab.type == EditorTabType.chapter && _currentBook != null && tab.cursorPosition != null) {
      _saveChapterCursorPosition(tab);
    }

    // 释放资源
    tab.textController?.dispose();
    tab.chapterTitleController?.dispose();
    tab.undoManager?.dispose();
  }

  /// 关闭标签页
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
      // debugPrint('已保存章节光标位置: ${tab.title}, offset: ${tab.cursorPosition!.baseOffset}');
    } catch (e) {
      debugPrint('保存章节光标位置失败: $e');
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

  /// 重写通知方法，增加 dispose 状态检查
  ///
  /// 防止在 Provider 被释放后继续通知监听者导致报错
  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  /// 释放资源
  ///
  /// 清理所有打开的标签页控制器，并标记为已释放状态
  @override
  void dispose() {
    // 标记为已释放，防止后续操作
    _isDisposed = true;

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

    // 调用父类的 dispose 方法
    super.dispose();
  }
}

/// 编辑器标签页数据模型
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
  TextEditingController? textController;
  
  /// 章节标题编辑控制器
  TextEditingController? chapterTitleController;
  
  /// 撤销控制器（保存撤销/恢复历史）
  EditorUndoManager? undoManager;
  
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
    this.undoManager,
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
      final selection = textController!.selection;
      if (selection.baseOffset != selection.extentOffset) {
        // 有选中内容：统计选区文本字数
        final selectedText = textController!.text.substring(
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
    undoManager?.dispose();
    _selectedWordCountTimer?.cancel();
    selectedWordCountNotifier.dispose();
  }
}

/// 编辑器标签页类型枚举
enum EditorTabType {
  chapter,       // 章节正文
  settings,       // 设定（大纲、角色、其他设定等）
  backupPreview, // 备份预览（只读）
}

/// 右侧边栏面板类型枚举
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
