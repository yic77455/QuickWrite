import 'package:flutter/material.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/shared/widgets/qw_dialogs.dart';

/// 标签页关闭守卫
///
/// 统一处理正文编辑器与大纲编辑器标签页在关闭前的未保存内容确认逻辑：
/// - 关闭单个标签页：检查 [EditorTab.isModified]，已修改时弹窗让用户选择保存/不保存/取消
/// - 关闭窗口：检查是否有未保存的标签页，统一弹窗让用户选择处理方式
class TabCloseGuard {
  /// 关闭单个标签页前的未保存确认
  ///
  /// [context] 弹窗上下文
  /// [provider] 工作区状态提供者
  /// [tabId] 待关闭的标签页 ID
  ///
  /// 返回 true 表示标签页已被关闭；false 表示用户取消了关闭操作
  /// （保存失败时也会返回 false，以便用户看到错误后自行处理）
  static Future<bool> confirmCloseTab({
    required BuildContext context,
    required WorkspaceProvider provider,
    required String tabId,
  }) async {
    // 查找待关闭的标签页（用户可能在确认前已切换标签页，需重新查找）
    final tab = provider.openedTabs.where((t) => t.id == tabId).firstOrNull;
    if (tab == null) return false;

    // 未修改的标签页直接关闭，无需弹窗
    if (!tab.isModified) {
      provider.closeTab(tabId);
      return true;
    }

    // 弹窗前检查上下文是否仍然可用
    if (!context.mounted) return false;

    // 已修改：弹窗让用户选择处理方式
    final result = await showUnsavedConfirmDialog(
      context: context,
      title: '关闭未保存的标签页',
      description: '《${tab.title}》的修改尚未保存，是否在关闭前保存？',
      saveText: '保存',
      discardText: '不保存',
      cancelText: '取消',
    );

    switch (result) {
      case UnsavedConfirmResult.save:
        // saveCurrentTab 仅作用于当前标签页，需先切换到目标标签页
        final index = provider.openedTabs.indexOf(tab);
        if (index >= 0) {
          provider.switchToTab(index);
        }
        // 执行保存，失败则不关闭以便用户处理错误
        final saved = await provider.saveCurrentTab();
        if (!saved) return false;
        provider.closeTab(tabId);
        return true;
      case UnsavedConfirmResult.discard:
        // 用户选择放弃修改，直接关闭
        provider.closeTab(tabId);
        return true;
      case UnsavedConfirmResult.cancel:
        return false;
    }
  }

  /// 关闭窗口或离开工作台前的未保存确认
  ///
  /// [context] 弹窗上下文
  /// [provider] 工作区状态提供者
  /// [title] 弹窗标题（默认"关闭窗口"，返回书架等场景可自定义）
  /// [descriptionTemplate] 描述模板，`{n}` 会被替换为未保存标签页数量
  /// [saveText] 保存按钮文字
  ///
  /// 返回 true 表示允许继续关闭/离开；false 表示用户取消了操作。
  /// 若用户选择"保存"，会保存所有未保存的标签页内容后再返回 true。
  static Future<bool> confirmCloseWindow({
    required BuildContext context,
    required WorkspaceProvider provider,
    String title = '关闭窗口',
    String descriptionTemplate = '有 {n} 个标签页的修改尚未保存，是否在关闭前保存？',
    String saveText = '保存',
  }) async {
    // 没有未保存的标签页，直接放行
    if (!provider.hasUnsavedTabs()) return true;

    // 弹窗前检查上下文是否仍然可用
    // widget 已销毁时（理论上不会发生在窗口关闭前），直接放行让原流程继续
    if (!context.mounted) return true;

    // 统计未保存数量并填充描述模板
    final unsavedCount = provider.unsavedTabsCount();
    final description = descriptionTemplate.replaceAll('{n}', unsavedCount.toString());
    final result = await showUnsavedConfirmDialog(
      context: context,
      title: title,
      description: description,
      saveText: saveText,
      discardText: '不保存',
      cancelText: '取消',
    );

    switch (result) {
      case UnsavedConfirmResult.save:
        // 保存所有未保存的标签页内容
        await provider.saveAllTabs();
        return true;
      case UnsavedConfirmResult.discard:
        // 用户选择放弃所有未保存修改
        return true;
      case UnsavedConfirmResult.cancel:
        return false;
    }
  }
}
