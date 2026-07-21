import 'package:flutter/services.dart';

/// 剪贴板内容状态缓存
///
/// 由于 [Clipboard.getData] 是异步的，无法在同步构建右键菜单时实时获取剪贴板状态。
/// 本类缓存剪贴板是否有内容的状态，供右键菜单同步读取以决定"粘贴"项是否可用。
///
/// 状态刷新时机：
/// - 编辑器获得焦点时（捕获从外部应用切回的场景）
/// - 右键按下时（确保当前菜单使用最新状态）
/// - 应用内剪切/复制后（直接标记为有内容，无需异步查询）
class ClipboardStateCache {
  ClipboardStateCache._();

  /// 缓存的剪贴板是否有内容状态
  ///
  /// 默认为 true，避免应用刚启动时还未完成首次刷新就错误地禁用粘贴项
  static bool _hasContent = true;

  /// 当前缓存指示剪贴板是否有内容
  static bool get hasContent => _hasContent;

  /// 异步刷新剪贴板状态
  ///
  /// 读取系统剪贴板并更新缓存值，调用方应在右键按下、编辑器获得焦点等时机调用
  static Future<void> refresh() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String? text = data?.text;
    _hasContent = text != null && text.isNotEmpty;
  }

  /// 标记剪贴板已有内容
  ///
  /// 在应用内执行剪切/复制操作后调用，无需异步查询即可更新状态
  static void markHasContent() {
    _hasContent = true;
  }
}
