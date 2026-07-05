import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/storage/secure_storage_options.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/service_adapters/trakt/api/trakt_api.dart';
import 'package:my_nas/service_adapters/trakt/trakt_config.dart';

/// Trakt 连接状态
enum TraktConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// Trakt 同步统计
class TraktStats {
  const TraktStats({
    this.moviesWatched = 0,
    this.showsWatched = 0,
    this.episodesWatched = 0,
    this.watchlistCount = 0,
  });

  factory TraktStats.fromJson(Map<String, dynamic> json) {
    final movies = json['movies'] as Map<String, dynamic>? ?? {};
    final shows = json['shows'] as Map<String, dynamic>? ?? {};
    final episodes = json['episodes'] as Map<String, dynamic>? ?? {};

    return TraktStats(
      moviesWatched: movies['watched'] as int? ?? 0,
      showsWatched: shows['watched'] as int? ?? 0,
      episodesWatched: episodes['watched'] as int? ?? 0,
      watchlistCount: 0, // 需要单独获取
    );
  }

  final int moviesWatched;
  final int showsWatched;
  final int episodesWatched;
  final int watchlistCount;
}

/// Trakt 连接状态
class TraktConnectionState {
  const TraktConnectionState({
    this.status = TraktConnectionStatus.disconnected,
    this.userSettings,
    this.stats,
    this.errorMessage,
    this.deviceCode,
  });

  final TraktConnectionStatus status;
  final TraktUserSettings? userSettings;
  final TraktStats? stats;
  final String? errorMessage;

  /// 当前的设备码（Device Code Flow）
  final TraktDeviceCode? deviceCode;

  bool get isConnected => status == TraktConnectionStatus.connected;

  TraktConnectionState copyWith({
    TraktConnectionStatus? status,
    TraktUserSettings? userSettings,
    TraktStats? stats,
    String? errorMessage,
    TraktDeviceCode? deviceCode,
    bool clearDeviceCode = false,
  }) =>
      TraktConnectionState(
        status: status ?? this.status,
        userSettings: userSettings ?? this.userSettings,
        stats: stats ?? this.stats,
        errorMessage: errorMessage,
        deviceCode: clearDeviceCode ? null : (deviceCode ?? this.deviceCode),
      );
}

/// Trakt 持久化配置
class TraktConfig {
  const TraktConfig({
    required this.clientId,
    required this.clientSecret,
    this.useBuiltInCredentials = false,
    this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  factory TraktConfig.fromJson(Map<String, dynamic> json) => TraktConfig(
        clientId: json['clientId'] as String,
        clientSecret: json['clientSecret'] as String,
        useBuiltInCredentials: json['useBuiltInCredentials'] as bool? ?? false,
        accessToken: json['accessToken'] as String?,
        refreshToken: json['refreshToken'] as String?,
        expiresAt: json['expiresAt'] != null
            ? DateTime.parse(json['expiresAt'] as String)
            : null,
      );

  final String clientId;
  final String clientSecret;
  final bool useBuiltInCredentials;
  final String? accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;

  bool get hasValidToken =>
      accessToken != null &&
      expiresAt != null &&
      expiresAt!.isAfter(DateTime.now());

  Map<String, dynamic> toJson() => {
        'clientId': clientId,
        'clientSecret': clientSecret,
        'useBuiltInCredentials': useBuiltInCredentials,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt?.toIso8601String(),
      };

  TraktConfig copyWith({
    String? clientId,
    String? clientSecret,
    bool? useBuiltInCredentials,
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
  }) =>
      TraktConfig(
        clientId: clientId ?? this.clientId,
        clientSecret: clientSecret ?? this.clientSecret,
        useBuiltInCredentials:
            useBuiltInCredentials ?? this.useBuiltInCredentials,
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        expiresAt: expiresAt ?? this.expiresAt,
      );
}

/// Trakt 连接管理器
final traktConnectionProvider =
    StateNotifierProvider<TraktConnectionNotifier, TraktConnectionState>(
  (ref) => TraktConnectionNotifier(),
);

class TraktConnectionNotifier extends StateNotifier<TraktConnectionState> {
  TraktConnectionNotifier() : super(const TraktConnectionState()) {
    _init();
  }

  static const _storage = defaultSecureStorage;

  static const _configKey = 'trakt_config';
  static const _pendingOAuthKey = 'trakt_pending_oauth';

  TraktApi? _api;
  TraktConfig? _config;

  /// 获取 API 实例
  TraktApi? get api => _api;

  /// 是否支持深度链接回调（仅移动端）
  bool get supportsDeepLinkCallback => Platform.isIOS || Platform.isAndroid;

  /// 是否有内置凭证可用
  bool get hasBuiltInCredentials => TraktOAuthConfig.hasBuiltInCredentials;

  /// 是否正在轮询设备授权
  bool _isPolling = false;

  // ==================== Device Code Flow ====================

  /// 启动设备码授权流程
  ///
  /// 返回设备码信息，UI 应显示 userCode 和 verificationUrl 给用户
  Future<TraktDeviceCode> startDeviceCodeFlow({
    String? clientId,
    String? clientSecret,
  }) async {
    // 使用提供的凭证或内置凭证
    final effectiveClientId = clientId ?? TraktOAuthConfig.builtInClientId;
    final effectiveClientSecret =
        clientSecret ?? TraktOAuthConfig.builtInClientSecret;

    state = state.copyWith(status: TraktConnectionStatus.connecting);

    try {
      _api = TraktApi(
        clientId: effectiveClientId,
        clientSecret: effectiveClientSecret,
      );

      final deviceCode = await _api!.requestDeviceCode();

      // 更新 state，触发 UI 重建
      state = state.copyWith(
        status: TraktConnectionStatus.connecting,
        deviceCode: deviceCode,
      );

      // 开始后台轮询
      _startPollingDeviceToken(
        deviceCode: deviceCode,
        clientId: effectiveClientId,
        clientSecret: effectiveClientSecret,
      );

      return deviceCode;
    } on Exception catch (e, st) {
      logger.e('TraktConnectionNotifier: 请求设备码失败', e, st);
      state = state.copyWith(
        status: TraktConnectionStatus.error,
        errorMessage: e.toString(),
        clearDeviceCode: true,
      );
      rethrow;
    }
  }

  /// 开始轮询设备授权状态
  void _startPollingDeviceToken({
    required TraktDeviceCode deviceCode,
    required String clientId,
    required String clientSecret,
  }) {
    if (_isPolling) return;
    _isPolling = true;

    final interval = Duration(seconds: deviceCode.interval);
    final expiresAt = DateTime.now().add(Duration(seconds: deviceCode.expiresIn));

    Future<void> poll() async {
      while (_isPolling && DateTime.now().isBefore(expiresAt)) {
        await Future<void>.delayed(interval);
        if (!_isPolling) break;

        try {
          final tokenResponse = await _api!.pollDeviceToken(deviceCode.deviceCode);

          if (tokenResponse != null) {
            // 授权成功！
            _isPolling = false;

            // 保存配置
            _config = TraktConfig(
              clientId: clientId,
              clientSecret: clientSecret,
              useBuiltInCredentials: clientId == TraktOAuthConfig.builtInClientId,
              accessToken: tokenResponse.accessToken,
              refreshToken: tokenResponse.refreshToken,
              expiresAt:
                  DateTime.now().add(Duration(seconds: tokenResponse.expiresIn)),
            );
            await _saveConfig();

            // 获取用户信息
            await _fetchUserData();

            state = state.copyWith(
              status: TraktConnectionStatus.connected,
              clearDeviceCode: true,
            );
            logger.i('TraktConnectionNotifier: Device Code 授权成功');
            return;
          }
        } on TraktApiException catch (e) {
          // 如果是致命错误，停止轮询
          if (e.isFatal) {
            _isPolling = false;
            state = state.copyWith(
              status: TraktConnectionStatus.error,
              errorMessage: e.message,
              clearDeviceCode: true,
            );
            return;
          }
          // 其他错误（如轮询过于频繁、临时网络错误）继续轮询
        }
      }

      // 轮询超时
      if (_isPolling) {
        _isPolling = false;
        state = state.copyWith(
          status: TraktConnectionStatus.error,
          errorMessage: appL10n.traktProviderAuthorizationTimeout,
          clearDeviceCode: true,
        );
      }
    }

    poll();
  }

  /// 取消设备码授权流程
  void cancelDeviceCodeFlow() {
    _isPolling = false;
    state = state.copyWith(
      status: TraktConnectionStatus.disconnected,
      clearDeviceCode: true,
    );
  }

  /// 初始化：尝试从安全存储加载配置并自动连接
  Future<void> _init() async {
    try {
      final configJson = await _storage.read(key: _configKey);
      if (configJson != null) {
        _config = TraktConfig.fromJson(
          jsonDecode(configJson) as Map<String, dynamic>,
        );

        if (_config!.hasValidToken) {
          await _connectWithConfig(_config!);
        } else if (_config!.refreshToken != null) {
          // Token 过期，尝试刷新
          await _refreshToken();
        }
      }
    } on Exception catch (e, st) {
      logger.e('TraktConnectionNotifier: 初始化失败', e, st);
    }
  }

  /// 获取授权 URL（兼容旧接口 - OOB 模式）
  String getAuthorizationUrl(String clientId, String clientSecret) {
    _api = TraktApi(clientId: clientId, clientSecret: clientSecret);
    return _api!.getAuthorizationUrl();
  }

  /// 启动 OAuth 流程（新接口 - 支持深度链接回调）
  ///
  /// [useBuiltIn] - 是否使用内置凭证
  /// [clientId] - 自定义 Client ID（useBuiltIn=false 时必须）
  /// [clientSecret] - 自定义 Client Secret（useBuiltIn=false 时必须）
  ///
  /// 返回授权 URL，调用方应在外部浏览器中打开此 URL
  Future<String> startOAuthFlow({
    bool useBuiltIn = true,
    String? clientId,
    String? clientSecret,
  }) async {
    final effectiveClientId = useBuiltIn
        ? TraktOAuthConfig.builtInClientId
        : clientId ?? '';
    final effectiveClientSecret = useBuiltIn
        ? TraktOAuthConfig.builtInClientSecret
        : clientSecret ?? '';

    if (effectiveClientId.isEmpty || effectiveClientSecret.isEmpty) {
      throw Exception(appL10n.traktProviderMissingCredentials);
    }

    // 选择重定向 URI：移动端使用深度链接，桌面端使用 OOB
    final redirectUri = supportsDeepLinkCallback
        ? TraktOAuthConfig.deepLinkRedirectUri
        : TraktOAuthConfig.oobRedirectUri;

    _api = TraktApi(
      clientId: effectiveClientId,
      clientSecret: effectiveClientSecret,
      redirectUri: redirectUri,
    );

    // 保存待处理的 OAuth 状态（用于回调时恢复）
    final pendingOAuth = {
      'clientId': effectiveClientId,
      'clientSecret': effectiveClientSecret,
      'useBuiltIn': useBuiltIn,
      'redirectUri': redirectUri,
    };
    await _storage.write(
      key: _pendingOAuthKey,
      value: jsonEncode(pendingOAuth),
    );

    state = state.copyWith(status: TraktConnectionStatus.connecting);
    return _api!.getAuthorizationUrl();
  }

  /// 处理 OAuth 回调（深度链接回调后调用）
  Future<void> handleOAuthCallback(String code) async {
    try {
      // 读取待处理的 OAuth 状态
      final pendingJson = await _storage.read(key: _pendingOAuthKey);
      if (pendingJson == null) {
        throw Exception(appL10n.traktProviderNoPendingOAuth);
      }

      final pending = jsonDecode(pendingJson) as Map<String, dynamic>;
      final clientId = pending['clientId'] as String;
      final clientSecret = pending['clientSecret'] as String;
      final useBuiltIn = pending['useBuiltIn'] as bool? ?? false;
      final redirectUri = pending['redirectUri'] as String;

      // 清除待处理状态
      await _storage.delete(key: _pendingOAuthKey);

      // 使用授权码换取 Token
      await _authenticateWithCodeInternal(
        code: code,
        clientId: clientId,
        clientSecret: clientSecret,
        redirectUri: redirectUri,
        useBuiltIn: useBuiltIn,
      );
    } on Exception catch (e, st) {
      logger.e('TraktConnectionNotifier: OAuth 回调处理失败', e, st);
      state = state.copyWith(
        status: TraktConnectionStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// 使用授权码完成认证（兼容旧接口 - OOB 模式）
  Future<void> authenticateWithCode(
    String code,
    String clientId,
    String clientSecret,
  ) async {
    await _authenticateWithCodeInternal(
      code: code,
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: TraktApi.defaultOobRedirectUri,
      useBuiltIn: false,
    );
  }

  /// 内部认证实现
  Future<void> _authenticateWithCodeInternal({
    required String code,
    required String clientId,
    required String clientSecret,
    required String redirectUri,
    required bool useBuiltIn,
  }) async {
    state = state.copyWith(status: TraktConnectionStatus.connecting);

    try {
      _api = TraktApi(
        clientId: clientId,
        clientSecret: clientSecret,
        redirectUri: redirectUri,
      );
      final tokenResponse = await _api!.exchangeCodeForToken(code);

      // 保存配置
      _config = TraktConfig(
        clientId: clientId,
        clientSecret: clientSecret,
        useBuiltInCredentials: useBuiltIn,
        accessToken: tokenResponse.accessToken,
        refreshToken: tokenResponse.refreshToken,
        expiresAt: DateTime.now().add(Duration(seconds: tokenResponse.expiresIn)),
      );
      await _saveConfig();

      // 获取用户信息和统计
      await _fetchUserData();

      state = state.copyWith(status: TraktConnectionStatus.connected);
      logger.i('TraktConnectionNotifier: 认证成功');
    } on Exception catch (e, st) {
      logger.e('TraktConnectionNotifier: 认证失败', e, st);
      state = state.copyWith(
        status: TraktConnectionStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// 使用已保存的配置连接
  Future<void> _connectWithConfig(TraktConfig config) async {
    state = state.copyWith(status: TraktConnectionStatus.connecting);

    try {
      _api = TraktApi(
        clientId: config.clientId,
        clientSecret: config.clientSecret,
        accessToken: config.accessToken,
        refreshToken: config.refreshToken,
        tokenExpiresAt: config.expiresAt,
      );

      await _fetchUserData();
      state = state.copyWith(status: TraktConnectionStatus.connected);
      logger.i('TraktConnectionNotifier: 使用保存的配置连接成功');
    } on Exception catch (e, st) {
      logger.e('TraktConnectionNotifier: 连接失败', e, st);
      state = state.copyWith(
        status: TraktConnectionStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// 刷新 Token
  Future<void> _refreshToken() async {
    if (_config?.refreshToken == null) return;

    try {
      _api = TraktApi(
        clientId: _config!.clientId,
        clientSecret: _config!.clientSecret,
        refreshToken: _config!.refreshToken,
      );

      final tokenResponse = await _api!.refreshAccessToken();

      _config = _config!.copyWith(
        accessToken: tokenResponse.accessToken,
        refreshToken: tokenResponse.refreshToken,
        expiresAt: DateTime.now().add(Duration(seconds: tokenResponse.expiresIn)),
      );
      await _saveConfig();

      await _fetchUserData();
      state = state.copyWith(status: TraktConnectionStatus.connected);
      logger.i('TraktConnectionNotifier: Token 刷新成功');
    } on Exception catch (e, st) {
      logger.e('TraktConnectionNotifier: Token 刷新失败', e, st);
      state = state.copyWith(
        status: TraktConnectionStatus.error,
        errorMessage: appL10n.traktProviderTokenRefreshFailed,
      );
    }
  }

  /// 获取用户数据
  Future<void> _fetchUserData() async {
    if (_api == null) return;

    try {
      // 并行获取用户设置、统计数据和待看列表
      final results = await Future.wait([
        _api!.getUserSettings(),
        _api!.getUserStats(),
        _api!.getWatchlist(limit: 1),
      ]);

      final userSettings = results[0] as TraktUserSettings;
      final userStats = results[1] as TraktUserStats;
      final watchlist = results[2] as List<TraktWatchlistItem>;

      state = state.copyWith(
        userSettings: userSettings,
        stats: TraktStats(
          moviesWatched: userStats.moviesWatched,
          showsWatched: userStats.showsWatched,
          episodesWatched: userStats.episodesWatched,
          watchlistCount: watchlist.length,
        ),
      );
    } on Exception catch (e, st) {
      logger.w('TraktConnectionNotifier: 获取用户数据失败', e, st);
    }
  }

  /// 刷新统计数据
  Future<void> refreshStats() async {
    if (_api == null || state.status != TraktConnectionStatus.connected) return;

    await _fetchUserData();
  }

  /// 注销
  Future<void> logout() async {
    try {
      if (_api != null) {
        await _api!.revokeToken();
      }
    } on Exception catch (e, st) {
      logger.w('TraktConnectionNotifier: 撤销 Token 失败（忽略）', e, st);
    }

    _api?.dispose();
    _api = null;
    _config = null;

    await _storage.delete(key: _configKey);

    state = const TraktConnectionState();
    logger.i('TraktConnectionNotifier: 已注销');
  }

  /// 保存配置到安全存储
  Future<void> _saveConfig() async {
    if (_config == null) return;

    try {
      await _storage.write(
        key: _configKey,
        value: jsonEncode(_config!.toJson()),
      );
    } on Exception catch (e, st) {
      logger.e('TraktConnectionNotifier: 保存配置失败', e, st);
    }
  }

  @override
  void dispose() {
    _api?.dispose();
    super.dispose();
  }
}
