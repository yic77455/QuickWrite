/// 章节光标位置缓存数据模型
///
/// 用于存储每本书每个章节最后一次编辑或关闭时的光标位置
/// 支持按书籍分组管理章节光标位置
class ChapterCursorCacheData {
  /// 书籍光标位置映射
  /// 
  /// Key: 书籍 UUID
  /// Value: 该书籍下所有章节的光标位置映射
  final Map<String, BookCursorCache> books;

  /// 默认构造函数
  const ChapterCursorCacheData({
    this.books = const {},
  });

  /// 从 JSON Map 创建实例
  factory ChapterCursorCacheData.fromJson(Map<String, dynamic> json) {
    final booksMap = json['books'] as Map<String, dynamic>? ?? {};
    final books = <String, BookCursorCache>{};
    
    booksMap.forEach((bookUuid, bookData) {
      books[bookUuid] = BookCursorCache.fromJson(bookData as Map<String, dynamic>);
    });
    
    return ChapterCursorCacheData(books: books);
  }

  /// 转换为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'books': books.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  /// 获取指定书籍和章节的光标位置
  ///
  /// [bookUuid] 书籍 UUID
  /// [chapterUuid] 章节 UUID
  /// 返回光标位置，如果不存在则返回 null
  ChapterCursorPosition? getCursorPosition(String bookUuid, String chapterUuid) {
    return books[bookUuid]?.chapters[chapterUuid];
  }

  /// 设置指定书籍和章节的光标位置
  ///
  /// [bookUuid] 书籍 UUID
  /// [chapterUuid] 章节 UUID
  /// [position] 光标位置
  ChapterCursorCacheData withCursorPosition(
    String bookUuid,
    String chapterUuid,
    ChapterCursorPosition position,
  ) {
    final newBooks = Map<String, BookCursorCache>.from(books);
    
    if (!newBooks.containsKey(bookUuid)) {
      newBooks[bookUuid] = BookCursorCache(chapters: {});
    }
    
    newBooks[bookUuid] = newBooks[bookUuid]!.withChapter(chapterUuid, position);
    
    return ChapterCursorCacheData(books: newBooks);
  }

  /// 移除指定书籍的所有光标位置缓存
  ///
  /// [bookUuid] 书籍 UUID
  ChapterCursorCacheData withoutBook(String bookUuid) {
    final newBooks = Map<String, BookCursorCache>.from(books);
    newBooks.remove(bookUuid);
    return ChapterCursorCacheData(books: newBooks);
  }

  /// 移除指定章节的光标位置缓存
  ///
  /// [bookUuid] 书籍 UUID
  /// [chapterUuid] 章节 UUID
  ChapterCursorCacheData withoutChapter(String bookUuid, String chapterUuid) {
    final newBooks = Map<String, BookCursorCache>.from(books);
    
    if (newBooks.containsKey(bookUuid)) {
      newBooks[bookUuid] = newBooks[bookUuid]!.withoutChapter(chapterUuid);
      
      if (newBooks[bookUuid]!.chapters.isEmpty) {
        newBooks.remove(bookUuid);
      }
    }
    
    return ChapterCursorCacheData(books: newBooks);
  }

  /// 清空所有缓存
  ChapterCursorCacheData clear() {
    return const ChapterCursorCacheData();
  }
}

/// 单本书籍的光标位置缓存
class BookCursorCache {
  /// 章节光标位置映射
  /// 
  /// Key: 章节 UUID
  /// Value: 该章节的光标位置
  final Map<String, ChapterCursorPosition> chapters;

  const BookCursorCache({
    this.chapters = const {},
  });

  /// 从 JSON Map 创建实例
  factory BookCursorCache.fromJson(Map<String, dynamic> json) {
    final chaptersMap = json['chapters'] as Map<String, dynamic>? ?? {};
    final chapters = <String, ChapterCursorPosition>{};
    
    chaptersMap.forEach((chapterUuid, chapterData) {
      chapters[chapterUuid] = ChapterCursorPosition.fromJson(chapterData as Map<String, dynamic>);
    });
    
    return BookCursorCache(chapters: chapters);
  }

  /// 转换为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'chapters': chapters.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  /// 添加或更新章节光标位置
  BookCursorCache withChapter(String chapterUuid, ChapterCursorPosition position) {
    final newChapters = Map<String, ChapterCursorPosition>.from(chapters);
    newChapters[chapterUuid] = position;
    return BookCursorCache(chapters: newChapters);
  }

  /// 移除章节光标位置
  BookCursorCache withoutChapter(String chapterUuid) {
    final newChapters = Map<String, ChapterCursorPosition>.from(chapters);
    newChapters.remove(chapterUuid);
    return BookCursorCache(chapters: newChapters);
  }
}

/// 章节光标位置
class ChapterCursorPosition {
  /// 光标偏移量（字符位置）
  final int offset;

  /// 最后更新时间
  final DateTime updatedAt;

  const ChapterCursorPosition({
    required this.offset,
    required this.updatedAt,
  });

  /// 从 JSON Map 创建实例
  factory ChapterCursorPosition.fromJson(Map<String, dynamic> json) {
    return ChapterCursorPosition(
      offset: json['offset'] as int? ?? 0,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  /// 转换为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'offset': offset,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// 创建副本
  ChapterCursorPosition copyWith({
    int? offset,
    DateTime? updatedAt,
  }) {
    return ChapterCursorPosition(
      offset: offset ?? this.offset,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
