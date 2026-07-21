import 'dart:io';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/models/recycle_bin.dart';
import 'package:quick_write/core/services/app_paths.dart';

/// 数据完整性校验结果
class IntegrityCheckResult {
  /// 丢失文件夹的书籍列表
  final List<BookModel> missingFolderBooks;

  /// 丢失文件的章节列表（按书籍分组）
  final Map<String, List<MissingChapterInfo>> missingFileChapters;

  /// 无主章节（所属书籍不存在的章节）
  final List<ChapterModel> orphanChapters;

  /// 是否有问题
  bool get hasIssues =>
      missingFolderBooks.isNotEmpty ||
      missingFileChapters.isNotEmpty ||
      orphanChapters.isNotEmpty;

  IntegrityCheckResult({
    this.missingFolderBooks = const [],
    this.missingFileChapters = const {},
    this.orphanChapters = const [],
  });
}

/// 丢失章节信息
class MissingChapterInfo {
  final ChapterModel chapter;
  final String expectedPath;

  MissingChapterInfo({
    required this.chapter,
    required this.expectedPath,
  });
}

/// 数据完整性校验服务
///
/// 在应用启动时检查数据库与本地文件的一致性：
/// 1. 检查书籍文件夹是否存在
/// 2. 检查章节文件是否存在
/// 3. 检查孤儿章节（书籍不存在但章节存在）
class DataIntegrityService {
  static final DataIntegrityService instance = DataIntegrityService._internal();
  DataIntegrityService._internal();

  /// 执行完整性校验
  ///
  /// [isar] 数据库实例
  /// 返回校验结果
  Future<IntegrityCheckResult> checkIntegrity(Isar isar) async {
    debugPrint('开始数据完整性校验...');

    final missingFolderBooks = <BookModel>[];
    final missingFileChapters = <String, List<MissingChapterInfo>>{};
    final orphanChapters = <ChapterModel>[];

    try {
      final worksPath = await AppPaths.instance.getBooksPath();

      // 1. 获取所有书籍
      final books = await isar.bookModels.where().findAll();
      final bookUuidSet = books.map((b) => b.uuid).toSet();

      // 2. 检查每本书的文件夹是否存在
      for (final book in books) {
        final bookFolderPath = '$worksPath${Platform.pathSeparator}${book.title}';
        final bookDir = Directory(bookFolderPath);

        if (!await bookDir.exists()) {
          debugPrint('书籍文件夹不存在: ${book.title}');
          missingFolderBooks.add(book);
          continue;
        }

        // 3. 检查该书籍的章节文件是否存在
        final chapters = await isar.chapterModels
            .where()
            .bookUuidEqualTo(book.uuid)
            .findAll();

        final missingChapters = <MissingChapterInfo>[];

        for (final chapter in chapters) {
          // 构建章节文件的完整路径
          final chapterFilePath =
              '$bookFolderPath${Platform.pathSeparator}chapters${Platform.pathSeparator}${chapter.filePath}';
          final chapterFile = File(chapterFilePath);

          if (!await chapterFile.exists()) {
            debugPrint('章节文件不存在: ${book.title} - ${chapter.title}');
            missingChapters.add(MissingChapterInfo(
              chapter: chapter,
              expectedPath: chapterFilePath,
            ));
          }
        }

        if (missingChapters.isNotEmpty) {
          missingFileChapters[book.uuid] = missingChapters;
        }
      }

      // 4. 检查无主章节（所属书籍不存在的章节）
      // 注意：需要同时检查书架和回收站中的书籍，避免误报
      final allChapters = await isar.chapterModels.where().findAll();
      
      // 获取回收站中所有书籍的 bookUuid
      final recycledBooks = await isar.recycleBinModels.where().findAll();
      final recycledBookUuidSet = recycledBooks.map((b) => b.bookUuid).toSet();
      
      for (final chapter in allChapters) {
        // 如果章节所属书籍既不在书架，也不在回收站，才是真正的无主章节
        if (!bookUuidSet.contains(chapter.bookUuid) && !recycledBookUuidSet.contains(chapter.bookUuid)) {
          debugPrint('无主章节: ${chapter.title} (bookUuid: ${chapter.bookUuid})');
          orphanChapters.add(chapter);
        }
      }

      debugPrint(
          '校验完成: 丢失文件夹书籍 ${missingFolderBooks.length} 本, '
          '丢失文件章节 ${missingFileChapters.values.fold(0, (sum, list) => sum + list.length)} 个, '
          '无主章节 ${orphanChapters.length} 个');

      return IntegrityCheckResult(
        missingFolderBooks: missingFolderBooks,
        missingFileChapters: missingFileChapters,
        orphanChapters: orphanChapters,
      );
    } catch (e) {
      debugPrint('数据完整性校验失败: $e');
      return IntegrityCheckResult();
    }
  }

  /// 清理丢失文件夹的书籍（从数据库删除）
  ///
  /// [isar] 数据库实例
  /// [books] 要删除的书籍列表
  /// 返回被删除的章节数量
  Future<int> removeMissingFolderBooks(
      Isar isar, List<BookModel> books) async {
    if (books.isEmpty) return 0;

    final bookUuids = books.map((b) => b.uuid).toSet();
    final bookIds = books.map((b) => b.id).toList();
    int deletedChaptersCount = 0;

    await isar.writeTxn(() async {
      // 删除书籍记录
      await isar.bookModels.deleteAll(bookIds);
      // 删除相关章节
      for (final uuid in bookUuids) {
        deletedChaptersCount += await isar.chapterModels.where().bookUuidEqualTo(uuid).deleteAll();
      }
    });

    debugPrint('已清理 ${books.length} 本丢失文件夹的书籍，同时清理 $deletedChaptersCount 个章节');
    return deletedChaptersCount;
  }

  /// 清理丢失文件的章节（从数据库删除）
  ///
  /// [isar] 数据库实例
  /// [chapters] 要删除的章节列表
  Future<void> removeMissingFileChapters(
      Isar isar, List<ChapterModel> chapters) async {
    if (chapters.isEmpty) return;

    final chapterIds = chapters.map((c) => c.id).toList();

    await isar.writeTxn(() async {
      await isar.chapterModels.deleteAll(chapterIds);
    });

    debugPrint('已清理 ${chapters.length} 个丢失文件的章节');
  }

  /// 清理无主章节（从数据库删除）
  ///
  /// [isar] 数据库实例
  /// [chapters] 要删除的章节列表
  Future<void> removeOrphanChapters(
      Isar isar, List<ChapterModel> chapters) async {
    if (chapters.isEmpty) return;

    final chapterIds = chapters.map((c) => c.id).toList();

    await isar.writeTxn(() async {
      await isar.chapterModels.deleteAll(chapterIds);
    });

    debugPrint('已清理 ${chapters.length} 个无主章节');
  }
}
