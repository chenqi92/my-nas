import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/file_browser/presentation/pages/file_browser_page.dart';
import 'package:my_nas/features/sources/data/services/network_discovery_service.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/source_form_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/sources/presentation/widgets/two_fa_sheet.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_card.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_page_scaffold.dart';
import 'package:my_nas/shared/widgets/dialogs/source_wizard_dialog.dart';

/// 桌面端连接状态必须按源类型选择正确的连接容器。
///
/// Jellyfin / Emby / Plex 使用独立的媒体服务器适配器，不能回退到普通
/// [SourceConnection]。公开为纯函数，便于防止桌面路由再次接错 Provider。
SourceStatus? desktopSourceStatus(
  SourceType type, {
  SourceStatus? standardStatus,
  SourceStatus? mediaServerStatus,
}) => type.category == SourceCategory.mediaServers
    ? mediaServerStatus
    : standardStatus;

String? desktopSourceError(
  SourceType type, {
  String? standardError,
  String? mediaServerError,
}) => type.category == SourceCategory.mediaServers
    ? mediaServerError
    : standardError;

/// 桌面端「数据源」骨架。
///
/// 宽屏把「已配置的连接」作为主区域，把局域网发现收敛为右侧辅助面板；
/// 窄屏按相同优先级纵向排列。添加源仍走 [SourceWizardDialog] 多步弹窗。
class SourcesDesktopPage extends ConsumerStatefulWidget {
  const SourcesDesktopPage({super.key});

  @override
  ConsumerState<SourcesDesktopPage> createState() => _SourcesDesktopPageState();
}

class _SourcesDesktopPageState extends ConsumerState<SourcesDesktopPage> {
  bool _isReorderMode = false;

  @override
  void initState() {
    super.initState();
    // 打开页面自动扫描一次局域网设备（mDNS / Bonjour）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(networkDiscoveryProvider.notifier).startDiscovery();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sourcesAsync = ref.watch(sourcesProvider);
    final connections = ref.watch(activeConnectionsProvider);
    final mediaServerConnections = ref.watch(
      activeMediaServerConnectionsProvider,
    );
    final t = DesignTokens.of(context);

    return DesktopPageScaffold(
      title: l.sourcesPageTitle,
      subtitle: l.sourcesPageSubtitle,
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            variant: AppButtonVariant.ghost,
            onPressed: () => setState(() => _isReorderMode = !_isReorderMode),
            icon: _isReorderMode ? Icons.done_rounded : Icons.reorder_rounded,
            label: _isReorderMode
                ? l.sourcesPageReorderComplete
                : l.sourcesPageReorderStart,
          ),
          const SizedBox(width: 8),
          AppButton(
            variant: AppButtonVariant.primary,
            onPressed: () => showDialog<void>(
              context: context,
              barrierColor: Colors.black.withValues(alpha: 0.5),
              builder: (_) => const SourceWizardDialog(),
            ),
            icon: Icons.add_rounded,
            label: l.sourcesPageAddSource,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final configured = sourcesAsync.when(
            loading: () => const _SourcesLoadingPanel(),
            error: (e, _) => _SourcesMessagePanel(
              icon: Icons.error_outline_rounded,
              message: l.sourcesPageLoadError(e.toString()),
              color: t.err,
            ),
            data: (sources) {
              // 库映射来自 mediaLibraryConfig 派生：源 → 已映射的媒体类型集合，
              // 设计稿 s.libs 没有对应后端字段，故从既有 state 派生而非臆造。
              final libsConfig = ref
                  .watch(mediaLibraryConfigProvider)
                  .valueOrNull;
              return _ConfiguredSourcesSection(
                sources: sources,
                connections: connections,
                mediaServerConnections: mediaServerConnections,
                libsConfig: libsConfig,
                reorderMode: _isReorderMode,
                onReorder: (oldIndex, newIndex) => ref
                    .read(sourcesProvider.notifier)
                    .reorderSources(oldIndex, newIndex),
              );
            },
          );

          // 右栏控制在 400–460px，发现结果不会再横跨整页；小窗口改为
          // 纵向布局，避免两个面板被硬挤成狭窄的两列。
          if (constraints.maxWidth >= 1080) {
            final discoveryWidth = (constraints.maxWidth * 0.36).clamp(
              400.0,
              460.0,
            );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: configured),
                const SizedBox(width: 18),
                SizedBox(
                  width: discoveryWidth,
                  child: const _DiscoveredDevicesSection(),
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              configured,
              const SizedBox(height: 18),
              const _DiscoveredDevicesSection(),
            ],
          );
        },
      ),
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
}

/// 页面主区域：把已配置源呈现为一组全宽连接行，避免只有一个源时出现
/// 一张孤零零的小卡片，也让状态、测试和更多操作保持在同一条阅读路径上。
class _ConfiguredSourcesSection extends StatelessWidget {
  const _ConfiguredSourcesSection({
    required this.sources,
    required this.connections,
    required this.mediaServerConnections,
    required this.libsConfig,
    required this.reorderMode,
    required this.onReorder,
  });

  final List<SourceEntity> sources;
  final Map<String, SourceConnection> connections;
  final Map<String, MediaServerConnection> mediaServerConnections;
  final MediaLibraryConfig? libsConfig;
  final bool reorderMode;
  final ReorderCallback onReorder;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            icon: Icons.dns_rounded,
            title: l.sourcesPageConfiguredConnections,
            subtitle: l.paneSourcesCount(sources.length),
          ),
          _PanelDivider(color: t.hairline),
          if (sources.isEmpty)
            _SourcesEmptyState(
              title: l.paneSourcesEmptyTitle,
              description: l.paneSourcesEmptyDesc,
            )
          else if (reorderMode)
            ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sources.length,
              onReorderItem: onReorder,
              itemBuilder: (context, index) => Column(
                key: ValueKey(sources[index].id),
                children: [
                  _sourceCard(sources[index], reorderIndex: index),
                  if (index != sources.length - 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 72),
                      child: _PanelDivider(color: t.hairline),
                    ),
                ],
              ),
            )
          else
            for (var i = 0; i < sources.length; i++) ...[
              _sourceCard(sources[i]),
              if (i != sources.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 72),
                  child: _PanelDivider(color: t.hairline),
                ),
            ],
        ],
      ),
    );
  }

  Widget _sourceCard(SourceEntity source, {int? reorderIndex}) {
    final standard = connections[source.id];
    final media = mediaServerConnections[source.id];
    return _SourceCard(
      source: source,
      status: desktopSourceStatus(
        source.type,
        standardStatus: standard?.status,
        mediaServerStatus: media?.status,
      ),
      errorMessage: desktopSourceError(
        source.type,
        standardError: standard?.errorMessage,
        mediaServerError: media?.errorMessage,
      ),
      libs: _SourcesDesktopPageState._libsForSource(libsConfig, source.id),
      reorderIndex: reorderIndex,
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: t.chipBgActive,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: t.accentBright),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: t.text0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: t.text2),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

class _PanelDivider extends StatelessWidget {
  const _PanelDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(height: 1, color: color);
}

class _SourcesLoadingPanel extends StatelessWidget {
  const _SourcesLoadingPanel();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _PanelHeader(
            icon: Icons.dns_rounded,
            title: l.sourcesPageConfiguredConnections,
            subtitle: l.paneSourcesLoading,
          ),
          _PanelDivider(color: t.hairline),
          const SizedBox(
            height: 112,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourcesMessagePanel extends StatelessWidget {
  const _SourcesMessagePanel({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: color),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SourcesEmptyState extends StatelessWidget {
  const _SourcesEmptyState({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      child: Column(
        children: [
          Icon(Icons.lan_outlined, size: 28, color: t.text3),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: t.text1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: t.text2),
          ),
        ],
      ),
    );
  }
}

/// 「发现的设备」区：mDNS / Bonjour 自动扫描到的可添加设备列表。
///
/// 面板头部含扫描状态 + 重新扫描，下面使用紧凑设备行。宽屏时固定在右栏，
/// 没有结果时仍保留扫描入口，避免功能在扫描结束后“消失”。
class _DiscoveredDevicesSection extends ConsumerWidget {
  const _DiscoveredDevicesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(networkDiscoveryProvider);
    final devices = state.devices;
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);

    final statusText = state.error != null
        ? l.paneSourcesDiscoveryError('${state.error}')
        : state.isDiscovering
        ? l.paneSourcesDiscoveryScanning
        : devices.isNotEmpty
        ? l.paneSourcesDiscoveryFound(devices.length)
        : state.lastDiscoveryTime != null
        ? l.paneSourcesDiscoveryEmpty
        : l.paneSourcesDiscoveryIdle;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            icon: Icons.radar_rounded,
            title: l.paneSourcesDiscoveryTitle,
            subtitle: statusText,
            trailing: AppButton(
              label: state.isDiscovering
                  ? l.paneSourcesScanning
                  : l.paneSourcesScan,
              icon: state.isDiscovering
                  ? Icons.sync_rounded
                  : Icons.refresh_rounded,
              dense: true,
              onPressed: state.isDiscovering
                  ? null
                  : () => ref
                        .read(networkDiscoveryProvider.notifier)
                        .startDiscovery(),
            ),
          ),
          _PanelDivider(color: t.hairline),
          if (devices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(
                children: [
                  if (state.isDiscovering)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: t.accentBright,
                      ),
                    )
                  else
                    Icon(Icons.wifi_find_rounded, size: 26, color: t.text3),
                  const SizedBox(height: 10),
                  Text(
                    statusText,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: t.text2),
                  ),
                ],
              ),
            )
          else
            for (var i = 0; i < devices.length; i++) ...[
              _DiscoveryRow(device: devices[i]),
              if (i != devices.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 62),
                  child: _PanelDivider(color: t.hairline),
                ),
            ],
        ],
      ),
    );
  }
}

/// 单台发现设备行：类型图标 + 名称 + host:port·类型 +「添加」按钮（预填进表单）。
class _DiscoveryRow extends StatelessWidget {
  const _DiscoveryRow({required this.device});

  final DiscoveredDevice device;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: t.insetBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(device.type.icon, size: 18, color: t.accentBright),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: t.text0,
                  ),
                ),
                Text(
                  '${device.host}:${device.port} · ${device.type.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: t.text2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AppButton(
            label: l.paneSourcesAddShort,
            icon: Icons.add_rounded,
            dense: true,
            onPressed: () => SourceFormPage.openAdaptive<void>(
              context,
              sourceType: device.type,
              initialValues: {
                'name': device.name,
                'host': device.host,
                'port': device.port.toString(),
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 单条已配置连接：在宽面板中横向排列关键信息和操作，小宽度时自动换行。
class _SourceCard extends ConsumerWidget {
  const _SourceCard({
    required this.source,
    required this.status,
    required this.errorMessage,
    required this.libs,
    this.reorderIndex,
  });

  final SourceEntity source;
  final SourceStatus? status;
  final String? errorMessage;
  final List<String> libs;
  final int? reorderIndex;

  bool get _isMediaServer =>
      source.type.category == SourceCategory.mediaServers;

  /// 测试 / 重新连接当前源，并把结果以 SnackBar 反馈；普通源与媒体服务器
  /// 分别走各自的连接容器，避免 Jellyfin / Emby / Plex 被当成 NAS 连接。
  Future<void> _reconnect(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context)
      ..showSnackBar(
        SnackBar(content: Text(l.sourcesPageConnecting(source.name))),
      );

    SourceStatus? resultStatus;
    String? resultError;
    try {
      final manager = ref.read(sourceManagerProvider);
      final credential = await manager.getCredential(source.id);
      var password = credential?.password;

      if (_isMediaServer) {
        final apiKey = credential?.apiKey ?? source.apiKey;
        final hasToken =
            (apiKey?.isNotEmpty ?? false) ||
            (source.accessToken?.isNotEmpty ?? false);
        if ((password?.isEmpty ?? true) && !hasToken) {
          if (!context.mounted) return;
          password = await _showPasswordDialog(context);
          if (password == null || password.isEmpty) return;
        }
        final notifier = ref.read(
          activeMediaServerConnectionsProvider.notifier,
        );
        await notifier.disconnect(source.id);
        final result = await notifier.connect(
          source,
          password: password,
          apiKey: apiKey,
          saveCredential: credential == null,
        );
        resultStatus = result.status;
        resultError = result.errorMessage;
      } else {
        if (source.usesPasswordAuthentication && (password?.isEmpty ?? true)) {
          if (!context.mounted) return;
          password = await _showPasswordDialog(context);
          if (password == null || password.isEmpty) return;
        }
        final result = await ref
            .read(activeConnectionsProvider.notifier)
            .connect(
              source,
              password: password ?? '',
              saveCredential: credential == null,
            );
        resultStatus = result.status;
        resultError = result.errorMessage;
        if (result.status == SourceStatus.requires2FA && context.mounted) {
          final verified = await _complete2FA(context, ref, password);
          resultStatus = verified?.status ?? resultStatus;
          resultError = verified?.errorMessage ?? resultError;
        }
      }
    } on Object catch (e) {
      resultStatus = SourceStatus.error;
      resultError = '$e';
    }

    if (!context.mounted) return;
    final ok = resultStatus == SourceStatus.connected;
    final need2fa = resultStatus == SourceStatus.requires2FA;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? l.sourcesPageConnectSuccess(source.name)
                : need2fa
                ? l.sourcesPageConnectNeeds2FA(source.name)
                : l.sourcesPageConnectFailed(
                    source.name,
                    resultError != null
                        ? l.sourcesPageErrorSuffix(resultError)
                        : '',
                  ),
          ),
        ),
      );
  }

  Future<SourceConnection?> _complete2FA(
    BuildContext context,
    WidgetRef ref,
    String? password,
  ) async {
    SourceConnection? verified;
    await showTwoFASheetWithVerify(
      context,
      sourceName: source.displayName,
      initialRememberDevice: source.rememberDevice,
      allowSkip: false,
      onVerify: (otpCode, rememberDevice) async {
        verified = await ref
            .read(activeConnectionsProvider.notifier)
            .verify2FA(
              source.id,
              otpCode,
              rememberDevice: rememberDevice,
              password: password,
            );
        return verified?.status == SourceStatus.connected;
      },
    );
    return verified;
  }

  Future<String?> _showPasswordDialog(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.sourcesPagePasswordDialogTitle),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            decoration: InputDecoration(
              labelText: l.sourcesPagePasswordLabel,
              hintText: l.sourcesPagePasswordHint(source.username),
            ),
            onSubmitted: (value) => Navigator.of(ctx).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: Text(l.commonConfirm),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _disconnect(BuildContext context, WidgetRef ref) async {
    if (_isMediaServer) {
      await ref
          .read(activeMediaServerConnectionsProvider.notifier)
          .disconnect(source.id);
    } else {
      await ref.read(activeConnectionsProvider.notifier).disconnect(source.id);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${source.displayName} · '
            '${AppLocalizations.of(context).sourcesPageStatusDisconnected}',
          ),
        ),
      );
    }
  }

  void _browse(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FileBrowserPage(
          sourceId: source.id,
          sourceName: source.displayName,
        ),
      ),
    );
  }

  void _edit(BuildContext context) {
    SourceFormPage.openAdaptive<SourceEntity>(
      context,
      sourceType: source.type,
      existingSource: source,
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.sourcesPageDeleteTitle),
        content: Text(l.sourcesPageDeleteConfirm(source.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.sourcesPageCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.sourcesPageDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    // 先解除库映射，再删源（源删除内部级联清理各库媒体数据）。
    await ref
        .read(mediaLibraryConfigProvider.notifier)
        .removePathsForSource(source.id);
    await ref.read(sourcesProvider.notifier).removeSource(source.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    // 未实现的源类型即「即将推出」，与设计稿 plan 态对齐。
    final isPlan = !source.type.isSupported;
    final (dot, label, isErr) = _statusView(l, isPlan, status, errorMessage);
    final connected = status == SourceStatus.connected;

    final identity = Row(
      children: [
        if (reorderIndex != null) ...[
          ReorderableDragStartListener(
            index: reorderIndex!,
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Icon(Icons.drag_indicator_rounded, color: t.text3),
            ),
          ),
        ],
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: t.insetBg,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(source.type.icon, size: 20, color: t.accentBright),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      source.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: t.text0,
                      ),
                    ),
                  ),
                  // 「需 2FA」从实时连接态派生（无静态 two_fa 字段）。
                  if (status == SourceStatus.requires2FA) ...[
                    const SizedBox(width: 7),
                    const AppTag('2FA', variant: TagVariant.accent),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                source.host.isEmpty
                    ? source.type.displayName
                    : '${source.type.displayName} · ${source.host}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: t.text2),
              ),
              if (libs.isNotEmpty) ...[
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final lib in libs)
                      AppTag(l.sourcesPageLibraryTag(lib)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );

    final stateAndActions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusDot(dot),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 138),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: isErr ? t.err : t.text1,
            ),
          ),
        ),
        if (!isPlan) ...[
          const SizedBox(width: 14),
          AppButton(
            label: status == SourceStatus.requires2FA
                ? l.sourcesPageStatusNeedsVerification
                : connected
                ? l.sourcesPageMenuReconnect
                : l.sourcesPageMenuConnect,
            dense: true,
            onPressed: () => _reconnect(context, ref),
          ),
          const SizedBox(width: 4),
          _SourceMenu(
            color: t.text2,
            connected: connected,
            onBrowse: source.type.supportsFileSystem && connected
                ? () => _browse(context)
                : null,
            onEdit: () => _edit(context),
            onReconnect: () => _reconnect(context, ref),
            onDisconnect: () => _disconnect(context, ref),
            onDelete: () => _confirmDelete(context, ref),
          ),
        ] else ...[
          const SizedBox(width: 12),
          AppTag(l.sourcesPageComingSoon, variant: TagVariant.plan),
        ],
      ],
    );

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: 13),
                Align(alignment: Alignment.centerRight, child: stateAndActions),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 18),
              stateAndActions,
            ],
          );
        },
      ),
    );

    // plan 行整体降透明，呼应既有视觉语义。
    final interactiveRow = source.type.supportsFileSystem && connected
        ? Material(
            color: Colors.transparent,
            child: InkWell(onTap: () => _browse(context), child: row),
          )
        : row;
    return isPlan
        ? Opacity(opacity: 0.75, child: interactiveRow)
        : interactiveRow;
  }

  /// 把（plan / 实时连接态）映射为「圆点 + 文案 + 是否错误色」。
  (DotStatus, String, bool) _statusView(
    AppLocalizations l,
    bool isPlan,
    SourceStatus? status,
    String? errorMessage,
  ) {
    if (isPlan) return (DotStatus.off, l.sourcesPageComingSoon, false);
    return switch (status) {
      SourceStatus.connected => (
        DotStatus.ok,
        l.sourcesPageStatusConnected,
        false,
      ),
      SourceStatus.requires2FA => (
        DotStatus.warn,
        l.sourcesPageStatusNeeds2FA,
        false,
      ),
      SourceStatus.connecting => (
        DotStatus.warn,
        l.sourcesPageStatusConnecting,
        false,
      ),
      SourceStatus.error => (
        DotStatus.err,
        errorMessage ?? l.sourcesPageStatusError,
        true,
      ),
      SourceStatus.disconnected ||
      null => (DotStatus.off, l.sourcesPageStatusDisconnected, false),
    };
  }
}

/// 卡片右上角 30x30 的「更多」菜单按钮（对齐设计稿 .icon-btn dots）。
/// 保留旧版的文件浏览、连接/断开、编辑与级联删除入口。
class _SourceMenu extends StatelessWidget {
  const _SourceMenu({
    required this.color,
    required this.connected,
    required this.onBrowse,
    required this.onEdit,
    required this.onReconnect,
    required this.onDisconnect,
    required this.onDelete,
  });

  final Color color;
  final bool connected;
  final VoidCallback? onBrowse;
  final VoidCallback onEdit;
  final VoidCallback onReconnect;
  final VoidCallback onDisconnect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SizedBox(
      width: 30,
      height: 30,
      child: PopupMenuButton<String>(
        tooltip: l.sourcesPageMore,
        padding: EdgeInsets.zero,
        icon: Icon(Icons.more_horiz_rounded, size: 18, color: color),
        onSelected: (v) {
          switch (v) {
            case 'browse':
              onBrowse?.call();
            case 'edit':
              onEdit();
            case 'reconnect':
              onReconnect();
            case 'disconnect':
              onDisconnect();
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (_) => [
          if (onBrowse != null)
            PopupMenuItem(value: 'browse', child: Text(l.shellNavEntryFiles)),
          PopupMenuItem(value: 'edit', child: Text(l.sourcesPageMenuEdit)),
          PopupMenuItem(
            value: 'reconnect',
            child: Text(
              connected ? l.sourcesPageMenuReconnect : l.sourcesPageMenuConnect,
            ),
          ),
          if (connected)
            PopupMenuItem(
              value: 'disconnect',
              child: Text(l.sourcesPageMenuDisconnect),
            ),
          PopupMenuItem(value: 'delete', child: Text(l.sourcesPageMenuDelete)),
        ],
      ),
    );
  }
}
