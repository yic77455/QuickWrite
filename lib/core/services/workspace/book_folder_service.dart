// 书籍文件夹结构与路径服务
//
// 提供书籍文件夹的创建、检查与路径计算能力，
// 供工作台 Provider 与未来的导出/备份等场景复用。
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/models/setting_item.dart';
import 'package:quick_write/core/services/app_paths.dart';

/// 书籍文件夹结构与路径服务
class BookFolderService {
  /// 确保书籍文件夹结构完整
  ///
  /// - 检查书籍文件夹是否存在
  /// - 检查 chapters 文件夹是否存在
  /// - 检查 settings 文件夹是否存在（如不存在则创建）
  Future<void> ensureBookFolderStructure(BookModel book) async {
    try {
      final worksPath = await AppPaths.instance.getBooksPath();
      final folderPath = '$worksPath${Platform.pathSeparator}${book.title}';

      // 检查书籍文件夹
      final bookDir = Directory(folderPath);
      if (!await bookDir.exists()) {
        await bookDir.create(recursive: true);
        debugPrint('已创建书籍文件夹: $folderPath');
      }

      // 检查 chapters 文件夹
      final chaptersPath = '$folderPath${Platform.pathSeparator}chapters';
      final chaptersDir = Directory(chaptersPath);
      if (!await chaptersDir.exists()) {
        await chaptersDir.create(recursive: true);
        debugPrint('已创建章节文件夹: $chaptersPath');
      }

      // 检查 settings 文件夹（设定文件夹）
      final settingsPath = '$folderPath${Platform.pathSeparator}settings';
      final settingsDir = Directory(settingsPath);
      if (!await settingsDir.exists()) {
        await settingsDir.create(recursive: true);
        debugPrint('已创建设定文件夹: $settingsPath');
      }
    } catch (e) {
      debugPrint('确保书籍文件夹结构失败: $e');
    }
  }

  /// 获取书籍文件夹路径
  String bookFolderPath(BookModel book) {
    // 这里使用同步方式获取路径，因为 AppPaths 已经初始化
    final worksPath = '${AppPaths.instance.appRootPath}${Platform.pathSeparator}works';
    return '$worksPath${Platform.pathSeparator}${book.title}';
  }

  /// 获取章节文件的完整路径
  String chapterFilePath(BookModel book, ChapterModel chapter) {
    return '${bookFolderPath(book)}${Platform.pathSeparator}chapters${Platform.pathSeparator}${chapter.filePath}';
  }

  /// 获取设定项文件的完整路径
  String settingItemFilePath(BookModel book, SettingItemModel item) {
    return '${bookFolderPath(book)}${Platform.pathSeparator}settings${Platform.pathSeparator}${item.filePath}';
  }
}
