import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/dialogs/import_book_dialog.dart';
import 'package:quick_write/shared/dialogs/new_book_dialog.dart';

/// 空书架状态组件
/// 
/// 当书架中没有书籍时显示此组件，引导用户创建第一本书或导入作品
class EmptyBookshelf extends StatelessWidget {
  const EmptyBookshelf({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 空状态插画
            Icon(
              Icons.menu_book_rounded,
              size: 120,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 24),
            Text(
              '你的书架空空如也',
              style: context.displaySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '点击下方按钮，开始你的第一部旷世巨作吧！',
              style: context.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 48),

            // 按钮区域（竖向排列）
            Column(
              children: [
                // 新建小说按钮
                SizedBox(
                  height: 48,
                  width: 260,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => showNewBookDialog(context),
                    icon: const Icon(Icons.add, size: 24),
                    label: Text(
                      '新建小说',
                      style: const TextStyle(
                        fontSize: 18,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // 导入作品按钮
                SizedBox(
                  height: 48,
                  width: 260,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => showImportBookDialog(context),
                    icon: const Icon(Icons.file_upload_outlined, size: 24),
                    label: Text(
                      '导入作品',
                      style: const TextStyle(
                        fontSize: 18,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
