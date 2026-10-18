import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:quick_write/core/services/app_paths.dart';
import 'package:quick_write/core/utils/font_parser.dart';

/// 推荐字体条目
///
/// 描述内置推荐的字体及其下载地址，供界面字体选择弹窗展示与下载
class RecommendedFont {
  /// 展示用字体名称
  final String displayName;

  /// 下载后保存的文件名，同时用于判断该字体是否已安装
  final String fileName;

  /// 按优先级排列的下载地址
  ///
  /// 优先使用 Gitee，国内访问更快，无法连接时再切换到 GitHub 兜底
  final List<String> urls;

  const RecommendedFont({
    required this.displayName,
    required this.fileName,
    required this.urls,
  });
}

class FontService extends ChangeNotifier {
  static final FontService _instance = FontService._internal();
  factory FontService() => _instance;
  
  FontService._internal();
  
  List<FontInfo> _systemFonts = [];
  bool _isLoading = false;
  Completer<void>? _loadCompleter;

  /// 用户导入的字体列表
  List<FontInfo> _userFonts = [];

  /// 正在下载的推荐字体文件名，null 表示当前没有下载任务
  String? _downloadingFileName;

  /// 当前下载进度（0~1），总大小未知时为 null
  double? _downloadProgress;

  /// 已注册到字体引擎的字体家族名，避免同一字体被重复注册
  final Set<String> _registeredFamilies = {};
  
  /// 系统字体列表
  List<FontInfo> get systemFonts => _systemFonts;

  /// 用户导入的字体列表
  List<FontInfo> get userFonts => _userFonts;

  /// 正在下载的推荐字体文件名，null 表示当前没有下载任务
  String? get downloadingFileName => _downloadingFileName;

  /// 当前下载进度（0~1），总大小未知时为 null
  double? get downloadProgress => _downloadProgress;

  /// 内置推荐的字体列表
  static const List<RecommendedFont> recommendedFonts = [
    RecommendedFont(
      displayName: '霞鹜文楷',
      fileName: 'LXGWWenKaiGB-Regular.ttf',
      urls: [
        'https://gitee.com/yic77455/quick-write/releases/download/v1.0.0/LXGWWenKaiGB-Regular.ttf',
        'https://github.com/yic77455/QuickWrite/releases/download/v1.0.0/LXGWWenKaiGB-Regular.ttf',
      ],
    ),
    RecommendedFont(
      displayName: '思源宋体',
      fileName: '思源宋体.otf',
      urls: [
        'https://gitee.com/yic77455/quick-write/releases/download/v1.0.0/%E6%80%9D%E6%BA%90%E5%AE%8B%E4%BD%93.otf',
        'https://github.com/yic77455/QuickWrite/releases/download/v1.0.0/siyuansongti.otf',
      ],
    ),
  ];

  /// 除推荐字体外的用户导入字体列表
  ///
  /// 推荐字体下载后同样进入用户字体列表，此处将其剔除，避免重复展示
  List<FontInfo> get importedFonts => _userFonts
      .where((font) => !recommendedFonts.any((rec) => _baseName(font.filePath) == rec.fileName))
      .toList();

  /// 按下载文件名查找已安装的推荐字体，未安装时返回 null
  FontInfo? userFontByFileName(String fileName) {
    for (final font in _userFonts) {
      if (_baseName(font.filePath) == fileName) return font;
    }
    return null;
  }

  /// 用户字体存放目录（应用私有目录下的 fonts 文件夹）
  String get _userFontDir => '${AppPaths.instance.appRootPath}${Platform.pathSeparator}fonts';
  
  /// 是否正在加载字体
  bool get isLoading => _isLoading;
  
  /// 初始化字体服务
  Future<void> initialize() async {
    if (_isLoading) {
      // 如果正在加载，等待加载完成
      return _loadCompleter?.future;
    }
    
    if (_systemFonts.isNotEmpty) {
      // 已经加载过，直接返回
      return;
    }
    
    _isLoading = true;
    _loadCompleter = Completer<void>();
    
    try {
      // 加载系统字体
      _systemFonts = await SystemFontParser.getSystemFonts();
      // 加载用户导入的字体，使已保存的自定义字体在启动后依然可用
      await loadUserFonts();
      _loadCompleter?.complete();
    } catch (e) {
      // 加载失败，使用空列表
      _systemFonts = [];
      _loadCompleter?.complete();
    } finally {
      _isLoading = false;
      _loadCompleter = null;
    }
  }
  
  /// 加载用户导入的字体
  ///
  /// 扫描用户字体目录，逐个解析并注册到字体引擎，
  /// 使用户之前导入的字体在应用重新启动后依然可用
  Future<void> loadUserFonts() async {
    _userFonts = [];
    final dir = Directory(_userFontDir);
    if (!await dir.exists()) return;

    for (final file in dir.listSync().whereType<File>()) {
      if (!_isFontFile(file)) continue;
      final info = await _parseAndRegister(file);
      if (info != null) _userFonts.add(info);
    }
  }

  /// 导入字体文件
  ///
  /// 将选中的字体文件复制到应用私有目录并注册到字体引擎，
  /// 返回解析出的字体信息；文件不存在或无法解析时返回 null
  Future<FontInfo?> importFontFile(String sourcePath) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) return null;

      final dir = Directory(_userFontDir);
      if (!await dir.exists()) await dir.create(recursive: true);

      // 以原文件名为准复制到字体目录，重复导入同一字体时直接覆盖
      final target = File('$_userFontDir${Platform.pathSeparator}${source.uri.pathSegments.last}');
      await source.copy(target.path);

      final info = await _parseAndRegister(target);
      if (info == null) return null;

      _userFonts.removeWhere((font) => font.fontFamily == info.fontFamily);
      _userFonts.add(info);
      return info;
    } catch (e) {
      debugPrint('导入字体失败: $e');
      return null;
    }
  }

  /// 下载并安装推荐字体
  ///
  /// 下载进度通过 [downloadingFileName] 与 [downloadProgress] 对外暴露，
  /// 因此关闭界面后再打开仍能恢复进度展示；
  /// 下载完成后解析并注册到字体引擎，成功时返回字体信息；
  /// 下载失败或文件无法解析时清理残留文件并返回 null
  Future<FontInfo?> downloadFont(RecommendedFont font) async {
    final dir = Directory(_userFontDir);
    if (!await dir.exists()) await dir.create(recursive: true);

    final target = File('$_userFontDir${Platform.pathSeparator}${font.fileName}');
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 2),
      ),
    );

    _downloadingFileName = font.fileName;
    _downloadProgress = null;
    notifyListeners();

    // 按优先级依次尝试各下载源，任一成功即结束
    var downloaded = false;
    for (final url in font.urls) {
      try {
        await dio.download(
          url,
          target.path,
          onReceiveProgress: (received, total) {
            _downloadProgress = total > 0 ? received / total : null;
            notifyListeners();
          },
        );
        downloaded = true;
        break;
      } catch (e) {
        debugPrint('下载字体失败: ${font.displayName}, $url, $e');
      }
    }
    if (!downloaded) {
      _clearDownloadState();
      return null;
    }

    final info = await _parseAndRegister(target);
    if (info == null) {
      // 下载得到的文件无法解析，清理以免残留
      try {
        if (await target.exists()) await target.delete();
      } catch (e) {
        debugPrint('清理无效字体文件失败: ${target.path}, $e');
      }
      _clearDownloadState();
      return null;
    }

    _userFonts.removeWhere((existing) => existing.fontFamily == info.fontFamily);
    _userFonts.add(info);
    _clearDownloadState();
    return info;
  }

  /// 清除下载状态并通知监听者
  void _clearDownloadState() {
    _downloadingFileName = null;
    _downloadProgress = null;
    notifyListeners();
  }

  /// 删除用户字体
  ///
  /// 移除字体文件与内存记录；已注册到字体引擎的字体无法即时注销，
  /// 会在应用重启后彻底失效
  Future<bool> deleteUserFont(String fontFamily) async {
    final index = _userFonts.indexWhere((font) => font.fontFamily == fontFamily);
    if (index < 0) return false;

    final font = _userFonts[index];
    try {
      final file = File(font.filePath);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('删除字体文件失败: ${font.filePath}, $e');
    }
    _userFonts.removeAt(index);
    notifyListeners();
    return true;
  }

  /// 取路径中的文件名
  String _baseName(String path) => path.split(Platform.pathSeparator).last;

  /// 判断文件是否为可解析的字体文件
  bool _isFontFile(File file) {
    final path = file.path.toLowerCase();
    return path.endsWith('.ttf') || path.endsWith('.otf') || path.endsWith('.ttc');
  }

  /// 解析字体文件并注册到字体引擎
  Future<FontInfo?> _parseAndRegister(File file) async {
    try {
      final infos = await SystemFontParser.parseFontFile(file);
      if (infos.isEmpty) return null;
      final info = infos.first;
      await _registerFont(info.fontFamily, file);
      return info;
    } catch (e) {
      debugPrint('解析字体文件失败: ${file.path}, $e');
      return null;
    }
  }

  /// 将字体文件注册到字体引擎
  ///
  /// 同一字体家族只注册一次，注册后即可被 TextStyle 的 fontFamily 引用
  Future<void> _registerFont(String family, File file) async {
    if (_registeredFamilies.contains(family)) return;
    try {
      final bytes = await file.readAsBytes();
      final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      _registeredFamilies.add(family);
    } catch (e) {
      debugPrint('注册字体失败: $family, $e');
    }
  }

  /// 刷新字体列表
  Future<void> refreshFonts() async {
    _isLoading = true;
    _loadCompleter = Completer<void>();
    
    try {
      // 重新加载系统字体
      _systemFonts = await SystemFontParser.getSystemFonts();
      _loadCompleter?.complete();
    } catch (e) {
      // 加载失败，保持原有列表
      _loadCompleter?.complete();
    } finally {
      _isLoading = false;
      _loadCompleter = null;
    }
  }
  
  /// 判断字体家族名在本地是否可用
  ///
  /// 系统字体或用户导入字体任一命中即视为可用，
  /// 用于校验设置中引用的字体在本机是否存在
  bool isFontFamilyAvailable(String fontFamily) {
    return _systemFonts.any((font) => font.fontFamily == fontFamily) ||
        _userFonts.any((font) => font.fontFamily == fontFamily);
  }

  /// 根据字体家族名称获取字体信息
  FontInfo? getFontByFamily(String fontFamily) {
    try {
      return _systemFonts.firstWhere(
        (font) => font.fontFamily == fontFamily,
      );
    } catch (e) {
      return null;
    }
  }
  
  /// 根据显示名称获取字体信息
  List<FontInfo> getFontsByDisplayName(String displayName) {
    return _systemFonts.where(
      (font) => font.displayName == displayName,
    ).toList();
  }
}
