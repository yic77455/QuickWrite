import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/cloud_sync_provider.dart';
import 'package:quick_write/core/utils/typography_extension.dart';

/// 云同步 - 同步待确认横幅
///
/// 同步因风险较高被暂停时显示在页面顶部，列出暂停的具体原因与处理方式，
/// 让用户清楚侧边栏红点提示的由来；没有待确认内容时不占任何空间
class SyncRiskBanner extends StatelessWidget {
  const SyncRiskBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final risk = context.watch<CloudSyncProvider>().pendingRisk;
    if (risk == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.tertiary;

    return Padding(
      // 横幅可自行隐藏，与下方分组的间距由自身提供，避免隐藏后留下空档
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.report_problem_outlined, color: accent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '同步已暂停，等待你的确认',
                    style: context.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    risk.reason ?? '本次同步改动较大，确认后才会执行',
                    style: context.bodySmall?.copyWith(height: 1.6),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '在下方「数据同步」中点击「立即同步」即可重新发起，确认之前不会执行任何文件传输与云端删除。',
                    style: context.bodySmall?.copyWith(
                      height: 1.6,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}