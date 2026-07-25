/// 全文搜索查询解析器
///
/// 支持使用 "&&" 连接多个关键词进行交集搜索，
/// 例如 "张三 && 李四" 表示搜索同时包含"张三"和"李四"的章节。
/// 解析、匹配、计数等纯逻辑均集中于此，便于复用与测试。
class SearchQueryParser {
  SearchQueryParser._();

  /// 多关键词分隔符
  static const String separator = '&&';

  /// 解析搜索查询字符串，返回多个关键词
  ///
  /// 以 [separator] 分割输入，去除每个关键词首尾空白并过滤空串。
  /// 返回的关键词保留原始大小写，由调用方决定是否进行大小写转换。
  ///
  /// 示例：
  /// - "张三 && 李四" -> ["张三", "李四"]
  /// - "  张三 &&  && 李四 " -> ["张三", "李四"]
  /// - "" -> []
  static List<String> parse(String query) {
    if (query.isEmpty) return const [];
    return query
        .split(separator)
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// 判断文本是否同时包含所有关键词（交集匹配）
  ///
  /// [caseSensitive] 控制是否区分大小写。关键词列表为空时返回 false。
  static bool containsAll(
    String text,
    List<String> keywords, {
    bool caseSensitive = false,
  }) {
    if (keywords.isEmpty) return false;
    final source = caseSensitive ? text : text.toLowerCase();
    for (final keyword in keywords) {
      final k = caseSensitive ? keyword : keyword.toLowerCase();
      if (k.isEmpty) continue;
      if (!source.contains(k)) return false;
    }
    return true;
  }

  /// 统计一行文本中所有关键词的匹配次数总和
  ///
  /// 用于显示每行的匹配数量。[caseSensitive] 控制是否区分大小写。
  static int countMatches(
    String line,
    List<String> keywords, {
    bool caseSensitive = false,
  }) {
    if (keywords.isEmpty) return 0;
    final sourceLine = caseSensitive ? line : line.toLowerCase();
    int total = 0;
    for (final keyword in keywords) {
      final k = caseSensitive ? keyword : keyword.toLowerCase();
      if (k.isEmpty) continue;
      int start = 0;
      while (true) {
        final index = sourceLine.indexOf(k, start);
        if (index == -1) break;
        total++;
        start = index + k.length;
      }
    }
    return total;
  }

  /// 在文本中查找最早出现的关键词位置
  ///
  /// 从 [start] 开始搜索，比较所有关键词在该位置的首次匹配，
  /// 返回起始偏移量最小的那个。无匹配时返回 null。
  /// 用于点击搜索结果时定位到具体的匹配位置。
  static KeywordMatch? findFirstMatch(
    String text,
    List<String> keywords, {
    int start = 0,
    bool caseSensitive = false,
  }) {
    if (keywords.isEmpty) return null;
    final source = caseSensitive ? text : text.toLowerCase();

    KeywordMatch? best;
    for (final keyword in keywords) {
      final k = caseSensitive ? keyword : keyword.toLowerCase();
      if (k.isEmpty) continue;
      final index = source.indexOf(k, start);
      if (index == -1) continue;
      if (best == null || index < best.start) {
        best = KeywordMatch(start: index, length: k.length);
      }
    }
    return best;
  }
}

/// 单个关键词匹配的位置信息
class KeywordMatch {
  /// 匹配起始偏移量
  final int start;

  /// 匹配长度
  final int length;

  const KeywordMatch({required this.start, required this.length});
}
