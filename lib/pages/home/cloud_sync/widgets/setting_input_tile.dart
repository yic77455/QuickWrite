import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';

/// 带文本输入框的设置项
///
/// 布局与 [SettingTile] 保持一致：左侧图标容器与标题说明，
/// 右侧为固定宽度的文本输入框，适用于服务器地址、账号等配置项的填写
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          // 图标容器：使用强调色的低透明度背景
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: effectiveAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: effectiveAccent),
          ),
          const SizedBox(width: 14),
          // 标题与副标题
          Expanded(
            child: Column(
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
            ),
          ),
          // 右侧输入框
          SizedBox(
            width: 300,
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              decoration: InputDecoration(
                hintText: hintText,
                suffixIcon: suffixIcon,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
