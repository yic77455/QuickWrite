import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';

/// 安卓原生能力入口
///
/// 打开外部链接、拉起安装程序等能力在桌面端由命令行工具实现，
/// 安卓端没有对应实现，统一转由 MainActivity 注册的方法通道执行。
/// 非安卓平台上的调用一律返回失败，避免触发通道未实现的异常。
class AndroidNative {
  AndroidNative._();

  /// 与原生端约定的通道名称
  static const MethodChannel _channel = MethodChannel('com.quickwrite.app/native');

  /// 在系统浏览器中打开链接，返回是否成功发起跳转
  static Future<bool> openUrl(String url) async {
    if (!PlatformCapabilities.isAndroid) return false;
    return await _invoke<bool>('openUrl', {'url': url}) ?? false;
  }

  /// 查询当前是否已获得「安装未知应用」授权
  static Future<bool> canInstallPackages() async {
    if (!PlatformCapabilities.isAndroid) return false;
    return await _invoke<bool>('canInstallPackages') ?? false;
  }

  /// 跳转到系统的「安装未知应用」授权页面，返回是否成功发起跳转
  static Future<bool> openInstallPermissionSettings() async {
    if (!PlatformCapabilities.isAndroid) return false;
    return await _invoke<bool>('openInstallPermissionSettings') ?? false;
  }

  /// 拉起系统安装程序安装指定路径的安装包，返回是否成功发起跳转
  static Future<bool> installApk(String path) async {
    if (!PlatformCapabilities.isAndroid) return false;
    return await _invoke<bool>('installApk', {'path': path}) ?? false;
  }

  /// 调用原生方法，并把通道异常统一降级为调用失败
  static Future<T?> _invoke<T>(String method, [Map<String, dynamic>? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } catch (e) {
      debugPrint('调用安卓原生能力失败（$method）: $e');
      return null;
    }
  }
}
