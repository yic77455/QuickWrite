import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quick_write/core/services/cloud_sync/cloud_sync_service.dart';
import 'package:quick_write/core/services/multi_window_service.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/shared/widgets/qw_dialogs.dart';
import 'package:quick_write/shared/widgets/qw_snackbar.dart';

/// 打开工作台（根据设置决定是否在新窗口中打开）
///
/// 进入工作台前，开启实时同步时会先同步一次云端内容，
/// 确保工作台加载到其他设备上的最新改动；
/// 多窗口模式下，若该书的工作台窗口尚未打开，会先弹出加载弹窗冻结主窗口，
/// 等子窗口初始化完成后自动关闭弹窗；窗口已打开时则不弹窗，直接聚焦已有窗口
///
/// [context] 构建上下文（需要包含 Navigator）
/// [bookId] 要打开的书籍ID
/// [bookTitle] 书籍名称，用于加载提示文字显示
Future<void> openWorkspace({
  required BuildContext context,
  required String bookId,
  String? bookTitle,
}) async {
  // 该书的工作台窗口已打开时不会创建新窗口，也就不会收到"工作台就绪"通知，
  // 且数据早已加载完成，因此不等待同步，直接聚焦已有窗口
  if (SettingsService.instance.openWorkspaceInNewWindow &&
      MultiWindowService.instance.isWorkspaceWindowOpen(bookId)) {
    await MultiWindowService.instance.openWorkspaceWindow(bookId);
    return;
  }

  // 进入工作台前先同步一次，避免打开后看到的是其他设备更新之前的旧内容
  await _syncBeforeOpen(context);

  // 同步期间界面可能已被销毁，此时不再继续导航
  if (!context.mounted) return;

  // 单窗口模式：直接在当前窗口内导航到工作台
  if (!SettingsService.instance.openWorkspaceInNewWindow) {
    // 移动端以 push 方式打开，使系统返回键能沿原路返回书架
    if (PlatformCapabilities.isMobile) {
      context.push('/workspace/$bookId');
    } else {
      context.go('/workspace/$bookId');
    }
    return;
  }

  // 多窗口模式：先显示加载弹窗冻结主窗口，再创建窗口
  final message = bookTitle != null ? '正在打开《$bookTitle》……' : '正在打开工作台……';
  final dismissLoading = showLoadingDialog(
    context: context,
    message: message,
  );
  // 注册回调：子窗口就绪后关闭加载弹窗
  MultiWindowService.instance.onWorkspaceReady = dismissLoading;

  final result = await MultiWindowService.instance.openWorkspaceWindow(bookId);
  if (result == WorkspaceOpenResult.created) return;

  // 未能创建新窗口时不会有就绪通知，需立即关闭加载弹窗，
  // 否则弹窗将一直停留，导致主窗口卡在加载状态
  MultiWindowService.instance.onWorkspaceReady = null;
  dismissLoading();
  if (result == WorkspaceOpenResult.failed && context.mounted) {
    SnackBarService.showError(context, '打开工作台失败，请重试');
  }
}

/// 打开书籍前同步一次云端内容
///
/// 仅在实时同步开启时执行，同步期间展示等待提示；
/// 等待超时或同步失败时提示用户，但不阻断后续的打开流程
Future<void> _syncBeforeOpen(BuildContext context) async {
  final syncService = CloudSyncService.instance;
  if (!syncService.willSyncBeforeOpeningBook) return;

  final dismissLoading = showLoadingDialog(
    context: context,
    message: '正在同步云端内容……',
  );
  bool succeeded;
  try {
    succeeded = await syncService.syncBeforeOpeningBook();
  } finally {
    dismissLoading();
  }

  // 同步未完成时告知用户，随后仍照常打开工作台
  if (!succeeded && context.mounted) {
    SnackBarService.show(context, '云同步未完成，已先打开工作台，可稍后手动同步');
  }
}
