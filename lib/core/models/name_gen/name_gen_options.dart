/// 名字性别取向
///
/// 用于人物名生成时选择名字用字的性别倾向。
enum PersonGender {
  /// 不限
  random('random', '随机'),

  /// 男性
  male('male', '男'),

  /// 女性
  female('female', '女');

  

  /// 唯一标识（用于持久化）
  final String id;

  /// 显示名称
  final String label;

  const PersonGender(this.id, this.label);

  /// 根据 ID 解析性别，未知 ID 回退为不限
  static PersonGender fromId(String id) =>
      values.firstWhere((g) => g.id == id, orElse: () => PersonGender.random);
}

/// 名字生成参数
///
/// 记录最后一次使用的生成配置，供下次打开弹窗时恢复。
/// 人名与地名共用同一份参数，各自使用与自己相关的字段。
class NameGenOptions {
  /// 每次生成数量的可选值
  static const List<int> batchCountOptions = [20, 50, 100, 200];

  /// 每次生成数量的默认值
  static const int defaultBatchCount = 100;

  /// 人名：性别取向
  final PersonGender gender;

  /// 人名：自定义姓氏（非空时优先于词典姓氏）
  final String customSurname;

  /// 人名：名字字数（0 表示随机取 1~2 字，仅对逐字词典有效）
  final int givenLength;

  /// 地名：自定义后缀（非空时优先于词典后缀）
  final String customSuffix;

  /// 地名：主体词字数（0 表示随机取 1~2 字，仅对逐字词典有效）
  final int stemLength;

  /// 每次生成的数量
  final int batchCount;

  const NameGenOptions({
    this.gender = PersonGender.random,
    this.customSurname = '',
    this.givenLength = 0,
    this.customSuffix = '',
    this.stemLength = 0,
    this.batchCount = defaultBatchCount,
  });

  /// 从 JSON Map 创建实例
  factory NameGenOptions.fromJson(Map<String, dynamic> json) {
    return NameGenOptions(
      gender: PersonGender.fromId(json['gender'] as String? ?? ''),
      customSurname: json['customSurname'] as String? ?? '',
      givenLength: json['givenLength'] as int? ?? 0,
      customSuffix: json['customSuffix'] as String? ?? '',
      stemLength: json['stemLength'] as int? ?? 0,
      batchCount: json['batchCount'] as int? ?? defaultBatchCount,
    );
  }

  /// 转换为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'gender': gender.id,
      'customSurname': customSurname,
      'givenLength': givenLength,
      'customSuffix': customSuffix,
      'stemLength': stemLength,
      'batchCount': batchCount,
    };
  }

  /// 创建副本
  NameGenOptions copyWith({
    PersonGender? gender,
    String? customSurname,
    int? givenLength,
    String? customSuffix,
    int? stemLength,
    int? batchCount,
  }) {
    return NameGenOptions(
      gender: gender ?? this.gender,
      customSurname: customSurname ?? this.customSurname,
      givenLength: givenLength ?? this.givenLength,
      customSuffix: customSuffix ?? this.customSuffix,
      stemLength: stemLength ?? this.stemLength,
      batchCount: batchCount ?? this.batchCount,
    );
  }
}
