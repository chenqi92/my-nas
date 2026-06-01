import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';

/// 桌面端「直播 / EPG」页面。
///
/// 现阶段铺出 hero + 分类 chips + "尚未配置 M3U8 源" 空态。后续接
/// `LiveStreamService` 提供真实频道与节目单。
class LiveTvDesktopPage extends StatefulWidget {
  const LiveTvDesktopPage({super.key});

  @override
  State<LiveTvDesktopPage> createState() => _LiveTvDesktopPageState();
}

class _LiveTvDesktopPageState extends State<LiveTvDesktopPage> {
  String _cat = '全部';

  static const _cats = ['全部', '央视', '卫视', '体育', '新闻', '电影'];

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 120),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1340),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: t.hot,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                LiveDot(size: 7),
                                SizedBox(width: 6),
                                Text(
                                  'LIVE',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'M3U8 / HLS 频道 · 自适应清晰度 · 电子节目单 (EPG)',
                        style: TextStyle(fontSize: 13, color: t.text2),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final c in _cats)
                        AppChip(
                          label: c,
                          active: c == _cat,
                          onTap: () => setState(() => _cat = c),
                          compact: true,
                        ),
                      const SizedBox(width: 4),
                      const AppChip(
                        label: '管理 M3U8 源',
                        icon: Icons.add_rounded,
                        compact: true,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _Hero(),
              const SizedBox(height: 26),
              Row(
                children: [
                  Text(
                    '节目单',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: t.text0,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '电子节目单 EPG',
                    style: TextStyle(fontSize: 12.5, color: t.text2),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _EpgEmpty(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
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
              t.hot.withValues(alpha: 0.36),
              const Color(0xFF120A0A),
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
                    Colors.black.withValues(alpha: 0.05),
                  ],
                  stops: const [0.0, 0.7],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 28, 36, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: t.hot,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '即将上线',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const AppTag('M3U8'),
                    ],
                  ),
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
                    '通过 sidebar → 数据源 → 添加 M3U8 / HLS 直播源后此处会显示当前直播节目与精选频道。',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.78),
                      height: 1.5,
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

class _EpgEmpty extends StatelessWidget {
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
