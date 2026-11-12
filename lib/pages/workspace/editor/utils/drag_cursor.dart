import 'package:custom_mouse_cursor/custom_mouse_cursor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 拖拽排序时使用的抓取光标
///
/// Windows 端的系统 grab 光标会回退成普通箭头，因此用 assets/cursors/Grabbing.png
/// 生成自定义光标；全局只创建一次，创建完成前与创建失败时使用系统光标。
class DragCursor {
  DragCursor._();

  /// 当前可用的抓取光标（创建完成后自动更新为自定义光标）
  static final ValueNotifier<MouseCursor> notifier =
      ValueNotifier<MouseCursor>(SystemMouseCursors.grab);

  /// 是否正在进行拖拽
  ///
  /// 拖拽过程中指针可能移出被拖动的控件，编辑器据此在整个编辑区覆盖抓取光标，
  /// 避免指针在控件之外变回普通光标。
  static final ValueNotifier<bool> isDragging = ValueNotifier<bool>(false);

  /// 光标创建任务（重复调用复用同一次创建）
  static Future<MouseCursor>? _loading;

  /// 当前可用的抓取光标
  static MouseCursor get current => notifier.value;

  /// 加载抓取光标
  ///
  /// 多次调用不会重复创建，返回同一个光标对象。
  static Future<MouseCursor> load() => _loading ??= _create();

  /// 按 1 倍图原尺寸创建光标
  ///
  /// 热点取图片中手指顶部的中间位置，与悬停时的手指光标一致，
  /// 切换光标时手形不会相对指针跳动。
  static Future<MouseCursor> _create() async {
    try {
      final MouseCursor cursor = await CustomMouseCursor.exactAsset(
        'assets/cursors/Grabbing.png',
        hotX: 6,
        hotY: 5,
        nativeDevicePixelRatio: 1.0,
      );
      notifier.value = cursor;
      return cursor;
    } catch (_) {
      // 创建失败时保持系统光标，不影响拖拽功能
      return notifier.value;
    }
  }
}
