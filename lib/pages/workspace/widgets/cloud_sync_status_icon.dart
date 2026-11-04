import 'package:flutter/material.dart';
import 'package:quick_write/core/services/cloud_sync/cloud_sync_service.dart';

/// 当前文件的同步状态图标
///
/// 未开启实时同步时保持普通文件图标；开启后改用云同步图标反映同步状态：
/// 未同步、正在同步（持续旋转）与已同步
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

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;

    // 未开启实时同步：保持普通文件图标
    if (!_realtimeSyncActive) {
      return Icon(Icons.article_outlined, size: widget.size, color: color);
    }

    // 正在同步：旋转的云同步图标
    if (_service.isSyncing) {
      return RotationTransition(
        turns: _rotationController,
        child: Icon(Icons.cloud_sync_outlined, size: widget.size, color: color),
      );
    }

    // 已同步：本地内容已落盘且不存在待推送的改动
    if (!widget.hasPendingLocalEdits && !_service.hasUnsyncedChanges) {
      return Icon(Icons.cloud_done_outlined, size: widget.size, color: color);
    }

    // 未同步：存在未保存的编辑内容，或仍有改动尚未推送
    return Icon(Icons.cloud_off_outlined, size: widget.size, color: color);
  }
}
