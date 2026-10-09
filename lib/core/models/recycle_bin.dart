import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';
import 'package:quick_write/core/utils/word_count_utils.dart';
import 'book.dart';

// 这行代码表示 Isar 会自动生成一个叫 recycle_bin_model.g.dart 的文件
part 'recycle_bin.g.dart';

/// 回收站数据模型
/// 
/// 存储被删除书籍的信息，支持恢复功能
/// 回收站中的书籍文件夹以 UUID 命名，避免同名书籍冲突
@collection
class RecycleBinModel {
  // Isar 强制要求必须有一个叫 id 的整型主键
  Id id = Isar.autoIncrement;

  // @Index(unique: true) 表示给这个字段建唯一索引
  @Index(unique: true)
  String uuid = ''; // 回收站记录的唯一ID（UUID）

  // ================= 原书籍信息 =================
  String bookUuid = ''; // 原书籍的 UUID
  String title = ''; // 书名
  String coverPath = ''; // 封面路径
  String synopsis = ''; // 简介/大纲
  int wordCount = 0; // 总字数
  String latestChapter = '暂无章节'; // 最新章节名
  DateTime updatedAt = DateTime.now(); // 上次编辑时间
  DateTime createdAt = DateTime.now(); // 创建时间
  int orderIndex = 0; // 原排序索引
  String groupId = ''; // 原所属分组 UUID

  // ================= 回收站特有字段 =================
  String recycleFolderName = ''; // 回收站中的文件夹名称（UUID命名）
  String originalFolderName = ''; // 原书籍文件夹名称（用于恢复时检测重名）
  DateTime deletedAt = DateTime.now(); // 删除时间

  RecycleBinModel(); // 默认构造函数，Isar 强制要求有

  // ==========================================
  // UI 展现辅助获取器 (Getters)
  // ==========================================

  /// 格式化字数显示 (例如：125000 -> "12.5万字")
  @ignore
  String get displayWordCount => WordCountUtils.formatWordCount(wordCount);

  /// 格式化删除日期 (例如："2023-10-21")
  @ignore
  String get displayDeletedDate {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String year = deletedAt.year.toString();
    String month = twoDigits(deletedAt.month);
    String day = twoDigits(deletedAt.day);
    return '$year-$month-$day';
  }

  /// 格式化删除时间 (例如："2023-10-21 14:30")
  @ignore
  String get displayDeletedTime {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String year = deletedAt.year.toString();
    String month = twoDigits(deletedAt.month);
    String day = twoDigits(deletedAt.day);
    String hour = twoDigits(deletedAt.hour);
    String minute = twoDigits(deletedAt.minute);
    return '$year-$month-$day $hour:$minute';
  }

  // ==========================================
  // 从 BookModel 创建回收站记录
  // ==========================================
  
  /// 从 BookModel 创建回收站记录
  /// 
  /// [book] 原书籍模型
  /// [recycleFolderName] 回收站中的文件夹名称（UUID）
  factory RecycleBinModel.fromBookModel(BookModel book, String recycleFolderName) {
    return RecycleBinModel()
      ..uuid = const Uuid().v4() // 生成新的 UUID 作为回收站记录 ID
      ..bookUuid = book.uuid
      ..title = book.title
      ..coverPath = book.coverPath
      ..synopsis = book.synopsis
      ..wordCount = book.wordCount
      ..latestChapter = book.latestChapter
      ..updatedAt = book.updatedAt
      ..createdAt = book.createdAt
      ..orderIndex = book.orderIndex
      ..groupId = book.groupId
      ..recycleFolderName = recycleFolderName
      ..originalFolderName = book.title
      ..deletedAt = DateTime.now();
  }

  // ==========================================
  // 转换为 BookModel（用于恢复）
  // ==========================================
  
  /// 转换为 BookModel（用于恢复）
  /// 
  /// [newTitle] 恢复后的新书名（如果有重名冲突，需要新名称）
  /// [newOrderIndex] 恢复后的排序索引
  BookModel toBookModel({String? newTitle, int? newOrderIndex}) {
    return BookModel()
      ..uuid = bookUuid // 保留原 UUID
      ..title = newTitle ?? title
      ..coverPath = coverPath
      ..synopsis = synopsis
      ..wordCount = wordCount
      ..latestChapter = latestChapter
      // 恢复本身即一次修改，修改时间需更新，否则会被判定为早于删除记录
      ..updatedAt = DateTime.now()
      ..createdAt = createdAt
      ..orderIndex = newOrderIndex ?? orderIndex
      ..groupId = groupId;
  }

  // ==========================================
  // 数据库序列化预留 (JSON 互转)
  // ==========================================
  Map<String, dynamic> toJson() {
    return {
      'uuid': uuid,
      'bookUuid': bookUuid,
      'title': title,
      'coverPath': coverPath,
      'synopsis': synopsis,
      'wordCount': wordCount,
      'latestChapter': latestChapter,
      'updatedAt': updatedAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'orderIndex': orderIndex,
      'groupId': groupId,
      'recycleFolderName': recycleFolderName,
      'originalFolderName': originalFolderName,
      'deletedAt': deletedAt.toIso8601String(),
    };
  }

  factory RecycleBinModel.fromJson(Map<String, dynamic> json) {
    return RecycleBinModel()
      ..uuid = json['uuid'] as String? ?? ''
      ..bookUuid = json['bookUuid'] as String? ?? ''
      ..title = json['title'] as String? ?? ''
      ..coverPath = json['coverPath'] as String? ?? ''
      ..synopsis = json['synopsis'] as String? ?? ''
      ..wordCount = json['wordCount'] as int? ?? 0
      ..latestChapter = json['latestChapter'] as String? ?? '暂无章节'
      ..updatedAt = json['updatedAt'] != null ? DateTime.parse(json['updatedAt'] as String) : DateTime.now()
      ..createdAt = json['createdAt'] != null ? DateTime.parse(json['createdAt'] as String) : DateTime.now()
      ..orderIndex = json['orderIndex'] as int? ?? 0
      ..groupId = json['groupId'] as String? ?? ''
      ..recycleFolderName = json['recycleFolderName'] as String? ?? ''
      ..originalFolderName = json['originalFolderName'] as String? ?? ''
      ..deletedAt = json['deletedAt'] != null ? DateTime.parse(json['deletedAt'] as String) : DateTime.now();
  }
}
