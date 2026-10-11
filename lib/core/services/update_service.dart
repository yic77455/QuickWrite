import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// 发布资产（Release 中上传的文件）
class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    required this.sourceName,
  });

  /// 文件名
  final String name;

  /// 下载地址
  final String downloadUrl;

  /// 文件大小（字节）
  final int size;

  /// 资产所属更新源的名称，用于当前源下载失败时切换到其他源兜底
  final String sourceName;
}

/// 更新源描述
///
/// 每个源提供最新发布查询接口与对应的版本发布页地址
class _UpdateSource {
  const _UpdateSource({
    required this.name,
    required this.latestApi,
    required this.releasesPageUrl,
    this.headers,
  });

  /// 源名称
  final String name;

  /// 最新发布查询接口
  final String latestApi;

  /// 版本发布页地址
  final String releasesPageUrl;

  /// 访问该源接口时附加的请求头
  final Map<String, String>? headers;
}

/// 更新检查结果
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.hasUpdate,
    required this.latestVersion,
    required this.releaseUrl,
    required this.releaseNotes,
    this.asset,
  });

  /// 是否存在比当前版本更新的版本
  final bool hasUpdate;

  /// 最新版本号（已去掉前缀 v）
  final String latestVersion;

  /// 最新版本对应的发布页地址
  final String releaseUrl;

  /// 更新说明（Release 正文）
  final String releaseNotes;

  /// 适配当前平台的安装包，未匹配到时为 null
  final UpdateAsset? asset;
}

/// 更新检查异常
class UpdateException implements Exception {
  const UpdateException(this.message);

  /// 面向用户的错误说明
  final String message;

  @override
  String toString() => message;
}

/// 用户主动取消下载
class UpdateCancelledException implements Exception {
  const UpdateCancelledException();
}

/// 下载中止令牌
///
/// 包装底层网络库的中止能力，使界面层无须直接依赖网络库
class UpdateCancelToken {
  final CancelToken _token = CancelToken();

  /// 中止对应的下载任务
  void cancel() => _token.cancel();

  /// 底层网络库的中止令牌
  CancelToken get raw => _token;
}

/// 应用更新服务
///
/// 通过发布仓库 API 检查最新版本，并支持下载当前平台对应的安装包。
/// 优先使用 GitHub，无法连接时自动切换到 Gitee 兜底。
class UpdateService {
  UpdateService._();

  /// 仓库所有者
  static const String _owner = 'yic77455';

  /// GitHub 仓库名称
  static const String _githubRepo = 'QuickWrite';

  /// Gitee 仓库名称
  static const String _giteeRepo = 'quick-write';

  /// 版本发布页地址（主源 GitHub）
  static const String releasesPageUrl = 'https://github.com/$_owner/$_githubRepo/releases';

  /// 更新源列表
  ///
  /// 按优先级排序：优先 GitHub，无法连接时自动切换到 Gitee
  static const List<_UpdateSource> _sources = [
    _UpdateSource(
      name: 'GitHub',
      latestApi: 'https://api.github.com/repos/$_owner/$_githubRepo/releases/latest',
      releasesPageUrl: releasesPageUrl,
      headers: {'Accept': 'application/vnd.github+json'},
    ),
    _UpdateSource(
      name: 'Gitee',
      latestApi: 'https://gitee.com/api/v5/repos/$_owner/$_giteeRepo/releases/latest',
      releasesPageUrl: 'https://gitee.com/$_owner/$_giteeRepo/releases',
    ),
  ];

  /// 查询更新所用的网络客户端
  static final Dio _apiDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
      headers: {'User-Agent': 'QuickWrite'},
    ),
  );

  // ================= 检查更新 =================

  /// 检查是否有新版本
  ///
  /// [currentVersion] 为当前应用版本号；按优先级依次尝试各更新源，
  /// 全部失败时抛出 [UpdateException]
  static Future<UpdateCheckResult> checkForUpdate(String currentVersion) async {
    UpdateException? lastError;

    for (final source in _sources) {
      try {
        final response = await _requestLatest(source);
        final data = response.data;
        if (data == null) throw const UpdateException('未获取到版本信息');
        return _buildResult(source, data, currentVersion);
      } on UpdateException catch (e) {
        lastError = e;
      }
    }

    throw lastError ?? const UpdateException('请求失败，请稍后重试');
  }

  /// 将某一更新源返回的发布信息转换为检查结果
  static UpdateCheckResult _buildResult(
    _UpdateSource source,
    Map<String, dynamic> data,
    String currentVersion,
  ) {
    final tag = (data['tag_name'] as String?)?.trim() ?? '';
    if (tag.isEmpty) throw const UpdateException('未获取到版本号');

    final latestVersion = _normalizeVersion(tag);

    return UpdateCheckResult(
      hasUpdate: compareVersion(latestVersion, currentVersion) > 0,
      latestVersion: latestVersion,
      releaseUrl: (data['html_url'] as String?) ?? source.releasesPageUrl,
      releaseNotes: (data['body'] as String?)?.trim() ?? '',
      asset: _pickPlatformAsset(data['assets'], source.name),
    );
  }

  /// 请求指定更新源的最新发布
  static Future<Response<Map<String, dynamic>>> _requestLatest(_UpdateSource source) async {
    try {
      return await _apiDio.get<Map<String, dynamic>>(
        source.latestApi,
        options: Options(headers: source.headers),
      );
    } on DioException catch (e) {
      throw UpdateException(_describeError(e));
    }
  }

  // ================= 下载安装包 =================

  /// 下载指定资产到本地
  ///
  /// [asset] 待下载的发布资产；[onProgress] 为进度回调（0~1，总大小未知时传 null）；
  /// [cancelToken] 可用于中止下载。返回下载完成后的本地文件路径；
  /// 当前源下载失败时自动改用其他源的同名资产重试；
  /// 失败抛出 [UpdateException]，被中止抛出 [UpdateCancelledException]
  static Future<String> downloadAsset(
    UpdateAsset asset, {
    void Function(double? progress)? onProgress,
    UpdateCancelToken? cancelToken,
  }) async {
    try {
      return await _downloadToFile(asset, onProgress: onProgress, cancelToken: cancelToken);
    } on UpdateException {
      // 当前源不可用时，改用其他源的同名资产重试
      final fallback = await _resolveFallbackAsset(asset);
      if (fallback == null) rethrow;
      return await _downloadToFile(fallback, onProgress: onProgress, cancelToken: cancelToken);
    }
  }

  /// 将资产下载到本地并返回保存路径
  static Future<String> _downloadToFile(
    UpdateAsset asset, {
    void Function(double? progress)? onProgress,
    UpdateCancelToken? cancelToken,
  }) async {
    final savePath = await _resolveSavePath(asset.name);

    final downloadDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 30),
        headers: {'User-Agent': 'QuickWrite'},
      ),
    );

    try {
      await downloadDio.download(
        asset.downloadUrl,
        savePath,
        cancelToken: cancelToken?.raw,
        onReceiveProgress: (received, total) {
          onProgress?.call(total > 0 ? received / total : null);
        },
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) throw const UpdateCancelledException();
      throw UpdateException(_describeError(e));
    }

    return savePath;
  }

  /// 在其他更新源中查找与 [asset] 同名的资产
  ///
  /// 供下载兜底使用：找不到或源不可用时返回 null
  static Future<UpdateAsset?> _resolveFallbackAsset(UpdateAsset asset) async {
    for (final source in _sources) {
      if (source.name == asset.sourceName) continue;
      try {
        final response = await _requestLatest(source);
        final data = response.data;
        if (data == null) continue;
        for (final candidate in _parseAssets(data['assets'], source.name)) {
          if (candidate.name == asset.name) return candidate;
        }
      } on UpdateException {
        // 兜底源不可用时跳过，继续尝试其他源
      }
    }
    return null;
  }

  // ================= 版本比较 =================

  /// 比较两个版本号
  ///
  /// 返回正数表示 [a] 比 [b] 新，负数表示更旧，0 表示相同
  static int compareVersion(String a, String b) {
    final segmentsA = _versionSegments(a);
    final segmentsB = _versionSegments(b);
    final length = segmentsA.length > segmentsB.length ? segmentsA.length : segmentsB.length;

    for (var i = 0; i < length; i++) {
      final valueA = i < segmentsA.length ? segmentsA[i] : 0;
      final valueB = i < segmentsB.length ? segmentsB[i] : 0;
      if (valueA != valueB) return valueA > valueB ? 1 : -1;
    }
    return 0;
  }

  /// 将版本号拆分为可比较的整数序列，忽略非数字后缀
  static List<int> _versionSegments(String version) {
    return version.split('.').map((segment) {
      final digits = RegExp(r'^\d+').firstMatch(segment)?.group(0);
      return digits == null ? 0 : int.parse(digits);
    }).toList();
  }

  /// 规范化版本号：去掉前缀 v 与预发布/构建元数据
  static String _normalizeVersion(String raw) {
    var version = raw.trim();
    if (version.startsWith('v') || version.startsWith('V')) {
      version = version.substring(1);
    }
    final cutIndex = version.indexOf(RegExp(r'[-+]'));
    return cutIndex >= 0 ? version.substring(0, cutIndex) : version;
  }

  // ================= 内部辅助 =================

  /// 解析发布资产列表
  static List<UpdateAsset> _parseAssets(dynamic rawAssets, String sourceName) {
    if (rawAssets is! List) return const [];

    final assets = <UpdateAsset>[];
    for (final item in rawAssets) {
      if (item is! Map) continue;
      final name = item['name'] as String?;
      final url = item['browser_download_url'] as String?;
      if (name == null || url == null) continue;
      assets.add(UpdateAsset(
        name: name,
        downloadUrl: url,
        size: (item['size'] as num?)?.toInt() ?? 0,
        sourceName: sourceName,
      ));
    }
    return assets;
  }

  /// 从发布资产中挑选适配当前平台的文件
  ///
  /// 优先按平台关键词匹配；仅有单个资产且未命中关键词时直接使用该资产
  static UpdateAsset? _pickPlatformAsset(dynamic rawAssets, String sourceName) {
    final assets = _parseAssets(rawAssets, sourceName);
    if (assets.isEmpty) return null;

    final keywords = _platformKeywords();
    for (final asset in assets) {
      final lowerName = asset.name.toLowerCase();
      if (keywords.any(lowerName.contains)) return asset;
    }

    return assets.length == 1 ? assets.first : null;
  }

  /// 当前平台对应的资产文件名关键词
  static List<String> _platformKeywords() {
    if (Platform.isWindows) return const ['win', 'exe', 'msi', 'setup'];
    if (Platform.isMacOS) return const ['mac', 'dmg', 'pkg'];
    if (Platform.isLinux) return const ['linux', 'appimage', 'deb', 'rpm'];
    return const [];
  }

  /// 解析安装包的保存路径
  ///
  /// 优先保存到系统下载目录，取不到时退回到文档目录
  static Future<String> _resolveSavePath(String fileName) async {
    final baseDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    return '${baseDir.path}${Platform.pathSeparator}$fileName';
  }

  /// 将网络异常转换为面向用户的提示
  static String _describeError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '连接超时，请检查网络后重试';
      case DioExceptionType.connectionError:
        return '网络连接失败，请检查网络后重试';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 404) return '仓库尚未发布任何版本';
        return '服务器返回异常（$code）';
      default:
        return '请求失败，请稍后重试';
    }
  }
}