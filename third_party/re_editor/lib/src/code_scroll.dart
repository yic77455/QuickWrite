part of re_editor;

typedef CodeScrollbarBuilder = Widget Function(BuildContext context, Widget child, ScrollableDetails details);

class CodeScrollController {

  final ScrollController verticalScroller;
  final ScrollController horizontalScroller;

  GlobalKey? _editorKey;

  CodeScrollController({
    ScrollController? verticalScroller,
    ScrollController? horizontalScroller,
  }) : verticalScroller = verticalScroller ?? ScrollController(),
    horizontalScroller = horizontalScroller ?? ScrollController();

  void makeCenterIfInvisible(CodeLinePosition position) {
    _render?.makePositionCenterIfInvisible(position);
  }

  void makeVisible(CodeLinePosition position) {
    _render?.makePositionVisible(position);
  }

  /// 指定逻辑行底部在外部滚动内容坐标系中的偏移
  ///
  /// 供外层滚动容器在 Layout 阶段对齐正文末尾内容使用；
  /// 编辑器尚未完成排版或索引越界时返回 null。
  double? contentBottomOfLine(int index) {
    return _render?.contentBottomOfLine(index);
  }

  void bindEditor(GlobalKey key) {
    _editorKey = key;
  }

  _CodeFieldRender? get _render => _editorKey?.currentContext?.findRenderObject() as _CodeFieldRender?;

  void dispose() {
    _editorKey = null;
  }

}