import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/media_tracking/presentation/providers/trakt_provider.dart';
import 'package:my_nas/features/media_tracking/presentation/providers/trakt_sync_provider.dart';
import 'package:my_nas/features/video/data/services/trakt_scrobble_service.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/presentation/pages/video_player_page.dart';
import 'package:my_nas/service_adapters/trakt/api/trakt_api.dart';
import 'package:my_nas/service_adapters/trakt/trakt_config.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';


/// Trakt 连接页面
///
/// 支持两种授权方式：
/// 1. Device Code Flow（推荐）- 显示验证码，用户在另一设备上输入
/// 2. 自定义凭证 - 用户输入自己的 Client ID/Secret
class TraktConnectionPage extends ConsumerStatefulWidget {
  const TraktConnectionPage({super.key});

  @override
  ConsumerState<TraktConnectionPage> createState() => _TraktConnectionPageState();
}

class _TraktConnectionPageState extends ConsumerState<TraktConnectionPage>
    with ConsumerTabBarVisibilityMixin {
  final _clientIdController = TextEditingController();
  final _clientSecretController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _showCustomCredentials = false;
  bool _obscureSecret = true;

  @override
  void initState() {
    super.initState();
    hideTabBar();
    // 使用 Future.microtask 确保在第一帧后执行
    Future.microtask(_initializeData);
  }

  /// 初始化数据：如果已连接则加载播放进度
  void _initializeData() {
    final traktState = ref.read(traktConnectionProvider);
    if (traktState.isConnected) {
      ref.read(traktSyncProvider.notifier).refreshPlaybackProgress();
    }

    // 监听连接状态变化，当刚连接成功时自动刷新播放进度
    ref.listenManual(traktConnectionProvider, (previous, next) {
      if (previous?.isConnected != true && next.isConnected) {
        ref.read(traktSyncProvider.notifier).refreshPlaybackProgress();
      }
    });
  }

  @override
  void deactivate() {
    // 离开页面时如果正在进行设备码流程，应该取消
    // 使用 Future.microtask 避免在构建过程中修改 Provider 状态
    Future.microtask(() {
      if (mounted) {
        ref.read(traktConnectionProvider.notifier).cancelDeviceCodeFlow();
      }
    });
    super.deactivate();
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final traktState = ref.watch(traktConnectionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trakt'),
        centerTitle: true,
        actions: [
          if (traktState.isConnected)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                ref.read(traktConnectionProvider.notifier).refreshStats();
              },
            ),
        ],
      ),
      body: traktState.isConnected
          ? _buildConnectedView(context, traktState)
          : _buildDisconnectedView(context, traktState),
    );
  }

  /// 已连接状态视图
  Widget _buildConnectedView(BuildContext context, TraktConnectionState state) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final userSettings = state.userSettings;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 用户信息卡片
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: colorScheme.primaryContainer,
                    backgroundImage: userSettings?.avatarUrl != null
                        ? NetworkImage(userSettings!.avatarUrl!)
                        : null,
                    child: userSettings?.avatarUrl == null
                        ? Icon(Icons.person, size: 40, color: colorScheme.primary)
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    userSettings?.username ?? '未知用户',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (userSettings?.name != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      userSettings!.name!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 16, color: AppColors.success),
                        const SizedBox(width: 6),
                        Text(
                          '已连接',
                          style: TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 同步统计
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '同步统计',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatItem(
                            context, Icons.movie_outlined, '电影',
                            '${state.stats?.moviesWatched ?? 0}'),
                      ),
                      Expanded(
                        child: _buildStatItem(
                            context, Icons.tv_outlined, '剧集',
                            '${state.stats?.episodesWatched ?? 0}'),
                      ),
                      Expanded(
                        child: _buildStatItem(
                            context, Icons.subscriptions_outlined, '节目',
                            '${state.stats?.showsWatched ?? 0}'),
                      ),
                      Expanded(
                        child: _buildStatItem(
                            context, Icons.bookmark_border, '待看',
                            '${state.stats?.watchlistCount ?? 0}'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 同步设置
          _buildSyncSettingsCard(context),
          const SizedBox(height: 16),

          // 继续观看
          _buildContinueWatchingCard(context),
          const SizedBox(height: 24),

          // 注销按钮
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showLogoutConfirmation,
              icon: const Icon(Icons.logout),
              label: const Text('注销'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.error,
                side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 同步设置卡片
  Widget _buildSyncSettingsCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final scrobbleSettings = ref.watch(traktScrobbleSettingsProvider);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '同步设置',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            // Scrobble 开关
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('自动 Scrobble'),
              subtitle: Text(
                '播放时自动上报进度到 Trakt',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              value: scrobbleSettings.enabled,
              onChanged: (value) {
                ref.read(traktScrobbleSettingsProvider.notifier).setEnabled(value);
              },
            ),
            const Divider(),
            // 说明文字
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '播放进度 ≥80% 时自动标记为已观看',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 继续观看卡片
  Widget _buildContinueWatchingCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final traktSync = ref.watch(traktSyncProvider);
    final combinedAsync = ref.watch(combinedContinueWatchingProvider);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '继续观看',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (traktSync.isLoading || combinedAsync.isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: () {
                      ref
                        ..read(traktSyncProvider.notifier).refreshPlaybackProgress()
                        ..invalidate(combinedContinueWatchingProvider);
                    },
                    tooltip: '刷新',
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            combinedAsync.when(
              data: (items) {
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        '暂无未完成的播放',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    ...items.take(5).map(
                          (item) => _buildContinueWatchingItem(context, item),
                        ),
                    if (items.length > 5)
                      Center(
                        child: TextButton(
                          onPressed: () => _showAllContinueWatching(context, items),
                          child: Text('查看全部 (${items.length})'),
                        ),
                      ),
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    '加载失败',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 继续观看项（使用本地化标题）
  Widget _buildContinueWatchingItem(BuildContext context, ContinueWatchingItem item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 使用本地化标题
    final title = item.displayTitle;
    String? subtitle;

    // 生成副标题（年份或来源标识）
    if (item.metadata?.year != null) {
      subtitle = item.metadata!.year.toString();
    } else if (item.traktProgress?.type == 'movie') {
      subtitle = item.traktProgress!.movie?.year?.toString();
    }

    // 添加来源标识
    final sourceLabel = item.source == ContinueWatchingSource.trakt ? 'Trakt' : '本地';

    return InkWell(
      onTap: item.isPlayable ? () => _playContinueWatchingItem(context, item) : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            // 进度圆环
            SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: item.progress / 100,
                    strokeWidth: 3,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    color: colorScheme.primary,
                  ),
                  Text(
                    '${item.progress.round()}%',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // 标题和副标题
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // 播放图标（可播放时显示）
            if (item.isPlayable)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
              ),
            // 来源标识
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: item.source == ContinueWatchingSource.trakt
                    ? const Color(0xFFED1C24).withValues(alpha: 0.1)
                    : colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                sourceLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: item.source == ContinueWatchingSource.trakt
                      ? const Color(0xFFED1C24)
                      : colorScheme.primary,
                  fontSize: 10,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 删除按钮（仅 Trakt 进度可删除）
            if (item.traktProgress != null)
              IconButton(
                icon: Icon(
                  Icons.close,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                onPressed: () {
                  ref.read(traktSyncProvider.notifier).deleteProgress(item.traktProgress!.id);
                  ref.invalidate(combinedContinueWatchingProvider);
                },
                tooltip: '删除进度',
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }

  /// 播放继续观看项
  Future<void> _playContinueWatchingItem(BuildContext context, ContinueWatchingItem item) async {
    // 优先使用本地历史记录播放
    if (item.localHistoryItem != null) {
      final historyItem = item.localHistoryItem!;
      final videoItem = VideoItem(
        name: item.displayTitle,
        path: historyItem.videoPath,
        url: historyItem.videoUrl,
        sourceId: historyItem.sourceId,
        size: historyItem.size,
        thumbnailUrl: historyItem.thumbnailUrl,
        lastPosition: historyItem.lastPosition,
      );

      if (!context.mounted) return;

      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (context) => VideoPlayerPage(video: videoItem),
        ),
      );

      if (!context.mounted) return;
      ref.invalidate(combinedContinueWatchingProvider);
      return;
    }

    // 使用元数据播放
    if (item.metadata != null && item.videoPath != null) {
      final videoItem = VideoItem(
        name: item.displayTitle,
        path: item.videoPath!,
        url: '', // URL 需要通过 VideoPlayerPage 内部获取
        sourceId: item.sourceId,
        thumbnailUrl: item.metadata!.displayPosterUrl,
      );

      if (!context.mounted) return;

      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (context) => VideoPlayerPage(video: videoItem),
        ),
      );

      if (!context.mounted) return;
      ref.invalidate(combinedContinueWatchingProvider);
    }
  }


  Widget _buildStatItem(BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Icon(icon, color: colorScheme.primary, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// 显示完整的继续观看列表
  void _showAllContinueWatching(BuildContext context, List<ContinueWatchingItem> items) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // 拖动指示器
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 标题
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    '继续观看',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '共 ${items.length} 项',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            // 列表
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: items.length,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemBuilder: (context, index) =>
                    _buildContinueWatchingItem(context, items[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutConfirmation() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('注销 Trakt'),
        content: const Text('确定要注销吗？这将清除所有保存的认证信息。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(traktConnectionProvider.notifier).logout();
            },
            child: const Text('注销'),
          ),
        ],
      ),
    );
  }

  /// 未连接状态视图
  Widget _buildDisconnectedView(BuildContext context, TraktConnectionState state) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final deviceCode = state.deviceCode; // 从 state 读取，以触发 UI 重建
    final isConnecting = state.status == TraktConnectionStatus.connecting;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Trakt Logo 和说明
            _buildHeader(context),
            const SizedBox(height: 24),

            // 如果有设备码，显示验证码界面
            if (deviceCode != null && isConnecting) ...[
              _buildDeviceCodeView(context, deviceCode),
            ] else if (_showCustomCredentials) ...[
              // 自定义凭证输入
              _buildCustomCredentialsForm(context, state),
            ] else ...[
              // 主登录按钮
              _buildMainLoginButton(context, state),
            ],

            // 错误信息
            if (state.errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.errorMessage!,
                        style: TextStyle(color: colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFED1C24).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.track_changes,
                size: 40,
                color: Color(0xFFED1C24),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Trakt',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '自动同步观看记录到云端\n跨设备追踪电影和剧集进度',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 设备码验证界面
  Widget _buildDeviceCodeView(BuildContext context, TraktDeviceCode deviceCode) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
      ),
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // 步骤说明
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('1', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '访问以下网址',
                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 验证网址
            InkWell(
              onTap: () => _launchUrl(deviceCode.verificationUrl),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.link, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      deviceCode.verificationUrl,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.open_in_new, size: 16, color: colorScheme.primary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 步骤 2
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('2', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '输入验证码',
                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 验证码显示
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: deviceCode.userCode));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('验证码已复制'), duration: Duration(seconds: 2)),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.primary, width: 2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      deviceCode.userCode,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.copy, color: colorScheme.primary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 等待状态
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '等待授权...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 取消按钮
            TextButton(
              onPressed: () {
                ref.read(traktConnectionProvider.notifier).cancelDeviceCodeFlow();
              },
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
  }

  /// 主登录按钮
  Widget _buildMainLoginButton(BuildContext context, TraktConnectionState state) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasBuiltIn = TraktOAuthConfig.hasBuiltInCredentials;
    final isConnecting = state.status == TraktConnectionStatus.connecting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 主按钮 - 如果有内置凭证则启动 Device Code Flow
        if (hasBuiltIn) ...[
          FilledButton.icon(
            onPressed: isConnecting ? null : _startDeviceCodeFlow,
            icon: isConnecting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: const Text('连接 Trakt 账号'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 12),
          // 简洁的说明文字
          Text(
            '点击后将显示验证码，在任意设备浏览器中输入即可完成连接',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          // 高级选项 - 更低调的展示
          Center(
            child: TextButton(
              onPressed: () {
                setState(() {
                  _showCustomCredentials = true;
                });
              },
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                textStyle: theme.textTheme.bodySmall,
              ),
              child: const Text('使用自定义 API 凭证'),
            ),
          ),
        ] else ...[
          // 没有内置凭证，直接显示自定义凭证表单
          _buildCustomCredentialsForm(context, state),
        ],
      ],
    );
  }

  /// 自定义凭证表单
  Widget _buildCustomCredentialsForm(BuildContext context, TraktConnectionState state) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isConnecting = state.status == TraktConnectionStatus.connecting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (TraktOAuthConfig.hasBuiltInCredentials) ...[
          // 返回按钮
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  _showCustomCredentials = false;
                });
              },
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('返回'),
            ),
          ),
          const SizedBox(height: 8),
        ],

        // 说明
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.code, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '开发者选项',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '使用自己在 trakt.tv/oauth/applications 创建的应用凭证',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        TextFormField(
          controller: _clientIdController,
          decoration: InputDecoration(
            labelText: 'Client ID',
            prefixIcon: const Icon(Icons.apps),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return '请输入 Client ID';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),

        TextFormField(
          controller: _clientSecretController,
          obscureText: _obscureSecret,
          decoration: InputDecoration(
            labelText: 'Client Secret',
            prefixIcon: const Icon(Icons.vpn_key),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            suffixIcon: IconButton(
              icon: Icon(_obscureSecret ? Icons.visibility : Icons.visibility_off),
              onPressed: () {
                setState(() {
                  _obscureSecret = !_obscureSecret;
                });
              },
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return '请输入 Client Secret';
            }
            return null;
          },
        ),
        const SizedBox(height: 24),

        FilledButton.icon(
          onPressed: isConnecting ? null : _startCustomDeviceCodeFlow,
          icon: isConnecting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.login),
          label: const Text('连接'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }

  /// 使用内置凭证启动 Device Code Flow
  Future<void> _startDeviceCodeFlow() async {
    try {
      await ref.read(traktConnectionProvider.notifier).startDeviceCodeFlow();
    } on Exception catch (e) {
      if (mounted) {
        context.showErrorToast('启动授权失败: $e');
      }
    }
  }

  /// 使用自定义凭证启动 Device Code Flow
  Future<void> _startCustomDeviceCodeFlow() async {
    if (!_formKey.currentState!.validate()) return;

    final clientId = _clientIdController.text.trim();
    final clientSecret = _clientSecretController.text.trim();

    try {
      await ref.read(traktConnectionProvider.notifier).startDeviceCodeFlow(
            clientId: clientId,
            clientSecret: clientSecret,
          );
    } on Exception catch (e) {
      if (mounted) {
        context.showErrorToast('启动授权失败: $e');
      }
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
