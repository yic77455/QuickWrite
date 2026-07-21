import 'package:isar/isar.dart';

part 'group.g.dart';

/// 书籍分组模型
/// 
/// 用于对书籍进行分类管理，用户可以自定义分组名称
@collection
class GroupModel {
  Id id = Isar.autoIncrement;

  /// 分组名称
  String name = '';

  /// 分组唯一标识符
  @Index(unique: true)
  String uuid = '';

  /// 排序索引（用于分组在列表中的显示顺序）
  int orderIndex = 0;

  /// 创建时间
  DateTime createdAt = DateTime.now();

  GroupModel();

  /// 创建副本
  GroupModel copyWith({
    String? name,
    String? uuid,
    int? orderIndex,
    DateTime? createdAt,
  }) {
    return GroupModel()
      ..id = id
      ..name = name ?? this.name
      ..uuid = uuid ?? this.uuid
      ..orderIndex = orderIndex ?? this.orderIndex
      ..createdAt = createdAt ?? this.createdAt;
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'uuid': uuid,
      'name': name,
      'orderIndex': orderIndex,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// 从 JSON 创建
  factory GroupModel.fromJson(Map<String, dynamic> json) {
    return GroupModel()
      ..uuid = json['uuid'] as String? ?? ''
      ..name = json['name'] as String? ?? ''
      ..orderIndex = json['orderIndex'] as int? ?? 0
      ..createdAt = json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now();
  }
}
