import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:quick_write/core/services/cloud_sync/sync_models.dart';

/// 远端存储平台类型
///
/// 同步流程本身与协议无关，仅通过 [RemoteStorage] 抽象访问云端；
/// 具体协议由该枚举区分，界面据此展示不同的连接参数
enum RemoteStorageKind {
  /// WebDAV 协议的网盘（坚果云、Nextcloud 等）
  webDav('webdav', 'WebDAV'),

  /// S3 协议的对象存储（AWS S3、Cloudflare R2、MinIO 等）
  s3('s3', 'S3');

  const RemoteStorageKind(this.id, this.label);

  /// 持久化标识
  final String id;

  /// 界面显示名称
  final String label;

  /// 由持久化标识还原平台类型，无法识别时按 WebDAV 处理
  static RemoteStorageKind fromId(String? id) {
    for (final kind in values) {
      if (kind.id == id) return kind;
    }
    return webDav;
  }
}

/// 坚果云 WebDAV 服务的主机名
const String kJianguoyunHost = 'jianguoyun.com';

/// 判断服务器地址是否指向坚果云
///
/// 坚果云对每 30 分钟内的 WebDAV 请求次数有严格限制，逐章上传会迅速耗尽配额，
/// 因此只有该平台需要把章节合并为归档包上传；其他平台没有该限制，
/// 逐章上传可以避免「改一章要重传整包」的流量浪费
bool isJianguoyunHost(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return false;
  final host = uri.host.toLowerCase();
  return host == kJianguoyunHost || host.endsWith('.$kJianguoyunHost');
}

/// 云同步连接配置
///
/// 同时承载 WebDAV 与 S3 两种协议的连接参数，字段按语义复用：
/// [endpoint] 在 WebDAV 下是服务器地址、在 S3 下是服务端点；
/// [account] 在 WebDAV 下是登录账号、在 S3 下是 Access Key；
/// [secret] 在 WebDAV 下是登录密码、在 S3 下是 Secret Key
class CloudConnectionConfig {
  /// 存储平台
  final RemoteStorageKind kind;

  /// 服务地址（WebDAV 服务器地址 / S3 服务端点）
  final String endpoint;

  /// 账号（WebDAV 账号 / S3 Access Key）
  final String account;

  /// 密钥（WebDAV 密码 / S3 Secret Key）
  final String secret;

  /// 远端目录（S3 下作为对象键前缀）
  final String remoteDir;

  /// S3 区域
  final String region;

  /// S3 存储桶
  final String bucket;

  /// S3 是否使用路径风格访问（MinIO 等自建服务通常需要）
  final bool pathStyle;

  const CloudConnectionConfig({
    required this.kind,
    required this.endpoint,
    required this.account,
    required this.secret,
    required this.remoteDir,
    this.region = 'cn-east-1',
    this.bucket = '',
    this.pathStyle = false,
  });

  /// 是否把章节合并为归档包上传
  ///
  /// 仅坚果云需要：归档包用一次请求传输上百章，可成数量级地节省请求配额。
  /// 其他平台没有请求次数限制，逐章上传可以让每次同步只传输改动的章节
  bool get packsChapters =>
      kind == RemoteStorageKind.webDav && isJianguoyunHost(endpoint);

  /// 平台识别结果的可读名称，用于界面提示当前采用的传输策略
  String get platformLabel {
    if (kind == RemoteStorageKind.s3) return 'S3 对象存储';
    return isJianguoyunHost(endpoint) ? '坚果云' : '通用 WebDAV';
  }
}

/// 远端存储抽象
///
/// 同步引擎只依赖该接口，因此 WebDAV 与 S3 可以共用同一套比对、传输与冲突处理逻辑。
/// 实现方需要保证：
/// - [remotePathOf] 返回的是「可直接用于本协议请求」的完整路径
/// - [listFilesRecursive] 返回的逻辑键相对于 [remoteDir]，且跳过内部目录与临时文件
/// - 删除文件在目标不存在时视为成功，便于重试
abstract class RemoteStorage {
  /// 远端同步根目录（已规范化，无首尾斜杠）
  String get remoteDir;

  /// 将逻辑键转换为远端完整路径
  String remotePathOf(String key);

  /// 测试与远端的连通性（地址、凭据、存储桶是否可用）
  Future<void> ping();

  /// 确保远端目录存在
  ///
  /// 对象存储没有目录概念，实现方可以留空
  Future<void> ensureDirectory(String path);

  /// 清除已创建目录的缓存
  void resetDirectoryCache();

  /// 递归列出远端同步目录下的全部文件
  Future<List<RemoteSyncFile>> listFilesRecursive();

  /// 上传本地文件到远端
  Future<void> uploadFile(String localPath, String remotePath);

  /// 上传内存中的字节数据到远端
  Future<void> uploadBytes(Uint8List bytes, String remotePath);

  /// 下载远端文件到内存
  Future<Uint8List> downloadBytes(String remotePath);

  /// 下载远端文件到内存，文件不存在时返回 null
  Future<Uint8List?> downloadBytesIfExists(String remotePath);

  /// 下载远端文件到本地指定路径
  Future<void> downloadFile(String remotePath, String localPath);

  /// 列出远端指定目录下的直接文件名
  Future<List<String>> listFileNames(String remotePath);

  /// 列出远端指定目录下的子目录名
  Future<List<String>> listDirectoryNames(String remotePath);

  /// 移动远端文件
  Future<void> moveFile(String fromPath, String toPath, {bool overwrite});

  /// 删除远端文件
  Future<void> deleteFile(String remotePath);

  /// 递归删除远端目录
  Future<void> deleteDirectoryRecursive(String remotePath);

  /// 清空远端目录内的全部内容，保留目录本身
  Future<void> clearDirectory(String remotePath);

  /// 读取远端文件属性
  Future<RemoteSyncFile> fileInfo(String key);

  /// 判断远端文件是否存在
  Future<bool> exists(String key);

  /// 释放底层连接资源
  void dispose();
}

/// 判断异常是否由服务端请求频率限制引起
bool isRemoteRateLimitError(Object error) {
  if (error is! DioException) return false;
  final status = error.response?.statusCode;
  return status == 429 || status == 503;
}

/// 将远端通信过程中的异常转换为便于用户理解的提示文本
String describeRemoteError(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status == 401) return '认证失败，请检查账号与密码';
    if (status == 403) return '没有访问权限，请检查账号权限或密钥是否正确';
    if (status == 404) return '服务器地址或远端目录不存在';
    if (status == 429 || status == 503) return '服务端请求过于频繁，请稍后再试';
    if (status != null) return '服务器返回错误（HTTP $status）';
    // 未收到响应时通常是网络异常或请求超时
    return '无法连接到服务器，请检查网络与服务器地址';
  }
  return error.toString();
}
