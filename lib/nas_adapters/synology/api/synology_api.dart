import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/errors/exceptions.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 会话刷新回调类型
/// 返回新的 session ID，如果刷新失败则返回 null
typedef SessionRefreshCallback = Future<String?> Function();

/// Synology DSM API 客户端
class SynologyApi {
  SynologyApi({required Dio dio}) : _dio = dio;

  final Dio _dio;
  String? _sid;

  /// 会话刷新回调
  SessionRefreshCallback? _onSessionRefresh;

  /// 是否正在刷新会话（防止并发刷新）
  bool _isRefreshing = false;

  /// 当前会话ID（用于调试）
  String? get sessionId => _sid;

  /// 会话是否有效
  bool get hasSession => _sid != null;

  /// 设置会话刷新回调
  void setSessionRefreshCallback(SessionRefreshCallback? callback) {
    _onSessionRefresh = callback;
  }

  /// 清除会话
  void clearSession() {
    _sid = null;
  }

  /// 确保会话有效
  ///
  /// 在执行耗时操作（如大文件上传）前调用，
  /// 通过轻量级 API 调用来验证会话是否有效，
  /// 如果会话已过期，会自动触发刷新机制。
  ///
  /// 这对于移动端特别重要，因为下载大文件可能需要较长时间，
  /// 期间会话可能已经超时。
  Future<void> ensureSession() async {
    if (_sid == null) return;

    try {
      // 使用轻量级的 API 调用来验证会话
      // _request 内部会处理会话过期并自动刷新
      await _request(
        'SYNO.FileStation.Info',
        'get',
        version: 1,
      );
      logger.d('SynologyApi: 会话验证成功');
    } on Exception catch (e) {
      // 如果验证失败（可能是网络问题），记录日志但不抛出异常
      // 后续的实际操作如果失败会有自己的重试机制
      logger.w('SynologyApi: 会话验证失败，继续尝试操作', e);
    }
  }

  /// 检查是否是会话过期错误
  bool _isSessionExpiredError(int? errorCode) =>
      errorCode == 106 || errorCode == 119;

  /// API 信息查询
  Future<Map<String, dynamic>> queryApiInfo() async {
    final response = await _request(
      'SYNO.API.Info',
      'query',
      version: 1,
      params: {'query': 'all'},
    );
    return response['data'] as Map<String, dynamic>;
  }

  /// 登录认证
  ///
  /// [deviceName] 设备名称，用于记住设备。设置后，服务器会返回 deviceId
  /// [deviceId] 之前登录返回的设备ID，传入后可以跳过二次验证
  /// [enableDeviceToken] 是否启用设备令牌（记住此设备）
  Future<AuthResult> login({
    required String account,
    required String password,
    String? otpCode,
    String? deviceName,
    String? deviceId,
    bool enableDeviceToken = false,
  }) async {
    logger..i('SynologyApi: 开始登录认证')
    ..d('SynologyApi: 账号 => $account, OTP => ${otpCode != null ? "有" : "无"}')
    ..d('SynologyApi: 设备名 => $deviceName, 设备ID => ${deviceId != null ? "有" : "无"}');

    final params = <String, dynamic>{
      'account': account,
      'passwd': password,
      'format': 'sid',
      // 指定会话名称为 FileStation，确保会话对 FileStation API 有效
      'session': 'FileStation',
    };

    if (otpCode != null) {
      params['otp_code'] = otpCode;
    }

    // 设备记住功能
    if (deviceName != null) {
      params['device_name'] = deviceName;
    }
    if (deviceId != null) {
      params['device_id'] = deviceId;
    }
    if (enableDeviceToken) {
      params['enable_device_token'] = 'yes';
    }

    try {
      // 登录请求需要特殊处理，因为认证错误也会返回 success=false
      final response = await _requestRaw(
        'SYNO.API.Auth',
        'login',
        version: 6,
        params: params,
      );

      logger.d('SynologyApi: 登录响应 => success=${response['success']}');

      if (response['success'] != true) {
        final error = response['error'];
        final errorCode = error is Map<String, dynamic> ? error['code'] as int? : null;
        logger.w('SynologyApi: 登录失败, 错误码 => $errorCode');
        return _handleAuthError(errorCode);
      }

      final data = response['data'] as Map<String, dynamic>;
      _sid = data['sid'] as String;

      logger.i('SynologyApi: 登录成功, sid => ${_sid!.substring(0, 8)}...');

      return AuthSuccess(
        sid: _sid!,
        deviceId: data['did'] as String?,
      );
    } catch (e, st) {
      AppError.handle(e, st, 'SynologyApi.login');
      rethrow;
    }
  }

  /// 登出
  Future<void> logout() async {
    if (_sid == null) return;

    await _request(
      'SYNO.API.Auth',
      'logout',
      version: 1,
      params: {
        'session': 'FileStation',
      },
    );
    _sid = null;
  }

  /// 获取 DSM 信息
  Future<DsmInfo> getDsmInfo() async {
    final response = await _request(
      'SYNO.DSM.Info',
      'getinfo',
      version: 2,
    );

    final data = response['data'] as Map<String, dynamic>;
    return DsmInfo(
      hostname: data['model'] as String? ?? 'Unknown',
      model: data['model'] as String?,
      version: data['version_string'] as String?,
      serial: data['serial'] as String?,
    );
  }

  /// 获取存储卷信息
  ///
  /// 返回所有存储卷的信息，包括总容量和已使用容量
  Future<List<SynoVolumeInfo>> getVolumeInfo() async {
    final response = await _request(
      'SYNO.Core.Storage.Volume',
      'list',
      version: 1,
    );

    final data = response['data'] as Map<String, dynamic>;
    final volumes = data['volumes'] as List<dynamic>? ?? [];

    return volumes
        .map((v) => SynoVolumeInfo.fromJson(v as Map<String, dynamic>))
        .toList();
  }

  /// 列出目录
  /// 返回 [FileListResult] 包含文件列表和总数，用于分页
  Future<FileListResult> listFiles({
    required String folderPath,
    int offset = 0,
    int limit = 100,
    String sortBy = 'name',
    String sortDirection = 'asc',
    List<String> additional = const ['real_path', 'size', 'owner', 'time', 'perm', 'type'],
  }) async {
    // Synology API v2 additional 参数需要 JSON 数组格式: ["real_path","size","owner","time"]
    // 参考: https://stackoverflow.com/questions/61786866/synology-filestation-api
    final additionalParam = '["${additional.join('","')}"]';
    logger.d('SynologyApi listFiles: folder=$folderPath, offset=$offset, limit=$limit');

    final response = await _request(
      'SYNO.FileStation.List',
      'list',
      version: 2,
      params: {
        'folder_path': folderPath,
        'offset': offset,
        'limit': limit,
        'sort_by': sortBy,
        'sort_direction': sortDirection,
        'additional': additionalParam,
      },
    );

    final data = response['data'] as Map<String, dynamic>;
    final files = data['files'] as List<dynamic>? ?? [];
    final total = data['total'] as int? ?? files.length;

    logger.d('SynologyApi listFiles: 获取 ${files.length} 个文件，总计 $total');

    return FileListResult(
      files: files
          .map((f) => FileStationFile.fromJson(f as Map<String, dynamic>))
          .toList(),
      total: total,
      offset: offset,
    );
  }

  /// 获取共享文件夹列表
  Future<List<ShareFolder>> listShareFolders() async {
    final response = await _request(
      'SYNO.FileStation.List',
      'list_share',
      version: 2,
      params: {
        'additional': '["volume_status"]',
      },
    );

    final data = response['data'] as Map<String, dynamic>;
    final shares = data['shares'] as List<dynamic>? ?? [];

    return shares
        .map((s) => ShareFolder.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  /// 获取文件信息
  Future<FileStationFile> getFileInfo(String path) async {
    final response = await _request(
      'SYNO.FileStation.List',
      'getinfo',
      version: 2,
      params: {
        'path': path,
        'additional': '["size","time","type"]',
      },
    );

    final data = response['data'] as Map<String, dynamic>;
    final files = data['files'] as List<dynamic>;
    final fileJson = files.first as Map<String, dynamic>;

    // 检查文件级别的错误码（如文件不存在）
    final fileErrorCode = fileJson['code'] as int?;
    if (fileErrorCode != null) {
      throw ServerException(
        message: _getErrorMessage(fileErrorCode),
        statusCode: fileErrorCode,
      );
    }

    return FileStationFile.fromJson(fileJson);
  }

  /// 创建文件夹
  Future<void> createFolder({
    required String folderPath,
    required String name,
  }) async {
    await _request(
      'SYNO.FileStation.CreateFolder',
      'create',
      version: 2,
      params: {
        'folder_path': folderPath,
        'name': name,
      },
    );
  }

  /// 删除文件/文件夹
  Future<String> deleteFiles(List<String> paths) async {
    final response = await _request(
      'SYNO.FileStation.Delete',
      'start',
      version: 2,
      params: {
        'path': paths.join(','),
        'recursive': true,
      },
    );

    final data = response['data'] as Map<String, dynamic>;
    return data['taskid'] as String;
  }

  /// 重命名
  Future<void> rename({
    required String path,
    required String name,
  }) async {
    await _request(
      'SYNO.FileStation.Rename',
      'rename',
      version: 2,
      params: {
        'path': path,
        'name': name,
      },
    );
  }

  /// 获取文件下载链接
  String getDownloadUrl(String path) {
    final params = {
      'api': 'SYNO.FileStation.Download',
      'version': '2',
      'method': 'download',
      'path': path,
      'mode': 'download',
      if (_sid != null) '_sid': _sid,
    };

    final queryString =
        params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value.toString())}').join('&');

    return '${_dio.options.baseUrl}/webapi/entry.cgi?$queryString';
  }

  /// 获取缩略图链接
  String getThumbnailUrl(String path, {String size = 'small'}) {
    final params = {
      'api': 'SYNO.FileStation.Thumb',
      'version': '2',
      'method': 'get',
      'path': path,
      'size': size,
      if (_sid != null) '_sid': _sid,
    };

    final queryString =
        params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value.toString())}').join('&');

    return '${_dio.options.baseUrl}/webapi/entry.cgi?$queryString';
  }

  /// 获取文件流（用于流式下载）
  ///
  /// [start] 和 [end] 用于范围请求，可选
  Future<Stream<List<int>>> getFileStream(
    String path, {
    int? start,
    int? end,
  }) async {
    final url = getDownloadUrl(path);
    logger.d('SynologyApi: getFileStream => $path');

    final headers = <String, dynamic>{};
    if (start != null || end != null) {
      final rangeStart = start ?? 0;
      final rangeEnd = end != null ? end.toString() : '';
      headers['Range'] = 'bytes=$rangeStart-$rangeEnd';
    }

    final response = await _dio.get<ResponseBody>(
      url,
      options: Options(
        headers: headers,
        responseType: ResponseType.stream,
      ),
    );

    if (response.data == null) {
      throw Exception('获取文件流失败：响应为空');
    }

    return response.data!.stream;
  }

  /// 通过 URL 获取数据流
  ///
  /// 用于在需要绕过证书验证等场景下，通过已知 URL（如缩略图 URL）获取数据
  /// 利用 Dio 的自签名证书支持
  Future<Stream<List<int>>> getUrlStream(String url) async {
    logger.d('SynologyApi: getUrlStream => $url');

    final response = await _dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
      ),
    );

    if (response.data == null) {
      throw Exception('获取 URL 数据流失败：响应为空');
    }

    return response.data!.stream;
  }

  /// 搜索文件
  Future<String> startSearch({
    required String folderPath,
    required String pattern,
  }) async {
    final response = await _request(
      'SYNO.FileStation.Search',
      'start',
      version: 2,
      params: {
        'folder_path': folderPath,
        'pattern': pattern,
      },
    );

    final data = response['data'] as Map<String, dynamic>;
    return data['taskid'] as String;
  }

  /// 获取搜索结果
  Future<SearchResult> getSearchResult(String taskId) async {
    final response = await _request(
      'SYNO.FileStation.Search',
      'list',
      version: 2,
      params: {
        'taskid': taskId,
        'additional': '["size","time","type"]',
      },
    );

    final data = response['data'] as Map<String, dynamic>;
    final files = (data['files'] as List<dynamic>? ?? [])
        .map((f) => FileStationFile.fromJson(f as Map<String, dynamic>))
        .toList();

    return SearchResult(
      files: files,
      finished: data['finished'] as bool? ?? false,
      total: data['total'] as int? ?? 0,
    );
  }

  /// 上传文件
  Future<void> uploadFile({
    required String localPath,
    required String destFolderPath,
    String? fileName,
    bool createParents = true,
    bool overwrite = true,
    void Function(int sent, int total)? onProgress,
    bool allowRetry = true,
  }) async {
    final file = MultipartFile.fromFileSync(
      localPath,
      filename: fileName,
    );

    final formData = FormData.fromMap({
      'api': 'SYNO.FileStation.Upload',
      'version': 2,
      'method': 'upload',
      'path': destFolderPath,
      'create_parents': createParents,
      'overwrite': overwrite,
      if (_sid != null) '_sid': _sid,
      'file': file,
    });

    logger.i('SynologyApi: 开始上传文件到 $destFolderPath');

    final response = await _dio.post<Map<String, dynamic>>(
      '/webapi/entry.cgi',
      data: formData,
      onSendProgress: onProgress,
    );

    final data = response.data;
    if (data == null || data['success'] != true) {
      final error = data?['error'];
      final errorCode = error is Map<String, dynamic> ? error['code'] as int? : null;

      // 检查是否是会话过期错误，尝试刷新会话
      if (allowRetry && _isSessionExpiredError(errorCode)) {
        logger.w('SynologyApi: 上传时会话已过期 (code: $errorCode)，尝试刷新...');
        final refreshed = await _tryRefreshSession();
        if (refreshed) {
          logger.i('SynologyApi: 会话刷新成功，重试上传');
          // 重试上传，但不允许再次重试
          return uploadFile(
            localPath: localPath,
            destFolderPath: destFolderPath,
            fileName: fileName,
            createParents: createParents,
            overwrite: overwrite,
            onProgress: onProgress,
            allowRetry: false,
          );
        }
      }

      throw ServerException(
        message: _getErrorMessage(errorCode),
        statusCode: errorCode,
      );
    }

    logger.i('SynologyApi: 文件上传成功');
  }

  /// 复制文件/文件夹
  Future<String> copyFiles({
    required List<String> paths,
    required String destFolderPath,
    bool overwrite = false,
  }) async {
    final response = await _request(
      'SYNO.FileStation.CopyMove',
      'start',
      version: 3,
      params: {
        'path': paths.join(','),
        'dest_folder_path': destFolderPath,
        'overwrite': overwrite,
        'remove_src': false,
      },
    );

    final data = response['data'] as Map<String, dynamic>;
    return data['taskid'] as String;
  }

  /// 移动文件/文件夹
  Future<String> moveFiles({
    required List<String> paths,
    required String destFolderPath,
    bool overwrite = false,
  }) async {
    final response = await _request(
      'SYNO.FileStation.CopyMove',
      'start',
      version: 3,
      params: {
        'path': paths.join(','),
        'dest_folder_path': destFolderPath,
        'overwrite': overwrite,
        'remove_src': true,
      },
    );

    final data = response['data'] as Map<String, dynamic>;
    return data['taskid'] as String;
  }

  /// 获取复制/移动任务状态
  Future<CopyMoveStatus> getCopyMoveStatus(String taskId) async {
    final response = await _request(
      'SYNO.FileStation.CopyMove',
      'status',
      version: 3,
      params: {
        'taskid': taskId,
      },
    );

    final data = response['data'] as Map<String, dynamic>;
    return CopyMoveStatus(
      finished: data['finished'] as bool? ?? false,
      progress: (data['progress'] as num?)?.toDouble() ?? 0.0,
      destFolderPath: data['dest_folder_path'] as String?,
      path: data['path'] as String?,
    );
  }

  /// 等待复制/移动任务完成
  Future<void> waitForCopyMove(String taskId) async {
    CopyMoveStatus status;
    do {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      status = await getCopyMoveStatus(taskId);
    } while (!status.finished);
  }

  /// 写入字节数据到远程文件
  ///
  /// 直接将内存中的字节数据写入到远程文件
  /// [remotePath] 远程文件完整路径（包含文件名）
  /// [data] 要写入的字节数据
  /// [allowRetry] 是否允许在会话过期时重试
  Future<void> writeFileData(
    String remotePath,
    List<int> data, {
    bool allowRetry = true,
  }) async {
    // 在上传前确保会话有效
    // 这对于移动端特别重要，因为前序操作（如下载大文件）可能耗时较长
    // 导致会话在此期间过期
    await ensureSession();

    // 获取目录和文件名
    final lastSlash = remotePath.lastIndexOf('/');
    final destFolderPath = lastSlash > 0 ? remotePath.substring(0, lastSlash) : '/';
    final fileName = lastSlash >= 0 ? remotePath.substring(lastSlash + 1) : remotePath;

    // 使用 MultipartFile.fromBytes
    final file = MultipartFile.fromBytes(data, filename: fileName);

    // 注意：Synology Upload API 的 _sid 应该放在 query string 中
    // 而不是 form data 中，以确保认证正确处理
    final formData = FormData.fromMap({
      'api': 'SYNO.FileStation.Upload',
      'version': 2,
      'method': 'upload',
      'path': destFolderPath,
      'create_parents': true,
      'overwrite': true,
      'file': file,
    });

    logger.d('SynologyApi: 写入文件到 $remotePath (${data.length} bytes), sid=${_sid?.substring(0, 8)}...');

    final response = await _dio.post<dynamic>(
      '/webapi/entry.cgi',
      data: formData,
      queryParameters: {
        if (_sid != null) '_sid': _sid,
      },
      options: Options(
        // 上传接口响应格式可能不规范，使用纯文本接收后手动解析
        responseType: ResponseType.plain,
        // 不设置 Content-Type，让 Dio 自动处理 multipart
        headers: {
          'Accept': '*/*',
        },
      ),
    );

    // 处理响应数据，可能是 Map 或 String（JSON字符串）
    Map<String, dynamic>? responseData;
    final rawData = response.data;

    if (rawData is Map<String, dynamic>) {
      responseData = rawData;
    } else if (rawData is String && rawData.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawData);
        if (decoded is Map<String, dynamic>) {
          responseData = decoded;
        }
      } on FormatException catch (e) {
        logger.w('SynologyApi: JSON 解析失败: $e, 原始响应: ${rawData.substring(0, rawData.length.clamp(0, 200))}');
      }
    }

    if (responseData == null || responseData['success'] != true) {
      final error = responseData?['error'];
      final errorCode = error is Map<String, dynamic> ? error['code'] as int? : null;

      // 检查是否是会话过期错误，尝试刷新会话
      if (allowRetry && _isSessionExpiredError(errorCode)) {
        logger.w('SynologyApi: 写入时会话已过期 (code: $errorCode)，尝试刷新...');
        final refreshed = await _tryRefreshSession();
        if (refreshed) {
          // 等待一小段时间，确保会话在 File Station 服务中生效
          // Synology 的各个服务之间可能存在会话传播延迟
          await Future<void>.delayed(const Duration(milliseconds: 500));
          logger.i('SynologyApi: 会话刷新成功，重试写入');
          // 重试写入，但不允许再次重试
          return writeFileData(remotePath, data, allowRetry: false);
        }
      }

      logger.e('SynologyApi: 写入失败, error=$error, code=$errorCode');
      throw ServerException(
        message: _getErrorMessage(errorCode),
        statusCode: errorCode,
      );
    }

    logger.d('SynologyApi: 文件写入成功');
  }

  /// 原始请求方法 - 不检查 success 字段，用于登录等需要自行处理错误的场景
  Future<Map<String, dynamic>> _requestRaw(
    String api,
    String method, {
    required int version,
    Map<String, dynamic>? params,
  }) async {
    final queryParams = <String, dynamic>{
      'api': api,
      'version': version,
      'method': method,
      if (_sid != null) '_sid': _sid,
      ...?params,
    };

    logger.d('SynologyApi: 原始请求 => $api.$method (v$version)');

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/webapi/entry.cgi',
        queryParameters: queryParams,
      );

      final data = response.data;
      logger.d('SynologyApi: 响应状态码 => ${response.statusCode}');

      if (data == null) {
        logger.e('SynologyApi: 服务器返回空数据');
        throw const ServerException(message: '服务器返回空数据');
      }

      return data;
    } on DioException catch (e, st) {
      AppError.handle(e, st, 'SynologyApi._requestRaw');
      rethrow;
    }
  }

  /// 对外暴露的扩展 API 调用入口
  ///
  /// 用于 Video Station / Audio Station 等不在本类直接封装的 DSM 扩展。
  /// 复用 [_request] 的错误处理和会话刷新逻辑。
  ///
  /// 失败时抛 [ServerException]——成功的响应原样返回（含 success/data/error 字段）。
  Future<Map<String, dynamic>> callExtensionApi(
    String api,
    String method, {
    required int version,
    Map<String, dynamic>? params,
  }) =>
      _request(api, method, version: version, params: params);

  /// 当前请求的 baseUrl（用于构造直接命中 cgi 的转码流 URL 等）
  String get baseUrl => _dio.options.baseUrl;

  /// 通用请求方法
  Future<Map<String, dynamic>> _request(
    String api,
    String method, {
    required int version,
    Map<String, dynamic>? params,
    bool allowRetry = true,
  }) async {
    final queryParams = <String, dynamic>{
      'api': api,
      'version': version,
      'method': method,
      if (_sid != null) '_sid': _sid,
      ...?params,
    };

    logger..d('SynologyApi: 请求 => $api.$method (v$version)')
    ..d('SynologyApi: 请求参数 => $queryParams');

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/webapi/entry.cgi',
        queryParameters: queryParams,
      );

      // 记录完整请求 URL
      logger.d('SynologyApi: 完整请求 URL => ${response.requestOptions.uri}');

      final data = response.data;
      logger.d('SynologyApi: 响应状态码 => ${response.statusCode}');
      // 只在非 listFiles 调用时打印响应数据（避免大量数据）
      if (method != 'list' || api != 'SYNO.FileStation.List') {
        logger.d('SynologyApi: 响应数据 => $data');
      }

      if (data == null) {
        logger.e('SynologyApi: 服务器返回空数据');
        throw const ServerException(message: '服务器返回空数据');
      }

      if (data['success'] != true) {
        final error = data['error'];
        final errorCode = error is Map<String, dynamic> ? error['code'] as int? : null;

        // 检查是否是会话过期错误，尝试刷新会话
        if (allowRetry && _isSessionExpiredError(errorCode)) {
          logger.w('SynologyApi: 会话已过期 (code: $errorCode)，尝试刷新...');
          final refreshed = await _tryRefreshSession();
          if (refreshed) {
            // 等待一小段时间，确保会话在各服务中生效
            await Future<void>.delayed(const Duration(milliseconds: 500));
            logger.i('SynologyApi: 会话刷新成功，重试请求');
            // 重试请求，但不允许再次重试
            return _request(api, method, version: version, params: params, allowRetry: false);
          }
        }

        final errorMsg = _getErrorMessage(errorCode);
        logger.e('SynologyApi: API 错误 => $errorMsg (code: $errorCode)');
        throw ServerException(
          message: errorMsg,
          statusCode: errorCode,
        );
      }

      logger.d('SynologyApi: 请求成功');
      return data;
    } on DioException catch (e, st) {
      AppError.handle(e, st, 'SynologyApi._request');
      rethrow;
    }
  }

  /// 尝试刷新会话
  Future<bool> _tryRefreshSession() async {
    if (_onSessionRefresh == null) {
      logger.w('SynologyApi: 未设置会话刷新回调，无法刷新');
      return false;
    }

    // 防止并发刷新
    if (_isRefreshing) {
      logger.d('SynologyApi: 正在刷新会话，等待...');
      // 等待刷新完成
      while (_isRefreshing) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return _sid != null;
    }

    _isRefreshing = true;
    try {
      final newSid = await _onSessionRefresh!();
      if (newSid != null) {
        _sid = newSid;
        logger.i('SynologyApi: 会话刷新成功，新 sid => ${_sid!.substring(0, 8)}...');
        return true;
      }
      logger.w('SynologyApi: 会话刷新失败，回调返回 null');
      return false;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '会话刷新失败');
      return false;
    } finally {
      _isRefreshing = false;
    }
  }

  AuthResult _handleAuthError(int? errorCode) => switch (errorCode) {
        400 => const AuthFailure(error: '账号或密码错误'),
        401 => const AuthFailure(error: '账号已禁用'),
        402 => const AuthFailure(error: '权限不足'),
        403 => const AuthRequires2FA(),
        404 => const AuthFailure(error: '二次验证失败'),
        406 => const AuthFailure(error: '需要强制更改密码'),
        407 => const AuthFailure(error: 'IP 被封禁'),
        _ => AuthFailure(error: '认证失败 (错误码: $errorCode)'),
      };

  String _getErrorMessage(int? errorCode) => switch (errorCode) {
        100 => '未知错误',
        101 => '无效参数',
        102 => 'API 不存在',
        103 => '方法不存在',
        104 => '版本不支持',
        105 => '权限不足',
        106 => '会话超时，请重新连接',
        107 => '重复登录',
        119 => '会话已失效，请重新连接',
        // FileStation 特定错误
        400 => '无效路径',
        401 => '路径不存在',
        402 => '权限不足',
        403 => '目标路径已存在',
        404 => '目标文件已锁定',
        405 => '目标路径拒绝',
        406 => '上传失败',
        407 => '磁盘空间不足',
        408 => '文件过大',
        409 => '操作中断',
        414 => '任务不存在',
        _ => '未知错误 ($errorCode)',
      };
}

/// 认证结果
sealed class AuthResult {
  const AuthResult();
}

class AuthSuccess extends AuthResult {
  const AuthSuccess({required this.sid, this.deviceId});
  final String sid;
  final String? deviceId;
}

class AuthFailure extends AuthResult {
  const AuthFailure({required this.error});
  final String error;
}

class AuthRequires2FA extends AuthResult {
  const AuthRequires2FA();
}

/// DSM 信息
class DsmInfo {
  const DsmInfo({
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

/// Synology 存储卷信息
class SynoVolumeInfo {
  const SynoVolumeInfo({
    required this.id,
    required this.volumePath,
    required this.totalSize,
    required this.usedSize,
    this.status,
    this.fsType,
    this.description,
  });

  factory SynoVolumeInfo.fromJson(Map<String, dynamic> json) {
    // Synology API 返回的 size 单位可能是字节或其他格式
    // total_size 和 used_size 通常是字符串，表示字节数
    final sizeMap = json['size'] as Map<String, dynamic>?;
    final totalSizeStr = sizeMap?['total'] as String? ?? '0';
    final usedSizeStr = sizeMap?['used'] as String? ?? '0';

    return SynoVolumeInfo(
      id: json['id'] as String? ?? json['volume_id'] as String? ?? '',
      volumePath: json['volume_path'] as String? ?? json['deploy_path'] as String? ?? '',
      totalSize: int.tryParse(totalSizeStr) ?? 0,
      usedSize: int.tryParse(usedSizeStr) ?? 0,
      status: json['status'] as String?,
      fsType: json['fs_type'] as String?,
      description: json['desc'] as String?,
    );
  }

  /// 卷 ID（如 volume_1）
  final String id;

  /// 卷路径（如 /volume1）
  final String volumePath;

  /// 总容量（字节）
  final int totalSize;

  /// 已使用容量（字节）
  final int usedSize;

  /// 状态（如 normal, degraded）
  final String? status;

  /// 文件系统类型（如 btrfs, ext4）
  final String? fsType;

  /// 描述
  final String? description;

  /// 可用容量（字节）
  int get freeSize => totalSize - usedSize;

  /// 使用百分比 (0.0 - 1.0)
  double get usagePercent => totalSize > 0 ? usedSize / totalSize : 0.0;
}

/// 共享文件夹
class ShareFolder {
  const ShareFolder({
    required this.name,
    required this.path,
    this.isDir = true,
  });

  factory ShareFolder.fromJson(Map<String, dynamic> json) {
    final path = json['path'] as String? ?? '';
    var name = json['name'] as String?;
    if (name == null || name.isEmpty) {
      // 从路径中提取名称
      final lastSlash = path.lastIndexOf('/');
      name = lastSlash >= 0 ? path.substring(lastSlash + 1) : path;
    }
    return ShareFolder(name: name, path: path);
  }

  final String name;
  final String path;
  final bool isDir;
}

/// FileStation 文件
class FileStationFile {
  const FileStationFile({
    required this.name,
    required this.path,
    required this.isDir,
    this.size = 0,
    this.createTime,
    this.modifyTime,
    this.type,
  });

  factory FileStationFile.fromJson(Map<String, dynamic> json) {
    final additional = json['additional'] as Map<String, dynamic>? ?? {};
    final time = additional['time'] as Map<String, dynamic>?;

    // 处理 path，可能为 null（虽然不应该发生）
    final path = json['path'] as String? ?? '';

    // name 可能为 null（当文件不存在时），从 path 中提取
    var name = json['name'] as String?;
    if (name == null || name.isEmpty) {
      // 从路径中提取文件名
      final lastSlash = path.lastIndexOf('/');
      name = lastSlash >= 0 ? path.substring(lastSlash + 1) : path;
    }

    return FileStationFile(
      name: name,
      path: path,
      isDir: json['isdir'] as bool? ?? false,
      size: additional['size'] as int? ?? 0,
      createTime: time?['crtime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (time!['crtime'] as int) * 1000,
            )
          : null,
      modifyTime: time?['mtime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (time!['mtime'] as int) * 1000,
            )
          : null,
      type: additional['type'] as String?,
    );
  }

  final String name;
  final String path;
  final bool isDir;
  final int size;
  final DateTime? createTime;
  final DateTime? modifyTime;
  final String? type;
}

/// 搜索结果
class SearchResult {
  const SearchResult({
    required this.files,
    required this.finished,
    required this.total,
  });

  final List<FileStationFile> files;
  final bool finished;
  final int total;
}

/// 复制/移动任务状态
class CopyMoveStatus {
  const CopyMoveStatus({
    required this.finished,
    required this.progress,
    this.destFolderPath,
    this.path,
  });

  final bool finished;
  final double progress;
  final String? destFolderPath;
  final String? path;
}

/// 文件列表结果（包含分页信息）
class FileListResult {
  const FileListResult({
    required this.files,
    required this.total,
    required this.offset,
  });

  /// 文件列表
  final List<FileStationFile> files;

  /// 目录中的文件总数
  final int total;

  /// 当前偏移量
  final int offset;

  /// 是否还有更多文件
  bool get hasMore => offset + files.length < total;
}
