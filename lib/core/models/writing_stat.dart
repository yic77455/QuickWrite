import 'package:isar/isar.dart';

// 这行代码表示 Isar 会自动生成一个叫 writing_stat.g.dart 的文件
part 'writing_stat.g.dart';

/// 码字统计模型
///
/// 记录每本书每天的码字统计数据，包括净增字数与码字时长。
/// 统计页面按 (bookUuid, date) 进行聚合查询，"全部书籍"由服务层汇总得出。
@collection
class WritingStatModel {
  // Isar 强制要求必须有一个叫 id 的整型主键
  Id id = Isar.autoIncrement;

  /// 所属书籍 UUID
  @Index()
  String bookUuid = '';

  /// 统计日期（已归一化为当天零点，便于按天聚合）
  @Index()
  DateTime date = DateTime.now();

  /// 当日净增字数（保存章节时累计字数增量，删除为负、新增为正）
  int wordsAdded = 0;

  /// 当日键盘输入字数（不含粘贴，用于计算码字速度）
  int typedWords = 0;

  /// 当日码字时长（单位：秒）
  int durationSeconds = 0;

  /// 最后更新时间
  DateTime updatedAt = DateTime.now();

  WritingStatModel(); // 默认构造函数，Isar 强制要求有
}
