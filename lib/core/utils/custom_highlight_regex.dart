/// 自定义高亮的正则表达式工具
///
/// 纯 Dart 实现（不依赖 Flutter），供服务层校验配置、渲染层解析命中区间共用。
/// 对外方法一律不抛异常：语法非法、运行时异常都降级为「不匹配」，
/// 保证云端同步过来或手工编辑出的坏配置不会让编辑器崩溃。
class CustomHighlightRegex {
  CustomHighlightRegex._();

  /// 单条表达式最多参与着色的命中数
  ///
  /// `.*` 之类表达式会命中全文每个字符，范围过多会拖慢高亮范围的
  /// 扫描线合并（HighlightRangeResolver.mergeRanges），故设上限。
  static const int maxMatches = 1000;

  /// 最多遍历的匹配次数（含零宽命中），用于限制病态表达式的扫描开销
  static const int _maxScanned = maxMatches * 4;

  /// 编译用户输入的正则表达式，语法非法时返回 null
  ///
  /// [multiLine] 让 `^`/`$` 按行生效，符合逐行写作的正文结构；
  /// 其余选项保持 Dart RegExp 默认值（区分大小写、`.` 不跨行），
  /// 与字面量模式的匹配直觉一致。
  static RegExp? tryCompile(String pattern) {
    if (pattern.isEmpty) return null;
    try {
      return RegExp(pattern, multiLine: true);
    } catch (_) {
      // FormatException：括号/字符类未闭合、量词无目标等
      return null;
    }
  }

  /// 表达式语法是否合法
  static bool isValid(String pattern) => tryCompile(pattern) != null;

  /// 计算表达式在 [text] 中的命中区间（全文 UTF-16 偏移，左闭右开）
  ///
  /// - 表达式含捕获组时优先只高亮第 1 组，便于用 `【([^】]*)】`
  ///   只着色成对符号内部；无法在命中段内定位分组文本时退回整段命中
  /// - 跳过零宽命中，避免 `.*?` 之类表达式产生大量空范围
  /// - 命中数与遍历次数均设上限，且捕获引擎异常时保留已解析的部分
  static List<({int start, int end})> findMatches(String text, RegExp regex) {
    final List<({int start, int end})> result = [];
    if (text.isEmpty) return result;

    int scanned = 0;
    try {
      for (final Match match in regex.allMatches(text)) {
        scanned++;
        if (scanned > _maxScanned || result.length >= maxMatches) break;

        int start = match.start;
        int end = match.end;
        if (end <= start) continue;

        if (match.groupCount >= 1) {
          // group(1) 在 groupCount == 0 时会抛 RangeError，必须先判分组数
          final String? group = match.group(1);
          if (group != null && group.isNotEmpty) {
            final int groupStart = text.indexOf(group, start);
            if (groupStart >= start && groupStart + group.length <= end) {
              start = groupStart;
              end = groupStart + group.length;
            }
          }
        }
        result.add((start: start, end: end));
      }
    } catch (_) {
      // 病态回溯等引擎异常：本条表达式不再继续解析，返回已得到的范围
    }
    return result;
  }
}
