import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quick_write/core/providers/workspace_provider.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/pages/workspace/sensitive_word/widgets/sensitive_word_editor_dialog.dart';
import 'package:quick_write/shared/widgets/qw_dialogs.dart';
import 'package:quick_write/shared/widgets/qw_switch.dart';

/// 显示桌面端敏感词检测弹窗
///
/// 打开后自动扫描全书章节，列出含有敏感词的章节与命中行；
/// 点击结果跳转到对应章节并选中敏感词，同时可编辑词库与切换正文标红开关。
Future<void> showSensitiveWordCheckDialog({
  required BuildContext context,
  required WorkspaceProvider provider,
}) {
  return showDialogBase(
    context: context,
    title: '敏感词检测',
    subtitle: '扫描全部章节并定位敏感词',
    titleIcon: Icons.gpp_bad_outlined,
    width: 780,
    height: 620,
    content: _SensitiveWordCheckDialog(provider: provider),
  );
}

/// 显示移动端敏感词检测弹窗
///
/// 与桌面端共用同一套内容，仅收窄弹窗宽度以适配移动端屏幕。
Future<void> showMobileSensitiveWordCheckDialog({
  required BuildContext context,
  required WorkspaceProvider provider,
}) {
  return showDialogBase(
    context: context,
    title: '敏感词检测',
    subtitle: '扫描全部章节并定位敏感词',
    titleIcon: Icons.gpp_bad_outlined,
    width: 460,
    height: 620,
    content: _SensitiveWordCheckDialog(provider: provider),
  );
}

/// 敏感词检测弹窗内容
class _SensitiveWordCheckDialog extends StatefulWidget {
  /// 工作台 Provider（弹窗位于根导航之下，需由调用方显式传入）
  final WorkspaceProvider provider;

  const _SensitiveWordCheckDialog({required this.provider});

  @override
  State<_SensitiveWordCheckDialog> createState() =>
      _SensitiveWordCheckDialogState();
}

class _SensitiveWordCheckDialogState extends State<_SensitiveWordCheckDialog> {
  /// 弹窗内最多展示的命中行数量
  static const int _maxVisibleLines = 5;

  /// 扫描结果
  List<SensitiveWordScanResult> _results = const [];

  /// 是否正在扫描
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    // 首帧后开始扫描，避免弹窗打开动画期间阻塞
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  /// 扫描全部章节中的敏感词
  Future<void> _scan() async {
    final words = widget.provider.sensitiveWordService.words;
    if (words.isEmpty) {
      setState(() {
        _results = const [];
        _scanning = false;
      });
      return;
    }

    setState(() => _scanning = true);
    final results = await widget.provider.scanSensitiveWords(words);
    if (!mounted) return;
    setState(() {
      _results = results;
      _scanning = false;
    });
  }

  /// 切换正文敏感词标红开关
  Future<void> _toggleHighlight(bool enabled) async {
    await widget.provider.sensitiveWordService.setHighlightEnabled(enabled);
    if (mounted) setState(() {});
  }

  /// 打开词库编辑弹窗，保存后重新扫描
  Future<void> _editWordLibrary() async {
    final changed = await showSensitiveWordEditorDialog(
      context: context,
      service: widget.provider.sensitiveWordService,
    );
    if (!mounted || !changed) return;
    setState(() {});
    await _scan();
  }

  /// 跳转到命中的敏感词
  ///
  /// 弹窗会遮挡正文，跳转前先关闭弹窗，再由工作台打开章节并选中敏感词。
  void _jumpToResult(
    SensitiveWordScanResult result,
    GlobalSearchMatchLine matchLine,
  ) {
    final words = widget.provider.sensitiveWordService.words;
    Navigator.of(context).pop();
    unawaited(
      widget.provider.navigateToSensitiveWordResult(result, matchLine, words),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        _buildToolbar(context),
        _buildSummary(context),
        const SizedBox(height: 8),
        Divider(
          height: 1,
          thickness: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  /// 顶部操作栏：标红开关 + 编辑词库 + 重新扫描
  Widget _buildToolbar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = widget.provider.sensitiveWordService.highlightEnabled;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
      child: Row(
        children: [
          Tooltip(
            message: '开启后正文中的敏感词会实时标红',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                QwSwitch(
                  value: enabled,
                  onChanged: _toggleHighlight,
                  activeColor: colorScheme.error,
                ),
                const SizedBox(width: 6),
                Text(
                  '标红',
                  style: context.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _editWordLibrary,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('编辑词库'),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: '重新扫描',
            onPressed: _scanning ? null : _scan,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
        ],
      ),
    );
  }

  /// 构建扫描结果统计
  Widget _buildSummary(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final wordCount = widget.provider.sensitiveWordService.words.length;
    final int totalMatches = _results.fold<int>(
      0,
      (sum, r) => sum + r.totalMatches,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _scanning
                  ? '正在扫描…'
                  : '共 ${_results.length} 个章节 / $totalMatches 处',
              style: context.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            '$wordCount 个词条',
            style: context.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建结果区域（扫描中、空词库、无命中、结果列表）
  Widget _buildBody(BuildContext context) {
    if (_scanning) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '正在扫描全部章节…',
              style: context.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.provider.sensitiveWordService.words.isEmpty) {
      return _buildEmptyState(
        context,
        icon: Icons.text_fields_rounded,
        text: '敏感词库为空，请先编辑词库',
      );
    }

    if (_results.isEmpty) {
      return _buildEmptyState(
        context,
        icon: Icons.verified_outlined,
        text: '未发现敏感词',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        return _buildResultItem(context, result);
      },
    );
  }

  /// 构建空状态提示
  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String text,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 36,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            style: context.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建单个章节的结果项
  Widget _buildResultItem(
    BuildContext context,
    SensitiveWordScanResult result,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final words = widget.provider.sensitiveWordService.words;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 章节标题行：点击跳转到该章节的第一个命中位置
        GestureDetector(
          onTap: () => _jumpToResult(result, result.matchLines.first),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 14,
                    color: colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  // 卷名（如有）
                  if (result.groupName.isNotEmpty) ...[
                    Text(
                      '${result.groupName} · ',
                      style: context.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  Expanded(
                    child: Text(
                      result.title,
                      style: context.titleSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 命中数
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${result.totalMatches}',
                      style: context.labelSmall?.copyWith(
                        color: colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 命中行列表
        ...result.matchLines
            .take(_maxVisibleLines)
            .map(
              (matchLine) =>
                  _buildMatchLineItem(context, result, matchLine, words),
            ),

        // 超出展示上限时提示剩余数量
        if (result.matchLines.length > _maxVisibleLines)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 4),
            child: Text(
              '还有 ${result.matchLines.length - _maxVisibleLines} 处命中...',
              style: context.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ),

        const SizedBox(height: 4),
      ],
    );
  }

  /// 构建单个命中行项
  Widget _buildMatchLineItem(
    BuildContext context,
    SensitiveWordScanResult result,
    GlobalSearchMatchLine matchLine,
    List<String> words,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _jumpToResult(result, matchLine),
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
              // 行内容（标红敏感词）
              Expanded(
                child: _buildHighlightedLine(
                  context,
                  matchLine.lineContent,
                  words,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建带敏感词标红的行文本
  ///
  /// 收集全部词条在行内的命中区间，按起始位置排序后合并重叠部分，
  /// 依次输出普通文本与标红文本。
  Widget _buildHighlightedLine(
    BuildContext context,
    String text,
    List<String> words,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final TextStyle? baseStyle = context.bodySmall?.copyWith(
      color: colorScheme.onSurface,
    );
    final String lowerText = text.toLowerCase();

    // 收集所有词条的命中区间（区间端点基于原始文本索引）
    final matches = <({int start, int end})>[];
    for (final word in words) {
      final keyword = word.toLowerCase();
      if (keyword.isEmpty) continue;
      int searchStart = 0;
      while (true) {
        final index = lowerText.indexOf(keyword, searchStart);
        if (index == -1) break;
        matches.add((start: index, end: index + keyword.length));
        searchStart = index + keyword.length;
      }
    }

    if (matches.isEmpty) {
      return RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(style: baseStyle, text: text),
      );
    }

    // 起始位置升序排序，起始相同时较长的区间优先
    matches.sort((a, b) {
      final cmp = a.start.compareTo(b.start);
      return cmp != 0 ? cmp : b.end.compareTo(a.end);
    });

    // 顺序遍历，跳过与上一段重叠的区间，拼装 TextSpan
    final spans = <TextSpan>[];
    int cursor = 0;
    for (final match in matches) {
      if (match.start < cursor) continue;
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: TextStyle(
            color: colorScheme.error,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.lineThrough,
            decorationColor: colorScheme.error,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: baseStyle, children: spans),
    );
  }
}
