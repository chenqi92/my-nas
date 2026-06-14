import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/media_management/presentation/pages/media_management_list_page.dart';
import 'package:my_nas/features/media_tracking/presentation/pages/trakt_connection_page.dart';
import 'package:my_nas/features/media_tracking/presentation/providers/trakt_provider.dart';
import 'package:my_nas/features/pt_sites/presentation/pages/pt_sites_list_page.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';

/// 设计稿 `settings_panes.jsx` › PaneSites（站点与追踪）。
///
/// - PT 资源站点：读 [ptSitesSourcesProvider] 真实源列表，行内状态点 +「管理」
///   打开 [PTSitesListPage]。
/// - 媒体追踪：Trakt 接 [traktConnectionProvider]，状态点随连接态变化，
///   「用户统计 / 断开 / 连接」打开 [TraktConnectionPage]。
/// - 媒体管理后端：NAStool 打开 [MediaManagementListPage]；MoviePilot 暂为规划。
class SitesPane extends ConsumerWidget {
  const SitesPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final ptSites = ref.watch(ptSitesSourcesProvider);
    final trakt = ref.watch(traktConnectionProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetHead(
          icon: Icons.flag_circle_outlined,
          title: '站点与追踪',
          subtitle:
              'PT 资源站点、Trakt 媒体追踪与媒体管理后端。OAuth 走系统浏览器 + mynas:// 回调，不嵌 WebView。',
          actions: [
            AppButton(
              label: '添加站点',
              icon: Icons.add_rounded,
              variant: AppButtonVariant.primary,
              onPressed: () => _openPtSites(context),
            ),
          ],
        ),

        // ---- PT 资源站点 ----
        SetSection(
          title: 'PT 资源站点',
          hint: 'APIKey / Cookie · ${ptSites.length} 个',
          children: _buildPtRows(context, t, ptSites),
        ),

        // ---- 媒体追踪 ----
        SetSection(
          title: '媒体追踪',
          children: [
            SetRow(
              title: 'Trakt',
              desc: _traktDesc(trakt),
              leading: StatusDot(_traktDot(trakt.status)),
              trailing: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: trakt.isConnected
                    ? [
                        AppChip(
                          label: '用户统计',
                          onTap: () => _openTrakt(context),
                        ),
                        AppChip(
                          label: '断开',
                          onTap: () => _openTrakt(context),
                        ),
                      ]
                    : [
                        AppChip(
                          label: '连接',
                          icon: Icons.link_rounded,
                          onTap: () => _openTrakt(context),
                        ),
                      ],
              ),
            ),
            SetRow(
              title: '自动上报',
              desc: '播放进度 ≥ 80% 自动标记为已看',
              last: true,
              trailing: const AppTag('即将推出', variant: TagVariant.plan),
            ),
          ],
        ),

        // ---- 媒体管理后端 ----
        SetSection(
          title: '媒体管理后端',
          bottomMargin: false,
          children: [
            SetRow(
              title: 'NAStool',
              desc: '订阅 / 搜索 / 转移 / 刷流 / RSS 源配置',
              leading: StatusDot(
                _backendDot(ref.watch(nastoolSourcesProvider)),
              ),
              trailing: AppChip(
                label: '配置',
                onTap: () => _openMediaManagement(context),
              ),
            ),
            SetRow(
              title: 'MoviePilot',
              desc: '下一代媒体自动化 — 源配置对齐中',
              last: true,
              trailing: const AppTag('即将推出', variant: TagVariant.plan),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildPtRows(
    BuildContext context,
    DesignTokens t,
    List<SourceEntity> sites,
  ) {
    if (sites.isEmpty) {
      return [
        SetRow(
          title: '尚未添加资源站点',
          desc: '添加 M-Team / HDChina 等站点以订阅、搜索与下载',
          last: true,
          trailing: AppButton(
            label: '管理',
            icon: Icons.rss_feed_rounded,
            onPressed: () => _openPtSites(context),
          ),
        ),
      ];
    }
    return [
      for (var i = 0; i < sites.length; i++)
        SetRow(
          title: sites[i].displayName,
          desc: '分享率 / 魔力 / 邀请 / 签到',
          last: i == sites.length - 1,
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: t.chipBgActive,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(Icons.rss_feed_rounded, size: 16, color: t.accentBright),
          ),
          trailing: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const StatusDot(DotStatus.ok),
              AppChip(
                label: '管理',
                onTap: () => _openPtSites(context),
              ),
            ],
          ),
        ),
    ];
  }

  String _traktDesc(TraktConnectionState s) {
    switch (s.status) {
      case TraktConnectionStatus.connected:
        final name = s.userSettings?.username ?? '';
        return name.isNotEmpty
            ? 'OAuth 已授权 · $name · 自动刷新 token'
            : 'OAuth 已授权 · 自动刷新 token · 继续观看合并（本地优先）';
      case TraktConnectionStatus.connecting:
        return '正在授权…';
      case TraktConnectionStatus.error:
        return s.errorMessage ?? '连接出错，请重试';
      case TraktConnectionStatus.disconnected:
        return '未连接 · OAuth 授权后合并 Trakt 进度（本地优先）';
    }
  }

  DotStatus _traktDot(TraktConnectionStatus s) => switch (s) {
        TraktConnectionStatus.connected => DotStatus.ok,
        TraktConnectionStatus.connecting => DotStatus.accent,
        TraktConnectionStatus.error => DotStatus.err,
        TraktConnectionStatus.disconnected => DotStatus.off,
      };

  DotStatus _backendDot(List<SourceEntity> nastool) =>
      nastool.isNotEmpty ? DotStatus.ok : DotStatus.off;

  void _openPtSites(BuildContext context) => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const PTSitesListPage()),
      );

  void _openTrakt(BuildContext context) => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const TraktConnectionPage()),
      );

  void _openMediaManagement(BuildContext context) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const MediaManagementListPage()),
      );
}
