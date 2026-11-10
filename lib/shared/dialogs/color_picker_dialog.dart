import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:quick_write/core/utils/color_utils.dart';
import 'package:quick_write/shared/widgets/qw_dialogs.dart';
import 'package:quick_write/shared/widgets/qw_tooltip.dart';

/// 颜色选择器对话框
class ColorPickerDialog {
  /// 显示颜色选择器对话框
  ///
  /// [context] - BuildContext
  /// [title] - 对话框标题
  /// [initialColorHex] - 初始颜色的十六进制字符串（#RRGGBB 格式，null 表示使用主题默认颜色）
  /// [onColorSelected] - 颜色选择完成后的回调，参数为选择的颜色（十六进制字符串格式）
  static Future<void> show({
    required BuildContext context,
    required String title,
    required String? initialColorHex,
    required ValueChanged<String> onColorSelected,
  }) async {
    // 获取初始颜色，既作为色板的起始颜色，也用于初始化文本控制器
    final Color initColor = ColorUtils.parseHexOrGetDefault(initialColorHex, context);

    final String? selectedHex = await showDialogBase<String>(
      context: context,
      title: title,
      subtitle: '输入十六进制色值或拖动色板选择颜色',
      titleIcon: Icons.palette_outlined,
      width: 360,
      // 高度随内容自适应，超出该高度时内容整体滚动
      height: 520,
      adaptiveHeight: true,
      content: _ColorPickerDialogContent(initialColor: initColor),
    );

    // 仅在用户确认颜色后回传，取消或直接关闭弹窗时不触发回调
    if (selectedHex != null) onColorSelected(selectedHex);
  }

  /// 私有构造函数，防止实例化
  ColorPickerDialog._();
}

/// 颜色选择器对话框内容
class _ColorPickerDialogContent extends StatefulWidget {
  /// 初始颜色
  final Color initialColor;

  const _ColorPickerDialogContent({required this.initialColor});

  @override
  State<_ColorPickerDialogContent> createState() => _ColorPickerDialogContentState();
}

class _ColorPickerDialogContentState extends State<_ColorPickerDialogContent> {
  /// HEX 文本控制器（不含 # 号）
  late final TextEditingController _textController;

  /// ColorPicker 追踪的当前颜色，文本框为空时作为兜底取值
  String? _confirmedHex;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: ColorUtils.toHex(widget.initialColor).substring(1));
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  /// 确认选择并回传颜色
  ///
  /// 优先使用文本框中的值，其次使用 ColorPicker 追踪的最终颜色
  void _confirm() {
    final String hex = _textController.text.isNotEmpty
        ? '#${_textController.text}'
        : (_confirmedHex ?? ColorUtils.toHex(widget.initialColor));
    Navigator.of(context).pop(hex);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // hexInputController 让 ColorPicker 内部自动管理颜色与文本框的双向同步
          // onColorChanged 仅用于追踪当前选中颜色，不触发外部重建
          ColorPicker(
            pickerColor: widget.initialColor,
            onColorChanged: (color) {
              _confirmedHex = ColorUtils.toHex(color);
            },
            hexInputController: _textController,
            pickerAreaHeightPercent: 0.8,
            colorPickerWidth: 300,
            enableAlpha: false,
            displayThumbColor: true,
            paletteType: PaletteType.hsvWithHue,
            labelTypes: const [],
            portraitOnly: true,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CupertinoTextField(
              controller: _textController,
              prefix: const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.tag)),
              suffix: CursorTooltipTarget(
                tooltipContent: const Text('粘贴颜色'),
                child: IconButton(
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: () async {
                    // 从剪贴板读取颜色值并写入文本框，ColorPicker 会自动监听变化并同步
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null) {
                      var hex = data!.text!.trim().toUpperCase();
                      if (hex.startsWith('#')) {
                        hex = hex.substring(1);
                      }
                      _textController.text = hex;
                    }
                  },
                ),
              ),
              autofocus: false,
              maxLength: 6,
              inputFormatters: [
                UpperCaseTextFormatter(),
                FilteringTextInputFormatter.allow(RegExp(kValidHexPattern)),
              ],
            ),
          ),
          // 操作按钮：取消 / 确定
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
              const SizedBox(width: 12),
              FilledButton(onPressed: _confirm, child: const Text('确定')),
            ],
          ),
        ],
      ),
    );
  }
}
