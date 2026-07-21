/// 大纲编辑器数据模型
///
/// 定义大纲树节点及其扁平化表示，供大纲编辑器及撤销管理器共同使用。
library;

import 'dart:ui' show Color;
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

  OutlineNode({
    required this.id,
    this.text = '',
    List<OutlineNode>? children,
    this.isExpanded = true,
    this.headingLevel = 0,
    List<TextStyleRange>? styleRanges,
    this.foregroundColor,
  })  : children = children ?? [],
        styleRanges = styleRanges ?? [];

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
      children: children.map((c) => c.clone()).toList(),
    );
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
