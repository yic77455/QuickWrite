import 'dart:math';

import 'package:quick_write/core/models/name_gen/name_dictionary.dart';
import 'package:quick_write/core/models/name_gen/name_gen_options.dart';

/// 名字生成器
///
/// 纯函数式的名字生成逻辑，根据词典与参数组合出人名或地名。
/// 词条池为"逐字"池（全部为单字）时按字数组合多个字，
/// 为"整词"池时直接取一个完整词条。
class NameGenerator {
  NameGenerator._();

  /// 生成单个名字
  ///
  /// 根据词典类别自动分派到人名或地名生成，返回 null 表示词典数据不足。
  static String? generate(
    NameDictionary dictionary, {
    required NameGenOptions options,
    required Random random,
  }) {
    return dictionary.category == NameCategory.person
        ? generatePerson(dictionary, options: options, random: random)
        : generatePlace(dictionary, options: options, random: random);
  }

  /// 批量生成名字
  ///
  /// 生成 [count] 个名字并对同批次结果去重；当词典无法继续生成时提前结束。
  static List<String> generateBatch(
    NameDictionary dictionary, {
    required NameGenOptions options,
    required int count,
    required Random random,
  }) {
    final results = <String>[];
    final seen = <String>{};
    for (int i = 0; i < count; i++) {
      final name = generate(dictionary, options: options, random: random);
      if (name == null) break;
      if (seen.add(name)) results.add(name);
    }
    return results;
  }

  /// 生成人名
  ///
  /// 姓氏优先取自定义姓氏，否则从词典姓氏池随机选取；
  /// 名字部分按性别从对应用字池组合，最后依据 [NameDictionary.givenFirst]
  /// 决定"姓+名"还是"名+姓"的拼接顺序。
  static String? generatePerson(
    NameDictionary dictionary, {
    required NameGenOptions options,
    required Random random,
  }) {
    final customSurname = options.customSurname.trim();
    final surname = customSurname.isNotEmpty
        ? customSurname
        : _pickOne(dictionary.pool(NamePoolKeys.surname), random);
    if (surname == null) return null;

    final given = _buildGivenName(dictionary, options.gender, options.givenLength, random);
    if (given == null || given.isEmpty) return null;

    return dictionary.givenFirst ? '$given$surname' : '$surname$given';
  }

  /// 生成地名
  ///
  /// 逐字主体池按字数组合单字，整词主体池直接取一个完整地名；
  /// 后缀优先取自定义后缀，否则从词典后缀池随机选取。
  static String? generatePlace(
    NameDictionary dictionary, {
    required NameGenOptions options,
    required Random random,
  }) {
    final stemPool = dictionary.pool(NamePoolKeys.stem);
    if (stemPool.isEmpty) return null;

    final String? stem = _isCharPool(stemPool)
        ? _pickChars(stemPool, _resolveLength(options.stemLength, random), random)
        : _pickOne(stemPool, random);
    if (stem == null || stem.isEmpty) return null;

    final customSuffix = options.customSuffix.trim();
    final suffix = customSuffix.isNotEmpty
        ? customSuffix
        : (_pickOne(dictionary.pool(NamePoolKeys.suffix), random) ?? '');
    return '$stem$suffix';
  }

  /// 构建名字部分
  ///
  /// 按性别取向选择用字池：指定性别时优先取该性别池，池为空时回退到另一性别；
  /// 不限性别时合并两性用字池。逐字池按字数组合单字，整词池直接取一个完整词条。
  static String? _buildGivenName(
    NameDictionary dictionary,
    PersonGender gender,
    int length,
    Random random,
  ) {
    final malePool = dictionary.pool(NamePoolKeys.male);
    final femalePool = dictionary.pool(NamePoolKeys.female);

    final List<String> pool;
    switch (gender) {
      case PersonGender.male:
        pool = malePool.isNotEmpty ? malePool : femalePool;
        break;
      case PersonGender.female:
        pool = femalePool.isNotEmpty ? femalePool : malePool;
        break;
      case PersonGender.random:
        pool = [...malePool, ...femalePool];
        break;
    }
    if (pool.isEmpty) return null;

    if (_isCharPool(pool)) {
      return _pickChars(pool, _resolveLength(length, random), random);
    }
    return _pickOne(pool, random);
  }

  /// 解析字数：大于 0 时使用指定值，否则随机取 1~2
  static int _resolveLength(int length, Random random) {
    return length > 0 ? length : 1 + random.nextInt(2);
  }

  /// 判断词条池是否为逐字池（所有词条均为单字）
  static bool _isCharPool(List<String> pool) {
    return pool.isNotEmpty && pool.every((e) => e.runes.length == 1);
  }

  /// 从词条池随机选取一个词条，池为空时返回 null
  static String? _pickOne(List<String> pool, Random random) {
    if (pool.isEmpty) return null;
    return pool[random.nextInt(pool.length)];
  }

  /// 从逐字池随机组合 [length] 个字（不重复），池不足时取池内全部
  static String _pickChars(List<String> pool, int length, Random random) {
    if (pool.isEmpty || length <= 0) return '';
    final count = length.clamp(1, pool.length);
    final remaining = List<String>.from(pool);
    final buffer = StringBuffer();
    for (int i = 0; i < count; i++) {
      buffer.write(remaining.removeAt(random.nextInt(remaining.length)));
    }
    return buffer.toString();
  }
}
