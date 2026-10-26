import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:quick_write/core/services/cloud_sync/sync_models.dart';

/// 同步冲突处理
///
/// 负责在用户选择冲突副本后，把副本内容落回正式文件，
/// 使下一次同步能够把用户确认的版本推送到云端
class SyncConflictResolver {
  SyncConflictResolver._();

  /// 用冲突副本替换正式文件
  ///
  /// 先复制到正式文件旁的临时文件，再重命名覆盖目标，避免写入中途失败留下半截内容；
  /// 替换成功后删除冲突副本，避免同一内容以副本形式长期残留。
  /// 副本不存在时抛出异常，由调用方提示用户
  static Future<void> replaceWithCopy(SyncConflictCopy conflict) async {
    final copyFile = File(conflict.copyPath);
    if (!await copyFile.exists()) {
      throw StateError('冲突副本已不存在');
    }

    final originalFile = File(conflict.originalPath);
    final originalDir = originalFile.parent;
    if (!await originalDir.exists()) {
      await originalDir.create(recursive: true);
    }

    // 清理可能残留的同名临时文件，避免复制时读到旧内容
    final tempFile = File('${conflict.originalPath}$kSyncTempSuffix');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    await copyFile.copy(tempFile.path);
    try {
      // 目标已存在时 rename 会直接替换，避免出现「先删除再改名」的空窗
      await tempFile.rename(conflict.originalPath);
    } catch (e) {
      // 替换失败时清理临时文件，避免残留半成品干扰后续同步
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    }

    // 正式文件已持有用户选择的版本，副本不再需要保留
    await copyFile.delete();
    debugPrint('已用冲突副本替换正式文件: ${conflict.originalPath}');
  }
}
