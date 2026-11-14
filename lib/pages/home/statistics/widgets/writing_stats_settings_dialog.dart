import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quick_write/core/providers/writing_stats_provider.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 显示码字统计设置弹窗
///
/// 集中管理码字统计的三项设置：是否包含粘贴字数、是否包含设定字数、
/// 以及空闲判定时间。
Future<void> showWritingStatsSettingsDialog({
  required BuildContext context,
  required WritingStatsProvider provider,
}) {
  return showDialogBase(
    context: context,
    title: '统计设置',
    width: 380,
    height: 320,
    adaptiveHeight: true,
    content: _WritingStatsSettingsContent(provider: provider),
  );
}

/// 统计设置弹窗内容
class _WritingStatsSettingsContent extends StatefulWidget {
  /// 码字统计 Provider，三项设置均通过它读写
  final WritingStatsProvider provider;

  const _WritingStatsSettingsContent({required this.provider});

  @override
  State<_WritingStatsSettingsContent> createState() =>
      _WritingStatsSettingsContentState();
}

class _WritingStatsSettingsContentState
    extends State<_WritingStatsSettingsContent> {
  /// 空闲判定时间的最小值（秒）
  static const int _minIdleSeconds = 1;

  /// 空闲判定时间的最大值（秒）
  static const int _maxIdleSeconds = 3600;

  /// 空闲判定时间输入框控制器
  late final TextEditingController _idleController;

  /// 空闲判定时间输入框焦点节点（失焦时校正数值）
  late final FocusNode _idleFocusNode;

  @override
  void initState() {
    super.initState();
    _idleController = TextEditingController(
      text: widget.provider.idleThresholdSeconds.toString(),
    );
    _idleFocusNode = FocusNode()..addListener(_handleIdleFocusChanged);
  }

  @override
  void dispose() {
    // 先移除焦点监听，避免销毁过程中触发数值校正
    _idleFocusNode.removeListener(_handleIdleFocusChanged);
    _idleFocusNode.dispose();
    _idleController.dispose();
    super.dispose();
  }

  /// 空闲判定时间输入变化
  ///
  /// 输入合法数值时立即保存，非法或超出范围时等待失焦统一校正
  void _handleIdleChanged(String text) {
    final int? seconds = int.tryParse(text);
    if (seconds == null) return;
    if (seconds < _minIdleSeconds || seconds > _maxIdleSeconds) return;
    widget.provider.setIdleThresholdSeconds(seconds);
  }

  /// 空闲判定时间输入框失焦时校正数值
  void _handleIdleFocusChanged() {
    if (_idleFocusNode.hasFocus) return;

    final int? seconds = int.tryParse(_idleController.text);
    // 输入为空或非法时恢复为已保存的值
    if (seconds == null) {
      _idleController.text = widget.provider.idleThresholdSeconds.toString();
      return;
    }
    // 超出范围时收敛到允许区间并写回输入框
    final int clamped = seconds.clamp(_minIdleSeconds, _maxIdleSeconds).toInt();
    _idleController.text = clamped.toString();
    widget.provider.setIdleThresholdSeconds(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.provider,
      builder: (context, _) {
        final provider = widget.provider;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SettingTile(
                icon: Icons.content_paste_rounded,
                title: '包含粘贴字数',
                subtitle: '统计时计入粘贴产生的字数',
                trailing: QwSwitch(
                  value: provider.includePasteWords,
                  onChanged: (_) => provider.toggleIncludePasteWords(),
                ),
              ),
              const _SettingDivider(),
              _SettingTile(
                icon: Icons.format_list_bulleted,
                title: '包含设定字数',
                subtitle: '开启后编辑设定项产生的字数计入统计',
                trailing: QwSwitch(
                  value: provider.includeSettingWords,
                  onChanged: provider.setIncludeSettingWords,
                ),
              ),
              const _SettingDivider(),
              _SettingTile(
                icon: Icons.local_cafe_outlined,
                title: '空闲判定时间',
                subtitle: '超过该时间无编辑活动即视为空闲',
                trailing: _buildIdleInput(context),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 构建空闲判定时间输入框
  Widget _buildIdleInput(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final inputTheme = Theme.of(context).inputDecorationTheme;

    // 以主题输入框边框为基础收小圆角，保留启用、聚焦等状态原有的边框颜色
    OutlineInputBorder smallRadius(InputBorder? border) {
      final BorderRadius radius = BorderRadius.circular(6);
      return border is OutlineInputBorder
          ? border.copyWith(borderRadius: radius)
          : OutlineInputBorder(borderRadius: radius);
    }

    return SizedBox(
      width: 92,
      child: TextField(
        controller: _idleController,
        focusNode: _idleFocusNode,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        onChanged: _handleIdleChanged,
        onSubmitted: (_) => _idleFocusNode.unfocus(),
        style: context.bodyMedium,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          suffixText: '秒',
          suffixStyle: context.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          border: smallRadius(inputTheme.border),
          enabledBorder: smallRadius(inputTheme.enabledBorder),
          focusedBorder: smallRadius(inputTheme.focusedBorder),
        ),
      ),
    );
  }
}

/// 统计设置项
///
/// 左侧图标 + 标题说明，右侧放置开关或输入控件。
class _SettingTile extends StatelessWidget {
  /// 设置项图标
  final IconData icon;

  /// 设置项标题
  final String title;

  /// 设置项说明
  final String subtitle;

  /// 右侧控件
  final Widget trailing;

  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 图标容器
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: colorScheme.primary),
          ),
          const SizedBox(width: 12),
          // 标题与说明
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: context.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

/// 设置项之间的细分割线
class _SettingDivider extends StatelessWidget {
  const _SettingDivider();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 44),
      child: Divider(
        height: 1,
        thickness: 1,
        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
      ),
    );
  }
}
