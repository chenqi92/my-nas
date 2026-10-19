import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/utils/logger.dart';

enum PlaybackOrientation {
  auto,
  video,
  portrait,
  reversePortrait,
  landscape,
  reverseLandscape;

  List<DeviceOrientation> orientations({double? aspectRatio}) => switch (this) {
    PlaybackOrientation.auto => [],
    PlaybackOrientation.video =>
      aspectRatio == null || aspectRatio <= 0
          ? []
          : aspectRatio < 1
          ? [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
          : [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
    PlaybackOrientation.portrait => [DeviceOrientation.portraitUp],
    PlaybackOrientation.reversePortrait => [DeviceOrientation.portraitDown],
    PlaybackOrientation.landscape => [DeviceOrientation.landscapeLeft],
    PlaybackOrientation.reverseLandscape => [DeviceOrientation.landscapeRight],
  };
}

/// 播放设置
class PlaybackSettings {
  const PlaybackSettings({
    this.volume = 1.0,
    this.speed = 1.0,
    this.autoPlayNext = true,
    this.rememberPosition = true,
    this.seekInterval = 10,
    this.orientation = PlaybackOrientation.auto,
    this.hideSystemBars = false,
  });

  factory PlaybackSettings.fromMap(Map<dynamic, dynamic> map) =>
      PlaybackSettings(
        volume: (map['volume'] as num?)?.toDouble() ?? 1.0,
        speed: (map['speed'] as num?)?.toDouble() ?? 1.0,
        autoPlayNext: map['autoPlayNext'] as bool? ?? true,
        rememberPosition: map['rememberPosition'] as bool? ?? true,
        seekInterval: map['seekInterval'] as int? ?? 10,
        orientation:
            PlaybackOrientation.values
                .where((value) => value.name == map['orientation'])
                .firstOrNull ??
            PlaybackOrientation.auto,
        hideSystemBars: map['hideSystemBars'] as bool? ?? false,
      );

  final PlaybackOrientation orientation;
  final bool hideSystemBars;
  final double volume;
  final double speed;
  final bool autoPlayNext;
  final bool rememberPosition;
  final int seekInterval; // 快进快退秒数

  PlaybackSettings copyWith({
    double? volume,
    double? speed,
    bool? autoPlayNext,
    bool? rememberPosition,
    int? seekInterval,
    PlaybackOrientation? orientation,
    bool? hideSystemBars,
  }) => PlaybackSettings(
    volume: volume ?? this.volume,
    speed: speed ?? this.speed,
    autoPlayNext: autoPlayNext ?? this.autoPlayNext,
    rememberPosition: rememberPosition ?? this.rememberPosition,
    seekInterval: seekInterval ?? this.seekInterval,
    orientation: orientation ?? this.orientation,
    hideSystemBars: hideSystemBars ?? this.hideSystemBars,
  );

  Map<String, dynamic> toMap() => {
    'volume': volume,
    'speed': speed,
    'autoPlayNext': autoPlayNext,
    'rememberPosition': rememberPosition,
    'seekInterval': seekInterval,
    'orientation': orientation.name,
    'hideSystemBars': hideSystemBars,
  };
}

/// 视频播放位置记录
class VideoPosition {
  const VideoPosition({
    required this.videoPath,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });

  factory VideoPosition.fromMap(Map<dynamic, dynamic> map) => VideoPosition(
        videoPath: map['videoPath'] as String,
        position: Duration(milliseconds: map['position'] as int),
        duration: Duration(milliseconds: map['duration'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int),
      );

  final String videoPath;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;

  double get progress =>
      duration.inMilliseconds > 0 ? position.inMilliseconds / duration.inMilliseconds : 0;

  Map<String, dynamic> toMap() => {
        'videoPath': videoPath,
        'position': position.inMilliseconds,
        'duration': duration.inMilliseconds,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };
}

/// 播放设置管理
class PlaybackSettingsNotifier extends StateNotifier<PlaybackSettings> {
  PlaybackSettingsNotifier() : super(const PlaybackSettings()) {
    _load();
  }

  static const _boxName = 'playback_settings';
  static const _settingsKey = 'settings';
  static const _positionsBoxName = 'video_positions';

  Box<Map<dynamic, dynamic>>? _box;
  Box<Map<dynamic, dynamic>>? _positionsBox;
  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;

    try {
      _box = await Hive.openBox<Map<dynamic, dynamic>>(_boxName);
      _positionsBox = await Hive.openBox<Map<dynamic, dynamic>>(_positionsBoxName);
      _initialized = true;
    } on Exception catch (e) {
      logger.e('PlaybackSettingsNotifier: 初始化失败', e);
    }
  }

  Future<void> _load() async {
    await _init();
    if (_box == null) return;

    final data = _box!.get(_settingsKey);
    if (data != null) {
      state = PlaybackSettings.fromMap(data);
      logger.i('PlaybackSettingsNotifier: 加载设置成功');
    }
  }

  Future<void> _save() async {
    await _init();
    if (_box == null) return;

    await _box!.put(_settingsKey, state.toMap());
  }

  /// 设置音量
  Future<void> setVolume(double volume) async {
    state = state.copyWith(volume: volume.clamp(0.0, 1.0));
    await _save();
  }

  /// 设置播放速度
  Future<void> setSpeed(double speed) async {
    state = state.copyWith(speed: speed);
    await _save();
  }

  /// 设置是否自动播放下一个
  Future<void> setAutoPlayNext({required bool enabled}) async {
    state = state.copyWith(autoPlayNext: enabled);
    await _save();
  }

  /// 设置是否记住播放位置
  Future<void> setRememberPosition({required bool enabled}) async {
    state = state.copyWith(rememberPosition: enabled);
    await _save();
  }

  /// 设置快进快退秒数
  Future<void> setSeekInterval(int seconds) async {
    state = state.copyWith(seekInterval: seconds.clamp(5, 30));
    await _save();
  }

  Future<void> setOrientation(PlaybackOrientation orientation) async {
    state = state.copyWith(orientation: orientation);
    await _save();
  }

  Future<void> setHideSystemBars({required bool hidden}) async {
    state = state.copyWith(hideSystemBars: hidden);
    await _save();
  }

  /// 保存视频播放位置
  Future<void> saveVideoPosition({
    required String videoPath,
    required Duration position,
    required Duration duration,
  }) async {
    if (!state.rememberPosition) return;

    await _init();
    if (_positionsBox == null) return;

    final record = VideoPosition(
      videoPath: videoPath,
      position: position,
      duration: duration,
      updatedAt: DateTime.now(),
    );

    await _positionsBox!.put(videoPath, record.toMap());
    logger.d('PlaybackSettingsNotifier: 保存播放位置 $videoPath @ ${position.inSeconds}s');
  }

  /// 获取视频播放位置
  Future<Duration?> getVideoPosition(String videoPath) async {
    if (!state.rememberPosition) return null;

    await _init();
    if (_positionsBox == null) return null;

    final data = _positionsBox!.get(videoPath);
    if (data == null) return null;

    try {
      final record = VideoPosition.fromMap(data);
      // 如果进度超过 95%，从头开始
      if (record.progress > 0.95) return null;
      return record.position;
    } on Exception catch (_) {
      return null;
    }
  }

  /// 获取所有播放位置记录
  Future<List<VideoPosition>> getAllPositions() async {
    await _init();
    if (_positionsBox == null) return [];

    final positions = <VideoPosition>[];
    for (final key in _positionsBox!.keys) {
      final data = _positionsBox!.get(key);
      if (data != null) {
        try {
          positions.add(VideoPosition.fromMap(data));
        } on Exception catch (_) {
          // 跳过无效数据
        }
      }
    }

    positions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return positions;
  }

  /// 清除视频播放位置
  Future<void> clearVideoPosition(String videoPath) async {
    await _init();
    if (_positionsBox == null) return;

    await _positionsBox!.delete(videoPath);
  }

  /// 清除所有播放位置
  Future<void> clearAllPositions() async {
    await _init();
    if (_positionsBox == null) return;

    await _positionsBox!.clear();
  }
}

/// 播放设置 provider
final playbackSettingsProvider =
    StateNotifierProvider<PlaybackSettingsNotifier, PlaybackSettings>((ref) => PlaybackSettingsNotifier());

/// 可用的播放速度列表
const availableSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

/// 可用的快进快退秒数（仅包含有原生图标的数值）
const availableSeekIntervals = [5, 10, 30];
