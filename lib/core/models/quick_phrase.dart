/// 快捷短语
///
/// 一条短语包含两段文本：点击后键入正文的完整内容，
/// 以及显示在快捷短语列表中用于辨认的简短文本。
class QuickPhrase {
  /// 点击后键入编辑器的完整内容
  final String content;

  /// 显示在快捷短语列表中的文本
  final String displayText;

  const QuickPhrase({
    required this.content,
    required this.displayText,
  });

  /// 从 JSON Map 创建快捷短语
  ///
  /// 字段缺失或类型异常时按空文本处理，显示文本为空时以完整内容代替，
  /// 保证列表始终有可显示的文本
  factory QuickPhrase.fromJson(Map<String, dynamic> json) {
    final Object? rawContent = json['content'];
    final Object? rawDisplayText = json['displayText'];
    final String content = rawContent is String ? rawContent : '';
    final String displayText = rawDisplayText is String && rawDisplayText.isNotEmpty
        ? rawDisplayText
        : content;
    return QuickPhrase(
      content: content,
      displayText: displayText,
    );
  }

  /// 将快捷短语转换为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'displayText': displayText,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is QuickPhrase &&
        other.content == content &&
        other.displayText == displayText;
  }

  @override
  int get hashCode => Object.hash(content, displayText);
}
