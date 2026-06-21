import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';

/// 媒体信息标签组件
///
/// 显示视频的各种技术规格标签：
/// - 分辨率：4K、1080p、720p
/// - HDR：Dolby Vision、HDR10+、HDR10
/// - 音频：Atmos、DTS:X、DTS-HD MA、TrueHD
/// - 来源：BluRay、WEB-DL、Remux
/// - 编码：HEVC、H.265、AVC
/// - 3D 标识
/// - 内容分级：PG、R、NC-17 等
class MediaInfoBadges extends StatelessWidget {
  const MediaInfoBadges({
    required this.metadata,
    this.showResolution = true,
    this.showHdr = true,
    this.showAudio = true,
    this.showSource = true,
    this.showCodec = false,
    this.show3D = true,
    this.showCertification = true,
    this.spacing = 6.0,
    this.runSpacing = 4.0,
    this.compact = false,
    super.key,
  });

  final VideoMetadata metadata;
  final bool showResolution;
  final bool showHdr;
  final bool showAudio;
  final bool showSource;
  final bool showCodec;
  final bool show3D;
  final bool showCertification;
  final double spacing;
  final double runSpacing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[];

    // 内容分级标签（优先显示，因为这是最重要的信息之一）
    if (showCertification && metadata.certification != null) {
      badges.add(_buildCertificationBadge(metadata.certification!));
    }

    // 分辨率标签
    if (showResolution && metadata.resolution != null) {
      badges.add(_buildResolutionBadge(metadata.resolution!));
    }

    // HDR 标签
    if (showHdr && metadata.hdrFormat != null) {
      badges.add(_buildHdrBadge(metadata.hdrFormat!));
    }

    // 3D 标签
    if (show3D && metadata.is3D) {
      badges.add(_build3DBadge());
    }

    // 音频格式标签
    if (showAudio && metadata.audioFormat != null) {
      badges.add(_buildAudioBadge(metadata.audioFormat!));
    }

    // 来源标签
    if (showSource) {
      if (metadata.isRemux) {
        badges.add(_buildSourceBadge('Remux'));
      } else if (metadata.videoSource != null) {
        badges.add(_buildSourceBadge(metadata.videoSource!));
      }
    }

    // 编码标签（通常不显示，除非明确需要）
    if (showCodec && metadata.videoCodec != null) {
      badges.add(_buildCodecBadge(metadata.videoCodec!));
    }

    if (badges.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      children: badges,
    );
  }

  /// 构建内容分级标签（带边框）
  Widget _buildCertificationBadge(String certification) {
    // 根据分级确定颜色
    Color borderColor;
    Color textColor;

    final upper = certification.toUpperCase();
    if (upper == 'G' || upper == 'TV-G') {
      borderColor = AppColors.success;
      textColor = AppColors.success;
    } else if (upper == 'PG' || upper == 'TV-PG') {
      borderColor = AppColors.info;
      textColor = AppColors.info;
    } else if (upper == 'PG-13' || upper == 'TV-14') {
      borderColor = AppColors.warning;
      textColor = AppColors.warning;
    } else if (upper == 'R' || upper == 'TV-MA') {
      borderColor = AppColors.error;
      textColor = AppColors.error;
    } else if (upper == 'NC-17') {
      borderColor = AppColors.error;
      textColor = AppColors.error;
    } else {
      borderColor = AppColors.disabled;
      textColor = AppColors.disabled;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        certification,
        style: TextStyle(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.bold,
          color: textColor,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// 构建分辨率标签
  Widget _buildResolutionBadge(String resolution) {
    final upper = resolution.toUpperCase();
    final is4K = upper == '4K' || upper == '2160P';
    final isHD = upper == '1080P';

    return _buildBadge(
      text: is4K ? '4K' : resolution.replaceAll('p', 'P'),
      backgroundColor: is4K
          ? const Color(0xFFE50914) // Netflix 红
          : isHD
              ? AppColors.primary
              : Colors.grey.shade700,
      textColor: Colors.white,
      icon: is4K ? Icons.hd_rounded : null,
    );
  }

  /// 构建 HDR 标签
  Widget _buildHdrBadge(String hdrFormat) {
    final isDolbyVision =
        hdrFormat.toUpperCase().contains('DOLBY') || hdrFormat == 'DV';

    return _buildBadge(
      text: isDolbyVision ? 'Dolby Vision' : hdrFormat,
      backgroundColor: isDolbyVision
          ? const Color(0xFF000000) // Dolby Vision 黑色背景
          : const Color(0xFFFFD700), // HDR10 金色
      textColor: isDolbyVision ? Colors.white : Colors.black,
      gradientColors: isDolbyVision
          ? [
              const Color(0xFF1E1E1E),
              const Color(0xFF000000),
            ]
          : null,
    );
  }

  /// 构建 3D 标签
  Widget _build3DBadge() => _buildBadge(
        text: '3D',
        backgroundColor: const Color(0xFF00BCD4),
        textColor: Colors.white,
      );

  /// 构建音频格式标签
  Widget _buildAudioBadge(String audioFormat) {
    final upper = audioFormat.toUpperCase();
    final isAtmos = upper.contains('ATMOS');
    final isDtsX = upper.contains('DTS') && upper.contains('X');
    final isDolby = upper.contains('TRUEHD') || upper.contains('DD');

    Color bgColor;
    if (isAtmos) {
      bgColor = const Color(0xFF000000); // Dolby Atmos 黑色
    } else if (isDtsX) {
      bgColor = const Color(0xFFE63946); // DTS:X 红色
    } else if (isDolby) {
      bgColor = const Color(0xFF1A1A1A);
    } else {
      bgColor = Colors.grey.shade800;
    }

    return _buildBadge(
      text: audioFormat,
      backgroundColor: bgColor,
      textColor: Colors.white,
    );
  }

  /// 构建来源标签
  Widget _buildSourceBadge(String source) {
    final upper = source.toUpperCase();
    final isBluRay = upper.contains('BLU') || upper.contains('BD');
    final isRemux = upper.contains('REMUX');
    final isWeb = upper.contains('WEB');

    Color bgColor;
    if (isRemux) {
      bgColor = const Color(0xFF4A148C); // 紫色
    } else if (isBluRay) {
      bgColor = const Color(0xFF0D47A1); // 蓝光蓝
    } else if (isWeb) {
      bgColor = const Color(0xFF2E7D32); // WEB 绿
    } else {
      bgColor = Colors.grey.shade700;
    }

    String displayText;
    if (isRemux) {
      displayText = 'Remux';
    } else if (isBluRay) {
      displayText = 'BluRay';
    } else if (isWeb) {
      displayText = upper.contains('DL') ? 'WEB-DL' : 'WEB';
    } else {
      displayText = source;
    }

    return _buildBadge(
      text: displayText,
      backgroundColor: bgColor,
      textColor: Colors.white,
    );
  }

  /// 构建编码标签
  Widget _buildCodecBadge(String codec) {
    final upper = codec.toUpperCase();
    final isHevc = upper.contains('HEVC') ||
        upper.contains('265') ||
        upper.contains('X265');

    return _buildBadge(
      text: isHevc ? 'HEVC' : codec,
      backgroundColor: isHevc ? Colors.teal : Colors.grey.shade700,
      textColor: Colors.white,
    );
  }

  /// 通用标签构建器
  Widget _buildBadge({
    required String text,
    required Color backgroundColor,
    required Color textColor,
    IconData? icon,
    List<Color>? gradientColors,
  }) =>
      Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 2 : 4,
        ),
        decoration: BoxDecoration(
          gradient: gradientColors != null
              ? LinearGradient(colors: gradientColors)
              : null,
          color: gradientColors == null ? backgroundColor : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: compact ? 12 : 14, color: textColor),
              SizedBox(width: compact ? 2 : 4),
            ],
            Text(
              text,
              style: TextStyle(
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.bold,
                color: textColor,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      );
}

/// 评分标签组件（紧凑横向风格）
///
/// 横向紧凑排列，图标+评分数字
/// 支持：TMDB、IMDb、Trakt、豆瓣、Metacritic
class RatingBadges extends StatelessWidget {
  const RatingBadges({
    this.tmdbRating,
    this.imdbRating,
    this.metacriticRating,
    this.traktRating,
    this.doubanRating,
    this.voteCount,
    this.spacing = 12.0,
    this.runSpacing = 8.0,
    this.showAll = false,
    super.key,
  });

  final double? tmdbRating;
  final double? imdbRating;
  final int? metacriticRating;
  final double? traktRating;
  final double? doubanRating;
  final int? voteCount;
  final double spacing;
  final double runSpacing;
  final bool showAll;

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[];

    // TMDB 评分
    if (tmdbRating != null && tmdbRating! > 0) {
      badges.add(_buildTmdbBadge(tmdbRating!));
    }

    // Metacritic 评分（百分制）
    if (metacriticRating != null && metacriticRating! > 0) {
      badges.add(_buildMetacriticBadge(metacriticRating!));
    }

    // Trakt 评分
    if (traktRating != null && traktRating! > 0) {
      badges.add(_buildTraktBadge(traktRating!));
    }

    // 豆瓣评分
    if (doubanRating != null && doubanRating! > 0) {
      badges.add(_buildDoubanBadge(context, doubanRating!));
    }

    // IMDb 评分
    if (imdbRating != null && imdbRating! > 0) {
      badges.add(_buildImdbBadge(imdbRating!));
    }

    if (badges.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: badges,
    );
  }

  /// TMDB 评分徽章
  Widget _buildTmdbBadge(double rating) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // TMDB 图标
          Container(
            width: 28,
            height: 20,
            decoration: BoxDecoration(
              color: const Color(0xFF0D253F),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: const Text(
              'TMDB',
              style: TextStyle(
                fontSize: 7,
                fontWeight: FontWeight.bold,
                color: Color(0xFF01D277),
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      );

  /// Metacritic 评分徽章（方形）
  Widget _buildMetacriticBadge(int score) {
    Color bgColor;
    if (score >= 75) {
      bgColor = const Color(0xFF66CC33);
    } else if (score >= 50) {
      bgColor = const Color(0xFFFFCC33);
    } else {
      bgColor = const Color(0xFFFF0000);
    }

    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: Text(
        score.toString(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  /// Trakt 评分徽章
  Widget _buildTraktBadge(double rating) {
    // Trakt 评分可能是百分制或 10 分制
    final displayRating = rating > 10 ? '${rating.toInt()}%' : rating.toStringAsFixed(1);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Trakt 图标（使用勾选样式）
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: const Color(0xFFED1C24),
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.check_rounded,
            size: 14,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          displayRating,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  /// 豆瓣评分徽章
  Widget _buildDoubanBadge(BuildContext context, double rating) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 豆瓣图标
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: const Color(0xFF2BC16B),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Text(
              context.l10n.videoRatingBadgesDoubanLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      );

  /// IMDb 评分徽章
  Widget _buildImdbBadge(double rating) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // IMDb 图标
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF5C518),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'IMDb',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Colors.black,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      );
}
