import 'dart:ui' show Color;

import 'package:quick_write/core/utils/text_style_range.dart';

/// 表格整表对齐方式
///
/// 对齐作用于整个表格，所有单元格共用同一水平对齐设置。
enum OutlineTableAlignment {
  /// 左对齐
  left,

  /// 居中
  center,

  /// 右对齐
  right,
}

/// 大纲表格数据模型
///
/// 表格属于节点的附加内容，与备注、图片一同保存在设定项的伴生文件中。
/// 单元格记录文本、文字样式与标题级别，字体颜色复用 [TextStyleFlags] 的前景色。
class OutlineTableData {
  /// 表格的行集合，每一行的单元格数量一致
  ///
  /// 行列结构由列表本身决定，不单独记录列数，避免两者不一致。
  final List<List<OutlineTableCell>> rows;

  /// 整表水平对齐方式
  OutlineTableAlignment alignment;

  /// 各列固定宽度（像素）
  ///
  /// 为空表示列宽按内容自动测量；非空时长度与列数一致，
  /// 用户拖动列分隔线后记录在此，并随表格一起保存。
  final List<double> columnWidths;

  OutlineTableData({
    required this.rows,
    this.alignment = OutlineTableAlignment.left,
    List<double>? columnWidths,
  }) : columnWidths = columnWidths ?? <double>[];

  /// 创建一个空表格
  ///
  /// 首行为表头，因此默认给出两行，第一行用于填写列标题。
  factory OutlineTableData.create({int rowCount = 2, int columnCount = 3}) {
    return OutlineTableData(
      rows: [
        for (int row = 0; row < rowCount; row++)
          [for (int column = 0; column < columnCount; column++) OutlineTableCell()],
      ],
    );
  }

  /// 行数
  int get rowCount => rows.length;

  /// 列数（表格为空时为 0）
  int get columnCount => rows.isEmpty ? 0 : rows.first.length;

  /// 深拷贝表格
  ///
  /// 用于撤销快照，避免快照与当前编辑内容共享单元格对象。
  OutlineTableData clone() {
    return OutlineTableData(
      rows: [
        for (final row in rows) [for (final cell in row) cell.clone()],
      ],
      alignment: alignment,
      columnWidths: List.of(columnWidths),
    );
  }

  /// 在末尾追加一行
  void addRow() {
    rows.add([for (int column = 0; column < columnCount; column++) OutlineTableCell()]);
  }

  /// 在末尾追加一列
  ///
  /// [width] 为新增列的宽度，仅在表格已启用固定列宽时记录。
  void addColumn({double? width}) {
    for (final row in rows) {
      row.add(OutlineTableCell());
    }
    if (columnWidths.isNotEmpty) {
      columnWidths.add(width ?? columnWidths.last);
    }
  }

  /// 记录各列固定宽度
  ///
  /// 传入的宽度数量与列数一致，写入后列宽不再随内容变化。
  void setColumnWidths(Iterable<double> widths) {
    columnWidths
      ..clear()
      ..addAll(widths);
  }

  /// 移动行到指定位置，返回是否移动成功
  ///
  /// 目标位置为移动完成后的行索引，越界或原地移动视为失败。
  bool moveRow(int from, int to) {
    if (from == to || from < 0 || to < 0 || from >= rowCount || to >= rowCount) return false;
    rows.insert(to, rows.removeAt(from));
    return true;
  }

  /// 移动列到指定位置，返回是否移动成功
  ///
  /// 目标位置为移动完成后的列索引；固定列宽随之一起移动。
  bool moveColumn(int from, int to) {
    if (from == to || from < 0 || to < 0 || from >= columnCount || to >= columnCount) return false;
    for (final row in rows) {
      row.insert(to, row.removeAt(from));
    }
    if (columnWidths.length == columnCount) {
      columnWidths.insert(to, columnWidths.removeAt(from));
    }
    return true;
  }

  /// 删除指定行，返回是否删除成功
  ///
  /// 表格至少保留一行，越界索引视为删除失败。
  bool removeRow(int index) {
    if (rowCount <= 1 || index < 0 || index >= rowCount) return false;
    rows.removeAt(index);
    return true;
  }

  /// 删除指定列，返回是否删除成功
  ///
  /// 表格至少保留一列，越界索引视为删除失败；固定列宽同步移除。
  bool removeColumn(int index) {
    if (columnCount <= 1 || index < 0 || index >= columnCount) return false;
    for (final row in rows) {
      row.removeAt(index);
    }
    if (columnWidths.length > index) columnWidths.removeAt(index);
    return true;
  }

  /// 序列化为 JSON
  ///
  /// 只写入非空字段，保持伴生文件精简、便于比对。
  Map<String, dynamic> toJson() => {
        'rows': [
          for (final row in rows) [for (final cell in row) cell.toJson()],
        ],
        // 仅在与默认左对齐不同时写入，减少伴生文件冗余
        if (alignment != OutlineTableAlignment.left) 'align': alignment.name,
        // 仅在用户调整过列宽时写入固定列宽
        if (columnWidths.isNotEmpty) 'widths': List.of(columnWidths),
      };

  /// 从 JSON 反序列化
  ///
  /// 数据缺失或结构非法时返回 null；列数不一致的行会按首行补齐或截断，
  /// 保证表格始终是规整的矩形。
  static OutlineTableData? fromJson(dynamic json) {
    if (json is! Map) return null;
    final dynamic rawRows = json['rows'];
    if (rawRows is! List) return null;

    final List<List<OutlineTableCell>> rows = [];
    for (final dynamic rawRow in rawRows) {
      if (rawRow is! List) continue;
      rows.add([for (final dynamic rawCell in rawRow) OutlineTableCell.fromJson(rawCell)]);
    }
    // 空行无法确定列数，直接丢弃
    rows.removeWhere((row) => row.isEmpty);
    if (rows.isEmpty) return null;

    final int columnCount = rows.first.length;
    for (final row in rows) {
      if (row.length > columnCount) {
        row.removeRange(columnCount, row.length);
      } else {
        while (row.length < columnCount) {
          row.add(OutlineTableCell());
        }
      }
    }

    // 固定列宽仅在数量与列数一致时采用，否则回退为按内容自动测量
    final List<double> columnWidths = [];
    final dynamic rawWidths = json['widths'];
    if (rawWidths is List) {
      for (final dynamic rawWidth in rawWidths) {
        if (rawWidth is num) columnWidths.add(rawWidth.toDouble());
      }
    }
    if (columnWidths.length != columnCount) columnWidths.clear();

    return OutlineTableData(
      rows: rows,
      alignment: OutlineTableAlignment.values.firstWhere(
        (value) => value.name == json['align'],
        orElse: () => OutlineTableAlignment.left,
      ),
      columnWidths: columnWidths,
    );
  }
}

/// 表格单元格
class OutlineTableCell {
  /// 单元格文本
  String text;

  /// 文字样式标记（加粗、斜体、下划线、删除线与字体颜色）
  TextStyleFlags flags;

  /// 标题级别（0=正文, 1=H1, 2=H2, 3=H3）
  ///
  /// 与节点一致，级别越高字号越大，用于强调单元格内容。
  int headingLevel;

  OutlineTableCell({
    this.text = '',
    this.flags = TextStyleFlags.none,
    this.headingLevel = 0,
  });

  /// 深拷贝单元格
  OutlineTableCell clone() {
    return OutlineTableCell(
      text: text,
      flags: flags.copyWith(),
      headingLevel: headingLevel,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
        if (text.isNotEmpty) 'text': text,
        if (flags.bold) 'bold': true,
        if (flags.italic) 'italic': true,
        if (flags.underline) 'underline': true,
        if (flags.strikethrough) 'strikethrough': true,
        if (flags.foregroundColor != null) 'color': _colorToHex(flags.foregroundColor!),
        if (headingLevel > 0) 'heading': headingLevel,
      };

  /// 从 JSON 反序列化
  factory OutlineTableCell.fromJson(dynamic json) {
    if (json is! Map) return OutlineTableCell();
    final int headingLevel = (json['heading'] as num?)?.toInt() ?? 0;
    return OutlineTableCell(
      text: json['text'] as String? ?? '',
      headingLevel: headingLevel.clamp(0, 3).toInt(),
      flags: TextStyleFlags(
        bold: json['bold'] == true,
        italic: json['italic'] == true,
        underline: json['underline'] == true,
        strikethrough: json['strikethrough'] == true,
        foregroundColor: _colorFromHex(json['color']),
      ),
    );
  }
}

/// 把颜色转换为 `#AARRGGBB` 形式的十六进制字符串
String _colorToHex(Color color) {
  return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
}

/// 从 `#AARRGGBB` 或 `#RRGGBB` 形式的字符串解析颜色
Color? _colorFromHex(dynamic raw) {
  if (raw is! String) return null;
  final String hex = raw.startsWith('#') ? raw.substring(1) : raw;
  final int? value = int.tryParse(hex, radix: 16);
  if (value == null) return null;
  // 六位颜色按不透明处理
  return Color(hex.length <= 6 ? value | 0xFF000000 : value);
}
