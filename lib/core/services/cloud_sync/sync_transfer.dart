import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:quick_write/core/services/cloud_sync/chapter_archive.dart';
import 'package:quick_write/core/services/cloud_sync/sync_models.dart';
import 'package:quick_write/core/services/cloud_sync/sync_state_store.dart';
import 'package:quick_write/core/services/cloud_sync/webdav_client.dart';
import 'package:quick_write/core/services/cloud_sync/workspace_indexer.dart';

/// 云同步传输执行器
///
/// 负责按同步计划执行单个逻辑文件的读取与写入，落实数据安全策略：
/// - 上传与下载都先落到临时位置，确认完整后再替换目标
/// - 下载完成后校验内容哈希，校验通过才落盘
/// - 出现冲突时保留双份，绝不覆盖用户的任何一版内容
/// - 删除远端文件时只做软删除，移动到 .trash 目录
///
/// 逻辑文件分为两类：章节归档包与普通文件，两者的落地方式不同
class SyncTransfer {
  SyncTransfer({
    required WebDavClient webdav,
    required SyncStateStore stateStore,
  }) : _webdav = webdav,
       _stateStore = stateStore;

  /// 远端通信客户端
  final WebDavClient _webdav;

  /// 本机同步状态存储
  final SyncStateStore _stateStore;

  // ================= 执行入口 =================

  /// 执行单个计划项
  ///
  /// 执行失败时抛出异常，由调用方汇总；返回本次另存出的冲突副本路径
  Future<List<String>> run(SyncPlanItem item, WorkspaceIndex index) async {
    switch (item.action) {
      case SyncAction.upload:
        if (isChapterChunkKey(item.key)) {
          await _uploadArchive(item, index);
        } else {
          await _uploadPlain(item);
        }
        return const [];
      case SyncAction.download:
        if (isChapterChunkKey(item.key)) {
          return await _downloadArchive(item, index);
        }
        await _downloadPlain(item, index);
        return const [];
      case SyncAction.keepBoth:
        if (isChapterChunkKey(item.key)) {
          return await _keepBothArchive(item, index);
        }
        return await _keepBothPlain(item, index);
    }
  }

  // ================= 普通文件：上传与下载 =================

  /// 上传普通文件
  ///
  /// 先上传到远端的临时名称，再移动到正式路径，
  /// 保证目标文件在传输过程中不会被写坏
  ///
  /// 上传后的基线由引擎在回读远端标识后统一写入，
  /// 避免为每个文件额外发起一次属性查询，从而减少请求次数
  Future<void> _uploadPlain(SyncPlanItem item) async {
    final remotePath = _webdav.remotePathOf(item.key);
    final tempPath = '$remotePath$kSyncTempSuffix';

    await _webdav.uploadFile(item.local!.localPath, tempPath);
    await _webdav.moveFile(tempPath, remotePath);
  }

  /// 下载远端文件覆盖本地
  Future<void> _downloadPlain(SyncPlanItem item, WorkspaceIndex index) async {
    final targetPath = _requireLocalPath(item.key, index);
    final remote = item.remote!;

    final preparedHash = await _prepareDownload(targetPath, remote);
    final committed = await _commitDownload(targetPath, preparedHash);
    _stateStore.recordSynced(
      key: item.key,
      localHash: committed.hash,
      localSize: committed.size,
      localModifiedAt: committed.modifiedAt,
      remoteContentId: remote.contentId,
    );
  }

  /// 处理普通文件的两端同时修改
  ///
  /// 远端版本落到正式路径，本地版本另存为冲突副本，两个版本都不会被丢弃；
  /// 返回另存出的冲突副本路径
  Future<List<String>> _keepBothPlain(SyncPlanItem item, WorkspaceIndex index) async {
    final local = item.local!;
    final targetPath = _requireLocalPath(item.key, index);
    final remote = item.remote!;

    // 先下载并校验远端内容，确认可以安全落地后再处理本地版本
    final preparedHash = await _prepareDownload(targetPath, remote);

    // 内容一致说明并非真正的冲突，直接以远端内容作为本地状态
    if (preparedHash == local.contentHash) {
      await _discardPrepared(targetPath);
      _stateStore.recordSynced(
        key: item.key,
        localHash: local.contentHash,
        localSize: local.size,
        localModifiedAt: local.modifiedAt,
        remoteContentId: remote.contentId,
      );
      return const [];
    }

    // 把本地版本另存为冲突副本
    final conflictPath = _conflictPathOf(targetPath);
    await File(targetPath).copy(conflictPath);

    final committed = await _commitDownload(targetPath, preparedHash);
    _stateStore.recordSynced(
      key: item.key,
      localHash: committed.hash,
      localSize: committed.size,
      localModifiedAt: committed.modifiedAt,
      remoteContentId: remote.contentId,
    );
    debugPrint('同步冲突已保留双份，本地版本另存为: $conflictPath');
    return [conflictPath];
  }

  // ================= 章节归档包：上传与下载 =================

  /// 上传章节归档包
  ///
  /// 内容在内存中打包完成后直接上传，避免在本地留下临时归档文件
  Future<void> _uploadArchive(SyncPlanItem item, WorkspaceIndex index) async {
    final sources = _requireSources(item.key, index);
    final manifest = buildManifest(sources);
    final bytes = await packArchive(manifest, sources);

    final remotePath = _webdav.remotePathOf(item.key);
    await _webdav.uploadBytes(bytes, '$remotePath$kSyncTempSuffix');
    await _webdav.moveFile('$remotePath$kSyncTempSuffix', remotePath);
  }

  /// 下载章节归档包并展开到本地
  ///
  /// 本地归档不完整时，包内已存在且与远端不一致的章节会另存为冲突副本；
  /// 返回另存出的冲突副本路径
  Future<List<String>> _downloadArchive(SyncPlanItem item, WorkspaceIndex index) async {
    final content = await _fetchArchiveContent(item.key);
    final result = await _writeArchiveChapters(
      key: item.key,
      index: index,
      content: content,
      keepLocalConflict: false,
    );

    _recordArchiveBaseline(item.key, item.remote!, content, result.written);
    return result.copies;
  }

  /// 处理章节归档包的两端同时修改
  ///
  /// 远端版本展开到本地，本地发生过修改的章节另存为冲突副本；
  /// 返回另存出的冲突副本路径
  Future<List<String>> _keepBothArchive(SyncPlanItem item, WorkspaceIndex index) async {
    final content = await _fetchArchiveContent(item.key);
    final result = await _writeArchiveChapters(
      key: item.key,
      index: index,
      content: content,
      keepLocalConflict: true,
    );

    _recordArchiveBaseline(item.key, item.remote!, content, result.written);
    return result.copies;
  }

  // ================= 章节归档包：内部实现 =================

  /// 获取归档包中需要打包的章节
  List<ChapterArchiveSource> _requireSources(String key, WorkspaceIndex index) {
    final members = index.archiveMembersOf(key);
    if (members == null || members.isEmpty) {
      throw StateError('无法定位章节归档内容: $key');
    }

    final sources = [
      for (final member in members)
        if (member.exists) member.toSource(),
    ];
    if (sources.isEmpty) {
      throw StateError('章节归档包中没有可上传的内容: $key');
    }
    return sources;
  }

  /// 下载并校验归档包内容
  ///
  /// 校验在写入本地之前完成，任一章节损坏都不会改动本地文件
  Future<ChapterArchiveContent> _fetchArchiveContent(String key) async {
    final bytes = await _webdav.downloadBytes(_webdav.remotePathOf(key));
    final content = unpackArchive(bytes);
    verifyArchiveContent(content);
    return content;
  }

  /// 将归档包中的章节写入本地
  ///
  /// [keepLocalConflict] 为 true 时，把与远端不一致的本地版本另存为冲突副本。
  /// 返回成功写入的章节数量与另存出的冲突副本路径
  Future<({int written, List<String> copies})> _writeArchiveChapters({
    required String key,
    required WorkspaceIndex index,
    required ChapterArchiveContent content,
    required bool keepLocalConflict,
  }) async {
    final members =
        index.archiveMembersOf(key) ?? const <ChapterArchiveMember>[];
    final localHashByUuid = {
      for (final member in members)
        if (member.exists) member.uuid: member.contentHash,
    };

    // 归档包本地不完整（缺少部分章节正文）时，本次下载是为了补齐缺失内容；
    // 此时包内其他章节可能存在尚未同步的本地修改，一并保留冲突副本，避免被远端版本覆盖
    final preserveLocal =
        keepLocalConflict || members.any((member) => !member.exists);

    var written = 0;
    final copies = <String>[];
    for (final entry in content.manifest.entries) {
      final targetPath = index.chapterPathOf(key, entry.uuid);
      if (targetPath == null) {
        // 本地尚无该章节的元数据，无法确定落点，待元数据同步建立实体后自动补齐
        debugPrint('跳过本地未知章节: ${entry.uuid}');
        continue;
      }

      if (preserveLocal) {
        final localHash = localHashByUuid[entry.uuid];
        if (localHash != null && localHash != entry.hash) {
          final conflictPath = _conflictPathOf(targetPath);
          await File(targetPath).copy(conflictPath);
          copies.add(conflictPath);
        }
      }

      await _writeBytesAtomically(targetPath, content.chapters[entry.uuid]!);
      written++;
    }

    return (written: written, copies: copies);
  }

  /// 记录归档包同步完成后的状态
  ///
  /// 归档包未能在本地完整展开时不记录状态，避免下次同步把它误判为本地删除
  void _recordArchiveBaseline(
    String key,
    RemoteSyncFile remote,
    ChapterArchiveContent content,
    int writtenCount,
  ) {
    if (writtenCount < content.manifest.entries.length) {
      debugPrint('归档包未完整展开，本次不记录同步状态: $key');
      return;
    }

    // 展开后本地内容与远端完全一致，直接沿用远端清单作为双方的内容标识
    var totalSize = 0;
    for (final entry in content.manifest.entries) {
      totalSize += entry.size;
    }

    _stateStore.recordSynced(
      key: key,
      localHash: manifestHashOf(content.manifest),
      localSize: totalSize,
      localModifiedAt: DateTime.now(),
      remoteContentId: remote.contentId,
    );
  }

  /// 将字节内容原子写入目标路径
  ///
  /// 先写入同目录的临时文件再重命名，避免出现写了一半的文件
  Future<void> _writeBytesAtomically(String targetPath, Uint8List bytes) async {
    final targetDir = File(targetPath).parent;
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final tempFile = File('$targetPath$kSyncTempSuffix');
    await tempFile.writeAsBytes(bytes, flush: true);
    await tempFile.rename(targetPath);
  }

  // ================= 普通文件：下载落地 =================

  /// 下载远端文件到目标路径旁的临时文件并校验
  ///
  /// 返回内容的哈希，此时目标文件尚未被修改
  Future<String> _prepareDownload(
    String targetPath,
    RemoteSyncFile remote,
  ) async {
    final targetDir = File(targetPath).parent;
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    // 清理可能残留的临时文件
    final tempFile = File('$targetPath$kSyncTempSuffix');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    await _webdav.downloadFile(_webdav.remotePathOf(remote.key), tempFile.path);

    // 校验下载结果的完整性，服务端未提供大小时跳过该校验
    final downloadedSize = await tempFile.length();
    if (remote.size > 0 && downloadedSize != remote.size) {
      await tempFile.delete();
      throw StateError('下载内容不完整（期望 ${remote.size} 字节，实际 $downloadedSize 字节）');
    }

    final digest = await sha256.bind(tempFile.openRead()).first;
    return digest.toString();
  }

  /// 将临时文件替换到目标路径
  ///
  /// 同一目录内的重命名接近原子操作，避免出现写了一半的文件
  Future<_SyncedFile> _commitDownload(
    String targetPath,
    String contentHash,
  ) async {
    await File('$targetPath$kSyncTempSuffix').rename(targetPath);

    final stat = await File(targetPath).stat();
    return _SyncedFile(
      hash: contentHash,
      size: stat.size,
      modifiedAt: stat.modified,
    );
  }

  /// 丢弃已下载到临时文件但不再需要的准备结果
  Future<void> _discardPrepared(String targetPath) async {
    final tempFile = File('$targetPath$kSyncTempSuffix');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
  }

  // ================= 工具方法 =================

  /// 获取逻辑键对应的本地路径，无法定位时抛出异常
  String _requireLocalPath(String key, WorkspaceIndex index) {
    final localPath = index.localPathOf(key);
    if (localPath == null) {
      throw StateError('无法定位本地路径: $key');
    }
    return localPath;
  }

  /// 生成冲突副本的路径
  ///
  /// 命名为「原文件名(冲突-设备名-时间).扩展名」，与源文件同目录
  String _conflictPathOf(String targetPath) {
    final dotIndex = targetPath.lastIndexOf('.');
    final separatorIndex = targetPath.lastIndexOf(Platform.pathSeparator);
    final hasExtension = dotIndex > separatorIndex;

    final basePath = hasExtension
        ? targetPath.substring(0, dotIndex)
        : targetPath;
    final extension = hasExtension ? targetPath.substring(dotIndex) : '';

    return '$basePath(冲突-${_stateStore.deviceName}-${_timeStampOf(DateTime.now())})$extension';
  }

  /// 生成日期戳（yyyyMMdd）
  String _dateStampOf(DateTime time) {
    return '${time.year}'
        '${time.month.toString().padLeft(2, '0')}'
        '${time.day.toString().padLeft(2, '0')}';
  }

  /// 生成时间戳（yyyyMMdd-HHmmss）
  String _timeStampOf(DateTime time) {
    return '${_dateStampOf(time)}-'
        '${time.hour.toString().padLeft(2, '0')}'
        '${time.minute.toString().padLeft(2, '0')}'
        '${time.second.toString().padLeft(2, '0')}';
  }
}

/// 已落盘的本地文件信息
class _SyncedFile {
  /// 内容哈希（sha256）
  final String hash;

  /// 文件大小（字节）
  final int size;

  /// 文件最后修改时间
  final DateTime modifiedAt;

  const _SyncedFile({
    required this.hash,
    required this.size,
    required this.modifiedAt,
  });
}
