import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/qw_tooltip.dart';
import 'package:quick_write/shared/widgets/segmented_control.dart';

/// 结果区视图类型
enum NameResultTab {
  /// 本次生成结果
  results('生成结果'),

  /// 生成历史
  history('历史');

  /// 显示名称
  final String label;

  const NameResultTab(this.label);
}

/// 结果面板
///
/// 随机取名弹窗下方的结果区，通过顶部标签在"生成结果 / 历史"之间切换；
/// 名字以紧凑标签流式排布，点击任意名字即可复制到剪贴板。
class NameResultPanel extends StatelessWidget {
  /// 当前视图
  final NameResultTab tab;

  /// 视图切换回调
  final ValueChanged<NameResultTab> onTabChanged;

  /// 当前视图展示的名字列表
  final List<String> names;

  /// 复制名字回调
  final Future<void> Function(String name) onCopy;

  /// 清空当前视图回调（历史视图使用）
  final VoidCallback? onClear;

  /// 空列表时的提示文字
  final String emptyHint;

  const NameResultPanel({
    super.key,
    required this.tab,
    required this.onTabChanged,
    required this.names,
    required this.onCopy,
    required this.emptyHint,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 视图切换 + 数量 + 清空
        Row(
          children: [
            SizedBox(
              width: 168,
              child: SegmentedControl(
                labels: NameResultTab.values.map((t) => t.label).toList(),
                selectedIndex: NameResultTab.values.indexOf(tab),
                onChanged: (index) => onTabChanged(NameResultTab.values[index]),
              ),
            ),
            if (names.isNotEmpty) ...[
              const SizedBox(width: 12),
              Text(
                '${names.length} 个',
                style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
            const Spacer(),
            if (onClear != null && names.isNotEmpty)
              CursorTooltipTarget(
                tooltipContent: Text('清空${tab.label}'),
                child: IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        // 名字标签流
        Expanded(
          child: names.isEmpty
              ? Center(
                  child: Text(
                    emptyHint,
                    textAlign: TextAlign.center,
                    style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                )
              : SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final name in names)
                        _NameChip(name: name, onTap: () => onCopy(name)),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// 单个名字标签
///
/// 悬浮时高亮，点击即复制名字到剪贴板。
class _NameChip extends StatefulWidget {
  final String name;
  final VoidCallback onTap;

  const _NameChip({required this.name, required this.onTap});

  @override
  State<_NameChip> createState() => _NameChipState();
}

class _NameChipState extends State<_NameChip> {
  /// 标签内容的最小宽度参考字数
  static const int _minContentChars = 4;

  /// 鼠标是否悬浮在标签上
  bool _hovered = false;

  /// 计算参考字数在当前文字样式下的宽度
  ///
  /// 作为标签内容的最小宽度：字数不足时在标签内居中，超出时按内容自适应。
  double _resolveMinContentWidth(BuildContext context, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: '字' * _minContentChars, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = context.bodyMedium?.copyWith(color: colorScheme.onSurface);

    return CursorTooltipTarget(
      tooltipContent: const Text('点击复制'),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _hovered
                  ? colorScheme.primary.withValues(alpha: 0.12)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _hovered
                    ? colorScheme.primary.withValues(alpha: 0.4)
                    : colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: _resolveMinContentWidth(context, textStyle),
              ),
              child: Text(
                widget.name,
                textAlign: TextAlign.center,
                style: textStyle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
