import 'package:flutter/foundation.dart';
import 'package:quick_write/core/services/app_info_service.dart';
import 'package:quick_write/core/services/settings_service.dart';
import 'package:quick_write/core/services/update_service.dart';

/// 应用更新状态管理 Provider
///
/// 应用启动后按设置静默检查一次更新，并把检查结果保存在内存中，
/// 供侧边栏、底部导航与关于页共享展示「有更新」提示。
class UpdateProvider extends ChangeNotifier {
  /// 是否存在比本机更新的版本
  bool _hasUpdate = false;

  /// 最新版本号，未检查出更新时为 null
  String? _latestVersion;

  /// 是否存在可用的新版本
  bool get hasUpdate => _hasUpdate;

  /// 最新版本号
  String? get latestVersion => _latestVersion;

  /// 启动检查
  ///
  /// 仅在设置为「自动检查」时执行；设置为「手动」时不发起检查，
  /// 也不显示红点，避免打扰用户
  Future<void> checkOnStartup() async {
    if (!SettingsService.instance.autoCheckUpdate) return;
    await _refresh();
  }

  /// 按最新的自动检查设置刷新状态
  ///
  /// 开启时立即检查一次；关闭时清除已检查出的更新状态与红点提示
  Future<void> applyAutoCheckSetting(bool autoCheck) async {
    if (autoCheck) {
      await _refresh();
      return;
    }
    _update(hasUpdate: false, latestVersion: null);
  }

  /// 向更新源查询最新版本并记录结果
  ///
  /// 静默执行：检查失败（如未联网）时保持当前状态，不打扰用户，
  /// 需要查看更新详情时用户可自行在关于页手动检查
  Future<void> _refresh() async {
    try {
      final result = await UpdateService.checkForUpdate(AppInfoService.instance.version);
      _update(
        hasUpdate: result.hasUpdate,
        latestVersion: result.hasUpdate ? result.latestVersion : null,
      );
    } on UpdateException {
      // 检查失败不影响使用，保持当前状态
    }
  }

  /// 更新内部状态，仅在发生变化时通知监听者
  void _update({required bool hasUpdate, required String? latestVersion}) {
    if (_hasUpdate == hasUpdate && _latestVersion == latestVersion) return;
    _hasUpdate = hasUpdate;
    _latestVersion = latestVersion;
    notifyListeners();
  }
}
