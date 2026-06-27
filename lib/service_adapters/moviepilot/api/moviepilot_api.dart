import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';

/// MoviePilot API 客户端
///
/// 支持 MoviePilot v2 API
/// 项目地址: https://github.com/jxxghp/MoviePilot
class MoviePilotApi {
  MoviePilotApi({required this.baseUrl, required this.apiToken});

  final String baseUrl;
  final String apiToken;

  http.Client? _client;
  bool _isAuthenticated = false;

  /// 获取 HTTP 客户端
  http.Client get client {
    _client ??= http.Client();
    return _client!;
  }

  /// 是否已认证
  bool get isAuthenticated => _isAuthenticated;

  /// 验证连接
  Future<bool> validateConnection() async {
    try {
      _log('validateConnection: 开始验证连接 baseUrl=$baseUrl');
      _log(
        'validateConnection: apiToken=${apiToken.isNotEmpty ? "已配置(${apiToken.length}字符)" : "未配置"}',
      );

      // MoviePilot 使用 /api/v1/system/env 端点验证连接
      final response = await _makeRequest('GET', '/api/v1/system/env');
      _log('validateConnection: 响应状态码=${response.statusCode}');

      if (response.statusCode == 200) {
        _isAuthenticated = true;
        _log('validateConnection: 连接验证成功');
        return true;
      }
      _log('validateConnection: 连接验证失败，状态码=${response.statusCode}');
      return false;
    } on MoviePilotApiException catch (e) {
      _log('validateConnection: API异常 - ${e.message}');
      return false;
    } on Exception catch (e) {
      _log('validateConnection: 未知异常 - $e');
      return false;
    }
  }

  void _log(String message) {
    logger.d('[MoviePilotApi] $message');
  }

  /// 获取系统信息
  Future<MoviePilotSystemInfo> getSystemInfo() async {
    final response = await _makeRequest('GET', '/api/v1/system/env');
    final data = _extractMap(jsonDecode(response.body));
    return MoviePilotSystemInfo.fromJson(data);
  }

  /// 获取订阅列表
  Future<List<MoviePilotSubscribe>> getSubscribes() async {
    final response = await _makeRequest('GET', '/api/v1/subscribe/');
    return _extractMaps(
      jsonDecode(response.body),
    ).map(MoviePilotSubscribe.fromJson).toList();
  }

  /// 添加订阅
  Future<bool> addSubscribe({
    required String name,
    required String mediaType,
    int? tmdbId,
    int? season,
  }) async {
    final response = await _makeRequest(
      'POST',
      '/api/v1/subscribe/',
      body: {
        'name': name,
        'type': mediaType,
        'tmdbid': ?tmdbId,
        'season': ?season,
      },
    );
    return response.statusCode == 200;
  }

  /// 删除订阅
  Future<bool> deleteSubscribe(int subscribeId) async {
    final response = await _makeRequest(
      'DELETE',
      '/api/v1/subscribe/$subscribeId',
    );
    return response.statusCode == 200;
  }

  /// 搜索资源
  Future<List<MoviePilotSearchResult>> searchResources({
    required String keyword,
    String? mediaType,
    int page = 1,
  }) async {
    final queryParams = <String, String>{
      'keyword': keyword,
      'mtype': ?mediaType,
      'page': page.toString(),
    };

    final response = await _makeRequest(
      'GET',
      '/api/v1/search/title',
      queryParams: queryParams,
    );

    return _extractMaps(
      jsonDecode(response.body),
    ).map(MoviePilotSearchResult.fromJson).toList();
  }

  /// 获取下载任务列表
  Future<List<MoviePilotDownloadTask>> getDownloadTasks() async {
    final response = await _makeRequest('GET', '/api/v1/download/');
    return _extractMaps(
      jsonDecode(response.body),
    ).map(MoviePilotDownloadTask.fromJson).toList();
  }

  /// 获取转移历史
  Future<List<MoviePilotTransferHistory>> getTransferHistory({
    int page = 1,
    int count = 20,
  }) async {
    final response = await _makeRequest(
      'GET',
      '/api/v1/history/transfer',
      queryParams: {'page': page.toString(), 'count': count.toString()},
    );

    return _extractMaps(
      jsonDecode(response.body),
    ).map(MoviePilotTransferHistory.fromJson).toList();
  }

  /// 发起请求
  Future<http.Response> _makeRequest(
    String method,
    String path, {
    Map<String, String>? queryParams,
    Map<String, dynamic>? body,
  }) async {
    var url = Uri.parse('$baseUrl$path');
    if (queryParams != null && queryParams.isNotEmpty) {
      url = url.replace(queryParameters: queryParams);
    }

    // MoviePilot 使用 X-API-KEY header 认证
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'X-API-KEY': apiToken,
    };

    _log('_makeRequest: $method $url');

    http.Response response;

    try {
      if (method == 'GET') {
        response = await client.get(url, headers: headers);
      } else if (method == 'POST') {
        response = await client.post(
          url,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        );
      } else if (method == 'DELETE') {
        response = await client.delete(url, headers: headers);
      } else {
        throw MoviePilotApiException(
          appL10n.moviepilotApiUnsupportedMethod(method),
        );
      }

      _log('_makeRequest: 响应 ${response.statusCode}');

      if (response.statusCode == 401 || response.statusCode == 403) {
        _isAuthenticated = false;
        throw MoviePilotApiException(appL10n.moviepilotApiAuthFailed);
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _log(
          '_makeRequest: 错误响应 body=${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}',
        );
        throw MoviePilotApiException(
          appL10n.moviepilotApiRequestFailed(
            response.statusCode,
            response.reasonPhrase ?? '',
          ),
        );
      }

      return response;
    } on SocketException catch (e) {
      _log('_makeRequest: SocketException - ${e.message}');
      throw MoviePilotApiException(
        appL10n.moviepilotApiConnectionError(e.message),
      );
    } on http.ClientException catch (e) {
      _log('_makeRequest: ClientException - ${e.message}');
      throw MoviePilotApiException(
        appL10n.moviepilotApiNetworkError(e.message),
      );
    } on FormatException catch (e) {
      _log('_makeRequest: FormatException - $e');
      throw MoviePilotApiException(appL10n.moviepilotApiUrlFormatError(e));
    }
  }

  /// 释放资源
  void dispose() {
    _client?.close();
    _client = null;
    _isAuthenticated = false;
  }

  Map<String, dynamic> _extractMap(Object? data) {
    if (data is Map<String, dynamic>) {
      final wrapped = data['data'];
      if (wrapped is Map<String, dynamic>) return wrapped;
      if (wrapped is Map) return Map<String, dynamic>.from(wrapped);
      final result = data['result'];
      if (result is Map<String, dynamic>) return result;
      if (result is Map) return Map<String, dynamic>.from(result);
      return data;
    }
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }

  List<dynamic> _extractList(Object? data) {
    if (data is List) return data;
    if (data is Map<Object?, Object?>) {
      for (final key in const ['data', 'items', 'list', 'results', 'rows']) {
        final value = data[key];
        final list = _extractList(value);
        if (list.isNotEmpty || value is List) return list;
      }
    }
    return const [];
  }

  Iterable<Map<String, dynamic>> _extractMaps(Object? data) sync* {
    for (final item in _extractList(data)) {
      if (item is Map<String, dynamic>) {
        yield item;
      } else if (item is Map<Object?, Object?>) {
        yield item.map((key, value) => MapEntry(key.toString(), value));
      }
    }
  }
}

/// MoviePilot API 异常
class MoviePilotApiException implements Exception {
  const MoviePilotApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

String? _asString(Object? value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _asDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

bool? _asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final lower = value.toLowerCase();
    if (lower == 'true' || lower == 'success' || lower == '1') return true;
    if (lower == 'false' ||
        lower == 'fail' ||
        lower == 'failed' ||
        lower == '0') {
      return false;
    }
  }
  return null;
}

DateTime? _asDateTime(Object? value) {
  final text = _asString(value);
  return text == null ? null : DateTime.tryParse(text);
}

/// 系统信息
class MoviePilotSystemInfo {
  const MoviePilotSystemInfo({
    this.version,
    this.frontendVersion,
    this.authVersion,
  });

  factory MoviePilotSystemInfo.fromJson(Map<String, dynamic> json) =>
      MoviePilotSystemInfo(
        version: _asString(json['VERSION'] ?? json['version']),
        frontendVersion: _asString(
          json['FRONTEND_VERSION'] ?? json['frontend_version'],
        ),
        authVersion: _asString(json['AUTH_VERSION'] ?? json['auth_version']),
      );

  final String? version;
  final String? frontendVersion;
  final String? authVersion;
}

/// 订阅
class MoviePilotSubscribe {
  const MoviePilotSubscribe({
    required this.id,
    required this.name,
    required this.type,
    this.tmdbId,
    this.season,
    this.state,
    this.lastUpdate,
  });

  factory MoviePilotSubscribe.fromJson(Map<String, dynamic> json) =>
      MoviePilotSubscribe(
        id: _asInt(json['id'] ?? json['sid']) ?? 0,
        name: _asString(json['name'] ?? json['title']) ?? '',
        type: _asString(json['type'] ?? json['media_type']) ?? '',
        tmdbId: _asInt(json['tmdbid'] ?? json['tmdb_id']),
        season: _asInt(json['season']),
        state: _asString(json['state'] ?? json['status']),
        lastUpdate: _asDateTime(json['last_update'] ?? json['updated_at']),
      );

  final int id;
  final String name;
  final String type;
  final int? tmdbId;
  final int? season;
  final String? state;
  final DateTime? lastUpdate;
}

/// 搜索结果
class MoviePilotSearchResult {
  const MoviePilotSearchResult({
    required this.title,
    this.size,
    this.seeders,
    this.leechers,
    this.downloadUrl,
    this.site,
    this.mediaType,
    this.resolution,
  });

  factory MoviePilotSearchResult.fromJson(Map<String, dynamic> json) =>
      MoviePilotSearchResult(
        title: _asString(json['title'] ?? json['name']) ?? '',
        size: _asInt(json['size']),
        seeders: _asInt(json['seeders'] ?? json['seeds']),
        leechers: _asInt(json['leechers'] ?? json['peers']),
        downloadUrl: _asString(json['enclosure'] ?? json['download_url']),
        site: _asString(json['site'] ?? json['site_name']),
        mediaType: _asString(json['media_type'] ?? json['mtype']),
        resolution: _asString(json['resource_pix'] ?? json['resolution']),
      );

  final String title;
  final int? size;
  final int? seeders;
  final int? leechers;
  final String? downloadUrl;
  final String? site;
  final String? mediaType;
  final String? resolution;
}

/// 下载任务
class MoviePilotDownloadTask {
  const MoviePilotDownloadTask({
    required this.id,
    required this.name,
    this.state,
    this.progress,
    this.size,
    this.speed,
  });

  factory MoviePilotDownloadTask.fromJson(Map<String, dynamic> json) {
    final rawProgress = _asDouble(
      json['progress'] ?? json['percentDone'] ?? json['completed'],
    );
    final progress = rawProgress != null && rawProgress <= 1
        ? rawProgress * 100
        : rawProgress;
    return MoviePilotDownloadTask(
      id: _asString(json['hash'] ?? json['id']) ?? '',
      name: _asString(json['name'] ?? json['title']) ?? '',
      state: _asString(json['state'] ?? json['status']),
      progress: progress,
      size: _asInt(json['size'] ?? json['total_size']),
      speed: _asInt(json['dlspeed'] ?? json['download_speed'] ?? json['speed']),
    );
  }

  final String id;
  final String name;
  final String? state;
  final double? progress;
  final int? size;
  final int? speed;
}

/// 转移历史
class MoviePilotTransferHistory {
  const MoviePilotTransferHistory({
    required this.id,
    required this.title,
    this.type,
    this.sourcePath,
    this.destPath,
    this.transferTime,
    this.success,
  });

  factory MoviePilotTransferHistory.fromJson(Map<String, dynamic> json) =>
      MoviePilotTransferHistory(
        id: _asInt(json['id']) ?? 0,
        title: _asString(json['title'] ?? json['name']) ?? '',
        type: _asString(json['type'] ?? json['media_type']),
        sourcePath: _asString(json['src'] ?? json['source_path']),
        destPath: _asString(json['dest'] ?? json['dest_path']),
        transferTime: _asDateTime(json['date'] ?? json['created_at']),
        success: _asBool(json['status'] ?? json['success']),
      );

  final int id;
  final String title;
  final String? type;
  final String? sourcePath;
  final String? destPath;
  final DateTime? transferTime;
  final bool? success;
}
