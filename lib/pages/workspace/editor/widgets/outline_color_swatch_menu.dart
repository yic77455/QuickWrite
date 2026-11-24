import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quick_write/core/services/cache_services/custom_color_cache_service.dart';
import 'package:quick_write/core/utils/color_utils.dart';
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
/// 第一行固定为无颜色色块与内置颜色，其后为自定义颜色行：
/// 自定义色块以第一行宽度为准换行，行末始终保留打开颜色选择器的入口；
/// 鼠标悬停自定义色块时按 Delete 或 X 可将其从缓存中移除。
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
  });

  @override
  State<OutlineColorSwatchMenu> createState() => _OutlineColorSwatchMenuState();
}

class _OutlineColorSwatchMenuState extends State<OutlineColorSwatchMenu> {
  static const double _swatchSize = 28;
  static const double _swatchGap = 6;
  static const double _runGap = 6;

  /// 新增自定义颜色按钮的圆形直径
  static const double _addButtonSize = 22;

  /// 每行最多显示的色块数量
  static const int _maxPerRow = 6;

  /// 自定义颜色列表
  late List<Color> _customColors;

  /// 鼠标悬停中的自定义色块
  Color? _hoveredCustom;

  /// 一行最多显示的色块数量对应的宽度，所有行按该宽度换行
  double get _trackWidth => _maxPerRow * _swatchSize + (_maxPerRow - 1) * _swatchGap;

  @override
  void initState() {
    super.initState();
    _customColors = CustomColorCacheService.instance.getColors(widget.scene);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
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
        await CustomColorCacheService.instance.addColor(scene, color);
        onSelected(color);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = SizedBox(
      width: _trackWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 内置颜色与自定义颜色合并换行，每行最多 _maxPerRow 个
          Wrap(
            spacing: _swatchGap,
            runSpacing: _runGap,
            children: [
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
              for (final color in _customColors)
                _buildSwatch(
                  fillColor: color,
                  tooltip: '按下 Delete 或 X 删除',
                  selected: !widget.isMixed && widget.currentColor == color,
                  onTap: () => _selectColor(color),
                  deletable: true,
                ),
              _buildAddButton(),
            ],
          ),
        ],
      ),
    );

    return Opacity(
      opacity: widget.enabled ? 1 : 0.45,
      child: IgnorePointer(ignoring: !widget.enabled, child: content),
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
    final Widget swatch = showNoneIcon
        ? ColorSwatchOption(
            isNone: true,
            tooltip: tooltip ?? '默认',
            selected: selected,
            onTap: onTap,
            size: _swatchSize,
          )
        : ColorSwatchOption(
            color: fillColor!,
            tooltip: tooltip,
            selected: selected,
            onTap: onTap,
            size: _swatchSize,
          );

    // 记录悬停的自定义色块，供 Delete / X 删除
    if (!deletable) return swatch;
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredCustom = fillColor!),
      onExit: (_) => _clearHovered(fillColor!),
      child: swatch,
    );
  }

  /// 构建打开颜色选择器的圆形色块按钮
  Widget _buildAddButton() {
    final Color baseColor = Theme.of(context).colorScheme.onSurface;

    return CursorTooltipTarget(
      tooltipContent: const Text('自定义颜色'),
      child: PressScale(
        onTap: _pickCustomColor,
        // 用 28 的占位包住 22 的圆形，保证在 Wrap 中与其它色块垂直居中对齐
        child: SizedBox(
          width: _swatchSize,
          height: _swatchSize,
          child: Center(
            child: Container(
              width: _addButtonSize,
              height: _addButtonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: baseColor.withValues(alpha: 0.28), width: 1.5),
              ),
              child: Icon(Icons.add_rounded, size: 15, color: baseColor.withValues(alpha: 0.6)),
            ),
          ),
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
