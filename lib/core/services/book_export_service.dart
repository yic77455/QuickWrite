import 'dart:io';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/models/setting_group.dart';
import 'package:quick_write/core/models/setting_item.dart';
import 'package:quick_write/core/models/volume.dart';
import 'package:quick_write/core/services/app_paths.dart';
import 'package:quick_write/core/utils/docx_builder.dart';
import 'package:path/path.dart' as p;

/// 导出格式
enum ExportFormat {
  /// TXT 纯文本格式
  txt,
  /// DOCX 文档格式
  docx,
}

/// 导出进度回调类型
typedef ExportProgressCallback = void Function(int current, int total, String status);

/// 导出结果
class ExportResult {
  /// 是否成功
  final bool success;
  /// 错误信息
  final String? errorMessage;
  /// 导出的文件/文件夹路径
  final String? exportPath;
  /// 导出的书籍数量
  final int bookCount;

  ExportResult({
    required this.success,
    this.errorMessage,
    this.exportPath,
    this.bookCount = 0,
  });
}

/// 书籍导出服务
///
/// 负责将书籍导出为 txt 或 docx 格式：
/// - 合并导出：将一本书的所有章节合并为一个文件
/// - 按结构导出：按照分卷建文件夹、每章一个文件的目录结构导出
class BookExportService {
  /// 单例实例
  static final BookExportService instance = BookExportService._internal();
  BookExportService._internal();

  /// 导出单本书籍
  ///
  /// [book] 要导出的书籍模型
  /// [exportDir] 导出目标目录
  /// [format] 导出格式（txt 或 docx）
  /// [mergeIntoOneFile] 是否合并为一个文件导出
  /// [isar] Isar 数据库实例，用于查询章节和分卷数据
  /// [onProgress] 进度回调
  Future<ExportResult> exportBook({
    required BookModel book,
    required String exportDir,
    required ExportFormat format,
    required bool mergeIntoOneFile,
    required Isar isar,
    ExportProgressCallback? onProgress,
  }) async {
    try {
      // 查询该书籍的所有章节和分卷
      final chapters = await isar.chapterModels
          .where()
          .filter()
          .bookUuidEqualTo(book.uuid)
          .sortByOrderIndex()
          .findAll();

      final volumes = await isar.volumeModels
          .where()
          .filter()
          .bookUuidEqualTo(book.uuid)
          .sortByOrderIndex()
          .findAll();

      // 查询该书籍的所有设定项和设定分组
      final settingItems = await isar.settingItemModels
          .where()
          .filter()
          .bookUuidEqualTo(book.uuid)
          .sortByOrderIndex()
          .findAll();

      final settingGroups = await isar.settingGroupModels
          .where()
          .filter()
          .bookUuidEqualTo(book.uuid)
          .sortByOrderIndex()
          .findAll();

      if (chapters.isEmpty && settingItems.isEmpty) {
        return ExportResult(
          success: false,
          errorMessage: '书籍「${book.title}」没有可导出的内容',
        );
      }

      // 获取书籍文件夹路径
      final worksPath = await AppPaths.instance.getBooksPath();
      final bookFolderPath = '$worksPath${Platform.pathSeparator}${book.title}';

      final extension = format == ExportFormat.txt ? '.txt' : '.docx';

      if (mergeIntoOneFile) {
        // 合并为文件导出
        return await _exportMerged(
          book: book,
          chapters: chapters,
          volumes: volumes,
          settingItems: settingItems,
          settingGroups: settingGroups,
          bookFolderPath: bookFolderPath,
          exportDir: exportDir,
          extension: extension,
          format: format,
          onProgress: onProgress,
        );
      } else {
        // 按目录结构导出
        return await _exportStructured(
          book: book,
          chapters: chapters,
          volumes: volumes,
          settingItems: settingItems,
          settingGroups: settingGroups,
          bookFolderPath: bookFolderPath,
          exportDir: exportDir,
          extension: extension,
          format: format,
          onProgress: onProgress,
        );
      }
    } catch (e) {
      debugPrint('导出书籍失败: $e');
      return ExportResult(
        success: false,
        errorMessage: '导出失败: $e',
      );
    }
  }

  /// 合并为文件导出
  ///
  /// 章节合并为一个文件，设定项合并为另一个文件。
  /// 如果设定项为空，则只导出章节文件。
  Future<ExportResult> _exportMerged({
    required BookModel book,
    required List<ChapterModel> chapters,
    required List<VolumeModel> volumes,
    required List<SettingItemModel> settingItems,
    required List<SettingGroupModel> settingGroups,
    required String bookFolderPath,
    required String exportDir,
    required String extension,
    required ExportFormat format,
    ExportProgressCallback? onProgress,
  }) async {
    final totalItems = chapters.length + settingItems.length;
    int processedItems = 0;
    onProgress?.call(0, totalItems, '正在准备导出...');

    // 分卷 UUID -> 分卷名称 的映射
    final volumeMap = <String, String>{};
    for (final v in volumes) {
      volumeMap[v.uuid] = v.name;
    }

    // 分组 UUID -> 分组名称 的映射
    final groupMap = <String, String>{};
    for (final g in settingGroups) {
      groupMap[g.uuid] = g.name;
    }

    // ========== 导出正文合并文件 ==========
    if (chapters.isNotEmpty) {
      // 未分卷章节放到最后
      final sortedChapters = [...chapters.where((c) => c.volumeUuid.isNotEmpty), ...chapters.where((c) => c.volumeUuid.isEmpty)];
      final chapterFileName = _sanitizeFileName(book.title) + extension;
      final chapterFilePath = p.join(exportDir, chapterFileName);

      if (format == ExportFormat.txt) {
        final buffer = StringBuffer();
        String currentVolumeUuid = '';
        bool hasUnvolumeHeader = false;

        for (final chapter in sortedChapters) {
          if (chapter.volumeUuid.isNotEmpty && chapter.volumeUuid != currentVolumeUuid) {
            currentVolumeUuid = chapter.volumeUuid;
            final volumeName = volumeMap[chapter.volumeUuid] ?? '';
            if (volumeName.isNotEmpty) {
              buffer.writeln();
              buffer.writeln('【$volumeName】');
              buffer.writeln();
            }
          } else if (chapter.volumeUuid.isEmpty && !hasUnvolumeHeader) {
            hasUnvolumeHeader = true;
            buffer.writeln();
            buffer.writeln('【未分卷】');
            buffer.writeln();
          }

          buffer.writeln(chapter.title);
          buffer.writeln();

          final content = await _readChapterContent(bookFolderPath, chapter.filePath);
          if (content.isNotEmpty) {
            buffer.writeln(content);
            buffer.writeln();
          }

          processedItems++;
          onProgress?.call(processedItems, totalItems, '正在导出: ${chapter.title}');
        }

        await File(chapterFilePath).writeAsString(buffer.toString());
      } else {
        final docx = DocxBuilder();
        docx.addHeading(book.title, level: 1);
        docx.addEmptyParagraph();

        String currentVolumeUuid = '';
        bool hasUnvolumeHeader = false;
        for (final chapter in sortedChapters) {
          if (chapter.volumeUuid.isNotEmpty && chapter.volumeUuid != currentVolumeUuid) {
            currentVolumeUuid = chapter.volumeUuid;
            final volumeName = volumeMap[chapter.volumeUuid] ?? '';
            if (volumeName.isNotEmpty) {
              docx.addHeading(volumeName, level: 2);
            }
          } else if (chapter.volumeUuid.isEmpty && !hasUnvolumeHeader) {
            hasUnvolumeHeader = true;
            docx.addHeading('未分卷', level: 2);
          }

          docx.addHeading(chapter.title, level: 3);

          final content = await _readChapterContent(bookFolderPath, chapter.filePath);
          if (content.isNotEmpty) {
            for (final line in content.split('\n')) {
              docx.addParagraph(line);
            }
          }
          docx.addEmptyParagraph();

          processedItems++;
          onProgress?.call(processedItems, totalItems, '正在导出: ${chapter.title}');
        }

        await docx.save(chapterFilePath);
      }
    }

    // ========== 导出设定合并文件 ==========
    if (settingItems.isNotEmpty) {
      // 未分组设定项放到最后
      final sortedSettings = [...settingItems.where((i) => i.groupUuid.isNotEmpty), ...settingItems.where((i) => i.groupUuid.isEmpty)];
      final settingFileName = _sanitizeFileName('${book.title}（设定）') + extension;
      final settingFilePath = p.join(exportDir, settingFileName);

      if (format == ExportFormat.txt) {
        final buffer = StringBuffer();
        String currentGroupUuid = '';
        bool hasUngroupHeader = false;

        for (final item in sortedSettings) {
          if (item.groupUuid.isNotEmpty && item.groupUuid != currentGroupUuid) {
            currentGroupUuid = item.groupUuid;
            final groupName = groupMap[item.groupUuid] ?? '';
            if (groupName.isNotEmpty) {
              buffer.writeln();
              buffer.writeln('【$groupName】');
              buffer.writeln();
            }
          } else if (item.groupUuid.isEmpty && !hasUngroupHeader) {
            hasUngroupHeader = true;
            buffer.writeln();
            buffer.writeln('【未分组】');
            buffer.writeln();
          }

          buffer.writeln(item.title);
          buffer.writeln();

          final content = await _readSettingContent(bookFolderPath, item.filePath);
          if (content.isNotEmpty) {
            buffer.writeln(content);
            buffer.writeln();
          }

          processedItems++;
          onProgress?.call(processedItems, totalItems, '正在导出: ${item.title}');
        }

        await File(settingFilePath).writeAsString(buffer.toString());
      } else {
        final docx = DocxBuilder();
        docx.addHeading('${book.title}（设定）', level: 1);
        docx.addEmptyParagraph();

        String currentGroupUuid = '';
        bool hasUngroupHeader = false;
        for (final item in sortedSettings) {
          if (item.groupUuid.isNotEmpty && item.groupUuid != currentGroupUuid) {
            currentGroupUuid = item.groupUuid;
            final groupName = groupMap[item.groupUuid] ?? '';
            if (groupName.isNotEmpty) {
              docx.addHeading(groupName, level: 2);
            }
          } else if (item.groupUuid.isEmpty && !hasUngroupHeader) {
            hasUngroupHeader = true;
            docx.addHeading('未分组', level: 2);
          }

          docx.addHeading(item.title, level: 3);

          final content = await _readSettingContent(bookFolderPath, item.filePath);
          if (content.isNotEmpty) {
            for (final line in content.split('\n')) {
              docx.addParagraph(line);
            }
          }
          docx.addEmptyParagraph();

          processedItems++;
          onProgress?.call(processedItems, totalItems, '正在导出: ${item.title}');
        }

        await docx.save(settingFilePath);
      }
    }

    return ExportResult(
      success: true,
      exportPath: exportDir,
      bookCount: 1,
    );
  }

  /// 按目录结构导出
  ///
  /// 在导出目录下创建以书名命名的文件夹，
  /// 章节放在"正文"子文件夹（按分卷建子目录），设定放在"设定相关"子文件夹（按分组建子目录）
  Future<ExportResult> _exportStructured({
    required BookModel book,
    required List<ChapterModel> chapters,
    required List<VolumeModel> volumes,
    required List<SettingItemModel> settingItems,
    required List<SettingGroupModel> settingGroups,
    required String bookFolderPath,
    required String exportDir,
    required String extension,
    required ExportFormat format,
    ExportProgressCallback? onProgress,
  }) async {
    final totalItems = chapters.length + settingItems.length;
    int processedItems = 0;
    onProgress?.call(0, totalItems, '正在准备导出...');

    // 创建以书名命名的导出文件夹
    final bookExportDir = p.join(exportDir, _sanitizeFileName(book.title));
    await Directory(bookExportDir).create(recursive: true);

    // 分卷 UUID -> 分卷名称 的映射
    final volumeMap = <String, String>{};
    for (final v in volumes) {
      volumeMap[v.uuid] = v.name;
    }

    // 分组 UUID -> 分组名称 的映射
    final groupMap = <String, String>{};
    for (final g in settingGroups) {
      groupMap[g.uuid] = g.name;
    }

    // ========== 导出正文（按分卷建子文件夹） ==========
    if (chapters.isNotEmpty) {
      for (final chapter in chapters) {
        // 确定章节文件的存放目录
        String chapterDir;
        if (chapter.volumeUuid.isNotEmpty) {
          final volumeName = volumeMap[chapter.volumeUuid] ?? '未命名分卷';
          chapterDir = p.join(bookExportDir, '正文', _sanitizeFileName(volumeName));
        } else {
          chapterDir = p.join(bookExportDir, '正文');
        }

        await Directory(chapterDir).create(recursive: true);

        final content = await _readChapterContent(bookFolderPath, chapter.filePath);
        final fileName = _sanitizeFileName(chapter.title) + extension;
        final filePath = p.join(chapterDir, fileName);

        if (format == ExportFormat.txt) {
          await File(filePath).writeAsString(content);
        } else {
          final docx = DocxBuilder();
          docx.addHeading(chapter.title, level: 3);
          if (content.isNotEmpty) {
            for (final line in content.split('\n')) {
              docx.addParagraph(line);
            }
          }
          await docx.save(filePath);
        }

        processedItems++;
        onProgress?.call(processedItems, totalItems, '正在导出: ${chapter.title}');
      }
    }

    // ========== 导出设定（按分组建子文件夹） ==========
    if (settingItems.isNotEmpty) {
      for (final item in settingItems) {
        // 确定设定项文件的存放目录
        String settingDir;
        if (item.groupUuid.isNotEmpty) {
          final groupName = groupMap[item.groupUuid] ?? '未命名分组';
          settingDir = p.join(bookExportDir, '设定相关', _sanitizeFileName(groupName));
        } else {
          settingDir = p.join(bookExportDir, '设定相关');
        }

        await Directory(settingDir).create(recursive: true);

        final content = await _readSettingContent(bookFolderPath, item.filePath);
        final fileName = _sanitizeFileName(item.title) + extension;
        final filePath = p.join(settingDir, fileName);

        if (format == ExportFormat.txt) {
          await File(filePath).writeAsString(content);
        } else {
          final docx = DocxBuilder();
          docx.addHeading(item.title, level: 3);
          if (content.isNotEmpty) {
            for (final line in content.split('\n')) {
              docx.addParagraph(line);
            }
          }
          await docx.save(filePath);
        }

        processedItems++;
        onProgress?.call(processedItems, totalItems, '正在导出: ${item.title}');
      }
    }

    return ExportResult(
      success: true,
      exportPath: bookExportDir,
      bookCount: 1,
    );
  }

  /// 读取章节内容
  ///
  /// [bookFolderPath] 书籍文件夹路径
  /// [relativePath] 章节文件的相对路径
  Future<String> _readChapterContent(String bookFolderPath, String relativePath) async {
    if (relativePath.isEmpty) return '';

    final fullPath = p.join(bookFolderPath, 'chapters', relativePath);
    final file = File(fullPath);

    if (!await file.exists()) return '';

    try {
      return await file.readAsString();
    } catch (e) {
      debugPrint('读取章节文件失败: $fullPath, 错误: $e');
      return '';
    }
  }

  /// 读取设定项内容
  ///
  /// [bookFolderPath] 书籍文件夹路径
  /// [relativePath] 设定项文件的相对路径
  Future<String> _readSettingContent(String bookFolderPath, String relativePath) async {
    if (relativePath.isEmpty) return '';

    final fullPath = p.join(bookFolderPath, 'settings', relativePath);
    final file = File(fullPath);

    if (!await file.exists()) return '';

    try {
      return await file.readAsString();
    } catch (e) {
      debugPrint('读取设定项文件失败: $fullPath, 错误: $e');
      return '';
    }
  }

  /// 导出章节列表（分卷/章节导出）
  ///
  /// [chapters] 要导出的章节列表
  /// [bookTitle] 书籍标题，用于定位数据文件夹和命名
  /// [volumeName] 分卷名称（分卷导出时使用）
  /// [exportDir] 导出目标目录
  /// [format] 导出格式
  /// [mergeIntoOneFile] 是否合并为一个文件导出
  /// [isar] Isar 数据库实例，用于查询分卷数据
  /// [onProgress] 进度回调
  Future<ExportResult> exportChapters({
    required List<ChapterModel> chapters,
    required String bookTitle,
    String? volumeName,
    required String exportDir,
    required ExportFormat format,
    required bool mergeIntoOneFile,
    Isar? isar,
    ExportProgressCallback? onProgress,
  }) async {
    try {
      if (chapters.isEmpty) {
        return ExportResult(
          success: false,
          errorMessage: '没有可导出的章节内容',
        );
      }

      // 获取书籍文件夹路径
      final worksPath = await AppPaths.instance.getBooksPath();
      final bookFolderPath = '$worksPath${Platform.pathSeparator}$bookTitle';

      final extension = format == ExportFormat.txt ? '.txt' : '.docx';

      // 查询分卷映射（volumeUuid -> volumeName）
      final volumeMap = <String, String>{};
      if (isar != null) {
        final bookUuid = chapters.first.bookUuid;
        final volumes = await isar.volumeModels
            .where()
            .filter()
            .bookUuidEqualTo(bookUuid)
            .sortByOrderIndex()
            .findAll();
        for (final v in volumes) {
          volumeMap[v.uuid] = v.name;
        }
      }

      // 单章导出：直接导出为单个文件
      if (chapters.length == 1) {
        return await _exportSingleChapter(
          chapter: chapters.first,
          bookFolderPath: bookFolderPath,
          exportDir: exportDir,
          extension: extension,
          format: format,
          onProgress: onProgress,
        );
      }

      if (mergeIntoOneFile) {
        // 合并为一个文件导出
        return await _exportChaptersMerged(
          chapters: chapters,
          bookTitle: bookTitle,
          volumeName: volumeName,
          volumeMap: volumeMap,
          bookFolderPath: bookFolderPath,
          exportDir: exportDir,
          extension: extension,
          format: format,
          onProgress: onProgress,
        );
      } else {
        // 按目录结构导出
        return await _exportChaptersStructured(
          chapters: chapters,
          bookTitle: bookTitle,
          volumeName: volumeName,
          volumeMap: volumeMap,
          bookFolderPath: bookFolderPath,
          exportDir: exportDir,
          extension: extension,
          format: format,
          onProgress: onProgress,
        );
      }
    } catch (e) {
      debugPrint('导出章节失败: $e');
      return ExportResult(
        success: false,
        errorMessage: '导出失败: $e',
      );
    }
  }

  /// 导出单个章节
  Future<ExportResult> _exportSingleChapter({
    required ChapterModel chapter,
    required String bookFolderPath,
    required String exportDir,
    required String extension,
    required ExportFormat format,
    ExportProgressCallback? onProgress,
  }) async {
    onProgress?.call(0, 1, '正在导出: ${chapter.title}');

    // 读取章节内容
    final content = await _readChapterContent(bookFolderPath, chapter.filePath);

    // 文件名使用章节名
    final fileName = _sanitizeFileName(chapter.title) + extension;
    final filePath = p.join(exportDir, fileName);

    if (format == ExportFormat.txt) {
      await File(filePath).writeAsString(content);
    } else {
      final docx = DocxBuilder();
      docx.addHeading(chapter.title, level: 3);
      if (content.isNotEmpty) {
        for (final line in content.split('\n')) {
          docx.addParagraph(line);
        }
      }
      await docx.save(filePath);
    }

    onProgress?.call(1, 1, '导出完成');

    return ExportResult(
      success: true,
      exportPath: filePath,
      bookCount: 1,
    );
  }

  /// 合并章节为一个文件导出
  Future<ExportResult> _exportChaptersMerged({
    required List<ChapterModel> chapters,
    required String bookTitle,
    String? volumeName,
    required Map<String, String> volumeMap,
    required String bookFolderPath,
    required String exportDir,
    required String extension,
    required ExportFormat format,
    ExportProgressCallback? onProgress,
  }) async {
    onProgress?.call(0, chapters.length, '正在准备导出...');

    // 未分卷章节放到最后
    final sortedChapters = [...chapters.where((c) => c.volumeUuid.isNotEmpty), ...chapters.where((c) => c.volumeUuid.isEmpty)];

    // 确定导出文件名
    final fileName = _sanitizeFileName(volumeName ?? bookTitle) + extension;
    final filePath = p.join(exportDir, fileName);

    if (format == ExportFormat.txt) {
      final buffer = StringBuffer();
      // 如果有分卷名称，写入分卷标题
      if (volumeName != null && volumeName.isNotEmpty) {
        buffer.writeln('【$volumeName】');
        buffer.writeln();
      }

      // 记录当前分卷，用于在分卷切换时插入分卷标题
      String currentVolumeUuid = '';
      bool hasUnvolumeHeader = false;

      for (int i = 0; i < sortedChapters.length; i++) {
        final chapter = sortedChapters[i];

        // 分卷切换时插入分卷标题
        if (volumeName == null && chapter.volumeUuid.isNotEmpty && chapter.volumeUuid != currentVolumeUuid) {
          currentVolumeUuid = chapter.volumeUuid;
          final vName = volumeMap[chapter.volumeUuid] ?? '';
          if (vName.isNotEmpty) {
            buffer.writeln();
            buffer.writeln('【$vName】');
            buffer.writeln();
          }
        } else if (volumeName == null && chapter.volumeUuid.isEmpty && !hasUnvolumeHeader) {
          hasUnvolumeHeader = true;
          buffer.writeln();
          buffer.writeln('【未分卷】');
          buffer.writeln();
        }

        buffer.writeln(chapter.title);
        buffer.writeln();

        final content = await _readChapterContent(bookFolderPath, chapter.filePath);
        if (content.isNotEmpty) {
          buffer.writeln(content);
          buffer.writeln();
        }

        onProgress?.call(i + 1, sortedChapters.length, '正在导出: ${chapter.title}');
      }

      await File(filePath).writeAsString(buffer.toString());
    } else {
      final docx = DocxBuilder();
      // 如果有分卷名称，写入分卷标题
      if (volumeName != null && volumeName.isNotEmpty) {
        docx.addHeading(volumeName, level: 2);
        docx.addEmptyParagraph();
      }

      // 记录当前分卷，用于在分卷切换时插入分卷标题
      String currentVolumeUuid = '';
      bool hasUnvolumeHeader = false;

      for (int i = 0; i < sortedChapters.length; i++) {
        final chapter = sortedChapters[i];

        // 分卷切换时插入分卷标题
        if (volumeName == null && chapter.volumeUuid.isNotEmpty && chapter.volumeUuid != currentVolumeUuid) {
          currentVolumeUuid = chapter.volumeUuid;
          final vName = volumeMap[chapter.volumeUuid] ?? '';
          if (vName.isNotEmpty) {
            docx.addHeading(vName, level: 2);
          }
        } else if (volumeName == null && chapter.volumeUuid.isEmpty && !hasUnvolumeHeader) {
          hasUnvolumeHeader = true;
          docx.addHeading('未分卷', level: 2);
        }

        docx.addHeading(chapter.title, level: 3);

        final content = await _readChapterContent(bookFolderPath, chapter.filePath);
        if (content.isNotEmpty) {
          for (final line in content.split('\n')) {
            docx.addParagraph(line);
          }
        }
        docx.addEmptyParagraph();

        onProgress?.call(i + 1, chapters.length, '正在导出: ${chapter.title}');
      }

      await docx.save(filePath);
    }

    return ExportResult(
      success: true,
      exportPath: filePath,
      bookCount: 1,
    );
  }

  /// 按目录结构导出章节
  Future<ExportResult> _exportChaptersStructured({
    required List<ChapterModel> chapters,
    required String bookTitle,
    String? volumeName,
    required Map<String, String> volumeMap,
    required String bookFolderPath,
    required String exportDir,
    required String extension,
    required ExportFormat format,
    ExportProgressCallback? onProgress,
  }) async {
    onProgress?.call(0, chapters.length, '正在准备导出...');

    // 创建以书名命名的导出文件夹
    final bookExportDir = p.join(exportDir, _sanitizeFileName(bookTitle));
    await Directory(bookExportDir).create(recursive: true);

    for (int i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];

      // 确定章节文件的存放目录
      String chapterDir;
      if (volumeName != null && volumeName.isNotEmpty) {
        // 分卷导出模式：在书名文件夹下创建分卷文件夹
        chapterDir = p.join(bookExportDir, _sanitizeFileName(volumeName));
      } else if (chapter.volumeUuid.isNotEmpty) {
        // 批量导出模式：按章节所属分卷建文件夹
        final vName = volumeMap[chapter.volumeUuid] ?? '未命名分卷';
        chapterDir = p.join(bookExportDir, _sanitizeFileName(vName));
      } else {
        // 无分卷：直接放在书名文件夹下
        chapterDir = bookExportDir;
      }

      // 确保目录存在
      await Directory(chapterDir).create(recursive: true);

      // 读取章节内容
      final content = await _readChapterContent(bookFolderPath, chapter.filePath);

      // 写入章节文件
      final fileName = _sanitizeFileName(chapter.title) + extension;
      final filePath = p.join(chapterDir, fileName);

      if (format == ExportFormat.txt) {
        await File(filePath).writeAsString(content);
      } else {
        final docx = DocxBuilder();
        docx.addHeading(chapter.title, level: 3);
        if (content.isNotEmpty) {
          for (final line in content.split('\n')) {
            docx.addParagraph(line);
          }
        }
        await docx.save(filePath);
      }

      onProgress?.call(i + 1, chapters.length, '正在导出: ${chapter.title}');
    }

    return ExportResult(
      success: true,
      exportPath: bookExportDir,
      bookCount: 1,
    );
  }

  /// 清理文件名中的非法字符
  String _sanitizeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  /// 导出设定项列表（分组/设定项导出）
  ///
  /// [settingItems] 要导出的设定项列表
  /// [bookTitle] 书籍标题，用于定位数据文件夹和命名
  /// [groupName] 分组名称（分组导出时使用）
  /// [exportDir] 导出目标目录
  /// [format] 导出格式
  /// [mergeIntoOneFile] 是否合并为一个文件导出
  /// [isar] Isar 数据库实例，用于查询分组数据
  /// [onProgress] 进度回调
  Future<ExportResult> exportSettings({
    required List<SettingItemModel> settingItems,
    required String bookTitle,
    String? groupName,
    required String exportDir,
    required ExportFormat format,
    required bool mergeIntoOneFile,
    Isar? isar,
    ExportProgressCallback? onProgress,
  }) async {
    try {
      if (settingItems.isEmpty) {
        return ExportResult(
          success: false,
          errorMessage: '没有可导出的设定内容',
        );
      }

      // 获取书籍文件夹路径
      final worksPath = await AppPaths.instance.getBooksPath();
      final bookFolderPath = '$worksPath${Platform.pathSeparator}$bookTitle';

      final extension = format == ExportFormat.txt ? '.txt' : '.docx';

      // 查询分组映射（groupUuid -> groupName）
      final groupMap = <String, String>{};
      if (isar != null) {
        final bookUuid = settingItems.first.bookUuid;
        final groups = await isar.settingGroupModels
            .where()
            .filter()
            .bookUuidEqualTo(bookUuid)
            .sortByOrderIndex()
            .findAll();
        for (final g in groups) {
          groupMap[g.uuid] = g.name;
        }
      }

      // 单个设定项导出：直接导出为单个文件
      if (settingItems.length == 1) {
        return await _exportSingleSetting(
          settingItem: settingItems.first,
          bookFolderPath: bookFolderPath,
          exportDir: exportDir,
          extension: extension,
          format: format,
          onProgress: onProgress,
        );
      }

      if (mergeIntoOneFile) {
        // 合并为一个文件导出
        return await _exportSettingsMerged(
          settingItems: settingItems,
          bookTitle: bookTitle,
          groupName: groupName,
          groupMap: groupMap,
          bookFolderPath: bookFolderPath,
          exportDir: exportDir,
          extension: extension,
          format: format,
          onProgress: onProgress,
        );
      } else {
        // 按目录结构导出
        return await _exportSettingsStructured(
          settingItems: settingItems,
          bookTitle: bookTitle,
          groupName: groupName,
          groupMap: groupMap,
          bookFolderPath: bookFolderPath,
          exportDir: exportDir,
          extension: extension,
          format: format,
          onProgress: onProgress,
        );
      }
    } catch (e) {
      debugPrint('导出设定项失败: $e');
      return ExportResult(
        success: false,
        errorMessage: '导出失败: $e',
      );
    }
  }

  /// 导出单个设定项
  Future<ExportResult> _exportSingleSetting({
    required SettingItemModel settingItem,
    required String bookFolderPath,
    required String exportDir,
    required String extension,
    required ExportFormat format,
    ExportProgressCallback? onProgress,
  }) async {
    onProgress?.call(0, 1, '正在导出: ${settingItem.title}');

    final content = await _readSettingContent(bookFolderPath, settingItem.filePath);

    final fileName = _sanitizeFileName(settingItem.title) + extension;
    final filePath = p.join(exportDir, fileName);

    if (format == ExportFormat.txt) {
      await File(filePath).writeAsString(content);
    } else {
      final docx = DocxBuilder();
      docx.addHeading(settingItem.title, level: 3);
      if (content.isNotEmpty) {
        for (final line in content.split('\n')) {
          docx.addParagraph(line);
        }
      }
      await docx.save(filePath);
    }

    onProgress?.call(1, 1, '导出完成');

    return ExportResult(
      success: true,
      exportPath: filePath,
      bookCount: 1,
    );
  }

  /// 合并设定项为一个文件导出
  Future<ExportResult> _exportSettingsMerged({
    required List<SettingItemModel> settingItems,
    required String bookTitle,
    String? groupName,
    required Map<String, String> groupMap,
    required String bookFolderPath,
    required String exportDir,
    required String extension,
    required ExportFormat format,
    ExportProgressCallback? onProgress,
  }) async {
    onProgress?.call(0, settingItems.length, '正在准备导出...');

    // 未分组设定项放到最后
    final sortedSettings = [...settingItems.where((i) => i.groupUuid.isNotEmpty), ...settingItems.where((i) => i.groupUuid.isEmpty)];

    final fileName = _sanitizeFileName(groupName != null ? '$groupName（设定）' : '$bookTitle（设定）') + extension;
    final filePath = p.join(exportDir, fileName);

    if (format == ExportFormat.txt) {
      final buffer = StringBuffer();
      // 如果有分组名称，写入分组标题
      if (groupName != null && groupName.isNotEmpty) {
        buffer.writeln('【$groupName】');
        buffer.writeln();
      }

      String currentGroupUuid = '';
      bool hasUngroupHeader = false;

      for (int i = 0; i < sortedSettings.length; i++) {
        final item = sortedSettings[i];

        // 分组切换时插入分组标题
        if (groupName == null && item.groupUuid.isNotEmpty && item.groupUuid != currentGroupUuid) {
          currentGroupUuid = item.groupUuid;
          final gName = groupMap[item.groupUuid] ?? '';
          if (gName.isNotEmpty) {
            buffer.writeln();
            buffer.writeln('【$gName】');
            buffer.writeln();
          }
        } else if (groupName == null && item.groupUuid.isEmpty && !hasUngroupHeader) {
          hasUngroupHeader = true;
          buffer.writeln();
          buffer.writeln('【未分组】');
          buffer.writeln();
        }

        buffer.writeln(item.title);
        buffer.writeln();

        final content = await _readSettingContent(bookFolderPath, item.filePath);
        if (content.isNotEmpty) {
          buffer.writeln(content);
          buffer.writeln();
        }

        onProgress?.call(i + 1, sortedSettings.length, '正在导出: ${item.title}');
      }

      await File(filePath).writeAsString(buffer.toString());
    } else {
      final docx = DocxBuilder();
      if (groupName != null && groupName.isNotEmpty) {
        docx.addHeading(groupName, level: 2);
        docx.addEmptyParagraph();
      }

      String currentGroupUuid = '';
      bool hasUngroupHeader = false;

      for (int i = 0; i < sortedSettings.length; i++) {
        final item = sortedSettings[i];

        if (groupName == null && item.groupUuid.isNotEmpty && item.groupUuid != currentGroupUuid) {
          currentGroupUuid = item.groupUuid;
          final gName = groupMap[item.groupUuid] ?? '';
          if (gName.isNotEmpty) {
            docx.addHeading(gName, level: 2);
          }
        } else if (groupName == null && item.groupUuid.isEmpty && !hasUngroupHeader) {
          hasUngroupHeader = true;
          docx.addHeading('未分组', level: 2);
        }

        docx.addHeading(item.title, level: 3);

        final content = await _readSettingContent(bookFolderPath, item.filePath);
        if (content.isNotEmpty) {
          for (final line in content.split('\n')) {
            docx.addParagraph(line);
          }
        }
        docx.addEmptyParagraph();

        onProgress?.call(i + 1, settingItems.length, '正在导出: ${item.title}');
      }

      await docx.save(filePath);
    }

    return ExportResult(
      success: true,
      exportPath: filePath,
      bookCount: 1,
    );
  }

  /// 按目录结构导出设定项
  Future<ExportResult> _exportSettingsStructured({
    required List<SettingItemModel> settingItems,
    required String bookTitle,
    String? groupName,
    required Map<String, String> groupMap,
    required String bookFolderPath,
    required String exportDir,
    required String extension,
    required ExportFormat format,
    ExportProgressCallback? onProgress,
  }) async {
    onProgress?.call(0, settingItems.length, '正在准备导出...');

    // 创建以书名命名的导出文件夹
    final bookExportDir = p.join(exportDir, _sanitizeFileName(bookTitle));
    await Directory(bookExportDir).create(recursive: true);

    for (int i = 0; i < settingItems.length; i++) {
      final item = settingItems[i];

      // 确定设定项文件的存放目录
      String settingDir;
      if (groupName != null && groupName.isNotEmpty) {
        // 分组导出模式：在书名文件夹下创建分组文件夹
        settingDir = p.join(bookExportDir, _sanitizeFileName(groupName));
      } else if (item.groupUuid.isNotEmpty) {
        // 批量导出模式：按设定项所属分组建文件夹
        final gName = groupMap[item.groupUuid] ?? '未命名分组';
        settingDir = p.join(bookExportDir, _sanitizeFileName(gName));
      } else {
        // 无分组：直接放在书名文件夹下
        settingDir = bookExportDir;
      }

      await Directory(settingDir).create(recursive: true);

      final content = await _readSettingContent(bookFolderPath, item.filePath);
      final fileName = _sanitizeFileName(item.title) + extension;
      final filePath = p.join(settingDir, fileName);

      if (format == ExportFormat.txt) {
        await File(filePath).writeAsString(content);
      } else {
        final docx = DocxBuilder();
        docx.addHeading(item.title, level: 3);
        if (content.isNotEmpty) {
          for (final line in content.split('\n')) {
            docx.addParagraph(line);
          }
        }
        await docx.save(filePath);
      }

      onProgress?.call(i + 1, settingItems.length, '正在导出: ${item.title}');
    }

    return ExportResult(
      success: true,
      exportPath: bookExportDir,
      bookCount: 1,
    );
  }
}
