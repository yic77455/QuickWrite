// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// 本文件基于 Flutter 源码 widgets/reorderable_list.dart 的交互实现裁剪改造：
// - 仅保留纵向列表的拖拽排序能力；
// - 行身份由外部传入的 rowKeys 决定，拖拽期间行集合变化时按身份重映射，不中断拖拽；
// - 增加拖拽结束回调，供宿主在落位动画结束后恢复界面状态。

library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 拖拽排序结果回调
///
/// [oldIndex] 为被拖拽行的原索引，[newIndex] 为目标插入位置，
/// 语义与 [SliverSortableList] 的 onReorder 一致：被拖拽行仍位于原位置时计算。
typedef SortableReorderCallback = void Function(int oldIndex, int newIndex);

/// 拖拽中的代理装饰器
///
/// [animation] 在拖起时从 0 到 1，落下时从 1 到 0，可用于给代理添加抬升、缩放等效果。
typedef SortableItemProxyDecorator = Widget Function(
  Widget child,
  int index,
  Animation<double> animation,
);

/// 支持拖拽排序的纵向 sliver 列表
///
/// 每个可拖拽行需由宿主用 [SortableDragStartListener] 或
/// [SortableDelayedDragStartListener] 包裹，并传入与该行索引一致的 index。
/// 所有行必须带有 key，且 [rowKeys] 需与各行 key 一一对应，
/// 以便拖拽过程中行集合变化时按身份定位被拖拽行。
class SliverSortableList extends StatefulWidget {
  const SliverSortableList({
    super.key,
    required this.rowKeys,
    required this.itemBuilder,
    required this.onReorder,
    this.onReorderStart,
    this.onReorderEnd,
    this.onReorderCompleted,
    this.itemExtentBuilder,
    this.proxyDecorator,
    double? autoScrollerVelocityScalar,
  }) : autoScrollerVelocityScalar = autoScrollerVelocityScalar ?? _kDefaultAutoScrollVelocityScalar;

  // 经验值，用于获得平滑的边缘自动滚动体验
  static const double _kDefaultAutoScrollVelocityScalar = 50;

  /// 各行稳定标识，顺序与列表中的行一致
  final List<Object> rowKeys;

  /// 行构建器
  final IndexedWidgetBuilder itemBuilder;

  /// 拖拽排序结果回调
  final SortableReorderCallback onReorder;

  /// 拖拽开始回调，参数为被拖拽行的索引
  final void Function(int index)? onReorderStart;

  /// 拖拽结束回调，参数为落点索引
  final void Function(int index)? onReorderEnd;

  /// 拖拽彻底结束回调
  ///
  /// 无论是否发生排序、也无论拖拽是取消还是落下，都会在落位动画结束后调用，
  /// 供宿主恢复拖拽期间的界面状态。
  final VoidCallback? onReorderCompleted;

  /// 行高构建器，用于按行提供固定高度
  final ItemExtentBuilder? itemExtentBuilder;

  /// 拖拽代理装饰器
  final SortableItemProxyDecorator? proxyDecorator;

  /// 边缘自动滚动的速度系数
  final double autoScrollerVelocityScalar;

  /// 行数量
  int get itemCount => rowKeys.length;

  @override
  SliverSortableListState createState() => SliverSortableListState();

  /// 获取最近的 [SliverSortableList] 状态
  static SliverSortableListState of(BuildContext context) {
    final state = context.findAncestorStateOfType<SliverSortableListState>();
    assert(
      state != null,
      'SliverSortableList.of() 的调用位置不在 SliverSortableList 之下',
    );
    return state!;
  }

  /// 获取最近的 [SliverSortableList] 状态，不存在时返回 null
  static SliverSortableListState? maybeOf(BuildContext context) {
    return context.findAncestorStateOfType<SliverSortableListState>();
  }
}

/// [SliverSortableList] 的状态
///
/// 负责拖拽手势的接管、落点计算、邻居行的让位动画、拖拽代理与边缘自动滚动。
class SliverSortableListState extends State<SliverSortableList> with TickerProviderStateMixin {
  /// 索引到行状态的映射，用于计算拖拽落点与让位偏移
  final Map<int, _SortableItemState> _items = <int, _SortableItemState>{};

  OverlayEntry? _overlayEntry;
  int? _dragIndex;
  Object? _dragKey;
  _DragInfo? _dragInfo;
  int? _insertIndex;
  Offset? _finalDropPosition;
  MultiDragGestureRecognizer? _recognizer;
  int? _recognizerPointer;

  EdgeDraggingAutoScroller? _autoScroller;
  late ScrollableState _scrollable;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollable = Scrollable.of(context);
    if (_autoScroller?.scrollable != _scrollable) {
      _autoScroller?.stopAutoScroll();
      _autoScroller = EdgeDraggingAutoScroller(
        _scrollable,
        onScrollViewScrolled: _handleScrollableAutoScrolled,
        velocityScalar: widget.autoScrollerVelocityScalar,
      );
    }
  }

  @override
  void didUpdateWidget(covariant SliverSortableList oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 行集合变化时按行身份重映射被拖拽行，避免拖拽被中断
    if (!listEquals(widget.rowKeys, oldWidget.rowKeys)) {
      _handleRowsChanged();
    }

    if (widget.autoScrollerVelocityScalar != oldWidget.autoScrollerVelocityScalar) {
      _autoScroller?.stopAutoScroll();
      _autoScroller = EdgeDraggingAutoScroller(
        _scrollable,
        onScrollViewScrolled: _handleScrollableAutoScrolled,
        velocityScalar: widget.autoScrollerVelocityScalar,
      );
    }
  }

  @override
  void dispose() {
    _dragReset();
    _recognizer?.dispose();
    super.dispose();
  }

  /// 开始拖拽指定行
  ///
  /// 通常由 [SortableDragStartListener] 或 [SortableDelayedDragStartListener] 调用
  void startItemDragReorder({
    required int index,
    required PointerDownEvent event,
    required MultiDragGestureRecognizer recognizer,
  }) {
    assert(0 <= index && index < widget.itemCount);
    setState(() {
      if (_dragInfo != null) {
        _dragReset();
      } else if (_recognizer != null && _recognizerPointer != event.pointer) {
        _recognizer!.dispose();
        _recognizer = null;
        _recognizerPointer = null;
      }

      if (_items.containsKey(index)) {
        _dragIndex = index;
        _dragKey = widget.rowKeys[index];
        _recognizer = recognizer
          ..onStart = _dragStart
          ..addPointer(event);
        _recognizerPointer = event.pointer;
      }
    });
  }

  /// 取消进行中的拖拽
  void cancelReorder() {
    setState(() {
      _dragReset();
    });
    widget.onReorderCompleted?.call();
  }

  void _registerItem(_SortableItemState item) {
    if (_dragInfo != null && _items[item.index] != item) {
      item.updateForGap(_dragInfo!.index, _dragInfo!.index, _dragInfo!.itemExtent, false);
    }
    _items[item.index] = item;
    if (item.index == _dragInfo?.index) {
      item.dragging = true;
      item.rebuild();
    }
  }

  void _unregisterItem(int index, _SortableItemState item) {
    final currentItem = _items[index];
    if (currentItem == item) {
      _items.remove(index);
    }
  }

  Drag? _dragStart(Offset position) {
    assert(_dragInfo == null);
    final item = _items[_dragIndex!]!;
    item.dragging = true;
    widget.onReorderStart?.call(_dragIndex!);
    item.rebuild();

    _insertIndex = item.index;
    _dragInfo = _DragInfo(
      item: item,
      initialPosition: position,
      onUpdate: _dragUpdate,
      onCancel: _dragCancel,
      onEnd: _dragEnd,
      onDropCompleted: _dropCompleted,
      proxyDecorator: widget.proxyDecorator,
      tickerProvider: this,
    );
    _dragInfo!.startDrag();

    final overlay = Overlay.of(context);
    assert(_overlayEntry == null);
    _overlayEntry = OverlayEntry(builder: _dragInfo!.createProxy);
    overlay.insert(_overlayEntry!);

    for (final childItem in _items.values) {
      if (childItem == item || !childItem.mounted) {
        continue;
      }
      childItem.updateForGap(_insertIndex!, _insertIndex!, _dragInfo!.itemExtent, false);
    }
    return _dragInfo;
  }

  void _dragUpdate(_DragInfo item, Offset position, Offset delta) {
    setState(() {
      _overlayEntry?.markNeedsBuild();
      _dragUpdateItems();
      _autoScroller?.startAutoScrollIfNecessary(_dragTargetRect);
    });
  }

  void _dragCancel(_DragInfo item) {
    setState(() {
      _dragReset();
    });
    widget.onReorderCompleted?.call();
  }

  void _dragEnd(_DragInfo item) {
    setState(() {
      if (_insertIndex! - item.index == 1) {
        // 从下方回到原位置时，落点索引包含被拖拽行自身，取真实目标位置用于落位动画
        _finalDropPosition = _itemOffsetAt(_insertIndex! - 1);
      } else if (_insertIndex == item.index) {
        _finalDropPosition = _itemOffsetAt(_insertIndex!);
      } else if (_insertIndex! == 0) {
        // 落点为第一行起始位置，向前偏移被拖拽行的高度
        _finalDropPosition = _itemOffsetAt(0) - Offset(0, item.itemExtent);
      } else {
        // 落点落在前一行之后，按前一行的高度偏移
        final atIndex = _insertIndex! - 1;
        _finalDropPosition = _itemOffsetAt(atIndex) + Offset(0, _itemExtentAt(atIndex));
      }
    });
    widget.onReorderEnd?.call(_insertIndex!);
  }

  void _dropCompleted() {
    final fromIndex = _dragIndex!;
    final toIndex = _insertIndex!;
    if (fromIndex != toIndex) {
      widget.onReorder.call(fromIndex, toIndex);
    }
    setState(() {
      _dragReset();
    });
    widget.onReorderCompleted?.call();
  }

  void _dragReset() {
    if (_dragInfo != null) {
      if (_dragIndex != null && _items.containsKey(_dragIndex)) {
        final dragItem = _items[_dragIndex!]!;
        dragItem._dragging = false;
        dragItem.rebuild();
        _dragIndex = null;
      }
      _dragInfo?.dispose();
      _dragInfo = null;
      _dragKey = null;
      _autoScroller?.stopAutoScroll();
      _resetItemGap();
      _recognizer?.dispose();
      _recognizer = null;
      _overlayEntry?.remove();
      _overlayEntry?.dispose();
      _overlayEntry = null;
      _finalDropPosition = null;
    }
  }

  void _resetItemGap() {
    for (final item in _items.values) {
      item.resetGap();
    }
  }

  /// 处理行集合变化
  ///
  /// 拖拽期间行被增删时，按行标识重定位被拖拽行；
  /// 若被拖拽行已不存在，则直接结束拖拽。
  void _handleRowsChanged() {
    final dragInfo = _dragInfo;
    if (dragInfo == null) return;

    final dragKey = _dragKey;
    final newIndex = dragKey == null ? -1 : widget.rowKeys.indexOf(dragKey);
    if (newIndex < 0) {
      // 被拖拽行已从列表移除，无法继续拖拽，直接清理拖拽状态
      _abortReorder();
      return;
    }

    if (newIndex == _dragIndex) return;

    _dragIndex = newIndex;
    dragInfo.index = newIndex;
    _insertIndex = newIndex;

    // 行集合变化后各行的布局位置已改变，需在布局完成后重新计算让位偏移
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _dragInfo == null) return;
      setState(() => _dragUpdateItems());
    });
  }

  /// 直接终止拖拽（不经过手势回调），用于行集合变化导致拖拽失效的场景
  void _abortReorder() {
    if (_dragIndex != null && _items.containsKey(_dragIndex)) {
      _items[_dragIndex!]!._dragging = false;
    }
    _dragIndex = null;
    _dragKey = null;
    _insertIndex = null;
    _finalDropPosition = null;
    _dragInfo?.dispose();
    _dragInfo = null;
    _autoScroller?.stopAutoScroll();
    _recognizer?.dispose();
    _recognizer = null;
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;

    // 帧后重置让位偏移并通知宿主恢复界面状态，避免在构建过程中触发重建
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(_resetItemGap);
      widget.onReorderCompleted?.call();
    });
  }

  void _handleScrollableAutoScrolled() {
    if (_dragInfo == null) return;
    _dragUpdateItems();
    _autoScroller?.startAutoScrollIfNecessary(_dragTargetRect);
  }

  void _dragUpdateItems() {
    assert(_dragInfo != null);
    final gapExtent = _dragInfo!.itemExtent;
    final proxyItemStart = _dragInfo!.dragPosition.dy - _dragInfo!.dragOffset.dy;
    final proxyItemEnd = proxyItemStart + gapExtent;

    // 找到被拖拽行的新插入位置
    int newIndex = _insertIndex!;
    // 按索引升序遍历：行在拖拽中被重建时会重新注册，映射的插入顺序不再可靠
    final indices = _items.keys.toList()..sort();
    for (final index in indices) {
      final item = _items[index]!;
      if (!item.mounted) continue;

      final geometry = item.targetGeometry();
      final itemStart = geometry.top;
      final itemExtent = geometry.height;
      final itemEnd = itemStart + itemExtent;
      final itemMiddle = itemStart + itemExtent / 2;

      if (item.index == _dragIndex!) {
        // 代理末端未越过原行中线时维持原位置
        if (itemMiddle <= proxyItemEnd && proxyItemEnd <= itemEnd) {
          newIndex = _dragIndex!;
        }
      } else if (itemStart <= proxyItemStart && proxyItemStart <= itemMiddle) {
        // 代理起点落在目标行上半区，插入到该行之前
        newIndex = item.index;
        break;
      } else if (itemMiddle <= proxyItemEnd && proxyItemEnd <= itemEnd) {
        // 代理末端落在目标行下半区，插入到该行之后
        newIndex = item.index + 1;
        break;
      } else if (itemEnd < proxyItemStart && newIndex < item.index + 1) {
        newIndex = item.index + 1;
      } else if (proxyItemEnd < itemStart && newIndex > item.index) {
        newIndex = item.index;
      }
    }

    if (newIndex != _insertIndex) {
      _insertIndex = newIndex;
      for (final item in _items.values) {
        if (item.index == _dragIndex! || !item.mounted) continue;
        item.updateForGap(_dragIndex!, newIndex, gapExtent, true);
      }
    }
  }

  Rect get _dragTargetRect {
    final origin = _dragInfo!.dragPosition - _dragInfo!.dragOffset;
    return Rect.fromLTWH(origin.dx, origin.dy, _dragInfo!.itemSize.width, _dragInfo!.itemSize.height);
  }

  Offset _itemOffsetAt(int index) {
    return _items[index]!.targetGeometry().topLeft;
  }

  double _itemExtentAt(int index) {
    return _items[index]!.targetGeometry().height;
  }

  Widget _itemBuilder(BuildContext context, int index) {
    final child = widget.itemBuilder(context, index);
    assert(child.key != null, '所有可排序行都必须带有 key');
    final overlay = Overlay.of(context);
    return _SortableItem(
      key: _SortableItemGlobalKey(child.key!, index, this),
      index: index,
      capturedThemes: InheritedTheme.capture(from: context, to: overlay.context),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasOverlay(context));
    final childrenDelegate = SliverChildBuilderDelegate(
      _itemBuilder,
      childCount: widget.itemCount,
    );
    if (widget.itemExtentBuilder != null) {
      return SliverVariedExtentList(
        delegate: childrenDelegate,
        itemExtentBuilder: widget.itemExtentBuilder!,
      );
    }
    return SliverList(delegate: childrenDelegate);
  }
}

/// 单个可排序行
///
/// 负责让位动画偏移与拖拽期间的占位显示。
class _SortableItem extends StatefulWidget {
  const _SortableItem({
    required Key super.key,
    required this.index,
    required this.child,
    required this.capturedThemes,
  });

  final int index;
  final Widget child;
  final CapturedThemes capturedThemes;

  @override
  _SortableItemState createState() => _SortableItemState();
}

class _SortableItemState extends State<_SortableItem> {
  late SliverSortableListState _listState;

  Offset _startOffset = Offset.zero;
  Offset _targetOffset = Offset.zero;
  AnimationController? _offsetAnimation;

  bool get dragging => _dragging;
  set dragging(bool dragging) {
    if (mounted) {
      setState(() {
        _dragging = dragging;
      });
    }
  }

  bool _dragging = false;

  int get index => widget.index;

  @override
  void initState() {
    _listState = SliverSortableList.of(context);
    _listState._registerItem(this);
    super.initState();
  }

  @override
  void dispose() {
    _offsetAnimation?.dispose();
    _listState._unregisterItem(index, this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SortableItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _listState._unregisterItem(oldWidget.index, this);
      _listState._registerItem(this);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dragging) {
      return SizedBox(height: _listState._dragInfo!.itemExtent);
    }
    _listState._registerItem(this);
    return Transform.translate(offset: offset, child: widget.child);
  }

  @override
  void deactivate() {
    _listState._unregisterItem(index, this);
    super.deactivate();
  }

  Offset get offset {
    if (_offsetAnimation != null) {
      final double animValue = Curves.easeInOut.transform(_offsetAnimation!.value);
      return Offset.lerp(_startOffset, _targetOffset, animValue)!;
    }
    return _targetOffset;
  }

  /// 按拖拽落点更新让位偏移
  ///
  /// 位于被拖拽行与落点之间的行需要朝反方向让出一个行高。
  void updateForGap(int dragIndex, int gapIndex, double gapExtent, bool animate) {
    final Offset newTargetOffset;
    if (gapIndex < dragIndex && index < dragIndex && index >= gapIndex) {
      newTargetOffset = Offset(0, gapExtent);
    } else if (gapIndex > dragIndex && index > dragIndex && index < gapIndex) {
      newTargetOffset = Offset(0, -gapExtent);
    } else {
      newTargetOffset = Offset.zero;
    }

    if (newTargetOffset != _targetOffset) {
      final previousTarget = _targetOffset;
      _targetOffset = newTargetOffset;
      if (animate) {
        if (_offsetAnimation == null) {
          _offsetAnimation = AnimationController(
            vsync: _listState,
            duration: const Duration(milliseconds: 250),
          )
            ..addListener(rebuild)
            ..addStatusListener((status) {
              if (status.isCompleted) {
                _startOffset = _targetOffset;
                _offsetAnimation!.dispose();
                _offsetAnimation = null;
              }
            })
            ..forward();
        } else {
          // 动画被打断时从当前位置继续
          final double currentAnimValue = Curves.easeInOut.transform(_offsetAnimation!.value);
          final Offset currentPosition = Offset.lerp(_startOffset, previousTarget, currentAnimValue)!;
          _startOffset = currentPosition;
          _offsetAnimation!.forward(from: 0.0);
        }
      } else {
        if (_offsetAnimation != null) {
          _offsetAnimation!.dispose();
          _offsetAnimation = null;
        }
        _startOffset = _targetOffset;
      }
      rebuild();
    }
  }

  void resetGap() {
    if (_offsetAnimation != null) {
      _offsetAnimation!.dispose();
      _offsetAnimation = null;
    }
    _startOffset = Offset.zero;
    _targetOffset = Offset.zero;
    rebuild();
  }

  Rect targetGeometry() {
    final itemRenderBox = context.findRenderObject()! as RenderBox;
    final itemPosition = itemRenderBox.localToGlobal(Offset.zero) + _targetOffset;
    return itemPosition & itemRenderBox.size;
  }

  void rebuild() {
    if (mounted) {
      setState(() {});
    }
  }
}

/// 按下即开始拖拽的监听器
class SortableDragStartListener extends StatelessWidget {
  const SortableDragStartListener({
    super.key,
    required this.child,
    required this.index,
    this.enabled = true,
  });

  final Widget child;

  /// 被拖拽行在列表中的索引
  final int index;

  /// 是否允许拖拽
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: enabled ? (event) => _startDragging(context, event) : null,
      child: child,
    );
  }

  /// 创建用于识别拖拽开始的手势识别器
  @protected
  MultiDragGestureRecognizer createRecognizer() {
    return ImmediateMultiDragGestureRecognizer(debugOwner: this);
  }

  void _startDragging(BuildContext context, PointerDownEvent event) {
    final gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
    final list = SliverSortableList.maybeOf(context);
    list?.startItemDragReorder(
      index: index,
      event: event,
      recognizer: createRecognizer()..gestureSettings = gestureSettings,
    );
  }
}

/// 长按后才开始拖拽的监听器
class SortableDelayedDragStartListener extends SortableDragStartListener {
  const SortableDelayedDragStartListener({
    super.key,
    required super.child,
    required super.index,
    super.enabled,
  });

  @override
  MultiDragGestureRecognizer createRecognizer() {
    return DelayedMultiDragGestureRecognizer(debugOwner: this);
  }
}

typedef _DragItemUpdate = void Function(_DragInfo item, Offset position, Offset delta);
typedef _DragItemCallback = void Function(_DragInfo item);

/// 单次拖拽的运行时信息
class _DragInfo extends Drag {
  _DragInfo({
    required _SortableItemState item,
    Offset initialPosition = Offset.zero,
    this.onUpdate,
    this.onEnd,
    this.onCancel,
    this.onDropCompleted,
    this.proxyDecorator,
    required this.tickerProvider,
  }) : boundary = DragBoundary.forRectMaybeOf(item._listState.context) {
    final itemRenderBox = item.context.findRenderObject()! as RenderBox;
    listState = item._listState;
    index = item.index;
    child = item.widget.child;
    capturedThemes = item.widget.capturedThemes;
    dragOffset = itemRenderBox.globalToLocal(initialPosition);
    itemSize = item.context.size!;
    _rawDragPosition = initialPosition;
    dragPosition = _adjustedDragOffset(initialPosition);
    itemExtent = itemSize.height;
    itemLayoutConstraints = itemRenderBox.constraints;
    scrollable = Scrollable.of(item.context);
  }

  final _DragItemUpdate? onUpdate;
  final _DragItemCallback? onEnd;
  final _DragItemCallback? onCancel;
  final VoidCallback? onDropCompleted;
  final SortableItemProxyDecorator? proxyDecorator;
  final TickerProvider tickerProvider;
  final DragBoundaryDelegate<Rect>? boundary;

  late SliverSortableListState listState;
  late int index;
  late Widget child;
  late Offset dragPosition;
  late Offset dragOffset;
  late Size itemSize;
  late BoxConstraints itemLayoutConstraints;
  late double itemExtent;
  late CapturedThemes capturedThemes;
  ScrollableState? scrollable;
  AnimationController? _proxyAnimation;
  late Offset _rawDragPosition;

  void dispose() {
    _proxyAnimation?.dispose();
  }

  void startDrag() {
    _proxyAnimation = AnimationController(
      vsync: tickerProvider,
      duration: const Duration(milliseconds: 250),
    )
      ..addStatusListener((status) {
        if (status.isDismissed) {
          _dropCompleted();
        }
      })
      ..forward();
  }

  @override
  void update(DragUpdateDetails details) {
    _rawDragPosition += Offset(0, details.delta.dy);
    dragPosition = _adjustedDragOffset(_rawDragPosition);
    onUpdate?.call(this, dragPosition, details.delta);
  }

  @override
  void end(DragEndDetails details) {
    _proxyAnimation!.reverse();
    onEnd?.call(this);
  }

  @override
  void cancel() {
    _proxyAnimation?.dispose();
    _proxyAnimation = null;
    onCancel?.call(this);
  }

  Offset _adjustedDragOffset(Offset offset) {
    if (boundary == null) {
      return offset;
    }
    final adjOffset = boundary!
        .nearestPositionWithinBoundary((offset - dragOffset) & itemSize)
        .shift(dragOffset)
        .topLeft;
    return adjOffset;
  }

  void _dropCompleted() {
    _proxyAnimation?.dispose();
    _proxyAnimation = null;
    onDropCompleted?.call();
  }

  Widget createProxy(BuildContext context) {
    return capturedThemes.wrap(
      _DragItemProxy(
        listState: listState,
        index: index,
        size: itemSize,
        constraints: itemLayoutConstraints,
        animation: _proxyAnimation!,
        position: dragPosition - dragOffset - _overlayOrigin(context),
        proxyDecorator: proxyDecorator,
        child: child,
      ),
    );
  }
}

Offset _overlayOrigin(BuildContext context) {
  final overlay = Overlay.of(context);
  final overlayBox = overlay.context.findRenderObject()! as RenderBox;
  return overlayBox.localToGlobal(Offset.zero);
}

/// 跟随指针的拖拽代理
class _DragItemProxy extends StatelessWidget {
  const _DragItemProxy({
    required this.listState,
    required this.index,
    required this.child,
    required this.position,
    required this.size,
    required this.constraints,
    required this.animation,
    required this.proxyDecorator,
  });

  final SliverSortableListState listState;
  final int index;
  final Widget child;
  final Offset position;
  final Size size;
  final BoxConstraints constraints;
  final AnimationController animation;
  final SortableItemProxyDecorator? proxyDecorator;

  @override
  Widget build(BuildContext context) {
    final proxyChild = proxyDecorator?.call(child, index, animation.view) ?? child;
    final overlayOrigin = _overlayOrigin(context);

    return MediaQuery(
      // 去掉内边距，避免内嵌列表在代理中带入脚手架的边距
      data: MediaQuery.of(context).removePadding(removeTop: true),
      child: AnimatedBuilder(
        animation: animation,
        builder: (BuildContext context, Widget? child) {
          var effectivePosition = position;
          final dropPosition = listState._finalDropPosition;
          if (dropPosition != null) {
            effectivePosition = Offset.lerp(
              dropPosition - overlayOrigin,
              effectivePosition,
              Curves.easeOut.transform(animation.value),
            )!;
          }
          return Positioned(
            left: effectivePosition.dx,
            top: effectivePosition.dy,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: OverflowBox(
                minWidth: constraints.minWidth,
                minHeight: constraints.minHeight,
                maxWidth: constraints.maxWidth,
                maxHeight: constraints.maxHeight,
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
          );
        },
        child: proxyChild,
      ),
    );
  }
}

/// 以对象与索引组合生成的行全局键
///
/// 与 GlobalObjectKey 的差异在于使用 == 而非 identical 比较行标识。
@optionalTypeArgs
class _SortableItemGlobalKey extends GlobalObjectKey {
  const _SortableItemGlobalKey(this.subKey, this.index, this.state) : super(subKey);

  final Key subKey;
  final int index;
  final SliverSortableListState state;

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is _SortableItemGlobalKey &&
        other.subKey == subKey &&
        other.index == index &&
        other.state == state;
  }

  @override
  int get hashCode => Object.hash(subKey, index, state);
}
