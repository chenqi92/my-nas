import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/pt_sites/domain/entities/pt_torrent.dart';
import 'package:my_nas/features/pt_sites/presentation/providers/pt_site_provider.dart';
import 'package:my_nas/features/pt_sites/presentation/widgets/send_to_downloader_sheet.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/atoms/app_card.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_page_scaffold.dart';
import 'package:my_nas/shared/widgets/dialogs/pt_torrent_detail_sheet.dart';

/// 桌面端「PT 站点」——列出已配置站点，展示用户信息 + 种子浏览/搜索。
class PtSitesDesktopPage extends ConsumerStatefulWidget {
  const PtSitesDesktopPage({super.key});

  @override
  ConsumerState<PtSitesDesktopPage> createState() => _PtSitesDesktopPageState();
}

class _PtSitesDesktopPageState extends ConsumerState<PtSitesDesktopPage> {
  String? _sourceId;
  final _searchCtrl = TextEditingController();
  final _connected = <String>{};

  /// 正在连接中的站点（去重并发触发，且不预先标记成功）。
  final _connecting = <String>{};

  /// 本地分类过滤（电影/剧集/音乐），设计稿为本地单选态。
  String? _category;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _ensureConnected(String sourceId) async {
    if (_connected.contains(sourceId) || _connecting.contains(sourceId)) return;
    final conn = ref.read(ptSiteConnectionProvider(sourceId));
    if (conn.status == PTSiteConnectionStatus.connected) {
      _connected.add(sourceId);
      await ref
          .read(ptTorrentListProvider(sourceId).notifier)
          .loadTorrents(refresh: true);
      return;
    }
    final sources = ref.read(ptSitesSourcesProvider);
    final source = sources.where((s) => s.id == sourceId).firstOrNull;
    if (source == null) return;
    _connecting.add(sourceId);
    try {
      await ref
          .read(ptSiteConnectionProvider(sourceId).notifier)
          .connect(source);
      // 仅连接成功后才标记，失败保持未标记，下次仍会重试。
      if (ref.read(ptSiteConnectionProvider(sourceId)).status ==
          PTSiteConnectionStatus.connected) {
        _connected.add(sourceId);
        await ref
            .read(ptTorrentListProvider(sourceId).notifier)
            .loadTorrents(refresh: true);
      }
    } finally {
      _connecting.remove(sourceId);
    }
  }

  void _search(String sourceId) {
    ref.read(ptTorrentListProvider(sourceId).notifier)
      ..setKeyword(
        _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      )
      ..loadTorrents(refresh: true);
  }

  /// 本地分类过滤：后端无独立分类字段时按 category 文案模糊匹配。
  /// 计数与表格共用，保证「找到 N 条」与实际行数一致。
  List<PTTorrent> _applyCategory(List<PTTorrent> torrents) {
    if (_category == null) return torrents;
    return torrents
        .where((x) => (x.category ?? '').contains(_category!))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final sources = ref.watch(ptSitesSourcesProvider);

    if (sources.isEmpty) {
      return DesktopPageScaffold(
        title: l.ptPageTitle,
        subtitle: l.ptPageSubtitle,
        body: DesktopComingSoon(
          icon: Icons.rss_feed_rounded,
          message: l.ptPageEmptyHint,
        ),
      );
    }

    final selected = _sourceId ?? sources.first.id;

    // 消费来自影视详情「在 PT 搜索」的待搜索关键词：填入搜索框 + 设置 keyword，
    // 站点连接后的加载会自动套用；若已连接则立即刷新。
    final pendingSearch = ref.read(ptPendingSearchProvider);
    if (pendingSearch != null) {
      _searchCtrl.text = pendingSearch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(ptPendingSearchProvider.notifier).state = null;
        final notifier = ref.read(ptTorrentListProvider(selected).notifier)
          ..setKeyword(pendingSearch);
        if (_connected.contains(selected)) {
          notifier.loadTorrents(refresh: true);
        }
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureConnected(selected);
    });

    final conn = ref.watch(ptSiteConnectionProvider(selected));
    final listState = ref.watch(ptTorrentListProvider(selected));

    return DesktopPageScaffold(
      title: l.ptPageTitle,
      subtitle: l.ptPageSubtitle,
      maxWidth: 1500,
      actions: sources.length > 1
          ? Row(
              children: [
                for (final s in sources)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: AppChip(
                      label: s.displayName,
                      active: s.id == selected,
                      compact: true,
                      onTap: () => setState(() => _sourceId = s.id),
                    ),
                  ),
              ],
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SiteStatsRow(sources: sources),
          const SizedBox(height: 20),
          _SearchPanel(
            controller: _searchCtrl,
            resultCount: _applyCategory(listState.torrents).length,
            category: _category,
            onCategory: (c) =>
                setState(() => _category = _category == c ? null : c),
            onSubmit: () => _search(selected),
            child: _resultsBody(context, t, conn, listState, selected),
          ),
        ],
      ),
    );
  }

  Widget _resultsBody(
    BuildContext context,
    DesignTokens t,
    PTSiteConnection conn,
    PTTorrentListState listState,
    String selected,
  ) {
    final l = AppLocalizations.of(context);
    if (conn.status == PTSiteConnectionStatus.error) {
      return _PanelMessage(
        icon: Icons.link_off_rounded,
        message: l.ptPageConnectFailed(
          conn.errorMessage ?? l.ptPageConnectFailedFallback,
        ),
      );
    }
    if (listState.isLoading) {
      return const SizedBox(
        height: 240,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (listState.error != null) {
      return _PanelMessage(
        icon: Icons.error_outline_rounded,
        message: listState.error!,
      );
    }

    final rows = _applyCategory(listState.torrents);

    if (rows.isEmpty) {
      return _PanelMessage(
        icon: Icons.inbox_outlined,
        message: l.ptPageNoMatch,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ResultHeaderRow(),
        for (final torrent in rows)
          _ResultRow(
            torrent: torrent,
            onOpen: () => showDialog<void>(
              context: context,
              barrierColor: Colors.black.withValues(alpha: 0.55),
              builder: (_) =>
                  PtTorrentDetailSheet(torrent: torrent, sourceId: selected),
            ),
            onDownload: () => showAdaptiveModalSheet<void>(
              context: context,
              builder: (_) =>
                  SendToDownloaderSheet(torrent: torrent, sourceId: selected),
            ),
          ),
        if (listState.hasMore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: OutlinedButton(
                onPressed: () => ref
                    .read(ptTorrentListProvider(selected).notifier)
                    .loadMore(),
                child: listState.isLoadingMore
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l.ptPageLoadMore),
              ),
            ),
          ),
      ],
    );
  }
}

/// 设计稿 `.stat-row`：每个站点一张统计卡片（分享率 / 魔力 / 上传 + 等级）。
class _SiteStatsRow extends StatelessWidget {
  const _SiteStatsRow({required this.sources});
  final List<SourceEntity> sources;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      // 与 .stat-row minmax(240) 对齐的响应式列数。
      const minTile = 240.0;
      const gap = 14.0;
      final cols = ((c.maxWidth + gap) / (minTile + gap)).floor().clamp(1, 4);
      final tileW = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final s in sources)
            SizedBox(
              width: tileW,
              child: _SiteStatCard(sourceId: s.id),
            ),
        ],
      );
    },
  );
}

class _SiteStatCard extends ConsumerWidget {
  const _SiteStatCard({required this.sourceId});
  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final conn = ref.watch(ptSiteConnectionProvider(sourceId));
    final user = conn.userInfo;
    final connecting = conn.status == PTSiteConnectionStatus.connecting;
    final ratioVal = user?.ratio;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  conn.source.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: t.text0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (connecting)
            const SizedBox(
              height: 38,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            Row(
              children: [
                _metric(
                  l.ptPageRatio,
                  user?.formattedRatio ?? '—',
                  (ratioVal != null && ratioVal > 4) ? t.ok : t.text0,
                  t,
                ),
                const SizedBox(width: 16),
                _metric(
                  l.ptPageBonus,
                  user != null ? user.formattedBonus : '—',
                  t.text0,
                  t,
                ),
                const SizedBox(width: 16),
                _metric(
                  l.ptPageUploaded,
                  user?.formattedUploaded ?? '—',
                  t.accentBright,
                  t,
                ),
              ],
            ),
          const SizedBox(height: 9),
          Text(
            user?.userClass ?? '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: t.text2),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, Color color, DesignTokens t) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 1),
          Text(label, style: TextStyle(fontSize: 10, color: t.text2)),
        ],
      );
}

/// 设计稿 `.panel`：顶部融入搜索框 + 分类 chip + 计数，下方 dense 表格。
class _SearchPanel extends StatelessWidget {
  const _SearchPanel({
    required this.controller,
    required this.resultCount,
    required this.category,
    required this.onCategory,
    required this.onSubmit,
    required this.child,
  });

  final TextEditingController controller;
  final int resultCount;
  final String? category;
  final ValueChanged<String> onCategory;
  final VoidCallback onSubmit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.hairline)),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 17, color: t.text2),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onSubmitted: (_) => onSubmit(),
                    cursorColor: t.accent,
                    style: TextStyle(color: t.text0, fontSize: 13),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: l.ptPageSearchHint,
                      hintStyle: TextStyle(color: t.text3, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // key 为后端 category 文案匹配用的过滤值（须保持中文），value 为本地化展示标签。
                for (final entry in <String, String>{
                  '电影': l.ptPageCategoryMovie,
                  '剧集': l.ptPageCategoryTv,
                  '音乐': l.ptPageCategoryMusic,
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: AppChip(
                      label: entry.value,
                      active: category == entry.key,
                      onTap: () => onCategory(entry.key),
                    ),
                  ),
                const SizedBox(width: 12),
                Text(
                  l.ptPageResultCount(resultCount),
                  style: TextStyle(fontSize: 12, color: t.text2),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// 设计稿 `.dense-table thead`：标题/大小/做种/下载/评分/折扣/操作。
class _ResultHeaderRow extends StatelessWidget {
  const _ResultHeaderRow();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    TextStyle s() => TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      color: t.text3,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(l.ptPageColTitle, style: s())),
          const SizedBox(width: 10),
          SizedBox(width: 90, child: Text(l.ptPageColSize, style: s())),
          SizedBox(width: 70, child: Text(l.ptPageColSeeders, style: s())),
          SizedBox(width: 70, child: Text(l.ptPageColLeechers, style: s())),
          SizedBox(width: 90, child: Text(l.ptPageColRating, style: s())),
          SizedBox(width: 80, child: Text(l.ptPageColPromo, style: s())),
          SizedBox(width: 180, child: Text(l.ptPageColActions, style: s())),
        ],
      ),
    );
  }
}

/// 设计稿 `.dense-table tbody tr`：单行种子结果。
class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.torrent,
    required this.onOpen,
    required this.onDownload,
  });

  final PTTorrent torrent;
  final VoidCallback onOpen;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final promo = torrent.status.promotionLabel;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        hoverColor: t.chipBg,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.hairline)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  torrent.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.text0,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 90,
                child: Text(
                  torrent.formattedSize,
                  style: TextStyle(
                    fontSize: 12,
                    color: t.text2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  '${torrent.seeders}',
                  style: TextStyle(
                    fontSize: 12,
                    color: torrent.seeders > 0 ? t.ok : t.text3,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  '${torrent.leechers}',
                  style: TextStyle(
                    fontSize: 12,
                    color: t.text2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(width: 90, child: _RatingCell(torrent: torrent)),
              SizedBox(
                width: 80,
                child: promo != null
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: AppTag(
                          promo,
                          variant:
                              torrent.status.isFree ||
                                  torrent.status.isDoubleFree
                              ? TagVariant.free
                              : TagVariant.accent,
                        ),
                      )
                    : Text('—', style: TextStyle(fontSize: 11, color: t.text3)),
              ),
              SizedBox(
                width: 180,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    FilledButton.icon(
                      onPressed: onDownload,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        minimumSize: const Size(0, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      icon: const Icon(Icons.download_rounded, size: 13),
                      label: Text(l.ptPageSendToDownloader),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: onOpen,
                      tooltip: l.ptPageDetail,
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      style: IconButton.styleFrom(
                        backgroundColor: t.chipBg,
                        minimumSize: const Size(28, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: Icon(Icons.chevron_right_rounded, color: t.text2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 评分列：后端只有 douban/imdb 的 ID（无具体评分数值），按存在性降级为标记。
class _RatingCell extends StatelessWidget {
  const _RatingCell({required this.torrent});
  final PTTorrent torrent;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final hasDouban = torrent.doubanId != null && torrent.doubanId!.isNotEmpty;
    final hasImdb = torrent.imdbId != null && torrent.imdbId!.isNotEmpty;
    if (!hasDouban && !hasImdb) {
      return Text('—', style: TextStyle(fontSize: 11, color: t.text3));
    }
    return Row(
      children: [
        if (hasDouban)
          Text(
            l.ptPageRatingDouban,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: t.accentBright,
            ),
          ),
        if (hasImdb) ...[
          if (hasDouban) const SizedBox(width: 6),
          Text('IMDb', style: TextStyle(fontSize: 11, color: t.text2)),
        ],
      ],
    );
  }
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 42),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: t.text3),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: t.text2),
            ),
          ],
        ),
      ),
    );
  }
}
