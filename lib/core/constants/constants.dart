class GlobalConstants {
  /// 应用标题（UI 显示用）
  static const String appTitle = '快码字';

  /// 章节文件扩展名
  static const String chapterFileExtension = '.txt';

  /// 设定项文件扩展名
  static const String settingFileExtension = '.md';

  /// 双击间隔阈值（毫秒）
  /// 两次点击间隔小于此值视为双击
  static const int doubleTapThreshold = 300;

    /// A4纸宽度（96 DPI 下约 794 像素）
  static const double a4Width = 794.0;

  /// A4纸高度（96 DPI 下约 1123 像素）
  static const double a4Height = 1123.0;

  /// 纸张与上层容器之间的顶边距，用于显露纸张上方轮廓
  static const double paperTopMargin = 32.0;

}
