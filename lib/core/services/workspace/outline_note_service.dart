import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:quick_write/core/models/outline_note.dart';
import 'package:quick_write/core/services/cloud_sync/cloud_sync_service.dart';
import 'package:quick_write/core/services/workspace/book_folder_service.dart';
import 'package:quick_write/core/services/workspace/outline_companion_store.dart';
import 'package:uuid/uuid.dart';

/// 大纲备注服务
///
/// 负责单个设定项「节点备注与附加图片」的持久化读写：
/// - 备注与图片文件名保存在设定项的合并伴生 `.json` 中，
///   与大纲 Markdown 分离，避免备注内容影响导出与备份正文；
/// - 图片文件存放在设定项文件所在目录的 image 文件夹下，
///   插入时复制、删除时同步移除，并通知云同步。
class OutlineNoteService {
  /// 读取设定项的备注内容
  ///
  /// 文件不存在或格式非法时返回空内容。
  Future<OutlineNoteFile> read(String? settingItemFilePath) async {
    final Map<String, OutlineNoteData> notes =
        await OutlineCompanionStore.instance.readNotes(settingItemFilePath);
    return OutlineNoteFile(nodes: notes);
  }

  /// 保存设定项的备注内容
  ///
  /// [nodes] 为节点路径到备注与图片数据的映射；
  /// 没有任何内容时清空对应字段，避免残留旧备注。
  Future<bool> save({
    required String? settingItemFilePath,
    required Map<String, OutlineNoteData> nodes,
  }) {
    return OutlineCompanionStore.instance.updateNotes(settingItemFilePath, nodes);
  }

  /// 随设定项文件移动迁移节点附加图片
  ///
  /// 设定项移动到其他分组后所在目录改变，节点引用的图片需要一并搬到新目录的
  /// image 文件夹，避免图片路径失效；目标目录中已存在同名文件时保留原有文件。
  Future<void> moveImages({
    required String? oldSettingItemFilePath,
    required String? newSettingItemFilePath,
    required Iterable<String> imageFileNames,
  }) async {
    final String? oldDirectory = BookFolderService.settingImageDirectory(oldSettingItemFilePath);
    final String? newDirectory = BookFolderService.settingImageDirectory(newSettingItemFilePath);
    if (oldDirectory == null || newDirectory == null || oldDirectory == newDirectory) return;

    try {
      bool moved = false;
      for (final String fileName in imageFileNames) {
        if (fileName.isEmpty) continue;

        final File source = File('$oldDirectory${Platform.pathSeparator}$fileName');
        if (!await source.exists()) continue;

        final File target = File('$newDirectory${Platform.pathSeparator}$fileName');
        if (await target.exists()) continue;

        final Directory targetDir = target.parent;
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }
        await source.rename(target.path);
        moved = true;
      }
      // 图片位置发生变化，交由云同步服务安排一次同步
      if (moved) CloudSyncService.instance.notifyLocalChange();
    } catch (e) {
      debugPrint('迁移备注图片失败: $e');
    }
  }

  /// 将选中的图片复制到设定项的 image 目录
  ///
  /// 复制成功后返回图片文件名（不含路径），供节点记录；
  /// 图片目录不存在时自动创建，文件名使用 UUID 避免重名覆盖。
  Future<String?> importImage({
    required String? settingItemFilePath,
    required String sourcePath,
  }) async {
    final String? imageDirectory = BookFolderService.settingImageDirectory(settingItemFilePath);
    if (imageDirectory == null) return null;

    try {
      final File source = File(sourcePath);
      if (!await source.exists()) return null;

      final String fileName = '${const Uuid().v4()}${_imageExtensionOf(sourcePath)}';
      final Directory targetDir = Directory(imageDirectory);
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      await source.copy('$imageDirectory${Platform.pathSeparator}$fileName');
      // 图片文件参与云同步，复制完成后安排一次同步
      CloudSyncService.instance.notifyLocalChange();
      return fileName;
    } catch (e) {
      debugPrint('插入备注图片失败: $e');
      return null;
    }
  }

  /// 删除设定项 image 目录下的图片文件
  ///
  /// 文件不存在时直接视为成功，避免残留引用阻塞删除操作。
  Future<void> deleteImage({
    required String? settingItemFilePath,
    required String imageFileName,
  }) async {
    final String? imagePath = BookFolderService.settingImageFilePath(
      settingItemFilePath,
      imageFileName,
    );
    if (imagePath == null) return;

    try {
      final File file = File(imagePath);
      if (!await file.exists()) return;
      await file.delete();
      // 图片文件参与云同步，删除后安排一次同步
      CloudSyncService.instance.notifyLocalChange();
    } catch (e) {
      debugPrint('删除备注图片失败: $e');
    }
  }

  /// 获取图片文件的扩展名（含点号）
  ///
  /// 仅保留常见图片格式，无法识别时统一按 PNG 处理，
  /// 保证复制出的文件名仍能作为图片被正常读取。
  String _imageExtensionOf(String path) {
    final int dotIndex = path.lastIndexOf('.');
    final int separatorIndex = path.lastIndexOf(Platform.pathSeparator);
    if (dotIndex <= separatorIndex) return '.png';
    final String extension = path.substring(dotIndex).toLowerCase();
    const List<String> allowedExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'];
    return allowedExtensions.contains(extension) ? extension : '.png';
  }
}
