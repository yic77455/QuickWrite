import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quick_write/core/services/multi_window_service.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/shared/widgets/qw_dialogs.dart';

/// 打开工作台（根据设置决定是否在新窗口中打开）
///
/// 多窗口模式下会先弹出加载弹窗冻结主窗口，
/// 等子窗口初始化完成后自动关闭弹窗
///
/// [context] 构建上下文（需要包含 Navigator）
/// [bookId] 要打开的书籍ID
/// [bookTitle] 书籍名称，用于加载提示文字显示
void openWorkspace({
  required BuildContext context,
  required String bookId,
  String? bookTitle,
}) {
  final openInNewWindow = SettingsService.instance.openWorkspaceInNewWindow;

  if (openInNewWindow) {
    // 多窗口模式：先显示加载弹窗冻结主窗口，再导航触发窗口创建
    final message = bookTitle != null ? '正在打开《$bookTitle》……' : '正在打开工作台……';
    final dismissLoading = showLoadingDialog(
      context: context,
      message: message,
    );
    // 注册回调：子窗口就绪后关闭加载弹窗
    MultiWindowService.instance.onWorkspaceReady = dismissLoading;
  }
  // 导航到工作台（多窗口模式下会被 redirect 拦截并创建新窗口）
  context.go('/workspace/$bookId');
}
