/// 大纲编辑器数据模型
///
/// 定义大纲树节点及其扁平化表示，供大纲编辑器及撤销管理器共同使用。
library;

import 'dart:ui' show Color;
import 'package:quick_write/core/models/outline_keyword.dart';
import 'package:quick_write/core/utils/text_style_range.dart';

/// 大纲节点数据模型
///
/// 表示大纲树中的一个节点，可包含子节点形成层级结构
class OutlineNode {
  /// 节点唯一标识
  final String id;

  /// 节点文本内容
  String text;

  /// 子节点列表
  List<OutlineNode> children;

  /// 是否展开（显示子节点）
  bool isExpanded;

  /// 标题级别（0=正文, 1=H1, 2=H2, 3=H3）
  ///
  /// 节点级属性，决定整行文字的字号偏移。
  /// 序列化为 markdown 时转换为行首 `#` 前缀。
  int headingLevel;

  /// 文字样式区间列表
  ///
  /// 记录节点文本中各段的样式标记（加粗/斜体/下划线/删除线）。
  /// 未被任何区间覆盖的文本使用默认样式。
  /// 序列化为 markdown 时转换为内联标记（`**`、`*`、`~~`、`<u>`）。
  List<TextStyleRange> styleRanges;

  /// 文字颜色（null 表示使用默认颜色）
  Color? foregroundColor;

  /// 节点绑定的关键词列表
  ///
  /// 一个节点可绑定多个关键词，关键词在整本书内唯一；
  /// 持久化到设定项文件旁的伴生 `.kw.json`，不写入大纲 Markdown。
  List<OutlineKeyword> keywords;

  OutlineNode({
    required this.id,
    this.text = '',
    List<OutlineNode>? children,
    this.isExpanded = true,
    this.headingLevel = 0,
    List<TextStyleRange>? styleRanges,
    this.foregroundColor,
    List<OutlineKeyword>? keywords,
  })  : children = children ?? [],
        styleRanges = styleRanges ?? [],
        keywords = keywords ?? [];

  /// 深拷贝节点（包括所有子孙节点）
  ///
  /// 用于撤销/恢复快照：快照需要保存独立的树副本，
  /// 避免后续修改影响到已保存的快照状态。
  /// 节点 ID 保持不变，以便恢复时能对应到原有的控制器和焦点节点。
  OutlineNode clone() {
    return OutlineNode(
      id: id,
      text: text,
      isExpanded: isExpanded,
      headingLevel: headingLevel,
      // 深拷贝样式区间列表，避免快照与原节点共享引用
      styleRanges: styleRanges.map((r) => r.copyWith()).toList(),
      foregroundColor: foregroundColor,
      // 关键词为不可变对象，复制列表即可使快照与原节点互不影响
      keywords: List<OutlineKeyword>.of(keywords),
      children: children.map((c) => c.clone()).toList(),
    );
  }

  /// 查找指定文本位置所在的关联文本范围
  ///
  /// 同一关联标识可能被其他样式拆分为多个区间，此处合并为完整范围；
  /// 位置不在任何关联文本内时返回 null。
  ({String linkId, int start, int end})? linkSpanAt(int offset) {
    if (offset < 0 || offset >= text.length) return null;

    String? linkId;
    for (final range in styleRanges) {
      final String? id = range.flags.linkId;
      if (id != null && offset >= range.start && offset < range.end) {
        linkId = id;
        break;
      }
    }
    if (linkId == null) return null;

    int start = text.length;
    int end = 0;
    for (final range in styleRanges) {
      if (range.flags.linkId != linkId) continue;
      if (range.start < start) start = range.start;
      if (range.end > end) end = range.end;
    }
    return (linkId: linkId, start: start, end: end);
  }
}

/// 扁平化的大纲节点（用于渲染）
///
/// 将树形结构展开为一维列表时，记录每个节点的深度和父节点
class FlatNode {
  /// 节点数据
  final OutlineNode node;

  /// 缩进深度（0为根节点）
  final int depth;

  /// 父节点（根节点为null）
  final OutlineNode? parent;

  FlatNode({required this.node, required this.depth, this.parent});
}
