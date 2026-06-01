import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_card.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';

/// 桌面端「运维总览」。
///
/// 现阶段铺出"实时吞吐 panel + 4 stat tiles + 3 客户端卡片 + 双栏"骨架。
/// 三客户端的 dn/up 真实读取（aria2/qBittorrent/Transmission provider）放在
/// 后续 Group E 完善 downloads_desktop_page 时一并接入。
class OpsOverviewPage extends ConsumerWidget {
  const OpsOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final connections = ref.watch(activeConnectionsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 120),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '运维总览',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: t.text0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '下载器 · 传输 · PT · 自动化 · 数据源 — 一处掌控',
                style: TextStyle(fontSize: 13, color: t.text2),
              ),
              const SizedBox(height: 22),
              _LiveThroughput(),
              const SizedBox(height: 16),
              _StatRow(connectedSources: connections.length),
              const SizedBox(height: 22),
              _ClientsRow(),
              const SizedBox(height: 16),
              _BottomTwoCol(),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveThroughput extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '实时吞吐',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: t.text0,
                ),
              ),
              const SizedBox(width: 9),
              const StatusDot(DotStatus.ok),
              const SizedBox(width: 5),
              Text(
                '聚合 3 个客户端 · 每秒刷新',
                style: TextStyle(fontSize: 11.5, color: t.text2),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(height: 150, child: _ThroughputChart()),
        ],
      ),
    );
  }
}

/// 简易吞吐图：用两条静态 ribbon 表达 dn / up。后续可接真实 sparkline。
class _ThroughputChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return CustomPaint(
      painter: _RibbonPainter(
        accent: t.accent,
        accentBright: t.accentBright,
        text2: t.text2,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  _RibbonPainter({
    required this.accent,
    required this.accentBright,
    required this.text2,
  });

  final Color accent;
  final Color accentBright;
  final Color text2;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final dnPath = Path()..moveTo(0, h);
    final upPath = Path()..moveTo(0, h);
    const points = 60;
    for (var i = 0; i <= points; i++) {
      final x = w * i / points;
      // 用 sin 模拟稳定的吞吐波形（占位，避免 ops 页空白）。
      final dnY = h - h * 0.55 *
          (0.42 + 0.5 * (0.5 + 0.5 * _sinish(i * 0.42)));
      final upY = h - h * 0.28 *
          (0.30 + 0.5 * (0.5 + 0.5 * _sinish(i * 0.55 + 1.4)));
      dnPath.lineTo(x, dnY);
      upPath.lineTo(x, upY);
    }
    dnPath.lineTo(w, h);
    upPath.lineTo(w, h);

    final dnFill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          accentBright.withValues(alpha: 0.30),
          accent.withValues(alpha: 0.02),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(dnPath, dnFill);

    final upFill = Paint()
      ..color = text2.withValues(alpha: 0.10);
    canvas.drawPath(upPath, upFill);
  }

  double _sinish(double x) {
    // 廉价波形，不引入 dart:math
    final wrapped = x - x.toInt();
    return 1 - (wrapped - 0.5).abs() * 4;
  }

  @override
  bool shouldRepaint(covariant _RibbonPainter old) =>
      old.accent != accent ||
      old.accentBright != accentBright ||
      old.text2 != text2;
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.connectedSources});
  final int connectedSources;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.6,
      children: [
        const _StatTile(label: '活动任务', value: '0', unit: '/ 0'),
        _StatTile(
          label: '源在线 · 共 $connectedSources',
          value: '$connectedSources',
          dot: DotStatus.ok,
        ),
        const _StatTile(label: 'PT 平均分享率', value: '—'),
        const _StatTile(label: '订阅追剧中', value: '0', accent: true),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.unit,
    this.accent = false,
    this.dot,
  });

  final String label;
  final String value;
  final String? unit;
  final bool accent;
  final DotStatus? dot;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text.rich(TextSpan(
            children: [
              TextSpan(
                text: value,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: accent ? t.accentBright : t.text0,
                  letterSpacing: -0.4,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (unit != null)
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.text2,
                  ),
                ),
            ],
          )),
          const SizedBox(height: 4),
          Row(
            children: [
              if (dot != null) ...[
                StatusDot(dot!),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12, color: t.text2),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClientsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final clients = const [
      ('qBittorrent', '0', '0.0'),
      ('aria2', '0', '0.0'),
      ('Transmission', '0', '0.0'),
    ];
    return GridView.count(
      crossAxisCount: 3,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 3.0,
      children: clients
          .map((c) => AppCard(
                onTap: () => GoRouter.of(context).go('/download'),
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const StatusDot(DotStatus.off),
                        const SizedBox(width: 9),
                        Text(
                          c.$1,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: t.text0,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '未连接',
                          style: TextStyle(fontSize: 11, color: t.text2),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '↓${c.$3}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: t.accentBright,
                                fontFamily: 'SF Mono',
                                fontFamilyFallback: const ['Menlo'],
                              ),
                            ),
                            Text(
                              'MB/s',
                              style:
                                  TextStyle(fontSize: 10.5, color: t.text2),
                            ),
                          ],
                        ),
                        const SizedBox(width: 18),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '↑${c.$3}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: t.text0,
                                fontFamily: 'SF Mono',
                                fontFamilyFallback: const ['Menlo'],
                              ),
                            ),
                            Text(
                              'MB/s',
                              style:
                                  TextStyle(fontSize: 10.5, color: t.text2),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ))
          .toList(growable: false),
    );
  }
}

class _BottomTwoCol extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 7,
          child: GlassPanel(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '正在下载',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: t.text0,
                      ),
                    ),
                    const Spacer(),
                    const AppChip(
                      label: '下载器',
                      icon: Icons.open_in_new_rounded,
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      '没有正在下载的任务。',
                      style: TextStyle(fontSize: 13, color: t.text2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 5,
          child: GlassPanel(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'PT 概况',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: t.text0,
                      ),
                    ),
                    const Spacer(),
                    const AppChip(
                      label: '站点',
                      icon: Icons.open_in_new_rounded,
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      '尚未配置 PT 站点。',
                      style: TextStyle(fontSize: 13, color: t.text2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
