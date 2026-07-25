// 分卷数据迁移服务
//
// 将文件系统中的分卷目录迁移为数据库记录，
// 仅在数据库中无分卷记录时执行（首次迁移）。
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/models/volume.dart';
import 'book_folder_service.dart';

/// 分卷数据迁移服务
class VolumeMigrationService {
  VolumeMigrationService(this._isar, this._folder);

  final Isar _isar;

  final BookFolderService _folder;

  /// 从文件系统迁移分卷数据到数据库
  ///
  /// 仅在 [volumes] 为空时执行（首次迁移）。
  /// 返回是否执行了迁移；执行后调用方需重新加载分卷与章节数据。
  Future<bool> runIfNeeded({
    required BookModel book,
    required List<VolumeModel> volumes,
    required List<ChapterModel> chapters,
  }) async {
    // 如果数据库中已有分卷记录，跳过迁移
    if (volumes.isNotEmpty) return false;

    // 扫描文件系统中的分卷目录
    final chaptersDir = Directory('${_folder.bookFolderPath(book)}${Platform.pathSeparator}chapters');
    if (!chaptersDir.existsSync()) return false;

    final dirNames = <String>[];
    for (final entity in chaptersDir.listSync()) {
      if (entity is Directory) {
        dirNames.add(entity.uri.pathSegments.where((s) => s.isNotEmpty).last);
      }
    }

    if (dirNames.isEmpty) return false;

    // 为每个分卷目录创建数据库记录
    final newVolumes = <VolumeModel>[];
    final volumeNameToUuid = <String, String>{};
    for (int i = 0; i < dirNames.length; i++) {
      final volumeName = dirNames[i];
      final volumeUuid = const Uuid().v4();

      final volume = VolumeModel()
        ..uuid = volumeUuid
        ..bookUuid = book.uuid
        ..name = volumeName
        ..orderIndex = i
        ..createdAt = DateTime.now()
        ..updatedAt = DateTime.now();

      newVolumes.add(volume);
      volumeNameToUuid[volumeName] = volumeUuid;
    }

    // 根据章节的 filePath 判断其所属分卷，设置 volumeUuid
    // filePath 格式："分卷名/章节名.txt" 或 "章节名.txt"
    for (final chapter in chapters) {
      if (chapter.filePath.contains(Platform.pathSeparator)) {
        final pathParts = chapter.filePath.split(Platform.pathSeparator);
        final dirName = pathParts.first;
        if (volumeNameToUuid.containsKey(dirName)) {
          chapter.volumeUuid = volumeNameToUuid[dirName]!;
        }
      }
    }

    // 批量写入数据库
    await _isar.writeTxn(() async {
      for (final volume in newVolumes) {
        await _isar.volumeModels.put(volume);
      }
      for (final chapter in chapters) {
        if (chapter.volumeUuid.isNotEmpty) {
          await _isar.chapterModels.put(chapter);
        }
      }
    });

    debugPrint('已从文件系统迁移 ${newVolumes.length} 个分卷到数据库');
    return true;
  }
}
