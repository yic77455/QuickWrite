import 'package:flutter/material.dart';
import 'package:quick_write/core/constants/material_icons.dart';
import 'package:quick_write/core/services/cloud_sync/cloud_sync_service.dart';

/// 当前文件的同步状态图标
///
/// 未开启实时同步时保持普通文件图标；开启后改用云同步图标反映同步状态：
/// 未同步、正在同步（持续旋转）、同步失败与已同步
class CloudSyncStatusIcon extends StatefulWidget {
  /// 图标尺寸
  final double size;

  /// 当前文件是否还有未保存到本地的编辑内容
  ///
  /// 未落盘的内容同样尚未进入云端，需按未同步展示
  final bool hasPendingLocalEdits;

  const CloudSyncStatusIcon({
    super.key,
    this.size = 14,
    this.hasPendingLocalEdits = false,
  });

  @override
  State<CloudSyncStatusIcon> createState() => _CloudSyncStatusIconState();
}

class _CloudSyncStatusIconState extends State<CloudSyncStatusIcon>
    with SingleTickerProviderStateMixin {
  // 云同步服务单例，直接监听其状态变化以刷新图标
  final CloudSyncService _service = CloudSyncService.instance;

  // 正在同步时驱动图标旋转的动画控制器
  late final AnimationController _rotationController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  // 逆时针旋转动画：进度从 0 到 1 时角度由 0 递减到 -1 圈
  late final Animation<double> _rotationAnimation = Tween<double>(
    begin: 0,
    end: -1,
  ).animate(_rotationController);

  @override
  void initState() {
    super.initState();
    _service.addListener(_handleServiceChanged);
    _syncRotationWithState();
  }

  @override
  void dispose() {
    _service.removeListener(_handleServiceChanged);
    _rotationController.dispose();
    super.dispose();
  }

  /// 服务状态变化时刷新图标，并让旋转动画与同步状态保持一致
  void _handleServiceChanged() {
    if (!mounted) return;
    _syncRotationWithState();
    setState(() {});
  }

  /// 同步进行中持续旋转，其余状态停在起始角度
  void _syncRotationWithState() {
    if (_service.isSyncing) {
      if (!_rotationController.isAnimating) _rotationController.repeat();
    } else if (_rotationController.isAnimating) {
      _rotationController.stop();
      _rotationController.value = 0;
    }
  }

  /// 实时同步是否处于生效状态
  ///
  /// 由云同步服务统一判定：主窗口依据本机设置判断，
  /// 工作台子窗口则跟随主窗口推送的状态
  bool get _realtimeSyncActive => _service.isRealtimeSyncActive;

  /// 构建状态图标
  ///
  /// [rotating] 控制图标是否随同步旋转，[color] 用于指定图标颜色
  Widget _buildStatusIcon(IconData icon, {bool rotating = false, Color? color}) {
    final iconColor = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    Widget child = Icon(icon, size: widget.size, color: iconColor);
    if (rotating) {
      child = RotationTransition(turns: _rotationAnimation, child: child);
    }
    return child;
  }

  @override
  Widget build(BuildContext context) {
    // 未开启实时同步：保持普通文件图标
    if (!_realtimeSyncActive) {
      return _buildStatusIcon(Icons.article_outlined);
    }

    // 正在同步：旋转的云同步图标
    if (_service.isSyncing) {
      return _buildStatusIcon(Icons.sync_outlined, rotating: true);
    }

    // 同步失败：以错误色提示用户检查网络或云盘设置
    if (_service.syncFailed) {
      return _buildStatusIcon(
        MaterialIcons.cloud_alert,
        color: Theme.of(context).colorScheme.error,
      );
    }

    // 已同步：本地内容已落盘且不存在待推送的改动
    if (!widget.hasPendingLocalEdits && !_service.hasUnsyncedChanges) {
      return _buildStatusIcon(Icons.cloud_done_outlined);
    }

    // 未同步：存在未保存的编辑内容，或仍有改动尚未推送
    return _buildStatusIcon(Icons.cloud_outlined);
  }
}

/// 云同步状态的悬停提示
///
/// 包裹状态图标与其后的文件名，使整块当前文件信息都能展示同步状态说明
class CloudSyncStatusTooltip extends StatelessWidget {
  /// 当前文件是否还有未保存到本地的编辑内容
  final bool hasPendingLocalEdits;

  /// 需要被提示包裹的内容
  final Widget child;

  const CloudSyncStatusTooltip({
    super.key,
    required this.child,
    this.hasPendingLocalEdits = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CloudSyncService.instance,
      builder: (context, _) => Tooltip(
        message: _describeSyncStatus(
          CloudSyncService.instance,
          hasPendingLocalEdits: hasPendingLocalEdits,
        ),
        child: child,
      ),
    );
  }
}

/// 生成当前云同步状态的说明文案
String _describeSyncStatus(
  CloudSyncService service, {
  required bool hasPendingLocalEdits,
}) {
  // 未开启实时同步时，图标不代表云同步状态
  if (!service.isRealtimeSyncActive) return '实时同步未开启';
  if (service.isSyncing) return '正在同步…';
  if (service.syncFailed) return '同步失败，请检查网络或云盘设置';
  if (hasPendingLocalEdits || service.hasUnsyncedChanges) return '尚未同步到云端';
  return '已同步到云端';
}
