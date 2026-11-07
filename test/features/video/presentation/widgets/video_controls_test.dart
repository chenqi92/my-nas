import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/video/presentation/providers/video_player_provider.dart';
import 'package:my_nas/features/video/presentation/widgets/video_controls.dart';

void main() {
  testWidgets('seek slider emits only once when dragging ends', (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoSeekSlider(
            progress: 0.25,
            duration: const Duration(seconds: 100),
            onSeek: seeks.add,
          ),
        ),
      ),
    );

    final slider = find.byType(Slider);
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();

    expect(seeks, isEmpty);

    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(seeks, isEmpty);

    await gesture.up();
    await tester.pump();

    expect(seeks, hasLength(1));
  });

  testWidgets('seek slider is disabled until duration is known', (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoSeekSlider(
            progress: 0,
            duration: Duration.zero,
            onSeek: seeks.add,
          ),
        ),
      ),
    );

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.onChanged, isNull);
    expect(seeks, isEmpty);
  });

  group('playerRelativeSeekTarget', () {
    test('no offset keeps absolute target', () {
      expect(
        playerRelativeSeekTarget(
          absoluteTarget: const Duration(seconds: 42),
          positionOffset: Duration.zero,
        ),
        const Duration(seconds: 42),
      );
    });

    test('subtracts transcode offset and clamps below zero', () {
      expect(
        playerRelativeSeekTarget(
          absoluteTarget: const Duration(seconds: 600),
          positionOffset: const Duration(seconds: 500),
        ),
        const Duration(seconds: 100),
      );
      expect(
        playerRelativeSeekTarget(
          absoluteTarget: const Duration(seconds: 200),
          positionOffset: const Duration(seconds: 500),
        ),
        Duration.zero,
      );
    });
  });

  group('VideoPlayerState progress timeline', () {
    test('progress / labels follow actualPosition and displayDuration', () {
      const state = VideoPlayerState(
        position: Duration(seconds: 100),
        duration: Duration(seconds: 500),
        positionOffset: Duration(seconds: 500),
        originalDuration: Duration(seconds: 1000),
      );
      expect(state.actualPosition, const Duration(seconds: 600));
      expect(state.displayDuration, const Duration(seconds: 1000));
      expect(state.progress, closeTo(0.6, 1e-9));
      expect(state.positionText, '10:00');
      expect(state.durationText, '16:40');
    });

    test('without originalDuration, displayDuration is stream length plus offset', () {
      const state = VideoPlayerState(
        position: Duration(seconds: 50),
        duration: Duration(seconds: 200),
        positionOffset: Duration(seconds: 300),
      );
      expect(state.displayDuration, const Duration(seconds: 500));
      expect(state.actualPosition, const Duration(seconds: 350));
      expect(state.progress, closeTo(0.7, 1e-9));
    });

    test('without offset, progress is plain position over duration', () {
      const state = VideoPlayerState(
        position: Duration(seconds: 25),
        duration: Duration(seconds: 100),
      );
      expect(state.actualPosition, const Duration(seconds: 25));
      expect(state.displayDuration, const Duration(seconds: 100));
      expect(state.progress, closeTo(0.25, 1e-9));
    });
  });

  testWidgets(
    'seek slider fraction maps through displayDuration then to player-relative',
    (tester) async {
      // 模拟控制栏：progress/displayDuration 同轴；松手后转成播放器相对位置。
      const offset = Duration(seconds: 500);
      const display = Duration(seconds: 1000);
      final playerSeeks = <Duration>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: VideoSeekSlider(
                progress: 0.6,
                duration: display,
                onSeek: (absolute) => playerSeeks.add(
                  playerRelativeSeekTarget(
                    absoluteTarget: absolute,
                    positionOffset: offset,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final slider = find.byType(Slider);
      final center = tester.getCenter(slider);
      final left = tester.getTopLeft(slider);
      final right = tester.getTopRight(slider);
      final gesture = await tester.startGesture(center);
      await gesture.moveTo(Offset(right.dx - 2, center.dy));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(playerSeeks, hasLength(1));
      // 接近片尾：绝对 ~1000s → 相对 ~500s（转码流时长）
      expect(playerSeeks.single.inSeconds, greaterThanOrEqualTo(450));
      expect(playerSeeks.single.inSeconds, lessThanOrEqualTo(500));

      // 再测片头附近：绝对 ~0 → 相对钳到 0（不能 seek 到偏移之前）
      playerSeeks.clear();
      final gesture2 = await tester.startGesture(center);
      await gesture2.moveTo(Offset(left.dx + 2, center.dy));
      await tester.pump();
      await gesture2.up();
      await tester.pump();
      expect(playerSeeks, hasLength(1));
      expect(playerSeeks.single, Duration.zero);
    },
  );
}
