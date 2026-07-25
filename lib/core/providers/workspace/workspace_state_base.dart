part of '../workspace_provider.dart';

/// 工作台 Provider 共享状态基类
///
/// 提供跨 Mixin 共享的依赖（Isar 实例、dispose 标志、窗口通信字段、
/// 书架刷新通知、文件夹与迁移服务、标签页列表），并声明 [BookDataMixin]
/// 与 [EditorMixin] 互相调用的协调方法。
abstract class WorkspaceStateBase extends ChangeNotifier {
  // ================= 共享状态 =================

  /// 是否已被释放（防止在 dispose 后继续调用方法导致报错）
  bool _isDisposed = false;

  /// Isar 数据库实例（initialize 中赋值）
  late Isar _isar;

  /// 是否已初始化（整体初始化完成标志，在 initialize 末尾置 true）
  bool _isInitialized = false;

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  // ================= 窗口通信与书架刷新 =================

  /// 主窗口ID（用于向主窗口发送消息）
  String? _mainWindowId;

  /// 同窗口模式下的书籍保存回调（保存章节后通知书架刷新）
  VoidCallback? _onBookSaved;

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

  // ================= 文件夹与迁移服务 =================

  /// 书籍文件夹路径服务（负责书籍文件夹结构维护与路径计算）
  late final BookFolderService _bookFolderService = BookFolderService();

  /// 分卷数据迁移服务（负责从文件系统迁移分卷到数据库，依赖 Isar 与文件夹路径服务）
  late VolumeMigrationService _volumeMigrationService;

  // ================= 跨域共享的标签页列表 =================

  /// 打开的标签页列表
  ///
  /// 由 [EditorMixin] 负责增删（openTab/closeTab 等），
  /// [BookDataMixin] 在删除章节/设定或重命名时需要读取/更新对应标签页。
  final List<EditorTab> _openedTabs = [];

  // ================= 跨 Mixin 协调接口 =================

  /// 关闭指定 ID 的标签页
  ///
  /// 由 [EditorMixin] 实现，供 [BookDataMixin] 在删除章节/设定时调用。
  void closeTab(String tabId);

  /// 保存章节内容到文件并更新数据库
  ///
  /// 由 [BookDataMixin] 实现，供 [EditorMixin] 在保存标签页时调用。
  /// 返回是否保存成功。
  Future<bool> saveChapterContent(ChapterModel chapter, String content);

  /// 读取章节文件内容
  ///
  /// 由 [BookDataMixin] 实现，供 [EditorMixin] 在全文搜索时调用。
  Future<String> readChapterContent(ChapterModel chapter);

  /// 保存指定章节对应的标签页光标位置（若该标签页已打开）
  ///
  /// 由 [EditorMixin] 实现，供 [BookDataMixin] 在保存章节内容后调用，
  /// 以保证无论是手动保存还是自动保存都能持久化光标位置。
  Future<void> saveChapterCursorPositionIfAny(String chapterUuid);

  // ================= notifyListeners 安全重写 =================

  @override
  void notifyListeners() {
    if (!_isDisposed) super.notifyListeners();
  }
}
