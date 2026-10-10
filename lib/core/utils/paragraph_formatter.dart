import 'package:quick_write/core/services/settings_service.dart';

/// 段落格式化工具
///
/// 对已有正文按设置进行段落整理：统一首行缩进与段落间空行。
/// 键入过程中的实时缩进由编辑器的缩进策略负责，不在此处理。
class ParagraphFormatter {
  ParagraphFormatter._();

  /// 对文本进行段落格式化
  ///
  /// 根据设置项对已有文档进行格式化，包括首行缩进和自动空行
  /// 如果设置项关闭，则清除对应的格式
  static String formatText(String text) {
    final settings = SettingsService.instance;
    
    // 按换行符分割成行（同时处理单换行和双换行）
    final lines = text.split('\n');
    final List<String> contentLines = [];
    
    for (final line in lines) {
      // 跳过空行
      if (line.isEmpty) {
        continue;
      }
      contentLines.add(line);
    }
    
    final List<String> formattedLines = [];
    
    for (final line in contentLines) {
      String formattedLine = line;
      
      // 处理首行缩进
      if (settings.isFirstLineIndentEnabled) {
        // 开启时：去除行首已有的空白字符，然后添加两个全角空格
        formattedLine = formattedLine.replaceFirst(RegExp(r'^[\u{3000}\s]+'), '');
        formattedLine = '\u{3000}\u{3000}$formattedLine';
      } else {
        // 关闭时：清除行首的全角空格
        formattedLine = formattedLine.replaceFirst(RegExp(r'^[\u{3000}\s]+'), '');
      }
      
      formattedLines.add(formattedLine);
    }
    
    // 根据自动空行设置连接行
    if (settings.autoLineBreak) {
      return formattedLines.join('\n\n');
    } else {
      return formattedLines.join('\n');
    }
  }
}