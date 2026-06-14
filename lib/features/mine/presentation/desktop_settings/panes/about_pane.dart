import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/shared/services/update_service.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';
import 'package:my_nas/shared/widgets/update_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 设置 › 关于 详情 pane（桌面）。
///
/// 迁移自设计稿 `settings_panes.jsx` 的 `PaneAbout`：版本信息、应用内更新、
/// 开源许可。版本通过 [PackageInfo] 读取；检查更新复用 [UpdateService] 单例
/// 与 [showUpdateDialog]；许可证用 Flutter 内置 [showLicensePage]。外壳负责
/// 滚动与 padding，故本 widget 不包 Scaffold / AppBar / SingleChildScrollView。
class AboutPane extends ConsumerStatefulWidget {
  const AboutPane({super.key});

  @override
  ConsumerState<AboutPane> createState() => _AboutPaneState();
}

class _AboutPaneState extends ConsumerState<AboutPane> {
  final _service = UpdateService();

  String _version = '…';
  String _buildNumber = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadVersion());
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = info.version;
        _buildNumber = info.buildNumber;
      });
    }
  }

  Future<void> _checkForUpdates() async {
    if (_checking) return;
    setState(() => _checking = true);
    final messenger = ScaffoldMessenger.of(context);
    await _service.checkForUpdates();
    if (!mounted) return;
    setState(() => _checking = false);

    if (_service.status == UpdateStatus.available &&
        _service.updateInfo != null) {
      await showUpdateDialog(context, _service.updateInfo!);
    } else if (_service.status == UpdateStatus.notAvailable) {
      messenger.showSnackBar(
        const SnackBar(content: Text('当前已是最新版本')),
      );
    } else if (_service.status == UpdateStatus.error) {
      messenger.showSnackBar(
        SnackBar(content: Text('检查更新失败：${_service.errorMessage}')),
      );
    }
  }

  void _showLicenses() {
    showLicensePage(
      context: context,
      applicationName: 'MyNAS',
      applicationVersion: _buildNumber.isNotEmpty
          ? '$_version ($_buildNumber)'
          : _version,
      applicationLegalese:
          '© 2024 MyNAS\n\n本应用使用了 Flutter 及众多开源组件，完整的第三方许可信息见下方列表。',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final versionText =
        _buildNumber.isNotEmpty ? 'v$_version ($_buildNumber)' : 'v$_version';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SetHead(
          icon: Icons.info_outline_rounded,
          title: '关于',
          subtitle: '版本信息、更新与开源许可。',
        ),
        SetSection(
          title: '应用',
          children: [
            SetRow(
              title: 'MyNAS',
              desc: '桌面端 · macOS / Windows / Linux',
              trailing: Text(
                versionText,
                style: TextStyle(
                  fontSize: 12.5,
                  fontFamily: 'monospace',
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: t.text2,
                ),
              ),
            ),
            SetRow(
              title: '应用更新',
              desc: '检查并在应用内下载新版本',
              trailing: AppButton(
                label: _checking ? '检查中…' : '检查更新',
                icon: Icons.refresh_rounded,
                dense: true,
                onPressed: _checking ? null : _checkForUpdates,
              ),
            ),
            SetRow(
              title: '开源许可证',
              desc: '第三方组件与许可',
              last: true,
              trailing: AppButton(
                label: '查看',
                dense: true,
                onPressed: _showLicenses,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
