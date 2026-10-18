import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:quick_write/core/models/app_settings.dart';
import 'package:quick_write/core/services/font_service.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/color_utils.dart';
import 'package:quick_write/shared/dialogs/color_picker_dialog.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 移动端格式设置卡片
///
/// 由顶部操作栏的格式入口在操作栏下方弹出，每个设置项独占一行，
/// 正文提供字体、字号、样式（字体颜色、加粗、斜体、下划线），
/// 标题提供字号与颜色。样式与颜色按钮复用桌面端工具栏的按钮组件。
/// 当前标签页为大纲编辑器时，仅字体与字号作用于大纲，其余设置项不可用
class MobileFormatCard extends StatefulWidget {
  /// 卡片最大宽度
  static const double maxWidth = 240;

  /// 卡片与屏幕左右边缘的最小留白
  static const double screenMargin = 16;

  /// 当前标签页是否为大纲编辑器
  final bool isOutline;

  /// 卡片的最大高度
  ///
  /// 由弹出方按操作栏下方的屏幕剩余空间给出，内容超出该高度时转为内部纵向滚动，
  /// 避免横屏等纵向空间紧张的场景下设置项被截断
  final double maxHeight;

  const MobileFormatCard({super.key, required this.isOutline, required this.maxHeight});

  @override
  State<MobileFormatCard> createState() => _MobileFormatCardState();
}

class _MobileFormatCardState extends State<MobileFormatCard> {
  /// 卡片内容的内边距
  static const double _padding = 16;

  /// 下拉框宽度
  static const double _dropdownWidth = 130;

  /// 字体下拉框中「选择字体文件」选项的值，用于与真实字体名区分
  static const String _pickFontValue = '__pick_font__';

  /// 字号下拉框中「默认」选项的值，用于与真实字号区分
  static const String _defaultSizeValue = '__default_size__';

  /// 字体下拉框的重建标记，用于在选择「选择字体文件」后强制重建下拉框
  int _fontDropdownNonce = 0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 卡片宽度取最大宽度与「屏幕宽度减去两侧留白」中的较小值，避免贴近屏幕边缘
    final cardWidth = math.min(
      MobileFormatCard.maxWidth,
      MediaQuery.sizeOf(context).width - MobileFormatCard.screenMargin * 2,
    );

    // 以 Material 承载卡片底色与阴影，同时为内部的水波纹控件提供材质层
    return Material(
      color: colorScheme.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: cardWidth,
        // 卡片高度限制在可用空间内，空间不足时内容转为内部纵向滚动，保证设置项都能触达
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: ListenableBuilder(
            // 监听设置变化，使各设置项始终回显当前设置
            listenable: SettingsService.instance,
            builder: (context, _) {
              return SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(_padding, 16, _padding, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildGroupLabel('正文', colorScheme),
                      const SizedBox(height: 12),
                      _buildSettingRow(Icons.text_fields_rounded, '字体', _buildFontDropdown()),
                      const SizedBox(height: 10),
                      _buildSettingRow(Icons.format_size_rounded, '字号', _buildFontSizeDropdown()),
                      const SizedBox(height: 10),
                      _wrapDisabled(_buildStyleRow()),
                      _buildDivider(colorScheme),
                      _buildGroupLabel('标题', colorScheme),
                      const SizedBox(height: 12),
                      _wrapDisabled(_buildSettingRow(Icons.format_size_rounded, '字号', _buildTitleFontSizeDropdown())),
                      const SizedBox(height: 10),
                      _wrapDisabled(_buildTitleColorRow(colorScheme)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 构建分组标签（主色竖条 + 标题文字）
  Widget _buildGroupLabel(String text, ColorScheme colorScheme) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }

  /// 构建设置行（行首图标 + 设置名称，行尾控件）
  Widget _buildSettingRow(IconData icon, String label, Widget control) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        control,
      ],
    );
  }

  /// 构建分组之间的分隔线
  Widget _buildDivider(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
    );
  }

  /// 按大纲编辑器的可用性包装设置项
  ///
  /// 大纲编辑器下仅字体与字号生效，其余设置项拦截点击并降低不透明度
  Widget _wrapDisabled(Widget child) {
    if (!widget.isOutline) return child;
    return IgnorePointer(
      child: Opacity(opacity: 0.38, child: child),
    );
  }

  /// 当前生效的字体（大纲编辑器读取大纲字体）
  String get _currentFontFamily {
    final settings = SettingsService.instance;
    return widget.isOutline ? settings.outlineFontFamily : settings.fontFamily;
  }

  /// 当前生效的字号（大纲编辑器读取大纲字号）
  String get _currentFontSize {
    final settings = SettingsService.instance;
    final double size = widget.isOutline ? settings.outlineFontSize : settings.fontSize;
    return size.toStringAsFixed(0);
  }

  /// 构建字体下拉框（默认 + 已导入字体 + 选择字体文件）
  Widget _buildFontDropdown() {
    return CustomDropdown(
      // 通过重建标记，使「选择字体文件」后下拉框回退显示当前字体
      key: ValueKey('mobile-font-$_fontDropdownNonce'),
      width: _dropdownWidth,
      height: 36,
      value: _currentFontFamily,
      items: [
        // 顶部的「默认」项，用于恢复系统默认字体
        DropdownItem(displayText: '默认', value: SettingsService.instance.defaultFontFamily),
        ...FontService().userFonts.map(
              (font) => DropdownItem(displayText: font.displayName, value: font.fontFamily),
            ),
        const DropdownItem(displayText: '选择字体文件…', value: _pickFontValue),
      ],
      onChanged: _onFontChanged,
    );
  }

  /// 构建正文字号下拉框（默认 + 连续字号）
  Widget _buildFontSizeDropdown() {
    return CustomDropdown(
      width: _dropdownWidth,
      height: 36,
      value: _currentFontSize,
      items: _buildSizeItems(minSize: widget.isOutline ? 10 : 5),
      onChanged: _onFontSizeChanged,
    );
  }

  /// 构建标题字号下拉框（默认 + 连续字号）
  Widget _buildTitleFontSizeDropdown() {
    return CustomDropdown(
      width: _dropdownWidth,
      height: 36,
      value: SettingsService.instance.chapterTitleFontSize.toStringAsFixed(0),
      items: _buildSizeItems(minSize: 12, maxSize: 48),
      onChanged: _onTitleFontSizeChanged,
    );
  }

  /// 构建字号选项（默认 + [minSize] 到 [maxSize] 的连续整数字号）
  List<DropdownItem> _buildSizeItems({required int minSize, int maxSize = 72}) {
    return [
      const DropdownItem(displayText: '默认', value: _defaultSizeValue),
      ...List.generate(maxSize - minSize + 1, (index) {
        final size = (index + minSize).toString();
        return DropdownItem(displayText: size, value: size);
      }),
    ];
  }

  /// 处理字体选择
  Future<void> _onFontChanged(String value) async {
    if (value == _pickFontValue) {
      await _pickFontFile();
      return;
    }
    final settings = SettingsService.instance;
    if (widget.isOutline) {
      await settings.updateOutlineFontFamily(value);
    } else {
      await settings.updateFontFamily(value);
    }
  }

  /// 处理正文字号选择
  Future<void> _onFontSizeChanged(String value) async {
    final double size = value == _defaultSizeValue
        ? (widget.isOutline ? AppSettings.defaults.outlineFontSize : AppSettings.defaults.fontSize)
        : (double.tryParse(value) ?? 0);
    if (size <= 0) return;

    final settings = SettingsService.instance;
    if (widget.isOutline) {
      await settings.updateOutlineFontSize(size);
    } else {
      await settings.updateFontSize(size);
    }
  }

  /// 处理标题字号选择
  Future<void> _onTitleFontSizeChanged(String value) async {
    final double size = value == _defaultSizeValue
        ? AppSettings.defaults.chapterTitleFontSize
        : (double.tryParse(value) ?? 0);
    if (size <= 0) return;

    await SettingsService.instance.updateChapterTitleFontSize(size);
  }

  /// 唤起系统文件选择器导入字体文件并应用到当前编辑器
  Future<void> _pickFontFile() async {
    // 先重建下拉框，避免其把「选择字体文件」当作已选项停留在触发器上
    setState(() => _fontDropdownNonce++);

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['ttf', 'otf', 'ttc'],
      );
    } catch (e) {
      if (mounted) SnackBarService.show(context, '无法打开文件选择器');
      return;
    }

    final path = result?.files.single.path;
    if (path == null) return; // 用户取消了选择

    final info = await FontService().importFontFile(path);
    if (!mounted) return;
    if (info == null) {
      SnackBarService.show(context, '字体文件无法解析，请更换字体文件');
      return;
    }

    final settings = SettingsService.instance;
    if (widget.isOutline) {
      await settings.updateOutlineFontFamily(info.fontFamily);
    } else {
      await settings.updateFontFamily(info.fontFamily);
    }
  }

  /// 构建正文样式按钮行（字体颜色、加粗、斜体、下划线）
  ///
  /// 复用桌面端工具栏的按钮组件，四个按钮等距铺满整行
  Widget _buildStyleRow() {
    final settings = SettingsService.instance;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ColorToolButton(
          tooltip: '字体颜色',
          color: ColorUtils.getFontColorForTheme(context),
          onPressed: _showFontColorPicker,
        ),
        ToggleToolButton(
          icon: Icons.format_bold_rounded,
          tooltip: '加粗',
          isSelected: settings.isBold,
          onChanged: (value) => settings.updateIsBold(value),
        ),
        ToggleToolButton(
          icon: Icons.format_italic_rounded,
          tooltip: '斜体',
          isSelected: settings.isItalic,
          onChanged: (value) => settings.updateIsItalic(value),
        ),
        ToggleToolButton(
          icon: Icons.format_underlined_rounded,
          tooltip: '下划线',
          isSelected: settings.isUnderline,
          onChanged: (value) => settings.updateIsUnderline(value),
        ),
      ],
    );
  }

  /// 构建标题颜色行（设置名称 + 颜色指示器）
  Widget _buildTitleColorRow(ColorScheme colorScheme) {
    return InkWell(
      onTap: _showTitleColorPicker,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.color_lens_outlined, size: 18, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  '颜色',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            // 颜色指示器
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: ColorUtils.getChapterTitleColorForTheme(context),
                shape: BoxShape.circle,
                border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 打开正文字体颜色选择器
  void _showFontColorPicker() {
    ColorPickerDialog.show(
      context: context,
      title: '选择正文字体颜色',
      initialColorHex: ColorUtils.getFontColorHexForTheme(context),
      onColorSelected: (colorHex) => ColorUtils.updateFontColorForTheme(context, colorHex),
    );
  }

  /// 打开章节标题颜色选择器
  void _showTitleColorPicker() {
    ColorPickerDialog.show(
      context: context,
      title: '选择章节标题颜色',
      initialColorHex: ColorUtils.getChapterTitleColorHexForTheme(context),
      onColorSelected: (colorHex) => ColorUtils.updateChapterTitleColorForTheme(context, colorHex),
    );
  }
}
