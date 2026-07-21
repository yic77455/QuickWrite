import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

class FontInfo {
  final String fontFamily; // Flutter 需要的英文/系统名
  final String displayName; // 展示用的中文/本地化名
  final String filePath; // 字体路径

  FontInfo({
    required this.fontFamily,
    required this.displayName,
    required this.filePath,
  });

  @override
  String toString() => 'FontInfo(Family: $fontFamily, Display: $displayName)';
}

class SystemFontParser {
  /// 获取当前系统所有字体的解析结果
  static Future<List<FontInfo>> getSystemFonts() async {
    List<File> fontFiles = _getSystemFontFiles();
    List<FontInfo> result = [];

    for (var file in fontFiles) {
      try {
        // 一个文件可能返回多个字体 (因为 .ttc 格式)
        List<FontInfo> infos = await parseFontFile(file);
        result.addAll(infos);
      } catch (e) {
        // 忽略损坏的或无法读取的字体文件
        continue;
      }
    }

    // 根据 fontFamily 去重 (忽略大小写)
    final Map<String, FontInfo> uniqueFonts = {};
    for (var font in result) {
      uniqueFonts[font.fontFamily.toLowerCase()] = font;
    }

    return uniqueFonts.values.toList();
  }

  /// 解析字体文件头部，提取名称（支持单 TTF 和多 TTC）
  static Future<List<FontInfo>> parseFontFile(File file) async {
    final raf = await file.open(mode: FileMode.read);
    List<FontInfo> extractedFonts = [];

    try {
      // 1. 读取前 4 个字节，判断文件类型
      var tagBytes = await raf.read(4);
      if (tagBytes.length < 4) return [];
      String tag = ascii.decode(tagBytes, allowInvalid: true);

      List<int> fontOffsets = [];

      // 2. 处理 TTC (TrueType Collection) 格式
      if (tag == 'ttcf') {
        await raf.setPosition(8); // 跳过 Header 和 Version (共 8 bytes)
        var numFontsBytes = await raf.read(4); // 读取包含的字体数量
        int numFonts = ByteData.view(numFontsBytes.buffer).getUint32(0);

        var offsetsBytes = await raf.read(numFonts * 4); // 读取所有的偏移量数组
        var offsetsBd = ByteData.view(offsetsBytes.buffer);
        for (int i = 0; i < numFonts; i++) {
          fontOffsets.add(offsetsBd.getUint32(i * 4));
        }
      } else {
        // 验证是否是合法的单字体文件
        final validTags = [
          [0x00, 0x01, 0x00, 0x00], // TTF
          'OTTO'.codeUnits,         // OTF
          'true'.codeUnits          // Mac OS X TTF
        ];
        bool isValid = validTags.any((t) => _listEquals(t, tagBytes));
        if (!isValid) return [];
        
        fontOffsets.add(0); // 单文件，起始偏移量就是 0
      }

      // 3. 遍历提取每个偏移量下的字体名称
      for (int offset in fontOffsets) {
        FontInfo? info = await _extractNameFromSfnt(raf, offset, file.path);
        if (info != null) {
          extractedFonts.add(info);
        }
      }
    } finally {
      await raf.close();
    }

    return extractedFonts;
  }

  /// 内部方法：从给定的 sfnt 偏移量处解析 name 表
  static Future<FontInfo?> _extractNameFromSfnt(RandomAccessFile raf, int sfntOffset, String filePath) async {
    await raf.setPosition(sfntOffset + 4); // 跳过 sfnt version
    var numTablesBytes = await raf.read(2);
    int numTables = ByteData.view(numTablesBytes.buffer).getUint16(0);

    await raf.setPosition(sfntOffset + 12); // 跳到 Table Directory
    var tableRecordsBytes = await raf.read(numTables * 16);
    var tableBd = ByteData.view(tableRecordsBytes.buffer);

    int nameTableOffset = -1;
    int nameTableLength = 0;

    // 寻找 'name' 表
    for (int i = 0; i < numTables; i++) {
      int base = i * 16;
      int tableTag = tableBd.getUint32(base);
      if (tableTag == 0x6E616D65) { // 'name' 的 ASCII Hex
        nameTableOffset = tableBd.getUint32(base + 8);
        nameTableLength = tableBd.getUint32(base + 12);
        break;
      }
    }

    if (nameTableOffset == -1) return null;

    // 将整个 name 表读入内存
    await raf.setPosition(nameTableOffset);
    var nameTableData = await raf.read(nameTableLength);
    var nameBd = ByteData.view(nameTableData.buffer);

    int count = nameBd.getUint16(2);
    int stringOffset = nameBd.getUint16(4);

    String? englishName;
    String? chineseName;

    final chineseRegex = RegExp(r'[\u4e00-\u9fa5]');

    // 遍历 name 记录
    for (int i = 0; i < count; i++) {
      int base = 6 + i * 12;
      if (base + 12 > nameTableData.length) break;

      int platformID = nameBd.getUint16(base);
      // int languageID = nameBd.getUint16(base + 4); // 不再完全依赖 languageID，因为太乱了
      int nameID = nameBd.getUint16(base + 6);
      int length = nameBd.getUint16(base + 8);
      int offset = nameBd.getUint16(base + 10);

      // Name ID 1 (Font Family) 或 Name ID 16 (Typographic Family)
      if (nameID == 1 || nameID == 16 || nameID == 4) {
        int strStart = stringOffset + offset;
        if (strStart + length <= nameTableData.length) {
          Uint8List strBytes = nameTableData.sublist(strStart, strStart + length);
          String decodedStr = '';

          // 尝试用 UTF-16BE 解码 (Platform 3: Windows / Platform 0: Unicode 通常用这个)
          if (platformID == 3 || platformID == 0) {
            decodedStr = _decodeUtf16BE(strBytes);
          } 
          // 尝试用 MacRoman 解码 (Platform 1: Mac)
          else if (platformID == 1) {
            decodedStr = ascii.decode(strBytes, allowInvalid: true).replaceAll('\x00', '');
          }

          decodedStr = decodedStr.trim();

          if (decodedStr.isNotEmpty) {
             // 智能匹配：只要包含中文字符，就认为是中文名
             if (chineseRegex.hasMatch(decodedStr)) {
               // 优先使用 Name ID 1 或 16 作为中文名
               if (chineseName == null || nameID == 1 || nameID == 16) {
                 chineseName = decodedStr;
               }
             } else {
               // 纯英文名，优先使用 Name ID 1 作为传给 Flutter 的 fontFamily
               if (englishName == null || nameID == 1) {
                 englishName = decodedStr;
               }
             }
          }
        }
      }
    }

    if (englishName == null && chineseName == null) return null;

    String finalFamily = englishName ?? chineseName!;
    String finalDisplay = chineseName ?? finalFamily;

    return FontInfo(
      fontFamily: finalFamily,
      displayName: finalDisplay,
      filePath: filePath,
    );
  }

  // --- 辅助方法 ---

  static String _decodeUtf16BE(Uint8List bytes) {
    List<int> chars = [];
    for (int i = 0; i < bytes.length; i += 2) {
      if (i + 1 < bytes.length) {
        int charCode = (bytes[i] << 8) | bytes[i + 1];
        if (charCode != 0) {
          chars.add(charCode);
        }
      }
    }
    return String.fromCharCodes(chars);
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static List<File> _getSystemFontFiles() {
    List<String> dirs = [];
    if (Platform.isWindows) {
      dirs.add(r'C:\Windows\Fonts');
      String? localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null) {
        dirs.add('$localAppData\\Microsoft\\Windows\\Fonts');
      }
    } else if (Platform.isMacOS) {
      dirs.addAll([
        '/System/Library/Fonts',
        '/Library/Fonts',
        '${Platform.environment['HOME']}/Library/Fonts'
      ]);
    } else if (Platform.isLinux) {
      dirs.addAll([
        '/usr/share/fonts',
        '/usr/local/share/fonts',
        '${Platform.environment['HOME']}/.local/share/fonts',
        '${Platform.environment['HOME']}/.fonts'
      ]);
    }

    List<File> files = [];
    for (var path in dirs) {
      final dir = Directory(path);
      if (dir.existsSync()) {
        for (var entity in dir.listSync(recursive: true, followLinks: false)) {
          if (entity is File) {
            final ext = entity.path.toLowerCase();
            if (ext.endsWith('.ttf') || ext.endsWith('.otf') || ext.endsWith('.ttc')) {
              files.add(entity);
            }
          }
        }
      }
    }
    return files;
  }
}