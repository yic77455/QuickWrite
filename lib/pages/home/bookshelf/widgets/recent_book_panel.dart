import 'package:flutter/material.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'hero_cover_item.dart';
import 'info_row.dart';
import 'workspace_opener.dart';

/// 左侧面板组件
/// 
/// 展示最近编辑的书籍信息，包括大封面、书名、字数、章节等
class RecentBookPanel extends StatelessWidget {
  final BookModel recentBook;

  const RecentBookPanel({super.key, required this.recentBook});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Text(
          '最近编辑',
          style: context.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 24),

        // 使用 LayoutBuilder 获取最大可用高度
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 定义理想中左侧面板需要多大空间
              // 宽度死锁在 320
              // 高度预估：封面高度 (320*4/3 = 426) + 文字和按钮的高度 (约 350) = 780 左右
              const double idealWidth = 320.0;
              const double idealHeight = 780.0;

              // 使用 FittedBox，让这个理想尺寸的面板自动缩放以适应窗口大小
              // BoxFit.scaleDown 表示：如果窗口很大，就保持原样；如果窗口太小，就等比缩小
              return FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter, // 缩放时靠顶部对齐
                child: SizedBox(
                  width: idealWidth,
                  height: idealHeight,
                  // 加个 Padding 让悬停阴影有空间
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 大封面图片
                        HeroCoverItem(
                          book: recentBook,
                          onTap: () => openWorkspace(
                            context: context,
                            bookId: recentBook.uuid,
                            bookTitle: recentBook.title,
                          ),
                        ),

                        const SizedBox(height: 32),

                        // 书籍信息区域
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                recentBook.title,
                                style: context.displayLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  height: 1.3,
                                  letterSpacing: 1.5,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 20),
                              InfoRow(
                                icon: Icons.text_snippet_rounded,
                                label: '总字数：',
                                value: recentBook.displayWordCount,
                              ),
                              const SizedBox(height: 8),
                              InfoRow(
                                icon: Icons.menu_book_rounded,
                                label: '最新进度：',
                                value: recentBook.latestChapter,
                              ),
                              const SizedBox(height: 8),
                              InfoRow(
                                icon: Icons.access_time_filled_rounded,
                                label: '上次编辑：',
                                value: recentBook.displayLastEditTime,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 40),

                        // 继续创作按钮
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(50),
                              ),
                            ),
                            onPressed: () => openWorkspace(
                              context: context,
                              bookId: recentBook.uuid,
                              bookTitle: recentBook.title,
                            ),
                            icon: const Icon(Icons.edit_note, size: 24),
                            label: Text(
                              '继续创作',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
