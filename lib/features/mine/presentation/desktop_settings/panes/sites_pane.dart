import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/media_management/presentation/pages/media_management_list_page.dart';
import 'package:my_nas/features/media_tracking/presentation/pages/trakt_connection_page.dart';
import 'package:my_nas/features/media_tracking/presentation/providers/trakt_provider.dart';
import 'package:my_nas/features/pt_sites/presentation/pages/pt_sites_list_page.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/trakt_scrobble_service.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';

/// 设计稿 `settings_panes.jsx` › PaneSites（站点与追踪）。
///
/// - PT 资源站点：读 [ptSitesSourcesProvider] 真实源列表，行内状态点 +「管理」
///   打开 [PTSitesListPage]。
/// - 媒体追踪：Trakt 接 [traktConnectionProvider]，状态点随连接态变化，
///   「用户统计 / 断开 / 连接」打开 [TraktConnectionPage]；自动上报开关接
///   [traktScrobbleSettingsProvider]（Hive 持久化）。
/// - 媒体管理后端：NAStool / MoviePilot 均为 [SourceCategory.mediaManagement]
///   源，行内状态点随已配置源变化，「配置」打开 [MediaManagementListPage]。
class SitesPane extends ConsumerWidget {
  const SitesPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final ptSites = ref.watch(ptSitesSourcesProvider);
    final trakt = ref.watch(traktConnectionProvider);
    final scrobble = ref.watch(traktScrobbleSettingsProvider);
    final mediaMgmt = ref.watch(mediaManagementSourcesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetHead(
          icon: Icons.flag_circle_outlined,
          title: l.paneSitesHeadTitle,
          subtitle: l.paneSitesHeadSubtitle,
          actions: [
            AppButton(
              label: l.paneSitesAddButton,
              icon: Icons.add_rounded,
              variant: AppButtonVariant.primary,
              onPressed: () => _openPtSites(context),
            ),
          ],
        ),

        // ---- PT 资源站点 ----
        SetSection(
          title: l.paneSitesPtSectionTitle,
          hint: l.paneSitesPtSectionHint(ptSites.length),
          children: _buildPtRows(context, t, ptSites),
        ),

        // ---- 媒体追踪 ----
        SetSection(
          title: l.paneSitesTrackingSectionTitle,
          children: [
            SetRow(
              title: 'Trakt',
              desc: _traktDesc(context, trakt),
              leading: StatusDot(_traktDot(trakt.status)),
              trailing: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: trakt.isConnected
                    ? [
                        AppChip(
                          label: l.paneSitesTraktStats,
                          onTap: () => _openTrakt(context),
                        ),
                        AppChip(
                          label: l.paneSitesTraktDisconnect,
                          onTap: () => _openTrakt(context),
                        ),
                      ]
                    : [
                        AppChip(
                          label: l.paneSitesTraktConnect,
                          icon: Icons.link_rounded,
                          onTap: () => _openTrakt(context),
                        ),
                      ],
              ),
            ),
            SetRow(
              title: l.paneSitesScrobbleTitle,
              desc: l.paneSitesScrobbleDesc(
                scrobble.minProgress.toStringAsFixed(0),
              ),
              last: true,
              trailing: AppSwitch(
                value: scrobble.enabled,
                onChanged: (v) => ref
                    .read(traktScrobbleSettingsProvider.notifier)
                    .setEnabled(v),
              ),
            ),
          ],
        ),

        // ---- 媒体管理后端 ----
        SetSection(
          title: l.paneSitesBackendSectionTitle,
          bottomMargin: false,
          children: [
            SetRow(
              title: 'NAStool',
              desc: l.paneSitesNastoolDesc,
              leading: StatusDot(
                _backendDot(ref.watch(nastoolSourcesProvider)),
              ),
              trailing: AppChip(
                label: l.paneSitesConfigure,
                onTap: () => _openMediaManagement(context),
              ),
            ),
            SetRow(
              title: 'MoviePilot',
              desc: l.paneSitesMoviepilotDesc,
              last: true,
              leading: StatusDot(
                _backendDot(
                  mediaMgmt
                      .where((s) => s.type == SourceType.moviepilot)
                      .toList(),
                ),
              ),
              trailing: AppChip(
                label: l.paneSitesConfigure,
                onTap: () => _openMediaManagement(context),
              ),
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
    final l = AppLocalizations.of(context);
    if (sites.isEmpty) {
      return [
        SetRow(
          title: l.paneSitesEmptyTitle,
          desc: l.paneSitesEmptyDesc,
          last: true,
          trailing: AppButton(
            label: l.paneSitesManage,
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
          desc: l.paneSitesPtRowDesc,
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
                label: l.paneSitesManage,
                onTap: () => _openPtSites(context),
              ),
            ],
          ),
        ),
    ];
  }

  String _traktDesc(BuildContext context, TraktConnectionState s) {
    final l = AppLocalizations.of(context);
    switch (s.status) {
      case TraktConnectionStatus.connected:
        final name = s.userSettings?.username ?? '';
        return name.isNotEmpty
            ? l.paneSitesTraktDescConnectedNamed(name)
            : l.paneSitesTraktDescConnected;
      case TraktConnectionStatus.connecting:
        return l.paneSitesTraktDescConnecting;
      case TraktConnectionStatus.error:
        return s.errorMessage ?? l.paneSitesTraktDescError;
      case TraktConnectionStatus.disconnected:
        return l.paneSitesTraktDescDisconnected;
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
