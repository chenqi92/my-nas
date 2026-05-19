import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/sync/cloud_sync_service.dart';
import 'package:my_nas/core/sync/syncable_module.dart';
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
        _statusMessage = ok ? '连接成功' : '连接失败：检查 endpoint / 用户名 / 密码';
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
        _statusMessage =
            '完成：拉取 $pulled / 推送 $pushed / 失败 $failed';
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
          '云同步',
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
              child: const Text('保存'),
            ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
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
                  '通过 WebDAV 同步',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '使用你已有的 WebDAV 服务（Nextcloud、Synology、坚果云等）跨设备同步。每个模块对应一份 JSON 文件，按 last-write-wins 合并。密码字段不会被同步。',
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
              'WebDAV 凭证',
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
              decoration: const InputDecoration(
                labelText: '用户名',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _password,
              decoration: const InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _rootPath,
              decoration: const InputDecoration(
                labelText: '根目录',
                hintText: '/my-nas-sync',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      );

  Widget _buildModulesSection(List<SyncableModule> modules, bool isDark) {
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
            '同步范围',
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
                '当前还没有模块注册到同步系统',
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
  }

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
              label: const Text('测试连接'),
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
              label: const Text('立即同步'),
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
            '本次同步详情',
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
        return '已拉取';
      case CloudSyncOutcome.pushed:
        return '已推送';
      case CloudSyncOutcome.skipped:
        return '已是最新';
      case CloudSyncOutcome.failed:
        return '失败';
    }
  }
}
