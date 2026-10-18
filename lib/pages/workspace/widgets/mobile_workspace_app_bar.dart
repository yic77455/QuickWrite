import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/constants/material_icons.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/pages/workspace/toolbar/widgets/mobile_format_card.dart';
import 'package:quick_write/pages/workspace/toolbar/widgets/mobile_tools_card.dart';

/// 移动端工作台顶部操作栏
///
/// 不承载标题，仅作为操作入口条：左侧为返回书架，右侧依次为格式设置、撤销、
/// 恢复、目录、工具。所有入口平时都是无边框、无底色的裸图标按钮，左右留白对称，
/// 并关闭水波纹与按压高亮，保持与主页面一致的简洁观感；
/// 入口对应的卡片或抽屉处于打开状态时，该入口以主色高亮显示。
/// 格式设置与工具入口会分别在顶部操作栏下方弹出对应卡片。
class MobileWorkspaceAppBar extends StatefulWidget {
  /// 内容区高度（不含顶部状态栏安全区）
  static const double contentHeight = 52;

  /// 图标按钮的点击热区边长
  static const double _buttonSize = 44;

  /// 图标大小
  static const double _iconSize = 22;

  /// 操作栏左右留白
  static const double _horizontalPadding = 4;

  /// 不可用状态下图标的透明度
  static const double _disabledOpacity = 0.38;

  /// 卡片与顶部操作栏之间的间距
  static const double _cardGap = 0;

  /// 卡片与屏幕底部之间的留白，作为卡片高度自适应时的下边界
  static const double _cardBottomMargin = 24;

  /// 返回书架
  final VoidCallback onBack;

  /// 撤销
  final VoidCallback onUndo;

  /// 恢复
  final VoidCallback onRedo;

  /// 打开目录抽屉
  final VoidCallback onContents;

  /// 当前是否可撤销，false 时撤销按钮呈禁用态
  final bool canUndo;

  /// 当前是否可重做，false 时恢复按钮呈禁用态
  final bool canRedo;

  /// 目录抽屉当前是否打开，打开时目录入口高亮
  final bool isContentsSelected;

  const MobileWorkspaceAppBar({
    super.key,
    required this.onBack,
    required this.onUndo,
    required this.onRedo,
    required this.onContents,
    this.canUndo = false,
    this.canRedo = false,
    this.isContentsSelected = false,
  });

  @override
  State<MobileWorkspaceAppBar> createState() => _MobileWorkspaceAppBarState();
}

class _MobileWorkspaceAppBarState extends State<MobileWorkspaceAppBar> {
  /// 格式设置卡片是否打开，打开期间格式设置入口保持高亮
  bool _isFormatCardOpen = false;

  /// 工具卡片是否打开，打开期间工具入口保持高亮
  bool _isToolsCardOpen = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 顶栏底色取主题的顶部栏颜色（与桌面端标题栏保持一致），随主题切换同步更新
    final backgroundColor = theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface;

    return ColoredBox(
      color: backgroundColor,
      child: SafeArea(
        top: true,
        bottom: false,
        left: false,
        right: false,
        child: SizedBox(
          height: MobileWorkspaceAppBar.contentHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: MobileWorkspaceAppBar._horizontalPadding),
            child: Row(
              children: [
                // 返回书架
                _BarIconButton(icon: Icons.arrow_back, tooltip: '返回书架', onPressed: widget.onBack),

                const Spacer(),

                // 右侧操作入口，等距排列
                _BarIconButton(
                  icon: Icons.text_fields_rounded,
                  tooltip: '格式设置',
                  isSelected: _isFormatCardOpen,
                  onPressed: () => _showFormatCard(context),
                ),
                _BarIconButton(
                  icon: MaterialIcons.undo,
                  tooltip: '撤销',
                  onPressed: widget.canUndo ? widget.onUndo : null,
                ),
                _BarIconButton(
                  icon: MaterialIcons.redo,
                  tooltip: '恢复',
                  onPressed: widget.canRedo ? widget.onRedo : null,
                ),
                _BarIconButton(
                  icon: Icons.article_outlined,
                  tooltip: '目录',
                  isSelected: widget.isContentsSelected,
                  onPressed: widget.onContents,
                ),
                _BarIconButton(
                  icon: Icons.dashboard_rounded,
                  tooltip: '工具',
                  isSelected: _isToolsCardOpen,
                  onPressed: () => _showToolsCard(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 计算卡片在顶部操作栏下方的弹出位置与可用高度
  ///
  /// 卡片靠屏幕右侧显示，顶端对齐顶部操作栏的下边缘；
  /// [maxWidth] 为卡片声明的最大宽度，[screenMargin] 为卡片与屏幕左右边缘的最小留白。
  /// 可用高度取操作栏下边缘与屏幕底部留白之间的剩余空间，超出部分由卡片内部滚动
  ({double left, double top, double maxHeight})? _resolveCardLayout(
    BuildContext context, {
    required double maxWidth,
    required double screenMargin,
  }) {
    final barBox = context.findRenderObject() as RenderBox?;
    if (barBox == null) return null;

    final screenSize = MediaQuery.sizeOf(context);
    final cardWidth = math.min(maxWidth, screenSize.width - screenMargin * 2);
    final cardTop =
        barBox.localToGlobal(Offset(0, barBox.size.height)).dy + MobileWorkspaceAppBar._cardGap;

    // 卡片下边缘最多落到「屏幕底部减去留白」处，保证卡片不会超出屏幕
    final double maxHeight =
        math.max(0.0, screenSize.height - cardTop - MobileWorkspaceAppBar._cardBottomMargin);

    return (
      left: screenSize.width - screenMargin - cardWidth,
      top: cardTop,
      maxHeight: maxHeight,
    );
  }

  /// 在顶部操作栏下方弹出格式设置卡片
  ///
  /// 卡片以透明遮罩的弹窗承载：点击卡片之外的区域仅关闭卡片，
  /// 并拦截该次点击，避免误触浮层下方的编辑器。
  /// 卡片打开期间对应入口保持高亮，关闭后恢复
  Future<void> _showFormatCard(BuildContext context) async {
    final layout = _resolveCardLayout(
      context,
      maxWidth: MobileFormatCard.maxWidth,
      screenMargin: MobileFormatCard.screenMargin,
    );
    if (layout == null) return;

    // 当前标签页是否使用大纲编辑器，决定卡片作用于正文还是大纲
    final bool isOutline = context.read<WorkspaceProvider>().currentTab?.usesOutlineEditor ?? false;

    setState(() => _isFormatCardOpen = true);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      barrierLabel: '关闭格式设置',
      pageBuilder: (_, _, _) => Stack(
        children: [
          Positioned(
            left: layout.left,
            top: layout.top,
            child: MobileFormatCard(isOutline: isOutline, maxHeight: layout.maxHeight),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _isFormatCardOpen = false);
  }

  /// 在顶部操作栏下方弹出工具卡片
  ///
  /// 卡片以透明遮罩的弹窗承载：点击卡片之外的区域仅关闭卡片，并拦截该次点击，
  /// 避免误触浮层下方的编辑器。卡片打开期间对应入口保持高亮，
  /// 卡片关闭后执行所选动作
  Future<void> _showToolsCard(BuildContext context) async {
    final layout = _resolveCardLayout(
      context,
      maxWidth: MobileToolsCard.maxWidth,
      screenMargin: MobileToolsCard.screenMargin,
    );
    if (layout == null) return;

    // 卡片通过弹窗返回值回传所选动作，遮罩点击关闭时返回 null
    setState(() => _isToolsCardOpen = true);
    final action = await showGeneralDialog<MobileToolAction>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      barrierLabel: '关闭工具',
      pageBuilder: (dialogContext, _, _) => Stack(
        children: [
          Positioned(
            left: layout.left,
            top: layout.top,
            child: MobileToolsCard(
              onSelected: (selected) => Navigator.of(dialogContext).pop(selected),
              maxHeight: layout.maxHeight,
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _isToolsCardOpen = false);

    if (action == null || !context.mounted) return;
    await handleMobileToolAction(context, action);
  }
}

/// 顶栏图标按钮
///
/// 统一点击热区与图标尺寸，仅展示图标本身：无边框、无底色、无分隔线，
/// 并关闭 Material 原生的水波纹、按压高亮与悬停色。
/// [onPressed] 为 null 时自动进入禁用态，图标降低不透明度以示不可用；
/// [isSelected] 为 true 时图标以主色显示表示选中
class _BarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool isSelected;

  const _BarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return IconButton(
      icon: Icon(icon, size: MobileWorkspaceAppBar._iconSize),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: MobileWorkspaceAppBar._buttonSize,
        height: MobileWorkspaceAppBar._buttonSize,
      ),
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          // 选中态使用主色
          if (isSelected) return colorScheme.primary;
          // 不可用状态降低不透明度，与可用状态形成区分
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurfaceVariant.withValues(alpha: MobileWorkspaceAppBar._disabledOpacity);
          }
          return colorScheme.onSurfaceVariant;
        }),
        // 关闭水波纹、按压高亮与悬停色，点击时不出现任何 Material 原生动效
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      onPressed: onPressed,
    );
  }
}
