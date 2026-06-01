import 'package:flutter/material.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_page_scaffold.dart';

/// 桌面端「影视库」骨架。
///
/// 视觉对齐设计稿 films.jsx：库 segmented + 类型 chips + 海报 grid +
/// 「继续观看」strip。具体海报数据接入沿用 `VideoListPage` 的 Notifier
/// 体系，后续单独 wire（见 plan Group E）。
class VideoListDesktopPage extends StatefulWidget {
  const VideoListDesktopPage({super.key});

  @override
  State<VideoListDesktopPage> createState() => _VideoListDesktopPageState();
}

class _VideoListDesktopPageState extends State<VideoListDesktopPage> {
  String _kind = '全部';
  String _view = 'grid';

  @override
  Widget build(BuildContext context) {
    return DesktopPageScaffold(
      title: '影视',
      subtitle: 'Trakt 同步 · 多版本 · 智能续播 · TMDB / 豆瓣 刮削',
      actions: Row(
        children: [
          AppSegmented<String>(
            value: _view,
            onChanged: (v) => setState(() => _view = v),
            dense: true,
            options: const [
              AppSegmentedOption(
                value: 'grid',
                label: '网格',
                icon: Icons.grid_view_rounded,
              ),
              AppSegmentedOption(
                value: 'list',
                label: '列表',
                icon: Icons.view_list_rounded,
              ),
            ],
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final k in const ['全部', '电影', '剧集', '动画', '纪录片'])
                AppChip(
                  label: k,
                  active: k == _kind,
                  compact: true,
                  onTap: () => setState(() => _kind = k),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const DesktopComingSoon(
            icon: Icons.movie_outlined,
            message: '映射「影视」媒体库后，此处显示海报网格 + 继续观看 strip。\n'
                '点击海报会打开「影视详情」浮层（多版本 / 剧集分集 / 演职 / 相关）。',
          ),
        ],
      ),
    );
  }
}
