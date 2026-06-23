import 'package:dio/dio.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart' show ThumbnailSize;

/// 飞牛 NAS API 认证结果
sealed class FnOSAuthResult {}

class FnOSAuthSuccess extends FnOSAuthResult {
  FnOSAuthSuccess({
    required this.token,
    this.userId,
    this.nickname,
  });

  final String token;
  final String? userId;
  final String? nickname;
}

class FnOSAuthFailure extends FnOSAuthResult {
  FnOSAuthFailure({required this.error, this.code});

  final String error;
  final int? code;
}

class FnOSAuthRequires2FA extends FnOSAuthResult {
  FnOSAuthRequires2FA({this.methods = const ['totp']});

  final List<String> methods;
}

/// 飞牛 NAS 设备信息
class FnOSDeviceInfo {
  const FnOSDeviceInfo({
    required this.hostname,
    this.model,
    this.version,
    this.serial,
  });

  final String hostname;
  final String? model;
  final String? version;
  final String? serial;
}

/// 飞牛 NAS 文件信息
class FnOSFileInfo {
  const FnOSFileInfo({
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

/// 飞牛 NAS (fnOS) API 接口
///
/// fnOS 是基于 Debian 的国产 NAS 系统
/// 默认端口: 5666 (Web管理界面)
/// WebDAV: 5005/5006
/// SMB: 445
class FnOSApi {
  FnOSApi({required this.dio});

  final Dio dio;
  String? _token;

  /// 是否已认证
  bool get isAuthenticated => _token != null;

  /// 当前 token
  String? get token => _token;

  /// 登录认证
  ///
  /// fnOS 使用 WebSocket 和 HTTP API 混合方式
  /// 主要端点尝试顺序:
  /// 1. /api/v1/auth/login
  /// 2. /api/auth/login
  /// 3. /user/login
  Future<FnOSAuthResult> login({
    required String username,
    required String password,
    String? otpCode,
  }) async {
    logger..i('FnOSApi: 开始登录认证')
    ..i('FnOSApi: 用户名 => $username');


    // 尝试多种登录端点
    final loginAttempts = [
      // 尝试 1: API v1 登录
      {
        'endpoint': '/api/v1/auth/login',
        'data': {
          'username': username,
          'password': password,
          'otp_code': ?otpCode,
        },
      },
      // 尝试 2: 简单 API 登录
      {
        'endpoint': '/api/auth/login',
        'data': {
          'username': username,
          'password': password,
          'otp': ?otpCode,
        },
      },
      // 尝试 3: 用户登录
      {
        'endpoint': '/user/login',
        'data': {
          'user': username,
          'passwd': password,
          'otp': ?otpCode,
        },
      },
      // 尝试 4: JSON-RPC 风格
      {
        'endpoint': '/api',
        'data': {
          'method': 'user.login',
          'params': {
            'username': username,
            'password': password,
            'otp': ?otpCode,
          },
        },
      },
    ];

    for (final attempt in loginAttempts) {
      try {
        final endpoint = attempt['endpoint']! as String;
        final data = attempt['data']! as Map<String, dynamic>;

        logger.d('FnOSApi: 尝试登录端点 => $endpoint');

        final response = await dio.post<dynamic>(
          endpoint,
          data: data,
          options: Options(
            validateStatus: (status) => status != null && status < 500,
          ),
        );

        // 不记录 response.data：登录响应含 token，日志会落盘到 app.log。
        logger.d('FnOSApi: 登录响应 ($endpoint) status=${response.statusCode}');

        final result = _parseLoginResponse(response.data);
        if (result is FnOSAuthSuccess) {
          _token = result.token;
          logger.i('FnOSApi: 登录成功 (使用 $endpoint)');
          return result;
        }

        // 需要 2FA
        if (result is FnOSAuthRequires2FA) {
          return result;
        }

        // 继续尝试下一个端点
      } on DioException catch (e) {
        logger.w('FnOSApi: 端点 ${attempt['endpoint']} 失败: ${e.message}');
      } on Exception catch (e) {
        logger.w('FnOSApi: 登录尝试失败', e);
      }
    }

    return FnOSAuthFailure(error: appL10n.fnosApiLoginFailedDefault);
  }

  FnOSAuthResult _parseLoginResponse(dynamic data) {
    if (data is! Map) {
      return FnOSAuthFailure(error: appL10n.fnosApiResponseFormatError);
    }

    // 检查成功响应
    final code = data['code'] ?? data['status'] ?? data['error_code'];
    if (code == 200 || code == 0 || data['success'] == true) {
      // 尝试提取 token
      final rawTokenData = data['data'] ?? data['result'] ?? data;
      final tokenData = rawTokenData is Map<String, dynamic>
          ? rawTokenData
          : <String, dynamic>{};
      final token = tokenData['token']?.toString() ??
          tokenData['access_token']?.toString() ??
          tokenData['session_id']?.toString() ??
          tokenData['sid']?.toString();

      if (token != null && token.isNotEmpty) {
        return FnOSAuthSuccess(
          token: token,
          userId: tokenData['user_id']?.toString() ?? tokenData['uid']?.toString(),
          nickname: tokenData['nickname']?.toString() ?? tokenData['name']?.toString(),
        );
      }
    }

    // 检查 2FA
    if (data['require_2fa'] == true ||
        data['need_otp'] == true ||
        code == 1001 ||
        code == 401 && (data['message']?.toString().contains('2fa') ?? false)) {
      return FnOSAuthRequires2FA();
    }

    // 错误
    final message = data['message']?.toString() ??
        data['msg']?.toString() ??
        data['error']?.toString() ??
        appL10n.fnosApiLoginFailedWithCode(code.toString());

    return FnOSAuthFailure(error: message, code: code as int?);
  }

  /// 登出
  Future<void> logout() async {
    if (_token == null) return;

    try {
      await dio.post<dynamic>(
        '/api/v1/auth/logout',
        options: _authOptions(),
      );
    } on Exception catch (e) {
      logger.w('FnOSApi: 登出请求失败', e);
    } finally {
      _token = null;
    }
  }

  /// 获取设备信息
  Future<FnOSDeviceInfo> getDeviceInfo() async {
    try {
      final response = await _request('/api/v1/system/info');
      final data = response.data;

      if (data is Map<String, dynamic>) {
        final info = data['data'] as Map<String, dynamic>? ?? data;
        return FnOSDeviceInfo(
          hostname: info['hostname']?.toString() ??
              info['device_name']?.toString() ??
              'fnOS NAS',
          model: info['model']?.toString(),
          version: info['version']?.toString() ?? info['os_version']?.toString(),
          serial: info['serial']?.toString(),
        );
      }
    } on Exception catch (e) {
      logger.w('FnOSApi: 获取设备信息失败', e);
    }

    return const FnOSDeviceInfo(hostname: 'fnOS NAS');
  }

  /// 列出目录内容
  Future<List<FnOSFileInfo>> listDirectory(String path) async {
    logger.i('FnOSApi: 列出目录 => $path');

    // 尝试多种文件列表 API
    final attempts = [
      // 尝试 1: 文件管理器 API
      {
        'endpoint': '/api/v1/file/list',
        'params': {'path': path, 'page': 1, 'limit': 1000},
      },
      // 尝试 2: 文件管理
      {
        'endpoint': '/api/file/list',
        'params': {'dir': path, 'offset': 0, 'limit': 1000},
      },
      // 尝试 3: 文件浏览
      {
        'endpoint': '/api/v1/filebrowser/list',
        'params': {'path': path},
      },
      // 尝试 4: JSON-RPC 风格
      {
        'endpoint': '/api',
        'method': 'POST',
        'data': {
          'method': 'file.list',
          'params': {'path': path},
        },
      },
    ];

    for (final attempt in attempts) {
      try {
        final endpoint = attempt['endpoint']! as String;
        Response<dynamic> response;

        if (attempt['method'] == 'POST') {
          response = await _request(endpoint, data: attempt['data'] as Map<String, dynamic>?);
        } else {
          response = await _request(endpoint, params: attempt['params'] as Map<String, dynamic>?);
        }

        final data = response.data;
        logger.d('FnOSApi: listDirectory 响应 ($endpoint) => $data');

        if (data is Map<String, dynamic>) {
          final code = data['code'] ?? data['status'];
          if (code == 200 || code == 0 || data['success'] == true) {
            final items = <FnOSFileInfo>[];
            final respData = data['data'];
            final dataMap = respData is Map<String, dynamic> ? respData : null;
            final files = dataMap?['list'] ??
                dataMap?['files'] ??
                dataMap?['items'] ??
                respData ??
                data['result'] ??
                <dynamic>[];

            if (files is List) {
              for (final file in files) {
                if (file is Map<String, dynamic>) {
                  items.add(_parseFileInfo(file, path));
                }
              }
            }

            if (items.isNotEmpty) {
              logger.i('FnOSApi: 找到 ${items.length} 个文件 (使用 $endpoint)');
              return items;
            }
          }
        }
      } on Exception catch (e) {
        logger.w('FnOSApi: 端点尝试失败', e);
      }
    }

    logger.e('FnOSApi: 所有文件列表端点都失败了');
    return [];
  }

  /// 获取共享文件夹列表
  Future<List<FnOSFileInfo>> listShares() async {
    logger.i('FnOSApi: 获取共享文件夹列表');

    // 尝试多种共享端点
    final attempts = [
      '/api/v1/storage/share/list',
      '/api/v1/share/list',
      '/api/storage/shares',
    ];

    for (final endpoint in attempts) {
      try {
        final response = await _request(endpoint);
        final data = response.data;

        logger.d('FnOSApi: listShares 响应 ($endpoint) => $data');

        if (data is Map<String, dynamic>) {
          final code = data['code'] ?? data['status'];
          if (code == 200 || code == 0 || data['success'] == true) {
            final items = <FnOSFileInfo>[];
            final respData = data['data'];
            final dataMap = respData is Map<String, dynamic> ? respData : null;
            final shares = dataMap?['list'] ??
                dataMap?['shares'] ??
                respData ??
                <dynamic>[];

            if (shares is List) {
              for (final share in shares) {
                if (share is Map<String, dynamic>) {
                  final name = share['name']?.toString() ??
                      share['share_name']?.toString() ??
                      '';
                  if (name.isEmpty) continue;

                  final path = share['path']?.toString() ??
                      share['mount_point']?.toString() ??
                      '/$name';

                  items.add(FnOSFileInfo(
                    name: name,
                    path: path,
                    isDir: true,
                  ));
                }
              }
            }

            if (items.isNotEmpty) {
              logger.i('FnOSApi: 找到 ${items.length} 个共享文件夹');
              return items;
            }
          }
        }
      } on Exception catch (e) {
        logger.w('FnOSApi: 端点 $endpoint 失败', e);
      }
    }

    // 尝试直接列出根目录
    logger.i('FnOSApi: 尝试直接列出根目录');
    return listDirectory('/');
  }

  /// 获取文件下载链接
  Future<String> getFileUrl(String path) async {
    final baseUrl = dio.options.baseUrl;
    final encodedPath = Uri.encodeComponent(path);
    return '$baseUrl/api/v1/file/download?path=$encodedPath&token=$_token';
  }

  /// 获取缩略图 URL
  String? getThumbnailUrl(String path, {ThumbnailSize? size}) {
    if (_token == null) return null;

    final baseUrl = dio.options.baseUrl;
    final encodedPath = Uri.encodeComponent(path);
    final sizeParam = switch (size) {
      ThumbnailSize.small => 'small',
      ThumbnailSize.medium => 'medium',
      ThumbnailSize.large => 'large',
      ThumbnailSize.xlarge => 'xlarge',
      null => 'medium',
    };
    return '$baseUrl/api/v1/file/thumbnail?path=$encodedPath&size=$sizeParam&token=$_token';
  }

  /// 通过 URL 获取数据流
  ///
  /// 用于在需要绕过证书验证等场景下，通过已知 URL 获取数据
  Future<Stream<List<int>>> getUrlStream(String url) async {
    logger.d('FnOSApi: getUrlStream => $url');

    final response = await dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
      ),
    );

    if (response.data == null) {
      throw Exception(appL10n.fnosApiFileStreamEmpty);
    }

    return response.data!.stream;
  }

  /// 创建目录
  Future<void> createDirectory(String path) async {
    await _request(
      '/api/v1/file/mkdir',
      data: {'path': path},
    );
  }

  /// 删除文件或目录
  Future<void> delete(String path) async {
    await _request(
      '/api/v1/file/delete',
      data: {'paths': [path]},
    );
  }

  /// 重命名
  Future<void> rename(String oldPath, String newPath) async {
    await _request(
      '/api/v1/file/rename',
      data: {
        'old_path': oldPath,
        'new_path': newPath,
      },
    );
  }

  /// 服务端复制
  ///
  /// 飞牛 NAS API `/api/v1/file/copy`，传 srcs（源路径列表）+ dst（目标父目录）。
  /// 调用方失败时应回退到客户端下载+上传。
  Future<void> copy(String sourcePath, String destPath) async {
    final lastSlash = destPath.lastIndexOf('/');
    final destParent = lastSlash > 0 ? destPath.substring(0, lastSlash) : '/';
    final destName = lastSlash >= 0 ? destPath.substring(lastSlash + 1) : destPath;
    await _request(
      '/api/v1/file/copy',
      data: {
        'srcs': [sourcePath],
        'dst': destParent,
        'new_name': destName,
      },
    );
  }

  /// 上传字节数据 (multipart)
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
      '/api/v1/file/upload',
      data: form,
      onSendProgress: onProgress,
      options: Options(
        contentType: 'multipart/form-data',
        headers: _token != null ? {'Authorization': 'Bearer $_token'} : null,
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
      '/api/v1/file/upload',
      data: form,
      onSendProgress: onProgress,
      options: Options(
        contentType: 'multipart/form-data',
        headers: _token != null ? {'Authorization': 'Bearer $_token'} : null,
      ),
    );
  }

  /// 服务端搜索
  Future<List<FnOSFileInfo>> search(String query, {String? path}) async {
    final response = await _request(
      '/api/v1/file/search',
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

  /// 发送 API 请求
  Future<Response<dynamic>> _request(
    String path, {
    Map<String, dynamic>? params,
    Map<String, dynamic>? data,
    String method = 'GET',
  }) async => dio.request<dynamic>(
      path,
      queryParameters: params,
      data: data,
      options: Options(
        method: data != null ? 'POST' : method,
        headers: _token != null
            ? {'Authorization': 'Bearer $_token'}
            : null,
      ),
    );

  Options _authOptions() => Options(
      headers: _token != null
          ? {'Authorization': 'Bearer $_token'}
          : null,
    );

  FnOSFileInfo _parseFileInfo(Map<dynamic, dynamic> file, String parentPath) {
    final name = file['name']?.toString() ?? file['filename']?.toString() ?? '';
    final isDir = file['is_dir'] == true ||
        file['isdir'] == true ||
        file['type'] == 'dir' ||
        file['type'] == 'folder' ||
        file['type'] == 'directory';

    DateTime? modified;
    final modifiedValue = file['modified'] ??
        file['mtime'] ??
        file['modify_time'] ??
        file['last_modified'];
    if (modifiedValue != null) {
      modified = _parseDateTime(modifiedValue);
    }

    DateTime? created;
    final createdValue = file['created'] ?? file['ctime'] ?? file['create_time'];
    if (createdValue != null) {
      created = _parseDateTime(createdValue);
    }

    return FnOSFileInfo(
      name: name,
      path: file['path']?.toString() ?? '$parentPath/$name',
      isDir: isDir,
      size: file['size'] as int?,
      modified: modified,
      created: created,
      mimeType: file['mime_type']?.toString() ?? file['mimetype']?.toString(),
    );
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;

    if (value is int) {
      // Unix 时间戳
      if (value < 10000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      } else {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
    } else if (value is String) {
      return DateTime.tryParse(value);
    }

    return null;
  }
}
