import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:my_nas/core/i18n/app_l10n.dart';

/// qBittorrent Web API 客户端
///
/// 支持 qBittorrent Web API v2.x
/// 文档: https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API-(qBittorrent-4.1)
class QBittorrentApi {
  QBittorrentApi({
    required this.baseUrl,
    this.username,
    this.password,
    this.apiKey,
  });

  final String baseUrl;
  final String? username;
  final String? password;
  final String? apiKey;

  http.Client? _client;
  String? _sid; // Session ID (Cookie-based auth)
  bool _isAuthenticated = false;

  /// API 版本路径前缀
  static const String apiPrefix = '/api/v2';

  /// 获取 HTTP 客户端
  http.Client get client {
    _client ??= http.Client();
    return _client!;
  }

  /// 是否已认证
  bool get isAuthenticated => _isAuthenticated;

  /// 登录认证
  ///
  /// 支持两种认证方式：
  /// 1. Cookie-based: 使用用户名/密码登录获取 SID
  /// 2. API Key: 使用 Bearer token 认证（v5.2.0+）
  Future<bool> login() async {
    // 如果使用 API Key，直接验证
    if (apiKey != null && apiKey!.isNotEmpty) {
      return _authenticateWithApiKey();
    }

    // Cookie-based 认证
    if (username == null || password == null) {
      throw QBittorrentApiException(appL10n.qbittorrentApiUsernamePasswordMissing);
    }

    final url = Uri.parse('$baseUrl$apiPrefix/auth/login');

    try {
      final response = await client.post(
        url,
        body: {
          'username': username,
          'password': password,
        },
      );

      if (response.statusCode == 200) {
        final body = response.body.toLowerCase();
        if (body == 'ok.' || body == 'ok') {
          // 从响应头获取 SID
          final cookies = response.headers['set-cookie'];
          if (cookies != null) {
            final sidMatch = RegExp('SID=([^;]+)').firstMatch(cookies);
            if (sidMatch != null) {
              _sid = sidMatch.group(1);
            }
          }
          _isAuthenticated = true;
          return true;
        } else if (body == 'fails.') {
          throw QBittorrentApiException(appL10n.qbittorrentApiUsernamePasswordIncorrect);
        }
      } else if (response.statusCode == 403) {
        throw QBittorrentApiException(appL10n.qbittorrentApiIpBlocked);
      }

      throw QBittorrentApiException(appL10n.qbittorrentApiLoginFailed(response.statusCode));
    } on SocketException catch (e) {
      throw QBittorrentApiException(appL10n.qbittorrentApiCannotConnectServer(e.message));
    } on http.ClientException catch (e) {
      throw QBittorrentApiException(appL10n.qbittorrentApiNetworkError(e.message));
    }
  }

  /// 使用 API Key 认证
  ///
  /// qBittorrent v5.2+ 的 API Key 通常以 'qbt_' 开头
  /// 但为了兼容性，我们不强制检查格式，而是直接尝试认证
  Future<bool> _authenticateWithApiKey() async {
    // 基本长度检查（API Key 应该有一定长度）
    if (apiKey!.length < 8) {
      throw QBittorrentApiException(appL10n.qbittorrentApiKeyFormatInvalid);
    }

    // 尝试获取应用版本来验证 API Key
    try {
      final version = await getAppVersion();
      if (version.isNotEmpty) {
        _isAuthenticated = true;
        return true;
      }
    } on QBittorrentApiException {
      throw QBittorrentApiException(appL10n.qbittorrentApiKeyAuthFailed);
    }

    return false;
  }

  /// 登出
  Future<void> logout() async {
    if (!_isAuthenticated) return;

    final url = Uri.parse('$baseUrl$apiPrefix/auth/logout');

    try {
      await _makeRequest('POST', url);
    } finally {
      _isAuthenticated = false;
      _sid = null;
    }
  }

  /// 获取应用版本
  Future<String> getAppVersion() async {
    final url = Uri.parse('$baseUrl$apiPrefix/app/version');
    final response = await _makeRequest('GET', url);
    return response.body;
  }

  /// 获取 API 版本
  Future<String> getApiVersion() async {
    final url = Uri.parse('$baseUrl$apiPrefix/app/webapiVersion');
    final response = await _makeRequest('GET', url);
    return response.body;
  }

  /// 获取所有 Torrent 列表
  Future<List<QBTorrent>> getTorrents({
    String? filter,
    String? category,
    String? tag,
    String? sort,
    bool? reverse,
    int? limit,
    int? offset,
    List<String>? hashes,
  }) async {
    final params = <String, String>{};
    if (filter != null) params['filter'] = filter;
    if (category != null) params['category'] = category;
    if (tag != null) params['tag'] = tag;
    if (sort != null) params['sort'] = sort;
    if (reverse != null) params['reverse'] = reverse.toString();
    if (limit != null) params['limit'] = limit.toString();
    if (offset != null) params['offset'] = offset.toString();
    if (hashes != null) params['hashes'] = hashes.join('|');

    final url = Uri.parse('$baseUrl$apiPrefix/torrents/info')
        .replace(queryParameters: params.isNotEmpty ? params : null);

    final response = await _makeRequest('GET', url);
    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((e) => QBTorrent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取 Torrent 详细属性
  Future<QBTorrentProperties> getTorrentProperties(String hash) async {
    final url = Uri.parse('$baseUrl$apiPrefix/torrents/properties')
        .replace(queryParameters: {'hash': hash});

    final response = await _makeRequest('GET', url);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return QBTorrentProperties.fromJson(data);
  }

  /// 获取 Torrent 的文件列表
  Future<List<QBTorrentFile>> getTorrentFiles(String hash) async {
    final url = Uri.parse('$baseUrl$apiPrefix/torrents/files')
        .replace(queryParameters: {'hash': hash});
    final response = await _makeRequest('GET', url);
    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((e) => QBTorrentFile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 添加 Torrent（通过 URL 或 Magnet 链接）
  Future<void> addTorrentByUrl(
    String url, {
    String? savePath,
    String? category,
    List<String>? tags,
    bool? paused,
    bool? skipChecking,
    String? contentLayout,
    String? rename,
  }) async {
    final apiUrl = Uri.parse('$baseUrl$apiPrefix/torrents/add');

    final fields = <String, String>{
      'urls': url,
    };

    if (savePath != null) fields['savepath'] = savePath;
    if (category != null) fields['category'] = category;
    if (tags != null) fields['tags'] = tags.join(',');
    if (paused != null) fields['paused'] = paused.toString();
    if (skipChecking != null) fields['skip_checking'] = skipChecking.toString();
    if (contentLayout != null) fields['contentLayout'] = contentLayout;
    if (rename != null) fields['rename'] = rename;

    await _makeRequest('POST', apiUrl, body: fields);
  }

  /// 暂停 Torrent
  Future<void> pauseTorrents(List<String> hashes) async {
    final url = Uri.parse('$baseUrl$apiPrefix/torrents/pause');
    await _makeRequest('POST', url, body: {'hashes': hashes.join('|')});
  }

  /// 恢复 Torrent
  Future<void> resumeTorrents(List<String> hashes) async {
    final url = Uri.parse('$baseUrl$apiPrefix/torrents/resume');
    await _makeRequest('POST', url, body: {'hashes': hashes.join('|')});
  }

  /// 删除 Torrent
  Future<void> deleteTorrents(
    List<String> hashes, {
    bool deleteFiles = false,
  }) async {
    final url = Uri.parse('$baseUrl$apiPrefix/torrents/delete');
    await _makeRequest('POST', url, body: {
      'hashes': hashes.join('|'),
      'deleteFiles': deleteFiles.toString(),
    });
  }

  /// 获取全局传输信息
  Future<QBTransferInfo> getTransferInfo() async {
    final url = Uri.parse('$baseUrl$apiPrefix/transfer/info');
    final response = await _makeRequest('GET', url);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return QBTransferInfo.fromJson(data);
  }

  // ============ 分类管理 ============

  /// 获取所有分类
  Future<Map<String, QBCategory>> getCategories() async {
    final url = Uri.parse('$baseUrl$apiPrefix/torrents/categories');
    final response = await _makeRequest('GET', url);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data.map(
      (key, value) => MapEntry(
        key,
        QBCategory.fromJson(value as Map<String, dynamic>),
      ),
    );
  }

  /// 创建分类
  Future<void> createCategory(String category, {String? savePath}) async {
    final url = Uri.parse('$baseUrl$apiPrefix/torrents/createCategory');
    await _makeRequest('POST', url, body: {
      'category': category,
      'savePath': ?savePath,
    });
  }

  /// 删除分类
  Future<void> removeCategories(List<String> categories) async {
    final url = Uri.parse('$baseUrl$apiPrefix/torrents/removeCategories');
    await _makeRequest('POST', url, body: {
      'categories': categories.join('\n'),
    });
  }

  /// 设置 Torrent 分类
  Future<void> setTorrentCategory(List<String> hashes, String category) async {
    final url = Uri.parse('$baseUrl$apiPrefix/torrents/setCategory');
    await _makeRequest('POST', url, body: {
      'hashes': hashes.join('|'),
      'category': category,
    });
  }

  // ============ 标签管理 ============

  /// 获取所有标签
  Future<List<String>> getTags() async {
    final url = Uri.parse('$baseUrl$apiPrefix/torrents/tags');
    final response = await _makeRequest('GET', url);
    final data = jsonDecode(response.body) as List<dynamic>;
    return data.cast<String>();
  }

  /// 创建标签
  Future<void> createTags(List<String> tags) async {
    final url = Uri.parse('$baseUrl$apiPrefix/torrents/createTags');
    await _makeRequest('POST', url, body: {
      'tags': tags.join(','),
    });
  }

  /// 删除标签
  Future<void> deleteTags(List<String> tags) async {
    final url = Uri.parse('$baseUrl$apiPrefix/torrents/deleteTags');
    await _makeRequest('POST', url, body: {
      'tags': tags.join(','),
    });
  }

  /// 添加标签到 Torrent
  Future<void> addTorrentTags(List<String> hashes, List<String> tags) async {
    final url = Uri.parse('$baseUrl$apiPrefix/torrents/addTags');
    await _makeRequest('POST', url, body: {
      'hashes': hashes.join('|'),
      'tags': tags.join(','),
    });
  }

  /// 从 Torrent 移除标签
  Future<void> removeTorrentTags(List<String> hashes, List<String> tags) async {
    final url = Uri.parse('$baseUrl$apiPrefix/torrents/removeTags');
    await _makeRequest('POST', url, body: {
      'hashes': hashes.join('|'),
      'tags': tags.join(','),
    });
  }

  // ============ Torrent 管理 ============

  /// 重命名 Torrent
  Future<void> renameTorrent(String hash, String name) async {
    final url = Uri.parse('$baseUrl$apiPrefix/torrents/rename');
    await _makeRequest('POST', url, body: {
      'hash': hash,
      'name': name,
    });
  }

  /// 设置 Torrent 保存位置
  Future<void> setTorrentLocation(List<String> hashes, String location) async {
    final url = Uri.parse('$baseUrl$apiPrefix/torrents/setLocation');
    await _makeRequest('POST', url, body: {
      'hashes': hashes.join('|'),
      'location': location,
    });
  }

  /// 设置 Torrent 下载限速
  Future<void> setTorrentDlLimit(List<String> hashes, int limit) async {
    final url = Uri.parse('$baseUrl$apiPrefix/torrents/setDownloadLimit');
    await _makeRequest('POST', url, body: {
      'hashes': hashes.join('|'),
      'limit': limit.toString(),
    });
  }

  /// 设置 Torrent 上传限速
  Future<void> setTorrentUpLimit(List<String> hashes, int limit) async {
    final url = Uri.parse('$baseUrl$apiPrefix/torrents/setUploadLimit');
    await _makeRequest('POST', url, body: {
      'hashes': hashes.join('|'),
      'limit': limit.toString(),
    });
  }

  // ============ 全局速度限制 ============

  /// 获取全局下载限速
  Future<int> getGlobalDlLimit() async {
    final url = Uri.parse('$baseUrl$apiPrefix/transfer/downloadLimit');
    final response = await _makeRequest('GET', url);
    return int.tryParse(response.body) ?? 0;
  }

  /// 设置全局下载限速
  Future<void> setGlobalDlLimit(int limit) async {
    final url = Uri.parse('$baseUrl$apiPrefix/transfer/setDownloadLimit');
    await _makeRequest('POST', url, body: {
      'limit': limit.toString(),
    });
  }

  /// 获取全局上传限速
  Future<int> getGlobalUpLimit() async {
    final url = Uri.parse('$baseUrl$apiPrefix/transfer/uploadLimit');
    final response = await _makeRequest('GET', url);
    return int.tryParse(response.body) ?? 0;
  }

  /// 设置全局上传限速
  Future<void> setGlobalUpLimit(int limit) async {
    final url = Uri.parse('$baseUrl$apiPrefix/transfer/setUploadLimit');
    await _makeRequest('POST', url, body: {
      'limit': limit.toString(),
    });
  }

  // ============ 备用速度限制 ============

  /// 获取备用速度限制状态
  Future<bool> getAlternativeSpeedLimitsEnabled() async {
    final url = Uri.parse('$baseUrl$apiPrefix/transfer/speedLimitsMode');
    final response = await _makeRequest('GET', url);
    return response.body == '1';
  }

  /// 切换备用速度限制
  Future<void> toggleAlternativeSpeedLimits() async {
    final url = Uri.parse('$baseUrl$apiPrefix/transfer/toggleSpeedLimitsMode');
    await _makeRequest('POST', url);
  }

  // ============ 应用偏好设置 ============

  /// 获取应用偏好设置
  Future<QBPreferences> getPreferences() async {
    final url = Uri.parse('$baseUrl$apiPrefix/app/preferences');
    final response = await _makeRequest('GET', url);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return QBPreferences.fromJson(data);
  }

  /// 设置应用偏好
  Future<void> setPreferences(Map<String, dynamic> prefs) async {
    final url = Uri.parse('$baseUrl$apiPrefix/app/setPreferences');
    await _makeRequest('POST', url, body: {
      'json': jsonEncode(prefs),
    });
  }

  /// 发起 HTTP 请求
  Future<http.Response> _makeRequest(
    String method,
    Uri url, {
    Map<String, String>? body,
  }) async {
    final headers = <String, String>{};

    // 添加认证信息
    if (apiKey != null && apiKey!.isNotEmpty) {
      // API Key 认证
      headers['Authorization'] = 'Bearer $apiKey';
    } else if (_sid != null) {
      // Cookie-based 认证
      headers['Cookie'] = 'SID=$_sid';
    }

    http.Response response;

    try {
      if (method == 'GET') {
        response = await client.get(url, headers: headers);
      } else if (method == 'POST') {
        response = await client.post(url, headers: headers, body: body);
      } else {
        throw QBittorrentApiException(appL10n.qbittorrentApiHttpMethodUnsupported(method));
      }

      if (response.statusCode == 403) {
        _isAuthenticated = false;
        throw QBittorrentApiException(appL10n.qbittorrentApiAuthExpired);
      }

      if (response.statusCode != 200) {
        throw QBittorrentApiException(
          appL10n.qbittorrentApiRequestFailed(response.statusCode, response.reasonPhrase ?? ''),
        );
      }

      return response;
    } on SocketException catch (e) {
      throw QBittorrentApiException(appL10n.qbittorrentApiCannotConnectServer(e.message));
    } on http.ClientException catch (e) {
      throw QBittorrentApiException(appL10n.qbittorrentApiNetworkError(e.message));
    }
  }

  /// 释放资源
  void dispose() {
    _client?.close();
    _client = null;
    _isAuthenticated = false;
    _sid = null;
  }
}

/// qBittorrent API 异常
class QBittorrentApiException implements Exception {
  const QBittorrentApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Torrent 信息
class QBTorrent {
  const QBTorrent({
    required this.hash,
    required this.name,
    required this.size,
    required this.progress,
    required this.dlSpeed,
    required this.upSpeed,
    required this.state,
    this.category,
    this.tags,
    this.addedOn,
    this.completedOn,
    this.savePath,
    this.eta,
    this.ratio,
    this.downloaded,
    this.uploaded,
    this.numSeeds,
    this.numLeechers,
  });

  factory QBTorrent.fromJson(Map<String, dynamic> json) => QBTorrent(
      hash: json['hash'] as String? ?? '',
      name: json['name'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      dlSpeed: json['dlspeed'] as int? ?? 0,
      upSpeed: json['upspeed'] as int? ?? 0,
      state: json['state'] as String? ?? 'unknown',
      category: json['category'] as String?,
      tags: json['tags'] as String?,
      addedOn: json['added_on'] as int?,
      completedOn: json['completion_on'] as int?,
      savePath: json['save_path'] as String?,
      eta: json['eta'] as int?,
      ratio: (json['ratio'] as num?)?.toDouble(),
      downloaded: json['downloaded'] as int?,
      uploaded: json['uploaded'] as int?,
      numSeeds: json['num_seeds'] as int?,
      numLeechers: json['num_leechs'] as int?,
    );

  final String hash;
  final String name;
  final int size;
  final double progress;
  final int dlSpeed;
  final int upSpeed;
  final String state;
  final String? category;
  final String? tags;
  final int? addedOn;
  final int? completedOn;
  final String? savePath;
  final int? eta;
  final double? ratio;
  final int? downloaded;
  final int? uploaded;
  final int? numSeeds;
  final int? numLeechers;

  /// 是否正在下载
  bool get isDownloading =>
      state == 'downloading' ||
      state == 'stalledDL' ||
      state == 'metaDL' ||
      state == 'forcedDL' ||
      state == 'allocating';

  /// 是否正在上传
  bool get isUploading =>
      state == 'uploading' || state == 'stalledUP' || state == 'forcedUP';

  /// 是否已暂停
  bool get isPaused => state == 'pausedDL' || state == 'pausedUP';

  /// 是否已完成
  bool get isCompleted => progress >= 1.0;

  /// 是否出错
  bool get hasError => state == 'error' || state == 'missingFiles';
}

/// Torrent 详细属性
class QBTorrentProperties {
  const QBTorrentProperties({
    required this.savePath,
    required this.creationDate,
    required this.pieceSize,
    required this.comment,
    required this.totalWasted,
    required this.totalUploaded,
    required this.totalDownloaded,
    required this.upLimit,
    required this.dlLimit,
    required this.timeElapsed,
    required this.seedingTime,
    required this.nbConnections,
    required this.shareRatio,
  });

  factory QBTorrentProperties.fromJson(Map<String, dynamic> json) => QBTorrentProperties(
      savePath: json['save_path'] as String? ?? '',
      creationDate: json['creation_date'] as int? ?? 0,
      pieceSize: json['piece_size'] as int? ?? 0,
      comment: json['comment'] as String? ?? '',
      totalWasted: json['total_wasted'] as int? ?? 0,
      totalUploaded: json['total_uploaded'] as int? ?? 0,
      totalDownloaded: json['total_downloaded'] as int? ?? 0,
      upLimit: json['up_limit'] as int? ?? 0,
      dlLimit: json['dl_limit'] as int? ?? 0,
      timeElapsed: json['time_elapsed'] as int? ?? 0,
      seedingTime: json['seeding_time'] as int? ?? 0,
      nbConnections: json['nb_connections'] as int? ?? 0,
      shareRatio: (json['share_ratio'] as num?)?.toDouble() ?? 0.0,
    );

  final String savePath;
  final int creationDate;
  final int pieceSize;
  final String comment;
  final int totalWasted;
  final int totalUploaded;
  final int totalDownloaded;
  final int upLimit;
  final int dlLimit;
  final int timeElapsed;
  final int seedingTime;
  final int nbConnections;
  final double shareRatio;
}

/// 全局传输信息
class QBTransferInfo {
  const QBTransferInfo({
    required this.dlInfoSpeed,
    required this.dlInfoData,
    required this.upInfoSpeed,
    required this.upInfoData,
    required this.dlRateLimit,
    required this.upRateLimit,
    required this.dhtNodes,
    required this.connectionStatus,
    this.useAltSpeedLimits = false,
  });

  factory QBTransferInfo.fromJson(Map<String, dynamic> json) => QBTransferInfo(
      dlInfoSpeed: json['dl_info_speed'] as int? ?? 0,
      dlInfoData: json['dl_info_data'] as int? ?? 0,
      upInfoSpeed: json['up_info_speed'] as int? ?? 0,
      upInfoData: json['up_info_data'] as int? ?? 0,
      dlRateLimit: json['dl_rate_limit'] as int? ?? 0,
      upRateLimit: json['up_rate_limit'] as int? ?? 0,
      dhtNodes: json['dht_nodes'] as int? ?? 0,
      connectionStatus: json['connection_status'] as String? ?? 'disconnected',
      useAltSpeedLimits: json['use_alt_speed_limits'] as bool? ?? false,
    );

  final int dlInfoSpeed;
  final int dlInfoData;
  final int upInfoSpeed;
  final int upInfoData;
  final int dlRateLimit;
  final int upRateLimit;
  final int dhtNodes;
  final String connectionStatus;
  final bool useAltSpeedLimits;
}

/// 分类信息
class QBCategory {
  const QBCategory({
    required this.name,
    required this.savePath,
  });

  factory QBCategory.fromJson(Map<String, dynamic> json) => QBCategory(
      name: json['name'] as String? ?? '',
      savePath: json['savePath'] as String? ?? '',
    );

  final String name;
  final String savePath;
}

/// 应用偏好设置
/// qBittorrent 单个 Torrent 内的文件。
class QBTorrentFile {
  const QBTorrentFile({
    required this.name,
    required this.size,
    required this.progress,
  });

  factory QBTorrentFile.fromJson(Map<String, dynamic> json) => QBTorrentFile(
        name: json['name'] as String? ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
        progress: (json['progress'] as num?)?.toDouble() ?? 0,
      );

  final String name;
  final int size;
  final double progress; // 0..1
}

class QBPreferences {
  const QBPreferences({
    this.dlLimit = 0,
    this.upLimit = 0,
    this.altDlLimit = 0,
    this.altUpLimit = 0,
    this.schedulerEnabled = false,
    this.savePath = '',
  });

  factory QBPreferences.fromJson(Map<String, dynamic> json) => QBPreferences(
      dlLimit: json['dl_limit'] as int? ?? 0,
      upLimit: json['up_limit'] as int? ?? 0,
      altDlLimit: json['alt_dl_limit'] as int? ?? 0,
      altUpLimit: json['alt_up_limit'] as int? ?? 0,
      schedulerEnabled: json['scheduler_enabled'] as bool? ?? false,
      savePath: json['save_path'] as String? ?? '',
    );

  /// 全局下载限速 (bytes/s)，0 表示无限制
  final int dlLimit;

  /// 全局上传限速 (bytes/s)，0 表示无限制
  final int upLimit;

  /// 备用下载限速 (bytes/s)
  final int altDlLimit;

  /// 备用上传限速 (bytes/s)
  final int altUpLimit;

  /// 是否启用计划任务
  final bool schedulerEnabled;

  /// 默认保存路径
  final String savePath;
}
