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
import 'package:my_nas/features/music/presentation/pages/music_player_settings_page.dart';
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

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: Column(
        children: [
          // 固定的顶部头像区域
          _buildHeader(context, isDark, connectedCount, connections.length),
          // 可滚动的设置列表
          Expanded(
            child: ListView(
              padding: AppSpacing.paddingMd,
              children: [
                // 连接设置
                _buildSectionHeader(context, '连接', Icons.lan_rounded, isDark),
                const SizedBox(height: AppSpacing.sm),
                _buildSettingsCard(
                  context,
                  isDark,
                  uiStyle,
                  children: [
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
                        context,
                        MaterialPageRoute<void>(builder: (_) => const MediaLibraryPage()),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.lg),

                // 我的内容
                _buildSectionHeader(context, '我的内容', Icons.bookmark_rounded, isDark),
                const SizedBox(height: AppSpacing.sm),
                _buildSettingsCard(
                  context,
                  isDark,
                  uiStyle,
                  children: [
                    _buildSettingsTile(
                      context,
                      isDark,
                      icon: Icons.favorite_rounded,
                      iconColor: AppColors.error,
                      title: '我的收藏',
                      subtitle: '已收藏的视频、照片、笔记、图书、漫画',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(builder: (_) => const FavoritesPage()),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.lg),

                // 视频设置
                _buildSectionHeader(context, '视频', Icons.movie_rounded, isDark),
                const SizedBox(height: AppSpacing.sm),
                _buildSettingsCard(
                  context,
                  isDark,
                  uiStyle,
                  children: [
                    _buildSettingsTile(
                      context,
                      isDark,
                      icon: Icons.play_circle_rounded,
                      iconColor: AppColors.primary,
                      title: '播放器设置',
                      subtitle: '清晰度、投屏、转码等',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(builder: (_) => const VideoPlayerSettingsPage()),
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

                const SizedBox(height: AppSpacing.lg),

                // 音乐设置
                _buildSectionHeader(context, '音乐', Icons.music_note_rounded, isDark),
                const SizedBox(height: AppSpacing.sm),
                _buildSettingsCard(
                  context,
                  isDark,
                  uiStyle,
                  children: [
                    _buildSettingsTile(
                      context,
                      isDark,
                      icon: Icons.play_circle_rounded,
                      iconColor: AppColors.primary,
                      title: '播放器设置',
                      subtitle: '播放引擎、音量、淡入淡出等',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(builder: (_) => const MusicPlayerSettingsPage()),
                      ),
                    ),
                    _buildDivider(isDark),
                    _MusicScraperSourcesTile(isDark: isDark),
                  ],
                ),

                const SizedBox(height: AppSpacing.lg),

                // 图书设置
                _buildSectionHeader(context, '图书', Icons.auto_stories_rounded, isDark),
                const SizedBox(height: AppSpacing.sm),
                _buildSettingsCard(
                  context,
                  isDark,
                  uiStyle,
                  children: [
                    _BookSourcesTile(isDark: isDark),
                    _buildDivider(isDark),
                    _BookSettingsTile(isDark: isDark),
                  ],
                ),

                const SizedBox(height: AppSpacing.lg),

                // 站点
                _buildSectionHeader(context, '站点', Icons.rss_feed_rounded, isDark),
                const SizedBox(height: AppSpacing.sm),
                _buildSettingsCard(
                  context,
                  isDark,
                  uiStyle,
                  children: [
                    _PTSitesTile(isDark: isDark),
                  ],
                ),

                const SizedBox(height: AppSpacing.lg),

                // 传输
                _buildSectionHeader(context, '传输', Icons.swap_vert_rounded, isDark),
                const SizedBox(height: AppSpacing.sm),
                _TransferCard(isDark: isDark),

                const SizedBox(height: AppSpacing.lg),

                // 外观设置
                _buildSectionHeader(context, '外观', Icons.palette_outlined, isDark),
                const SizedBox(height: AppSpacing.sm),
                _buildSettingsCard(
                  context,
                  isDark,
                  uiStyle,
                  children: [
                    _buildSettingsTile(
                      context,
                      isDark,
                      icon: Icons.palette_rounded,
                      iconColor: Theme.of(context).colorScheme.primary,
                      title: '外观设置',
                      subtitle: '主题、配色、UI 风格',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const AppearanceSettingsPage(),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.lg),

                // 关于
                _buildSectionHeader(context, '关于', Icons.info_outline_rounded, isDark),
                const SizedBox(height: AppSpacing.sm),
                _buildSettingsCard(
                  context,
                  isDark,
                  uiStyle,
                  children: [
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
                // 底部间距：使用统一的滚动底部间距，自动适配玻璃/经典模式和平台
                SizedBox(height: context.scrollBottomPadding),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark, int connectedCount, int totalCount) => Container(
      padding: EdgeInsets.fromLTRB(20, context.padding.top + 20, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [AppColors.darkSurface, AppColors.darkBackground]
              : [AppColors.primary.withValues(alpha: 0.1), Colors.white],
        ),
      ),
      child: Row(
        children: [
          // 头像
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/logo.png',
                width: 64,
                height: 64,
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
                  style: context.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
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
    return AdaptiveGlassContainer(
      uiStyle: uiStyle,
      isDark: isDark,
      cornerRadius: 20,
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
  }) => Material(
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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.textTheme.bodyLarge?.copyWith(
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
              if (showChevron && onTap != null)
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
