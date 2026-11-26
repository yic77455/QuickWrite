import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:quick_write/core/models/outline_table.dart';
import 'package:quick_write/core/utils/color_utils.dart';
import 'package:quick_write/core/utils/text_style_range.dart';

/// DOCX 文件构建器
///
/// 使用 Dart 手动构建 DOCX 文件（本质是 ZIP + XML），
/// 支持样式化文本、缩进段落、表格与内嵌图片。
class DocxBuilder {
  /// 正文块（段落、表格与图片按加入顺序输出）
  final List<Object> _body = [];

  /// 已加入的图片资源
  final List<_DocxImage> _images = [];

  /// 添加标题段落
  void addHeading(String text, {int level = 1}) {
    _body.add(_DocxParagraph(
      runs: [DocxRun(text)],
      styleName: 'Heading${level.clamp(1, 4)}',
    ));
  }

  /// 添加正文段落
  void addParagraph(String text) {
    _body.add(_DocxParagraph(runs: [DocxRun(text)]));
  }

  /// 添加带缩进的正文段落
  void addIndentedParagraph(String text, {int indentLevel = 0, String? styleName}) {
    _body.add(_DocxParagraph(
      runs: [DocxRun(text)],
      styleName: styleName,
      indentLevel: indentLevel,
    ));
  }

  /// 添加样式化段落
  ///
  /// [runs] 按顺序拼接的文字片段，每段可带独立样式；
  /// [indentLevel] 用于还原大纲树的层级缩进。
  void addRichParagraph(
    List<DocxRun> runs, {
    int indentLevel = 0,
    String? styleName,
  }) {
    _body.add(_DocxParagraph(
      runs: runs,
      styleName: styleName,
      indentLevel: indentLevel,
    ));
  }

  /// 添加空行
  void addEmptyParagraph() {
    _body.add(_DocxParagraph(runs: const []));
  }

  /// 添加表格
  void addTable(OutlineTableData table) => _body.add(_DocxTable.from(table));

  /// 添加图片
  ///
  /// 图片文件会被读取并嵌入 DOCX；按扩展名和文件头识别格式。
  Future<void> addImage(String filePath, {int indentLevel = 0}) async {
    final file = File(filePath);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    final ext = _imageExtension(filePath, bytes);
    if (ext == null) return;

    final rId = 'rId${_images.length + 2}';
    final size = _imageSize(bytes, ext);
    final image = _DocxImage(
      rId: rId,
      name: 'image${_images.length + 1}.$ext',
      bytes: bytes,
      ext: ext,
      widthEmu: size.$1,
      heightEmu: size.$2,
      indentLevel: indentLevel,
    );
    _images.add(image);
    _body.add(image);
  }

  /// 构建 DOCX 文件并写入指定路径
  Future<void> save(String filePath) async {
    final archive = Archive();

    _addStringToArchive(archive, '[Content_Types].xml', _buildContentTypesXml());
    _addStringToArchive(archive, '_rels/.rels', _relsXml);
    _addStringToArchive(archive, 'word/_rels/document.xml.rels', _buildDocumentRelsXml());
    _addStringToArchive(archive, 'word/styles.xml', _buildStylesXml());
    _addStringToArchive(archive, 'word/document.xml', _buildDocumentXml());

    for (final image in _images) {
      archive.addFile(ArchiveFile('word/media/${image.name}', image.bytes.length, image.bytes));
    }

    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) throw Exception('DOCX 编码失败');
    await File(filePath).writeAsBytes(zipData);
  }

  // ================= XML 模板 =================

  static const String _relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

  void _addStringToArchive(Archive archive, String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  /// 构建内容类型声明，按实际加入的图片追加 Default 项
  String _buildContentTypesXml() {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
      ..writeln('  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
      ..writeln('  <Default Extension="xml" ContentType="application/xml"/>');

    for (final ext in _images.map((image) => image.ext).toSet()) {
      final mime = switch (ext) {
        'png' => 'image/png',
        'jpeg' => 'image/jpeg',
        'gif' => 'image/gif',
        _ => 'application/octet-stream',
      };
      buffer.writeln('  <Default Extension="$ext" ContentType="$mime"/>');
    }

    buffer
      ..writeln('  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>')
      ..writeln('  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>')
      ..writeln('</Types>');
    return buffer.toString();
  }

  /// 构建文档关系声明
  String _buildDocumentRelsXml() {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">')
      ..writeln('  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>');
    for (final image in _images) {
      buffer.writeln('  <Relationship Id="${image.rId}" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
          'Target="media/${image.name}"/>');
    }
    buffer.writeln('</Relationships>');
    return buffer.toString();
  }

  /// 构建 word/styles.xml
  String _buildStylesXml() {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln('<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">')
      ..writeln('''
  <w:style w:type="paragraph" w:styleId="Normal">
    <w:name w:val="Normal"/>
    <w:rPr>
      <w:rFonts w:eastAsia="宋体"/>
    </w:rPr>
  </w:style>''');

    final headingConfigs = [
      _HeadingConfig('Heading1', '宋体', 36, 240, 120),
      _HeadingConfig('Heading2', '宋体', 32, 200, 80),
      _HeadingConfig('Heading3', '宋体', 28, 160, 60),
      _HeadingConfig('Heading4', '宋体', 24, 120, 40),
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

    // 节点标题左对齐，不使用居中样式
    final outlineConfigs = [
      _HeadingConfig('OutlineHeading1', '宋体', 32, 120, 60),
      _HeadingConfig('OutlineHeading2', '宋体', 28, 100, 50),
      _HeadingConfig('OutlineHeading3', '宋体', 24, 80, 40),
    ];
    for (final config in outlineConfigs) {
      buffer.writeln('''
  <w:style w:type="paragraph" w:styleId="${config.styleId}">
    <w:name w:val="${config.styleId}"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:spacing w:before="${config.spaceBefore}" w:after="${config.spaceAfter}"/>
      <w:jc w:val="left"/>
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
  String _buildDocumentXml() {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..writeln('<w:document '
          'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
          'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
          'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
          'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">')
      ..writeln('  <w:body>');

    for (final block in _body) {
      if (block is _DocxParagraph) {
        _writeParagraph(buffer, block);
      } else if (block is _DocxTable) {
        _writeTable(buffer, block);
      } else if (block is _DocxImage) {
        _writeImageParagraph(buffer, block);
      }
    }

    buffer
      ..writeln('  </w:body>')
      ..writeln('</w:document>');
    return buffer.toString();
  }

  /// 写入段落
  void _writeParagraph(StringBuffer buffer, _DocxParagraph paragraph) {
    buffer.writeln('    <w:p>');
    buffer.writeln('      <w:pPr>');
    if (paragraph.styleName != null) {
      buffer.writeln('        <w:pStyle w:val="${paragraph.styleName}"/>');
    }
    if (paragraph.indentLevel > 0) {
      buffer.writeln('        <w:ind w:left="${paragraph.indentLevel * 360}"/>');
    }
    buffer.writeln('      </w:pPr>');
    for (final run in paragraph.runs) {
      _writeRun(buffer, run);
    }
    buffer.writeln('    </w:p>');
  }

  /// 写入带样式的文字片段
  void _writeRun(StringBuffer buffer, DocxRun run) {
    final flags = run.flags;
    final hasStyle = flags.bold ||
        flags.italic ||
        flags.underline ||
        flags.strikethrough ||
        flags.foregroundColor != null ||
        flags.backgroundColor != null ||
        run.halfPoints != null;

    buffer.writeln('      <w:r>');
    if (hasStyle) {
      buffer.write('        <w:rPr>');
      if (flags.bold) buffer.write('<w:b/>');
      if (flags.italic) buffer.write('<w:i/>');
      if (flags.strikethrough) buffer.write('<w:strike/>');
      if (flags.foregroundColor != null) {
        buffer.write('<w:color w:val="${ColorUtils.toHex(flags.foregroundColor!).substring(1)}"/>');
      }
      if (run.halfPoints != null) {
        buffer.write('<w:sz w:val="${run.halfPoints}"/><w:szCs w:val="${run.halfPoints}"/>');
      }
      if (flags.underline) buffer.write('<w:u w:val="single"/>');
      if (flags.backgroundColor != null) {
        buffer.write('<w:shd w:val="clear" w:fill="${ColorUtils.toHex(flags.backgroundColor!).substring(1)}"/>');
      }
      buffer.writeln('</w:rPr>');
    }
    buffer.writeln('        <w:t xml:space="preserve">${_escapeXml(run.text)}</w:t>');
    buffer.writeln('      </w:r>');
  }

  /// 写入图片段落
  void _writeImageParagraph(StringBuffer buffer, _DocxImage image) {
    buffer.writeln('    <w:p>');
    if (image.indentLevel > 0) {
      buffer.writeln('      <w:pPr><w:ind w:left="${image.indentLevel * 360}"/></w:pPr>');
    }
    buffer.writeln('      <w:r>');
    buffer.writeln('        <w:drawing>');
    buffer.writeln('          <wp:inline distT="0" distB="0" distL="0" distR="0">');
    buffer.writeln('            <wp:extent cx="${image.widthEmu}" cy="${image.heightEmu}"/>');
    buffer.writeln('            <wp:docPr id="${image.docPrId}" name="${image.name}"/>');
    buffer.writeln('            <a:graphic>');
    buffer.writeln('              <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">');
    buffer.writeln('                <pic:pic>');
    buffer.writeln('                  <pic:nvPicPr>');
    buffer.writeln('                    <pic:cNvPr id="0" name="${image.name}"/>');
    buffer.writeln('                    <pic:cNvPicPr/>');
    buffer.writeln('                  </pic:nvPicPr>');
    buffer.writeln('                  <pic:blipFill>');
    buffer.writeln('                    <a:blip r:embed="${image.rId}"/>');
    buffer.writeln('                    <a:stretch><a:fillRect/></a:stretch>');
    buffer.writeln('                  </pic:blipFill>');
    buffer.writeln('                  <pic:spPr>');
    buffer.writeln('                    <a:xfrm><a:off x="0" y="0"/>'
        '<a:ext cx="${image.widthEmu}" cy="${image.heightEmu}"/></a:xfrm>');
    buffer.writeln('                    <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>');
    buffer.writeln('                  </pic:spPr>');
    buffer.writeln('                </pic:pic>');
    buffer.writeln('              </a:graphicData>');
    buffer.writeln('            </a:graphic>');
    buffer.writeln('          </wp:inline>');
    buffer.writeln('        </w:drawing>');
    buffer.writeln('      </w:r>');
    buffer.writeln('    </w:p>');
  }

  /// 写入表格
  void _writeTable(StringBuffer buffer, _DocxTable table) {
    const int columnWidth = 2400;
    buffer.writeln('    <w:tbl>');
    buffer.writeln('      <w:tblPr>');
    if (table.alignment != OutlineTableAlignment.left) {
      final jc = table.alignment == OutlineTableAlignment.center ? 'center' : 'right';
      buffer.writeln('        <w:jc w:val="$jc"/>');
    }
    buffer.writeln('      </w:tblPr>');
    buffer.writeln('      <w:tblGrid>');
    for (int i = 0; i < table.columnCount; i++) {
      buffer.writeln('        <w:gridCol w:w="$columnWidth"/>');
    }
    buffer.writeln('      </w:tblGrid>');

    for (final row in table.rows) {
      buffer.writeln('      <w:tr>');
      for (final cell in row) {
        buffer.writeln('        <w:tc>');
        buffer.writeln('          <w:tcPr><w:tcW w:w="$columnWidth" w:type="dxa"/></w:tcPr>');
        buffer.writeln('          <w:p>');
        _writeRun(buffer, cell);
        buffer.writeln('          </w:p>');
        buffer.writeln('        </w:tc>');
      }
      buffer.writeln('      </w:tr>');
    }
    buffer.writeln('    </w:tbl>');
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

  /// 按文件扩展名和文件头识别图片格式
  String? _imageExtension(String path, Uint8List bytes) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png') || (bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50)) {
      return 'png';
    }
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        (bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8)) {
      return 'jpeg';
    }
    if (lower.endsWith('.gif') ||
        (bytes.length > 6 && String.fromCharCodes(bytes.sublist(0, 6)).startsWith('GIF'))) {
      return 'gif';
    }
    return null;
  }

  /// 读取图片尺寸并换算为 EMU（914400 EMU = 1 英寸）
  (int, int) _imageSize(Uint8List bytes, String ext) {
    const int maxWidthEmu = 3800000;
    int? width;
    int? height;

    if (ext == 'png' && bytes.length >= 24) {
      width = _readUint32(bytes, 16);
      height = _readUint32(bytes, 20);
    } else if (ext == 'gif' && bytes.length >= 10) {
      width = bytes[6] | (bytes[7] << 8);
      height = bytes[8] | (bytes[9] << 8);
    } else if (ext == 'jpeg') {
      int i = 2;
      while (i + 9 < bytes.length) {
        if (bytes[i] != 0xFF) {
          i++;
          continue;
        }
        final marker = bytes[i + 1];
        if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
          height = (bytes[i + 5] << 8) | bytes[i + 6];
          width = (bytes[i + 7] << 8) | bytes[i + 8];
          break;
        }
        final length = (bytes[i + 2] << 8) | bytes[i + 3];
        if (length < 2) break;
        i += 2 + length;
      }
    }

    if (width == null || height == null || width <= 0 || height <= 0) return (maxWidthEmu, 2600000);
    final ratio = height / width;
    return (maxWidthEmu, (maxWidthEmu * ratio).round());
  }

  int _readUint32(Uint8List bytes, int offset) =>
      (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
}

/// 带样式的文字片段
class DocxRun {
  /// 文本内容
  final String text;

  /// 文字样式
  final TextStyleFlags flags;

  /// 半磅字号（可选）
  final int? halfPoints;

  const DocxRun(this.text, [this.flags = TextStyleFlags.none, this.halfPoints]);
}

/// 段落数据
class _DocxParagraph {
  final List<DocxRun> runs;
  final String? styleName;
  final int indentLevel;

  _DocxParagraph({required this.runs, this.styleName, this.indentLevel = 0});
}

/// 表格块
class _DocxTable {
  final List<List<DocxRun>> rows;
  final OutlineTableAlignment alignment;

  _DocxTable({required this.rows, required this.alignment});

  int get columnCount => rows.isEmpty ? 0 : rows.first.length;

  factory _DocxTable.from(OutlineTableData table) {
    return _DocxTable(
      alignment: table.alignment,
      rows: [
        for (final row in table.rows)
          [
            for (final cell in row)
              DocxRun(
                cell.text,
                cell.flags.copyWith(clearLink: true),
                cell.headingLevel > 0 ? 24 + cell.headingLevel * 2 : null,
              ),
          ],
      ],
    );
  }
}

/// 图片块
class _DocxImage {
  final String rId;
  final String name;
  final String ext;
  final Uint8List bytes;
  final int widthEmu;
  final int heightEmu;
  final int indentLevel;

  int get docPrId => int.tryParse(rId.replaceFirst('rId', '')) ?? 1;

  _DocxImage({
    required this.rId,
    required this.name,
    required this.ext,
    required this.bytes,
    required this.widthEmu,
    required this.heightEmu,
    required this.indentLevel,
  });
}

/// 标题样式配置
class _HeadingConfig {
  final String styleId;
  final String fontName;
  final int fontSize;
  final int spaceBefore;
  final int spaceAfter;

  _HeadingConfig(this.styleId, this.fontName, this.fontSize, this.spaceBefore, this.spaceAfter);
}
