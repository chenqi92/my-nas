import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/domain/entities/video_quality.dart';

/// 播放质量监控服务
/// 监控视频播放的缓冲状态，检测卡顿并建议切换清晰度
class QualityMonitorService {
  QualityMonitorService({
    this.bufferThresholdSeconds = 3,
    this.checkIntervalMs = 500,
  });

  /// 缓冲阈值（秒），超过此时长触发建议
  final int bufferThresholdSeconds;

  /// 检查间隔（毫秒）
  final int checkIntervalMs;

  // ignore: unused_field
  Player? _player;
  Timer? _monitorTimer;
  StreamSubscription<bool>? _bufferingSubscription;

  /// 缓冲开始时间
  DateTime? _bufferingStartTime;

  /// 是否正在缓冲
  bool _isBuffering = false;

  /// 当前清晰度
  VideoQuality _currentQuality = VideoQuality.original;

  /// 可用清晰度列表
  List<VideoQuality> _availableQualities = [VideoQuality.original];

  /// 已经建议过的清晰度（避免重复建议）
  final Set<VideoQuality> _suggestedQualities = {};

  /// 用户拒绝切换的次数
  int _rejectionCount = 0;

  /// 用户选择"不再询问"
  bool _userOptedOut = false;

  /// 回调：建议切换清晰度
  void Function(VideoQuality current, VideoQuality suggested)? onQualitySuggestion;

  /// 回调：不支持清晰度切换
  void Function()? onQualityUnsupported;

  /// 初始化监控
  void init({
    required Player player,
    required List<VideoQuality> availableQualities,
    VideoQuality? currentQuality,
  }) {
    _player = player;
    _availableQualities = availableQualities;
    _currentQuality = currentQuality ?? VideoQuality.original;
    _suggestedQualities.clear();
    _rejectionCount = 0;

    // 监听缓冲状态
    _bufferingSubscription = player.stream.buffering.listen(_onBufferingChanged);
  }

  /// 设置当前清晰度
  void setCurrentQuality(VideoQuality quality) {
    _currentQuality = quality;
    // 切换清晰度后重置建议状态
    _suggestedQualities.clear();
    _rejectionCount = 0;
  }

  /// 设置可用清晰度列表
  void setAvailableQualities(List<VideoQuality> qualities) {
    _availableQualities = qualities;
  }

  /// 用户选择不再询问
  void optOut() {
    _userOptedOut = true;
    _stopMonitoring();
  }

  /// 用户拒绝切换
  void rejectSuggestion(VideoQuality suggested) {
    _suggestedQualities.add(suggested);
    _rejectionCount++;

    // 如果拒绝次数过多，自动停止建议
    if (_rejectionCount >= 3) {
      logger.i('用户多次拒绝切换清晰度，停止建议');
      _stopMonitoring();
    }
  }

  void _onBufferingChanged(bool isBuffering) {
    if (_userOptedOut) return;

    if (isBuffering && !_isBuffering) {
      // 开始缓冲
      _isBuffering = true;
      _bufferingStartTime = DateTime.now();
      _startMonitoring();
    } else if (!isBuffering && _isBuffering) {
      // 停止缓冲
      _isBuffering = false;
      _bufferingStartTime = null;
      _stopMonitoring();
    }
  }

  void _startMonitoring() {
    _stopMonitoring();
    _monitorTimer = Timer.periodic(
      Duration(milliseconds: checkIntervalMs),
      (_) => _checkBufferingDuration(),
    );
  }

  void _stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  void _checkBufferingDuration() {
    if (_bufferingStartTime == null) return;

    final duration = DateTime.now().difference(_bufferingStartTime!);

    if (duration.inSeconds >= bufferThresholdSeconds) {
      _handleLongBuffering();
    }
  }

  void _handleLongBuffering() {
    // 停止监控，避免重复触发
    _stopMonitoring();

    // 如果是原画，检查是否有可用的较低清晰度
    if (_currentQuality == VideoQuality.original) {
      // 检查是否有低于原画的清晰度可用
      final lowerQualities = _availableQualities
          .where((q) => !q.isOriginal && !_suggestedQualities.contains(q))
          .toList();

      if (lowerQualities.isEmpty) {
        // 没有可用的低清晰度
        onQualityUnsupported?.call();
        return;
      }

      // 建议切换到最高的可用低清晰度
      final suggested = lowerQualities.first;
      logger.i('检测到长时间缓冲，建议从 ${_currentQuality.label} 切换到 ${suggested.label}');
      onQualitySuggestion?.call(_currentQuality, suggested);
    } else {
      // 已经不是原画，找更低的清晰度
      final currentIndex = _availableQualities.indexOf(_currentQuality);
      if (currentIndex < 0) return;

      // 找到更低的清晰度
      final lowerQualities = _availableQualities
          .skip(currentIndex + 1)
          .where((q) => !_suggestedQualities.contains(q))
          .toList();

      if (lowerQualities.isEmpty) {
        // 已经是最低清晰度
        logger.i('已经是最低清晰度，无法继续降级');
        return;
      }

      final suggested = lowerQualities.first;
      logger.i('检测到长时间缓冲，建议从 ${_currentQuality.label} 切换到 ${suggested.label}');
      onQualitySuggestion?.call(_currentQuality, suggested);
    }
  }

  /// 释放资源
  void dispose() {
    _stopMonitoring();
    _bufferingSubscription?.cancel();
    _bufferingSubscription = null;
    _player = null;
  }
}

/// 播放质量统计
class PlaybackQualityStats {
  PlaybackQualityStats();

  /// 总播放时长（毫秒）
  int totalPlaybackMs = 0;

  /// 总缓冲时长（毫秒）
  int totalBufferingMs = 0;

  /// 缓冲次数
  int bufferingCount = 0;

  /// 清晰度切换次数
  int qualitySwitchCount = 0;

  /// 缓冲比例
  double get bufferingRatio =>
      totalPlaybackMs > 0 ? totalBufferingMs / totalPlaybackMs : 0;

  /// 平均每次缓冲时长（毫秒）
  int get averageBufferingMs =>
      bufferingCount > 0 ? totalBufferingMs ~/ bufferingCount : 0;

  /// 添加缓冲事件
  void addBufferingEvent(int durationMs) {
    bufferingCount++;
    totalBufferingMs += durationMs;
  }

  /// 添加播放时长
  void addPlaybackTime(int durationMs) {
    totalPlaybackMs += durationMs;
  }

  /// 添加清晰度切换
  void addQualitySwitch() {
    qualitySwitchCount++;
  }

  /// 重置统计
  void reset() {
    totalPlaybackMs = 0;
    totalBufferingMs = 0;
    bufferingCount = 0;
    qualitySwitchCount = 0;
  }
}
