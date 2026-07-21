import 'package:quick_write/core/models/chapter.dart';

/// 章节序号格式
enum ChapterNumberFormat {
  /// 阿拉伯数字（如：1, 01, 001）
  arabic,

  /// 中文位置制（如：一, 十二, 一百九十五）
  chinesePositional,

  /// 中文逐位制（如：一, 一二, 一九五）
  chineseDigitByDigit,
}

/// 章节序号信息
class ChapterNumberInfo {
  /// 解析出的数字值
  final int number;

  /// 序号格式
  final ChapterNumberFormat format;

  /// 阿拉伯数字的零填充位数（仅 arabic 格式有效）
  final int padding;

  const ChapterNumberInfo({
    required this.number,
    required this.format,
    this.padding = 1,
  });
}

/// 章节序号工具类
///
/// 提供章节序号的解析和生成功能，支持多种格式：
/// - 阿拉伯数字：第1章、第01章、第001章、第0001章
/// - 中文位置制：第一章、第十二章、第一百九十五章
/// - 中文逐位制：第一九五章、第一二章
class ChapterNumberUtils {
  ChapterNumberUtils._();

  /// 中文数字字符到数值的映射
  static const Map<String, int> _chineseDigitMap = {
    '零': 0, '〇': 0,
    '一': 1, '壹': 1,
    '二': 2, '贰': 2,
    '三': 3, '叁': 3,
    '四': 4, '肆': 4,
    '五': 5, '伍': 5,
    '六': 6, '陆': 6,
    '七': 7, '柒': 7,
    '八': 8, '捌': 8,
    '九': 9, '玖': 9,
  };

  /// 中文位置制单位到数值的映射
  static const Map<String, int> _chinesePositionalMap = {
    '十': 10, '拾': 10,
    '百': 100, '佰': 100,
    '千': 1000, '仟': 1000,
    '万': 10000,
    '亿': 100000000,
  };

  /// 中文数字字符（用于逐位制格式化）
  static const List<String> _chineseDigits = [
    '零', '一', '二', '三', '四', '五', '六', '七', '八', '九',
  ];

  /// 从章节标题中解析章节序号
  ///
  /// 支持的格式示例：
  /// - 第1章、第01章、第001章 → 阿拉伯数字
  /// - 第一章、第十二章、第一百九十五章 → 中文位置制
  /// - 第一九五章、第一二章 → 中文逐位制
  ///
  /// 返回 null 表示无法解析
  static ChapterNumberInfo? parseChapterNumber(String title) {
    final regex = RegExp(r'^第(.+?)章');
    final match = regex.firstMatch(title);
    if (match == null) return null;

    final numberPart = match.group(1)!;

    // 尝试解析为阿拉伯数字
    final arabic = int.tryParse(numberPart);
    if (arabic != null && arabic >= 0) {
      return ChapterNumberInfo(
        number: arabic,
        format: ChapterNumberFormat.arabic,
        padding: numberPart.length,
      );
    }

    // 判断是否包含位置制单位
    if (_containsPositionalMarker(numberPart)) {
      final value = _parsePositionalChinese(numberPart);
      if (value != null) {
        return ChapterNumberInfo(
          number: value,
          format: ChapterNumberFormat.chinesePositional,
        );
      }
    }

    // 尝试解析为中文逐位制
    final value = _parseDigitByDigitChinese(numberPart);
    if (value != null) {
      return ChapterNumberInfo(
        number: value,
        format: ChapterNumberFormat.chineseDigitByDigit,
      );
    }

    return null;
  }

  /// 生成下一个章节序号字符串
  ///
  /// 根据已有的序号信息，递增并按相同格式生成下一个序号
  static String generateNextChapterNumber(ChapterNumberInfo info) {
    final nextNumber = info.number + 1;
    return '第${_formatNumber(nextNumber, info.format, info.padding)}章 ';
  }

  /// 生成默认的章节序号字符串
  ///
  /// 新书没有章节或空分卷时使用此方法，默认格式为第001章
  static String generateDefaultChapterNumber(int nextNumber) {
    return '第${nextNumber.toString().padLeft(3, '0')}章 ';
  }

  /// 从章节列表中获取指定分卷的最大章节序号信息
  ///
  /// 遍历指定分卷的所有章节，找到可解析的序号中数值最大的那个
  /// [volumeUuid] 为空字符串表示未分卷
  static ChapterNumberInfo? getMaxChapterNumber(
    List<ChapterModel> chapters,
    String volumeUuid,
  ) {
    ChapterNumberInfo? maxInfo;

    for (final chapter in chapters) {
      if (chapter.volumeUuid != volumeUuid) continue;

      final info = parseChapterNumber(chapter.title);
      if (info != null) {
        if (maxInfo == null || info.number > maxInfo.number) {
          maxInfo = info;
        }
      }
    }

    return maxInfo;
  }

  /// 根据章节列表和分卷 UUID 生成下一个章节序号
  ///
  /// 如果分卷中有可解析的章节序号，则按相同格式递增
  /// 否则使用默认格式（第001章）
  static String generateNextForVolume(
    List<ChapterModel> chapters,
    String volumeUuid,
  ) {
    final maxInfo = getMaxChapterNumber(chapters, volumeUuid);
    if (maxInfo != null) {
      return generateNextChapterNumber(maxInfo);
    }
    return generateDefaultChapterNumber(1);
  }

  /// 判断字符串是否包含中文位置制单位
  static bool _containsPositionalMarker(String s) {
    for (final char in s.split('')) {
      if (_chinesePositionalMap.containsKey(char)) return true;
    }
    return false;
  }

  /// 解析中文位置制数字
  ///
  /// 例如：一 → 1, 十二 → 12, 一百九十五 → 195, 一千零一 → 1001
  static int? _parsePositionalChinese(String s) {
    int result = 0;
    int current = 0;
    bool afterZero = false;

    for (int i = 0; i < s.length; i++) {
      final char = s[i];

      if (_chineseDigitMap.containsKey(char)) {
        current = _chineseDigitMap[char]!;
      } else if (_chinesePositionalMap.containsKey(char)) {
        final positionalValue = _chinesePositionalMap[char]!;

        if (positionalValue >= 10000) {
          // 万、亿：将已累积的值乘以单位
          result = (result + current) * positionalValue;
          current = 0;
        } else {
          // 十、百、千：将当前数字乘以单位并累加
          if (current == 0 && !afterZero) current = 1;
          result += current * positionalValue;
          current = 0;
        }
        afterZero = false;
      } else if (char == '零' || char == '〇') {
        result += current;
        current = 0;
        afterZero = true;
      } else {
        return null;
      }
    }

    result += current;
    return result > 0 ? result : null;
  }

  /// 解析中文逐位制数字
  ///
  /// 例如：一 → 1, 一二 → 12, 一九五 → 195
  static int? _parseDigitByDigitChinese(String s) {
    if (s.isEmpty) return null;

    int result = 0;
    for (int i = 0; i < s.length; i++) {
      final char = s[i];
      final digit = _chineseDigitMap[char];
      if (digit == null) return null;
      result = result * 10 + digit;
    }

    return result > 0 ? result : null;
  }

  /// 将数字按指定格式格式化
  static String _formatNumber(int n, ChapterNumberFormat format, int padding) {
    switch (format) {
      case ChapterNumberFormat.arabic:
        return n.toString().padLeft(padding, '0');
      case ChapterNumberFormat.chinesePositional:
        return _intToPositionalChinese(n);
      case ChapterNumberFormat.chineseDigitByDigit:
        return _intToDigitByDigitChinese(n);
    }
  }

  /// 将整数转换为中文位置制数字字符串
  ///
  /// 例如：1 → 一, 10 → 十, 12 → 十二, 195 → 一百九十五
  static String _intToPositionalChinese(int n) {
    if (n <= 0) return '';

    if (n >= 100000000) {
      final yiPart = n ~/ 100000000;
      final remainder = n % 100000000;
      String result = '${_intToPositionalChinese(yiPart)}亿';
      if (remainder > 0) {
        if (remainder < 10000000) result += '零';
        result += _intToPositionalChinese(remainder);
      }
      return result;
    }

    if (n >= 10000) {
      final wanPart = n ~/ 10000;
      final remainder = n % 10000;
      String result = '${_intToPositionalChinese(wanPart)}万';
      if (remainder > 0) {
        if (remainder < 1000) result += '零';
        result += _intToPositionalChinese(remainder);
      }
      return result;
    }

    String result = '';
    bool needZero = false;

    // 千位
    if (n >= 1000) {
      result = '${_chineseDigits[n ~/ 1000]}千';
      n %= 1000;
      if (n > 0 && n < 100) needZero = true;
    }

    // 百位
    if (n >= 100) {
      if (needZero) {
        result += '零';
        needZero = false;
      }
      result = '$result${_chineseDigits[n ~/ 100]}百';
      n %= 100;
      if (n > 0 && n < 10) needZero = true;
    }

    // 十位
    if (n >= 10) {
      if (needZero) {
        result += '零';
        needZero = false;
      }
      final tenDigit = n ~/ 10;
      // 10-19 且前面没有更高位时省略前导"一"
      if (tenDigit > 1 || result.isNotEmpty) {
        result = '$result${_chineseDigits[tenDigit]}十';
      } else {
        result += '十';
      }
      n %= 10;
    }

    // 个位
    if (n > 0) {
      if (needZero) {
        result += '零';
        needZero = false;
      }
      result += _chineseDigits[n];
    }

    return result;
  }

  /// 将整数转换为中文逐位制数字字符串
  ///
  /// 例如：1 → 一, 12 → 一二, 195 → 一九五
  static String _intToDigitByDigitChinese(int n) {
    if (n <= 0) return _chineseDigits[0];

    String result = '';
    final str = n.toString();
    for (final char in str.split('')) {
      result += _chineseDigits[int.parse(char)];
    }
    return result;
  }
}
