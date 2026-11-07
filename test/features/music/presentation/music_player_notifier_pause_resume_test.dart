import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:my_nas/features/music/data/services/music_audio_handler_interface.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/main.dart' show audioHandler;

class FakeMusicAudioHandler extends BaseAudioHandler
    implements IMusicAudioHandler {
  final _pos = StreamController<Duration>.broadcast();
  final _bufPos = StreamController<Duration>.broadcast();
  final _dur = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();

  int pauseCalls = 0;
  int playCalls = 0;
  double _volume = 1.0;
  MusicItem? _music;
  int _index = 0;
  Future<void> Function(int index)? _onSkip;

  @override
  Uint8List? get currentArtworkData => null;
  @override
  MusicItem? get currentMusicItem => _music;
  @override
  int get currentIndex => _index;
  @override
  set onSkipToIndex(Future<void> Function(int index)? callback) =>
      _onSkip = callback;
  @override
  Future<void> Function(int index)? get onSkipToIndex => _onSkip;
  @override
  Future<Duration?> setAudioSource(String url,
          {Map<String, String>? headers}) async =>
      const Duration(seconds: 10);
  @override
  Future<void> stopPlayer() async {}
  @override
  Future<void> seekTo(Duration position) async {}
  @override
  Future<void> setCurrentMusic(MusicItem music,
      {Uint8List? artworkData}) async {
    _music = music;
  }
  @override
  Future<void> updateArtwork(Uint8List artworkData) async {}
  @override
  void updateDuration(Duration duration) {}
  @override
  void setQueue(List<MusicItem> items, {int startIndex = 0}) {
    _index = startIndex;
  }
  @override
  void updateCurrentIndex(int index) => _index = index;
  @override
  Future<void> setVolume(double volume) async => _volume = volume;
  @override
  double get volume => _volume;
  @override
  Future<void> prepareForNewTrack() async {}
  @override
  Future<void> refreshNowPlaying() async {}
  @override
  Stream<Duration> get positionStream => _pos.stream;
  @override
  Stream<Duration> get bufferedPositionStream => _bufPos.stream;
  @override
  Stream<Duration> get durationStream => _dur.stream;
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<bool> get bufferingStream => _buffering.stream;
  @override
  Stream<bool> get completedStream => _completed.stream;
  @override
  Future<void> pause() async {
    pauseCalls++;
    _playing.add(false);
  }
  @override
  Future<void> play() async {
    playCalls++;
    _playing.add(true);
  }
  @override
  Future<void> stop() async {
    _playing.add(false);
  }
  @override
  Future<void> dispose() async {
    await _pos.close();
    await _bufPos.close();
    await _dur.close();
    await _playing.close();
    await _buffering.close();
    await _completed.close();
  }
}

/// localhost fixture：用 Fake IMusicAudioHandler 覆盖 MusicPlayerNotifier.pause/resume。
/// 不改产品代码：替换全局 late audioHandler；Hive.init 仅测试侧。
/// ≠真实 NAS / ≠真实音频引擎。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('qa-r4-hive-');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
    }
  });

  test('MusicPlayerNotifier.pause/resume 委托 Fake handler 并同步 isPlaying', () async {
    final fake = FakeMusicAudioHandler();
    audioHandler = fake;

    final container = ProviderContainer();
    addTearDown(() async {
      container.dispose();
      await fake.dispose();
    });

    final notifier = container.read(musicPlayerControllerProvider.notifier);
    // 等待 _applySettings / MediaProxy 异步副作用
    await Future<void>.delayed(const Duration(milliseconds: 200));

    await notifier.pause();
    expect(fake.pauseCalls, greaterThanOrEqualTo(1));

    await notifier.resume();
    expect(fake.playCalls, greaterThanOrEqualTo(1));

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(musicPlayerControllerProvider).isPlaying, isTrue);

    await notifier.pause();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(musicPlayerControllerProvider).isPlaying, isFalse);

    final pausesBeforeToggle = fake.pauseCalls;
    final playsBeforeToggle = fake.playCalls;
    // playOrPause：当前未播放 → resume/play
    await notifier.playOrPause();
    expect(fake.playCalls, greaterThan(playsBeforeToggle));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(musicPlayerControllerProvider).isPlaying, isTrue);
    await notifier.playOrPause();
    expect(fake.pauseCalls, greaterThan(pausesBeforeToggle));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(musicPlayerControllerProvider).isPlaying, isFalse);
  });
}
