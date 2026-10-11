import 'package:flutter/material.dart';
import 'package:quick_write/core/constants/constants.dart';
import 'package:quick_write/core/services/app_info_service.dart';
import 'package:quick_write/core/utils/typography_extension.dart';
import 'package:quick_write/core/utils/url_opener.dart';
import 'package:quick_write/shared/dialogs/update_dialog.dart';
import 'package:quick_write/shared/widgets/widgets.dart';

/// 关于页面
///
/// 面向开源软件的展示页：顶部应用标识与社区入口，向下依次为版本与更新、
/// 应用简介、开源许可（含全部直接依赖清单）与版权信息。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  /// 开源协议名称
  static const String _licenseName = 'GPL-3.0';

  /// 源码仓库地址
  static const String _githubUrl = 'https://github.com/yic77455/QuickWrite';

  /// 问题反馈地址（Issue）
  static const String _issuesUrl = 'https://github.com/yic77455/QuickWrite/issues';

  /// 版本发布记录地址（Releases）
  static const String _releasesUrl = 'https://github.com/yic77455/QuickWrite/releases';

/// 标识区右侧插图
  static const String _heroImage = 'assets/image/about01.png';

  /// 一句话简介
  static const String _tagline = '专注于小说创作的本地写作工具';

  /// 应用简介正文
  static const String _introduction =
      '快码字是一款面向小说创作者的本地写作工具，'
      '将作品、章节、大纲设定与码字工具集中在一处，帮助你专注地把故事写下去。'
      '所有创作数据均保存在本地，无需联网即可使用。同时提供云备份服务，可自选WebDAV平台，安全自由，无泄露风险。';

  /// 作者 / 版权归属方
  static const String _authorName = 'yic77455';

  /// 版权年份
  static const String _copyrightYear = '2026';

  /// 功能亮点：图标 + 文案
  static const List<({IconData icon, String label})> _features = [
    (icon: Icons.storage_rounded, label: '本地存储'),
    (icon: Icons.bolt_rounded, label: '长文不卡顿'),
    (icon: Icons.window_rounded, label: '多窗口并行'),
    (icon: Icons.account_tree_outlined, label: '大纲节点树'),
    (icon: Icons.cloud_sync_outlined, label: '云同步备份'),
    (icon: Icons.bar_chart_rounded, label: '码字统计'),
  ];

  /// 直接依赖的第三方组件及其许可协议
  ///
  /// 与 pubspec.yaml 中的直接依赖一一对应；间接依赖可通过
  /// "查看完整第三方许可"入口查看（由 Flutter 汇总全部已注册许可）
  static const List<({String name, String license})> _dependencies = [
    (name: 'Flutter SDK', license: 'BSD-3-Clause'),
    (name: 'flutter_localizations', license: 'BSD-3-Clause'),
    (name: 'cupertino_icons', license: 'MIT'),
    (name: 'go_router', license: 'BSD-3-Clause'),
    (name: 'window_manager', license: 'MIT'),
    (name: 'provider', license: 'MIT'),
    (name: 'flutter_reorderable_grid_view', license: 'BSD-3-Clause'),
    (name: 'path_provider', license: 'BSD-3-Clause'),
    (name: 'isar', license: 'Apache-2.0'),
    (name: 'isar_flutter_libs', license: 'Apache-2.0'),
    (name: 'shared_preferences', license: 'BSD-3-Clause'),
    (name: 'uuid', license: 'MIT'),
    (name: 'screen_retriever', license: 'MIT'),
    (name: 'desktop_multi_window', license: 'Apache-2.0'),
    (name: 'file_picker', license: 'MIT'),
    (name: 'docx_to_text', license: 'MIT'),
    (name: 'path', license: 'BSD-3-Clause'),
    (name: 'archive', license: 'MIT'),
    (name: 'flutter_colorpicker', license: 'MIT'),
    (name: 'webdav_client', license: 'BSD-3-Clause'),
    (name: 'flutter_secure_storage', license: 'BSD-3-Clause'),
    (name: 'crypto', license: 'BSD-3-Clause'),
    (name: 'dio', license: 'MIT'),
    (name: 'ffi', license: 'BSD-3-Clause'),
    (name: 're_editor', license: 'MIT'),
    (name: 'flutter_launcher_icons', license: 'MIT'),
    (name: 'tray_manager', license: 'MIT'),
    (name: 'package_info_plus', license: 'BSD-3-Clause'),
  ];

  // =========================================================
  // 页面主体
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 48),
      children: [
        _buildHero(context),
        const SizedBox(height: 40),

        _buildSection(context, '版本与更新', _buildVersion(context)),
        const SizedBox(height: 36),

        _buildSection(context, '关于本应用', _buildIntroduction(context)),
        const SizedBox(height: 36),

        _buildSection(context, '开源许可', _buildLicense(context)),
        const SizedBox(height: 40),

        _buildFooter(context),
      ],
    );
  }

  // =========================================================
  // 顶部应用标识区
  // =========================================================

  /// 应用标识区：内容整体居中，右上叠加装饰插图
  Widget _buildHero(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 顶部主色光晕，为标识区增加视觉重量
          Positioned(
            top: -90,
            left: -40,
            right: -40,
            height: 260,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    colorScheme.primary.withValues(alpha: 0.18),
                    colorScheme.primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // 右侧插图：叠在面板之上，不参与内容排布，因此不影响原有布局
          Positioned(
            right: 28,
            top: 0,
            bottom: 0,
            width: 500,
            child: IgnorePointer(
              child: Center(
                child: Image.asset(_heroImage, fit: BoxFit.contain),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: _buildHeroInfo(context),
          ),
        ],
      ),
    );
  }

  /// 标识区内容：图标、名称、版本信息、一句话简介与社区入口按钮
  Widget _buildHeroInfo(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // 应用图标
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: Image.asset(_appIconAsset(context), width: 54, height: 54, fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: 20),

        // 应用名称
        Text(
          GlobalConstants.appTitle,
          style: context.headlineMedium?.copyWith(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 14),

        // 版本 / 协议 / 平台 标识
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            _buildMetaChip(context, 'v${AppInfoService.instance.version}', emphasized: true),
            _buildMetaChip(context, '$_licenseName 协议'),
            _buildMetaChip(context, '桌面端'),
          ],
        ),
        const SizedBox(height: 18),

        // 一句话简介
        Text(
          _tagline,
          textAlign: TextAlign.center,
          style: context.bodyLarge?.copyWith(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
            height: 1.6,
          ),
        ),
        const SizedBox(height: 24),

        // 社区入口：源码仓库与问题反馈
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: () => _openLink(context, _githubUrl, '项目地址'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
              icon: const Icon(Icons.code_rounded, size: 18),
              label: const Text('项目地址'),
            ),
            OutlinedButton.icon(
              onPressed: () => _openLink(context, _issuesUrl, '反馈建议'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
              icon: const Icon(Icons.forum_outlined, size: 18),
              label: const Text('反馈建议'),
            ),
          ],
        ),
      ],
    );
  }

  /// 标识区的小型信息标签
  Widget _buildMetaChip(BuildContext context, String text, {bool emphasized = false}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: emphasized
            ? colorScheme.primary.withValues(alpha: 0.12)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: context.labelMedium?.copyWith(
          fontSize: 11,
          color: emphasized ? colorScheme.primary : colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // =========================================================
  // 关于本应用
  // =========================================================

  /// 应用简介与功能亮点
  Widget _buildIntroduction(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 简介正文
        Text(
          _introduction,
          style: context.bodyLarge?.copyWith(
            height: 1.9,
            color: colorScheme.onSurface.withValues(alpha: 0.82),
          ),
        ),
        const SizedBox(height: 20),
        // 功能亮点
        Wrap(
          spacing: 22,
          runSpacing: 12,
          children: [
            for (final feature in _features)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(feature.icon, size: 17, color: colorScheme.primary),
                  const SizedBox(width: 7),
                  Text(
                    feature.label,
                    style: context.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  // =========================================================
  // 开源许可
  // =========================================================

  /// 开源协议说明、全部直接依赖清单与完整许可入口
  Widget _buildLicense(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 协议说明
        Text(
          '本项目基于 $_licenseName 协议开源，你可以自由地使用、修改与分发，'
          '但基于本项目的衍生作品须以相同协议开源，并保留原始版权声明。'
          '软件按“原样”提供，不附带任何明示或暗示的担保。',
          style: context.bodyMedium?.copyWith(
            height: 1.8,
            color: colorScheme.onSurface.withValues(alpha: 0.82),
          ),
        ),
        const SizedBox(height: 20),

        // 直接依赖清单
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final dependency in _dependencies) _buildDependencyCard(context, dependency),
          ],
        ),
        const SizedBox(height: 14),

        // 完整许可入口：覆盖间接依赖在内的全部第三方许可
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _showFullLicense(context),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
            icon: const Icon(Icons.receipt_long_outlined, size: 16),
            label: const Text('查看完整第三方许可'),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '上方为直接依赖，完整清单还包含全部间接依赖。',
          style: context.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
        ),
      ],
    );
  }

  /// 单个依赖条目：组件名与许可协议标签
  Widget _buildDependencyCard(BuildContext context, ({String name, String license}) dependency) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 210,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              dependency.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          // 许可协议标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              dependency.license,
              style: context.labelSmall?.copyWith(fontSize: 10, color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // 版本与更新
  // =========================================================

  /// 当前版本展示与更新检查、历史版本入口
  Widget _buildVersion(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 当前版本与检查更新
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前版本',
                    style: context.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'v${AppInfoService.instance.version}',
                    style: context.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const Spacer(),
              // 检查更新：向 GitHub 查询最新版本
              OutlinedButton.icon(
                onPressed: () => UpdateDialog.show(context, currentVersion: AppInfoService.instance.version),
                icon: const Icon(Icons.autorenew, size: 16),
                label: const Text('检查更新'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // 历史版本记录入口
        TextButton.icon(
          onPressed: () => _openLink(context, _releasesUrl, '版本发布页'),
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
          icon: const Icon(Icons.history_rounded, size: 16),
          label: const Text('查看历史版本记录'),
        ),
      ],
    );
  }

  // =========================================================
  // 版式辅助
  // =========================================================

  /// 分组标题：标题文字 + 向右延伸的细分隔线
  Widget _buildSection(BuildContext context, String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, title),
        const SizedBox(height: 18),
        child,
      ],
    );
  }

  /// 分组标题行
  Widget _buildSectionTitle(BuildContext context, String title) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Text(
          title,
          style: context.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.4),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Container(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ],
    );
  }

  /// 页面底部版权信息
  Widget _buildFooter(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final footerStyle = context.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
    );

    return Column(
      children: [
        Text('© $_copyrightYear $_authorName · 保留所有权利', style: footerStyle),
        const SizedBox(height: 6),
        Text('本软件基于 $_licenseName 协议开源', style: footerStyle),
      ],
    );
  }

  // =========================================================
  // 交互操作
  // =========================================================

  /// 根据当前主题亮度返回应用图标资源路径
  String _appIconAsset(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? 'assets/icon/icon2.png'
        : 'assets/icon/icon1.png';
  }

  /// 在系统浏览器中打开指定链接
  Future<void> _openLink(BuildContext context, String url, String label) async {
    final success = await UrlOpener.open(url);
    if (!context.mounted) return;
    SnackBarService.show(context, success ? '已在浏览器中打开$label' : '打开链接失败：$url');
  }

  /// 展示由 Flutter 收集的完整第三方许可清单
  void _showFullLicense(BuildContext context) {
    showLicensePage(
      context: context,
      applicationName: GlobalConstants.appTitle,
      applicationVersion: AppInfoService.instance.version,
      applicationLegalese: '© $_copyrightYear $_authorName\n本软件基于 $_licenseName 协议开源',
      applicationIcon: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Image.asset(_appIconAsset(context), width: 48, height: 48, fit: BoxFit.contain),
      ),
    );
  }
}