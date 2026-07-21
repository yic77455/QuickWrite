import 'package:isar/isar.dart';

// 这行代码表示 Isar 会自动生成一个叫 chapter.g.dart 的文件
part 'chapter.g.dart';

/// 章节模型
/// 
/// 定义了章节在数据库中的数据结构
/// 支持分卷功能，同一卷下的章节按 orderIndex 排序
@collection
class ChapterModel {
  // Isar 强制要求必须有一个叫 id 的整型主键
  Id id = Isar.autoIncrement;

  // @Index(unique: true) 表示给这个字段建唯一索引
  @Index(unique: true)
  String uuid = ''; // 章节唯一ID（UUID）

  /// 所属书籍 UUID
  @Index()
  String bookUuid = '';

  /// 章节标题
  String title = '';

  /// 所属分卷 UUID（空字符串表示未分卷）
  /// 通过 UUID 引用分卷，重命名分卷时无需级联更新
  @Index()
  String volumeUuid = '';

  /// 章节序号（用于排序，从1开始）
  /// 这是全局序号，不区分分卷
  int orderIndex = 0;

  /// 卷内序号（在当前卷内的排序）
  /// 如果没有分卷，则与 orderIndex 相同
  int volumeOrderIndex = 0;

  /// 字数
  int wordCount = 0;

  /// 章节文件相对路径（相对于书籍的 chapters 目录）
  /// 例如："第一卷/第一章 开端.txt" 或 "第一章 开端.txt"
  String filePath = '';

  /// 创建时间
  DateTime createdAt = DateTime.now();

  /// 最后修改时间
  DateTime updatedAt = DateTime.now();

  ChapterModel(); // 默认构造函数，Isar 强制要求有

  /// 创建副本
  ChapterModel copyWith({
    String? uuid,
    String? bookUuid,
    String? title,
    String? volumeUuid,
    int? orderIndex,
    int? volumeOrderIndex,
    int? wordCount,
    String? filePath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ChapterModel()
      ..id = id
      ..uuid = uuid ?? this.uuid
      ..bookUuid = bookUuid ?? this.bookUuid
      ..title = title ?? this.title
      ..volumeUuid = volumeUuid ?? this.volumeUuid
      ..orderIndex = orderIndex ?? this.orderIndex
      ..volumeOrderIndex = volumeOrderIndex ?? this.volumeOrderIndex
      ..wordCount = wordCount ?? this.wordCount
      ..filePath = filePath ?? this.filePath
      ..createdAt = createdAt ?? this.createdAt
      ..updatedAt = updatedAt ?? this.updatedAt;
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'uuid': uuid,
      'bookUuid': bookUuid,
      'title': title,
      'volumeUuid': volumeUuid,
      'orderIndex': orderIndex,
      'volumeOrderIndex': volumeOrderIndex,
      'wordCount': wordCount,
      'filePath': filePath,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// 从 JSON 创建
  factory ChapterModel.fromJson(Map<String, dynamic> json) {
    return ChapterModel()
      ..uuid = json['uuid'] as String? ?? ''
      ..bookUuid = json['bookUuid'] as String? ?? ''
      ..title = json['title'] as String? ?? ''
      ..volumeUuid = json['volumeUuid'] as String? ?? ''
      ..orderIndex = json['orderIndex'] as int? ?? 0
      ..volumeOrderIndex = json['volumeOrderIndex'] as int? ?? 0
      ..wordCount = json['wordCount'] as int? ?? 0
      ..filePath = json['filePath'] as String? ?? ''
      ..createdAt = json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now()
      ..updatedAt = json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now();
  }
}
