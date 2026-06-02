import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/pt_sites/presentation/providers/pt_site_provider.dart';
import 'package:my_nas/features/pt_sites/presentation/widgets/pt_torrent_card.dart';
import 'package:my_nas/features/pt_sites/presentation/widgets/send_to_downloader_sheet.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';
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

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _ensureConnected(String sourceId) async {
    if (_connected.contains(sourceId)) return;
    _connected.add(sourceId);
    final sources = ref.read(ptSitesSourcesProvider);
    final source = sources.where((s) => s.id == sourceId).firstOrNull;
    if (source == null) return;
    final conn = ref.read(ptSiteConnectionProvider(sourceId));
    if (conn.status != PTSiteConnectionStatus.connected) {
      await ref.read(ptSiteConnectionProvider(sourceId).notifier).connect(source);
    }
    await ref.read(ptTorrentListProvider(sourceId).notifier).loadTorrents(refresh: true);
  }

  void _search(String sourceId) {
    ref.read(ptTorrentListProvider(sourceId).notifier)
      ..setKeyword(_searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim())
      ..loadTorrents(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final sources = ref.watch(ptSitesSourcesProvider);

    if (sources.isEmpty) {
      return const DesktopPageScaffold(
        title: 'PT 站点',
        subtitle: '资源站点聚合 — 浏览 / 搜索 / 一键发送到下载器',
        body: DesktopComingSoon(
          icon: Icons.rss_feed_rounded,
          message: '尚未配置 PT 站点。到「数据源」添加资源站点后，这里可浏览种子并一键发送到下载器。',
        ),
      );
    }

    final selected = _sourceId ?? sources.first.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureConnected(selected);
    });

    final conn = ref.watch(ptSiteConnectionProvider(selected));
    final listState = ref.watch(ptTorrentListProvider(selected));

    return DesktopPageScaffold(
      title: 'PT 站点',
      subtitle: '资源站点聚合 — 浏览 / 搜索 / 一键发送到下载器',
      maxWidth: 1400,
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
          _UserInfoBar(conn: conn),
          const SizedBox(height: 14),
          _SearchBar(
            controller: _searchCtrl,
            onSubmit: () => _search(selected),
          ),
          const SizedBox(height: 14),
          if (conn.status == PTSiteConnectionStatus.error)
            DesktopComingSoon(
              icon: Icons.link_off_rounded,
              message: '连接失败：${conn.errorMessage ?? "请检查站点配置"}',
            )
          else if (listState.isLoading)
            const SizedBox(
              height: 280,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (listState.error != null)
            DesktopComingSoon(
              icon: Icons.error_outline_rounded,
              message: listState.error!,
            )
          else if (listState.torrents.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 42),
              decoration: BoxDecoration(
                color: t.panelBg,
                border: Border.all(color: t.panelBorder),
                borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              ),
              child: Center(
                child: Text('没有匹配的种子。',
                    style: TextStyle(fontSize: 13, color: t.text2)),
              ),
            )
          else
            Column(
              children: [
                for (final torrent in listState.torrents)
                  PTTorrentCard(
                    torrent: torrent,
                    onTap: () => showDialog<void>(
                      context: context,
                      barrierColor: Colors.black.withValues(alpha: 0.55),
                      builder: (_) => PtTorrentDetailSheet(
                        torrent: torrent,
                        sourceId: selected,
                      ),
                    ),
                    onDownload: () => showAdaptiveModalSheet<void>(
                      context: context,
                      builder: (_) => SendToDownloaderSheet(
                        torrent: torrent,
                        sourceId: selected,
                      ),
                    ),
                  ),
                if (listState.hasMore)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
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
                          : const Text('加载更多'),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _UserInfoBar extends StatelessWidget {
  const _UserInfoBar({required this.conn});
  final PTSiteConnection conn;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final user = conn.userInfo;
    final connecting = conn.status == PTSiteConnectionStatus.connecting;
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          StatusDot(conn.status == PTSiteConnectionStatus.connected
              ? DotStatus.ok
              : DotStatus.off),
          const SizedBox(width: 10),
          Text(
            user?.username ?? conn.source.displayName,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: t.text0,
            ),
          ),
          if (user?.userClass != null) ...[
            const SizedBox(width: 8),
            Text(user!.userClass!,
                style: TextStyle(fontSize: 12, color: t.text2)),
          ],
          const Spacer(),
          if (connecting)
            const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
          else if (user != null) ...[
            _metric('↑', user.formattedUploaded, t.ok, t),
            _div(t),
            _metric('↓', user.formattedDownloaded, t.accentBright, t),
            _div(t),
            _metric('分享率', user.formattedRatio, t.text0, t),
            _div(t),
            _metric('魔力', user.formattedBonus, t.warn, t),
          ],
        ],
      ),
    );
  }

  Widget _div(DesignTokens t) => Container(
        width: 1,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        color: t.hairline,
      );

  Widget _metric(String label, String value, Color color, DesignTokens t) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: t.text2)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onSubmit});
  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return TextField(
      controller: controller,
      onSubmitted: (_) => onSubmit(),
      decoration: InputDecoration(
        hintText: '搜索种子（标题 / 关键词）…',
        hintStyle: TextStyle(color: t.text3, fontSize: 13),
        prefixIcon: Icon(Icons.search_rounded, size: 18, color: t.text2),
        suffixIcon: TextButton(onPressed: onSubmit, child: const Text('搜索')),
        filled: true,
        fillColor: t.insetBg,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.accent, width: 1.5),
        ),
      ),
      style: TextStyle(color: t.text0, fontSize: 13),
    );
  }
}
