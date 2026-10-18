import 'package:flutter/material.dart';

/// 移动端子页面标题栏
///
/// 在标题左侧提供返回按钮，与标题同行展示，标题下方可选展示说明文字，
/// 供云同步、回收站等子页面在移动端统一返回来源页面
class MobilePageHeader extends StatelessWidget {
  /// 页面标题
  final Widget title;

  /// 标题下方的说明文字（可选）
  final Widget? subtitle;

  /// 返回按钮点击回调
  final VoidCallback onBack;

  /// 返回按钮的占位宽度（贴合图标大小，避免图标与标题之间留出多余空白）
  static const double _backButtonWidth = 28;

  /// 返回按钮与标题之间的间距
  static const double _backButtonGap = 4;

  const MobilePageHeader({
    required this.title,
    required this.onBack,
    this.subtitle,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行：返回按钮置于标题左侧
        Row(
          children: [
            _buildBackButton(context),
            const SizedBox(width: _backButtonGap),
            title,
          ],
        ),
        // 说明文字
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          subtitle!,
        ],
      ],
    );
  }

  /// 构建返回按钮
  Widget _buildBackButton(BuildContext context) {
    return SizedBox(
      width: _backButtonWidth,
      height: 40,
      child: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: '返回',
        // 图标左对齐，使其与页面左侧留白对齐
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.zero,
        onPressed: onBack,
      ),
    );
  }
}
