import 'package:package_info_plus/package_info_plus.dart';

/// 应用信息
///
/// 启动时读取应用包信息并缓存，供界面展示与更新检查直接取用版本号
class AppInfoService {
  AppInfoService._();

  /// 全局单例
  static final AppInfoService instance = AppInfoService._();

  /// 应用版本号（形如 1.0.0）
  String _version = '0.0.0';

  /// 构建号
  String _buildNumber = '0';

  /// 应用版本号
  String get version => _version;

  /// 构建号
  String get buildNumber => _buildNumber;

  /// 读取应用包信息
  Future<void> initialize() async {
    final info = await PackageInfo.fromPlatform();
    _version = info.version;
    _buildNumber = info.buildNumber;
  }
}