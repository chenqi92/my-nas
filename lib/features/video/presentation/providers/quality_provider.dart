import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:media_kit/media_kit.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/video/data/services/quality/quality_monitor_service.dart';
import 'package:my_nas/features/video/data/services/transcoding/client_transcoding_service.dart';
import 'package:my_nas/features/video/data/services/transcoding/nas_transcoding_service.dart';
import 'package:my_nas/features/video/data/services/transcoding/transcoding_capability.dart';
import 'package:my_nas/features/video/domain/entities/video_quality.dart';

/// 清晰度设置 Provider
final qualitySettingsProvider =
    StateNotifierProvider<QualitySettingsNotifier, QualitySettings>(
  (ref) => QualitySettingsNotifier(),
);

/// 清晰度状态 Provider
/// 注意：不使用 autoDispose，因为视频控制栏会隐藏/显示，
/// 隐藏时如果使用 autoDispose 会导致 provider 被销毁，丢失初始化的画质状态
final qualityStateProvider = StateNotifierProvider<QualityNotifier, QualityState>(
  QualityNotifier.new,
);

/// 清晰度设置
class QualitySettings {
  const QualitySettings({
    this.defaultQuality = VideoQuality.original,
    this.enableAdaptiveSuggestion = true,
    this.bufferThresholdSeconds = 3,
    this.rememberPerVideo = true,
    this.showUnsupportedHint = true,
    this.allowServerTranscoding = true,
    this.allowClientTranscoding = true,
  });

  factory QualitySettings.fromMap(Map<dynamic, dynamic> map) => QualitySettings(
        defaultQuality: VideoQuality.values.firstWhere(
          (q) => q.name == (map['defaultQuality'] as String?),
          orElse: () => VideoQuality.original,
        ),
        enableAdaptiveSuggestion: map['enableAdaptiveSuggestion'] as bool? ?? true,
        bufferThresholdSeconds: map['bufferThresholdSeconds'] as int? ?? 3,
        rememberPerVideo: map['rememberPerVideo'] as bool? ?? true,
        showUnsupportedHint: map['showUnsupportedHint'] as bool? ?? true,
        allowServerTranscoding: map['allowServerTranscoding'] as bool? ?? true,
        allowClientTranscoding: map['allowClientTranscoding'] as bool? ?? true,
      );

  /// 默认清晰度
  final VideoQuality defaultQuality;

  /// 是否启用自适应建议
  final bool enableAdaptiveSuggestion;

  /// 缓冲阈值（秒）
  final int bufferThresholdSeconds;

  /// 记住每个视频的清晰度选择
  final bool rememberPerVideo;

  /// 不支持转码时显示提示
  final bool showUnsupportedHint;

  /// 是否允许服务端转码（Synology / Jellyfin 等）。
  /// 关闭后服务端能力的源被降级为「仅原画」，播放时不再向服务端请求转码流。
  final bool allowServerTranscoding;

  /// 是否允许客户端（本地 FFmpeg）转码。
  /// 关闭后客户端能力的源被降级为「仅原画」，不再初始化本地转码。
  final bool allowClientTranscoding;

  QualitySettings copyWith({
    VideoQuality? defaultQuality,
    bool? enableAdaptiveSuggestion,
    int? bufferThresholdSeconds,
    bool? rememberPerVideo,
    bool? showUnsupportedHint,
    bool? allowServerTranscoding,
    bool? allowClientTranscoding,
  }) =>
      QualitySettings(
        defaultQuality: defaultQuality ?? this.defaultQuality,
        enableAdaptiveSuggestion: enableAdaptiveSuggestion ?? this.enableAdaptiveSuggestion,
        bufferThresholdSeconds: bufferThresholdSeconds ?? this.bufferThresholdSeconds,
        rememberPerVideo: rememberPerVideo ?? this.rememberPerVideo,
        showUnsupportedHint: showUnsupportedHint ?? this.showUnsupportedHint,
        allowServerTranscoding: allowServerTranscoding ?? this.allowServerTranscoding,
        allowClientTranscoding: allowClientTranscoding ?? this.allowClientTranscoding,
      );

  Map<String, dynamic> toMap() => {
        'defaultQuality': defaultQuality.name,
        'enableAdaptiveSuggestion': enableAdaptiveSuggestion,
        'bufferThresholdSeconds': bufferThresholdSeconds,
        'rememberPerVideo': rememberPerVideo,
        'showUnsupportedHint': showUnsupportedHint,
        'allowServerTranscoding': allowServerTranscoding,
        'allowClientTranscoding': allowClientTranscoding,
      };
}

/// 清晰度设置管理
class QualitySettingsNotifier extends StateNotifier<QualitySettings> {
  QualitySettingsNotifier() : super(const QualitySettings()) {
    _load();
  }

  static const _boxName = 'quality_settings';
  static const _settingsKey = 'settings';

  Box<Map<dynamic, dynamic>>? _box;
  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;

    try {
      _box = await Hive.openBox<Map<dynamic, dynamic>>(_boxName);
      _initialized = true;
    } on Exception catch (e) {
      logger.e('QualitySettingsNotifier: 初始化失败', e);
    }
  }

  Future<void> _load() async {
    await _init();
    if (_box == null) return;

    final data = _box!.get(_settingsKey);
    if (data != null) {
      state = QualitySettings.fromMap(data);
      logger.i('QualitySettingsNotifier: 加载设置成功');
    }
  }

  Future<void> _save() async {
    await _init();
    if (_box == null) return;

    await _box!.put(_settingsKey, state.toMap());
  }

  /// 设置默认清晰度
  Future<void> setDefaultQuality(VideoQuality quality) async {
    state = state.copyWith(defaultQuality: quality);
    await _save();
  }

  /// 设置是否启用自适应建议
  Future<void> setEnableAdaptiveSuggestion({required bool enabled}) async {
    state = state.copyWith(enableAdaptiveSuggestion: enabled);
    await _save();
  }

  /// 设置缓冲阈值
  Future<void> setBufferThreshold(int seconds) async {
    state = state.copyWith(bufferThresholdSeconds: seconds.clamp(1, 30));
    await _save();
  }

  /// 设置是否记住清晰度选择
  Future<void> setRememberPerVideo({required bool enabled}) async {
    state = state.copyWith(rememberPerVideo: enabled);
    await _save();
  }

  /// 设置是否显示不支持转码提示
  Future<void> setShowUnsupportedHint({required bool enabled}) async {
    state = state.copyWith(showUnsupportedHint: enabled);
    await _save();
  }

  /// 设置是否允许服务端转码
  Future<void> setAllowServerTranscoding({required bool enabled}) async {
    state = state.copyWith(allowServerTranscoding: enabled);
    await _save();
  }

  /// 设置是否允许客户端转码
  Future<void> setAllowClientTranscoding({required bool enabled}) async {
    state = state.copyWith(allowClientTranscoding: enabled);
    await _save();
  }
}

/// 清晰度状态
class QualityState {
  const QualityState({
    this.currentQuality = VideoQuality.original,
    this.availableQualities = const [VideoQuality.original],
    this.capability = TranscodingCapability.none,
    this.isLoading = false,
    this.showSuggestionDialog = false,
    this.suggestedQuality,
    this.errorMessage,
    this.videoPath,
    this.videoUrl,
    this.transcodedStreamUrl,
    this.activeSession,
    this.transcodingStartPosition = Duration.zero,
  });

  /// 当前清晰度
  final VideoQuality currentQuality;

  /// 可用清晰度列表
  final List<VideoQuality> availableQualities;

  /// 转码能力
  final TranscodingCapability capability;

  /// 是否正在加载/切换中
  final bool isLoading;

  /// 是否显示切换建议弹窗
  final bool showSuggestionDialog;

  /// 建议的清晰度
  final VideoQuality? suggestedQuality;

  /// 错误信息
  final String? errorMessage;

  /// 当前视频路径（原始路径，用于标识视频）
  final String? videoPath;

  /// 可访问的视频 URL（用于转码）
  final String? videoUrl;

  /// 转码后的流 URL（用于服务端转码）
  final String? transcodedStreamUrl;

  /// 当前活跃的转码会话
  final TranscodingSession? activeSession;

  /// 转码起始位置（用于计算实际播放进度）
  /// 当使用客户端转码时，转码从此位置开始，播放器报告的位置需要加上此偏移量
  final Duration transcodingStartPosition;

  /// 是否支持清晰度切换
  bool get canSwitchQuality => capability != TranscodingCapability.none;

  /// 是否使用服务端转码
  bool get isServerSideTranscoding => capability == TranscodingCapability.serverSide;

  /// 是否使用客户端转码
  bool get isClientSideTranscoding => capability == TranscodingCapability.clientSide;

  /// 是否正在使用转码流
  bool get isUsingTranscodedStream =>
      transcodedStreamUrl != null && !currentQuality.isOriginal;

  QualityState copyWith({
    VideoQuality? currentQuality,
    List<VideoQuality>? availableQualities,
    TranscodingCapability? capability,
    bool? isLoading,
    bool? showSuggestionDialog,
    VideoQuality? suggestedQuality,
    String? errorMessage,
    String? videoPath,
    String? videoUrl,
    String? transcodedStreamUrl,
    TranscodingSession? activeSession,
    Duration? transcodingStartPosition,
  }) =>
      QualityState(
        currentQuality: currentQuality ?? this.currentQuality,
        availableQualities: availableQualities ?? this.availableQualities,
        capability: capability ?? this.capability,
        isLoading: isLoading ?? this.isLoading,
        showSuggestionDialog: showSuggestionDialog ?? this.showSuggestionDialog,
        suggestedQuality: suggestedQuality ?? this.suggestedQuality,
        errorMessage: errorMessage,
        videoPath: videoPath ?? this.videoPath,
        videoUrl: videoUrl ?? this.videoUrl,
        transcodedStreamUrl: transcodedStreamUrl,
        activeSession: activeSession,
        transcodingStartPosition: transcodingStartPosition ?? this.transcodingStartPosition,
      );
}

/// 切换清晰度后的回调类型
typedef QualitySwitchCallback = Future<void> Function(String newStreamUrl);

/// 清晰度管理 Notifier
class QualityNotifier extends StateNotifier<QualityState> {
  QualityNotifier(this._ref) : super(const QualityState()) {
    _capabilityService = TranscodingCapabilityService();
    _monitorService = QualityMonitorService(
      bufferThresholdSeconds: _ref.read(qualitySettingsProvider).bufferThresholdSeconds,
    );

    // 设置监控回调
    _monitorService.onQualitySuggestion = _onQualitySuggestion;
    _monitorService.onQualityUnsupported = _onQualityUnsupported;
  }

  final Ref _ref;
  late final TranscodingCapabilityService _capabilityService;
  late final QualityMonitorService _monitorService;

  /// 播放器引用（用于获取当前播放位置）
  Player? _player;

  /// NAS 转码服务（用于服务端转码）
  NasTranscodingService? _transcodingService;

  /// 客户端转码服务（用于 SMB/FTP/WebDAV 等）
  ClientTranscodingService? _clientTranscodingService;

  /// 清晰度切换后的回调
  QualitySwitchCallback? onQualitySwitched;

  /// 初始化（设置源类型和播放器）
  ///
  /// [videoPath] 原始文件路径（用于标识视频）
  /// [videoUrl] 可访问的视频 URL（用于转码，如代理 URL）
  Future<void> init({
    required SourceType sourceType,
    required Player player,
    required String videoPath,
    String? videoUrl,
    int? videoWidth,
    int? videoHeight,
    NasTranscodingService? transcodingService,
    ClientTranscodingService? clientTranscodingService,
  }) async {
    // 检查是否已被销毁
    if (!mounted) {
      logger.w('清晰度: init 被调用但 Notifier 已销毁，跳过');
      return;
    }

    _player = player; // 保存播放器引用，用于获取当前位置
    _transcodingService = transcodingService;
    _clientTranscodingService = clientTranscodingService;

    // 读取转码相关设置（服务端 / 客户端转码开关）
    final settings = _ref.read(qualitySettingsProvider);

    // 检测转码能力
    var capability = _capabilityService.getCapability(sourceType);
    logger.d('清晰度: 源类型=$sourceType, 初始能力=$capability');

    // 服务端转码开关：关闭后服务端能力源降级为「仅原画」
    if (capability == TranscodingCapability.serverSide &&
        !settings.allowServerTranscoding) {
      capability = TranscodingCapability.none;
      logger.i('清晰度: 服务端转码已被用户关闭，降级为仅原画');
    }

    // 客户端转码开关：关闭后客户端能力源降级为「仅原画」，跳过 FFmpeg 初始化
    if (capability == TranscodingCapability.clientSide &&
        !settings.allowClientTranscoding) {
      capability = TranscodingCapability.none;
      logger.i('清晰度: 客户端转码已被用户关闭，降级为仅原画');
    }

    // 对于客户端转码，需要检查 FFmpeg 是否可用
    if (capability == TranscodingCapability.clientSide) {
      // 如果没有传入客户端转码服务，创建一个
      _clientTranscodingService ??= ClientTranscodingService();
      logger.d('清晰度: 开始初始化客户端转码服务...');
      await _clientTranscodingService!.init();
      logger.d('清晰度: 客户端转码服务初始化完成, isAvailable=${_clientTranscodingService!.isAvailable}');

      // 异步操作后再次检查是否已销毁
      if (!mounted) {
        logger.w('清晰度: FFmpeg 初始化后 Notifier 已销毁，跳过');
        return;
      }

      // 如果客户端转码不可用，降级为不支持转码
      if (!_clientTranscodingService!.isAvailable) {
        capability = TranscodingCapability.none;
        logger.w('清晰度: 客户端转码不可用 (FFmpeg 未找到)，禁用清晰度切换');
      } else {
        logger.i('清晰度: 客户端转码可用');
      }
    }

    // 再次检查是否已销毁（在更新 state 之前）
    if (!mounted) {
      logger.w('清晰度: 更新状态前 Notifier 已销毁，跳过');
      return;
    }

    // 计算可用清晰度
    List<VideoQuality> availableQualities;
    if (capability == TranscodingCapability.none) {
      availableQualities = [VideoQuality.original];
    } else if (videoWidth != null && videoHeight != null) {
      availableQualities = VideoQuality.getAvailableQualities(
        videoWidth: videoWidth,
        videoHeight: videoHeight,
      );
    } else {
      // 没有视频尺寸信息，提供全部选项
      availableQualities = VideoQuality.values.toList();
    }

    // 获取默认清晰度
    var defaultQuality = settings.defaultQuality;

    // 如果默认清晰度不在可用列表中，使用原画
    if (!availableQualities.contains(defaultQuality)) {
      defaultQuality = VideoQuality.original;
    }

    state = state.copyWith(
      currentQuality: defaultQuality,
      availableQualities: availableQualities,
      capability: capability,
      videoPath: videoPath,
      videoUrl: videoUrl ?? videoPath, // 如果没有提供 videoUrl，使用 videoPath
    );

    // 初始化质量监控（仅在启用自适应建议时）
    if (settings.enableAdaptiveSuggestion && capability != TranscodingCapability.none) {
      _monitorService.init(
        player: player,
        availableQualities: availableQualities,
        currentQuality: defaultQuality,
      );
    }

    logger.i('清晰度初始化: 能力=$capability, 当前=${defaultQuality.label}, '
        '可用=${availableQualities.map((q) => q.label).join(",")}');
  }

  /// 切换清晰度
  Future<void> switchQuality(VideoQuality quality) async {
    if (!state.availableQualities.contains(quality)) {
      logger.w('清晰度 ${quality.label} 不可用');
      return;
    }

    if (state.currentQuality == quality) {
      logger.i('已经是 ${quality.label}');
      return;
    }

    // 检查是否已销毁
    if (!mounted) {
      logger.w('清晰度: switchQuality 被调用但 Notifier 已销毁');
      return;
    }

    state = state.copyWith(isLoading: true);

    try {
      String? newStreamUrl;

      // 根据转码能力类型处理
      if (state.isServerSideTranscoding && _transcodingService != null) {
        // 服务端转码：从 NAS/媒体服务器获取转码流
        newStreamUrl = await _handleServerSideTranscoding(quality);
      } else if (state.isClientSideTranscoding && _clientTranscodingService != null) {
        // 客户端转码：使用本地 FFmpeg
        newStreamUrl = await _handleClientSideTranscoding(quality);
      }

      // 异步操作后检查是否已销毁
      if (!mounted) {
        logger.w('清晰度: 转码完成后 Notifier 已销毁');
        return;
      }

      // 停止之前的转码会话
      if (state.activeSession != null) {
        await _transcodingService?.stopSession(state.activeSession!.sessionId);
      }

      // 再次检查是否已销毁
      if (!mounted) {
        logger.w('清晰度: 停止会话后 Notifier 已销毁');
        return;
      }

      // 更新状态
      // 如果切换回原画（newStreamUrl 为 null），重置偏移量为零
      state = state.copyWith(
        currentQuality: quality,
        isLoading: false,
        showSuggestionDialog: false,
        suggestedQuality: null,
        transcodedStreamUrl: newStreamUrl,
        transcodingStartPosition: newStreamUrl == null ? Duration.zero : null, // 原画时重置
      );

      // 更新监控服务
      _monitorService.setCurrentQuality(quality);

      // 通知播放器切换流
      if (newStreamUrl != null && onQualitySwitched != null) {
        await onQualitySwitched!(newStreamUrl);
      }

      logger.i('清晰度已切换到 ${quality.label}');
    } catch (e) {
      // 更新错误状态前检查是否已销毁
      if (!mounted) {
        logger.w('清晰度: 错误处理时 Notifier 已销毁: $e');
        return;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: '切换清晰度失败: $e',
      );
      logger.w('切换清晰度失败: $e');
    }
  }

  /// 处理服务端转码
  Future<String?> _handleServerSideTranscoding(VideoQuality quality) async {
    if (_transcodingService == null || state.videoPath == null) {
      return null;
    }

    // 如果是原画，返回 null 表示使用原始流
    if (quality.isOriginal) {
      return null;
    }

    // 请求转码会话
    final session = await _transcodingService!.startSession(
      videoPath: state.videoPath!,
      quality: quality,
    );

    if (session != null) {
      state = state.copyWith(activeSession: session);
      return session.streamUrl;
    }

    // 如果会话创建失败，尝试直接获取流 URL
    return _transcodingService!.getTranscodedStreamUrl(
      videoPath: state.videoPath!,
      quality: quality,
    );
  }

  /// 处理客户端转码
  Future<String?> _handleClientSideTranscoding(VideoQuality quality) async {
    if (_clientTranscodingService == null || state.videoUrl == null) {
      return null;
    }

    // 如果是原画，返回 null 表示使用原始流
    if (quality.isOriginal) {
      return null;
    }

    // 获取当前播放位置（从这个位置开始转码，加速切换）
    final currentPosition = _player?.state.position ?? Duration.zero;

    logger.i('客户端转码: 开始转码到 ${quality.label}，从 ${currentPosition.inSeconds}s 开始');
    logger.d('客户端转码: 输入 URL = ${state.videoUrl}');

    // 请求转码（传入起始位置）
    final streamUrl = await _clientTranscodingService!.getTranscodedStreamUrl(
      videoPath: state.videoUrl!, // 使用可访问的 URL
      quality: quality,
      startPosition: currentPosition, // 从当前位置开始转码
    );

    if (streamUrl != null) {
      // 创建会话记录，保存转码起始位置用于进度计算
      final session = TranscodingSession(
        sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
        streamUrl: streamUrl,
        quality: quality,
      );
      state = state.copyWith(
        activeSession: session,
        transcodingStartPosition: currentPosition, // 保存起始位置用于进度偏移
      );
      logger.i('客户端转码: 转码完成，流 URL: $streamUrl，起始位置: ${currentPosition.inSeconds}s');
      return streamUrl;
    }

    // 转码失败
    logger.e('客户端转码: 转码失败');
    return null;
  }

  /// 处理质量建议回调
  void _onQualitySuggestion(VideoQuality current, VideoQuality suggested) {
    state = state.copyWith(
      showSuggestionDialog: true,
      suggestedQuality: suggested,
    );
  }

  /// 处理不支持转码回调
  void _onQualityUnsupported() {
    final settings = _ref.read(qualitySettingsProvider);
    if (settings.showUnsupportedHint) {
      state = state.copyWith(
        errorMessage: '当前源不支持清晰度切换',
      );
    }
  }

  /// 接受建议切换
  Future<void> acceptSuggestion() async {
    final suggested = state.suggestedQuality;
    if (suggested == null) return;

    await switchQuality(suggested);
  }

  /// 拒绝建议切换
  void rejectSuggestion({bool dontAskAgain = false}) {
    final suggested = state.suggestedQuality;
    if (suggested != null) {
      _monitorService.rejectSuggestion(suggested);
    }

    if (dontAskAgain) {
      _monitorService.optOut();
    }

    state = state.copyWith(
      showSuggestionDialog: false,
      suggestedQuality: null,
    );
  }

  /// 清除错误信息
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  /// 隐藏建议弹窗
  void hideSuggestionDialog() {
    state = state.copyWith(
      showSuggestionDialog: false,
    );
  }

  /// 停止当前转码会话
  Future<void> stopTranscoding() async {
    if (state.activeSession != null) {
      if (_transcodingService != null) {
        await _transcodingService!.stopSession(state.activeSession!.sessionId);
      }
      if (_clientTranscodingService != null) {
        await _clientTranscodingService!.stopSession(state.activeSession!.sessionId);
      }
      state = state.copyWith(
        activeSession: null,
        transcodedStreamUrl: null,
      );
    }
  }

  @override
  void dispose() {
    // 停止转码会话
    if (state.activeSession != null) {
      _transcodingService?.stopSession(state.activeSession!.sessionId);
      _clientTranscodingService?.stopSession(state.activeSession!.sessionId);
    }
    // 清理客户端转码服务
    _clientTranscodingService?.dispose();
    _monitorService.dispose();
    super.dispose();
  }
}
