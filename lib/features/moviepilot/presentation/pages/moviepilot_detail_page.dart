import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/moviepilot/presentation/providers/moviepilot_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/service_adapters/moviepilot/moviepilot_adapter.dart';

/// MoviePilot 详情页
///
/// 加源成功后由此接管：自动连接 → 展示概况（订阅 / 下载）/ 订阅列表 /
/// 下载任务。取代此前的"开发中"占位提示。
///
/// 仅消费 MoviePilotApi 实际提供的能力（系统信息、订阅、下载任务、转移历史），
/// 连接失败时优雅降级为错误态而非崩溃。
class MoviePilotDetailPage extends ConsumerStatefulWidget {
  const MoviePilotDetailPage({required this.source, super.key});

  final SourceEntity source;

  @override
  ConsumerState<MoviePilotDetailPage> createState() =>
      _MoviePilotDetailPageState();
}

class _MoviePilotDetailPageState extends ConsumerState<MoviePilotDetailPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  Future<void> _connect() async {
    final notifier =
        ref.read(moviepilotConnectionProvider(widget.source.id).notifier);
    final connection = ref.read(moviepilotConnectionProvider(widget.source.id));
    if (connection == null ||
        connection.status == MoviePilotConnectionStatus.disconnected ||
        connection.status == MoviePilotConnectionStatus.error) {
      await notifier.connect(widget.source);
    }
  }

  void _refresh() {
    ref
      ..invalidate(moviepilotStatsProvider(widget.source.id))
      ..invalidate(moviepilotSubscribesProvider(widget.source.id))
      ..invalidate(moviepilotDownloadsProvider(widget.source.id));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final connection = ref.watch(moviepilotConnectionProvider(widget.source.id));
    final status = connection?.status ?? MoviePilotConnectionStatus.connecting;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: Text(widget.source.name),
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightSurface,
        elevation: 0,
        actions: [
          if (status == MoviePilotConnectionStatus.connected)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _refresh,
            ),
        ],
      ),
      body: switch (status) {
        MoviePilotConnectionStatus.connecting ||
        MoviePilotConnectionStatus.disconnected =>
          const Center(child: CircularProgressIndicator()),
        MoviePilotConnectionStatus.error => _ErrorView(
            message: connection?.errorMessage ?? '',
            onRetry: _connect,
          ),
        MoviePilotConnectionStatus.connected => _ConnectedView(
            sourceId: widget.source.id,
            onRefresh: _refresh,
          ),
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 48, color: Colors.redAccent),
              const SizedBox(height: AppSpacing.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: context.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.l10n.commonRetry),
              ),
            ],
          ),
        ),
      );
}

class _ConnectedView extends ConsumerWidget {
  const _ConnectedView({required this.sourceId, required this.onRefresh});

  final String sourceId;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(moviepilotStatsProvider(sourceId));
    final subscribes = ref.watch(moviepilotSubscribesProvider(sourceId));
    final downloads = ref.watch(moviepilotDownloadsProvider(sourceId));

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          statsAsync.when(
            data: (stats) => _StatsRow(stats: stats),
            loading: () => const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: AppSpacing.lg),
          _SectionHeader(
            icon: Icons.bookmark_rounded,
            title: context.l10n.nastoolNavSubscribe,
          ),
          subscribes.when(
            data: (list) => list.isEmpty
                ? _EmptyHint(text: context.l10n.nastoolPageEmptyHint)
                : Column(
                    children: [
                      for (final s in list)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.movie_rounded),
                          title: Text(s.name),
                          subtitle: Text(
                            [
                              s.type,
                              if (s.season != null) 'S${s.season}',
                              if (s.state != null) s.state!,
                            ].where((e) => e.isNotEmpty).join(' · '),
                          ),
                        ),
                    ],
                  ),
            loading: () => const _InlineLoading(),
            error: (_, _) => _EmptyHint(text: context.l10n.nastoolPageEmptyHint),
          ),
          const SizedBox(height: AppSpacing.lg),
          _SectionHeader(
            icon: Icons.download_rounded,
            title: context.l10n.nastoolNavDownload,
          ),
          downloads.when(
            data: (list) => list.isEmpty
                ? _EmptyHint(text: context.l10n.transferPageNoDownloadTasks)
                : Column(
                    children: [
                      for (final d in list)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.downloading_rounded),
                          title: Text(
                            d.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: LinearProgressIndicator(
                            value: ((d.progress ?? 0) / 100).clamp(0.0, 1.0),
                          ),
                          trailing: Text(
                            '${(d.progress ?? 0).toStringAsFixed(0)}%',
                          ),
                        ),
                    ],
                  ),
            loading: () => const _InlineLoading(),
            error: (_, _) =>
                _EmptyHint(text: context.l10n.transferPageNoDownloadTasks),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});

  final MoviePilotOverviewStats? stats;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    if (s == null) return const SizedBox.shrink();
    return Row(
      children: [
        _StatCard(
          label: context.l10n.nastoolNavSubscribe,
          value: '${s.subscribeCount}',
          icon: Icons.bookmark_rounded,
        ),
        const SizedBox(width: AppSpacing.sm),
        _StatCard(
          label: context.l10n.downloadStatusDownloading,
          value: '${s.activeDownloads}',
          icon: Icons.downloading_rounded,
        ),
        const SizedBox(width: AppSpacing.sm),
        _StatCard(
          label: context.l10n.downloadStatusCompleted,
          value: '${s.completedDownloads}',
          icon: Icons.check_circle_rounded,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(height: AppSpacing.sm),
            Text(
              value,
              style: context.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: AppSpacing.xs),
            Text(
              title,
              style: context.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(text, style: context.textTheme.bodySmall),
      );
}

class _InlineLoading extends StatelessWidget {
  const _InlineLoading();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      );
}
