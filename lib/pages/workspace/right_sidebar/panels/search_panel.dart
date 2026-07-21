import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/utils/ime_cursor_fixer.dart';
import 'package:quick_write/core/utils/typography_extension.dart';

/// 全文搜索面板
///
/// 在右侧边栏中提供全文搜索功能，支持跨章节搜索关键词，
/// 显示匹配结果列表，点击可跳转到对应章节的匹配位置
class SearchPanel extends StatefulWidget {
  const SearchPanel({super.key});

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  /// 搜索输入控制器
  final TextEditingController _searchController = TextEditingController();

  /// 搜索输入焦点节点
  final FocusNode _searchFocusNode = FocusNode();

  /// 防抖定时器
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    // 初始化时填充已有的搜索关键词
    final provider = context.read<WorkspaceProvider>();
    _searchController.text = provider.globalSearchQuery;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// 处理搜索输入变化
  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        context.read<WorkspaceProvider>().updateGlobalSearchQuery(value);
      }
    });
  }

  /// 清空搜索内容
  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    context.read<WorkspaceProvider>().updateGlobalSearchQuery('');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: colorScheme.surface.withValues(alpha: 0.3),
      child: Column(
        children: [
          // 搜索输入区域
          _buildSearchInput(context),

          // 分隔线
          Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),

          // 搜索结果区域
          Expanded(child: _buildSearchResults(context)),
        ],
      ),
    );
  }

  /// 构建搜索输入区域
  Widget _buildSearchInput(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final provider = context.watch<WorkspaceProvider>();

    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 搜索输入框
          ImeCursorFixerWrapper(
            controller: _searchController,
            focusNode: _searchFocusNode,
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _onSearchChanged,
              style: context.bodyMedium,
              decoration: InputDecoration(
                hintText: '搜索全部章节...',
                hintStyle: context.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  height: 1.8,
                ),
                prefixIcon: Icon(Icons.search_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                suffixIcon: _searchController.text.isNotEmpty
                    ? Padding(
                          padding: const EdgeInsets.all(8),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: IconButton(
                              onPressed: _clearSearch,
                              tooltip: '清空内容',
                              icon: Icon(Icons.close_rounded, size: 16),
                              padding: EdgeInsets.zero,
                              color: colorScheme.onSurfaceVariant,
                              hoverColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.08),
                              highlightColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.12),
                            ),
                          ),
                        )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 结果统计
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _buildResultSummary(context, provider),
          ),
        ],
      ),
    );
  }

  /// 构建结果统计文本
  Widget _buildResultSummary(BuildContext context, WorkspaceProvider provider) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalMatches = provider.globalSearchResults.fold<int>(0, (sum, r) => sum + r.totalMatches);
    final chapterCount = provider.globalSearchResults.length;

    return Text(
      '共搜索到 $chapterCount 章 / $totalMatches 处',
      style: context.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
    );
  }

  /// 构建搜索结果区域
  Widget _buildSearchResults(BuildContext context) {
    final provider = context.watch<WorkspaceProvider>();

    // 搜索中
    if (provider.isGlobalSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 12),
            Text('正在搜索...', style: context.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    // 未输入关键词
    if (provider.globalSearchQuery.isEmpty) {
      return _buildEmptyState(context, icon: Icons.search_rounded, text: '输入关键词搜索全部章节');
    }

    // 无匹配结果
    if (provider.globalSearchResults.isEmpty) {
      return _buildEmptyState(context, icon: Icons.search_off_rounded, text: '未找到匹配结果');
    }

    // 显示搜索结果列表
    return _buildResultList(context, provider);
  }

  /// 构建空状态提示
  Widget _buildEmptyState(BuildContext context, {required IconData icon, required String text}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 36, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(text, style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  /// 构建搜索结果列表
  Widget _buildResultList(BuildContext context, WorkspaceProvider provider) {
    final colorScheme = Theme.of(context).colorScheme;
    final searchQuery = provider.globalSearchQuery;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: provider.globalSearchResults.length,
      itemBuilder: (context, index) {
        final result = provider.globalSearchResults[index];
        return _buildChapterResultItem(context, result, searchQuery, colorScheme, provider);
      },
    );
  }

  /// 构建单个章节的搜索结果项
  Widget _buildChapterResultItem(
    BuildContext context,
    GlobalSearchResult result,
    String searchQuery,
    ColorScheme colorScheme,
    WorkspaceProvider provider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 章节标题行
        GestureDetector(
          onTap: () {
            // 点击章节标题，跳转到第一个匹配行
            if (result.matchLines.isNotEmpty) {
              provider.navigateToGlobalSearchResult(result, result.matchLines.first);
            }
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  // 章节图标
                  Icon(Icons.article_outlined, size: 14, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  // 卷名（如有）
                  if (result.volumeName.isNotEmpty) ...[
                    Text(
                      '${result.volumeName} · ',
                      style: context.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                  // 章节标题
                  Expanded(
                    child: Text(
                      result.chapterTitle,
                      style: context.titleSmall?.copyWith(color: colorScheme.onSurface, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 匹配数
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${result.totalMatches}',
                      style: context.labelSmall?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 匹配行列表（最多显示3行）
        ...result.matchLines
            .take(3)
            .map((matchLine) => _buildMatchLineItem(context, result, matchLine, searchQuery, colorScheme, provider)),

        // 如果还有更多匹配行
        if (result.matchLines.length > 3)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 4),
            child: Text(
              '还有 ${result.matchLines.length - 3} 处匹配...',
              style: context.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
            ),
          ),

        const SizedBox(height: 4),
      ],
    );
  }

  /// 构建单个匹配行项
  Widget _buildMatchLineItem(
    BuildContext context,
    GlobalSearchResult result,
    GlobalSearchMatchLine matchLine,
    String searchQuery,
    ColorScheme colorScheme,
    WorkspaceProvider provider,
  ) {
    return GestureDetector(
      onTap: () {
        provider.navigateToGlobalSearchResult(result, matchLine);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          margin: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 行号
              Container(
                width: 28,
                margin: const EdgeInsets.only(right: 6, top: 1),
                child: Text(
                  'L${matchLine.lineNumber}',
                  style: context.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    fontFeatures: [const FontFeature.tabularFigures()],
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              // 行内容（高亮关键词）
              Expanded(child: _buildHighlightedText(matchLine.lineContent, searchQuery, colorScheme)),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建带关键词高亮的文本
  Widget _buildHighlightedText(String text, String query, ColorScheme colorScheme) {
    final sourceText = text.toLowerCase();
    final searchQuery = query.toLowerCase();

    final spans = <TextSpan>[];
    int start = 0;

    while (start < sourceText.length) {
      final index = sourceText.indexOf(searchQuery, start);
      if (index == -1) {
        // 剩余部分无匹配
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }

      // 匹配前的普通文本
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }

      // 高亮匹配文本
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: TextStyle(
            color: colorScheme.primary,
            fontWeight: FontWeight.w600,
            backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
          ),
        ),
      );

      start = index + query.length;
    }

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: context.bodySmall?.copyWith(color: colorScheme.onSurface),
        children: spans,
      ),
    );
  }
}
