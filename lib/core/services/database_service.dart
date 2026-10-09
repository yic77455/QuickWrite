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

    return Isar.open(
      _schemas,
      directory: AppPaths.instance.databaseDirectory,
      name: name,
      // 启动时自动压缩数据库（只要有空闲空间就压缩）
      compactOnLaunch: const CompactCondition(minBytes: 1),
    );
  }
}
