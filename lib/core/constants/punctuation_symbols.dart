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
class PunctuationSymbols {
  PunctuationSymbols._();

  /// 快捷输入栏的按键顺序
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
}
