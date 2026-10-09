import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:quick_write/core/models/custom_highlight.dart';

/// 自定义高亮配置文件名（保存在书籍根目录下）
const String kCustomHighlightFileName = 'custom_highlights.json';

/// 自定义高亮服务
///
/// 负责单本书自定义高亮配置的加载、保存与运行时增删改查。
/// 配置以 JSON 文件形式持久化到书籍根目录（与 chapters、settings 同级），
/// 通过 [ChangeNotifier] 通知编辑器在配置变化时重建高亮渲染。
///
/// 生命周期由 [WorkspaceProvider] 管理：每本书的工作台持有一个独立实例。
class CustomHighlightService extends ChangeNotifier {
  /// 当前配置（初始为空配置，加载完成后更新）
  CustomHighlightConfig _config = CustomHighlightConfig.empty;

  /// 配置文件完整路径（load 成功后才有值）
  String? _configFilePath;

  /// 获取当前配置（只读）
  CustomHighlightConfig get config => _config;

  /// 是否启用自定义高亮
  bool get enabled => _config.enabled;

  /// 当前高亮项列表（只读）
  List<CustomHighlightItem> get items => List.unmodifiable(_config.items);

  /// 从指定书籍根目录加载配置
  ///
  /// 文件不存在时使用空配置并标记为已加载，避免阻塞编辑器渲染。
  Future<void> load(String bookFolderPath) async {
    _configFilePath = '$bookFolderPath${Platform.pathSeparator}$kCustomHighlightFileName';

    try {
      final file = File(_configFilePath!);
      if (await file.exists()) {
        final content = await file.readAsString();
        final jsonMap = json.decode(content) as Map<String, dynamic>;
        _config = CustomHighlightConfig.fromJson(jsonMap);
      } else {
        // 文件不存在时使用空配置，不主动创建文件，待用户首次保存时再写入
        _config = CustomHighlightConfig.empty;
      }
    } catch (e) {
      debugPrint('加载自定义高亮配置失败: $e，使用空配置');
      _config = CustomHighlightConfig.empty;
    }
  }

  /// 保存当前配置到文件
  Future<bool> _save() async {
    if (_configFilePath == null) {
      debugPrint('自定义高亮配置文件路径为空，无法保存');
      return false;
    }

    try {
      final file = File(_configFilePath!);
      // 确保父目录存在（书籍根目录通常已存在，此处兜底）
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      final jsonContent = const JsonEncoder.withIndent('  ').convert(_config.toJson());
      await file.writeAsString(jsonContent);
      return true;
    } catch (e) {
      debugPrint('保存自定义高亮配置失败: $e');
      return false;
    }
  }

  /// 更新启用状态
  Future<void> setEnabled(bool value) async {
    if (_config.enabled == value) return;
    _config = _config.copyWith(enabled: value);
    await _save();
    notifyListeners();
  }

  /// 添加一个高亮项
  ///
  /// [keyword] 不能为空字符串，否则跳过。
  /// 同名关键词不重复添加（保持配置整洁，避免重复扫描浪费性能）。
  Future<void> addItem(String keyword, String colorHex) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;
    if (_config.items.any((e) => e.keyword == trimmed)) return;

    final newItems = List<CustomHighlightItem>.from(_config.items)
      ..add(CustomHighlightItem(keyword: trimmed, colorHex: colorHex));
    _config = _config.copyWith(items: newItems);
    await _save();
    notifyListeners();
  }

  /// 修改指定索引处高亮项的颜色
  Future<void> updateItemColor(int index, String colorHex) async {
    if (index < 0 || index >= _config.items.length) return;
    final newItems = List<CustomHighlightItem>.from(_config.items);
    newItems[index] = newItems[index].copyWith(colorHex: colorHex);
    _config = _config.copyWith(items: newItems);
    await _save();
    notifyListeners();
  }

  /// 修改指定索引处高亮项的关键词
  Future<void> updateItemKeyword(int index, String keyword) async {
    final trimmed = keyword.trim();
    if (index < 0 || index >= _config.items.length) return;
    if (trimmed.isEmpty) return;
    // 与其他项重名时跳过（保留原值）
    for (int i = 0; i < _config.items.length; i++) {
      if (i != index && _config.items[i].keyword == trimmed) return;
    }
    final newItems = List<CustomHighlightItem>.from(_config.items);
    newItems[index] = newItems[index].copyWith(keyword: trimmed);
    _config = _config.copyWith(items: newItems);
    await _save();
    notifyListeners();
  }

  /// 删除指定索引处的高亮项
  Future<void> removeItem(int index) async {
    if (index < 0 || index >= _config.items.length) return;
    final newItems = List<CustomHighlightItem>.from(_config.items)..removeAt(index);
    _config = _config.copyWith(items: newItems);
    await _save();
    notifyListeners();
  }

  /// 批量替换全部高亮项（用于对话框一次性提交修改）
  Future<void> replaceAll(List<CustomHighlightItem> newItems) async {
    // 去重并过滤空关键词，保留首次出现的同名项
    final seen = <String>{};
    final filtered = <CustomHighlightItem>[];
    for (final item in newItems) {
      final trimmed = item.keyword.trim();
      if (trimmed.isEmpty) continue;
      if (seen.contains(trimmed)) continue;
      seen.add(trimmed);
      filtered.add(item.copyWith(keyword: trimmed));
    }

    _config = _config.copyWith(items: filtered);
    await _save();
    notifyListeners();
  }
}
