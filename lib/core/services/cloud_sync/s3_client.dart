import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:quick_write/core/services/cloud_sync/remote_storage.dart';
import 'package:quick_write/core/services/cloud_sync/sigv4_signer.dart';
import 'package:quick_write/core/services/cloud_sync/sync_models.dart';

/// 默认区域
const String kS3DefaultRegion = 'cn-east-1';

/// S3 客户端
///
/// 使用 SigV4 签名直接与 S3 兼容服务通信，兼容 AWS S3、Cloudflare R2、
/// 阿里云 OSS（S3 兼容模式）、MinIO 等对象存储。
///
/// 对象存储没有目录概念，因此：
/// - 创建目录为空操作，目录由对象键中的前缀隐式表达
/// - 移动对象实现为「复制 + 删除」
/// - 删除目录实现为「按前缀列出全部对象后逐个删除」
///
/// 该类只负责与远端的通信，不感知同步业务逻辑
class S3Client implements RemoteStorage {
  S3Client({
    required String endpoint,
    required this.bucket,
    required String region,
    required this.accessKey,
    required this.secretKey,
    required String remoteDir,
    this.pathStyle = false,
    this.sessionToken = '',
    DateTime Function()? clock,
  }) : _baseUri = Uri.parse(_normalizeEndpoint(endpoint)),
       region = region.trim().isEmpty ? kS3DefaultRegion : region.trim(),
       remoteDir = _normalizePrefix(remoteDir),
       _clock = clock ?? DateTime.now;

  /// 请求超时时间（毫秒）
  static const int _connectTimeout = 15000;

  /// 传输超时时间（毫秒）
  static const int _transferTimeout = 180000;

  /// 单个请求的最大尝试次数
  ///
  /// 对象存储的失败多为网络抖动或服务端临时故障，重试一两次通常即可恢复
  static const int _maxAttempts = 3;

  /// 参与文件同步的内部目录（元数据、软删除、快照）
  static const Set<String> _internalDirNames = {
    '.quickwrite',
    '.trash',
    '.snapshots',
  };

  /// 服务端点（已去除结尾斜杠）
  final Uri _baseUri;

  /// 存储桶名称
  final String bucket;

  /// 区域
  final String region;

  /// Access Key
  final String accessKey;

  /// Secret Key
  final String secretKey;

  /// 临时凭据的会话令牌（使用长期密钥时为空）
  final String sessionToken;

  /// 远端目录（对象键前缀，已规范化）
  @override
  final String remoteDir;

  /// 是否使用路径风格访问（`endpoint/bucket/key`），否则使用虚拟主机风格
  final bool pathStyle;

  /// 当前时间来源
  ///
  /// 抽成可替换的函数，便于用固定时间验证签名算法
  final DateTime Function() _clock;

  /// HTTP 客户端（首次使用时创建）
  Dio? _dio;

  // ================= 静态工具 =================

  /// 校验服务端点是否合法
  ///
  /// 要求使用 HTTPS；本机地址允许明文，便于调试自建的 MinIO
  static bool isValidEndpoint(String value) {
    final uri = Uri.tryParse(_normalizeEndpoint(value));
    if (uri == null || uri.host.isEmpty) return false;
    if (uri.scheme == 'https') return true;
    if (uri.scheme != 'http') return false;
    const localHosts = {'localhost', '127.0.0.1', '::1'};
    return localHosts.contains(uri.host);
  }

  /// 规范化服务端点：去除结尾斜杠，未填写协议时补全为 HTTPS
  static String _normalizeEndpoint(String value) {
    var endpoint = value.trim();
    if (endpoint.isEmpty) return endpoint;
    if (!endpoint.startsWith('http://') && !endpoint.startsWith('https://')) {
      endpoint = 'https://$endpoint';
    }
    while (endpoint.endsWith('/')) {
      endpoint = endpoint.substring(0, endpoint.length - 1);
    }
    return endpoint;
  }

  /// 规范化对象键前缀：去除首尾斜杠
  static String _normalizePrefix(String value) {
    var prefix = value.trim();
    while (prefix.startsWith('/')) {
      prefix = prefix.substring(1);
    }
    while (prefix.endsWith('/')) {
      prefix = prefix.substring(0, prefix.length - 1);
    }
    return prefix;
  }

  // ================= 连接操作 =================

  @override
  String remotePathOf(String key) => remoteDir.isEmpty ? key : '$remoteDir/$key';

  @override
  Future<void> ping() async {
    // 列举 1 个对象即可同时验证地址、签名与存储桶是否存在
    await _send('GET', '', query: {'list-type': '2', 'max-keys': '1'});
  }

  @override
  Future<void> ensureDirectory(String path) async {
    // 对象存储无需创建目录
  }

  @override
  void resetDirectoryCache() {
    // 对象存储不缓存目录
  }

  @override
  Future<List<RemoteSyncFile>> listFilesRecursive() async {
    final prefix = remoteDir.isEmpty ? '' : '$remoteDir/';
    final files = <RemoteSyncFile>[];

    String? token;
    do {
      final xml = await _listXml(
        prefix: prefix,
        continuationToken: token,
      );
      for (final object in _parseContents(xml)) {
        if (object.key.endsWith(kSyncTempSuffix)) continue;

        // 列举结果包含前缀本身，转换为相对于同步根目录的逻辑键
        final relativeKey = object.key.startsWith(prefix)
            ? object.key.substring(prefix.length)
            : object.key;
        if (relativeKey.isEmpty) continue;
        if (_isInternalKey(relativeKey)) continue;

        files.add(
          RemoteSyncFile(
            key: relativeKey,
            etag: object.etag,
            size: object.size,
            modifiedAt: object.modifiedAt,
          ),
        );
      }
      token = _tagText(xml, 'NextContinuationToken');
    } while (token.isNotEmpty);

    return files;
  }

  @override
  Future<void> uploadFile(String localPath, String remotePath) async {
    final bytes = await File(localPath).readAsBytes();
    await _putObject(remotePath, bytes);
  }

  @override
  Future<void> uploadBytes(Uint8List bytes, String remotePath) =>
      _putObject(remotePath, bytes);

  @override
  Future<Uint8List> downloadBytes(String remotePath) async {
    final response = await _send(
      'GET',
      remotePath,
      responseType: ResponseType.bytes,
    );
    return Uint8List.fromList(response.data as List<int>);
  }

  @override
  Future<Uint8List?> downloadBytesIfExists(String remotePath) async {
    final response = await _send(
      'GET',
      remotePath,
      responseType: ResponseType.bytes,
      allowNotFound: true,
    );
    if (response.statusCode == 404) return null;
    return Uint8List.fromList(response.data as List<int>);
  }

  @override
  Future<void> downloadFile(String remotePath, String localPath) async {
    final bytes = await downloadBytes(remotePath);
    final file = File(localPath);
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<List<String>> listFileNames(String remotePath) async {
    final prefix = _prefixOf(remotePath);
    final xml = await _listXml(prefix: prefix, delimiter: '/');
    return [
      for (final object in _parseContents(xml))
        if (object.key.length > prefix.length)
          object.key.substring(prefix.length),
    ];
  }

  @override
  Future<List<String>> listDirectoryNames(String remotePath) async {
    final prefix = _prefixOf(remotePath);
    final xml = await _listXml(prefix: prefix, delimiter: '/');
    final names = <String>[];
    for (final match
        in RegExp(r'<CommonPrefixes>([\s\S]*?)</CommonPrefixes>').allMatches(xml)) {
      final value = _tagText(match.group(1)!, 'Prefix');
      if (value.length <= prefix.length) continue;
      final name = value.substring(prefix.length);
      if (name.isEmpty) continue;
      names.add(name.endsWith('/') ? name.substring(0, name.length - 1) : name);
    }
    return names;
  }

  @override
  Future<void> moveFile(
    String fromPath,
    String toPath, {
    bool overwrite = true,
  }) async {
    // 复制源固定为「/存储桶/对象键」，对象键逐段编码但保留斜杠
    final sourceKey = _pathSegmentsOf(fromPath).map(encodeRfc3986).join('/');
    final copySource = '/${encodeRfc3986(bucket)}/$sourceKey';

    final response = await _send(
      'PUT',
      toPath,
      headers: {'x-amz-copy-source': copySource},
    );

    // 复制失败时服务端仍可能返回 200，错误信息放在响应体中
    final data = response.data;
    final text = data is String ? data : '';
    if (text.contains('<Error>')) {
      throw StateError('远端复制失败：${_tagText(text, 'Message')}');
    }

    await deleteFile(fromPath);
  }

  @override
  Future<void> deleteFile(String remotePath) async {
    await _send('DELETE', remotePath, allowNotFound: true);
  }

  @override
  Future<void> deleteDirectoryRecursive(String remotePath) =>
      _deleteByPrefix(_prefixOf(remotePath));

  @override
  Future<void> clearDirectory(String remotePath) =>
      _deleteByPrefix(_prefixOf(remotePath));

  @override
  Future<RemoteSyncFile> fileInfo(String key) async {
    final response = await _send('HEAD', key);
    return _remoteFileOf(key, response);
  }

  @override
  Future<bool> exists(String key) async {
    final response = await _send('HEAD', key, allowNotFound: true);
    return response.statusCode != 404;
  }

  @override
  void dispose() {
    _dio?.close(force: true);
    _dio = null;
  }

  // ================= 内部实现 =================

  /// 上传一个对象
  Future<void> _putObject(String remotePath, List<int> bytes) async {
    await _send('PUT', remotePath, body: bytes);
  }

  /// 按前缀删除全部对象
  ///
  /// 对象存储没有目录，删除目录等价于删除该前缀下的所有对象
  Future<void> _deleteByPrefix(String prefix) async {
    String? token;
    do {
      final xml = await _listXml(prefix: prefix, continuationToken: token);
      for (final object in _parseContents(xml)) {
        await deleteFile(object.key);
      }
      token = _tagText(xml, 'NextContinuationToken');
    } while (token.isNotEmpty);
  }

  /// 目录路径对应的对象键前缀（统一以斜杠结尾）
  String _prefixOf(String remotePath) {
    final path = remotePath.trim();
    if (path.isEmpty) return '';
    return path.endsWith('/') ? path : '$path/';
  }

  /// 判断相对键是否位于内部目录中
  bool _isInternalKey(String relativeKey) {
    final firstSegment = relativeKey.split('/').first;
    return _internalDirNames.contains(firstSegment);
  }

  /// 发起一次列举请求并返回响应体
  Future<String> _listXml({
    required String prefix,
    String? delimiter,
    String? continuationToken,
  }) async {
    final query = <String, String>{
      'list-type': '2',
      'max-keys': '1000',
      if (prefix.isNotEmpty) 'prefix': prefix,
      // ignore: use_null_aware_elements
      if (delimiter != null) 'delimiter': delimiter,
      if (continuationToken != null && continuationToken.isNotEmpty)
        'continuation-token': continuationToken,
    };
    final response = await _send('GET', '', query: query);
    final data = response.data;
    return data is String ? data : utf8.decode(data as List<int>);
  }

  /// 由 HEAD 响应构造远端文件描述
  RemoteSyncFile _remoteFileOf(String key, Response<dynamic> response) {
    final etag = response.headers.value('etag') ?? '';
    final length = int.tryParse(response.headers.value('content-length') ?? '');
    final modified = DateTime.tryParse(
      response.headers.value('last-modified') ?? '',
    );
    return RemoteSyncFile(
      key: key,
      etag: etag.replaceAll('"', ''),
      size: length ?? 0,
      modifiedAt: modified,
    );
  }

  /// HTTP 客户端
  Dio get _dioInstance {
    final existing = _dio;
    if (existing != null) return existing;

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(milliseconds: _connectTimeout),
        sendTimeout: const Duration(milliseconds: _transferTimeout),
        receiveTimeout: const Duration(milliseconds: _transferTimeout),
        // 状态码由本类统一判断，便于区分「文件不存在」与真正的失败
        validateStatus: (_) => true,
      ),
    );
    _dio = dio;
    return dio;
  }

  /// 发起一次带签名的请求
  ///
  /// 对象存储的临时性错误较多，这里对网络异常与 5xx 做有限次重试
  Future<Response<dynamic>> _send(
    String method,
    String key, {
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
    List<int>? body,
    ResponseType responseType = ResponseType.plain,
    bool allowNotFound = false,
  }) async {
    final request = _buildSignedRequest(
      method: method,
      key: key,
      query: query,
      extraHeaders: headers,
      body: body,
    );

    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final response = await _dioInstance.request<dynamic>(
          request.url,
          data: body,
          options: Options(
            method: method,
            headers: request.headers,
            responseType: responseType,
          ),
        );

        final status = response.statusCode ?? 0;
        if (status >= 200 && status < 300) return response;
        if (status == 404 && allowNotFound) return response;

        final error = _badResponseError(response);
        if (!_isRetryableStatus(status) || attempt == _maxAttempts) throw error;
        lastError = error;
      } on DioException catch (e) {
        if (!_isRetryableDioError(e) || attempt == _maxAttempts) rethrow;
        lastError = e;
      }

      await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
    }

    throw lastError ?? StateError('S3 请求失败: $method $key');
  }

  /// 构造带 SigV4 签名的请求
  _SignedRequest _buildSignedRequest({
    required String method,
    required String key,
    required Map<String, String> query,
    required Map<String, String> extraHeaders,
    required List<int>? body,
  }) {
    if (!isValidEndpoint(_baseUri.toString())) {
      throw ArgumentError('S3 服务端点无效，请填写完整地址（本地服务可使用 http://）');
    }
    if (bucket.trim().isEmpty) {
      throw ArgumentError('请填写 S3 存储桶名称');
    }

    final canonicalPath = _canonicalPathOf(key);
    final canonicalQuery = canonicalQueryOf(query);
    final authority = _authority;
    final url = '${_baseUri.scheme}://$authority$canonicalPath'
        '${canonicalQuery.isEmpty ? '' : '?$canonicalQuery'}';

    final payloadHash = sha256Hex(body ?? const <int>[]);

    // 必须参与签名的头：host 与全部 x-amz-*
    final headersToSign = <String, String>{
      'host': authority,
      'x-amz-content-sha256': payloadHash,
      for (final entry in extraHeaders.entries)
        if (entry.key.toLowerCase().startsWith('x-amz-'))
          entry.key.toLowerCase(): entry.value,
    };

    final signature = _signer.sign(
      method: method,
      canonicalPath: canonicalPath,
      canonicalQuery: canonicalQuery,
      headers: headersToSign,
      payloadHash: payloadHash,
      timestamp: _clock(),
    );

    return _SignedRequest(
      url: url,
      headers: {...extraHeaders, ...signature.headers},
    );
  }

  /// SigV4 签名器
  SigV4Signer get _signer => SigV4Signer(
    accessKey: accessKey,
    secretKey: secretKey,
    region: region,
    sessionToken: sessionToken,
  );

  /// 请求的主机头：路径风格下为服务端点本身，虚拟主机风格下前置存储桶名
  String get _authority {
    final host = pathStyle || bucket.isEmpty
        ? _baseUri.host
        : '$bucket.${_baseUri.host}';
    return _baseUri.hasPort ? '$host:${_baseUri.port}' : host;
  }

  /// 规范化的请求路径（含存储桶与对象键，逐段进行 RFC3986 编码）
  String _canonicalPathOf(String key) {
    final segments = <String>[
      if (pathStyle && bucket.isNotEmpty) bucket,
      ..._pathSegmentsOf(key),
    ];
    if (segments.isEmpty) return '/';
    return '/${segments.map(encodeRfc3986).join('/')}';
  }

  /// 对象键拆分为路径片段
  List<String> _pathSegmentsOf(String key) =>
      key.split('/').where((segment) => segment.isNotEmpty).toList();

  /// 构造响应错误，便于上层通过状态码统一判断错误类型
  DioException _badResponseError(Response<dynamic> response) {
    return DioException(
      requestOptions: response.requestOptions,
      response: response,
      type: DioExceptionType.badResponse,
      error: response.statusMessage,
    );
  }

  /// 服务端临时故障与限流可以重试
  bool _isRetryableStatus(int status) =>
      status == 429 || status == 408 || status >= 500;

  /// 网络类异常可以重试
  bool _isRetryableDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode;
        return status != null && _isRetryableStatus(status);
      default:
        return false;
    }
  }

  /// 解析列举结果中的对象条目
  Iterable<_S3Object> _parseContents(String xml) sync* {
    final pattern = RegExp(r'<Contents>([\s\S]*?)</Contents>');
    for (final match in pattern.allMatches(xml)) {
      final block = match.group(1)!;
      yield _S3Object(
        key: _tagText(block, 'Key'),
        etag: _tagText(block, 'ETag').replaceAll('"', ''),
        size: int.tryParse(_tagText(block, 'Size')) ?? 0,
        modifiedAt: DateTime.tryParse(_tagText(block, 'LastModified')),
      );
    }
  }

  /// 读取指定标签的文本内容
  String _tagText(String xml, String tag) {
    final match = RegExp('<$tag>([\\s\\S]*?)</$tag>').firstMatch(xml);
    if (match == null) return '';
    return _unescapeXml(match.group(1)!.trim());
  }

  /// 还原 XML 实体
  String _unescapeXml(String value) => value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

/// 待发送的签名请求
class _SignedRequest {
  /// 完整请求地址
  final String url;

  /// 需要附加的请求头（含签名）
  final Map<String, String> headers;

  const _SignedRequest({required this.url, required this.headers});
}

/// 列举结果中的一个对象
class _S3Object {
  /// 完整对象键
  final String key;

  /// 对象 ETag
  final String etag;

  /// 对象字节数
  final int size;

  /// 最后修改时间
  final DateTime? modifiedAt;

  const _S3Object({
    required this.key,
    required this.etag,
    required this.size,
    this.modifiedAt,
  });
}
