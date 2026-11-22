import 'package:flutter/services.dart';

/// Windows 原生层的全屏切换。
///
/// 整段切换放在一次原生调用内完成，避免中间状态被合成出一帧残影。
class WindowsFullScreenChannel {
  WindowsFullScreenChannel._();

  static const MethodChannel _channel =
      MethodChannel('window_fullscreen_channel');

  /// 进入全屏：脱离最大化、去掉可缩放边框并铺满显示器。
  /// 返回 false 表示原生通道不可用。
  static Future<bool> enterFullScreen() async {
    try {
      final bool? applied = await _channel.invokeMethod<bool>('enterFullScreen');
      return applied ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 退出全屏：一次还原进入前的样式、位置与最大化状态。
  /// 返回 false 表示原生通道不可用。
  static Future<bool> exitFullScreen() async {
    try {
      final bool? applied = await _channel.invokeMethod<bool>('exitFullScreen');
      return applied ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
