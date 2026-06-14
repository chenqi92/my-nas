import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/video/domain/entities/live_stream_models.dart';
import 'package:my_nas/features/video/presentation/pages/live_player_page.dart';
import 'package:my_nas/features/video/presentation/pages/live_stream_settings_page.dart';
import 'package:my_nas/features/video/presentation/providers/live_stream_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';

/// 桌面端「直播 / EPG」页面。
///
/// 对齐设计稿 `live.jsx` LiveTV：精选频道 hero + 电子节目单时间轴。
/// 数据取自真实 M3U/HLS 频道（[allLiveChannelsProvider]）。节目单的「节目」
/// 数据需 XMLTV/EPG 源解析，当前数据层未提供，故时间轴只渲染频道与当前时间
/// 红线，节目轨道留空（不伪造节目），点击频道行即可直接播放。
class LiveTvDesktopPage extends ConsumerStatefulWidget {
  const LiveTvDesktopPage({super.key});

  @override
  ConsumerState<LiveTvDesktopPage> createState() => _LiveTvDesktopPageState();
}

class _LiveTvDesktopPageState extends ConsumerState<LiveTvDesktopPage> {
  String _cat = '全部';
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    // 每分钟刷新，让 EPG 的「当前时间红线」与时钟随真实时间走，
    // 而非只在 build 时算一次后静止。
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  void _play(LiveChannel channel) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => LivePlayerPage(channel: channel)),
    );
  }

  void _manageSources() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LiveStreamSettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final allChannels = ref.watch(allLiveChannelsProvider);
    final sources = ref.watch(enabledLiveSourcesProvider);
    final cats = <String>[
      '全部',
      ...(ref.watch(liveChannelCategoriesProvider).toList()..sort()),
    ];
    final active = cats.contains(_cat) ? _cat : '全部';
    final channels = active == '全部'
        ? allChannels
        : allChannels
            .where((c) => (c.category ?? '未分类') == active)
            .toList();
    final featured = channels.isNotEmpty ? channels.first : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 120),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1340),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(t, cats, active),
              const SizedBox(height: 22),
              if (featured == null) ...[
                _EmptyHero(onManage: _manageSources),
                const SizedBox(height: 26),
                _sectionHead(t, sub: '电子节目单 EPG'),
                const SizedBox(height: 14),
                const _EpgEmpty(),
              ] else ...[
                _Hero(
                  channel: featured,
                  sourceName: _sourceNameFor(featured, sources),
                  onPlay: () => _play(featured),
                ),
                const SizedBox(height: 26),
                _sectionHead(
                  t,
                  sub: '电子节目单 · ${_fmtClock(_nowMin())} 现在',
                  right: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PulseDot(color: t.hot, size: 8),
                      const SizedBox(width: 6),
                      Text('红线为当前时间',
                          style: TextStyle(fontSize: 12, color: t.text2)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '节目（EPG）数据需 XMLTV 源，当前仅展示频道与时间轴；点击频道行即可直接播放。',
                  style: TextStyle(fontSize: 12, color: t.text3, height: 1.4),
                ),
                const SizedBox(height: 12),
                _EpgGuide(channels: channels, onPlay: _play),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── header ────────────────────────────────────────────────────────────
  Widget _buildHeader(DesignTokens t, List<String> cats, String active) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '直播',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: t.text0,
                  ),
                ),
                const SizedBox(width: 12),
                const _LiveBadge('LIVE'),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'M3U8 / HLS 频道 · 自适应清晰度 · 电子节目单 (EPG)',
              style: TextStyle(fontSize: 13, color: t.text2),
            ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final c in cats)
                AppChip(
                  label: c,
                  active: c == active,
                  onTap: () => setState(() => _cat = c),
                  compact: true,
                ),
              AppChip(
                label: '管理 M3U8 源',
                icon: Icons.add_rounded,
                compact: true,
                onTap: _manageSources,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHead(DesignTokens t, {required String sub, Widget? right}) {
    return Row(
      children: [
        Text(
          '节目单',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: t.text0,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(width: 10),
        Text(sub, style: TextStyle(fontSize: 12.5, color: t.text2)),
        if (right != null) ...[const Spacer(), right],
      ],
    );
  }

  String? _sourceNameFor(LiveChannel ch, List<LiveStreamSource> sources) {
    for (final s in sources) {
      if (s.channels.any((c) => c.id == ch.id)) return s.name;
    }
    return null;
  }
}

// ── time helpers ──────────────────────────────────────────────────────────
const double _pxPerMin = 4;
const double _channelColW = 184;
const double _epgRowH = 62;
const double _epgHeaderH = 42;
const int _epgMaxRows = 50;

int _nowMin() {
  final n = DateTime.now();
  return n.hour * 60 + n.minute;
}

String _fmtClock(int minutes) {
  final m = minutes % 1440;
  final h = (m ~/ 60).toString().padLeft(2, '0');
  final mm = (m % 60).toString().padLeft(2, '0');
  return '$h:$mm';
}

// ── hero ────────────────────────────────────────────────────────────────
class _Hero extends StatelessWidget {
  const _Hero({
    required this.channel,
    required this.sourceName,
    required this.onPlay,
  });

  final LiveChannel channel;
  final String? sourceName;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
      child: SizedBox(
        height: 300,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 背景：品牌渐变 + 频道 logo 水印（频道无整图，只有小 logo）
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    t.accentDeep.withValues(alpha: 0.55),
                    const Color(0xFF0B0D12),
                  ],
                ),
              ),
            ),
            if (channel.logoUrl != null)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 340,
                child: Opacity(
                  opacity: 0.16,
                  child: CachedNetworkImage(
                    imageUrl: channel.logoUrl!,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerRight,
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                    placeholder: (_, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            // scrim：左深右浅 + 底深
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xF208090C),
                    Color(0xBD08090C),
                    Color(0x5708090C),
                    Color(0x2E08090C),
                  ],
                  stops: [0.0, 0.42, 0.72, 1.0],
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xEB08090C), Color(0x0008090C)],
                  stops: [0.0, 0.64],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 40, 44, 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const _LiveBadge('正在直播'),
                        if (channel.category != null &&
                            channel.category!.isNotEmpty)
                          _whiteTag(channel.category!),
                        const AppTag('M3U8', variant: TagVariant.accent),
                        if (sourceName != null) _whiteTag(sourceName!),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      channel.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.6,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      [
                        if (channel.category != null &&
                            channel.category!.isNotEmpty)
                          channel.category,
                        if (sourceName != null) sourceName,
                        'M3U8 / HLS · 自适应清晰度',
                      ].whereType<String>().join('  ·  '),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        _HeroBtn(
                          label: '立即观看',
                          icon: Icons.play_arrow_rounded,
                          variant: _HeroBtnVariant.primary,
                          onTap: onPlay,
                        ),
                        const SizedBox(width: 12),
                        _HeroBtn(
                          label: '完整节目单',
                          icon: Icons.view_agenda_outlined,
                          variant: _HeroBtnVariant.outline,
                          onTap: onPlay,
                        ),
                        const SizedBox(width: 12),
                        _HeroBtn(
                          icon: Icons.cast_rounded,
                          variant: _HeroBtnVariant.ghost,
                          onTap: onPlay,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _whiteTag(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      );
}

enum _HeroBtnVariant { primary, outline, ghost }

class _HeroBtn extends StatelessWidget {
  const _HeroBtn({
    required this.icon,
    required this.variant,
    required this.onTap,
    this.label,
  });

  final IconData icon;
  final _HeroBtnVariant variant;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final Color bg;
    final Color fg;
    final Border? border;
    final FontWeight weight;
    switch (variant) {
      case _HeroBtnVariant.primary:
        bg = t.accent;
        fg = t.accentContrast;
        border = null;
        weight = FontWeight.w600;
      case _HeroBtnVariant.outline:
        bg = Colors.white.withValues(alpha: 0.12);
        fg = Colors.white;
        border = Border.all(color: Colors.white.withValues(alpha: 0.18));
        weight = FontWeight.w500;
      case _HeroBtnVariant.ghost:
        bg = Colors.transparent;
        fg = Colors.white;
        border = null;
        weight = FontWeight.w500;
    }
    final iconOnly = label == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        child: Container(
          padding: iconOnly
              ? const EdgeInsets.all(9)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            border: border,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              if (!iconOnly) ...[
                const SizedBox(width: 7),
                Text(
                  label!,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: weight,
                    color: fg,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── EPG guide ─────────────────────────────────────────────────────────────
class _EpgGuide extends StatelessWidget {
  const _EpgGuide({required this.channels, required this.onPlay});

  final List<LiveChannel> channels;
  final void Function(LiveChannel) onPlay;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final shown = channels.length > _epgMaxRows
        ? channels.sublist(0, _epgMaxRows)
        : channels;

    final now = _nowMin();
    // 时间窗：当前时刻向前对齐到半点的前一格，向后展开约 6 小时。
    final base = ((now - 30) ~/ 30) * 30;
    const span = 360; // 6h
    final end = base + span;
    final timelineW = span * _pxPerMin;
    final gridW = _channelColW + timelineW;
    final playX = _channelColW + (now - base) * _pxPerMin;

    final slots = <int>[for (var m = base; m <= end; m += 30) m];
    final contentH = _epgHeaderH + shown.length * _epgRowH;

    final grid = SizedBox(
      width: gridW,
      height: contentH,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(t, slots, base, timelineW),
              for (final ch in shown) _row(context, t, ch, timelineW),
            ],
          ),
          // 当前时间红线（节目区，从表头下方开始）
          Positioned(
            left: playX,
            top: _epgHeaderH,
            bottom: 0,
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                color: t.hot,
                boxShadow: [
                  BoxShadow(
                    color: t.hot.withValues(alpha: 0.6),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
          // now-pill（表头内）；FractionalTranslation(-0.5) = 设计稿 translateX(-50%)，
          // 居中于红线，与 pill 实际宽度无关。
          Positioned(
            left: playX,
            top: 9,
            child: FractionalTranslation(
              translation: const Offset(-0.5, 0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: t.hot,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  _fmtClock(now),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Widget body = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: grid,
    );
    // 仅在内容超高时套竖向滚动，避免短列表抢占整页滚动手势。
    if (contentH > 540) {
      body = SizedBox(
        height: 540,
        child: SingleChildScrollView(child: body),
      );
    }

    return GlassPanel(
      padding: EdgeInsets.zero,
      radius: DesignTokens.radiusLg,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        child: body,
      ),
    );
  }

  Widget _header(
      DesignTokens t, List<int> slots, int base, double timelineW) {
    TextStyle cornerStyle() => TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: t.text3,
        );
    return Container(
      height: _epgHeaderH,
      decoration: BoxDecoration(
        color: t.panelBgStrong,
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: Row(
        children: [
          Container(
            width: _channelColW,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('频道', style: cornerStyle()),
          ),
          SizedBox(
            width: timelineW,
            height: _epgHeaderH,
            child: Stack(
              children: [
                for (final m in slots)
                  Positioned(
                    left: (m - base) * _pxPerMin,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.only(left: 10),
                      decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: t.hairline)),
                      ),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _fmtClock(m),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: t.text2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
      BuildContext context, DesignTokens t, LiveChannel ch, double timelineW) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onPlay(ch),
        hoverColor: t.cardBgHover,
        child: Container(
          height: _epgRowH,
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: t.hairline)),
          ),
          child: Row(
            children: [
              // 频道列
              Container(
                width: _channelColW,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    _ChannelLogo(channel: ch),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  ch.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: t.text0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            ch.categoryDisplayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10.5, color: t.text2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 节目轨道（暂无 EPG 节目数据，留空）
              SizedBox(width: timelineW, height: _epgRowH),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelLogo extends StatelessWidget {
  const _ChannelLogo({required this.channel});
  final LiveChannel channel;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final name = channel.displayName.trim();
    final initials = name.length <= 2 ? name : name.substring(0, 2);
    final fallback = Container(
      alignment: Alignment.center,
      color: t.chipBgActive,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: t.accentBright,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 34,
        height: 34,
        child: channel.logoUrl != null
            ? CachedNetworkImage(
                imageUrl: channel.logoUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => fallback,
                placeholder: (_, _) => fallback,
              )
            : fallback,
      ),
    );
  }
}

// ── live badge / pulse dot ──────────────────────────────────────────────
class _LiveBadge extends StatelessWidget {
  const _LiveBadge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: t.hot,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _PulseDot(color: Colors.white, size: 7),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// 设计稿 `.live-pulse` / `.live-dot`：1.6s 呼吸点。
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, this.size = 8});
  final Color color;
  final double size;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.35).animate(
        CurvedAnimation(parent: _c, curve: DesignTokens.ease),
      ),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.7),
              blurRadius: 8,
            ),
          ],
        ),
      ),
    );
  }
}

// ── empty states ──────────────────────────────────────────────────────────
class _EmptyHero extends StatelessWidget {
  const _EmptyHero({required this.onManage});

  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
      child: Container(
        height: 260,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              t.accentDeep.withValues(alpha: 0.4),
              const Color(0xFF0B0D12),
            ],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xEB08090C), Color(0x0D08090C)],
                  stops: [0.0, 0.7],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 40, 44, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const _LiveBadge('即将上线'),
                  const SizedBox(height: 14),
                  const Text(
                    '导入 M3U8 频道源以激活',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '在「管理直播源」中添加 M3U8 / HLS 直播源后，此处会显示精选频道与电子节目单。',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.78),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: onManage,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('管理直播源'),
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

class _EpgEmpty extends StatelessWidget {
  const _EpgEmpty();

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 38),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.live_tv_outlined, size: 40, color: t.text3),
            const SizedBox(height: 12),
            Text(
              '尚未配置直播源',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: t.text1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '添加 M3U8 / HLS 源后将自动生成电子节目单（pxPerMin=4，sticky 频道列）。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
