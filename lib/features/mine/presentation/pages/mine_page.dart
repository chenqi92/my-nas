import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/app/theme/ui_style.dart';
import 'package:my_nas/shared/pages/favorites_page.dart';
import 'package:my_nas/shared/widgets/adaptive_glass_container.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/mine/presentation/pages/appearance_settings_page.dart';
import 'package:my_nas/features/downloader/presentation/pages/downloader_list_page.dart';
import 'package:my_nas/features/media_management/presentation/pages/media_management_list_page.dart';
import 'package:my_nas/features/media_tracking/presentation/pages/media_tracking_list_page.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/presentation/pages/duplicate_songs_page.dart';
import 'package:my_nas/features/music/presentation/pages/listening_stats_page.dart';
import 'package:my_nas/features/music/presentation/pages/music_player_settings_page.dart';
import 'package:my_nas/features/music/presentation/pages/recycle_bin_page.dart';
import 'package:my_nas/features/music/presentation/pages/scrobble_settings_page.dart';
import 'package:my_nas/features/sync/presentation/pages/cloud_sync_settings_page.dart';
import 'package:my_nas/features/music/presentation/pages/music_scraper_sources_page.dart';
import 'package:my_nas/features/music/presentation/providers/music_scraper_provider.dart';
import 'package:my_nas/features/pt_sites/presentation/pages/pt_sites_list_page.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/media_library_page.dart';
import 'package:my_nas/features/book/presentation/pages/book_settings_page.dart';
import 'package:my_nas/features/book/presentation/pages/book_sources_page.dart';
import 'package:my_nas/features/sources/presentation/pages/service_sources_page.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/transfer/presentation/pages/transfer_manager_page.dart';
import 'package:my_nas/features/transfer/presentation/providers/transfer_provider.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';
import 'package:my_nas/features/video/presentation/pages/live_stream_settings_page.dart';
import 'package:my_nas/features/video/presentation/pages/scraper_sources_page.dart';
import 'package:my_nas/features/video/presentation/pages/video_player_settings_page.dart';
import 'package:my_nas/features/video/presentation/providers/live_stream_provider.dart';
import 'package:my_nas/features/video/presentation/providers/scraper_provider.dart';
import 'package:my_nas/shared/providers/language_preference_provider.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/widgets/update_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 桌面端 mine 页选中的 section 索引（在 [_buildSections] 列表中）。
final _selectedDesktopSectionProvider = StateProvider.autoDispose<int>((_) => 0);

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
      body: Column(
        children: [
          _buildHeader(context, isDark, connectedCount, connections.length),
          Expanded(
            child: context.isDesktopLayout
                ? _buildDesktopBody(context, ref, isDark, uiStyle, sections)
                : _buildMobileBody(context, isDark, uiStyle, sections),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 桌面端：左侧 section 列表 + 右侧选中 section 的 settings card
  // ===========================================================================

  Widget _buildDesktopBody(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    UIStyle uiStyle,
    List<_MineSection> sections,
  ) {
    final selectedIndex = ref
        .watch(_selectedDesktopSectionProvider)
        .clamp(0, sections.length - 1);
    final dividerColor = isDark
        ? AppColors.darkOutline.withValues(alpha: 0.3)
        : context.colorScheme.outlineVariant;
    final masterWidth = context.screenWidth >= 1100 ? 220.0 : 180.0;
    final selected = sections[selectedIndex];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: masterWidth,
          child: _DesktopSectionList(
            sections: sections,
            selectedIndex: selectedIndex,
            isDark: isDark,
            onSelect: (i) =>
                ref.read(_selectedDesktopSectionProvider.notifier).state = i,
          ),
        ),
        VerticalDivider(width: 1, thickness: 1, color: dividerColor),
        Expanded(
          child: _DesktopSectionDetail(
            section: selected,
            isDark: isDark,
            uiStyle: uiStyle,
            // ignore: avoid_types_on_closure_parameters
            buildSettingsCard: ({required List<Widget> children}) =>
                _buildSettingsCard(
                  context,
                  isDark,
                  uiStyle,
                  children: children,
                ),
          ),
        ),
      ],
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
  ) {
    return [
      _MineSection(
        title: '连接',
        icon: Icons.lan_rounded,
        tilesBuilder: (ctx) => [
          _buildSourcesTile(context, ref, isDark),
          _buildDivider(isDark),
          _buildSettingsTile(
            context,
            isDark,
            icon: Icons.folder_special_rounded,
            iconColor: AppColors.accent,
            title: '媒体库',
            subtitle: '配置视频、音乐、漫画等目录',
            onTap: () => Navigator.push(
              ctx,
              MaterialPageRoute<void>(builder: (_) => const MediaLibraryPage()),
            ),
          ),
        ],
      ),
      _MineSection(
        title: '我的内容',
        icon: Icons.bookmark_rounded,
        tilesBuilder: (ctx) => [
          _buildSettingsTile(
            context,
            isDark,
            icon: Icons.favorite_rounded,
            iconColor: AppColors.error,
            title: '我的收藏',
            subtitle: '已收藏的视频、照片、笔记、图书、漫画',
            onTap: () => Navigator.push(
              ctx,
              MaterialPageRoute<void>(builder: (_) => const FavoritesPage()),
            ),
          ),
        ],
      ),
      _MineSection(
        title: '视频',
        icon: Icons.movie_rounded,
        tilesBuilder: (ctx) => [
          _buildSettingsTile(
            context,
            isDark,
            icon: Icons.play_circle_rounded,
            iconColor: AppColors.primary,
            title: '播放器设置',
            subtitle: '清晰度、投屏、转码等',
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
        title: '音乐',
        icon: Icons.music_note_rounded,
        tilesBuilder: (ctx) => [
          _buildSettingsTile(
            context,
            isDark,
            icon: Icons.play_circle_rounded,
            iconColor: AppColors.primary,
            title: '播放器设置',
            subtitle: '播放引擎、音量、淡入淡出等',
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
            title: '听歌统计',
            subtitle: '本周/本月/本年 Top 歌曲、艺术家、专辑',
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
            title: '重复歌曲',
            subtitle: '检测同首歌的多个版本（mp3 + flac 等）',
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
            title: '回收站',
            subtitle: '已删除的播放列表保留 30 天，可恢复',
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
            title: 'Scrobble 上报',
            subtitle: 'Last.fm / ListenBrainz 听歌历史同步',
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
        title: '图书',
        icon: Icons.auto_stories_rounded,
        tilesBuilder: (ctx) => [
          _BookSourcesTile(isDark: isDark),
          _buildDivider(isDark),
          _BookSettingsTile(isDark: isDark),
        ],
      ),
      _MineSection(
        title: '站点',
        icon: Icons.rss_feed_rounded,
        tilesBuilder: (ctx) => [
          _PTSitesTile(isDark: isDark),
        ],
      ),
      _MineSection(
        title: '传输',
        icon: Icons.swap_vert_rounded,
        useCardWrapper: false,
        tilesBuilder: (ctx) => [
          _TransferCard(isDark: isDark),
        ],
      ),
      _MineSection(
        title: '外观',
        icon: Icons.palette_outlined,
        tilesBuilder: (ctx) => [
          _buildSettingsTile(
            context,
            isDark,
            icon: Icons.palette_rounded,
            iconColor: Theme.of(context).colorScheme.primary,
            title: '外观设置',
            subtitle: '主题、配色、UI 风格',
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
        title: '云同步',
        icon: Icons.cloud_sync_rounded,
        tilesBuilder: (ctx) => [
          _buildSettingsTile(
            context,
            isDark,
            icon: Icons.cloud_sync_rounded,
            iconColor: AppColors.primary,
            title: 'WebDAV 同步',
            subtitle: '跨设备同步歌单 / 阅读进度等',
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
        title: '关于',
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
            title: '开源许可证',
            subtitle: '查看第三方开源库声明',
            onTap: () => _showOpenSourceLicenses(context),
          ),
        ],
      ),
    ];
  }

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
              '设置',
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
                        ? '$connectedCount / $totalCount 已连接'
                        : '未连接',
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
                          ? '$connectedCount / $totalCount 已连接'
                          : '未连接',
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
  }) {
    // 使用自适应玻璃容器 - 自动根据平台选择原生/Flutter实现
    // 桌面下圆角缩小到 10（macOS 风），手机保留 20（iOS 风）。
    return AdaptiveGlassContainer(
      uiStyle: uiStyle,
      isDark: isDark,
      cornerRadius: context.isDesktopLayout ? 10 : 20,
      child: Column(children: children),
    );
  }

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
  }) {
    // 桌面下用更紧凑的密度：图标 32、垂直 padding 8、标题 bodyMedium。
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
              // 桌面下不显示 chevron：macOS 系统设置的 sidebar 子项均无
              // chevron，靠 hover 高亮提示可点击。
              if (showChevron && onTap != null && !isDesktop)
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const SourcesPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.storage_rounded,
                  color: AppColors.info,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '连接源',
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '管理 NAS、WebDAV、SMB 等连接',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // 连接状态徽章
              if (totalCount > 0)
                Container(
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
              else
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

  void _showOpenSourceLicenses(BuildContext context) {
    // 显示开源许可证页面
    showLicensePage(
      context: context,
      applicationName: 'MyNAS',
      applicationLegalese: '© 2024 MyNAS. All rights reserved.\n\n'
          '本应用使用了以下开源软件：\n\n'
          '• FFmpeg - 视频转码（GPL v3）\n'
          '  https://ffmpeg.org\n'
          '  源代码：https://github.com/FFmpeg/FFmpeg\n\n'
          '• media_kit - 媒体播放\n'
          '• Flutter 及其相关库\n\n'
          '完整的开源许可证信息请查看下方列表。',
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
  String _version = '加载中...';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
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
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.info_rounded,
              color: AppColors.secondary,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '版本',
                  style: context.textTheme.bodyLarge?.copyWith(
                    color: widget.isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _buildNumber.isNotEmpty ? '$_version ($_buildNumber)' : _version,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: widget.isDark
                        ? AppColors.darkOnSurfaceVariant
                        : AppColors.lightOnSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
}

/// 视频刮削源入口组件
class _VideoScraperSourcesTile extends ConsumerWidget {
  const _VideoScraperSourcesTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourcesAsync = ref.watch(scraperSourcesProvider);

    return sourcesAsync.when(
      data: (sources) {
        final enabledCount = sources.where((s) => s.isEnabled).length;
        // 使用所有可用刮削源类型数量作为总数
        final totalCount = ScraperType.values.length;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const ScraperSourcesPage()),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.fileVideo.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.video_library_rounded,
                      color: AppColors.fileVideo,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '刮削源',
                          style: context.textTheme.bodyLarge?.copyWith(
                            color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '管理 TMDB、豆瓣等视频刮削源',
                          style: context.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (enabledCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$enabledCount/$totalCount',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.success,
                        ),
                      ),
                    )
                  else
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
      },
      loading: () => _buildLoadingTile(context),
      error: (_, _) => _buildLoadingTile(context),
    );
  }

  Widget _buildLoadingTile(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.fileVideo.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.video_library_rounded,
                color: AppColors.fileVideo,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '刮削源',
                    style: context.textTheme.bodyLarge?.copyWith(
                      color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '加载中...',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant
                          : AppColors.lightOnSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// 字幕源入口组件
class _SubtitleSourcesTile extends ConsumerWidget {
  const _SubtitleSourcesTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitleSources = ref.watch(subtitleSourcesProvider);
    final count = subtitleSources.length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => const ServiceSourcesPage(
              title: '字幕源',
              category: SourceCategory.subtitleSites,
              emptyIcon: Icons.subtitles_rounded,
              emptyTitle: '暂无字幕源',
              emptySubtitle: '添加 OpenSubtitles 等字幕源来下载字幕',
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.subtitles_rounded,
                  color: AppColors.success,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '字幕源',
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '管理 OpenSubtitles 等字幕下载源',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                )
              else
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
}

/// 音乐刮削源入口组件
class _MusicScraperSourcesTile extends ConsumerWidget {
  const _MusicScraperSourcesTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(musicScraperSourcesProvider);
    final enabledCount = state.sources.where((s) => s.isEnabled).length;
    // 使用所有可用刮削源类型数量作为总数
    final totalCount = MusicScraperType.values.length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const MusicScraperSourcesPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.fileAudio.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.library_music_rounded,
                  color: AppColors.fileAudio,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '刮削源',
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '管理 MusicBrainz、网易云等音乐刮削源',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (enabledCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$enabledCount/$totalCount',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                )
              else
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
      loading: () => '计算中...',
      error: (_, _) => '未知',
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
            label: '下载',
            count: downloadingCount,
            subtitle: downloadingCount > 0
                ? '$downloadingCount 个任务进行中'
                : '暂无下载任务',
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
            label: '上传',
            count: uploadingCount,
            subtitle: uploadingCount > 0
                ? '$uploadingCount 个任务进行中'
                : '暂无上传任务',
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
            label: '缓存',
            count: cachingCount > 0 ? cachingCount : null,
            subtitle: cachingCount > 0
                ? '$cachingCount 个任务进行中'
                : cacheCount > 0
                    ? '$cacheCount 个缓存 ($cacheSizeText)'
                    : '暂无缓存',
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
  }) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                // 图标
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: isActive ? 0.15 : 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        icon,
                        color: color,
                        size: 20,
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
                        style: context.textTheme.bodyLarge?.copyWith(
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
                // 右侧箭头
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const MediaTrackingListPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.track_changes_rounded,
                  color: Colors.purple,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '媒体追踪',
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '管理 Trakt 等媒体追踪工具',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.purple,
                    ),
                  ),
                )
              else
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
}

/// 媒体管理入口组件
class _MediaManagementTile extends ConsumerWidget {
  const _MediaManagementTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final managementSources = ref.watch(mediaManagementSourcesProvider);
    final count = managementSources.length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const MediaManagementListPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.construction_rounded,
                  color: Colors.teal,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '媒体管理',
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '管理 NASTool、MoviePilot 等工具',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.teal,
                    ),
                  ),
                )
              else
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
}

/// 下载器入口组件
class _DownloaderTile extends ConsumerWidget {
  const _DownloaderTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaderSources = ref.watch(downloadToolSourcesProvider);
    final count = downloaderSources.length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const DownloaderListPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.download_for_offline_rounded,
                  color: AppColors.warning,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '远程任务',
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '管理远程下载任务和服务',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning,
                    ),
                  ),
                )
              else
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
}

/// 直播源入口组件
class _LiveStreamingTile extends ConsumerWidget {
  const _LiveStreamingTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(liveStreamSettingsProvider);
    final count = settings.enabledSources.length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const LiveStreamSettingsPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.live_tv_rounded,
                  color: Colors.red,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '直播源',
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '管理 IPTV、M3U 播放列表等直播源',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.red,
                    ),
                  ),
                )
              else
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
}

/// PT 站点入口组件
class _PTSitesTile extends ConsumerWidget {
  const _PTSitesTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ptSitesSources = ref.watch(ptSitesSourcesProvider);
    final count = ptSitesSources.length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const PTSitesListPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.rss_feed_rounded,
                  color: Colors.indigo,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '资源站点',
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '管理资源站点连接',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.indigo,
                    ),
                  ),
                )
              else
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
}

/// 语言偏好设置组件
class _LanguagePreferenceTile extends ConsumerWidget {
  const _LanguagePreferenceTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(languagePreferenceProvider);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showLanguageSettingsSheet(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.language_rounded,
                  color: AppColors.info,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '语言偏好',
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getPreferenceSummary(preference),
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
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

  String _getPreferenceSummary(LanguagePreference preference) {
    final metadata = preference.getPreferredLanguage(LanguageType.metadata);
    final audio = preference.getPreferredLanguage(LanguageType.audio);
    final subtitle = preference.getPreferredLanguage(LanguageType.subtitle);

    final isAllAuto = metadata == LanguageOption.auto &&
        audio == LanguageOption.auto &&
        subtitle == LanguageOption.auto;

    if (isAllAuto) {
      return '全部自动';
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

    return parts.isEmpty ? '全部自动' : parts.join(' | ');
  }

  void _showLanguageSettingsSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _LanguageSettingsSheet(isDark: isDark),
    );
  }
}

/// 语言设置底部弹窗
class _LanguageSettingsSheet extends ConsumerWidget {
  const _LanguageSettingsSheet({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(languagePreferenceProvider);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurface.withValues(alpha: 0.95)
                : AppColors.lightSurface.withValues(alpha: 0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: isDark ? AppColors.glassStroke : AppColors.lightOutline.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 拖动指示器
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.3)
                        : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    '语言偏好设置',
                    style: context.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Text(
                    '设置影片元数据、音频和字幕的默认显示语言',
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
                  title: '元数据语言',
                  subtitle: '影片标题、简介、演员信息',
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
                  title: '音频语言',
                  subtitle: '默认播放的音轨语言',
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
                  title: '字幕语言',
                  subtitle: '默认显示的字幕语言',
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
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const BookSourcesPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.library_books_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '书源管理',
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '导入和管理在线书源',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
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
}

/// 图书设置入口组件
class _BookSettingsTile extends StatelessWidget {
  const _BookSettingsTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const BookSettingsPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_stories_rounded,
                  color: Colors.amber,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '阅读器设置',
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '选择阅读引擎、翻页方式等',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
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

/// 桌面 mine 页左侧 section 列表。
class _DesktopSectionList extends StatelessWidget {
  const _DesktopSectionList({
    required this.sections,
    required this.selectedIndex,
    required this.isDark,
    required this.onSelect,
  });

  final List<_MineSection> sections;
  final int selectedIndex;
  final bool isDark;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      itemCount: sections.length,
      itemBuilder: (context, index) {
        final section = sections[index];
        final isSelected = index == selectedIndex;
        final color = isSelected
            ? AppColors.primary
            : (isDark
                ? AppColors.darkOnSurfaceVariant
                : context.colorScheme.onSurfaceVariant);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onSelect(index),
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(section.icon, size: 20, color: color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        section.title,
                        style: TextStyle(
                          fontSize: 14,
                          color: color,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 桌面 mine 页右侧详情面板：标题 + 当前选中 section 的 tiles。
/// 桌面 mine 页右侧详情面板。
///
/// 内嵌一个 [Navigator]，section 内容是该 navigator 的 root route。
/// 这样 settings tile 的 `Navigator.push(ctx, ...)` 会 push 到这个嵌套
/// navigator——子页只覆盖右侧 panel，不会覆盖左侧 NavigationRail 与
/// section 列表。
///
/// section 切换时清空栈，pushAndRemoveUntil 到新 section root route。
class _DesktopSectionDetail extends StatefulWidget {
  const _DesktopSectionDetail({
    required this.section,
    required this.isDark,
    required this.uiStyle,
    required this.buildSettingsCard,
  });

  final _MineSection section;
  final bool isDark;
  final UIStyle uiStyle;

  /// 复用 mine_page 的 _buildSettingsCard 逻辑（保持视觉一致）。
  final Widget Function({required List<Widget> children}) buildSettingsCard;

  @override
  State<_DesktopSectionDetail> createState() => _DesktopSectionDetailState();
}

class _DesktopSectionDetailState extends State<_DesktopSectionDetail> {
  final _navKey = GlobalKey<NavigatorState>();

  @override
  void didUpdateWidget(covariant _DesktopSectionDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section.title != widget.section.title) {
      // 切换到新 section：清栈、显示新 root 路由。
      _navKey.currentState?.pushAndRemoveUntil(
        _buildRootRoute(),
        (_) => false,
      );
    }
  }

  /// section 切换时使用无过渡动画的 PageRoute，避免 slide-in 让用户感觉
  /// "进入了新页面"。push 二级 settings 子页仍走默认 slide 动画。
  PageRoute<void> _buildRootRoute() => PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => _DesktopSectionRootContent(
          section: widget.section,
          isDark: widget.isDark,
          uiStyle: widget.uiStyle,
          buildSettingsCard: widget.buildSettingsCard,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      );

  @override
  Widget build(BuildContext context) {
    // 限宽 800 + 居中：detail panel 内容（含 section root 与所有
    // push 进来的 settings 子页）在大屏下不再被拉伸到全宽。
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Navigator(
          key: _navKey,
          onGenerateInitialRoutes: (_, __) => [_buildRootRoute()],
        ),
      ),
    );
  }
}

/// detail navigator 的根路由内容：section 标题 + tiles 卡片。
class _DesktopSectionRootContent extends StatelessWidget {
  const _DesktopSectionRootContent({
    required this.section,
    required this.isDark,
    required this.uiStyle,
    required this.buildSettingsCard,
  });

  final _MineSection section;
  final bool isDark;
  final UIStyle uiStyle;
  final Widget Function({required List<Widget> children}) buildSettingsCard;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md, left: 4),
            child: Row(
              children: [
                Icon(
                  section.icon,
                  size: 22,
                  color: isDark
                      ? AppColors.darkOnSurface
                      : context.colorScheme.onSurface,
                ),
                const SizedBox(width: 10),
                Text(
                  section.title,
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.darkOnSurface
                        : context.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          // section.tilesBuilder 接收 root route 内 context；
          // tile 内 Navigator.push(ctx, ...) 会进入嵌套 detail navigator。
          Builder(builder: (innerCtx) {
            final tiles = section.tilesBuilder(innerCtx);
            return section.useCardWrapper
                ? buildSettingsCard(children: tiles)
                : Column(children: tiles);
          }),
          SizedBox(height: context.scrollBottomPadding),
        ],
      ),
    );
  }
}
