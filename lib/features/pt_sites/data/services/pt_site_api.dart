import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/pt_sites/domain/entities/pt_torrent.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';

final _logger = logger;

bool _allowInvalidCertificatesForSource(SourceEntity source) {
  final verifySSL = source.extraConfig?['verifySSL'];
  if (verifySSL is bool) return !verifySSL;
  return false;
}

String _headerNames(Map<String, String> headers) => headers.keys.join(', ');

/// PT 站点 API 基类
abstract class PTSiteApi {
  PTSiteApi({required this.source, http.Client? client})
    : _client = client ?? http.Client();

  final SourceEntity source;
  final http.Client _client;

  /// Whether this implementation can provide transfer history/statistics.
  ///
  /// Generic tracker pages do not expose a stable, portable endpoint for this
  /// data. Implementations must opt in when they have a real parser/API.
  bool get supportsTransferStats => false;

  /// 获取基础 URL
  String get baseUrl {
    // 如果 host 已经包含协议，解析并使用其 scheme 和 host
    if (source.host.startsWith('http://') ||
        source.host.startsWith('https://')) {
      final uri = Uri.parse(source.host);
      final port = source.port == 443 || source.port == 80
          ? ''
          : ':${source.port}';
      return '${uri.scheme}://${uri.host}$port';
    }
    final protocol = source.useSsl ? 'https' : 'http';
    final port = source.port == 443 || source.port == 80
        ? ''
        : ':${source.port}';
    return '$protocol://${source.host}$port';
  }

  /// 获取请求头
  Map<String, String> get headers;

  /// 测试连接
  Future<bool> testConnection();

  /// 获取用户信息
  Future<PTUserInfo> getUserInfo();

  /// 获取种子列表
  Future<List<PTTorrent>> getTorrents({
    int page = 1,
    int pageSize = 50,
    String? category,
    String? keyword,
    PTTorrentSortBy sortBy = PTTorrentSortBy.uploadTime,
    bool descending = true,
  });

  /// 获取种子详情
  Future<PTTorrent> getTorrentDetail(String torrentId);

  /// 获取种子下载链接
  Future<String> getDownloadUrl(String torrentId);

  /// 获取分类列表
  Future<List<PTCategory>> getCategories();

  /// 搜索种子
  Future<List<PTTorrent>> searchTorrents(String keyword, {int page = 1});

  /// 获取传输统计数据
  /// [type] 统计类型（做种/下载/已完成等）
  /// [page] 页码
  Future<PTTransferStats> getTransferStats({
    PTTransferLogType type = PTTransferLogType.all,
    int page = 1,
  });

  /// 关闭连接
  void dispose() {
    _client.close();
  }
}

/// 排序方式
enum PTTorrentSortBy { uploadTime, size, seeders, leechers, snatched, name }

/// 馒头 M-Team API
class MTeamApi extends PTSiteApi {
  MTeamApi({required super.source, super.client})
    : _ioClient = _createIOClient(
        allowInvalidCertificates: _allowInvalidCertificatesForSource(source),
      );

  /// 创建禁用自动重定向的 IOClient，以便更好地处理 302 等状态码
  static http.Client _createIOClient({required bool allowInvalidCertificates}) {
    final httpClient = HttpClient();
    if (allowInvalidCertificates) {
      // ignore: cascade_invocations
      httpClient.badCertificateCallback = (cert, host, port) => true;
    }
    // ignore: cascade_invocations
    httpClient.connectionTimeout = const Duration(seconds: 30);
    // 禁用自动重定向，以便能够检测到 302 等认证问题
    // ignore: cascade_invocations
    httpClient.autoUncompress = true;
    return IOClient(httpClient);
  }

  final http.Client _ioClient;

  @override
  bool get supportsTransferStats => true;

  @override
  Map<String, String> get headers {
    final xApiKey = source.extraConfig?['xApiKey'] as String? ?? '';
    // 获取 userAgent，确保空字符串也使用默认值
    final configUserAgent = source.extraConfig?['userAgent'] as String?;
    final userAgent = (configUserAgent != null && configUserAgent.isNotEmpty)
        ? configUserAgent
        : 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

    // 参考 nas-tools 实现: 只需要 x-api-key，不需要 authorization
    // https://github.com/linyuan0213/nas-tools/blob/master/app/indexer/client/_mteam.py
    return {
      'Content-Type': 'application/json; charset=utf-8',
      'x-api-key': xApiKey,
      'User-Agent': userAgent,
    };
  }

  String get _apiBase => 'https://api.m-team.cc';

  @override
  void dispose() {
    _ioClient.close();
    super.dispose();
  }

  @override
  Future<bool> testConnection() async {
    try {
      // 检查必要的认证信息（只需要 x-api-key）
      final xApiKey = source.extraConfig?['xApiKey'] as String? ?? '';
      final requestHeaders = headers;

      _logger
        ..d(
          'MTeamApi.testConnection: extraConfig keys = '
          '${source.extraConfig?.keys.join(', ') ?? '无'}',
        )
        ..d(
          'MTeamApi.testConnection: API key '
          '${xApiKey.isNotEmpty ? "已配置(${xApiKey.length}字符)" : "未配置"}',
        )
        ..d(
          'MTeamApi.testConnection: header keys = '
          '${_headerNames(requestHeaders)}',
        );

      if (xApiKey.isEmpty) {
        _logger.w('MTeamApi.testConnection: 缺少 x-api-key');
        AppError.ignore(
          Exception(appL10n.ptSiteAuthMissingError),
          StackTrace.current,
          appL10n.ptSiteMTeamApiKeyRequired,
        );
        return false;
      }

      // 使用搜索接口测试连接（不需要 uid 参数）
      // 参考 nas-tools 的实现: https://github.com/linyuan0213/nas-tools
      _logger.i('MTeamApi.testConnection: 开始请求 $_apiBase/api/torrent/search');

      // 构建搜索请求体
      final searchBody = json.encode({
        'mode': 'normal',
        'categories': <String>[],
        'visible': 1,
        'keyword': '',
        'pageNumber': 1,
        'pageSize': 1, // 只获取一条用于测试
      });

      final response = await _ioClient.post(
        Uri.parse('$_apiBase/api/torrent/search'),
        headers: requestHeaders,
        body: searchBody,
      );

      _logger
        ..d('MTeamApi.testConnection: HTTP ${response.statusCode}')
        ..d(
          'MTeamApi.testConnection: response = ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}',
        );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        // 检查 API 返回的状态码（可能是字符串 "0" 或整数 0）
        final code = data['code'];
        if (code == '0' || code == 0 || code == 'SUCCESS') {
          _logger.i('MTeamApi.testConnection: 连接成功');
          return true;
        }
        // API 返回错误
        final message =
            data['message'] as String? ?? appL10n.ptSiteUnknownErrorMessage;
        _logger.w(
          'MTeamApi.testConnection: API 返回错误 - code=$code, message=$message',
        );
        AppError.ignore(
          Exception(appL10n.ptSiteApiResponseError(message)),
          StackTrace.current,
          appL10n.ptSiteMTeamApiError(message),
        );
        return false;
      }

      // HTTP 状态码错误
      _logger.w('MTeamApi.testConnection: HTTP 状态码错误 ${response.statusCode}');

      // 302 重定向通常表示认证信息无效或已过期
      final errorMessage = switch (response.statusCode) {
        302 => appL10n.ptSiteAuthExpiredError,
        401 => appL10n.ptSiteAuthFailedError,
        403 => appL10n.ptSiteAccessDeniedError,
        _ => appL10n.ptSiteHttpStatusError(response.statusCode),
      };

      AppError.ignore(
        Exception(errorMessage),
        StackTrace.current,
        '馒头连接失败: $errorMessage',
      );
      return false;
    } on Exception catch (e, st) {
      _logger.e('MTeamApi.testConnection: 异常 - $e');
      AppError.ignore(e, st, appL10n.ptSiteMTeamTestConnectionFailed);
      return false;
    }
  }

  @override
  Future<PTUserInfo> getUserInfo() async {
    try {
      // /api/member/profile 需要 uid 参数
      // 从 authorization JWT token 解析 uid，或从配置获取
      final uid = _extractUidFromConfig();
      if (uid == null) {
        _logger.w('MTeamApi.getUserInfo: 无法获取 uid，返回空用户信息');
        return const PTUserInfo(username: '', userId: '');
      }

      // M-Team API 需要将 uid 放在 POST body 中，而不是 query parameter
      final response = await _ioClient.post(
        Uri.parse('$_apiBase/api/member/profile'),
        headers: headers,
        body: json.encode({'uid': uid}),
      );

      if (response.statusCode != 200) {
        throw Exception(appL10n.ptSiteGetUserInfoFailed(response.statusCode));
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final code = data['code'];
      if (code != '0' && code != 0 && code != 'SUCCESS') {
        throw Exception(
          data['message'] ?? appL10n.ptSiteGetUserInfoFailedDefault,
        );
      }

      final profile = data['data'] as Map<String, dynamic>;
      final memberCount = profile['memberCount'] as Map<String, dynamic>? ?? {};

      // 调试日志：记录 API 返回的完整数据以便排查问题
      _logger
        ..d('MTeamApi.getUserInfo: profile = $profile')
        ..d('MTeamApi.getUserInfo: memberCount = $memberCount');

      // 用户等级：M-Team 的 role 是数字 ID，需要映射到文字名称
      final userClass = _parseUserClass(profile);

      // 获取做种/下载数 - 需要调用 api/tracker/myPeerStatus 接口
      final peerStatus = await _getPeerStatus(uid);
      _logger.d('MTeamApi.getUserInfo: peerStatus = $peerStatus');

      final seedingCount = peerStatus['seeder'] ?? peerStatus['seeding'] ?? 0;
      final leechingCount =
          peerStatus['leecher'] ?? peerStatus['leeching'] ?? 0;

      return PTUserInfo(
        username: profile['username'] as String? ?? '',
        userId: profile['id']?.toString() ?? '',
        userClass: userClass,
        uploaded: _parseBytes(memberCount['uploaded']),
        downloaded: _parseBytes(memberCount['downloaded']),
        ratio: double.tryParse(memberCount['shareRate']?.toString() ?? ''),
        bonus: double.tryParse(memberCount['bonus']?.toString() ?? '0') ?? 0,
        seedingCount: seedingCount,
        leechingCount: leechingCount,
        // 额外字段
        invites: _parseInt(profile['invites']),
        joinTime: DateTime.tryParse(profile['createdDate']?.toString() ?? ''),
        lastAccess: DateTime.tryParse(
          profile['lastBrowseTime']?.toString() ?? '',
        ),
      );
    } catch (e, st) {
      AppError.handle(e, st, 'MTeamApi.getUserInfo');
      rethrow;
    }
  }

  /// 获取用户做种/下载状态
  /// 调用 api/tracker/myPeerStatus 接口
  Future<Map<String, int>> _getPeerStatus(int uid) async {
    try {
      final response = await _ioClient.post(
        Uri.parse('$_apiBase/api/tracker/myPeerStatus'),
        headers: headers,
        body: json.encode({'uid': uid}),
      );

      if (response.statusCode != 200) {
        _logger.w('_getPeerStatus: HTTP ${response.statusCode}');
        return {};
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final code = data['code'];
      if (code != '0' && code != 0 && code != 'SUCCESS') {
        _logger.w('_getPeerStatus: API 返回错误 - ${data['message']}');
        return {};
      }

      final statusData = data['data'] as Map<String, dynamic>? ?? {};
      _logger.d('_getPeerStatus: statusData = $statusData');

      return {
        'seeder': _parseInt(statusData['seeder']),
        'leecher': _parseInt(statusData['leecher']),
      };
    } on Exception catch (e) {
      _logger.w('_getPeerStatus: 获取失败 - $e');
      return {};
    }
  }

  /// 从配置或 JWT token 中提取 uid
  int? _extractUidFromConfig() {
    // 优先从 extraConfig 获取
    final configUid = source.extraConfig?['uid'];
    if (configUid != null) {
      if (configUid is int) return configUid;
      if (configUid is String) return int.tryParse(configUid);
    }

    // 尝试从 authorization JWT token 解析 uid
    final authorization = source.extraConfig?['authorization'] as String?;
    if (authorization != null && authorization.isNotEmpty) {
      try {
        // JWT 格式: header.payload.signature
        final parts = authorization.split('.');
        if (parts.length == 3) {
          // Base64 解码 payload，补齐 padding
          final payload = parts[1].padRight((parts[1].length + 3) & ~3, '=');
          final decoded = utf8.decode(base64Decode(payload));
          final payloadJson = json.decode(decoded) as Map<String, dynamic>;
          final uid = payloadJson['uid'];
          if (uid is int) return uid;
          if (uid is String) return int.tryParse(uid);
        }
      } on FormatException catch (e) {
        _logger.w('MTeamApi: 解析 JWT token 失败 - $e');
      }
    }

    return null;
  }

  @override
  Future<List<PTTorrent>> getTorrents({
    int page = 1,
    int pageSize = 50,
    String? category,
    String? keyword,
    PTTorrentSortBy sortBy = PTTorrentSortBy.uploadTime,
    bool descending = true,
  }) async {
    try {
      final body = <String, dynamic>{
        'pageNumber': page,
        'pageSize': pageSize,
        'visible': 1,
      };

      if (category != null) {
        body['categories'] = [category];
      }

      if (keyword != null && keyword.isNotEmpty) {
        body['keyword'] = keyword;
        body['mode'] = 'normal';
      }

      // 排序
      final sortField = switch (sortBy) {
        PTTorrentSortBy.uploadTime => 'CREATED_DATE',
        PTTorrentSortBy.size => 'SIZE',
        PTTorrentSortBy.seeders => 'SEEDERS',
        PTTorrentSortBy.leechers => 'LEECHERS',
        PTTorrentSortBy.snatched => 'TIMES_COMPLETED',
        PTTorrentSortBy.name => 'NAME',
      };
      body['sortField'] = sortField;
      body['sortDirection'] = descending ? 'DESC' : 'ASC';

      final response = await _ioClient.post(
        Uri.parse('$_apiBase/api/torrent/search'),
        headers: headers,
        body: json.encode(body),
      );

      if (response.statusCode != 200) {
        throw Exception(
          appL10n.ptSiteGetTorrentListFailed(response.statusCode),
        );
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final code = data['code'];
      // code 可能是字符串 "0" 或整数 0
      if (code != '0' && code != 0 && code != 'SUCCESS') {
        throw Exception(
          data['message'] ?? appL10n.ptSiteGetTorrentListFailedDefault,
        );
      }

      final torrentsData = data['data'] as Map<String, dynamic>? ?? {};
      final list = torrentsData['data'] as List<dynamic>? ?? [];

      return list
          .map((item) => _parseTorrent(item as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      AppError.handle(e, st, 'MTeamApi.getTorrents');
      rethrow;
    }
  }

  @override
  Future<PTTorrent> getTorrentDetail(String torrentId) async {
    try {
      final response = await _ioClient.post(
        Uri.parse('$_apiBase/api/torrent/detail'),
        headers: headers,
        body: json.encode({'id': torrentId}),
      );

      if (response.statusCode != 200) {
        throw Exception(
          appL10n.ptSiteGetTorrentDetailFailed(response.statusCode),
        );
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final code = data['code'];
      if (code != '0' && code != 0 && code != 'SUCCESS') {
        throw Exception(
          data['message'] ?? appL10n.ptSiteGetTorrentDetailFailedDefault,
        );
      }

      return _parseTorrent(data['data'] as Map<String, dynamic>);
    } catch (e, st) {
      AppError.handle(e, st, 'MTeamApi.getTorrentDetail');
      rethrow;
    }
  }

  @override
  Future<String> getDownloadUrl(String torrentId) async {
    try {
      final response = await _ioClient.post(
        Uri.parse('$_apiBase/api/torrent/genDlToken'),
        headers: headers,
        body: json.encode({'id': torrentId}),
      );

      if (response.statusCode != 200) {
        throw Exception(
          appL10n.ptSiteGetDownloadUrlFailed(response.statusCode),
        );
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final code = data['code'];
      if (code != '0' && code != 0 && code != 'SUCCESS') {
        throw Exception(
          data['message'] ?? appL10n.ptSiteGetDownloadUrlFailedDefault,
        );
      }

      return data['data'] as String? ?? '';
    } catch (e, st) {
      AppError.handle(e, st, 'MTeamApi.getDownloadUrl');
      rethrow;
    }
  }

  @override
  Future<List<PTCategory>> getCategories() async => [
    const PTCategory(id: '401', name: '电影/Movie'),
    const PTCategory(id: '404', name: '纪录/Documentary'),
    const PTCategory(id: '405', name: '动漫/Anime'),
    const PTCategory(id: '402', name: '剧集/TV Series'),
    const PTCategory(id: '403', name: '综艺/TV Show'),
    const PTCategory(id: '406', name: '体育/Sports'),
    const PTCategory(id: '407', name: 'MV/Music Video'),
    const PTCategory(id: '408', name: '音乐/Music'),
    const PTCategory(id: '410', name: '软件/Software'),
    const PTCategory(id: '411', name: '学习/Education'),
    const PTCategory(id: '409', name: '其他/Other'),
  ];

  @override
  Future<List<PTTorrent>> searchTorrents(String keyword, {int page = 1}) =>
      getTorrents(keyword: keyword, page: page);

  @override
  Future<PTTransferStats> getTransferStats({
    PTTransferLogType type = PTTransferLogType.all,
    int page = 1,
  }) async {
    try {
      final uid = _extractUidFromConfig();
      if (uid == null) {
        _logger.w('MTeamApi.getTransferStats: 无法获取 uid，返回空统计');
        return const PTTransferStats();
      }

      // 1. 获取做种/下载数统计（从 myPeerStatus）
      final peerStatus = await _getPeerStatus(uid);
      final seedingCount = peerStatus['seeder'] ?? 0;
      final leechingCount = peerStatus['leecher'] ?? 0;

      // 2. 获取用户基本信息（上传/下载量）
      final userInfo = await getUserInfo();

      // 3. 获取种子列表（根据类型筛选）
      final logs = await _getUserTorrentList(uid, type, page);

      return PTTransferStats(
        totalUploaded: userInfo.uploaded,
        totalDownloaded: userInfo.downloaded,
        seedingCount: seedingCount,
        leechingCount: leechingCount,
        logs: logs,
      );
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'MTeamApi.getTransferStats');
      // 降级到从 profile 获取基本数据
      return _getTransferStatsFromProfile(type);
    }
  }

  /// 获取用户种子列表
  /// 调用 api/member/getUserTorrentList 接口
  Future<List<PTTransferLog>> _getUserTorrentList(
    int uid,
    PTTransferLogType type,
    int page,
  ) async {
    try {
      // 根据类型设置过滤条件
      final typeStr = switch (type) {
        PTTransferLogType.seeding => 'SEEDING',
        PTTransferLogType.leeching => 'LEECHING',
        PTTransferLogType.completed => 'COMPLETED',
        PTTransferLogType.hit => 'HITRUN',
        PTTransferLogType.all => 'SEEDING', // 默认显示做种
      };

      final body = {
        'pageNumber': page,
        'pageSize': 50,
        'type': typeStr,
        'userid': uid,
      };

      _logger.d('_getUserTorrentList: 请求参数 = $body');

      final response = await _ioClient.post(
        Uri.parse('$_apiBase/api/member/getUserTorrentList'),
        headers: headers,
        body: json.encode(body),
      );

      if (response.statusCode != 200) {
        _logger.w('_getUserTorrentList: HTTP ${response.statusCode}');
        return [];
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final code = data['code'];
      if (code != '0' && code != 0 && code != 'SUCCESS') {
        _logger.w('_getUserTorrentList: API 返回错误 - ${data['message']}');
        return [];
      }

      final responseData = data['data'] as Map<String, dynamic>?;
      final listData = responseData?['data'] as List<dynamic>? ?? [];
      _logger.d('_getUserTorrentList: 响应数据量 = ${listData.length}');

      return listData
          .whereType<Map<String, dynamic>>()
          .map(_parseTransferLog)
          .toList();
    } on Exception catch (e) {
      _logger.w('_getUserTorrentList: 获取失败 - $e');
      return [];
    }
  }

  /// 从 profile 接口获取基本统计数据（降级方案）
  Future<PTTransferStats> _getTransferStatsFromProfile(
    PTTransferLogType type,
  ) async {
    try {
      final userInfo = await getUserInfo();
      return PTTransferStats(
        totalUploaded: userInfo.uploaded,
        totalDownloaded: userInfo.downloaded,
        seedingCount: userInfo.seedingCount,
        leechingCount: userInfo.leechingCount,
      );
    } on Exception {
      return const PTTransferStats();
    }
  }

  /// 解析单条传输日志（来自 api/member/getUserTorrentList）
  /// 数据结构: { torrent: { id, name, size, ... }, uploaded, downloaded, ... }
  PTTransferLog _parseTransferLog(Map<String, dynamic> data) {
    final torrent = data['torrent'] as Map<String, dynamic>? ?? {};

    // 获取上传/下载量
    final uploaded = _parseBytes(data['uploaded'] ?? torrent['uploaded']);
    final downloaded = _parseBytes(data['downloaded'] ?? torrent['downloaded']);

    // 计算分享率
    double ratio;
    if (data['ratio'] != null) {
      ratio = double.tryParse(data['ratio'].toString()) ?? double.infinity;
    } else if (downloaded > 0) {
      ratio = uploaded / downloaded;
    } else {
      ratio = double.infinity;
    }

    return PTTransferLog(
      torrentId:
          torrent['id']?.toString() ?? data['torrentId']?.toString() ?? '',
      torrentName:
          torrent['name'] as String? ?? data['torrentName'] as String? ?? '',
      uploaded: uploaded,
      downloaded: downloaded,
      ratio: ratio,
      seedTime: _parseInt(data['seedTime'] ?? data['seedingTime'] ?? 0),
      addedTime: DateTime.tryParse(
        data['createdDate']?.toString() ??
            torrent['createdDate']?.toString() ??
            '',
      ),
      lastActive: DateTime.tryParse(
        data['lastModifiedDate']?.toString() ??
            data['lastActive']?.toString() ??
            '',
      ),
      status: data['status']?.toString(),
    );
  }

  PTTorrent _parseTorrent(Map<String, dynamic> data) {
    final status = data['status'] as Map<String, dynamic>? ?? {};

    return PTTorrent(
      id: data['id']?.toString() ?? '',
      name: data['name'] as String? ?? '',
      size: _parseBytes(data['size']),
      seeders: _parseInt(status['seeders']),
      leechers: _parseInt(status['leechers']),
      snatched: _parseInt(status['timesCompleted']),
      uploadTime:
          DateTime.tryParse(data['createdDate'] as String? ?? '') ??
          DateTime.now(),
      category: data['category'] as String?,
      smallDescr: data['smallDescr'] as String?,
      detailUrl: '$baseUrl/detail/${data['id']}',
      imdbId: data['imdb'] as String?,
      doubanId: data['douban'] as String?,
      status: PTTorrentStatus(
        isFree:
            status['discount'] == 'FREE' || status['discount'] == '_2X_FREE',
        isDoubleFree: status['discount'] == '_2X_FREE',
        isHalfDown: status['discount'] == '_50_PERCENT_OFF',
        isDoubleUp: status['discount'] == '_2X_UPLOAD',
        freeEndTime: status['discountEndTime'] != null
            ? DateTime.tryParse(status['discountEndTime'] as String)
            : null,
      ),
      labels: _parseLabels(data),
    );
  }

  List<String> _parseLabels(Map<String, dynamic> data) {
    final labels = <String>[];

    // 解析标签 - 可能是字符串或数组
    final labelsValue = data['labels'];
    if (labelsValue != null) {
      if (labelsValue is String && labelsValue.isNotEmpty) {
        // 如果是字符串，可能是逗号分隔的列表
        labels.addAll(labelsValue.split(',').map((s) => s.trim()));
      } else if (labelsValue is List) {
        for (final label in labelsValue) {
          if (label is String) {
            labels.add(label);
          } else if (label is Map) {
            labels.add(label['name']?.toString() ?? '');
          }
        }
      }
    }

    // 解析编码格式等 - 安全处理可能的非字符串类型
    final videoCodec = data['videoCodec'];
    if (videoCodec != null) labels.add(videoCodec.toString());
    final audioCodec = data['audioCodec'];
    if (audioCodec != null) labels.add(audioCodec.toString());
    final resolution = data['resolution'];
    if (resolution != null) labels.add(resolution.toString());
    final source = data['source'];
    if (source != null) labels.add(source.toString());

    return labels.where((l) => l.isNotEmpty).toList();
  }

  int _parseBytes(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  /// 解析整数值（可能是 int 或 String）
  int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is double) return value.toInt();
    return 0;
  }

  // M-Team 用户等级映射表（来自 MoviePilot）
  static const _mteamRoleMap = {
    '1': 'User',
    '2': 'Power User',
    '3': 'Elite User',
    '4': 'Crazy User',
    '5': 'Insane User',
    '6': 'Veteran User',
    '7': 'Extreme User',
    '8': 'Ultimate User',
    '9': 'Nexus Master',
    '10': 'VIP',
    '11': 'Retiree',
    '12': 'Uploader',
    '13': 'Moderator',
    '14': 'Administrator',
    '15': 'Sysop',
    '16': 'Staff',
    '17': 'Offer memberStaff',
    '18': 'Bet memberStaff',
  };

  /// 解析用户等级
  /// M-Team 的 role 是数字 ID，需要映射到文字名称
  String? _parseUserClass(Map<String, dynamic> profile) {
    final role = profile['role']?.toString();
    if (role == null) return null;

    // 优先使用映射表
    final mappedRole = _mteamRoleMap[role];
    if (mappedRole != null) {
      return mappedRole;
    }

    // 如果 role 本身就是文字（非纯数字），直接返回
    if (int.tryParse(role) == null && role.isNotEmpty) {
      return role;
    }

    // 尝试从 memberStatus 获取
    final memberStatus = profile['memberStatus'] as Map<String, dynamic>?;
    if (memberStatus != null) {
      final statusName =
          memberStatus['name'] ??
          memberStatus['className'] ??
          memberStatus['roleName'];
      if (statusName != null) {
        return statusName.toString();
      }
    }

    return role;
  }
}

/// 通用 PT 站点 API
/// 支持 Cookie 认证和自定义请求头认证
class GenericPTSiteApi extends PTSiteApi {
  GenericPTSiteApi({required super.source, super.client});

  HttpClient _createHttpClient() {
    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    if (_allowInvalidCertificatesForSource(source)) {
      httpClient.badCertificateCallback = (cert, host, port) => true;
    }
    return httpClient;
  }

  @override
  Map<String, String> get headers {
    final authType = source.extraConfig?['authType'] as String? ?? 'Cookie';
    final userAgent =
        source.extraConfig?['userAgent'] as String? ??
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36';

    final result = <String, String>{
      'User-Agent': userAgent,
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    };

    _logger.d('GenericPTSiteApi.headers: authType = $authType');

    if (authType == '自定义请求头') {
      // 使用自定义请求头
      final customHeaders = source.extraConfig?['customHeaders'];
      if (customHeaders is List) {
        for (final header in customHeaders) {
          if (header is Map) {
            final key = header['key']?.toString() ?? '';
            final value = header['value']?.toString() ?? '';
            if (key.isNotEmpty) {
              result[key] = value;
            }
          }
        }
      }
      // 添加 Content-Type（自定义请求头模式通常使用 JSON API）
      result['Content-Type'] = 'application/json';
    } else {
      // Cookie 认证
      final cookie = source.extraConfig?['cookie'] as String? ?? '';
      _logger.d('GenericPTSiteApi.headers: Cookie 长度 = ${cookie.length} 字符');
      if (cookie.isEmpty) {
        _logger.w('GenericPTSiteApi.headers: Cookie 为空！请检查配置');
      } else {
        result['Cookie'] = cookie;
      }
    }

    return result;
  }

  @override
  Future<bool> testConnection() async {
    try {
      // 使用 IOClient 以更好地处理各种 Content-Type
      final httpClient = _createHttpClient();
      final requestHeaders = headers;

      final request = await httpClient.getUrl(Uri.parse(baseUrl));
      requestHeaders.forEach((key, value) {
        request.headers.set(key, value);
      });

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      httpClient.close();

      // 检查是否被重定向到登录页
      return response.statusCode == 200 &&
          !body.contains('login') &&
          !body.contains('登录');
    } on FormatException catch (e, st) {
      // 处理 Content-Type 解析错误（如 "Invalid media type"）
      _logger.w('GenericPTSiteApi.testConnection: 响应格式解析错误 - $e');
      AppError.ignore(e, st, appL10n.ptSiteResponseFormatError);
      return false;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, appL10n.ptSiteTestConnectionFailed);
      return false;
    }
  }

  @override
  Future<PTUserInfo> getUserInfo() async =>
      const PTUserInfo(username: '', userId: '');

  @override
  Future<List<PTTorrent>> getTorrents({
    int page = 1,
    int pageSize = 50,
    String? category,
    String? keyword,
    PTTorrentSortBy sortBy = PTTorrentSortBy.uploadTime,
    bool descending = true,
  }) async {
    try {
      // 构建种子列表 URL (NexusPHP 标准格式)
      final params = <String, String>{
        'page': (page - 1).toString(), // NexusPHP 页码从 0 开始
      };
      if (keyword != null && keyword.isNotEmpty) {
        params['search'] = keyword;
        params['notnewword'] = '1';
      }
      if (category != null) {
        params['cat'] = category;
      }

      // 透传排序参数到 NexusPHP torrents.php 的 sort/type 列号。
      // 列号映射依据 NexusPHP 通用 torrents.php 实现：
      // 1=name 4=added(发布时间) 5=size 6=times_completed 7=seeders 8=leechers。
      // 无法可靠映射的排序项（如部分站点不暴露的列）保持默认排序（按 id 倒序）。
      final sortColumn = _nexusPHPSortColumn(sortBy);
      if (sortColumn != null) {
        params['sort'] = sortColumn;
        params['type'] = descending ? 'desc' : 'asc';
      }

      final uri = Uri.parse(
        '$baseUrl/torrents.php',
      ).replace(queryParameters: params);
      final requestHeaders = headers;
      _logger
        ..d('GenericPTSiteApi.getTorrents: 请求 URL = $uri')
        ..d(
          'GenericPTSiteApi.getTorrents: header keys = '
          '${_headerNames(requestHeaders)}',
        );

      final httpClient = _createHttpClient();

      final request = await httpClient.getUrl(uri);
      requestHeaders.forEach((key, value) {
        request.headers.set(key, value);
      });

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      httpClient.close();

      _logger
        ..d('GenericPTSiteApi.getTorrents: HTTP ${response.statusCode}')
        ..d('GenericPTSiteApi.getTorrents: 响应长度 = ${body.length} 字符');

      if (response.statusCode != 200) {
        _logger.e(
          'GenericPTSiteApi.getTorrents: HTTP 状态错误 ${response.statusCode}',
        );
        throw Exception(
          appL10n.ptSiteGetTorrentListFailed(response.statusCode),
        );
      }

      // 检测是否被重定向到登录页
      if (body.contains('login.php') ||
          body.contains('Please login') ||
          body.contains('class="login"')) {
        _logger.w('GenericPTSiteApi.getTorrents: 检测到登录页面，Cookie 可能已失效');
        return [];
      }

      // 打印响应内容预览（用于调试）
      final preview = body.length > 500 ? body.substring(0, 500) : body;
      _logger.d('GenericPTSiteApi.getTorrents: 响应预览 = $preview');

      // 解析 HTML 获取种子列表
      final torrents = _parseNexusPHPTorrents(body);
      _logger.i('GenericPTSiteApi.getTorrents: 解析到 ${torrents.length} 个种子');

      return torrents;
    } on Exception catch (e, st) {
      _logger.e('GenericPTSiteApi.getTorrents: $e');
      AppError.ignore(e, st, '获取种子列表失败');
      return [];
    }
  }

  /// 解析 NexusPHP 种子列表 HTML
  /// 使用 html 包进行 DOM 解析，支持嵌套标签
  List<PTTorrent> _parseNexusPHPTorrents(String html) {
    final torrents = <PTTorrent>[];

    _logger.d(
      'GenericPTSiteApi._parseNexusPHPTorrents: HTML 长度 = ${html.length} 字符',
    );

    try {
      final document = html_parser.parse(html);

      // 查找种子表格 - NexusPHP 通常使用 class 包含 "torrents" 的表格
      final tables = document.querySelectorAll(
        'table.torrents, table#torrent_table, table[class*="torrent"]',
      );
      _logger.d(
        'GenericPTSiteApi._parseNexusPHPTorrents: 找到 ${tables.length} 个种子表格',
      );

      // 如果没找到特定表格，尝试查找包含 details.php 链接的表格
      var targetTable = tables.isNotEmpty ? tables.first : null;
      if (targetTable == null) {
        final allTables = document.querySelectorAll('table');
        for (final table in allTables) {
          if (table.querySelector('a[href*="details.php"]') != null) {
            targetTable = table;
            _logger.d(
              'GenericPTSiteApi._parseNexusPHPTorrents: 通过 details.php 链接找到表格',
            );
            break;
          }
        }
      }

      if (targetTable == null) {
        _logger.w('GenericPTSiteApi._parseNexusPHPTorrents: 未找到种子表格');
        return torrents;
      }

      // 获取所有行
      final rows = targetTable.querySelectorAll('tr');
      _logger.d(
        'GenericPTSiteApi._parseNexusPHPTorrents: 表格中有 ${rows.length} 行',
      );

      for (final row in rows) {
        // 跳过表头行
        if (row.querySelector('th') != null) continue;

        // 查找详情链接 - 这是识别种子行的关键
        final detailLink = row.querySelector('a[href*="details.php"]');
        if (detailLink == null) continue;

        // 提取种子 ID
        final href = detailLink.attributes['href'] ?? '';
        final idMatch = RegExp(r'id=(\d+)').firstMatch(href);
        if (idMatch == null) continue;
        final id = idMatch.group(1) ?? '';

        // 提取标题 - 使用 text 属性获取所有嵌套文本
        final name = _htmlDecode(detailLink.text.trim());
        if (name.isEmpty) continue;

        // 提取副标题 - 通常在标题链接后面或 br 标签后
        String? smallDescr;
        final torrentNameCell = row.querySelector(
          'td.torrentname, td.embedded, td[class*="name"]',
        );
        if (torrentNameCell != null) {
          // 查找 br 标签后的文本或 class 包含 subtitle 的元素
          final subtitleEl = torrentNameCell.querySelector(
            '.subtitle, .torrent_small, span[title]',
          );
          if (subtitleEl != null) {
            smallDescr = _htmlDecode(subtitleEl.text.trim());
          } else {
            // 尝试获取 br 后的文本节点
            final brEl = torrentNameCell.querySelector('br');
            if (brEl != null && brEl.nextElementSibling != null) {
              smallDescr = _htmlDecode(brEl.nextElementSibling!.text.trim());
            }
          }
        }

        // 提取大小 - 从单元格中查找
        var size = 0;
        final cells = row.querySelectorAll('td');
        for (final cell in cells) {
          final cellText = cell.text;
          final sizeMatch = RegExp(
            r'(\d+(?:\.\d+)?)\s*(GB|MB|KB|TB|GiB|MiB|KiB|TiB)',
            caseSensitive: false,
          ).firstMatch(cellText);
          if (sizeMatch != null) {
            final parsedSize = _parseSize(sizeMatch.group(0) ?? '');
            if (parsedSize > 0) {
              size = parsedSize;
              break;
            }
          }
        }

        // 提取做种/下载/完成数 - 从带有特定 class 或 title 的元素
        var seeders = 0;
        var leechers = 0;
        var snatched = 0;

        // 方法1: 通过 class 名称查找
        final seedersEl = row.querySelector('.seeders, td[class*="seeder"]');
        final leechersEl = row.querySelector('.leechers, td[class*="leecher"]');
        final snatchedEl = row.querySelector(
          '.snatched, td[class*="snatch"], td[class*="times"]',
        );

        if (seedersEl != null) {
          seeders =
              int.tryParse(seedersEl.text.replaceAll(RegExp(r'[^\d]'), '')) ??
              0;
        }
        if (leechersEl != null) {
          leechers =
              int.tryParse(leechersEl.text.replaceAll(RegExp(r'[^\d]'), '')) ??
              0;
        }
        if (snatchedEl != null) {
          snatched =
              int.tryParse(snatchedEl.text.replaceAll(RegExp(r'[^\d]'), '')) ??
              0;
        }

        // 方法2: 通过链接查找 (NexusPHP 常见模式)
        if (seeders == 0) {
          final seedersLink = row.querySelector(
            'a[href*="seeders"], a[title*="做种"], a[title*="seeder"]',
          );
          if (seedersLink != null) {
            seeders =
                int.tryParse(
                  seedersLink.text.replaceAll(RegExp(r'[^\d]'), ''),
                ) ??
                0;
          }
        }
        if (leechers == 0) {
          final leechersLink = row.querySelector(
            'a[href*="leechers"], a[title*="下载"], a[title*="leecher"]',
          );
          if (leechersLink != null) {
            leechers =
                int.tryParse(
                  leechersLink.text.replaceAll(RegExp(r'[^\d]'), ''),
                ) ??
                0;
          }
        }
        if (snatched == 0) {
          final snatchedLink = row.querySelector(
            'a[href*="snatches"], a[title*="完成"], a[title*="snatch"]',
          );
          if (snatchedLink != null) {
            snatched =
                int.tryParse(
                  snatchedLink.text.replaceAll(RegExp(r'[^\d]'), ''),
                ) ??
                0;
          }
        }

        // 方法3: 如果还是没找到，尝试从后三列提取数字
        if (seeders == 0 &&
            leechers == 0 &&
            snatched == 0 &&
            cells.length >= 4) {
          // 通常顺序是: ... 大小, 做种, 下载, 完成
          for (var i = cells.length - 1; i >= cells.length - 4 && i >= 0; i--) {
            final text = cells[i].text.trim();
            final num = int.tryParse(text.replaceAll(RegExp(r'[^\d]'), ''));
            if (num != null && num >= 0) {
              if (i == cells.length - 1) {
                snatched = num;
              } else if (i == cells.length - 2) {
                leechers = num;
              } else if (i == cells.length - 3) {
                seeders = num;
              }
            }
          }
        }

        // 检测免费状态 - 从 class 或 img 元素判断
        final rowHtml = row.outerHtml.toLowerCase();
        final isFree =
            rowHtml.contains('free') ||
            row.querySelector(
                  'img[class*="free"], img[src*="free"], .pro_free',
                ) !=
                null;
        final isDoubleFree =
            rowHtml.contains('2xfree') ||
            rowHtml.contains('twoupfree') ||
            row.querySelector('img[class*="2xfree"], .pro_free2up') != null;
        final isDoubleUp =
            rowHtml.contains('2x') && rowHtml.contains('up') ||
            row.querySelector('img[class*="2xup"], .pro_2up') != null;
        final isHalfDown =
            rowHtml.contains('50%') ||
            rowHtml.contains('halfdown') ||
            row.querySelector('img[class*="50"], .pro_50pctdown') != null;

        torrents.add(
          PTTorrent(
            id: id,
            name: name,
            size: size,
            seeders: seeders,
            leechers: leechers,
            snatched: snatched,
            uploadTime: _parseNexusPHPTime(row),
            smallDescr: (smallDescr?.isNotEmpty ?? false) ? smallDescr : null,
            detailUrl: '$baseUrl/details.php?id=$id',
            status: PTTorrentStatus(
              isFree: isFree || isDoubleFree,
              isDoubleFree: isDoubleFree,
              isDoubleUp: isDoubleUp,
              isHalfDown: isHalfDown,
            ),
          ),
        );
      }

      _logger.i(
        'GenericPTSiteApi._parseNexusPHPTorrents: 成功解析 ${torrents.length} 个种子',
      );
    } on Exception catch (e, st) {
      _logger.w('GenericPTSiteApi._parseNexusPHPTorrents: 解析失败 - $e');
      AppError.ignore(e, st, 'NexusPHP HTML 解析失败');
    }

    return torrents;
  }

  /// 将 [PTTorrentSortBy] 映射到 NexusPHP torrents.php 的 sort 列号。
  /// 返回 null 表示无可靠映射，应保持站点默认排序（零破坏）。
  String? _nexusPHPSortColumn(PTTorrentSortBy sortBy) => switch (sortBy) {
    PTTorrentSortBy.name => '1',
    PTTorrentSortBy.uploadTime => '4', // added
    PTTorrentSortBy.size => '5',
    PTTorrentSortBy.snatched => '6', // times_completed
    PTTorrentSortBy.seeders => '7',
    PTTorrentSortBy.leechers => '8',
  };

  /// 从 NexusPHP 种子行中解析发布时间。
  /// 优先级：
  /// 1. 含绝对时间 (yyyy-MM-dd HH:mm:ss / yyyy-MM-dd HH:mm) 的 span title 属性；
  /// 2. 单元格文本中的绝对时间；
  /// 3. 相对时间（"3天前"、"2小时前"、"5 mins ago" 等）转换为 DateTime；
  /// 解析失败回退 [DateTime.now]（零破坏，不影响列表展示）。
  DateTime _parseNexusPHPTime(html_dom.Element row) {
    try {
      // 1. 优先取语义明确的时间元素 title（timealive 模式：<span title="yyyy-MM-dd HH:mm:ss">3天前</span>）。
      for (final el in row.querySelectorAll('span[title], time[title]')) {
        final abs = _parseAbsoluteDateTime(el.attributes['title'] ?? '');
        if (abs != null) return abs;
      }
      // 1b. 兜底：行内任意带绝对时间 title 的元素（放最后，避免优先命中促销到期等 title）。
      for (final el in row.querySelectorAll('*[title]')) {
        final abs = _parseAbsoluteDateTime(el.attributes['title'] ?? '');
        if (abs != null) return abs;
      }

      // 候选时间单元格：排除种子名/标题列（含 details.php 链接或 name/torrentname class），
      // 避免把片名（如 "13 Hours"、"28 Weeks Later"）误解析为相对时间。
      bool isNameCell(html_dom.Element cell) {
        final cls = (cell.attributes['class'] ?? '').toLowerCase();
        if (cls.contains('name') ||
            cls.contains('torrentname') ||
            cls.contains('embedded')) {
          return true;
        }
        return cell.querySelector('a[href*="details.php"]') != null;
      }

      final timeCells = row
          .querySelectorAll('td')
          .where((c) => !isNameCell(c))
          .toList();

      // 2. 绝对时间（默认显示模式直接渲染 yyyy-MM-dd HH:mm:ss）。
      for (final cell in timeCells) {
        final abs = _parseAbsoluteDateTime(cell.text);
        if (abs != null) return abs;
      }

      // 3. 相对时间解析。
      for (final cell in timeCells) {
        final rel = _parseRelativeTime(cell.text.trim());
        if (rel != null) return rel;
      }
    } on Object catch (e, st) {
      AppError.ignore(e, st, 'NexusPHP 发布时间解析失败');
    }
    // 零破坏回退。
    return DateTime.now();
  }

  /// 从任意文本中提取绝对时间 yyyy-MM-dd HH:mm[:ss]，返回本地时间。
  DateTime? _parseAbsoluteDateTime(String text) {
    final match = RegExp(
      r'(\d{4})-(\d{1,2})-(\d{1,2})[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2}))?',
    ).firstMatch(text);
    if (match == null) return null;
    final year = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    final day = int.tryParse(match.group(3) ?? '');
    final hour = int.tryParse(match.group(4) ?? '');
    final minute = int.tryParse(match.group(5) ?? '');
    final second = int.tryParse(match.group(6) ?? '0') ?? 0;
    if (year == null ||
        month == null ||
        day == null ||
        hour == null ||
        minute == null) {
      return null;
    }
    try {
      return DateTime(year, month, day, hour, minute, second);
    } on Object {
      return null;
    }
  }

  /// 解析相对时间为 DateTime（基于当前时间回推）。
  /// 支持中文（年/月/周/天/日/小时/时/分钟/分/秒）与英文（year/month/week/day/hour/min/sec）。
  /// 形如 "3天前"、"2 小时 30 分钟前"、"5 mins ago"。无法识别返回 null。
  DateTime? _parseRelativeTime(String text) {
    if (text.isEmpty) return null;
    // 必须明显是相对时间，避免把无关数字误判（要求含 前/ago 或时间单位）。
    final lower = text.toLowerCase();
    final looksRelative =
        text.contains('前') ||
        lower.contains('ago') ||
        RegExp(
          r'\d+\s*(年|个?月|周|星期|天|日|小时|时|分钟|分|秒|year|month|week|day|hour|hr|min|sec)',
          caseSensitive: false,
        ).hasMatch(text);
    if (!looksRelative) return null;

    var totalSeconds = 0;
    var matched = false;
    final unitMatches = RegExp(
      r'(\d+)\s*(年|个月|月|周|星期|天|日|小时|时|分钟|分|秒|years?|months?|weeks?|days?|hours?|hrs?|h|mins?|minutes?|m|secs?|seconds?|s)',
      caseSensitive: false,
    ).allMatches(text);

    for (final m in unitMatches) {
      final value = int.tryParse(m.group(1) ?? '');
      final unit = (m.group(2) ?? '').toLowerCase();
      if (value == null) continue;
      final factor = switch (unit) {
        '年' || 'year' || 'years' => 365 * 24 * 3600,
        '个月' || '月' || 'month' || 'months' => 30 * 24 * 3600,
        '周' || '星期' || 'week' || 'weeks' => 7 * 24 * 3600,
        '天' || '日' || 'day' || 'days' => 24 * 3600,
        '小时' || '时' || 'hour' || 'hours' || 'hr' || 'hrs' || 'h' => 3600,
        '分钟' || '分' || 'min' || 'mins' || 'minute' || 'minutes' || 'm' => 60,
        '秒' || 'sec' || 'secs' || 'second' || 'seconds' || 's' => 1,
        _ => 0,
      };
      if (factor > 0) {
        totalSeconds += value * factor;
        matched = true;
      }
    }
    if (!matched) return null;
    return DateTime.now().subtract(Duration(seconds: totalSeconds));
  }

  /// HTML 实体解码
  String _htmlDecode(String text) => text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .trim();

  /// 解析文件大小
  int _parseSize(String sizeStr) {
    if (sizeStr.isEmpty) return 0;
    final match = RegExp(
      r'(\d+(?:\.\d+)?)\s*(GB|MB|KB|TB|GiB|MiB|KiB|TiB)',
      caseSensitive: false,
    ).firstMatch(sizeStr);
    if (match == null) return 0;

    final value = double.tryParse(match.group(1) ?? '0') ?? 0;
    final unit = (match.group(2) ?? '').toUpperCase();

    return switch (unit) {
      'TB' || 'TIB' => (value * 1024 * 1024 * 1024 * 1024).toInt(),
      'GB' || 'GIB' => (value * 1024 * 1024 * 1024).toInt(),
      'MB' || 'MIB' => (value * 1024 * 1024).toInt(),
      'KB' || 'KIB' => (value * 1024).toInt(),
      _ => value.toInt(),
    };
  }

  @override
  Future<PTTorrent> getTorrentDetail(String torrentId) async =>
      throw UnimplementedError(appL10n.ptSiteUnimplementedError);

  @override
  Future<String> getDownloadUrl(String torrentId) async =>
      '$baseUrl/download.php?id=$torrentId';

  @override
  Future<List<PTCategory>> getCategories() async => [];

  @override
  Future<List<PTTorrent>> searchTorrents(String keyword, {int page = 1}) =>
      getTorrents(keyword: keyword, page: page);

  @override
  Future<PTTransferStats> getTransferStats({
    PTTransferLogType type = PTTransferLogType.all,
    int page = 1,
  }) async => throw UnimplementedError(appL10n.ptSiteUnimplementedError);
}

/// PT 站点 API 工厂
class PTSiteApiFactory {
  /// 创建 PT 站点 API 实例
  /// 根据站点类型选择合适的 API 实现
  static PTSiteApi create(SourceEntity source) {
    _logger
      ..d(
        'PTSiteApiFactory.create: source.name = ${source.name}, host = ${source.host}',
      )
      ..d(
        'PTSiteApiFactory.create: extraConfig keys = '
        '${source.extraConfig?.keys.join(', ') ?? '无'}',
      );

    // 判断是否是馒头站点（只检查 host）
    if (_isMTeamSite(source)) {
      _logger.i('PTSiteApiFactory.create: 识别为馒头站点，使用 MTeamApi');

      // 预处理：从 customHeaders 或表单字段提取 API Key
      final preparedSource = _prepareApiKeyConfig(source);
      _logger.d(
        'PTSiteApiFactory.create: 预处理后 extraConfig keys = '
        '${preparedSource.extraConfig?.keys.join(', ') ?? '无'}',
      );

      return MTeamApi(source: preparedSource);
    }

    _logger.i('PTSiteApiFactory.create: 使用通用 GenericPTSiteApi');
    return GenericPTSiteApi(source: source);
  }

  /// 判断是否是馒头站点
  /// 参考 nas-tools：只检查 host 是否包含 m-team
  static bool _isMTeamSite(SourceEntity source) {
    final host = source.host.toLowerCase();
    // 馒头域名特征
    return host.contains('m-team') || host.contains('mteam');
  }

  /// 预处理 API Key 配置
  /// 从 customHeaders 中提取 x-api-key 和 authorization，写入 extraConfig
  static SourceEntity _prepareApiKeyConfig(SourceEntity source) {
    final extraConfig = Map<String, dynamic>.from(source.extraConfig ?? {});

    // 已有的直接配置
    var xApiKey = extraConfig['xApiKey'] as String? ?? '';
    var authorization = extraConfig['authorization'] as String? ?? '';

    // 尝试从 customHeaders 提取
    var customHeaders = extraConfig['customHeaders'];

    // 解析 String 类型的 customHeaders（兼容旧数据）
    if (customHeaders is String && customHeaders.isNotEmpty) {
      _logger.d(
        'PTSiteApiFactory._prepareApiKeyConfig: 解析 String 类型 customHeaders',
      );
      customHeaders = _parseCustomHeadersString(customHeaders);
    }

    if (customHeaders is List) {
      for (final header in customHeaders) {
        if (header is Map) {
          final key = header['key']?.toString().toLowerCase() ?? '';
          final value = header['value']?.toString() ?? '';
          if (key == 'x-api-key' && value.isNotEmpty && xApiKey.isEmpty) {
            xApiKey = value;
            _logger.d(
              'PTSiteApiFactory._prepareApiKeyConfig: 从 customHeaders 提取 x-api-key',
            );
          } else if (key == 'authorization' &&
              value.isNotEmpty &&
              authorization.isEmpty) {
            authorization = value;
            _logger.d(
              'PTSiteApiFactory._prepareApiKeyConfig: 从 customHeaders 提取 authorization',
            );
          }
        }
      }
    }

    // 更新 extraConfig
    if (xApiKey.isNotEmpty) extraConfig['xApiKey'] = xApiKey;
    if (authorization.isNotEmpty) extraConfig['authorization'] = authorization;

    return source.copyWith(extraConfig: extraConfig);
  }

  /// 尝试解析 String 格式的 customHeaders
  static List<Map<String, String>>? _parseCustomHeadersString(String str) {
    if (str.isEmpty) return null;

    // 尝试 JSON 解析
    try {
      final parsed = json.decode(str);
      if (parsed is List) {
        return parsed.map((e) {
          if (e is Map) {
            return Map<String, String>.from(
              e.map((k, v) => MapEntry(k.toString(), v.toString())),
            );
          }
          return <String, String>{};
        }).toList();
      }
    } on FormatException {
      // JSON 解析失败，尝试其他格式
    }

    // 尝试解析 "key: value\nkey2: value2" 格式
    final lines = str.split(RegExp(r'[\n;]'));
    final result = <Map<String, String>>[];
    for (final line in lines) {
      final colonIndex = line.indexOf(':');
      if (colonIndex > 0) {
        final key = line.substring(0, colonIndex).trim();
        final value = line.substring(colonIndex + 1).trim();
        if (key.isNotEmpty && value.isNotEmpty) {
          result.add({'key': key, 'value': value});
        }
      }
    }

    if (result.isNotEmpty) {
      _logger.d(
        'PTSiteApiFactory._parseCustomHeadersString: 解析出 ${result.length} 个 header',
      );
      return result;
    }

    return null;
  }
}
