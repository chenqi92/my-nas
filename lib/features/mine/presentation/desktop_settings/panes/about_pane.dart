import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/l10n/app_localizations.dart';
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
    final l = AppLocalizations.of(context);
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
        SnackBar(content: Text(l.paneAboutUpToDate)),
      );
    } else if (_service.status == UpdateStatus.error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.paneAboutCheckFailed(_service.errorMessage ?? '')),
        ),
      );
    }
  }

  void _showLicenses() {
    final l = AppLocalizations.of(context);
    showLicensePage(
      context: context,
      applicationName: 'MyNAS',
      applicationVersion: _buildNumber.isNotEmpty
          ? '$_version ($_buildNumber)'
          : _version,
      applicationIcon: Padding(
        padding: const EdgeInsets.all(8),
        child: Image.asset('assets/logo.png', width: 64, height: 64),
      ),
      applicationLegalese: l.paneAboutLegalese,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    final versionText =
        _buildNumber.isNotEmpty ? 'v$_version ($_buildNumber)' : 'v$_version';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetHead(
          icon: Icons.info_outline_rounded,
          title: l.paneAboutTitle,
          subtitle: l.paneAboutSubtitle,
        ),
        SetSection(
          title: l.paneAboutSectionApp,
          children: [
            SetRow(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/logo.png',
                  width: 34,
                  height: 34,
                  fit: BoxFit.cover,
                ),
              ),
              title: 'MyNAS',
              desc: l.paneAboutAppDesc,
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
              title: l.paneAboutUpdateTitle,
              desc: l.paneAboutUpdateDesc,
              trailing: AppButton(
                label: _checking ? l.paneAboutChecking : l.paneAboutCheckUpdate,
                icon: Icons.refresh_rounded,
                dense: true,
                onPressed: _checking ? null : _checkForUpdates,
              ),
            ),
            SetRow(
              title: l.paneAboutLicenseTitle,
              desc: l.paneAboutLicenseDesc,
              last: true,
              trailing: AppButton(
                label: l.paneAboutLicenseView,
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
