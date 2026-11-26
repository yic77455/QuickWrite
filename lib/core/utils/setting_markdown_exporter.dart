import 'package:quick_write/core/models/outline_models.dart';
import 'package:quick_write/core/models/outline_note.dart';
import 'package:quick_write/core/models/outline_table.dart';
import 'package:quick_write/core/utils/outline_markdown_codec.dart';
import 'package:quick_write/core/utils/text_style_range.dart';

/// 设定内容转标准 Markdown
///
/// 节点层级用缩进列表表示，行内样式仅保留 MD 支持的标记；
/// 伴生数据只写入备注、图片链接与表格，关键词和关联不参与导出。
class SettingMarkdownExporter {
  SettingMarkdownExporter._();

  /// 生成 Markdown 文本
  ///
  /// [content] 为设定文件原始内容（按行存储节点，缩进表示层级）；
  /// [notes] 为伴生文件中按节点 ID 或层级路径索引的备注数据。
  static String build({
    required String title,
    required String content,
    required Map<String, OutlineNoteData> notes,
  }) {
    final buffer = StringBuffer()
      ..writeln('# $title')
      ..writeln();

    final lines = content.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();

    final counters = <int>[];
    int previousDepth = -1;

    for (final rawLine in lines) {
      int depth = 0;
      var line = rawLine;
      while (line.startsWith('\t')) {
        if (depth < 6) {
          depth++;
        }
        line = line.substring(1);
      }
      while (line.startsWith('    ')) {
        if (depth < 6) {
          depth++;
        }
        line = line.substring(4);
      }

      final split = OutlineMarkdownCodec.splitNodeId(line);
      final parsed = OutlineMarkdownCodec.deserialize(split.text);

      if (depth > previousDepth) {
        while (counters.length <= depth) {
          counters.add(-1);
        }
        for (int i = previousDepth + 1; i <= depth; i++) {
          counters[i] = -1;
        }
      }
      while (counters.length > depth + 1) {
        counters.removeLast();
      }
      counters[depth]++;
      final nodePath = counters.join('.');
      previousDepth = depth;

      final node = OutlineNode(
        id: split.nodeId ?? '',
        text: parsed.text,
        headingLevel: parsed.headingLevel,
        styleRanges: parsed.styleRanges,
      );
      final prefix = '  ' * depth;
      final heading = node.headingLevel > 0 ? '${'#' * node.headingLevel} ' : '';
      buffer.writeln('$prefix- $heading${_renderInline(node)}');

      final note = (node.id.isNotEmpty ? notes[node.id] : null) ?? notes[nodePath];
      if (note == null || note.isEmpty) continue;

      final childPrefix = '  ' * (depth + 1);
      if (note.note.isNotEmpty) {
        for (final noteLine in note.note.split('\n')) {
          buffer.writeln('$childPrefix> $noteLine');
        }
      }
      if (note.imageFileName.isNotEmpty) {
        buffer.writeln('$childPrefix![图片](image/${_escapeLink(note.imageFileName)})');
      }
      if (note.table != null) {
        _writeTable(buffer, note.table!, childPrefix);
      }
    }

    return buffer.toString();
  }

  /// 按节点样式区间渲染行内 Markdown 标记
  static String _renderInline(OutlineNode node) {
    final text = node.text;
    final parts = <String>[];
    var currentPos = 0;

    final ranges = List<TextStyleRange>.from(node.styleRanges)
      ..sort((a, b) => a.start.compareTo(b.start));
    for (final range in ranges) {
      if (range.flags.isEmpty) continue;
      final start = range.start.clamp(0, text.length);
      final end = range.end.clamp(0, text.length);
      if (start >= end) continue;

      if (currentPos < start) parts.add(_escapeText(text.substring(currentPos, start)));
      var segment = _escapeText(text.substring(start, end));
      if (range.flags.underline) segment = '<u>$segment</u>';
      if (range.flags.strikethrough) segment = '~~$segment~~';
      if (range.flags.italic) segment = '*$segment*';
      if (range.flags.bold) segment = '**$segment**';
      parts.add(segment);
      currentPos = end;
    }
    if (currentPos < text.length) parts.add(_escapeText(text.substring(currentPos)));
    return parts.join();
  }

  /// 转义行内文本中的 MD 标记字面量
  static String _escapeText(String raw) {
    final buffer = StringBuffer();
    for (int i = 0; i < raw.length; i++) {
      final char = raw[i];
      if (char == '\\' || char == '*' || char == '~' || char == '`') {
        buffer.write('\\$char');
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  /// 写入 Markdown 表格
  static void _writeTable(StringBuffer buffer, OutlineTableData table, String prefix) {
    if (table.rows.isEmpty || table.columnCount == 0) return;

    final aligns = switch (table.alignment) {
      OutlineTableAlignment.center => ':---:',
      OutlineTableAlignment.right => '---:',
      OutlineTableAlignment.left => ':---',
    };

    for (int rowIndex = 0; rowIndex < table.rows.length; rowIndex++) {
      final cells = table.rows[rowIndex].map(_renderCell).toList();
      buffer.writeln('$prefix| ${cells.join(' | ')} |');
      if (rowIndex == 0) {
        buffer.writeln('$prefix| ${List.filled(table.columnCount, aligns).join(' | ')} |');
      }
    }
  }

  /// 渲染表格单元格，忽略字体颜色等非 MD 样式
  static String _renderCell(OutlineTableCell cell) {
    var text = _escapeText(cell.text.replaceAll('\n', ' ')).replaceAll('|', r'\|');
    if (cell.flags.bold) text = '**$text**';
    if (cell.flags.italic) text = '*$text*';
    if (cell.flags.strikethrough) text = '~~$text~~';
    if (cell.flags.underline) text = '<u>$text</u>';
    if (cell.headingLevel > 0) text = '${'#' * cell.headingLevel} $text';
    return text;
  }

  /// 转义图片链接中的空格与括号
  static String _escapeLink(String fileName) =>
      fileName.replaceAll(' ', '%20').replaceAll('(', '%28').replaceAll(')', '%29');
}
