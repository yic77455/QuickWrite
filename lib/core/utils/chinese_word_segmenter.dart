import 'dart:math' as math;
import 'dart:ui' show TextRange;

import 'package:flutter/services.dart' show rootBundle;
import 'package:re_editor/re_editor.dart';

/// 中文分词器
///
/// 基于精简词表做最长匹配，为编辑器双击选词提供词汇边界。
/// 词库作为资源文件一次性加载并常驻内存。
class ChineseWordSegmenter {
  ChineseWordSegmenter._();

  /// 全局单例
  static final ChineseWordSegmenter instance = ChineseWordSegmenter._();

  /// 词库资源路径
  static const String _assetPath = 'assets/dict/chinese_words.txt';

  /// 词表中最长词的长度，用于限定匹配尝试范围
  static const int _maxWordLength = 6;

  /// 词表，未加载完成时为 null
  Set<String>? _words;

  /// 加载中的任务，保证只加载一次
  Future<void>? _loading;

  /// 加载词库并把分词器安装到编辑器
  ///
  /// 重复调用不会重复加载；加载失败时静默处理，编辑器将退回内置逻辑。
  Future<void> install() {
    codeWordBoundaryResolver = resolve;
    return _loading ??= _load();
  }

  Future<void> _load() async {
    final String data = await rootBundle.loadString(_assetPath);
    _words = data.split('\n').where((String e) => e.isNotEmpty).toSet();
  }

  /// 解析 [text] 中覆盖 [offset] 位置的词汇范围
  ///
  /// 对整行做正向最大匹配分词，返回命中位置所在词的范围；词库未就绪、
  /// 位置越界或该位置不是汉字时返回 null，交由编辑器内置逻辑处理。
  TextRange? resolve(String text, int offset) {
    final Set<String>? words = _words;
    if (words == null) {
      return null;
    }
    final int length = text.length;
    if (length == 0) {
      return null;
    }
    final int index = offset.clamp(0, length - 1);
    if (!_isHan(text.codeUnitAt(index))) {
      return null;
    }
    // 正向最大匹配逐段切分，直到覆盖目标位置
    int position = 0;
    while (position < length) {
      int matched = 1;
      final int limit = math.min(_maxWordLength, length - position);
      for (int len = limit; len >= 2; len--) {
        if (words.contains(text.substring(position, position + len))) {
          matched = len;
          break;
        }
      }
      if (index < position + matched) {
        return TextRange(start: position, end: position + matched);
      }
      position += matched;
    }
    return TextRange(start: index, end: index + 1);
  }

  /// 判断是否为汉字码元
  bool _isHan(int codeUnit) {
    return (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) ||
        (codeUnit >= 0x3400 && codeUnit <= 0x4DBF) ||
        (codeUnit >= 0xF900 && codeUnit <= 0xFAFF) ||
        codeUnit == 0x3007 ||
        codeUnit == 0x3005;
  }
}
