import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/cloud_sync_provider.dart';
import 'package:quick_write/core/services/cloud_sync/remote_storage.dart';
import 'package:quick_write/core/services/cloud_sync/s3_client.dart';
import 'package:quick_write/core/utils/platform_capabilities.dart';
import 'package:quick_write/pages/home/cloud_sync/widgets/setting_input_tile.dart';
import 'package:quick_write/pages/home/settings/setting_widgets.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 云同步 - 服务连接分组
///
/// 提供云存储服务的连接配置，支持两种协议：
/// - WebDAV：坚果云等网盘
/// - S3：AWS S3、Cloudflare R2、MinIO 等对象存储
///
/// 分组内还会展示平台识别结果，说明章节将以归档包还是逐章的方式上传
class ConnectionSection extends StatefulWidget {
  const ConnectionSection({super.key});

  @override
  State<ConnectionSection> createState() => _ConnectionSectionState();
}

class _ConnectionSectionState extends State<ConnectionSection> {
  // ================= 状态属性 =================

  /// 当前选择的存储平台
  RemoteStorageKind _kind = RemoteStorageKind.webDav;

  /// WebDAV 服务器地址输入控制器
  final TextEditingController _serverUrlController = TextEditingController();

  /// WebDAV 账号输入控制器
  final TextEditingController _usernameController = TextEditingController();

  /// WebDAV 密码输入控制器
  final TextEditingController _passwordController = TextEditingController();

  /// S3 服务端点输入控制器
  final TextEditingController _s3EndpointController = TextEditingController();

  /// S3 区域输入控制器
  final TextEditingController _s3RegionController = TextEditingController(
    text: kS3DefaultRegion,
  );

  /// S3 存储桶输入控制器
  final TextEditingController _s3BucketController = TextEditingController();

  /// S3 Access Key 输入控制器
  final TextEditingController _s3AccessKeyController = TextEditingController();

  /// S3 Secret Key 输入控制器
  final TextEditingController _s3SecretKeyController = TextEditingController();

  /// 远端目录输入控制器
  final TextEditingController _remoteDirController = TextEditingController(
    text: 'QuickWrite',
  );

  /// S3 是否使用路径风格访问
  bool _s3PathStyle = false;

  /// 密码是否以明文显示
  bool _obscurePassword = true;

  /// Secret Key 是否以明文显示
  bool _obscureS3Secret = true;

  // ================= 生命周期 =================

  @override
  void initState() {
    super.initState();
    // 回填已保存的连接配置，便于快速重连
    final provider = context.read<CloudSyncProvider>();
    _kind = provider.storageKind;
    _serverUrlController.text = provider.storageKind == RemoteStorageKind.webDav
        ? provider.serverUrl
        : '';
    _s3EndpointController.text = provider.storageKind == RemoteStorageKind.s3
        ? provider.serverUrl
        : '';
    if (provider.storageKind == RemoteStorageKind.webDav) {
      _usernameController.text = provider.username;
    } else {
      _s3AccessKeyController.text = provider.username;
      _s3BucketController.text = provider.s3Bucket;
      _s3RegionController.text = provider.s3Region;
      _s3PathStyle = provider.s3PathStyle;
    }
    if (provider.remoteDir.isNotEmpty) {
      _remoteDirController.text = provider.remoteDir;
    }

    // 地址变化会改变平台识别结果（例如填入坚果云地址后章节改为打包上传），
    // 因此监听输入变化以实时刷新提示
    _serverUrlController.addListener(_onEndpointChanged);
    _s3EndpointController.addListener(_onEndpointChanged);
  }

  @override
  void dispose() {
    // 释放输入控制器，避免内存泄漏
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _s3EndpointController.dispose();
    _s3RegionController.dispose();
    _s3BucketController.dispose();
    _s3AccessKeyController.dispose();
    _s3SecretKeyController.dispose();
    _remoteDirController.dispose();
    super.dispose();
  }

  /// 地址变化后刷新平台识别提示
  void _onEndpointChanged() {
    if (mounted) setState(() {});
  }

  // ================= 构建界面 =================

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CloudSyncProvider>();
    final isWebDav = _kind == RemoteStorageKind.webDav;

    return SettingSectionCard(
      title: '服务连接',
      children: [
        _buildProviderTile(provider.isConnected),
        if (isWebDav) ...[
          _buildServerUrlTile(),
          _buildUsernameTile(),
          _buildPasswordTile(),
        ] else ...[
          _buildS3EndpointTile(),
          _buildS3RegionTile(),
          _buildS3BucketTile(),
          _buildS3AccessKeyTile(),
          _buildS3SecretKeyTile(),
          _buildS3PathStyleTile(),
        ],
        _buildRemoteDirTile(),
        _buildStrategyTile(),
        _buildActionRow(context, provider.isConnected, provider.isBusy),
      ],
    );
  }

  /// 服务提供商：选择云同步使用的协议
  Widget _buildProviderTile(bool isConnected) {
    // 移动端窄屏：下拉框换行到标题下方并占满整行
    final isMobile = PlatformCapabilities.isMobile;
    final enabled = !isConnected;

    return SettingTile(
      icon: Icons.cloud_outlined,
      title: '服务提供商',
      subtitle: isConnected
          ? '已连接，断开后可切换协议'
          : 'WebDAV 适配坚果云等网盘，S3 适配 AWS S3、R2、MinIO 等对象存储',
      trailingBelow: isMobile,
      trailing: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: IgnorePointer(
          ignoring: !enabled,
          child: CustomDropdown(
            width: isMobile ? double.infinity : 140,
            value: _kind.id,
            items: const [
              DropdownItem(displayText: 'WebDAV', value: 'webdav'),
              DropdownItem(displayText: 'S3', value: 's3'),
            ],
            onChanged: (value) =>
                setState(() => _kind = RemoteStorageKind.fromId(value)),
          ),
        ),
      ),
    );
  }

  /// 服务器地址：填写 WebDAV 服务器地址
  Widget _buildServerUrlTile() {
    return SettingInputTile(
      icon: Icons.dns_outlined,
      title: '服务器地址',
      subtitle: '以 https:// 开头的完整 WebDAV 地址',
      controller: _serverUrlController,
      hintText: 'https://dav.jianguoyun.com/dav/',
    );
  }

  /// 账号：填写 WebDAV 登录账号
  Widget _buildUsernameTile() {
    return SettingInputTile(
      icon: Icons.person_outline,
      title: '账号',
      subtitle: '坚果云为你的登录账号',
      controller: _usernameController,
      hintText: '请输入账号',
    );
  }

  /// 密码：填写 WebDAV 密码或应用密码
  Widget _buildPasswordTile() {
    return SettingInputTile(
      icon: Icons.lock_outline,
      title: '密码',
      subtitle: '坚果云请使用「安全选项」中生成的应用密码',
      controller: _passwordController,
      hintText: '请输入密码',
      obscureText: _obscurePassword,
      suffixIcon: IconButton(
        icon: Icon(
          _obscurePassword
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          size: 18,
        ),
        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
      ),
    );
  }

  /// S3 服务端点
  Widget _buildS3EndpointTile() {
    return SettingInputTile(
      icon: Icons.dns_outlined,
      title: '服务端点',
      subtitle: 'S3 兼容服务的访问地址，不要带存储桶名',
      controller: _s3EndpointController,
      hintText: 'https://s3.cn-east-1.qiniucs.com',
    );
  }

  /// S3 区域
  Widget _buildS3RegionTile() {
    return SettingInputTile(
      icon: Icons.public_outlined,
      title: '区域',
      subtitle: '存储桶所在区域，R2 填写 auto',
      controller: _s3RegionController,
      hintText: kS3DefaultRegion,
    );
  }

  /// S3 存储桶
  Widget _buildS3BucketTile() {
    return SettingInputTile(
      icon: Icons.inventory_2_outlined,
      title: '存储桶',
      subtitle: '同步数据存放的存储桶名称，需要预先创建',
      controller: _s3BucketController,
      hintText: '请输入存储桶名称',
    );
  }

  /// S3 Access Key
  Widget _buildS3AccessKeyTile() {
    return SettingInputTile(
      icon: Icons.person_outline,
      title: 'Access Key',
      subtitle: '访问密钥 ID',
      controller: _s3AccessKeyController,
      hintText: '请输入 Access Key',
    );
  }

  /// S3 Secret Key
  Widget _buildS3SecretKeyTile() {
    return SettingInputTile(
      icon: Icons.lock_outline,
      title: 'Secret Key',
      subtitle: '访问密钥，仅保存在本机的系统安全存储中',
      controller: _s3SecretKeyController,
      hintText: '请输入 Secret Key',
      obscureText: _obscureS3Secret,
      suffixIcon: IconButton(
        icon: Icon(
          _obscureS3Secret
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          size: 18,
        ),
        onPressed: () => setState(() => _obscureS3Secret = !_obscureS3Secret),
      ),
    );
  }

  /// S3 路径风格：自建服务（如 MinIO）通常需要开启
  Widget _buildS3PathStyleTile() {
    return SettingTile(
      icon: Icons.route_outlined,
      title: '路径风格访问',
      subtitle: '自建服务（如 MinIO）通常需要开启，公有云一般无需开启',
      trailing: QwSwitch(
        value: _s3PathStyle,
        onChanged: (value) => setState(() => _s3PathStyle = value),
      ),
    );
  }

  /// 远端目录：云端的同步数据存放目录
  Widget _buildRemoteDirTile() {
    return SettingInputTile(
      icon: Icons.folder_open_outlined,
      title: _kind == RemoteStorageKind.s3 ? '远端前缀' : '远端目录',
      subtitle: _kind == RemoteStorageKind.s3
          ? '同步数据在存储桶中的对象键前缀'
          : '同步数据在网盘中的存放目录',
      controller: _remoteDirController,
      hintText: 'QuickWrite',
    );
  }

  /// 平台识别结果：说明章节将以归档包还是逐章的方式上传
  Widget _buildStrategyTile() {
    final config = _formConfig;
    final packsChapters = config.packsChapters;

    return SettingTile(
      icon: Icons.info_outline,
      title: '识别结果：${config.platformLabel}',
      subtitle: packsChapters
          ? '该平台限制请求次数，章节将每 100 章打包为一个文件上传'
          : '章节将逐章上传，每次同步只传输改动过的章节',
    );
  }

  /// 底部操作按钮行：未连接时提供测试与连接，已连接时提供断开
  Widget _buildActionRow(BuildContext context, bool isConnected, bool isBusy) {
    /// 操作进行中显示的加载指示器
    const loadingIndicator = SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );

    if (isConnected) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (isBusy) ...[loadingIndicator, const SizedBox(width: 12)],
            OutlinedButton.icon(
              onPressed: isBusy ? null : () => _disconnect(context),
              icon: const Icon(Icons.link_off, size: 16),
              label: const Text('断开连接'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (isBusy) ...[loadingIndicator, const SizedBox(width: 12)],
          OutlinedButton.icon(
            onPressed: isBusy ? null : () => _testConnection(context),
            icon: const Icon(Icons.wifi_tethering, size: 16),
            label: const Text('测试连接'),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: isBusy ? null : () => _connect(context),
            icon: const Icon(Icons.link, size: 16),
            label: const Text('连接'),
          ),
        ],
      ),
    );
  }

  // ================= 操作处理 =================

  /// 由当前表单内容构造连接参数
  CloudConnectionConfig get _formConfig => CloudConnectionConfig(
    kind: _kind,
    endpoint: _kind == RemoteStorageKind.webDav
        ? _serverUrlController.text
        : _s3EndpointController.text,
    account: _kind == RemoteStorageKind.webDav
        ? _usernameController.text
        : _s3AccessKeyController.text,
    secret: _kind == RemoteStorageKind.webDav
        ? _passwordController.text
        : _s3SecretKeyController.text,
    remoteDir: _remoteDirController.text,
    region: _s3RegionController.text,
    bucket: _s3BucketController.text,
    pathStyle: _s3PathStyle,
  );

  /// 测试连接：验证地址与凭据是否可用
  Future<void> _testConnection(BuildContext context) async {
    final result = await context.read<CloudSyncProvider>().testConnection(
      _formConfig,
    );
    if (!context.mounted) return;
    SnackBarService.show(context, result.message);
  }

  /// 建立连接：保存配置并连接云服务
  Future<void> _connect(BuildContext context) async {
    final result = await context.read<CloudSyncProvider>().connect(
      _formConfig,
    );
    if (!context.mounted) return;
    SnackBarService.show(context, result.message);
  }

  /// 断开连接：清除连接状态
  void _disconnect(BuildContext context) {
    showConfirmDialog(
      context: context,
      title: '断开连接',
      description: '断开后将停止自动同步，云端数据会被保留。确定要断开连接吗？',
      type: ConfirmType.info,
      confirmText: '断开',
      cancelText: '取消',
      onConfirm: () {
        context.read<CloudSyncProvider>().disconnect();
      },
    );
  }
}
