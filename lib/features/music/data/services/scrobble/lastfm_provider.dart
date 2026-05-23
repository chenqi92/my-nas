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
/// 简化：本实现只接 sk，不集成 OAuth。把流程走完后用户复制 sk 进来即可。
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
