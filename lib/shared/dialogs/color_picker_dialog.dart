import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:quick_write/core/utils/color_utils.dart';
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
    // 获取初始颜色并转换为 HEX 字符串（不含 # 号），用于初始化文本控制器
    final initColor = ColorUtils.parseHexOrGetDefault(initialColorHex, context);
    final textController = TextEditingController(
      text: ColorUtils.toHex(initColor).substring(1),
    );

    // 记录用户最终确认的颜色，仅在点击确定时更新
    String? confirmedHex;

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              children: [
                // hexInputController 让 ColorPicker 内部自动管理颜色与文本框的双向同步
                // onColorChanged 仅用于追踪当前选中颜色，不触发外部重建
                ColorPicker(
                  pickerColor: initColor,
                  onColorChanged: (color) {
                    confirmedHex = ColorUtils.toHex(color);
                  },
                  hexInputController: textController,
                  pickerAreaHeightPercent: 0.8,
                  colorPickerWidth: 300,
                  enableAlpha: false,
                  displayThumbColor: true,
                  paletteType: PaletteType.hsvWithHue,
                  labelTypes: const [],
                  portraitOnly: true,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: CupertinoTextField(
                    controller: textController,
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
                            textController.text = hex;
                          }
                        },
                      ),
                    ),
                    autofocus: true,
                    maxLength: 6,
                    inputFormatters: [
                      UpperCaseTextFormatter(),
                      FilteringTextInputFormatter.allow(RegExp(kValidHexPattern)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(child: const Text('取消'), onPressed: () => Navigator.of(dialogContext).pop()),
            FilledButton(
              child: const Text('确定'),
              onPressed: () {
                // 优先使用文本框中的值，其次使用 ColorPicker 追踪的最终颜色
                final hex = textController.text.isNotEmpty ? '#${textController.text}' : (confirmedHex ?? ColorUtils.toHex(initColor));
                onColorSelected(hex);
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
    // 对话框关闭后释放控制器资源
    textController.dispose();
  }

  /// 私有构造函数，防止实例化
  ColorPickerDialog._();
}
