/// 大纲上次编辑节点缓存数据模型
///
/// 用于存储每本书每个设定项最后一次编辑的节点位置，
/// 供「打开文件时」的「上一次编辑」模式定位使用。
/// 数据仅保存在应用缓存中，不写入用户的设定项文件。
class OutlineLastEditCacheData {
  /// 书籍缓存映射
  ///
  /// Key: 书籍 UUID
  /// Value: 该书籍下各设定项的上次编辑记录
  final Map<String, BookOutlineLastEditCache> books;

  const OutlineLastEditCacheData({
    this.books = const {},
  });

  /// 从 JSON Map 创建实例
  factory OutlineLastEditCacheData.fromJson(Map<String, dynamic> json) {
    final booksMap = json['books'] as Map<String, dynamic>? ?? {};
    final books = <String, BookOutlineLastEditCache>{};

    booksMap.forEach((bookUuid, bookData) {
      books[bookUuid] = BookOutlineLastEditCache.fromJson(bookData as Map<String, dynamic>);
    });

    return OutlineLastEditCacheData(books: books);
  }

  /// 转换为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'books': books.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  /// 获取指定设定项上次编辑节点的路径
  ///
  /// 未记录时返回 null
  String? getLastEditedPath(String bookUuid, String settingItemUuid) {
    return books[bookUuid]?.items[settingItemUuid]?.path;
  }

  /// 记录指定设定项上次编辑节点的路径
  OutlineLastEditCacheData withLastEditedPath(
    String bookUuid,
    String settingItemUuid,
    OutlineLastEditPosition position,
  ) {
    final newBooks = Map<String, BookOutlineLastEditCache>.from(books);
    final bookCache = newBooks[bookUuid] ?? const BookOutlineLastEditCache();
    newBooks[bookUuid] = bookCache.withItem(settingItemUuid, position);
    return OutlineLastEditCacheData(books: newBooks);
  }

  /// 移除指定设定项的上次编辑记录
  OutlineLastEditCacheData withoutSettingItem(String bookUuid, String settingItemUuid) {
    final newBooks = Map<String, BookOutlineLastEditCache>.from(books);
    final bookCache = newBooks[bookUuid];
    if (bookCache == null) return this;

    final updated = bookCache.withoutItem(settingItemUuid);
    // 书籍下已无任何记录时一并移除，避免残留空分组
    if (updated.items.isEmpty) {
      newBooks.remove(bookUuid);
    } else {
      newBooks[bookUuid] = updated;
    }
    return OutlineLastEditCacheData(books: newBooks);
  }

  /// 移除指定书籍的所有上次编辑记录
  OutlineLastEditCacheData withoutBook(String bookUuid) {
    final newBooks = Map<String, BookOutlineLastEditCache>.from(books);
    newBooks.remove(bookUuid);
    return OutlineLastEditCacheData(books: newBooks);
  }

  /// 清空所有缓存
  OutlineLastEditCacheData clear() {
    return const OutlineLastEditCacheData();
  }
}

/// 单本书籍的大纲上次编辑记录
class BookOutlineLastEditCache {
  /// 设定项上次编辑记录映射
  ///
  /// Key: 设定项 UUID
  /// Value: 该设定项上次编辑的节点位置
  final Map<String, OutlineLastEditPosition> items;

  const BookOutlineLastEditCache({
    this.items = const {},
  });

  /// 从 JSON Map 创建实例
  factory BookOutlineLastEditCache.fromJson(Map<String, dynamic> json) {
    final itemsMap = json['items'] as Map<String, dynamic>? ?? {};
    final items = <String, OutlineLastEditPosition>{};

    itemsMap.forEach((itemUuid, itemData) {
      items[itemUuid] = OutlineLastEditPosition.fromJson(itemData as Map<String, dynamic>);
    });

    return BookOutlineLastEditCache(items: items);
  }

  /// 转换为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'items': items.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  /// 记录指定设定项的上次编辑位置
  BookOutlineLastEditCache withItem(String settingItemUuid, OutlineLastEditPosition position) {
    final newItems = Map<String, OutlineLastEditPosition>.from(items);
    newItems[settingItemUuid] = position;
    return BookOutlineLastEditCache(items: newItems);
  }

  /// 移除指定设定项的上次编辑位置
  BookOutlineLastEditCache withoutItem(String settingItemUuid) {
    final newItems = Map<String, OutlineLastEditPosition>.from(items);
    newItems.remove(settingItemUuid);
    return BookOutlineLastEditCache(items: newItems);
  }
}

/// 大纲上次编辑节点位置
class OutlineLastEditPosition {
  /// 节点自根节点起的层级索引路径（如 `0.2.1`）
  ///
  /// 节点 ID 每次解析文件都会重新生成，无法跨次加载对应到同一节点，
  /// 因此与折叠状态一致，使用层级索引路径标识节点。
  final String path;

  /// 最后更新时间
  final DateTime updatedAt;

  const OutlineLastEditPosition({
    required this.path,
    required this.updatedAt,
  });

  /// 从 JSON Map 创建实例
  factory OutlineLastEditPosition.fromJson(Map<String, dynamic> json) {
    return OutlineLastEditPosition(
      path: json['path'] as String? ?? '',
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  /// 转换为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
