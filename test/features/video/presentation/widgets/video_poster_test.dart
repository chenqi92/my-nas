import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:my_nas/features/video/presentation/widgets/video_poster.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/adaptive_image.dart';
import 'package:my_nas/shared/widgets/stream_image.dart';

class _MockNasFileSystem extends Mock implements NasFileSystem {}

void main() {
  testWidgets('loads NAS poster paths through StreamImage', (tester) async {
    const path = '/movies/example/poster.jpg';
    final fileSystem = _MockNasFileSystem();
    when(() => fileSystem.getThumbnailData(path)).thenAnswer(
      (_) async => base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
        '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPoster(
          posterUrl: path,
          sourceId: 'nas-1',
          fileSystem: fileSystem,
        ),
      ),
    );

    expect(find.byType(StreamImage), findsOneWidget);
  });

  testWidgets('loads file URLs through AdaptiveImage', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VideoPoster(posterUrl: 'file:///C:/missing/poster.jpg'),
      ),
    );

    expect(find.byType(AdaptiveImage), findsOneWidget);
  });

  testWidgets('keeps network posters on the cached image path', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VideoPoster(posterUrl: 'https://image.example/poster.jpg'),
      ),
    );

    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });

  testWidgets('falls back to the network poster when a NAS poster is missing', (
    tester,
  ) async {
    final fileSystem = _MockNasFileSystem();
    when(
      () => fileSystem.getThumbnailData('/missing/poster.jpg'),
    ).thenAnswer((_) async => null);
    when(
      () => fileSystem.getFileStream('/missing/poster.jpg'),
    ).thenThrow(Exception('File not found'));

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPoster(
          posterUrl: '/missing/poster.jpg',
          fallbackUrls: const ['https://image.example/fallback.jpg'],
          sourceId: 'nas-missing',
          fileSystem: fileSystem,
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.imageUrl, 'https://image.example/fallback.jpg');
  });

  testWidgets('NAS poster cache keys include the source', (tester) async {
    final fileSystem = _MockNasFileSystem();
    when(() => fileSystem.getThumbnailData(any())).thenAnswer(
      (_) async => base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
        '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            for (final source in ['nas-a', 'nas-b'])
              VideoPoster(
                posterUrl: '/poster.jpg',
                sourceId: source,
                fileSystem: fileSystem,
              ),
          ],
        ),
      ),
    );
    expect(
      tester
          .widgetList<StreamImage>(find.byType(StreamImage))
          .map((image) => image.cacheKey),
      unorderedEquals(['nas-a:/poster.jpg', 'nas-b:/poster.jpg']),
    );
  });
}
