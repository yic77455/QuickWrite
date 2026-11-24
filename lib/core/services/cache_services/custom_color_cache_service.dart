import 'package:flutter/material.dart';
import 'package:quick_write/core/models/cache_models/custom_color_cache.dart';
import 'package:quick_write/core/services/cache_services/cache_service.dart';
import 'package:quick_write/core/utils/color_utils.dart';

/// 自定义颜色缓存服务
///
/// 统一保存各类场景的自定义颜色，使用独立的缓存文件（custom_colors.cache）。
/// 字体颜色、字底颜色等场景共用该文件，仅在数据内部按场景键区分。
class CustomColorCacheService extends CacheService<CustomColorCacheData> {
  // ================= 单例模式 =================

  static final CustomColorCacheService instance = CustomColorCacheService._internal();

  /// 私有构造函数
  CustomColorCacheService._internal() : super('custom_colors');

  // ================= 场景键 =================

  /// 大纲字体颜色场景
  static const String sceneOutlineFont = 'outlineFont';

  /// 大纲字底颜色场景
  static const String sceneOutlineBackground = 'outlineBackground';

  /// 大纲关键词颜色场景
  static const String sceneOutlineKeyword = 'outlineKeyword';

  // ================= 变更通知 =================

  /// 自定义颜色增删后自增，供已打开的颜色选单同步
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  // ================= 状态属性 =================

  /// 当前缓存数据（内存中的副本）
  CustomColorCacheData _data = const CustomColorCacheData();

  /// 获取当前缓存数据（只读访问）
  CustomColorCacheData get data => _data;

  // ================= 初始化方法 =================

  @override
  Future<void> initialize() async {
    try {
      await super.initialize();

      final loadedData = await load();

      if (loadedData != null) {
        _data = loadedData;
        debugPrint('CustomColorCacheService: 已从缓存文件加载数据');
      } else {
        debugPrint('CustomColorCacheService: 使用空数据（缓存文件不存在或为空）');
      }
    } catch (e, stackTrace) {
      debugPrint('CustomColorCacheService 初始化失败: $e');
      debugPrint('堆栈跟踪: $stackTrace');
      _data = const CustomColorCacheData();
    }
  }

  // ================= 反序列化实现 =================

  @override
  CustomColorCacheData fromJson(Map<String, dynamic> json) {
    return CustomColorCacheData.fromJson(json);
  }

  // ================= 自定义颜色管理 =================

  /// 获取指定场景的自定义颜色列表（按添加顺序）
  List<Color> getColors(String scene) {
    final List<Color> colors = <Color>[];
    for (final String hex in _data.colorsByScene[scene] ?? const <String>[]) {
      final Color? color = ColorUtils.tryParseHex(hex);
      if (color != null) colors.add(color);
    }
    return colors;
  }

  /// 向指定场景添加自定义颜色，已存在时直接返回
  Future<bool> addColor(String scene, Color color) async {
    final String hex = ColorUtils.toHex(color);
    final List<String> current = _data.colorsByScene[scene] ?? const <String>[];
    if (current.contains(hex)) return true;

    final updated = Map<String, List<String>>.from(_data.colorsByScene);
    updated[scene] = [...current, hex];
    _data = _data.copyWith(colorsByScene: updated);
    revision.value++;
    return save(_data);
  }

  /// 从指定场景移除自定义颜色
  Future<bool> removeColor(String scene, Color color) async {
    final String hex = ColorUtils.toHex(color);
    final List<String> current = _data.colorsByScene[scene] ?? const <String>[];
    if (!current.contains(hex)) return true;

    final updated = Map<String, List<String>>.from(_data.colorsByScene);
    final remaining = current.where((String item) => item != hex).toList(growable: false);
    if (remaining.isEmpty) {
      updated.remove(scene);
    } else {
      updated[scene] = remaining;
    }
    _data = _data.copyWith(colorsByScene: updated);
    revision.value++;
    return save(_data);
  }
}
