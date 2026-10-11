import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quick_write/core/services/multi_window_service.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/shared/widgets/qw_dialogs.dart';
import 'package:quick_write/shared/widgets/qw_snackbar.dart';

/// 打开工作台（根据设置决定是否在新窗口中打开）
///
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
  // 单窗口模式：直接在当前窗口内导航到工作台
  if (!SettingsService.instance.openWorkspaceInNewWindow) {
    context.go('/workspace/$bookId');
    return;
  }

  // 该书的工作台窗口已打开时不会创建新窗口，也就不会收到"工作台就绪"通知，
  // 因此不显示等待弹窗，直接聚焦已有窗口
  if (MultiWindowService.instance.isWorkspaceWindowOpen(bookId)) {
    await MultiWindowService.instance.openWorkspaceWindow(bookId);
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
