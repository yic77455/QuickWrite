import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ============================================================================
// 右键菜单实现说明
// ============================================================================
//
// 整体架构：
// 1. ContextMenuItem - 数据类，定义单个菜单项的配置（文本、图标、回调）
// 2. _ContextMenuController - 全局控制器，确保同一时间只有一个菜单显示
// 3. ContextMenu - 主组件，监听右键事件并触发菜单显示
// 4. _MenuOverlay - Overlay 层，包含遮罩和菜单主体
// 5. _MenuBody - 菜单主体，渲染菜单项列表
// 6. _MenuItem - 单个菜单项，处理悬停和点击
// 7. _SubMenuOverlay - 子菜单 Overlay 层
// 8. _SubMenuBody - 子菜单主体
// 9. _SubMenuItem - 子菜单项
//
// 功能特性：
// - 键盘导航：上下左右箭头、回车/空格激活、ESC 关闭
// - 子菜单支持：鼠标悬停自动展开，键盘右箭头展开
// - 鼠标/键盘协调：键盘操作后鼠标移动自动接管控制
// - 智能定位：自动检测屏幕边界，避免菜单超出屏幕
// - 修复边缘唤起时的闪烁渲染：位置计算完成前隐藏菜单，使用 ValueNotifier 更新选中状态
//
// 工作流程：
// 1. 用户右键点击 → ContextMenu 的 Listener 捕获事件（buttons == 2）
// 2. 调用 _showMenu() 创建 OverlayEntry 并插入到 Overlay 层
// 3. _MenuOverlay 渲染透明遮罩 + 菜单主体
// 4. 菜单渲染后，通过 addPostFrameCallback 获取实际尺寸
// 5. 根据尺寸调整位置，确保不超出屏幕边界
// 6. 用户点击菜单项或遮罩 → 关闭菜单
//
// 关键技术点：
// - Overlay：Flutter 的顶层绘制机制，可以在所有组件之上显示内容
// - Listener：底层指针事件监听器，只处理右键（buttons == 2），左键正常传递
// - KeyboardListener：监听键盘事件，实现键盘导航
// - ValueNotifier：用于更新子菜单选中状态，避免重建 Overlay 导致闪烁
// - addPostFrameCallback：在当前帧渲染完成后执行，用于获取组件尺寸
// - 静态变量：用于全局状态管理，防止多个菜单同时显示
// ============================================================================

/// 菜单类型
///
/// 用于区分右键菜单和下拉菜单两种场景，
/// 菜单类型决定了定位策略、点击行为等所有差异
enum ContextMenuType {
  /// 右键菜单
  ///
  /// - position 为鼠标点击位置，菜单左上角对齐该位置
  /// - 底部空间不足时，菜单底部对齐点击位置
  /// - 点击外部区域时，关闭菜单的同时响应点击事件
  contextMenu,

  /// 下拉菜单
  ///
  /// - position 为锚点组件左上角，菜单显示在锚点下方
  /// - 底部空间不足时，菜单翻转到锚点上方显示
  /// - 点击外部区域时，仅关闭菜单，不响应点击事件
  /// - 需要提供 anchorSize 以计算锚点区域
  dropdown,
}

/// 右键菜单项配置
///
/// 用于定义单个菜单项的显示内容和行为
/// 可以是可点击的菜单项、分隔线，或带子菜单的级联菜单项
class ContextMenuItem {
  /// 菜单项内容（Widget）
  /// 与 [labelText] 二选一，优先使用 [label]
  final Widget? label;

  /// 菜单项文本（便捷属性）
  /// 会自动包装为 Text 组件，与 [label] 二选一
  final String? labelText;

  /// 菜单项图标（可选）
  final IconData? icon;

  /// 菜单项图标构建器（可选）
  ///
  /// 与 [icon] 二选一，优先使用 [iconBuilder]。
  /// 回调参数 [color] 为当前图标颜色（已含悬停/禁用状态），
  /// 用于需要自定义图标渲染的场景（如带颜色指示条的图标）。
  final Widget Function(Color color)? iconBuilder;

  /// 菜单项颜色（可选）
  /// 同时应用于图标和文字，用于特殊标识（如删除项用红色）
  final Color? labelColor;

  /// 菜单项文字是否加粗（可选，默认 false）
  final bool labelBold;

  /// 点击回调（可选，分隔线和子菜单没有回调）
  final VoidCallback? onTap;

  /// 是否为分隔线
  /// 分隔线不显示文本和图标，只渲染一条水平线
  final bool isDivider;

  /// 子菜单项列表（可选）
  /// 如果提供，则此菜单项会显示展开箭头，悬停时展开子菜单
  final List<ContextMenuItem>? children;

  /// 是否启用（可选，默认为 true）
  /// 禁用时菜单项变灰且不可点击
  final bool enabled;

  /// 创建普通菜单项
  ///
  /// [label] 自定义内容 Widget（可选）
  /// [labelText] 简单文本（可选，与 label 二选一）
  /// [icon] 菜单项左侧的图标（可选）
  /// [iconBuilder] 图标构建器，接收当前图标颜色（可选，与 icon 二选一，优先使用）
  /// [labelColor] 菜单项颜色，同时应用于图标和文字（可选）
  /// [labelBold] 菜单项文字是否加粗（可选，默认 false）
  /// [onTap] 点击时的回调函数（可选）
  /// [enabled] 是否启用，禁用时变灰且不可点击（可选，默认 true）
  const ContextMenuItem({
    this.label,
    this.labelText,
    this.icon,
    this.iconBuilder,
    this.labelColor,
    this.labelBold = false,
    this.onTap,
    this.children,
    this.enabled = true,
  }) : isDivider = false;

  /// 创建分隔线
  ///
  /// 分隔线用于在视觉上分隔不同功能组的菜单项
  /// 例如：复制/粘贴/剪切 与 删除 之间可以加分隔线
  const ContextMenuItem.divider()
      : isDivider = true,
        label = null,
        labelText = null,
        icon = null,
        iconBuilder = null,
        labelColor = null,
        labelBold = false,
        onTap = null,
        children = null,
        enabled = false;

  /// 是否有子菜单
  bool get hasChildren => children != null && children!.isNotEmpty;

  /// 获取实际显示的内容
  ///
  /// [isHovered] 是否处于悬停状态，用于改变文字颜色
  /// [theme] 当前主题，用于获取颜色
  /// [fontSize] 字体大小（可选，覆盖主题默认值）
  Widget displayLabel({bool isHovered = false, required ThemeData theme, double? fontSize}) {
    if (label != null) return label!;
    if (labelText != null) {
      // 禁用时使用灰色
      Color color;
      if (!enabled) {
        color = theme.colorScheme.onSurface.withValues(alpha: 0.38);
      } else {
        // 颜色优先级：labelColor > 悬停时 primary > 默认 onSurface
        color = labelColor ??
            (isHovered ? theme.colorScheme.primary : theme.colorScheme.onSurface);
      }
      return Text(
        labelText!,
        style: (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
          color: color,
          fontSize: fontSize,
          fontWeight: labelBold ? FontWeight.bold : null,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// 全局菜单状态管理器
///
/// 使用静态变量管理全局菜单状态，确保同一时间只有一个右键菜单显示
///
/// 为什么需要全局管理？
/// - 当页面有多个 ContextMenu 组件嵌套时（如书籍网格 + 单个书籍卡片）
/// - 右键事件会冒泡，可能导致多个菜单同时触发
/// - 通过全局状态，只有第一个响应的组件能显示菜单
///
/// 实现原理：
/// - _isShowing：标记当前是否有菜单显示中
/// - _currentEntry：保存当前显示的 OverlayEntry 引用，用于关闭
class _ContextMenuController {
  /// 当前显示的菜单 Overlay 条目
  /// 保存引用是为了在需要时能够关闭它
  static OverlayEntry? _currentEntry;

  /// 是否有菜单正在显示
  /// 用于快速判断，避免重复创建菜单
  static bool _isShowing = false;

  /// 上次菜单关闭的时间戳
  static int _lastClosedTime = 0;

  /// 尝试显示菜单
  ///
  /// 这是一个"乐观锁"模式的实现：
  /// 1. 检查是否已有菜单显示
  /// 2. 如果没有，标记为"正在显示"并返回 true
  /// 3. 如果有，直接返回 false，拒绝显示
  ///
  /// [entry] 要显示的 OverlayEntry
  /// 返回 true 表示可以显示，false 表示已有菜单显示中
  static bool tryShow(OverlayEntry entry) {
    // 已有菜单显示中，拒绝新的菜单
    if (_isShowing) return false;

    // 标记为显示中
    _isShowing = true;

    // 移除之前的菜单（如果有）
    _currentEntry?.remove();

    // 保存新菜单的引用
    _currentEntry = entry;

    return true;
  }

  /// 关闭当前菜单
  ///
  /// 由外部调用，强制关闭当前显示的菜单
  /// 例如：组件销毁时、路由切换时
  static void close() {
    _currentEntry?.remove();
    _currentEntry = null;
    _isShowing = false;
  }

  /// 标记菜单已关闭
  ///
  /// 由菜单自身调用，表示菜单已被关闭（如用户点击了菜单项）
  /// 只清除状态，不执行 remove 操作（因为菜单已经自己移除了）
  static void markClosed() {
    _currentEntry = null;
    _isShowing = false;
    _lastClosedTime = DateTime.now().millisecondsSinceEpoch;
  }

  /// 检查当前是否有菜单正在显示
  ///
  /// 用于外部判断是否需要显示空白区域的菜单
  static bool isShowing() => _isShowing;

  /// 检查菜单是否刚刚关闭（在 100 毫秒内）
  ///
  /// 用于处理菜单关闭时的焦点和手势冲突问题
  static bool wasJustClosed() {
    return DateTime.now().millisecondsSinceEpoch - _lastClosedTime < 100;
  }
}

/// 右键菜单组件
///
/// 这是一个包装组件，为其子组件添加右键菜单功能
///
/// 核心功能：
/// 1. 监听右键点击事件
/// 2. 在鼠标位置显示菜单
/// 3. 自动处理屏幕边界情况
/// 4. 点击菜单项或外部区域关闭菜单
///
/// 使用方式：
///
/// ```dart
/// // 方式一：静态菜单（菜单项固定）
/// ContextMenu(
///   menuItems: [
///     ContextMenuItem(label: '复制', icon: Icons.copy, onTap: () => print('复制')),
///     ContextMenuItem.divider(),
///     ContextMenuItem(label: '删除', icon: Icons.delete, onTap: () => print('删除')),
///   ],
///   child: YourWidget(),
/// )
///
/// // 方式二：动态菜单（菜单项根据上下文变化）
/// ContextMenu(
///   getMenuItems: () {
///     // 根据当前状态返回不同的菜单项
///     if (isSelected) {
///       return [ContextMenuItem(label: '取消选择', onTap: () {})];
///     } else {
///       return [ContextMenuItem(label: '选择', onTap: () {})];
///     }
///   },
///   child: YourWidget(),
/// )
///
/// // 方式三：静态方法显示菜单（用于父容器监听空白区域右键）
/// // 先检查是否已有菜单显示，避免与子组件的菜单冲突
/// if (!ContextMenu.isMenuShowing()) {
///   ContextMenu.showMenuAt(
///     context: context,
///     position: tapPosition,
///     menuItems: [ContextMenuItem(label: '新建', onTap: () {})],
///   );
/// }
/// ```
class ContextMenu extends StatefulWidget {
  /// 子组件
  /// 右键点击这个区域会显示菜单
  final Widget child;

  /// 菜单项列表（静态菜单）
  ///
  /// 当菜单项固定不变时使用
  /// 与 [getMenuItems] 二选一
  final List<ContextMenuItem>? menuItems;

  /// 菜单项回调（动态菜单）
  ///
  /// 当菜单项需要根据上下文动态变化时使用
  /// 在右键点击时立即调用，获取当前应该显示的菜单项
  ///
  /// 优势：可以捕获右键时刻的状态，避免状态在菜单显示期间变化
  /// 例如：根据当前悬停的书籍显示不同的菜单
  final List<ContextMenuItem> Function()? getMenuItems;

  /// 右键按下回调（可选）
  ///
  /// 检测到右键按下时触发，在显示菜单之前调用。
  /// 用于让调用方获取右键事件信息（如点击位置），自行处理光标定位等逻辑。
  /// 支持同步或异步回调：若返回 [Future]，菜单会在 Future 完成后再显示，
  /// 便于调用方在菜单显示前完成异步状态刷新（如剪贴板内容检测）。
  final FutureOr<void> Function(PointerDownEvent)? onSecondaryTapDown;

  /// 菜单关闭回调（可选）
  ///
  /// 当菜单被关闭（无论是点击外部、点击菜单项还是按ESC键）时触发。
  /// 用于让调用方在菜单关闭时恢复焦点等状态。
  final VoidCallback? onDismissed;

  /// 是否显示菜单项图标（可选，默认为 true）
  ///
  /// 设为 false 时，所有菜单项的图标都不渲染，使菜单更紧凑
  final bool showIcons;

  /// 菜单项字体大小（可选，默认为 null，使用主题默认值）
  final double? fontSize;

  /// 菜单项内边距（可选，默认为 null，使用 EdgeInsets.symmetric(horizontal: 12, vertical: 8)）
  final EdgeInsets? itemPadding;

  /// 菜单类型（可选，默认为 ContextMenuType.contextMenu）
  ///
  /// 决定菜单的定位策略和点击行为：
  /// - [ContextMenuType.contextMenu]：右键菜单（默认）
  /// - [ContextMenuType.dropdown]：下拉菜单
  final ContextMenuType type;

  /// 菜单外层内边距（可选，默认为 null，使用 EdgeInsets.symmetric(vertical: 8)）
  final EdgeInsets? menuPadding;

  /// 点击菜单外部时是否仅关闭菜单而不响应点击（可选，默认为 null）
  ///
  /// - null：根据 [type] 自动决定（右键菜单为 false，下拉菜单为 true）
  /// - true：点击外部仅关闭菜单，不响应点击
  /// - false：点击外部关闭菜单的同时响应点击
  final bool? consumeOutsideClicks;

  const ContextMenu({
    super.key,
    required this.child,
    this.menuItems,
    this.getMenuItems,
    this.onSecondaryTapDown,
    this.onDismissed,
    this.showIcons = true,
    this.fontSize,
    this.itemPadding,
    this.type = ContextMenuType.contextMenu,
    this.menuPadding,
    this.consumeOutsideClicks,
  }) : assert(
         menuItems != null || getMenuItems != null,
         'menuItems 或 getMenuItems 必须提供一个',
       );

  /// 检查当前是否有右键菜单正在显示
  ///
  /// 用于外部判断是否需要显示其他菜单（如空白区域菜单）
  static bool isMenuShowing() => _ContextMenuController.isShowing();

  /// 检查右键菜单是否刚刚关闭（100毫秒内）
  ///
  /// 用于处理菜单关闭时的焦点和手势冲突，例如防止 TextField 光标闪烁
  static bool wasJustClosed() => _ContextMenuController.wasJustClosed();

  /// 在指定位置显示菜单（静态方法）
  ///
  /// 用于在代码中主动调用显示菜单，而非由右键事件自动触发
  /// 例如：在书架空白区域右键时，由代码决定显示的菜单内容
  ///
  /// [context] BuildContext，用于获取 Overlay
  /// [position] 菜单显示位置（屏幕坐标）
  /// [menuItems] 菜单项列表
  static void showMenuAt({
    required BuildContext context,
    required Offset position,
    required List<ContextMenuItem> menuItems,
    bool showIcons = true,
    double? fontSize,
    EdgeInsets? itemPadding,
    ContextMenuType type = ContextMenuType.contextMenu,
    Size? anchorSize,
    EdgeInsets? menuPadding,
    VoidCallback? onDismissed,
    bool? consumeOutsideClicks,
  }) {
    if (menuItems.isEmpty) return;

    OverlayEntry? overlayEntry;

    void hideMenu() {
      overlayEntry?.remove();
      overlayEntry = null;
      _ContextMenuController.markClosed();
      onDismissed?.call();
    }

    overlayEntry = OverlayEntry(
      builder: (context) => _MenuOverlay(
        position: position,
        menuItems: menuItems,
        onDismiss: hideMenu,
        showIcons: showIcons,
        fontSize: fontSize,
        itemPadding: itemPadding,
        type: type,
        anchorSize: anchorSize,
        menuPadding: menuPadding,
        consumeOutsideClicks: consumeOutsideClicks,
      ),
    );

    if (!_ContextMenuController.tryShow(overlayEntry!)) {
      return;
    }

    Overlay.of(context).insert(overlayEntry!);
  }

  @override
  State<ContextMenu> createState() => _ContextMenuState();
}

/// 仅识别右键按下的手势识别器
///
/// 继承自 EagerGestureRecognizer，在检测到右键时立即消费该指针事件序列，
/// 阻止事件穿透到子组件，同时通过 [onSecondaryDown] 回调通知调用方。
class _SecondaryButtonGestureRecognizer extends EagerGestureRecognizer {
  /// 右键按下时的回调
  void Function(PointerDownEvent event)? onSecondaryDown;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    // 仅处理右键（buttons == 2），左键/中键等忽略并正常传递给子组件
    if (event.buttons == 2) {
      super.addAllowedPointer(event);
      onSecondaryDown?.call(event);
    }
  }
}

class _ContextMenuState extends State<ContextMenu> {
  /// 当前显示的菜单 Overlay 条目
  /// 保存引用是为了在组件销毁时能够清理
  OverlayEntry? _overlayEntry;

  /// 获取菜单项
  ///
  /// 优先使用动态回调，其次使用静态列表
  /// 这样设计是为了支持两种使用方式
  List<ContextMenuItem> _getMenuItems() {
    return widget.getMenuItems?.call() ?? widget.menuItems ?? [];
  }

  /// 显示右键菜单
  ///
  /// 实现步骤：
  /// 1. 获取菜单项配置
  /// 2. 创建 OverlayEntry（Overlay 的内容）
  /// 3. 尝试获取显示权限（防止多个菜单同时显示）
  /// 4. 将 OverlayEntry 插入到 Overlay 层
  ///
  /// [position] 鼠标点击位置（屏幕坐标）
  void _showMenu(Offset position) {
    // 获取菜单项
    final items = _getMenuItems();
    if (items.isEmpty) return;

    // 创建 OverlayEntry
    // OverlayEntry 是 Overlay 层的一个条目
    // 它的 builder 会在 Overlay 层渲染时调用
    _overlayEntry = OverlayEntry(
      builder: (context) => _MenuOverlay(
        position: position,
        menuItems: items,
        onDismiss: _hideMenu,
        showIcons: widget.showIcons,
        fontSize: widget.fontSize,
        itemPadding: widget.itemPadding,
        type: widget.type,
        menuPadding: widget.menuPadding,
        consumeOutsideClicks: widget.consumeOutsideClicks,
      ),
    );

    // 尝试显示菜单
    // 如果全局已有菜单显示中，则放弃显示
    if (!_ContextMenuController.tryShow(_overlayEntry!)) {
      _overlayEntry = null;
      return;
    }

    // 将 OverlayEntry 插入到 Overlay 层
    // Overlay.of(context) 获取最近的 Overlay 组件
    // Material App 默认在根部有一个 Overlay
    Overlay.of(context).insert(_overlayEntry!);
  }

  /// 隐藏右键菜单
  void _hideMenu() {
    // 移除 Overlay 层中的菜单
    _overlayEntry?.remove();
    _overlayEntry = null;
    _ContextMenuController.markClosed();
    widget.onDismissed?.call();
  }

  @override
  void dispose() {
    // 组件销毁时，如果当前菜单是此组件创建的，则关闭它
    // 这是为了防止组件销毁后菜单仍然显示的问题
    if (_ContextMenuController._currentEntry == _overlayEntry) {
      _ContextMenuController.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 使用 RawGestureDetector + _SecondaryButtonGestureRecognizer 监听右键事件
    // EagerGestureRecognizer 会立即消费右键指针序列，阻止穿透到子组件
    // 左键等非右键事件不受影响，正常传递给子组件处理
    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        _SecondaryButtonGestureRecognizer: GestureRecognizerFactoryWithHandlers<
            _SecondaryButtonGestureRecognizer>(
          () => _SecondaryButtonGestureRecognizer(),
          (_SecondaryButtonGestureRecognizer instance) {
            instance.onSecondaryDown = (PointerDownEvent event) async {
              // 先通知调用方（用于光标定位等自定义逻辑）
              // 支持异步回调：等待调用方完成异步状态刷新后再显示菜单
              final dynamic result = widget.onSecondaryTapDown?.call(event);
              if (result is Future) await result;
              // 组件可能在 await 期间被销毁，需检查后再显示菜单
              if (!mounted) return;
              // 显示菜单
              _showMenu(event.position);
            };
          },
        ),
      },
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }
}

/// 菜单 Overlay 内容
///
/// 显示在 Overlay 层的内容，包含：
/// 1. 全屏透明遮罩 - 用于检测外部点击，关闭菜单
/// 2. 菜单主体
class _MenuOverlay extends StatefulWidget {
  /// 鼠标点击位置（屏幕坐标）
  final Offset position;

  /// 菜单项列表
  final List<ContextMenuItem> menuItems;

  /// 关闭菜单的回调
  final VoidCallback onDismiss;

  /// 是否显示菜单项图标
  final bool showIcons;

  /// 菜单项字体大小（可选，默认为 null，使用主题默认值）
  final double? fontSize;

  /// 菜单项内边距（可选，默认为 null）
  final EdgeInsets? itemPadding;

  /// 菜单类型
  final ContextMenuType type;

  /// 锚点组件尺寸（可选，仅下拉菜单使用）
  ///
  /// 与 [position] 配合计算锚点矩形区域，用于下拉菜单的定位：
  /// - 正常显示：菜单出现在锚点下方
  /// - 翻转显示：菜单出现在锚点上方
  final Size? anchorSize;

  /// 菜单外层内边距（可选，默认为 null，使用 EdgeInsets.symmetric(vertical: 8)）
  final EdgeInsets? menuPadding;

  /// 点击菜单外部时是否仅关闭菜单而不响应点击（可选，默认为 null）
  ///
  /// - null：根据 [type] 自动决定（右键菜单为 false，下拉菜单为 true）
  /// - true：点击外部仅关闭菜单，不响应点击
  /// - false：点击外部关闭菜单的同时响应点击
  final bool? consumeOutsideClicks;

  const _MenuOverlay({
    required this.position,
    required this.menuItems,
    required this.onDismiss,
    this.showIcons = true,
    this.fontSize,
    this.itemPadding,
    this.type = ContextMenuType.contextMenu,
    this.anchorSize,
    this.menuPadding,
    this.consumeOutsideClicks,
  });

  @override
  State<_MenuOverlay> createState() => _MenuOverlayState();
}

class _MenuOverlayState extends State<_MenuOverlay>
    with SingleTickerProviderStateMixin {
  /// 菜单实际显示位置
  /// 初始值是鼠标位置，可能会被调整
  late Offset _menuPosition;

  /// 是否已经调整过位置
  /// 防止重复调整
  bool _positionAdjusted = false;

  /// 动画控制器
  late AnimationController _animationController;

  /// 缩放动画
  late Animation<double> _scaleAnimation;

  /// 透明度动画
  late Animation<double> _opacityAnimation;

  /// 当前选中的菜单项索引（键盘导航用）
  /// -1 表示没有选中任何项
  int _selectedIndex = -1;

  /// 当前打开的子菜单索引
  /// -1 表示没有打开的子菜单
  int _openedSubmenuIndex = -1;

  /// 子菜单中选中的索引
  int _submenuSelectedIndex = -1;

  /// 焦点节点（用于键盘事件监听）
  final FocusNode _focusNode = FocusNode();

  /// 子菜单的 OverlayEntry
  OverlayEntry? _submenuEntry;

  /// 子菜单项的位置信息（用于键盘导航时更新子菜单）
  Rect? _submenuParentRect;

  /// 关闭子菜单的计时器
  Timer? _closeSubmenuTimer;

  /// 是否鼠标在子菜单内
  bool _isMouseInSubmenu = false;

  /// 是否鼠标在主菜单内
  bool _isMouseInMainMenu = false;

  /// 是否处于键盘导航模式（键盘操作后，鼠标需要移动才能重新接管控制）
  bool _isKeyboardMode = false;

  /// 子菜单选中状态的 ValueNotifier（用于更新子菜单而不重建 Overlay）
  ValueNotifier<int>? _submenuSelectedIndexNotifier;


  /// 获取当前菜单中可选择的项（排除分隔线）
  List<int> get _selectableIndices {
    final indices = <int>[];
    for (int i = 0; i < widget.menuItems.length; i++) {
      if (!widget.menuItems[i].isDivider) {
        indices.add(i);
      }
    }
    return indices;
  }

  /// 获取子菜单中可选择的项（排除分隔线）
  List<int> _getSubmenuSelectableIndices(List<ContextMenuItem> items) {
    final indices = <int>[];
    for (int i = 0; i < items.length; i++) {
      if (!items[i].isDivider) {
        indices.add(i);
      }
    }
    return indices;
  }

  @override
  void initState() {
    super.initState();
    // 初始位置为鼠标点击位置
    _menuPosition = widget.position;

    // 初始化子菜单选中状态 Notifier
    _submenuSelectedIndexNotifier = ValueNotifier<int>(-1);

    // 初始化动画控制器
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    // 缩放动画：从 0.9 缩放到 1.0
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    // 透明度动画：从 0.0 到 1.0
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    // 启动渐入动画
    _animationController.forward();

    // 自动获取焦点以接收键盘事件
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _focusNode.dispose();
    _closeSubmenuTimer?.cancel();
    _submenuSelectedIndexNotifier?.dispose();
    _submenuEntry?.remove();
    _submenuEntry = null;
    super.dispose();
  }

  /// 处理键盘事件
  ///
  /// 支持的按键：
  /// - 上/下箭头：在菜单项之间移动选中状态
  /// - 右箭头：打开子菜单（如果当前项有子菜单）
  /// - 左箭头：关闭子菜单（如果子菜单已打开）
  /// - 回车/空格：激活当前选中的菜单项
  /// - ESC：关闭整个菜单
  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    // 进入键盘模式
    _isKeyboardMode = true;

    final key = event.logicalKey;

    // ESC 键：关闭菜单
    if (key == LogicalKeyboardKey.escape) {
      widget.onDismiss();
      return;
    }

    // 如果子菜单已打开，优先处理子菜单的导航
    if (_openedSubmenuIndex != -1) {
      _handleSubmenuKeyEvent(key);
      return;
    }

    // 主菜单的键盘导航
    final selectableIndices = _selectableIndices;
    if (selectableIndices.isEmpty) return;

    // 获取当前选中在可选项列表中的位置
    int currentSelectableIndex = selectableIndices.indexOf(_selectedIndex);

    switch (key) {
      case LogicalKeyboardKey.arrowUp:
        // 上箭头：移动到上一个可选项
        setState(() {
          if (currentSelectableIndex <= 0) {
            // 如果已在第一项，跳到最后一项
            _selectedIndex = selectableIndices.last;
          } else {
            _selectedIndex = selectableIndices[currentSelectableIndex - 1];
          }
        });
        break;

      case LogicalKeyboardKey.arrowDown:
        // 下箭头：移动到下一个可选项
        setState(() {
          if (currentSelectableIndex < 0 ||
              currentSelectableIndex >= selectableIndices.length - 1) {
            // 如果没有选中或已在最后一项，跳到第一项
            _selectedIndex = selectableIndices.first;
          } else {
            _selectedIndex = selectableIndices[currentSelectableIndex + 1];
          }
        });
        break;

      case LogicalKeyboardKey.arrowRight:
        // 右箭头：打开子菜单（如果当前项有子菜单）
        if (_selectedIndex != -1) {
          final item = widget.menuItems[_selectedIndex];
          if (item.hasChildren) {
            // 需要获取当前菜单项的位置来显示子菜单
            _openSubmenuFromKeyboard(_selectedIndex);
          }
        }
        break;

      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.space:
        // 回车或空格：激活当前选中项
        if (_selectedIndex != -1) {
          final item = widget.menuItems[_selectedIndex];
          if (item.hasChildren) {
            // 如果有子菜单，打开子菜单
            _openSubmenuFromKeyboard(_selectedIndex);
          } else if (item.onTap != null) {
            // 执行回调并关闭菜单
            widget.onDismiss();
            item.onTap!();
          }
        }
        break;
    }
  }

  /// 处理子菜单的键盘事件
  void _handleSubmenuKeyEvent(LogicalKeyboardKey key) {
    final parentItem = widget.menuItems[_openedSubmenuIndex];
    final children = parentItem.children!;
    final selectableIndices = _getSubmenuSelectableIndices(children);

    if (selectableIndices.isEmpty) return;

    int currentSelectableIndex =
        selectableIndices.indexOf(_submenuSelectedIndex);

    switch (key) {
      case LogicalKeyboardKey.arrowUp:
        // 上箭头：在子菜单中向上移动
        setState(() {
          if (currentSelectableIndex <= 0) {
            _submenuSelectedIndex = selectableIndices.last;
          } else {
            _submenuSelectedIndex = selectableIndices[currentSelectableIndex - 1];
          }
        });
        // 更新子菜单选中状态（通过 ValueNotifier，不重建 Overlay）
        _updateSubmenuSelectedIndex(_submenuSelectedIndex);
        break;

      case LogicalKeyboardKey.arrowDown:
        // 下箭头：在子菜单中向下移动
        setState(() {
          if (currentSelectableIndex < 0 ||
              currentSelectableIndex >= selectableIndices.length - 1) {
            _submenuSelectedIndex = selectableIndices.first;
          } else {
            _submenuSelectedIndex = selectableIndices[currentSelectableIndex + 1];
          }
        });
        // 更新子菜单选中状态（通过 ValueNotifier，不重建 Overlay）
        _updateSubmenuSelectedIndex(_submenuSelectedIndex);
        break;

      case LogicalKeyboardKey.arrowLeft:
        // 左箭头：关闭子菜单，返回主菜单
        _closeSubmenu();
        break;

      case LogicalKeyboardKey.arrowRight:
        // 右箭头：如果子菜单项有自己的子菜单，打开它
        // 目前暂不支持嵌套子菜单，但保留扩展空间
        // 如果需要支持，可以递归处理
        break;

      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.space:
        // 回车或空格：激活子菜单项
        if (_submenuSelectedIndex != -1) {
          final subItem = children[_submenuSelectedIndex];
          if (subItem.onTap != null) {
            widget.onDismiss();
            subItem.onTap!();
          }
        }
        break;
    }
  }

  /// 通过键盘打开子菜单
  /// 需要从 _MenuBody 获取菜单项的位置信息
  void _openSubmenuFromKeyboard(int index) {
    // 调用 _openSubmenu，标记为键盘触发
    _openSubmenu(index, null, true);
  }

  /// 打开子菜单
  /// [index] 主菜单项索引
  /// [itemRect] 菜单项的位置和尺寸（鼠标悬停时提供）
  /// [fromKeyboard] 是否由键盘导航触发（决定是否默认选中子菜单第一项）
  void _openSubmenu(int index, [Rect? itemRect, bool fromKeyboard = false]) {
    final item = widget.menuItems[index];
    if (!item.hasChildren) return;

    // 如果是键盘导航触发的，需要在下一帧执行 Overlay 操作
    if (itemRect == null) {
      // 键盘导航触发，延迟到下一帧
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _createSubmenuOverlay(index);
      });
    } else {
      // 鼠标悬停触发，可以直接执行（因为是在 onEnter 回调中）
      _submenuParentRect = itemRect;
      _createSubmenuOverlay(index);
    }

    setState(() {
      _openedSubmenuIndex = index;
      // 键盘导航打开子菜单时，默认选中第一项
      // 鼠标悬停打开子菜单时，不选中任何项
      if (fromKeyboard) {
        final submenuSelectable = _getSubmenuSelectableIndices(item.children!);
        _submenuSelectedIndex =
            submenuSelectable.isEmpty ? -1 : submenuSelectable.first;
      } else {
        _submenuSelectedIndex = -1;
      }
      // 更新 ValueNotifier
      _submenuSelectedIndexNotifier?.value = _submenuSelectedIndex;
    });
  }

  /// 创建子菜单 Overlay
  void _createSubmenuOverlay(int index) {
    final item = widget.menuItems[index];
    if (!item.hasChildren || _submenuParentRect == null) return;

    // 先移除旧的子菜单
    _submenuEntry?.remove();
    _submenuEntry = null;

    // 同步 ValueNotifier 的值
    _submenuSelectedIndexNotifier?.value = _submenuSelectedIndex;

    _submenuEntry = OverlayEntry(
      builder: (context) => _SubMenuOverlay(
        position: Offset(_submenuParentRect!.right - 1, _submenuParentRect!.top),
        parentItemWidth: _submenuParentRect!.width,
        menuItems: item.children!,
        // 使用 ValueNotifier 来更新选中状态，避免重建 Overlay
        selectedIndexNotifier: _submenuSelectedIndexNotifier!,
        onDismiss: widget.onDismiss,
        showIcons: widget.showIcons,
        fontSize: widget.fontSize,
        itemPadding: widget.itemPadding,
        menuPadding: widget.menuPadding,
        onMouseEnter: _onSubmenuEnter,
        onMouseExit: _onSubmenuExit,
        // 鼠标移动回调（退出键盘模式）
        onPointerHover: _onPointerHover,
        // 鼠标悬停到子菜单项时的回调
        onItemHover: (index) {
          if (!mounted) return;
          // 键盘模式下，忽略鼠标悬停事件
          if (_isKeyboardMode) return;
          setState(() {
            _submenuSelectedIndex = index;
          });
          // 直接更新 ValueNotifier，不重建 Overlay
          _submenuSelectedIndexNotifier?.value = index;
        },
      ),
    );

    Overlay.of(context).insert(_submenuEntry!);
  }

  /// 更新子菜单选中状态（通过 ValueNotifier，不重建 Overlay）
  void _updateSubmenuSelectedIndex(int index) {
    _submenuSelectedIndexNotifier?.value = index;
  }

  /// 关闭子菜单
  void _closeSubmenu() {
    _submenuEntry?.remove();
    _submenuEntry = null;
    setState(() {
      _openedSubmenuIndex = -1;
      _submenuSelectedIndex = -1;
    });
  }

  /// 鼠标悬停移动时的处理（退出键盘模式）
  void _onPointerHover(PointerEvent event) {
    if (_isKeyboardMode) {
      _isKeyboardMode = false;
    }
  }

  /// 鼠标悬停到菜单项时的处理
  void _onMenuItemHover(int index, Rect itemRect) {
    // 键盘模式下，忽略鼠标悬停事件
    if (_isKeyboardMode) return;

    // 如果选中项没变化，不需要更新
    if (_selectedIndex == index) return;

    _isMouseInMainMenu = true;
    _cancelCloseSubmenuTimer();

    final item = widget.menuItems[index];

    // 保存菜单项位置信息（用于键盘导航打开子菜单）
    _submenuParentRect = itemRect;

    // 更新选中状态（统一鼠标和键盘）
    setState(() {
      _selectedIndex = index;
    });

    // 如果该项有子菜单，打开子菜单
    if (item.hasChildren) {
      _openSubmenu(index, itemRect);
    } else if (_openedSubmenuIndex != -1) {
      // 如果当前有打开的子菜单，但鼠标悬停的项没有子菜单，关闭子菜单
      _closeSubmenu();
    }
  }

  /// 鼠标离开菜单项时的处理
  void _onMenuItemExit(int index) {
    // 标记鼠标离开主菜单项（但可能还在主菜单区域内）
    // 不立即关闭子菜单，等待鼠标移动到其他地方
  }

  /// 鼠标离开整个菜单区域时的处理
  void _onMenuExit() {
    _isMouseInMainMenu = false;
    // 清除选中状态
    setState(() {
      _selectedIndex = -1;
    });
    // 鼠标离开主菜单区域，延迟关闭子菜单
    _scheduleCloseSubmenu();
  }

  /// 取消关闭子菜单的计时器
  void _cancelCloseSubmenuTimer() {
    _closeSubmenuTimer?.cancel();
    _closeSubmenuTimer = null;
  }

  /// 延迟关闭子菜单
  void _scheduleCloseSubmenu() {
    // 如果鼠标在子菜单内，不关闭
    if (_isMouseInSubmenu) return;

    _closeSubmenuTimer?.cancel();
    _closeSubmenuTimer = Timer(const Duration(milliseconds: 150), () {
      // 再次检查鼠标是否在子菜单或主菜单内
      if (!_isMouseInSubmenu && !_isMouseInMainMenu) {
        _closeSubmenu();
      }
    });
  }

  /// 鼠标进入子菜单
  void _onSubmenuEnter() {
    _isMouseInSubmenu = true;
    _cancelCloseSubmenuTimer();
  }

  /// 鼠标离开子菜单
  void _onSubmenuExit() {
    _isMouseInSubmenu = false;
    // 鼠标离开子菜单，不关闭子菜单（可能回主菜单或其他地方）
    // 子菜单只有在鼠标离开主菜单区域时才关闭
  }

  /// 位置报告回调（用于键盘导航时获取菜单项位置）
  void _onPositionReport(int index, Rect itemRect) {
    // 只保存位置信息，不触发打开子菜单
    _submenuParentRect = itemRect;
  }

  /// 调整菜单位置，确保不超出屏幕边界
  ///
  /// 根据 [type] 区分两种场景：
  ///
  /// 右键菜单（contextMenu）：
  /// - position 为点击位置，菜单左上角对齐该位置
  /// - 翻转到上方时，菜单底部对齐点击位置
  /// - 翻转到左侧时，菜单右边缘对齐点击位置
  ///
  /// 下拉菜单（dropdown）：
  /// - position 为锚点左上角，菜单默认显示在锚点下方
  /// - 翻转到上方时，菜单底部对齐锚点顶部
  /// - 翻转到左侧时，菜单右边缘对齐锚点右边缘
  ///
  /// [screenSize] 屏幕尺寸
  /// [menuSize] 菜单实际尺寸
  void _adjustPosition(Size screenSize, Size menuSize) {
    // 只调整一次
    if (_positionAdjusted) return;
    _positionAdjusted = true;

    final isDropdown = widget.type == ContextMenuType.dropdown;

    // 下拉菜单：锚点矩形由 position + anchorSize 计算
    final anchorRect = isDropdown && widget.anchorSize != null
        ? widget.position & widget.anchorSize!
        : null;

    double left;
    double top;

    if (isDropdown && anchorRect != null) {
      // 下拉菜单：菜单默认出现在锚点下方
      left = anchorRect.left;
      top = anchorRect.bottom + 4;
    } else {
      // 右键菜单：菜单左上角对齐点击位置
      left = widget.position.dx;
      top = widget.position.dy;
    }

    // 检查右边界
    if (left + menuSize.width > screenSize.width) {
      if (isDropdown && anchorRect != null) {
        // 下拉菜单：菜单右边缘对齐锚点右边缘
        left = anchorRect.right - menuSize.width;
      } else {
        // 右键菜单：菜单右边缘对齐点击位置
        left = widget.position.dx - menuSize.width;
      }
      if (left < 0) left = 8;
    }

    // 检查下边界
    if (top + menuSize.height > screenSize.height) {
      if (isDropdown && anchorRect != null) {
        // 下拉菜单：菜单底部对齐锚点顶部，留 6px 间距
        top = anchorRect.top - menuSize.height - 6;
      } else {
        // 右键菜单：菜单底部对齐点击位置
        top = widget.position.dy - menuSize.height;
      }
      if (top < 0) top = 8;
    }

    // 更新位置并重新渲染
    setState(() => _menuPosition = Offset(left, top));
  }

  @override
  Widget build(BuildContext context) {
    // 获取屏幕尺寸，用于边界检测
    final screenSize = MediaQuery.of(context).size;

    // 下拉菜单：点击外部仅关闭菜单，不响应点击事件
    // 右键菜单：点击外部关闭菜单的同时响应点击事件
    final isDropdown = widget.type == ContextMenuType.dropdown;
    // 是否消费菜单外部的点击事件
    // null 时根据菜单类型自动决定：下拉菜单消费，右键菜单穿透
    final shouldConsumeClicks = widget.consumeOutsideClicks ?? isDropdown;

    return KeyboardListener(
      // 焦点节点，用于接收键盘事件
      focusNode: _focusNode,
      // 处理键盘事件
      onKeyEvent: _handleKeyEvent,
      child: Stack(
        children: [
          // ----------------------------------------------------------
          // 全屏透明遮罩层
          // ----------------------------------------------------------
          // 作用：捕获菜单外部的点击事件，点击时关闭菜单
          //
          // HitTestBehavior 差异：
          // - shouldConsumeClicks=true：opaque，阻止事件穿透，点击仅关闭菜单
          // - shouldConsumeClicks=false：translucent，允许事件穿透到下层组件
          // ----------------------------------------------------------
          Positioned.fill(
            child: Listener(
              behavior: shouldConsumeClicks ? HitTestBehavior.opaque : HitTestBehavior.translucent,
              onPointerDown: (_) => widget.onDismiss(),
              child: const SizedBox.expand(),
            ),
          ),

          // ----------------------------------------------------------
          // 菜单主体
          // ----------------------------------------------------------
          // 使用 Positioned 定位到鼠标位置
          // left 和 top 是屏幕绝对坐标
          // 位置计算完成前隐藏菜单，避免闪烁
          // ----------------------------------------------------------
          Positioned(
            left: _menuPosition.dx,
            top: _menuPosition.dy,
            child: Opacity(
              // 位置计算完成前隐藏，避免闪烁
              opacity: _positionAdjusted ? 1.0 : 0.0,
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _opacityAnimation.value,
                    child: Transform.scale(
                      scale: _scaleAnimation.value,
                      alignment: Alignment.topLeft,
                      child: child,
                    ),
                  );
                },
                // Listener 用于监听鼠标移动，退出键盘模式
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerHover: _onPointerHover,
                  child: _MenuBody(
                    menuItems: widget.menuItems,
                    onDismiss: widget.onDismiss,
                    onSizeReady: (size) => _adjustPosition(screenSize, size),
                    showIcons: widget.showIcons,
                    fontSize: widget.fontSize,
                    itemPadding: widget.itemPadding,
                    menuPadding: widget.menuPadding,
                    // 键盘导航相关参数
                    selectedIndex: _selectedIndex,
                    openedSubmenuIndex: _openedSubmenuIndex,
                    // 鼠标交互回调
                    onItemHover: _onMenuItemHover,
                    onItemExit: _onMenuItemExit,
                    onMenuExit: _onMenuExit,
                    // 位置报告回调（用于键盘导航）
                    onPositionReport: _onPositionReport,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 菜单主体组件，负责渲染菜单项列表
class _MenuBody extends StatelessWidget {
  final List<ContextMenuItem> menuItems;
  final VoidCallback onDismiss;
  final ValueChanged<Size> onSizeReady;

  /// 是否显示菜单项图标
  final bool showIcons;

  /// 菜单项字体大小
  final double? fontSize;

  /// 菜单项内边距
  final EdgeInsets? itemPadding;

  /// 菜单外层内边距
  final EdgeInsets? menuPadding;

  /// 键盘导航：当前选中的菜单项索引
  final int selectedIndex;

  /// 键盘导航：当前打开的子菜单索引
  final int openedSubmenuIndex;

  /// 鼠标悬停回调
  final void Function(int index, Rect itemRect)? onItemHover;

  /// 鼠标离开回调
  final void Function(int index)? onItemExit;

  /// 鼠标离开整个菜单区域回调
  final VoidCallback? onMenuExit;

  /// 位置报告回调（用于键盘导航时获取菜单项位置）
  final void Function(int index, Rect itemRect)? onPositionReport;

  const _MenuBody({
    required this.menuItems,
    required this.onDismiss,
    required this.onSizeReady,
    this.showIcons = true,
    this.fontSize,
    this.itemPadding,
    this.menuPadding,
    this.selectedIndex = -1,
    this.openedSubmenuIndex = -1,
    this.onItemHover,
    this.onItemExit,
    this.onMenuExit,
    this.onPositionReport,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // ----------------------------------------------------------
    // 在帧结束后获取菜单尺寸
    // ----------------------------------------------------------
    // 菜单使用 IntrinsicWidth，宽度在布局时才能确定
    // 在渲染后才能知道实际尺寸，知道尺寸后才能判断是否超出屏幕边界
    //
    // addPostFrameCallback 的执行时机：
    // 1. build 方法执行完毕
    // 2. Flutter 完成布局和绘制
    // 3. 回调被触发
    // ----------------------------------------------------------
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // findRenderObject() 获取当前组件的 RenderObject
      // RenderBox 是有大小信息的渲染对象
      final box = context.findRenderObject() as RenderBox?;
      if (box != null) {
        // 将尺寸回调给父组件
        onSizeReady(box.size);
      }
    });

    return MouseRegion(
      onExit: (_) {
        // 鼠标离开整个菜单区域
        onMenuExit?.call();
      },
      child: Material(
        // Material 提供阴影效果
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        // 使用主题色作为背景
        color: theme.colorScheme.surfaceContainerHigh,
        // IntrinsicWidth 让宽度根据内容自适应
        // 同时 ConstrainedBox 保证最小宽度
        child: IntrinsicWidth(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 160),
            child: Padding(
              padding: menuPadding ?? const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: List.generate(menuItems.length, (index) {
                  final item = menuItems[index];
                  // 分隔线渲染为 Divider
                  if (item.isDivider) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Divider(height: 1),
                    );
                  }
                  // 普通菜单项
                  return _MenuItem(
                    item: item,
                    index: index,
                    onDismiss: onDismiss,
                    showIcons: showIcons,
                    fontSize: fontSize,
                    itemPadding: itemPadding,
                    // 键盘导航相关参数
                    isSelected: selectedIndex == index,
                    isSubmenuOpen: openedSubmenuIndex == index,
                    // 鼠标交互回调
                    onHover: onItemHover,
                    onExit: onItemExit,
                    // 位置报告回调
                    onPositionReport: onPositionReport,
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 单个菜单项组件
///
/// 功能：
/// 1. 显示图标和文本
/// 2. 悬停时高亮
/// 3. 点击时触发回调并关闭菜单
/// 4. 支持键盘导航选中状态
/// 5. 通过回调通知父组件处理子菜单
class _MenuItem extends StatefulWidget {
  final ContextMenuItem item;

  /// 菜单项索引
  final int index;

  final VoidCallback onDismiss;

  /// 是否显示菜单项图标
  final bool showIcons;

  /// 菜单项字体大小
  final double? fontSize;

  /// 菜单项内边距
  final EdgeInsets? itemPadding;

  /// 键盘导航：是否被选中
  final bool isSelected;

  /// 键盘导航：子菜单是否打开
  final bool isSubmenuOpen;

  /// 鼠标悬停回调
  final void Function(int index, Rect itemRect)? onHover;

  /// 鼠标离开回调
  final void Function(int index)? onExit;

  /// 位置报告回调（用于键盘导航时获取菜单项位置，不触发打开子菜单）
  final void Function(int index, Rect itemRect)? onPositionReport;

  const _MenuItem({
    required this.item,
    required this.index,
    required this.onDismiss,
    this.showIcons = true,
    this.fontSize,
    this.itemPadding,
    this.isSelected = false,
    this.isSubmenuOpen = false,
    this.onHover,
    this.onExit,
    this.onPositionReport,
  });

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  /// 子菜单显示位置的 GlobalKey
  final GlobalKey _itemKey = GlobalKey();

  @override
  void didUpdateWidget(_MenuItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当选中状态变化时，报告位置信息（用于键盘导航）
    if (widget.isSelected && !oldWidget.isSelected) {
      _reportPosition();
    }
  }

  /// 报告菜单项位置（不触发打开子菜单）
  void _reportPosition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final RenderBox? itemBox =
          _itemKey.currentContext?.findRenderObject() as RenderBox?;
      if (itemBox != null) {
        final itemRect = itemBox.localToGlobal(Offset.zero) & itemBox.size;
        widget.onPositionReport?.call(widget.index, itemRect);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasChildren = widget.item.hasChildren;
    final isEnabled = widget.item.enabled;

    // 综合判断是否应该高亮显示：
    // 1. 鼠标悬停或键盘选中
    // 2. 子菜单打开时，母选项也显示高亮
    // 3. 禁用时不显示高亮
    final shouldHighlight = isEnabled && (widget.isSelected || widget.isSubmenuOpen);

    return MouseRegion(
      key: _itemKey,
      onHover: (_) {
        // 鼠标在菜单项上移动时，通知父组件
        // 使用 onHover 而非 onEnter，这样即使鼠标在原选项上移动也能触发
        final RenderBox? itemBox =
            _itemKey.currentContext?.findRenderObject() as RenderBox?;
        if (itemBox != null) {
          final itemRect = itemBox.localToGlobal(Offset.zero) & itemBox.size;
          widget.onHover?.call(widget.index, itemRect);
        }
      },
      onExit: (_) {
        widget.onExit?.call(widget.index);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: (hasChildren || !isEnabled)
            ? null
            : () {
                widget.onDismiss();
                widget.item.onTap?.call();
              },
        child: Container(
          padding: widget.itemPadding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          // 键盘选中或鼠标悬停时显示高亮背景
          color: shouldHighlight
              ? theme.colorScheme.primary.withValues(alpha: 0.1)
              : null,
          child: Row(
            children: [
              if (widget.showIcons && (widget.item.icon != null || widget.item.iconBuilder != null)) ...[
                // 图标颜色：禁用时变灰，否则根据悬停/选中状态变化
                widget.item.iconBuilder != null
                    ? widget.item.iconBuilder!(
                        !isEnabled
                            ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
                            : widget.item.labelColor ??
                                (shouldHighlight
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                      )
                    : Icon(
                        widget.item.icon,
                        size: 18,
                        color: !isEnabled
                            ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
                            : widget.item.labelColor ??
                                (shouldHighlight
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                      ),
                const SizedBox(width: 12),
              ],
              Expanded(
                  child: widget.item.displayLabel(
                      isHovered: shouldHighlight, theme: theme, fontSize: widget.fontSize)),
              if (hasChildren)
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: !isEnabled
                      ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
                      : (shouldHighlight
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 子菜单 Overlay 内容
///
/// 包含位置定位和鼠标悬停检测
class _SubMenuOverlay extends StatefulWidget {
  final Offset position;
  final double parentItemWidth;
  final List<ContextMenuItem> menuItems;
  final VoidCallback onDismiss;
  final VoidCallback onMouseEnter;
  final VoidCallback onMouseExit;

  /// 是否显示菜单项图标
  final bool showIcons;

  /// 菜单项字体大小
  final double? fontSize;

  /// 菜单项内边距
  final EdgeInsets? itemPadding;

  /// 菜单外层内边距
  final EdgeInsets? menuPadding;

  /// 键盘导航：子菜单中选中的索引（使用 ValueNotifier 避免重建 Overlay）
  final ValueNotifier<int> selectedIndexNotifier;

  /// 鼠标悬停到子菜单项时的回调
  final void Function(int index)? onItemHover;

  /// 鼠标悬停移动回调（用于退出键盘模式）
  final void Function(PointerEvent event)? onPointerHover;

  const _SubMenuOverlay({
    required this.position,
    required this.parentItemWidth,
    required this.menuItems,
    required this.onDismiss,
    required this.onMouseEnter,
    required this.onMouseExit,
    required this.selectedIndexNotifier,
    this.showIcons = true,
    this.fontSize,
    this.itemPadding,
    this.menuPadding,
    this.onItemHover,
    this.onPointerHover,
  });

  @override
  State<_SubMenuOverlay> createState() => _SubMenuOverlayState();
}

class _SubMenuOverlayState extends State<_SubMenuOverlay> {
  /// 子菜单实际显示位置
  late Offset _menuPosition;

  /// 是否已经调整过位置
  bool _positionAdjusted = false;

  @override
  void initState() {
    super.initState();
    _menuPosition = widget.position;
  }

  /// 调整子菜单位置，确保不超出屏幕边界
  void _adjustPosition(Size screenSize, Size menuSize) {
    if (_positionAdjusted) return;
    _positionAdjusted = true;

    double left = widget.position.dx;
    double top = widget.position.dy;

    // 检查右边界：如果子菜单超出屏幕右侧，显示在父菜单项左侧
    if (left + menuSize.width > screenSize.width) {
      // 显示在父菜单项左侧
      left = widget.position.dx - widget.parentItemWidth - menuSize.width;
      // 如果左侧也超出，则贴屏幕左边缘
      if (left < 0) left = 8;
    }

    // 检查下边界
    if (top + menuSize.height > screenSize.height) {
      top = screenSize.height - menuSize.height - 8;
    }

    // 确保不超出上边界
    if (top < 0) top = 8;

    setState(() => _menuPosition = Offset(left, top));
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Positioned(
      left: _menuPosition.dx,
      top: _menuPosition.dy,
      // 位置计算完成前隐藏，避免闪烁
      child: Opacity(
        opacity: _positionAdjusted ? 1.0 : 0.0,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerHover: widget.onPointerHover,
          child: MouseRegion(
            onEnter: (_) => widget.onMouseEnter(),
            onExit: (_) => widget.onMouseExit(),
            child: _SubMenuBody(
              menuItems: widget.menuItems,
              onDismiss: widget.onDismiss,
              onSizeReady: (size) => _adjustPosition(screenSize, size),
              showIcons: widget.showIcons,
              fontSize: widget.fontSize,
              itemPadding: widget.itemPadding,
              menuPadding: widget.menuPadding,
              // 使用 ValueNotifier 来更新选中状态
              selectedIndexNotifier: widget.selectedIndexNotifier,
              // 鼠标悬停回调
              onItemHover: widget.onItemHover,
            ),
          ),
        ),
      ),
    );
  }
}

/// 子菜单主体组件
///
/// 使用 ValueNotifier 接收选中状态更新，避免重建 Overlay 导致闪烁
class _SubMenuBody extends StatelessWidget {
  final List<ContextMenuItem> menuItems;
  final VoidCallback onDismiss;
  final ValueChanged<Size> onSizeReady;

  /// 是否显示菜单项图标
  final bool showIcons;

  /// 菜单项字体大小
  final double? fontSize;

  /// 菜单项内边距
  final EdgeInsets? itemPadding;

  /// 菜单外层内边距
  final EdgeInsets? menuPadding;

  /// 键盘导航：当前选中的索引（使用 ValueNotifier 避免重建 Overlay）
  final ValueNotifier<int> selectedIndexNotifier;

  /// 鼠标悬停回调
  final void Function(int index)? onItemHover;

  const _SubMenuBody({
    required this.menuItems,
    required this.onDismiss,
    required this.onSizeReady,
    required this.selectedIndexNotifier,
    this.showIcons = true,
    this.fontSize,
    this.itemPadding,
    this.menuPadding,
    this.onItemHover,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 在帧结束后获取菜单尺寸
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = context.findRenderObject() as RenderBox?;
      if (box != null) {
        onSizeReady(box.size);
      }
    });

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerHigh,
      child: IntrinsicWidth(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 160),
          child: Padding(
            padding: menuPadding ?? const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(menuItems.length, (index) {
                final item = menuItems[index];
                if (item.isDivider) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Divider(height: 1),
                  );
                }
                return _SubMenuItem(
                  item: item,
                  index: index,
                  onDismiss: onDismiss,
                  showIcons: showIcons,
                  fontSize: fontSize,
                  itemPadding: itemPadding,
                  // 使用 ValueNotifier 来监听选中状态
                  selectedIndexNotifier: selectedIndexNotifier,
                  // 鼠标悬停回调
                  onHover: (idx, rect) {
                    onItemHover?.call(idx);
                  },
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

/// 子菜单项组件（使用 ValueNotifier 监听选中状态）
class _SubMenuItem extends StatelessWidget {
  final ContextMenuItem item;
  final int index;
  final VoidCallback onDismiss;
  final ValueNotifier<int> selectedIndexNotifier;
  final void Function(int index, Rect itemRect)? onHover;

  /// 是否显示菜单项图标
  final bool showIcons;

  /// 菜单项字体大小
  final double? fontSize;

  /// 菜单项内边距
  final EdgeInsets? itemPadding;

  const _SubMenuItem({
    required this.item,
    required this.index,
    required this.onDismiss,
    required this.selectedIndexNotifier,
    this.showIcons = true,
    this.fontSize,
    this.itemPadding,
    this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasChildren = item.hasChildren;
    final isEnabled = item.enabled;

    return ValueListenableBuilder<int>(
      valueListenable: selectedIndexNotifier,
      builder: (context, selectedIndex, child) {
        // 禁用项也可以获取焦点（显示悬停效果），但不响应点击
        final isSelected = selectedIndex == index;

        return MouseRegion(
          onHover: (_) {
            onHover?.call(index, Rect.zero);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: (hasChildren || !isEnabled)
                ? null
                : () {
                    onDismiss();
                    item.onTap?.call();
                  },
            child: Container(
              padding: itemPadding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: isSelected
                  ? theme.colorScheme.primary.withValues(alpha: 0.1)
                  : null,
              child: Row(
                children: [
                  // 图标
                  if (showIcons && (item.icon != null || item.iconBuilder != null)) ...[
                    item.iconBuilder != null
                        ? item.iconBuilder!(
                            !isEnabled
                                ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
                                : isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface,
                          )
                        : Icon(
                            item.icon,
                            size: 18,
                            color: !isEnabled
                                ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
                                : isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface,
                          ),
                    const SizedBox(width: 8),
                  ],
                  // 标签
                  Expanded(
                    child: item.displayLabel(isHovered: isSelected, theme: theme, fontSize: fontSize),
                  ),
                  // 子菜单箭头
                  if (hasChildren) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_right,
                      size: 18,
                      color: !isEnabled
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
                          : isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
