/// 工作台会话缓存数据模型
///
/// 用于存储每本书最后一次退出工作台时打开的标签页会话，
/// 以便再次打开作品时恢复标签页。支持按书籍分组管理。
class WorkspaceSessionCacheData {
  /// 书籍会话映射
  ///
  /// Key: 书籍 UUID
  /// Value: 该书籍的标签页会话
  final Map<String, BookTabSession> books;

  const WorkspaceSessionCacheData({
    this.books = const {},
  });

  /// 从 JSON Map 创建实例
  factory WorkspaceSessionCacheData.fromJson(Map<String, dynamic> json) {
    final booksMap = json['books'] as Map<String, dynamic>? ?? {};
    final books = <String, BookTabSession>{};

    booksMap.forEach((bookUuid, bookData) {
      books[bookUuid] = BookTabSession.fromJson(bookData as Map<String, dynamic>);
    });

    return WorkspaceSessionCacheData(books: books);
  }

  /// 转换为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'books': books.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  /// 获取指定书籍的标签页会话
  BookTabSession? getSession(String bookUuid) {
    return books[bookUuid];
  }

  /// 设置指定书籍的标签页会话
  WorkspaceSessionCacheData withSession(String bookUuid, BookTabSession session) {
    final newBooks = Map<String, BookTabSession>.from(books);
    newBooks[bookUuid] = session;
    return WorkspaceSessionCacheData(books: newBooks);
  }

  /// 移除指定书籍的会话缓存
  WorkspaceSessionCacheData withoutBook(String bookUuid) {
    final newBooks = Map<String, BookTabSession>.from(books);
    newBooks.remove(bookUuid);
    return WorkspaceSessionCacheData(books: newBooks);
  }

  /// 清空所有缓存
  WorkspaceSessionCacheData clear() {
    return const WorkspaceSessionCacheData();
  }
}

/// 单本书籍的标签页会话
class BookTabSession {
  /// 打开的标签页列表（按打开顺序）
  final List<TabSessionEntry> tabs;

  /// 退出时选中的标签页索引（-1 表示无选中）
  final int currentIndex;

  const BookTabSession({
    this.tabs = const [],
    this.currentIndex = -1,
  });

  /// 从 JSON Map 创建实例
  factory BookTabSession.fromJson(Map<String, dynamic> json) {
    return BookTabSession(
      tabs: (json['tabs'] as List<dynamic>?)
              ?.map((e) => TabSessionEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      currentIndex: json['currentIndex'] as int? ?? -1,
    );
  }

  /// 转换为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'tabs': tabs.map((e) => e.toJson()).toList(),
      'currentIndex': currentIndex,
    };
  }
}

/// 标签页会话条目
///
/// 仅记录恢复标签页所需的最小信息：标识、标题与类型
class TabSessionEntry {
  /// 标签页唯一标识（章节ID或设定ID）
  final String id;

  /// 标签页标题
  final String title;

  /// 标签页类型（EditorTabType 的枚举名称）
  final String type;

  const TabSessionEntry({
    required this.id,
    required this.title,
    required this.type,
  });

  /// 从 JSON Map 创建实例
  factory TabSessionEntry.fromJson(Map<String, dynamic> json) {
    return TabSessionEntry(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      type: json['type'] as String? ?? '',
    );
  }

  /// 转换为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'type': type,
    };
  }
}