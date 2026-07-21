import 'package:isar/isar.dart';
import 'package:quick_write/core/utils/word_count_utils.dart';

// 这行代码表示 Isar 会自动生成一个叫 book_model.g.dart 的文件
// 即使这个文件现在还不存在（会报错），也必须要先写上
part 'book.g.dart';

/// 书籍模型
/// 
/// 定义了书籍在数据库中的数据结构，包括字段、索引、约束等
@collection
class BookModel {
  // Isar 强制要求必须有一个叫 id 的整型主键（Id 类型）
  // 使用 Isar.autoIncrement 让数据库自动分配自增 ID
  Id id = Isar.autoIncrement;

  // @Index(unique: true) 表示给这个字段建唯一索引，查询极快，且不能重复
  @Index(unique: true)
  
  String uuid = ''; // 唯一ID（UUID，用于应对重装软件或跨设备同步）
  
  String title = ''; // 书名
  String coverPath = ''; // 封面路径
  String synopsis = ''; // 简介/大纲 (非必填，预留字段)
  int wordCount = 0; // 总字数
  String latestChapter = '暂无章节'; // 最新章节名
  
  // Dart 允许直接使用 DateTime.now() 作为实例变量的初始值
  DateTime updatedAt = DateTime.now(); // 上次编辑时间
  DateTime createdAt = DateTime.now(); // 创建时间
  
  int orderIndex = 0; // 排序索引
  
  /// 所属分组 UUID（空字符串表示未分组，即"全部作品"）
  String groupId = '';

  BookModel(); // 默认构造函数，Isar 强制要求有

  // ==========================================
  // UI 展现辅助获取器 (Getters)
  // 把纯数据格式化为 UI 需要的字符串，UI 层直接调用这些属性即可
  // ==========================================

  // 格式化字数显示 (例如：125000 -> "12.5万字")
  // @ignore:明确告诉 Isar 引擎，这个只是用来显示的计算属性，不要把它们存进数据库
  @ignore 
  String get displayWordCount => WordCountUtils.formatWordCount(wordCount);

  // 格式化最后编辑时间 (例如："2023-10-21 14:30")
  // @ignore:明确告诉 Isar 引擎，这个只是用来显示的计算属性，不要把它们存进数据库
  @ignore 
  String get displayLastEditTime {
    // 补齐两位的辅助函数 (如 9 -> "09")
    String twoDigits(int n) => n.toString().padLeft(2, '0');

    String year = updatedAt.year.toString();
    String month = twoDigits(updatedAt.month);
    String day = twoDigits(updatedAt.day);
    String hour = twoDigits(updatedAt.hour);
    String minute = twoDigits(updatedAt.minute);

    // 如果是今天，可以优化显示为 "今天 14:30" (这里提供基础版)
    return '$year-$month-$day $hour:$minute';
  }

  // ==========================================
  // 状态管理：copyWith
  // 创建副本，用于在不改变原对象其他属性的情况下，修改某几个特定属性（比如只更新排序序号或字数）
  // ==========================================
  BookModel copyWith({
    String? uuid,
    String? title,
    String? coverPath,
    String? synopsis,
    int? wordCount,
    String? latestChapter,
    DateTime? updatedAt,
    DateTime? createdAt,
    int? orderIndex,
    String? groupId,
  }) {
    return BookModel()
      ..id = id // 极其重要：保留原底层 ID
      ..uuid = uuid ?? this.uuid
      ..title = title ?? this.title
      ..coverPath = coverPath ?? this.coverPath
      ..synopsis = synopsis ?? this.synopsis
      ..wordCount = wordCount ?? this.wordCount
      ..latestChapter = latestChapter ?? this.latestChapter
      ..updatedAt = updatedAt ?? this.updatedAt
      ..createdAt = createdAt ?? this.createdAt
      ..orderIndex = orderIndex ?? this.orderIndex
      ..groupId = groupId ?? this.groupId;
  }

  // ==========================================
  // 数据库序列化预留 (JSON 互转)
  // ==========================================
  Map<String, dynamic> toJson() {
    return {
      'uuid': uuid,
      'title': title,
      'coverPath': coverPath,
      'synopsis': synopsis,
      'wordCount': wordCount,
      'latestChapter': latestChapter,
      'updatedAt': updatedAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'orderIndex': orderIndex,
      'groupId': groupId,
    };
  }

  factory BookModel.fromJson(Map<String, dynamic> json) {
    return BookModel()
      ..uuid = json['uuid'] as String? ?? ''
      ..title = json['title'] as String? ?? ''
      ..coverPath = json['coverPath'] as String? ?? ''
      ..synopsis = json['synopsis'] as String? ?? ''
      ..wordCount = json['wordCount'] as int? ?? 0
      ..latestChapter = json['latestChapter'] as String? ?? '暂无章节'
      ..updatedAt = json['updatedAt'] != null ? DateTime.parse(json['updatedAt'] as String) : DateTime.now()
      ..createdAt = json['createdAt'] != null ? DateTime.parse(json['createdAt'] as String) : DateTime.now()
      ..orderIndex = json['orderIndex'] as int? ?? 0
      ..groupId = json['groupId'] as String? ?? '';
  }
}
