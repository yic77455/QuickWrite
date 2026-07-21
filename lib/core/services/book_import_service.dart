import 'dart:convert';
import 'dart:io';
import 'package:docx_to_text/docx_to_text.dart';
import 'package:flutter/material.dart';
import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/models/volume.dart';
import 'package:quick_write/core/services/app_paths.dart';
import 'package:quick_write/core/utils/text_parser.dart';
import 'package:quick_write/core/utils/word_count_utils.dart';
import 'package:uuid/uuid.dart';

/// 导入进度回调类型
typedef ProgressCallback = void Function(int current, int total, String status);

/// 导入结果
class ImportResult {
  /// 是否成功
  final bool success;
  
  /// 错误信息（失败时）
  final String? errorMessage;
  
  /// 书名
  final String bookTitle;
  
  /// 书籍文件夹路径
  final String bookFolderPath;
  
  /// 识别到的章节数量
  final int chapterCount;
  
  /// 识别到的分卷数量
  final int volumeCount;
  
  /// 总字数
  final int totalWordCount;
  
  /// 章节列表
  final List<ChapterModel> chapters;
  
  /// 分卷列表
  final List<VolumeModel> volumes;
  
  ImportResult({
    required this.success,
    this.errorMessage,
    this.bookTitle = '',
    this.bookFolderPath = '',
    this.chapterCount = 0,
    this.volumeCount = 0,
    this.totalWordCount = 0,
    this.chapters = const [],
    this.volumes = const [],
  });
}

/// 书籍导入服务
/// 
/// 负责处理书籍导入的核心逻辑：
/// - 读取 txt/docx 文件
/// - 解析文本内容，识别章节和分卷
/// - 创建书籍目录结构
/// - 保存章节文件
class BookImportService {
  /// 单例实例
  static final BookImportService instance = BookImportService._internal();
  BookImportService._internal();
  
  /// 文本解析器
  final TextParser _parser = TextParser();
  
  /// 导入单本书籍
  /// 
  /// [filePath] 文件路径（txt 或 docx）
  /// [bookTitle] 书名（可选，默认使用文件名）
  /// [onProgress] 进度回调
  Future<ImportResult> importBook({
    required String filePath,
    String? bookTitle,
    ProgressCallback? onProgress,
  }) async {
    try {
      // 1. 获取书名
      final file = File(filePath);
      if (!await file.exists()) {
        return ImportResult(
          success: false,
          errorMessage: '文件不存在',
        );
      }
      
      final fileName = file.path.split(Platform.pathSeparator).last;
      final extension = fileName.split('.').last.toLowerCase();
      
      // 检查文件格式
      if (extension != 'txt' && extension != 'docx') {
        return ImportResult(
          success: false,
          errorMessage: '不支持的文件格式，仅支持 txt 和 docx',
        );
      }
      
      // 使用传入的书名或文件名（去除扩展名）
      final title = bookTitle ?? fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
      
      onProgress?.call(0, 100, '正在读取文件...');
      
      // 2. 读取文件内容
      String content;
      if (extension == 'docx') {
        content = await _readDocxFile(file);
      } else {
        content = await _readTxtFile(file);
      }
      
      if (content.isEmpty) {
        return ImportResult(
          success: false,
          errorMessage: '文件内容为空',
        );
      }
      
      onProgress?.call(10, 100, '正在解析文本...');
      
      // 3. 解析文本内容
      final parseResult = _parser.parse(content);
      
      if (parseResult.chapters.isEmpty) {
        return ImportResult(
          success: false,
          errorMessage: '未能识别到章节内容',
        );
      }
      
      onProgress?.call(20, 100, '正在创建书籍目录...');
      
      // 4. 创建书籍目录结构
      final bookFolderPath = await _createBookDirectory(title);
      
      onProgress?.call(25, 100, '正在导入章节文件...');
      
      // 5. 导入章节文件并创建章节数据（主要耗时操作，占 25-90%）
      final chapters = <ChapterModel>[];
      final volumes = <VolumeModel>[];
      int totalWordCount = 0;
      final totalChapters = parseResult.chapters.length;

      // 为解析出的分卷生成 UUID 映射
      final volumeUuidMap = <String, String>{};
      for (final volumeName in parseResult.volumes) {
        final volumeUuid = const Uuid().v4();
        volumeUuidMap[volumeName] = volumeUuid;
        volumes.add(VolumeModel()
          ..uuid = volumeUuid
          ..bookUuid = '' // 稍后在 Provider 中设置
          ..name = volumeName
          ..orderIndex = volumeUuidMap.length - 1
          ..createdAt = DateTime.now()
          ..updatedAt = DateTime.now());
      }
      
      for (int i = 0; i < totalChapters; i++) {
        final parsedChapter = parseResult.chapters[i];
        
        // 更新进度（导入章节占 25-90%）
        final progress = 25 + (i / totalChapters * 65).toInt();
        onProgress?.call(progress, 100, '正在导入: ${parsedChapter.title}');
        
        // 计算字数
        final wordCount = _countWords(parsedChapter.content);
        totalWordCount += wordCount;
        
        // 创建章节文件路径
        final chapterFilePath = await _saveChapterFile(
          bookFolderPath: bookFolderPath,
          volumeName: parsedChapter.volumeName,
          chapterTitle: parsedChapter.title,
          content: parsedChapter.content,
        );
        
        // 通过分卷名称查找对应的 UUID
        final volumeUuid = volumeUuidMap[parsedChapter.volumeName] ?? '';

        // 创建章节模型
        final chapter = ChapterModel()
          ..uuid = const Uuid().v4()
          ..bookUuid = '' // 稍后在 Provider 中设置
          ..title = parsedChapter.title
          ..volumeUuid = volumeUuid
          ..orderIndex = parsedChapter.orderIndex
          ..volumeOrderIndex = parsedChapter.volumeOrderIndex
          ..wordCount = wordCount
          ..filePath = chapterFilePath
          ..createdAt = DateTime.now()
          ..updatedAt = DateTime.now();
        
        chapters.add(chapter);
      }
      
      onProgress?.call(100, 100, '导入完成');
      
      return ImportResult(
        success: true,
        bookTitle: title,
        bookFolderPath: bookFolderPath,
        chapterCount: chapters.length,
        volumeCount: parseResult.volumes.length,
        totalWordCount: totalWordCount,
        chapters: chapters,
        volumes: volumes,
      );
    } catch (e) {
      debugPrint('导入书籍失败: $e');
      return ImportResult(
        success: false,
        errorMessage: '导入失败: $e',
      );
    }
  }
  
  /// 读取 txt 文件
  Future<String> _readTxtFile(File file) async {
    try {
      // 尝试多种编码读取
      final bytes = await file.readAsBytes();
      
      // 尝试 UTF-8
      try {
        final content = utf8.decode(bytes);
        // 检查是否有乱码字符
        if (!_hasGarbledText(content)) {
          return content;
        }
      } catch (_) {}
      
      // 尝试 GBK (简体中文)
      try {
        final content = _decodeGbk(bytes);
        if (!_hasGarbledText(content)) {
          return content;
        }
      } catch (_) {}
      
      // 尝试 GB2312
      try {
        final content = _decodeGb2312(bytes);
        if (!_hasGarbledText(content)) {
          return content;
        }
      } catch (_) {}
      
      // 默认使用 UTF-8，忽略错误
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      debugPrint('读取 txt 文件失败: $e');
      return '';
    }
  }
  
  /// 读取 docx 文件
  Future<String> _readDocxFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final text = docxToText(bytes, handleNumbering: true);
      return text;
    } catch (e) {
      debugPrint('读取 docx 文件失败: $e');
      return '';
    }
  }
  
  /// 创建书籍目录结构
  Future<String> _createBookDirectory(String bookTitle) async {
    final worksPath = await AppPaths.instance.getBooksPath();
    final bookFolderPath = '$worksPath${Platform.pathSeparator}$bookTitle';
    
    final bookDirectory = Directory(bookFolderPath);
    if (!bookDirectory.existsSync()) {
      bookDirectory.createSync(recursive: true);
    }
    
    // 创建 chapters 文件夹
    final chaptersPath = '$bookFolderPath${Platform.pathSeparator}chapters';
    final chaptersDir = Directory(chaptersPath);
    if (!chaptersDir.existsSync()) {
      chaptersDir.createSync(recursive: true);
    }
    
    return bookFolderPath;
  }
  
  /// 保存章节文件
  /// 
  /// 返回相对于书籍 chapters 目录的相对路径
  Future<String> _saveChapterFile({
    required String bookFolderPath,
    required String volumeName,
    required String chapterTitle,
    required String content,
  }) async {
    final chaptersPath = '$bookFolderPath${Platform.pathSeparator}chapters';
    
    // 如果有分卷，创建分卷目录
    String targetPath;
    String relativePath;
    
    if (volumeName.isNotEmpty) {
      // 清理分卷名中的非法文件名字符
      final safeVolumeName = _sanitizeFileName(volumeName);
      targetPath = '$chaptersPath${Platform.pathSeparator}$safeVolumeName';
      relativePath = '$safeVolumeName${Platform.pathSeparator}${_sanitizeFileName(chapterTitle)}${GlobalConstants.chapterFileExtension}';
    } else {
      targetPath = chaptersPath;
      relativePath = '${_sanitizeFileName(chapterTitle)}${GlobalConstants.chapterFileExtension}';
    }

    // 确保目录存在
    final targetDir = Directory(targetPath);
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    // 保存章节文件
    final filePath = '$targetPath${Platform.pathSeparator}${_sanitizeFileName(chapterTitle)}${GlobalConstants.chapterFileExtension}';
    final chapterFile = File(filePath);
    await chapterFile.writeAsString(content);
    
    return relativePath;
  }
  
  /// 清理文件名中的非法字符
  String _sanitizeFileName(String fileName) {
    // 移除 Windows 文件名中不允许的字符: \ / : * ? " < > |
    return fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }
  
  /// 计算字数
  int _countWords(String text) {
    return WordCountUtils.countWords(text);
  }
  
  /// 检查是否有乱码
  bool _hasGarbledText(String text) {
    // 检查常见的乱码模式
    final garbledPatterns = [
      RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), // 控制字符
      RegExp(r'锘'), // BOM 乱码
      RegExp(r'[\ufffd]{2,}'), // 替换字符
    ];
    
    for (final pattern in garbledPatterns) {
      if (pattern.hasMatch(text)) {
        return true;
      }
    }
    return false;
  }
  
  /// GBK 解码（简化实现）
  String _decodeGbk(List<int> bytes) {
    // 由于 Flutter 没有内置 GBK 编码支持，这里使用简化方案
    // 实际项目中建议使用 gbk_codec 包
    return String.fromCharCodes(bytes);
  }
  
  /// GB2312 解码（简化实现）
  String _decodeGb2312(List<int> bytes) {
    return String.fromCharCodes(bytes);
  }

  /// 从文件夹导入书籍
  ///
  /// [folderPath] 文件夹路径
  /// [bookTitle] 书名（可选，默认使用文件夹名）
  /// [onProgress] 进度回调
  ///
  /// 文件夹结构规则：
  /// - 选择的文件夹名称作为书名
  /// - 子目录作为分卷（目录名作为分卷名）
  /// - txt/docx 文件作为章节（文件名作为章节名）
  Future<ImportResult> importFromFolder({
    required String folderPath,
    String? bookTitle,
    ProgressCallback? onProgress,
  }) async {
    try {
      // 1. 检查文件夹是否存在
      final folder = Directory(folderPath);
      if (!await folder.exists()) {
        return ImportResult(
          success: false,
          errorMessage: '文件夹不存在',
        );
      }

      // 使用传入的书名或文件夹名
      final title = bookTitle ?? folderPath.split(Platform.pathSeparator).last;

      onProgress?.call(0, 100, '正在扫描文件夹...');

      // 2. 扫描文件夹结构
      final scanResult = await _scanFolder(folder);
      if (scanResult.isEmpty) {
        return ImportResult(
          success: false,
          errorMessage: '未找到有效的章节文件（txt/docx）',
        );
      }

      onProgress?.call(10, 100, '正在创建书籍目录...');

      // 3. 创建书籍目录结构
      final bookFolderPath = await _createBookDirectory(title);

      onProgress?.call(15, 100, '正在导入章节文件...');

      // 4. 导入章节文件并创建章节数据
      final chapters = <ChapterModel>[];
      final volumes = <VolumeModel>[];
      int totalWordCount = 0;
      int orderIndex = 0;
      final totalFiles = scanResult.length;

      // 收集所有分卷名并生成 UUID 映射
      final volumeNames = <String>{};
      final volumeUuidMap = <String, String>{};
      for (final fileInfo in scanResult) {
        if (fileInfo.volumeName.isNotEmpty && !volumeNames.contains(fileInfo.volumeName)) {
          volumeNames.add(fileInfo.volumeName);
          final volumeUuid = const Uuid().v4();
          volumeUuidMap[fileInfo.volumeName] = volumeUuid;
          volumes.add(VolumeModel()
            ..uuid = volumeUuid
            ..bookUuid = '' // 稍后在 Provider 中设置
            ..name = fileInfo.volumeName
            ..orderIndex = volumes.length
            ..createdAt = DateTime.now()
            ..updatedAt = DateTime.now());
        }
      }

      for (int i = 0; i < totalFiles; i++) {
        final fileInfo = scanResult[i];

        // 更新进度（导入章节占 15-90%）
        final progress = 15 + (i / totalFiles * 75).toInt();
        onProgress?.call(progress, 100, '正在导入: ${fileInfo.chapterTitle}');

        // 读取文件内容
        String content;
        if (fileInfo.extension == 'docx') {
          content = await _readDocxFile(File(fileInfo.filePath));
        } else {
          content = await _readTxtFile(File(fileInfo.filePath));
        }

        if (content.isEmpty) {
          debugPrint('跳过空文件: ${fileInfo.filePath}');
          continue;
        }

        // 计算字数
        final wordCount = _countWords(content);
        totalWordCount += wordCount;

        // 创建章节文件路径
        final chapterFilePath = await _saveChapterFile(
          bookFolderPath: bookFolderPath,
          volumeName: fileInfo.volumeName,
          chapterTitle: fileInfo.chapterTitle,
          content: content,
        );

        // 通过分卷名称查找对应的 UUID
        final volumeUuid = volumeUuidMap[fileInfo.volumeName] ?? '';

        // 创建章节模型
        final chapter = ChapterModel()
          ..uuid = const Uuid().v4()
          ..bookUuid = '' // 稍后在 Provider 中设置
          ..title = fileInfo.chapterTitle
          ..volumeUuid = volumeUuid
          ..orderIndex = orderIndex
          ..volumeOrderIndex = fileInfo.volumeOrderIndex
          ..wordCount = wordCount
          ..filePath = chapterFilePath
          ..createdAt = DateTime.now()
          ..updatedAt = DateTime.now();

        chapters.add(chapter);
        orderIndex++;
      }

      if (chapters.isEmpty) {
        return ImportResult(
          success: false,
          errorMessage: '所有章节文件内容为空',
        );
      }

      // 5. 为章节设置正确的分卷排序索引
      _assignVolumeOrderIndex(chapters);

      onProgress?.call(100, 100, '导入完成');

      return ImportResult(
        success: true,
        bookTitle: title,
        bookFolderPath: bookFolderPath,
        chapterCount: chapters.length,
        volumeCount: volumeNames.length,
        totalWordCount: totalWordCount,
        chapters: chapters,
        volumes: volumes,
      );
    } catch (e) {
      debugPrint('从文件夹导入书籍失败: $e');
      return ImportResult(
        success: false,
        errorMessage: '导入失败: $e',
      );
    }
  }

  /// 扫描文件夹，返回章节文件信息列表
  Future<List<_ChapterFileInfo>> _scanFolder(Directory folder) async {
    final result = <_ChapterFileInfo>[];

    // 先扫描根目录下的文件（无分卷）
    await for (final entity in folder.list()) {
      if (entity is File) {
        final info = _getFileInfo(entity.path, '');
        if (info != null) {
          result.add(info);
        }
      }
    }

    // 再扫描子目录（作为分卷）
    await for (final entity in folder.list()) {
      if (entity is Directory) {
        final volumeName = entity.path.split(Platform.pathSeparator).last;
        // 跳过隐藏目录和特殊目录
        if (volumeName.startsWith('.')) continue;

        await for (final subEntity in entity.list()) {
          if (subEntity is File) {
            final info = _getFileInfo(subEntity.path, volumeName);
            if (info != null) {
              result.add(info);
            }
          }
        }
      }
    }

    // 按文件名排序（自然排序）
    result.sort((a, b) => _naturalCompare(a.chapterTitle, b.chapterTitle));

    return result;
  }

  /// 获取文件信息
  _ChapterFileInfo? _getFileInfo(String filePath, String volumeName) {
    final fileName = filePath.split(Platform.pathSeparator).last;
    final extension = fileName.split('.').last.toLowerCase();

    // 只处理 txt 和 docx 文件
    if (extension != 'txt' && extension != 'docx') {
      return null;
    }

    // 跳过隐藏文件
    if (fileName.startsWith('.')) {
      return null;
    }

    // 章节名为文件名（去除扩展名）
    final chapterTitle = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');

    return _ChapterFileInfo(
      filePath: filePath,
      chapterTitle: chapterTitle,
      volumeName: volumeName,
      extension: extension,
      volumeOrderIndex: 0, // 稍后设置
    );
  }

  /// 自然排序比较（支持数字排序）
  int _naturalCompare(String a, String b) {
    // 提取数字进行比较
    final regExp = RegExp(r'(\d+)');

    final aMatches = regExp.allMatches(a).toList();
    final bMatches = regExp.allMatches(b).toList();

    // 如果两个字符串都包含数字，比较第一个数字
    if (aMatches.isNotEmpty && bMatches.isNotEmpty) {
      final aNum = int.tryParse(aMatches.first.group(1) ?? '0') ?? 0;
      final bNum = int.tryParse(bMatches.first.group(1) ?? '0') ?? 0;
      if (aNum != bNum) {
        return aNum.compareTo(bNum);
      }
    }

    // 否则按字符串比较
    return a.compareTo(b);
  }

  /// 为章节分配分卷排序索引
  void _assignVolumeOrderIndex(List<ChapterModel> chapters) {
    // 按分卷分组
    final volumeGroups = <String, List<ChapterModel>>{};

    for (final chapter in chapters) {
      final volumeKey = chapter.volumeUuid.isEmpty ? '' : chapter.volumeUuid;
      volumeGroups.putIfAbsent(volumeKey, () => []).add(chapter);
    }

    // 为每个分卷内的章节设置分卷排序索引
    for (final group in volumeGroups.values) {
      for (int i = 0; i < group.length; i++) {
        group[i].volumeOrderIndex = i;
      }
    }
  }
}

/// 章节文件信息（内部使用）
class _ChapterFileInfo {
  final String filePath;
  final String chapterTitle;
  final String volumeName;
  final String extension;
  int volumeOrderIndex;

  _ChapterFileInfo({
    required this.filePath,
    required this.chapterTitle,
    required this.volumeName,
    required this.extension,
    required this.volumeOrderIndex,
  });
}
