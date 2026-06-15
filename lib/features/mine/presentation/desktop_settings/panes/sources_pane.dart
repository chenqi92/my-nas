import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/sources/data/services/network_discovery_service.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/source_form_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';
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
    final l = AppLocalizations.of(context);
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
          title: l.paneSourcesTitle,
          subtitle: l.paneSourcesSubtitle,
          actions: [
            AppButton(
              label: l.paneSourcesAddButton,
              icon: Icons.add_rounded,
              variant: AppButtonVariant.primary,
              onPressed: () => _openWizard(context),
            ),
          ],
        ),
        SetSection(
          title: l.paneSourcesConnectedSection,
          hint: sourcesAsync.isLoading
              ? l.paneSourcesLoading
              : l.paneSourcesCount(sources.length),
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
          title: l.paneSourcesBehaviorSection,
          hint: 'trust_self_signed_cert · source_default_auto_connect · '
              'source_default_remember_device',
          bottomMargin: false,
          children: [
            _DiscoveryRow(),
            SetRow(
              title: l.paneSourcesDefaultAutoConnectTitle,
              desc: l.paneSourcesDefaultAutoConnectDesc,
              trailing: AppSwitch(
                value: ref.watch(defaultAutoConnectProvider),
                onChanged: (v) => ref
                    .read(defaultAutoConnectProvider.notifier)
                    .setEnabled(enabled: v),
              ),
            ),
            SetRow(
              title: l.paneSourcesTrustSelfSignedTitle,
              desc: l.paneSourcesTrustSelfSignedDesc,
              trailing: AppSwitch(
                value: ref.watch(trustSelfSignedCertProvider),
                onChanged: (v) => ref
                    .read(trustSelfSignedCertProvider.notifier)
                    .setEnabled(enabled: v),
              ),
            ),
            SetRow(
              title: l.paneSourcesDefaultRememberDeviceTitle,
              desc: l.paneSourcesDefaultRememberDeviceDesc,
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
  ) {
    final l = AppLocalizations.of(context);
    return sourcesAsync.when(
    loading: () => [SetRow(title: l.paneSourcesRowLoading, last: true)],
    error: (e, _) =>
        [SetRow(title: l.paneSourcesRowLoadError, desc: '$e', last: true)],
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
            title: l.paneSourcesEmptyTitle,
            desc: l.paneSourcesEmptyDesc,
            last: true,
            trailing: AppButton(
              label: l.paneSourcesAddShort,
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
  }

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
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final source = widget.source;
    final status = widget.conn?.status;
    final (dot, label, isErr) = _statusView(
      l,
      status,
      widget.conn?.errorMessage,
    );

    final descParts = <String>[
      source.type.displayName,
      if (source.host.isNotEmpty) source.host,
      if (widget.libs.isNotEmpty) l.paneSourcesLibsSuffix(widget.libs.join(' / ')),
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
            label: _testing ? l.paneSourcesTesting : l.paneSourcesTest,
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
    AppLocalizations l,
    SourceStatus? status,
    String? errorMessage,
  ) =>
      switch (status) {
        SourceStatus.connected => (DotStatus.ok, l.paneSourcesStatusConnected, false),
        SourceStatus.requires2FA => (DotStatus.warn, l.paneSourcesStatus2FA, false),
        SourceStatus.connecting => (DotStatus.warn, l.paneSourcesStatusConnecting, false),
        SourceStatus.error =>
          (DotStatus.err, errorMessage ?? l.paneSourcesStatusError, true),
        SourceStatus.disconnected || null =>
          (DotStatus.off, l.paneSourcesStatusDisconnected, false),
      };

  Future<void> _reconnect() async {
    final l = AppLocalizations.of(context);
    final source = widget.source;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _testing = true);
    messenger.showSnackBar(
      SnackBar(content: Text(l.paneSourcesConnecting(source.name))),
    );
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
                  ? l.paneSourcesConnectSuccess(source.name)
                  : need2fa
                  ? l.paneSourcesConnectNeed2FA(source.name)
                  : l.paneSourcesConnectFailed(
                      source.name,
                      result?.errorMessage != null
                          ? l.paneSourcesConnectFailedReason(result!.errorMessage!)
                          : '',
                    ),
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
    final l = AppLocalizations.of(context);
    final source = widget.source;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.paneSourcesDeleteTitle),
        content: Text(l.paneSourcesDeleteContent(source.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.paneSourcesCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.paneSourcesDelete),
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
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SizedBox(
      width: 30,
      height: 30,
      child: PopupMenuButton<String>(
        tooltip: l.paneSourcesMore,
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
        itemBuilder: (_) => [
          PopupMenuItem(value: 'edit', child: Text(l.paneSourcesMenuEdit)),
          PopupMenuItem(
            value: 'reconnect',
            child: Text(l.paneSourcesMenuReconnect),
          ),
          PopupMenuItem(value: 'delete', child: Text(l.paneSourcesMenuDelete)),
        ],
      ),
    );
  }
}

/// 「发现的设备」：mDNS / Bonjour 扫描到的可添加设备列表，点击「添加」预填
/// 主机 / 端口 / 类型进入添加源表单。无发现结果时整段不渲染。
class _DiscoveredDevicesSection extends ConsumerWidget {
  const _DiscoveredDevicesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(networkDiscoveryProvider).devices;
    if (devices.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    return SetSection(
      title: l.paneSourcesDiscoveredSection,
      hint: l.paneSourcesDiscoveredHint(devices.length),
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
              label: l.paneSourcesAddShort,
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
    final l = AppLocalizations.of(context);
    final state = ref.watch(networkDiscoveryProvider);
    final count = state.devices.length;
    final desc = state.error != null
        ? l.paneSourcesDiscoveryError('${state.error}')
        : state.isDiscovering
        ? l.paneSourcesDiscoveryScanning
        : count > 0
        ? l.paneSourcesDiscoveryFound(count)
        : l.paneSourcesDiscoveryIdle;

    return SetRow(
      title: l.paneSourcesDiscoveryTitle,
      desc: desc,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (count > 0 && !state.isDiscovering)
            AppTag(l.paneSourcesDeviceCount(count), variant: TagVariant.accent),
          if (count > 0 && !state.isDiscovering) const SizedBox(width: 8),
          AppChip(
            label: state.isDiscovering
                ? l.paneSourcesScanning
                : l.paneSourcesScan,
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
