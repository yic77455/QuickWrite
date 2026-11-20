/// 快捷输入栏的标点符号按键
///
/// 描述一个标点按键：[symbol] 为按键显示与插入的符号，
/// [closing] 为该符号成对时的结束符号（不成对时为 null）。
class PunctuationSymbol {
  /// 按键显示与插入的符号
  final String symbol;

  /// 成对符号的结束符号，null 表示该符号不成对
  final String? closing;

  const PunctuationSymbol(this.symbol, {this.closing});

  /// 是否成对符号的起始符号
  bool get isPairStart => closing != null;
}

/// 正文标点符号表
///
/// 快捷输入栏的按键、以及编辑器自动补全使用的成对符号统一由此提供，
/// 保证两处的标点集合始终一致。
/// 用户可在设置中以文本形式自定义符号列表，文本与源码中的写法一致：
/// 每行一个符号并用单引号包裹，成对符号在逗号后追加 `closing: '结束符号'`。
class PunctuationSymbols {
  PunctuationSymbols._();

  /// 解析符号列表文本时匹配单引号包裹内容的正则
  static final RegExp _quotedTokenPattern = RegExp(r"'([^']*)'");

  /// 默认的快捷输入栏按键顺序
  static const List<PunctuationSymbol> quickInputKeys = [
    PunctuationSymbol('，'),
    PunctuationSymbol('。'),
    PunctuationSymbol('？'),
    PunctuationSymbol('！'),
    PunctuationSymbol('、'),
    PunctuationSymbol('：'),
    PunctuationSymbol('；'),
    PunctuationSymbol('“', closing: '”'),
    PunctuationSymbol('”'),
    PunctuationSymbol('‘', closing: '’'),
    PunctuationSymbol('’'),
    PunctuationSymbol('「', closing: '」'),
    PunctuationSymbol('」'),
    PunctuationSymbol('（', closing: '）'),
    PunctuationSymbol('）'),
    PunctuationSymbol('《', closing: '》'),
    PunctuationSymbol('》'),
    PunctuationSymbol('【', closing: '】'),
    PunctuationSymbol('】'),
    PunctuationSymbol('……'),
    PunctuationSymbol('——'),
    PunctuationSymbol('·'),
  ];

  /// 将符号列表格式化为可编辑文本
  ///
  /// 每行一个符号并以单引号包裹，成对符号在其后追加 `, closing: '结束符号'`，
  /// 与源码中的书写格式保持一致。
  static String formatSymbolList(Iterable<PunctuationSymbol> symbols) {
    return symbols.map((symbol) {
      final String head = "'${symbol.symbol}'";
      final String? closing = symbol.closing;
      return closing == null ? head : "$head, closing: '$closing'";
    }).join('\n');
  }

  /// 解析符号列表文本
  ///
  /// 逐行读取单引号中的内容：第一个是按键符号，第二个（存在时）为成对符号的
  /// 结束符号。空行与不含符号的行会被跳过；文本为空或没有任何有效符号时
  /// 返回默认符号列表。
  static List<PunctuationSymbol> parseSymbolList(String? text) {
    if (text == null) return quickInputKeys;

    final List<PunctuationSymbol> symbols = [];
    for (final String line in text.split('\n')) {
      final List<String> tokens = _quotedTokenPattern
          .allMatches(line)
          .map((match) => match.group(1)!)
          .where((token) => token.isNotEmpty)
          .toList();
      if (tokens.isEmpty) continue;
      symbols.add(PunctuationSymbol(
        tokens.first,
        closing: tokens.length > 1 ? tokens[1] : null,
      ));
    }
    return symbols.isEmpty ? quickInputKeys : symbols;
  }
}
