import 'package:quick_write/core/models/outline_note.dart';
import 'package:quick_write/core/services/workspace/book_folder_service.dart';
import 'package:quick_write/core/utils/docx_builder.dart';
import 'package:quick_write/core/utils/outline_markdown_codec.dart';
import 'package:quick_write/core/utils/text_style_range.dart';

/// 设定内容转 DOCX
///
/// 按节点原有的标题级别、文字样式和树层级写入文档，
/// 并把备注、图片与表格作为节点的附加内容放在其后。
class SettingDocxExporter {
  SettingDocxExporter._();

  /// 把单个设定项写入 [docx]
  ///
  /// [content] 为设定文件原始内容；[notes] 为伴生备注数据；
  /// [settingItemFilePath] 用于定位伴生图片文件。
  static Future<void> build({
    required DocxBuilder docx,
    required String title,
    required String content,
    required Map<String, OutlineNoteData> notes,
    required String? settingItemFilePath,
  }) async {
    docx.addHeading(title, level: 2);

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

      final runs = _buildRuns(parsed.text, parsed.styleRanges);
      if (parsed.headingLevel > 0) {
        docx.addRichParagraph(
          runs,
          indentLevel: depth,
          styleName: 'OutlineHeading${parsed.headingLevel.clamp(1, 3)}',
        );
      } else {
        docx.addRichParagraph(runs, indentLevel: depth);
      }

      final nodeId = split.nodeId;
      final note = (nodeId != null && nodeId.isNotEmpty ? notes[nodeId] : null) ?? notes[nodePath];
      if (note == null || note.isEmpty) continue;

      if (note.note.isNotEmpty) {
        for (final noteLine in note.note.split('\n')) {
          docx.addRichParagraph(
            [DocxRun(noteLine, const TextStyleFlags(italic: true))],
            indentLevel: depth + 1,
          );
        }
      }
      if (note.imageFileName.isNotEmpty) {
        final path = BookFolderService.settingImageFilePath(
          settingItemFilePath,
          note.imageFileName,
        );
        if (path != null) {
          await docx.addImage(path, indentLevel: depth + 1);
        }
      }
      if (note.table != null) {
        docx.addTable(note.table!);
      }
    }
  }

  /// 把样式区间转换为带格式的文字片段
  static List<DocxRun> _buildRuns(String text, List<TextStyleRange> ranges) {
    final runs = <DocxRun>[];
    int currentPos = 0;

    final sorted = List<TextStyleRange>.from(ranges)
      ..sort((a, b) => a.start.compareTo(b.start));
    for (final range in sorted) {
      final flags = range.flags.copyWith(clearLink: true);
      if (flags.isEmpty) continue;
      final start = range.start.clamp(0, text.length);
      final end = range.end.clamp(0, text.length);
      if (start >= end) continue;

      if (currentPos < start) runs.add(DocxRun(text.substring(currentPos, start)));
      runs.add(DocxRun(text.substring(start, end), flags));
      currentPos = end;
    }
    if (currentPos < text.length) runs.add(DocxRun(text.substring(currentPos)));
    return runs;
  }
}
