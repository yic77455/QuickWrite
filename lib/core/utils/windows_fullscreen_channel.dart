import 'package:flutter/services.dart';

/// Windows 原生层的全屏过渡操作，避免 PostMessage 产生中间帧。
class WindowsFullScreenChannel {
  WindowsFullScreenChannel._();

  static const MethodChannel _channel =
      MethodChannel('window_fullscreen_channel');

  /// 同步脱离最大化并保持当前矩形；返回 false 表示原生通道不可用。
  static Future<bool> prepareForFullScreen() async {
    try {
      await _channel.invokeMethod('prepareForFullScreen');
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 同步恢复最大化；返回 false 表示原生通道不可用。
  static Future<bool> restoreMaximized() async {
    try {
      await _channel.invokeMethod('restoreMaximized');
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
