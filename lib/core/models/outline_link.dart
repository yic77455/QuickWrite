/// 大纲关联数据模型
///
/// 描述大纲编辑器中被关联的文本片段及其跳转目标。
/// 文本片段的位置记录在节点的样式区间中（通过关联标识关联），
/// 关联目标信息持久化到设定项文件旁的伴生 `.link.json`。
library;

/// 关联目标类型
enum OutlineLinkTargetType {
  /// 正文文件（章节）
  chapter,

  /// 设定文件（大纲）
  setting,
}

/// 关联目标信息
///
/// 记录被关联文件的标识、展示名称以及跳转定位信息：
/// - 正文文件：记录段落序号与段落文本，跳转时优先按文本匹配，失败时按序号兜底
/// - 设定文件：记录大纲节点的层级索引路径，跳转时优先按路径定位，失败时按文本兜底
class OutlineLinkTarget {
  /// 关联标识
  ///
  /// 与节点样式区间中的关联标识一一对应，用于从文本片段反查跳转目标。
  final String id;

  /// 目标类型（正文文件 / 设定文件）
  final OutlineLinkTargetType type;

  /// 目标文件 UUID（章节或设定项）
  final String targetUuid;

  /// 目标文件标题（关联设置时的快照，用于界面展示）
  final String targetTitle;

  /// 大纲节点的层级索引路径（形如 `0.2.1`，仅设定文件使用）
  final String nodePath;

  /// 段落序号（从 0 开始，仅正文文件使用）
  final int paragraphIndex;

  /// 关联时正文文件的段落总数（仅正文文件使用）
  ///
  /// 用于判断段落序号是否仍然可信：段落数量变化后序号可能整体偏移，
  /// 此时不再按序号兜底，避免跳转到错误段落。
  final int paragraphCount;

  /// 目标内容文本快照
  ///
  /// 正文文件记录该段落文本，设定文件记录节点文本；
  /// 跳转时用于在文件内容或结构变化后仍能定位到目标。
  final String anchorText;

  const OutlineLinkTarget({
    this.id = '',
    required this.type,
    required this.targetUuid,
    this.targetTitle = '',
    this.nodePath = '',
    this.paragraphIndex = 0,
    this.paragraphCount = 0,
    this.anchorText = '',
  });

  /// 创建修改后的副本
  OutlineLinkTarget copyWith({
    String? id,
    OutlineLinkTargetType? type,
    String? targetUuid,
    String? targetTitle,
    String? nodePath,
    int? paragraphIndex,
    int? paragraphCount,
    String? anchorText,
  }) {
    return OutlineLinkTarget(
      id: id ?? this.id,
      type: type ?? this.type,
      targetUuid: targetUuid ?? this.targetUuid,
      targetTitle: targetTitle ?? this.targetTitle,
      nodePath: nodePath ?? this.nodePath,
      paragraphIndex: paragraphIndex ?? this.paragraphIndex,
      paragraphCount: paragraphCount ?? this.paragraphCount,
      anchorText: anchorText ?? this.anchorText,
    );
  }

  /// 从 JSON 反序列化
  factory OutlineLinkTarget.fromJson(Map<String, dynamic> json) {
    return OutlineLinkTarget(
      type: json['type'] == OutlineLinkTargetType.setting.name
          ? OutlineLinkTargetType.setting
          : OutlineLinkTargetType.chapter,
      targetUuid: (json['targetUuid'] as String?) ?? '',
      targetTitle: (json['targetTitle'] as String?) ?? '',
      nodePath: (json['nodePath'] as String?) ?? '',
      paragraphIndex: (json['paragraphIndex'] as num?)?.toInt() ?? 0,
      paragraphCount: (json['paragraphCount'] as num?)?.toInt() ?? 0,
      anchorText: (json['anchorText'] as String?) ?? '',
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
        'type': type.name,
        'targetUuid': targetUuid,
        if (targetTitle.isNotEmpty) 'targetTitle': targetTitle,
        if (nodePath.isNotEmpty) 'nodePath': nodePath,
        if (type == OutlineLinkTargetType.chapter) 'paragraphIndex': paragraphIndex,
        if (type == OutlineLinkTargetType.chapter) 'paragraphCount': paragraphCount,
        if (anchorText.isNotEmpty) 'anchorText': anchorText,
      };
}

/// 节点内的关联文本范围
///
/// 记录关联标识在节点文本中的起止位置，用于把关联目标写回节点样式区间。
/// 同时保存被关联的文字内容，加载时若位置因编辑产生偏差，可按文字重新定位。
class OutlineLinkRange {
  /// 起始位置（包含）
  final int start;

  /// 结束位置（不包含）
  final int end;

  /// 关联标识
  final String linkId;

  /// 关联文本快照
  final String text;

  const OutlineLinkRange({
    required this.start,
    required this.end,
    required this.linkId,
    this.text = '',
  });

  /// 从 JSON 反序列化
  factory OutlineLinkRange.fromJson(Map<String, dynamic> json) {
    return OutlineLinkRange(
      start: (json['start'] as num?)?.toInt() ?? 0,
      end: (json['end'] as num?)?.toInt() ?? 0,
      linkId: (json['linkId'] as String?) ?? '',
      text: (json['text'] as String?) ?? '',
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
        'start': start,
        'end': end,
        'linkId': linkId,
        if (text.isNotEmpty) 'text': text,
      };
}

/// 单个设定项的关联伴生文件内容
class OutlineLinkFile {
  /// 关联标识到关联目标的映射
  final Map<String, OutlineLinkTarget> links;

  /// 节点路径到关联文本范围的映射（仅包含存在关联文本的节点）
  final Map<String, List<OutlineLinkRange>> nodes;

  const OutlineLinkFile({
    this.links = const {},
    this.nodes = const {},
  });

  /// 空文件内容
  static const OutlineLinkFile empty = OutlineLinkFile();
}
