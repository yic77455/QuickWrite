part of re_editor;

/// 单词边界解析器
///
/// 引擎的字边界接口对中文通常只返回单字。外部可通过 [codeWordBoundaryResolver]
/// 注入按语言规则实现的解析器：返回 [text] 中覆盖 [offset] 位置的词汇范围，
/// 返回 null 表示交由编辑器内置逻辑处理。
typedef CodeWordBoundaryResolver = TextRange? Function(String text, int offset);

/// 全局单词边界解析器，供 [CodeEditor] 在双击选词时调用
CodeWordBoundaryResolver? codeWordBoundaryResolver;
