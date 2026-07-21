import 'package:flutter/material.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 大封面组件
/// 
/// 用于左侧面板展示最近编辑的书籍，悬停时有放大和阴影效果
class HeroCoverItem extends StatefulWidget {
  final BookModel book;
  final VoidCallback onTap;

  const HeroCoverItem({super.key, required this.book, required this.onTap});

  @override
  State<HeroCoverItem> createState() => _HeroCoverItemState();
}

class _HeroCoverItemState extends State<HeroCoverItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300), // 大封面动画稍微平缓一点
          curve: Curves.easeOutCubic,
          // 悬停时：放大 4% 并向上轻微浮动
          transform: _isHovered
              ? (Matrix4.identity()
                  ..scaleByDouble(1.03, 1.03, 1.0, 1.0)
                  ..setTranslationRaw(-2.0, -4.0, 0.0))
              : Matrix4.identity(),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            // 阴影也随之加深
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 40,
                      offset: const Offset(0, 20),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 30,
                      offset: const Offset(0, 15),
                    ),
                  ],
          ),
          // 裁剪放在这里，这样圆角才不会被破坏
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: widget.book.coverPath.isNotEmpty
                  ? ThemedCoverImage(
                      coverPath: widget.book.coverPath,
                      cacheKey: widget.book.updatedAt.millisecondsSinceEpoch.toString(),
                      errorBuilder: (context, error, stackTrace) => _buildDefaultCover(),
                    )
                  : _buildDefaultCover(),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建默认封面（无封面或加载失败时显示）
  Widget _buildDefaultCover() {
    return DefaultCover.buildThemed(
      title: widget.book.title,
      context: context,
      fontSize: 32,
      borderRadius: 16,
    );
  }
}
