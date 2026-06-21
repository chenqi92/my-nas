import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:my_nas/core/i18n/app_l10n.dart';

/// Transmission RPC API 客户端
///
/// 支持 Transmission RPC 协议
/// 文档: https://github.com/transmission/transmission/blob/main/docs/rpc-spec.md
class TransmissionApi {
  TransmissionApi({
    required this.baseUrl,
    this.rpcPath = '/transmission/rpc',
    this.username,
    this.password,
  });

  final String baseUrl;
  final String rpcPath;
  final String? username;
  final String? password;

  http.Client? _client;
  String? _sessionId;
  bool _isConnected = false;
  String? _version;
  String? _rpcVersion;

  /// 获取 HTTP 客户端
  http.Client get client {
    _client ??= http.Client();
    return _client!;
  }

  /// 是否已连接
  bool get isConnected => _isConnected;

  /// Transmission 版本
  String? get version => _version;

  /// RPC 版本
  String? get rpcVersion => _rpcVersion;

  /// 构建认证头
  Map<String, String> _buildHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    // 添加 Session ID（CSRF 保护）
    if (_sessionId != null) {
      headers['X-Transmission-Session-Id'] = _sessionId!;
    }

    // 添加 Basic Auth
    if (username != null && password != null) {
      final credentials = base64Encode(utf8.encode('$username:$password'));
      headers['Authorization'] = 'Basic $credentials';
    }

    return headers;
  }

  /// 发起 RPC 请求
  Future<Map<String, dynamic>> _call(
    String method, {
    Map<String, dynamic>? arguments,
  }) async {
    final url = Uri.parse('$baseUrl$rpcPath');

    final body = jsonEncode({
      'method': method,
      'arguments': ?arguments,
    });

    try {
      var response = await client.post(
        url,
        headers: _buildHeaders(),
        body: body,
      );

      // 处理 CSRF 保护（409 响应包含 Session ID）
      if (response.statusCode == 409) {
        _sessionId = response.headers['x-transmission-session-id'];
        if (_sessionId == null) {
          throw TransmissionApiException(appL10n.transmissionApiErrorFailedToGetSessionId);
        }

        // 使用新的 Session ID 重试请求
        response = await client.post(
          url,
          headers: _buildHeaders(),
          body: body,
        );
      }

      if (response.statusCode == 401) {
        throw TransmissionApiException(appL10n.transmissionApiErrorAuthenticationFailed);
      }

      if (response.statusCode != 200) {
        throw TransmissionApiException(appL10n.transmissionApiErrorHttpError(response.statusCode));
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final result = data['result'] as String?;

      if (result != 'success') {
        throw TransmissionApiException(appL10n.transmissionApiErrorOperationFailed(result ?? ''));
      }

      return data['arguments'] as Map<String, dynamic>? ?? {};
    } on SocketException catch (e) {
      throw TransmissionApiException(appL10n.transmissionApiErrorUnableToConnectServer(e.message));
    } on http.ClientException catch (e) {
      throw TransmissionApiException(appL10n.transmissionApiErrorNetworkError(e.message));
    } on FormatException catch (e) {
      throw TransmissionApiException(appL10n.transmissionApiErrorResponseParseFailed(e.message));
    }
  }

  /// 连接到 Transmission（验证连接）
  Future<bool> connect() async {
    try {
      final session = await sessionGet();
      _version = session['version'] as String?;
      _rpcVersion = session['rpc-version']?.toString();
      _isConnected = true;
      return true;
    } on TransmissionApiException {
      _isConnected = false;
      rethrow;
    }
  }

  /// 获取会话信息
  Future<Map<String, dynamic>> sessionGet({List<String>? fields}) async => _call('session-get', arguments: fields != null ? {'fields': fields} : null);

  /// 获取会话统计
  Future<TransmissionSessionStats> sessionStats() async {
    final result = await _call('session-stats');
    return TransmissionSessionStats.fromJson(result);
  }

  /// 获取种子列表
  Future<List<TransmissionTorrent>> torrentGet({
    List<int>? ids,
    List<String>? fields,
  }) async {
    // 默认请求的字段
    final requestFields = fields ??
        [
          'id',
          'name',
          'hashString',
          'status',
          'totalSize',
          'percentDone',
          'rateDownload',
          'rateUpload',
          'downloadedEver',
          'uploadedEver',
          'eta',
          'error',
          'errorString',
          'addedDate',
          'doneDate',
          'downloadDir',
          'isFinished',
          'peersConnected',
        ];

    final arguments = <String, dynamic>{
      'fields': requestFields,
    };

    if (ids != null) {
      arguments['ids'] = ids;
    }

    final result = await _call('torrent-get', arguments: arguments);
    final torrents = result['torrents'] as List<dynamic>? ?? [];

    return torrents
        .map((e) => TransmissionTorrent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 添加种子（通过 URL 或 Magnet 链接）
  Future<TransmissionTorrentAdded> torrentAdd({
    String? filename,
    String? metainfo,
    String? downloadDir,
    bool? paused,
  }) async {
    if (filename == null && metainfo == null) {
      throw TransmissionApiException(appL10n.transmissionApiErrorMissingFilenameOrMetainfo);
    }

    final arguments = <String, dynamic>{};
    if (filename != null) arguments['filename'] = filename;
    if (metainfo != null) arguments['metainfo'] = metainfo;
    if (downloadDir != null) arguments['download-dir'] = downloadDir;
    if (paused != null) arguments['paused'] = paused;

    final result = await _call('torrent-add', arguments: arguments);

    // 检查是否是重复的种子
    if (result.containsKey('torrent-duplicate')) {
      final duplicate = result['torrent-duplicate'] as Map<String, dynamic>;
      return TransmissionTorrentAdded(
        id: duplicate['id'] as int,
        name: duplicate['name'] as String? ?? '',
        hashString: duplicate['hashString'] as String? ?? '',
        isDuplicate: true,
      );
    }

    final added = result['torrent-added'] as Map<String, dynamic>;
    return TransmissionTorrentAdded(
      id: added['id'] as int,
      name: added['name'] as String? ?? '',
      hashString: added['hashString'] as String? ?? '',
      isDuplicate: false,
    );
  }

  /// 开始种子
  Future<void> torrentStart(List<int> ids) async {
    await _call('torrent-start', arguments: {'ids': ids});
  }

  /// 开始所有种子
  Future<void> torrentStartAll() async {
    await _call('torrent-start');
  }

  /// 停止种子
  Future<void> torrentStop(List<int> ids) async {
    await _call('torrent-stop', arguments: {'ids': ids});
  }

  /// 停止所有种子
  Future<void> torrentStopAll() async {
    await _call('torrent-stop');
  }

  /// 删除种子
  Future<void> torrentRemove(List<int> ids, {bool deleteLocalData = false}) async {
    await _call('torrent-remove', arguments: {
      'ids': ids,
      'delete-local-data': deleteLocalData,
    });
  }

  /// 验证种子数据
  Future<void> torrentVerify(List<int> ids) async {
    await _call('torrent-verify', arguments: {'ids': ids});
  }

  /// 重新获取 Tracker
  Future<void> torrentReannounce(List<int> ids) async {
    await _call('torrent-reannounce', arguments: {'ids': ids});
  }

  /// 设置种子属性
  Future<void> torrentSet(List<int> ids, Map<String, dynamic> properties) async {
    final arguments = <String, dynamic>{
      'ids': ids,
      ...properties,
    };
    await _call('torrent-set', arguments: arguments);
  }

  /// 释放资源
  void dispose() {
    _client?.close();
    _client = null;
    _sessionId = null;
    _isConnected = false;
    _version = null;
    _rpcVersion = null;
  }
}

/// Transmission API 异常
class TransmissionApiException implements Exception {
  const TransmissionApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Transmission 会话统计
class TransmissionSessionStats {
  const TransmissionSessionStats({
    required this.activeTorrentCount,
    required this.pausedTorrentCount,
    required this.torrentCount,
    required this.downloadSpeed,
    required this.uploadSpeed,
    this.currentStats,
    this.cumulativeStats,
  });

  factory TransmissionSessionStats.fromJson(Map<String, dynamic> json) =>
      TransmissionSessionStats(
        activeTorrentCount: json['activeTorrentCount'] as int? ?? 0,
        pausedTorrentCount: json['pausedTorrentCount'] as int? ?? 0,
        torrentCount: json['torrentCount'] as int? ?? 0,
        downloadSpeed: json['downloadSpeed'] as int? ?? 0,
        uploadSpeed: json['uploadSpeed'] as int? ?? 0,
        currentStats: json['current-stats'] != null
            ? TransmissionStats.fromJson(
                json['current-stats'] as Map<String, dynamic>,
              )
            : null,
        cumulativeStats: json['cumulative-stats'] != null
            ? TransmissionStats.fromJson(
                json['cumulative-stats'] as Map<String, dynamic>,
              )
            : null,
      );

  final int activeTorrentCount;
  final int pausedTorrentCount;
  final int torrentCount;
  final int downloadSpeed;
  final int uploadSpeed;
  final TransmissionStats? currentStats;
  final TransmissionStats? cumulativeStats;
}

/// Transmission 统计信息
class TransmissionStats {
  const TransmissionStats({
    required this.uploadedBytes,
    required this.downloadedBytes,
    required this.filesAdded,
    required this.sessionCount,
    required this.secondsActive,
  });

  factory TransmissionStats.fromJson(Map<String, dynamic> json) =>
      TransmissionStats(
        uploadedBytes: json['uploadedBytes'] as int? ?? 0,
        downloadedBytes: json['downloadedBytes'] as int? ?? 0,
        filesAdded: json['filesAdded'] as int? ?? 0,
        sessionCount: json['sessionCount'] as int? ?? 0,
        secondsActive: json['secondsActive'] as int? ?? 0,
      );

  final int uploadedBytes;
  final int downloadedBytes;
  final int filesAdded;
  final int sessionCount;
  final int secondsActive;
}

/// Transmission 种子信息
class TransmissionTorrent {
  const TransmissionTorrent({
    required this.id,
    required this.name,
    required this.hashString,
    required this.status,
    required this.totalSize,
    required this.percentDone,
    required this.rateDownload,
    required this.rateUpload,
    this.downloadedEver,
    this.uploadedEver,
    this.eta,
    this.error,
    this.errorString,
    this.addedDate,
    this.doneDate,
    this.downloadDir,
    this.isFinished,
    this.peersConnected,
  });

  factory TransmissionTorrent.fromJson(Map<String, dynamic> json) =>
      TransmissionTorrent(
        id: json['id'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        hashString: json['hashString'] as String? ?? '',
        status: json['status'] as int? ?? 0,
        totalSize: json['totalSize'] as int? ?? 0,
        percentDone: (json['percentDone'] as num?)?.toDouble() ?? 0.0,
        rateDownload: json['rateDownload'] as int? ?? 0,
        rateUpload: json['rateUpload'] as int? ?? 0,
        downloadedEver: json['downloadedEver'] as int?,
        uploadedEver: json['uploadedEver'] as int?,
        eta: json['eta'] as int?,
        error: json['error'] as int?,
        errorString: json['errorString'] as String?,
        addedDate: json['addedDate'] as int?,
        doneDate: json['doneDate'] as int?,
        downloadDir: json['downloadDir'] as String?,
        isFinished: json['isFinished'] as bool?,
        peersConnected: json['peersConnected'] as int?,
      );

  final int id;
  final String name;
  final String hashString;
  final int status;
  final int totalSize;
  final double percentDone;
  final int rateDownload;
  final int rateUpload;
  final int? downloadedEver;
  final int? uploadedEver;
  final int? eta;
  final int? error;
  final String? errorString;
  final int? addedDate;
  final int? doneDate;
  final String? downloadDir;
  final bool? isFinished;
  final int? peersConnected;

  /// 种子状态
  /// 0 = stopped
  /// 1 = checking files
  /// 2 = checking resume data
  /// 3 = downloading queue
  /// 4 = downloading
  /// 5 = seeding queue
  /// 6 = seeding
  TransmissionTorrentStatus get statusEnum => switch (status) {
      0 => TransmissionTorrentStatus.stopped,
      1 => TransmissionTorrentStatus.checkWait,
      2 => TransmissionTorrentStatus.check,
      3 => TransmissionTorrentStatus.downloadWait,
      4 => TransmissionTorrentStatus.download,
      5 => TransmissionTorrentStatus.seedWait,
      6 => TransmissionTorrentStatus.seed,
      _ => TransmissionTorrentStatus.stopped,
    };

  /// 是否正在下载
  bool get isDownloading =>
      status == 4 || status == 3;

  /// 是否正在做种
  bool get isSeeding => status == 6 || status == 5;

  /// 是否已停止
  bool get isStopped => status == 0;

  /// 是否已完成
  bool get isComplete => percentDone >= 1.0;

  /// 是否有错误
  bool get hasError => error != null && error! > 0;
}

/// 种子状态枚举
enum TransmissionTorrentStatus {
  stopped,
  checkWait,
  check,
  downloadWait,
  download,
  seedWait,
  seed,
}

/// 添加种子的结果
class TransmissionTorrentAdded {
  const TransmissionTorrentAdded({
    required this.id,
    required this.name,
    required this.hashString,
    required this.isDuplicate,
  });

  final int id;
  final String name;
  final String hashString;
  final bool isDuplicate;
}
