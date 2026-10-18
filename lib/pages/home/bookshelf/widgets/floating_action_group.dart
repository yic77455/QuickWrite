import 'package:flutter/material.dart';

/// 悬浮操作项
///
/// 描述悬浮按钮组中单个操作按钮的图标、提示与点击回调
class FloatingActionItem {
  /// 按钮图标
  final IconData icon;

  /// 按钮提示文字
  final String tooltip;

  /// 点击回调
  final VoidCallback onPressed;

  const FloatingActionItem({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
}

/// 悬浮操作按钮组
///
/// 收起时只显示一个主按钮，点击主按钮后各操作按钮向上展开，
/// 展开的操作按钮按从下往上的顺序排列
class FloatingActionGroup extends StatefulWidget {
  /// 展开后显示的操作项，按从下往上的顺序提供
  final List<FloatingActionItem> actions;

  const FloatingActionGroup({super.key, required this.actions});

  @override
  State<FloatingActionGroup> createState() => _FloatingActionGroupState();
}

class _FloatingActionGroupState extends State<FloatingActionGroup> {
  /// 展开与收起的动画时长
  static const Duration _animationDuration = Duration(milliseconds: 200);

  /// 主悬浮按钮的圆角半径，与 Material 3 默认形状一致
  static const double _regularFabRadius = 16;

  /// 小悬浮按钮的圆角半径，与 Material 3 默认形状一致
  static const double _smallFabRadius = 12;

  /// 小悬浮按钮的边长
  ///
  /// 移动端为触摸操作，需要足够大的点击区域，因此大于默认的小悬浮按钮尺寸（40）
  static const double _smallFabSize = 46;

  /// 小悬浮按钮的图标尺寸
  static const double _smallFabIconSize = 26;

  /// 主悬浮按钮的投影
  static const BoxShadow _regularFabShadow = BoxShadow(
    color: Color(0x29000000),
    offset: Offset(3, 4),
    blurRadius: 10,
  );

  /// 小悬浮按钮的投影：尺寸更小，采用更紧更淡的阴影避免按钮周围发黑
  static const BoxShadow _smallFabShadow = BoxShadow(
    color: Color(0x0E000000),
    offset: Offset(3, 4),
    blurRadius: 6,
  );

  /// 点击区域分组标识
  ///
  /// 使用独立分组（而非默认的 null 分组），避免与其他未分组的点击区域归为同一组，
  /// 保证按钮组区域外的判定只依据按钮组自身
  final Object _tapRegionGroupId = Object();

  /// 是否处于展开状态
  bool _isExpanded = false;

  /// 为悬浮按钮包裹一层投影
  ///
  /// [radius] 需与对应悬浮按钮的圆角半径保持一致，保证阴影形状贴合按钮
  Widget _buildShadowedFab({
    required Widget child,
    required double radius,
    required BoxShadow shadow,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [shadow],
      ),
      child: child,
    );
  }

  /// 构建单个操作按钮
  ///
  /// 收起时按钮向下滑出并淡出，同时不再响应点击
  Widget _buildActionButton(FloatingActionItem action) {
    // 操作按钮需要更大的触摸区域，仅在按钮组范围内放大悬浮按钮的尺寸与图标
    final theme = Theme.of(context);
    final actionButtonTheme = theme.copyWith(
      floatingActionButtonTheme: theme.floatingActionButtonTheme.copyWith(
        smallSizeConstraints: const BoxConstraints.tightFor(
          width: _smallFabSize,
          height: _smallFabSize,
        ),
        iconSize: _smallFabIconSize,
      ),
    );

    return IgnorePointer(
      ignoring: !_isExpanded,
      child: AnimatedSlide(
        offset: _isExpanded ? Offset.zero : const Offset(0, 0.4),
        duration: _animationDuration,
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _isExpanded ? 1 : 0,
          duration: _animationDuration,
          curve: Curves.easeOut,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildShadowedFab(
              radius: _smallFabRadius,
              shadow: _smallFabShadow,
              child: Theme(
                data: actionButtonTheme,
                child: FloatingActionButton.small(
                  // 同一界面可能存在多个悬浮按钮，关闭默认的 Hero 动画避免冲突
                  heroTag: null,
                  tooltip: action.tooltip,
                  onPressed: () {
                    // 先收起按钮组，再执行对应操作
                    setState(() => _isExpanded = false);
                    action.onPressed();
                  },
                  child: Icon(action.icon),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 监听按钮组区域外的点击：展开状态下点击空白处先收起按钮组，
    // 并消费该次点击，阻止其穿透到下层组件，避免误触
    return TapRegion(
      groupId: _tapRegionGroupId,
      // 仅在展开时消费区域外的点击；收起时不消费，不影响书架卡片等下层组件的正常交互
      consumeOutsideTaps: _isExpanded,
      onTapOutside: (_) {
        if (_isExpanded) setState(() => _isExpanded = false);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 操作按钮从下往上排列，因此按倒序渲染
          for (final action in widget.actions.reversed)
            _buildActionButton(action),

          // 主按钮：点击切换展开状态，展开时图标旋转为关闭形态
          _buildShadowedFab(
            radius: _regularFabRadius,
            shadow: _regularFabShadow,
            child: FloatingActionButton(
              heroTag: null,
              onPressed: () => setState(() => _isExpanded = !_isExpanded),
              child: AnimatedRotation(
                // 0.125 圈即 45 度
                turns: _isExpanded ? 0.125 : 0,
                duration: _animationDuration,
                child: const Icon(Icons.add),
              ),
            ),
          ),
        ],
      ),
    );
  }
}