/// 大纲节点附加内容（备注、图片与表格）的持久化数据模型
///
/// 三者按「层级索引路径」与节点对应，与关键词、关联使用同一套路径规则，
/// 统一保存在设定项文件旁的合并伴生 `.json` 中。
library;

import 'package:quick_write/core/models/outline_table.dart';

/// 单个节点的备注、图片与表格数据
class OutlineNoteData {
  /// 备注文本（空字符串表示没有备注）
  final String note;

  /// 图片文件名（不含路径，空字符串表示没有图片）
  final String imageFileName;

  /// 表格数据（null 表示没有表格）
  final OutlineTableData? table;

  const OutlineNoteData({
    this.note = '',
    this.imageFileName = '',
    this.table,
  });

  /// 是否没有任何内容
  bool get isEmpty => note.isEmpty && imageFileName.isEmpty && table == null;

  /// 序列化为 JSON
  ///
  /// 空字段不写入，保持文件内容精简、便于比对。
  Map<String, dynamic> toJson() => {
        if (note.isNotEmpty) 'note': note,
        if (imageFileName.isNotEmpty) 'image': imageFileName,
        if (table != null) 'table': table!.toJson(),
      };

  /// 从 JSON 反序列化
  factory OutlineNoteData.fromJson(Map<String, dynamic> json) {
    return OutlineNoteData(
      note: json['note'] as String? ?? '',
      imageFileName: json['image'] as String? ?? '',
      table: OutlineTableData.fromJson(json['table']),
    );
  }
}

/// 备注伴生数据（从统一伴生文件中读取的备注部分）
class OutlineNoteFile {
  /// 节点层级索引路径 → 备注、图片与表格数据
  final Map<String, OutlineNoteData> nodes;

  const OutlineNoteFile({required this.nodes});
}
