import 'package:isar/isar.dart';
import 'package:quick_write/core/services/cloud_sync/metadata_codec.dart';
import 'package:quick_write/core/services/cloud_sync/metadata_types.dart';

/// 删除记录的保留时长
///
/// 超过该时长后，持有旧副本的设备已不太可能再推回被删除的实体，
/// 此时可以清理记录以控制数据量
const Duration kTombstoneRetention = Duration(days: 30);

/// 元数据合并结果
class MetadataMergeOutcome {
  /// 需要写入本地的实体（集合名 → 实体 JSON 列表）
  final Map<String, List<Map<String, dynamic>>> localUpserts;

  /// 需要从本地移除的实体（集合名 → 被移除实体的 JSON 列表）
  ///
  /// 保留被移除实体本身的信息，便于调用方在删除前安置其正文文件
  final Map<String, List<Map<String, dynamic>>> localRemovals;

  /// 合并后应推送到远端的快照
  final MetadataSnapshot merged;

  /// 合并后各集合的存活实体标识，用于更新同步基线
  final Map<String, Set<String>> aliveKeys;

  const MetadataMergeOutcome({
    required this.localUpserts,
    required this.localRemovals,
    required this.merged,
    required this.aliveKeys,
  });

  /// 是否存在本地改动
  bool get hasLocalChanges =>
      localUpserts.values.any((items) => items.isNotEmpty) ||
      localRemovals.values.any((items) => items.isNotEmpty);
}

/// 元数据合并器
///
/// 对每个集合按实体做「较新者胜」的合并，并借助删除记录处理删除：
/// - 实体之间：修改时间较新的一方胜出；时间相同时按内容比较，保证两端结果一致
/// - 实体与删除记录之间：同样按时间比较，较新的一方胜出，
///   因此「删除后又恢复」的实体会因时间更新而保留
///
/// 本地的删除由同步基线推导：基线中存在、当前本地不存在的实体即视为本地已删除，
/// 无需在应用的各删除路径上埋点
class MetadataMerger {
  const MetadataMerger();

  /// 执行一次元数据合并
  ///
  /// [isar] 应用数据库实例
  /// [remote] 远端快照
  /// [baselineKeys] 上次同步完成时各集合的存活实体标识
  Future<MetadataMergeOutcome> merge({
    required Isar isar,
    required MetadataSnapshot remote,
    required Map<String, Set<String>> baselineKeys,
  }) async {
    final now = DateTime.now();
    final upserts = <String, List<Map<String, dynamic>>>{};
    final removals = <String, List<Map<String, dynamic>>>{};
    final mergedCollections = <String, MetadataCollectionData>{};
    final aliveKeys = <String, Set<String>>{};

    for (final type in kMetadataEntityTypes) {
      final localEntities = await type.loadAll(isar);
      final result = mergeCollection(
        type: type,
        localEntities: localEntities,
        remoteData: remote[type.name],
        baselineKeys: baselineKeys[type.name] ?? const {},
        now: now,
      );

      if (result.upserts.isNotEmpty) upserts[type.name] = result.upserts;
      if (result.removals.isNotEmpty) removals[type.name] = result.removals;
      aliveKeys[type.name] = result.aliveKeys;

      if (!result.data.isEmpty) mergedCollections[type.name] = result.data;
    }

    return MetadataMergeOutcome(
      localUpserts: upserts,
      localRemovals: removals,
      merged: MetadataSnapshot(collections: mergedCollections),
      aliveKeys: aliveKeys,
    );
  }

  /// 合并单个集合
  ///
  /// 该方法是合并的最小单元，不依赖数据库，便于独立验证
  CollectionMergeResult mergeCollection({
    required MetadataEntityType type,
    required List<Map<String, dynamic>> localEntities,
    required MetadataCollectionData remoteData,
    required Set<String> baselineKeys,
    required DateTime now,
  }) {
    final localByKey = {
      for (final entity in localEntities) type.keyOf(entity): entity,
    };
    final remoteByKey = {
      for (final entity in remoteData.entities) type.keyOf(entity): entity,
    };

    // 删除记录：以远端记录为基础，并补上本地新发生的删除
    final tombstones = <String, DateTime>{};
    for (final tombstone in remoteData.tombstones) {
      final existing = tombstones[tombstone.uuid];
      if (existing == null || tombstone.deletedAt.isAfter(existing)) {
        tombstones[tombstone.uuid] = tombstone.deletedAt;
      }
    }
    // 基线中存在、当前本地不存在，说明本地删除了该实体
    for (final key in baselineKeys) {
      if (key.isNotEmpty && !localByKey.containsKey(key)) {
        tombstones[key] = now;
      }
    }

    final upserts = <Map<String, dynamic>>[];
    final removals = <Map<String, dynamic>>[];
    final aliveEntities = <Map<String, dynamic>>[];
    final aliveKeys = <String>{};

    final allKeys = <String>{
      ...localByKey.keys,
      ...remoteByKey.keys,
      ...tombstones.keys,
    };

    for (final key in allKeys) {
      final local = localByKey[key];
      final remoteEntity = remoteByKey[key];
      final winner = _pickEntity(local, remoteEntity);

      // 删除记录与实体按时间比较，较新的一方胜出
      final deletedAt = tombstones[key];
      final isDeleted =
          winner == null ||
          (deletedAt != null &&
              !metadataUpdatedAtOf(winner).isAfter(deletedAt));

      if (isDeleted) {
        // 实体被删除：本地若存在则移除，删除记录保留以便传达给其他设备
        if (local != null) removals.add(local);
        continue;
      }

      // 实体胜出：删除记录不再需要保留，并作为存活实体继续参与同步
      tombstones.remove(key);
      aliveEntities.add(winner);
      aliveKeys.add(key);

      // 本地与合并结果不一致时才需要写回
      if (local == null ||
          canonicalEntityOf(local) != canonicalEntityOf(winner)) {
        upserts.add(winner);
      }
    }

    // 清理过期的删除记录
    final retainedTombstones = <MetadataTombstone>[
      for (final entry in tombstones.entries)
        if (now.difference(entry.value) < kTombstoneRetention)
          MetadataTombstone(uuid: entry.key, deletedAt: entry.value),
    ];

    return CollectionMergeResult(
      data: MetadataCollectionData(
        entities: aliveEntities,
        tombstones: retainedTombstones,
      ),
      upserts: upserts,
      removals: removals,
      aliveKeys: aliveKeys,
    );
  }

  /// 在两个实体中选出胜者
  ///
  /// 优先比较修改时间；时间相同时按规范化内容比较，
  /// 使两端对同一冲突得到相同结论
  Map<String, dynamic>? _pickEntity(
    Map<String, dynamic>? local,
    Map<String, dynamic>? remote,
  ) {
    if (local == null) return remote;
    if (remote == null) return local;

    final localTime = metadataUpdatedAtOf(local);
    final remoteTime = metadataUpdatedAtOf(remote);
    final comparison = localTime.compareTo(remoteTime);
    if (comparison != 0) return comparison > 0 ? local : remote;

    return canonicalEntityOf(local).compareTo(canonicalEntityOf(remote)) >= 0
        ? local
        : remote;
  }
}

/// 单个集合的合并结果
class CollectionMergeResult {
  /// 合并后的集合数据
  final MetadataCollectionData data;

  /// 需要写入本地的实体
  final List<Map<String, dynamic>> upserts;

  /// 需要从本地移除的实体
  final List<Map<String, dynamic>> removals;

  /// 存活实体的标识
  final Set<String> aliveKeys;

  const CollectionMergeResult({
    required this.data,
    required this.upserts,
    required this.removals,
    required this.aliveKeys,
  });
}
