// 书籍文件夹结构与路径服务
//
// 提供书籍文件夹的创建、检查与路径计算能力，
// 供工作台 Provider 与未来的导出/备份等场景复用。
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/models/book.dart';
import 'package:quick_write/core/models/chapter.dart';
import 'package:quick_write/core/models/setting_item.dart';
import 'package:quick_write/core/services/app_paths.dart';
import 'package:quick_write/core/utils/relative_path_utils.dart';

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
    final worksPath = AppPaths.instance.booksPath;
    return '$worksPath${Platform.pathSeparator}${book.title}';
  }

  /// 获取书籍封面文件的完整路径
  ///
  /// 封面固定存放在书籍文件夹下，数据库中只记录文件名（如 cover.jpg），
  /// 完整路径在此统一拼接，任何平台都无需把路径写进数据库。
  /// 文件名为空表示该书没有封面，此时返回空路径
  String coverFilePath(BookModel book) {
    if (book.coverFileName.isEmpty) return '';
    return '${bookFolderPath(book)}${Platform.pathSeparator}${book.coverFileName}';
  }

  /// 获取章节文件的完整路径
  String chapterFilePath(BookModel book, ChapterModel chapter) {
    final relativePath = relativePathToPlatform(chapter.filePath);
    return '${bookFolderPath(book)}${Platform.pathSeparator}chapters${Platform.pathSeparator}$relativePath';
  }

  /// 获取设定项文件的完整路径
  String settingItemFilePath(BookModel book, SettingItemModel item) {
    final relativePath = relativePathToPlatform(item.filePath);
    return '${bookFolderPath(book)}${Platform.pathSeparator}settings${Platform.pathSeparator}$relativePath';
  }

  /// 大纲合并伴生文件后缀
  ///
  /// 关键词、关联与备注统一存放在该文件中；
  /// 与设定项文件同目录同名，扩展名替换为 `.json`。
  static const String outlineMetaFileSuffix = '.json';

  /// 大纲折叠状态文件后缀
  ///
  /// 折叠状态属于本地界面状态，单独存放且不参与云同步。
  static const String foldStateFileSuffix = '.fold.json';

  /// 设定项附加图片的目录名
  ///
  /// 图片存放在设定项文件所在目录的 image 文件夹下，
  /// 目录不存在时在插入图片时创建。
  static const String settingImageDirName = 'image';

  /// 设定项的伴生文件后缀集合
  ///
  /// 合并伴生文件由设定项正文派生，随正文一同创建、迁移与删除。
  static const List<String> settingCompanionFileSuffixes = [
    outlineMetaFileSuffix,
  ];

  /// 由设定项文件路径派生指定后缀的伴生文件路径
  ///
  /// 伴生文件与设定项文件同目录同名，扩展名替换为 [suffix]；
  /// 独立存放可避免辅助数据混入正文，影响导出与备份内容。
  /// 路径为空时返回 null。
  static String? companionFilePath(String? settingItemFilePath, String suffix) {
    if (settingItemFilePath == null || settingItemFilePath.isEmpty) return null;
    const String extension = GlobalConstants.settingFileExtension;
    final String base = settingItemFilePath.endsWith(extension)
        ? settingItemFilePath.substring(0, settingItemFilePath.length - extension.length)
        : settingItemFilePath;
    return '$base$suffix';
  }

  /// 由设定项文件路径派生合并伴生文件路径
  static String? outlineMetaFilePath(String? settingItemFilePath) =>
      companionFilePath(settingItemFilePath, outlineMetaFileSuffix);

  /// 由设定项文件路径派生大纲折叠状态文件路径
  ///
  /// 折叠状态文件与设定项文件同目录同名，扩展名替换为 `.fold.json`；
  /// 该文件只在本机使用，不参与云同步。
  static String? foldStateFilePath(String? settingItemFilePath) =>
      companionFilePath(settingItemFilePath, foldStateFileSuffix);

  /// 获取设定项附加图片所在目录
  ///
  /// 目录固定为设定项文件所在目录下的 image 文件夹；
  /// 设定项路径为空时返回 null。
  static String? settingImageDirectory(String? settingItemFilePath) {
    if (settingItemFilePath == null || settingItemFilePath.isEmpty) return null;
    final String parentPath = File(settingItemFilePath).parent.path;
    return '$parentPath${Platform.pathSeparator}$settingImageDirName';
  }

  /// 获取设定项附加图片的完整路径
  ///
  /// [imageFileName] 为空或设定项路径为空时返回 null。
  static String? settingImageFilePath(String? settingItemFilePath, String imageFileName) {
    if (imageFileName.isEmpty) return null;
    final String? directory = settingImageDirectory(settingItemFilePath);
    if (directory == null) return null;
    return '$directory${Platform.pathSeparator}$imageFileName';
  }

  /// 判断路径是否为设定项的伴生文件
  ///
  /// 伴生文件由设定项内容派生，删除后需要同步清理远端副本，
  /// 否则文件层会把本地缺失当成待补齐内容，重新下载已删除的旧文件。
  static bool isSettingCompanionFile(String path) =>
      settingCompanionFileSuffixes.any((suffix) => path.endsWith(suffix));
}
