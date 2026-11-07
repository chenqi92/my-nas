import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/widgets/music_player_controls.dart';
import 'package:my_nas/l10n/app_localizations.dart';

/// localhost fixture：校验播放控件在暂停/播放态下的图标与回调，
/// 以及 seek 滑条把进度映射为 Duration。≠真实 NAS / 无私有媒体。
void main() {
  Widget wrap(Widget child) => MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  MusicPlayerState playingState({
    bool isPlaying = false,
    Duration position = const Duration(seconds: 30),
    Duration duration = const Duration(seconds: 120),
    PlayMode playMode = PlayMode.loop,
    double volume = 1,
  }) => MusicPlayerState(
        isPlaying: isPlaying,
        position: position,
        duration: duration,
        playMode: playMode,
        volume: volume,
      );

  testWidgets('暂停态显示播放图标，点击触发 onPlayPause（恢复路径入口）', (
    tester,
  ) async {
    var playPauseTaps = 0;
    await tester.pumpWidget(
      wrap(
        MusicPlayerControls(
          state: playingState(isPlaying: false),
          onPlayPause: () => playPauseTaps++,
          onNext: () {},
          onPrevious: () {},
          onSeek: (_) {},
          onVolumeChange: (_) {},
          onTogglePlayMode: () {},
          onShowQueue: () {},
        ),
      ),
    );

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(playPauseTaps, 1);
  });

  testWidgets('播放态显示暂停图标，点击触发 onPlayPause（暂停路径）', (tester) async {
    var playPauseTaps = 0;
    await tester.pumpWidget(
      wrap(
        MusicPlayerControls(
          state: playingState(isPlaying: true),
          onPlayPause: () => playPauseTaps++,
          onNext: () {},
          onPrevious: () {},
          onSeek: (_) {},
          onVolumeChange: (_) {},
          onTogglePlayMode: () {},
          onShowQueue: () {},
        ),
      ),
    );

    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    expect(playPauseTaps, 1);
  });

  testWidgets('拖动进度条结束时发出一次 seek Duration', (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(
      wrap(
        MusicPlayerControls(
          state: playingState(
            isPlaying: true,
            position: const Duration(seconds: 30),
            duration: const Duration(seconds: 100),
          ),
          onPlayPause: () {},
          onNext: () {},
          onPrevious: () {},
          onSeek: seeks.add,
          onVolumeChange: (_) {},
          onTogglePlayMode: () {},
          onShowQueue: () {},
        ),
      ),
    );

    final slider = find.byType(Slider).first;
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(seeks, isNotEmpty);
    expect(seeks.last.inMilliseconds, greaterThan(0));
    expect(seeks.last.inMilliseconds, lessThanOrEqualTo(100000));
  });

  testWidgets('播放模式图标随 PlayMode 切换', (tester) async {
    await tester.pumpWidget(
      wrap(
        MusicPlayerControls(
          state: playingState(playMode: PlayMode.loop),
          onPlayPause: () {},
          onNext: () {},
          onPrevious: () {},
          onSeek: (_) {},
          onVolumeChange: (_) {},
          onTogglePlayMode: () {},
          onShowQueue: () {},
        ),
      ),
    );
    expect(find.byIcon(Icons.repeat), findsOneWidget);

    await tester.pumpWidget(
      wrap(
        MusicPlayerControls(
          state: playingState(playMode: PlayMode.repeatOne),
          onPlayPause: () {},
          onNext: () {},
          onPrevious: () {},
          onSeek: (_) {},
          onVolumeChange: (_) {},
          onTogglePlayMode: () {},
          onShowQueue: () {},
        ),
      ),
    );
    expect(find.byIcon(Icons.repeat_one), findsOneWidget);

    await tester.pumpWidget(
      wrap(
        MusicPlayerControls(
          state: playingState(playMode: PlayMode.shuffle),
          onPlayPause: () {},
          onNext: () {},
          onPrevious: () {},
          onSeek: (_) {},
          onVolumeChange: (_) {},
          onTogglePlayMode: () {},
          onShowQueue: () {},
        ),
      ),
    );
    expect(find.byIcon(Icons.shuffle), findsOneWidget);
  });

  test('MusicPlayerState.progress / positionText 纯逻辑', () {
    const state = MusicPlayerState(
      position: Duration(minutes: 1, seconds: 5),
      duration: Duration(minutes: 4),
    );
    expect(state.progress, closeTo(65 / 240, 0.0001));
    expect(state.positionText, '01:05');
    expect(state.durationText, '04:00');

    const zero = MusicPlayerState();
    expect(zero.progress, 0);
    expect(zero.bufferedProgress, 0);
  });
}
