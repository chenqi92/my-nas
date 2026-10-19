import 'package:my_nas/features/video/domain/entities/video_metadata.dart';

/// Keep all files for an episode; the browsing grid can choose a representative.
Map<int, Map<int, List<VideoMetadata>>> groupEpisodeVersions(
  Iterable<VideoMetadata> videos,
) {
  final result = <int, Map<int, List<VideoMetadata>>>{};
  final unnumbered = <VideoMetadata>[];
  for (final video in videos) {
    final parsed = VideoFileNameParser.parse(video.fileName);
    final season = video.seasonNumber ?? parsed.season;
    final episode = video.episodeNumber ?? parsed.episode;
    if (season == null || episode == null) {
      unnumbered.add(video);
      continue;
    }
    result
        .putIfAbsent(season, () => {})
        .putIfAbsent(episode, () => [])
        .add(video.copyWith(seasonNumber: season, episodeNumber: episode));
  }
  unnumbered.sort((a, b) => a.fileName.compareTo(b.fileName));
  if (unnumbered.isNotEmpty) {
    final season = result.putIfAbsent(1, () => {});
    var next = season.keys.fold(0, (a, b) => a > b ? a : b) + 1;
    for (final video in unnumbered) {
      season[next] = [video.copyWith(seasonNumber: 1, episodeNumber: next)];
      next++;
    }
  }
  return result;
}

Map<int, Map<int, VideoMetadata>> episodeRepresentatives(
  Iterable<VideoMetadata> videos, {
  String? preferredSourceId,
}) => groupEpisodeVersions(videos).map(
  (season, episodes) => MapEntry(
    season,
    episodes.map(
      (number, versions) => MapEntry(
        number,
        versions.where((v) => v.sourceId == preferredSourceId).firstOrNull ??
            versions.first,
      ),
    ),
  ),
);

List<int> mergedEpisodeNumbers(Iterable<int> remote, Iterable<int> local) =>
    {...remote, ...local}.toList()..sort();
