import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/features/video/presentation/widgets/cast_card.dart';

/// 演员阵容区域组件
class CastSection extends StatelessWidget {
  const CastSection({
    required this.cast,
    this.title = '演员阵容',
    this.maxCount = 20,
    this.cardSize = 80,
    this.onCastTap,
    super.key,
  });

  final List<TmdbCast> cast;
  final String title;
  final int maxCount;
  final double cardSize;
  final void Function(TmdbCast cast)? onCastTap;

  @override
  Widget build(BuildContext context) {
    if (cast.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayCast = cast.take(maxCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 演员列表
        SizedBox(
          height: cardSize + 50, // 头像 + 文字高度
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: displayCast.length,
            itemBuilder: (context, index) => Padding(
                padding: EdgeInsets.only(
                  right: index < displayCast.length - 1 ? 16 : 0,
                ),
                child: CastCard(
                  cast: displayCast[index],
                  size: cardSize,
                  onTap: onCastTap != null
                      ? () => onCastTap!(displayCast[index])
                      : null,
                ),
              ),
          ),
        ),
      ],
    );
  }
}

/// 剧组人员区域组件 (导演、编剧等)
class CrewSection extends StatelessWidget {
  const CrewSection({
    required this.crew,
    this.title = '制作团队',
    this.jobs = const ['Director', 'Writer', 'Producer', 'Screenplay'],
    this.cardSize = 80,
    this.onCrewTap,
    super.key,
  });

  final List<TmdbCrew> crew;
  final String title;
  final List<String> jobs;
  final double cardSize;
  final void Function(TmdbCrew crew)? onCrewTap;

  @override
  Widget build(BuildContext context) {
    // 过滤出指定职位的人员
    final filteredCrew = crew.where((c) => jobs.contains(c.job)).toList();
    if (filteredCrew.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 剧组列表
        SizedBox(
          height: cardSize + 50,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filteredCrew.length,
            itemBuilder: (context, index) => Padding(
                padding: EdgeInsets.only(
                  right: index < filteredCrew.length - 1 ? 16 : 0,
                ),
                child: CrewCard(
                  crew: filteredCrew[index],
                  size: cardSize,
                  onTap: onCrewTap != null
                      ? () => onCrewTap!(filteredCrew[index])
                      : null,
                ),
              ),
          ),
        ),
      ],
    );
  }
}

/// 演职人员综合区域 (包含演员和主要剧组人员)
class CastAndCrewSection extends StatelessWidget {
  const CastAndCrewSection({
    required this.cast,
    required this.crew,
    this.maxCastCount = 10,
    this.cardSize = 80,
    super.key,
  });

  final List<TmdbCast> cast;
  final List<TmdbCrew> crew;
  final int maxCastCount;
  final double cardSize;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 获取导演
    final directors = crew.where((c) => c.job == 'Director').toList();

    // 合并列表：导演在前，演员在后
    final allPeople = <_CastOrCrew>[];

    for (final director in directors) {
      allPeople.add(_CastOrCrew.crew(director));
    }

    for (final actor in cast.take(maxCastCount)) {
      allPeople.add(_CastOrCrew.cast(actor));
    }

    if (allPeople.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            context.l10n.videoCastCrewLabel,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 人员列表
        SizedBox(
          height: cardSize + 50,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: allPeople.length,
            itemBuilder: (context, index) {
              final person = allPeople[index];
              return Padding(
                padding: EdgeInsets.only(
                  right: index < allPeople.length - 1 ? 16 : 0,
                ),
                child: person.isCast
                    ? CastCard(cast: person.cast!, size: cardSize)
                    : CrewCard(crew: person.crew!, size: cardSize),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 内部类：演员或剧组人员
class _CastOrCrew {
  _CastOrCrew.cast(this.cast) : crew = null;
  _CastOrCrew.crew(this.crew) : cast = null;

  final TmdbCast? cast;
  final TmdbCrew? crew;

  bool get isCast => cast != null;
}
