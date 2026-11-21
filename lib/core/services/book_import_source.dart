import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:quick_write/core/utils/android_native.dart';

/// 文件夹导入的数据来源
///
/// 桌面端拿到的是可直接读写的真实路径，安卓端只能通过系统文件选择器获得
/// content:// 授权。两种来源统一暴露「列目录 + 读字节」接口，
/// 上层的章节解析与写入逻辑无需关心数据究竟从哪里来。
abstract class ImportFolderSource {
  /// 文件夹名称（作为默认书名）
  String get folderName;

  /// 界面展示的位置说明
  String get displayLocation;

  /// 列出待导入的章节文件，按章节标题自然排序
  Future<List<ImportFileEntry>> listFiles();
}

/// 待导入的章节文件
class ImportFileEntry {
  /// 文件显示名（含扩展名）
  final String fileName;

  /// 所属分卷名，文件位于来源根目录时为空字符串
  final String volumeName;

  /// 读取文件字节的实现，由具体来源提供
  final Future<Uint8List?> Function() _readBytes;

  ImportFileEntry({
    required this.fileName,
    required this.volumeName,
    required Future<Uint8List?> Function() readBytes,
  }) : _readBytes = readBytes;

  /// 章节标题（文件名去掉扩展名）
  String get chapterTitle => fileName.replaceAll(RegExp(r'\.[^.]+$'), '');

  /// 扩展名（小写，不含点）
  String get extension => fileName.split('.').last.toLowerCase();

  /// 读取文件全部字节，读取失败返回 null
  Future<Uint8List?> readBytes() => _readBytes();
}

/// 来源文件夹已不可用（例如选择后被删除或移动）
class FolderUnavailableException implements Exception {
  const FolderUnavailableException();
}

/// 基于真实文件系统的来源（桌面端）
///
/// 目录结构规则：根目录下的文件作为无分卷章节，一层子目录作为分卷。
class LocalFolderSource implements ImportFolderSource {
  /// 文件夹的绝对路径
  final String folderPath;

  const LocalFolderSource(this.folderPath);

  @override
  String get folderName => folderPath.split(Platform.pathSeparator).last;

  @override
  String get displayLocation => folderPath;

  @override
  Future<List<ImportFileEntry>> listFiles() async {
    final folder = Directory(folderPath);
    if (!await folder.exists()) {
      throw const FolderUnavailableException();
    }

    final entries = <ImportFileEntry>[];

    // 根目录下的文件视为无分卷章节
    await for (final entity in folder.list()) {
      if (entity is File) {
        _addFileEntry(entity.path, '', entries);
      }
    }

    // 一层子目录视为分卷
    await for (final entity in folder.list()) {
      if (entity is! Directory) continue;

      final volumeName = entity.path.split(Platform.pathSeparator).last;
      // 跳过隐藏目录
      if (volumeName.startsWith('.')) continue;

      await for (final child in entity.list()) {
        if (child is File) {
          _addFileEntry(child.path, volumeName, entries);
        }
      }
    }

    entries.sort((a, b) => _naturalCompare(a.chapterTitle, b.chapterTitle));
    return entries;
  }

  /// 把符合格式的文件加入待导入列表
  void _addFileEntry(String path, String volumeName, List<ImportFileEntry> entries) {
    final fileName = path.split(Platform.pathSeparator).last;
    if (!_isImportableFile(fileName)) return;

    entries.add(ImportFileEntry(
      fileName: fileName,
      volumeName: volumeName,
      readBytes: () async {
        try {
          return await File(path).readAsBytes();
        } catch (e) {
          debugPrint('读取章节文件失败: $path: $e');
          return null;
        }
      },
    ));
  }
}

/// 基于安卓系统文件选择器授权的来源
///
/// 应用无法直接枚举共享存储中的目录，这里通过 SAF 返回的目录树 URI
/// 按 URI 列目录、按 URI 读字节，规避分区存储的原始路径限制。
class SafFolderSource implements ImportFolderSource {
  /// 系统文件选择器返回的目录树 URI
  final String treeUri;

  @override
  final String folderName;

  const SafFolderSource({required this.treeUri, required this.folderName});

  @override
  String get displayLocation => '系统文件选择器授权目录';

  @override
  Future<List<ImportFileEntry>> listFiles() async {
    final files = await AndroidNative.listChapterFiles(treeUri);
    final entries = files
        .map((file) => ImportFileEntry(
              fileName: file.fileName,
              volumeName: file.volumeName,
              readBytes: () => AndroidNative.readFileBytes(file.uri),
            ))
        .toList();

    entries.sort((a, b) => _naturalCompare(a.chapterTitle, b.chapterTitle));
    return entries;
  }
}

/// 是否是需要导入的章节文件（跳过隐藏文件与非 txt/docx 文件）
bool _isImportableFile(String fileName) {
  if (fileName.startsWith('.')) return false;

  final extension = fileName.split('.').last.toLowerCase();
  return extension == 'txt' || extension == 'docx';
}

/// 自然排序比较（优先比较文件名中的第一个数字）
int _naturalCompare(String a, String b) {
  final regExp = RegExp(r'(\d+)');

  final aMatches = regExp.allMatches(a).toList();
  final bMatches = regExp.allMatches(b).toList();

  // 两个字符串都包含数字时，先按第一个数字比较
  if (aMatches.isNotEmpty && bMatches.isNotEmpty) {
    final aNum = int.tryParse(aMatches.first.group(1) ?? '0') ?? 0;
    final bNum = int.tryParse(bMatches.first.group(1) ?? '0') ?? 0;
    if (aNum != bNum) {
      return aNum.compareTo(bNum);
    }
  }

  return a.compareTo(b);
}
