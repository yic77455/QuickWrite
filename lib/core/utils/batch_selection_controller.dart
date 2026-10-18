import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 批量多选交互控制器
///
/// 为列表型面板的批量模式提供统一的多选交互逻辑：
/// - Shift + 点击：范围选择。基于被点击项当前状态智能判定
///   选中或取消整个范围（未选中→选中范围，已选中→取消范围）。
/// - 按住拖拽：以按下项为锚点，与当前命中项构成区间，
///   区间内的项统一应用目标状态（按下项未选中→区间全部选中，已选中→区间全部取消）；
///   反向滑回时滑出区间的项恢复为拖拽前的状态，可反复撤销与重选。
/// - 触摸端在复选框区域纵向拖拽即可进入该交互，无需长按。
///
/// 控制器只管理交互状态与选中集合的修改，不持有任何 UI 引用。
/// 选中集合、扁平化列表与状态刷新均由调用方通过回调提供。
class BatchSelectionController {
  BatchSelectionController({
    required this.getSelectedIds,
    required this.getFlatDisplayIds,
    required this.onChanged,
    this.hitTestId,
  });

  /// 获取当前选中集合（控制器直接修改此集合）
  final Set<String> Function() getSelectedIds;

  /// 获取当前显示顺序的扁平化项 UUID 列表（仅可视项）
  final List<String> Function() getFlatDisplayIds;

  /// 选中状态变化时触发（调用方在此调用 setState 刷新 UI）
  final VoidCallback onChanged;

  /// 按全局坐标命中项 UUID 的查询回调（触摸端无悬停事件，拖拽时以此定位指针下方的项）
  final String? Function(Offset globalPosition)? hitTestId;

  /// 范围选择的锚点项 UUID
  String? _anchorId;

  /// 是否正在拖拽多选
  bool _isDragging = false;

  /// 是否处于"复选框区域拖拽"模式（触摸端手势，指针移动时按位置命中项）
  bool _isCheckboxDragging = false;

  /// 拖拽起始项 UUID
  String? _dragStartId;

  /// 拖拽起始指针位置（用于判定拖拽阈值）
  Offset? _dragStartPosition;

  /// 拖拽的目标状态（true=选中，false=取消选中）
  bool _dragTargetSelected = false;

  /// 拖拽过程中当前已应用状态的项
  final Set<String> _dragAppliedIds = {};

  /// 拖拽应用前各项的原始选中状态（滑出区间时用于还原）
  final Map<String, bool> _dragOriginalStates = {};

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
    _isCheckboxDragging = false;
    _dragStartId = null;
    _dragStartPosition = null;
    _dragAppliedIds.clear();
    _dragOriginalStates.clear();
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

  // ================= 拖拽多选 =================

  /// 项按下事件
  ///
  /// 在项的 Listener.onPointerDown 中调用。
  /// 记录拖拽起点与目标状态（按下项当前状态的取反）。
  ///
  /// 仅响应鼠标左键：触摸端的按下总是落在同一项上，若一并处理，
  /// 则列表滑动时会被误判为拖拽并选中手指落下位置的项。
  void onItemPointerDown(String id, PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse || event.buttons != kPrimaryButton) return;

    // 新一次按下开始，重置点击抑制标志
    _suppressNextTap = false;

    _dragStartId = id;
    _dragStartPosition = event.position;
    _dragTargetSelected = !getSelectedIds().contains(id);
    _dragAppliedIds.clear();
    _dragOriginalStates.clear();
    _isDragging = false;
  }

  /// 复选框拖拽的选择入口
  ///
  /// 在复选框区域的纵向拖拽开始时调用。以按下项当前状态的取反作为目标状态，
  /// 并在指针移动时以按下项为锚点、当前命中项为终点构成区间连续应用。
  void onCheckboxDragStart(String id) {
    _isCheckboxDragging = true;
    _isDragging = true;
    _dragStartId = id;
    _dragStartPosition = null;
    _dragTargetSelected = !getSelectedIds().contains(id);
    _dragAppliedIds.clear();
    _dragOriginalStates.clear();
    _updateDragRange(id);
  }

  /// 指针移动事件
  ///
  /// 在列表容器的 Listener.onPointerMove 中调用。
  void onPointerMove(PointerMoveEvent event) {
    // 复选框区域拖拽：按指针位置命中途经的项并更新选区
    if (_isCheckboxDragging) {
      final hitId = hitTestId?.call(event.position);
      if (hitId != null) _updateDragRange(hitId);
      return;
    }

    // 鼠标拖拽：移动距离超过阈值后正式开始拖拽，并更新起始项所在选区
    if (_dragStartId == null || _isDragging) return;

    final distance = (event.position - _dragStartPosition!).distance;
    if (distance < _dragThreshold) return;

    _isDragging = true;
    _updateDragRange(_dragStartId!);
  }

  /// 指针进入项区域事件
  ///
  /// 在项的 MouseRegion.onEnter 中调用。
  /// 拖拽过程中指针进入新项时，更新选区。
  void onItemPointerEnter(String id) {
    if (!_isDragging) return;
    _updateDragRange(id);
  }

  /// 更新拖拽选区
  ///
  /// 以拖拽起始项为锚点、当前命中项为终点构成区间（含两端）：
  /// - 区间内的项统一应用目标状态，并记录其原始状态以便还原；
  /// - 滑出区间的项还原为原始状态。
  /// 因此反向滑回时，之前被勾选/取消的项会依次撤销，可反复撤销与重选。
  void _updateDragRange(String currentId) {
    if (_dragStartId == null) return;

    final flatIds = getFlatDisplayIds();
    final startIndex = flatIds.indexOf(_dragStartId!);
    final currentIndex = flatIds.indexOf(currentId);
    if (startIndex == -1 || currentIndex == -1) return;

    final rangeStart = startIndex < currentIndex ? startIndex : currentIndex;
    final rangeEnd = startIndex < currentIndex ? currentIndex : startIndex;
    final inRange = flatIds.sublist(rangeStart, rangeEnd + 1);

    var changed = false;

    // 滑出区间的项还原为拖拽前的状态
    for (final id in _dragAppliedIds.toList()) {
      if (inRange.contains(id)) continue;
      _setSelected(id, _dragOriginalStates[id] ?? false);
      _dragAppliedIds.remove(id);
      _dragOriginalStates.remove(id);
      changed = true;
    }

    // 区间内的项应用目标状态，并记录原始状态
    for (final id in inRange) {
      if (_dragAppliedIds.contains(id)) continue;
      _dragOriginalStates[id] = getSelectedIds().contains(id);
      _dragAppliedIds.add(id);
      _setSelected(id, _dragTargetSelected);
      changed = true;
    }

    if (changed) onChanged();
  }

  /// 将指定项设置为选中或取消选中
  void _setSelected(String id, bool selected) {
    final selectedIds = getSelectedIds();
    if (selected) {
      selectedIds.add(id);
    } else {
      selectedIds.remove(id);
    }
  }

  /// 指针抬起事件
  ///
  /// 在列表容器的 Listener.onPointerUp / onPointerCancel 中调用。
  /// 鼠标拖拽可能以一次点击收尾，此时抑制紧随其后的点击事件。
  void onPointerUp() {
    // 复选框区域拖拽由纵向手势完成，不会产生尾随点击，无需抑制
    if (_isDragging && !_isCheckboxDragging) {
      _suppressNextTap = true;
    }
    _isDragging = false;
    _isCheckboxDragging = false;
    _dragStartId = null;
    _dragStartPosition = null;
    _dragAppliedIds.clear();
    _dragOriginalStates.clear();
  }
}
