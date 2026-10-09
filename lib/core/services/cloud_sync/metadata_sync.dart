import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/models/recycle_bin.dart';
import 'package:quick_write/core/models/setting_group.dart';
import 'package:quick_write/core/models/setting_item.dart';
import 'package:quick_write/core/models/volume.dart';
import 'package:quick_write/core/services/app_paths.dart';
import 'package:quick_write/core/services/cloud_sync/metadata_codec.dart';
import 'package:quick_write/core/services/cloud_sync/metadata_merger.dart';
import 'package:quick_write/core/services/cloud_sync/metadata_types.dart';
import 'package:quick_write/core/services/cloud_sync/sync_state_store.dart';
import 'package:quick_write/core/services/cloud_sync/webdav_client.dart';
import 'package:quick_write/core/services/recycle_item_service.dart';
import 'package:uuid/uuid.dart';

/// 按书籍存放的元数据子目录名（相对于元数据目录）
const String kBooksMetaSubDirName = 'books';

/// 元数据同步结果
class MetadataSyncResult {
  /// 写回本地的实体数量
  final int upsertCount;

  /// 从本地移除的实体数量
  final int removalCount;

  /// 推送到远端的元数据文件数量
  final int uploadedFileCount;

  /// 从远端读取到的元数据文件数量
  ///
  /// 为 0 说明远端尚无元数据，通常意味着还没有任何设备推送过
  final int remoteFileCount;

  /// 存在删除记录、等待清理正文目录的书籍 UUID
  ///
  /// 远端目录的删除不可逆，交由调用方在风险确认通过后执行
  final Set<String> deletedBookUuids;

  const MetadataSyncResult({
    this.upsertCount = 0,
    this.removalCount = 0,
    this.uploadedFileCount = 0,
    this.remoteFileCount = 0,
    this.deletedBookUuids = const {},
  });

  /// 是否存在需要上报的变化
  bool get hasChanges =>
      upsertCount > 0 || removalCount > 0 || uploadedFileCount > 0;
}

/// 元数据同步器
///
/// 负责元数据的完整往返：读取远端快照、与本地合并、落地本地改动、回写远端。
/// 该过程必须先于正文文件同步执行，本地实体具备正确的章节结构后，
/// 按章节归档打包时两端才能得到相同的分块结果
class MetadataSync {
  MetadataSync({
    required WebDavClient webdav,
    required SyncStateStore stateStore,
    MetadataMerger merger = const MetadataMerger(),
  }) : _webdav = webdav,
       _stateStore = stateStore,
       _merger = merger;

  /// 远端通信客户端
  final WebDavClient _webdav;

  /// 本机同步状态存储
  final SyncStateStore _stateStore;

  /// 元数据合并器
  final MetadataMerger _merger;

  // ================= 执行入口 =================

  /// 执行一次元数据同步
  Future<MetadataSyncResult> run({required Isar isar}) async {
    final remote = await _loadRemote();

    // 远端元数据整体缺失但本地留有同步基线，说明远端数据已被清空，
    // 应按重新建立关联处理：基线归零后本地内容会作为全新数据完整推送
    final isRemoteCleared = remote.fileCount == 0 && _stateStore.hasBaselines;
    if (isRemoteCleared) {
      debugPrint('远端元数据为空且本地留有基线，按重新关联处理');
      _stateStore.clearSyncBaselines();
    }

    final outcome = await _merger.merge(
      isar: isar,
      remote: remote.combined,
      baselineKeys: _stateStore.entityBaselines,
    );

    // 先安置被移除实体的正文文件，再删除实体本身
    final removalCount = await _applyRemovals(isar, outcome);
    await _applyUpserts(isar, outcome);
    final uploadedFileCount = await _pushMerged(outcome.merged, remote);

    // 基线更新为本次合并后的存活实体，未成功完成同步时不会走到这里
    _stateStore.setEntityBaselines(outcome.aliveKeys);

    return MetadataSyncResult(
      upsertCount: outcome.localUpserts.values.fold(
        0,
        (sum, items) => sum + items.length,
      ),
      removalCount: removalCount,
      uploadedFileCount: uploadedFileCount,
      remoteFileCount: remote.fileCount,
      deletedBookUuids: deletedBookUuidsOf(outcome.merged),
    );
  }

  // ================= 远端读取 =================

  /// 读取远端全部元数据文件
  Future<_RemoteMetadata> _loadRemote() async {
    final global = await _readSnapshot(kGlobalMetadataFileName);
    final perBook = <String, MetadataSnapshot>{};

    final fileNames = await _webdav.listFileNames(_booksMetaDirPath);
    final bookFileNames = [
      for (final fileName in fileNames)
        if (fileName.endsWith('.gz')) fileName,
    ];

    for (final fileName in bookFileNames) {
      final bookUuid = fileName.substring(0, fileName.length - '.gz'.length);
      final snapshot = await _readSnapshot('$kBooksMetaSubDirName/$fileName');
      if (snapshot != null) perBook[bookUuid] = snapshot;
    }

    // 元数据缺失时会被当作「远端暂无数据」而不报错，此处记录实际读到的内容便于排查
    final entityCount = perBook.values.fold(
      0,
      (sum, snapshot) =>
          sum +
          snapshot.collections.values.fold(
            0,
            (inner, data) => inner + data.entities.length,
          ),
    );
    debugPrint(
      '远端元数据：书籍文件 ${perBook.length} 个，'
      '全局文件 ${global == null ? '缺失' : '存在'}，实体 $entityCount 条',
    );

    return _RemoteMetadata(
      global: global ?? MetadataSnapshot.empty,
      perBook: perBook,
      combined: _combine(global ?? MetadataSnapshot.empty, perBook.values),
      fileCount: perBook.length + (global == null ? 0 : 1),
    );
  }

  /// 读取单个元数据文件，文件不存在时返回 null
  Future<MetadataSnapshot?> _readSnapshot(String relativePath) async {
    final bytes = await _webdav.downloadBytesIfExists(
      _webdav.remotePathOf('$kMetadataDirName/$relativePath'),
    );
    if (bytes == null) return null;
    return MetadataSnapshot.fromBytes(bytes);
  }

  /// 把分散的文件快照合并为一个整体快照
  static MetadataSnapshot _combine(
    MetadataSnapshot global,
    Iterable<MetadataSnapshot> perBook,
  ) {
    final collections = <String, MetadataCollectionData>{};

    void mergeIn(MetadataSnapshot snapshot) {
      for (final entry in snapshot.collections.entries) {
        final existing = collections[entry.key];
        collections[entry.key] = existing == null
            ? entry.value
            : MetadataCollectionData(
                entities: [...existing.entities, ...entry.value.entities],
                tombstones: [...existing.tombstones, ...entry.value.tombstones],
              );
      }
    }

    mergeIn(global);
    for (final snapshot in perBook) {
      mergeIn(snapshot);
    }

    return MetadataSnapshot(collections: collections);
  }

  // ================= 本地落地 =================

  /// 将合并结果写回本地
  Future<void> _applyUpserts(Isar isar, MetadataMergeOutcome outcome) async {
    for (final type in kMetadataEntityTypes) {
      final entities = outcome.localUpserts[type.name];
      if (entities == null || entities.isEmpty) continue;

      await isar.writeTxn(() async {
        await type.putAll(isar, entities);
      });
    }
  }

  /// 移除本地已被删除的实体，并安置其正文文件
  ///
  /// 正文文件统一移入回收站，避免删除动作直接抹掉稿件内容
  Future<int> _applyRemovals(Isar isar, MetadataMergeOutcome outcome) async {
    var removalCount = 0;

    for (final type in kMetadataEntityTypes) {
      final entities = outcome.localRemovals[type.name];
      if (entities == null || entities.isEmpty) continue;

      await _disposeRemovedContent(isar, type.name, entities);

      final keys = {for (final entity in entities) type.keyOf(entity)};
      await isar.writeTxn(() async {
        await type.deleteByKeys(isar, keys);
      });
      removalCount += entities.length;
    }

    return removalCount;
  }

  // ================= 正文安置 =================

  /// 在删除实体前安置其正文文件
  Future<void> _disposeRemovedContent(
    Isar isar,
    String collection,
    List<Map<String, dynamic>> entities,
  ) async {
    switch (collection) {
      case kChaptersCollection:
        await _recycleChapters(isar, entities);
      case kSettingItemsCollection:
        await _recycleSettingItems(isar, entities);
      case kBooksCollection:
        await _recycleBooks(isar, entities);
    }
  }

  /// 将章节正文移入回收站
  Future<void> _recycleChapters(
    Isar isar,
    List<Map<String, dynamic>> entities,
  ) async {
    final worksPath = await AppPaths.instance.getBooksPath();
    final recycleService = RecycleItemService.instance..initialize(isar);

    // 书籍标题与分卷名称仅用于回收站展示，缺失时留空
    final titleByBookUuid = await _bookTitles(isar);
    final nameByVolumeUuid = await _volumeNames(isar);

    for (final json in entities) {
      final chapter = ChapterModel.fromJson(json);
      final bookTitle = titleByBookUuid[chapter.bookUuid];
      if (bookTitle == null || chapter.filePath.isEmpty) continue;

      await recycleService.moveChapterToRecycleBin(
        chapter: chapter,
        bookTitle: bookTitle,
        volumeName: nameByVolumeUuid[chapter.volumeUuid] ?? '',
        chapterFilePath: _joinPath([
          worksPath,
          bookTitle,
          'chapters',
          chapter.filePath,
        ]),
      );
    }
  }

  /// 将设定项正文移入回收站
  Future<void> _recycleSettingItems(
    Isar isar,
    List<Map<String, dynamic>> entities,
  ) async {
    final worksPath = await AppPaths.instance.getBooksPath();
    final recycleService = RecycleItemService.instance..initialize(isar);

    final titleByBookUuid = await _bookTitles(isar);
    final nameByGroupUuid = await _settingGroupNames(isar);

    for (final json in entities) {
      final item = SettingItemModel.fromJson(json);
      final bookTitle = titleByBookUuid[item.bookUuid];
      if (bookTitle == null || item.filePath.isEmpty) continue;

      await recycleService.moveSettingItemToRecycleBin(
        item: item,
        bookTitle: bookTitle,
        groupName: nameByGroupUuid[item.groupUuid] ?? '',
        itemFilePath: _joinPath([
          worksPath,
          bookTitle,
          'settings',
          item.filePath,
        ]),
      );
    }
  }

  /// 将书籍文件夹移入回收站
  ///
  /// 与本地删除书籍的做法保持一致：建立回收站记录并移动整个文件夹。
  /// 文件夹移动失败时不做任何删除，只记录提示，避免稿件内容被抹掉
  Future<void> _recycleBooks(
    Isar isar,
    List<Map<String, dynamic>> entities,
  ) async {
    final worksPath = await AppPaths.instance.getBooksPath();
    final recycleBinPath = await AppPaths.instance.getRecycleBinPath();

    for (final json in entities) {
      final book = BookModel.fromJson(json);
      if (book.title.isEmpty) continue;

      final recycleFolderName = const Uuid().v4();
      try {
        final directory = Directory(_joinPath([worksPath, book.title]));
        if (await directory.exists()) {
          await directory.rename(
            _joinPath([recycleBinPath, recycleFolderName]),
          );
        }

        await isar.writeTxn(() async {
          await isar.recycleBinModels.put(
            RecycleBinModel.fromBookModel(book, recycleFolderName),
          );
        });
      } catch (e) {
        debugPrint('书籍文件夹移入回收站失败，已保留原文件夹: $e');
      }
    }
  }

  // ================= 远端回写 =================

  /// 将合并结果写回远端
  ///
  /// 内容未变化的文件不会重写，避免每次同步都产生书籍数量级的请求
  Future<int> _pushMerged(
    MetadataSnapshot merged,
    _RemoteMetadata remote,
  ) async {
    var uploaded = 0;

    final global = buildGlobalSnapshot(merged);
    if (global.canonicalString() != remote.global.canonicalString()) {
      await _webdav.uploadBytes(
        global.toBytes(),
        _webdav.remotePathOf('$kMetadataDirName/$kGlobalMetadataFileName'),
      );
      uploaded++;
    }

    // 按书籍拆分：每本书一个文件，仅改动的那本需要重写
    final perBook = splitByBook(merged);
    final bookUuids = {...perBook.keys, ...remote.perBook.keys};
    for (final bookUuid in bookUuids) {
      final snapshot = perBook[bookUuid] ?? MetadataSnapshot.empty;
      final existing = remote.perBook[bookUuid];

      if (snapshot.isEmpty) {
        // 该书的元数据已全部清理，移除远端残留文件
        if (existing != null) {
          await _webdav.deleteFile(
            _webdav.remotePathOf(
              '$kMetadataDirName/$kBooksMetaSubDirName/$bookUuid.gz',
            ),
          );
        }
        continue;
      }

      if (existing != null &&
          snapshot.canonicalString() == existing.canonicalString()) {
        continue;
      }

      await _webdav.uploadBytes(
        snapshot.toBytes(),
        _webdav.remotePathOf(
          '$kMetadataDirName/$kBooksMetaSubDirName/$bookUuid.gz',
        ),
      );
      uploaded++;
    }

    return uploaded;
  }

  /// 清理已删除书籍在远端的正文目录
  ///
  /// 文件层不做删除决策，书籍被删除后其正文目录需要在此按删除记录清理。
  /// 只依据删除记录而非「不在存活列表」判断，避免在远端元数据缺失时
  /// 把仍然有效的目录一并清掉
  ///
  /// 删除远端目录不可逆，因此拆分为「查找」与「删除」两步：
  /// 先查找出确实存在、需要清理的目录供风险预检评估，确认后再执行删除
  Future<List<String>> findDeletableBookDirs(Set<String> deletedBookUuids) async {
    if (deletedBookUuids.isEmpty) return const [];

    final remoteDirs = await _webdav.listDirectoryNames(_booksContentDirPath);
    return [
      for (final dirName in remoteDirs)
        if (deletedBookUuids.contains(dirName)) dirName,
    ];
  }

  /// 删除指定的远端书籍正文目录
  ///
  /// 返回成功删除的目录数量；单个目录删除失败不影响其余目录
  Future<int> deleteBookDirs(List<String> dirNames) async {
    var removedCount = 0;

    for (final dirName in dirNames) {
      try {
        await _webdav.deleteDirectoryRecursive(
          '$_booksContentDirPath/$dirName',
        );
        removedCount++;
      } catch (e) {
        debugPrint('清理书籍正文目录失败: $dirName，$e');
      }
    }

    return removedCount;
  }

  /// 收集存在删除记录、需要清理正文目录的书籍 UUID
  static Set<String> deletedBookUuidsOf(MetadataSnapshot merged) {
    return {
      for (final tombstone in merged[kBooksCollection].tombstones)
        if (tombstone.uuid.isNotEmpty) tombstone.uuid,
    };
  }

  /// 构建全局快照
  ///
  /// 全局文件承载全局集合的实体，以及按书籍存放集合的全部删除记录。
  /// 删除记录离开实体后无法判断所属书籍，集中存放可以保证不丢失
  static MetadataSnapshot buildGlobalSnapshot(MetadataSnapshot merged) {
    final collections = <String, MetadataCollectionData>{};

    for (final name in kGlobalCollectionNames) {
      final data = merged[name];
      if (!data.isEmpty) collections[name] = data;
    }

    for (final type in kMetadataEntityTypes) {
      if (!type.perBook) continue;
      final tombstones = merged[type.name].tombstones;
      if (tombstones.isNotEmpty) {
        collections[type.name] = MetadataCollectionData(tombstones: tombstones);
      }
    }

    return MetadataSnapshot(collections: collections);
  }

  /// 把按书籍存放的实体拆分为「每本书一个快照」
  static Map<String, MetadataSnapshot> splitByBook(MetadataSnapshot merged) {
    final perBook = <String, Map<String, MetadataCollectionData>>{};

    for (final type in kMetadataEntityTypes) {
      if (!type.perBook) continue;

      for (final entity in merged[type.name].entities) {
        final bookUuid = metadataBookUuidOf(type.name, entity);
        if (bookUuid.isEmpty) continue;

        final collections = perBook.putIfAbsent(bookUuid, () => {});
        final existing = collections[type.name] ?? MetadataCollectionData.empty;
        collections[type.name] = MetadataCollectionData(
          entities: [...existing.entities, entity],
        );
      }
    }

    return {
      for (final entry in perBook.entries)
        entry.key: MetadataSnapshot(collections: entry.value),
    };
  }

  // ================= 工具方法 =================

  /// 以当前平台的分隔符拼接路径片段
  static String _joinPath(List<String> parts) =>
      parts.join(Platform.pathSeparator);

  /// 获取书籍标题映射
  Future<Map<String, String>> _bookTitles(Isar isar) async {
    final books = await isar.bookModels.where().findAll();
    return {for (final book in books) book.uuid: book.title};
  }

  /// 获取分卷名称映射
  Future<Map<String, String>> _volumeNames(Isar isar) async {
    final volumes = await isar.volumeModels.where().findAll();
    return {for (final volume in volumes) volume.uuid: volume.name};
  }

  /// 获取设定分组名称映射
  Future<Map<String, String>> _settingGroupNames(Isar isar) async {
    final groups = await isar.settingGroupModels.where().findAll();
    return {for (final group in groups) group.uuid: group.name};
  }

  /// 按书籍存放的元数据目录绝对路径
  String get _booksMetaDirPath =>
      _webdav.remotePathOf('$kMetadataDirName/$kBooksMetaSubDirName');

  /// 书籍正文目录的绝对路径
  String get _booksContentDirPath => _webdav.remotePathOf('books');
}

/// 远端元数据
class _RemoteMetadata {
  /// 全局文件快照
  final MetadataSnapshot global;

  /// 每本书的文件快照
  final Map<String, MetadataSnapshot> perBook;

  /// 所有文件合并后的整体快照
  final MetadataSnapshot combined;

  /// 从远端读取到的文件数量
  final int fileCount;

  const _RemoteMetadata({
    required this.global,
    required this.perBook,
    required this.combined,
    required this.fileCount,
  });
}
