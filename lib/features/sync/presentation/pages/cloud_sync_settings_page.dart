import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/sync/cloud_sync_service.dart';
import 'package:my_nas/core/sync/syncable_module.dart';
import 'package:my_nas/shared/providers/cloud_sync_auto_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

/// 云同步设置页（WebDAV）：配置后端凭证 + 选择要同步的模块 + 手动触发同步。
class CloudSyncSettingsPage extends ConsumerStatefulWidget {
  const CloudSyncSettingsPage({super.key});

  @override
  ConsumerState<CloudSyncSettingsPage> createState() =>
      _CloudSyncSettingsPageState();
}

class _CloudSyncSettingsPageState
    extends ConsumerState<CloudSyncSettingsPage> {
  final _service = CloudSyncService.instance;

  late TextEditingController _endpoint;
  late TextEditingController _username;
  late TextEditingController _password;
  late TextEditingController _rootPath;

  Set<String> _enabled = {};
  bool _loaded = false;

  /// 桌面分支专用的纯 UI 门控（对应设计稿 PaneSync 的 `useState` on/off）：
  /// 仅控制后端 / 同步范围卡片的 opacity 与 pointerEvents，不写入任何业务状态。
  /// 不影响移动端，也不改 provider / settings。
  bool _desktopSyncOn = true;
  bool _testingConnection = false;
  bool _syncing = false;
  String? _statusMessage;
  List<CloudSyncReport>? _lastReports;

  @override
  void initState() {
    super.initState();
    _endpoint = TextEditingController();
    _username = TextEditingController();
    _password = TextEditingController();
    _rootPath = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _username.dispose();
    _password.dispose();
    _rootPath.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _service.init();
    final s = _service.settings;
    _endpoint.text = s.endpoint ?? '';
    _username.text = s.username ?? '';
    _password.text = s.password ?? '';
    _rootPath.text = s.rootPath;
    _enabled = Set<String>.from(s.enabledModuleKeys);
    _desktopSyncOn = s.isConfigured;
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _saveSettings() async {
    await _service.applySettings(
      _service.settings.copyWith(
        endpoint: _endpoint.text.trim().isEmpty ? null : _endpoint.text.trim(),
        username: _username.text.trim().isEmpty ? null : _username.text.trim(),
        password: _password.text.trim().isEmpty ? null : _password.text.trim(),
        rootPath: _rootPath.text.trim().isEmpty
            ? '/my-nas-sync'
            : _rootPath.text.trim(),
        enabledModuleKeys: _enabled,
      ),
    );
  }

  Future<void> _test() async {
    await _saveSettings();
    setState(() {
      _testingConnection = true;
      _statusMessage = null;
    });
    final ok = await _service.testConnection();
    if (mounted) {
      setState(() {
        _testingConnection = false;
        _statusMessage = ok ? context.l10n.syncSettingsTestSuccess : context.l10n.syncSettingsTestFailure;
      });
    }
  }

  Future<void> _sync() async {
    await _saveSettings();
    setState(() {
      _syncing = true;
      _statusMessage = null;
      _lastReports = null;
    });
    final reports = await _service.syncNow();
    if (mounted) {
      setState(() {
        _syncing = false;
        _lastReports = reports;
        final pulled =
            reports.where((r) => r.outcome == CloudSyncOutcome.pulled).length;
        final pushed =
            reports.where((r) => r.outcome == CloudSyncOutcome.pushed).length;
        final failed =
            reports.where((r) => r.outcome == CloudSyncOutcome.failed).length;
        _statusMessage = context.l10n.syncSettingsSyncComplete(pulled, pushed, failed);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final modules = CloudSyncRegistry.instance.modules;
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      appBar: AppBar(
        leading: const RoundedBackButton(),
        backgroundColor: isDark ? AppColors.darkSurface : null,
        title: Text(
          context.l10n.syncSettingsPageTitle,
          style: TextStyle(
            color: isDark ? AppColors.darkOnSurface : null,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: IconThemeData(
          color: isDark ? AppColors.darkOnSurface : null,
        ),
        actions: [
          if (_loaded)
            TextButton(
              onPressed: _saveSettings,
              child: Text(context.l10n.syncSettingsSaveButton),
            ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : context.isDesktopLayout
              ? _buildDesktopBody(modules)
              : ListView(
                  padding: AppSpacing.paddingMd,
                  children: [
                    _buildIntro(isDark),
                    const SizedBox(height: AppSpacing.lg),
                    _buildBackendSection(isDark),
                    const SizedBox(height: AppSpacing.lg),
                    _buildModulesSection(modules, isDark),
                    const SizedBox(height: AppSpacing.lg),
                    _buildActions(),
                    if (_statusMessage != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _buildStatus(isDark),
                    ],
                    if (_lastReports != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _buildReports(isDark),
                    ],
                  ],
                ),
    );
  }

  // ===================== 桌面端分支（macOS 风设计语言） =====================
  //
  // 复用与移动端完全相同的 controller / state / 回调（_endpoint、_username、
  // _password、_rootPath、_enabled、_test、_testingConnection、_statusMessage、
  // _lastReports），仅替换呈现层为 design atoms。

  Widget _buildDesktopBody(List<SyncableModule> modules) =>
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(38, 32, 38, 96),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SetHead(
                  icon: Icons.sync_rounded,
                  title: context.l10n.syncSettingsPageTitle,
                  subtitle: context.l10n.syncSettingsDesktopSubtitle,
                ),
                _buildDesktopBackendSection(),
                _buildGated(
                  on: _desktopSyncOn,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildDesktopModulesSection(modules),
                      const SizedBox(height: 22),
                      _buildDesktopAutomationSection(),
                      if (_lastReports != null) ...[
                        const SizedBox(height: 14),
                        _buildReports(
                          Theme.of(context).brightness == Brightness.dark,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  /// 纯 UI 门控包装：off 时降透明度并屏蔽交互，不动任何业务状态。
  Widget _buildGated({required bool on, required Widget child}) =>
      AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: on ? 1 : 0.45,
        child: IgnorePointer(ignoring: !on, child: child),
      );

  Widget _buildDesktopBackendSection() => SetSection(
      title: context.l10n.syncSettingsBackendSection,
      hint: 'cloud_sync_settings',
      children: [
        SetRow(
          title: context.l10n.syncSettingsEnableTitle,
          trailing: AppSwitch(
            value: _desktopSyncOn,
            onChanged: (v) => setState(() => _desktopSyncOn = v),
          ),
        ),
        _buildGated(
          on: _desktopSyncOn,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDesktopField(
                        label: 'Endpoint', controller: _endpoint),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildDesktopField(
                              label: context.l10n.syncSettingsUsernameLabel, controller: _username),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _buildDesktopField(
                            label: context.l10n.syncSettingsPasswordLabel,
                            controller: _password,
                            obscure: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildDesktopField(label: context.l10n.syncSettingsRootPathLabel, controller: _rootPath),
                  ],
                ),
              ),
              _buildDesktopConnectionRow(),
            ],
          ),
        ),
      ],
    );

  Widget _buildDesktopField({
    required String label,
    required TextEditingController controller,
    bool obscure = false,
  }) {
    final t = DesignTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: t.text1,
            ),
          ),
        ),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: TextStyle(fontSize: 13.5, color: t.text0),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: t.insetBg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: t.hairline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: t.accent.withValues(alpha: 0.5)),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: t.hairline),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopConnectionRow() {
    final t = DesignTokens.of(context);
    return SetRow(
      title: context.l10n.syncSettingsConnectionStatus,
      last: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const StatusDot(DotStatus.ok),
          const SizedBox(width: 8),
          Text(
            _statusMessage ?? context.l10n.syncSettingsConnectionHealthy,
            style: TextStyle(fontSize: 12, color: t.text2),
          ),
          const SizedBox(width: 12),
          AppButton(
            label: _testingConnection ? context.l10n.syncSettingsTestingButton : context.l10n.syncSettingsTestButton,
            icon: Icons.link_rounded,
            dense: true,
            onPressed: _testingConnection ? null : _test,
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopModulesSection(List<SyncableModule> modules) {
    if (modules.isEmpty) {
      return SetSection(
        title: '同步范围',
        hint: '按模块开关',
        bottomMargin: false,
        children: const [
          SetRow(title: '当前还没有模块注册到同步系统', last: true),
        ],
      );
    }
    return SetSection(
      title: context.l10n.syncSettingsModulesSection,
      hint: context.l10n.syncSettingsModulesHint,
      bottomMargin: false,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: LayoutBuilder(
            builder: (context, c) {
              const gap = 10.0;
              const minTile = 212.0;
              var cols = ((c.maxWidth + gap) / (minTile + gap)).floor();
              if (cols < 1) cols = 1;
              final tileW = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final m in modules)
                    SizedBox(
                      width: tileW,
                      child: _buildModuleTile(m),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildModuleTile(SyncableModule m) {
    final t = DesignTokens.of(context);
    final on = _enabled.contains(m.key);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.cardBg,
        border: Border.all(color: t.cardBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: t.insetBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_moduleIcon(m.key), size: 15, color: t.accentBright),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: t.text0,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  m.key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: t.text2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 11),
          AppSwitch(
            value: on,
            onChanged: (v) {
              setState(() {
                if (v) {
                  _enabled.add(m.key);
                } else {
                  _enabled.remove(m.key);
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopAutomationSection() {
    final autoOn = ref.watch(cloudSyncAutoEnabledProvider);
    final interval = ref.watch(cloudSyncIntervalProvider);
    return SetSection(
      title: context.l10n.syncSettingsAutomationSection,
      hint: 'cloud_sync',
      bottomMargin: false,
      children: [
        SetRow(
          title: context.l10n.syncSettingsAutoSyncTitle,
          desc: context.l10n.syncSettingsAutoSyncDesc,
          trailing: AppSwitch(
            value: autoOn,
            onChanged: (v) => ref
                .read(cloudSyncAutoEnabledProvider.notifier)
                .setEnabled(enabled: v),
          ),
        ),
        _buildGated(
          on: autoOn,
          child: SetRow(
            title: context.l10n.syncSettingsIntervalTitle,
            desc: context.l10n.syncSettingsIntervalDesc,
            trailing: AppSegmented<int>(
              value: interval,
              options: [
                AppSegmentedOption(value: 15, label: context.l10n.syncSettingsInterval15),
                AppSegmentedOption(value: 30, label: context.l10n.syncSettingsInterval30),
                AppSegmentedOption(value: 60, label: context.l10n.syncSettingsInterval60),
                AppSegmentedOption(value: 360, label: context.l10n.syncSettingsInterval360),
              ],
              onChanged: (v) =>
                  ref.read(cloudSyncIntervalProvider.notifier).setMinutes(v),
            ),
          ),
        ),
        SetRow(
          title: context.l10n.syncSettingsSyncNowTitle,
          desc: context.l10n.syncSettingsSyncNowDesc,
          last: true,
          trailing: AppButton(
            label: _syncing ? context.l10n.syncSettingsSyncingButton : context.l10n.syncSettingsSyncNowButton,
            icon: Icons.sync_rounded,
            variant: AppButtonVariant.primary,
            onPressed: _syncing ? null : _sync,
          ),
        ),
      ],
    );
  }

  IconData _moduleIcon(String key) {
    final k = key.toLowerCase();
    if (k.contains('favorite') || k.contains('like')) {
      return Icons.favorite_rounded;
    }
    if (k.contains('playlist') || k.contains('music')) {
      return Icons.music_note_rounded;
    }
    if (k.contains('setting') || k.contains('pref') || k.contains('config')) {
      return Icons.settings_rounded;
    }
    if (k.contains('video') || k.contains('film') || k.contains('movie')) {
      return Icons.movie_rounded;
    }
    if (k.contains('read') || k.contains('book')) {
      return Icons.menu_book_rounded;
    }
    if (k.contains('note') || k.contains('todo')) {
      return Icons.sticky_note_2_rounded;
    }
    if (k.contains('stat') || k.contains('history')) {
      return Icons.bar_chart_rounded;
    }
    return Icons.cloud_sync_rounded;
  }

  Widget _buildIntro(bool isDark) => Container(
        padding: AppSpacing.paddingMd,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_sync_rounded,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  context.l10n.syncSettingsIntroTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.syncSettingsIntroDesc,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black87,
                height: 1.5,
              ),
            ),
          ],
        ),
      );

  Widget _buildBackendSection(bool isDark) => Container(
        padding: AppSpacing.paddingMd,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.syncSettingsCredentialsSection,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _endpoint,
              decoration: const InputDecoration(
                labelText: 'Endpoint',
                hintText: 'https://nas.example.com/dav',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _username,
              decoration: InputDecoration(
                labelText: context.l10n.syncSettingsUsernameLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _password,
              decoration: InputDecoration(
                labelText: context.l10n.syncSettingsPasswordLabel,
                border: const OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _rootPath,
              decoration: InputDecoration(
                labelText: context.l10n.syncSettingsRootPathLabel,
                hintText: '/my-nas-sync',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      );

  Widget _buildModulesSection(List<SyncableModule> modules, bool isDark) => Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.syncSettingsModulesSection,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          if (modules.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                context.l10n.syncSettingsNoModules,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            )
          else
            for (final m in modules)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(m.displayName),
                subtitle: Text(
                  m.key,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                value: _enabled.contains(m.key),
                onChanged: (v) {
                  setState(() {
                    if (v ?? false) {
                      _enabled.add(m.key);
                    } else {
                      _enabled.remove(m.key);
                    }
                  });
                },
              ),
        ],
      ),
    );

  Widget _buildActions() => Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _testingConnection ? null : _test,
              icon: _testingConnection
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.network_check_rounded),
              label: Text(context.l10n.syncSettingsTestButton),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: _syncing ? null : _sync,
              icon: _syncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync_rounded),
              label: Text(context.l10n.syncSettingsSyncNowButton),
            ),
          ),
        ],
      );

  Widget _buildStatus(bool isDark) => Container(
        padding: AppSpacing.paddingMd,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _statusMessage!,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      );

  Widget _buildReports(bool isDark) {
    final reports = _lastReports!;
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.syncSettingsSyncDetails,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          for (final r in reports)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(_iconFor(r.outcome), size: 16, color: _colorFor(r.outcome)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r.moduleKey,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  Text(
                    _labelFor(r.outcome),
                    style: TextStyle(
                      fontSize: 11,
                      color: _colorFor(r.outcome),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconFor(CloudSyncOutcome o) {
    switch (o) {
      case CloudSyncOutcome.pulled:
        return Icons.cloud_download_rounded;
      case CloudSyncOutcome.pushed:
        return Icons.cloud_upload_rounded;
      case CloudSyncOutcome.skipped:
        return Icons.check_circle_outline_rounded;
      case CloudSyncOutcome.failed:
        return Icons.error_outline_rounded;
    }
  }

  Color _colorFor(CloudSyncOutcome o) {
    switch (o) {
      case CloudSyncOutcome.pulled:
      case CloudSyncOutcome.pushed:
        return AppColors.primary;
      case CloudSyncOutcome.skipped:
        return Colors.green;
      case CloudSyncOutcome.failed:
        return Colors.red;
    }
  }

  String _labelFor(CloudSyncOutcome o) {
    switch (o) {
      case CloudSyncOutcome.pulled:
        return context.l10n.syncSettingsOutcomePulled;
      case CloudSyncOutcome.pushed:
        return context.l10n.syncSettingsOutcomePushed;
      case CloudSyncOutcome.skipped:
        return context.l10n.syncSettingsOutcomeSkipped;
      case CloudSyncOutcome.failed:
        return context.l10n.syncSettingsOutcomeFailed;
    }
  }
}
