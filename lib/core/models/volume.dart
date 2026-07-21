import 'package:isar/isar.dart';

// 这行代码表示 Isar 会自动生成一个叫 volume.g.dart 的文件
part 'volume.g.dart';

/// 分卷模型
///
/// 定义了分卷在数据库中的数据结构
/// 分卷属于某本书籍，包含排序索引以支持拖拽排序
@collection
class VolumeModel {
  // Isar 强制要求必须有一个叫 id 的整型主键
  Id id = Isar.autoIncrement;

  // @Index(unique: true) 表示给这个字段建唯一索引
  @Index(unique: true)
  String uuid = ''; // 分卷唯一ID（UUID）

  /// 所属书籍 UUID
  @Index()
  String bookUuid = '';

  /// 分卷名称
  String name = '';

  /// 排序索引（用于分卷在列表中的显示顺序）
  int orderIndex = 0;

  /// 展开状态（true 表示展开，false 表示折叠）
  bool isExpanded = true;

  /// 创建时间
  DateTime createdAt = DateTime.now();

  /// 最后修改时间
  DateTime updatedAt = DateTime.now();

  VolumeModel(); // 默认构造函数，Isar 强制要求有

  /// 创建副本
  VolumeModel copyWith({
    String? uuid,
    String? bookUuid,
    String? name,
    int? orderIndex,
    bool? isExpanded,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return VolumeModel()
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
  factory VolumeModel.fromJson(Map<String, dynamic> json) {
    return VolumeModel()
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
