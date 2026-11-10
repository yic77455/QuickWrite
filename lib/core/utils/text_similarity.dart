/// 文本相似度工具
///
/// 用于关联目标被编辑后仍能尽量定位：先比较文本是否相同或互相包含，
/// 再按字符二元组的重合程度计算相似度，适合中文段落的局部增删改场景。
class TextSimilarity {
  TextSimilarity._();

  /// 模糊匹配的相似度阈值
  ///
  /// 低于该值时认为不是同一段文字，避免跳转到无关位置。
  static const double matchThreshold = 0.55;

  /// 互相包含时采用的相似度
  ///
  /// 一段文字完整出现在另一段中，通常说明目标被扩写或截断，视为高度相似。
  static const double _containmentScore = 0.8;

  /// 互相包含判定所需的最短文字长度
  ///
  /// 过短的文字容易在大量段落中重复出现，不适合作为包含匹配依据。
  static const int _minContainmentLength = 6;

  /// 计算两段文本的相似度（0~1）
  ///
  /// 忽略空白字符；完全相同返回 1，互相包含返回固定高分，
  /// 其余情况按字符二元组的 Dice 系数计算。
  static double similarity(String a, String b) {
    final String x = _normalize(a);
    final String y = _normalize(b);
    if (x.isEmpty || y.isEmpty) return 0;
    if (x == y) return 1;

    final String shorter = x.length <= y.length ? x : y;
    final String longer = x.length <= y.length ? y : x;
    if (shorter.length >= _minContainmentLength && longer.contains(shorter)) {
      return _containmentScore;
    }

    return _diceCoefficient(x, y);
  }

  /// 去除空白字符，避免排版差异影响比较结果
  static String _normalize(String text) => text.replaceAll(RegExp(r'\s+'), '');

  /// 按字符二元组计算 Dice 相似度
  ///
  /// 二元组对中文的局部增删改较为敏感，且计算量与文本长度线性相关。
  static double _diceCoefficient(String a, String b) {
    // 任一文本不足两个字符时退化为单字符重合度
    if (a.length < 2 || b.length < 2) {
      final Set<String> setA = a.split('').toSet();
      final Set<String> setB = b.split('').toSet();
      final int intersection = setA.intersection(setB).length;
      if (intersection == 0) return 0;
      return 2 * intersection / (setA.length + setB.length);
    }

    final Map<String, int> grams = {};
    for (int i = 0; i < a.length - 1; i++) {
      final String gram = a.substring(i, i + 2);
      grams[gram] = (grams[gram] ?? 0) + 1;
    }

    int intersection = 0;
    for (int i = 0; i < b.length - 1; i++) {
      final String gram = b.substring(i, i + 2);
      final int? count = grams[gram];
      if (count != null && count > 0) {
        intersection++;
        grams[gram] = count - 1;
      }
    }

    final int total = (a.length - 1) + (b.length - 1);
    return total == 0 ? 0 : 2 * intersection / total;
  }
}
