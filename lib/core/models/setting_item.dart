import 'package:isar/isar.dart';

// 这行代码表示 Isar 会自动生成一个叫 setting_item.g.dart 的文件
part 'setting_item.g.dart';

/// 设定项模型
///
/// 定义了设定项在数据库中的数据结构
/// 支持分组功能，同一组下的设定项按 orderIndex 排序
/// 类似于章节，是设定的具体内容条目
@collection
class SettingItemModel {
  // Isar 强制要求必须有一个叫 id 的整型主键
  Id id = Isar.autoIncrement;

  // @Index(unique: true) 表示给这个字段建唯一索引
  @Index(unique: true)
  String uuid = ''; // 设定项唯一ID（UUID）

  /// 所属书籍 UUID
  @Index()
  String bookUuid = '';

  /// 设定项标题
  String title = '';

  /// 所属分组 UUID（空字符串表示未分组）
  /// 通过 UUID 引用分组，重命名分组时无需级联更新
  @Index()
  String groupUuid = '';

  /// 设定项序号（用于排序，从1开始）
  /// 这是全局序号，不区分分组
  int orderIndex = 0;

  /// 组内序号（在当前分组内的排序）
  /// 如果没有分组，则与 orderIndex 相同
  int groupOrderIndex = 0;

  /// 字数
  int wordCount = 0;

  /// 设定项文件相对路径（相对于书籍的 settings 目录）
  /// 例如："角色设定/主角 - 李明.txt" 或 "世界观设定.txt"
  String filePath = '';

  /// 创建时间
  DateTime createdAt = DateTime.now();

  /// 最后修改时间
  DateTime updatedAt = DateTime.now();

  SettingItemModel(); // 默认构造函数，Isar 强制要求有

  /// 创建副本
  SettingItemModel copyWith({
    String? uuid,
    String? bookUuid,
    String? title,
    String? groupUuid,
    int? orderIndex,
    int? groupOrderIndex,
    int? wordCount,
    String? filePath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SettingItemModel()
      ..id = id
      ..uuid = uuid ?? this.uuid
      ..bookUuid = bookUuid ?? this.bookUuid
      ..title = title ?? this.title
      ..groupUuid = groupUuid ?? this.groupUuid
      ..orderIndex = orderIndex ?? this.orderIndex
      ..groupOrderIndex = groupOrderIndex ?? this.groupOrderIndex
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
      'groupUuid': groupUuid,
      'orderIndex': orderIndex,
      'groupOrderIndex': groupOrderIndex,
      'wordCount': wordCount,
      'filePath': filePath,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// 从 JSON 创建
  factory SettingItemModel.fromJson(Map<String, dynamic> json) {
    return SettingItemModel()
      ..uuid = json['uuid'] as String? ?? ''
      ..bookUuid = json['bookUuid'] as String? ?? ''
      ..title = json['title'] as String? ?? ''
      ..groupUuid = json['groupUuid'] as String? ?? ''
      ..orderIndex = json['orderIndex'] as int? ?? 0
      ..groupOrderIndex = json['groupOrderIndex'] as int? ?? 0
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
