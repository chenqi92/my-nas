import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/nastool/presentation/providers/nastool_provider.dart';
import 'package:my_nas/features/nastool/presentation/widgets/add_subscription_sheet.dart';
import 'package:my_nas/features/nastool/presentation/widgets/subscription_detail_sheet.dart';
import 'package:my_nas/features/nastool/presentation/widgets/subscription_poster.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/service_adapters/nastool/models/organization_models.dart';
import 'package:my_nas/service_adapters/nastool/models/plugin_models.dart';
import 'package:my_nas/service_adapters/nastool/models/subscribe_models.dart';
import 'package:my_nas/service_adapters/nastool/models/sync_models.dart';
import 'package:my_nas/shared/widgets/atoms/app_card.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
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
    final t = DesignTokens.of(context);
    final sources = ref.watch(nastoolSourcesProvider);

    if (sources.isEmpty) {
      return const DesktopPageScaffold(
        title: '媒体自动化',
        subtitle: 'NAStool 订阅 — 自动追剧 / 电影补全',
        body: DesktopComingSoon(
          icon: Icons.auto_awesome_outlined,
          message: '尚未配置 NAStool。到「数据源」添加 NAStool 之后，可在此管理订阅、自动追剧。',
        ),
      );
    }

    final selected = _sourceId ?? sources.first.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureConnected(selected);
    });

    final subsAsync = ref.watch(nastoolSubscribesProvider(selected));

    return DesktopPageScaffold(
      title: '媒体自动化',
      subtitle: 'NAStool 订阅 — 自动追剧 / 电影补全',
      maxWidth: 1400,
      actions: Row(
        children: [
          AppSegmented<String>(
            value: _filter,
            onChanged: (v) => setState(() => _filter = v),
            dense: true,
            options: const [
              AppSegmentedOption(value: 'all', label: '全部'),
              AppSegmentedOption(value: 'mov', label: '电影'),
              AppSegmentedOption(value: 'tv', label: '剧集'),
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
          FilledButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              barrierColor: Colors.black.withValues(alpha: 0.5),
              builder: (_) => AddSubscriptionSheet(sourceId: selected),
            ),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('新增订阅'),
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
          message: '加载订阅失败：$e',
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
                      ? '还没有订阅。点击右上角「新增订阅」搜索并添加想追的影视。'
                      : '当前筛选下没有订阅。',
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
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
                '自动化工具',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: t.text0,
                ),
              ),
              const SizedBox(height: 12),
              _ToolsRow(sourceId: selected),
            ],
          );
        },
      ),
    );
  }
}

/// 4 个自动化工具入口（插件商店 / 目录同步 / 转移历史 / 系统信息）+
/// MoviePilot 规划占位。点击打开对应数据 sheet。
class _ToolsRow extends StatelessWidget {
  const _ToolsRow({required this.sourceId});
  final String sourceId;

  void _open(BuildContext context, String title, Widget child) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => _ToolSheet(title: title, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = <(String, IconData, VoidCallback)>[
      (
        '插件商店',
        Icons.extension_outlined,
        () => _open(context, '插件', _PluginsSheet(sourceId: sourceId)),
      ),
      (
        '目录同步',
        Icons.sync_alt_rounded,
        () => _open(context, '目录同步', _SyncDirsSheet(sourceId: sourceId)),
      ),
      (
        '转移历史',
        Icons.move_to_inbox_outlined,
        () => _open(context, '转移历史', _TransferHistorySheet(sourceId: sourceId)),
      ),
      (
        '系统信息',
        Icons.dns_outlined,
        () => _open(context, '系统信息', _SystemInfoSheet(sourceId: sourceId)),
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
        const _ToolCard(
          label: 'MoviePilot',
          icon: Icons.auto_awesome_outlined,
          plan: true,
        ),
      ],
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.label,
    required this.icon,
    this.onTap,
    this.plan = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool plan;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Opacity(
      opacity: plan ? 0.6 : 1,
      child: AppCard(
        onTap: plan ? null : onTap,
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
            if (plan) const AppTag('规划', variant: TagVariant.plan),
          ],
        ),
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
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: child,
                ),
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
    final t = DesignTokens.of(context);
    return async.when(
      loading: () => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => SizedBox(
        height: 200,
        child: Center(
          child: Text('加载失败：$e',
              style: TextStyle(fontSize: 12.5, color: t.err)),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return SizedBox(
            height: 160,
            child: Center(
              child: Text(empty,
                  style: TextStyle(fontSize: 12.5, color: t.text2)),
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
    final t = DesignTokens.of(context);
    return _AsyncList<NtPlugin>(
      async: ref.watch(nastoolPluginsProvider(sourceId)),
      empty: '未安装插件。',
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
                  Text(p.name,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: t.text0)),
                  if (p.description != null && p.description!.isNotEmpty)
                    Text(p.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: t.text2)),
                ],
              ),
            ),
            if (p.version != null)
              Text('v${p.version}',
                  style: TextStyle(fontSize: 11, color: t.text3)),
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
    final t = DesignTokens.of(context);
    return _AsyncList<NtSyncDir>(
      async: ref.watch(nastoolSyncDirsProvider(sourceId)),
      empty: '未配置目录同步。',
      itemBuilder: (_, d) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${d.from ?? '—'}  →  ${d.to ?? '—'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: t.text0)),
                  if (d.mode != null)
                    Text(d.mode!,
                        style: TextStyle(fontSize: 11, color: t.text2)),
                ],
              ),
            ),
            IconButton(
              tooltip: '立即同步',
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
    final t = DesignTokens.of(context);
    return _AsyncList<NtTransferHistory>(
      async: ref.watch(nastoolTransferHistoryProvider(sourceId)),
      empty: '暂无转移历史。',
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
                        color: t.text0),
                  ),
                  if (h.mode != null)
                    Text(h.mode!,
                        style: TextStyle(fontSize: 11, color: t.text2)),
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
    final t = DesignTokens.of(context);
    final async = ref.watch(nastoolSystemInfoProvider(sourceId));
    return async.when(
      loading: () => const SizedBox(
          height: 160, child: Center(child: CircularProgressIndicator())),
      error: (e, _) => Text('加载失败：$e',
          style: TextStyle(fontSize: 12.5, color: t.err)),
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
          ('版本', info.version ?? '—'),
          ('最新版本', info.latestVersion ?? '—'),
          ('更新通道', info.updateChannel ?? '—'),
          ('总空间', space(info.totalSpace)),
          ('可用空间', space(info.freeSpace)),
          if (info.cpuUsage != null)
            ('CPU', '${info.cpuUsage!.toStringAsFixed(0)}%'),
          if (info.memoryUsage != null)
            ('内存', '${info.memoryUsage!.toStringAsFixed(0)}%'),
        ];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    Text(label,
                        style: TextStyle(fontSize: 12.5, color: t.text2)),
                    const Spacer(),
                    Text(value,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: t.text0)),
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
    return Row(
      children: [
        Expanded(child: _StatCard(value: '$total', label: '订阅中')),
        const SizedBox(width: 14),
        Expanded(child: _StatCard(value: '$movies', label: '电影')),
        const SizedBox(width: 14),
        Expanded(child: _StatCard(value: '$tv', label: '剧集')),
        const SizedBox(width: 14),
        Expanded(child: _StatCard(value: '$chasing', label: '追剧中', accent: true)),
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
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showDialog<void>(
          context: context,
          barrierColor: Colors.black.withValues(alpha: 0.55),
          builder: (_) =>
              SubscriptionDetailSheet(sub: sub, sourceId: sourceId),
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
}
