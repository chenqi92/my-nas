import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/sync/cloud_sync_service.dart';
import 'package:my_nas/core/sync/syncable_module.dart';
import 'package:my_nas/shared/providers/cloud_sync_auto_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';

/// 设置 › 云同步 详情 pane（桌面）。
///
/// 迁移自 `CloudSyncSettingsPage` 的桌面分支：复用相同的 [CloudSyncService]
/// 与 [cloudSyncAutoEnabledProvider] / [cloudSyncIntervalProvider]，但作为
/// 独立 widget 自持 [TextEditingController] 与加载逻辑（外壳负责滚动与 padding，
/// 故本 widget 不包 Scaffold / AppBar / SingleChildScrollView）。
class SyncPane extends ConsumerStatefulWidget {
  const SyncPane({super.key});

  @override
  ConsumerState<SyncPane> createState() => _SyncPaneState();
}

class _SyncPaneState extends ConsumerState<SyncPane> {
  final _service = CloudSyncService.instance;

  late final TextEditingController _endpoint;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _rootPath;

  Set<String> _enabled = {};
  bool _loaded = false;

  /// 纯 UI 门控（对齐设计稿 PaneSync 的 on/off）：仅控制后端 / 同步范围卡片的
  /// opacity 与交互，不写入任何业务状态。
  bool _syncOn = true;
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
    _syncOn = s.isConfigured;
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
        _statusMessage = '完成：拉取 $pulled / 推送 $pushed / 失败 $failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SetHead(
            icon: Icons.sync_rounded,
            title: '云同步',
            subtitle:
                '基于 WebDAV 的跨设备同步（非云厂商专有）。冲突按 manifest 时间戳最后修改优先，失败自动重试 3 次。',
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }

    final modules = CloudSyncRegistry.instance.modules;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SetHead(
          icon: Icons.sync_rounded,
          title: '云同步',
          subtitle:
              '基于 WebDAV 的跨设备同步（非云厂商专有）。冲突按 manifest 时间戳最后修改优先，失败自动重试 3 次。',
        ),
        _buildBackendSection(),
        _gated(
          on: _syncOn,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildModulesSection(modules),
              const SizedBox(height: 22),
              _buildAutomationSection(),
              if (_lastReports != null) ...[
                const SizedBox(height: 14),
                _buildReports(isDark),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 纯 UI 门控：off 时降透明度并屏蔽交互，不动任何业务状态。
  Widget _gated({required bool on, required Widget child}) => AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: on ? 1 : 0.45,
        child: IgnorePointer(ignoring: !on, child: child),
      );

  Widget _buildBackendSection() => SetSection(
        title: 'WebDAV 后端',
        hint: 'cloud_sync_settings',
        children: [
          SetRow(
            title: '启用云同步',
            trailing: AppSwitch(
              value: _syncOn,
              onChanged: (v) => setState(() => _syncOn = v),
            ),
          ),
          _gated(
            on: _syncOn,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildField(label: 'Endpoint', controller: _endpoint),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildField(
                                label: '用户名', controller: _username),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _buildField(
                              label: '密码',
                              controller: _password,
                              obscure: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildField(label: '根目录', controller: _rootPath),
                    ],
                  ),
                ),
                _buildConnectionRow(),
              ],
            ),
          ),
        ],
      );

  Widget _buildField({
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

  Widget _buildConnectionRow() {
    final t = DesignTokens.of(context);
    return SetRow(
      title: '连接状态',
      last: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const StatusDot(DotStatus.ok),
          const SizedBox(width: 8),
          Text(
            _statusMessage ?? '已连接 · 健康检查通过',
            style: TextStyle(fontSize: 12, color: t.text2),
          ),
          const SizedBox(width: 12),
          AppButton(
            label: _testingConnection ? '测试中…' : '测试连接',
            icon: Icons.link_rounded,
            dense: true,
            onPressed: _testingConnection ? null : _test,
          ),
        ],
      ),
    );
  }

  Widget _buildModulesSection(List<SyncableModule> modules) {
    if (modules.isEmpty) {
      return const SetSection(
        title: '同步范围',
        hint: '按模块开关',
        bottomMargin: false,
        children: [
          SetRow(title: '当前还没有模块注册到同步系统', last: true),
        ],
      );
    }
    return SetSection(
      title: '同步范围',
      hint: '按模块开关',
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

  Widget _buildAutomationSection() {
    final autoOn = ref.watch(cloudSyncAutoEnabledProvider);
    final interval = ref.watch(cloudSyncIntervalProvider);
    return SetSection(
      title: '自动化',
      hint: 'cloud_sync',
      bottomMargin: false,
      children: [
        SetRow(
          title: '自动同步',
          desc: '开启后在 app 运行期间按周期自动同步（不含后台 / 系统级调度）',
          trailing: AppSwitch(
            value: autoOn,
            onChanged: (v) => ref
                .read(cloudSyncAutoEnabledProvider.notifier)
                .setEnabled(enabled: v),
          ),
        ),
        _gated(
          on: autoOn,
          child: SetRow(
            title: '同步周期',
            desc: '两次自动同步之间的最短间隔',
            trailing: AppSegmented<int>(
              value: interval,
              options: const [
                AppSegmentedOption(value: 15, label: '15 分钟'),
                AppSegmentedOption(value: 30, label: '30 分钟'),
                AppSegmentedOption(value: 60, label: '1 小时'),
                AppSegmentedOption(value: 360, label: '6 小时'),
              ],
              onChanged: (v) =>
                  ref.read(cloudSyncIntervalProvider.notifier).setMinutes(v),
            ),
          ),
        ),
        SetRow(
          title: '立即同步',
          desc: '手动触发一次全量同步',
          last: true,
          trailing: AppButton(
            label: _syncing ? '同步中…' : '立即同步',
            icon: Icons.sync_rounded,
            variant: AppButtonVariant.primary,
            onPressed: _syncing ? null : _sync,
          ),
        ),
      ],
    );
  }

  Widget _buildReports(bool isDark) {
    final t = DesignTokens.of(context);
    final reports = _lastReports!;
    return SetSection(
      title: '本次同步详情',
      bottomMargin: false,
      children: [
        for (var i = 0; i < reports.length; i++)
          SetRow(
            title: reports[i].moduleKey,
            last: i == reports.length - 1,
            leading: Icon(
              _iconFor(reports[i].outcome),
              size: 16,
              color: _colorFor(t, reports[i].outcome),
            ),
            trailing: Text(
              _labelFor(reports[i].outcome),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _colorFor(t, reports[i].outcome),
              ),
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

  Color _colorFor(DesignTokens t, CloudSyncOutcome o) {
    switch (o) {
      case CloudSyncOutcome.pulled:
      case CloudSyncOutcome.pushed:
        return t.accentBright;
      case CloudSyncOutcome.skipped:
        return t.ok;
      case CloudSyncOutcome.failed:
        return t.err;
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
