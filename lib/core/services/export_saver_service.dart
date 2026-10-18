import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

/// 导出内容保存服务（移动端）
///
/// 移动端受分区存储限制，无法通过真实文件路径直接写入公共目录，
/// 因此导出内容先落到应用私有的临时中转目录，再由本服务打包成单个文件，
/// 通过系统「保存」选择器写入用户指定的公共位置。
class ExportSaverService {
  /// 单例实例
  static final ExportSaverService instance = ExportSaverService._internal();
  ExportSaverService._internal();

  /// 创建导出中转目录
  ///
  /// 返回应用临时目录下的一个全新文件夹，供导出内容先落盘再打包
  Future<Directory> createStagingDirectory() async {
    return Directory.systemTemp.createTemp('quick_write_export_');
  }

  /// 将中转目录中的导出内容保存到公共存储
  ///
  /// - 内容只有一个文件时，直接保存该文件，不做多余的打包
  /// - 内容包含多个文件或目录结构时，统一打包成一个 zip 再保存
  ///
  /// [stagingDirectory] 导出中转目录
  /// [preferredName] 打包为 zip 时使用的默认文件名（不含扩展名）
  ///
  /// 返回保存后文件的路径；用户在系统保存框取消时返回 null
  Future<String?> saveToPublicStorage({
    required Directory stagingDirectory,
    required String preferredName,
  }) async {
    final contents = await stagingDirectory
        .list()
        .where((entity) => entity is File || entity is Directory)
        .toList();

    if (contents.isEmpty) {
      throw Exception('没有可保存的导出内容');
    }

    // 单个文件：直接保存原文件
    if (contents.length == 1 && contents.first is File) {
      final file = contents.first as File;
      return FilePicker.platform.saveFile(
        dialogTitle: '选择保存位置',
        fileName: p.basename(file.path),
        bytes: await file.readAsBytes(),
      );
    }

    // 多个文件或目录结构：打包成一个 zip 便于保存
    final archive = Archive();
    for (final entity in contents) {
      final entryName = p.basename(entity.path);
      if (entity is File) {
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
      } else if (entity is Directory) {
        await _addDirectoryToArchive(archive, entity, entryName);
      }
    }

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw Exception('打包失败');
    }

    return FilePicker.platform.saveFile(
      dialogTitle: '选择保存位置',
      fileName: '${_sanitizeFileName(preferredName)}.zip',
      type: FileType.custom,
      allowedExtensions: ['zip'],
      bytes: Uint8List.fromList(zipBytes),
    );
  }

  /// 将目录（含子文件夹）中的文件加入压缩包
  ///
  /// [archive] 目标压缩包
  /// [directory] 待加入的目录
  /// [archivePath] 该目录在压缩包内的根路径
  Future<void> _addDirectoryToArchive(
    Archive archive,
    Directory directory,
    String archivePath,
  ) async {
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      // 压缩包内部统一使用 "/" 作为路径分隔符
      final relativePath = p
          .relative(entity.path, from: directory.path)
          .replaceAll(Platform.pathSeparator, '/');
      final entryName = '$archivePath/$relativePath';
      final bytes = await entity.readAsBytes();
      archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
    }
  }

  /// 清理中转目录
  Future<void> disposeStagingDirectory(Directory stagingDirectory) async {
    if (await stagingDirectory.exists()) {
      await stagingDirectory.delete(recursive: true);
    }
  }

  /// 清理文件名中的非法字符
  String _sanitizeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }
}
