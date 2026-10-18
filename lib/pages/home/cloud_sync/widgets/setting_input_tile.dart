import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/core/utils/typography_extension.dart';

/// 带文本输入框的设置项
///
/// 布局与 [SettingTile] 保持一致：左侧图标容器与标题说明，
/// 右侧为固定宽度的文本输入框，适用于服务器地址、账号等配置项的填写；
/// 移动端屏幕较窄，改为标题在上、输入框在下占满整行的排列方式，避免输入框溢出
class SettingInputTile extends StatelessWidget {
  /// 图标
  final IconData icon;

  /// 标题
  final String title;

  /// 副标题（填写说明）
  final String? subtitle;

  /// 输入框控制器
  final TextEditingController controller;

  /// 输入框占位提示文本
  final String? hintText;

  /// 是否以密码模式显示（遮挡输入内容）
  final bool obscureText;

  /// 输入框右侧附加控件（如密码可见性切换按钮）
  final Widget? suffixIcon;

  /// 图标强调色，为 null 时使用主题主色
  final Color? accentColor;

  const SettingInputTile({
    super.key,
    required this.icon,
    required this.title,
    required this.controller,
    this.subtitle,
    this.hintText,
    this.obscureText = false,
    this.suffixIcon,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveAccent = accentColor ?? colorScheme.primary;

    // 移动端：标题行与输入框上下排列，输入框自适应卡片宽度
    if (PlatformCapabilities.isMobile) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIconBox(effectiveAccent),
                const SizedBox(width: 14),
                Expanded(child: _buildTitleColumn(context, colorScheme)),
              ],
            ),
            const SizedBox(height: 12),
            _buildInputField(),
          ],
        ),
      );
    }

    // 桌面端：图标、标题与固定宽度输入框同行排列
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          _buildIconBox(effectiveAccent),
          const SizedBox(width: 14),
          // 标题与副标题
          Expanded(child: _buildTitleColumn(context, colorScheme)),
          // 右侧输入框
          SizedBox(width: 300, child: _buildInputField()),
        ],
      ),
    );
  }

  /// 图标容器：使用强调色的低透明度背景
  Widget _buildIconBox(Color accent) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: accent),
    );
  }

  /// 标题与副标题
  Widget _buildTitleColumn(BuildContext context, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: context.titleLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: context.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  /// 文本输入框
  Widget _buildInputField() {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      // 点击输入框以外的区域（如测试连接、连接、立即同步等按钮）时取消输入框焦点，
      // 移动端平台默认不处理点击外部区域的行为
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: InputDecoration(
        hintText: hintText,
        suffixIcon: suffixIcon,
      ),
    );
  }
}
