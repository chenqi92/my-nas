import 'dart:async';
import 'dart:io';

import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

/// 投屏媒体代理服务器
/// 为投屏设备提供HTTP访问NAS文件的能力
class CastMediaProxyServer {
  CastMediaProxyServer({
    this.port = 8899,
  });

  /// 服务器端口
  final int port;

  /// 已绑定的监听套接字（loopback + 当前 LAN 地址）
  final List<HttpServer> _servers = [];

  /// 是否正在运行
  bool get isRunning => _servers.isNotEmpty;

  /// 当前已绑定的 LAN 地址，网络切换后用于判断是否需要重新绑定
  String? _boundLanIp;

  /// 注册的媒体流
  final Map<String, _StreamRegistration> _streams = {};

  /// 本机 IP 地址缓存
  String? _localIp;

  /// IP 地址缓存时间
  DateTime? _localIpCachedAt;

  /// IP 地址缓存有效期（5分钟）
  static const _ipCacheDuration = Duration(minutes: 5);

  /// 自动清理定时器
  Timer? _cleanupTimer;

  /// 获取本机 IP（带缓存过期检查）
  Future<String?> getLocalIp({bool forceRefresh = false}) async {
    // 检查缓存是否有效
    final isCacheValid = _localIp != null &&
        _localIpCachedAt != null &&
        DateTime.now().difference(_localIpCachedAt!) < _ipCacheDuration;

    if (!forceRefresh && isCacheValid) {
      return _localIp;
    }

    try {
      // getWifiIP 在有线连接 / 桌面端可能返回 null 或抛插件异常，回退到枚举网卡
      final wifiIp = await AppError.guard(
        () => NetworkInfo().getWifiIP(),
        action: 'getWifiIP',
      );
      _localIp = wifiIp ?? await _firstPrivateIpv4();
      _localIpCachedAt = DateTime.now();
      return _localIp;
    } catch (e, st) {
      AppError.handle(e, st, 'getLocalIp');
      return null;
    }
  }

  /// 枚举网卡取第一个私有网段 IPv4（有线连接下 getWifiIP 会返回 null）
  Future<String?> _firstPrivateIpv4() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );

    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (_isPrivateIpv4(address.address)) return address.address;
      }
    }
    return null;
  }

  /// 判断是否为 RFC1918 私有地址（只在局域网内暴露代理）
  bool _isPrivateIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    if (first == null || second == null) return false;
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }

  /// 清除 IP 缓存（网络变化时调用）
  void clearIpCache() {
    _localIp = null;
    _localIpCachedAt = null;
  }

  /// 启动服务器
  Future<void> start() async {
    if (isRunning) {
      logger.i('投屏代理服务器已在运行');
      return;
    }

    final router = Router()
      // 媒体流路由
      ..get('/stream/<token>', _handleStreamRequest)
      ..head('/stream/<token>', _handleStreamHeadRequest)
      // 字幕路由
      ..get('/subtitle/<token>', _handleSubtitleRequest)
      ..head('/subtitle/<token>', _handleSubtitleHeadRequest)
      // 健康检查
      ..get('/health', _handleHealthRequest);

    // CORS 中间件
    shelf.Handler corsHandler(shelf.Handler innerHandler) => (request) async {
        // 处理 OPTIONS 预检请求
        if (request.method == 'OPTIONS') {
          return shelf.Response.ok(
            '',
            headers: _corsHeaders,
          );
        }

        final response = await innerHandler(request);
        return response.change(headers: _corsHeaders);
      };

    // 不加 shelf.logRequests()：请求行包含 URL 中的 token（LAN 代理访问凭据），
    // 会被 logger 落盘到 app.log。
    final handler = const shelf.Pipeline()
        .addMiddleware(corsHandler)
        .addHandler(router.call);

    try {
      // 只绑定 loopback + 当前 LAN 地址，不用 InternetAddress.anyIPv4：
      // anyIPv4 会在所有网卡（含 VPN / 热点 / 公网网卡）上监听。
      final lanIp = await getLocalIp();
      final addresses = <InternetAddress>[InternetAddress.loopbackIPv4];
      if (lanIp != null) {
        final lanAddress = InternetAddress.tryParse(lanIp);
        if (lanAddress != null) addresses.add(lanAddress);
      }

      for (final address in addresses) {
        _servers.add(
          await shelf_io.serve(handler, address, port, shared: true),
        );
      }
      _boundLanIp = lanIp;

      // 启动自动清理定时器（每30分钟清理一次过期流）
      _cleanupTimer = Timer.periodic(
        const Duration(minutes: 30),
        (_) => cleanupExpiredStreams(),
      );

      if (lanIp == null) {
        logger.w('投屏代理服务器仅绑定 loopback：未取到局域网 IPv4 地址');
      } else {
        logger.i('投屏代理服务器启动成功，已绑定 loopback 与局域网地址，端口 $port');
      }
    } catch (e, st) {
      // 部分地址绑定成功时要回收，避免端口悬挂
      await _closeServers();
      AppError.handle(e, st, 'startCastProxyServer');
      rethrow;
    }
  }

  /// 健康检查（不泄露主机名/路径等信息）
  shelf.Response _handleHealthRequest(shelf.Request request) =>
      shelf.Response.ok('OK');

  /// CORS 响应头
  ///
  /// 不下发 `Access-Control-Allow-Origin`：DLNA / AirPlay 设备不是浏览器，不走
  /// 同源策略；给 `*` 只会让局域网内任意网页脚本能读取代理响应内容。
  static const _corsHeaders = <String, String>{
    'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
    'Access-Control-Allow-Headers': 'Range, Content-Type',
    'Access-Control-Expose-Headers': 'Content-Length, Content-Range, Accept-Ranges',
  };

  /// 确保服务器运行
  ///
  /// 网络切换后 LAN 地址会变，此时重新绑定，否则投屏 URL 指向已失效的地址。
  Future<void> ensureRunning() async {
    if (!isRunning) {
      await start();
      return;
    }

    final currentIp = await getLocalIp(forceRefresh: true);
    if (currentIp != _boundLanIp) {
      logger.i('局域网地址变化，重新绑定投屏代理服务器');
      await _closeServers();
      _cleanupTimer?.cancel();
      _cleanupTimer = null;
      await start();
    }
  }

  /// 关闭所有监听套接字（保留已注册的流）
  Future<void> _closeServers() async {
    for (final server in _servers) {
      await AppError.guard(
        () => server.close(force: true),
        action: 'closeCastProxyServer',
      );
    }
    _servers.clear();
    _boundLanIp = null;
  }

  /// 停止服务器
  Future<void> stop() async {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;

    if (!isRunning) return;

    await _closeServers();
    _streams.clear();
    clearIpCache();
    logger.i('投屏代理服务器已停止');
  }

  /// 注册媒体流
  /// 返回访问 token
  ///
  /// [createdAt] 仅用于测试注入注册时间以验证 token 时效，生产代码不要传。
  String registerStream({
    required String path,
    required NasFileSystem fileSystem,
    String? mimeType,
    int? fileSize,
    String? subtitlePath,
    DateTime? createdAt,
  }) {
    final token = const Uuid().v4();

    _streams[token] = _StreamRegistration(
      path: path,
      fileSystem: fileSystem,
      mimeType: mimeType ?? _getMimeType(path),
      fileSize: fileSize,
      subtitlePath: subtitlePath,
      createdAt: createdAt ?? DateTime.now(),
    );

    // 不记录 token：它是 LAN 代理的访问凭据，日志会落盘到 app.log。
    logger.i('注册媒体流: path=$path');
    return token;
  }

  /// 注销媒体流
  void unregisterStream(String token) {
    _streams.remove(token);
    logger.i('注销媒体流，剩余 ${_streams.length} 个');
  }

  /// 获取媒体流 URL
  Future<String?> getStreamUrl(String token) async {
    final localIp = await getLocalIp();
    if (localIp == null) return null;
    return 'http://$localIp:$port/stream/$token';
  }

  /// 获取字幕 URL
  Future<String?> getSubtitleUrl(String token) async {
    final registration = _streams[token];
    if (registration?.subtitlePath == null) return null;

    final localIp = await getLocalIp();
    if (localIp == null) return null;
    return 'http://$localIp:$port/subtitle/$token';
  }

  /// token 有效期：与 [cleanupExpiredStreams] 默认值一致
  static const _tokenMaxAge = Duration(hours: 2);

  /// 按 token 取注册信息，超期视为无效并立即移除
  ///
  /// 定时清理每 30 分钟才跑一次，中间窗口内过期 token 仍可用，所以每次请求都校验。
  _StreamRegistration? _resolveRegistration(String? token) {
    if (token == null) return null;

    final registration = _streams[token];
    if (registration == null) return null;

    if (DateTime.now().difference(registration.createdAt) > _tokenMaxAge) {
      _streams.remove(token);
      logger.w('投屏 token 已过期，拒绝请求');
      return null;
    }

    return registration;
  }

  /// 处理媒体流请求
  Future<shelf.Response> _handleStreamRequest(shelf.Request request) async {
    final token = request.params['token'];
    final registration = _resolveRegistration(token);
    if (registration == null) {
      return shelf.Response.notFound('Stream not found');
    }

    try {
      // 解析 Range 请求头
      final rangeHeader = request.headers['range'];
      FileRange? range;

      if (rangeHeader != null) {
        range = _parseRangeHeader(rangeHeader, registration.fileSize);
      }

      // 获取文件流
      final stream = await registration.fileSystem.getFileStream(
        registration.path,
        range: range,
      );

      // 构建响应头
      final headers = <String, String>{
        'Content-Type': registration.mimeType,
        'Accept-Ranges': 'bytes',
      };

      // 处理 Range 响应
      if (range != null && registration.fileSize != null) {
        final start = range.start;
        final end = range.end ?? registration.fileSize! - 1;
        final length = end - start + 1;

        headers['Content-Range'] = 'bytes $start-$end/${registration.fileSize}';
        headers['Content-Length'] = length.toString();

        return shelf.Response(
          206, // Partial Content
          body: stream,
          headers: headers,
        );
      }

      // 完整响应
      if (registration.fileSize != null) {
        headers['Content-Length'] = registration.fileSize.toString();
      }

      return shelf.Response.ok(
        stream,
        headers: headers,
      );
    } catch (e, st) {
      // 不把 token 写进 extraData：它是访问凭据，会落盘到 app.log
      AppError.handle(e, st, 'handleStreamRequest', {'path': registration.path});
      return shelf.Response.internalServerError(body: 'Error streaming file: $e');
    }
  }

  /// 处理媒体流 HEAD 请求（DLNA 设备经常先发 HEAD 请求获取文件信息）
  Future<shelf.Response> _handleStreamHeadRequest(shelf.Request request) async {
    final registration = _resolveRegistration(request.params['token']);
    if (registration == null) {
      return shelf.Response.notFound('Stream not found');
    }

    final headers = <String, String>{
      'Content-Type': registration.mimeType,
      'Accept-Ranges': 'bytes',
    };

    if (registration.fileSize != null) {
      headers['Content-Length'] = registration.fileSize.toString();
    }

    // Note: shelf 框架会自动从 body 计算 Content-Length，对于空 body 会设为 0
    // DLNA 设备主要依赖 Content-Type 和 Accept-Ranges 头，实际文件大小在流式传输时确定
    return shelf.Response.ok(null, headers: headers);
  }

  /// 处理字幕请求
  Future<shelf.Response> _handleSubtitleRequest(shelf.Request request) async {
    final token = request.params['token'];
    final registration = _resolveRegistration(token);
    if (registration == null || registration.subtitlePath == null) {
      return shelf.Response.notFound('Subtitle not found');
    }

    try {
      final stream = await registration.fileSystem.getFileStream(registration.subtitlePath!);

      final mimeType = _getMimeType(registration.subtitlePath!);

      return shelf.Response.ok(
        stream,
        headers: {
          'Content-Type': mimeType,
        },
      );
    } catch (e, st) {
      AppError.handle(e, st, 'handleSubtitleRequest');
      return shelf.Response.internalServerError(body: 'Error loading subtitle: $e');
    }
  }

  /// 处理字幕 HEAD 请求
  Future<shelf.Response> _handleSubtitleHeadRequest(shelf.Request request) async {
    final registration = _resolveRegistration(request.params['token']);
    if (registration == null || registration.subtitlePath == null) {
      return shelf.Response.notFound('Subtitle not found');
    }

    final mimeType = _getMimeType(registration.subtitlePath!);

    return shelf.Response.ok(
      null,
      headers: {
        'Content-Type': mimeType,
      },
    );
  }

  /// 解析 Range 请求头
  FileRange? _parseRangeHeader(String rangeHeader, int? totalSize) {
    // 格式: bytes=start-end 或 bytes=start-
    final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
    if (match == null) return null;

    final start = int.parse(match.group(1)!);
    final endStr = match.group(2);
    final end = endStr != null && endStr.isNotEmpty ? int.parse(endStr) : null;

    return FileRange(start: start, end: end);
  }

  /// 根据文件扩展名获取 MIME 类型
  String _getMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      // 视频
      'mp4' => 'video/mp4',
      'mkv' => 'video/x-matroska',
      'avi' => 'video/x-msvideo',
      'mov' => 'video/quicktime',
      'wmv' => 'video/x-ms-wmv',
      'flv' => 'video/x-flv',
      'webm' => 'video/webm',
      'ts' => 'video/mp2t',
      'm2ts' => 'video/mp2t',
      // 字幕
      'srt' => 'text/plain; charset=utf-8',
      'vtt' => 'text/vtt',
      'ass' => 'text/plain; charset=utf-8',
      'ssa' => 'text/plain; charset=utf-8',
      // 默认
      _ => 'application/octet-stream',
    };
  }

  /// 清理过期的流注册
  void cleanupExpiredStreams({Duration maxAge = _tokenMaxAge}) {
    final now = DateTime.now();
    final expiredTokens = <String>[];

    for (final entry in _streams.entries) {
      if (now.difference(entry.value.createdAt) > maxAge) {
        expiredTokens.add(entry.key);
      }
    }

    for (final token in expiredTokens) {
      _streams.remove(token);
    }

    if (expiredTokens.isNotEmpty) {
      logger.i('清理过期媒体流: ${expiredTokens.length} 个');
    }
  }
}

/// 流注册信息
class _StreamRegistration {
  const _StreamRegistration({
    required this.path,
    required this.fileSystem,
    required this.mimeType,
    required this.createdAt,
    this.fileSize,
    this.subtitlePath,
  });

  final String path;
  final NasFileSystem fileSystem;
  final String mimeType;
  final int? fileSize;
  final String? subtitlePath;
  final DateTime createdAt;
}
