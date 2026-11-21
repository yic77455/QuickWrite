import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:quick_write/core/utils/android_native.dart';

/// 文件夹导入的数据来源
///
/// 桌面端拿到的是可直接读写的真实路径，安卓端只能通过系统文件选择器获得
/// content:// 授权。两种来源统一暴露「列目录 + 读字节」接口，
/// 上层的章节解析与写入逻辑无需关心数据究竟从哪里来。
abstract class ImportFolderSource {
  /// 文件夹名称（作为默认书名）
  String get folderName;

  /// 界面展示的位置说明
  String get displayLocation;

  /// 列出待导入的章节文件，按分卷卷标与章节标题排序
  Future<List<ImportFileEntry>> listFiles();
}

/// 待导入的章节文件
class ImportFileEntry {
  /// 文件显示名（含扩展名）
  final String fileName;

  /// 所属分卷名，文件位于来源根目录时为空字符串
  final String volumeName;

  /// 读取文件字节的实现，由具体来源提供
  final Future<Uint8List?> Function() _readBytes;

  ImportFileEntry({
    required this.fileName,
    required this.volumeName,
    required Future<Uint8List?> Function() readBytes,
  }) : _readBytes = readBytes;

  /// 章节标题（文件名去掉扩展名）
  String get chapterTitle => fileName.replaceAll(RegExp(r'\.[^.]+$'), '');

  /// 扩展名（小写，不含点）
  String get extension => fileName.split('.').last.toLowerCase();

  /// 读取文件全部字节，读取失败返回 null
  Future<Uint8List?> readBytes() => _readBytes();
}

/// 来源文件夹已不可用（例如选择后被删除或移动）
class FolderUnavailableException implements Exception {
  const FolderUnavailableException();
}

/// 基于真实文件系统的来源（桌面端）
///
/// 目录结构规则：根目录下的文件作为无分卷章节，一层子目录作为分卷。
class LocalFolderSource implements ImportFolderSource {
  /// 文件夹的绝对路径
  final String folderPath;

  const LocalFolderSource(this.folderPath);

  @override
  String get folderName => folderPath.split(Platform.pathSeparator).last;

  @override
  String get displayLocation => folderPath;

  @override
  Future<List<ImportFileEntry>> listFiles() async {
    final folder = Directory(folderPath);
    if (!await folder.exists()) {
      throw const FolderUnavailableException();
    }

    final entries = <ImportFileEntry>[];

    // 根目录下的文件视为无分卷章节
    await for (final entity in folder.list()) {
      if (entity is File) {
        _addFileEntry(entity.path, '', entries);
      }
    }

    // 一层子目录视为分卷
    await for (final entity in folder.list()) {
      if (entity is! Directory) continue;

      final volumeName = entity.path.split(Platform.pathSeparator).last;
      // 跳过隐藏目录
      if (volumeName.startsWith('.')) continue;

      await for (final child in entity.list()) {
        if (child is File) {
          _addFileEntry(child.path, volumeName, entries);
        }
      }
    }

    _sortEntries(entries);
    return entries;
  }

  /// 把符合格式的文件加入待导入列表
  void _addFileEntry(String path, String volumeName, List<ImportFileEntry> entries) {
    final fileName = path.split(Platform.pathSeparator).last;
    if (!_isImportableFile(fileName)) return;

    entries.add(ImportFileEntry(
      fileName: fileName,
      volumeName: volumeName,
      readBytes: () async {
        try {
          return await File(path).readAsBytes();
        } catch (e) {
          debugPrint('读取章节文件失败: $path: $e');
          return null;
        }
      },
    ));
  }
}

/// 基于安卓系统文件选择器授权的来源
///
/// 应用无法直接枚举共享存储中的目录，这里通过 SAF 返回的目录树 URI
/// 按 URI 列目录、按 URI 读字节，规避分区存储的原始路径限制。
class SafFolderSource implements ImportFolderSource {
  /// 系统文件选择器返回的目录树 URI
  final String treeUri;

  @override
  final String folderName;

  const SafFolderSource({required this.treeUri, required this.folderName});

  @override
  String get displayLocation => '系统文件选择器授权目录';

  @override
  Future<List<ImportFileEntry>> listFiles() async {
    final files = await AndroidNative.listChapterFiles(treeUri);
    final entries = files
        .map((file) => ImportFileEntry(
              fileName: file.fileName,
              volumeName: file.volumeName,
              readBytes: () => AndroidNative.readFileBytes(file.uri),
            ))
        .toList();

    _sortEntries(entries);
    return entries;
  }
}

/// 是否是需要导入的章节文件（跳过隐藏文件与非 txt/docx 文件）
bool _isImportableFile(String fileName) {
  if (fileName.startsWith('.')) return false;

  final extension = fileName.split('.').last.toLowerCase();
  return extension == 'txt' || extension == 'docx';
}

/// 按分卷顺序整理待导入文件
///
/// 先按分卷卷标排序分卷，再在每个分卷内按章节标题自然排序；
/// 未归属分卷的文件固定排在所有分卷之后。
void _sortEntries(List<ImportFileEntry> entries) {
  entries.sort((a, b) {
    final aHasVolume = a.volumeName.isNotEmpty;
    final bHasVolume = b.volumeName.isNotEmpty;

    // 未分卷的文件统一排在分卷文件之后
    if (aHasVolume != bHasVolume) {
      return aHasVolume ? -1 : 1;
    }

    // 不同分卷之间先比较分卷顺序
    if (aHasVolume && a.volumeName != b.volumeName) {
      final volumeOrder = _compareVolumeNames(a.volumeName, b.volumeName);
      if (volumeOrder != 0) return volumeOrder;
    }

    // 同一分卷内按章节标题自然排序
    return _naturalCompare(a.chapterTitle, b.chapterTitle);
  });
}

/// 比较两个分卷名的先后顺序
///
/// 双方都识别出卷标时按卷标序号比较；只有一方识别出卷标时，
/// 有卷标的分卷排在前面；都无法识别时按分卷名自然排序。
int _compareVolumeNames(String a, String b) {
  final aOrder = _parseVolumeOrder(a);
  final bOrder = _parseVolumeOrder(b);

  if (aOrder != null && bOrder != null) {
    final result = aOrder.compareTo(bOrder);
    if (result != 0) return result;
  } else if (aOrder != null) {
    return -1;
  } else if (bOrder != null) {
    return 1;
  }

  return _naturalCompare(a, b);
}

/// 卷标中可出现的数字字符（阿拉伯数字与中文数字）
const String _volumeNumberChars = r'[零〇两一二三四五六七八九十百千万亿壹贰叁肆伍陆柒捌玖拾佰仟\d]+';

/// 匹配「第X卷」「第X部」等卷标（可出现在分卷名任意位置）
final RegExp _volumePrefixedPattern =
    RegExp('第\\s*($_volumeNumberChars)\\s*[卷部册集篇幕]');

/// 匹配「卷X」「卷之X」等卷标
final RegExp _volumeSuffixedPattern =
    RegExp('[卷部册集篇幕]\\s*之?\\s*($_volumeNumberChars)');

/// 匹配「Vol. X」「Volume X」「Book X」「Part X」等卷标
final RegExp _volumeEnglishPattern =
    RegExp(r'(?:vol(?:ume)?|book|part)\.?\s*(\d+)', caseSensitive: false);

/// 匹配以数字开头的卷标，如「01」「1卷」「01 番外」
final RegExp _volumeLeadingNumberPattern =
    RegExp('^($_volumeNumberChars)(?:[卷部册集篇幕]|\$|[\\s._、．:：\\-])');

/// 解析分卷名中的卷标序号
///
/// 支持的格式示例：第一卷、第2部、卷三、卷之四、Vol. 5、Book 6、
/// 01、1卷、01 番外。返回 null 表示未识别到卷标。
int? _parseVolumeOrder(String volumeName) {
  final name = volumeName.trim();
  if (name.isEmpty) return null;

  final prefixed = _volumePrefixedPattern.firstMatch(name);
  if (prefixed != null) {
    return _parseVolumeNumber(prefixed.group(1)!);
  }

  final suffixed = _volumeSuffixedPattern.firstMatch(name);
  if (suffixed != null) {
    return _parseVolumeNumber(suffixed.group(1)!);
  }

  final english = _volumeEnglishPattern.firstMatch(name);
  if (english != null) {
    return int.tryParse(english.group(1)!);
  }

  final leading = _volumeLeadingNumberPattern.firstMatch(name);
  if (leading != null) {
    return _parseVolumeNumber(leading.group(1)!);
  }

  return null;
}

/// 中文数字字符对应的数值
const Map<String, int> _chineseDigitValues = {
  '零': 0, '〇': 0,
  '一': 1, '壹': 1, '二': 2, '两': 2, '贰': 2,
  '三': 3, '叁': 3, '四': 4, '肆': 4,
  '五': 5, '伍': 5, '六': 6, '陆': 6,
  '七': 7, '柒': 7, '八': 8, '捌': 8,
  '九': 9, '玖': 9,
};

/// 中文位置制单位对应的数值
const Map<String, int> _chineseUnitValues = {
  '十': 10, '拾': 10,
  '百': 100, '佰': 100,
  '千': 1000, '仟': 1000,
  '万': 10000,
  '亿': 100000000,
};

/// 把卷标中的数字片段转换为整数
///
/// 阿拉伯数字直接转换；中文数字按位置制解析（如「十一」→ 11），
/// 全部由数字字符组成时按逐位制解析（如「一二」→ 12）。
int? _parseVolumeNumber(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  final arabic = int.tryParse(text);
  if (arabic != null) return arabic;

  // 全为数字字符时逐位拼接，避免多位数被当成单个数字
  final allDigits = text.split('').every(_chineseDigitValues.containsKey);
  if (allDigits) {
    int value = 0;
    for (final char in text.split('')) {
      value = value * 10 + _chineseDigitValues[char]!;
    }
    return value;
  }

  int total = 0;
  int digit = 0;
  bool hasDigit = false;

  for (final char in text.split('')) {
    final unit = _chineseUnitValues[char];
    if (unit != null) {
      // 万、亿按段累计，十、百、千按当前数字换算
      if (unit >= 10000) {
        total = (total + digit) * unit;
      } else {
        total += (digit == 0 ? 1 : digit) * unit;
      }
      digit = 0;
      hasDigit = true;
      continue;
    }

    final value = _chineseDigitValues[char];
    if (value == null) return null;
    digit = value;
    hasDigit = true;
  }

  total += digit;
  return hasDigit ? total : null;
}

/// 自然排序比较
///
/// 把字符串拆分为文本与数字片段后逐段比较：数字片段按数值比较，
/// 文本片段按字典序比较，从而让「第2章」排在「第10章」之前，
/// 并正确识别「第九章」「第十章」这类中文数字章节。
int _naturalCompare(String a, String b) {
  final aTokens = _splitNaturalTokens(a);
  final bTokens = _splitNaturalTokens(b);

  final commonLength =
      aTokens.length < bTokens.length ? aTokens.length : bTokens.length;

  for (int i = 0; i < commonLength; i++) {
    final aToken = aTokens[i];
    final bToken = bTokens[i];

    // 双方都是数字片段时按数值大小比较
    if (aToken.number != null && bToken.number != null) {
      final result = aToken.number!.compareTo(bToken.number!);
      if (result != 0) return result;
      continue;
    }

    // 其余情况按原始文本比较
    final result = aToken.text.compareTo(bToken.text);
    if (result != 0) return result;
  }

  // 前缀相同时，片段更少的字符串排在前面
  final lengthResult = aTokens.length.compareTo(bTokens.length);
  if (lengthResult != 0) return lengthResult;

  // 片段完全等价时按原始文本兜底，保证排序结果稳定
  return a.compareTo(b);
}

/// 把字符串拆分为文本与数字片段
///
/// 连续的阿拉伯数字或中文数字组成一个数字片段，其余字符组成文本片段。
List<_NaturalToken> _splitNaturalTokens(String value) {
  final tokens = <_NaturalToken>[];
  final buffer = StringBuffer();
  bool bufferIsNumber = false;

  void flush() {
    if (buffer.isEmpty) return;
    final text = buffer.toString();
    tokens.add(_NaturalToken(
      text: text,
      number: bufferIsNumber ? _parseVolumeNumber(text) : null,
    ));
    buffer.clear();
  }

  for (final char in value.split('')) {
    final isNumber = _isNaturalNumberChar(char);
    if (buffer.isNotEmpty && isNumber != bufferIsNumber) {
      flush();
    }
    bufferIsNumber = isNumber;
    buffer.write(char);
  }
  flush();

  return tokens;
}

/// 判断字符是否属于数字片段（阿拉伯数字或中文数字）
bool _isNaturalNumberChar(String char) {
  final code = char.codeUnitAt(0);
  final isArabicDigit = code >= 0x30 && code <= 0x39;
  return isArabicDigit ||
      _chineseDigitValues.containsKey(char) ||
      _chineseUnitValues.containsKey(char);
}

/// 自然排序片段
///
/// [number] 非空表示数字片段，比较时按数值大小；
/// 否则按 [text] 的字典序比较。
class _NaturalToken {
  /// 片段原文
  final String text;

  /// 数字片段对应的数值，文本片段为 null
  final int? number;

  const _NaturalToken({required this.text, this.number});
}
