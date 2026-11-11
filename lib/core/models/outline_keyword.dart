import 'dart:ui' show Color;

import 'package:quick_write/core/utils/color_utils.dart';
import 'package:quick_write/core/utils/text_style_range.dart';

/// 大纲节点绑定的关键词
///
/// 关键词以十六进制字符串保存颜色，便于直接写入伴生 JSON 文件；
/// 展示与正文高亮时再转换为 [Color]。
class OutlineKeyword {
  /// 关键词文本
  final String keyword;

  /// 关键词颜色（#RRGGBB 格式）
  final String colorHex;

  const OutlineKeyword({required this.keyword, required this.colorHex});

  /// 转换为 [Color]
  Color get color => ColorUtils.parseHex(colorHex);

  /// 从 JSON 反序列化
  factory OutlineKeyword.fromJson(Map<String, dynamic> json) {
    return OutlineKeyword(
      keyword: (json['keyword'] as String?) ?? '',
      colorHex: (json['colorHex'] as String?) ?? '#1565C0',
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {'keyword': keyword, 'colorHex': colorHex};

  /// 创建一份修改后的副本
  OutlineKeyword copyWith({String? keyword, String? colorHex}) {
    return OutlineKeyword(
      keyword: keyword ?? this.keyword,
      colorHex: colorHex ?? this.colorHex,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OutlineKeyword &&
          other.keyword == keyword &&
          other.colorHex == colorHex;

  @override
  int get hashCode => Object.hash(keyword, colorHex);
}

/// 关键词绑定节点的子孙节点快照
///
/// [depth] 为相对绑定节点的层级（子节点为 1，孙节点为 2），
/// 供正文悬浮卡片按层级缩进展示，无需在悬停时重新读取大纲文件。
/// 同时记录节点的标题级别、文字样式区间、备注与图片，
/// 使卡片内容区还原节点自身的排版样式并展示节点的附加内容。
class OutlineKeywordSubNode {
  /// 相对绑定节点的层级
  final int depth;

  /// 节点文本
  final String text;

  /// 节点备注
  final String note;

  /// 节点图片文件名（相对设定项目录下的 image 文件夹）
  final String imageFileName;

  /// 节点图片的绝对路径
  ///
  /// 由关键词索引按设定项目录解析后写入内存，不参与伴生文件序列化。
  final String imagePath;

  /// 节点文字样式区间（相对 [text] 的偏移量）
  final List<TextStyleRange> styleRanges;

  /// 标题级别（0=正文, 1=H1, 2=H2, 3=H3）
  final int headingLevel;

  const OutlineKeywordSubNode({
    required this.depth,
    required this.text,
    this.note = '',
    this.imageFileName = '',
    this.imagePath = '',
    this.styleRanges = const [],
    this.headingLevel = 0,
  });

  /// 从 JSON 反序列化
  factory OutlineKeywordSubNode.fromJson(Map<String, dynamic> json) {
    final rawRanges = json['styleRanges'];
    return OutlineKeywordSubNode(
      depth: (json['depth'] as num?)?.toInt() ?? 1,
      text: (json['text'] as String?) ?? '',
      note: (json['note'] as String?) ?? '',
      imageFileName: (json['image'] as String?) ?? '',
      headingLevel: (json['headingLevel'] as num?)?.toInt() ?? 0,
      styleRanges: [
        if (rawRanges is List)
          for (final range in rawRanges)
            if (range is Map<String, dynamic>) _styleRangeFromJson(range),
      ],
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
    'depth': depth,
    'text': text,
    if (note.isNotEmpty) 'note': note,
    if (imageFileName.isNotEmpty) 'image': imageFileName,
    // 正文节点不写入标题级别，保持文件简洁
    if (headingLevel > 0) 'headingLevel': headingLevel,
    if (styleRanges.isNotEmpty)
      'styleRanges': styleRanges.map(_styleRangeToJson).toList(),
  };

  /// 创建一份替换了图片绝对路径的副本
  ///
  /// 图片路径依赖设定项所在目录，由索引构建时统一解析，序列化时只保留文件名。
  OutlineKeywordSubNode withImagePath(String imagePath) {
    return OutlineKeywordSubNode(
      depth: depth,
      text: text,
      note: note,
      imageFileName: imageFileName,
      imagePath: imagePath,
      styleRanges: styleRanges,
      headingLevel: headingLevel,
    );
  }

  /// 将文字样式区间序列化为 JSON
  ///
  /// 仅写入已开启的标记位与已设置的颜色，未出现的字段在反序列化时取默认值。
  static Map<String, dynamic> _styleRangeToJson(TextStyleRange range) {
    final TextStyleFlags flags = range.flags;
    return {
      'start': range.start,
      'end': range.end,
      if (flags.bold) 'bold': true,
      if (flags.italic) 'italic': true,
      if (flags.underline) 'underline': true,
      if (flags.strikethrough) 'strikethrough': true,
      if (flags.foregroundColor != null)
        'foregroundColor': ColorUtils.toHex(flags.foregroundColor!),
      if (flags.backgroundColor != null)
        'backgroundColor': ColorUtils.toHex(flags.backgroundColor!),
    };
  }

  /// 从 JSON 还原文字样式区间
  ///
  /// 颜色字段缺失或格式非法时按无颜色处理。
  static TextStyleRange _styleRangeFromJson(Map<String, dynamic> json) {
    final String? foreground = json['foregroundColor'] as String?;
    final String? background = json['backgroundColor'] as String?;
    return TextStyleRange(
      start: (json['start'] as num?)?.toInt() ?? 0,
      end: (json['end'] as num?)?.toInt() ?? 0,
      flags: TextStyleFlags(
        bold: json['bold'] == true,
        italic: json['italic'] == true,
        underline: json['underline'] == true,
        strikethrough: json['strikethrough'] == true,
        foregroundColor: foreground == null
            ? null
            : ColorUtils.tryParseHex(foreground),
        backgroundColor: background == null
            ? null
            : ColorUtils.tryParseHex(background),
      ),
    );
  }
}

/// 单个节点的关键词数据
///
/// 对应合并伴生文件 `xxx.json` 中 `keywords` 下某一项，
/// 同时用于大纲编辑器加载时回填节点关键词。
class OutlineKeywordFileNode {
  /// 节点文本
  final String text;

  /// 节点图片文件名（相对设定项目录下的 image 文件夹）
  final String imageFileName;

  /// 绑定节点全部子孙节点的扁平快照
  final List<OutlineKeywordSubNode> children;

  /// 节点绑定的关键词
  final List<OutlineKeyword> keywords;

  const OutlineKeywordFileNode({
    this.text = '',
    this.imageFileName = '',
    this.children = const [],
    this.keywords = const [],
  });

  /// 从 JSON 反序列化
  factory OutlineKeywordFileNode.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['children'];
    final rawKeywords = json['keywords'];
    return OutlineKeywordFileNode(
      text: (json['text'] as String?) ?? '',
      imageFileName: (json['image'] as String?) ?? '',
      children: [
        if (rawChildren is List)
          for (final child in rawChildren)
            if (child is Map<String, dynamic>)
              OutlineKeywordSubNode.fromJson(child),
      ],
      keywords: [
        if (rawKeywords is List)
          for (final keyword in rawKeywords)
            if (keyword is Map<String, dynamic>)
              OutlineKeyword.fromJson(keyword),
      ],
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
    'text': text,
    if (imageFileName.isNotEmpty) 'image': imageFileName,
    'children': children.map((e) => e.toJson()).toList(),
    'keywords': keywords.map((e) => e.toJson()).toList(),
  };
}

/// 书籍级关键词索引项
///
/// 描述「某个关键词绑定到了哪个设定项的哪个节点」，
/// 供正文编辑器在 Ctrl 状态下高亮、展示悬浮卡片与跳转。
class OutlineKeywordEntry {
  /// 所属设定项 UUID
  final String settingItemUuid;

  /// 所属设定项标题
  final String settingItemTitle;

  /// 节点在大纲树中的层级索引路径（形如 `0.2.1`）
  final String nodePath;

  /// 绑定节点的文本
  final String nodeText;

  /// 绑定节点图片的绝对路径（空字符串表示没有图片）
  ///
  /// 由关键词索引按设定项目录解析，供正文悬浮卡片在标题栏展示缩略图。
  final String imagePath;

  /// 绑定节点全部子孙节点的扁平快照
  final List<OutlineKeywordSubNode> children;

  /// 绑定节点上的全部关键词
  final List<OutlineKeyword> keywords;

  const OutlineKeywordEntry({
    required this.settingItemUuid,
    required this.settingItemTitle,
    required this.nodePath,
    required this.nodeText,
    this.imagePath = '',
    this.children = const [],
    this.keywords = const [],
  });
}
