import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quick_write/core/services/cache_services/custom_color_cache_service.dart';
import 'package:quick_write/core/utils/color_utils.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/shared/dialogs/color_picker_dialog.dart';
import 'package:quick_write/shared/widgets/color_swatch_option.dart';
import 'package:quick_write/shared/widgets/context_menu.dart';
import 'package:quick_write/shared/widgets/press_scale.dart';
import 'package:quick_write/shared/widgets/qw_tooltip.dart';

/// 颜色子菜单内容的内边距
const EdgeInsets outlineColorSwatchPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 10);

/// 内置色块：颜色与名称
typedef OutlinePresetSwatch = ({Color color, String name});

/// 大纲颜色子菜单的横向色块面板
///
/// 首行可含无颜色色块（由 [showNoneSwatch] 控制）与内置颜色，其后为自定义颜色行：
/// 自定义色块以第一行宽度为准换行，行末始终保留打开颜色选择器的入口；
/// 鼠标悬停自定义色块时按 Delete 或 X 可将其从缓存中移除。
/// 移动端在已有自定义色时额外显示删除模式按钮；紧凑模式供移动端工具栏使用。
class OutlineColorSwatchMenu extends StatefulWidget {
  /// 自定义颜色所属场景（缓存内部按场景分组）
  final String scene;

  /// 内置色块
  final List<OutlinePresetSwatch> presetSwatches;

  /// 打开颜色选择器时的初始颜色
  final Color pickerInitialColor;

  /// 当前生效的颜色，null 表示默认颜色
  final Color? currentColor;

  /// 当前选区颜色是否不一致（不一致时不标记任何色块）
  final bool isMixed;

  /// 是否可用
  final bool enabled;

  /// 颜色选择器标题
  final String pickerTitle;

  /// 选择回调，null 表示恢复默认颜色
  final ValueChanged<Color?> onSelected;

  /// 是否显示「无颜色」色块（字体、字底色需要清空，关键词色不需要）
  final bool showNoneSwatch;

  /// 是否为移动端工具栏的紧凑模式（仅自定义色块与新增、删除按钮）
  final bool compact;

  const OutlineColorSwatchMenu({
    super.key,
    required this.scene,
    required this.presetSwatches,
    required this.pickerInitialColor,
    required this.currentColor,
    required this.enabled,
    required this.pickerTitle,
    required this.onSelected,
    this.isMixed = false,
    this.showNoneSwatch = true,
    this.compact = false,
  });

  @override
  State<OutlineColorSwatchMenu> createState() => _OutlineColorSwatchMenuState();
}

class _OutlineColorSwatchMenuState extends State<OutlineColorSwatchMenu> {
  static const double _swatchSize = 28;
  static const double _swatchGap = 6;
  static const double _runGap = 6;

  /// 新增/删除按钮的圆形直径
  static const double _actionButtonSize = 22;

  /// 每行最多显示的色块数量
  static const int _maxPerRow = 6;

  /// 紧凑模式的色块直径、内部颜色圆直径与点击热区
  static const double _compactSwatchSize = 30;
  static const double _compactInnerSize = 22;
  static const double _compactHitTargetSize = 42;

  /// 自定义颜色列表
  late List<Color> _customColors;

  /// 鼠标悬停中的自定义色块
  Color? _hoveredCustom;

  /// 是否处于删除模式（仅移动端，点击自定义色块即删除）
  bool _deleteMode = false;

  /// 删除模式只在移动端生效，桌面端沿用 Delete / X 快捷键
  bool get _deleting => PlatformCapabilities.isMobile && _deleteMode;

  /// 移动端仅在已有自定义色时显示删除按钮
  bool get _showDeleteButton => PlatformCapabilities.isMobile && _visibleCustomColors.isNotEmpty;

  /// 一行最多显示的色块数量对应的宽度，所有行按该宽度换行
  double get _trackWidth => _maxPerRow * _swatchSize + (_maxPerRow - 1) * _swatchGap;

  /// 展示的自定义色：排除与内置色相同及重复的历史缓存项
  List<Color> get _visibleCustomColors {
    final Set<Color> presets = widget.presetSwatches.map((swatch) => swatch.color).toSet();
    final Set<Color> seen = <Color>{};
    return _customColors.where((color) => !presets.contains(color) && seen.add(color)).toList();
  }

  @override
  void initState() {
    super.initState();
    _customColors = CustomColorCacheService.instance.getColors(widget.scene);
    CustomColorCacheService.instance.revision.addListener(_refreshCustomColors);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    CustomColorCacheService.instance.revision.removeListener(_refreshCustomColors);
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  /// 缓存增删后同步色块
  void _refreshCustomColors() {
    if (!mounted) return;
    setState(() => _customColors = CustomColorCacheService.instance.getColors(widget.scene));
  }

  /// 悬停自定义色块时按 Delete 或 X 删除该色块
  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || !widget.enabled) return false;

    final Color? hovered = _hoveredCustom;
    if (hovered == null) return false;

    final LogicalKeyboardKey key = event.logicalKey;
    if (key != LogicalKeyboardKey.delete && key != LogicalKeyboardKey.keyX) return false;

    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed || keyboard.isMetaPressed || keyboard.isAltPressed) return false;

    _deleteCustom(hovered);
    return true;
  }

  /// 从自定义颜色中移除并同步缓存
  void _deleteCustom(Color color) {
    setState(() {
      _customColors = [..._customColors]..remove(color);
      if (_hoveredCustom == color) _hoveredCustom = null;
      if (PlatformCapabilities.isMobile && _customColors.isEmpty) _deleteMode = false;
    });
    unawaited(CustomColorCacheService.instance.removeColor(widget.scene, color));
  }

  /// 选择颜色并收起菜单
  void _selectColor(Color? color) {
    final ValueChanged<Color?> onSelected = widget.onSelected;
    ContextMenu.dismissCurrent();
    onSelected(color);
  }

  /// 收起菜单后打开颜色选择器，选中的颜色写入缓存并立即应用
  Future<void> _pickCustomColor() async {
    if (!widget.enabled) return;

    final ValueChanged<Color?> onSelected = widget.onSelected;
    final String scene = widget.scene;
    final String title = widget.pickerTitle;
    final List<OutlinePresetSwatch> presets = widget.presetSwatches;
    final String initialHex = ColorUtils.toHex(widget.currentColor ?? widget.pickerInitialColor);
    // 菜单收起后当前组件会被销毁，提前取好窗口上下文
    final BuildContext dialogContext = Navigator.of(context, rootNavigator: true).context;

    // 先收起右键菜单，再弹出颜色选择器
    ContextMenu.dismissCurrent();

    await ColorPickerDialog.show(
      context: dialogContext,
      title: title,
      initialColorHex: initialHex,
      onColorSelected: (String hex) async {
        final Color color = ColorUtils.parseHex(hex);
        if (!presets.any((preset) => preset.color == color)) {
          await CustomColorCacheService.instance.addColor(scene, color);
        }
        if (mounted && PlatformCapabilities.isMobile) setState(() => _deleteMode = false);
        onSelected(color);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = widget.compact ? _buildCompactContent() : _buildMenuContent();

    return Opacity(
      opacity: widget.enabled ? 1 : 0.45,
      child: IgnorePointer(ignoring: !widget.enabled, child: content),
    );
  }

  /// 菜单模式：内置色与自定义色合并换行
  Widget _buildMenuContent() {
    return SizedBox(
      width: _trackWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: _swatchGap,
            runSpacing: _runGap,
            children: [
              if (widget.showNoneSwatch)
                _buildSwatch(
                  selected: !widget.isMixed && widget.currentColor == null,
                  onTap: () => _selectColor(null),
                  showNoneIcon: true,
                ),
              for (final preset in widget.presetSwatches)
                _buildSwatch(
                  fillColor: preset.color,
                  tooltip: preset.name,
                  selected: !widget.isMixed && widget.currentColor == preset.color,
                  onTap: () => _selectColor(preset.color),
                ),
              for (final color in _visibleCustomColors) _buildCustomSwatch(color),
              _buildAddButton(),
              if (_showDeleteButton) _buildDeleteButton(),
            ],
          ),
        ],
      ),
    );
  }

  /// 紧凑模式：仅自定义色块与新增、删除按钮
  Widget _buildCompactContent() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final color in _visibleCustomColors)
          Padding(
            padding: const EdgeInsets.only(right: _swatchGap),
            child: _buildCustomSwatch(color),
          ),
        _buildAddButton(),
        if (_showDeleteButton) ...[
          const SizedBox(width: _swatchGap),
          _buildDeleteButton(),
        ],
      ],
    );
  }

  /// 构建自定义色块：移动端删除模式下点击即删除，桌面端仍为选择
  Widget _buildCustomSwatch(Color color) {
    return _buildSwatch(
      fillColor: color,
      tooltip: PlatformCapabilities.isMobile ? null : '按下 Delete 或 X 删除',
      selected: !widget.isMixed && widget.currentColor == color && !_deleting,
      onTap: _deleting ? () => _deleteCustom(color) : () => _selectColor(color),
      deletable: true,
    );
  }

  /// 构建单个色块（外观与交互由共享的 ColorSwatchOption 统一）
  ///
  /// [showNoneIcon] 为 true 时渲染「无颜色」色块：中性底色 + 斜杠，不再使用具体颜色。
  Widget _buildSwatch({
    Color? fillColor,
    String? tooltip,
    required bool selected,
    required VoidCallback onTap,
    bool deletable = false,
    bool showNoneIcon = false,
  }) {
    final double swatchSize = widget.compact ? _compactSwatchSize : _swatchSize;
    final Widget swatch = showNoneIcon
        ? ColorSwatchOption(
            isNone: true,
            tooltip: tooltip ?? '默认',
            selected: selected,
            onTap: onTap,
            size: swatchSize,
          )
        : ColorSwatchOption(
            color: fillColor!,
            tooltip: tooltip,
            selected: selected,
            onTap: onTap,
            size: swatchSize,
            innerSize: widget.compact ? _compactInnerSize : 20,
            checkSize: widget.compact ? 12 : 13,
            showInnerBorder: widget.compact,
            hitTargetSize: widget.compact ? _compactHitTargetSize : null,
            pressedScale: widget.compact ? 0.82 : 0.9,
            deleteMode: deletable && _deleting,
          );

    // 记录悬停的自定义色块，供 Delete / X 删除
    if (!deletable) return swatch;
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredCustom = fillColor!),
      onExit: (_) => _clearHovered(fillColor!),
      child: swatch,
    );
  }

  /// 构建打开颜色选择器的圆形按钮
  Widget _buildAddButton() {
    final Color baseColor = Theme.of(context).colorScheme.onSurface;

    return CursorTooltipTarget(
      tooltipContent: const Text('自定义颜色'),
      child: PressScale(
        onTap: _pickCustomColor,
        child: _buildActionPlaceholder(
          icon: Icons.add_rounded,
          color: baseColor.withValues(alpha: 0.6),
          borderColor: baseColor.withValues(alpha: 0.28),
        ),
      ),
    );
  }

  /// 构建删除模式切换按钮，激活后点击自定义色块即删除
  Widget _buildDeleteButton() {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color color = _deleteMode ? colorScheme.error : colorScheme.onSurface;

    return CursorTooltipTarget(
      tooltipContent: const Text('删除自定义颜色'),
      child: PressScale(
        onTap: () => setState(() => _deleteMode = !_deleteMode),
        child: _buildActionPlaceholder(
          icon: Icons.remove_rounded,
          color: _deleteMode ? color : color.withValues(alpha: 0.6),
          borderColor: _deleteMode ? color : color.withValues(alpha: 0.28),
          fillColor: _deleteMode ? color.withValues(alpha: 0.1) : null,
        ),
      ),
    );
  }

  /// 圆形按钮的占位容器，保证与其它色块垂直居中对齐
  Widget _buildActionPlaceholder({
    required IconData icon,
    required Color color,
    required Color borderColor,
    Color? fillColor,
  }) {
    // 紧凑模式下与色块的颜色圆同尺寸，点击热区保持 42
    final double diameter = widget.compact ? _compactInnerSize : _actionButtonSize;

    return SizedBox(
      width: widget.compact ? _compactHitTargetSize : _swatchSize,
      height: widget.compact ? _compactHitTargetSize : _swatchSize,
      child: Center(
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fillColor,
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Icon(icon, size: widget.compact ? 12 : 14, color: color),
        ),
      ),
    );
  }

  /// 清除悬停状态
  void _clearHovered(Color color) {
    if (_hoveredCustom != color) return;
    setState(() => _hoveredCustom = null);
  }
}
