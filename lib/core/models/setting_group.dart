import 'package:isar/isar.dart';

// 这行代码表示 Isar 会自动生成一个叫 setting_group.g.dart 的文件
part 'setting_group.g.dart';

/// 设定分组模型
///
/// 定义了设定分组在数据库中的数据结构
/// 设定分组属于某本书籍，包含排序索引以支持拖拽排序
/// 类似于章节的分卷，是设定的分组容器
@collection
class SettingGroupModel {
  // Isar 强制要求必须有一个叫 id 的整型主键
  Id id = Isar.autoIncrement;

  // @Index(unique: true) 表示给这个字段建唯一索引
  @Index(unique: true)
  String uuid = ''; // 分组唯一ID（UUID）

  /// 所属书籍 UUID
  @Index()
  String bookUuid = '';

  /// 分组名称
  String name = '';

  /// 排序索引（用于分组在列表中的显示顺序）
  int orderIndex = 0;

  /// 展开状态（true 表示展开，false 表示折叠）
  bool isExpanded = true;

  /// 创建时间
  DateTime createdAt = DateTime.now();

  /// 最后修改时间
  DateTime updatedAt = DateTime.now();

  SettingGroupModel(); // 默认构造函数，Isar 强制要求有

  /// 创建副本
  SettingGroupModel copyWith({
    String? uuid,
    String? bookUuid,
    String? name,
    int? orderIndex,
    bool? isExpanded,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SettingGroupModel()
      ..id = id
      ..uuid = uuid ?? this.uuid
      ..bookUuid = bookUuid ?? this.bookUuid
      ..name = name ?? this.name
      ..orderIndex = orderIndex ?? this.orderIndex
      ..isExpanded = isExpanded ?? this.isExpanded
      ..createdAt = createdAt ?? this.createdAt
      ..updatedAt = updatedAt ?? this.updatedAt;
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'uuid': uuid,
      'bookUuid': bookUuid,
      'name': name,
      'orderIndex': orderIndex,
      'isExpanded': isExpanded,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// 从 JSON 创建
  factory SettingGroupModel.fromJson(Map<String, dynamic> json) {
    return SettingGroupModel()
      ..uuid = json['uuid'] as String? ?? ''
      ..bookUuid = json['bookUuid'] as String? ?? ''
      ..name = json['name'] as String? ?? ''
      ..orderIndex = json['orderIndex'] as int? ?? 0
      ..isExpanded = json['isExpanded'] as bool? ?? true
      ..createdAt = json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now()
      ..updatedAt = json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now();
  }
}
