import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/scrobble/lastfm_provider.dart';
import 'package:my_nas/features/music/data/services/scrobble/listenbrainz_provider.dart';
import 'package:my_nas/features/music/data/services/scrobble/scrobble_provider.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';

/// 设置层级凭证。UI 改变时调 [MusicScrobbleService.applySettings]。
class ScrobbleSettings {
  const ScrobbleSettings({
    this.enabled = false,
    this.listenbrainzToken,
    this.lastfmApiKey,
    this.lastfmApiSecret,
    this.lastfmSessionKey,
  });

  factory ScrobbleSettings.fromMap(Map<dynamic, dynamic> m) =>
      ScrobbleSettings(
        enabled: m['enabled'] as bool? ?? false,
        listenbrainzToken: m['listenbrainzToken'] as String?,
        lastfmApiKey: m['lastfmApiKey'] as String?,
        lastfmApiSecret: m['lastfmApiSecret'] as String?,
        lastfmSessionKey: m['lastfmSessionKey'] as String?,
      );

  final bool enabled;
  final String? listenbrainzToken;
  final String? lastfmApiKey;
  final String? lastfmApiSecret;
  final String? lastfmSessionKey;

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        if (listenbrainzToken != null) 'listenbrainzToken': listenbrainzToken,
        if (lastfmApiKey != null) 'lastfmApiKey': lastfmApiKey,
        if (lastfmApiSecret != null) 'lastfmApiSecret': lastfmApiSecret,
        if (lastfmSessionKey != null) 'lastfmSessionKey': lastfmSessionKey,
      };

  ScrobbleSettings copyWith({
    bool? enabled,
    Object? listenbrainzToken = const Object(),
    Object? lastfmApiKey = const Object(),
    Object? lastfmApiSecret = const Object(),
    Object? lastfmSessionKey = const Object(),
  }) =>
      ScrobbleSettings(
        enabled: enabled ?? this.enabled,
        listenbrainzToken: identical(listenbrainzToken, const Object())
            ? this.listenbrainzToken
            : listenbrainzToken as String?,
        lastfmApiKey: identical(lastfmApiKey, const Object())
            ? this.lastfmApiKey
            : lastfmApiKey as String?,
        lastfmApiSecret: identical(lastfmApiSecret, const Object())
            ? this.lastfmApiSecret
            : lastfmApiSecret as String?,
        lastfmSessionKey: identical(lastfmSessionKey, const Object())
            ? this.lastfmSessionKey
            : lastfmSessionKey as String?,
      );
}

class _PendingEntry {
  _PendingEntry({
    required this.providerId,
    required this.track,
    required this.playedAt,
    this.attempts = 0,
  });

  factory _PendingEntry.fromJson(Map<dynamic, dynamic> m) => _PendingEntry(
        providerId: (m['providerId'] as String?) ?? '',
        track: ScrobbleTrack.fromJson(
          (m['track'] as Map<dynamic, dynamic>?) ?? {},
        ),
        playedAt: DateTime.fromMillisecondsSinceEpoch(
          (m['playedAt'] as num?)?.toInt() ?? 0,
        ),
        attempts: (m['attempts'] as num?)?.toInt() ?? 0,
      );

  final String providerId;
  final ScrobbleTrack track;
  final DateTime playedAt;
  int attempts;

  Map<String, dynamic> toJson() => {
        'providerId': providerId,
        'track': track.toJson(),
        'playedAt': playedAt.millisecondsSinceEpoch,
        'attempts': attempts,
      };
}

/// 音乐 Scrobble 服务。
///
/// 阈值：50% 或 240s（较小者），最小 30s。
/// 上报：track 开始时调 [reportNowPlaying]；用户实听过阈值后调 [reportScrobble]。
/// 失败队列：本地 Hive 持久化，每次启动时重试一次；失败后指数退避（最多 5 次后丢弃）。
class MusicScrobbleService {
  MusicScrobbleService._();
  static final MusicScrobbleService instance = MusicScrobbleService._();

  /// 50% 触发阈值 / 240s 上限 / 30s 保底
  static const double percentThreshold = 0.5;
  static const Duration absoluteThreshold = Duration(seconds: 240);
  static const Duration minListenSec = Duration(seconds: 30);

  static const String _settingsBox = 'music_scrobble_settings';
  static const String _settingsKey = 'settings';
  static const String _queueBox = 'music_scrobble_pending';

  Box<dynamic>? _sb;
  Box<dynamic>? _qb;
  Timer? _retryTimer;

  ScrobbleSettings _settings = const ScrobbleSettings();
  final ListenBrainzProvider _lb = ListenBrainzProvider();
  final LastFmProvider _lf = LastFmProvider();

  bool _initialized = false;

  // 当前会话状态
  MusicItem? _currentSong;
  DateTime? _currentStartedAt;
  double _currentMaxElapsedSec = 0;

  Future<void> init() async {
    if (_initialized) return;
    _sb = await Hive.openBox<dynamic>(_settingsBox);
    _qb = await Hive.openBox<dynamic>(_queueBox);
    final raw = _sb!.get(_settingsKey);
    if (raw is Map) {
      _settings = ScrobbleSettings.fromMap(raw);
    }
    _applyToProviders();
    _initialized = true;
    // 启动后异步重试历史失败队列
    AppError.fireAndForget(_retryQueue(), action: 'scrobble.retryQueue');
  }

  ScrobbleSettings get settings => _settings;

  Future<void> applySettings(ScrobbleSettings next) async {
    await init();
    _settings = next;
    _applyToProviders();
    await _sb?.put(_settingsKey, next.toMap());
  }

  void _applyToProviders() {
    _lb.userToken = _settings.listenbrainzToken;
    _lf.apiKey = _settings.lastfmApiKey;
    _lf.apiSecret = _settings.lastfmApiSecret;
    _lf.sessionKey = _settings.lastfmSessionKey;
  }

  List<ScrobbleProvider> get _activeProviders {
    if (!_settings.enabled) return const [];
    return [
      if (_lb.isConfigured) _lb,
      if (_lf.isConfigured) _lf,
    ];
  }

  // ----------------------------- 会话生命周期 -----------------------------

  /// 用户开始播放新歌；若上一首未结算则先 flush
  Future<void> beginSession(MusicItem song) async {
    await init();
    await endSession(); // flush 上一首
    _currentSong = song;
    _currentStartedAt = DateTime.now();
    _currentMaxElapsedSec = 0;
    await reportNowPlaying(song);
  }

  /// 进度刻度（与 PlayHistory 同一时机）。high-water mark：seek 回去不让累计变小
  void tick(Duration elapsed) {
    if (_currentSong == null) return;
    final sec = elapsed.inMilliseconds / 1000.0;
    if (sec > _currentMaxElapsedSec) _currentMaxElapsedSec = sec;
  }

  /// 结束会话（停 / 切歌 / 播完）。达到阈值才上报。
  Future<void> endSession() async {
    final song = _currentSong;
    final startedAt = _currentStartedAt;
    final elapsedSec = _currentMaxElapsedSec;
    _currentSong = null;
    _currentStartedAt = null;
    _currentMaxElapsedSec = 0;
    if (song == null || startedAt == null) return;
    final listened = Duration(milliseconds: (elapsedSec * 1000).toInt());
    if (!shouldScrobble(listened: listened, totalDuration: song.duration)) {
      return;
    }
    await reportScrobble(song, startedAt);
  }

  // ----------------------------- 上报入口 -----------------------------

  /// 是否值得 scrobble：满足 30s 最低 + 50%/240s 阈值
  bool shouldScrobble({
    required Duration listened,
    required Duration? totalDuration,
  }) {
    if (listened < minListenSec) return false;
    if (listened >= absoluteThreshold) return true;
    if (totalDuration == null || totalDuration == Duration.zero) {
      return false;
    }
    return listened.inMilliseconds / totalDuration.inMilliseconds >=
        percentThreshold;
  }

  Future<void> reportNowPlaying(MusicItem song) async {
    await init();
    if (_activeProviders.isEmpty) return;
    final track = _trackOf(song);
    for (final p in _activeProviders) {
      AppError.fireAndForget(
        p.nowPlaying(track),
        action: 'scrobble.${p.id}.nowPlaying',
      );
    }
  }

  Future<void> reportScrobble(MusicItem song, DateTime playedAt) async {
    await init();
    if (_activeProviders.isEmpty) return;
    final track = _trackOf(song);
    for (final p in _activeProviders) {
      final ok = await p.scrobble(track, playedAt);
      if (!ok) {
        await _enqueue(_PendingEntry(
          providerId: p.id,
          track: track,
          playedAt: playedAt,
        ));
      }
    }
  }

  ScrobbleTrack _trackOf(MusicItem s) => ScrobbleTrack(
        title: s.title ?? s.name,
        artist: s.artist ?? '',
        album: s.album,
        durationMs: s.duration?.inMilliseconds,
      );

  // ----------------------------- 失败队列 -----------------------------

  Future<void> _enqueue(_PendingEntry entry) async {
    final qb = _qb;
    if (qb == null) return;
    final id = '${DateTime.now().microsecondsSinceEpoch}-${entry.providerId}';
    await qb.put(id, jsonEncode(entry.toJson()));
    _scheduleRetry();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(minutes: 5), () {
      AppError.fireAndForget(_retryQueue(), action: 'scrobble.retryQueueTick');
    });
  }

  Future<void> _retryQueue() async {
    final qb = _qb;
    if (qb == null) return;
    if (_activeProviders.isEmpty) return;
    final keys = qb.keys.toList();
    for (final key in keys) {
      final raw = qb.get(key);
      if (raw is! String) continue;
      _PendingEntry entry;
      try {
        entry = _PendingEntry.fromJson(
          jsonDecode(raw) as Map<dynamic, dynamic>,
        );
      } on Exception {
        await qb.delete(key);
        continue;
      }
      // 指数退避（attempts 越多间隔越长，最多 5 次）
      if (entry.attempts >= 5) {
        await qb.delete(key);
        logger.w('Scrobble: 队列条目超过重试次数，丢弃 $key');
        continue;
      }
      final provider = _providerById(entry.providerId);
      if (provider == null) continue;
      final ok = await provider.scrobble(entry.track, entry.playedAt);
      if (ok) {
        await qb.delete(key);
      } else {
        entry.attempts++;
        await qb.put(key, jsonEncode(entry.toJson()));
      }
      // 简单 backoff：每条之间 sleep min(2^attempts, 30) 秒
      final backoff =
          Duration(seconds: math.min(30, math.pow(2, entry.attempts).toInt()));
      await Future<void>.delayed(backoff);
    }
  }

  ScrobbleProvider? _providerById(String id) {
    if (id == _lb.id) return _lb.isConfigured ? _lb : null;
    if (id == _lf.id) return _lf.isConfigured ? _lf : null;
    return null;
  }

  /// 工具：UI 设置页用，触发一次手动重试
  Future<void> retryNow() => _retryQueue();

  // ----------------------------- Last.fm OAuth -----------------------------

  /// OAuth 第一步：用给定 key/secret 取一次性 token（无需先保存设置）。
  /// 失败返回 null，UI 据此降级回手动粘贴 sk。
  Future<String?> lastfmFetchToken({
    required String apiKey,
    required String apiSecret,
  }) async {
    final p = LastFmProvider(apiKey: apiKey, apiSecret: apiSecret);
    return p.fetchAuthToken();
  }

  /// OAuth 拼授权页 URL（由 UI 用 url_launcher 打开）。
  String lastfmAuthorizeUrl({
    required String apiKey,
    required String token,
  }) =>
      LastFmProvider(apiKey: apiKey).buildAuthorizeUrl(token);

  /// OAuth 第三步：用户授权后取回 sk。成功返回 sk，失败/未授权返回 null。
  Future<String?> lastfmFetchSessionKey({
    required String apiKey,
    required String apiSecret,
    required String token,
  }) async {
    final p = LastFmProvider(apiKey: apiKey, apiSecret: apiSecret);
    return p.fetchSessionKey(token);
  }
}
