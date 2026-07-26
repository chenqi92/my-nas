import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/moviepilot/presentation/pages/moviepilot_detail_page.dart';
import 'package:my_nas/features/nastool/presentation/pages/nastool_main_page.dart';
import 'package:my_nas/features/nastool/presentation/providers/nastool_provider.dart';
import 'package:my_nas/features/nastool/presentation/widgets/add_subscription_sheet.dart';
import 'package:my_nas/features/nastool/presentation/widgets/subscription_detail_sheet.dart';
import 'package:my_nas/features/nastool/presentation/widgets/subscription_poster.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/service_adapters/nastool/models/organization_models.dart';
import 'package:my_nas/service_adapters/nastool/models/plugin_models.dart';
import 'package:my_nas/service_adapters/nastool/models/subscribe_models.dart';
import 'package:my_nas/service_adapters/nastool/models/sync_models.dart';
import 'package:my_nas/shared/widgets/atoms/app_card.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_page_scaffold.dart';

/// 桌面端「媒体自动化(NAStool)」——订阅管理（电影 / 剧集）+ 新增订阅。
class NasToolDesktopPage extends ConsumerStatefulWidget {
  const NasToolDesktopPage({super.key});

  @override
  ConsumerState<NasToolDesktopPage> createState() => _NasToolDesktopPageState();
}

class _NasToolDesktopPageState extends ConsumerState<NasToolDesktopPage> {
  String? _sourceId;
  String _filter = 'all';
  final _connected = <String>{};
  final _connecting = <String>{};

  Future<void> _ensureConnected(String sourceId) async {
    if (_connected.contains(sourceId) || _connecting.contains(sourceId)) return;
    final conn = ref.read(nastoolConnectionProvider(sourceId));
    if (conn?.status == NasToolConnectionStatus.connected) {
      _connected.add(sourceId);
      return;
    }
    final source = ref
        .read(nastoolSourcesProvider)
        .where((s) => s.id == sourceId)
        .firstOrNull;
    if (source == null) return;
    _connecting.add(sourceId);
    try {
      await ref
          .read(nastoolConnectionProvider(sourceId).notifier)
          .connect(source);
      // 仅连接成功后才标记，失败保持未标记以便重试。
      if (ref.read(nastoolConnectionProvider(sourceId))?.status ==
          NasToolConnectionStatus.connected) {
        _connected.add(sourceId);
      }
    } finally {
      _connecting.remove(sourceId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final sources = ref.watch(nastoolSourcesProvider);
    final moviePilotSources = ref
        .watch(mediaManagementSourcesProvider)
        .where((source) => source.type == SourceType.moviepilot)
        .toList();

    if (!desktopAutomationHasConfiguredService(
      nastoolCount: sources.length,
      moviePilotCount: moviePilotSources.length,
    )) {
      return DesktopPageScaffold(
        title: l.nastoolPageTitle,
        subtitle: l.nastoolPageSubtitle,
        body: DesktopComingSoon(
          icon: Icons.auto_awesome_outlined,
          message: l.nastoolPageNotConfigured,
        ),
      );
    }

    if (sources.isEmpty) {
      return DesktopPageScaffold(
        title: l.nastoolPageTitle,
        subtitle: l.nastoolPageSubtitle,
        body: _MoviePilotGrid(sources: moviePilotSources),
      );
    }

    final selected = _sourceId ?? sources.first.id;
    final selectedSource = sources.firstWhere(
      (source) => source.id == selected,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureConnected(selected);
    });

    final subsAsync = ref.watch(nastoolSubscribesProvider(selected));

    return DesktopPageScaffold(
      title: l.nastoolPageTitle,
      subtitle: l.nastoolPageSubtitle,
      maxWidth: 1400,
      actions: Row(
        children: [
          AppSegmented<String>(
            value: _filter,
            onChanged: (v) => setState(() => _filter = v),
            dense: true,
            options: [
              AppSegmentedOption(value: 'all', label: l.nastoolPageFilterAll),
              AppSegmentedOption(value: 'mov', label: l.nastoolPageFilterMovie),
              AppSegmentedOption(value: 'tv', label: l.nastoolPageFilterTv),
            ],
          ),
          const SizedBox(width: 12),
          if (sources.length > 1)
            for (final s in sources)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: AppChip(
                  label: s.displayName,
                  active: s.id == selected,
                  compact: true,
                  onTap: () => setState(() => _sourceId = s.id),
                ),
              ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => _pushPage(NasToolMainPage(source: selectedSource)),
            icon: const Icon(Icons.dashboard_customize_rounded, size: 16),
            label: Text(l.paneAdvancedManageButton),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              barrierColor: Colors.black.withValues(alpha: 0.5),
              builder: (_) => AddSubscriptionSheet(sourceId: selected),
            ),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: Text(l.nastoolPageAddSubscription),
          ),
        ],
      ),
      body: subsAsync.when(
        loading: () => const SizedBox(
          height: 300,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => DesktopComingSoon(
          icon: Icons.error_outline_rounded,
          message: l.nastoolPageLoadSubscriptionsFailed(e.toString()),
        ),
        data: (subs) {
          final filtered = subs.where((s) {
            if (_filter == 'mov') return s.isMovie;
            if (_filter == 'tv') return s.isTv;
            return true;
          }).toList();
          final stats = _SubStatRow(
            total: subs.length,
            movies: subs.where((s) => s.isMovie).length,
            tv: subs.where((s) => s.isTv).length,
            chasing: subs.where((s) => s.isTv && !s.isCompleted).length,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              stats,
              const SizedBox(height: 22),
              if (filtered.isEmpty)
                DesktopComingSoon(
                  icon: Icons.bookmark_border_rounded,
                  message: subs.isEmpty
                      ? l.nastoolPageEmptyHint
                      : l.nastoolPageEmptyFiltered,
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                    childAspectRatio: 0.65,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) =>
                      _SubCard(sub: filtered[i], sourceId: selected, t: t),
                ),
              const SizedBox(height: 28),
              Text(
                l.nastoolPageAutomationTools,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: t.text0,
                ),
              ),
              const SizedBox(height: 12),
              _ToolsRow(
                sourceId: selected,
                moviePilotSources: moviePilotSources,
              ),
            ],
          );
        },
      ),
    );
  }

  void _pushPage(Widget page) {
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

/// MoviePilot-only configurations must still make the desktop automation page
/// usable; previously the page incorrectly treated them as unconfigured.
@visibleForTesting
bool desktopAutomationHasConfiguredService({
  required int nastoolCount,
  required int moviePilotCount,
}) => nastoolCount > 0 || moviePilotCount > 0;

/// 4 个 NAStool 快捷工具 + 已配置 MoviePilot 实际入口。
class _ToolsRow extends StatelessWidget {
  const _ToolsRow({required this.sourceId, required this.moviePilotSources});
  final String sourceId;
  final List<SourceEntity> moviePilotSources;

  void _open(BuildContext context, String title, Widget child) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => _ToolSheet(title: title, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final entries = <(String, IconData, VoidCallback)>[
      (
        l.nastoolPageToolPluginStore,
        Icons.extension_outlined,
        () => _open(
          context,
          l.nastoolPageToolPlugins,
          _PluginsSheet(sourceId: sourceId),
        ),
      ),
      (
        l.nastoolPageToolSyncDirs,
        Icons.sync_alt_rounded,
        () => _open(
          context,
          l.nastoolPageToolSyncDirs,
          _SyncDirsSheet(sourceId: sourceId),
        ),
      ),
      (
        l.nastoolPageToolTransferHistory,
        Icons.move_to_inbox_outlined,
        () => _open(
          context,
          l.nastoolPageToolTransferHistory,
          _TransferHistorySheet(sourceId: sourceId),
        ),
      ),
      (
        l.nastoolPageToolSystemInfo,
        Icons.dns_outlined,
        () => _open(
          context,
          l.nastoolPageToolSystemInfo,
          _SystemInfoSheet(sourceId: sourceId),
        ),
      ),
    ];
    return GridView.count(
      crossAxisCount: 5,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.4,
      children: [
        for (final (label, icon, onTap) in entries)
          _ToolCard(label: label, icon: icon, onTap: onTap),
        for (final source in moviePilotSources)
          _ToolCard(
            label: source.displayName,
            icon: Icons.auto_awesome_outlined,
            onTap: () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute<void>(
                builder: (_) => MoviePilotDetailPage(source: source),
              ),
            ),
          ),
      ],
    );
  }
}

class _MoviePilotGrid extends StatelessWidget {
  const _MoviePilotGrid({required this.sources});

  final List<SourceEntity> sources;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.nastoolPageAutomationTools,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: t.text0,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 260,
            mainAxisExtent: 74,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: sources.length,
          itemBuilder: (_, index) {
            final source = sources[index];
            return _ToolCard(
              label: source.displayName,
              icon: Icons.auto_awesome_outlined,
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute<void>(
                  builder: (_) => MoviePilotDetailPage(source: source),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.label, required this.icon, this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: t.chipBgActive,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: t.accentBright),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: t.text0,
              ),
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 16, color: t.text3),
        ],
      ),
    );
  }
}

/// 通用工具 sheet 外壳：标题 + 滚动内容。
class _ToolSheet extends StatelessWidget {
  const _ToolSheet({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: GlassPanel(
          strong: true,
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: t.hairline)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: t.text0,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, size: 16, color: t.text2),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: Padding(padding: const EdgeInsets.all(16), child: child),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 通用：FutureProvider 列表 → loading/error/empty/list。
class _AsyncList<T> extends StatelessWidget {
  const _AsyncList({
    required this.async,
    required this.empty,
    required this.itemBuilder,
  });
  final AsyncValue<List<T>> async;
  final String empty;
  final Widget Function(BuildContext, T) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    return async.when(
      loading: () => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => SizedBox(
        height: 200,
        child: Center(
          child: Text(
            l.nastoolPageLoadFailed(e.toString()),
            style: TextStyle(fontSize: 12.5, color: t.err),
          ),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return SizedBox(
            height: 160,
            child: Center(
              child: Text(
                empty,
                style: TextStyle(fontSize: 12.5, color: t.text2),
              ),
            ),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          itemCount: items.length,
          separatorBuilder: (_, _) => Divider(height: 1, color: t.hairline),
          itemBuilder: (c, i) => itemBuilder(c, items[i]),
        );
      },
    );
  }
}

class _PluginsSheet extends ConsumerWidget {
  const _PluginsSheet({required this.sourceId});
  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    return _AsyncList<NtPlugin>(
      async: ref.watch(nastoolPluginsProvider(sourceId)),
      empty: l.nastoolPagePluginsEmpty,
      itemBuilder: (_, p) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(
              (p.enabled ?? false)
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              size: 15,
              color: (p.enabled ?? false) ? t.ok : t.text3,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: t.text0,
                    ),
                  ),
                  if (p.description != null && p.description!.isNotEmpty)
                    Text(
                      p.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: t.text2),
                    ),
                ],
              ),
            ),
            if (p.version != null)
              Text(
                'v${p.version}',
                style: TextStyle(fontSize: 11, color: t.text3),
              ),
          ],
        ),
      ),
    );
  }
}

class _SyncDirsSheet extends ConsumerWidget {
  const _SyncDirsSheet({required this.sourceId});
  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    return _AsyncList<NtSyncDir>(
      async: ref.watch(nastoolSyncDirsProvider(sourceId)),
      empty: l.nastoolPageSyncDirsEmpty,
      itemBuilder: (_, d) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${d.from ?? '—'}  →  ${d.to ?? '—'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: t.text0),
                  ),
                  if (d.mode != null)
                    Text(
                      d.mode!,
                      style: TextStyle(fontSize: 11, color: t.text2),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: l.nastoolPageSyncNow,
              onPressed: d.id == null
                  ? null
                  : () => ref
                        .read(nastoolActionsProvider(sourceId))
                        .runSyncDir(d.id!),
              icon: Icon(Icons.play_circle_outline, size: 18, color: t.accent),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferHistorySheet extends ConsumerWidget {
  const _TransferHistorySheet({required this.sourceId});
  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    return _AsyncList<NtTransferHistory>(
      async: ref.watch(nastoolTransferHistoryProvider(sourceId)),
      empty: l.nastoolPageTransferHistoryEmpty,
      itemBuilder: (_, h) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(
              (h.success ?? false)
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              size: 15,
              color: (h.success ?? false) ? t.ok : t.err,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    h.seasonEpisode != null && h.seasonEpisode!.isNotEmpty
                        ? '${h.title} · ${h.seasonEpisode}'
                        : h.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: t.text0,
                    ),
                  ),
                  if (h.mode != null)
                    Text(
                      h.mode!,
                      style: TextStyle(fontSize: 11, color: t.text2),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemInfoSheet extends ConsumerWidget {
  const _SystemInfoSheet({required this.sourceId});
  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final async = ref.watch(nastoolSystemInfoProvider(sourceId));
    return async.when(
      loading: () => const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Text(
        l.nastoolPageLoadFailed(e.toString()),
        style: TextStyle(fontSize: 12.5, color: t.err),
      ),
      data: (info) {
        String space(int? b) {
          if (b == null || b <= 0) return '—';
          const u = ['B', 'KB', 'MB', 'GB', 'TB'];
          var v = b.toDouble();
          var i = 0;
          while (v >= 1024 && i < u.length - 1) {
            v /= 1024;
            i++;
          }
          return '${v.toStringAsFixed(1)} ${u[i]}';
        }

        final rows = <(String, String)>[
          (l.nastoolPageInfoVersion, info.version ?? '—'),
          (l.nastoolPageInfoLatestVersion, info.latestVersion ?? '—'),
          (l.nastoolPageInfoUpdateChannel, info.updateChannel ?? '—'),
          (l.nastoolPageInfoTotalSpace, space(info.totalSpace)),
          (l.nastoolPageInfoFreeSpace, space(info.freeSpace)),
          if (info.cpuUsage != null)
            ('CPU', '${info.cpuUsage!.toStringAsFixed(0)}%'),
          if (info.memoryUsage != null)
            (
              l.nastoolPageInfoMemory,
              '${info.memoryUsage!.toStringAsFixed(0)}%',
            ),
        ];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(fontSize: 12.5, color: t.text2),
                    ),
                    const Spacer(),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: t.text0,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SubStatRow extends StatelessWidget {
  const _SubStatRow({
    required this.total,
    required this.movies,
    required this.tv,
    required this.chasing,
  });
  final int total;
  final int movies;
  final int tv;
  final int chasing;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            value: '$total',
            label: l.nastoolPageStatSubscribing,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _StatCard(value: '$movies', label: l.nastoolPageStatMovies),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _StatCard(value: '$tv', label: l.nastoolPageStatTv),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _StatCard(
            value: '$chasing',
            label: l.nastoolPageStatChasing,
            accent: true,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    this.accent = false,
  });
  final String value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: t.cardBg,
        border: Border.all(color: t.cardBorder),
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: accent ? t.accentBright : t.text0,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: t.text2)),
        ],
      ),
    );
  }
}

class _SubCard extends StatelessWidget {
  const _SubCard({required this.sub, required this.sourceId, required this.t});
  final NtSubscribe sub;
  final String sourceId;
  final DesignTokens t;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (_) => SubscriptionDetailSheet(sub: sub, sourceId: sourceId),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SubscriptionPoster(path: sub.posterPath),
                  if (sub.progress != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: sub.progress,
                        minHeight: 4,
                        backgroundColor: Colors.black.withValues(alpha: 0.4),
                        valueColor: AlwaysStoppedAnimation(t.accentBright),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sub.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: t.text0,
            ),
          ),
          Text(
            [
              if (sub.year != null) sub.year!,
              if (sub.seasonDisplay != null) sub.seasonDisplay!,
              if (sub.isTv && sub.totalEp != null)
                '${sub.currentEp ?? 0}/${sub.totalEp}',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: t.text2),
          ),
        ],
      ),
    ),
  );
}
