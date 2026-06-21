import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';

/// 音乐库统计卡片
class MusicStatsCard extends StatelessWidget {
  const MusicStatsCard({
    required this.totalTracks,
    required this.totalArtists,
    required this.totalAlbums,
    required this.isDark,
    this.isDesktop = false,
    super.key,
  });

  final int totalTracks;
  final int totalArtists;
  final int totalAlbums;
  final bool isDark;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    if (isDesktop) {
      return _buildDesktopLayout(context);
    }
    return _buildMobileLayout(context);
  }

  Widget _buildMobileLayout(BuildContext context) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            context: context,
            icon: Icons.music_note_rounded,
            value: totalTracks,
            label: context.l10n.musicStatsCardSongs,
            color: AppColors.primary,
          ),
          _buildDivider(),
          _buildStatItem(
            context: context,
            icon: Icons.person_rounded,
            value: totalArtists,
            label: context.l10n.musicStatsCardArtists,
            color: Colors.purple,
          ),
          _buildDivider(),
          _buildStatItem(
            context: context,
            icon: Icons.album_rounded,
            value: totalAlbums,
            label: context.l10n.musicStatsCardAlbums,
            color: AppColors.warning,
          ),
        ],
      ),
    );

  Widget _buildDesktopLayout(BuildContext context) => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.musicStatsCardLibraryTitle,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 16),
          _buildStatItem(
            context: context,
            icon: Icons.music_note_rounded,
            value: totalTracks,
            label: context.l10n.musicStatsCardSongs,
            color: AppColors.primary,
            isDesktop: true,
          ),
          const SizedBox(height: 12),
          _buildStatItem(
            context: context,
            icon: Icons.person_rounded,
            value: totalArtists,
            label: context.l10n.musicStatsCardArtists,
            color: Colors.purple,
            isDesktop: true,
          ),
          const SizedBox(height: 12),
          _buildStatItem(
            context: context,
            icon: Icons.album_rounded,
            value: totalAlbums,
            label: context.l10n.musicStatsCardAlbums,
            color: AppColors.warning,
            isDesktop: true,
          ),
        ],
      ),
    );

  Widget _buildStatItem({
    required BuildContext context,
    required IconData icon,
    required int value,
    required String label,
    required Color color,
    bool isDesktop = false,
  }) {
    final formattedValue = _formatNumber(value);

    if (isDesktop) {
      return Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formattedValue,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 8),
        Text(
          formattedValue,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white60 : Colors.black45,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() => Container(
      width: 1,
      height: 50,
      color: isDark
          ? Colors.white.withValues(alpha: 0.1)
          : Colors.black.withValues(alpha: 0.08),
    );

  String _formatNumber(int number) {
    if (number >= 10000) {
      return '${(number / 10000).toStringAsFixed(1)}${appL10n.musicStatsCardNumberSuffixTenThousand}';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}${appL10n.musicStatsCardNumberSuffixThousand}';
    }
    return number.toString();
  }
}
