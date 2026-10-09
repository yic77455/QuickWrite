part of '../workspace_provider.dart';

/// 目录列表域 Mixin
///
/// 管理左侧边栏的章节、分卷、设定分组、设定项数据状态与 CRUD 操作，
/// 以及章节/设定项文件的读写。通过 [WorkspaceStateBase] 的协调接口
/// 与 [EditorMixin]（Phase 4 引入）交互，如删除数据时关闭对应标签页。
mixin BookDataMixin on WorkspaceStateBase {
  // ================= 书籍数据 =================

  /// 当前书籍
  BookModel? _currentBook;

  /// 当前书籍的章节列表
  List<ChapterModel> _chapters = [];

  /// 当前书籍的分卷列表
  List<VolumeModel> _volumes = [];

  /// 当前书籍的设定分组列表
  List<SettingGroupModel> _settingGroups = [];

  /// 当前书籍的设定项列表
  List<SettingItemModel> _settingItems = [];

  /// 获取当前书籍
  BookModel? get currentBook => _currentBook;

  /// 获取当前书籍标题
  String get bookTitle => _currentBook?.title ?? '未知书籍';

  /// 获取章节列表
  List<ChapterModel> get chapters => List.unmodifiable(_chapters);

  /// 获取分卷列表（按 orderIndex 排序）
  List<VolumeModel> get volumes => List.unmodifiable(_volumes);

  /// 获取设定分组列表（按 orderIndex 排序）
  List<SettingGroupModel> get settingGroups => List.unmodifiable(_settingGroups);

  /// 获取设定项列表
  List<SettingItemModel> get settingItems => List.unmodifiable(_settingItems);

  // ================= 数据加载 =================

  /// 加载当前书籍的章节列表
  Future<void> _loadChapters() async {
    if (_currentBook == null) return;

    _chapters = await _isar.chapterModels
        .where()
        .bookUuidEqualTo(_currentBook!.uuid)
        .sortByOrderIndex()
        .findAll();
  }

  /// 加载当前书籍的分卷列表
  Future<void> _loadVolumes() async {
    if (_currentBook == null) return;

    _volumes = await _isar.volumeModels
        .where()
        .bookUuidEqualTo(_currentBook!.uuid)
        .sortByOrderIndex()
        .findAll();
  }

  /// 加载当前书籍的设定分组列表
  Future<void> _loadSettingGroups() async {
    if (_currentBook == null) return;

    _settingGroups = await _isar.settingGroupModels
        .where()
        .bookUuidEqualTo(_currentBook!.uuid)
        .sortByOrderIndex()
        .findAll();
  }

  /// 加载当前书籍的设定项列表
  Future<void> _loadSettingItems() async {
    if (_currentBook == null) return;

    _settingItems = await _isar.settingItemModels
        .where()
        .bookUuidEqualTo(_currentBook!.uuid)
        .sortByOrderIndex()
        .findAll();
  }

  // ================= 路径辅助 =================

  /// 获取书籍文件夹路径
  String get bookFolderPath {
    if (_currentBook == null) return '';
    return _bookFolderService.bookFolderPath(_currentBook!);
  }

  /// 获取章节文件的完整路径
  String getChapterFilePath(ChapterModel chapter) {
    if (_currentBook == null) return '';
    return _bookFolderService.chapterFilePath(_currentBook!, chapter);
  }

  /// 获取设定项文件的完整路径
  String getSettingItemFilePath(SettingItemModel item) {
    if (_currentBook == null) return '';
    return _bookFolderService.settingItemFilePath(_currentBook!, item);
  }

  /// 获取标签页对应的文件路径
  ///
  /// 仅章节类型和备份预览类型返回有效路径，其他类型返回 null
  String? getTabFilePath(EditorTab tab) {
    switch (tab.type) {
      case EditorTabType.chapter:
        try {
          final chapter = _chapters.firstWhere((c) => c.uuid == tab.id);
          return getChapterFilePath(chapter);
        } catch (_) {
          return null;
        }
      case EditorTabType.settings:
        try {
          final item = _settingItems.firstWhere((i) => i.uuid == tab.id);
          return getSettingItemFilePath(item);
        } catch (_) {
          return null;
        }
      case EditorTabType.backupPreview:
        return tab.backupFilePath;
    }
  }

  // ================= 章节文件读写 =================

  /// 读取章节文件内容
  @override
  Future<String> readChapterContent(ChapterModel chapter) async {
    try {
      final filePath = getChapterFilePath(chapter);
      final file = File(filePath);

      if (!await file.exists()) {
        debugPrint('章节文件不存在: $filePath');
        return '';
      }

      return await file.readAsString();
    } catch (e) {
      debugPrint('读取章节文件失败: $e');
      return '';
    }
  }

  /// 保存章节内容到文件
  /// [chapter] 章节模型
  /// [content] 章节内容
  /// 返回是否保存成功
  @override
  Future<bool> saveChapterContent(ChapterModel chapter, String content) async {
    try {
      final filePath = getChapterFilePath(chapter);
      final file = File(filePath);

      // 确保父目录存在
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      // 写入文件
      await file.writeAsString(content);

      // 计算字数
      final wordCount = WordCountUtils.countWords(content);

      // 更新数据库中的字数和修改时间
      chapter.wordCount = wordCount;
      chapter.updatedAt = DateTime.now();

      await _isar.writeTxn(() async {
        await _isar.chapterModels.put(chapter);

        // 更新书籍总字数
        if (_currentBook != null) {
          // 计算所有章节的总字数
          final allChapters = await _isar.chapterModels
              .where()
              .bookUuidEqualTo(_currentBook!.uuid)
              .findAll();
          final totalWordCount = allChapters.fold<int>(
            0,
            (sum, c) => sum + c.wordCount,
          );

          _currentBook!.wordCount = totalWordCount;
          _currentBook!.updatedAt = DateTime.now();
          await _isar.bookModels.put(_currentBook!);
        }
      });

      // 刷新章节列表
      await _loadChapters();

      // 通知刷新书架（更新最近编辑显示）
      _notifyBookshelfRefresh();

      debugPrint('章节保存成功: ${chapter.title}, 字数: $wordCount');

      // 保存当前章节的光标位置到缓存（用于下次打开时恢复）
      await saveChapterCursorPositionIfAny(chapter.uuid);

      return true;
    } catch (e) {
      debugPrint('保存章节文件失败: $e');
      return false;
    }
  }

  // ================= 章节 CRUD =================

  /// 清理文件名中的非法字符
  String _sanitizeFileName(String fileName) {
    // 移除 Windows 文件名中不允许的字符: \ / : * ? " < > |
    return fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  /// 更新章节标题
  /// 返回是否更新成功
  Future<bool> _updateChapterTitle(ChapterModel chapter, String newTitle) async {
    // 检查章节标题是否发生了变化
    if (chapter.title == newTitle) return true;

    // 保存旧的文件路径
    final oldFilePath = getChapterFilePath(chapter);

    // 保存旧标题用于重命名备份目录
    final oldTitle = chapter.title;

    // 更新章节标题
    chapter.title = newTitle;
    chapter.updatedAt = DateTime.now();

    // 生成新的文件路径
    String newRelativePath;
    final volumeName = getVolumeName(chapter.volumeUuid);
    if (volumeName.isNotEmpty) {
      newRelativePath = '${_sanitizeFileName(volumeName)}${Platform.pathSeparator}${_sanitizeFileName(chapter.title)}${GlobalConstants.chapterFileExtension}';
    } else {
      newRelativePath = '${_sanitizeFileName(chapter.title)}${GlobalConstants.chapterFileExtension}';
    }
    chapter.filePath = newRelativePath;

    // 生成新的完整文件路径
    final newFilePath = getChapterFilePath(chapter);

    // 重命名文件
    try {
      final oldFile = File(oldFilePath);
      if (await oldFile.exists()) {
        final newFile = File(newFilePath);
        // 确保新文件的父目录存在
        final parentDir = newFile.parent;
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }
        // 重命名文件
        await oldFile.rename(newFilePath);
      }
    } catch (e) {
      debugPrint('重命名章节文件失败: $e');
      return false;
    }

    // 重命名备份目录
    if (_currentBook != null) {
      await BackupService.instance.renameChapterBackupDir(
        bookUuid: _currentBook!.uuid,
        oldChapterTitle: oldTitle,
        newChapterTitle: newTitle,
        volumeName: getVolumeName(chapter.volumeUuid),
      );
    }

    // 更新备份计时器中的章节标题
    BackupService.instance.updateTabBackupInfo(
      tabId: chapter.uuid,
      chapterTitle: newTitle,
    );

    // 更新数据库中的章节标题和文件路径
    await _isar.writeTxn(() async {
      await _isar.chapterModels.put(chapter);
    });

    // 刷新章节列表
    await _loadChapters();

    return true;
  }

  /// 新建章节
  /// [title] 章节标题
  /// [volumeUuid] 分卷 UUID，空字符串表示无分卷
  /// 返回新建的章节模型，失败返回 null
  Future<ChapterModel?> addChapter({
    required String title,
    String volumeUuid = '',
  }) async {
    if (_currentBook == null) return null;

    // 检查同一分卷下是否已存在同名章节
    final existing = _chapters.where(
      (c) => c.title == title && c.volumeUuid == volumeUuid,
    );
    if (existing.isNotEmpty) return null;

    // 计算排序序号
    final globalMaxOrder = _chapters.fold<int>(0, (max, c) => c.orderIndex > max ? c.orderIndex : max);
    final volumeChapters = _chapters.where((c) => c.volumeUuid == volumeUuid).toList();
    final volumeMaxOrder = volumeChapters.fold<int>(0, (max, c) => c.volumeOrderIndex > max ? c.volumeOrderIndex : max);

    // 生成文件路径
    String filePath;
    final volumeName = getVolumeName(volumeUuid);
    if (volumeName.isNotEmpty) {
      filePath = '${_sanitizeFileName(volumeName)}${Platform.pathSeparator}${_sanitizeFileName(title)}${GlobalConstants.chapterFileExtension}';
    } else {
      filePath = '${_sanitizeFileName(title)}${GlobalConstants.chapterFileExtension}';
    }

    // 创建章节模型
    final chapter = ChapterModel()
      ..uuid = const Uuid().v4()
      ..bookUuid = _currentBook!.uuid
      ..title = title
      ..volumeUuid = volumeUuid
      ..orderIndex = globalMaxOrder + 1
      ..volumeOrderIndex = volumeMaxOrder + 1
      ..wordCount = 0
      ..filePath = filePath
      ..createdAt = DateTime.now()
      ..updatedAt = DateTime.now();

    // 创建章节文件
    try {
      final fullPath = getChapterFilePath(chapter);
      final file = File(fullPath);
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      // 根据首行缩进设置写入初始内容
      final initialContent = SettingsService.instance.isFirstLineIndentEnabled ? '\u{3000}\u{3000}' : '';
      await file.writeAsString(initialContent);
    } catch (e) {
      debugPrint('创建章节文件失败: $e');
      return null;
    }

    // 写入数据库
    await _isar.writeTxn(() async {
      await _isar.chapterModels.put(chapter);

      // 更新书籍修改时间
      if (_currentBook != null) {
        _currentBook!.updatedAt = DateTime.now();
        await _isar.bookModels.put(_currentBook!);
      }
    });

    // 刷新章节列表
    await _loadChapters();

    // 通知刷新书架（更新最近编辑显示）
    _notifyBookshelfRefresh();

    notifyListeners();

    return chapter;
  }

  /// 重命名章节
  /// [chapterUuid] 章节UUID
  /// [newTitle] 新标题
  /// 返回是否重命名成功
  Future<bool> renameChapter({
    required String chapterUuid,
    required String newTitle,
  }) async {
    final chapter = _chapters.where((c) => c.uuid == chapterUuid).firstOrNull;
    if (chapter == null) return false;

    // 检查同一分卷下是否已存在同名章节
    final existing = _chapters.where(
      (c) => c.title == newTitle && c.volumeUuid == chapter.volumeUuid && c.uuid != chapterUuid,
    );
    if (existing.isNotEmpty) return false;

    final success = await _updateChapterTitle(chapter, newTitle);
    if (success) {
      // 同步更新已打开标签页的标题和标题输入框
      final tab = _openedTabs.where((t) => t.id == chapterUuid).firstOrNull;
      if (tab != null) {
        tab.title = newTitle;
        if (tab.chapterTitleController != null) {
          tab.chapterTitleController!.text = newTitle;
        }
        notifyListeners();
      }
    }
    return success;
  }

  /// 删除章节
  /// [chapterUuid] 章节UUID
  /// 返回是否删除成功
  Future<bool> deleteChapter({required String chapterUuid}) async {
    if (_currentBook == null) return false;

    final chapter = _chapters.where((c) => c.uuid == chapterUuid).firstOrNull;
    if (chapter == null) return false;

    // 关闭该章节的标签页（如果已打开）
    final tabIndex = _openedTabs.indexWhere((t) => t.id == chapterUuid);
    if (tabIndex != -1) {
      closeTab(chapterUuid);
    }

    // 将章节移入回收站
    final volumeName = getVolumeName(chapter.volumeUuid);
    await RecycleItemService.instance.moveChapterToRecycleBin(
      chapter: chapter,
      bookTitle: _currentBook!.title,
      volumeName: volumeName,
      chapterFilePath: getChapterFilePath(chapter),
    );

    // 删除章节备份目录
    try {
      final backupPath = await AppPaths.instance.getBackupPath();
      final sanitizedChapter = _sanitizeFileName(chapter.title);
      String chapterBackupPath;
      if (volumeName.isNotEmpty) {
        final sanitizedVolume = _sanitizeFileName(volumeName);
        chapterBackupPath = '$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedVolume${Platform.pathSeparator}$sanitizedChapter';
      } else {
        chapterBackupPath = '$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedChapter';
      }
      final backupDir = Directory(chapterBackupPath);
      if (await backupDir.exists()) {
        await backupDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('删除章节备份目录失败: $e');
    }

    // 从数据库中删除章节记录
    await _isar.writeTxn(() async {
      await _isar.chapterModels.delete(chapter.id);

      // 更新书籍总字数
      final allChapters = await _isar.chapterModels
          .where()
          .bookUuidEqualTo(_currentBook!.uuid)
          .findAll();
      final totalWordCount = allChapters.fold<int>(0, (sum, c) => sum + c.wordCount);
      _currentBook!.wordCount = totalWordCount;
      _currentBook!.updatedAt = DateTime.now();
      await _isar.bookModels.put(_currentBook!);
    });

    // 刷新章节列表
    await _loadChapters();

    // 清理章节光标位置缓存
    await ChapterCursorCacheService.instance.removeChapter(
      bookUuid: _currentBook!.uuid,
      chapterUuid: chapterUuid,
    );

    notifyListeners();
    // 同步书架最近编辑与字数显示
    _notifyBookshelfRefresh();

    return true;
  }

  /// 批量删除章节
  /// [chapterUuids] 要删除的章节UUID列表
  /// 返回成功删除的数量
  Future<int> batchDeleteChapters({required List<String> chapterUuids}) async {
    if (_currentBook == null || chapterUuids.isEmpty) return 0;

    // 取出待删除的章节对象
    final chaptersToDelete = _chapters
        .where((c) => chapterUuids.contains(c.uuid))
        .toList();
    if (chaptersToDelete.isEmpty) return 0;

    // 集中关闭已打开的章节标签页
    for (final chapter in chaptersToDelete) {
      if (_openedTabs.any((t) => t.id == chapter.uuid)) {
        closeTab(chapter.uuid);
      }
    }

    // 批量将章节移入回收站
    await RecycleItemService.instance.moveChaptersToRecycleBinBatch(
      chapters: chaptersToDelete,
      bookTitle: _currentBook!.title,
      bookFolderPath: bookFolderPath,
      volumeNameOf: getVolumeName,
    );

    // 集中删除章节备份目录
    final backupPath = await AppPaths.instance.getBackupPath();
    for (final chapter in chaptersToDelete) {
      try {
        final sanitizedChapter = _sanitizeFileName(chapter.title);
        final volumeName = getVolumeName(chapter.volumeUuid);
        String chapterBackupPath;
        if (volumeName.isNotEmpty) {
          final sanitizedVolume = _sanitizeFileName(volumeName);
          chapterBackupPath = '$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedVolume${Platform.pathSeparator}$sanitizedChapter';
        } else {
          chapterBackupPath = '$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedChapter';
        }
        final backupDir = Directory(chapterBackupPath);
        if (await backupDir.exists()) {
          await backupDir.delete(recursive: true);
        }
      } catch (e) {
        debugPrint('删除章节备份目录失败: $e');
      }
    }

    // 删除所有章节记录、重算总字数、更新书籍
    await _isar.writeTxn(() async {
      for (final chapter in chaptersToDelete) {
        await _isar.chapterModels.delete(chapter.id);
      }

      // 重新查询剩余章节并累计总字数
      final remainingChapters = await _isar.chapterModels
          .where()
          .bookUuidEqualTo(_currentBook!.uuid)
          .findAll();
      final totalWordCount = remainingChapters.fold<int>(
        0,
        (sum, c) => sum + c.wordCount,
      );
      _currentBook!.wordCount = totalWordCount;
      _currentBook!.updatedAt = DateTime.now();
      await _isar.bookModels.put(_currentBook!);
    });

    // 刷新章节列表
    await _loadChapters();

    // 集中清理章节光标位置缓存
    for (final chapter in chaptersToDelete) {
      await ChapterCursorCacheService.instance.removeChapter(
        bookUuid: _currentBook!.uuid,
        chapterUuid: chapter.uuid,
      );
    }

    // 通知 UI 刷新并同步书架最近编辑/字数
    notifyListeners();
    _notifyBookshelfRefresh();

    return chaptersToDelete.length;
  }

  /// 批量移动章节到指定分卷
  /// [chapterUuids] 要移动的章节UUID列表
  /// [targetVolumeUuid] 目标分卷UUID，空字符串表示未分卷
  /// 返回成功移动的数量
  Future<int> batchMoveChaptersToVolume({
    required List<String> chapterUuids,
    required String targetVolumeUuid,
  }) async {
    if (_currentBook == null) return 0;

    final targetVolumeName = getVolumeName(targetVolumeUuid);

    // 收集可移动的章节（跳过目标分卷相同和目标分卷下重名的）
    final chaptersToMove = <ChapterModel>[];
    for (final chapterUuid in chapterUuids) {
      final chapter = _chapters.where((c) => c.uuid == chapterUuid).firstOrNull;
      if (chapter == null) continue;
      if (chapter.volumeUuid == targetVolumeUuid) continue;
      // 检查目标分卷下是否已存在同名章节
      final existing = _chapters.where(
        (c) => c.title == chapter.title && c.volumeUuid == targetVolumeUuid,
      );
      if (existing.isNotEmpty) continue;
      chaptersToMove.add(chapter);
    }

    if (chaptersToMove.isEmpty) return 0;

    // 按全局 orderIndex 排序，确保移动项在目标分卷中的相对顺序与原始顺序一致
    chaptersToMove.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    // 计算目标分卷内的起始排序序号
    final targetVolumeChapters = _chapters.where((c) => c.volumeUuid == targetVolumeUuid).toList();
    int nextVolumeOrderIndex = targetVolumeChapters.fold<int>(
      0, (max, c) => c.volumeOrderIndex > max ? c.volumeOrderIndex : max,
    ) + 1;

    final backupPath = await AppPaths.instance.getBackupPath();
    final bookUuid = _currentBook!.uuid;

    // 逐个移动文件和备份目录（文件系统操作无法批量）
    for (final chapter in chaptersToMove) {
      final oldVolumeName = getVolumeName(chapter.volumeUuid);
      final oldFilePath = getChapterFilePath(chapter);

      // 更新章节的分卷归属和排序
      chapter.volumeUuid = targetVolumeUuid;
      chapter.updatedAt = DateTime.now();
      chapter.volumeOrderIndex = nextVolumeOrderIndex++;

      // 生成新的文件相对路径
      final String newRelativePath = targetVolumeName.isNotEmpty
          ? '${_sanitizeFileName(targetVolumeName)}${Platform.pathSeparator}${_sanitizeFileName(chapter.title)}${GlobalConstants.chapterFileExtension}'
          : '${_sanitizeFileName(chapter.title)}${GlobalConstants.chapterFileExtension}';
      chapter.filePath = newRelativePath;

      // 移动章节文件
      try {
        final oldFile = File(oldFilePath);
        if (await oldFile.exists()) {
          final newFilePath = getChapterFilePath(chapter);
          final parentDir = Directory(newFilePath).parent;
          if (!await parentDir.exists()) {
            await parentDir.create(recursive: true);
          }
          await oldFile.rename(newFilePath);
        }
      } catch (e) {
        debugPrint('移动章节文件失败: $e');
      }

      // 移动备份目录
      try {
        final sanitizedChapter = _sanitizeFileName(chapter.title);
        String oldBackupPath;
        String newBackupPath;

        if (oldVolumeName.isNotEmpty) {
          final sanitizedVolume = _sanitizeFileName(oldVolumeName);
          oldBackupPath = '$backupPath${Platform.pathSeparator}$bookUuid${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedVolume${Platform.pathSeparator}$sanitizedChapter';
        } else {
          oldBackupPath = '$backupPath${Platform.pathSeparator}$bookUuid${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedChapter';
        }

        if (targetVolumeName.isNotEmpty) {
          final sanitizedVolume = _sanitizeFileName(targetVolumeName);
          newBackupPath = '$backupPath${Platform.pathSeparator}$bookUuid${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedVolume${Platform.pathSeparator}$sanitizedChapter';
        } else {
          newBackupPath = '$backupPath${Platform.pathSeparator}$bookUuid${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedChapter';
        }

        final oldBackupDir = Directory(oldBackupPath);
        if (await oldBackupDir.exists()) {
          final newBackupDir = Directory(newBackupPath);
          if (!await newBackupDir.exists()) {
            if (!await newBackupDir.parent.exists()) {
              await newBackupDir.parent.create(recursive: true);
            }
            await oldBackupDir.rename(newBackupPath);
          }
        }
      } catch (e) {
        debugPrint('移动章节备份目录失败: $e');
      }

      // 更新备份服务中的分卷信息
      BackupService.instance.updateTabBackupInfo(
        tabId: chapter.uuid,
        chapterTitle: chapter.title,
        volumeName: targetVolumeName,
      );
    }

    // 单事务批量更新所有章节记录和书籍修改时间
    await _isar.writeTxn(() async {
      await _isar.chapterModels.putAll(chaptersToMove);
      _currentBook!.updatedAt = DateTime.now();
      await _isar.bookModels.put(_currentBook!);
    });

    // 重建全局 orderIndex 并刷新章节列表
    await _rebuildGlobalOrderIndex();
    notifyListeners();

    return chaptersToMove.length;
  }

  /// 批量导出章节
  /// [chapterUuids] 要导出的章节UUID列表
  /// [outputDir] 导出目录路径
  /// 返回成功导出的数量
  Future<int> exportChapters({
    required List<String> chapterUuids,
    required String outputDir,
  }) async {
    if (_currentBook == null) return 0;

    int exportedCount = 0;

    // 确保输出目录存在
    final outputDirectory = Directory(outputDir);
    if (!await outputDirectory.exists()) {
      await outputDirectory.create(recursive: true);
    }

    for (final chapterUuid in chapterUuids) {
      final chapter = _chapters.where((c) => c.uuid == chapterUuid).firstOrNull;
      if (chapter == null) continue;

      try {
        // 读取章节内容
        final content = await readChapterContent(chapter);
        // 生成导出文件名（包含分卷名作为子目录）
        final volumeName = getVolumeName(chapter.volumeUuid);
        String exportFilePath;
        if (volumeName.isNotEmpty) {
          final volumeDir = Directory('$outputDir${Platform.pathSeparator}${_sanitizeFileName(volumeName)}');
          if (!await volumeDir.exists()) {
            await volumeDir.create(recursive: true);
          }
          exportFilePath = '$outputDir${Platform.pathSeparator}${_sanitizeFileName(volumeName)}${Platform.pathSeparator}${_sanitizeFileName(chapter.title)}.txt';
        } else {
          exportFilePath = '$outputDir${Platform.pathSeparator}${_sanitizeFileName(chapter.title)}.txt';
        }
        // 写入文件
        final exportFile = File(exportFilePath);
        await exportFile.writeAsString(content);
        exportedCount++;
      } catch (e) {
        debugPrint('导出章节失败: ${chapter.title}, 错误: $e');
      }
    }

    return exportedCount;
  }

  /// 移动章节到指定分卷
  /// [chapterUuid] 章节UUID
  /// [targetVolumeUuid] 目标分卷UUID，空字符串表示未分卷
  /// 返回是否移动成功
  Future<bool> moveChapterToVolume({
    required String chapterUuid,
    required String targetVolumeUuid,
  }) async {
    if (_currentBook == null) return false;

    final chapter = _chapters.where((c) => c.uuid == chapterUuid).firstOrNull;
    if (chapter == null) return false;

    // 目标分卷与当前分卷相同，无需移动
    if (chapter.volumeUuid == targetVolumeUuid) return false;

    // 检查目标分卷下是否已存在同名章节
    final existing = _chapters.where(
      (c) => c.title == chapter.title && c.volumeUuid == targetVolumeUuid && c.uuid != chapterUuid,
    );
    if (existing.isNotEmpty) return false;

    // 保存旧的文件路径
    final oldFilePath = getChapterFilePath(chapter);
    final oldVolumeName = getVolumeName(chapter.volumeUuid);
    final newVolumeName = getVolumeName(targetVolumeUuid);

    // 更新章节的分卷归属
    chapter.volumeUuid = targetVolumeUuid;
    chapter.updatedAt = DateTime.now();

    // 生成新的文件路径
    String newRelativePath;
    if (newVolumeName.isNotEmpty) {
      newRelativePath = '${_sanitizeFileName(newVolumeName)}${Platform.pathSeparator}${_sanitizeFileName(chapter.title)}${GlobalConstants.chapterFileExtension}';
    } else {
      newRelativePath = '${_sanitizeFileName(chapter.title)}${GlobalConstants.chapterFileExtension}';
    }
    chapter.filePath = newRelativePath;

    // 计算目标分卷内的排序序号
    final targetVolumeChapters = _chapters.where((c) => c.volumeUuid == targetVolumeUuid && c.uuid != chapterUuid).toList();
    final maxVolumeOrder = targetVolumeChapters.fold<int>(0, (max, c) => c.volumeOrderIndex > max ? c.volumeOrderIndex : max);
    chapter.volumeOrderIndex = maxVolumeOrder + 1;

    // 生成新的完整文件路径
    final newFilePath = getChapterFilePath(chapter);

    // 移动章节文件
    try {
      final oldFile = File(oldFilePath);
      if (await oldFile.exists()) {
        final newFile = File(newFilePath);
        // 确保目标目录存在
        final parentDir = newFile.parent;
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }
        await oldFile.rename(newFilePath);
      }
    } catch (e) {
      debugPrint('移动章节文件失败: $e');
      return false;
    }

    // 移动备份目录
    try {
      final backupPath = await AppPaths.instance.getBackupPath();
      final sanitizedChapter = _sanitizeFileName(chapter.title);

      String oldBackupPath;
      String newBackupPath;

      if (oldVolumeName.isNotEmpty) {
        final sanitizedVolume = _sanitizeFileName(oldVolumeName);
        oldBackupPath = '$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedVolume${Platform.pathSeparator}$sanitizedChapter';
      } else {
        oldBackupPath = '$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedChapter';
      }

      if (newVolumeName.isNotEmpty) {
        final sanitizedVolume = _sanitizeFileName(newVolumeName);
        newBackupPath = '$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedVolume${Platform.pathSeparator}$sanitizedChapter';
      } else {
        newBackupPath = '$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedChapter';
      }

      final oldBackupDir = Directory(oldBackupPath);
      if (await oldBackupDir.exists()) {
        final newBackupDir = Directory(newBackupPath);
        if (!await newBackupDir.exists()) {
          // 确保目标父目录存在
          if (!await newBackupDir.parent.exists()) {
            await newBackupDir.parent.create(recursive: true);
          }
          await oldBackupDir.rename(newBackupPath);
        }
      }
    } catch (e) {
      debugPrint('移动章节备份目录失败: $e');
    }

    // 更新备份服务中的分卷信息
    BackupService.instance.updateTabBackupInfo(
      tabId: chapter.uuid,
      chapterTitle: chapter.title,
      volumeName: newVolumeName,
    );

    // 更新数据库
    await _isar.writeTxn(() async {
      await _isar.chapterModels.put(chapter);
    });

    // 重建全局 orderIndex 并刷新章节列表
    await _rebuildGlobalOrderIndex();

    notifyListeners();
    return true;
  }

  // ================= 分卷辅助 =================

  /// 根据分卷 UUID 获取分卷名称
  String getVolumeName(String volumeUuid) {
    if (volumeUuid.isEmpty) return '';
    final volume = _volumes.where((v) => v.uuid == volumeUuid).firstOrNull;
    return volume?.name ?? '';
  }

  /// 根据分卷名称获取分卷 UUID
  String getVolumeUuid(String volumeName) {
    if (volumeName.isEmpty) return '';
    final volume = _volumes.where((v) => v.name == volumeName).firstOrNull;
    return volume?.uuid ?? '';
  }

  // ================= 分卷 CRUD =================

  /// 新建分卷
  /// [volumeName] 分卷名称
  /// 返回新建分卷的 UUID，失败返回 null
  Future<String?> addVolume({required String volumeName}) async {
    if (_currentBook == null) return null;
    if (volumeName.trim().isEmpty) return null;

    // 检查是否已存在同名分卷
    if (_volumes.any((v) => v.name == volumeName)) return null;

    // 计算排序序号
    final maxOrder = _volumes.fold<int>(0, (max, v) => v.orderIndex > max ? v.orderIndex : max);

    // 创建分卷模型
    final volume = VolumeModel()
      ..uuid = const Uuid().v4()
      ..bookUuid = _currentBook!.uuid
      ..name = volumeName
      ..orderIndex = maxOrder + 1
      ..createdAt = DateTime.now()
      ..updatedAt = DateTime.now();

    // 创建分卷目录
    final chaptersDir = '$bookFolderPath${Platform.pathSeparator}chapters';
    final volumeDir = Directory('$chaptersDir${Platform.pathSeparator}${_sanitizeFileName(volumeName)}');
    try {
      if (!await volumeDir.exists()) {
        await volumeDir.create(recursive: true);
      }
    } catch (e) {
      debugPrint('创建分卷目录失败: $e');
      return null;
    }

    // 写入数据库
    await _isar.writeTxn(() async {
      await _isar.volumeModels.put(volume);
    });

    // 刷新分卷列表
    await _loadVolumes();

    notifyListeners();
    return volume.uuid;
  }

  /// 调整同一分卷内章节的顺序
  /// [volumeUuid] 分卷 UUID
  /// [oldIndex] 原索引
  /// [newIndex] 新索引
  Future<void> reorderChaptersInVolume(String volumeUuid, int oldIndex, int newIndex) async {
    if (_currentBook == null) return;

    // 获取该分卷下的所有章节，并按现有的 volumeOrderIndex 排序
    final volumeChapters = _chapters
        .where((c) => c.volumeUuid == volumeUuid)
        .toList()
      ..sort((a, b) => a.volumeOrderIndex.compareTo(b.volumeOrderIndex));

    if (oldIndex < 0 || oldIndex >= volumeChapters.length) return;
    if (newIndex < 0 || newIndex > volumeChapters.length) return;

    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    if (oldIndex == newIndex) return;

    final chapter = volumeChapters.removeAt(oldIndex);
    volumeChapters.insert(newIndex, chapter);

    // 更新卷内序号
    for (int i = 0; i < volumeChapters.length; i++) {
      volumeChapters[i].volumeOrderIndex = i;
    }

    // 重建全局 orderIndex 并写入数据库
    await _rebuildGlobalOrderIndex();

    notifyListeners();
  }

  /// 重建所有章节的全局 orderIndex
  ///
  /// 按分卷顺序与卷内 volumeOrderIndex 重新分配全局 orderIndex，
  /// 确保 _chapters 按 orderIndex 排序时，各分卷内章节顺序与 volumeOrderIndex 一致。
  /// 同时将更新后的章节数据批量写入数据库。
  Future<void> _rebuildGlobalOrderIndex() async {
    // 按分卷分组（包含未分卷组）
    final groups = <String, List<ChapterModel>>{};
    for (final v in _volumes) {
      groups[v.uuid] = [];
    }
    groups[''] = [];

    for (final c in _chapters) {
      groups.putIfAbsent(c.volumeUuid, () => []).add(c);
    }

    // 卷内按 volumeOrderIndex 排序
    for (final list in groups.values) {
      list.sort((a, b) => a.volumeOrderIndex.compareTo(b.volumeOrderIndex));
    }

    // 按分卷顺序拼接（未分卷在前，各分卷按 orderIndex 排序）
    final newAllChapters = <ChapterModel>[];
    if (groups.containsKey('')) {
      newAllChapters.addAll(groups['']!);
    }
    for (final v in _volumes) {
      if (groups.containsKey(v.uuid)) {
        newAllChapters.addAll(groups[v.uuid]!);
      }
    }

    // 重新分配全局 orderIndex
    for (int i = 0; i < newAllChapters.length; i++) {
      newAllChapters[i].orderIndex = i;
    }

    _chapters = newAllChapters;

    // 立即通知 UI 更新，避免拖拽完成后因等待数据库写入而产生的闪烁
    notifyListeners();

    // 批量写入数据库
    await _isar.writeTxn(() async {
      await _isar.chapterModels.putAll(newAllChapters);
    });
  }

  /// 切换分卷展开/折叠状态
  /// [volumeUuid] 分卷 UUID
  Future<void> toggleVolumeExpanded({required String volumeUuid}) async {
    final volume = _volumes.where((v) => v.uuid == volumeUuid).firstOrNull;
    if (volume == null) return;

    volume.isExpanded = !volume.isExpanded;

    await _isar.writeTxn(() async {
      await _isar.volumeModels.put(volume);
    });

    notifyListeners();
  }

  /// 重命名分卷
  /// [volumeUuid] 分卷 UUID
  /// [newName] 新分卷名
  /// 返回是否重命名成功
  Future<bool> renameVolume({
    required String volumeUuid,
    required String newName,
  }) async {
    if (_currentBook == null) return false;
    if (newName.trim().isEmpty) return false;

    // 查找分卷
    final volume = _volumes.where((v) => v.uuid == volumeUuid).firstOrNull;
    if (volume == null) return false;
    if (volume.name == newName) return true;

    // 检查是否已存在同名分卷
    if (_volumes.any((v) => v.name == newName && v.uuid != volumeUuid)) return false;

    final oldName = volume.name;

    // 重命名分卷目录
    final chaptersDir = '$bookFolderPath${Platform.pathSeparator}chapters';
    final oldDir = Directory('$chaptersDir${Platform.pathSeparator}${_sanitizeFileName(oldName)}');
    final newDir = Directory('$chaptersDir${Platform.pathSeparator}${_sanitizeFileName(newName)}');

    try {
      if (await oldDir.exists()) {
        if (!await newDir.parent.exists()) {
          await newDir.parent.create(recursive: true);
        }
        await oldDir.rename(newDir.path);
      }
    } catch (e) {
      debugPrint('重命名分卷目录失败: $e');
      return false;
    }

    // 重命名备份目录
    final backupPath = await AppPaths.instance.getBackupPath();
    final oldBackupDir = Directory('$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}${_sanitizeFileName(oldName)}');
    final newBackupDir = Directory('$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}${_sanitizeFileName(newName)}');

    try {
      if (await oldBackupDir.exists()) {
        if (!await newBackupDir.exists()) {
          await oldBackupDir.rename(newBackupDir.path);
        }
      }
    } catch (e) {
      debugPrint('重命名分卷备份目录失败: $e');
    }

    // 获取该分卷下的所有章节
    final volumeChapters = _chapters.where((c) => c.volumeUuid == volumeUuid).toList();

    // 更新所有章节的 filePath（volumeUuid 不变，只需更新路径中的分卷名部分）
    for (final chapter in volumeChapters) {
      chapter.updatedAt = DateTime.now();
      chapter.filePath = '${_sanitizeFileName(newName)}${Platform.pathSeparator}${_sanitizeFileName(chapter.title)}${GlobalConstants.chapterFileExtension}';

      // 更新备份计时器中的分卷名
      BackupService.instance.updateTabBackupInfo(
        tabId: chapter.uuid,
        chapterTitle: chapter.title,
        volumeName: newName,
      );
    }

    // 更新分卷名称
    volume.name = newName;
    volume.updatedAt = DateTime.now();

    // 批量更新数据库
    await _isar.writeTxn(() async {
      await _isar.volumeModels.put(volume);
      for (final chapter in volumeChapters) {
        await _isar.chapterModels.put(chapter);
      }
    });

    // 刷新列表
    await _loadVolumes();
    await _loadChapters();

    // 更新已打开标签页中的分卷信息
    for (final tab in _openedTabs) {
      final chapter = volumeChapters.where((c) => c.uuid == tab.id).firstOrNull;
      if (chapter != null) {
        BackupService.instance.startTabBackupTimer(
          tabId: tab.id,
          bookUuid: _currentBook!.uuid,
          chapterTitle: tab.title,
          volumeName: newName,
          contentGetter: () => tab.textController?.text ?? '',
        );
      }
    }

    notifyListeners();
    return true;
  }

  /// 删除分卷
  /// [volumeUuid] 分卷 UUID
  /// 返回是否删除成功
  Future<bool> deleteVolume({required String volumeUuid}) async {
    if (_currentBook == null) return false;

    // 查找分卷
    final volume = _volumes.where((v) => v.uuid == volumeUuid).firstOrNull;
    if (volume == null) return false;

    final volumeName = volume.name;

    // 获取该分卷下的所有章节
    final volumeChapters = _chapters.where((c) => c.volumeUuid == volumeUuid).toList();

    if (volumeChapters.isNotEmpty) {
      // 集中关闭已打开的章节标签页
      for (final chapter in volumeChapters) {
        if (_openedTabs.any((t) => t.id == chapter.uuid)) {
          closeTab(chapter.uuid);
        }
      }

      // 批量将章节移入回收站
      await RecycleItemService.instance.moveChaptersToRecycleBinBatch(
        chapters: volumeChapters,
        bookTitle: _currentBook!.title,
        bookFolderPath: bookFolderPath,
        volumeNameOf: getVolumeName,
      );

      // 集中删除章节备份目录（同分卷下的章节共享分卷备份子目录）
      final backupPath = await AppPaths.instance.getBackupPath();
      final sanitizedVolume = _sanitizeFileName(volumeName);
      for (final chapter in volumeChapters) {
        try {
          final sanitizedChapter = _sanitizeFileName(chapter.title);
          final chapterBackupPath =
              '$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}$sanitizedVolume${Platform.pathSeparator}$sanitizedChapter';
          final backupDir = Directory(chapterBackupPath);
          if (await backupDir.exists()) {
            await backupDir.delete(recursive: true);
          }
        } catch (e) {
          debugPrint('删除章节备份目录失败: $e');
        }
      }

      // 删除所有章节记录、重算总字数、更新书籍
      await _isar.writeTxn(() async {
        for (final chapter in volumeChapters) {
          await _isar.chapterModels.delete(chapter.id);
        }

        // 重新查询剩余章节并累计总字数
        final remainingChapters = await _isar.chapterModels
            .where()
            .bookUuidEqualTo(_currentBook!.uuid)
            .findAll();
        final totalWordCount = remainingChapters.fold<int>(
          0,
          (sum, c) => sum + c.wordCount,
        );
        _currentBook!.wordCount = totalWordCount;
        _currentBook!.updatedAt = DateTime.now();
        await _isar.bookModels.put(_currentBook!);
      });

      // 集中清理章节光标位置缓存
      for (final chapter in volumeChapters) {
        await ChapterCursorCacheService.instance.removeChapter(
          bookUuid: _currentBook!.uuid,
          chapterUuid: chapter.uuid,
        );
      }
    }

    // 删除分卷目录（如果还有残留）
    final chaptersDir = '$bookFolderPath${Platform.pathSeparator}chapters';
    final volumeDir = Directory('$chaptersDir${Platform.pathSeparator}${_sanitizeFileName(volumeName)}');
    try {
      if (await volumeDir.exists()) {
        await volumeDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('删除分卷目录失败: $e');
    }

    // 删除分卷备份目录
    final backupPath = await AppPaths.instance.getBackupPath();
    final backupDir = Directory('$backupPath${Platform.pathSeparator}${_currentBook!.uuid}${Platform.pathSeparator}chapters${Platform.pathSeparator}${_sanitizeFileName(volumeName)}');
    try {
      if (await backupDir.exists()) {
        await backupDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('删除分卷备份目录失败: $e');
    }

    // 从数据库中删除分卷记录
    await _isar.writeTxn(() async {
      await _isar.volumeModels.delete(volume.id);
    });

    // 一次性刷新章节和分卷列表
    await _loadChapters();
    await _loadVolumes();

    // 通知 UI 刷新并同步书架最近编辑/字数
    notifyListeners();
    _notifyBookshelfRefresh();
    return true;
  }

  // ================= 设定数据操作 =================

  /// 根据分组 UUID 获取分组名称
  String getSettingGroupName(String groupUuid) {
    if (groupUuid.isEmpty) return '';
    final group = _settingGroups.where((g) => g.uuid == groupUuid).firstOrNull;
    return group?.name ?? '';
  }

  /// 读取设定项文件内容
  Future<String> readSettingItemContent(SettingItemModel item) async {
    try {
      final filePath = getSettingItemFilePath(item);
      final file = File(filePath);

      if (!await file.exists()) {
        debugPrint('设定项文件不存在: $filePath');
        return '';
      }

      return await file.readAsString();
    } catch (e) {
      debugPrint('读取设定项文件失败: $e');
      return '';
    }
  }

  /// 保存设定项内容到文件
  /// [item] 设定项模型
  /// [content] 设定项内容
  /// 返回是否保存成功
  Future<bool> saveSettingItemContent(SettingItemModel item, String content) async {
    try {
      final filePath = getSettingItemFilePath(item);
      final file = File(filePath);

      // 确保父目录存在
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      // 写入文件
      await file.writeAsString(content);

      // 计算字数
      final wordCount = WordCountUtils.countWords(content);

      // 更新数据库中的字数和修改时间
      item.wordCount = wordCount;
      item.updatedAt = DateTime.now();

      await _isar.writeTxn(() async {
        await _isar.settingItemModels.put(item);

        // 更新书籍修改时间
        if (_currentBook != null) {
          _currentBook!.updatedAt = DateTime.now();
          await _isar.bookModels.put(_currentBook!);
        }
      });

      // 刷新设定项列表
      await _loadSettingItems();

      // 通知刷新书架
      _notifyBookshelfRefresh();

      debugPrint('设定项保存成功: ${item.title}, 字数: $wordCount');
      return true;
    } catch (e) {
      debugPrint('保存设定项文件失败: $e');
      return false;
    }
  }

  /// 新建设定分组
  /// [name] 分组名称
  /// 返回新建的设定分组模型，失败返回 null
  Future<SettingGroupModel?> addSettingGroup({required String name}) async {
    if (_currentBook == null) return null;

    // 检查是否已存在同名分组
    if (_settingGroups.any((g) => g.name == name)) return null;

    // 计算排序序号
    final maxOrder = _settingGroups.fold<int>(0, (max, g) => g.orderIndex > max ? g.orderIndex : max);

    final group = SettingGroupModel()
      ..uuid = const Uuid().v4()
      ..bookUuid = _currentBook!.uuid
      ..name = name
      ..orderIndex = maxOrder + 1
      ..isExpanded = true
      ..createdAt = DateTime.now()
      ..updatedAt = DateTime.now();

    await _isar.writeTxn(() async {
      await _isar.settingGroupModels.put(group);

      // 更新书籍修改时间
      if (_currentBook != null) {
        _currentBook!.updatedAt = DateTime.now();
        await _isar.bookModels.put(_currentBook!);
      }
    });

    await _loadSettingGroups();
    notifyListeners();

    return group;
  }

  /// 新建设定项
  /// [title] 设定项标题
  /// [groupUuid] 分组 UUID，空字符串表示未分组
  /// 返回新建的设定项模型，失败返回 null
  Future<SettingItemModel?> addSettingItem({
    required String title,
    String groupUuid = '',
  }) async {
    if (_currentBook == null) return null;

    // 检查同一分组下是否已存在同名设定项
    final existing = _settingItems.where(
      (i) => i.title == title && i.groupUuid == groupUuid,
    );
    if (existing.isNotEmpty) return null;

    // 计算排序序号
    final globalMaxOrder = _settingItems.fold<int>(0, (max, i) => i.orderIndex > max ? i.orderIndex : max);
    final groupItems = _settingItems.where((i) => i.groupUuid == groupUuid).toList();
    final groupMaxOrder = groupItems.fold<int>(0, (max, i) => i.groupOrderIndex > max ? i.groupOrderIndex : max);

    // 生成文件路径
    String filePath;
    final groupName = getSettingGroupName(groupUuid);
    if (groupName.isNotEmpty) {
      filePath = '${_sanitizeFileName(groupName)}${Platform.pathSeparator}${_sanitizeFileName(title)}${GlobalConstants.settingFileExtension}';
    } else {
      filePath = '${_sanitizeFileName(title)}${GlobalConstants.settingFileExtension}';
    }

    final item = SettingItemModel()
      ..uuid = const Uuid().v4()
      ..bookUuid = _currentBook!.uuid
      ..title = title
      ..groupUuid = groupUuid
      ..orderIndex = globalMaxOrder + 1
      ..groupOrderIndex = groupMaxOrder + 1
      ..wordCount = 0
      ..filePath = filePath
      ..createdAt = DateTime.now()
      ..updatedAt = DateTime.now();

    // 创建设定项文件
    try {
      final fullPath = getSettingItemFilePath(item);
      final file = File(fullPath);
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      await file.writeAsString('');
    } catch (e) {
      debugPrint('创建设定项文件失败: $e');
      return null;
    }

    // 写入数据库
    await _isar.writeTxn(() async {
      await _isar.settingItemModels.put(item);

      // 更新书籍修改时间
      if (_currentBook != null) {
        _currentBook!.updatedAt = DateTime.now();
        await _isar.bookModels.put(_currentBook!);
      }
    });

    await _loadSettingItems();
    notifyListeners();

    return item;
  }

  /// 重命名设定分组
  /// [groupUuid] 分组 UUID
  /// [newName] 新分组名
  /// 返回是否重命名成功
  Future<bool> renameSettingGroup({
    required String groupUuid,
    required String newName,
  }) async {
    if (_currentBook == null) return false;
    if (newName.trim().isEmpty) return false;

    final group = _settingGroups.where((g) => g.uuid == groupUuid).firstOrNull;
    if (group == null) return false;
    if (group.name == newName) return true;

    // 检查是否已存在同名分组
    if (_settingGroups.any((g) => g.name == newName && g.uuid != groupUuid)) return false;

    final oldName = group.name;

    // 重命名分组目录
    final settingsDir = '$bookFolderPath${Platform.pathSeparator}settings';
    final oldDir = Directory('$settingsDir${Platform.pathSeparator}${_sanitizeFileName(oldName)}');
    final newDir = Directory('$settingsDir${Platform.pathSeparator}${_sanitizeFileName(newName)}');

    try {
      if (await oldDir.exists()) {
        if (!await newDir.parent.exists()) {
          await newDir.parent.create(recursive: true);
        }
        await oldDir.rename(newDir.path);
      }
    } catch (e) {
      debugPrint('重命名设定分组目录失败: $e');
      return false;
    }

    // 获取该分组下的所有设定项
    final groupItems = _settingItems.where((i) => i.groupUuid == groupUuid).toList();

    // 更新所有设定项的 filePath
    for (final item in groupItems) {
      item.updatedAt = DateTime.now();
      item.filePath = '${_sanitizeFileName(newName)}${Platform.pathSeparator}${_sanitizeFileName(item.title)}${GlobalConstants.settingFileExtension}';
    }

    // 更新分组名称
    group.name = newName;
    group.updatedAt = DateTime.now();

    // 批量更新数据库
    await _isar.writeTxn(() async {
      await _isar.settingGroupModels.put(group);
      for (final item in groupItems) {
        await _isar.settingItemModels.put(item);
      }
    });

    await _loadSettingGroups();
    await _loadSettingItems();

    notifyListeners();
    return true;
  }

  /// 重命名设定项
  /// [itemUuid] 设定项 UUID
  /// [newTitle] 新标题
  /// 返回是否重命名成功
  Future<bool> renameSettingItem({
    required String itemUuid,
    required String newTitle,
  }) async {
    if (_currentBook == null) return false;

    final item = _settingItems.where((i) => i.uuid == itemUuid).firstOrNull;
    if (item == null) return false;
    if (item.title == newTitle) return true;

    // 检查同一分组下是否已存在同名设定项
    if (_settingItems.any((i) => i.title == newTitle && i.groupUuid == item.groupUuid && i.uuid != itemUuid)) return false;

    // 保存旧标题和文件路径，用于后续重命名文件和备份目录
    final oldTitle = item.title;
    final oldFilePath = getSettingItemFilePath(item);

    // 更新标题
    item.title = newTitle;
    item.updatedAt = DateTime.now();

    // 生成新的文件路径
    final groupName = getSettingGroupName(item.groupUuid);
    if (groupName.isNotEmpty) {
      item.filePath = '${_sanitizeFileName(groupName)}${Platform.pathSeparator}${_sanitizeFileName(newTitle)}${GlobalConstants.settingFileExtension}';
    } else {
      item.filePath = '${_sanitizeFileName(newTitle)}${GlobalConstants.settingFileExtension}';
    }

    // 重命名文件
    final newFilePath = getSettingItemFilePath(item);
    try {
      final oldFile = File(oldFilePath);
      if (await oldFile.exists()) {
        final newFile = File(newFilePath);
        if (!await newFile.parent.exists()) {
          await newFile.parent.create(recursive: true);
        }
        await oldFile.rename(newFilePath);
      }
    } catch (e) {
      debugPrint('重命名设定项文件失败: $e');
      return false;
    }

    // 重命名备份目录（沿用标题变更后的新目录名）
    await BackupService.instance.renameSettingBackupDir(
      bookUuid: _currentBook!.uuid,
      oldSettingTitle: oldTitle,
      newSettingTitle: newTitle,
    );

    // 更新数据库
    await _isar.writeTxn(() async {
      await _isar.settingItemModels.put(item);

      if (_currentBook != null) {
        _currentBook!.updatedAt = DateTime.now();
        await _isar.bookModels.put(_currentBook!);
      }
    });

    await _loadSettingItems();

    // 更新已打开标签页的标题及备份计时器中的标题
    final tab = _openedTabs.where((t) => t.id == itemUuid).firstOrNull;
    if (tab != null) {
      tab.title = newTitle;
      BackupService.instance.updateTabBackupInfo(tabId: itemUuid, chapterTitle: newTitle);
    }

    notifyListeners();
    return true;
  }

  /// 删除设定分组
  /// [groupUuid] 分组 UUID
  /// 返回是否删除成功
  Future<bool> deleteSettingGroup({required String groupUuid}) async {
    if (_currentBook == null) return false;

    final group = _settingGroups.where((g) => g.uuid == groupUuid).firstOrNull;
    if (group == null) return false;

    final groupName = group.name;

    // 获取该分组下的所有设定项
    final groupItems = _settingItems.where((i) => i.groupUuid == groupUuid).toList();

    if (groupItems.isNotEmpty) {
      // 集中关闭已打开的设定项标签页
      for (final item in groupItems) {
        if (_openedTabs.any((t) => t.id == item.uuid)) {
          closeTab(item.uuid);
        }
      }

      // 批量将设定项移入回收站
      await RecycleItemService.instance.moveSettingItemsToRecycleBinBatch(
        items: groupItems,
        bookTitle: _currentBook!.title,
        bookFolderPath: bookFolderPath,
        groupNameOf: getSettingGroupName,
      );

      // 集中删除设定项备份目录
      for (final item in groupItems) {
        await BackupService.instance.deleteSettingBackups(
          _currentBook!.uuid,
          item.title,
        );
      }

      // 删除所有设定项记录、更新书籍修改时间
      await _isar.writeTxn(() async {
        for (final item in groupItems) {
          await _isar.settingItemModels.delete(item.id);
        }

        _currentBook!.updatedAt = DateTime.now();
        await _isar.bookModels.put(_currentBook!);
      });
    }

    // 删除分组目录
    final settingsDir = '$bookFolderPath${Platform.pathSeparator}settings';
    final groupDir = Directory('$settingsDir${Platform.pathSeparator}${_sanitizeFileName(groupName)}');
    try {
      if (await groupDir.exists()) {
        await groupDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('删除设定分组目录失败: $e');
    }

    // 从数据库中删除分组记录
    await _isar.writeTxn(() async {
      await _isar.settingGroupModels.delete(group.id);
    });

    // 一次性刷新设定项和分组列表
    await _loadSettingItems();
    await _loadSettingGroups();

    // 通知 UI 刷新并同步书架最近编辑/字数
    notifyListeners();
    _notifyBookshelfRefresh();
    return true;
  }

  /// 删除设定项
  /// [itemUuid] 设定项 UUID
  /// 返回是否删除成功
  Future<bool> deleteSettingItem({required String itemUuid}) async {
    if (_currentBook == null) return false;

    final item = _settingItems.where((i) => i.uuid == itemUuid).firstOrNull;
    if (item == null) return false;

    // 保存标题，用于后续删除对应的备份目录
    final itemTitle = item.title;

    // 关闭已打开的标签页
    final tab = _openedTabs.where((t) => t.id == itemUuid).firstOrNull;
    if (tab != null) {
      closeTab(itemUuid);
    }

    // 将设定项移入回收站
    final groupName = getSettingGroupName(item.groupUuid);
    await RecycleItemService.instance.moveSettingItemToRecycleBin(
      item: item,
      bookTitle: _currentBook!.title,
      groupName: groupName,
      itemFilePath: getSettingItemFilePath(item),
    );

    // 删除对应的设定备份目录
    await BackupService.instance.deleteSettingBackups(_currentBook!.uuid, itemTitle);

    // 从数据库中删除设定项记录
    await _isar.writeTxn(() async {
      await _isar.settingItemModels.delete(item.id);

      if (_currentBook != null) {
        _currentBook!.updatedAt = DateTime.now();
        await _isar.bookModels.put(_currentBook!);
      }
    });

    await _loadSettingItems();
    notifyListeners();
    // 同步书架最近编辑与字数显示
    _notifyBookshelfRefresh();
    return true;
  }

  /// 切换设定分组展开/折叠状态
  /// [groupUuid] 分组 UUID
  Future<void> toggleSettingGroupExpanded({required String groupUuid}) async {
    final group = _settingGroups.where((g) => g.uuid == groupUuid).firstOrNull;
    if (group == null) return;

    group.isExpanded = !group.isExpanded;

    await _isar.writeTxn(() async {
      await _isar.settingGroupModels.put(group);
    });

    notifyListeners();
  }

  /// 重新排序指定分组内的设定项
  /// [groupUuid] 分组 UUID，空字符串表示未分组
  /// [oldIndex] 原始位置
  /// [newIndex] 目标位置
  Future<void> reorderSettingItemsInGroup(String groupUuid, int oldIndex, int newIndex) async {
    if (_currentBook == null) return;

    // 获取该分组下的所有设定项，并按现有的 groupOrderIndex 排序
    final groupItems = _settingItems
        .where((i) => i.groupUuid == groupUuid)
        .toList()
      ..sort((a, b) => a.groupOrderIndex.compareTo(b.groupOrderIndex));

    if (oldIndex < 0 || oldIndex >= groupItems.length) return;
    if (newIndex < 0 || newIndex > groupItems.length) return;

    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    if (oldIndex == newIndex) return;

    final item = groupItems.removeAt(oldIndex);
    groupItems.insert(newIndex, item);

    // 更新所有的 groupOrderIndex
    for (int i = 0; i < groupItems.length; i++) {
      groupItems[i].groupOrderIndex = i;
    }

    // 重建全局 orderIndex 并写入数据库
    await _rebuildGlobalSettingOrderIndex();

    notifyListeners();
  }

  /// 重建所有设定项的全局 orderIndex
  ///
  /// 按分组顺序与组内 groupOrderIndex 重新分配全局 orderIndex，
  /// 确保 _settingItems 按 orderIndex 排序时，各分组内设定项顺序与 groupOrderIndex 一致。
  /// 同时将更新后的设定项数据批量写入数据库。
  Future<void> _rebuildGlobalSettingOrderIndex() async {
    // 按分组分组（包含未分组）
    final groups = <String, List<SettingItemModel>>{};
    for (final g in _settingGroups) {
      groups[g.uuid] = [];
    }
    groups[''] = [];

    for (final i in _settingItems) {
      groups.putIfAbsent(i.groupUuid, () => []).add(i);
    }

    // 组内按 groupOrderIndex 排序
    for (final list in groups.values) {
      list.sort((a, b) => a.groupOrderIndex.compareTo(b.groupOrderIndex));
    }

    // 按分组顺序拼接（未分组在前，各分组按 orderIndex 排序）
    final newAllItems = <SettingItemModel>[];
    if (groups.containsKey('')) {
      newAllItems.addAll(groups['']!);
    }
    for (final g in _settingGroups) {
      if (groups.containsKey(g.uuid)) {
        newAllItems.addAll(groups[g.uuid]!);
      }
    }

    // 重新分配全局 orderIndex
    for (int i = 0; i < newAllItems.length; i++) {
      newAllItems[i].orderIndex = i;
    }

    _settingItems = newAllItems;

    // 立即通知 UI 更新，避免拖拽完成后因等待数据库写入而产生的闪烁
    notifyListeners();

    // 批量写入数据库
    await _isar.writeTxn(() async {
      await _isar.settingItemModels.putAll(newAllItems);
    });
  }

  /// 移动设定项到指定分组
  /// [itemUuid] 设定项 UUID
  /// [targetGroupUuid] 目标分组 UUID，空字符串表示未分组
  /// 返回是否移动成功
  Future<bool> moveSettingItemToGroup({
    required String itemUuid,
    required String targetGroupUuid,
  }) async {
    if (_currentBook == null) return false;

    final item = _settingItems.where((i) => i.uuid == itemUuid).firstOrNull;
    if (item == null) return false;

    // 目标分组与当前分组相同，无需移动
    if (item.groupUuid == targetGroupUuid) return false;

    // 检查目标分组下是否已存在同名设定项
    final existing = _settingItems.where(
      (i) => i.title == item.title && i.groupUuid == targetGroupUuid && i.uuid != itemUuid,
    );
    if (existing.isNotEmpty) return false;

    // 保存旧的文件路径
    final oldFilePath = getSettingItemFilePath(item);
    final newGroupName = getSettingGroupName(targetGroupUuid);

    // 更新设定项的分组归属
    item.groupUuid = targetGroupUuid;
    item.updatedAt = DateTime.now();

    // 生成新的文件路径
    if (newGroupName.isNotEmpty) {
      item.filePath = '${_sanitizeFileName(newGroupName)}${Platform.pathSeparator}${_sanitizeFileName(item.title)}${GlobalConstants.settingFileExtension}';
    } else {
      item.filePath = '${_sanitizeFileName(item.title)}${GlobalConstants.settingFileExtension}';
    }

    // 重命名文件
    final newFilePath = getSettingItemFilePath(item);
    try {
      final oldFile = File(oldFilePath);
      if (await oldFile.exists()) {
        final newFile = File(newFilePath);
        if (!await newFile.parent.exists()) {
          await newFile.parent.create(recursive: true);
        }
        await oldFile.rename(newFilePath);
      }
    } catch (e) {
      debugPrint('移动设定项文件失败: $e');
      return false;
    }

    // 更新组内序号
    final targetGroupItems = _settingItems.where((i) => i.groupUuid == targetGroupUuid && i.uuid != itemUuid).toList();
    item.groupOrderIndex = targetGroupItems.length;

    // 更新数据库
    await _isar.writeTxn(() async {
      await _isar.settingItemModels.put(item);

      if (_currentBook != null) {
        _currentBook!.updatedAt = DateTime.now();
        await _isar.bookModels.put(_currentBook!);
      }
    });

    // 重建全局 orderIndex 并刷新设定项列表
    await _rebuildGlobalSettingOrderIndex();
    notifyListeners();
    return true;
  }

  /// 批量删除设定项
  /// [itemUuids] 要删除的设定项UUID列表
  /// 返回成功删除的数量
  Future<int> batchDeleteSettingItems({required List<String> itemUuids}) async {
    if (_currentBook == null || itemUuids.isEmpty) return 0;

    // 取出待删除的设定项对象
    final itemsToDelete = _settingItems
        .where((i) => itemUuids.contains(i.uuid))
        .toList();
    if (itemsToDelete.isEmpty) return 0;

    // 集中关闭已打开的设定项标签页
    for (final item in itemsToDelete) {
      if (_openedTabs.any((t) => t.id == item.uuid)) {
        closeTab(item.uuid);
      }
    }

    // 批量将设定项移入回收站
    await RecycleItemService.instance.moveSettingItemsToRecycleBinBatch(
      items: itemsToDelete,
      bookTitle: _currentBook!.title,
      bookFolderPath: bookFolderPath,
      groupNameOf: getSettingGroupName,
    );

    // 集中删除设定项备份目录
    for (final item in itemsToDelete) {
      await BackupService.instance.deleteSettingBackups(
        _currentBook!.uuid,
        item.title,
      );
    }

    // 删除所有设定项记录、更新书籍修改时间
    await _isar.writeTxn(() async {
      for (final item in itemsToDelete) {
        await _isar.settingItemModels.delete(item.id);
      }

      if (_currentBook != null) {
        _currentBook!.updatedAt = DateTime.now();
        await _isar.bookModels.put(_currentBook!);
      }
    });

    // 一次性刷新设定项列表
    await _loadSettingItems();

    // 通知 UI 刷新并同步书架最近编辑/字数
    notifyListeners();
    _notifyBookshelfRefresh();

    return itemsToDelete.length;
  }

  /// 批量移动设定项到指定分组
  /// [itemUuids] 要移动的设定项UUID列表
  /// [targetGroupUuid] 目标分组UUID，空字符串表示未分组
  /// 返回成功移动的数量
  Future<int> batchMoveSettingItemsToGroup({
    required List<String> itemUuids,
    required String targetGroupUuid,
  }) async {
    if (_currentBook == null) return 0;

    final targetGroupName = getSettingGroupName(targetGroupUuid);

    // 收集可移动的设定项（跳过目标分组相同和目标分组下重名的）
    final itemsToMove = <SettingItemModel>[];
    for (final itemUuid in itemUuids) {
      final item = _settingItems.where((i) => i.uuid == itemUuid).firstOrNull;
      if (item == null) continue;
      if (item.groupUuid == targetGroupUuid) continue;
      // 检查目标分组下是否已存在同名设定项
      final existing = _settingItems.where(
        (i) => i.title == item.title && i.groupUuid == targetGroupUuid,
      );
      if (existing.isNotEmpty) continue;
      itemsToMove.add(item);
    }

    if (itemsToMove.isEmpty) return 0;

    // 按全局 orderIndex 排序，确保移动项在目标分组中的相对顺序与原始顺序一致
    itemsToMove.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    // 计算目标分组内的起始排序序号
    final targetGroupItems = _settingItems.where((i) => i.groupUuid == targetGroupUuid).toList();
    int nextGroupOrderIndex = targetGroupItems.length;

    // 逐个移动文件（文件系统操作无法批量）
    for (final item in itemsToMove) {
      final oldFilePath = getSettingItemFilePath(item);

      // 更新设定项的分组归属和排序
      item.groupUuid = targetGroupUuid;
      item.updatedAt = DateTime.now();
      item.groupOrderIndex = nextGroupOrderIndex++;

      // 生成新的文件相对路径
      final String newRelativePath = targetGroupName.isNotEmpty
          ? '${_sanitizeFileName(targetGroupName)}${Platform.pathSeparator}${_sanitizeFileName(item.title)}${GlobalConstants.settingFileExtension}'
          : '${_sanitizeFileName(item.title)}${GlobalConstants.settingFileExtension}';
      item.filePath = newRelativePath;

      // 移动设定项文件
      try {
        final oldFile = File(oldFilePath);
        if (await oldFile.exists()) {
          final newFilePath = getSettingItemFilePath(item);
          final parentDir = Directory(newFilePath).parent;
          if (!await parentDir.exists()) {
            await parentDir.create(recursive: true);
          }
          await oldFile.rename(newFilePath);
        }
      } catch (e) {
        debugPrint('移动设定项文件失败: $e');
      }
    }

    // 单事务批量更新所有设定项记录和书籍修改时间
    await _isar.writeTxn(() async {
      await _isar.settingItemModels.putAll(itemsToMove);
      _currentBook!.updatedAt = DateTime.now();
      await _isar.bookModels.put(_currentBook!);
    });

    // 重建全局 orderIndex 并刷新设定项列表
    await _rebuildGlobalSettingOrderIndex();
    notifyListeners();

    return itemsToMove.length;
  }
}
