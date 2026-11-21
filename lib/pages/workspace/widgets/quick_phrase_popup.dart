import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:quick_write/core/models/quick_phrase.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:re_editor/re_editor.dart';

/// 浮层与屏幕边缘的最小留白
const double _screenMargin = 8;

/// 浮层与图标之间的间距
const double _anchorGap = 4;

/// 浮层宽度
const double _popupWidth = 200;

/// 浮层内容的最大高度，短语较多时列表在内部滚动
const double _maxPopupHeight = 320;

/// 浮层内容的最小高度，空状态时保持稳定的浮层高度
const double _minPopupHeight = 180;

/// 快捷短语浮层
///
/// 以触发图标的矩形 [anchorRect] 为锚点显示在图标上方，
/// 样式与应用的浮动菜单保持一致；点击外部关闭浮层，
/// 点击短语回传选择结果，底部提供短语编辑入口。
/// 整个浮层归属编辑器的点击区域组，关闭时输入法保持不收起。
class QuickPhrasePopup extends StatefulWidget {
  /// 触发图标的屏幕矩形
  final Rect anchorRect;

  /// 当前可选的短语列表
  final List<QuickPhrase> phrases;

  /// 选中某条短语
  final ValueChanged<QuickPhrase> onSelect;

  /// 打开短语编辑入口
  final VoidCallback onEdit;

  /// 关闭浮层
  final VoidCallback onDismiss;

  const QuickPhrasePopup({
    super.key,
    required this.anchorRect,
    required this.phrases,
    required this.onSelect,
    required this.onEdit,
    required this.onDismiss,
  });

  @override
  State<QuickPhrasePopup> createState() => _QuickPhrasePopupState();
}

class _QuickPhrasePopupState extends State<QuickPhrasePopup> {
  /// 短语列表滚动控制器，滚动条据此跟随列表滚动
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Size screenSize = MediaQuery.sizeOf(context);
    final double topLimit = MediaQuery.paddingOf(context).top + _screenMargin;

    // 浮层宽度在窄屏上收窄，避免左右两侧贴边
    final double width = math.min(
      _popupWidth,
      screenSize.width - _screenMargin * 2,
    );
    // 右边缘与图标右边缘对齐，空间不足时向左收敛到屏幕留白内
    final double maxLeft = math.max(
      _screenMargin,
      screenSize.width - width - _screenMargin,
    );
    final double left = (widget.anchorRect.right - width)
        .clamp(_screenMargin, maxLeft)
        .toDouble();
    // 底部对齐图标顶部上方，高度由内容决定
    final double bottom =
        screenSize.height - widget.anchorRect.top + _anchorGap;
    // 浮层向上伸展，最多占用到状态栏下方的可用高度
    final double availableHeight =
        widget.anchorRect.top - _anchorGap - topLimit;
    final double maxHeight = math.max(
      0.0,
      math.min(availableHeight, _maxPopupHeight),
    );
    // 空状态固定为最小高度，有短语时高度随列表内容增长
    final BoxConstraints contentConstraints = widget.phrases.isEmpty
        ? BoxConstraints.tightFor(height: math.min(_minPopupHeight, maxHeight))
        : BoxConstraints(maxHeight: maxHeight);

    // 整个浮层纳入编辑器的点击区域组，点击遮罩关闭浮层时编辑器不失焦
    return CodeEditorTapRegion(
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          // 外部点击遮罩：关闭浮层，不把点击传递给下层组件
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => widget.onDismiss(),
              child: const SizedBox.expand(),
            ),
          ),

          // 悬浮菜单主体，从图标上方弹出
          Positioned(
            left: left,
            bottom: bottom,
            width: width,
            // 菜单不参与焦点争夺，避免点击时输入法收起
            child: ExcludeFocus(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.scale(
                      scale: 0.96 + 0.04 * value,
                      alignment: Alignment.bottomRight,
                      child: child,
                    ),
                  );
                },
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(10),
                  clipBehavior: Clip.antiAlias,
                  color: colorScheme.surfaceContainerHigh,
                  child: ConstrainedBox(
                    constraints: contentConstraints,
                    child: Column(
                      mainAxisSize: widget.phrases.isEmpty
                          ? MainAxisSize.max
                          : MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.phrases.isEmpty)
                          // 空状态提示在分隔线上方的内容区居中
                          Expanded(
                            child: Center(
                              // 图标与提示语整体下移 4px，视觉上更居中
                              child: Transform.translate(
                                offset: const Offset(0, 4),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 空状态图标，弱化显示避免抢眼
                                    Icon(
                                      Icons.quickreply_rounded,
                                      size: 32,
                                      color: colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.4),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '还没有快捷短语',
                                      textAlign: TextAlign.center,
                                      style: context.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        else
                          Flexible(
                            // 去除系统安全区内边距，避免滚动条被系统留白顶开
                            child: MediaQuery.removePadding(
                              context: context,
                              removeTop: true,
                              removeBottom: true,
                              removeLeft: true,
                              removeRight: true,
                              // 短语较多滚动时显示滚动条
                              child: Scrollbar(
                                controller: _scrollController,
                                child: ListView.builder(
                                  controller: _scrollController,
                                  shrinkWrap: true,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  itemCount: widget.phrases.length,
                                  itemBuilder: (context, index) {
                                    final phrase = widget.phrases[index];
                                    return _PopupTile(
                                      icon: Icons.chat_bubble_outline_rounded,
                                      label: phrase.displayText,
                                      onTap: () => widget.onSelect(phrase),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        // 短语编辑入口固定在内容底部
                        _buildEditEntry(colorScheme),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建浮层底部的短语编辑入口（分割线 + 菜单项）
  Widget _buildEditEntry(ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Divider(height: 1, color: colorScheme.outlineVariant),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: _PopupTile(
            icon: Icons.edit_outlined,
            label: '编辑短语',
            trailingChevron: true,
            onTap: widget.onEdit,
          ),
        ),
      ],
    );
  }
}

/// 浮层中的单行菜单项
class _PopupTile extends StatelessWidget {
  /// 左侧图标
  final IconData icon;

  /// 显示文本
  final String label;

  /// 是否在右侧显示进入箭头
  final bool trailingChevron;

  /// 点击回调
  final VoidCallback onTap;

  const _PopupTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailingChevron = false,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        // 不参与焦点争夺，避免点击时输入法收起
        canRequestFocus: false,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              if (trailingChevron) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
