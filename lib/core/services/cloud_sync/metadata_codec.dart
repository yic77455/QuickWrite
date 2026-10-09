import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 元数据文件的格式版本
const int kMetadataFormatVersion = 1;

/// 远端元数据存放目录
///
/// 位于同步根目录下的内部目录，不参与正文文件的同步
const String kMetadataDirName = '.quickwrite/meta';

/// 全局元数据文件名（存放不隶属于某本书的集合）
const String kGlobalMetadataFileName = 'global.json.gz';

/// 单个书籍的元数据文件名
const String kBookMetadataFileName = 'book.json.gz';

/// 单个集合在快照中的数据
///
/// 实体记录当前有效的元数据，墓碑记录已发生的删除。
/// 缺少墓碑时无法区分「远端删除了该实体」与「该实体本地新增、尚未上传」，
/// 前者会在合并时被误判为新增而复活
class MetadataCollectionData {
  /// 实体列表，每项为对应模型的完整 JSON
  final List<Map<String, dynamic>> entities;

  /// 墓碑列表
  final List<MetadataTombstone> tombstones;

  const MetadataCollectionData({
    this.entities = const [],
    this.tombstones = const [],
  });

  /// 空数据
  static const MetadataCollectionData empty = MetadataCollectionData();

  /// 是否存在任何内容
  bool get isEmpty => entities.isEmpty && tombstones.isEmpty;

  Map<String, dynamic> toJson() => {
    'entities': entities,
    'tombstones': tombstones.map((item) => item.toJson()).toList(),
  };

  factory MetadataCollectionData.fromJson(Map<String, dynamic> json) {
    final entities = <Map<String, dynamic>>[];
    final rawEntities = json['entities'];
    if (rawEntities is List) {
      for (final item in rawEntities) {
        if (item is Map<String, dynamic>) entities.add(item);
      }
    }

    final tombstones = <MetadataTombstone>[];
    final rawTombstones = json['tombstones'];
    if (rawTombstones is List) {
      for (final item in rawTombstones) {
        if (item is Map<String, dynamic>) {
          tombstones.add(MetadataTombstone.fromJson(item));
        }
      }
    }

    return MetadataCollectionData(entities: entities, tombstones: tombstones);
  }
}

/// 元数据快照
///
/// 一个快照对应远端的一个元数据文件，可同时承载多个集合，
/// 便于把一本书的书籍信息、分卷、章节、设定等存放在同一个文件中
class MetadataSnapshot {
  /// 格式版本
  final int version;

  /// 集合名 → 集合数据
  final Map<String, MetadataCollectionData> collections;

  const MetadataSnapshot({
    this.version = kMetadataFormatVersion,
    this.collections = const {},
  });

  /// 空快照
  static const MetadataSnapshot empty = MetadataSnapshot();

  /// 获取指定集合的数据，不存在时返回空数据
  MetadataCollectionData operator [](String collection) =>
      collections[collection] ?? MetadataCollectionData.empty;

  /// 是否存在任何内容
  bool get isEmpty => collections.values.every((data) => data.isEmpty);

  /// 生成仅包含指定集合的快照
  MetadataSnapshot only(Set<String> names) {
    return MetadataSnapshot(
      collections: {
        for (final entry in collections.entries)
          if (names.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  /// 序列化为压缩后的字节内容
  ///
  /// 元数据中的新增章节等改动较为频繁，压缩可以显著降低重复上传的数据量
  Uint8List toBytes() {
    final jsonMap = <String, dynamic>{
      'version': version,
      'collections': collections.map(
        (name, data) => MapEntry(name, data.toJson()),
      ),
    };
    return Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(jsonMap))));
  }

  /// 从压缩后的字节内容反序列化
  factory MetadataSnapshot.fromBytes(List<int> bytes) {
    if (bytes.isEmpty) return MetadataSnapshot.empty;

    final jsonMap =
        jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;

    final collections = <String, MetadataCollectionData>{};
    final rawCollections = jsonMap['collections'];
    if (rawCollections is Map) {
      for (final entry in rawCollections.entries) {
        final value = entry.value;
        if (value is Map<String, dynamic>) {
          collections[entry.key as String] = MetadataCollectionData.fromJson(
            value,
          );
        }
      }
    }

    return MetadataSnapshot(
      version: jsonMap['version'] as int? ?? kMetadataFormatVersion,
      collections: collections,
    );
  }

  /// 生成快照的规范化字符串
  ///
  /// 集合、实体的字段与删除记录均按名称排序，使内容相同即得到相同的字符串，
  /// 用于判断远端文件是否真的需要重写
  String canonicalString() {
    final names = collections.keys.toList()..sort();
    final buffer = StringBuffer();

    for (final name in names) {
      final data = collections[name]!;
      if (data.isEmpty) continue;

      buffer.write(name);
      final entities = data.entities.map(canonicalEntityOf).toList()..sort();
      buffer.write(entities.join('|'));

      final tombstones =
          data.tombstones
              .map((item) => '${item.uuid}@${item.deletedAt.toIso8601String()}')
              .toList()
            ..sort();
      buffer.write(tombstones.join('|'));
    }

    return buffer.toString();
  }
}

/// 生成实体的规范化字符串
///
/// 字段按名称排序后编码，消除字段顺序带来的差异，
/// 使两端对同一实体得到完全一致的结果
String canonicalEntityOf(Map<String, dynamic> entity) {
  final keys = entity.keys.toList()..sort();
  return jsonEncode({for (final key in keys) key: entity[key]});
}

/// 实体删除标记
///
/// 一旦某实体被删除，其删除记录需要在一段时间内继续参与合并，
/// 否则持有旧副本的设备会把该实体重新推回
class MetadataTombstone {
  /// 被删除实体的稳定标识
  final String uuid;

  /// 删除时间
  final DateTime deletedAt;

  const MetadataTombstone({required this.uuid, required this.deletedAt});

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'deletedAt': deletedAt.toIso8601String(),
  };

  factory MetadataTombstone.fromJson(Map<String, dynamic> json) {
    return MetadataTombstone(
      uuid: json['uuid'] as String? ?? '',
      deletedAt: json['deletedAt'] != null
          ? DateTime.parse(json['deletedAt'] as String)
          : DateTime.now(),
    );
  }
}
