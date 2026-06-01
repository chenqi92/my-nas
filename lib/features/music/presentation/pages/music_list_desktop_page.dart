import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_page_scaffold.dart';

/// 桌面端「音乐」骨架。
///
/// 视觉对齐设计稿 media2.jsx (MusicLibrary)：歌曲 / 专辑 / 艺术家 / 文件夹
/// segmented + 听歌统计 stat row + 左歌曲表 + 右 sidepanel（歌单 + EQ）。
class MusicListDesktopPage extends StatefulWidget {
  const MusicListDesktopPage({super.key});

  @override
  State<MusicListDesktopPage> createState() => _MusicListDesktopPageState();
}

class _MusicListDesktopPageState extends State<MusicListDesktopPage> {
  String _view = 'songs';

  @override
  Widget build(BuildContext context) {
    return DesktopPageScaffold(
      title: '音乐',
      subtitle: 'Gapless · 10 段 EQ · NCM 解密 · MusicBrainz / AcoustID 刮削',
      actions: AppSegmented<String>(
        value: _view,
        onChanged: (v) => setState(() => _view = v),
        dense: true,
        options: const [
          AppSegmentedOption(value: 'songs', label: '歌曲'),
          AppSegmentedOption(value: 'albums', label: '专辑'),
          AppSegmentedOption(value: 'artists', label: '艺术家'),
          AppSegmentedOption(value: 'folders', label: '文件夹'),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 7,
            child: GlassPanel(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: const SizedBox(
                height: 380,
                child: DesktopComingSoon(
                  icon: Icons.queue_music_rounded,
                  message: '映射「音乐」媒体库后，此处显示歌曲 dense-table\n'
                      '（编号 / 标题 / 艺术家 / 专辑 / 收藏 / 时长）。',
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            flex: 3,
            child: Column(
              children: const [
                _SidePanel(
                  title: '歌单',
                  icon: Icons.library_music_outlined,
                  message: '我喜欢 / 自建歌单将显示在这里。',
                ),
                SizedBox(height: 18),
                _SidePanel(
                  title: '均衡器',
                  icon: Icons.equalizer_rounded,
                  message: '10 段 EQ + 8 预设 + 自定义保存。',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.title,
    required this.icon,
    required this.message,
  });

  final String title;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: t.accentBright),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: t.text0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(fontSize: 12, color: t.text2, height: 1.5),
          ),
        ],
      ),
    );
  }
}
