import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/widgets/video_poster.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

/// 重复视频管理页面
class VideoDuplicatesPage extends ConsumerStatefulWidget {
  const VideoDuplicatesPage({super.key});

  @override
  ConsumerState<VideoDuplicatesPage> createState() => _VideoDuplicatesPageState();
}

class _VideoDuplicatesPageState extends ConsumerState<VideoDuplicatesPage>
    with ConsumerTabBarVisibilityMixin {
  final VideoDatabaseService _db = VideoDatabaseService();

  // 状态
  bool _isLoading = true;
  bool _isDeleting = false;
  String? _errorMessage;

  // 重复视频数据
  Map<int, List<VideoMetadata>> _tmdbDuplicates = {};
  Map<String, List<VideoMetadata>> _titleYearDuplicates = {};
  VideoDuplicateStats? _stats;

  // 选中的视频（用于删除）
  final Set<String> _selectedVideos = {}; // 存储 uniqueKey

  // 当前显示模式: 0=TMDB ID 重复, 1=标题+年份重复
  int _currentMode = 0;

  @override
  void initState() {
    super.initState();
    hideTabBar();
    _loadDuplicates();
  }

  Future<void> _loadDuplicates() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _db.init();

      final stats = await _db.getDuplicateStats();
      final tmdbDups = await _db.getDuplicatesByTmdbId();
      final titleYearDups = await _db.getDuplicatesByTitleYear();

      setState(() {
        _stats = stats;
        _tmdbDuplicates = tmdbDups;
        _titleYearDuplicates = titleYearDups;
        _isLoading = false;
      });
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'VideoDuplicatesPage._loadDuplicates');
      setState(() {
        _errorMessage = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  void _toggleVideoSelection(VideoMetadata video) {
    setState(() {
      if (_selectedVideos.contains(video.uniqueKey)) {
        _selectedVideos.remove(video.uniqueKey);
      } else {
        _selectedVideos.add(video.uniqueKey);
      }
    });
  }

  void _selectAllExceptFirst(List<VideoMetadata> videos) {
    setState(() {
      // 保留第一个（文件最大的），选中其他所有
      for (var i = 1; i < videos.length; i++) {
        _selectedVideos.add(videos[i].uniqueKey);
      }
    });
  }

  void _clearSelection() {
    setState(_selectedVideos.clear);
  }

  Future<void> _deleteSelected() async {
    if (_selectedVideos.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(
          '确定要删除选中的 ${_selectedVideos.length} 个视频吗？\n\n'
          '注意：此操作会从 NAS 中永久删除文件，无法恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);

    try {
      final connections = ref.read(activeConnectionsProvider);
      var deleted = 0;
      var failed = 0;

      for (final uniqueKey in _selectedVideos.toList()) {
        // 解析 uniqueKey (sourceId_filePath)
        final parts = uniqueKey.split('_');
        if (parts.length < 2) continue;

        final sourceId = parts.first;
        final filePath = parts.sublist(1).join('_');

        final connection = connections[sourceId];
        if (connection == null) {
          failed++;
          continue;
        }

        try {
          // 从 NAS 删除文件
          await connection.adapter.fileSystem.delete(filePath);
          // 从数据库删除记录
          await _db.deleteByPath(sourceId, filePath);
          deleted++;
        } on Exception catch (e) {
          logger.w('删除失败: $filePath - $e');
          failed++;
        }
      }

      _selectedVideos.clear();
      await _loadDuplicates();

      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(failed > 0
                ? l.videoDuplicatesDeleteWithFailure(deleted, failed)
                : l.videoDuplicatesDeleteSuccess(deleted)),
          ),
        );
      }
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'VideoDuplicatesPage._deleteSelected');
      setState(() {
        _errorMessage = '删除失败: $e';
        _isDeleting = false;
      });
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
      appBar: AppBar(
        leading: const RoundedBackButton(),
        title: const Text('重复视频'),
        backgroundColor: isDark ? AppColors.darkSurface : null,
        actions: [
          if (_selectedVideos.isNotEmpty) ...[
            TextButton(
              onPressed: _clearSelection,
              child: Text('取消选择 (${_selectedVideos.length})'),
            ),
            IconButton(
              onPressed: _isDeleting ? null : _deleteSelected,
              icon: _isDeleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.delete_rounded, color: AppColors.error),
              tooltip: '删除选中',
            ),
          ],
          IconButton(
            onPressed: _isLoading ? null : _loadDuplicates,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
          ),
        ],
      ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error.withValues(alpha: 0.8)),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: TextStyle(color: AppColors.error.withValues(alpha: 0.8))),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadDuplicates,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        // 模式切换选项卡
        SliverToBoxAdapter(child: _buildModeTabBar(isDark)),

        // 统计信息卡片
        SliverToBoxAdapter(child: _buildStatsCard(isDark)),

        // 根据模式显示不同内容
        ..._buildContentByMode(isDark),
      ],
    );
  }

  List<Widget> _buildContentByMode(bool isDark) {
    switch (_currentMode) {
      case 0: // TMDB ID 重复
        if (_tmdbDuplicates.isEmpty) {
          return [SliverFillRemaining(child: _buildEmptyState(isDark))];
        }
        return [
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final entry = _tmdbDuplicates.entries.elementAt(index);
                final videos = entry.value;
                final firstVideo = videos.first;
                return _buildDuplicateGroup(
                  title: firstVideo.title ?? firstVideo.fileName,
                  subtitle: 'TMDB ID: ${entry.key}',
                  year: firstVideo.year,
                  videos: videos,
                  isDark: isDark,
                );
              },
              childCount: _tmdbDuplicates.length,
            ),
          ),
        ];

      case 1: // 标题+年份重复
        if (_titleYearDuplicates.isEmpty) {
          return [SliverFillRemaining(child: _buildEmptyState(isDark))];
        }
        return [
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final entry = _titleYearDuplicates.entries.elementAt(index);
                final videos = entry.value;
                final parts = entry.key.split('|');
                final title = parts.isNotEmpty ? parts.first : '';
                final year = parts.length > 1 ? int.tryParse(parts.last) : null;
                return _buildDuplicateGroup(
                  title: title,
                  subtitle: '基于标题+年份匹配',
                  year: year,
                  videos: videos,
                  isDark: isDark,
                );
              },
              childCount: _titleYearDuplicates.length,
            ),
          ),
        ];

      default:
        return [SliverFillRemaining(child: _buildEmptyState(isDark))];
    }
  }

  Widget _buildModeTabBar(bool isDark) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceElevated : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildModeTab(
                title: 'TMDB ID',
                subtitle: '精确匹配',
                isSelected: _currentMode == 0,
                count: _stats?.tmdbIdGroups ?? 0,
                isDark: isDark,
                onTap: () => setState(() => _currentMode = 0),
              ),
            ),
            Expanded(
              child: _buildModeTab(
                title: '标题+年份',
                subtitle: '无元数据',
                isSelected: _currentMode == 1,
                count: _stats?.titleYearGroups ?? 0,
                isDark: isDark,
                onTap: () => setState(() => _currentMode = 1),
              ),
            ),
          ],
        ),
      );

  Widget _buildModeTab({
    required String title,
    required String subtitle,
    required bool isSelected,
    required int count,
    required bool isDark,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? AppColors.darkSurface : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected
                          ? AppColors.primary
                          : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : (isDark ? AppColors.darkOutline : AppColors.lightOutline),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? AppColors.primary
                              : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.grey[500] : Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildStatsCard(bool isDark) {
    final stats = _stats;
    if (stats == null) return const SizedBox.shrink();

    final (groups, files) = _currentMode == 0
        ? (stats.tmdbIdGroups, stats.tmdbIdFiles)
        : (stats.titleYearGroups, stats.titleYearFiles);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDark ? AppColors.darkSurfaceElevated : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildStatItem(
                  '重复组',
                  '$groups',
                  Icons.collections_rounded,
                  isDark,
                ),
                const SizedBox(width: 24),
                _buildStatItem(
                  '涉及文件',
                  '$files',
                  Icons.video_library_rounded,
                  isDark,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _currentMode == 0
                          ? '基于 TMDB ID 精确匹配，这些视频是同一部影片的不同版本。'
                          : '基于标题和年份匹配，仅针对未刮削的视频。可能存在误判。',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
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

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    bool isDark,
  ) =>
      Expanded(
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : null,
              ),
            ),
            Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ],
        ),
      );

  Widget _buildEmptyState(bool isDark) {
    final (title, subtitle) = switch (_currentMode) {
      0 => ('没有发现 TMDB ID 重复', '所有已刮削的视频都是唯一的'),
      1 => ('没有发现标题+年份重复', '未刮削的视频中没有重复'),
      _ => ('没有数据', ''),
    };

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 64,
            color: AppColors.success.withValues(alpha: 0.8),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: context.textTheme.titleMedium?.copyWith(
              color: isDark ? Colors.white : null,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: context.textTheme.bodyMedium?.copyWith(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDuplicateGroup({
    required String title,
    required String subtitle,
    required int? year,
    required List<VideoMetadata> videos,
    required bool isDark,
  }) {
    final connections = ref.watch(activeConnectionsProvider);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDark ? AppColors.darkSurfaceElevated : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 组头部
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.movie_outlined, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$title${year != null ? ' ($year)' : ''}',
                              style: context.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${videos.length} 个文件',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            subtitle,
                            style: context.textTheme.bodySmall?.copyWith(
                              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _selectAllExceptFirst(videos),
                  icon: const Icon(Icons.select_all, size: 18),
                  label: const Text('选择其他'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
          ),

          // 视频列表
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            itemCount: videos.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final video = videos[index];
              final isSelected = _selectedVideos.contains(video.uniqueKey);
              final isFirst = index == 0;
              final connection = connections[video.sourceId];
              final fileSystem = connection?.adapter.fileSystem;

              return GestureDetector(
                onTap: () => _toggleVideoSelection(video),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.error.withValues(alpha: 0.1)
                        : (isDark ? Colors.grey[850] : Colors.grey[100]),
                    borderRadius: BorderRadius.circular(8),
                    border: isSelected ? Border.all(color: AppColors.error, width: 2) : null,
                  ),
                  child: Row(
                    children: [
                      // 海报
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          width: 60,
                          height: 90,
                          child: VideoPoster(
                            posterUrl: video.posterUrl,
                            sourceId: video.sourceId,
                            fileSystem: fileSystem,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // 文件信息
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 文件名
                            Text(
                              video.fileName,
                              style: context.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                                decoration:
                                    isSelected ? TextDecoration.lineThrough : null,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),

                            // 文件大小和分辨率
                            Row(
                              children: [
                                if (video.fileSizeText.isNotEmpty) ...[
                                  Icon(
                                    Icons.storage,
                                    size: 14,
                                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    video.fileSizeText,
                                    style: context.textTheme.bodySmall?.copyWith(
                                      color:
                                          isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                if (video.resolution != null) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.downloadColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      video.resolution!,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.downloadColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),

                            // 文件路径
                            Text(
                              video.filePath,
                              style: context.textTheme.bodySmall?.copyWith(
                                color: isDark ? Colors.grey[500] : Colors.grey[500],
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      // 状态标记
                      Column(
                        children: [
                          if (isFirst)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.success,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '推荐保留',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Icon(
                            isSelected
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked_rounded,
                            color: isSelected ? AppColors.error : Colors.grey,
                            size: 24,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
