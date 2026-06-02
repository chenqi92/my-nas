import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_card.dart';
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

  String get _greet {
    final h = _now.hour;
    if (h < 6) return '凌晨好';
    if (h < 11) return '早上好';
    if (h < 14) return '中午好';
    if (h < 18) return '下午好';
    return '晚上好';
  }

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final sourcesOnline = ref.watch(activeConnectionsProvider).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 120),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1340),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _NowHero(now: _now, greet: _greet, sourcesOnline: sourcesOnline),
              const SizedBox(height: 30),
              _SectionHead(
                title: '继续',
                sub: '观看 · 阅读 · 收听 — 本地与 Trakt 合并，本地优先',
              ),
              const SizedBox(height: 14),
              _EmptyContinue(),
              const SizedBox(height: 30),
              _SectionHead(title: '快速操作'),
              const SizedBox(height: 14),
              _QuickGrid(),
              const SizedBox(height: 30),
              _SectionHead(title: '人物', sub: '人脸聚类 · 128 维特征'),
              const SizedBox(height: 14),
              _PeopleHint(),
              const SizedBox(height: 8),
              Text(
                '映射「照片」媒体库后这里会出现已识别人物。',
                style: TextStyle(fontSize: 12, color: t.text3),
              ),
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
    return SizedBox(
      height: 340,
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
                          '$greet，欢迎回来',
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
                          '${now.month} 月 ${now.day} 日 · '
                          '${_zhWeek(now.weekday)} · '
                          '$sourcesOnline 个源在线',
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

  String _zhWeek(int w) =>
      ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][w - 1];
}

class _SpotlightCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
      child: Container(
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
                    children: const [
                      AppTag('继续观看', variant: TagVariant.accent),
                      AppTag('4K HDR'),
                      AppTag('Trakt 同步', variant: TagVariant.accent),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '映射「影视」媒体库以激活此处',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.6,
                      shadows: [
                        Shadow(color: Colors.black54, blurRadius: 12),
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
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: const [
                                Text(
                                  '继续观看会自动出现在这里',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFCCCCD0),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const AppProgressBar(value: 0.0),
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
  }
}

class _SystemPulse extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
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
                  '系统脉搏',
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
                  '实时',
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
                    title: '下载吞吐',
                    subtitle: '当前无任务',
                  ),
                  _PulseRow(
                    icon: Icons.image_search_rounded,
                    iconColor: const Color(0xFFFB923C),
                    title: '照片扫描',
                    subtitle: '空闲',
                  ),
                  _PulseRow(
                    icon: Icons.cast_rounded,
                    iconColor: t.hot,
                    title: '直播中',
                    subtitle: '映射 M3U8 源后激活',
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
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: t.insetBg,
              borderRadius: BorderRadius.circular(8),
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

class _EmptyContinue extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      child: Row(
        children: [
          Icon(Icons.history_rounded, size: 22, color: t.text3),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '观看 / 阅读 / 收听任意媒体，进度都会出现在这里。',
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
    final tiles = [
      _QuickItem(
        title: '新建下载',
        desc: '发送磁力 / 直链',
        icon: Icons.download_rounded,
        onTap: () => GoRouter.of(context).go('/download'),
      ),
      _QuickItem(
        title: 'PT 搜索',
        desc: '跨站找资源',
        icon: Icons.flag_circle_outlined,
        onTap: () => GoRouter.of(context).go('/sources'),
      ),
      _QuickItem(
        title: '上传到 NAS',
        desc: '照片 / 文件备份',
        icon: Icons.upload_rounded,
        onTap: () => GoRouter.of(context).go('/transfer'),
      ),
      _QuickItem(
        title: '添加数据源',
        desc: '连接新设备',
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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

class _PeopleHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(width: 18),
        itemBuilder: (_, _) => Column(
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.insetBg,
                border: Border.all(color: t.hairline),
              ),
              child: Icon(Icons.person_outline_rounded,
                  size: 36, color: t.text3),
            ),
            const SizedBox(height: 8),
            Text('未识别',
                style: TextStyle(
                  fontSize: 11.5,
                  color: t.text3,
                )),
          ],
        ),
      ),
    );
  }
}
