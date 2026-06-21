import 'package:dio/dio.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/errors/exceptions.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';

/// QNAP QTS API 客户端
class QnapApi {
  QnapApi({required Dio dio}) : _dio = dio;

  final Dio _dio;
  String? _sid;

  /// 当前会话ID
  String? get sessionId => _sid;

  /// 会话是否有效
  bool get hasSession => _sid != null;

  /// 清除会话
  void clearSession() {
    _sid = null;
  }

  /// 登录认证
  Future<QnapAuthResult> login({
    required String account,
    required String password,
    String? otpCode,
    bool rememberMe = false,
  }) async {
    logger..i('QnapApi: 开始登录认证')
    ..d('QnapApi: 账号 => $account, OTP => ${otpCode != null ? "有" : "无"}');

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/cgi-bin/authLogin.cgi',
        data: FormData.fromMap({
          'user': account,
          'pwd': _encodePassword(password),
          'otp_code': ?otpCode,
          'remme': rememberMe ? '1' : '0',
        }),
        options: Options(
          contentType: 'application/x-www-form-urlencoded',
        ),
      );

      final data = response.data;
      logger.d('QnapApi: 登录响应 => $data');

      if (data == null) {
        return QnapAuthFailure(error: appL10n.qnapApiServerEmptyResponse);
      }

      // QNAP 返回 authPassed = 1 表示成功
      final authPassed = data['authPassed'] as int? ?? 0;

      if (authPassed == 1) {
        _sid = data['authSid'] as String?;
        if (_sid == null) {
          return QnapAuthFailure(error: appL10n.qnapApiNoSessionId);
        }

        logger.i('QnapApi: 登录成功, sid => ${_sid!.substring(0, 8)}...');
        return QnapAuthSuccess(sid: _sid!);
      }

      // 检查是否需要2FA
      final need2FA = data['need_otp'] == 1 || data['authCode'] == 5;
      if (need2FA) {
        logger.i('QnapApi: 需要二次验证');
        return const QnapAuthRequires2FA();
      }

      // 处理其他错误
      final errorCode = data['authCode'] as int? ?? -1;
      final errorMsg = _getAuthErrorMessage(errorCode);
      logger.w('QnapApi: 登录失败, 错误码 => $errorCode, 消息 => $errorMsg');
      return QnapAuthFailure(error: errorMsg);
    } catch (e, st) {
      AppError.handle(e, st, 'QnapApi.login');
      rethrow;
    }
  }

  /// 登出
  Future<void> logout() async {
    if (_sid == null) return;

    try {
      await _dio.get<dynamic>(
        '/cgi-bin/authLogout.cgi',
        queryParameters: {'sid': _sid},
      );
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '登出时发生错误不影响操作');
    } finally {
      _sid = null;
    }
  }

  /// 获取系统信息
  Future<QnapSystemInfo> getSystemInfo() async {
    final response = await _request(
      '/cgi-bin/management/manaRequest.cgi',
      params: {
        'subfunc': 'sysinfo',
        'sysInfo': '1',
      },
    );

    final data = response is Map<String, dynamic>
        ? response
        : <String, dynamic>{};
    return QnapSystemInfo(
      hostname: data['hostname'] as String? ?? 'QNAP',
      model: data['model'] as String?,
      version: data['version'] as String?,
      serial: data['serialNumber'] as String?,
    );
  }

  /// 列出共享文件夹
  Future<List<QnapShareFolder>> listShareFolders() async {
    final response = await _request(
      '/cgi-bin/filemanager/utilRequest.cgi',
      params: {
        'func': 'get_tree',
        'is_iso': '0',
        'node': 'share_root',
      },
    );

    final items = response as List<dynamic>? ?? [];
    return items.map((item) {
      final map = item as Map<String, dynamic>;
      return QnapShareFolder(
        name: map['text'] as String? ?? '',
        path: '/${map['id'] ?? map['text']}',
        iconCls: map['iconCls'] as String?,
      );
    }).toList();
  }

  /// 列出目录内容
  Future<List<QnapFile>> listFiles({
    required String folderPath,
    int start = 0,
    int limit = 100,
    String sortBy = 'filename',
    String sortDirection = 'ASC',
  }) async {
    final response = await _request(
      '/cgi-bin/filemanager/utilRequest.cgi',
      params: {
        'func': 'get_list',
        'path': folderPath,
        'list_mode': 'all',
        'start': start.toString(),
        'limit': limit.toString(),
        'sort': sortBy,
        'dir': sortDirection,
        'is_iso': '0',
      },
    );

    final data = response as Map<String, dynamic>? ?? {};
    final datas = data['datas'] as List<dynamic>? ?? [];

    // 调试：打印原始数据中的文件大小字段
    if (datas.isNotEmpty) {
      final sample = datas.first as Map<String, dynamic>;
      logger.d('QnapApi listFiles 原始数据样本: filesize=${sample['filesize']}, size=${sample['size']}');
    }

    return datas.map((item) => QnapFile.fromJson(item as Map<String, dynamic>)).toList();
  }

  /// 获取文件信息
  Future<QnapFile> getFileInfo(String path) async {
    final response = await _request(
      '/cgi-bin/filemanager/utilRequest.cgi',
      params: {
        'func': 'stat',
        'path': path,
      },
    );

    return QnapFile.fromJson(response as Map<String, dynamic>);
  }

  /// 创建文件夹
  Future<void> createFolder({
    required String folderPath,
    required String name,
  }) async {
    await _request(
      '/cgi-bin/filemanager/utilRequest.cgi',
      params: {
        'func': 'createdir',
        'dest_path': folderPath,
        'dest_folder': name,
      },
    );
  }

  /// 删除文件/文件夹
  Future<void> deleteFiles(List<String> paths) async {
    final pathList = paths.join(',');
    await _request(
      '/cgi-bin/filemanager/utilRequest.cgi',
      params: {
        'func': 'delete',
        'path': pathList,
      },
    );
  }

  /// 重命名
  Future<void> rename({
    required String path,
    required String newName,
  }) async {
    await _request(
      '/cgi-bin/filemanager/utilRequest.cgi',
      params: {
        'func': 'rename',
        'path': path,
        'new_name': newName,
      },
    );
  }

  /// 复制文件/文件夹
  Future<void> copyFiles({
    required List<String> sourcePaths,
    required String destPath,
    bool overwrite = false,
  }) async {
    await _request(
      '/cgi-bin/filemanager/utilRequest.cgi',
      params: {
        'func': 'copy',
        'source_path': sourcePaths.join(','),
        'dest_path': destPath,
        'mode': overwrite ? '1' : '0',
      },
    );
  }

  /// 移动文件/文件夹
  Future<void> moveFiles({
    required List<String> sourcePaths,
    required String destPath,
    bool overwrite = false,
  }) async {
    await _request(
      '/cgi-bin/filemanager/utilRequest.cgi',
      params: {
        'func': 'move',
        'source_path': sourcePaths.join(','),
        'dest_path': destPath,
        'mode': overwrite ? '1' : '0',
      },
    );
  }

  /// 获取文件下载链接
  String getDownloadUrl(String path) {
    final params = {
      'func': 'download',
      'source_path': path,
      'sid': _sid ?? '',
    };

    final queryString =
        params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');

    return '${_dio.options.baseUrl}/cgi-bin/filemanager/utilRequest.cgi?$queryString';
  }

  /// 列出指定目录下的媒体文件
  ///
  /// 复用 File Station 的 `get_list`，通过 `type` 参数按媒体类型过滤：
  /// 1=音乐, 2=视频, 3=照片（QNAP File Station HTTP API 文档定义）。
  /// 仅返回文件（不含子目录），用于媒体库浏览。
  Future<List<QnapFile>> listMediaFiles({
    required String folderPath,
    required QnapMediaType mediaType,
    int start = 0,
    int limit = 100,
    String sortBy = 'filename',
    String sortDirection = 'ASC',
  }) async {
    final response = await _request(
      '/cgi-bin/filemanager/utilRequest.cgi',
      params: {
        'func': 'get_list',
        'path': folderPath,
        'list_mode': 'all',
        'type': mediaType.code.toString(),
        'start': start.toString(),
        'limit': limit.toString(),
        'sort': sortBy,
        'dir': sortDirection,
        'is_iso': '0',
        'hidden_file': '0',
      },
    );

    final data = response as Map<String, dynamic>? ?? {};
    final datas = data['datas'] as List<dynamic>? ?? [];

    return datas
        .map((item) => QnapFile.fromJson(item as Map<String, dynamic>))
        .where((f) => !f.isDir)
        .toList();
  }

  /// 构造媒体播放/转码流 URL
  ///
  /// 使用 File Station 文档中的 `get_viewer` 接口。`format` 为空时返回原始
  /// 文件流（直接 download），否则请求转码格式（mp4_360 / mp4_720 / flv_720）。
  /// URL 中携带当前 sid，可直接交给播放器加载。
  String getMediaStreamUrl(
    String path, {
    String? format,
  }) {
    final lastSlash = path.lastIndexOf('/');
    final sourcePath = lastSlash > 0 ? path.substring(0, lastSlash) : '/';
    final sourceFile = lastSlash >= 0 ? path.substring(lastSlash + 1) : path;

    final params = <String, String>{
      'func': 'get_viewer',
      'source_path': sourcePath,
      'source_file': sourceFile,
      'player': '1',
      'sid': _sid ?? '',
      if (format != null && format.isNotEmpty) 'format': format,
    };

    final queryString = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');

    return '${_dio.options.baseUrl}/cgi-bin/filemanager/utilRequest.cgi?$queryString';
  }

  /// 获取缩略图链接
  String getThumbnailUrl(String path, {String size = 'small'}) {
    final sizeValue = switch (size) {
      'small' => '80',
      'medium' => '160',
      'large' => '320',
      'xl' => '640',
      _ => '80',
    };

    final params = {
      'func': 'get_thumb',
      'path': path,
      'size': sizeValue,
      'sid': _sid ?? '',
    };

    final queryString =
        params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');

    return '${_dio.options.baseUrl}/cgi-bin/filemanager/utilRequest.cgi?$queryString';
  }

  /// 通过 URL 获取数据流
  ///
  /// 用于在需要绕过证书验证等场景下，通过已知 URL 获取数据
  Future<Stream<List<int>>> getUrlStream(String url) async {
    logger.d('QnapApi: getUrlStream => $url');

    final response = await _dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
      ),
    );

    if (response.data == null) {
      throw Exception(appL10n.qnapApiGetUrlStreamFailed);
    }

    return response.data!.stream;
  }

  /// 搜索文件
  Future<List<QnapFile>> searchFiles({
    required String folderPath,
    required String pattern,
    int limit = 100,
  }) async {
    final response = await _request(
      '/cgi-bin/filemanager/utilRequest.cgi',
      params: {
        'func': 'search',
        'path': folderPath,
        'keyword': pattern,
        'limit': limit.toString(),
      },
    );

    final data = response as Map<String, dynamic>? ?? {};
    final datas = data['datas'] as List<dynamic>? ?? [];

    return datas.map((item) => QnapFile.fromJson(item as Map<String, dynamic>)).toList();
  }

  /// 上传文件
  Future<void> uploadFile({
    required String localPath,
    required String destFolderPath,
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    final file = MultipartFile.fromFileSync(
      localPath,
      filename: fileName,
    );

    final formData = FormData.fromMap({
      'func': 'upload',
      'dest_path': destFolderPath,
      'overwrite': '1',
      'sid': _sid ?? '',
      'file': file,
    });

    logger.i('QnapApi: 开始上传文件到 $destFolderPath');

    final response = await _dio.post<Map<String, dynamic>>(
      '/cgi-bin/filemanager/utilRequest.cgi',
      data: formData,
      onSendProgress: onProgress,
    );

    final data = response.data;
    if (data == null || data['status'] != 1) {
      throw ServerException(
        message: data?['msg'] as String? ?? appL10n.qnapApiUploadFailed,
      );
    }

    logger.i('QnapApi: 文件上传成功');
  }

  /// 写入字节数据到远程文件
  ///
  /// 直接将内存中的字节数据写入到远程文件
  /// [remotePath] 远程文件完整路径（包含文件名）
  /// [data] 要写入的字节数据
  Future<void> writeFileData(String remotePath, List<int> data) async {
    // 获取目录和文件名
    final lastSlash = remotePath.lastIndexOf('/');
    final destFolderPath = lastSlash > 0 ? remotePath.substring(0, lastSlash) : '/';
    final fileName = lastSlash >= 0 ? remotePath.substring(lastSlash + 1) : remotePath;

    // 使用 MultipartFile.fromBytes
    final file = MultipartFile.fromBytes(data, filename: fileName);

    final formData = FormData.fromMap({
      'func': 'upload',
      'dest_path': destFolderPath,
      'overwrite': '1',
      'sid': _sid ?? '',
      'file': file,
    });

    logger.d('QnapApi: 写入文件到 $remotePath (${data.length} bytes)');

    final response = await _dio.post<Map<String, dynamic>>(
      '/cgi-bin/filemanager/utilRequest.cgi',
      data: formData,
    );

    final responseData = response.data;
    if (responseData == null || responseData['status'] != 1) {
      throw ServerException(
        message: responseData?['msg'] as String? ?? appL10n.qnapApiWriteFailed,
      );
    }

    logger.d('QnapApi: 文件写入成功');
  }

  /// 通用请求方法
  Future<dynamic> _request(
    String path, {
    Map<String, String>? params,
  }) async {
    final queryParams = <String, String>{
      'sid': ?_sid,
      ...?params,
    };

    logger.d('QnapApi: 请求 => $path');

    try {
      final response = await _dio.get<dynamic>(
        path,
        queryParameters: queryParams,
      );

      final data = response.data;
      logger.d('QnapApi: 响应状态码 => ${response.statusCode}');

      if (data == null) {
        logger.e('QnapApi: 服务器返回空数据');
        throw ServerException(message: appL10n.qnapApiServerEmptyResponse);
      }

      // 检查是否为错误响应
      if (data is Map<String, dynamic>) {
        final status = data['status'] as int?;
        if (status != null && status != 1) {
          final errorMsg = data['msg'] as String? ?? appL10n.qnapApiOperationFailed;
          logger.e('QnapApi: API 错误 => $errorMsg');
          throw ServerException(message: errorMsg);
        }
      }

      return data;
    } on DioException catch (e, st) {
      AppError.handle(e, st, 'QnapApi._request');
      rethrow;
    }
  }

  /// 编码密码 (Base64)
  String _encodePassword(String password) => Uri.encodeComponent(password);

  /// 获取认证错误消息
  String _getAuthErrorMessage(int errorCode) => switch (errorCode) {
        0 => appL10n.qnapApiAuthFailed,
        1 => appL10n.qnapApiInvalidCredentials,
        2 => appL10n.qnapApiAccountDisabled,
        3 => appL10n.qnapApiInsufficientPermission,
        4 => appL10n.qnapApiConnectionLimitReached,
        5 => appL10n.qnapApiRequires2FA,
        6 => appL10n.qnapApi2FAFailed,
        7 => appL10n.qnapApiIPBlocked,
        _ => appL10n.qnapApiAuthFailedWithCode(errorCode),
      };
}

/// 认证结果
sealed class QnapAuthResult {
  const QnapAuthResult();
}

class QnapAuthSuccess extends QnapAuthResult {
  const QnapAuthSuccess({required this.sid});
  final String sid;
}

class QnapAuthFailure extends QnapAuthResult {
  const QnapAuthFailure({required this.error});
  final String error;
}

class QnapAuthRequires2FA extends QnapAuthResult {
  const QnapAuthRequires2FA();
}

/// QNAP File Station 媒体类型过滤值
///
/// 对应 `get_list` 的 `type` 参数：1=音乐 2=视频 3=照片。
enum QnapMediaType {
  music(1),
  video(2),
  photo(3);

  const QnapMediaType(this.code);

  final int code;
}

/// QNAP 系统信息
class QnapSystemInfo {
  const QnapSystemInfo({
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

/// QNAP 共享文件夹
class QnapShareFolder {
  const QnapShareFolder({
    required this.name,
    required this.path,
    this.iconCls,
  });

  final String name;
  final String path;
  final String? iconCls;
}

/// QNAP 文件
class QnapFile {
  const QnapFile({
    required this.name,
    required this.path,
    required this.isDir,
    this.size = 0,
    this.createTime,
    this.modifyTime,
    this.mimeType,
    this.owner,
    this.group,
  });

  factory QnapFile.fromJson(Map<String, dynamic> json) {
    final isDir = json['isfolder'] == 1 ||
        json['isdir'] == 1 ||
        json['filetype'] == 'folder';

    return QnapFile(
      name: json['filename'] as String? ?? json['text'] as String? ?? '',
      path: json['path'] as String? ??
          json['real_path'] as String? ??
          '/${json['filename'] ?? json['text'] ?? ''}',
      isDir: isDir,
      size: _parseSize(json['filesize'] ?? json['size']),
      createTime: _parseTime(json['epochcreate'] ?? json['create_time']),
      modifyTime: _parseTime(json['epochmt'] ?? json['modify_time']),
      mimeType: json['mimetype'] as String?,
      owner: json['owner'] as String?,
      group: json['group'] as String?,
    );
  }

  final String name;
  final String path;
  final bool isDir;
  final int size;
  final DateTime? createTime;
  final DateTime? modifyTime;
  final String? mimeType;
  final String? owner;
  final String? group;

  static int _parseSize(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static DateTime? _parseTime(dynamic value) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    if (value is String) {
      final intValue = int.tryParse(value);
      if (intValue != null) {
        return DateTime.fromMillisecondsSinceEpoch(intValue * 1000);
      }
    }
    return null;
  }
}
