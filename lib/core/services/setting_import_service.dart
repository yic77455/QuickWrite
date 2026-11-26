import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/models/setting_item.dart';
import 'package:quick_write/core/services/workspace/book_folder_service.dart';

/// 设定导入前的检查结果
class SettingImportPreview {
  /// 由文件名推断的设定标题
  final String title;

  /// 是否找到同名伴生文件
  final bool hasCompanion;

  /// 伴生文件中引用且实际存在的图片数量
  final int imageCount;

  /// 不影响导入但需提示用户的问题
  final List<String> warnings;

  const SettingImportPreview({
    required this.title,
    required this.hasCompanion,
    required this.imageCount,
    required this.warnings,
  });
}

/// 设定导入结果
class SettingImportResult {
  /// 是否成功
  final bool success;

  /// 错误信息
  final String? errorMessage;

  /// 导入后创建的设定项
  final SettingItemModel? item;

  /// 恢复的图片数量
  final int imageCount;

  /// 提示信息
  final List<String> warnings;

  const SettingImportResult({
    required this.success,
    this.errorMessage,
    this.item,
    this.imageCount = 0,
    this.warnings = const [],
  });

  /// 构造失败结果
  factory SettingImportResult.failure(String message) =>
      SettingImportResult(success: false, errorMessage: message);

  /// 附带新建设定项
  SettingImportResult withItem(SettingItemModel value) => SettingImportResult(
        success: success,
        errorMessage: errorMessage,
        item: value,
        imageCount: imageCount,
        warnings: warnings,
      );
}

/// 设定文件导入服务
///
/// 只处理「原格式」导出的 .md 文件：设定内容原样写回设定项目录，
/// 同名 .json 伴生文件与 image 图片一并恢复。
class SettingImportService {
  SettingImportService._();

  static final SettingImportService instance = SettingImportService._();

  /// 单个设定文件大小上限
  static const int maxFileBytes = 20 * 1024 * 1024;

  /// 检查导出的设定文件，返回预览信息；不可导入时抛出异常
  Future<SettingImportPreview> inspect(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) throw const FormatException('文件不存在');
    if (!filePath.toLowerCase().endsWith(GlobalConstants.settingFileExtension)) {
      throw const FormatException('仅支持导入原格式导出的 .md 设定文件');
    }

    final stat = await file.stat();
    if (stat.size > maxFileBytes) throw const FormatException('文件过大（上限 20MB）');

    try {
      utf8.decode(await file.readAsBytes());
    } on FormatException {
      throw const FormatException('文件不是有效的 UTF-8 文本');
    }

    final warnings = <String>[];
    final String basePath = _stripExtension(filePath);
    final File companionFile = File('$basePath${BookFolderService.outlineMetaFileSuffix}');
    bool hasCompanion = false;
    int imageCount = 0;

    if (await companionFile.exists()) {
      final Map<String, dynamic> json = await _readJsonMap(companionFile);
      hasCompanion = true;
      if (json['version'] == null) warnings.add('伴生文件缺少版本号，仍按当前版本解析');
      for (final key in const ['keywords', 'links', 'notes']) {
        final value = json[key];
        if (value != null && value is! Map) {
          throw FormatException('伴生文件中 $key 字段格式错误');
        }
      }

      final imageNames = <String>{};
      _collectImageNames(json, imageNames);
      final String? sourceImageDir = BookFolderService.settingImageDirectory(filePath);
      for (final name in imageNames) {
        final safeName = _safeFileName(name);
        if (safeName.isEmpty) continue;
        if (sourceImageDir == null || !await File(p.join(sourceImageDir, safeName)).exists()) {
          warnings.add('图片 $safeName 缺失');
        } else {
          imageCount++;
        }
      }
    }

    return SettingImportPreview(
      title: p.basenameWithoutExtension(filePath),
      hasCompanion: hasCompanion,
      imageCount: imageCount,
      warnings: warnings,
    );
  }

  /// 把检查通过的文件写入目标设定项
  ///
  /// [targetFilePath] 由 Provider 新建设定项时生成；任一步骤失败时清理
  /// 本次已写入的文件（不触碰目标目录中原有的其它文件）。
  Future<SettingImportResult> apply({
    required String sourceFilePath,
    required String targetFilePath,
  }) async {
    final createdPaths = <String>[];
    try {
      await _inspectBeforeApply(sourceFilePath);

      final targetFile = File(targetFilePath);
      if (!await targetFile.parent.exists()) {
        await targetFile.parent.create(recursive: true);
      }

      final String content = await _readUtf8(File(sourceFilePath));
      if (await targetFile.exists()) createdPaths.add(targetFilePath);
      await targetFile.writeAsString(content);

      int imageCount = 0;
      final String sourceBase = _stripExtension(sourceFilePath);
      final File sourceCompanion = File('$sourceBase${BookFolderService.outlineMetaFileSuffix}');
      if (await sourceCompanion.exists()) {
        final Map<String, dynamic> json = await _readJsonMap(sourceCompanion);
        final String targetCompanionPath =
            '${_stripExtension(targetFilePath)}${BookFolderService.outlineMetaFileSuffix}';
        if (await File(targetCompanionPath).exists()) createdPaths.add(targetCompanionPath);
        await File(targetCompanionPath).writeAsString(
          const JsonEncoder.withIndent('  ').convert(json),
        );
        imageCount = await _copyImages(
          sourceFilePath: sourceFilePath,
          targetFilePath: targetFilePath,
          json: json,
          createdPaths: createdPaths,
        );
      }

      return SettingImportResult(success: true, imageCount: imageCount);
    } on FormatException catch (e) {
      await _cleanup(createdPaths);
      return SettingImportResult.failure(e.message);
    } catch (e) {
      await _cleanup(createdPaths);
      return SettingImportResult.failure('导入文件失败: $e');
    }
  }

  /// 写入前再做一次基础检查，避免检查与写入之间文件被替换
  Future<void> _inspectBeforeApply(String sourceFilePath) async {
    final file = File(sourceFilePath);
    if (!await file.exists()) throw const FormatException('源文件不存在');
    if (!sourceFilePath.toLowerCase().endsWith(GlobalConstants.settingFileExtension)) {
      throw const FormatException('仅支持导入 .md 设定文件');
    }
    final stat = await file.stat();
    if (stat.size > maxFileBytes) throw const FormatException('文件过大（上限 20MB）');
    await _readUtf8(file);
  }

  /// 复制伴生文件中引用且实际存在的图片
  Future<int> _copyImages({
    required String sourceFilePath,
    required String targetFilePath,
    required Map<String, dynamic> json,
    required List<String> createdPaths,
  }) async {
    final names = <String>{};
    _collectImageNames(json, names);
    if (names.isEmpty) return 0;

    final String? sourceDir = BookFolderService.settingImageDirectory(sourceFilePath);
    final String? targetDir = BookFolderService.settingImageDirectory(targetFilePath);
    if (sourceDir == null || targetDir == null) return 0;

    int copied = 0;
    for (final name in names) {
      final safeName = _safeFileName(name);
      if (safeName.isEmpty) continue;
      final File source = File(p.join(sourceDir, safeName));
      if (!await source.exists()) continue;
      await Directory(targetDir).create(recursive: true);
      final String targetPath = p.join(targetDir, safeName);
      if (await File(targetPath).exists()) createdPaths.add(targetPath);
      await source.copy(targetPath);
      copied++;
    }
    return copied;
  }

  /// 递归收集伴生 JSON 中的图片文件名
  void _collectImageNames(dynamic node, Set<String> result) {
    if (node is Map) {
      final dynamic image = node['image'];
      if (image is String && image.isNotEmpty) result.add(image);
      for (final value in node.values) {
        _collectImageNames(value, result);
      }
    } else if (node is List) {
      for (final value in node) {
        _collectImageNames(value, result);
      }
    }
  }

  /// 读取并解析 JSON 对象，格式非法时抛出异常
  Future<Map<String, dynamic>> _readJsonMap(File file) async {
    final dynamic decoded;
    try {
      decoded = jsonDecode(await _readUtf8(file));
    } on FormatException {
      throw const FormatException('伴生文件不是有效的 JSON');
    }
    if (decoded is! Map) throw const FormatException('伴生文件根节点必须是 JSON 对象');
    return Map<String, dynamic>.from(decoded);
  }

  /// 严格按 UTF-8 读取文本
  Future<String> _readUtf8(File file) async => utf8.decode(await file.readAsBytes());

  /// 去除设定文件扩展名
  String _stripExtension(String path) {
    const extension = GlobalConstants.settingFileExtension;
    return path.toLowerCase().endsWith(extension)
        ? path.substring(0, path.length - extension.length)
        : path;
  }

  /// 仅保留文件名，避免伴生字段造成路径越界
  String _safeFileName(String name) => name.split(RegExp(r'[\\/]')).last.trim();

  /// 清理本次导入写入的文件
  Future<void> _cleanup(List<String> paths) async {
    for (final path in paths.reversed) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // 清理失败不影响错误提示
      }
    }
  }
}
