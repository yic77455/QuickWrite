/// 文本解析工具类
/// 
/// 用于解析导入的文本内容，识别章节和分卷结构
class TextParser {
  /// 中文数字到阿拉伯数字的映射
  static const Map<String, int> _chineseNumberMap = {
    '零': 0, '〇': 0,
    '一': 1, '二': 2, '三': 3, '四': 4,
    '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
    '十': 10, '百': 100, '千': 1000, '万': 10000, '亿': 100000000,
  };

  /// 分卷识别正则表达式
  /// 匹配格式：
  /// - 第X卷、第X部、卷X、部X
  /// - X可以是阿拉伯数字或中文数字
  static final RegExp _volumePattern = RegExp(
    r'^[\s]*(第\s*([零〇一二三四五六七八九十百千万亿\d]+)\s*(卷|部)|卷\s*([零〇一二三四五六七八九十百千万亿\d]+)|部\s*([零〇一二三四五六七八九十百千万亿\d]+))[\s:：]*(.*)$',
    multiLine: true,
  );

  /// 章节识别正则表达式
  /// 匹配格式：
  /// - 第X章、第X节、Chapter X
  /// - 纯数字开头：1、章节名、001 章节名、1. 章节名
  /// - X可以是阿拉伯数字或中文数字
  static final RegExp _chapterPattern = RegExp(
    r'^[\s]*(第\s*([零〇一二三四五六七八九十百千万亿\d]+)\s*(章|节)|Chapter\s*(\d+)|^(\d+)[\s.、．]+(.*)$)',
    multiLine: true,
  );

  /// 纯数字章节识别（如 "1、章节名" 或 "001 章节名"）
  static final RegExp _numericChapterPattern = RegExp(
    r'^[\s]*(\d{1,5})[\s.、．]+(.+)$',
    multiLine: true,
  );

  /// 解析文本内容，提取章节和分卷信息
  /// 
  /// [content] 原始文本内容
  /// 返回解析结果，包含分卷列表和章节列表
  ParseResult parse(String content) {
    final lines = content.split('\n');
    final chapters = <ParsedChapter>[];
    final volumes = <String>{}; // 收集所有分卷名
    
    // 用于检测重复章节标题的集合（格式：分卷名|章节标题）
    final chapterTitleSet = <String>{};
    
    String currentVolume = ''; // 当前分卷名
    int globalOrderIndex = 0; // 全局章节序号
    int volumeOrderIndex = 0; // 卷内章节序号
    StringBuffer? currentContent; // 当前章节内容缓存
    ParsedChapter? currentChapter; // 当前正在处理的章节
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      
      // 跳过空行（但如果是章节内容的一部分则保留）
      if (line.isEmpty) {
        if (currentContent != null) {
          currentContent.writeln();
        }
        continue;
      }
      
      // 检查是否是分卷标题
      final volumeMatch = _volumePattern.firstMatch(line);
      if (volumeMatch != null) {
        // 保存上一个章节
        if (currentChapter != null && currentContent != null) {
          currentChapter.content = currentContent.toString().trim();
          chapters.add(currentChapter);
        }
        
        // 提取分卷信息
        currentVolume = _extractVolumeTitle(volumeMatch);
        if (currentVolume.isNotEmpty) {
          volumes.add(currentVolume);
        }
        
        // 重置章节相关状态
        currentChapter = null;
        currentContent = null;
        volumeOrderIndex = 0;
        // 切换分卷时清空章节标题集合，因为不同分卷的章节标题可以相同
        chapterTitleSet.clear();
        continue;
      }
      
      // 检查是否是章节标题
      final chapterMatch = _chapterPattern.firstMatch(line);
      final numericMatch = _numericChapterPattern.firstMatch(line);
      
      if (chapterMatch != null || numericMatch != null) {
        // 提取章节信息
        final chapterInfo = chapterMatch != null
            ? _extractChapterInfo(chapterMatch, line)
            : _extractNumericChapterInfo(numericMatch!);
        
        // 生成唯一标识（分卷名|章节标题）
        final chapterKey = '$currentVolume|${chapterInfo.title}';
        
        // 检查是否是重复的章节标题
        if (chapterTitleSet.contains(chapterKey)) {
          // 重复标题，跳过此标题行，后续内容追加到当前章节
          // debugPrint('检测到重复章节标题: ${chapterInfo.title}，内容将合并到已有章节');
          continue;
        }
        
        // 保存上一个章节
        if (currentChapter != null && currentContent != null) {
          currentChapter.content = currentContent.toString().trim();
          chapters.add(currentChapter);
        }
        
        // 记录章节标题
        chapterTitleSet.add(chapterKey);
        
        globalOrderIndex++;
        volumeOrderIndex++;
        
        currentChapter = ParsedChapter(
          title: chapterInfo.title,
          volumeName: currentVolume,
          orderIndex: globalOrderIndex,
          volumeOrderIndex: volumeOrderIndex,
          chapterNumber: chapterInfo.number,
        );
        currentContent = StringBuffer();
        continue;
      }
      
      // 普通文本行，添加到当前章节内容
      if (currentContent != null) {
        currentContent.writeln(line);
      }
    }
    
    // 保存最后一个章节
    if (currentChapter != null && currentContent != null) {
      currentChapter.content = currentContent.toString().trim();
      chapters.add(currentChapter);
    }
    
    // 如果没有识别到任何章节，将整个文本作为第一章
    if (chapters.isEmpty && content.trim().isNotEmpty) {
      chapters.add(ParsedChapter(
        title: '第一章',
        volumeName: '',
        orderIndex: 1,
        volumeOrderIndex: 1,
        chapterNumber: 1,
        content: content.trim(),
      ));
    }
    
    return ParseResult(
      volumes: volumes.toList(),
      chapters: chapters,
    );
  }

  /// 提取分卷标题
  String _extractVolumeTitle(Match match) {
    // 尝试从不同分组提取数字
    String? numberStr;
    String suffix = '';
    
    if (match.group(2) != null) {
      // 格式：第X卷/部
      numberStr = match.group(2);
      suffix = match.group(3) ?? '卷';
    } else if (match.group(4) != null) {
      // 格式：卷X
      numberStr = match.group(4);
      suffix = '卷';
    } else if (match.group(5) != null) {
      // 格式：部X
      numberStr = match.group(5);
      suffix = '部';
    }
    
    if (numberStr == null) return '';
    
    // 保留原始数字字符串（用于显示，如 "001" 或 "一九五"）
    final originalNumStr = numberStr.trim();
    // 提取附加的标题（如 "第一卷 天地玄黄" 中的 "天地玄黄"）
    final extraTitle = match.group(6)?.trim() ?? '';
    
    // 保留原始数字格式（阿拉伯数字保留前导零，中文数字保留原样）
    final displayNum = originalNumStr;
    
    if (extraTitle.isNotEmpty) {
      return '第$displayNum$suffix $extraTitle';
    }
    return '第$displayNum$suffix';
  }

  /// 从正则匹配中提取章节信息
  _ChapterInfo _extractChapterInfo(Match match, String originalLine) {
    String? numberStr;
    String suffix = '章';
    
    if (match.group(2) != null) {
      // 格式：第X章/节
      numberStr = match.group(2);
      suffix = match.group(3) ?? '章';
    } else if (match.group(4) != null) {
      // 格式：Chapter X
      numberStr = match.group(4);
      suffix = '章';
    }
    
    final number = numberStr != null ? _convertToNumber(numberStr) : 0;
    // 保留原始数字字符串（用于显示，如 "001" 或 "一九五"）
    final originalNumStr = numberStr?.trim() ?? '';
    // 判断原始数字是否为阿拉伯数字格式
    final isArabicNumber = originalNumStr.isNotEmpty && RegExp(r'^\d+$').hasMatch(originalNumStr);
    
    // 提取章节名（标题行中除去章节编号的部分）
    String title = originalLine;
    // 尝试提取章节名部分
    final afterNumber = RegExp(r'(?:第\s*[零〇一二三四五六七八九十百千万亿\d]+\s*[章节]|Chapter\s*\d+)[\s:：]*(.*)$')
        .firstMatch(originalLine);
    if (afterNumber != null && afterNumber.group(1) != null) {
      final name = afterNumber.group(1)!.trim();
      if (name.isNotEmpty) {
        if (isArabicNumber) {
          title = '第$originalNumStr$suffix $name';
        } else {
          // 中文数字保留原始格式
          title = '第$originalNumStr$suffix $name';
        }
      } else {
        if (isArabicNumber) {
          title = '第$originalNumStr$suffix';
        } else {
          title = '第$originalNumStr$suffix';
        }
      }
    } else {
      if (isArabicNumber) {
        title = '第$originalNumStr$suffix';
      } else {
        title = '第$originalNumStr$suffix';
      }
    }
    
    return _ChapterInfo(number: number, title: title, originalNumberStr: originalNumStr);
  }

  /// 从纯数字格式中提取章节信息
  _ChapterInfo _extractNumericChapterInfo(Match match) {
    final numberStr = match.group(1) ?? '1';
    final name = match.group(2)?.trim() ?? '';
    final number = int.tryParse(numberStr) ?? 1;
    
    String title;
    if (name.isNotEmpty) {
      // 保留原始数字字符串（包括前导零）
      title = '第$numberStr章 $name';
    } else {
      title = '第$numberStr章';
    }
    
    return _ChapterInfo(number: number, title: title, originalNumberStr: numberStr);
  }

  /// 将中文数字或阿拉伯数字字符串转换为整数
  int _convertToNumber(String str) {
    str = str.trim();
    
    // 如果是纯阿拉伯数字，直接转换
    if (RegExp(r'^\d+$').hasMatch(str)) {
      return int.tryParse(str) ?? 0;
    }
    
    // 判断是否为中文逐位制格式（仅包含数字字符，不包含位置制单位）
    // 逐位制示例：一九五 → 195, 二零二六 → 2026, 一二 → 12
    if (_isDigitByDigitChinese(str)) {
      return _convertDigitByDigitChinese(str);
    }
    
    // 中文位置制数字转换
    // 处理规则：
    // - "十" = 10, "十一" = 11, "十九" = 19
    // - "二十" = 20, "二十一" = 21
    // - "一百二十三" = 123
    // - "一万零一" = 10001
    // - "一亿二千三百万" = 123000000
    int result = 0;
    int current = 0;
    bool afterZero = false;

    for (int i = 0; i < str.length; i++) {
      final char = str[i];
      final value = _chineseNumberMap[char];

      if (value == null) continue;

      if (value >= 10) {
        // 位置制单位：十、百、千、万、亿
        if (value >= 10000) {
          // 万、亿：将已累积的值乘以单位
          result = (result + current) * value;
          current = 0;
        } else {
          // 十、百、千：将当前数字乘以单位并累加
          if (current == 0 && !afterZero) current = 1;
          result += current * value;
          current = 0;
        }
        afterZero = false;
      } else {
        // 数字：0-9
        if (value == 0) {
          result += current;
          current = 0;
          afterZero = true;
        } else {
          current = value;
          afterZero = false;
        }
      }
    }

    result += current;

    return result > 0 ? result : 0;
  }

  /// 判断字符串是否为中文逐位制格式
  ///
  /// 逐位制格式仅包含数字字符（零一二三四五六七八九〇），
  /// 不包含位置制单位（十百千万亿等）
  static bool _isDigitByDigitChinese(String str) {
    if (str.isEmpty) return false;
    final digitChars = {'零', '一', '二', '三', '四', '五', '六', '七', '八', '九', '〇'};
    for (int i = 0; i < str.length; i++) {
      if (!digitChars.contains(str[i])) return false;
    }
    return true;
  }

  /// 将中文逐位制数字字符串转换为整数
  ///
  /// 每个字符代表一位数字，按位拼接
  /// 例如：一九五 → 195, 二零二六 → 2026, 一二 → 12
  static int _convertDigitByDigitChinese(String str) {
    final digitMap = <String, int>{
      '零': 0, '〇': 0,
      '一': 1, '二': 2, '三': 3, '四': 4,
      '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
    };
    int result = 0;
    for (int i = 0; i < str.length; i++) {
      final digit = digitMap[str[i]];
      if (digit == null) return 0;
      result = result * 10 + digit;
    }
    return result;
  }
}

/// 解析结果
class ParseResult {
  /// 所有分卷名列表
  final List<String> volumes;
  
  /// 所有章节列表
  final List<ParsedChapter> chapters;
  
  ParseResult({
    required this.volumes,
    required this.chapters,
  });
}

/// 解析出的章节数据
class ParsedChapter {
  /// 章节标题
  final String title;
  
  /// 所属分卷名（空字符串表示未分卷）
  final String volumeName;
  
  /// 全局排序索引
  final int orderIndex;
  
  /// 卷内排序索引
  final int volumeOrderIndex;
  
  /// 章节序号
  final int chapterNumber;
  
  /// 章节内容
  String content;
  
  ParsedChapter({
    required this.title,
    required this.volumeName,
    required this.orderIndex,
    required this.volumeOrderIndex,
    required this.chapterNumber,
    this.content = '',
  });
}

/// 章节信息内部类
class _ChapterInfo {
  final int number;
  final String title;
  final String originalNumberStr; // 保留原始数字字符串（包括前导零）
  
  _ChapterInfo({required this.number, required this.title, this.originalNumberStr = ''});
}
