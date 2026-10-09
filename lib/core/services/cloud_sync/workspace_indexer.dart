import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:isar/isar.dart';
import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/models/setting_item.dart';
import 'package:quick_write/core/services/app_paths.dart';
import 'package:quick_write/core/services/cloud_sync/chapter_archive.dart';
import 'package:quick_write/core/services/cloud_sync/sync_models.dart';
import 'package:quick_write/core/services/workspace/custom_highlight_service.dart';

/// 书籍相关文件的逻辑键前缀
const String _booksKeyPrefix = 'books/';

/// 应用配置文件的逻辑键
const String _appSettingsKey = 'app/settings.json';

/// 书籍的章节正文目录名
const String _chaptersDirName = 'chapters';

/// 书籍的设定项目录名
const String _settingsDirName = 'settings';

/// 以当前平台的分隔符拼接路径片段
String _joinPath(List<String> parts) => parts.join(Platform.pathSeparator);

/// 章节归档包中的一个章节成员
class ChapterArchiveMember {
  /// 章节 UUID，同时也是归档包内的文件名
  final String uuid;

  /// 章节正文在本地的绝对路径
  final String localPath;

  /// 章节正文的内容哈希（sha256 十六进制字符串），为空表示本地文件缺失
  final String contentHash;

  /// 章节正文的字节数
  final int size;

  const ChapterArchiveMember({
    required this.uuid,
    required this.localPath,
    required this.contentHash,
    required this.size,
  });

  /// 本地是否存在该章节正文
  bool get exists => contentHash.isNotEmpty;

  /// 转换为待打包章节
  ChapterArchiveSource toSource() => ChapterArchiveSource(
    uuid: uuid,
    localPath: localPath,
    hash: contentHash,
    size: size,
  );
}

/// 章节正文哈希的缓存项
///
/// 章节以归档包为单位传输，不再作为独立的同步单元，
/// 但逐章哈希仍是判断归档包是否变化的基础，因此单独缓存以避免每次同步重读全部章节文件
class ChapterHashCacheEntry {
  /// 缓存键
  final String key;

  /// 章节正文的内容哈希
  final String hash;

  /// 章节正文的字节数
  final int size;

  /// 章节正文的最后修改时间
  final DateTime modifiedAt;

  const ChapterHashCacheEntry({
    required this.key,
    required this.hash,
    required this.size,
    required this.modifiedAt,
  });
}

/// 工作区索引结果
///
/// 既包含当前已存在的本地逻辑文件，也提供「逻辑键 → 本地路径」与
/// 「归档包 → 章节成员」的解析能力，使远端新增的文件也能定位到它在本机的落点
class WorkspaceIndex {
  /// 当前已存在的本地文件
  final List<LocalSyncFile> files;

  /// 普通文件逻辑键 → 本地绝对路径
  final Map<String, String> _plainPaths;

  /// 章节归档包逻辑键 → 章节成员列表
  final Map<String, List<ChapterArchiveMember>> _archiveMembers;

  /// 章节正文哈希缓存，供调用方写回状态存储
  final List<ChapterHashCacheEntry> chapterHashCache;

  const WorkspaceIndex({
    required this.files,
    required Map<String, String> plainPaths,
    required Map<String, List<ChapterArchiveMember>> archiveMembers,
    required this.chapterHashCache,
  }) : _plainPaths = plainPaths,
       _archiveMembers = archiveMembers;

  /// 解析逻辑键对应的本地绝对路径
  ///
  /// 返回 null 表示无法定位：远端存在该文件，但本地数据库尚未记录对应实体
  String? localPathOf(String key) {
    final plainPath = _plainPaths[key];
    if (plainPath != null) return plainPath;

    // 归档包以章节正文所在目录作为其本地位置
    final members = _archiveMembers[key];
    if (members != null && members.isNotEmpty) {
      return File(members.first.localPath).parent.path;
    }

    return null;
  }

  /// 获取归档包的章节成员列表
  ///
  /// 返回 null 表示该逻辑键不是归档包
  List<ChapterArchiveMember>? archiveMembersOf(String key) =>
      _archiveMembers[key];

  /// 获取归档包中指定章节的本地路径
  String? chapterPathOf(String key, String chapterUuid) {
    final members = _archiveMembers[key];
    if (members == null) return null;
    for (final member in members) {
      if (member.uuid == chapterUuid) return member.localPath;
    }
    return null;
  }
}

/// 工作区索引器
///
/// 将本地数据库记录与磁盘文件映射为「逻辑文件表」，供同步比对使用。
/// 索引范围包括：
/// - 书籍的章节正文（按每 [kChapterChunkSize] 章合并为一个归档包）
/// - 书籍的设定项正文、封面、自定义高亮配置
/// - 应用配置文件
///
/// 为提高性能，文件内容哈希优先复用基线中记录的结果，
/// 仅当文件大小或修改时间发生变化时才重新计算
class WorkspaceIndexer {
  const WorkspaceIndexer();

  // ================= 索引入口 =================

  /// 扫描工作区，生成索引结果
  ///
  /// [isar] 应用数据库实例
  /// [baselines] 同步基线，用于复用文件哈希并据此判断文件是否变化
  Future<WorkspaceIndex> scan({
    required Isar isar,
    required Map<String, SyncBaselineRecord> baselines,
  }) async {
    final files = <LocalSyncFile>[];
    final plainPaths = <String, String>{};
    final archiveMembers = <String, List<ChapterArchiveMember>>{};
    final hashCache = <ChapterHashCacheEntry>[];

    await _collectBooks(
      isar: isar,
      baselines: baselines,
      files: files,
      plainPaths: plainPaths,
      archiveMembers: archiveMembers,
      hashCache: hashCache,
    );

    // 应用配置文件
    final configFilePath = AppPaths.instance.configFilePath;
    await _collectPlainFile(
      baselines: baselines,
      files: files,
      plainPaths: plainPaths,
      key: _appSettingsKey,
      localPath: configFilePath,
    );

    return WorkspaceIndex(
      files: files,
      plainPaths: plainPaths,
      archiveMembers: archiveMembers,
      chapterHashCache: hashCache,
    );
  }

  // ================= 书籍相关文件 =================

  /// 收集书籍相关的全部同步文件
  Future<void> _collectBooks({
    required Isar isar,
    required Map<String, SyncBaselineRecord> baselines,
    required List<LocalSyncFile> files,
    required Map<String, String> plainPaths,
    required Map<String, List<ChapterArchiveMember>> archiveMembers,
    required List<ChapterHashCacheEntry> hashCache,
  }) async {
    final books = await isar.bookModels.where().findAll();
    if (books.isEmpty) return;

    final worksPath = await AppPaths.instance.getBooksPath();

    // 按书籍分组，避免每本书都遍历一次全量章节与设定项
    final chaptersByBook = _groupByBookUuid(
      await isar.chapterModels.where().findAll(),
      (chapter) => chapter.bookUuid,
    );
    final settingItemsByBook = _groupByBookUuid(
      await isar.settingItemModels.where().findAll(),
      (item) => item.bookUuid,
    );

    for (final book in books) {
      if (book.uuid.isEmpty || book.title.isEmpty) continue;
      final bookFolder = _joinPath([worksPath, book.title]);

      // 章节正文：按顺序每 kChapterChunkSize 章合并为一个归档包
      await _collectChapterChunks(
        bookUuid: book.uuid,
        chapters: chaptersByBook[book.uuid] ?? const <ChapterModel>[],
        bookFolder: bookFolder,
        baselines: baselines,
        files: files,
        archiveMembers: archiveMembers,
        hashCache: hashCache,
      );

      // 设定项正文
      for (final item
          in settingItemsByBook[book.uuid] ?? const <SettingItemModel>[]) {
        if (item.filePath.isEmpty) continue;
        await _collectPlainFile(
          baselines: baselines,
          files: files,
          plainPaths: plainPaths,
          key:
              '$_booksKeyPrefix${book.uuid}/settings/'
              '${item.uuid}${GlobalConstants.settingFileExtension}',
          localPath: _joinPath([bookFolder, _settingsDirName, item.filePath]),
        );
      }

      // 封面（远端保留原扩展名，避免不同格式互相覆盖）
      if (book.coverPath.isNotEmpty) {
        await _collectPlainFile(
          baselines: baselines,
          files: files,
          plainPaths: plainPaths,
          key:
              '$_booksKeyPrefix${book.uuid}/cover${_extensionOf(book.coverPath)}',
          localPath: book.coverPath,
        );
      }

      // 自定义高亮配置
      await _collectPlainFile(
        baselines: baselines,
        files: files,
        plainPaths: plainPaths,
        key: '$_booksKeyPrefix${book.uuid}/$kCustomHighlightFileName',
        localPath: _joinPath([bookFolder, kCustomHighlightFileName]),
      );
    }
  }

  /// 收集一本书的章节归档包
  ///
  /// 章节按顺序每 [kChapterChunkSize] 章划分为一块，
  /// 两端依据同一份章节顺序能够推导出完全相同的分块，无需额外的分块元数据
  Future<void> _collectChapterChunks({
    required String bookUuid,
    required List<ChapterModel> chapters,
    required String bookFolder,
    required Map<String, SyncBaselineRecord> baselines,
    required List<LocalSyncFile> files,
    required Map<String, List<ChapterArchiveMember>> archiveMembers,
    required List<ChapterHashCacheEntry> hashCache,
  }) async {
    if (chapters.isEmpty) return;

    // 按全局顺序排列，顺序相同时以 UUID 兜底，保证分块结果稳定
    final sorted = List<ChapterModel>.from(chapters)
      ..sort((a, b) {
        final byOrder = a.orderIndex.compareTo(b.orderIndex);
        return byOrder != 0 ? byOrder : a.uuid.compareTo(b.uuid);
      });

    final chaptersDirPath = _joinPath([bookFolder, _chaptersDirName]);

    for (var start = 0; start < sorted.length; start += kChapterChunkSize) {
      final chunkIndex = start ~/ kChapterChunkSize;
      final end = start + kChapterChunkSize;
      final slice = sorted.sublist(
        start,
        end > sorted.length ? sorted.length : end,
      );
      final chunkKey = chapterChunkKey(bookUuid, chunkIndex);

      var allExist = true;
      var totalSize = 0;
      DateTime? latestModified;
      final members = <ChapterArchiveMember>[];

      for (final chapter in slice) {
        if (chapter.uuid.isEmpty || chapter.filePath.isEmpty) {
          allExist = false;
          continue;
        }

        final localPath = _joinPath([chaptersDirPath, chapter.filePath]);
        final cacheKey = chapterCacheKeyOf(bookUuid, chapter.uuid);
        final resolved = await _resolveFileContent(
          cacheKey,
          localPath,
          baselines,
        );

        if (resolved == null) {
          allExist = false;
          members.add(
            ChapterArchiveMember(
              uuid: chapter.uuid,
              localPath: localPath,
              contentHash: '',
              size: 0,
            ),
          );
          continue;
        }

        members.add(
          ChapterArchiveMember(
            uuid: chapter.uuid,
            localPath: localPath,
            contentHash: resolved.hash,
            size: resolved.size,
          ),
        );
        hashCache.add(
          ChapterHashCacheEntry(
            key: cacheKey,
            hash: resolved.hash,
            size: resolved.size,
            modifiedAt: resolved.modifiedAt,
          ),
        );

        totalSize += resolved.size;
        if (latestModified == null ||
            resolved.modifiedAt.isAfter(latestModified)) {
          latestModified = resolved.modifiedAt;
        }
      }

      archiveMembers[chunkKey] = members;

      // 仅在全部章节正文均存在时才把归档包视为本地文件；
      // 任一章缺失说明本地归档不完整，交由比对阶段按「本地不存在」处理
      if (!allExist || members.isEmpty) continue;

      final manifest = buildManifest([
        for (final member in members) member.toSource(),
      ]);
      files.add(
        LocalSyncFile(
          key: chunkKey,
          localPath: chaptersDirPath,
          size: totalSize,
          modifiedAt: latestModified!,
          contentHash: manifestHashOf(manifest),
        ),
      );
    }
  }

  // ================= 文件收集 =================

  /// 收集普通文件
  ///
  /// 无论文件是否存在都会登记其本地路径，便于远端新增的同名文件定位落点
  Future<void> _collectPlainFile({
    required Map<String, SyncBaselineRecord> baselines,
    required List<LocalSyncFile> files,
    required Map<String, String> plainPaths,
    required String key,
    required String localPath,
  }) async {
    plainPaths[key] = localPath;

    final resolved = await _resolveFileContent(key, localPath, baselines);
    if (resolved == null) return;

    files.add(
      LocalSyncFile(
        key: key,
        localPath: localPath,
        size: resolved.size,
        modifiedAt: resolved.modifiedAt,
        contentHash: resolved.hash,
      ),
    );
  }

  /// 解析文件内容特征
  ///
  /// 文件不存在时返回 null；文件大小与修改时间均与基线一致时，
  /// 直接复用基线中的哈希，避免重复读取文件内容
  Future<_ResolvedContent?> _resolveFileContent(
    String key,
    String localPath,
    Map<String, SyncBaselineRecord> baselines,
  ) async {
    final file = File(localPath);
    if (!await file.exists()) return null;

    final stat = await file.stat();
    final baseline = baselines[key];
    if (baseline != null &&
        !baseline.deleted &&
        baseline.localHash != null &&
        baseline.localSize == stat.size &&
        baseline.localModifiedMs == stat.modified.millisecondsSinceEpoch) {
      return _ResolvedContent(
        hash: baseline.localHash!,
        size: stat.size,
        modifiedAt: stat.modified,
      );
    }

    // 以流式方式计算哈希，避免大文件一次性读入内存
    final digest = await sha256.bind(file.openRead()).first;
    return _ResolvedContent(
      hash: digest.toString(),
      size: stat.size,
      modifiedAt: stat.modified,
    );
  }

  // ================= 工具方法 =================

  /// 按书籍 UUID 对记录分组
  Map<String, List<T>> _groupByBookUuid<T>(
    List<T> items,
    String Function(T item) bookUuidOf,
  ) {
    final grouped = <String, List<T>>{};
    for (final item in items) {
      grouped.putIfAbsent(bookUuidOf(item), () => []).add(item);
    }
    return grouped;
  }

  /// 获取路径中的扩展名（含点号），无扩展名时返回空字符串
  String _extensionOf(String path) {
    final dotIndex = path.lastIndexOf('.');
    final separatorIndex = path.lastIndexOf(Platform.pathSeparator);
    if (dotIndex <= separatorIndex) return '';
    return path.substring(dotIndex);
  }
}

/// 章节正文哈希的缓存键
///
/// 章节不再作为独立的同步单元，该键仅用于标记缓存归属
String chapterCacheKeyOf(String bookUuid, String chapterUuid) {
  return '$_booksKeyPrefix$bookUuid/$_chaptersDirName/'
      '$chapterUuid${GlobalConstants.chapterFileExtension}';
}

/// 已解析的文件内容特征
class _ResolvedContent {
  /// 内容哈希（sha256 十六进制字符串）
  final String hash;

  /// 文件大小（字节）
  final int size;

  /// 文件最后修改时间
  final DateTime modifiedAt;

  const _ResolvedContent({
    required this.hash,
    required this.size,
    required this.modifiedAt,
  });
}
