import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart' show ThumbnailSize;
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/pkcs1.dart';
import 'package:pointycastle/asymmetric/rsa.dart';

/// 绿联 NAS API 认证结果
sealed class UGreenAuthResult {}

class UGreenAuthSuccess extends UGreenAuthResult {
  UGreenAuthSuccess({
    required this.token,
    this.refreshToken,
    this.userId,
  });

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
  String? _username;
  String? _password;

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
    logger..i('UGreenApi: 开始登录认证 (UGOS API)')
    ..i('UGreenApi: 用户名 => $username');

    _username = username;
    _password = password;

    try {
      // Step 1: 获取 RSA 公钥
      logger.i('UGreenApi: Step 1 - 获取 RSA 公钥');
      final checkResponse = await dio.post<dynamic>(
        '/ugreen/v1/verify/check',
        queryParameters: {'token': ''},
        data: {'username': username},
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      logger..d('UGreenApi: check 响应状态码 => ${checkResponse.statusCode}')
      ..d('UGreenApi: check 响应头 => ${checkResponse.headers.map}');

      // 从响应头获取 RSA 公钥
      final rsaTokenHeader = checkResponse.headers.value('x-rsa-token');
      if (rsaTokenHeader == null) {
        logger.e('UGreenApi: 未获取到 RSA 公钥');
        return UGreenAuthFailure(error: appL10n.ugreenAuthServerNoEncryptionKey);
      }

      logger..i('UGreenApi: 获取到 RSA 公钥')

      // Step 2: 使用 RSA 加密密码并登录
      ..i('UGreenApi: Step 2 - 加密密码并登录');
      final encryptedPassword = _encryptPassword(password, rsaTokenHeader);
      logger.d('UGreenApi: 密码加密完成');

      final loginResponse = await dio.post<dynamic>(
        '/ugreen/v1/verify/login',
        data: {
          'is_simple': true,
          'keepalive': true,
          'otp': otpCode != null,
          'username': username,
          'password': encryptedPassword,
          'otp_code': ?otpCode,
        },
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      logger..i('UGreenApi: login 响应状态码 => ${loginResponse.statusCode}')
      ..d('UGreenApi: login 响应 => ${loginResponse.data}');

      final data = loginResponse.data;
      if (data is Map<String, dynamic>) {
        final code = data['code'];

        // 成功
        if (code == 200) {
          final tokenData = data['data'];
          if (tokenData is Map<String, dynamic> && tokenData['token'] != null) {
            _token = tokenData['token'] as String;
            logger.i('UGreenApi: 登录成功');
            return UGreenAuthSuccess(
              token: _token!,
              userId: tokenData['user_id']?.toString(),
            );
          }
        }

        // 需要 2FA
        if (code == 1001 || data['need_otp'] == true || data['require_2fa'] == true) {
          logger.i('UGreenApi: 需要二次验证');
          return UGreenAuthRequires2FA();
        }

        // 其他错误
        final message = data['message']?.toString() ??
                       data['msg']?.toString() ??
                       appL10n.ugreenAuthLoginFailed('$code');
        logger.e('UGreenApi: 登录失败 => $message');
        return UGreenAuthFailure(error: message, code: code as int?);
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
      return UGreenAuthFailure(error: e.message ?? appL10n.ugreenAuthNetworkError);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'UGreenApi.login');
      return UGreenAuthFailure(error: e.toString());
    }
  }

  /// RSA 加密密码
  String _encryptPassword(String password, String rsaPublicKeyBase64) {
    try {
      // 解码 Base64 公钥
      final publicKeyBytes = base64Decode(rsaPublicKeyBase64);
      final publicKeyPem = utf8.decode(publicKeyBytes);

      logger.d('UGreenApi: 公钥 PEM:\n$publicKeyPem');

      // 解析 PEM 格式的公钥
      final publicKey = _parsePublicKeyFromPem(publicKeyPem);

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
        .where((line) =>
            !line.startsWith('-----BEGIN') &&
            !line.startsWith('-----END') &&
            line.trim().isNotEmpty)
        .join();

    final keyBytes = base64Decode(base64String);

    // 解析 ASN.1 结构
    final asn1Parser = ASN1Parser(Uint8List.fromList(keyBytes));
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
      );
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '登出失败不影响操作');
    } finally {
      _token = null;
      _username = null;
      _password = null;
    }
  }

  /// 获取设备信息
  Future<UGreenDeviceInfo> getDeviceInfo() async {
    final response = await _request('/ugreen/v1/system/info');

    final data = response.data;
    if (data is Map<String, dynamic> && data['code'] == 200) {
      final info = data['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
      return UGreenDeviceInfo(
        hostname: info['hostname']?.toString() ??
                  info['device_name']?.toString() ??
                  'UGREEN NAS',
        model: info['model']?.toString(),
        version: info['version']?.toString() ??
                 info['firmware_version']?.toString(),
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
        final data = attempt['data']! as Map<String, dynamic>;
        final method = attempt['method'] as String? ?? 'POST';
        logger.d('UGreenApi: 尝试端点 => $endpoint ($method), 参数 => $data');

        final response = await _request(endpoint, data: data, method: method);

        final respData = response.data;
        logger.d('UGreenApi: listDirectory 响应 => $respData');

        if (respData is Map<String, dynamic>) {
          final code = respData['code'];
          if (code == 200) {
            final items = <UGreenFileInfo>[];
            // 尝试不同的响应结构
            final data = respData['data'];
            final dataMap = data is Map<String, dynamic> ? data : null;
            final files = dataMap?['list'] ??
                          dataMap?['files'] ??
                          dataMap?['items'] ??
                          dataMap?['children'] ??
                          data ??
                          <dynamic>[];

            if (files is List) {
              for (final file in files) {
                if (file is Map<String, dynamic>) {
                  items.add(_parseFileInfo(file, path));
                }
              }
            }

            if (items.isNotEmpty) {
              logger.i('UGreenApi: 找到 ${items.length} 个文件/目录 (使用 $endpoint)');
              return items;
            }
            logger.d('UGreenApi: $endpoint 返回空列表');
          } else {
            final msg = respData['message'] ?? respData['msg'] ?? 'code=$code';
            logger.w('UGreenApi: $endpoint 返回错误: $msg');
          }
        }
      } on Exception catch (e, st) {
        AppError.ignore(e, st, '尝试不同的 API 端点，失败是预期的');
      }
    }

    logger.e('UGreenApi: 所有端点都失败了，路径: $path');
    return [];
  }

  /// 获取文件下载链接
  Future<String> getFileUrl(String path) async {
    final baseUrl = dio.options.baseUrl;
    return '$baseUrl/ugreen/v1/file/download?path=${Uri.encodeComponent(path)}&token=$_token';
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
    return '$baseUrl/ugreen/v1/file/thumbnail?path=${Uri.encodeComponent(path)}&size=$sizeParam&token=$_token';
  }

  /// 通过 URL 获取数据流
  ///
  /// 用于在需要绕过证书验证等场景下，通过已知 URL 获取数据
  Future<Stream<List<int>>> getUrlStream(String url) async {
    logger.d('UGreenApi: getUrlStream => $url');

    final response = await dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
      ),
    );

    if (response.data == null) {
      throw Exception(appL10n.ugreenFileUrlStreamFailed);
    }

    return response.data!.stream;
  }

  /// 创建目录
  Future<void> createDirectory(String path) async {
    await _request(
      '/ugreen/v1/file/mkdir',
      data: {'path': path},
    );
  }

  /// 删除文件或目录
  Future<void> delete(String path) async {
    await _request(
      '/ugreen/v1/file/delete',
      data: {'paths': [path]},
    );
  }

  /// 重命名
  Future<void> rename(String oldPath, String newPath) async {
    await _request(
      '/ugreen/v1/file/rename',
      data: {
        'old_path': oldPath,
        'new_path': newPath,
      },
    );
  }

  /// 服务端复制
  ///
  /// UGOS 提供 `/ugreen/v1/file/copy` 端点接收 `srcs`（源路径列表）和 `dst`（目标父目录）。
  /// 不同固件可能字段名稍有差异，调用方在失败时应自行回退到下载+上传。
  Future<void> copy(String sourcePath, String destPath) async {
    final lastSlash = destPath.lastIndexOf('/');
    final destParent = lastSlash > 0 ? destPath.substring(0, lastSlash) : '/';
    final destName = lastSlash >= 0 ? destPath.substring(lastSlash + 1) : destPath;
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
      options: Options(
        contentType: 'multipart/form-data',
      ),
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
      options: Options(
        contentType: 'multipart/form-data',
      ),
    );
  }

  /// 服务端搜索
  ///
  /// UGOS `/ugreen/v1/file/search` 端点支持关键字搜索。
  /// [path] 限定搜索范围（可选）。
  Future<List<UGreenFileInfo>> search(String query, {String? path}) async {
    final response = await _request(
      '/ugreen/v1/file/search',
      data: {
        'keyword': query,
        'path': ?path,
      },
    );

    final body = response.data;
    if (body is! Map<String, dynamic>) return [];
    final dataField = body['data'];
    final list = dataField is Map<String, dynamic>
        ? (dataField['files'] as List? ?? dataField['list'] as List? ?? const <dynamic>[])
        : (dataField is List ? dataField : const <dynamic>[]);

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
      {'endpoint': '/ugreen/v1/storage/share/list', 'data': <String, dynamic>{}, 'method': 'GET'},
      {'endpoint': '/ugreen/v1/storage/share/list', 'data': <String, dynamic>{}},
      {'endpoint': '/ugreen/v1/storage/shares', 'data': <String, dynamic>{}, 'method': 'GET'},
      {'endpoint': '/ugreen/v1/storage/volume/list', 'data': <String, dynamic>{}, 'method': 'GET'},
      // 文件管理相关端点
      {'endpoint': '/ugreen/v1/filemgr/share/list', 'data': <String, dynamic>{}, 'method': 'GET'},
      {'endpoint': '/ugreen/v1/filemgr/shares', 'data': <String, dynamic>{}, 'method': 'GET'},
      {'endpoint': '/ugreen/v1/filemgr/root', 'data': <String, dynamic>{}, 'method': 'GET'},
      // 通用共享端点
      {'endpoint': '/ugreen/v1/share/list', 'data': <String, dynamic>{}, 'method': 'GET'},
      {'endpoint': '/ugreen/v1/shares', 'data': <String, dynamic>{}, 'method': 'GET'},
      // 用户目录相关
      {'endpoint': '/ugreen/v1/user/home', 'data': <String, dynamic>{}, 'method': 'GET'},
      {'endpoint': '/ugreen/v1/user/shares', 'data': <String, dynamic>{}, 'method': 'GET'},
    ];

    for (final attempt in attempts) {
      try {
        final endpoint = attempt['endpoint']! as String;
        final data = attempt['data']! as Map<String, dynamic>;
        final method = attempt['method'] as String? ?? 'POST';
        logger.d('UGreenApi: 尝试共享端点 => $endpoint ($method)');

        final response = await _request(endpoint, data: data.isEmpty ? null : data, method: method);

        final respData = response.data;
        logger.d('UGreenApi: listShares 响应 ($endpoint) => $respData');

        if (respData is Map<String, dynamic> && respData['code'] == 200) {
          final items = <UGreenFileInfo>[];

          // 尝试不同的响应结构
          final data = respData['data'];
          final dataMap = data is Map<String, dynamic> ? data : null;
          final shares = dataMap?['list'] ??
                         dataMap?['shares'] ??
                         dataMap?['volumes'] ??
                         dataMap?['items'] ??
                         dataMap?['folders'] ??
                         (data is List ? data : null) ??
                         <dynamic>[];

          if (shares is List) {
            for (final share in shares) {
              if (share is Map<String, dynamic>) {
                final name = share['name']?.toString() ??
                             share['share_name']?.toString() ??
                             share['volume_name']?.toString() ??
                             share['folder_name']?.toString() ??
                             '';
                if (name.isEmpty) continue;

                final path = share['path']?.toString() ??
                             share['mount_point']?.toString() ??
                             share['share_path']?.toString() ??
                             '/$name';
                items.add(UGreenFileInfo(
                  name: name,
                  path: path,
                  isDir: true,
                ));
              }
            }
          }

          if (items.isNotEmpty) {
            logger.i('UGreenApi: 找到 ${items.length} 个共享文件夹 (使用 $endpoint)');
            return items;
          }
        }
      } on Exception catch (e, st) {
        AppError.ignore(e, st, '尝试不同的共享 API 端点，失败是预期的');
      }
    }

    // 所有共享端点都失败，尝试直接列出根目录 (使用不同的路径格式)
    logger.i('UGreenApi: 共享端点都失败，尝试直接列出根目录');

    // 尝试不同的根路径
    for (final rootPath in ['/', '/Volume1', '/volume1', '/mnt', '/data']) {
      try {
        final rootFiles = await listDirectory(rootPath);
        if (rootFiles.isNotEmpty) {
          logger.i('UGreenApi: 从 $rootPath 获取到 ${rootFiles.length} 个文件夹');
          // 如果是子目录，调整路径
          if (rootPath != '/') {
            return rootFiles.map((f) => UGreenFileInfo(
              name: f.name,
              path: f.path,
              isDir: f.isDir,
              size: f.size,
              modified: f.modified,
              created: f.created,
              mimeType: f.mimeType,
            )).toList();
          }
          return rootFiles;
        }
      } on Exception catch (e, st) {
        AppError.ignore(e, st, '尝试不同的根路径，失败是预期的');
      }
    }

    // 如果所有尝试都失败，返回空列表而不是硬编码的默认值
    // 这样用户可以知道实际上没有获取到共享文件夹
    logger..e('UGreenApi: 无法获取共享列表！请检查 API 连接和权限')
    ..e('UGreenApi: 你可能需要在 NAS 上创建共享文件夹或检查用户权限');
    return [];
  }

  /// 从存储池 API 获取共享文件夹
  ///
  /// 使用 /ugreen/v1/storage/pool/list 端点获取存储池信息
  /// 然后从中提取共享文件夹路径
  Future<List<UGreenFileInfo>> _getSharesFromStoragePool() async {
    logger.d('UGreenApi: 尝试从存储池获取共享文件夹');

    final response = await _request('/ugreen/v1/storage/pool/list', method: 'GET');
    final respData = response.data;
    logger.i('UGreenApi: storage/pool/list 完整响应 => $respData');

    if (respData is! Map<String, dynamic> || respData['code'] != 200) {
      return [];
    }

    final items = <UGreenFileInfo>[];
    final data = respData['data'];
    final dataMap = data is Map<String, dynamic> ? data : null;

    // 尝试多种可能的响应结构
    // 结构 1: { pools: [ { volumes: [...] } ] }
    final pools = dataMap?['pools'] ?? dataMap?['list'] ?? (data is List ? data : null) ?? <dynamic>[];
    if (pools is List) {
      for (final pool in pools) {
        if (pool is! Map) continue;

        logger.d('UGreenApi: 处理存储池: ${pool['name']} (${pool['id']})');

        // 从池中提取卷/共享
        final volumes = pool['volumes'] ?? pool['shares'] ?? pool['folders'] ?? <dynamic>[];
        if (volumes is List) {
          for (final vol in volumes) {
            if (vol is! Map) continue;

            final name = vol['name']?.toString() ??
                         vol['volume_name']?.toString() ??
                         vol['share_name']?.toString() ??
                         '';
            if (name.isEmpty) continue;

            // 尝试获取路径
            var path = vol['path']?.toString() ??
                       vol['mount_point']?.toString() ??
                       vol['share_path']?.toString();

            // 如果没有路径，根据名称构造
            if (path == null || path.isEmpty) {
              path = '/$name';
            }

            logger.d('UGreenApi: 发现共享: $name => $path');
            items.add(UGreenFileInfo(
              name: name,
              path: path,
              isDir: true,
            ));
          }
        }

        // 有些 UGOS 版本可能将共享文件夹放在 pool 级别
        final shareFolders = pool['share_folders'] ?? pool['shared_folders'] ?? <dynamic>[];
        if (shareFolders is List) {
          for (final folder in shareFolders) {
            if (folder is! Map) continue;

            final name = folder['name']?.toString() ?? '';
            if (name.isEmpty) continue;

            final path = folder['path']?.toString() ?? '/$name';

            logger.d('UGreenApi: 发现共享文件夹: $name => $path');
            items.add(UGreenFileInfo(
              name: name,
              path: path,
              isDir: true,
            ));
          }
        }
      }
    }

    // 结构 2: 直接的共享列表
    final directShares = dataMap?['shares'] ?? dataMap?['volumes'] ?? <dynamic>[];
    if (directShares is List) {
      for (final share in directShares) {
        if (share is! Map) continue;

        final name = share['name']?.toString() ?? '';
        if (name.isEmpty) continue;

        final path = share['path']?.toString() ??
                     share['mount_point']?.toString() ??
                     '/$name';

        // 避免重复
        if (!items.any((item) => item.path == path)) {
          logger.d('UGreenApi: 发现直接共享: $name => $path');
          items.add(UGreenFileInfo(
            name: name,
            path: path,
            isDir: true,
          ));
        }
      }
    }

    return items;
  }

  /// 发送 API 请求（自动处理 token）
  Future<Response<dynamic>> _request(
    String path, {
    Map<String, dynamic>? data,
    String method = 'POST',
  }) async {
    final response = await dio.request<dynamic>(
      path,
      queryParameters: {'token': _token ?? ''},
      data: data,
      options: Options(method: method),
    );

    // 检查 token 是否过期 (code 1024)
    final responseData = response.data;
    if (responseData is Map<String, dynamic> && responseData['code'] == 1024) {
      logger.i('UGreenApi: Token 过期，重新登录');
      if (_username != null && _password != null) {
        final result = await login(username: _username!, password: _password!);
        if (result is UGreenAuthSuccess) {
          // 重试请求
          return dio.request<dynamic>(
            path,
            queryParameters: {'token': _token ?? ''},
            data: data,
            options: Options(method: method),
          );
        }
      }
    }

    return response;
  }

  UGreenFileInfo _parseFileInfo(Map<dynamic, dynamic> file, String parentPath) {
    final name = file['name']?.toString() ?? file['filename']?.toString() ?? '';
    final isDir = file['is_dir'] == true ||
                  file['isdir'] == true ||
                  file['type'] == 'dir' ||
                  file['type'] == 'folder' ||
                  file['type'] == 'directory';

    DateTime? modified;
    // 尝试多种可能的时间字段名
    final modifiedValue = file['modified'] ??
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
    final createdValue = file['created'] ??
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
      size: file['size'] as int?,
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
