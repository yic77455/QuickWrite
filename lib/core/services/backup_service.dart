import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/services/app_paths.dart';
import 'package:quick_write/core/services/settings_service.dart';

/// 标签页备份信息
class _TabBackupInfo {
  /// 书籍 UUID
  final String bookUuid;

  /// 章节名称
  final String chapterTitle;

  /// 分卷名称（空字符串表示无分卷）
  final String volumeName;

  /// 是否为设定类型（设定使用 settings/ 目录，章节使用 chapters/ 目录）
  final bool isSetting;

  /// 获取当前内容的回调
  final String Function() contentGetter;

  _TabBackupInfo({
    required this.bookUuid,
    required this.chapterTitle,
    required this.volumeName,
    required this.contentGetter,
    this.isSetting = false,
  });
}

/// 备份记录信息
class BackupRecord {
  /// 备份文件完整路径
  final String filePath;

  /// 备份时间
  final DateTime dateTime;

  /// 文件大小（字节）
  final int fileSize;

  BackupRecord({
    required this.filePath,
    required this.dateTime,
    required this.fileSize,
  });

  /// 格式化显示的时间字符串
  String get formattedTime {
    return '${dateTime.year}-'
        '${dateTime.month.toString().padLeft(2, '0')}-'
        '${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}:'
        '${dateTime.second.toString().padLeft(2, '0')}';
  }

  /// 格式化显示的文件大小
  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// 备份服务
///
/// 单例模式，负责管理章节历史备份的创建、清理和定时调度：
/// - 按标签页管理独立的备份计时器
/// - 备份前检查内容是否与上次备份相同，相同则跳过
/// - 超过上限时自动删除最早的备份记录
///
/// 备份目录结构：
/// ```
/// backups/
///   └── {书籍UUID}/
///       ├── chapters/
///       │   └── {章节名称}/
///       │       ├── 20260517_143025.txt
///       │       ├── 20260517_150130.txt
///       │       └── ...
///       └── settings/
///           └── {设定名称}/
///               ├── 20260517_143025.md
///               └── ...
/// ```
class BackupService {
  // ================= 单例模式 =================
  static final BackupService instance = BackupService._internal();
  BackupService._internal();

  // ================= 状态属性 =================

  /// 每个标签页的备份计时器
  final Map<String, Timer> _backupTimers = {};

  /// 每个标签页的备份信息
  final Map<String, _TabBackupInfo> _tabInfos = {};

  /// 每个标签页上次备份的内容（用于比对是否需要新建备份）
  final Map<String, String> _lastBackupContent = {};

  /// 正在执行备份的标签页集合（防止并发备份）
  final Set<String> _backingUpTabs = {};

  // ================= 公开方法 =================

  /// 为指定标签页启动备份计时器
  ///
  /// 如果该标签页已有计时器在运行，则跳过
  /// 如果自动备份未开启，也跳过
  /// [isSetting] 为 true 时使用 settings/ 目录，否则使用 chapters/ 目录
  void startTabBackupTimer({
    required String tabId,
    required String bookUuid,
    required String chapterTitle,
    required String volumeName,
    required String Function() contentGetter,
    bool isSetting = false,
  }) {
    if (_backupTimers.containsKey(tabId)) return;
    if (!SettingsService.instance.autoBackupEnabled) return;

    final interval = Duration(minutes: SettingsService.instance.backupInterval);

    _tabInfos[tabId] = _TabBackupInfo(
      bookUuid: bookUuid,
      chapterTitle: chapterTitle,
      volumeName: volumeName,
      contentGetter: contentGetter,
      isSetting: isSetting,
    );

    _backupTimers[tabId] = Timer.periodic(interval, (_) async {
      if (!SettingsService.instance.autoBackupEnabled) return;
      // 从 _tabInfos 读取最新信息，避免闭包捕获旧值
      final info = _tabInfos[tabId];
      if (info == null) return;
      await _performBackup(tabId, info);
    });

    debugPrint('已启动备份计时器: $chapterTitle, 间隔: ${interval.inMinutes}分钟');
  }

  /// 停止指定标签页的备份计时器
  void stopTabBackupTimer(String tabId) {
    _backupTimers[tabId]?.cancel();
    _backupTimers.remove(tabId);
    _tabInfos.remove(tabId);
    _lastBackupContent.remove(tabId);
    _backingUpTabs.remove(tabId);
  }

  /// 更新指定标签页的备份信息（章节标题或分卷名变更时调用）
  void updateTabBackupInfo({required String tabId, required String chapterTitle, String? volumeName}) {
    final info = _tabInfos[tabId];
    if (info == null) return;

    _tabInfos[tabId] = _TabBackupInfo(
      bookUuid: info.bookUuid,
      chapterTitle: chapterTitle,
      volumeName: volumeName ?? info.volumeName,
      contentGetter: info.contentGetter,
      isSetting: info.isSetting,
    );

    // 清除上次备份缓存，以便下次备份时使用新路径比对
    _lastBackupContent.remove(tabId);
  }

  /// 停止所有备份计时器
  void stopAllBackupTimers() {
    for (final timer in _backupTimers.values) {
      timer.cancel();
    }
    _backupTimers.clear();
    _tabInfos.clear();
    _lastBackupContent.clear();
    _backingUpTabs.clear();
  }

  /// 重启所有备份计时器（用于备份间隔设置变更后刷新计时器周期）
  void restartAllBackupTimers() {
    // 先停止所有计时器
    for (final timer in _backupTimers.values) {
      timer.cancel();
    }
    _backupTimers.clear();

    // 保留 _tabInfos、_lastBackupContent 和 _backingUpTabs，用已有的信息重新启动
    for (final entry in _tabInfos.entries) {
      final tabId = entry.key;

      if (!SettingsService.instance.autoBackupEnabled) continue;

      final interval = Duration(minutes: SettingsService.instance.backupInterval);
      _backupTimers[tabId] = Timer.periodic(interval, (_) async {
        if (!SettingsService.instance.autoBackupEnabled) return;
        // 从 _tabInfos 读取最新信息，避免闭包捕获旧值
        final info = _tabInfos[tabId];
        if (info == null) return;
        await _performBackup(tabId, info);
      });
    }
  }

  /// 获取指定章节的备份记录列表
  ///
  /// 按时间降序排列（最新的在前）
  Future<List<BackupRecord>> getChapterBackups(String bookUuid, String chapterTitle, {String volumeName = ''}) async {
    try {
      final backupPath = await AppPaths.instance.getBackupPath();
      final chapterDirPath = _buildChapterBackupPath(backupPath, bookUuid, chapterTitle, volumeName);
      return _collectBackupRecords(chapterDirPath, GlobalConstants.chapterFileExtension);
    } catch (e) {
      debugPrint('获取备份列表失败: $e');
      return [];
    }
  }

  /// 获取指定设定的备份记录列表
  ///
  /// 按时间降序排列（最新的在前）
  Future<List<BackupRecord>> getSettingBackups(String bookUuid, String settingTitle) async {
    try {
      final backupPath = await AppPaths.instance.getBackupPath();
      final settingDirPath = _buildSettingBackupPath(backupPath, bookUuid, settingTitle);
      return _collectBackupRecords(settingDirPath, GlobalConstants.settingFileExtension);
    } catch (e) {
      debugPrint('获取设定备份列表失败: $e');
      return [];
    }
  }

  /// 从指定目录收集备份记录
  ///
  /// [extension] 指定备份文件扩展名，章节备份为 .txt，设定项备份为 .md
  /// 列出目录下匹配扩展名的备份文件，解析文件名时间戳并按时间降序排列
  Future<List<BackupRecord>> _collectBackupRecords(String dirPath, String extension) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];

    final files = await dir
        .list()
        .where((f) => f is File && f.path.endsWith(extension))
        .cast<File>()
        .toList();

    final records = <BackupRecord>[];
    for (final file in files) {
      final fileName = file.path.split(Platform.pathSeparator).last;
      final timestamp = fileName.substring(0, fileName.length - extension.length);
      final dateTime = _parseTimestamp(timestamp);
      final stat = await file.stat();
      records.add(BackupRecord(
        filePath: file.path,
        dateTime: dateTime,
        fileSize: stat.size,
      ));
    }

    // 降序排列（最新的在前）
    records.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return records;
  }

  /// 删除指定备份文件
  Future<bool> deleteBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        debugPrint('已删除备份: $filePath');

        // 删除后清理可能产生的空目录
        await _cleanupEmptyAncestors(file.parent);

        return true;
      }
      return false;
    } catch (e) {
      debugPrint('删除备份失败: $e');
      return false;
    }
  }

  /// 读取指定备份文件的内容
  ///
  /// 用于恢复历史版本
  Future<String?> readBackupContent(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (e) {
      debugPrint('读取备份内容失败: $e');
      return null;
    }
  }

  /// 删除指定书籍的全部备份目录
  ///
  /// 彻底删除书籍时调用，删除该书籍名下的所有备份数据
  Future<void> deleteBookBackups(String bookUuid) async {
    try {
      final backupPath = await AppPaths.instance.getBackupPath();
      final bookBackupDir = Directory('$backupPath${Platform.pathSeparator}$bookUuid');

      if (await bookBackupDir.exists()) {
        await bookBackupDir.delete(recursive: true);
        debugPrint('已删除书籍备份目录: $bookUuid');
      }
    } catch (e) {
      debugPrint('删除书籍备份目录失败: $e');
    }
  }

  /// 重命名章节备份目录
  ///
  /// 章节标题变更时调用，将旧名称的备份目录重命名为新名称
  Future<void> renameChapterBackupDir({
    required String bookUuid,
    required String oldChapterTitle,
    required String newChapterTitle,
    String volumeName = '',
  }) async {
    final backupPath = await AppPaths.instance.getBackupPath();
    final oldPath = _buildChapterBackupPath(backupPath, bookUuid, oldChapterTitle, volumeName);
    final newPath = _buildChapterBackupPath(backupPath, bookUuid, newChapterTitle, volumeName);
    await _renameBackupDir(oldPath, newPath, oldChapterTitle, newChapterTitle);
  }

  /// 重命名设定备份目录
  ///
  /// 设定标题变更时调用，将旧名称的备份目录重命名为新名称
  Future<void> renameSettingBackupDir({
    required String bookUuid,
    required String oldSettingTitle,
    required String newSettingTitle,
  }) async {
    final backupPath = await AppPaths.instance.getBackupPath();
    final oldPath = _buildSettingBackupPath(backupPath, bookUuid, oldSettingTitle);
    final newPath = _buildSettingBackupPath(backupPath, bookUuid, newSettingTitle);
    await _renameBackupDir(oldPath, newPath, oldSettingTitle, newSettingTitle);
  }

  /// 执行备份目录重命名的通用逻辑
  Future<void> _renameBackupDir(
    String oldPath,
    String newPath,
    String oldTitle,
    String newTitle,
  ) async {
    final oldDir = Directory(oldPath);
    if (!await oldDir.exists()) return;

    // 如果新路径已存在，不覆盖
    final newDir = Directory(newPath);
    if (await newDir.exists()) return;

    try {
      await oldDir.rename(newPath);
      debugPrint('已重命名备份目录: $oldTitle -> $newTitle');
    } catch (e) {
      debugPrint('重命名备份目录失败: $e');
    }
  }

  /// 删除指定设定的全部备份
  ///
  /// 设定被删除时调用，清理该设定名下的所有历史备份
  Future<void> deleteSettingBackups(String bookUuid, String settingTitle) async {
    try {
      final backupPath = await AppPaths.instance.getBackupPath();
      final settingDirPath = _buildSettingBackupPath(backupPath, bookUuid, settingTitle);
      final settingDir = Directory(settingDirPath);

      if (await settingDir.exists()) {
        await settingDir.delete(recursive: true);
        debugPrint('已删除设定备份目录: $settingTitle');
      }
    } catch (e) {
      debugPrint('删除设定备份目录失败: $e');
    }
  }

  /// 清空所有备份文件
  ///
  /// 删除备份根目录下所有书籍的章节和设定备份，操作不可恢复
  /// 返回被清理的备份文件数
  Future<int> clearAllBackups() async {
    try {
      final backupPath = await AppPaths.instance.getBackupPath();
      final backupDir = Directory(backupPath);
      if (!await backupDir.exists()) return 0;

      int deletedCount = 0;

      // 遍历备份目录下的所有书籍子目录
      await for (final bookDir in backupDir.list()) {
        if (bookDir is! Directory) continue;

        // 先统计该书籍目录下的备份文件数
        await for (final entity in bookDir.list(recursive: true)) {
          if (_isBackupFile(entity)) {
            deletedCount++;
          }
        }

        // 递归删除整个书籍备份目录
        await bookDir.delete(recursive: true);
      }

      debugPrint('已清空备份目录，删除 $deletedCount 个备份文件');
      return deletedCount;
    } catch (e) {
      debugPrint('清空备份文件失败: $e');
      return 0;
    }
  }

  // ================= 私有方法 =================

  /// 备份文件支持的所有扩展名
  ///
  /// 章节备份使用 .txt，设定项备份使用 .md
  static const List<String> _backupExtensions = [
    GlobalConstants.chapterFileExtension,
    GlobalConstants.settingFileExtension,
  ];

  /// 判断文件系统实体是否为备份文件
  ///
  /// 遍历书籍目录树时使用，同时识别章节备份（.txt）和设定项备份（.md）
  bool _isBackupFile(FileSystemEntity entity) {
    if (entity is! File) return false;
    return _backupExtensions.any((ext) => entity.path.endsWith(ext));
  }

  /// 根据标签页类型获取对应的备份文件扩展名
  ///
  /// 设定项使用 .md，章节使用 .txt
  String _backupExtensionFor(bool isSetting) {
    return isSetting
        ? GlobalConstants.settingFileExtension
        : GlobalConstants.chapterFileExtension;
  }

  /// 去除备份文件名中的扩展名，仅保留时间戳部分
  String _stripBackupExtension(String fileName) {
    for (final ext in _backupExtensions) {
      if (fileName.endsWith(ext)) {
        return fileName.substring(0, fileName.length - ext.length);
      }
    }
    return fileName;
  }

  /// 执行单次备份
  Future<void> _performBackup(String tabId, _TabBackupInfo info) async {
    if (_backingUpTabs.contains(tabId)) return;
    _backingUpTabs.add(tabId);

    try {
      final content = info.contentGetter();

      // 检查内容是否与上次备份相同
      if (_lastBackupContent[tabId] == content) return;

      // 首次备份时，从磁盘读取最近一次备份内容进行比对
      if (!_lastBackupContent.containsKey(tabId)) {
        final lastBackup = await _readLastBackupContent(info);
        if (lastBackup == content) {
          _lastBackupContent[tabId] = content;
          return;
        }
      }

      // 创建备份文件
      await _createBackupFile(info, content);

      // 更新缓存
      _lastBackupContent[tabId] = content;

      debugPrint('备份已创建: ${info.bookUuid}/${info.chapterTitle}');
    } catch (e) {
      debugPrint('备份失败: $e');
    } finally {
      _backingUpTabs.remove(tabId);
    }
  }

  /// 创建备份文件
  Future<void> _createBackupFile(_TabBackupInfo info, String content) async {
    final backupPath = await AppPaths.instance.getBackupPath();
    final dirPath = _buildBackupItemPath(backupPath, info);
    final dir = Directory(dirPath);

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final now = DateTime.now();
    final timestamp = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';

    final extension = _backupExtensionFor(info.isSetting);
    final file = File('$dirPath${Platform.pathSeparator}$timestamp$extension');
    await file.writeAsString(content);
  }

  /// 读取指定标签页最近一次备份的内容
  ///
  /// 返回 null 表示没有任何备份
  Future<String?> _readLastBackupContent(_TabBackupInfo info) async {
    try {
      final backupPath = await AppPaths.instance.getBackupPath();
      final dirPath = _buildBackupItemPath(backupPath, info);
      final dir = Directory(dirPath);

      if (!await dir.exists()) return null;

      final extension = _backupExtensionFor(info.isSetting);
      final files = await dir
          .list()
          .where((f) => f is File && f.path.endsWith(extension))
          .cast<File>()
          .toList();

      if (files.isEmpty) return null;

      // 文件名即时间戳，降序排列取最新
      files.sort((a, b) => b.path.compareTo(a.path));

      return await files.first.readAsString();
    } catch (e) {
      debugPrint('读取最近备份失败: $e');
      return null;
    }
  }

  /// 清理过期的备份文件
  ///
  /// 遍历所有备份目录，删除超过保存天数的备份
  /// 如果保存天数设置为 0（永久保留），则不执行清理
  /// 应在应用启动时异步调用，不影响 UI
  Future<void> cleanupExpiredBackups() async {
    final retentionDays = SettingsService.instance.historyRetentionDays;

    // 永久保留，不清理
    if (retentionDays == 0) return;

    final backupPath = await AppPaths.instance.getBackupPath();
    final backupDir = Directory(backupPath);

    if (!await backupDir.exists()) return;

    final cutoffDate = DateTime.now().subtract(Duration(days: retentionDays));
    int deletedCount = 0;

    // 遍历所有书籍目录
    await for (final bookEntity in backupDir.list()) {
      if (bookEntity is! Directory) continue;

      // 遍历书籍下所有备份文件
      await for (final entity in bookEntity.list(recursive: true)) {
        if (_isBackupFile(entity)) {
          final fileName = _stripBackupExtension(entity.path.split(Platform.pathSeparator).last);
          final dateTime = _parseTimestamp(fileName);

          if (dateTime.isBefore(cutoffDate)) {
            try {
              await entity.delete();
              deletedCount++;
            } catch (e) {
              debugPrint('删除过期备份失败: $e');
            }
          }
        }
      }

      // 清理空文件夹（章节目录、分卷目录等）
      await _cleanupEmptyDirectories(bookEntity);
    }

    if (deletedCount > 0) {
      debugPrint('已清理 $deletedCount 个过期备份（保留 $retentionDays 天）');
    }
  }

  /// 递归清理空目录
  ///
  /// 从最深层开始向上检查，删除不包含任何文件的空目录
  /// 例如：章节目录空了就删除章节目录，分卷目录空了就删除分卷目录
  Future<void> _cleanupEmptyDirectories(Directory dir) async {
    if (!await dir.exists()) return;

    // 先递归处理子目录
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        await _cleanupEmptyDirectories(entity);
      }
    }

    // 检查当前目录是否为空
    try {
      final hasContent = await dir.list().isEmpty;
      if (hasContent) {
        await dir.delete();
        debugPrint('已删除空目录: ${dir.path}');
      }
    } catch (e) {
      debugPrint('删除空目录失败: $e');
    }
  }

  /// 从指定目录向上逐级清理空目录
  ///
  /// 删除单个备份文件后使用，从文件所在目录开始向上检查
  /// 不会超出备份根目录的范围
  Future<void> _cleanupEmptyAncestors(Directory dir) async {
    final backupPath = await AppPaths.instance.getBackupPath();
    final backupDir = Directory(backupPath);

    if (!await dir.exists()) return;

    Directory current = dir;
    while (await current.exists()) {
      // 不超出备份根目录
      if (current.path == backupDir.path) break;

      try {
        final hasContent = await current.list().isEmpty;
        if (hasContent) {
          final parent = current.parent;
          await current.delete();
          debugPrint('已删除空目录: ${current.path}');
          current = parent;
        } else {
          break;
        }
      } catch (e) {
        debugPrint('删除空目录失败: $e');
        break;
      }
    }
  }

  /// 构建章节备份目录路径
  ///
  /// 有分卷时：backups/{bookUuid}/chapters/{volumeName}/{chapterTitle}/
  /// 无分卷时：backups/{bookUuid}/chapters/{chapterTitle}/
  String _buildChapterBackupPath(String backupPath, String bookUuid, String chapterTitle, String volumeName) {
    final sanitizedChapter = _sanitizeFileName(chapterTitle);

    if (volumeName.isNotEmpty) {
      final sanitizedVolume = _sanitizeFileName(volumeName);
      return '$backupPath${Platform.pathSeparator}$bookUuid${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedVolume${Platform.pathSeparator}$sanitizedChapter';
    }

    return '$backupPath${Platform.pathSeparator}$bookUuid${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedChapter';
  }

  /// 构建设定备份目录路径
  ///
  /// 路径格式：backups/{bookUuid}/settings/{settingTitle}/
  String _buildSettingBackupPath(String backupPath, String bookUuid, String settingTitle) {
    final sanitizedSetting = _sanitizeFileName(settingTitle);
    return '$backupPath${Platform.pathSeparator}$bookUuid${Platform.pathSeparator}settings${Platform.pathSeparator}$sanitizedSetting';
  }

  /// 根据备份信息构建对应的备份目录路径
  ///
  /// 设定类型使用 settings/ 目录，章节类型使用 chapters/ 目录
  String _buildBackupItemPath(String backupPath, _TabBackupInfo info) {
    if (info.isSetting) {
      return _buildSettingBackupPath(backupPath, info.bookUuid, info.chapterTitle);
    }
    return _buildChapterBackupPath(backupPath, info.bookUuid, info.chapterTitle, info.volumeName);
  }

  /// 清理文件名中的非法字符
  String _sanitizeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  /// 将时间戳文件名解析为 DateTime
  ///
  /// 文件名格式：20260517_143025
  DateTime _parseTimestamp(String timestamp) {
    try {
      final year = int.parse(timestamp.substring(0, 4));
      final month = int.parse(timestamp.substring(4, 6));
      final day = int.parse(timestamp.substring(6, 8));
      final hour = int.parse(timestamp.substring(9, 11));
      final minute = int.parse(timestamp.substring(11, 13));
      final second = int.parse(timestamp.substring(13, 15));
      return DateTime(year, month, day, hour, minute, second);
    } catch (e) {
      return DateTime.now();
    }
  }
}
