import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';

/// 音轨信息
class AudioTrackInfo {
  const AudioTrackInfo({
    required this.index,
    required this.id,
    this.title,
    this.language,
    this.codec,
    this.channels,
  });

  final int index;
  final String id;
  final String? title;
  final String? language;
  final String? codec;
  final int? channels;

  /// 显示名称
  String get displayName {
    final parts = <String>[];
    if (title != null && title!.isNotEmpty) {
      parts.add(title!);
    }
    if (language != null && language!.isNotEmpty) {
      parts.add('[$language]');
    }
    if (codec != null) {
      parts.add('($codec)');
    }
    if (channels != null && channels! > 0) {
      parts.add('${channels}ch');
    }
    return parts.isEmpty ? 'Track ${index + 1}' : parts.join(' ');
  }

  @override
  String toString() => 'AudioTrackInfo(index: $index, id: $id, title: $title)';
}

/// 字幕轨道信息
class SubtitleTrackInfo {
  const SubtitleTrackInfo({
    required this.index,
    required this.id,
    this.title,
    this.language,
    this.codec,
    this.isForced = false,
    this.isDefault = false,
  });

  final int index;
  final String id;
  final String? title;
  final String? language;
  final String? codec;
  final bool isForced;
  final bool isDefault;

  /// 显示名称
  String get displayName {
    final parts = <String>[];
    if (title != null && title!.isNotEmpty) {
      parts.add(title!);
    }
    if (language != null && language!.isNotEmpty) {
      parts.add('[$language]');
    }
    if (isDefault) {
      parts.add(appL10n.videoTrackDefaultMark);
    }
    if (isForced) {
      parts.add(appL10n.videoTrackForcedMark);
    }
    return parts.isEmpty ? 'Subtitle ${index + 1}' : parts.join(' ');
  }

  @override
  String toString() =>
      'SubtitleTrackInfo(index: $index, id: $id, title: $title)';
}

/// 播放器后端类型
enum PlayerBackendType {
  /// media_kit (MPV/libmpv)
  mediaKit,

  /// 原生 AVPlayer (iOS/macOS)
  nativeAVPlayer,
}

/// 视频播放器后端抽象接口
///
/// 定义了播放器后端必须实现的功能，使得 media_kit 和原生 AVPlayer
/// 可以通过统一的接口被使用
abstract class VideoPlayerBackend {
  /// 后端类型
  PlayerBackendType get type;

  /// 是否已初始化
  bool get isInitialized;

  /// 是否已销毁
  bool get isDisposed;

  // ==================== 生命周期 ====================

  /// 打开视频
  ///
  /// [url] 视频 URL（支持 http/https/file 协议）
  /// [headers] HTTP 请求头（用于认证等）
  Future<void> open(String url, {Map<String, String>? headers});

  /// 关闭当前视频
  Future<void> close();

  /// 销毁播放器
  void dispose();

  // ==================== 播放控制 ====================

  /// 开始播放
  Future<void> play();

  /// 暂停播放
  Future<void> pause();

  /// 播放/暂停切换
  Future<void> playOrPause();

  /// 跳转到指定位置
  Future<void> seek(Duration position);

  /// 设置播放速度
  Future<void> setSpeed(double speed);

  /// 设置音量 (0.0 - 1.0)
  Future<void> setVolume(double volume);

  // ==================== 音轨管理 ====================

  /// 获取可用音轨列表
  Future<List<AudioTrackInfo>> getAudioTracks();

  /// 设置当前音轨
  Future<void> setAudioTrack(int index);

  /// 当前音轨索引
  int? get currentAudioTrackIndex;

  // ==================== 字幕管理 ====================

  /// 获取内嵌字幕轨道列表
  Future<List<SubtitleTrackInfo>> getSubtitleTracks();

  /// 设置内嵌字幕轨道
  Future<void> setSubtitleTrack(int index);

  /// 关闭字幕
  Future<void> disableSubtitle();

  /// 加载外部字幕
  Future<void> loadExternalSubtitle(String url, {String? title});

  /// 当前字幕轨道索引（-1 表示无字幕）
  int get currentSubtitleTrackIndex;

  // ==================== 画中画 ====================

  /// 是否支持画中画
  Future<bool> get isPipSupported;

  /// 进入画中画模式
  Future<bool> enterPictureInPicture();

  /// 退出画中画模式
  Future<bool> exitPictureInPicture();

  /// 当前是否在画中画模式
  bool get isPictureInPicture;

  // ==================== 截图 ====================

  /// 截取当前帧
  Future<List<int>?> screenshot();

  // ==================== 状态流 ====================

  /// 播放状态流
  Stream<bool> get playingStream;

  /// 缓冲状态流
  Stream<bool> get bufferingStream;

  /// 播放位置流
  Stream<Duration> get positionStream;

  /// 视频时长流
  Stream<Duration> get durationStream;

  /// 音量流 (0.0 - 1.0)
  Stream<double> get volumeStream;

  /// 播放速度流
  Stream<double> get speedStream;

  /// 错误流
  Stream<String?> get errorStream;

  /// 播放完成流
  Stream<bool> get completedStream;

  /// 音轨变化流
  Stream<List<AudioTrackInfo>> get audioTracksStream;

  /// 字幕轨道变化流
  Stream<List<SubtitleTrackInfo>> get subtitleTracksStream;

  // ==================== 当前状态 ====================

  /// 当前是否正在播放
  bool get isPlaying;

  /// 当前是否正在缓冲
  bool get isBuffering;

  /// 当前播放位置
  Duration get position;

  /// 视频总时长
  Duration get duration;

  /// 当前音量 (0.0 - 1.0)
  double get volume;

  /// 当前播放速度
  double get speed;

  /// 视频宽度
  int? get videoWidth;

  /// 视频高度
  int? get videoHeight;

  /// 视频宽高比
  double get aspectRatio {
    final w = videoWidth;
    final h = videoHeight;
    if (w != null && h != null && h > 0) {
      return w / h;
    }
    return 16 / 9;
  }

  // ==================== 视图 ====================

  /// 构建视频显示 Widget
  Widget buildVideoWidget({BoxFit fit = BoxFit.contain});
}
