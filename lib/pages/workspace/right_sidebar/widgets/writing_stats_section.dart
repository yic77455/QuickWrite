import 'package:flutter/material.dart';
import 'package:quick_write/core/providers/writing_session_tracker.dart';
import 'package:quick_write/core/services/cache_services/misc_cache_service.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 显示码字统计弹窗
///
/// 将工作台工具面板中的码字统计区块以弹窗形式展示。
/// [tracker] 为会话统计追踪器，为空时区块内展示占位提示
Future<void> showWritingStatsDialog({
  required BuildContext context,
  required WritingSessionTracker? tracker,
}) {
  return showDialogBase(
    context: context,
    title: '码字统计',
    width: 360,
    height: 480,
    adaptiveHeight: true,
    content: Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: WritingStatsSection(tracker: tracker, showTitle: false, showPasteToggle: false),
    ),
  );
}

/// 码字统计区块
///
/// 展示今日码字、本次码字、码字速度与时长等会话统计数据。
/// 标题行右侧附带"是否包含粘贴字数"开关，与码字统计界面共享同一状态。
/// [showTitle] 为 false 时隐藏内置标题，仅保留开关与统计卡片；
/// [showPasteToggle] 为 false 时隐藏"是否包含粘贴字数"开关
class WritingStatsSection extends StatefulWidget {
  /// 会话统计追踪器，为空时展示占位提示
  final WritingSessionTracker? tracker;

  /// 是否展示内置的"码字统计"标题
  final bool showTitle;

  /// 是否展示"是否包含粘贴字数"开关
  final bool showPasteToggle;

  const WritingStatsSection({
    super.key,
    required this.tracker,
    this.showTitle = true,
    this.showPasteToggle = true,
  });

  @override
  State<WritingStatsSection> createState() => _WritingStatsSectionState();
}

class _WritingStatsSectionState extends State<WritingStatsSection> {
  /// 是否包含粘贴字数（与码字统计界面共享同一状态）
  late bool _includePasteWords;

  @override
  void initState() {
    super.initState();
    _includePasteWords = MiscCacheService.instance.isStatsIncludePasteWords();
  }

  /// 切换是否包含粘贴字数
  ///
  /// 切换后实时影响后续的统计计算，但不会追溯调整已记录的数据
  void _toggleIncludePasteWords() {
    setState(() {
      _includePasteWords = !_includePasteWords;
    });
    MiscCacheService.instance.saveStatsIncludePasteWords(_includePasteWords);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tracker = widget.tracker;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行（可隐藏） + 粘贴字数开关（可隐藏）
        if (widget.showTitle || widget.showPasteToggle) ...[
          Row(
            children: [
              if (widget.showTitle) ...[
                Icon(Icons.insights_rounded, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  '码字统计',
                  style: context.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                ),
              ],
              const Spacer(),
              if (widget.showPasteToggle) _buildPasteToggle(colorScheme),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (tracker == null)
          _buildPlaceholder(context)
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

  /// 构建"是否包含粘贴字数"开关
  Widget _buildPasteToggle(ColorScheme colorScheme) {
    return CursorTooltipTarget(
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
    );
  }

  /// 构建统计区占位（追踪器未初始化时显示）
  Widget _buildPlaceholder(BuildContext context) {
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
