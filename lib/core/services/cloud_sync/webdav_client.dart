import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:quick_write/core/services/cloud_sync/sync_models.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

/// WebDAV 客户端封装
///
/// 在 webdav_client 的基础上提供：
/// - 服务器地址校验，要求使用 HTTPS，避免账号密码以明文传输
/// - 统一的连接与传输超时
/// - 请求节流与限流退避，避免触发网盘的访问频率限制
///
/// 该类只负责与远端服务器的通信，不感知具体的同步业务逻辑
class WebDavClient {
  // ================= 常量定义 =================

  /// 建立连接的超时时间（毫秒）
  static const int _connectTimeout = 15000;

  /// 发送数据的超时时间（毫秒）
  static const int _sendTimeout = 180000;

  /// 接收数据的超时时间（毫秒）
  static const int _receiveTimeout = 180000;

  /// 普通临时错误的最大重试次数
  static const int _maxRetries = 3;

  /// 服务端限流时的最大重试次数
  ///
  /// 网盘的访问频率限制通常按较长的时间窗口计算，短时间内重试没有意义，
  /// 因此重试次数较少、等待时间较长，超过后交由上层中止本轮同步
  static const int _maxRateLimitRetries = 3;

  /// 相邻两次请求之间的最小间隔
  ///
  /// 网盘普遍对 WebDAV 请求频率有严格限制（例如每 30 分钟数百次），
  /// 保持间隔可以让长时间同步不至于迅速耗尽配额
  static const Duration _minRequestInterval = Duration(milliseconds: 300);

  /// 请求间隔放宽后的上限
  static const Duration _maxRequestInterval = Duration(seconds: 5);

  /// 服务端限流时的退避基数
  static const Duration _rateLimitBaseDelay = Duration(seconds: 5);

  /// 单次重试等待的上限
  static const Duration _maxRetryDelay = Duration(seconds: 30);

  /// 普通临时错误的基础等待时间
  static const Duration _retryBaseDelay = Duration(milliseconds: 800);

  /// 不作为普通文件同步的远端内部目录
  static const Set<String> _internalDirNames = {
    '.quickwrite', // 同步元数据
    '.trash', // 软删除文件
    '.snapshots', // 首次同步前的整包快照
  };

  // ================= 构造与属性 =================

  WebDavClient({
    required this.serverUrl,
    required this.username,
    required this.password,
    required this.remoteDir,
  });

  /// 服务器地址
  final String serverUrl;

  /// 登录账号
  final String username;

  /// 登录密码
  final String password;

  /// 远端同步根目录（已规范化，无首尾斜杠）
  final String remoteDir;

  /// 底层 WebDAV 客户端（首次使用时创建）
  webdav.Client? _rawClient;

  /// 已确认存在的远端目录，避免重复发起创建请求
  final Set<String> _ensuredDirs = {};

  /// 请求节流器
  final _RequestThrottle _throttle = _RequestThrottle(
    initialInterval: _minRequestInterval,
    maxInterval: _maxRequestInterval,
  );

  /// 生成退避抖动用的随机数
  final math.Random _random = math.Random();

  // ================= 连接操作 =================

  /// 校验服务器地址是否合法
  ///
  /// 要求地址格式正确且使用 HTTPS 协议
  static bool isValidServerUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  /// 判断异常是否由服务端请求频率限制引起
  static bool isRateLimitError(Object error) {
    if (error is! DioException) return false;
    final status = error.response?.statusCode;
    return status == 429 || status == 503;
  }

  /// 将通信过程中的异常转换为便于用户理解的提示文本
  static String describeError(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) return '账号或密码错误';
      if (status == 404) return '服务器地址或远端目录不存在';
      if (status == 429 || status == 503) return '服务端请求过于频繁，请稍后再试';
      if (status != null) return '服务器返回错误（HTTP $status）';
      // 未收到响应时通常是网络异常或请求超时
      return '无法连接到服务器，请检查网络与服务器地址';
    }
    return error.toString();
  }

  /// 测试与服务器的连接是否可用
  Future<void> ping() => _withRetry(() => _client.ping());

  /// 确保远端目录存在（不存在时逐级创建）
  Future<void> ensureDirectory(String path) =>
      _withRetry(() => _client.mkdirAll(path));

  /// 清除已创建目录的缓存
  ///
  /// 远端目录被整体删除后，缓存中的目录已不存在，需要重新创建
  void resetDirectoryCache() => _ensuredDirs.clear();

  /// 递归列出远端同步目录下的全部文件
  ///
  /// WebDAV 的单次列举只覆盖一层目录，因此按目录逐层展开。
  /// 返回结果中的逻辑键为相对于同步根目录的路径，内部目录不会进入结果
  Future<List<RemoteSyncFile>> listFilesRecursive() async {
    final files = <RemoteSyncFile>[];
    // 待展开的目录队列，元素为相对于同步根目录的目录路径，空字符串表示根目录
    final pendingDirs = <String>[''];

    while (pendingDirs.isNotEmpty) {
      final relativeDir = pendingDirs.removeAt(0);
      final remotePath = relativeDir.isEmpty
          ? remoteDir
          : '$remoteDir/$relativeDir';

      final entries = await _withRetry(() => _client.readDir(remotePath));
      for (final entry in entries) {
        final name = entry.name;
        if (name == null || name.isEmpty) continue;

        final relativePath = relativeDir.isEmpty ? name : '$relativeDir/$name';
        if (entry.isDir == true) {
          // 内部目录不参与文件同步
          if (_internalDirNames.contains(name)) continue;
          pendingDirs.add(relativePath);
          continue;
        }

        // 跳过传输中断残留的临时文件
        if (name.endsWith(kSyncTempSuffix)) continue;

        files.add(
          RemoteSyncFile(
            key: relativePath,
            etag: entry.eTag ?? '',
            size: entry.size ?? 0,
            modifiedAt: entry.mTime,
          ),
        );
      }
    }

    return files;
  }

  /// 释放底层连接资源
  void dispose() {
    _rawClient?.c.close(force: true);
    _rawClient = null;
    _ensuredDirs.clear();
  }

  // ================= 文件传输 =================

  /// 将逻辑键转换为远端绝对路径
  String remotePathOf(String key) => '$remoteDir/$key';

  /// 上传本地文件到远端
  ///
  /// 直接发起 PUT，跳过 webdav_client 内部为兼容摘要认证而附加的预检请求，
  /// 从而显著减少请求次数
  Future<void> uploadFile(String localPath, String remotePath) async {
    await _ensureParentDirectory(remotePath);

    final file = File(localPath);
    final length = await file.length();
    await _request(
      'PUT',
      remotePath,
      data: file.openRead(),
      optionsHandler: (options) => options.headers?['content-length'] = length,
    );
  }

  /// 上传内存中的字节数据到远端
  ///
  /// 用于上传归档包等已在内存中生成的内容
  Future<void> uploadBytes(Uint8List bytes, String remotePath) async {
    await _ensureParentDirectory(remotePath);

    await _request(
      'PUT',
      remotePath,
      data: bytes,
      optionsHandler: (options) =>
          options.headers?['content-length'] = bytes.length,
    );
  }

  /// 下载远端文件到内存
  Future<Uint8List> downloadBytes(String remotePath) async {
    final response = await _request(
      'GET',
      remotePath,
      optionsHandler: (options) => options.responseType = ResponseType.bytes,
    );

    // 部分服务端会把文件内容重定向到其他地址，跟随一次重定向
    final status = response.statusCode;
    if (status != null && status >= 300 && status < 400) {
      final location = response.headers.value('location');
      if (location == null || location.isEmpty) {
        throw StateError('远端文件下载被重定向，但响应中缺少目标地址');
      }
      final redirected = await _request(
        'GET',
        location,
        optionsHandler: (options) => options.responseType = ResponseType.bytes,
      );
      return Uint8List.fromList(redirected.data as List<int>);
    }

    return Uint8List.fromList(response.data as List<int>);
  }

  /// 下载远端文件到内存，文件不存在时返回 null
  Future<Uint8List?> downloadBytesIfExists(String remotePath) async {
    try {
      return await downloadBytes(remotePath);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// 列出远端指定目录下的直接文件名，目录不存在时返回空列表
  Future<List<String>> listFileNames(String remotePath) async {
    final entries = await _listEntries(remotePath);
    return [
      for (final entry in entries)
        if (entry.isDir != true && entry.name != null && entry.name!.isNotEmpty)
          entry.name!,
    ];
  }

  /// 列出远端指定目录下的子目录名，目录不存在时返回空列表
  Future<List<String>> listDirectoryNames(String remotePath) async {
    final entries = await _listEntries(remotePath);
    return [
      for (final entry in entries)
        if (entry.isDir == true && entry.name != null && entry.name!.isNotEmpty)
          entry.name!,
    ];
  }

  /// 递归删除远端目录
  ///
  /// 目录内可能包含大量条目，优先请求服务端整目录删除；
  /// 服务端不支持时退化为逐个条目删除
  Future<void> deleteDirectoryRecursive(String remotePath) async {
    if (await _tryDeleteCollection(remotePath)) return;

    final entries = await _listEntries(remotePath);
    for (final entry in entries) {
      final name = entry.name;
      if (name == null || name.isEmpty) continue;

      final childPath = '$remotePath/$name';
      if (entry.isDir == true) {
        await deleteDirectoryRecursive(childPath);
      } else {
        await deleteFile(childPath);
      }
    }

    try {
      await deleteFile(remotePath);
    } on DioException {
      // 部分服务端拒绝删除目录本身，目录内已无内容时视为删除完成
      final remaining = await _listEntries(remotePath);
      if (remaining.isNotEmpty) rethrow;
      debugPrint('服务端未删除目录本身，目录内容已清空: $remotePath');
    }
  }

  /// 清空远端目录内的全部内容
  ///
  /// 只清理目录内的内容并保留目录本身，
  /// 避免因服务端不允许删除该目录而误报失败
  Future<void> clearDirectory(String remotePath) async {
    final entries = await _listEntries(remotePath);
    for (final entry in entries) {
      final name = entry.name;
      if (name == null || name.isEmpty) continue;

      final childPath = '$remotePath/$name';
      if (entry.isDir == true) {
        await deleteDirectoryRecursive(childPath);
      } else {
        await deleteFile(childPath);
      }
    }
  }

  /// 尝试一次性删除目录，成功返回 true
  Future<bool> _tryDeleteCollection(String remotePath) async {
    try {
      await _request('DELETE', remotePath);
      return true;
    } on DioException catch (e) {
      // 目录不存在时视为删除完成
      if (e.response?.statusCode == 404) return true;
      debugPrint('服务端未能整目录删除，改为逐个删除: $remotePath');
      return false;
    }
  }

  /// 列出目录下的原始条目，目录不存在时返回空列表
  Future<List<webdav.File>> _listEntries(String remotePath) async {
    try {
      return await _withRetry(() => _client.readDir(remotePath));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return const [];
      rethrow;
    }
  }

  /// 下载远端文件到本地指定路径
  Future<void> downloadFile(String remotePath, String localPath) =>
      _withRetry(() => _client.read2File(remotePath, localPath));

  /// 移动远端文件
  ///
  /// 部分服务端不支持 MOVE 覆盖已存在的目标，遇到目标冲突时先删除目标再重试，
  /// 从而在保留 MOVE 原子替换特性的同时兼容这类服务端。
  /// 直接发起 MOVE，跳过内部预检请求
  Future<void> moveFile(
    String fromPath,
    String toPath, {
    bool overwrite = true,
  }) async {
    try {
      await _moveOnce(fromPath, toPath, overwrite: overwrite);
    } on DioException catch (e) {
      if (!overwrite || !_isTargetConflict(e)) rethrow;
      await deleteFile(toPath);
      await _moveOnce(fromPath, toPath, overwrite: overwrite);
    }
  }

  /// 删除远端文件
  ///
  /// 文件已不存在时视为删除成功，便于重试
  Future<void> deleteFile(String remotePath) async {
    try {
      await _request('DELETE', remotePath);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return;
      rethrow;
    }
  }

  /// 发起一次 MOVE 请求
  Future<void> _moveOnce(
    String fromPath,
    String toPath, {
    required bool overwrite,
  }) async {
    await _request(
      'MOVE',
      fromPath,
      optionsHandler: (options) {
        options.headers?['destination'] = _absoluteUrlOf(toPath);
        options.headers?['overwrite'] = overwrite ? 'T' : 'F';
      },
    );
  }

  /// 判断异常是否表示移动目标已存在
  bool _isTargetConflict(DioException error) {
    final status = error.response?.statusCode;
    // 409 表示目标冲突，412 表示目标已存在且服务端未允许覆盖
    return status == 409 || status == 412;
  }

  /// 读取远端文件属性
  Future<RemoteSyncFile> fileInfo(String key) async {
    final file = await _withRetry(() => _client.readProps(remotePathOf(key)));
    return RemoteSyncFile(
      key: key,
      etag: file.eTag ?? '',
      size: file.size ?? 0,
      modifiedAt: file.mTime,
    );
  }

  /// 判断远端文件是否存在
  Future<bool> exists(String key) async {
    try {
      await _client.readProps(remotePathOf(key));
      return true;
    } on DioException catch (e) {
      // 404 表示文件不存在，其余错误继续向上抛出
      if (e.response?.statusCode == 404) return false;
      rethrow;
    }
  }

  // ================= 内部实现 =================

  /// 获取底层客户端，首次访问时按配置创建
  webdav.Client get _client {
    if (_rawClient != null) return _rawClient!;

    if (!isValidServerUrl(serverUrl)) {
      throw ArgumentError('服务器地址无效，请填写以 https:// 开头的完整地址');
    }

    final client = webdav.newClient(
      serverUrl,
      user: username,
      password: password,
    );
    client.setConnectTimeout(_connectTimeout);
    client.setSendTimeout(_sendTimeout);
    client.setReceiveTimeout(_receiveTimeout);
    _rawClient = client;
    debugPrint('WebDavClient 已创建，服务器地址: ${client.uri}');
    return client;
  }

  /// 确保远端文件所在目录存在
  ///
  /// 同一目录在一次同步中只创建一次
  Future<void> _ensureParentDirectory(String remotePath) async {
    final separatorIndex = remotePath.lastIndexOf('/');
    if (separatorIndex <= 0) return;

    final parentPath = remotePath.substring(0, separatorIndex);
    if (!_ensuredDirs.add(parentPath)) return;
    await _withRetry(() => _client.mkdirAll(parentPath));
  }

  /// 拼接远端资源的绝对地址，用于 MOVE 的目标地址头
  String _absoluteUrlOf(String remotePath) {
    final base = _client.uri.endsWith('/') ? _client.uri : '${_client.uri}/';
    final relative = remotePath.startsWith('/')
        ? remotePath.substring(1)
        : remotePath;
    return Uri.encodeFull('$base$relative');
  }

  /// 发起原始请求并校验响应状态
  ///
  /// 底层 HTTP 客户端把所有状态码都视为正常响应，因此状态校验必须放在重试闭包内，
  /// 服务端限流与临时故障才能被识别并进入统一的退避与冷却流程
  Future<Response<dynamic>> _request(
    String method,
    String path, {
    dynamic data,
    void Function(Options options)? optionsHandler,
  }) {
    return _withRetry(() async {
      final response = await _client.c.req<dynamic>(
        _client,
        method,
        path,
        data: data,
        optionsHandler: optionsHandler,
      );

      final status = response.statusCode;
      if (status == null || (status >= 200 && status < 300)) return response;
      throw _badResponseError(response);
    });
  }

  /// 构造响应错误
  ///
  /// 便于上层通过状态码统一判断错误类型
  DioException _badResponseError(Response<dynamic> response) {
    return DioException(
      requestOptions: response.requestOptions,
      response: response,
      type: DioExceptionType.badResponse,
      error: response.statusMessage,
    );
  }

  // ================= 重试机制 =================

  /// 执行带自动重试的操作
  ///
  /// 每次尝试前都会经过节流，既保证请求间隔，也让服务端限流时并发的请求一并等待；
  /// 仅在出现可重试的临时性错误时重试，其余错误直接抛出
  Future<T> _withRetry<T>(Future<T> Function() action) async {
    var attempt = 0;
    while (true) {
      await _throttle.acquire();

      try {
        return await action();
      } catch (e) {
        attempt++;
        final rateLimited = isRateLimitError(e);
        final maxAttempts = rateLimited ? _maxRateLimitRetries : _maxRetries;
        if (!_isRetryable(e) || attempt > maxAttempts) rethrow;

        // 放宽请求间隔并进入全局冷却，避免并发的其他请求继续冲击已被限流的服务端
        if (rateLimited) _throttle.slowDown();
        _throttle.cooldown(_retryDelayFor(e, attempt));
      }
    }
  }

  /// 判断错误是否属于可重试的临时性错误
  bool _isRetryable(Object error) {
    if (error is! DioException) return false;

    final status = error.response?.statusCode;
    // 未收到响应，通常是网络中断或请求超时
    if (status == null) return true;
    // 请求过于频繁或服务端临时故障
    return status == 429 || status >= 500;
  }

  /// 计算重试前的等待时长
  ///
  /// 服务端限流时采用指数退避并附加随机抖动，避免多个并发请求同时重试
  Duration _retryDelayFor(Object error, int attempt) {
    if (!isRateLimitError(error)) {
      return _retryBaseDelay * attempt;
    }

    final exponential = _rateLimitBaseDelay * (1 << (attempt - 1));
    final capped = exponential > _maxRetryDelay ? _maxRetryDelay : exponential;
    return capped + Duration(milliseconds: _random.nextInt(500));
  }
}

/// 请求节流器
///
/// 统一控制对远端的请求节奏：
/// - 保证相邻请求之间存在最小间隔，避免过快耗尽服务端的访问配额
/// - 服务端限流时逐步放宽间隔并进入全局冷却，冷却期内所有请求排队等待
class _RequestThrottle {
  _RequestThrottle({
    required Duration initialInterval,
    required this.maxInterval,
  }) : _interval = initialInterval;

  /// 请求间隔放宽后的上限
  final Duration maxInterval;

  /// 当前的请求间隔，服务端限流后会自动放宽
  Duration _interval;

  /// 上一次请求的发起时间
  DateTime? _lastRequestAt;

  /// 冷却截止时间
  DateTime? _cooldownUntil;

  /// 等待轮到本次请求发起
  Future<void> acquire() async {
    while (true) {
      final now = DateTime.now();

      // 处于冷却期时先等待冷却结束
      final cooldownUntil = _cooldownUntil;
      if (cooldownUntil != null && now.isBefore(cooldownUntil)) {
        await Future.delayed(cooldownUntil.difference(now));
        continue;
      }

      // 与上一次请求保持最小间隔
      final lastRequestAt = _lastRequestAt;
      if (lastRequestAt != null) {
        final earliest = lastRequestAt.add(_interval);
        if (now.isBefore(earliest)) {
          await Future.delayed(earliest.difference(now));
          continue;
        }
      }

      _lastRequestAt = DateTime.now();
      return;
    }
  }

  /// 放宽请求间隔
  ///
  /// 服务端返回限流响应时调用，使后续请求节奏逐步放缓，
  /// 最终稳定在服务端能够接受的频率附近
  void slowDown() {
    final next = _interval * 2;
    _interval = next > maxInterval ? maxInterval : next;
  }

  /// 进入冷却期
  ///
  /// 冷却期内所有请求都会被推迟
  void cooldown(Duration duration) {
    final until = DateTime.now().add(duration);
    if (_cooldownUntil == null || until.isAfter(_cooldownUntil!)) {
      _cooldownUntil = until;
    }
  }
}
