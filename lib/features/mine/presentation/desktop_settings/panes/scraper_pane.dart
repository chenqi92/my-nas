import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/presentation/pages/music_scraper_sources_page.dart';
import 'package:my_nas/features/music/presentation/providers/music_scraper_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/source_form_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/opensubtitles_service.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';
import 'package:my_nas/features/video/presentation/pages/scraper_sources_page.dart';
import 'package:my_nas/features/video/presentation/providers/scrape_defaults_provider.dart';
import 'package:my_nas/features/video/presentation/providers/scraper_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';
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
/// - 字幕源（OpenSubtitles）接 [hasOpenSubtitlesConfigProvider] 显示连接状态点，
///   「账户」按钮打开 [SourceFormPage]（账号 / API Key 配置是多步表单，保留弹窗）。
class ScraperPane extends ConsumerWidget {
  const ScraperPane({super.key});

  /// 来源优先级分段值：true=TMDB 优先，false=豆瓣优先。
  bool _isTmdbType(ScraperType type) => type == ScraperType.tmdb;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final scraperAsync = ref.watch(scraperSourcesProvider);
    final musicState = ref.watch(musicScraperSourcesProvider);
    final hasOpenSubtitles = ref.watch(hasOpenSubtitlesConfigProvider);
    final scrapeDefaults = ref.watch(scrapeDefaultsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetHead(
          icon: Icons.auto_awesome_outlined,
          title: l.paneScraperTitle,
          subtitle: l.paneScraperSubtitle,
        ),

        // ===== 影视刮削 =====
        SetSection(
          title: l.paneScraperMovieSection,
          hint: l.paneScraperMovieHint,
          children: [
            _buildMoviePriorityRow(context, ref, scraperAsync),
            SetRow(
              title: l.paneScraperGenerateNfoTitle,
              desc: l.paneScraperGenerateNfoDesc,
              trailing: AppSwitch(
                value: scrapeDefaults.generateNfo,
                onChanged: (v) => ref
                    .read(scrapeDefaultsProvider.notifier)
                    .setGenerateNfo(enabled: v),
              ),
            ),
            SetRow(
              title: l.paneScraperDownloadArtworkTitle,
              desc: l.paneScraperDownloadArtworkDesc,
              trailing: AppSwitch(
                value: scrapeDefaults.downloadPoster ||
                    scrapeDefaults.downloadFanart,
                onChanged: (v) {
                  ref.read(scrapeDefaultsProvider.notifier)
                    ..setDownloadPoster(enabled: v)
                    ..setDownloadFanart(enabled: v);
                },
              ),
            ),
            SetRow(
              title: l.paneScraperManageSourcesTitle,
              desc: scraperAsync.maybeWhen(
                data: (list) => l.paneScraperManageSourcesCount(
                  list.length,
                  list.where((s) => s.isEnabled).length,
                ),
                orElse: () => l.paneScraperManageSourcesHint,
              ),
              last: true,
              trailing: AppButton(
                label: l.paneScraperOpenButton,
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
          title: l.paneScraperSubtitleSection,
          children: [
            SetRow(
              title: 'OpenSubtitles',
              desc: hasOpenSubtitles
                  ? l.paneScraperOpenSubtitlesDescConfigured
                  : l.paneScraperOpenSubtitlesDescPublic,
              last: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusDot(hasOpenSubtitles ? DotStatus.ok : DotStatus.off),
                  const SizedBox(width: 8),
                  AppChip(
                    label: l.paneScraperAccountChip,
                    onTap: () => _openOpenSubtitlesAccount(context, ref),
                  ),
                ],
              ),
            ),
          ],
        ),

        // ===== 音乐刮削 =====
        SetSection(
          title: l.paneScraperMusicSection,
          children: [
            _musicSourceRow(
              context,
              ref,
              state: musicState,
              type: MusicScraperType.musicBrainz,
              title: 'MusicBrainz',
              desc: l.paneScraperMusicBrainzDesc,
            ),
            _musicSourceRow(
              context,
              ref,
              state: musicState,
              type: MusicScraperType.neteaseMusic,
              title: l.paneScraperNeteaseTitle,
              desc: l.paneScraperNeteaseDesc,
            ),
            _musicSourceRow(
              context,
              ref,
              state: musicState,
              type: MusicScraperType.acoustId,
              title: l.paneScraperAcoustIdTitle,
              desc: l.paneScraperAcoustIdDesc,
            ),
            SetRow(
              title: l.paneScraperManageMusicSourcesTitle,
              desc: l.paneScraperManageMusicSourcesDesc(
                musicState.sources.where((s) => s.isEnabled).length,
              ),
              last: true,
              trailing: AppButton(
                label: l.paneScraperOpenButton,
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
    final l = AppLocalizations.of(context);
    final sources = async.valueOrNull ?? const <ScraperSourceEntity>[];
    final ordered = [...sources]
      ..sort((a, b) => a.priority.compareTo(b.priority));
    final top = ordered.where((s) => s.isEnabled).isNotEmpty
        ? ordered.firstWhere((s) => s.isEnabled)
        : (ordered.isNotEmpty ? ordered.first : null);
    final current = top == null || _isTmdbType(top.type);

    return SetRow(
      title: l.paneScraperPriorityTitle,
      desc: l.paneScraperPriorityDesc,
      trailing: AppSegmented<bool>(
        value: current,
        onChanged: sources.isEmpty
            ? (_) {}
            : (v) => _applyPriority(ref, ordered, tmdbFirst: v),
        options: [
          AppSegmentedOption(value: true, label: l.paneScraperPriorityTmdbFirst),
          AppSegmentedOption(value: false, label: l.paneScraperPriorityDoubanFirst),
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

  /// 打开 OpenSubtitles 账户配置表单。若已存在 opensubtitles 源则进入编辑模式，
  /// 否则新建。账号 / API Key / 密码属多步表单，复用 [SourceFormPage]。
  void _openOpenSubtitlesAccount(BuildContext context, WidgetRef ref) {
    final sources = ref.read(sourcesProvider).valueOrNull ?? const [];
    SourceEntity? existing;
    for (final s in sources) {
      if (s.type == SourceType.opensubtitles) {
        existing = s;
        break;
      }
    }
    SourceFormPage.openAdaptive<void>(
      context,
      sourceType: SourceType.opensubtitles,
      existingSource: existing,
    );
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
    final l = AppLocalizations.of(context);
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
              l.paneScraperNotAdded,
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
