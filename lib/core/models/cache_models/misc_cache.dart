/// 杂项缓存数据模型
///
/// 用于存储各类零散的缓存数据，避免创建过多小文件
///
/// 缓存内容包括：
/// - 书架上当前选中的分组 ID（应用重启后恢复）
/// - 每本书的已展开设定分类 ID 列表
class MiscCacheData {
  /// 书架选中的分组 ID
  ///
  /// - 空字符串 '' 表示"书架（未分组）"
  /// - '__all__' 表示"全部作品"
  /// - 其他为分组 UUID
  final String selectedGroupId;

  /// 章节列表是否倒序排列
  final bool isChapterReversed;

  /// 设定列表是否倒序排列
  final bool isSettingReversed;

  /// 统计界面是否包含粘贴字数
  final bool statsIncludePasteWords;

  /// 书籍展开状态映射
  ///
  /// Key: 书籍 UUID
  /// Value: 该书籍下分组的展开状态
  final Map<String, BookGroupExpandCache> books;

  const MiscCacheData({
    this.selectedGroupId = '',
    this.isChapterReversed = false,
    this.isSettingReversed = false,
    this.statsIncludePasteWords = false,
    this.books = const {},
  });

  /// 从 JSON Map 创建实例
  factory MiscCacheData.fromJson(Map<String, dynamic> json) {
    // 解析书籍展开状态映射
    final booksMap = json['books'] as Map<String, dynamic>? ?? {};
    final books = <String, BookGroupExpandCache>{};

    booksMap.forEach((bookUuid, bookData) {
      books[bookUuid] = BookGroupExpandCache.fromJson(bookData as Map<String, dynamic>);
    });

    return MiscCacheData(
      selectedGroupId: json['selectedGroupId'] as String? ?? '',
      isChapterReversed: json['isChapterReversed'] as bool? ?? false,
      isSettingReversed: json['isSettingReversed'] as bool? ?? false,
      statsIncludePasteWords: json['statsIncludePasteWords'] as bool? ?? false,
      books: books,
    );
  }

  /// 转换为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'selectedGroupId': selectedGroupId,
      'isChapterReversed': isChapterReversed,
      'isSettingReversed': isSettingReversed,
      'statsIncludePasteWords': statsIncludePasteWords,
      'books': books.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  /// 创建副本
  MiscCacheData copyWith({
    String? selectedGroupId,
    bool? isChapterReversed,
    bool? isSettingReversed,
    bool? statsIncludePasteWords,
    Map<String, BookGroupExpandCache>? books,
  }) {
    return MiscCacheData(
      selectedGroupId: selectedGroupId ?? this.selectedGroupId,
      isChapterReversed: isChapterReversed ?? this.isChapterReversed,
      isSettingReversed: isSettingReversed ?? this.isSettingReversed,
      statsIncludePasteWords: statsIncludePasteWords ?? this.statsIncludePasteWords,
      books: books ?? this.books,
    );
  }
}

/// 单本书籍的分组展开状态缓存
class BookGroupExpandCache {
  /// 未分卷组是否折叠
  final bool isUnassignedCollapsed;

  /// 已展开的设定分类 ID 列表
  final List<String> expandedCategories;

  /// 新建章节时上次选择的分卷 UUID
  ///
  /// 空字符串表示"未分卷"，用于记忆顶部操作栏新建弹窗中的分卷选择
  final String lastSelectedVolume;

  const BookGroupExpandCache({
    this.isUnassignedCollapsed = false,
    this.expandedCategories = const [],
    this.lastSelectedVolume = '',
  });

  /// 从 JSON Map 创建实例
  factory BookGroupExpandCache.fromJson(Map<String, dynamic> json) {
    return BookGroupExpandCache(
      isUnassignedCollapsed: json['isUnassignedCollapsed'] as bool? ?? false,
      expandedCategories: (json['expandedCategories'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      lastSelectedVolume: json['lastSelectedVolume'] as String? ?? '',
    );
  }

  /// 转换为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'isUnassignedCollapsed': isUnassignedCollapsed,
      'expandedCategories': expandedCategories,
      'lastSelectedVolume': lastSelectedVolume,
    };
  }

  /// 创建副本
  BookGroupExpandCache copyWith({
    bool? isUnassignedCollapsed,
    List<String>? expandedCategories,
    String? lastSelectedVolume,
  }) {
    return BookGroupExpandCache(
      isUnassignedCollapsed: isUnassignedCollapsed ?? this.isUnassignedCollapsed,
      expandedCategories: expandedCategories ?? this.expandedCategories,
      lastSelectedVolume: lastSelectedVolume ?? this.lastSelectedVolume,
    );
  }
}
