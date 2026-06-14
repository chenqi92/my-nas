import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/widgets/media_info_badges.dart';
import 'package:my_nas/features/video/presentation/widgets/video_poster.dart';
import 'package:my_nas/shared/widgets/adaptive_image.dart';

/// 桌面端详情页左侧的 Master 面板
///
/// 与 [DetailHeroSection] 的区别：不再使用全屏 backdrop + 白色文字叠加，
/// 而是以普通主题表面承载，垂直排列 poster / 标题 / 评分 / 元数据 / 操作按钮。
/// 仅用于 master-detail 桌面布局，移动端仍走 DetailHeroSection。
class DetailMasterPanel extends StatelessWidget {
  const DetailMasterPanel({
    required this.metadata,
    required this.onPlay,
    this.onFavorite,
    this.onToggleWatched,
    this.onScrape,
    this.isFavorite = false,
    this.isWatched = false,
    this.watchProgress,
    this.tagline,
    this.displayTitle,
    this.tmdbRating,
    this.doubanRating,
    this.traktRating,
    this.imdbRating,
    this.metacriticRating,
    this.voteCount,
    this.sourceId,
    this.hideEpisodeInfo = false,
    this.qualitySelector,
    super.key,
  });

  final VideoMetadata metadata;
  final VoidCallback onPlay;
  final VoidCallback? onFavorite;
  final VoidCallback? onToggleWatched;
  final VoidCallback? onScrape;
  final bool isFavorite;
  final bool isWatched;
  final double? watchProgress;
  final String? tagline;
  final String? displayTitle;
  final double? tmdbRating;
  final double? doubanRating;
  final double? traktRating;
  final double? imdbRating;
  final int? metacriticRating;
  final int? voteCount;
  final String? sourceId;
  final bool hideEpisodeInfo;

  /// 可选的质量选择器（电影多版本时显示）
  final Widget? qualitySelector;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final colorScheme = theme.colorScheme;
    final poster = metadata.displayPosterUrl;
    final hasPoster = poster != null && poster.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poster
          Center(
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 280),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: hasPoster
                    ? _buildPoster(poster, colorScheme)
                    : _buildPosterPlaceholder(colorScheme),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 标题
          Text(
            displayTitle ?? metadata.displayTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          if (metadata.originalTitle != null &&
              metadata.originalTitle != metadata.title &&
              metadata.originalTitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              metadata.originalTitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],

          // 评分
          if (_hasAnyRating) ...[
            const SizedBox(height: 12),
            RatingBadges(
              tmdbRating: tmdbRating,
              imdbRating: imdbRating,
              metacriticRating: metacriticRating,
              traktRating: traktRating,
              doubanRating: doubanRating ??
                  (tmdbRating == null ? metadata.rating : null),
              voteCount: voteCount,
              spacing: 10,
              runSpacing: 6,
            ),
          ],

          // 元数据行
          const SizedBox(height: 12),
          _buildMetaText(theme, l),

          // 媒体技术标签（4K / HDR / Atmos）
          const SizedBox(height: 8),
          _buildTechChips(colorScheme),

          // tagline
          if (tagline != null && tagline!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              '"$tagline"',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ],

          // 操作按钮
          const SizedBox(height: 20),
          _buildActions(context, colorScheme),

          // 质量选择器
          if (qualitySelector != null) ...[
            const SizedBox(height: 12),
            qualitySelector!,
          ],
        ],
      ),
    );
  }

  bool get _hasAnyRating =>
      (tmdbRating != null && tmdbRating! > 0) ||
      (imdbRating != null && imdbRating! > 0) ||
      (traktRating != null && traktRating! > 0) ||
      (doubanRating != null && doubanRating! > 0) ||
      (metacriticRating != null && metacriticRating! > 0) ||
      (metadata.rating != null && metadata.rating! > 0);

  Widget _buildMetaText(ThemeData theme, AppLocalizations l) {
    final parts = <String>[];
    if (metadata.year != null) parts.add('${metadata.year}');
    if (metadata.runtime != null && metadata.runtime! > 0) {
      parts.add(_formatRuntime(metadata.runtime!, l));
    }
    if (metadata.genres != null && metadata.genres!.isNotEmpty) {
      parts.add(metadata.genres!);
    }
    if (metadata.category == MediaCategory.tvShow && !hideEpisodeInfo) {
      if (metadata.seasonNumber != null && metadata.episodeNumber != null) {
        final reparsed = VideoFileNameParser.parse(metadata.fileName);
        if (reparsed.season != null || reparsed.episode != null) {
          parts.add('S${metadata.seasonNumber} E${metadata.episodeNumber}');
        }
      }
    }
    if (parts.isEmpty) return const SizedBox.shrink();

    return Text(
      parts.join(' · '),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildTechChips(ColorScheme colorScheme) {
    final chips = <Widget>[];

    if (metadata.certification != null) {
      chips.add(_techChip(metadata.certification!, colorScheme,
          accent: _certColor(metadata.certification!), outlined: true));
    }
    if (metadata.resolution != null) {
      final upper = metadata.resolution!.toUpperCase();
      final is4K = upper == '4K' || upper == '2160P';
      chips.add(_techChip(
        is4K ? '4K' : metadata.resolution!.replaceAll('p', 'P'),
        colorScheme,
        accent: is4K ? const Color(0xFFE50914) : null,
      ));
    }
    if (metadata.hdrFormat != null) {
      final isDV = metadata.hdrFormat!.toUpperCase().contains('DOLBY') ||
          metadata.hdrFormat == 'DV';
      chips.add(_techChip(isDV ? 'Dolby Vision' : metadata.hdrFormat!,
          colorScheme,
          accent: const Color(0xFFFFB300)));
    }
    if (metadata.is3D) {
      chips.add(_techChip('3D', colorScheme, accent: const Color(0xFF00BCD4)));
    }
    if (metadata.audioFormat != null) {
      chips.add(_techChip(metadata.audioFormat!, colorScheme));
    }
    if (metadata.isRemux) {
      chips.add(_techChip('Remux', colorScheme,
          accent: const Color(0xFF7B1FA2)));
    } else if (metadata.videoSource != null) {
      final upper = metadata.videoSource!.toUpperCase();
      if (upper.contains('BLU') || upper.contains('BD')) {
        chips.add(
            _techChip('BluRay', colorScheme, accent: const Color(0xFF1565C0)));
      } else if (upper.contains('WEB')) {
        chips.add(_techChip(
            upper.contains('DL') ? 'WEB-DL' : 'WEB', colorScheme,
            accent: const Color(0xFF2E7D32)));
      } else {
        chips.add(_techChip(metadata.videoSource!, colorScheme));
      }
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }

  Widget _techChip(String label, ColorScheme cs,
      {Color? accent, bool outlined = false}) {
    final color = accent ?? cs.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: outlined ? Border.all(color: color, width: 1.2) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Color _certColor(String cert) {
    final upper = cert.toUpperCase();
    if (upper == 'G' || upper == 'TV-G') return AppColors.success;
    if (upper == 'PG' || upper == 'TV-PG') return AppColors.info;
    if (upper == 'PG-13' || upper == 'TV-14') return AppColors.warning;
    if (upper == 'R' || upper == 'TV-MA' || upper == 'NC-17') {
      return AppColors.error;
    }
    return AppColors.disabled;
  }

  Widget _buildActions(BuildContext context, ColorScheme cs) {
    final l = AppLocalizations.of(context);
    final progress = watchProgress;
    final hasProgress = progress != null && progress > 0.05;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: FilledButton.icon(
            onPressed: onPlay,
            icon: const Icon(Icons.play_arrow_rounded, size: 22),
            label: Text(
              hasProgress
                  ? l.detailPanelResume((progress * 100).toInt())
                  : l.detailPanelPlay,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        if (hasProgress) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            if (onToggleWatched != null) ...[
              Expanded(
                child: _SecondaryActionButton(
                  icon: isWatched
                      ? Icons.check_circle_rounded
                      : Icons.check_circle_outline_rounded,
                  label: isWatched
                      ? l.detailPanelWatched
                      : l.detailPanelUnwatched,
                  active: isWatched,
                  onTap: onToggleWatched!,
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (onFavorite != null) ...[
              Expanded(
                child: _SecondaryActionButton(
                  icon: isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  label: isFavorite
                      ? l.detailPanelFavorited
                      : l.detailPanelFavorite,
                  active: isFavorite,
                  activeColor: AppColors.error,
                  onTap: onFavorite!,
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (onScrape != null)
              Expanded(
                child: _SecondaryActionButton(
                  icon: Icons.auto_fix_high_rounded,
                  label: l.detailPanelScrape,
                  onTap: onScrape!,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPoster(String url, ColorScheme cs) {
    final isNasPath =
        url.startsWith('/') && !url.startsWith('//') && !url.contains('://');
    if (isNasPath && sourceId != null && sourceId!.isNotEmpty) {
      return VideoPoster(
        posterUrl: url,
        sourceId: sourceId,
        placeholder: _buildPosterPlaceholder(cs),
        errorWidget: _buildPosterPlaceholder(cs),
      );
    }
    return AdaptiveImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_) => _buildPosterPlaceholder(cs),
      errorWidget: (_, _) => _buildPosterPlaceholder(cs),
    );
  }

  Widget _buildPosterPlaceholder(ColorScheme cs) => Container(
        color: cs.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          metadata.category == MediaCategory.tvShow
              ? Icons.live_tv_rounded
              : Icons.movie_rounded,
          size: 48,
          color: cs.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      );

  String _formatRuntime(int minutes, AppLocalizations l) {
    if (minutes < 60) return l.detailPanelRuntimeMinutes(minutes);
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }
}

class _SecondaryActionButton extends StatelessWidget {
  const _SecondaryActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.activeColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = active ? (activeColor ?? cs.primary) : cs.onSurfaceVariant;

    return Material(
      color: active
          ? color.withValues(alpha: 0.12)
          : cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
