import 'package:isar/isar.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/models/group.dart';
import 'package:quick_write/core/models/setting_group.dart';
import 'package:quick_write/core/models/setting_item.dart';
import 'package:quick_write/core/models/volume.dart';
import 'package:quick_write/core/models/writing_stat.dart';

/// 书籍信息集合名
const String kBooksCollection = 'books';

/// 分卷集合名
const String kVolumesCollection = 'volumes';

/// 章节集合名
const String kChaptersCollection = 'chapters';

/// 设定分组集合名
const String kSettingGroupsCollection = 'settingGroups';

/// 设定项集合名
const String kSettingItemsCollection = 'settingItems';

/// 书籍分组集合名
const String kGroupsCollection = 'groups';

/// 码字统计集合名
const String kStatsCollection = 'stats';

/// 存放于全局元数据文件的集合
///
/// 这些集合不隶属于某本书，改动频率低、数据量小
const Set<String> kGlobalCollectionNames = {
  kGroupsCollection,
  kStatsCollection,
};

/// 参与元数据同步的实体类型注册表
final List<MetadataEntityType> kMetadataEntityTypes = [
  _booksType,
  _volumesType,
  _chaptersType,
  _settingGroupsType,
  _settingItemsType,
  _groupsType,
  _statsType,
];

/// 参与同步的一种元数据实体类型
///
/// 以 JSON 作为统一的交换格式，各类型的差异仅体现在所属集合、
/// 稳定标识与读写方式上，合并逻辑因此可以完全共用
class MetadataEntityType {
  /// 类型标识，同时作为快照中的集合名
  final String name;

  /// 该类型是否按书籍存放
  ///
  /// 按书籍存放的类型每本书一个远端文件，其余类型集中存放在全局文件
  final bool perBook;

  /// 读取本地全部实体
  final Future<List<Map<String, dynamic>>> Function(Isar isar) loadAll;

  /// 从实体 JSON 中取出稳定标识
  final String Function(Map<String, dynamic> json) keyOf;

  /// 写入实体，本地已存在同标识实体时更新
  final Future<void> Function(Isar isar, List<Map<String, dynamic>> entities)
  putAll;

  /// 按稳定标识删除本地实体
  final Future<void> Function(Isar isar, Set<String> keys) deleteByKeys;

  const MetadataEntityType({
    required this.name,
    required this.perBook,
    required this.loadAll,
    required this.keyOf,
    required this.putAll,
    required this.deleteByKeys,
  });
}

// ================= 通用工具 =================

/// 读取实体的 uuid 字段作为稳定标识
String _uuidKeyOf(Map<String, dynamic> json) => json['uuid'] as String? ?? '';

/// 读取实体的最后修改时间
///
/// 时间缺失的历史数据按最早时间处理，使其在合并时不会压过正常数据
DateTime _updatedAtOf(Map<String, dynamic> json) {
  final raw = json['updatedAt'] as String?;
  if (raw == null) return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  return DateTime.tryParse(raw) ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

/// 读取全体实体的「稳定标识 → 底层 ID」映射
///
/// 写入前据此沿用已有 ID，避免同一实体被重复插入
Map<String, Id> _idMapOf<T>(
  List<T> existing,
  String Function(T item) keyOf,
  Id Function(T item) idOf,
) {
  return {for (final item in existing) keyOf(item): idOf(item)};
}

/// 解析实体应使用的底层 ID
Id _resolveId(String key, Map<String, Id> idMap) =>
    idMap[key] ?? Isar.autoIncrement;

/// 逐个删除指定标识的实体
///
/// uuid 为唯一索引，Isar 未生成按多个标识批量删除的接口，
/// 因此逐个删除；单次同步涉及的删除数量通常很小
Future<void> _deleteEach(
  Set<String> keys,
  Future<int> Function(String key) deleteOne,
) async {
  for (final key in keys) {
    await deleteOne(key);
  }
}

// ================= 书籍信息 =================

final MetadataEntityType _booksType = MetadataEntityType(
  name: kBooksCollection,
  perBook: true,
  keyOf: _uuidKeyOf,
  loadAll: (isar) async {
    final books = await isar.bookModels.where().findAll();
    return [for (final book in books) book.toJson()];
  },
  putAll: (isar, entities) async {
    final idMap = _idMapOf<BookModel>(
      await isar.bookModels.where().findAll(),
      (book) => book.uuid,
      (book) => book.id,
    );

    final models = <BookModel>[];
    for (final json in entities) {
      final model = BookModel.fromJson(json);
      model.id = _resolveId(model.uuid, idMap);
      models.add(model);
    }
    await isar.bookModels.putAll(models);
  },
  deleteByKeys: (isar, keys) async {
    if (keys.isEmpty) return;
    await _deleteEach(
      keys,
      (key) => isar.bookModels.where().uuidEqualTo(key).deleteAll(),
    );
  },
);

// ================= 分卷 =================

final MetadataEntityType _volumesType = MetadataEntityType(
  name: kVolumesCollection,
  perBook: true,
  keyOf: _uuidKeyOf,
  loadAll: (isar) async {
    final volumes = await isar.volumeModels.where().findAll();
    return [for (final volume in volumes) volume.toJson()];
  },
  putAll: (isar, entities) async {
    final localVolumes = await isar.volumeModels.where().findAll();
    final idMap = _idMapOf<VolumeModel>(
      localVolumes,
      (volume) => volume.uuid,
      (volume) => volume.id,
    );

    // 展开状态属于本机的界面偏好，不参与同步：已存在的分卷沿用本机状态，
    // 避免被远端记录覆盖而让目录列表的展开/折叠状态在同步后跳变
    final expandedByUuid = {
      for (final volume in localVolumes) volume.uuid: volume.isExpanded,
    };

    final models = <VolumeModel>[];
    for (final json in entities) {
      final model = VolumeModel.fromJson(json);
      model.id = _resolveId(model.uuid, idMap);
      final localExpanded = expandedByUuid[model.uuid];
      if (localExpanded != null) model.isExpanded = localExpanded;
      models.add(model);
    }
    await isar.volumeModels.putAll(models);
  },
  deleteByKeys: (isar, keys) async {
    if (keys.isEmpty) return;
    await _deleteEach(
      keys,
      (key) => isar.volumeModels.where().uuidEqualTo(key).deleteAll(),
    );
  },
);

// ================= 章节 =================

final MetadataEntityType _chaptersType = MetadataEntityType(
  name: kChaptersCollection,
  perBook: true,
  keyOf: _uuidKeyOf,
  loadAll: (isar) async {
    final chapters = await isar.chapterModels.where().findAll();
    return [for (final chapter in chapters) chapter.toJson()];
  },
  putAll: (isar, entities) async {
    final idMap = _idMapOf<ChapterModel>(
      await isar.chapterModels.where().findAll(),
      (chapter) => chapter.uuid,
      (chapter) => chapter.id,
    );

    final models = <ChapterModel>[];
    for (final json in entities) {
      final model = ChapterModel.fromJson(json);
      model.id = _resolveId(model.uuid, idMap);
      models.add(model);
    }
    await isar.chapterModels.putAll(models);
  },
  deleteByKeys: (isar, keys) async {
    if (keys.isEmpty) return;
    await _deleteEach(
      keys,
      (key) => isar.chapterModels.where().uuidEqualTo(key).deleteAll(),
    );
  },
);

// ================= 设定分组 =================

final MetadataEntityType _settingGroupsType = MetadataEntityType(
  name: kSettingGroupsCollection,
  perBook: true,
  keyOf: _uuidKeyOf,
  loadAll: (isar) async {
    final groups = await isar.settingGroupModels.where().findAll();
    return [for (final group in groups) group.toJson()];
  },
  putAll: (isar, entities) async {
    final idMap = _idMapOf<SettingGroupModel>(
      await isar.settingGroupModels.where().findAll(),
      (group) => group.uuid,
      (group) => group.id,
    );

    final models = <SettingGroupModel>[];
    for (final json in entities) {
      final model = SettingGroupModel.fromJson(json);
      model.id = _resolveId(model.uuid, idMap);
      models.add(model);
    }
    await isar.settingGroupModels.putAll(models);
  },
  deleteByKeys: (isar, keys) async {
    if (keys.isEmpty) return;
    await _deleteEach(
      keys,
      (key) => isar.settingGroupModels.where().uuidEqualTo(key).deleteAll(),
    );
  },
);

// ================= 设定项 =================

final MetadataEntityType _settingItemsType = MetadataEntityType(
  name: kSettingItemsCollection,
  perBook: true,
  keyOf: _uuidKeyOf,
  loadAll: (isar) async {
    final items = await isar.settingItemModels.where().findAll();
    return [for (final item in items) item.toJson()];
  },
  putAll: (isar, entities) async {
    final idMap = _idMapOf<SettingItemModel>(
      await isar.settingItemModels.where().findAll(),
      (item) => item.uuid,
      (item) => item.id,
    );

    final models = <SettingItemModel>[];
    for (final json in entities) {
      final model = SettingItemModel.fromJson(json);
      model.id = _resolveId(model.uuid, idMap);
      models.add(model);
    }
    await isar.settingItemModels.putAll(models);
  },
  deleteByKeys: (isar, keys) async {
    if (keys.isEmpty) return;
    await _deleteEach(
      keys,
      (key) => isar.settingItemModels.where().uuidEqualTo(key).deleteAll(),
    );
  },
);

// ================= 书籍分组 =================

final MetadataEntityType _groupsType = MetadataEntityType(
  name: kGroupsCollection,
  perBook: false,
  keyOf: _uuidKeyOf,
  loadAll: (isar) async {
    final groups = await isar.groupModels.where().findAll();
    return [for (final group in groups) group.toJson()];
  },
  putAll: (isar, entities) async {
    final idMap = _idMapOf<GroupModel>(
      await isar.groupModels.where().findAll(),
      (group) => group.uuid,
      (group) => group.id,
    );

    final models = <GroupModel>[];
    for (final json in entities) {
      final model = GroupModel.fromJson(json);
      model.id = _resolveId(model.uuid, idMap);
      models.add(model);
    }
    await isar.groupModels.putAll(models);
  },
  deleteByKeys: (isar, keys) async {
    if (keys.isEmpty) return;
    await _deleteEach(
      keys,
      (key) => isar.groupModels.where().uuidEqualTo(key).deleteAll(),
    );
  },
);

// ================= 码字统计 =================

/// 生成码字统计的稳定标识
///
/// 统计以「书籍 + 日期」为粒度，不存在天然的主键字段，因此由两者组合而成
String _statKeyOf(Map<String, dynamic> json) {
  final bookUuid = json['bookUuid'] as String? ?? '';
  final date = json['date'] as String? ?? '';
  return '$bookUuid@$date';
}

final MetadataEntityType _statsType = MetadataEntityType(
  name: kStatsCollection,
  perBook: false,
  keyOf: _statKeyOf,
  loadAll: (isar) async {
    final stats = await isar.writingStatModels.where().findAll();
    return [for (final stat in stats) stat.toJson()];
  },
  putAll: (isar, entities) async {
    // 统计没有 uuid 索引，按稳定标识建立现有数据的 ID 映射
    final existing = await isar.writingStatModels.where().findAll();
    final idMap = <String, Id>{};
    for (final stat in existing) {
      idMap[_statKeyOf(stat.toJson())] = stat.id;
    }

    final models = <WritingStatModel>[];
    for (final json in entities) {
      final model = WritingStatModel.fromJson(json);
      model.id = _resolveId(_statKeyOf(json), idMap);
      models.add(model);
    }
    await isar.writingStatModels.putAll(models);
  },
  deleteByKeys: (isar, keys) async {
    if (keys.isEmpty) return;

    final existing = await isar.writingStatModels.where().findAll();
    final ids = [
      for (final stat in existing)
        if (keys.contains(_statKeyOf(stat.toJson()))) stat.id,
    ];
    if (ids.isEmpty) return;
    await isar.writingStatModels.deleteAll(ids);
  },
);

/// 读取实体的最后修改时间
///
/// 供合并逻辑比较新旧版本使用
DateTime metadataUpdatedAtOf(Map<String, dynamic> json) => _updatedAtOf(json);

/// 读取实体所属的书籍 UUID
///
/// 用于把按书籍存放的集合拆分成每本书一个文件。
/// 书籍信息自身的 UUID 即代表该书，其余实体通过 bookUuid 字段归属
String metadataBookUuidOf(String collection, Map<String, dynamic> json) {
  if (collection == kBooksCollection) return json['uuid'] as String? ?? '';
  return json['bookUuid'] as String? ?? '';
}
