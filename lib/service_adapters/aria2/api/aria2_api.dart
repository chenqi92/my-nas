import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:my_nas/core/i18n/app_l10n.dart';

/// Aria2 JSON-RPC API 客户端
///
/// 支持 Aria2 JSON-RPC 2.0 接口
/// 文档: https://aria2.github.io/manual/en/html/aria2c.html#rpc-interface
class Aria2Api {
  Aria2Api({
    required this.baseUrl,
    this.rpcSecret,
  });

  final String baseUrl;
  final String? rpcSecret;

  http.Client? _client;
  int _requestId = 0;
  bool _isConnected = false;
  String? _version;

  /// JSON-RPC 路径
  static const String jsonRpcPath = '/jsonrpc';

  /// 获取 HTTP 客户端
  http.Client get client {
    _client ??= http.Client();
    return _client!;
  }

  /// 是否已连接
  bool get isConnected => _isConnected;

  /// Aria2 版本
  String? get version => _version;

  /// 生成带 token 前缀的参数列表
  List<dynamic> _buildParams([List<dynamic>? params]) {
    final result = <dynamic>[];
    if (rpcSecret != null && rpcSecret!.isNotEmpty) {
      result.add('token:$rpcSecret');
    }
    if (params != null) {
      result.addAll(params);
    }
    return result;
  }

  /// 发起 JSON-RPC 请求
  Future<dynamic> _call(String method, [List<dynamic>? params]) async {
    final url = Uri.parse('$baseUrl$jsonRpcPath');
    final id = '${++_requestId}';

    final body = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': _buildParams(params),
    });

    try {
      final response = await client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode != 200) {
        throw Aria2ApiException(appL10n.aria2ApiHttpError(response.statusCode));
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data.containsKey('error')) {
        final error = data['error'] as Map<String, dynamic>;
        throw Aria2ApiException(
          error['message'] as String? ?? appL10n.aria2ApiUnknownError,
          code: error['code'] as int?,
        );
      }

      return data['result'];
    } on SocketException catch (e) {
      throw Aria2ApiException(appL10n.aria2ApiCannotConnectServer(e.message));
    } on http.ClientException catch (e) {
      throw Aria2ApiException(appL10n.aria2ApiNetworkError(e.message));
    } on FormatException catch (e) {
      throw Aria2ApiException(appL10n.aria2ApiResponseParseError(e.message));
    }
  }

  /// 连接到 Aria2（验证连接）
  Future<bool> connect() async {
    try {
      final versionInfo = await getVersion();
      _version = versionInfo.version;
      _isConnected = true;
      return true;
    } on Aria2ApiException {
      _isConnected = false;
      rethrow;
    }
  }

  /// 获取版本信息
  Future<Aria2VersionInfo> getVersion() async {
    final result = await _call('aria2.getVersion') as Map<String, dynamic>;
    return Aria2VersionInfo.fromJson(result);
  }

  /// 获取全局统计信息
  Future<Aria2GlobalStat> getGlobalStat() async {
    final result = await _call('aria2.getGlobalStat') as Map<String, dynamic>;
    return Aria2GlobalStat.fromJson(result);
  }

  /// 添加 URI 下载
  ///
  /// [uris] URI 列表（HTTP/FTP/Magnet 等）
  /// [options] 下载选项
  /// [position] 队列位置
  ///
  /// 返回下载的 GID
  Future<String> addUri(
    List<String> uris, {
    Map<String, dynamic>? options,
    int? position,
  }) async {
    final params = <dynamic>[uris];
    if (options != null) {
      params.add(options);
    }
    if (position != null) {
      if (options == null) params.add(<String, dynamic>{});
      params.add(position);
    }

    final result = await _call('aria2.addUri', params) as String;
    return result;
  }

  /// 添加种子下载（Base64 编码的种子文件）
  Future<String> addTorrent(
    String torrentBase64, {
    List<String>? uris,
    Map<String, dynamic>? options,
    int? position,
  }) async {
    final params = <dynamic>[torrentBase64];
    if (uris != null) {
      params.add(uris);
    } else {
      params.add(<String>[]);
    }
    if (options != null) {
      params.add(options);
    }
    if (position != null) {
      if (options == null) params.add(<String, dynamic>{});
      params.add(position);
    }

    final result = await _call('aria2.addTorrent', params) as String;
    return result;
  }

  /// 获取下载状态
  Future<Aria2Download> tellStatus(String gid, {List<String>? keys}) async {
    final params = <dynamic>[gid];
    if (keys != null) {
      params.add(keys);
    }

    final result = await _call('aria2.tellStatus', params) as Map<String, dynamic>;
    return Aria2Download.fromJson(result);
  }

  /// 获取活动下载列表
  Future<List<Aria2Download>> tellActive({List<String>? keys}) async {
    final params = <dynamic>[];
    if (keys != null) {
      params.add(keys);
    }

    final result = await _call('aria2.tellActive', params) as List<dynamic>;
    return result
        .map((e) => Aria2Download.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取等待下载列表
  Future<List<Aria2Download>> tellWaiting(
    int offset,
    int num, {
    List<String>? keys,
  }) async {
    final params = <dynamic>[offset, num];
    if (keys != null) {
      params.add(keys);
    }

    final result = await _call('aria2.tellWaiting', params) as List<dynamic>;
    return result
        .map((e) => Aria2Download.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取已停止下载列表
  Future<List<Aria2Download>> tellStopped(
    int offset,
    int num, {
    List<String>? keys,
  }) async {
    final params = <dynamic>[offset, num];
    if (keys != null) {
      params.add(keys);
    }

    final result = await _call('aria2.tellStopped', params) as List<dynamic>;
    return result
        .map((e) => Aria2Download.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 暂停下载
  Future<String> pause(String gid) async {
    final result = await _call('aria2.pause', [gid]) as String;
    return result;
  }

  /// 强制暂停下载
  Future<String> forcePause(String gid) async {
    final result = await _call('aria2.forcePause', [gid]) as String;
    return result;
  }

  /// 暂停所有下载
  Future<String> pauseAll() async {
    final result = await _call('aria2.pauseAll') as String;
    return result;
  }

  /// 恢复下载
  Future<String> unpause(String gid) async {
    final result = await _call('aria2.unpause', [gid]) as String;
    return result;
  }

  /// 恢复所有下载
  Future<String> unpauseAll() async {
    final result = await _call('aria2.unpauseAll') as String;
    return result;
  }

  /// 删除下载
  Future<String> remove(String gid) async {
    final result = await _call('aria2.remove', [gid]) as String;
    return result;
  }

  /// 强制删除下载
  Future<String> forceRemove(String gid) async {
    final result = await _call('aria2.forceRemove', [gid]) as String;
    return result;
  }

  /// 删除下载结果（从已停止列表中移除）
  Future<String> removeDownloadResult(String gid) async {
    final result = await _call('aria2.removeDownloadResult', [gid]) as String;
    return result;
  }

  /// 清除所有已完成/错误/已移除的下载
  Future<String> purgeDownloadResult() async {
    final result = await _call('aria2.purgeDownloadResult') as String;
    return result;
  }

  /// 释放资源
  void dispose() {
    _client?.close();
    _client = null;
    _isConnected = false;
    _version = null;
  }
}

/// Aria2 API 异常
class Aria2ApiException implements Exception {
  const Aria2ApiException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() => message;
}

/// Aria2 版本信息
class Aria2VersionInfo {
  const Aria2VersionInfo({
    required this.version,
    required this.enabledFeatures,
  });

  factory Aria2VersionInfo.fromJson(Map<String, dynamic> json) =>
      Aria2VersionInfo(
        version: json['version'] as String? ?? '',
        enabledFeatures: (json['enabledFeatures'] as List<dynamic>?)
                ?.cast<String>() ??
            [],
      );

  final String version;
  final List<String> enabledFeatures;
}

/// Aria2 全局统计信息
class Aria2GlobalStat {
  const Aria2GlobalStat({
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.numActive,
    required this.numWaiting,
    required this.numStopped,
    required this.numStoppedTotal,
  });

  factory Aria2GlobalStat.fromJson(Map<String, dynamic> json) =>
      Aria2GlobalStat(
        downloadSpeed: int.tryParse(json['downloadSpeed'] as String? ?? '0') ?? 0,
        uploadSpeed: int.tryParse(json['uploadSpeed'] as String? ?? '0') ?? 0,
        numActive: int.tryParse(json['numActive'] as String? ?? '0') ?? 0,
        numWaiting: int.tryParse(json['numWaiting'] as String? ?? '0') ?? 0,
        numStopped: int.tryParse(json['numStopped'] as String? ?? '0') ?? 0,
        numStoppedTotal:
            int.tryParse(json['numStoppedTotal'] as String? ?? '0') ?? 0,
      );

  final int downloadSpeed;
  final int uploadSpeed;
  final int numActive;
  final int numWaiting;
  final int numStopped;
  final int numStoppedTotal;
}

/// Aria2 下载信息
class Aria2Download {
  const Aria2Download({
    required this.gid,
    required this.status,
    required this.totalLength,
    required this.completedLength,
    required this.uploadLength,
    required this.downloadSpeed,
    required this.uploadSpeed,
    this.errorCode,
    this.errorMessage,
    this.dir,
    this.files,
    this.bittorrent,
  });

  factory Aria2Download.fromJson(Map<String, dynamic> json) => Aria2Download(
        gid: json['gid'] as String? ?? '',
        status: json['status'] as String? ?? 'unknown',
        totalLength:
            int.tryParse(json['totalLength'] as String? ?? '0') ?? 0,
        completedLength:
            int.tryParse(json['completedLength'] as String? ?? '0') ?? 0,
        uploadLength:
            int.tryParse(json['uploadLength'] as String? ?? '0') ?? 0,
        downloadSpeed:
            int.tryParse(json['downloadSpeed'] as String? ?? '0') ?? 0,
        uploadSpeed:
            int.tryParse(json['uploadSpeed'] as String? ?? '0') ?? 0,
        errorCode: json['errorCode'] as String?,
        errorMessage: json['errorMessage'] as String?,
        dir: json['dir'] as String?,
        files: (json['files'] as List<dynamic>?)
            ?.map((e) => Aria2File.fromJson(e as Map<String, dynamic>))
            .toList(),
        bittorrent: json['bittorrent'] != null
            ? Aria2BittorrentInfo.fromJson(
                json['bittorrent'] as Map<String, dynamic>,
              )
            : null,
      );

  final String gid;
  final String status;
  final int totalLength;
  final int completedLength;
  final int uploadLength;
  final int downloadSpeed;
  final int uploadSpeed;
  final String? errorCode;
  final String? errorMessage;
  final String? dir;
  final List<Aria2File>? files;
  final Aria2BittorrentInfo? bittorrent;

  /// 获取下载名称
  String get name {
    // 优先使用 BT 名称
    if (bittorrent?.info?.name != null) {
      return bittorrent!.info!.name!;
    }
    // 否则使用第一个文件的路径
    if (files != null && files!.isNotEmpty) {
      final path = files!.first.path;
      if (path.isNotEmpty) {
        return path.split('/').last;
      }
    }
    return gid;
  }

  /// 下载进度 (0.0 - 1.0)
  double get progress {
    if (totalLength == 0) return 0;
    return completedLength / totalLength;
  }

  /// 是否正在下载
  bool get isActive => status == 'active';

  /// 是否已暂停
  bool get isPaused => status == 'paused';

  /// 是否等待中
  bool get isWaiting => status == 'waiting';

  /// 是否已完成
  bool get isComplete => status == 'complete';

  /// 是否出错
  bool get hasError => status == 'error';

  /// 是否已移除
  bool get isRemoved => status == 'removed';
}

/// Aria2 文件信息
class Aria2File {
  const Aria2File({
    required this.index,
    required this.path,
    required this.length,
    required this.completedLength,
    required this.selected,
  });

  factory Aria2File.fromJson(Map<String, dynamic> json) => Aria2File(
        index: json['index'] as String? ?? '0',
        path: json['path'] as String? ?? '',
        length: int.tryParse(json['length'] as String? ?? '0') ?? 0,
        completedLength:
            int.tryParse(json['completedLength'] as String? ?? '0') ?? 0,
        selected: json['selected'] == 'true',
      );

  final String index;
  final String path;
  final int length;
  final int completedLength;
  final bool selected;
}

/// Aria2 BT 信息
class Aria2BittorrentInfo {
  const Aria2BittorrentInfo({
    this.announceList,
    this.comment,
    this.creationDate,
    this.mode,
    this.info,
  });

  factory Aria2BittorrentInfo.fromJson(Map<String, dynamic> json) =>
      Aria2BittorrentInfo(
        announceList: json['announceList'] as List<dynamic>?,
        comment: json['comment'] as String?,
        creationDate: json['creationDate'] as int?,
        mode: json['mode'] as String?,
        info: json['info'] != null
            ? Aria2BtInfo.fromJson(json['info'] as Map<String, dynamic>)
            : null,
      );

  final List<dynamic>? announceList;
  final String? comment;
  final int? creationDate;
  final String? mode;
  final Aria2BtInfo? info;
}

/// Aria2 BT Info
class Aria2BtInfo {
  const Aria2BtInfo({this.name});

  factory Aria2BtInfo.fromJson(Map<String, dynamic> json) => Aria2BtInfo(
        name: json['name'] as String?,
      );

  final String? name;
}
