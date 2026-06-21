import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/scrobble/scrobble_provider.dart';

/// Last.fm scrobble provider — Web API auth.scrobble / track.updateNowPlaying。
/// 用户需在设置页填三项：API key、API secret、session key。
///
/// session key 获取流程（首次配置时一次性走完）：
/// 1. 浏览器打开 `http://www.last.fm/api/auth/?api_key=YOUR_KEY` 授权
/// 2. 重定向参数里拿到 token
/// 3. 调用 auth.getSession(api_key, token, api_sig) 拿 sk
/// 4. 把 sk 粘贴回 app
///
/// 支持应用内 OAuth：[fetchAuthToken] 取 token → [buildAuthorizeUrl] 打开授权页 →
/// 用户授权后 [fetchSessionKey] 自动取回 sk。手动粘贴 sk 仍可作为兜底。
class LastFmProvider implements ScrobbleProvider {
  LastFmProvider({
    this.apiKey,
    this.apiSecret,
    this.sessionKey,
  });

  String? apiKey;
  String? apiSecret;
  String? sessionKey;

  static const String _endpoint = 'https://ws.audioscrobbler.com/2.0/';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    sendTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));

  @override
  String get id => 'lastfm';

  @override
  String get displayName => 'Last.fm';

  @override
  bool get isConfigured =>
      (apiKey?.isNotEmpty ?? false) &&
      (apiSecret?.isNotEmpty ?? false) &&
      (sessionKey?.isNotEmpty ?? false);

  @override
  Future<bool> nowPlaying(ScrobbleTrack track) async {
    if (!isConfigured) return false;
    return _post(_buildParams('track.updateNowPlaying', track));
  }

  @override
  Future<bool> scrobble(ScrobbleTrack track, DateTime playedAt) async {
    if (!isConfigured) return false;
    final params = _buildParams('track.scrobble', track);
    params['timestamp'] =
        (playedAt.millisecondsSinceEpoch ~/ 1000).toString();
    return _post(params);
  }

  /// 工具：列出当前可用的 OAuth 跳转 URL，UI 引导用户完成授权
  String authorizeUrl() {
    if (apiKey == null || apiKey!.isEmpty) return '';
    return 'https://www.last.fm/api/auth/?api_key=$apiKey';
  }

  /// OAuth 第一步：auth.getToken 取一次性 token。
  /// 失败返回 null（调用方应优雅降级到手动粘贴）。
  Future<String?> fetchAuthToken() async {
    if (apiKey == null || apiKey!.isEmpty) return null;
    if (apiSecret == null || apiSecret!.isEmpty) return null;
    final params = <String, String>{
      'method': 'auth.getToken',
      'api_key': apiKey!,
    };
    final data = await _getSigned(params);
    if (data is Map && data['token'] is String) {
      final token = data['token'] as String;
      return token.isEmpty ? null : token;
    }
    return null;
  }

  /// OAuth 第二步：用 token 拼授权页 URL，由 UI（url_launcher）打开。
  String buildAuthorizeUrl(String token) {
    if (apiKey == null || apiKey!.isEmpty) return '';
    return 'https://www.last.fm/api/auth/?api_key=$apiKey&token=$token';
  }

  /// OAuth 第三步：用户授权后调用 auth.getSession 取回 sk。
  /// 成功时把 [sessionKey] 写入本实例并返回 sk；失败返回 null
  /// （token 未授权 / 过期会返回 error 14/15，调用方据此提示用户重试）。
  Future<String?> fetchSessionKey(String token) async {
    if (apiKey == null || apiKey!.isEmpty) return null;
    if (apiSecret == null || apiSecret!.isEmpty) return null;
    if (token.isEmpty) return null;
    final params = <String, String>{
      'method': 'auth.getSession',
      'api_key': apiKey!,
      'token': token,
    };
    final data = await _getSigned(params);
    if (data is Map) {
      if (data['error'] != null) {
        logger.w('Last.fm: auth.getSession 失败 ${data['error']} ${data['message']}');
        return null;
      }
      final session = data['session'];
      if (session is Map && session['key'] is String) {
        final sk = session['key'] as String;
        if (sk.isNotEmpty) {
          sessionKey = sk;
          return sk;
        }
      }
    }
    return null;
  }

  /// 已签名 GET 请求（auth.* 系列用），返回解析后的 JSON map，异常返回 null。
  Future<dynamic> _getSigned(Map<String, String> params) async {
    final query = Map<String, String>.from(params)
      ..['api_sig'] = _signature(params)
      ..['format'] = 'json';
    try {
      final resp = await _dio.get<dynamic>(
        _endpoint,
        queryParameters: query,
      );
      final data = resp.data;
      if (data is String) {
        try {
          return jsonDecode(data);
        } on FormatException {
          return null;
        }
      }
      return data;
    } on DioException catch (e) {
      logger.w('Last.fm: auth 请求失败 ${e.response?.statusCode} ${e.message}');
      return null;
    } on Exception catch (e) {
      logger.w('Last.fm: auth 请求失败 $e');
      return null;
    }
  }

  Map<String, String> _buildParams(String method, ScrobbleTrack track) => <String, String>{
      'method': method,
      'api_key': apiKey ?? '',
      'sk': sessionKey ?? '',
      'artist': track.artist,
      'track': track.title,
      if (track.album != null) 'album': track.album!,
      if (track.albumArtist != null) 'albumArtist': track.albumArtist!,
      if (track.durationMs != null)
        'duration': (track.durationMs! ~/ 1000).toString(),
      if (track.trackNumber != null)
        'trackNumber': track.trackNumber.toString(),
      if (track.mbid != null) 'mbid': track.mbid!,
    };

  /// Last.fm 签名：把所有非 format/api_sig 的参数按 key 升序拼接 + secret，md5 hex。
  String _signature(Map<String, String> params) {
    final keys = params.keys.toList()..sort();
    final buf = StringBuffer();
    for (final k in keys) {
      buf
        ..write(k)
        ..write(params[k]);
    }
    buf.write(apiSecret ?? '');
    return md5.convert(utf8.encode(buf.toString())).toString();
  }

  Future<bool> _post(Map<String, String> params) async {
    final signed = Map<String, String>.from(params)
      ..['api_sig'] = _signature(params)
      ..['format'] = 'json';
    try {
      final resp = await _dio.post<dynamic>(
        _endpoint,
        data: signed,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      final data = resp.data;
      if (data is Map && data['error'] != null) {
        logger.w('Last.fm: 错误 ${data['error']} ${data['message']}');
        return false;
      }
      return resp.statusCode == 200;
    } on DioException catch (e) {
      logger.w('Last.fm: 请求失败 ${e.response?.statusCode} ${e.message}');
      return false;
    } on Exception catch (e) {
      logger.w('Last.fm: 请求失败 $e');
      return false;
    }
  }
}
