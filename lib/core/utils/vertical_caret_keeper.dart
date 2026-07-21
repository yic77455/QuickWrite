// ignore_for_file: unintended_html_in_doc_comment

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'persistent_selection.dart';

/// 保持横向位置的纵向光标移动 Action
///
/// 覆盖 Flutter 默认的 [DirectionalCaretMovementIntent] 处理逻辑（仅处理
/// [ExtendSelectionVerticallyToAdjacentLineIntent]，Page 移动回退到默认行为）。
///
/// 为什么要继承 'Action<DirectionalCaretMovementIntent>'：
/// Flutter 的 'EditableText' 中 '_verticalSelectionUpdateAction' 的类型为
/// '_UpdateTextSelectionVerticallyAction<DirectionalCaretMovementIntent>'，
/// 经 'Action.overridable' 包装后，覆盖查找使用的泛型参数 T 是
/// 'DirectionalCaretMovementIntent'，并以该 Type 作为 key 在祖先 'Actions'
/// 中查找。若注册 key 为 'ExtendSelectionVerticallyToAdjacentLineIntent'
/// 则永远无法被查找到。
///
/// 本 Action 的策略：
/// 自行维护 '_preferredX'，在连续纵向移动期间始终保持起始横向像素位置，
/// 借助 [VerticalCaretMovementRun] 定位目标行后，用 '_preferredX' 重新计算
/// 最接近的 TextPosition：
/// - 目标行字符长度足够：出现在对应横向位置
/// - 目标行字符长度不足：出现在行末
class KeepHorizontalXVerticalSelectionAction
    extends Action<DirectionalCaretMovementIntent> {
  KeepHorizontalXVerticalSelectionAction({
    required this.controller,
    required this.textFieldKey,
  });

  /// 文本控制器，用于读取和修改选区
  final TextEditingController controller;

  /// TextField 的 GlobalKey，用于查找底层 RenderEditable
  final GlobalKey textFieldKey;

  /// 记忆的横向像素位置（RenderEditable 本地坐标系）
  ///
  /// 在连续纵向移动期间保持不变，确保光标回到正确的横向位置
  double? _preferredX;

  /// 上一次纵向移动结束后的选区 extent（用于判断是否为连续纵向移动）
  int? _lastVerticalExtent;

  /// 标记：当前选区变化是否由本 Action 触发
  ///
  /// 用于区分"本 Action 触发的选区变化"和"外部操作触发的选区变化"，
  /// 后者需要重置纵向移动状态
  bool _isApplying = false;

  @override
  Object? invoke(DirectionalCaretMovementIntent intent) {
    // 仅处理逐行移动；逐页移动（Page Up/Down）回退到 Flutter 默认行为
    if (intent is! ExtendSelectionVerticallyToAdjacentLineIntent) {
      return callingAction?.invoke(intent);
    }

    final RenderEditable? renderEditable = findPersistentRenderEditable(textFieldKey);
    if (renderEditable == null) return null;

    final TextSelection selection = controller.selection;
    if (!selection.isValid) {
      _reset();
      return null;
    }

    final TextPosition extent = selection.extent;

    // 判断是否为连续纵向移动：
    // 当前选区的 extent 与上次纵向移动后的 extent 一致时，认为是连续移动
    final bool isContinuous =
        _lastVerticalExtent != null && selection.extentOffset == _lastVerticalExtent;

    // 非连续移动或尚未初始化时，从当前光标位置提取横向位置
    if (!isContinuous || _preferredX == null) {
      final Rect caretRect = renderEditable.getLocalRectForCaret(extent);
      _preferredX = caretRect.left;
    }

    // 借助 Flutter 的 VerticalCaretMovementRun 定位到目标行
    // 它内部会基于当前光标的 dx 移动，但最终位置会用 _preferredX 重新计算
    final VerticalCaretMovementRun run =
        renderEditable.startVerticalCaretMovement(extent);
    final bool moved = intent.forward ? run.moveNext() : run.movePrevious();

    final TextPosition newPosition;
    if (moved) {
      // 通过移动后的光标矩形获取目标行的 Y 坐标
      final Rect targetCaretRect = renderEditable.getLocalRectForCaret(run.current);
      final double targetY = targetCaretRect.center.dy;
      // 用记忆的横向位置在目标行上查找最接近的 TextPosition
      final Offset localOffset = Offset(_preferredX!, targetY);
      final Offset globalOffset = renderEditable.localToGlobal(localOffset);
      newPosition = renderEditable.getPositionForPoint(globalOffset);
    } else {
      // 已到文档边界，定位到文档首尾
      newPosition = intent.forward
          ? TextPosition(offset: controller.text.length)
          : const TextPosition(offset: 0);
    }

    final TextSelection newSelection = intent.collapseSelection
        ? TextSelection.fromPosition(newPosition)
        : selection.extendTo(newPosition);

    // 通过 TextSelectionDelegate 更新选区，保留 SelectionChangedCause.keyboard 副作用
    // （如自动滚动光标到可见区域），与 Flutter 默认的纵向移动行为保持一致
    final TextEditingValue newValue = controller.value.copyWith(selection: newSelection);
    _isApplying = true;
    renderEditable.textSelectionDelegate
        .userUpdateTextEditingValue(newValue, SelectionChangedCause.keyboard);
    _isApplying = false;

    _lastVerticalExtent = newSelection.extentOffset;

    return null;
  }

  /// 选区变化监听入口
  ///
  /// 应在 [TextEditingController] 的 listener 中调用。
  /// 当选区变化不是由本 Action 触发时（如鼠标点击、左右键、文本输入等），
  /// 重置纵向移动状态，使下次纵向移动重新初始化横向位置
  void onSelectionChanged() {
    if (_isApplying) return;
    _reset();
  }

  /// 重置纵向移动状态
  void _reset() {
    _preferredX = null;
    _lastVerticalExtent = null;
  }
}
