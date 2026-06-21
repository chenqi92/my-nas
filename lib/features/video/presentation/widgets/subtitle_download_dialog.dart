import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:my_nas/features/sources/presentation/pages/service_sources_page.dart';
import 'package:my_nas/features/video/data/services/opensubtitles_service.dart';
import 'package:my_nas/shared/providers/language_preference_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

/// 字幕下载对话框
///
/// 用于搜索和下载在线字幕（OpenSubtitles）
class SubtitleDownloadDialog extends ConsumerStatefulWidget {
  const SubtitleDownloadDialog({
    super.key,
    this.tmdbId,
    this.imdbId,
    this.title,
    this.seasonNumber,
    this.episodeNumber,
    this.isMovie = true,
    required this.savePath,
    this.onDownloaded,
  });

  /// TMDB ID
  final int? tmdbId;

  /// IMDB ID
  final String? imdbId;

  /// 标题（用于搜索）
  final String? title;

  /// 季号
  final int? seasonNumber;

  /// 集号
  final int? episodeNumber;

  /// 是否为电影
  final bool isMovie;

  /// 字幕保存路径
  final String savePath;

  /// 下载完成回调
  final void Function(String path)? onDownloaded;

  /// 显示字幕下载对话框
  static Future<void> show({
    required BuildContext context,
    int? tmdbId,
    String? imdbId,
    String? title,
    int? seasonNumber,
    int? episodeNumber,
    bool isMovie = true,
    required String savePath,
    void Function(String path)? onDownloaded,
  }) async => showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SubtitleDownloadDialog(
        tmdbId: tmdbId,
        imdbId: imdbId,
        title: title,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        isMovie: isMovie,
        savePath: savePath,
        onDownloaded: onDownloaded,
      ),
    );

  @override
  ConsumerState<SubtitleDownloadDialog> createState() => _SubtitleDownloadDialogState();
}

class _SubtitleDownloadDialogState extends ConsumerState<SubtitleDownloadDialog> {
  List<OpenSubtitleResult>? _results;
  bool _isLoading = false;
  bool _isDownloading = false;
  String? _error;
  int? _downloadingFileId;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    final service = ref.read(openSubtitlesServiceProvider);
    if (service == null) {
      setState(() {
        _error = context.l10n.videoSubtitleDownloadDialogNotConfigured;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final languagePreference = ref.read(languagePreferenceProvider);
      final languages = getPreferredLanguageCodes(languagePreference);

      final params = OpenSubtitleSearchParams(
        tmdbId: widget.tmdbId,
        imdbId: widget.imdbId,
        query: widget.tmdbId == null && widget.imdbId == null ? widget.title : null,
        seasonNumber: widget.seasonNumber,
        episodeNumber: widget.episodeNumber,
        type: widget.isMovie ? 'movie' : 'episode',
        languages: languages,
      );

      final results = await service.search(params);

      if (!mounted) return;

      setState(() {
        _results = results;
        _isLoading = false;
        if (results.isEmpty) {
          _error = context.l10n.videoSubtitleDownloadDialogNoMatches;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _download(OpenSubtitleResult subtitle) async {
    final service = ref.read(openSubtitlesServiceProvider);
    if (service == null) return;

    setState(() {
      _isDownloading = true;
      _downloadingFileId = subtitle.fileId;
    });

    try {
      final savedPath = await service.downloadSubtitle(
        fileId: subtitle.fileId,
        savePath: widget.savePath,
      );

      if (!mounted) return;

      if (savedPath != null) {
        context.showSuccessToast(context.l10n.videoSubtitleDownloadSuccess);
        widget.onDownloaded?.call(savedPath);
        Navigator.of(context).pop();
      } else {
        context.showErrorToast(context.l10n.videoSubtitleDownloadFailed);
        setState(() {
          _isDownloading = false;
          _downloadingFileId = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      logger.e('下载字幕失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
      );
      setState(() {
        _isDownloading = false;
        _downloadingFileId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasService = ref.watch(hasOpenSubtitlesConfigProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // 拖动条
          const SheetDragHandle(topPadding: 8, bottomPadding: 8),
          // 标题栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.subtitles,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.videoSubtitleDownloadDialogTitle,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (widget.title != null)
                        Text(
                          widget.title!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (!hasService)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ServiceSourcesPage(
                            title: '字幕站点',
                            category: SourceCategory.subtitleSites,
                            emptyIcon: Icons.subtitles_rounded,
                            emptyTitle: '尚未配置字幕站点',
                            emptySubtitle: '添加 OpenSubtitles 等字幕服务\n用于在线搜索和下载字幕',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.settings_rounded, size: 18),
                    label: Text(context.l10n.videoSubtitleConfigureButton),
                  )
                else if (_isLoading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    onPressed: _search,
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: context.l10n.videoSubtitleRefreshButton,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 内容
          Expanded(
            child: _buildContent(theme, scrollController),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme, ScrollController scrollController) {
    if (!ref.watch(hasOpenSubtitlesConfigProvider)) {
      return _buildEmptyState(
        theme,
        icon: Icons.settings_rounded,
        title: context.l10n.videoSubtitleSourcesNotSetup,
        message: context.l10n.videoSubtitleSourcesSetupHint,
      );
    }

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(context.l10n.videoSubtitleDownloadDialogSearching),
          ],
        ),
      );
    }

    if (_error != null && (_results == null || _results!.isEmpty)) {
      return _buildEmptyState(
        theme,
        icon: Icons.search_off,
        title: context.l10n.videoSubtitleDownloadDialogSearchFailed,
        message: _error!,
        action: TextButton.icon(
          onPressed: _search,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(context.l10n.videoSubtitleDownloadDialogRetryButton),
        ),
      );
    }

    if (_results == null || _results!.isEmpty) {
      return _buildEmptyState(
        theme,
        icon: Icons.subtitles_off,
        title: context.l10n.videoSubtitleDownloadDialogNoResults,
        message: context.l10n.videoSubtitleDownloadDialogNoResultsHint,
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _results!.length,
      itemBuilder: (context, index) {
        final subtitle = _results![index];
        final isDownloading = _downloadingFileId == subtitle.fileId;

        return ListTile(
          leading: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getLanguageColor(subtitle.languageCode),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              subtitle.displayLanguage,
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(
            subtitle.fileName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          subtitle: Row(
            children: [
              Icon(
                Icons.download_rounded,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                _formatDownloadCount(subtitle.downloadCount),
                style: theme.textTheme.bodySmall,
              ),
              if (subtitle.qualityTags.isNotEmpty) ...[
                const SizedBox(width: 8),
                ...subtitle.qualityTags.map((tag) => Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: _getTagColor(tag),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        tag,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    )),
              ],
              if (subtitle.release != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    subtitle.release!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          trailing: isDownloading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  onPressed: _isDownloading ? null : () => _download(subtitle),
                  icon: const Icon(Icons.download_rounded),
                  tooltip: context.l10n.videoSubtitleDownloadButton,
                ),
          onTap: _isDownloading ? null : () => _download(subtitle),
        );
      },
    );
  }

  Widget _buildEmptyState(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              action,
            ],
          ],
        ),
      ),
    );

  Color _getLanguageColor(String languageCode) => switch (languageCode) {
      'zh-cn' || 'zh-tw' || 'zh' => AppColors.error,
      'en' => Colors.blue,
      'ja' => Colors.pink,
      'ko' => Colors.purple,
      'fr' => Colors.indigo,
      'de' => Colors.amber.shade700,
      'es' => Colors.orange,
      _ => Colors.grey,
    };

  Color _getTagColor(String tag) => switch (tag) {
      'SDH' => Colors.teal,
      'AI' => Colors.deepPurple,
      '机翻' => Colors.orange,
      _ => Colors.grey,
    };

  String _formatDownloadCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}
