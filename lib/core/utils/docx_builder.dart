import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';

/// DOCX 文件构建器
///
/// 使用 Dart 手动构建 DOCX 文件（本质是 ZIP + XML）
class DocxBuilder {
  // ================= XML 模板常量 =================

  /// [Content_Types].xml 模板
  static const String _contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>''';

  /// _rels/.rels 模板
  static const String _relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

  /// word/_rels/document.xml.rels 模板
  static const String _documentRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''';

  // ================= 文档内容缓存 =================

  /// 段落列表，每段包含样式名和文本
  final List<_DocxParagraph> _paragraphs = [];

  /// 添加标题段落
  ///
  /// [text] 标题文本
  /// [level] 标题级别（1-4），对应 Heading1-Heading4
  void addHeading(String text, {int level = 1}) {
    final styleName = 'Heading$level';
    _paragraphs.add(_DocxParagraph(text: text, styleName: styleName));
  }

  /// 添加正文段落
  ///
  /// [text] 正文文本
  void addParagraph(String text) {
    _paragraphs.add(_DocxParagraph(text: text, styleName: 'Normal'));
  }

  /// 添加空行
  void addEmptyParagraph() {
    _paragraphs.add(_DocxParagraph(text: '', styleName: 'Normal'));
  }

  /// 构建 DOCX 文件并写入指定路径
  ///
  /// [filePath] 输出文件路径
  Future<void> save(String filePath) async {
    final archive = Archive();

    // 添加 [Content_Types].xml
    _addStringToArchive(archive, '[Content_Types].xml', _contentTypesXml);

    // 添加 _rels/.rels
    _addStringToArchive(archive, '_rels/.rels', _relsXml);

    // 添加 word/_rels/document.xml.rels
    _addStringToArchive(archive, 'word/_rels/document.xml.rels', _documentRelsXml);

    // 添加 word/styles.xml
    _addStringToArchive(archive, 'word/styles.xml', _buildStylesXml());

    // 添加 word/document.xml
    _addStringToArchive(archive, 'word/document.xml', _buildDocumentXml());

    // 编码为 ZIP 并写入文件
    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) {
      throw Exception('DOCX 编码失败');
    }
    await File(filePath).writeAsBytes(zipData);
  }

  /// 将字符串添加到 ZIP 归档中
  void _addStringToArchive(Archive archive, String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  /// 构建 word/styles.xml
  ///
  /// 正文样式不指定字体/字号/间距，使用 Word/WPS 默认设置；
  /// 标题样式自定义字体、字号、加粗、段前段后间距
  String _buildStylesXml() {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buffer.writeln('<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">');

    // 正文样式：指定东亚字体为宋体，确保中文标点使用宋体渲染
    buffer.writeln('''
  <w:style w:type="paragraph" w:styleId="Normal">
    <w:name w:val="Normal"/>
    <w:rPr>
      <w:rFonts w:eastAsia="宋体"/>
    </w:rPr>
  </w:style>''');

    // 标题样式（1-4级）
    final headingConfigs = [
      _HeadingConfig('Heading1', '宋体', 36, 240, 120), // 一级标题：小二号，段前段后
      _HeadingConfig('Heading2', '宋体', 32, 200, 80),  // 二级标题：三号
      _HeadingConfig('Heading3', '宋体', 28, 160, 60),  // 三级标题：小三号
      _HeadingConfig('Heading4', '宋体', 24, 120, 40),  // 四级标题：四号
    ];

    for (final config in headingConfigs) {
      buffer.writeln('''
  <w:style w:type="paragraph" w:styleId="${config.styleId}">
    <w:name w:val="${config.styleId}"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:spacing w:before="${config.spaceBefore}" w:after="${config.spaceAfter}"/>
      <w:jc w:val="center"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:eastAsia="${config.fontName}" w:ascii="${config.fontName}" w:hAnsi="${config.fontName}"/>
      <w:sz w:val="${config.fontSize}"/>
      <w:szCs w:val="${config.fontSize}"/>
      <w:b/>
    </w:rPr>
  </w:style>''');
    }

    buffer.writeln('</w:styles>');
    return buffer.toString();
  }

  /// 构建 word/document.xml
  ///
  /// 根据段落列表生成文档主体内容
  String _buildDocumentXml() {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buffer.writeln('<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">');
    buffer.writeln('  <w:body>');

    for (final paragraph in _paragraphs) {
      buffer.writeln('    <w:p>');
      // 段落属性：样式
      buffer.writeln('      <w:pPr>');
      buffer.writeln('        <w:pStyle w:val="${paragraph.styleName}"/>');
      buffer.writeln('      </w:pPr>');
      // 段落文本，hint=eastAsia 强制歧义字符（引号、省略号等）使用东亚字体
      buffer.writeln('      <w:r>');
      buffer.writeln('        <w:rPr><w:rFonts w:hint="eastAsia"/></w:rPr>');
      buffer.writeln('        <w:t xml:space="preserve">${_escapeXml(paragraph.text)}</w:t>');
      buffer.writeln('      </w:r>');
      buffer.writeln('    </w:p>');
    }

    buffer.writeln('  </w:body>');
    buffer.writeln('</w:document>');
    return buffer.toString();
  }

  /// XML 特殊字符转义
  String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

/// 段落数据
class _DocxParagraph {
  /// 文本内容
  final String text;
  /// 样式名称
  final String styleName;

  _DocxParagraph({required this.text, required this.styleName});
}

/// 标题样式配置
class _HeadingConfig {
  final String styleId;
  final String fontName;
  final int fontSize;       // 半磅为单位（24 = 12pt）
  final int spaceBefore;    // 段前间距（twip，1/20 磅）
  final int spaceAfter;     // 段后间距（twip）

  _HeadingConfig(this.styleId, this.fontName, this.fontSize, this.spaceBefore, this.spaceAfter);
}
