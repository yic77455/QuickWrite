import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/models/group.dart';
import 'package:quick_write/core/models/recycle_bin.dart';
import 'package:quick_write/core/models/recycle_item.dart';
import 'package:quick_write/core/models/setting_group.dart';
import 'package:quick_write/core/models/setting_item.dart';
import 'package:quick_write/core/models/volume.dart';
import 'package:quick_write/core/models/writing_stat.dart';
import 'package:quick_write/core/services/app_paths.dart';

/// 应用数据库服务
///
/// 集中持有数据库的集合定义与打开逻辑。全应用只有这一处声明集合列表，
/// 避免各处各自维护时出现遗漏：先打开数据库的一方若缺少某个集合的声明，
/// 后续复用该实例的代码访问该集合就会报错
class DatabaseService {
  // ================= 单例模式 =================

  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();

  // ================= 集合定义 =================

  /// 数据库的完整集合定义
  ///
  /// 新增集合时必须在此登记，其余位置无需改动
  static final List<CollectionSchema<dynamic>> _schemas = [
    BookModelSchema,
    GroupModelSchema,
    RecycleBinModelSchema,
    RecycleItemModelSchema,
    ChapterModelSchema,
    VolumeModelSchema,
    SettingGroupModelSchema,
    SettingItemModelSchema,
    WritingStatModelSchema,
  ];

  /// 是否已打开过数据库
  bool get isOpen => Isar.getInstance(AppPaths.instance.databaseName) != null;

  // ================= 打开数据库 =================

  /// 启动压缩条件：数据库只要存在空闲空间就压缩
  static const CompactCondition _compactCondition = CompactCondition(minBytes: 1);

  /// 压缩残留文件路径
  ///
  /// Isar 压缩时会把数据库整体复制为该文件，成功后再用它替换原数据库文件
  String get _compactFilePath {
    final separator = Platform.pathSeparator;
    final directory = AppPaths.instance.databaseDirectory;
    final name = AppPaths.instance.databaseName;
    return '$directory$separator$name.isar.compact';
  }

  /// 获取数据库实例
  ///
  /// 已打开时直接复用，否则按完整集合定义打开。
  /// 各处统一走此方法，可避免因打开顺序不同而拿到缺少集合声明的实例
  Future<Isar> open() async {
    // 确保 AppPaths 已初始化
    if (!AppPaths.instance.isInitialized) {
      await AppPaths.instance.initialize();
    }

    final name = AppPaths.instance.databaseName;
    final existing = Isar.getInstance(name);
    if (existing != null) return existing;

    // 清理上次压缩中断留下的残留文件，否则会阻碍本次的启动压缩
    await _removeCompactLeftover();

    try {
      return await _open(name, compactOnLaunch: _compactCondition);
    } catch (e) {
      // 启动压缩失败时降级为不压缩重新打开，保证数据库始终能正常启动
      debugPrint('数据库启动压缩失败，降级为不压缩重试: $e');
      await _removeCompactLeftover();
      return await _open(name);
    }
  }

  /// 按完整集合定义打开数据库
  ///
  /// [compactOnLaunch] 为 null 时本次打开不做压缩
  Future<Isar> _open(String name, {CompactCondition? compactOnLaunch}) {
    return Isar.open(
      _schemas,
      directory: AppPaths.instance.databaseDirectory,
      name: name,
      compactOnLaunch: compactOnLaunch,
    );
  }

  /// 删除启动压缩残留的数据库复制文件
  ///
  /// 该文件仅在压缩期间短暂存在，若进程在替换原文件前退出便会残留下来，
  /// 残留文件会使后续的压缩打开直接失败
  Future<void> _removeCompactLeftover() async {
    final leftover = File(_compactFilePath);
    if (!await leftover.exists()) return;

    try {
      await leftover.delete();
      debugPrint('已清理数据库压缩残留文件: $_compactFilePath');
    } catch (e) {
      debugPrint('清理数据库压缩残留文件失败: $e');
    }
  }
}
