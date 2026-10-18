import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/theme_provider.dart';
import 'package:quick_write/core/services/font_service.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/pages/home/settings/custom_theme_list.dart';
import 'package:quick_write/pages/home/settings/setting_widgets.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 外观设置分组
///
/// 包含主题模式切换和暗色模式下封面变暗选项
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final settingsService = SettingsService.instance;

    return SettingSectionCard(
      title: '外观',
      children: [
        _buildThemeTile(context, themeProvider),
        // 界面字体：桌面端从系统字体中选择，移动端无法枚举系统字体，改为弹窗选择字体文件
        _buildAppFontTile(context, themeProvider),
        _buildAppFontSizeTile(themeProvider),
        _buildDimCoverTile(context, settingsService),
      ],
    );
  }

  /// 构建主题切换选项
  Widget _buildThemeTile(BuildContext context, ThemeProvider themeProvider) {
    String themeName;
    IconData themeIcon;

    switch (themeProvider.themeMode) {
      case ThemeMode.light:
        themeName = '浅色模式';
        themeIcon = Icons.light_mode;
        break;
      case ThemeMode.dark:
        themeName = '深色模式';
        themeIcon = Icons.dark_mode;
        break;
      case ThemeMode.system:
        themeName = '跟随系统';
        themeIcon = Icons.settings_suggest;
        break;
    }

    return SettingTile(
      icon: themeIcon,
      title: '主题模式',
      subtitle: themeName,
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _showThemeDialog(context, themeProvider),
    );
  }

  /// 构建暗色模式封面变暗选项
  Widget _buildDimCoverTile(BuildContext context, SettingsService settingsService) {
    return AnimatedBuilder(
      animation: settingsService,
      builder: (context, _) {
        return SettingTile(
          icon: Icons.dark_mode_outlined,
          title: '暗色模式下封面变暗',
          subtitle: '开启后，暗色模式下封面图片会添加遮罩，减少对眼睛的刺激',
          trailing: QwSwitch(
            value: settingsService.dimCoverInDarkMode,
            onChanged: (value) async {
              await settingsService.updateDimCoverInDarkMode(value);
            },
          ),
        );
      },
    );
  }

  /// 构建应用界面字体选择项
  ///
  /// 仅改变应用界面的文字字体，与编辑器正文字体相互独立。
  /// 桌面端可枚举系统字体，直接从下拉框中选择；
  /// 移动端无法枚举系统字体，改为点击后弹窗从已导入的字体文件中选择
  Widget _buildAppFontTile(BuildContext context, ThemeProvider themeProvider) {
    if (PlatformCapabilities.supportsSystemFontEnumeration) {
      return SettingTile(
        icon: Icons.text_fields,
        title: '界面字体',
        subtitle: '仅影响应用界面文字，编辑器字体可在工作台右侧设置面板调整',
        trailing: _buildSystemFontDropdown(themeProvider),
      );
    }

    return SettingTile(
      icon: Icons.text_fields,
      title: '界面字体',
      subtitle: _currentAppFontLabel(themeProvider),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _showFontDialog(context, themeProvider),
    );
  }

  /// 构建系统字体下拉框（桌面端）
  ///
  /// 字体列表顶部插入“默认”选项（空字符串），代表跟随系统默认字体
  Widget _buildSystemFontDropdown(ThemeProvider themeProvider) {
    return CustomDropdown(
      width: 150,
      value: themeProvider.appFontFamily ?? '',
      items: [
        const DropdownItem(displayText: '默认', value: ''),
        ..._buildFontItems(),
      ],
      onChanged: (value) => themeProvider.setAppFontFamily(value.isEmpty ? null : value),
    );
  }

  /// 当前界面字体的显示名称，用于移动端设置项的副标题
  String _currentAppFontLabel(ThemeProvider themeProvider) {
    final family = themeProvider.appFontFamily;
    if (family == null) return '默认';
    for (final font in FontService().userFonts) {
      if (font.fontFamily == family) return font.displayName;
    }
    return family;
  }

  /// 界面字号档位（小/中/大）与缩放倍数的对应关系，中档为默认大小
  static const Map<String, double> _fontScaleOptions = {
    'small': 0.8,
    'medium': 1.0,
    'large': 1.2,
  };

  /// 界面字号档位对应的显示名称
  static const Map<String, String> _fontScaleLabels = {
    'small': '小',
    'medium': '中',
    'large': '大',
  };

  /// 根据当前缩放倍数反查所属档位，用于回显下拉框选中项
  String _fontScaleToOption(double scale) {
    for (final entry in _fontScaleOptions.entries) {
      if ((entry.value - scale).abs() < 0.001) return entry.key;
    }
    return 'medium';
  }

  /// 构建应用界面字号选择项
  ///
  /// 提供小、中、大三档字号，用于适配不同字体在相同字号下的视觉大小差异
  Widget _buildAppFontSizeTile(ThemeProvider themeProvider) {
    // 档位下拉选项由档位映射表派生，保证显示名称与缩放倍数始终一致
    final items = _fontScaleOptions.entries
        .map((entry) => DropdownItem(
              displayText: _fontScaleLabels[entry.key] ?? entry.key,
              value: entry.key,
            ))
        .toList();

    return SettingTile(
      icon: Icons.format_size,
      title: '界面字号',
      subtitle: '调整界面文字大小，编辑器字体不受影响',
      trailing: CustomDropdown(
        width: 90,
        value: _fontScaleToOption(themeProvider.appFontScale),
        items: items,
        onChanged: (value) =>
            themeProvider.setAppFontScale(_fontScaleOptions[value] ?? 1.0),
      ),
    );
  }

  /// 构建可选字体列表
  ///
  /// 取自系统字体服务，字体服务尚未加载完成时回退到常见中文字体
  List<DropdownItem> _buildFontItems() {
    final fonts = FontService().systemFonts;
    if (fonts.isEmpty) {
      return const [
        DropdownItem(displayText: '微软雅黑', value: '微软雅黑'),
        DropdownItem(displayText: '宋体', value: '宋体'),
      ];
    }
    return fonts
        .map((font) => DropdownItem(displayText: font.displayName, value: font.fontFamily))
        .toList();
  }

  /// 显示界面字体选择对话框（移动端）
  void _showFontDialog(BuildContext context, ThemeProvider themeProvider) {
    showDialogBase(
      context: context,
      title: '选择界面字体',
      width: 400,
      height: 480,
      adaptiveHeight: true,
      borderRadius: 18,
      titleFontSize: 15,
      content: _FontPickerContent(
        currentFontFamily: themeProvider.appFontFamily,
        onSelected: (family) async {
          await themeProvider.setAppFontFamily(family);
        },
      ),
    );
  }

  /// 显示主题选择对话框
  void _showThemeDialog(BuildContext context, ThemeProvider themeProvider) {
    showDialogBase(
      context: context,
      title: '选择主题',
      width: 400,
      height: 540,
      adaptiveHeight: true,
      borderRadius: 18,
      titleFontSize: 15,
      content: _ThemePickerContent(
        currentMode: themeProvider.themeMode,
        onSelected: (mode) => themeProvider.setThemeMode(mode),
      ),
    );
  }
}

/// 界面字体选择对话框的内容区域
///
/// 列出「默认」「推荐字体」与用户已导入的字体，每项以该字体自身渲染名称便于预览，
/// 推荐字体可下载，下载后与导入字体一样可选中或删除，
/// 末尾提供「选择字体文件…」入口导入新的字体文件
class _FontPickerContent extends StatelessWidget {
  /// 当前界面字体家族名（null 表示跟随系统默认字体）
  final String? currentFontFamily;

  /// 选中界面字体的回调，传入 null 表示使用默认字体
  final ValueChanged<String?> onSelected;

  const _FontPickerContent({
    required this.currentFontFamily,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final fontService = FontService();

    // 监听字体服务：下载进度与已安装字体列表变化时自动刷新
    return ListenableBuilder(
      listenable: fontService,
      builder: (context, _) {
        final importedFonts = fontService.importedFonts;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FontOptionTile(
                label: '默认',
                selected: currentFontFamily == null,
                onTap: () => _apply(context, null),
              ),
              const _FontGroupLabel('推荐字体'),
              for (final font in FontService.recommendedFonts) ...[
                _buildRecommendedTile(context, font),
                const SizedBox(height: 8),
              ],
              if (importedFonts.isNotEmpty) ...[
                const _FontGroupLabel('已导入字体'),
                for (final font in importedFonts) ...[
                  _FontOptionTile(
                    label: font.displayName,
                    fontFamily: font.fontFamily,
                    selected: currentFontFamily == font.fontFamily,
                    onTap: () => _apply(context, font.fontFamily),
                    action: _TileIconButton(
                      icon: Icons.delete_outline_rounded,
                      onTap: () => _deleteFont(font.fontFamily),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
              const SizedBox(height: 8),
              _FontFileTile(onTap: () => _pickFontFile(context)),
            ],
          ),
        );
      },
    );
  }

  /// 构建推荐字体选项
  ///
  /// 未安装时展示名称并提供下载入口，下载中展示进度，
  /// 已安装时与普通字体一样可选并可删除
  Widget _buildRecommendedTile(BuildContext context, RecommendedFont font) {
    final fontService = FontService();
    final installed = fontService.userFontByFileName(font.fileName);
    if (installed == null) {
      return _FontOptionTile(
        label: font.displayName,
        action: fontService.downloadingFileName == font.fileName
            ? _TileProgress(progress: fontService.downloadProgress)
            : _TileIconButton(
                icon: Icons.download_rounded,
                onTap: () => _downloadFont(context, font),
              ),
      );
    }

    return _FontOptionTile(
      // 保持推荐字体的中文名称，字形预览仍使用其真实字体家族
      label: font.displayName,
      fontFamily: installed.fontFamily,
      selected: currentFontFamily == installed.fontFamily,
      onTap: () => _apply(context, installed.fontFamily),
      action: _TileIconButton(
        icon: Icons.delete_outline_rounded,
        onTap: () => _deleteFont(installed.fontFamily),
      ),
    );
  }

  /// 应用选中的界面字体并关闭对话框
  void _apply(BuildContext context, String? fontFamily) {
    onSelected(fontFamily);
    Navigator.of(context).pop();
  }

  /// 唤起系统文件选择器导入字体文件并应用为界面字体
  Future<void> _pickFontFile(BuildContext context) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['ttf', 'otf', 'ttc'],
      );
    } catch (e) {
      if (context.mounted) SnackBarService.show(context, '无法打开文件选择器');
      return;
    }

    final path = result?.files.single.path;
    if (path == null) return; // 用户取消了选择

    final info = await FontService().importFontFile(path);
    if (!context.mounted) return;
    if (info == null) {
      SnackBarService.show(context, '字体文件无法解析，请更换字体文件');
      return;
    }

    _apply(context, info.fontFamily);
  }

  /// 下载推荐的界面字体
  ///
  /// 下载进度由字体服务记录，对话框关闭后再打开仍会恢复展示
  Future<void> _downloadFont(BuildContext context, RecommendedFont font) async {
    final info = await FontService().downloadFont(font);
    if (info == null && context.mounted) {
      SnackBarService.show(context, '字体下载失败，请检查网络后重试');
    }
  }

  /// 删除已安装的字体，并修正引用了该字体的设置
  Future<void> _deleteFont(String fontFamily) async {
    final deleted = await FontService().deleteUserFont(fontFamily);
    if (!deleted) return;

    // 删除后引用该字体的设置会失效，交由设置服务恢复为默认字体
    await SettingsService.instance.validateFontAvailability();
  }
}

/// 字体分组标题
class _FontGroupLabel extends StatelessWidget {
  /// 标题文字
  final String text;

  const _FontGroupLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8, left: 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}

/// 单个界面字体选项
///
/// 使用字体自身渲染名称以便预览，选中时以主色高亮并显示对勾，
/// 右侧可选地放置下载或删除等操作图标
class _FontOptionTile extends StatelessWidget {
  /// 选项中显示的字体名称
  final String label;

  /// 预览所用的字体家族名，为 null 时使用系统默认字体
  final String? fontFamily;

  /// 是否为当前选中的字体
  final bool selected;

  /// 点击回调，为 null 时该选项不可点击
  final VoidCallback? onTap;

  /// 右侧操作图标，为 null 时不展示
  final Widget? action;

  const _FontOptionTile({
    required this.label,
    this.fontFamily,
    this.selected = false,
    this.onTap,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.primary;

    return Material(
      color: selected ? accent.withValues(alpha: 0.08) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: colorScheme.onSurface.withValues(alpha: 0.06),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent : colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: fontFamily,
                    fontSize: 16,
                    color: selected ? accent : colorScheme.onSurface,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (selected) Icon(Icons.check_rounded, size: 20, color: accent),
              if (action != null) ...[
                const SizedBox(width: 6),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 字体选项右侧的操作图标按钮
class _TileIconButton extends StatelessWidget {
  /// 图标
  final IconData icon;

  /// 点击回调
  final VoidCallback onTap;

  const _TileIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// 字体选项右侧的下载进度指示
class _TileProgress extends StatelessWidget {
  /// 下载进度（0~1），总大小未知时为 null
  final double? progress;

  const _TileProgress({required this.progress});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final percent = progress == null ? null : '${(progress! * 100).round()}%';

    return Padding(
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, value: progress),
          ),
          if (percent != null) ...[
            const SizedBox(width: 6),
            // 固定宽度，避免百分比位数变化时文字左右抖动
            SizedBox(
              width: 34,
              child: Text(
                percent,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 「选择字体文件」入口
class _FontFileTile extends StatelessWidget {
  /// 点击回调
  final VoidCallback onTap;

  const _FontFileTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.primary;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: colorScheme.onSurface.withValues(alpha: 0.06),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(Icons.add_rounded, size: 20, color: accent),
              const SizedBox(width: 8),
              Text(
                '选择字体文件…',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 主题选择对话框的内容区域
///
/// 上方以三列卡片形式展示明暗模式选项，点击卡片即应用并关闭；
/// 下方为自定义主题区域，可管理并激活自定义配色方案。
class _ThemePickerContent extends StatelessWidget {
  /// 当前主题模式
  final ThemeMode currentMode;

  /// 选择主题回调
  final void Function(ThemeMode) onSelected;

  const _ThemePickerContent({
    required this.currentMode,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _ThemeCard(
                    mode: ThemeMode.system,
                    label: '跟随系统',
                    icon: Icons.settings_suggest,
                    selected: currentMode == ThemeMode.system,
                    onSelected: onSelected,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ThemeCard(
                    mode: ThemeMode.light,
                    label: '浅色',
                    icon: Icons.light_mode,
                    selected: currentMode == ThemeMode.light,
                    onSelected: onSelected,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ThemeCard(
                    mode: ThemeMode.dark,
                    label: '深色',
                    icon: Icons.dark_mode,
                    selected: currentMode == ThemeMode.dark,
                    onSelected: onSelected,
                  ),
                ),
              ],
            ),
            // 自定义主题区域
            const CustomThemeSection(),
          ],
        ),
      ),
    );
  }
}

/// 单个主题卡片
///
/// 选中时显示主色边框、主色图标背景和加粗的主色文字
class _ThemeCard extends StatelessWidget {
  /// 该卡片对应的主题模式
  final ThemeMode mode;

  /// 卡片显示名称
  final String label;

  /// 卡片图标
  final IconData icon;

  /// 是否选中
  final bool selected;

  /// 选中回调
  final void Function(ThemeMode) onSelected;

  const _ThemeCard({
    required this.mode,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cardColor = selected
        ? colorScheme.primary.withValues(alpha: 0.08)
        : Colors.transparent;
    final borderColor = selected
        ? colorScheme.primary
        : colorScheme.outlineVariant.withValues(alpha: 0.5);
    final iconBgColor = selected
        ? colorScheme.primary
        : colorScheme.surfaceContainerHighest;
    final iconColor = selected
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant;
    final textColor = selected ? colorScheme.primary : colorScheme.onSurface;

    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          onSelected(mode);
          Navigator.of(context).pop();
        },
        borderRadius: BorderRadius.circular(14),
        hoverColor: colorScheme.primary.withValues(alpha: 0.06),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 图标圆形容器
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 22, color: iconColor),
              ),
              const SizedBox(height: 10),
              // 主题名称
              Text(
                label,
                style: context.bodyMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
