import 'package:flutter/material.dart';
import 'package:quick_write/core/services/cloud_sync/sync_models.dart';
import 'package:quick_write/core/utils/file_explorer.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 展示同步风险确认弹窗
///
/// 通过应用根导航器弹出确认框，使任意界面、任意时机触发的同步
/// 被风险预检拦截时都能第一时间告知用户。
/// [navigatorKey] 应用根导航器的键；界面尚未就绪时无法弹窗，按未确认处理
Future<bool> showSyncRiskDialog(
  GlobalKey<NavigatorState> navigatorKey,
  SyncRiskAssessment risk,
) async {
  final context = navigatorKey.currentContext;
  if (context == null) return false;

  // 涉及删除云端内容时单独说明影响范围，避免用「不会覆盖」描述一次删除
  final deletingRemote = risk.deletedBookDirCount > 0;
  final title = deletingRemote
      ? '删除云端数据确认'
      : (risk.isFirstSync ? '首次同步确认' : '同步影响面较大');
  final description = deletingRemote
      ? '${risk.reason ?? '本次同步会删除云端的书籍内容'}。\n'
            '删除的是云端副本，本机内容不受影响；但云端的删除无法撤销，请确认后再继续。'
      : '${risk.reason ?? '本次同步改动较大'}。\n'
            '同步只会补齐两端缺失的内容，两端都修改过的文件会保留双份，不会覆盖你的稿件。';

  return showConfirmDialog(
    context: context,
    title: title,
    description: description,
    type: ConfirmType.warning,
    confirmText: deletingRemote ? '确认删除并同步' : '继续同步',
    cancelText: '取消',
    // 高风险同步必须由用户明确选择，不允许误触弹窗外部而静默跳过
    barrierDismissible: false,
  );
}

/// 展示同步冲突副本提示弹窗
///
/// 同步过程中为本机版本另存出冲突副本时弹出，说明副本数量与文件名特征，
/// 并提供在文件管理器中定位副本的入口，使副本不会只停留在磁盘上而被忽略。
/// [navigatorKey] 应用根导航器的键；界面尚未就绪时无法弹窗，直接跳过提示
/// [conflictCopyPaths] 本次另存出的冲突副本路径，用于定位查看
Future<void> showSyncConflictDialog(
  GlobalKey<NavigatorState> navigatorKey,
  List<String> conflictCopyPaths,
) async {
  final context = navigatorKey.currentContext;
  if (context == null) return;

  final hasCopies = conflictCopyPaths.isNotEmpty;

  final viewed = await showConfirmDialog(
    context: context,
    title: '同步保留了冲突副本',
    barrierDismissible: false,
    description:
        '本次同步有 ${conflictCopyPaths.length} 处内容两端都做过修改，'
        '已把本机版本另存为冲突副本，正式的稿件内容不受影响。\n'
        '副本文件名形如「原名(冲突-设备名-时间戳).扩展名」，与原文位于同一目录，'
        '请前往查看后再自行取舍。',
    // 存在副本时优先提供定位入口，否则只保留关闭按钮
    confirmText: hasCopies ? '查看文件' : '知道了',
    cancelText: hasCopies ? '知道了' : null,
  );

  // 用户选择查看时，在系统文件管理器中定位全部冲突副本
  if (viewed && hasCopies) {
    await FileExplorer.revealAll(conflictCopyPaths);
  }
}