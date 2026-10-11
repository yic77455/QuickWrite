import 'package:flutter/material.dart';
import 'package:quick_write/core/models/app_settings.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/widgets/qw_dialogs.dart';

/// 关闭主窗口行为的选择结果
class CloseActionChoice {
  /// 用户选择的行为，取值见 [AppSettings.closeActionExit] / [AppSettings.closeActionTray]
  final String action;

  /// 是否记住本次选择
  final bool remember;

  const CloseActionChoice({required this.action, required this.remember});
}

/// 显示关闭主窗口行为选择弹窗
///
/// 提供"退出程序"与"最小化至托盘"两个选项，并可勾选记住本次选择；
/// 用户点击取消或直接关闭弹窗时返回 null
Future<CloseActionChoice?> showCloseActionDialog({
  required BuildContext context,
}) {
  return showDialogBase<CloseActionChoice>(
    context: context,
    title: '关闭窗口',
    width: 420,
    height: 400,
    adaptiveHeight: true,
    content: const _CloseActionDialogContent(),
  );
}

/// 关闭主窗口行为选择弹窗内容
class _CloseActionDialogContent extends StatefulWidget {
  const _CloseActionDialogContent();

  @override
  State<_CloseActionDialogContent> createState() =>
      _CloseActionDialogContentState();
}

class _CloseActionDialogContentState extends State<_CloseActionDialogContent> {
  /// 是否记住本次选择
  bool _remember = false;

  /// 关闭弹窗并返回用户选择的行为
  void _choose(String action) {
    Navigator.of(context).pop(
      CloseActionChoice(action: action, remember: _remember),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 说明文字
          Text(
            '关闭窗口后，您希望如何处理？',
            textAlign: TextAlign.center,
            style: context.bodyLarge?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 18),
          // 退出程序选项
          _buildActionOption(
            context: context,
            icon: Icons.power_settings_new,
            title: '退出程序',
            description: '关闭所有窗口并结束程序运行',
            onTap: () => _choose(AppSettings.closeActionExit),
          ),
          const SizedBox(height: 10),
          // 最小化至托盘选项
          _buildActionOption(
            context: context,
            icon: Icons.keyboard_arrow_down,
            title: '最小化至托盘',
            description: '窗口隐藏到系统托盘，程序继续在后台运行',
            onTap: () => _choose(AppSettings.closeActionTray),
          ),
          const SizedBox(height: 14),
          // 记住本次选择
          InkWell(
            onTap: () => setState(() => _remember = !_remember),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Checkbox(
                    value: _remember,
                    onChanged: (value) =>
                        setState(() => _remember = value ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                  Text('记住我的选择', style: context.bodyMedium),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          // 取消按钮
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  /// 构建单个行为选项
  Widget _buildActionOption({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: context.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
