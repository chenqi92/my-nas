import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/providers/video_detail_provider.dart';
import 'package:my_nas/features/video/presentation/widgets/unified_episode_selector.dart';
import 'package:my_nas/l10n/app_localizations.dart';

void main() {
  testWidgets('a local episode absent from TMDB stays visible and playable', (
    tester,
  ) async {
    final local = VideoMetadata(
      sourceId: 'nas-a',
      filePath: '/show/S01E20.mkv',
      fileName: 'S01E20.mkv',
      seasonNumber: 1,
      episodeNumber: 20,
      episodeTitle: 'Local finale',
    );
    VideoMetadata? played;
    final season = TmdbSeasonDetail.fromJson({
      'id': 1,
      'season_number': 1,
      'episodes': [
        {
          'id': 19,
          'episode_number': 19,
          'season_number': 1,
          'name': 'Remote episode',
        },
      ],
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          seasonDetailProvider((
            tvId: 123,
            seasonNumber: 1,
          )).overrideWith((ref) async => season),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: UnifiedEpisodeSelector(
              tmdbId: 123,
              tmdbSeasons: [
                TmdbSeason.fromJson({
                  'id': 1,
                  'season_number': 1,
                  'episode_count': 19,
                }),
              ],
              localEpisodes: {
                1: {20: local},
              },
              onEpisodePlay: (file, {tmdbEpisode}) => played = file,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('20. Local finale'), findsOneWidget);
    await tester.tap(find.text('20. Local finale'));
    expect(played, same(local));
    expect(tester.takeException(), isNull);
  });
}
