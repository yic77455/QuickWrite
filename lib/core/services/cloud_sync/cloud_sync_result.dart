/// 云同步操作结果
///
/// 用于承载一次云同步相关操作（连接测试、建立连接等）的执行结果，
/// 供界面层统一展示提示信息
class CloudSyncResult {
  /// 操作是否成功
  final bool success;

  /// 结果提示信息
  final String message;

  const CloudSyncResult._(this.success, this.message);

  /// 成功结果
  const CloudSyncResult.success(String message) : this._(true, message);

  /// 失败结果
  const CloudSyncResult.failure(String message) : this._(false, message);
}
