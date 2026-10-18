import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/core/utils/typography_extension.dart';

/// 字数浮窗
///
/// 移动端叠加在编辑区上的一层半透明浮窗，实时显示当前标签页字数；
/// 开启码字速度后额外显示一行码字速度。显示位置由设置决定，
/// 位于底部时随编辑区一同被键盘上推。浮窗不参与点击，不影响正文操作。
class WordCountFloatingWindow extends StatefulWidget {
  const WordCountFloatingWindow({super.key});

  @override
  State<WordCountFloatingWindow> createState() => _WordCountFloatingWindowState();
}

class _WordCountFloatingWindowState extends State<WordCountFloatingWindow> {
  /// 浮窗与编辑区边缘的间距
  static const double _edgeMargin = 12;

  /// 浮窗背景不透明度（半透明效果）
  static const double _backgroundOpacity = 0.72;

  @override
  void initState() {
    super.initState();
    // 设置变化（开关、显示位置、码字速度）需要重新构建以应用
    SettingsService.instance.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  /// 处理设置变化
  void _onSettingsChanged() {
    if (mounted) {
      setState(() {
        // 重新构建以应用新的设置
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 移动端专属功能，桌面端不显示
    if (!PlatformCapabilities.isMobile) return const SizedBox.shrink();
    // 未开启时不显示
    if (!SettingsService.instance.wordCountFloatingEnabled) return const SizedBox.shrink();

    final provider = context.watch<WorkspaceProvider>();
    final tab = provider.currentTab;
    // 没有打开的标签页时不显示
    if (tab == null) return const SizedBox.shrink();

    // 码字速度开启时需同时监听会话追踪器，随其每秒刷新
    final tracker = provider.sessionTracker;
    final speedEnabled = SettingsService.instance.wordCountFloatingSpeedEnabled;
    final Listenable listenable = speedEnabled && tracker != null
        ? Listenable.merge([provider.wordCountNotifier, tracker])
        : provider.wordCountNotifier;

    // 计算浮窗贴靠的四角位置
    final position = SettingsService.instance.wordCountFloatingPosition;
    final bool alignTop = position == 'topLeft' || position == 'topRight';
    final bool alignLeft = position == 'topLeft' || position == 'bottomLeft';

    return Positioned(
      top: alignTop ? _edgeMargin : null,
      bottom: alignTop ? null : _edgeMargin,
      left: alignLeft ? _edgeMargin : null,
      right: alignLeft ? null : _edgeMargin,
      child: IgnorePointer(
        child: ListenableBuilder(
          listenable: listenable,
          builder: (context, _) => _buildWindow(
            context,
            tab.wordCount,
            speedEnabled ? (tracker?.writingSpeed ?? 0) : null,
          ),
        ),
      ),
    );
  }

  /// 构建浮窗内容
  ///
  /// [writingSpeed] 非空时额外渲染一行码字速度
  Widget _buildWindow(BuildContext context, int wordCount, int? writingSpeed) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        // 半透明底色，保留正文可见
        color: colorScheme.surface.withValues(alpha: _backgroundOpacity),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 本章字数
          _buildRow(
            context,
            icon: Icons.text_fields_rounded,
            label: '字数',
            value: '$wordCount 字',
          ),
          if (writingSpeed != null) ...[
            const SizedBox(height: 4),
            // 码字速度
            _buildRow(
              context,
              icon: Icons.speed_rounded,
              label: '速度',
              value: '$writingSpeed 字/分',
            ),
          ],
        ],
      ),
    );
  }

  /// 构建单行统计（图标 + 标签 + 数值）
  Widget _buildRow(BuildContext context, {required IconData icon, required String label, required String value}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colorScheme.primary),
        const SizedBox(width: 6),
        Text(label, style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
        const SizedBox(width: 8),
        Text(
          value,
          style: context.bodyMedium?.copyWith(color: colorScheme.onSurface, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
