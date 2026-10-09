import 'package:flutter/material.dart';
import 'package:quick_write/core/theme/custom_theme.dart';
import 'package:quick_write/core/theme/theme_palette.dart';
import 'package:quick_write/core/utils/color_utils.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/shared/dialogs/color_picker_dialog.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 关键的单个语义色字段描述
///
/// 描述编辑器列表中的一项关键色：显示名称、在 [KeyColors] 中的读写方式，
/// 以及基底调色板中对应的锚点颜色（未覆盖时作为取色器的初始颜色）
class _KeyColorField {
  /// 显示名称
  final String label;

  /// 读取当前关键色覆盖值
  final String? Function(KeyColors colors) read;

  /// 写入关键色覆盖值，传入 null 表示重置为未覆盖
  final KeyColors Function(KeyColors colors, String? value) write;

  /// 基底调色板中对应的锚点颜色
  final Color Function(ThemePalette palette) base;

  const _KeyColorField({
    required this.label,
    required this.read,
    required this.write,
    required this.base,
  });
}

/// 编辑器中可调整的关键色字段清单（按展示顺序排列）
final List<_KeyColorField> _keyColorFields = [
  _KeyColorField(
    label: '主色调',
    read: (colors) => colors.primary,
    write: (colors, value) => colors.copyWith(primary: value),
    base: (palette) => palette.primary,
  ),
  _KeyColorField(
    label: '强调色',
    read: (colors) => colors.accent,
    write: (colors, value) => colors.copyWith(accent: value),
    base: (palette) => palette.secondary,
  ),
  _KeyColorField(
    label: '页面背景',
    read: (colors) => colors.background,
    write: (colors, value) => colors.copyWith(background: value),
    base: (palette) => palette.scaffoldBackground,
  ),
  _KeyColorField(
    label: '表面色',
    read: (colors) => colors.surface,
    write: (colors, value) => colors.copyWith(surface: value),
    base: (palette) => palette.surface,
  ),
  _KeyColorField(
    label: '主要文字',
    read: (colors) => colors.text,
    write: (colors, value) => colors.copyWith(text: value),
    base: (palette) => palette.text,
  ),
  _KeyColorField(
    label: '次要文字',
    read: (colors) => colors.textSecondary,
    write: (colors, value) => colors.copyWith(textSecondary: value),
    base: (palette) => palette.textSecondary,
  ),
  _KeyColorField(
    label: '边框',
    read: (colors) => colors.border,
    write: (colors, value) => colors.copyWith(border: value),
    base: (palette) => palette.outline,
  ),
  _KeyColorField(
    label: '悬停背景',
    read: (colors) => colors.hover,
    write: (colors, value) => colors.copyWith(hover: value),
    base: (palette) => palette.hover,
  ),
  _KeyColorField(
    label: '选中背景',
    read: (colors) => colors.selection,
    write: (colors, value) => colors.copyWith(selection: value),
    base: (palette) => palette.selection,
  ),
  _KeyColorField(
    label: '错误色',
    read: (colors) => colors.error,
    write: (colors, value) => colors.copyWith(error: value),
    base: (palette) => palette.error,
  ),
];

/// 显示自定义主题的关键色编辑对话框
///
/// [theme] 待编辑的自定义主题
/// [onChanged] 关键色发生变化时的回调，携带更新后的主题
Future<void> showCustomThemeEditor({
  required BuildContext context,
  required CustomTheme theme,
  required ValueChanged<CustomTheme> onChanged,
}) {
  return showDialogBase(
    context: context,
    title: '编辑配色 · ${theme.name}',
    width: 420,
    height: 560,
    content: _CustomThemeEditorContent(theme: theme, onChanged: onChanged),
  );
}

/// 关键色编辑对话框内容
///
/// 通过浅色/深色基底切换分别编辑两套关键色，逐项点击即可调色，
/// 未调整的关键色自动继承所选基底。
class _CustomThemeEditorContent extends StatefulWidget {
  /// 待编辑的主题
  final CustomTheme theme;

  /// 变化回调
  final ValueChanged<CustomTheme> onChanged;

  const _CustomThemeEditorContent({required this.theme, required this.onChanged});

  @override
  State<_CustomThemeEditorContent> createState() => _CustomThemeEditorContentState();
}

class _CustomThemeEditorContentState extends State<_CustomThemeEditorContent> {
  /// 正在编辑的主题（含用户已做的修改）
  late CustomTheme _theme;

  /// 当前正在编辑的关键色所属基底
  Brightness _brightness = Brightness.light;

  @override
  void initState() {
    super.initState();
    _theme = widget.theme;
  }

  /// 当前基底下正在编辑的关键色集合
  KeyColors get _keyColors => _brightness == Brightness.dark ? _theme.dark : _theme.light;

  /// 当前基底对应的内置调色板
  ThemePalette get _basePalette => _brightness == Brightness.dark ? ThemePalette.dark : ThemePalette.light;

  /// 更新当前基底的关键色集合，并通知外部
  void _updateKeyColors(KeyColors colors) {
    setState(() {
      _theme = _brightness == Brightness.dark
          ? _theme.copyWith(dark: colors)
          : _theme.copyWith(light: colors);
    });
    widget.onChanged(_theme);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 基底切换：亮/暗两套关键色分别编辑
          SegmentedControl(
            labels: const ['浅色基底', '深色基底'],
            selectedIndex: _brightness == Brightness.dark ? 1 : 0,
            onChanged: (index) {
              setState(() {
                _brightness = index == 1 ? Brightness.dark : Brightness.light;
              });
            },
          ),
          const SizedBox(height: 12),
          // 说明文字
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '点击任意颜色进行调整，未调整的颜色自动继承基底。',
              style: context.bodySmall?.copyWith(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // 关键色列表
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final field in _keyColorFields)
                    _KeyColorRow(
                      label: field.label,
                      overrideHex: field.read(_keyColors),
                      baseColor: field.base(_basePalette),
                      onChanged: (value) => _updateKeyColors(field.write(_keyColors, value)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个关键色的编辑行
///
/// 展示当前生效的颜色与取值，点击行打开取色器，
/// 尾部按钮可将该颜色重置回继承基底的状态。
class _KeyColorRow extends StatelessWidget {
  /// 关键色名称
  final String label;

  /// 用户覆盖的颜色，为 null 表示继承基底
  final String? overrideHex;

  /// 基底对应锚点颜色（未覆盖时生效）
  final Color baseColor;

  /// 颜色变化回调，传入 null 表示重置为继承基底
  final ValueChanged<String?> onChanged;

  const _KeyColorRow({
    required this.label,
    required this.overrideHex,
    required this.baseColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOverridden = overrideHex != null;
    final effectiveColor = isOverridden ? ColorUtils.parseHex(overrideHex!) : baseColor;
    final hexText = ColorUtils.toHex(effectiveColor);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ColorPickerDialog.show(
          context: context,
          title: label,
          initialColorHex: hexText,
          onColorSelected: onChanged,
        ),
        borderRadius: BorderRadius.circular(12),
        hoverColor: colorScheme.onSurface.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              // 颜色预览块
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: effectiveColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                ),
              ),
              const SizedBox(width: 12),
              // 名称与当前取值
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: context.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isOverridden ? hexText : '继承基底 · $hexText',
                      style: context.bodySmall?.copyWith(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              // 重置按钮：仅在已覆盖时可点击
              IconButton(
                icon: const Icon(Icons.restart_alt, size: 18),
                tooltip: '恢复基底颜色',
                onPressed: isOverridden ? () => onChanged(null) : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }
}