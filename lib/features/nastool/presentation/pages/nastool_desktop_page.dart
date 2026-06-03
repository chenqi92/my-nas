import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/nastool/presentation/providers/nastool_provider.dart';
import 'package:my_nas/features/nastool/presentation/widgets/add_subscription_sheet.dart';
import 'package:my_nas/features/nastool/presentation/widgets/subscription_detail_sheet.dart';
import 'package:my_nas/features/nastool/presentation/widgets/subscription_poster.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/service_adapters/nastool/models/subscribe_models.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
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

  Future<void> _ensureConnected(String sourceId) async {
    if (_connected.contains(sourceId)) return;
    _connected.add(sourceId);
    final source =
        ref.read(nastoolSourcesProvider).where((s) => s.id == sourceId).firstOrNull;
    if (source == null) return;
    final conn = ref.read(nastoolConnectionProvider(sourceId));
    if (conn?.status != NasToolConnectionStatus.connected) {
      await ref.read(nastoolConnectionProvider(sourceId).notifier).connect(source);
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
                    childAspectRatio: 0.56,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) =>
                      _SubCard(sub: filtered[i], sourceId: selected, t: t),
                ),
            ],
          );
        },
      ),
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
