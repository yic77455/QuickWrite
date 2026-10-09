import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';
import 'package:quick_write/core/utils/word_count_utils.dart';
import 'chapter.dart';
import 'setting_item.dart';

// 这行代码表示 Isar 会自动生成一个叫 recycle_item.g.dart 的文件
part 'recycle_item.g.dart';

/// 回收站项类型枚举
///
/// 区分回收项是章节还是设定项
/// 使用字符串存储以兼容 Isar 索引
enum RecycleItemType {
  /// 章节类型
  chapter('chapter'),
  /// 设定项类型
  setting('setting');

  final String value;
  const RecycleItemType(this.value);

  /// 从字符串解析枚举值
  static RecycleItemType fromString(String value) {
    return RecycleItemType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => RecycleItemType.chapter,
    );
  }
}

/// 章节回收站数据模型
///
/// 存储被删除的章节和设定项信息，支持恢复功能
/// 通过 [itemType] 字段区分章节和设定项
/// 文件内容统一保存到回收站目录下，以 UUID 命名避免冲突
@collection
class RecycleItemModel {
  // Isar 强制要求必须有一个叫 id 的整型主键
  Id id = Isar.autoIncrement;

  // @Index(unique: true) 表示给这个字段建唯一索引
  @Index(unique: true)
  String uuid = ''; // 回收项记录的唯一ID（UUID）

  // ================= 原项目信息 =================

  /// 项目类型（chapter / setting）
  @Index()
  String itemType = RecycleItemType.chapter.value;

  /// 原项目 UUID（章节或设定项的 UUID）
  String itemUuid = '';

  /// 所属书籍 UUID
  @Index()
  String bookUuid = '';

  /// 所属书籍标题（用于显示，恢复时检测书籍是否存在）
  String bookTitle = '';

  /// 项目标题
  String title = '';

  /// 所属容器名称（章节为分卷名，设定项为分组名，空字符串表示未分卷/未分组）
  String containerName = '';

  /// 所属容器 UUID（章节为分卷 UUID，设定项为分组 UUID）
  String containerUuid = '';

  /// 字数
  int wordCount = 0;

  /// 创建时间
  DateTime createdAt = DateTime.now();

  /// 最后修改时间
  DateTime updatedAt = DateTime.now();

  // ================= 回收站特有字段 =================

  /// 回收站中的文件路径（相对于回收站根目录）
  /// 格式为 "items/{uuid}.txt"
  String recycleFilePath = '';

  /// 删除时间
  DateTime deletedAt = DateTime.now();

  RecycleItemModel(); // 默认构造函数，Isar 强制要求有

  // ==========================================
  // UI 展现辅助获取器 (Getters)
  // ==========================================

  /// 项目类型枚举
  @ignore
  RecycleItemType get typeEnum => RecycleItemType.fromString(itemType);

  /// 是否为章节
  @ignore
  bool get isChapter => itemType == RecycleItemType.chapter.value;

  /// 是否为设定项
  @ignore
  bool get isSetting => itemType == RecycleItemType.setting.value;

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

  /// 容器显示名称（用于 UI 展示，未分卷/未分组时返回"未分卷"/"未分组"）
  @ignore
  String get displayContainerName {
    if (containerName.isEmpty) {
      return isChapter ? '未分卷' : '未分组';
    }
    return containerName;
  }

  // ==========================================
  // 工厂构造函数
  // ==========================================

  /// 从 ChapterModel 创建回收站记录
  ///
  /// [chapter] 原章节模型
  /// [bookTitle] 所属书籍标题
  /// [containerName] 所属分卷名称（空字符串表示未分卷）
  /// [recycleFilePath] 回收站中的文件相对路径
  factory RecycleItemModel.fromChapter({
    required ChapterModel chapter,
    required String bookTitle,
    required String containerName,
    required String recycleFilePath,
  }) {
    return RecycleItemModel()
      ..uuid = const Uuid().v4()
      ..itemType = RecycleItemType.chapter.value
      ..itemUuid = chapter.uuid
      ..bookUuid = chapter.bookUuid
      ..bookTitle = bookTitle
      ..title = chapter.title
      ..containerName = containerName
      ..containerUuid = chapter.volumeUuid
      ..wordCount = chapter.wordCount
      ..createdAt = chapter.createdAt
      ..updatedAt = chapter.updatedAt
      ..recycleFilePath = recycleFilePath
      ..deletedAt = DateTime.now();
  }

  /// 从 SettingItemModel 创建回收站记录
  ///
  /// [item] 原设定项模型
  /// [bookTitle] 所属书籍标题
  /// [containerName] 所属分组名称（空字符串表示未分组）
  /// [recycleFilePath] 回收站中的文件相对路径
  factory RecycleItemModel.fromSettingItem({
    required SettingItemModel item,
    required String bookTitle,
    required String containerName,
    required String recycleFilePath,
  }) {
    return RecycleItemModel()
      ..uuid = const Uuid().v4()
      ..itemType = RecycleItemType.setting.value
      ..itemUuid = item.uuid
      ..bookUuid = item.bookUuid
      ..bookTitle = bookTitle
      ..title = item.title
      ..containerName = containerName
      ..containerUuid = item.groupUuid
      ..wordCount = item.wordCount
      ..createdAt = item.createdAt
      ..updatedAt = item.updatedAt
      ..recycleFilePath = recycleFilePath
      ..deletedAt = DateTime.now();
  }

  // ==========================================
  // 转换为原模型（用于恢复）
  // ==========================================

  /// 转换为 ChapterModel（用于恢复）
  ///
  /// [filePath] 恢复后的章节文件相对路径
  /// [orderIndex] 全局排序索引
  /// [volumeOrderIndex] 卷内排序索引
  ChapterModel toChapterModel({
    required String filePath,
    required int orderIndex,
    required int volumeOrderIndex,
  }) {
    return ChapterModel()
      ..uuid = itemUuid
      ..bookUuid = bookUuid
      ..title = title
      ..volumeUuid = containerUuid
      ..orderIndex = orderIndex
      ..volumeOrderIndex = volumeOrderIndex
      ..wordCount = wordCount
      ..filePath = filePath
      ..createdAt = createdAt
      // 恢复本身即一次修改，修改时间需更新，否则会被判定为早于删除记录
      ..updatedAt = DateTime.now();
  }

  /// 转换为 SettingItemModel（用于恢复）
  ///
  /// [filePath] 恢复后的设定项文件相对路径
  /// [orderIndex] 全局排序索引
  /// [groupOrderIndex] 组内排序索引
  SettingItemModel toSettingItemModel({
    required String filePath,
    required int orderIndex,
    required int groupOrderIndex,
  }) {
    return SettingItemModel()
      ..uuid = itemUuid
      ..bookUuid = bookUuid
      ..title = title
      ..groupUuid = containerUuid
      ..orderIndex = orderIndex
      ..groupOrderIndex = groupOrderIndex
      ..wordCount = wordCount
      ..filePath = filePath
      ..createdAt = createdAt
      // 恢复本身即一次修改，修改时间需更新，否则会被判定为早于删除记录
      ..updatedAt = DateTime.now();
  }

  // ==========================================
  // 数据库序列化 (JSON 互转)
  // ==========================================
  Map<String, dynamic> toJson() {
    return {
      'uuid': uuid,
      'itemType': itemType,
      'itemUuid': itemUuid,
      'bookUuid': bookUuid,
      'bookTitle': bookTitle,
      'title': title,
      'containerName': containerName,
      'containerUuid': containerUuid,
      'wordCount': wordCount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'recycleFilePath': recycleFilePath,
      'deletedAt': deletedAt.toIso8601String(),
    };
  }

  factory RecycleItemModel.fromJson(Map<String, dynamic> json) {
    return RecycleItemModel()
      ..uuid = json['uuid'] as String? ?? ''
      ..itemType = json['itemType'] as String? ?? RecycleItemType.chapter.value
      ..itemUuid = json['itemUuid'] as String? ?? ''
      ..bookUuid = json['bookUuid'] as String? ?? ''
      ..bookTitle = json['bookTitle'] as String? ?? ''
      ..title = json['title'] as String? ?? ''
      ..containerName = json['containerName'] as String? ?? ''
      ..containerUuid = json['containerUuid'] as String? ?? ''
      ..wordCount = json['wordCount'] as int? ?? 0
      ..createdAt = json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now()
      ..updatedAt = json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now()
      ..recycleFilePath = json['recycleFilePath'] as String? ?? ''
      ..deletedAt = json['deletedAt'] != null
          ? DateTime.parse(json['deletedAt'] as String)
          : DateTime.now();
  }
}
