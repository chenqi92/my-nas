import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/presentation/pages/music_scraper_sources_page.dart';
import 'package:my_nas/features/music/presentation/providers/music_scraper_provider.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';
import 'package:my_nas/features/video/presentation/pages/scraper_sources_page.dart';
import 'package:my_nas/features/video/presentation/providers/scraper_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';

/// 桌面「设置 › 刮削源」详情 pane。
///
/// 对齐 `design/my-nas/settings_panes.jsx` 的 `PaneScraper`：影视刮削 / 字幕源 /
/// 音乐刮削三组。
/// - 影视来源优先级接 [scraperSourcesProvider]（按 priority 重排 TMDB / 豆瓣组）；
///   完整的源增删改测在 [ScraperSourcesPage]。
/// - 音乐各刮削源开关接 [musicScraperSourcesProvider]（按类型定位 entity）；
///   完整管理在 [MusicScraperSourcesPage]。
/// - 字幕源（OpenSubtitles）暂无独立 provider / 管理页，降级为「即将推出」只读行。
class ScraperPane extends ConsumerWidget {
  const ScraperPane({super.key});

  /// 来源优先级分段值：true=TMDB 优先，false=豆瓣优先。
  bool _isTmdbType(ScraperType type) => type == ScraperType.tmdb;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scraperAsync = ref.watch(scraperSourcesProvider);
    final musicState = ref.watch(musicScraperSourcesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SetHead(
          icon: Icons.auto_awesome_outlined,
          title: '刮削源',
          subtitle: '影视、字幕与音乐的元数据来源与优先级。',
        ),

        // ===== 影视刮削 =====
        SetSection(
          title: '影视刮削',
          hint: 'NFO 优先',
          children: [
            _buildMoviePriorityRow(context, ref, scraperAsync),
            const SetRow(
              title: '解析本地 NFO',
              desc: '优先使用媒体目录内的 .nfo',
              trailing: AppTag('即将推出', variant: TagVariant.plan),
            ),
            SetRow(
              title: '管理刮削源',
              desc: scraperAsync.maybeWhen(
                data: (list) =>
                    '已配置 ${list.length} 个 · 启用 ${list.where((s) => s.isEnabled).length} 个',
                orElse: () => '添加 / 编辑 / 排序 TMDB、豆瓣等来源',
              ),
              last: true,
              trailing: AppButton(
                label: '打开',
                icon: Icons.tune_rounded,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ScraperSourcesPage(),
                  ),
                ),
              ),
            ),
          ],
        ),

        // ===== 字幕源 =====
        SetSection(
          title: '字幕源',
          children: [
            SetRow(
              title: 'OpenSubtitles',
              desc: '在线字幕搜索与下载',
              last: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  AppTag('即将推出', variant: TagVariant.plan),
                ],
              ),
            ),
          ],
        ),

        // ===== 音乐刮削 =====
        SetSection(
          title: '音乐刮削',
          children: [
            _musicSourceRow(
              context,
              ref,
              state: musicState,
              type: MusicScraperType.musicBrainz,
              title: 'MusicBrainz',
              desc: '主元数据来源',
            ),
            _musicSourceRow(
              context,
              ref,
              state: musicState,
              type: MusicScraperType.neteaseMusic,
              title: '网易云',
              desc: '封面 / 歌词补全',
            ),
            _musicSourceRow(
              context,
              ref,
              state: musicState,
              type: MusicScraperType.acoustId,
              title: 'AcoustID 指纹',
              desc: '无标签音频按音频指纹识别',
            ),
            SetRow(
              title: '管理音乐刮削源',
              desc: '已启用 ${musicState.sources.where((s) => s.isEnabled).length} 个 · '
                  '更多来源与优先级',
              last: true,
              trailing: AppButton(
                label: '打开',
                icon: Icons.tune_rounded,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MusicScraperSourcesPage(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 影视「来源优先级」分段：依据当前启用源里 priority 最高（值最小）的类型
  /// 决定 TMDB / 豆瓣，切换时把对应组重排到最前。
  Widget _buildMoviePriorityRow(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<ScraperSourceEntity>> async,
  ) {
    final sources = async.valueOrNull ?? const <ScraperSourceEntity>[];
    final ordered = [...sources]
      ..sort((a, b) => a.priority.compareTo(b.priority));
    final top = ordered.where((s) => s.isEnabled).isNotEmpty
        ? ordered.firstWhere((s) => s.isEnabled)
        : (ordered.isNotEmpty ? ordered.first : null);
    final current = top == null || _isTmdbType(top.type);

    return SetRow(
      title: '来源优先级',
      desc: '命中顺序：本地 NFO → 在线',
      trailing: AppSegmented<bool>(
        value: current,
        onChanged: sources.isEmpty
            ? (_) {}
            : (v) => _applyPriority(ref, ordered, tmdbFirst: v),
        options: const [
          AppSegmentedOption(value: true, label: 'TMDB 优先'),
          AppSegmentedOption(value: false, label: '豆瓣优先'),
        ],
      ),
    );
  }

  /// 把选中的类型组移动到列表最前，复用 notifier 的 reorder（逐步前移）。
  Future<void> _applyPriority(
    WidgetRef ref,
    List<ScraperSourceEntity> ordered, {
    required bool tmdbFirst,
  }) async {
    // 找到目标组里第一个源在当前排序中的位置。
    final targetIndex = ordered.indexWhere(
      (s) => _isTmdbType(s.type) == tmdbFirst,
    );
    if (targetIndex <= 0) return; // 已在最前或不存在该组
    await ref
        .read(scraperSourcesProvider.notifier)
        .reorderSources(targetIndex, 0);
  }

  /// 音乐单个刮削源开关行：按 [type] 在已配置源里定位 entity 后接真实 toggle；
  /// 若该类型尚未添加为源，则展示「未添加」点 + 引导到管理页。
  Widget _musicSourceRow(
    BuildContext context,
    WidgetRef ref, {
    required MusicScraperSourcesState state,
    required MusicScraperType type,
    required String title,
    required String desc,
  }) {
    final t = DesignTokens.of(context);
    MusicScraperSourceEntity? entity;
    for (final s in state.sources) {
      if (s.type == type) {
        entity = s;
        break;
      }
    }

    if (entity == null) {
      return SetRow(
        title: title,
        desc: desc,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const StatusDot(DotStatus.off),
            const SizedBox(width: 8),
            Text(
              '未添加',
              style: TextStyle(fontSize: 12, color: t.text3),
            ),
          ],
        ),
      );
    }

    final src = entity;
    return SetRow(
      title: title,
      desc: desc,
      trailing: AppSwitch(
        value: src.isEnabled,
        onChanged: (v) => ref
            .read(musicScraperSourcesProvider.notifier)
            .toggleSource(src.id, isEnabled: v),
      ),
    );
  }
}
