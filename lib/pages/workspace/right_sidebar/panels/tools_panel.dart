import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/writing_session_tracker.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/services/cache_services/misc_cache_service.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/widgets.dart';
import 'package:quick_write/pages/workspace/right_sidebar/widgets/book_info_section.dart';

/// 工具面板
///
/// 右侧边栏的工具面板，包含功能区和码字统计两个区域。
/// 功能区提供快捷工具入口（如随机取名）；
/// 码字统计区展示今日码字、本次码字、码字速度、码字时长、空闲时长等数据。
class ToolsPanel extends StatefulWidget {
  const ToolsPanel({super.key});

  @override
  State<ToolsPanel> createState() => _ToolsPanelState();
}

class _ToolsPanelState extends State<ToolsPanel> {
  /// 是否包含粘贴字数（与码字统计界面共享同一状态）
  bool _includePasteWords = true;

  @override
  void initState() {
    super.initState();
    _includePasteWords = MiscCacheService.instance.isStatsIncludePasteWords();
  }

  /// 切换是否包含粘贴字数
  ///
  /// 与码字统计界面共享同一缓存状态，切换后实时影响后续的统计计算，
  /// 但不会追溯调整已记录的数据。
  void _toggleIncludePasteWords() {
    setState(() {
      _includePasteWords = !_includePasteWords;
    });
    MiscCacheService.instance.saveStatsIncludePasteWords(_includePasteWords);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: colorScheme.surface.withValues(alpha: 0.3),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 功能区
            _buildFunctionSection(context),
            const SizedBox(height: 20),
            // 码字统计区
            _buildStatsSection(context),
            const SizedBox(height: 20),
            // 书籍信息区
            const BookInfoSection(),
          ],
        ),
      ),
    );
  }

  /// 构建分区标题（图标 + 文字）
  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: context.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  /// 构建功能区
  Widget _buildFunctionSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, '功能区', Icons.build_outlined),
        const SizedBox(height: 8),
        _buildRandomNameButton(context),
      ],
    );
  }

  /// 构建随机取名按钮卡片
  Widget _buildRandomNameButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(8),
        hoverColor: colorScheme.primary.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // 工具图标
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.casino_rounded, size: 22, color: colorScheme.primary),
              ),
              const SizedBox(width: 12),
              // 标题和描述
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '随机取名',
                      style: context.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text('一键生成角色姓名', style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              // 右侧箭头
              Icon(Icons.chevron_right_rounded, size: 20, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建码字统计区
  ///
  /// 标题栏右侧附带"是否包含粘贴字数"开关，与码字统计界面共享同一状态。
  /// 统计数据通过 [ListenableBuilder] 监听 [WritingSessionTracker]，
  /// 仅在统计数据变化时局部重建，不影响工作台其他区域。
  Widget _buildStatsSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tracker = context.watch<WorkspaceProvider>().sessionTracker;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行 + 粘贴字数开关
        Row(
          children: [
            Icon(Icons.insights_rounded, size: 16, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              '码字统计',
              style: context.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
            ),
            const Spacer(),
            // 粘贴字数开关
            CursorTooltipTarget(
              showTooltip: true,
              tooltipContent: Text('是否包含粘贴字数', style: context.bodySmall),
              child: IconButton(
                icon: const Icon(Icons.content_paste_rounded),
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                color: _includePasteWords ? colorScheme.primary : colorScheme.onSurfaceVariant,
                style: IconButton.styleFrom(
                  backgroundColor: _includePasteWords ? colorScheme.primary.withValues(alpha: 0.1) : Colors.transparent,
                ),
                onPressed: _toggleIncludePasteWords,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (tracker == null)
          _buildStatsPlaceholder(context)
        else
          ListenableBuilder(
            listenable: tracker,
            builder: (context, _) {
              return Column(
                children: [
                  // 今日码字（突出显示）
                  _StatCard(
                    icon: Icons.today_rounded,
                    label: '今日码字',
                    value: _formatNumber(tracker.todayWords),
                    unit: '字',
                    isHero: true,
                  ),
                  const SizedBox(height: 8),
                  // 次要统计项（2列网格）
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.edit_note_rounded,
                          label: '本次码字',
                          value: _formatNumber(tracker.sessionWords),
                          unit: '字',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.speed_rounded,
                          label: '码字速度',
                          value: _formatNumber(tracker.writingSpeed),
                          unit: '字/分',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.schedule_rounded,
                          label: '码字时长',
                          durationSeconds: tracker.sessionDurationSeconds,
                          autoFit: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.local_cafe_outlined,
                          label: '空闲时长',
                          durationSeconds: tracker.idleDurationSeconds,
                          autoFit: true,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
      ],
    );
  }

  /// 构建统计区占位（追踪器未初始化时显示）
  Widget _buildStatsPlaceholder(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text('统计数据加载中...', style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
      ),
    );
  }
}

/// 格式化数字，添加千位分隔符
///
/// 例如：3256 → "3,256"，-1024 → "-1,024"
String _formatNumber(int n) {
  final isNegative = n < 0;
  final abs = n.abs();
  final formatted = abs.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
  return isNegative ? '-$formatted' : formatted;
}

/// 统计数据卡片
///
/// 用于展示单项统计数据，包含图标、数值和标签。
/// [isHero] 为 true 时使用更突出的样式（用于今日码字等核心指标）。
/// [durationSeconds] 非空时按时长模式渲染，数字粗体、单位普通字重。
/// [autoFit] 为 true 时数值文字随容器宽度自适应缩放。
class _StatCard extends StatelessWidget {
  /// 卡片图标
  final IconData icon;

  /// 数据标签
  final String label;

  /// 数据数值
  final String value;

  /// 数值单位
  final String unit;

  /// 是否使用突出样式
  final bool isHero;

  /// 时长秒数（非空时按时长模式渲染，忽略 [value]/[unit]）
  final int? durationSeconds;

  /// 数值是否随容器宽度自适应缩放
  final bool autoFit;

  const _StatCard({
    required this.icon,
    required this.label,
    this.value = '',
    this.unit = '',
    this.isHero = false,
    this.durationSeconds,
    this.autoFit = false,
  });

  /// 构建时长富文本（数字粗体 + 单位普通字重）
  Widget _buildDurationRichText(BuildContext context) {
    final totalSeconds = durationSeconds!;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    final colorScheme = Theme.of(context).colorScheme;
    final baseStyle = context.titleLarge?.copyWith(color: colorScheme.onSurface);
    final numberStyle = baseStyle?.copyWith(fontWeight: FontWeight.w600);
    final unitStyle = baseStyle?.copyWith(fontWeight: FontWeight.normal);

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: hours.toString().padLeft(2, '0'), style: numberStyle),
          TextSpan(text: ' 时 ', style: unitStyle),
          TextSpan(text: minutes.toString().padLeft(2, '0'), style: numberStyle),
          TextSpan(text: ' 分 ', style: unitStyle),
          TextSpan(text: seconds.toString().padLeft(2, '0'), style: numberStyle),
          TextSpan(text: ' 秒', style: unitStyle),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 时长模式：数字粗体 + 单位普通字重的富文本
    // 普通模式：数值 + 单位
    final Widget valueWidget;
    if (durationSeconds != null) {
      valueWidget = _buildDurationRichText(context);
    } else {
      valueWidget = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            value,
            style: (isHero ? context.headlineSmall : context.titleLarge)?.copyWith(
              fontWeight: isHero ? FontWeight.w700 : FontWeight.w600,
              color: isHero ? colorScheme.primary : colorScheme.onSurface,
            ),
          ),
          if (unit.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(unit, style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
          ],
        ],
      );
    }

    return Container(
      padding: EdgeInsets.all(isHero ? 16 : 14),
      decoration: BoxDecoration(
        color: isHero
            ? colorScheme.primary.withValues(alpha: 0.08)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 图标 + 标签
          Row(
            children: [
              Icon(icon, size: 16, color: isHero ? colorScheme.primary : colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                label,
                style: context.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: isHero ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // autoFit 时用 FittedBox 包裹，使数值文字在容器宽度内自适应缩放
          if (autoFit)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: valueWidget,
            )
          else
            valueWidget,
        ],
      ),
    );
  }
}
