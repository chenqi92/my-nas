import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/app/theme/ui_style.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/app_lock/presentation/pages/privacy_security_page.dart';
import 'package:my_nas/features/book/presentation/pages/book_settings_page.dart';
import 'package:my_nas/features/book/presentation/pages/book_sources_page.dart';
import 'package:my_nas/features/downloader/presentation/pages/downloader_list_page.dart';
import 'package:my_nas/features/media_management/presentation/pages/media_management_list_page.dart';
import 'package:my_nas/features/media_tracking/presentation/pages/media_tracking_list_page.dart';
import 'package:my_nas/features/mine/presentation/desktop_settings/desktop_settings_screen.dart';
import 'package:my_nas/features/mine/presentation/pages/appearance_settings_page.dart';
import 'package:my_nas/features/mine/presentation/pages/hosts_mapping_page.dart';
import 'package:my_nas/features/mine/presentation/pages/spotlight_settings_page.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/presentation/pages/duplicate_songs_page.dart';
import 'package:my_nas/features/music/presentation/pages/listening_stats_page.dart';
import 'package:my_nas/features/music/presentation/pages/music_player_settings_page.dart';
import 'package:my_nas/features/music/presentation/pages/music_scraper_sources_page.dart';
import 'package:my_nas/features/music/presentation/pages/recycle_bin_page.dart';
import 'package:my_nas/features/music/presentation/pages/scrobble_settings_page.dart';
import 'package:my_nas/features/music/presentation/providers/music_scraper_provider.dart';
import 'package:my_nas/features/pt_sites/presentation/pages/pt_sites_list_page.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/media_library_page.dart';
import 'package:my_nas/features/sources/presentation/pages/service_sources_page.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/sync/presentation/pages/cloud_sync_settings_page.dart';
import 'package:my_nas/features/transfer/presentation/pages/transfer_manager_page.dart';
import 'package:my_nas/features/transfer/presentation/providers/transfer_provider.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';
import 'package:my_nas/features/video/presentation/pages/live_stream_settings_page.dart';
import 'package:my_nas/features/video/presentation/pages/scraper_sources_page.dart';
import 'package:my_nas/features/video/presentation/pages/video_player_settings_page.dart';
import 'package:my_nas/features/video/presentation/providers/live_stream_provider.dart';
import 'package:my_nas/features/video/presentation/providers/scraper_provider.dart';
import 'package:my_nas/shared/pages/favorites_page.dart';
import 'package:my_nas/shared/providers/language_preference_provider.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_glass_container.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';
import 'package:my_nas/shared/widgets/update_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';

class MinePage extends ConsumerWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final connections = ref.watch(activeConnectionsProvider);
    final connectedCount = connections.values
        .where((c) => c.status == SourceStatus.connected)
        .length;

    final sections = _buildSections(context, ref, isDark);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      // 桌面端：整页 = 设计稿设置 master-detail 外壳（无 Mine 身份头）。
      // 移动端：保留原 头部 + ListView 形态。
      body: context.isDesktopLayout
          ? const DesktopSettingsScreen()
          : Column(
              children: [
                _buildHeader(context, isDark, connectedCount, connections.length),
                Expanded(
                  child: _buildMobileBody(context, isDark, uiStyle, sections),
                ),
              ],
            ),
    );
  }

  // ===========================================================================
  // 移动端：原 ListView 形态，所有 sections 串联
  // ===========================================================================

  Widget _buildMobileBody(
    BuildContext context,
    bool isDark,
    UIStyle uiStyle,
    List<_MineSection> sections,
  ) {
    final children = <Widget>[];
    for (var i = 0; i < sections.length; i++) {
      final s = sections[i];
      if (i > 0) {
        children.add(const SizedBox(height: AppSpacing.lg));
      }
      children
        ..add(_buildSectionHeader(context, s.title, s.icon, isDark))
        ..add(const SizedBox(height: AppSpacing.sm))
        ..add(Builder(
          builder: (innerCtx) => s.useCardWrapper
              ? _buildSettingsCard(
                  innerCtx,
                  isDark,
                  uiStyle,
                  children: s.tilesBuilder(innerCtx),
                )
              : Column(children: s.tilesBuilder(innerCtx)),
        ));
    }
    children.add(SizedBox(height: context.scrollBottomPadding));

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      children: children,
    );
  }

  // ===========================================================================
  // sections 元数据：标题 / 图标 / tiles 构造器
  // ===========================================================================

  List<_MineSection> _buildSections(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
  ) => [
      _MineSection(
        title: context.l10n.mineSectionConnection,
        icon: Icons.lan_rounded,
        tilesBuilder: (ctx) => [
          _buildSourcesTile(context, ref, isDark),
          _buildDivider(isDark),
          _buildSettingsTile(
            context,
            isDark,
            icon: Icons.folder_special_rounded,
            iconColor: AppColors.accent,
            title: context.l10n.mineMediaLibrary,
            subtitle: context.l10n.mineMediaLibraryDesc,
            onTap: () => Navigator.push(
              ctx,
              MaterialPageRoute<void>(builder: (_) => const MediaLibraryPage()),
            ),
          ),
        ],
      ),
      _MineSection(
        title: context.l10n.mineSectionMyContent,
        icon: Icons.bookmark_rounded,
        tilesBuilder: (ctx) => [
          _buildSettingsTile(
            context,
            isDark,
            icon: Icons.favorite_rounded,
            iconColor: AppColors.error,
            title: context.l10n.mineFavorites,
            subtitle: context.l10n.mineFavoritesDesc,
            onTap: () => Navigator.push(
              ctx,
              MaterialPageRoute<void>(builder: (_) => const FavoritesPage()),
            ),
          ),
        ],
      ),
      _MineSection(
        title: context.l10n.mineSectionVideo,
        icon: Icons.movie_rounded,
        tilesBuilder: (ctx) => [
          _buildSettingsTile(
            context,
            isDark,
            icon: Icons.play_circle_rounded,
            iconColor: AppColors.primary,
            title: context.l10n.mineVideoPlayerSettings,
            subtitle: context.l10n.mineVideoPlayerSettingsDesc,
            onTap: () => Navigator.push(
              ctx,
              MaterialPageRoute<void>(
                builder: (_) => const VideoPlayerSettingsPage(),
              ),
            ),
          ),
          _buildDivider(isDark),
          _VideoScraperSourcesTile(isDark: isDark),
          _buildDivider(isDark),
          _SubtitleSourcesTile(isDark: isDark),
          _buildDivider(isDark),
          _LanguagePreferenceTile(isDark: isDark),
          _buildDivider(isDark),
          _MediaTrackingTile(isDark: isDark),
          _buildDivider(isDark),
          _MediaManagementTile(isDark: isDark),
          _buildDivider(isDark),
          _DownloaderTile(isDark: isDark),
          _buildDivider(isDark),
          _LiveStreamingTile(isDark: isDark),
        ],
      ),
      _MineSection(
        title: context.l10n.mineSectionMusic,
        icon: Icons.music_note_rounded,
        tilesBuilder: (ctx) => [
          _buildSettingsTile(
            context,
            isDark,
            icon: Icons.play_circle_rounded,
            iconColor: AppColors.primary,
            title: context.l10n.mineMusicPlayerSettings,
            subtitle: context.l10n.mineMusicPlayerSettingsDesc,
            onTap: () => Navigator.push(
              ctx,
              MaterialPageRoute<void>(
                builder: (_) => const MusicPlayerSettingsPage(),
              ),
            ),
          ),
          _buildDivider(isDark),
          _buildSettingsTile(
            context,
            isDark,
            icon: Icons.bar_chart_rounded,
            iconColor: AppColors.primary,
            title: context.l10n.mineListeningStats,
            subtitle: context.l10n.mineListeningStatsDesc,
            onTap: () => Navigator.push(
              ctx,
              MaterialPageRoute<void>(
                builder: (_) => const ListeningStatsPage(),
              ),
            ),
          ),
          _buildDivider(isDark),
          _buildSettingsTile(
            context,
            isDark,
            icon: Icons.content_copy_rounded,
            iconColor: AppColors.primary,
            title: context.l10n.mineDuplicateSongs,
            subtitle: context.l10n.mineDuplicateSongsDesc,
            onTap: () => Navigator.push(
              ctx,
              MaterialPageRoute<void>(
                builder: (_) => const DuplicateSongsPage(),
              ),
            ),
          ),
          _buildDivider(isDark),
          _buildSettingsTile(
            context,
            isDark,
            icon: Icons.delete_outline_rounded,
            iconColor: AppColors.primary,
            title: context.l10n.mineRecycleBin,
            subtitle: context.l10n.mineRecycleBinDesc,
            onTap: () => Navigator.push(
              ctx,
              MaterialPageRoute<void>(
                builder: (_) => const RecycleBinPage(),
              ),
            ),
          ),
          _buildDivider(isDark),
          _buildSettingsTile(
            context,
            isDark,
            icon: Icons.cast_rounded,
            iconColor: AppColors.primary,
            title: context.l10n.mineScrobbleReporting,
            subtitle: context.l10n.mineScrobbleReportingDesc,
            onTap: () => Navigator.push(
              ctx,
              MaterialPageRoute<void>(
                builder: (_) => const ScrobbleSettingsPage(),
              ),
            ),
          ),
          _buildDivider(isDark),
          _MusicScraperSourcesTile(isDark: isDark),
        ],
      ),
      _MineSection(
        title: context.l10n.mineSectionBook,
        icon: Icons.auto_stories_rounded,
        tilesBuilder: (ctx) => [
          _BookSourcesTile(isDark: isDark),
          _buildDivider(isDark),
          _BookSettingsTile(isDark: isDark),
        ],
      ),
      _MineSection(
        title: context.l10n.mineSectionSites,
        icon: Icons.rss_feed_rounded,
        tilesBuilder: (ctx) => [
          _PTSitesTile(isDark: isDark),
        ],
      ),
      _MineSection(
        title: context.l10n.mineSectionTransfer,
        icon: Icons.swap_vert_rounded,
        useCardWrapper: false,
        tilesBuilder: (ctx) => [
          _TransferCard(isDark: isDark),
        ],
      ),
      _MineSection(
        title: context.l10n.mineSectionAppearance,
        icon: Icons.palette_outlined,
        tilesBuilder: (ctx) => [
          _buildSettingsTile(
            context,
            isDark,
            icon: Icons.palette_rounded,
            iconColor: Theme.of(context).colorScheme.primary,
            title: context.l10n.mineAppearanceSettings,
            subtitle: context.l10n.mineAppearanceSettingsDesc,
            onTap: () => Navigator.push(
              ctx,
              MaterialPageRoute<void>(
                builder: (_) => const AppearanceSettingsPage(),
              ),
            ),
          ),
        ],
      ),
      _MineSection(
        title: context.l10n.mineSectionPrivacySecurity,
        icon: Icons.lock_outline_rounded,
        tilesBuilder: (ctx) => [
          _buildSettingsTile(
            context,
            isDark,
            icon: Icons.lock_rounded,
            iconColor: AppColors.primary,
            title: context.l10n.mineAppLock,
            subtitle: context.l10n.mineAppLockDesc,
            onTap: () => Navigator.push(
              ctx,
              MaterialPageRoute<void>(
                builder: (_) => const PrivacySecurityPage(),
              ),
            ),
          ),
        ],
      ),
      _MineSection(
        title: context.l10n.mineSectionCloudSync,
        icon: Icons.cloud_sync_rounded,
        tilesBuilder: (ctx) => [
          _buildSettingsTile(
            context,
            isDark,
            icon: Icons.cloud_sync_rounded,
            iconColor: AppColors.primary,
            title: context.l10n.mineWebDAVSync,
            subtitle: context.l10n.mineWebDAVSyncDesc,
            onTap: () => Navigator.push(
              ctx,
              MaterialPageRoute<void>(
                builder: (_) => const CloudSyncSettingsPage(),
              ),
            ),
          ),
        ],
      ),
      _MineSection(
        title: context.l10n.mineSectionAdvanced,
        icon: Icons.tune_rounded,
        tilesBuilder: (ctx) => [
          _buildSettingsTile(
            context,
            isDark,
            icon: Icons.dns_rounded,
            iconColor: AppColors.accent,
            title: context.l10n.mineHostsMapping,
            subtitle: context.l10n.mineHostsMappingDesc,
            onTap: () => Navigator.push(
              ctx,
              MaterialPageRoute<void>(
                builder: (_) => const HostsMappingPage(),
              ),
            ),
          ),
          if (Theme.of(ctx).platform == TargetPlatform.macOS) ...[
            _buildDivider(isDark),
            _buildSettingsTile(
              context,
              isDark,
              icon: Icons.search_rounded,
              iconColor: AppColors.info,
              title: context.l10n.mineSpotlightIndexing,
              subtitle: context.l10n.mineSpotlightIndexingDesc,
              onTap: () => Navigator.push(
                ctx,
                MaterialPageRoute<void>(
                  builder: (_) => const SpotlightSettingsPage(),
                ),
              ),
            ),
          ],
        ],
      ),
      _MineSection(
        title: context.l10n.mineSectionAbout,
        icon: Icons.info_outline_rounded,
        tilesBuilder: (ctx) => [
          _VersionTile(isDark: isDark),
          _buildDivider(isDark),
          CheckUpdateTile(isDark: isDark),
          _buildDivider(isDark),
          _buildSettingsTile(
            context,
            isDark,
            icon: Icons.article_rounded,
            iconColor: AppColors.info,
            title: context.l10n.mineOpenSourceLicenses,
            subtitle: context.l10n.mineOpenSourceLicensesDesc,
            onTap: () => _showOpenSourceLicenses(context),
          ),
        ],
      ),
    ];

  Widget _buildHeader(BuildContext context, bool isDark, int connectedCount, int totalCount) {
    // 桌面端 header 更紧凑：48 头像、titleMedium 标题、padding 12+12。
    final isDesktop = context.isDesktopLayout;
    final avatarSize = isDesktop ? 40.0 : 64.0;
    final avatarRadius = isDesktop ? 10.0 : 20.0;
    final titleStyle = isDesktop
        ? context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)
        : context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold);
    final verticalPadding = isDesktop ? 12.0 : 20.0;
    final topPadding = isDesktop ? 12.0 : context.padding.top + 20;

    // 桌面下用纯净 surface 色 + 底部细分隔线（macOS sidebar 风），
    // 移动端保留原渐变。
    final headerDecoration = isDesktop
        ? BoxDecoration(
            color: isDark ? AppColors.darkSurface : context.colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? AppColors.darkOutline.withValues(alpha: 0.3)
                    : context.colorScheme.outlineVariant,
              ),
            ),
          )
        : BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [AppColors.darkSurface, AppColors.darkBackground]
                  : [AppColors.primary.withValues(alpha: 0.1), Colors.white],
            ),
          );

    // 桌面下精简：去掉 logo + "MyNAS"（NavigationRail 已显示），
    // 只显示标题 "设置" + 连接状态 chip。
    if (isDesktop) {
      return Container(
        padding: EdgeInsets.fromLTRB(20, topPadding, 16, verticalPadding),
        decoration: headerDecoration,
        child: Row(
          children: [
            Text(
              context.l10n.mineHeaderSettings,
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.darkOnSurface : null,
              ),
            ),
            const Spacer(),
            // 连接状态 chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (connectedCount > 0
                        ? AppColors.success
                        : Colors.grey)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color:
                          connectedCount > 0 ? AppColors.success : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    connectedCount > 0
                        ? context.l10n.mineConnectionStatusConnected(connectedCount, totalCount)
                        : context.l10n.mineConnectionStatusDisconnected,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: connectedCount > 0
                          ? AppColors.success
                          : (isDark
                              ? AppColors.darkOnSurfaceVariant
                              : AppColors.lightOnSurfaceVariant),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 移动端保留原 header（含 logo + 头像 + 大标题 + 状态行）
    return Container(
      padding: EdgeInsets.fromLTRB(20, topPadding, 20, verticalPadding),
      decoration: headerDecoration,
      child: Row(
        children: [
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(avatarRadius),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(avatarRadius),
              child: Image.asset(
                'assets/logo.png',
                width: avatarSize,
                height: avatarSize,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MyNAS',
                  style: titleStyle?.copyWith(
                    color: isDark ? AppColors.darkOnSurface : null,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: connectedCount > 0 ? AppColors.success : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      connectedCount > 0
                          ? context.l10n.mineConnectionStatusConnected(connectedCount, totalCount)
                          : context.l10n.mineConnectionStatusDisconnected,
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon, bool isDark) => Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 16,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: context.textTheme.titleSmall?.copyWith(
            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );

  Widget _buildSettingsCard(
    BuildContext context,
    bool isDark,
    UIStyle uiStyle, {
    required List<Widget> children,
  }) =>
      // 使用自适应玻璃容器 - 自动根据平台选择原生/Flutter实现
      // 桌面下圆角与 AppRadius.card 对齐（macOS Settings 风），手机保留 20（iOS 风）。
      AdaptiveGlassContainer(
        uiStyle: uiStyle,
        isDark: isDark,
        cornerRadius: context.isDesktopLayout ? AppRadius.card : 20,
        child: Column(children: children),
      );

  Widget _buildSettingsTile(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Color? titleColor,
    bool showChevron = true,
    VoidCallback? onTap,
  }) =>
      _mineTileRow(
        context,
        isDark: isDark,
        icon: icon,
        iconColor: iconColor,
        title: title,
        subtitle: subtitle,
        titleColor: titleColor,
        showChevronWhenNoTrailing: showChevron,
        onTap: onTap,
      );

  Widget _buildDivider(bool isDark) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Divider(
        height: 1,
        color: isDark
            ? AppColors.darkOutline.withValues(alpha: 0.2)
            : AppColors.lightOutline.withValues(alpha: 0.3),
      ),
    );

  Widget _buildSourcesTile(BuildContext context, WidgetRef ref, bool isDark) {
    // 只统计存储类源的连接状态
    final storageSources = ref.watch(storageSourcesProvider);
    final connections = ref.watch(activeConnectionsProvider);
    final storageConnections = storageSources
        .map((s) => connections[s.id])
        .where((c) => c != null)
        .toList();
    final connectedCount = storageConnections
        .where((c) => c?.status == SourceStatus.connected)
        .length;
    final totalCount = storageSources.length;

    final statusColor = connectedCount == 0
        ? AppColors.warning
        : connectedCount == totalCount
            ? AppColors.success
            : AppColors.accent;

    final trailing = totalCount > 0
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '$connectedCount/$totalCount',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          )
        : null;

    return _mineTileRow(
      context,
      isDark: isDark,
      icon: Icons.storage_rounded,
      iconColor: AppColors.info,
      title: context.l10n.mineConnectionSources,
      subtitle: context.l10n.mineConnectionSourcesDesc,
      trailing: trailing,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const SourcesPage()),
      ),
    );
  }

  void _showOpenSourceLicenses(BuildContext context) {
    // 显示开源许可证页面
    showLicensePage(
      context: context,
      applicationName: 'MyNAS',
      applicationIcon: Padding(
        padding: const EdgeInsets.all(8),
        child: Image.asset('assets/logo.png', width: 64, height: 64),
      ),
      applicationLegalese: context.l10n.mineLicenseContent,
    );
  }
}


/// 版本号组件
class _VersionTile extends StatefulWidget {
  const _VersionTile({required this.isDark});

  final bool isDark;

  @override
  State<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<_VersionTile> {
  late String _version;
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _version = context.l10n.mineLoadingStatus;
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = packageInfo.version;
        _buildNumber = packageInfo.buildNumber;
      });
    }
  }

  @override
  Widget build(BuildContext context) => _mineTileRow(
        context,
        isDark: widget.isDark,
        icon: Icons.info_rounded,
        iconColor: AppColors.secondary,
        title: context.l10n.mineVersion,
        subtitle: _buildNumber.isNotEmpty ? '$_version ($_buildNumber)' : _version,
        showChevronWhenNoTrailing: false,
      );
}

/// 视频刮削源入口组件
class _VideoScraperSourcesTile extends ConsumerWidget {
  const _VideoScraperSourcesTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourcesAsync = ref.watch(scraperSourcesProvider);

    final (subtitle, trailing) = sourcesAsync.when<(String, Widget?)>(
      data: (sources) {
        final enabledCount = sources.where((s) => s.isEnabled).length;
        final totalCount = ScraperType.values.length;
        return (
          context.l10n.mineVideoScraperDesc,
          enabledCount > 0
              ? _mineCountBadge('$enabledCount/$totalCount', AppColors.success)
              : null,
        );
      },
      loading: () => (context.l10n.mineLoadingStatus, null),
      error: (_, _) => (context.l10n.mineLoadingStatus, null),
    );

    return _mineTileRow(
      context,
      isDark: isDark,
      icon: Icons.video_library_rounded,
      iconColor: AppColors.fileVideo,
      title: context.l10n.mineScraperSources,
      subtitle: subtitle,
      trailing: trailing,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const ScraperSourcesPage()),
      ),
    );
  }
}

/// 字幕源入口组件
class _SubtitleSourcesTile extends ConsumerWidget {
  const _SubtitleSourcesTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitleSources = ref.watch(subtitleSourcesProvider);
    final count = subtitleSources.length;

    return _mineTileRow(
      context,
      isDark: isDark,
      icon: Icons.subtitles_rounded,
      iconColor: AppColors.success,
      title: context.l10n.mineSubtitleSources,
      subtitle: context.l10n.mineSubtitleSourcesDesc,
      trailing: count > 0 ? _mineCountBadge('$count', AppColors.success) : null,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ServiceSourcesPage(
            title: context.l10n.mineSubtitleSources,
            category: SourceCategory.subtitleSites,
            emptyIcon: Icons.subtitles_rounded,
            emptyTitle: context.l10n.mineEmptySubtitleTitle,
            emptySubtitle: context.l10n.mineEmptySubtitleDesc,
          ),
        ),
      ),
    );
  }
}

/// 音乐刮削源入口组件
class _MusicScraperSourcesTile extends ConsumerWidget {
  const _MusicScraperSourcesTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(musicScraperSourcesProvider);
    final enabledCount = state.sources.where((s) => s.isEnabled).length;
    final totalCount = MusicScraperType.values.length;

    return _mineTileRow(
      context,
      isDark: isDark,
      icon: Icons.library_music_rounded,
      iconColor: AppColors.fileAudio,
      title: context.l10n.mineScraperSources,
      subtitle: context.l10n.mineMusicScraperDesc,
      trailing: enabledCount > 0
          ? _mineCountBadge('$enabledCount/$totalCount', AppColors.success)
          : null,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const MusicScraperSourcesPage()),
      ),
    );
  }
}

/// 传输卡片组件 - 下载、上传和缓存合并在一个卡片中
class _TransferCard extends ConsumerWidget {
  const _TransferCard({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadingCount = ref.watch(downloadingCountProvider);
    final uploadingCount = ref.watch(uploadingCountProvider);
    final cachingCount = ref.watch(cachingCountProvider);
    final cacheStats = ref.watch(cacheStatsProvider);
    final uiStyle = ref.watch(uiStyleProvider);

    // 计算缓存总数和大小
    final cacheCount = cacheStats.when(
      data: (stats) => stats.values.fold(0, (sum, s) => sum + s.count),
      loading: () => 0,
      error: (_, _) => 0,
    );
    final cacheSizeText = cacheStats.when(
      data: (stats) {
        final totalSize = stats.values.fold(0, (sum, s) => sum + s.size);
        return _formatBytes(totalSize);
      },
      loading: () => context.l10n.mineCalculatingStatus,
      error: (_, _) => context.l10n.mineUnknownStatus,
    );

    // 使用自适应玻璃容器 - 自动根据平台选择原生/Flutter实现
    return AdaptiveGlassContainer(
      uiStyle: uiStyle,
      isDark: isDark,
      cornerRadius: 20,
      child: Column(
        children: [
          // 下载项
          _buildTransferItem(
            context,
            icon: Icons.download_rounded,
            label: context.l10n.mineTransferDownload,
            count: downloadingCount,
            subtitle: downloadingCount > 0
                ? context.l10n.mineTransferDownloadTasksActive(downloadingCount)
                : context.l10n.mineTransferDownloadNoTasks,
            color: AppColors.primary,
            isActive: downloadingCount > 0,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const TransferManagerPage(initialTab: 0)),
            ),
          ),
          // 分隔线
          _buildDivider(),
          // 上传项
          _buildTransferItem(
            context,
            icon: Icons.upload_rounded,
            label: context.l10n.mineTransferUpload,
            count: uploadingCount,
            subtitle: uploadingCount > 0
                ? context.l10n.mineTransferUploadTasksActive(uploadingCount)
                : context.l10n.mineTransferUploadNoTasks,
            color: AppColors.accent,
            isActive: uploadingCount > 0,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const TransferManagerPage(initialTab: 1)),
            ),
          ),
          // 分隔线
          _buildDivider(),
          // 缓存项
          _buildTransferItem(
            context,
            icon: Icons.storage_rounded,
            label: context.l10n.mineTransferCache,
            count: cachingCount > 0 ? cachingCount : null,
            subtitle: cachingCount > 0
                ? context.l10n.mineTransferCacheTasksActive(cachingCount)
                : cacheCount > 0
                    ? context.l10n.mineTransferCacheItems(cacheCount, cacheSizeText)
                    : context.l10n.mineTransferCacheNoTasks,
            color: Colors.teal,
            isActive: cachingCount > 0,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const TransferManagerPage(initialTab: 2)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Divider(
          height: 1,
          color: isDark
              ? AppColors.darkOutline.withValues(alpha: 0.2)
              : AppColors.lightOutline.withValues(alpha: 0.3),
        ),
      );

  Widget _buildTransferItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    int? count,
    required String subtitle,
    required Color color,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final isDesktop = context.isDesktopLayout;
    final iconBox = isDesktop ? 32.0 : 40.0;
    final iconSize = isDesktop ? 18.0 : 20.0;
    final verticalPadding = isDesktop ? AppSpacing.sm : AppSpacing.md;
    final titleStyle = isDesktop
        ? context.textTheme.bodyMedium
        : context.textTheme.bodyLarge;
    return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: verticalPadding,
            ),
            child: Row(
              children: [
                // 图标
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: iconBox,
                      height: iconBox,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: isActive ? 0.15 : 0.12),
                        borderRadius: BorderRadius.circular(isDesktop ? 8 : 12),
                      ),
                      child: Icon(
                        icon,
                        color: color,
                        size: iconSize,
                      ),
                    ),
                    if (count != null && count > 0)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            count > 99 ? '99+' : count.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: AppSpacing.md),
                // 标题和副标题
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: titleStyle?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (isActive) ...[
                            SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: color,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              subtitle,
                              style: context.textTheme.bodySmall?.copyWith(
                                color: isActive
                                    ? color
                                    : (isDark
                                        ? AppColors.darkOnSurfaceVariant
                                        : AppColors.lightOnSurfaceVariant),
                                fontWeight: isActive ? FontWeight.w500 : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // 右侧箭头（桌面 hover 提示即可，与其他 tile 一致）
                if (!isDesktop)
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isDark
                        ? AppColors.darkOnSurfaceVariant
                        : AppColors.lightOnSurfaceVariant,
                    size: 22,
                  ),
              ],
            ),
          ),
        ),
      );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// 媒体追踪入口组件
class _MediaTrackingTile extends ConsumerWidget {
  const _MediaTrackingTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackingSources = ref.watch(mediaTrackingSourcesProvider);
    final count = trackingSources.length;

    return _mineTileRow(
      context,
      isDark: isDark,
      icon: Icons.track_changes_rounded,
      iconColor: Colors.purple,
      title: context.l10n.mineMediaTracking,
      subtitle: context.l10n.mineMediaTrackingDesc,
      trailing: count > 0 ? _mineCountBadge('$count', Colors.purple) : null,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const MediaTrackingListPage()),
      ),
    );
  }
}

/// 媒体管理入口组件
class _MediaManagementTile extends ConsumerWidget {
  const _MediaManagementTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final managementSources = ref.watch(mediaManagementSourcesProvider);
    final count = managementSources.length;

    return _mineTileRow(
      context,
      isDark: isDark,
      icon: Icons.construction_rounded,
      iconColor: Colors.teal,
      title: context.l10n.mineMediaManagement,
      subtitle: context.l10n.mineMediaManagementDesc,
      trailing: count > 0 ? _mineCountBadge('$count', Colors.teal) : null,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const MediaManagementListPage()),
      ),
    );
  }
}

/// 下载器入口组件
class _DownloaderTile extends ConsumerWidget {
  const _DownloaderTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaderSources = ref.watch(downloadToolSourcesProvider);
    final count = downloaderSources.length;

    return _mineTileRow(
      context,
      isDark: isDark,
      icon: Icons.download_for_offline_rounded,
      iconColor: AppColors.warning,
      title: context.l10n.mineDownloader,
      subtitle: context.l10n.mineDownloaderDesc,
      trailing: count > 0 ? _mineCountBadge('$count', AppColors.warning) : null,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const DownloaderListPage()),
      ),
    );
  }
}

/// 直播源入口组件
class _LiveStreamingTile extends ConsumerWidget {
  const _LiveStreamingTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(liveStreamSettingsProvider);
    final count = settings.enabledSources.length;

    return _mineTileRow(
      context,
      isDark: isDark,
      icon: Icons.live_tv_rounded,
      iconColor: Colors.red,
      title: context.l10n.mineLiveStreaming,
      subtitle: context.l10n.mineLiveStreamingDesc,
      trailing: count > 0 ? _mineCountBadge('$count', Colors.red) : null,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const LiveStreamSettingsPage()),
      ),
    );
  }
}

/// PT 站点入口组件
class _PTSitesTile extends ConsumerWidget {
  const _PTSitesTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ptSitesSources = ref.watch(ptSitesSourcesProvider);
    final count = ptSitesSources.length;

    return _mineTileRow(
      context,
      isDark: isDark,
      icon: Icons.rss_feed_rounded,
      iconColor: Colors.indigo,
      title: context.l10n.minePTSites,
      subtitle: context.l10n.minePTSitesDesc,
      trailing: count > 0 ? _mineCountBadge('$count', Colors.indigo) : null,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const PTSitesListPage()),
      ),
    );
  }
}

/// 语言偏好设置组件
class _LanguagePreferenceTile extends ConsumerWidget {
  const _LanguagePreferenceTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(languagePreferenceProvider);

    return _mineTileRow(
      context,
      isDark: isDark,
      icon: Icons.language_rounded,
      iconColor: AppColors.info,
      title: context.l10n.mineLanguagePreference,
      subtitle: _getPreferenceSummary(context, preference),
      onTap: () => _showLanguageSettingsSheet(context, ref),
    );
  }

  String _getPreferenceSummary(BuildContext context, LanguagePreference preference) {
    final metadata = preference.getPreferredLanguage(LanguageType.metadata);
    final audio = preference.getPreferredLanguage(LanguageType.audio);
    final subtitle = preference.getPreferredLanguage(LanguageType.subtitle);

    final isAllAuto = metadata == LanguageOption.auto &&
        audio == LanguageOption.auto &&
        subtitle == LanguageOption.auto;

    if (isAllAuto) {
      return context.l10n.mineLanguagePreferenceAllAuto;
    }

    final parts = <String>[];
    if (metadata != LanguageOption.auto) {
      parts.add('元数据: ${metadata.displayName}');
    }
    if (audio != LanguageOption.auto) {
      parts.add('音频: ${audio.displayName}');
    }
    if (subtitle != LanguageOption.auto) {
      parts.add('字幕: ${subtitle.displayName}');
    }

    return parts.isEmpty ? context.l10n.mineLanguagePreferenceAllAuto : parts.join(' | ');
  }

  void _showLanguageSettingsSheet(BuildContext context, WidgetRef ref) {
    showAdaptiveModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _LanguageSettingsSheet(isDark: isDark),
    );
  }
}

/// 语言设置弹窗（移动端底部 sheet / 桌面端居中 dialog 自适应）
class _LanguageSettingsSheet extends ConsumerWidget {
  const _LanguageSettingsSheet({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(languagePreferenceProvider);
    final isDesktop = context.isDesktopLayout;

    // 桌面下外层 Dialog 已经处理圆角和容器，sheet 内部走全圆角；
    // 移动端保留底部 sheet 风格的顶部圆角。
    final radius = isDesktop
        ? const BorderRadius.all(Radius.circular(20))
        : const BorderRadius.vertical(top: Radius.circular(24));

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurface.withValues(alpha: 0.95)
                : AppColors.lightSurface.withValues(alpha: 0.98),
            borderRadius: radius,
            border: isDesktop
                ? null
                : Border(
                    top: BorderSide(
                      color: isDark
                          ? AppColors.glassStroke
                          : AppColors.lightOutline.withValues(alpha: 0.2),
                    ),
                  ),
          ),
          child: SafeArea(
            top: !isDesktop,
            bottom: !isDesktop,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 桌面下 SheetDragHandle 自动渲染为 SizedBox.shrink
                const SheetDragHandle(),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    isDesktop ? AppSpacing.lg : AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: Text(
                    context.l10n.mineLanguagePreferenceSettings,
                    style: context.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Text(
                    context.l10n.mineLanguagePreferenceDesc,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant
                          : AppColors.lightOnSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // 元数据语言
                _buildLanguageDropdown(
                  context,
                  ref,
                  type: LanguageType.metadata,
                  title: context.l10n.mineMetadataLanguage,
                  subtitle: context.l10n.mineMetadataLanguageDesc,
                  icon: Icons.description_rounded,
                  iconColor: AppColors.primary,
                  currentValue: preference.getPreferredLanguage(LanguageType.metadata),
                  availableLanguages: LanguageOption.metadataLanguages,
                ),

                const SizedBox(height: AppSpacing.sm),

                // 音频语言
                _buildLanguageDropdown(
                  context,
                  ref,
                  type: LanguageType.audio,
                  title: context.l10n.mineAudioLanguage,
                  subtitle: context.l10n.mineAudioLanguageDesc,
                  icon: Icons.audiotrack_rounded,
                  iconColor: AppColors.accent,
                  currentValue: preference.getPreferredLanguage(LanguageType.audio),
                  availableLanguages: LanguageOption.audioSubtitleLanguages,
                ),

                const SizedBox(height: AppSpacing.sm),

                // 字幕语言
                _buildLanguageDropdown(
                  context,
                  ref,
                  type: LanguageType.subtitle,
                  title: context.l10n.mineSubtitleLanguage,
                  subtitle: context.l10n.mineSubtitleLanguageDesc,
                  icon: Icons.subtitles_rounded,
                  iconColor: AppColors.fileVideo,
                  currentValue: preference.getPreferredLanguage(LanguageType.subtitle),
                  availableLanguages: LanguageOption.audioSubtitleLanguages,
                ),

                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageDropdown(
    BuildContext context,
    WidgetRef ref, {
    required LanguageType type,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required LanguageOption currentValue,
    required List<LanguageOption> availableLanguages,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
                : AppColors.lightSurfaceVariant.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? AppColors.darkOutline.withValues(alpha: 0.2)
                  : AppColors.lightOutline.withValues(alpha: 0.3),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                // 图标
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: AppSpacing.md),
                // 标题和副标题
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppColors.darkOnSurfaceVariant
                              : AppColors.lightOnSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                // 下拉选择
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurface.withValues(alpha: 0.5)
                        : AppColors.lightSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkOutline.withValues(alpha: 0.3)
                          : AppColors.lightOutline.withValues(alpha: 0.5),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<LanguageOption>(
                      value: currentValue,
                      isDense: true,
                      menuMaxHeight: 300, // 限制下拉菜单最大高度
                      icon: Icon(
                        Icons.expand_more_rounded,
                        size: 18,
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                      dropdownColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                      borderRadius: BorderRadius.circular(12),
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      ),
                      items: availableLanguages.map((lang) => DropdownMenuItem(
                        value: lang,
                        child: Text(lang.displayName),
                      )).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          ref.read(languagePreferenceProvider.notifier)
                              .setLanguages(type, [value]);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// 书源管理入口
class _BookSourcesTile extends StatelessWidget {
  const _BookSourcesTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) => _mineTileRow(
        context,
        isDark: isDark,
        icon: Icons.library_books_rounded,
        iconColor: AppColors.primary,
        title: context.l10n.mineBookSources,
        subtitle: context.l10n.mineBookSourcesDesc,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const BookSourcesPage()),
        ),
      );
}

/// 图书设置入口组件
class _BookSettingsTile extends StatelessWidget {
  const _BookSettingsTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) => _mineTileRow(
        context,
        isDark: isDark,
        icon: Icons.auto_stories_rounded,
        iconColor: Colors.amber,
        title: context.l10n.mineBookSettings,
        subtitle: context.l10n.mineBookSettingsDesc,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const BookSettingsPage()),
        ),
      );
}

// =============================================================================
// 桌面 master-detail 实现
// =============================================================================

/// mine 页 section 元数据。
class _MineSection {
  const _MineSection({
    required this.title,
    required this.icon,
    required this.tilesBuilder,
    this.useCardWrapper = true,
  });

  final String title;
  final IconData icon;
  /// 接收实际渲染 tiles 的 navigator 内 context，使内部 inline
  /// `Navigator.push(context, ...)` 在桌面下进入嵌套 detail navigator，
  /// 移动下进入 main shell navigator。
  final List<Widget> Function(BuildContext context) tilesBuilder;

  /// 是否要用 [AdaptiveGlassContainer] 包裹 tiles。
  /// 部分 section（如 "传输"）的内容本身就是 card，不需要再包一层。
  final bool useCardWrapper;
}

/// Mine 页所有 tile 共用的统一行布局：图标+标题+副标题+末尾控件。
/// 桌面下统一切到紧凑模式（32 图标 / 18 字 / bodyMedium / sm padding / 8 圆角），
/// 移动端保持 40 图标 / 20 字 / bodyLarge / md padding / 12 圆角。
Widget _mineTileRow(
  BuildContext context, {
  required bool isDark,
  required IconData icon,
  required Color iconColor,
  required String title,
  String? subtitle,
  Color? titleColor,
  Widget? trailing,
  bool showChevronWhenNoTrailing = true,
  VoidCallback? onTap,
}) {
  final isDesktop = context.isDesktopLayout;
  final iconBox = isDesktop ? 32.0 : 40.0;
  final iconSize = isDesktop ? 18.0 : 20.0;
  final verticalPadding = isDesktop ? AppSpacing.sm : AppSpacing.md;
  final titleStyle = isDesktop
      ? context.textTheme.bodyMedium
      : context.textTheme.bodyLarge;

  var effectiveTrailing = trailing;
  // 桌面下不显示 chevron：与 macOS 系统设置 sidebar 一致，靠 hover 高亮提示可点击。
  if (effectiveTrailing == null &&
      showChevronWhenNoTrailing &&
      onTap != null &&
      !isDesktop) {
    effectiveTrailing = Icon(
      Icons.chevron_right_rounded,
      color: isDark
          ? AppColors.darkOnSurfaceVariant
          : AppColors.lightOnSurfaceVariant,
      size: 22,
    );
  }

  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: verticalPadding,
        ),
        child: Row(
          children: [
            Container(
              width: iconBox,
              height: iconBox,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(isDesktop ? 8 : 12),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: iconSize,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: titleStyle?.copyWith(
                      color: titleColor ??
                          (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            ?effectiveTrailing,
          ],
        ),
      ),
    ),
  );
}

/// 计数徽章，配合 _mineTileRow 的 trailing 使用。
Widget _mineCountBadge(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
