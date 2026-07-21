import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 批量多选交互控制器
///
/// 为列表型面板的批量模式提供统一的多选交互逻辑：
/// - Shift + 点击：范围选择。基于被点击项当前状态智能判定
///   选中或取消整个范围（未选中→选中范围，已选中→取消范围）。
/// - 鼠标按住拖拽：从按下项开始，沿途经过的所有项统一应用
///   目标状态（按下项未选中→沿途全部选中，已选中→沿途全部取消）。
///
/// 控制器只管理交互状态与选中集合的修改，不持有任何 UI 引用。
/// 选中集合、扁平化列表与状态刷新均由调用方通过回调提供。
class BatchSelectionController {
  BatchSelectionController({
    required this.getSelectedIds,
    required this.getFlatDisplayIds,
    required this.onChanged,
  });

  /// 获取当前选中集合（控制器直接修改此集合）
  final Set<String> Function() getSelectedIds;

  /// 获取当前显示顺序的扁平化项 UUID 列表（仅可视项）
  final List<String> Function() getFlatDisplayIds;

  /// 选中状态变化时触发（调用方在此调用 setState 刷新 UI）
  final VoidCallback onChanged;

  /// 范围选择的锚点项 UUID
  String? _anchorId;

  /// 是否正在拖拽多选
  bool _isDragging = false;

  /// 拖拽起始项 UUID
  String? _dragStartId;

  /// 拖拽起始指针位置（用于判定拖拽阈值）
  Offset? _dragStartPosition;

  /// 拖拽的目标状态（true=选中，false=取消选中）
  bool _dragTargetSelected = false;

  /// 拖拽过程中已应用状态的项（避免重复处理）
  final Set<String> _dragAppliedIds = {};

  /// 拖拽结束后是否需要抑制下一次点击
  bool _suppressNextTap = false;

  /// 判定拖拽开始的移动阈值（像素）
  static const double _dragThreshold = 4.0;

  /// 当前是否处于拖拽多选状态
  bool get isDragging => _isDragging;

  /// 重置所有交互状态（进入/退出批量模式时调用）
  void reset() {
    _anchorId = null;
    _isDragging = false;
    _dragStartId = null;
    _dragStartPosition = null;
    _dragAppliedIds.clear();
    _suppressNextTap = false;
  }

  // ================= 点击与范围选择 =================

  /// 项点击入口
  ///
  /// 由项的 onTap 回调调用。处理普通点击与 Shift+点击两种情形，
  /// 返回 true 表示已处理（调用方不再执行其他逻辑）。
  bool onItemTap(String id) {
    // 拖拽刚结束，抑制本次点击避免与拖拽末端的 onTap 重复触发
    if (_suppressNextTap) {
      _suppressNextTap = false;
      return true;
    }

    if (HardwareKeyboard.instance.isShiftPressed) {
      _selectRangeTo(id);
      return true;
    }

    // 普通点击：切换选中状态并更新锚点
    final selectedIds = getSelectedIds();
    if (selectedIds.contains(id)) {
      selectedIds.remove(id);
    } else {
      selectedIds.add(id);
    }
    _anchorId = id;
    onChanged();
    return true;
  }

  /// Shift + 点击的范围选择
  ///
  /// 以锚点为起点、目标项为终点（含两端）计算范围，
  /// 按被点击项当前状态统一应用：未选中则选中整个范围，已选中则取消整个范围。
  void _selectRangeTo(String id) {
    final flatIds = getFlatDisplayIds();
    final anchorIndex = _anchorId == null ? -1 : flatIds.indexOf(_anchorId!);
    final targetIndex = flatIds.indexOf(id);

    // 目标不在可视列表中，直接返回
    if (targetIndex == -1) return;

    final selectedIds = getSelectedIds();

    // 无锚点或锚点不在可视列表中，按普通切换处理
    if (anchorIndex == -1) {
      if (selectedIds.contains(id)) {
        selectedIds.remove(id);
      } else {
        selectedIds.add(id);
      }
      _anchorId = id;
      onChanged();
      return;
    }

    final startIndex = anchorIndex < targetIndex ? anchorIndex : targetIndex;
    final endIndex = anchorIndex < targetIndex ? targetIndex : anchorIndex;

    // 基于被点击项当前状态决定目标状态
    final shouldSelect = !selectedIds.contains(id);

    for (var i = startIndex; i <= endIndex; i++) {
      if (shouldSelect) {
        selectedIds.add(flatIds[i]);
      } else {
        selectedIds.remove(flatIds[i]);
      }
    }
    _anchorId = id;
    onChanged();
  }

  // ================= 鼠标拖拽多选 =================

  /// 项按下事件
  ///
  /// 在项的 Listener.onPointerDown 中调用。
  /// 记录拖拽起点与目标状态（按下项当前状态的取反）。
  void onItemPointerDown(String id, PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) return;

    // 新一次按下开始，重置点击抑制标志
    _suppressNextTap = false;

    _dragStartId = id;
    _dragStartPosition = event.position;
    _dragTargetSelected = !getSelectedIds().contains(id);
    _dragAppliedIds.clear();
    _isDragging = false;
  }

  /// 指针移动事件
  ///
  /// 在列表容器的 Listener.onPointerMove 中调用。
  /// 移动距离超过阈值后正式开始拖拽，并对起始项应用目标状态。
  void onPointerMove(PointerMoveEvent event) {
    if (_dragStartId == null || _isDragging) return;

    final distance = (event.position - _dragStartPosition!).distance;
    if (distance < _dragThreshold) return;

    _isDragging = true;
    _applyDragTo(_dragStartId!);
  }

  /// 指针进入项区域事件
  ///
  /// 在项的 MouseRegion.onEnter 中调用。
  /// 拖拽过程中指针进入新项时，对该项应用目标状态。
  void onItemPointerEnter(String id) {
    if (!_isDragging) return;
    _applyDragTo(id);
  }

  /// 对指定项应用拖拽目标状态
  void _applyDragTo(String id) {
    if (_dragAppliedIds.contains(id)) return;
    _dragAppliedIds.add(id);

    final selectedIds = getSelectedIds();
    if (_dragTargetSelected) {
      selectedIds.add(id);
    } else {
      selectedIds.remove(id);
    }
    onChanged();
  }

  /// 指针抬起事件
  ///
  /// 在列表容器的 Listener.onPointerUp / onPointerCancel 中调用。
  /// 若发生过拖拽，则抑制紧随其后的点击事件。
  void onPointerUp() {
    if (_isDragging) {
      _suppressNextTap = true;
    }
    _isDragging = false;
    _dragStartId = null;
    _dragStartPosition = null;
    _dragAppliedIds.clear();
  }
}
