import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/theme_provider.dart';
import 'package:quick_write/core/theme/custom_theme.dart';
import 'package:quick_write/core/theme/theme_palette.dart';
import 'package:quick_write/core/utils/color_utils.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/pages/home/settings/custom_theme_editor.dart';
import 'package:quick_write/shared/widgets/widgets.dart';
import 'package:uuid/uuid.dart';

/// 主题弹窗中的自定义主题区域
///
/// 展示默认配色与已保存的自定义主题，支持选中、新建、编辑配色、重命名与删除
class CustomThemeSection extends StatelessWidget {
  const CustomThemeSection({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final brightness = Theme.of(context).brightness;
    // 内置调色板：默认配色的预览不受当前激活的自定义主题影响
    final basePalette = brightness == Brightness.dark
        ? ThemePalette.dark
        : ThemePalette.light;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行与新建入口
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '自定义主题',
                  style: context.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _createTheme(context, themeProvider),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建'),
              ),
            ],
          ),
        ),
        // 默认配色项，用于取消激活自定义主题
        _ThemeEntry(
          name: '默认配色',
          previewColor: basePalette.primary,
          selected: themeProvider.activeCustomThemeId == null,
          onTap: () => themeProvider.setActiveCustomTheme(null),
        ),
        // 已保存的自定义主题
        for (final theme in themeProvider.customThemes)
          _ThemeEntry(
            name: theme.name,
            previewColor: _previewPrimary(theme, basePalette, brightness),
            selected: themeProvider.activeCustomThemeId == theme.id,
            onTap: () => themeProvider.setActiveCustomTheme(theme.id),
            trailing: _buildThemeMenu(themeProvider, theme),
          ),
      ],
    );
  }

  /// 计算主题在当前亮度下的主色预览色
  ///
  /// 未覆盖主色时使用该亮度基底的内置主色
  Color _previewPrimary(
    CustomTheme theme,
    ThemePalette basePalette,
    Brightness brightness,
  ) {
    final keyColors = brightness == Brightness.dark ? theme.dark : theme.light;
    final hex = keyColors.primary;
    return hex != null ? ColorUtils.parseHex(hex) : basePalette.primary;
  }

  /// 构建主题条目的操作菜单按钮
  Widget _buildThemeMenu(ThemeProvider themeProvider, CustomTheme theme) {
    // 借助 Builder 取得按钮自身的上下文，用于定位弹出菜单
    return Builder(
      builder: (buttonContext) => IconButton(
        icon: const Icon(Icons.more_horiz, size: 18),
        tooltip: '更多操作',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        onPressed: () => _showThemeMenu(buttonContext, themeProvider, theme),
      ),
    );
  }

  /// 显示主题条目的操作菜单
  void _showThemeMenu(
    BuildContext buttonContext,
    ThemeProvider themeProvider,
    CustomTheme theme,
  ) {
    final renderBox = buttonContext.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    showMenu<String>(
      context: buttonContext,
      position: RelativeRect.fromLTRB(
        offset.dx + size.width - 120,
        offset.dy + size.height + 4,
        offset.dx + size.width,
        offset.dy + size.height,
      ),
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 180),
      popUpAnimationStyle: AnimationStyle.noAnimation,
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      items: const [
        PopupMenuItem<String>(
          value: 'edit',
          height: 32,
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('编辑配色'),
        ),
        PopupMenuItem<String>(
          value: 'rename',
          height: 32,
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('重命名'),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          height: 32,
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('删除'),
        ),
      ],
    ).then((value) {
      if (!buttonContext.mounted) return;
      switch (value) {
        case 'edit':
          _editTheme(buttonContext, themeProvider, theme);
          break;
        case 'rename':
          _renameTheme(buttonContext, themeProvider, theme);
          break;
        case 'delete':
          _deleteTheme(buttonContext, themeProvider, theme);
          break;
      }
    });
  }

  /// 新建主题：创建后立即激活并进入配色编辑
  Future<void> _createTheme(
    BuildContext context,
    ThemeProvider themeProvider,
  ) async {
    final theme = CustomTheme(
      id: const Uuid().v4(),
      name: '自定义主题 ${themeProvider.customThemes.length + 1}',
    );
    await themeProvider.addCustomTheme(theme);
    await themeProvider.setActiveCustomTheme(theme.id);
    if (!context.mounted) return;
    await _editTheme(context, themeProvider, theme);
  }

  /// 编辑主题的关键色
  Future<void> _editTheme(
    BuildContext context,
    ThemeProvider themeProvider,
    CustomTheme theme,
  ) {
    return showCustomThemeEditor(
      context: context,
      theme: theme,
      onChanged: (updated) => themeProvider.updateCustomTheme(updated),
    );
  }

  /// 重命名主题
  Future<void> _renameTheme(
    BuildContext context,
    ThemeProvider themeProvider,
    CustomTheme theme,
  ) {
    return showInputDialog(
      context: context,
      title: '重命名主题',
      hintText: '请输入主题名称',
      initialValue: theme.name,
      onConfirm: (value) async {
        final name = value.trim();
        if (name.isEmpty) return '名称不能为空';
        await themeProvider.updateCustomTheme(theme.copyWith(name: name));
        return null;
      },
    );
  }

  /// 删除主题，删除当前激活主题时自动回落内置配色
  Future<void> _deleteTheme(
    BuildContext context,
    ThemeProvider themeProvider,
    CustomTheme theme,
  ) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: '删除主题',
      description: '确定要删除「${theme.name}」吗？此操作不可撤销。',
      type: ConfirmType.delete,
      confirmText: '删除',
    );
    if (!confirmed) return;
    await themeProvider.removeCustomTheme(theme.id);
  }
}

/// 自定义主题区域中的单个条目
///
/// 左侧展示主色预览，选中时显示主色描边与勾选标记
class _ThemeEntry extends StatelessWidget {
  /// 主题名称
  final String name;

  /// 主色预览色
  final Color previewColor;

  /// 是否为当前激活项
  final bool selected;

  /// 点击回调
  final VoidCallback onTap;

  /// 右侧附加控件（操作菜单）
  final Widget? trailing;

  const _ThemeEntry({
    required this.name,
    required this.previewColor,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: colorScheme.onSurface.withValues(alpha: 0.06),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: EdgeInsets.fromLTRB(12, 8, trailing != null ? 4 : 12, 8),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: selected ? 1.5 : 1,
            ),
          ),
          // 固定行高，保证默认配色与自定义主题条目高度一致
          child: SizedBox(
            height: 32,
            child: Row(
              children: [
                // 主色预览圆点
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: previewColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 主题名称
                Expanded(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: context.bodyMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
                // 激活标记
                if (selected)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.check_circle,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                  ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
