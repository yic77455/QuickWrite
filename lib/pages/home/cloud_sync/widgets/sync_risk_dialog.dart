import 'package:flutter/material.dart';
import 'package:quick_write/core/services/cloud_sync/sync_models.dart';
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
