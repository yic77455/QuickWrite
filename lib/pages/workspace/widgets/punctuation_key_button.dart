import 'package:flutter/material.dart';
import 'package:quick_write/core/constants/punctuation_symbols.dart';
import 'package:quick_write/core/utils/typography_extension.dart';

/// 标点符号快捷按键
///
/// 供移动端快捷输入栏与大纲编辑器键盘工具栏共用：
/// 按键宽度统一便于连续点按，多字标点按可用宽度等比缩小避免文字裁切。
class PunctuationKeyButton extends StatelessWidget {
  /// 按键宽度，所有按键统一宽度
  static const double width = 44;

  /// 按键高度
  static const double height = 44;

  /// 按键对应的标点符号
  final PunctuationSymbol symbol;

  /// 点击回调
  final VoidCallback onTap;

  const PunctuationKeyButton({
    super.key,
    required this.symbol,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        // 按键不参与焦点争夺，避免点击时输入法收起
        canRequestFocus: false,
        onTap: onTap,
        highlightColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.12),
        splashColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.08),
        child: SizedBox(
          width: width,
          height: height,
          // 多字标点按可用宽度等比缩小，保证各按键宽度一致且文字不被裁切
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                symbol.symbol,
                style: context.bodyLarge?.copyWith(color: colorScheme.onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
