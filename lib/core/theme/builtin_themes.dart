import 'custom_theme.dart';

/// 内置主题预设
///
/// 与「默认配色」并列的一组内置配色方案，直接以常量形式提供，
/// 不写入磁盘、不参与自定义主题的增删改，因此不可编辑、不可删除。
/// 每个预设通过固定的 [CustomTheme.id] 标识，明暗两套关键色分别对应
/// 亮色与暗色模式，未覆盖的字段继承对应亮度的内置基底调色板。
class BuiltinThemes {
  // ================= 主题标识 =================

  /// 古典雅韵主题 ID
  static const String classicalId = 'builtin_classical';

  /// 绿色护眼主题 ID
  static const String greenId = 'builtin_green';

  /// 仿羊皮纸主题 ID
  static const String parchmentId = 'builtin_parchment';

  // ================= 主题预设 =================

  /// 古典雅韵：宣纸米色为底，朱砂作主色，青瓷绿为辅，配墨色文字
  static const CustomTheme classical = CustomTheme(
    id: classicalId,
    name: '古典雅韵',
    light: KeyColors(
      primary: '#9C3B2E',
      accent: '#6E8B7B',
      background: '#F4EDE1',
      surface: '#EDE4D3',
      text: '#2E2A24',
      textSecondary: '#8A6A4A',
      border: '#D9C9B0',
      hover: '#EAE0CE',
      selection: '#E2CFB2',
    ),
    dark: KeyColors(
      primary: '#C9735F',
      accent: '#8FA897',
      background: '#1C1916',
      surface: '#262120',
      text: '#EAE0D2',
      textSecondary: '#C6A281',
      border: '#3E362E',
      hover: '#2F2823',
      selection: '#4A3A2E',
    ),
  );

  /// 绿色护眼：低饱和豆沙绿为底，深绿作主色，缓解长时间阅读的视觉疲劳
  static const CustomTheme green = CustomTheme(
    id: greenId,
    name: '绿色护眼',
    light: KeyColors(
      primary: '#2E7D46',
      accent: '#3F8A5C',
      background: '#CDEBD1',
      surface: '#D8F0DC',
      text: '#253324',
      textSecondary: '#37694A',
      border: '#A6CFAD',
      hover: '#C0E4C6',
      selection: '#A9DBB4',
    ),
    dark: KeyColors(
      primary: '#74C08A',
      accent: '#55A87A',
      background: '#10190F',
      surface: '#17231A',
      text: '#D8E8DA',
      textSecondary: '#9CC6A6',
      border: '#2A3B2F',
      hover: '#1E2B20',
      selection: '#294232',
    ),
  );

  /// 仿羊皮纸：暖黄纸张底色，棕褐作主色，暗金为辅，复古书写质感
  static const CustomTheme parchment = CustomTheme(
    id: parchmentId,
    name: '仿羊皮纸',
    light: KeyColors(
      primary: '#8B5E3C',
      accent: '#9A7B3F',
      background: '#F2E7D0',
      surface: '#EBDFC4',
      text: '#3A2E1E',
      textSecondary: '#7A5C38',
      border: '#D6C29A',
      hover: '#E7D8BC',
      selection: '#DFC9A4',
    ),
    dark: KeyColors(
      primary: '#C8A06A',
      accent: '#AE8A55',
      background: '#1B1611',
      surface: '#241E17',
      text: '#EADFC8',
      textSecondary: '#C4A87E',
      border: '#3B3125',
      hover: '#2D251C',
      selection: '#403425',
    ),
  );

  /// 全部内置主题预设（不含「默认配色」，默认配色以未激活任何主题表示）
  static const List<CustomTheme> all = [classical, green, parchment];

  /// 按 ID 查找内置主题预设，未匹配时返回 null
  static CustomTheme? byId(String? id) {
    if (id == null) return null;
    for (final theme in all) {
      if (theme.id == id) return theme;
    }
    return null;
  }

  /// 判断给定 ID 是否属于内置主题
  static bool isBuiltin(String id) => byId(id) != null;

  /// 私有构造函数，防止实例化
  BuiltinThemes._();
}
