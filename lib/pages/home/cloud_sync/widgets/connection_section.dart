import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_write/core/providers/cloud_sync_provider.dart';
import 'package:quick_write/pages/home/cloud_sync/widgets/setting_input_tile.dart';
import 'package:quick_write/pages/home/settings/setting_widgets.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 云同步 - 服务连接分组
///
/// 提供 WebDAV 服务的连接配置：
/// - 服务提供商选择
/// - 服务器地址、账号、密码、远端目录的填写
/// - 连接测试、建立连接与断开连接操作
class ConnectionSection extends StatefulWidget {
  const ConnectionSection({super.key});

  @override
  State<ConnectionSection> createState() => _ConnectionSectionState();
}

class _ConnectionSectionState extends State<ConnectionSection> {
  // ================= 状态属性 =================

  /// 服务器地址输入控制器
  final TextEditingController _serverUrlController = TextEditingController();

  /// 账号输入控制器
  final TextEditingController _usernameController = TextEditingController();

  /// 密码输入控制器
  final TextEditingController _passwordController = TextEditingController();

  /// 远端目录输入控制器
  final TextEditingController _remoteDirController = TextEditingController(
    text: 'QuickWrite',
  );

  /// 密码是否以明文显示
  bool _obscurePassword = true;

  // ================= 生命周期 =================

  @override
  void initState() {
    super.initState();
    // 回填已保存的连接配置，便于快速重连
    final provider = context.read<CloudSyncProvider>();
    _serverUrlController.text = provider.serverUrl;
    _usernameController.text = provider.username;
    if (provider.remoteDir.isNotEmpty) {
      _remoteDirController.text = provider.remoteDir;
    }
  }

  @override
  void dispose() {
    // 释放输入控制器，避免内存泄漏
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _remoteDirController.dispose();
    super.dispose();
  }

  // ================= 构建界面 =================

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CloudSyncProvider>();

    return SettingSectionCard(
      title: '服务连接',
      children: [
        _buildProviderTile(),
        _buildServerUrlTile(),
        _buildUsernameTile(),
        _buildPasswordTile(),
        _buildRemoteDirTile(),
        _buildActionRow(context, provider.isConnected, provider.isBusy),
      ],
    );
  }

  /// 服务提供商：选择云同步使用的服务类型
  Widget _buildProviderTile() {
    return SettingTile(
      icon: Icons.cloud_outlined,
      title: '服务提供商',
      subtitle: '目前仅支持 WebDAV 协议的网盘服务，如坚果云',
      trailing: CustomDropdown(
        width: 140,
        value: 'webdav',
        items: const [
          DropdownItem(displayText: 'WebDAV', value: 'webdav'),
        ],
        onChanged: (_) {},
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
          _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          size: 18,
        ),
        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
      ),
    );
  }

  /// 远端目录：云端的同步数据存放目录
  Widget _buildRemoteDirTile() {
    return SettingInputTile(
      icon: Icons.folder_open_outlined,
      title: '远端目录',
      subtitle: '同步数据在网盘中的存放目录',
      controller: _remoteDirController,
      hintText: 'QuickWrite',
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

  /// 测试连接：验证服务器地址与账号密码是否可用
  Future<void> _testConnection(BuildContext context) async {
    final result = await context.read<CloudSyncProvider>().testConnection(
          serverUrl: _serverUrlController.text,
          username: _usernameController.text,
          password: _passwordController.text,
          remoteDir: _remoteDirController.text,
        );
    if (!context.mounted) return;
    SnackBarService.show(context, result.message);
  }

  /// 建立连接：保存配置并连接云服务
  Future<void> _connect(BuildContext context) async {
    final result = await context.read<CloudSyncProvider>().connect(
          serverUrl: _serverUrlController.text,
          username: _usernameController.text,
          password: _passwordController.text,
          remoteDir: _remoteDirController.text,
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
