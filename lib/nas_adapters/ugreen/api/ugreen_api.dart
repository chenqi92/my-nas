import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/dio_file_stream.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart'
    show FileRange, ThumbnailSize;
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/pkcs1.dart';
import 'package:pointycastle/asymmetric/rsa.dart';

/// 绿联 NAS API 认证结果
sealed class UGreenAuthResult {}

class UGreenAuthSuccess extends UGreenAuthResult {
  UGreenAuthSuccess({required this.token, this.refreshToken, this.userId});

  final String token;
  final String? refreshToken;
  final String? userId;
}

class UGreenAuthFailure extends UGreenAuthResult {
  UGreenAuthFailure({required this.error, this.code});

  final String error;
  final int? code;
}

class UGreenAuthRequires2FA extends UGreenAuthResult {
  UGreenAuthRequires2FA({this.methods = const ['totp']});

  final List<String> methods;
}

/// 绿联 NAS 设备信息
class UGreenDeviceInfo {
  const UGreenDeviceInfo({
    required this.hostname,
    this.model,
    this.version,
    this.serial,
    this.mac,
  });

  final String hostname;
  final String? model;
  final String? version;
  final String? serial;
  final String? mac;
}

/// 绿联 NAS 文件信息
class UGreenFileInfo {
  const UGreenFileInfo({
    required this.name,
    required this.path,
    required this.isDir,
    this.size,
    this.modified,
    this.created,
    this.mimeType,
  });

  final String name;
  final String path;
  final bool isDir;
  final int? size;
  final DateTime? modified;
  final DateTime? created;
  final String? mimeType;
}

/// 绿联 NAS API 接口
///
/// UGOS 系统使用两步 RSA 加密登录流程:
/// 1. POST /ugreen/v1/verify/check - 获取 RSA 公钥
/// 2. POST /ugreen/v1/verify/login - 使用加密密码登录
class UGreenApi {
  UGreenApi({required this.dio});

  final Dio dio;
  String? _token;
  String? _staticToken;
  String? _tokenId;
  String? _loginPublicKey;
  String? _sessionCookie;
  String? _username;
  String? _password;
  bool _v2ListDisabled = false;
  bool _v2DownloadDisabled = false;
  final Map<String, ({String url, DateTime createdAt})> _v2DownloadCache = {};

  /// 是否已认证
  bool get isAuthenticated => _token != null;

  /// 当前 token
  String? get token => _token;

  /// 登录认证
  ///
  /// UGOS 使用两步 RSA 加密登录:
  /// 1. 获取公钥
  /// 2. 使用公钥加密密码后登录
  Future<UGreenAuthResult> login({
    required String username,
    required String password,
    String? otpCode,
  }) async {
    logger
      ..i('UGreenApi: 开始登录认证 (UGOS API)')
      ..i('UGreenApi: 用户名 => $username');

    _username = username;
    _password = password;
    _invalidateSession();

    try {
      // 新固件先从 verify/check 获取 RSA 公钥；早期固件没有
      // 该端点，仍接受旧的登录 payload。只在 RSA 初始化不可用时
      // 回退，不会在新固件上重复发送密码。
      var passwordPayload = password;
      try {
        logger.i('UGreenApi: Step 1 - 获取 RSA 公钥');
        final checkResponse = await dio.post<dynamic>(
          '/ugreen/v1/verify/check',
          queryParameters: {'token': ''},
          data: {'username': username},
          options: Options(
            validateStatus: (status) => status != null && status < 500,
          ),
        );
        logger.d('UGreenApi: check 响应状态码 => ${checkResponse.statusCode}');
        final rsaTokenHeader = checkResponse.headers.value('x-rsa-token');
        if (rsaTokenHeader == null || rsaTokenHeader.isEmpty) {
          logger.w('UGreenApi: 固件未提供 RSA 公钥，尝试早期登录流程');
        } else {
          passwordPayload = _encryptPassword(password, rsaTokenHeader);
          logger.i('UGreenApi: RSA 密码加密完成');
        }
      } on Exception catch (e, st) {
        AppError.ignore(e, st, 'UGREEN RSA 登录初始化失败，尝试早期固件流程');
      }

      final loginResponse = await dio.post<dynamic>(
        '/ugreen/v1/verify/login',
        data: {
          'is_simple': true,
          'keepalive': true,
          'otp': otpCode != null,
          'username': username,
          'password': passwordPayload,
          'otp_code': ?otpCode,
        },
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      // 登录响应包含 token，不写入日志。
      logger.i('UGreenApi: login 响应状态码 => ${loginResponse.statusCode}');
      _sessionCookie = _cookiesFrom(loginResponse.headers);

      final data = loginResponse.data;
      if (data is Map<String, dynamic>) {
        final code = _intCode(data['code']);

        // 成功
        if (code == 200) {
          final tokenData = data['data'];
          if (tokenData is Map<String, dynamic>) {
            final sessionToken = tokenData['token']?.toString();
            final staticToken = tokenData['static_token']?.toString();
            _token = sessionToken ?? staticToken;
            _staticToken = staticToken;
            _tokenId = tokenData['token_id']?.toString();
            _loginPublicKey = tokenData['public_key']?.toString();
          }
          if (_token != null && _token!.isNotEmpty) {
            logger.i('UGreenApi: 登录成功');
            return UGreenAuthSuccess(
              token: _token!,
              userId: tokenData is Map
                  ? tokenData['user_id']?.toString() ??
                        tokenData['uid']?.toString()
                  : null,
            );
          }
        }

        // 需要 2FA
        if (code == 1001 ||
            data['need_otp'] == true ||
            data['require_2fa'] == true) {
          logger.i('UGreenApi: 需要二次验证');
          return UGreenAuthRequires2FA();
        }

        // 其他错误
        final message =
            data['message']?.toString() ??
            data['msg']?.toString() ??
            appL10n.ugreenAuthLoginFailed('$code');
        logger.e('UGreenApi: 登录失败 => $message');
        return UGreenAuthFailure(error: message, code: code);
      }

      return UGreenAuthFailure(error: appL10n.ugreenAuthServerResponseInvalid);
    } on DioException catch (e, st) {
      AppError.handle(e, st, 'UGreenApi.login');
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return UGreenAuthFailure(error: appL10n.ugreenAuthConnectionTimeout);
      }
      if (e.type == DioExceptionType.connectionError) {
        return UGreenAuthFailure(error: appL10n.ugreenAuthConnectionFailed);
      }
      return UGreenAuthFailure(
        error: e.message ?? appL10n.ugreenAuthNetworkError,
      );
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'UGreenApi.login');
      return UGreenAuthFailure(error: e.toString());
    }
  }

  /// RSA 加密密码
  String _encryptPassword(String password, String rsaPublicKeyBase64) {
    try {
      final normalizedKey = rsaPublicKeyBase64.trim();
      late RSAPublicKey publicKey;
      if (normalizedKey.contains('-----BEGIN')) {
        publicKey = _parsePublicKeyFromPem(normalizedKey);
      } else {
        // UGOS 固件会返回“Base64(PEM)”或直接的 Base64 DER。
        final decoded = Uint8List.fromList(
          base64Decode(base64.normalize(normalizedKey)),
        );
        final maybePem = utf8.decode(decoded, allowMalformed: true);
        publicKey = maybePem.contains('-----BEGIN')
            ? _parsePublicKeyFromPem(maybePem)
            : _parsePublicKeyFromDer(decoded);
      }

      // 使用 PKCS1 v1.5 加密
      final encryptor = PKCS1Encoding(RSAEngine())
        ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));

      final passwordBytes = utf8.encode(password);
      final encrypted = encryptor.process(Uint8List.fromList(passwordBytes));

      // Base64 编码
      return base64Encode(encrypted);
    } catch (e, st) {
      AppError.handle(e, st, 'UGreenApi._encryptPassword');
      rethrow;
    }
  }

  /// 从 PEM 格式解析 RSA 公钥
  RSAPublicKey _parsePublicKeyFromPem(String pem) {
    // 移除 PEM 头尾
    final lines = pem.split('\n');
    final base64String = lines
        .where(
          (line) =>
              !line.startsWith('-----BEGIN') &&
              !line.startsWith('-----END') &&
              line.trim().isNotEmpty,
        )
        .join();

    return _parsePublicKeyFromDer(
      Uint8List.fromList(base64Decode(base64String)),
    );
  }

  RSAPublicKey _parsePublicKeyFromDer(Uint8List keyBytes) {
    // 解析 ASN.1 结构
    final asn1Parser = ASN1Parser(keyBytes);
    final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

    // PKCS#1 格式: 直接包含 n 和 e
    // PKCS#8/SubjectPublicKeyInfo 格式: 包含算法标识符和公钥
    if (topLevelSeq.elements!.length == 2) {
      final firstElement = topLevelSeq.elements![0];
      if (firstElement is ASN1Integer) {
        // PKCS#1 格式
        final modulus = firstElement.integer;
        final exponent = (topLevelSeq.elements![1] as ASN1Integer).integer;
        return RSAPublicKey(modulus!, exponent!);
      } else {
        // PKCS#8 格式
        final publicKeyBitString = topLevelSeq.elements![1] as ASN1BitString;
        final publicKeyBytes = publicKeyBitString.stringValues!;
        final publicKeyParser = ASN1Parser(Uint8List.fromList(publicKeyBytes));
        final publicKeySeq = publicKeyParser.nextObject() as ASN1Sequence;
        final modulus = (publicKeySeq.elements![0] as ASN1Integer).integer;
        final exponent = (publicKeySeq.elements![1] as ASN1Integer).integer;
        return RSAPublicKey(modulus!, exponent!);
      }
    }

    throw FormatException(appL10n.ugreenEncryptionPublicKeyFormatInvalid);
  }

  /// 登出
  Future<void> logout() async {
    if (_token == null) return;

    try {
      await dio.post<dynamic>(
        '/ugreen/v1/verify/logout',
        queryParameters: {'token': _token},
        options: Options(
          headers: _sessionCookie == null ? null : {'cookie': _sessionCookie},
        ),
      );
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '登出失败不影响操作');
    } finally {
      _invalidateSession();
      _username = null;
      _password = null;
    }
  }

  /// 获取设备信息
  Future<UGreenDeviceInfo> getDeviceInfo() async {
    final response = await _request('/ugreen/v1/system/info');

    final data = response.data;
    if (data is Map<String, dynamic> && _intCode(data['code']) == 200) {
      final info = data['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
      return UGreenDeviceInfo(
        hostname:
            info['hostname']?.toString() ??
            info['device_name']?.toString() ??
            'UGREEN NAS',
        model: info['model']?.toString(),
        version:
            info['version']?.toString() ?? info['firmware_version']?.toString(),
        serial: info['serial']?.toString(),
        mac: info['mac']?.toString(),
      );
    }

    return const UGreenDeviceInfo(hostname: 'UGREEN NAS');
  }

  /// 列出目录内容
  ///
  /// UGOS 文件管理器 API 端点尝试顺序:
  /// 1. /ugreen/v1/filemgr/list (带不同参数格式)
  /// 2. /ugreen/v1/file/list
  /// 3. /ugreen/v2/file/list
  Future<List<UGreenFileInfo>> listDirectory(String path) async {
    logger.i('UGreenApi: 列出目录 => $path');

    // 尝试不同的 API 端点和参数组合
    final attempts = [
      // UGOS Pro / new firmware (header-authenticated v2 API).
      {
        'endpoint': '/ugreen/v2/filemgr/getDirFileListV2',
        'data': {
          'path': path,
          'page': 1,
          'limit': 2000,
          'is_shield_recycle': false,
          'data_type': 0,
          'left_no_page_show': false,
          'left_count': 5000,
          'sort_type': 1,
          'reverse': false,
          'permission': 4,
          'root_type': 3,
        },
        'method': 'POST',
        'v2': true,
      },
      // 尝试 1: filemgr/list 带 path 参数 (POST)
      {
        'endpoint': '/ugreen/v1/filemgr/list',
        'data': {'path': path, 'page': 1, 'page_size': 1000},
        'method': 'POST',
      },
      // 尝试 2: filemgr/list (GET with query params)
      {
        'endpoint': '/ugreen/v1/filemgr/list',
        'data': {'path': path, 'page': 1, 'page_size': 1000},
        'method': 'GET',
      },
      // 尝试 3: filemgr/list 带 dir 参数
      {
        'endpoint': '/ugreen/v1/filemgr/list',
        'data': {'dir': path, 'page': 1, 'limit': 1000},
        'method': 'POST',
      },
      // 尝试 4: file/list
      {
        'endpoint': '/ugreen/v1/file/list',
        'data': {'path': path, 'page': 1, 'page_size': 1000},
        'method': 'POST',
      },
      // 尝试 5: file/list (GET)
      {
        'endpoint': '/ugreen/v1/file/list',
        'data': {'path': path, 'page': 1, 'page_size': 1000},
        'method': 'GET',
      },
      // 尝试 6: file/list 带 folder 参数
      {
        'endpoint': '/ugreen/v1/file/list',
        'data': {'folder': path, 'offset': 0, 'limit': 1000},
        'method': 'POST',
      },
      // 尝试 7: v2 file/list
      {
        'endpoint': '/ugreen/v2/file/list',
        'data': {'path': path, 'page': 1, 'page_size': 1000},
        'method': 'POST',
      },
      // 尝试 8: filemgr/dir/list
      {
        'endpoint': '/ugreen/v1/filemgr/dir/list',
        'data': {'path': path},
        'method': 'POST',
      },
      // 尝试 9: filemgr/dir/list (GET)
      {
        'endpoint': '/ugreen/v1/filemgr/dir/list',
        'data': {'path': path},
        'method': 'GET',
      },
      // 尝试 10: filestation API (类似群晖)
      {
        'endpoint': '/ugreen/v1/filestation/list',
        'data': {'folder_path': path},
        'method': 'POST',
      },
    ];

    for (final attempt in attempts) {
      try {
        final endpoint = attempt['endpoint']! as String;
        final baseData = attempt['data']! as Map<String, dynamic>;
        final method = attempt['method'] as String? ?? 'POST';
        final isV2 = attempt['v2'] == true;
        final v2Headers = isV2 ? _v2AuthHeaders() : null;
        if (isV2 && (_v2ListDisabled || v2Headers == null)) continue;
        logger.d('UGreenApi: 尝试端点 => $endpoint ($method), 参数 => $baseData');

        Future<Response<dynamic>> requestPage(int page) {
          final data = Map<String, dynamic>.from(baseData);
          if (data.containsKey('page')) data['page'] = page;
          if (data.containsKey('offset')) {
            data['offset'] = (page - 1) * (data['limit'] as int? ?? 1000);
          }
          return _request(
            endpoint,
            data: data,
            method: method,
            headers: {
              ...?v2Headers,
              if (isV2)
                'referer': '${dio.options.baseUrl}/filemgr/?_filemgr=my_nas',
            },
          );
        }

        var response = await requestPage(1);

        final respData = response.data;
        logger.d('UGreenApi: listDirectory 响应 => $respData');
        var files = _extractSuccessfulList(respData, const [
          'list',
          'files',
          'items',
          'children',
        ]);
        if (files == null) continue;

        final allFiles = <dynamic>[...files];
        var pageFiles = files;
        final seenPages = <String>{_pageMarker(files)};
        final pageSize =
            baseData['page_size'] as int? ?? baseData['limit'] as int?;
        final isPaged =
            baseData.containsKey('page') || baseData.containsKey('offset');
        if (pageSize != null && isPaged) {
          var page = 2;
          final total = _extractTotal(respData);
          while (pageFiles.length >= pageSize) {
            if (total != null && allFiles.length >= total) break;
            if (page > 10000) {
              throw StateError('$endpoint 分页超过安全上限');
            }
            response = await requestPage(page++);
            final nextFiles = _extractSuccessfulList(response.data, const [
              'list',
              'files',
              'items',
              'children',
            ]);
            if (nextFiles == null) {
              throw StateError('$endpoint 分页响应格式发生变化');
            }
            if (!seenPages.add(_pageMarker(nextFiles))) {
              throw StateError('$endpoint 忽略分页参数，返回了重复页');
            }
            pageFiles = nextFiles;
            allFiles.addAll(pageFiles);
          }
        }

        final items = allFiles
            .whereType<Map<dynamic, dynamic>>()
            .map((file) => _parseFileInfo(file, path))
            .toList();
        if (isV2 && !_itemsBelongToPath(items, path)) {
          _v2ListDisabled = true;
          logger.w('UGreenApi: v2 列表忽略目录路径，本会话回退 v1');
          continue;
        }
        logger.i('UGreenApi: 找到 ${items.length} 个文件/目录 (使用 $endpoint)');
        return items;
      } on Exception catch (e, st) {
        if (attempt['v2'] == true) _v2ListDisabled = true;
        AppError.ignore(e, st, '尝试不同的 API 端点，失败是预期的');
      }
    }

    logger.e('UGreenApi: 所有端点都失败了，路径: $path');
    throw StateError('UGREEN 无法获取目录列表：$path');
  }

  /// 获取文件下载链接
  Future<String> getFileUrl(String path) async {
    final v2Url = await _getV2DownloadUrl(path);
    if (v2Url != null) return v2Url;
    final baseUrl = dio.options.baseUrl;
    return Uri.parse('$baseUrl/ugreen/v1/file/download')
        .replace(queryParameters: {'path': path, 'token': _token ?? ''})
        .toString();
  }

  /// 获取缩略图 URL
  String? getThumbnailUrl(String path, {ThumbnailSize? size}) {
    final baseUrl = dio.options.baseUrl;
    // UGOS 缩略图可能的端点
    // 尝试使用 thumbnail 端点
    final sizeParam = switch (size) {
      ThumbnailSize.small => 'small',
      ThumbnailSize.medium => 'medium',
      ThumbnailSize.large => 'large',
      ThumbnailSize.xlarge => 'xlarge',
      null => 'medium',
    };
    return Uri.parse('$baseUrl/ugreen/v1/file/thumbnail')
        .replace(
          queryParameters: {
            'path': path,
            'size': sizeParam,
            'token': _token ?? '',
          },
        )
        .toString();
  }

  /// 通过 URL 获取数据流
  ///
  /// 用于在需要绕过证书验证等场景下，通过已知 URL 获取数据
  Future<Stream<List<int>>> getUrlStream(String url, {FileRange? range}) async {
    logger.d('UGreenApi: getUrlStream => $url');
    return openDioFileStream(
      dio,
      url,
      range: range,
      onSessionInvalid: _invalidateSession,
    );
  }

  /// 创建目录
  Future<void> createDirectory(String path) async {
    await _request('/ugreen/v1/file/mkdir', data: {'path': path});
  }

  /// 删除文件或目录
  Future<void> delete(String path) async {
    await _request(
      '/ugreen/v1/file/delete',
      data: {
        'paths': [path],
      },
    );
  }

  /// 重命名
  Future<void> rename(String oldPath, String newPath) async {
    await _request(
      '/ugreen/v1/file/rename',
      data: {'old_path': oldPath, 'new_path': newPath},
    );
  }

  /// 服务端复制
  ///
  /// UGOS 提供 `/ugreen/v1/file/copy` 端点接收 `srcs`（源路径列表）和 `dst`（目标父目录）。
  /// 不同固件可能字段名稍有差异，调用方在失败时应自行回退到下载+上传。
  Future<void> copy(String sourcePath, String destPath) async {
    final lastSlash = destPath.lastIndexOf('/');
    final destParent = lastSlash > 0 ? destPath.substring(0, lastSlash) : '/';
    final destName = lastSlash >= 0
        ? destPath.substring(lastSlash + 1)
        : destPath;
    await _request(
      '/ugreen/v1/file/copy',
      data: {
        'srcs': [sourcePath],
        'dst': destParent,
        // 部分固件支持复制时重命名
        'new_name': destName,
      },
    );
  }

  /// 上传文件 (multipart/form-data)
  ///
  /// UGOS 上传端点：`/ugreen/v1/file/upload`，支持以 multipart 上传单文件。
  /// [remoteDir] 目标目录，[fileName] 远端文件名。
  /// 对于大文件，调用方应自行分块（UGOS 也支持分片上传，未来可优化）。
  Future<void> uploadBytes({
    required String remoteDir,
    required String fileName,
    required List<int> data,
    String? mimeType,
    void Function(int sent, int total)? onProgress,
  }) async {
    final form = FormData.fromMap({
      'path': remoteDir,
      'file': MultipartFile.fromBytes(
        data,
        filename: fileName,
        contentType: mimeType != null ? DioMediaType.parse(mimeType) : null,
      ),
    });

    await dio.post<dynamic>(
      '/ugreen/v1/file/upload',
      queryParameters: {'token': _token ?? ''},
      data: form,
      onSendProgress: onProgress,
      options: Options(contentType: 'multipart/form-data'),
    );
  }

  /// 上传本地文件
  Future<void> uploadFile({
    required String localPath,
    required String remoteDir,
    required String fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    final form = FormData.fromMap({
      'path': remoteDir,
      'file': await MultipartFile.fromFile(localPath, filename: fileName),
    });

    await dio.post<dynamic>(
      '/ugreen/v1/file/upload',
      queryParameters: {'token': _token ?? ''},
      data: form,
      onSendProgress: onProgress,
      options: Options(contentType: 'multipart/form-data'),
    );
  }

  /// 服务端搜索
  ///
  /// UGOS `/ugreen/v1/file/search` 端点支持关键字搜索。
  /// [path] 限定搜索范围（可选）。
  Future<List<UGreenFileInfo>> search(String query, {String? path}) async {
    final response = await _request(
      '/ugreen/v1/file/search',
      data: {'keyword': query, 'path': ?path},
    );

    final list = _extractSuccessfulList(response.data, const [
      'files',
      'list',
      'items',
    ]);
    if (list == null) {
      throw StateError('UGREEN 搜索响应格式无效');
    }

    return list
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => _parseFileInfo(m, path ?? '/'))
        .toList();
  }

  /// 获取共享文件夹列表
  ///
  /// UGOS 共享文件夹 API 端点尝试顺序 (尝试多种已知的 UGOS API 格式)
  Future<List<UGreenFileInfo>> listShares() async {
    logger.i('UGreenApi: 获取共享文件夹列表');

    // 首先尝试通过存储池 API 获取共享文件夹
    // 这是 Home Assistant 集成发现的可靠端点
    try {
      final poolResult = await _getSharesFromStoragePool();
      if (poolResult.isNotEmpty) {
        logger.i('UGreenApi: 从存储池获取到 ${poolResult.length} 个共享文件夹');
        return poolResult;
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '从存储池获取共享失败，继续尝试其他方法');
    }

    // 尝试不同的共享端点和参数组合
    final attempts = [
      // 存储管理相关端点
      {
        'endpoint': '/ugreen/v1/storage/share/list',
        'data': <String, dynamic>{},
        'method': 'GET',
      },
      {
        'endpoint': '/ugreen/v1/storage/share/list',
        'data': <String, dynamic>{},
      },
      {
        'endpoint': '/ugreen/v1/storage/shares',
        'data': <String, dynamic>{},
        'method': 'GET',
      },
      {
        'endpoint': '/ugreen/v1/storage/volume/list',
        'data': <String, dynamic>{},
        'method': 'GET',
      },
      // 文件管理相关端点
      {
        'endpoint': '/ugreen/v1/filemgr/share/list',
        'data': <String, dynamic>{},
        'method': 'GET',
      },
      {
        'endpoint': '/ugreen/v1/filemgr/shares',
        'data': <String, dynamic>{},
        'method': 'GET',
      },
      {
        'endpoint': '/ugreen/v1/filemgr/root',
        'data': <String, dynamic>{},
        'method': 'GET',
      },
      // 通用共享端点
      {
        'endpoint': '/ugreen/v1/share/list',
        'data': <String, dynamic>{},
        'method': 'GET',
      },
      {
        'endpoint': '/ugreen/v1/shares',
        'data': <String, dynamic>{},
        'method': 'GET',
      },
      // 用户目录相关
      {
        'endpoint': '/ugreen/v1/user/home',
        'data': <String, dynamic>{},
        'method': 'GET',
      },
      {
        'endpoint': '/ugreen/v1/user/shares',
        'data': <String, dynamic>{},
        'method': 'GET',
      },
    ];

    for (final attempt in attempts) {
      try {
        final endpoint = attempt['endpoint']! as String;
        final data = attempt['data']! as Map<String, dynamic>;
        final method = attempt['method'] as String? ?? 'POST';
        logger.d('UGreenApi: 尝试共享端点 => $endpoint ($method)');

        final response = await _request(
          endpoint,
          data: data.isEmpty ? null : data,
          method: method,
        );

        final respData = response.data;
        logger.d('UGreenApi: listShares 响应 ($endpoint) => $respData');

        final shares = _extractSuccessfulList(respData, const [
          'list',
          'shares',
          'volumes',
          'items',
          'folders',
        ]);
        if (shares == null) continue;
        final items = <UGreenFileInfo>[];
        for (final share in shares.whereType<Map<dynamic, dynamic>>()) {
          final name =
              share['name']?.toString() ??
              share['share_name']?.toString() ??
              share['volume_name']?.toString() ??
              share['folder_name']?.toString() ??
              '';
          if (name.isEmpty) continue;
          final path =
              share['path']?.toString() ??
              share['mount_point']?.toString() ??
              share['share_path']?.toString() ??
              '/$name';
          items.add(UGreenFileInfo(name: name, path: path, isDir: true));
        }
        logger.i('UGreenApi: 找到 ${items.length} 个共享文件夹 (使用 $endpoint)');
        return items;
      } on Exception catch (e, st) {
        AppError.ignore(e, st, '尝试不同的共享 API 端点，失败是预期的');
      }
    }

    // 所有共享端点都失败，尝试直接列出根目录 (使用不同的路径格式)
    logger.i('UGreenApi: 共享端点都失败，尝试直接列出根目录');

    return listDirectory('/');
  }

  List<dynamic>? _extractSuccessfulList(dynamic body, List<String> keys) {
    if (body is! Map<String, dynamic> || _intCode(body['code']) != 200) {
      return null;
    }
    final payload = body['data'];
    if (payload is List) return payload;
    if (payload is Map) {
      for (final key in keys) {
        final value = payload[key];
        if (value is List) return value;
      }
    }
    return null;
  }

  int? _extractTotal(dynamic body) {
    if (body is! Map) return null;
    final payload = body['data'];
    if (payload is! Map || payload['total'] == null) return null;
    final total = _intCode(payload['total']);
    return total > 0 ? total : null;
  }

  String _pageMarker(List<dynamic> page) => page
      .map((item) {
        if (item is Map) {
          return '${item['path']}\u0000${item['id']}\u0000${item['name']}';
        }
        return item.toString();
      })
      .join('\u0001');

  /// 从存储池 API 获取共享文件夹
  ///
  /// 使用 /ugreen/v1/storage/pool/list 端点获取存储池信息
  /// 然后从中提取共享文件夹路径
  Future<List<UGreenFileInfo>> _getSharesFromStoragePool() async {
    logger.d('UGreenApi: 尝试从存储池获取共享文件夹');

    final response = await _request(
      '/ugreen/v1/storage/pool/list',
      method: 'GET',
    );
    final respData = response.data;
    logger.d('UGreenApi: storage/pool/list 响应状态已接收');

    if (respData is! Map<String, dynamic> ||
        _intCode(respData['code']) != 200) {
      return [];
    }

    final items = <UGreenFileInfo>[];
    final data = respData['data'];
    final dataMap = data is Map<String, dynamic> ? data : null;

    // 尝试多种可能的响应结构
    // 结构 1: { pools: [ { volumes: [...] } ] }
    final pools =
        dataMap?['pools'] ??
        dataMap?['list'] ??
        (data is List ? data : null) ??
        <dynamic>[];
    if (pools is List) {
      for (final pool in pools) {
        if (pool is! Map) continue;

        logger.d('UGreenApi: 处理存储池: ${pool['name']} (${pool['id']})');

        // 从池中提取卷/共享
        final volumes =
            pool['volumes'] ?? pool['shares'] ?? pool['folders'] ?? <dynamic>[];
        if (volumes is List) {
          for (final vol in volumes) {
            if (vol is! Map) continue;

            final name =
                vol['name']?.toString() ??
                vol['volume_name']?.toString() ??
                vol['share_name']?.toString() ??
                '';
            if (name.isEmpty) continue;

            // 尝试获取路径
            var path =
                vol['path']?.toString() ??
                vol['mount_point']?.toString() ??
                vol['share_path']?.toString();

            // 如果没有路径，根据名称构造
            if (path == null || path.isEmpty) {
              path = '/$name';
            }

            logger.d('UGreenApi: 发现共享: $name => $path');
            items.add(UGreenFileInfo(name: name, path: path, isDir: true));
          }
        }

        // 有些 UGOS 版本可能将共享文件夹放在 pool 级别
        final shareFolders =
            pool['share_folders'] ?? pool['shared_folders'] ?? <dynamic>[];
        if (shareFolders is List) {
          for (final folder in shareFolders) {
            if (folder is! Map) continue;

            final name = folder['name']?.toString() ?? '';
            if (name.isEmpty) continue;

            final path = folder['path']?.toString() ?? '/$name';

            logger.d('UGreenApi: 发现共享文件夹: $name => $path');
            items.add(UGreenFileInfo(name: name, path: path, isDir: true));
          }
        }
      }
    }

    // 结构 2: 直接的共享列表
    final directShares =
        dataMap?['shares'] ?? dataMap?['volumes'] ?? <dynamic>[];
    if (directShares is List) {
      for (final share in directShares) {
        if (share is! Map) continue;

        final name = share['name']?.toString() ?? '';
        if (name.isEmpty) continue;

        final path =
            share['path']?.toString() ??
            share['mount_point']?.toString() ??
            '/$name';

        // 避免重复
        if (!items.any((item) => item.path == path)) {
          logger.d('UGreenApi: 发现直接共享: $name => $path');
          items.add(UGreenFileInfo(name: name, path: path, isDir: true));
        }
      }
    }

    return items;
  }

  Map<String, dynamic>? _v2AuthHeaders() {
    final token = _token;
    final tokenId = _tokenId;
    final publicKey = _loginPublicKey;
    if (token == null || tokenId == null || publicKey == null) return null;
    try {
      return {
        'x-ugreen-security-key': tokenId,
        'x-ugreen-token': _encryptPassword(token, publicKey),
        if (_sessionCookie != null) 'cookie': _sessionCookie,
      };
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'UGREEN v2 token 加密失败，回退 v1');
      return null;
    }
  }

  bool _itemsBelongToPath(List<UGreenFileInfo> items, String path) {
    final normalized = path == '/' || path.isEmpty
        ? ''
        : path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    if (normalized.isEmpty) return true;
    final pathedItems = items.where((item) => item.path.isNotEmpty).toList();
    if (pathedItems.isEmpty) return true;
    return pathedItems.any(
      (item) => item.path == normalized || item.path.startsWith('$normalized/'),
    );
  }

  Future<String?> _getV2DownloadUrl(String path) async {
    if (_v2DownloadDisabled) return null;
    final cached = _v2DownloadCache[path];
    if (cached != null &&
        DateTime.now().difference(cached.createdAt) <
            const Duration(seconds: 60)) {
      return cached.url;
    }
    final headers = _v2AuthHeaders();
    if (headers == null) return null;

    try {
      final permission = await _request(
        '/ugreen/v1/filemgr/detectionPermissions',
        data: {
          'paths': [path],
          'type': 4,
          'intranet_share_id': 0,
        },
        headers: headers,
      );
      if (_intCode((permission.data as Map?)?['code']) != 200) return null;

      final tokenResponse = await _request(
        '/ugreen/v2/filemgr/getDownloadToken',
        method: 'GET',
        data: {'paths': path, 'intranet_share_id': 0, 'coding': true},
        headers: headers,
      );
      final responseBody = tokenResponse.data;
      if (responseBody is! Map || _intCode(responseBody['code']) != 200) {
        return null;
      }
      final responseData = responseBody['data'];
      if (responseData is! Map) return null;
      final downloadPath = responseData['dl_url']?.toString();
      if (downloadPath == null || downloadPath.isEmpty) return null;
      final downloadUri = Uri.tryParse(downloadPath);
      final resolved = downloadUri?.hasScheme == true
          ? downloadUri!.toString()
          : Uri.parse(dio.options.baseUrl).resolve(downloadPath).toString();
      _v2DownloadCache[path] = (url: resolved, createdAt: DateTime.now());
      return resolved;
    } on Exception catch (e, st) {
      _v2DownloadDisabled = true;
      AppError.ignore(e, st, 'UGREEN v2 下载令牌失败，本会话回退 v1');
      return null;
    }
  }

  void _invalidateSession() {
    _token = null;
    _staticToken = null;
    _tokenId = null;
    _loginPublicKey = null;
    _sessionCookie = null;
    _v2DownloadCache.clear();
    _v2ListDisabled = false;
    _v2DownloadDisabled = false;
  }

  int _intCode(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String? _cookiesFrom(Headers headers) {
    final cookies = headers.map.entries
        .where((entry) => entry.key.toLowerCase() == 'set-cookie')
        .expand((entry) => entry.value)
        .map((value) => value.split(';').first.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    return cookies.isEmpty ? null : cookies.join('; ');
  }

  bool _isAuthFailureCode(int code) =>
      code == 401 ||
      code == 403 ||
      code == 1001 ||
      code == 1002 ||
      code == 1024;

  /// 发送 API 请求（自动处理 token）
  Future<Response<dynamic>> _request(
    String path, {
    Map<String, dynamic>? data,
    String method = 'POST',
    Map<String, dynamic>? headers,
  }) async {
    final isGet = method.toUpperCase() == 'GET';
    final query = <String, dynamic>{'token': _token ?? '', if (isGet) ...?data};
    late Response<dynamic> response;
    try {
      response = await dio.request<dynamic>(
        path,
        queryParameters: query,
        data: isGet ? null : data,
        options: Options(method: method, headers: headers),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        _invalidateSession();
      }
      rethrow;
    }

    // 检查 token 是否过期 (code 1024)
    final responseData = response.data;
    final responseCode = responseData is Map
        ? _intCode(responseData['code'])
        : 0;
    if (responseCode == 1024) {
      logger.i('UGreenApi: Token 过期，重新登录');
      _invalidateSession();
      if (_username != null && _password != null) {
        final result = await login(username: _username!, password: _password!);
        if (result is UGreenAuthSuccess) {
          final retryHeaders = headers?.containsKey('x-ugreen-token') == true
              ? {
                  ...?_v2AuthHeaders(),
                  if (headers?['referer'] != null)
                    'referer': headers!['referer'],
                }
              : headers;
          // 重试请求
          return dio.request<dynamic>(
            path,
            queryParameters: {'token': _token ?? '', if (isGet) ...?data},
            data: isGet ? null : data,
            options: Options(method: method, headers: retryHeaders),
          );
        }
      }
    } else if (_isAuthFailureCode(responseCode)) {
      _invalidateSession();
    }

    return response;
  }

  UGreenFileInfo _parseFileInfo(Map<dynamic, dynamic> file, String parentPath) {
    final name = file['name']?.toString() ?? file['filename']?.toString() ?? '';
    final isDir =
        file['is_dir'] == true ||
        file['isdir'] == true ||
        file['type'] == 'dir' ||
        file['type'] == 'folder' ||
        file['type'] == 'directory';

    DateTime? modified;
    // 尝试多种可能的时间字段名
    final modifiedValue =
        file['modified'] ??
        file['mtime'] ??
        file['modify_time'] ??
        file['modifyTime'] ??
        file['last_modified'] ??
        file['lastModified'] ??
        file['update_time'] ??
        file['updateTime'] ??
        file['time'] ??
        file['date'];
    if (modifiedValue != null) {
      modified = _parseDateTime(modifiedValue);
    }

    DateTime? created;
    final createdValue =
        file['created'] ??
        file['ctime'] ??
        file['create_time'] ??
        file['createTime'] ??
        file['creation_time'] ??
        file['creationTime'];
    if (createdValue != null) {
      created = _parseDateTime(createdValue);
    }

    return UGreenFileInfo(
      name: name,
      path: file['path']?.toString() ?? '$parentPath/$name',
      isDir: isDir,
      size: file['size'] == null ? null : _intCode(file['size']),
      modified: modified,
      created: created,
      mimeType: file['mime_type']?.toString() ?? file['mimetype']?.toString(),
    );
  }

  /// 解析日期时间，支持多种格式
  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;

    if (value is int) {
      // 检查是秒还是毫秒 (Unix 时间戳)
      // 如果值小于 10000000000，假设是秒；否则是毫秒
      if (value < 10000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      } else {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
    } else if (value is String) {
      // 首先尝试标准解析
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;

      // 尝试解析常见的日期格式
      // 格式: "2024-01-15 10:30:00"
      final parts = value.split(RegExp(r'[\s\-/:]'));
      if (parts.length >= 3) {
        try {
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final day = int.parse(parts[2]);
          final hour = parts.length > 3 ? int.tryParse(parts[3]) ?? 0 : 0;
          final minute = parts.length > 4 ? int.tryParse(parts[4]) ?? 0 : 0;
          final second = parts.length > 5 ? int.tryParse(parts[5]) ?? 0 : 0;
          return DateTime(year, month, day, hour, minute, second);
        } on Exception catch (e, st) {
          AppError.ignore(e, st, '日期格式解析失败是预期的，返回 null');
        }
      }
    }

    return null;
  }
}
