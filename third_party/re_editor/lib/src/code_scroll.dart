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

  /// 指定位置所在可见行顶部在外部滚动内容坐标系中的偏移
  ///
  /// 供外层滚动容器在 Layout 阶段定位光标所在行使用；
  /// 编辑器尚未完成排版或索引越界时返回 null。
  double? contentTopOfPosition(CodeLinePosition position) {
    return _render?.contentTopOfPosition(position);
  }

  /// 正文行高（像素），编辑器尚未排版时返回 0
  double get preferredLineHeight => _render?.preferredLineHeight ?? 0;

  /// 按当前外部滚动偏移重算可见段落
  ///
  /// 供外层滚动容器在 Layout 阶段修正滚动位置后调用，
  /// 使本帧构建的行段落与修正后的滚动位置一致。
  void refreshVisibleParagraphs() {
    _render?.refreshVisibleParagraphs();
  }

  void bindEditor(GlobalKey key) {
    _editorKey = key;
  }

  _CodeFieldRender? get _render => _editorKey?.currentContext?.findRenderObject() as _CodeFieldRender?;

  void dispose() {
    _editorKey = null;
  }

}