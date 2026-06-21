import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/downloader/presentation/providers/downloader_aggregate_provider.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/video_history_service.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/pages/video_list_page.dart'
    show VideoListLoaded, videoListProvider;
import 'package:my_nas/features/video/presentation/providers/video_history_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/atoms/app_card.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_progress_bar.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';

/// 桌面端「概览 / 此刻」首屏。
///
/// 现阶段铺出"此刻 hero + 时钟卡 + 系统脉搏 + 快速操作 + 继续 strip"骨架，
/// 数据接线（继续观看 spotlight 真实条目、追剧订阅、人物 row）放在后续。
class HomeOverviewPage extends ConsumerStatefulWidget {
  const HomeOverviewPage({super.key});

  @override
  ConsumerState<HomeOverviewPage> createState() => _HomeOverviewPageState();
}

class _HomeOverviewPageState extends ConsumerState<HomeOverviewPage> {
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  String _greet(AppLocalizations l) {
    final h = _now.hour;
    if (h < 6) return l.homeGreetEarlyMorning;
    if (h < 11) return l.homeGreetMorning;
    if (h < 14) return l.homeGreetNoon;
    if (h < 18) return l.homeGreetAfternoon;
    return l.homeGreetEvening;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sourcesOnline = ref.watch(activeConnectionsProvider).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 120),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1340),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _NowHero(
                now: _now,
                greet: _greet(l),
                sourcesOnline: sourcesOnline,
              ),
              const SizedBox(height: 30),
              _SectionHead(
                title: l.homeSectionContinue,
                sub: l.homeSectionContinueSub,
              ),
              const SizedBox(height: 14),
              const _ContinueStrip(),
              const SizedBox(height: 30),
              _SectionHead(title: l.homeSectionQuickActions),
              const SizedBox(height: 14),
              _QuickGrid(),
              const SizedBox(height: 30),
              _SectionHead(title: l.homeSectionRecentlyAdded, sub: l.homeSectionRecentlyAddedSub),
              const SizedBox(height: 14),
              const _RecentlyAdded(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.title, this.sub});
  final String title;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: t.text0,
                letterSpacing: -0.2,
              ),
            ),
            if (sub != null) ...[
              const SizedBox(height: 3),
              Text(
                sub!,
                style: TextStyle(fontSize: 12.5, color: t.text2),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _NowHero extends StatelessWidget {
  const _NowHero({
    required this.now,
    required this.greet,
    required this.sourcesOnline,
  });

  final DateTime now;
  final String greet;
  final int sourcesOnline;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    return SizedBox(
      // 容纳右侧时钟卡 + 三行系统脉搏（脉搏行加高后 340 会溢出 24px）。
      height: 372,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 31,
            child: _SpotlightCard(),
          ),
          const SizedBox(width: 18),
          Expanded(
            flex: 20,
            child: Column(
              children: [
                GlassPanel(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l.homeWelcomeBack(greet),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: t.text2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            color: t.text0,
                            letterSpacing: -1.2,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l.homeNowDateLine(
                            now.month,
                            now.day,
                            _zhWeek(l, now.weekday),
                            sourcesOnline,
                          ),
                          style: TextStyle(fontSize: 12, color: t.text2),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(child: _SystemPulse()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _zhWeek(AppLocalizations l, int w) => [
        l.homeWeekdayMon,
        l.homeWeekdayTue,
        l.homeWeekdayWed,
        l.homeWeekdayThu,
        l.homeWeekdayFri,
        l.homeWeekdaySat,
        l.homeWeekdaySun,
      ][w - 1];
}

class _SpotlightCard extends ConsumerWidget {
  const _SpotlightCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    final items = ref.watch(continueWatchingProvider).valueOrNull ?? const [];
    final top = items.isNotEmpty ? items.first : null;
    final pos = top?.lastPosition?.inMilliseconds ?? 0;
    final dur = top?.duration?.inMilliseconds ?? 0;
    final progress = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;

    final card = ClipRRect(
      borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              t.accentDeep.withValues(alpha: 0.5),
              const Color(0xFF1A1416),
            ],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 顶部继续观看条目的缩略图作为底图（有则铺）。
            if (top?.thumbnailUrl != null && top!.thumbnailUrl!.isNotEmpty)
              Positioned.fill(
                child: _Poster(url: top.thumbnailUrl, fallback: t.insetBg),
              ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.92),
                    Colors.black.withValues(alpha: 0.10),
                  ],
                  stops: const [0.04, 0.55],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 30, 32, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      AppTag(l.homeTagContinueWatching,
                          variant: TagVariant.accent),
                      AppTag(l.homeTagLocalFirst),
                      AppTag(l.homeTagTraktSync, variant: TagVariant.accent),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    top?.videoName ?? l.homeSpotlightEmptyTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.6,
                      shadows: [
                        const Shadow(color: Colors.black54, blurRadius: 12),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: t.accent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: t.accent.withValues(alpha: 0.6),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: t.accentContrast,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              top != null
                                  ? l.homeSpotlightContinueProgress(
                                      (progress * 100).round(),
                                    )
                                  : l.homeSpotlightContinueHint,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFFCCCCD0),
                              ),
                            ),
                            const SizedBox(height: 6),
                            AppProgressBar(value: progress),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (top == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        onTap: () => GoRouter.of(context).go('/video'),
        child: card,
      ),
    );
  }
}

String _fmtSpeed(int bytesPerSec) {
  if (bytesPerSec <= 0) return '0 KB/s';
  const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
  var v = bytesPerSec.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
}

class _SystemPulse extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    final tp = ref.watch(downloaderThroughputProvider);
    final downloadSub = tp.activeCount > 0
        ? l.homePulseDownloadActive(_fmtSpeed(tp.downloadSpeed), tp.activeCount)
        : tp.connectedClients > 0
            ? l.homePulseDownloadIdle(tp.connectedClients)
            : l.homePulseDownloadDisconnected;
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  l.homePulseTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: t.text0,
                  ),
                ),
                const Spacer(),
                const StatusDot(DotStatus.ok),
                const SizedBox(width: 5),
                Text(
                  l.homePulseRealtime,
                  style: TextStyle(fontSize: 11, color: t.text2),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 三行在剩余空间内均匀分布，避免固定高度下溢出。
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _PulseRow(
                    icon: Icons.download_rounded,
                    iconColor: t.accentBright,
                    title: l.homePulseDownloadTitle,
                    subtitle: downloadSub,
                    trailing: _Sparkline(color: t.accentBright),
                  ),
                  _PulseRow(
                    icon: Icons.image_search_rounded,
                    iconColor: t.warn,
                    title: l.homePulsePhotoScanTitle,
                    subtitle: l.homePulsePhotoScanIdle,
                    trailing: _MiniRing(value: 0, color: t.warn),
                  ),
                  _PulseRow(
                    icon: Icons.cast_rounded,
                    iconColor: t.hot,
                    title: l.homePulseLiveTitle,
                    subtitle: l.homePulseLiveHint,
                    trailing: AppChip(
                      label: l.homePulseLiveWatch,
                      compact: true,
                      onTap: () => GoRouter.of(context).go('/live'),
                    ),
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

class _PulseRow extends StatelessWidget {
  const _PulseRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: t.insetBg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 14, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: t.text0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: t.text2),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// 迷你 sparkline（设计稿系统脉搏下载吞吐行）。静态波形 + accent 渐变。
class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 64,
        height: 24,
        child: CustomPaint(painter: _SparkPainter(color)),
      );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.color);
  final Color color;

  static const _pts = [.3, .5, .35, .6, .45, .7, .5, .8, .55, .9, .6];

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var i = 0; i < _pts.length; i++) {
      final x = size.width * i / (_pts.length - 1);
      final y = size.height * (1 - _pts[i]);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas
      ..drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
          ).createShader(Offset.zero & size),
      )
      ..drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.color != color;
}

/// 迷你进度环（设计稿照片扫描行）。
class _MiniRing extends StatelessWidget {
  const _MiniRing({required this.value, required this.color});
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return SizedBox(
      width: 26,
      height: 26,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: value,
            strokeWidth: 3,
            backgroundColor: t.insetBg,
            valueColor: AlwaysStoppedAnimation(color),
          ),
          Text(
            (value * 100).toStringAsFixed(0),
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: t.text2,
            ),
          ),
        ],
      ),
    );
  }
}

/// 「继续」strip：接 continueWatchingProvider（本地播放历史，未来与 Trakt
/// 合并、本地优先）。无进度时回退空态卡。
class _ContinueStrip extends ConsumerWidget {
  const _ContinueStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items =
        ref.watch(continueWatchingProvider).valueOrNull ?? const [];
    if (items.isEmpty) return const _EmptyContinue();
    final list = items.take(8).toList();
    return SizedBox(
      height: 156,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (_, i) => _ContinueCard(
          item: list[i],
          onTap: () => GoRouter.of(context).go('/video'),
        ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.item, required this.onTap});
  final VideoHistoryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    final pos = item.lastPosition?.inMilliseconds ?? 0;
    final dur = item.duration?.inMilliseconds ?? 0;
    final progress = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
    return SizedBox(
      width: 200,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(11),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 92,
                height: 60,
                child: _Poster(url: item.thumbnailUrl, fallback: t.insetBg),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.videoName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: t.text0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AppProgressBar(value: progress),
                  const SizedBox(height: 5),
                  Text(
                    l.homeWatchedPercent((progress * 100).round()),
                    style: TextStyle(fontSize: 10.5, color: t.text2),
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

class _EmptyContinue extends StatelessWidget {
  const _EmptyContinue();

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      child: Row(
        children: [
          Icon(Icons.history_rounded, size: 22, color: t.text3),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l.homeEmptyContinueHint,
              style: TextStyle(fontSize: 13, color: t.text2),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tiles = [
      _QuickItem(
        title: l.homeQuickNewDownloadTitle,
        desc: l.homeQuickNewDownloadDesc,
        icon: Icons.download_rounded,
        onTap: () => GoRouter.of(context).go('/download'),
      ),
      _QuickItem(
        title: l.homeQuickPtSearchTitle,
        desc: l.homeQuickPtSearchDesc,
        icon: Icons.flag_circle_outlined,
        onTap: () => GoRouter.of(context).go('/pt'),
      ),
      _QuickItem(
        title: l.homeQuickUploadTitle,
        desc: l.homeQuickUploadDesc,
        icon: Icons.upload_rounded,
        onTap: () => GoRouter.of(context).go('/transfer'),
      ),
      _QuickItem(
        title: l.homeQuickAddSourceTitle,
        desc: l.homeQuickAddSourceDesc,
        icon: Icons.lan_rounded,
        onTap: () => GoRouter.of(context).go('/sources'),
      ),
    ];
    return GridView.count(
      crossAxisCount: 4,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.7,
      children: tiles,
    );
  }
}

class _QuickItem extends StatelessWidget {
  const _QuickItem({
    required this.title,
    required this.desc,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String desc;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: t.text0,
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(fontSize: 11, color: t.text2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 最近添加（对齐设计稿 media.jsx HomeOverview 末节）。接 videoListProvider
/// 的 recentVideos，空库时显示提示卡。
class _RecentlyAdded extends ConsumerWidget {
  const _RecentlyAdded();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    final state = ref.watch(videoListProvider);
    final recents = (state is VideoListLoaded
            ? state.recentVideos
            : const <VideoMetadata>[])
        .take(7)
        .toList();

    if (recents.isEmpty) {
      return AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        child: Row(
          children: [
            Icon(Icons.movie_outlined, size: 22, color: t.text3),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l.homeEmptyRecentlyAddedHint,
                style: TextStyle(fontSize: 13, color: t.text2),
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        childAspectRatio: 0.58,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: recents.length,
      itemBuilder: (_, i) {
        final m = recents[i];
        final poster = m.localPosterUrl ?? m.posterUrl;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _Poster(url: poster, fallback: t.insetBg),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              m.displayTitle,
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
                if (m.year != null) '${m.year}',
                if (m.rating != null) '★ ${m.rating!.toStringAsFixed(1)}',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: t.accentBright),
            ),
          ],
        );
      },
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.url, required this.fallback});
  final String? url;
  final Color fallback;

  @override
  Widget build(BuildContext context) {
    final fb = ColoredBox(
      color: fallback,
      child: const Center(
        child: Icon(Icons.movie_outlined, size: 22, color: Colors.white24),
      ),
    );
    if (url == null || url!.isEmpty) return fb;
    if (url!.startsWith('file://')) {
      return Image.file(
        File(url!.substring(7)),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fb,
      );
    }
    return Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => fb);
  }
}
