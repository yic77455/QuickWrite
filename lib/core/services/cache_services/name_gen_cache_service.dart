import 'package:flutter/material.dart';
import 'package:quick_write/core/models/cache_models/name_gen_cache.dart';
import 'package:quick_write/core/models/name_gen/name_dictionary.dart';
import 'package:quick_write/core/models/name_gen/name_gen_options.dart';
import 'package:quick_write/core/services/cache_services/cache_service.dart';
import 'package:quick_write/core/services/name_gen/name_dictionary_store.dart';

/// 随机取名缓存服务
///
/// 管理随机取名功能的持久化数据，使用独立缓存文件（name_gen.cache）。
///
/// 缓存内容包括：
/// - 人名/地名各自选中的词典
/// - 最近一次使用的生成参数
/// - 按类别分组的生成历史
///
/// 词典由 [NameDictionaryStore] 从 JSON 文件加载，
/// 初始化时一次性读入内存（内置词典 + 自定义词典），供界面查询与管理。
class NameGenCacheService extends CacheService<NameGenCacheData> {
  // ================= 单例模式 =================

  static final NameGenCacheService instance = NameGenCacheService._internal();

  /// 私有构造函数
  NameGenCacheService._internal() : super('name_gen');

  // ================= 常量 =================

  /// 每类生成历史保留的最大条数
  static const int _historyLimit = 500;

  // ================= 状态属性 =================

  /// 当前缓存数据（内存中的副本）
  NameGenCacheData _data = const NameGenCacheData();

  /// 获取当前缓存数据（只读访问）
  NameGenCacheData get data => _data;

  /// 词典存取服务（负责读写词典 JSON 文件）
  final NameDictionaryStore _store = NameDictionaryStore();

  /// 内存中的全部词典（内置词典 + 自定义词典）
  List<NameDictionary> _dictionaries = const [];

  // ================= 初始化方法 =================

  @override
  Future<void> initialize() async {
    try {
      await super.initialize();

      final loadedData = await load();

      if (loadedData != null) {
        _data = loadedData;
        debugPrint('NameGenCacheService: 已从缓存文件加载数据');
      } else {
        debugPrint('NameGenCacheService: 使用默认数据（缓存文件不存在或为空）');
      }

      // 词典统一从 JSON 文件加载（内置资源 + 用户目录）
      await _loadDictionaries();
      await save(_data);
    } catch (e, stackTrace) {
      debugPrint('NameGenCacheService 初始化失败: $e');
      debugPrint('堆栈跟踪: $stackTrace');
      _data = const NameGenCacheData();
      await _loadDictionaries();
    }
  }

  /// 从 JSON 文件加载全部词典到内存
  Future<void> _loadDictionaries() async {
    final builtin = await _store.loadBuiltinDictionaries();
    final custom = await _store.loadCustomDictionaries();
    _dictionaries = [...builtin, ...custom];
  }

  // ================= 反序列化实现 =================

  @override
  NameGenCacheData fromJson(Map<String, dynamic> json) {
    return NameGenCacheData.fromJson(json);
  }

  // ================= 词典管理 =================

  /// 获取指定类别的全部词典
  List<NameDictionary> getDictionaries(NameCategory category) {
    return _dictionaries.where((d) => d.category == category).toList();
  }

  /// 新增或更新词典
  ///
  /// 写入自定义词典文件，并同步更新内存列表；已存在相同 ID 的词典则覆盖，
  /// 否则追加到列表末尾。内置词典不允许新增或修改，此类请求直接拒绝并返回 false。
  Future<bool> saveDictionary(NameDictionary dictionary) async {
    if (dictionary.isBuiltin) return false;
    final dictionaries = List<NameDictionary>.from(_dictionaries);
    final index = dictionaries.indexWhere((d) => d.id == dictionary.id);
    if (index >= 0) {
      if (dictionaries[index].isBuiltin) return false;
      dictionaries[index] = dictionary;
    } else {
      dictionaries.add(dictionary);
    }
    if (!await _store.saveDictionary(dictionary)) return false;
    _dictionaries = dictionaries;
    return true;
  }

  /// 删除指定 ID 的词典
  ///
  /// 删除对应的自定义词典文件并同步更新内存列表。
  /// 内置词典不允许删除，此类请求直接拒绝并返回 false。
  Future<bool> deleteDictionary(String id) async {
    final index = _dictionaries.indexWhere((d) => d.id == id);
    if (index < 0 || _dictionaries[index].isBuiltin) return false;
    if (!await _store.deleteDictionary(id)) return false;
    final dictionaries = List<NameDictionary>.from(_dictionaries)..removeAt(index);
    _dictionaries = dictionaries;
    return true;
  }

  // ================= 选中词典 =================

  /// 获取指定类别当前选中的词典 ID
  ///
  /// 缓存中记录的 ID 无效时回退为该类别的第一个词典。
  String getSelectedDictionaryId(NameCategory category) {
    final stored = category == NameCategory.person
        ? _data.selectedPersonDictId
        : _data.selectedPlaceDictId;
    final dictionaries = getDictionaries(category);
    if (dictionaries.any((d) => d.id == stored)) return stored;
    return dictionaries.isEmpty ? '' : dictionaries.first.id;
  }

  /// 保存指定类别选中的词典 ID
  Future<bool> saveSelectedDictionaryId(NameCategory category, String id) async {
    _data = category == NameCategory.person
        ? _data.copyWith(selectedPersonDictId: id)
        : _data.copyWith(selectedPlaceDictId: id);
    return await save(_data);
  }

  // ================= 生成参数 =================

  /// 获取最近一次使用的生成参数
  NameGenOptions getOptions() => _data.options;

  /// 保存生成参数
  Future<bool> saveOptions(NameGenOptions options) async {
    _data = _data.copyWith(options: options);
    return await save(_data);
  }

  // ================= 生成历史 =================

  /// 获取指定类别的生成历史
  List<String> getHistory(NameCategory category) {
    return List<String>.from(_data.history[category.id] ?? const []);
  }

  /// 追加生成历史
  ///
  /// 新生成的名字插入到列表头部（最新在前），并按上限裁剪。
  Future<bool> addHistory(NameCategory category, List<String> names) async {
    if (names.isEmpty) return true;
    final list = [...names, ...getHistory(category)];
    if (list.length > _historyLimit) {
      list.removeRange(_historyLimit, list.length);
    }
    _data = _data.copyWith(history: {..._data.history, category.id: list});
    return await save(_data);
  }

  /// 清空指定类别的生成历史
  Future<bool> clearHistory(NameCategory category) async {
    _data = _data.copyWith(history: {..._data.history, category.id: const []});
    return await save(_data);
  }
}
