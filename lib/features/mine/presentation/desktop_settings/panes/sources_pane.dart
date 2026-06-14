import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/sources/data/services/network_discovery_service.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/source_form_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/shared/providers/source_defaults_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';
import 'package:my_nas/shared/widgets/dialogs/source_wizard_dialog.dart';

/// 桌面「设置 · 数据源」详情 pane（设计稿 `settings.jsx` PaneSources）。
///
/// 已连接源列表来自真实 [sourcesProvider]，连接态来自 [activeConnectionsProvider]，
/// 库映射从 [mediaLibraryConfigProvider] 派生。每行提供 测试连接 / 编辑 / 重新连接 /
/// 删除（级联）。「添加源」打开 [SourceWizardDialog]。局域网发现接 mDNS 真实扫描
/// （[networkDiscoveryProvider]）。
///
/// 外壳负责滚动与 padding + maxWidth 居中，这里只返回内容 Column。
class SourcesPane extends ConsumerWidget {
  const SourcesPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final sourcesAsync = ref.watch(sourcesProvider);
    final connections = ref.watch(activeConnectionsProvider);
    final libsConfig = ref.watch(mediaLibraryConfigProvider).valueOrNull;
    final sources = sourcesAsync.valueOrNull ?? const <SourceEntity>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetHead(
          icon: Icons.dns_rounded,
          title: '数据源',
          subtitle: '添加 / 编辑 / 删除源，测试连接、2FA 与凭据存储。删除源将级联清除其媒体库映射与已索引媒体。',
          actions: [
            AppButton(
              label: '添加源',
              icon: Icons.add_rounded,
              variant: AppButtonVariant.primary,
              onPressed: () => _openWizard(context),
            ),
          ],
        ),
        SetSection(
          title: '已连接的源',
          hint: sourcesAsync.isLoading ? '加载中…' : '${sources.length} 个',
          children: _connectedRows(
            context,
            ref,
            t,
            sourcesAsync,
            connections,
            libsConfig,
          ),
        ),
        const _DiscoveredDevicesSection(),
        SetSection(
          title: '连接行为',
          hint: 'trust_self_signed_cert · source_default_auto_connect · '
              'source_default_remember_device',
          bottomMargin: false,
          children: [
            _DiscoveryRow(),
            SetRow(
              title: '新建源默认自动连接',
              desc: '新增数据源时默认勾选「启动时自动连接」。已有源仍按各自配置，'
                  '可在「编辑源」中单独调整',
              trailing: AppSwitch(
                value: ref.watch(defaultAutoConnectProvider),
                onChanged: (v) => ref
                    .read(defaultAutoConnectProvider.notifier)
                    .setEnabled(enabled: v),
              ),
            ),
            SetRow(
              title: '信任自签名证书',
              desc: '允许 HTTPS 自签名证书。关闭后将对所有源启用证书校验，自签名证书的服务器会连接失败',
              trailing: AppSwitch(
                value: ref.watch(trustSelfSignedCertProvider),
                onChanged: (v) => ref
                    .read(trustSelfSignedCertProvider.notifier)
                    .setEnabled(enabled: v),
              ),
            ),
            SetRow(
              title: '新建源默认记住 2FA 设备',
              desc: '新增支持两步验证的源时，默认勾选「记住此设备以跳过二次验证」。'
                  '已有源仍按各自配置',
              last: true,
              trailing: AppSwitch(
                value: ref.watch(defaultRememberDeviceProvider),
                onChanged: (v) => ref
                    .read(defaultRememberDeviceProvider.notifier)
                    .setEnabled(enabled: v),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _connectedRows(
    BuildContext context,
    WidgetRef ref,
    DesignTokens t,
    AsyncValue<List<SourceEntity>> sourcesAsync,
    Map<String, SourceConnection> connections,
    MediaLibraryConfig? libsConfig,
  ) => sourcesAsync.when(
    loading: () => [const SetRow(title: '正在加载源…', last: true)],
    error: (e, _) => [SetRow(title: '加载源失败', desc: '$e', last: true)],
    data: (allSources) {
      // 仅展示已实现的源类型；未实现类型（绿联 / 飞牛 / NFS 等）不可连接，
      // 不在列表中渲染。
      final sources = [
        for (final s in allSources)
          if (s.type.isSupported) s,
      ];
      if (sources.isEmpty) {
        return [
          SetRow(
            leading: _SourceIcon(icon: Icons.lan_outlined, enabled: false),
            title: '暂无数据源',
            desc: '点击右上「添加源」连接你的第一个 NAS / 媒体服务器 / 下载器',
            last: true,
            trailing: AppButton(
              label: '添加',
              icon: Icons.add_rounded,
              dense: true,
              onPressed: () => _openWizard(context),
            ),
          ),
        ];
      }
      return [
        for (var i = 0; i < sources.length; i++)
          _SourceRow(
            source: sources[i],
            conn: connections[sources[i].id],
            libs: _libsForSource(libsConfig, sources[i].id),
            last: i == sources.length - 1,
          ),
      ];
    },
  );

  /// 从媒体库配置派生某源已映射的媒体类型展示名（视频/音乐/…）。
  static List<String> _libsForSource(
    MediaLibraryConfig? config,
    String sourceId,
  ) {
    if (config == null) return const [];
    return [
      for (final type in MediaType.values)
        if (config.getPathsForType(type).any((p) => p.sourceId == sourceId))
          type.displayName,
    ];
  }

  static void _openWizard(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => const SourceWizardDialog(),
    );
  }
}

/// 单个源行（设计稿 `.conn-row`）：图标 + 名称/类型·host·库 + 状态点/文案 +
/// 测试 + 更多。仅渲染已实现的源类型（未实现类型已在列表层过滤）。
class _SourceRow extends ConsumerStatefulWidget {
  const _SourceRow({
    required this.source,
    required this.conn,
    required this.libs,
    required this.last,
  });

  final SourceEntity source;
  final SourceConnection? conn;
  final List<String> libs;
  final bool last;

  @override
  ConsumerState<_SourceRow> createState() => _SourceRowState();
}

class _SourceRowState extends ConsumerState<_SourceRow> {
  bool _testing = false;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final source = widget.source;
    final status = widget.conn?.status;
    final (dot, label, isErr) = _statusView(
      status,
      widget.conn?.errorMessage,
    );

    final descParts = <String>[
      source.type.displayName,
      if (source.host.isNotEmpty) source.host,
      if (widget.libs.isNotEmpty) '${widget.libs.join(' / ')} 库',
    ];

    return SetRow(
      leading: _SourceIcon(icon: source.type.icon, enabled: true),
      title: source.name.isEmpty ? source.type.displayName : source.name,
      desc: descParts.join(' · '),
      last: widget.last,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == SourceStatus.requires2FA) ...[
            const AppTag('2FA', variant: TagVariant.accent),
            const SizedBox(width: 10),
          ],
          StatusDot(dot, size: 7),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 76),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isErr ? t.err : t.text1,
              ),
            ),
          ),
          const SizedBox(width: 10),
          AppChip(
            label: _testing ? '测试中' : '测试',
            compact: true,
            onTap: _testing ? null : _reconnect,
          ),
          const SizedBox(width: 4),
          _SourceMenu(
            color: t.text2,
            onEdit: _edit,
            onReconnect: _reconnect,
            onDelete: _confirmDelete,
          ),
        ],
      ),
    );
  }

  /// 把实时连接态映射为「圆点 + 文案 + 是否错误色」。
  (DotStatus, String, bool) _statusView(
    SourceStatus? status,
    String? errorMessage,
  ) =>
      switch (status) {
        SourceStatus.connected => (DotStatus.ok, '已连接', false),
        SourceStatus.requires2FA => (DotStatus.warn, '需 2FA', false),
        SourceStatus.connecting => (DotStatus.warn, '连接中', false),
        SourceStatus.error => (DotStatus.err, errorMessage ?? '错误', true),
        SourceStatus.disconnected || null => (DotStatus.off, '未连接', false),
      };

  Future<void> _reconnect() async {
    final source = widget.source;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _testing = true);
    messenger.showSnackBar(SnackBar(content: Text('正在连接「${source.name}」…')));
    try {
      final result = await ref
          .read(activeConnectionsProvider.notifier)
          .reconnect(source.id);
      if (!mounted) return;
      final ok = result?.status == SourceStatus.connected;
      final need2fa = result?.status == SourceStatus.requires2FA;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? '「${source.name}」连接成功'
                  : need2fa
                  ? '「${source.name}」需要两步验证'
                  : '「${source.name}」连接失败'
                        '${result?.errorMessage != null ? '：${result!.errorMessage}' : ''}',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _edit() {
    SourceFormPage.openAdaptive<SourceEntity>(
      context,
      sourceType: widget.source.type,
      existingSource: widget.source,
    );
  }

  Future<void> _confirmDelete() async {
    final source = widget.source;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除数据源'),
        content: Text(
          '删除「${source.name}」将级联移除该源的媒体库映射与已扫描的媒体数据，'
          '此操作不可恢复。确定继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // 先解除库映射，再删源（源删除内部级联清理各库媒体数据）。
    await ref
        .read(mediaLibraryConfigProvider.notifier)
        .removePathsForSource(source.id);
    await ref.read(sourcesProvider.notifier).removeSource(source.id);
  }
}

/// 行首的源类型图标：随是否可用切换强调 / 灰显。
class _SourceIcon extends StatelessWidget {
  const _SourceIcon({required this.icon, required this.enabled});

  final IconData icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: enabled ? t.chipBgActive : t.insetBg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, size: 18, color: enabled ? t.accentBright : t.text3),
    );
  }
}

/// 行尾「更多」菜单：编辑 / 重新连接 / 删除（级联）。
class _SourceMenu extends StatelessWidget {
  const _SourceMenu({
    required this.color,
    required this.onEdit,
    required this.onReconnect,
    required this.onDelete,
  });

  final Color color;
  final VoidCallback onEdit;
  final VoidCallback onReconnect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 30,
    height: 30,
    child: PopupMenuButton<String>(
      tooltip: '更多',
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_horiz_rounded, size: 18, color: color),
      onSelected: (v) {
        switch (v) {
          case 'edit':
            onEdit();
          case 'reconnect':
            onReconnect();
          case 'delete':
            onDelete();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'edit', child: Text('编辑')),
        PopupMenuItem(value: 'reconnect', child: Text('重新连接')),
        PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    ),
  );
}

/// 「发现的设备」：mDNS / Bonjour 扫描到的可添加设备列表，点击「添加」预填
/// 主机 / 端口 / 类型进入添加源表单。无发现结果时整段不渲染。
class _DiscoveredDevicesSection extends ConsumerWidget {
  const _DiscoveredDevicesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(networkDiscoveryProvider).devices;
    if (devices.isEmpty) return const SizedBox.shrink();
    final t = DesignTokens.of(context);
    return SetSection(
      title: '发现的设备',
      hint: '${devices.length} 台 · 点击添加',
      children: [
        for (var i = 0; i < devices.length; i++)
          SetRow(
            title: devices[i].name,
            desc: '${devices[i].host}:${devices[i].port} · '
                '${devices[i].type.displayName}',
            last: i == devices.length - 1,
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: t.insetBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(devices[i].type.icon, size: 19, color: t.accentBright),
            ),
            trailing: AppButton(
              label: '添加',
              icon: Icons.add_rounded,
              dense: true,
              onPressed: () => SourceFormPage.openAdaptive<void>(
                context,
                sourceType: devices[i].type,
                initialValues: {
                  'name': devices[i].name,
                  'host': devices[i].host,
                  'port': devices[i].port.toString(),
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// 局域网发现行（设计稿 .conn 行的「扫描」）：接 mDNS / Bonjour 真实发现。
class _DiscoveryRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(networkDiscoveryProvider);
    final count = state.devices.length;
    final desc = state.error != null
        ? '发现失败：${state.error}'
        : state.isDiscovering
        ? '正在通过 mDNS / Bonjour 扫描局域网…'
        : count > 0
        ? '已发现 $count 台可添加的设备'
        : '通过 mDNS / Bonjour 自动发现可添加的设备';

    return SetRow(
      title: '局域网发现',
      desc: desc,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (count > 0 && !state.isDiscovering)
            AppTag('$count 台', variant: TagVariant.accent),
          if (count > 0 && !state.isDiscovering) const SizedBox(width: 8),
          AppChip(
            label: state.isDiscovering ? '扫描中' : '扫描',
            icon: Icons.refresh_rounded,
            compact: true,
            onTap: state.isDiscovering
                ? null
                : () => ref
                      .read(networkDiscoveryProvider.notifier)
                      .startDiscovery(),
          ),
        ],
      ),
    );
  }
}
