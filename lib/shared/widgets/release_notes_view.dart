import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/core/utils/url_opener.dart';

/// GitHub Release 正文渲染
///
/// 只处理项目发版文档会用到的 Markdown 子集：标题、无序列表、链接、
/// 行内代码、加粗、引用块与下载表格，外加 GitHub 允许的两类内联 HTML：
/// `<kbd>` 按键与 `<br>` 换行；不引入额外依赖。
class ReleaseNotesView extends StatelessWidget {
  const ReleaseNotesView({super.key, required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final lines = markdown.replaceAll('\r\n', '\n').split('\n');
    final blocks = <Widget>[];
    var i = 0;

    while (i < lines.length) {
      final line = lines[i].trimRight();
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        blocks.add(const SizedBox(height: 6));
        i++;
        continue;
      }

      // 表格：表头行 + |---|---| 分隔行
      if (trimmed.startsWith('|') &&
          i + 1 < lines.length &&
          _isTableSeparator(lines[i + 1].trim())) {
        final rows = <List<String>>[_splitRow(trimmed)];
        i += 2;
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          rows.add(_splitRow(lines[i].trim()));
          i++;
        }
        blocks.add(_buildTable(context, rows));
        continue;
      }

      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        final level = heading.group(1)!.length;
        final base = level <= 2
            ? context.titleSmall
            : context.bodyMedium;
        blocks.add(Padding(
          padding: EdgeInsets.only(top: level <= 2 ? 8 : 4, bottom: 2),
          child: RichText(
            text: _inline(
              context,
              heading.group(2)!,
              style: base?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ));
        i++;
        continue;
      }

      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        blocks.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• ', style: context.bodySmall),
            Expanded(
              child: RichText(text: _inline(context, trimmed.substring(2))),
            ),
          ],
        ));
        i++;
        continue;
      }

      if (trimmed.startsWith('> ')) {
        final color = Theme.of(context).colorScheme;
        blocks.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: color.outlineVariant, width: 2),
            ),
          ),
          child: RichText(
            text: _inline(
              context,
              trimmed.substring(2),
              style: context.bodySmall?.copyWith(
                color: color.onSurfaceVariant,
              ),
            ),
          ),
        ));
        i++;
        continue;
      }

      blocks.add(RichText(text: _inline(context, trimmed)));
      i++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  bool _isTableSeparator(String line) {
    if (!line.startsWith('|') || !line.endsWith('|')) return false;
    final cells = _splitRow(line);
    return cells.isNotEmpty &&
        cells.every((c) => RegExp(r'^:?-{3,}:?$').hasMatch(c.trim()));
  }

  List<String> _splitRow(String line) {
    var value = line.trim();
    if (value.startsWith('|')) value = value.substring(1);
    if (value.endsWith('|')) value = value.substring(0, value.length - 1);
    return value.split('|').map((e) => e.trim()).toList();
  }

  Widget _buildTable(BuildContext context, List<List<String>> rows) {
    final borderColor = Theme.of(context).dividerColor;
    final base = context.bodySmall ?? const TextStyle(fontSize: 13);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Table(
        border: TableBorder.all(color: borderColor, width: 0.5),
        columnWidths: const {
          0: FixedColumnWidth(72),
          1: FlexColumnWidth(),
          2: FlexColumnWidth(),
        },
        children: [
          for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
            TableRow(
              children: [
                for (var cellIndex = 0; cellIndex < 3; cellIndex++)
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: RichText(
                      text: _inline(
                        context,
                        cellIndex < rows[rowIndex].length
                            ? rows[rowIndex][cellIndex]
                            : '',
                        style: base.copyWith(
                          fontSize: 12,
                          fontWeight: rowIndex == 0
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  TextSpan _inline(
    BuildContext context,
    String text, {
    TextStyle? style,
  }) {
    final base = style ?? context.bodySmall ?? const TextStyle(fontSize: 13);
    final color = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    final pattern = RegExp(
      r'(\[[^\]]+\]\([^)]+\)|<kbd>[^<]+</kbd>|<br\s*/?>|`[^`]+`|\*\*[^*]+\*\*)',
      caseSensitive: false,
    );

    var lastEnd = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: base,
        ));
      }

      final token = match.group(0)!;
      if (token.startsWith('[')) {
        final link = RegExp(r'^\[([^\]]+)\]\(([^)]+)\)$').firstMatch(token)!;
        spans.add(TextSpan(
          text: link.group(1),
          style: base.copyWith(
            color: color.primary,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => UrlOpener.open(link.group(2)!),
        ));
      } else if (token.toLowerCase().startsWith('<kbd>')) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: color.surfaceContainerHighest.withValues(alpha: 0.6),
              border: Border.all(color: color.outlineVariant, width: 0.8),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              token.substring(5, token.length - 6),
              style: base.copyWith(
                fontFamily: 'monospace',
                fontSize: (base.fontSize ?? 13) - 1,
                height: 1.2,
              ),
            ),
          ),
        ));
      } else if (token.toLowerCase().startsWith('<br')) {
        spans.add(const TextSpan(text: '\n'));
      } else if (token.startsWith('`')) {
        spans.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: base.copyWith(fontFamily: 'monospace'),
        ));
      } else {
        spans.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: base.copyWith(fontWeight: FontWeight.w600),
        ));
      }

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd), style: base));
    }

    return TextSpan(children: spans, style: base);
  }
}
