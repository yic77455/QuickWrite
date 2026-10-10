import 'package:flutter/widgets.dart';
import 'package:quick_write/core/utils/code_line_selection_utils.dart';
import 'package:re_editor/re_editor.dart';

/// 查找替换目标抽象接口
///
/// 为不同类型的编辑器（小说编辑器、大纲编辑器）提供统一的查找替换操作接口，
/// 使查找替换栏无需关心底层编辑器的具体实现，实现编辑器间的通用化。
abstract class FindReplaceTarget {
  /// 获取可搜索的完整文本
  ///
  /// 小说编辑器返回控制器的完整文本；
  /// 大纲编辑器返回所有节点文本以换行符拼接后的完整文本。
  String get text;

  /// 获取当前选区（使用全局偏移量）
  ///
  /// 全局偏移量是相对于 [text] 的字符位置。
  TextSelection get selection;

  /// 设置当前选区（使用全局偏移量）
  set selection(TextSelection value);

  /// 替换指定范围的文本
  ///
  /// [start] 和 [end] 为相对于 [text] 的全局偏移量（左闭右开）。
  void replaceRange(int start, int end, String replacement);

  /// 替换所有匹配项
  ///
  /// [matches] 为所有匹配的选区列表（全局偏移量）。
  /// 实现可按节点分组批量替换，并通过撤销管理器合并为单条撤销记录。
  void replaceAll(List<TextSelection> matches, String replacement);

  /// 滚动到当前选区位置
  void scrollToSelection();

  /// 请求编辑器获取焦点
  void requestFocus();

  /// 通知内容已变化
  ///
  /// 触发自动保存、字数统计等后续流程。
  void notifyContentChanged();
}

/// 基于 re_editor 行编辑控制器的查找替换目标
///
/// 用于只有一个文本控制器的编辑器（如小说编辑器），
/// 以扁平偏移量代理控制器的文本与选区操作，滚动与焦点通过回调委托给编辑器状态。
class CodeLineFindReplaceTarget implements FindReplaceTarget {
  /// 被代理的编辑控制器
  final CodeLineEditingController controller;

  /// 滚动到选区的回调（由编辑器状态提供）
  final VoidCallback onScrollToSelection;

  /// 请求焦点的回调（由编辑器状态提供）
  final VoidCallback onRequestFocus;

  CodeLineFindReplaceTarget({
    required this.controller,
    required this.onScrollToSelection,
    required this.onRequestFocus,
  });

  @override
  String get text => controller.text;

  @override
  TextSelection get selection =>
      CodeLineSelectionUtils.flatSelectionOf(controller.text, controller.selection);

  @override
  set selection(TextSelection value) {
    controller.selection =
        CodeLineSelectionUtils.selectionFromTextSelection(controller.text, value);
  }

  @override
  void replaceRange(int start, int end, String replacement) {
    final text = controller.text;
    if (start < 0 || end > text.length || start > end) return;
    controller.replaceSelection(
      replacement,
      CodeLineSelectionUtils.selectionFromFlat(text, start, end),
    );
  }

  @override
  void replaceAll(List<TextSelection> matches, String replacement) {
    if (matches.isEmpty) return;
    // 从后往前替换，避免偏移量变化影响后续匹配的位置
    final sortedMatches = List<TextSelection>.from(matches)
      ..sort((a, b) => b.start.compareTo(a.start));
    for (final match in sortedMatches) {
      final text = controller.text;
      if (match.start < 0 || match.end > text.length) continue;
      controller.replaceSelection(
        replacement,
        CodeLineSelectionUtils.selectionFromFlat(text, match.start, match.end),
      );
    }
  }

  @override
  void scrollToSelection() => onScrollToSelection();

  @override
  void requestFocus() => onRequestFocus();

  @override
  void notifyContentChanged() {
    // 小说编辑器的内容变化通知（字数统计、标记修改、自动保存）由 WorkspaceProvider 统一处理
  }
}