import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';

/// NASTool 认证管理器
///
/// 使用 /user/login 端点进行会话认证
class NasToolAuth {
  NasToolAuth({required this.baseUrl});

  final String baseUrl;

  String? _sessionToken;
  String? _username;
  bool _isCookieAuth = false;

  /// 是否已认证
  bool get isAuthenticated => _sessionToken != null;

  /// 当前用户名
  String? get username => _username;

  /// 获取认证头（用于需要 header 认证的场景）
  Map<String, String> get authHeaders {
    if (_sessionToken == null) return {};

    // 根据认证类型返回正确的头
    if (_isCookieAuth) {
      return {'Cookie': _sessionToken!};
    }
    // 注意：NASTool 主要使用 apikey 作为 URL 查询参数
    // 但某些端点可能还需要 header，保留以便兼容
    return {'Authorization': _sessionToken!};
  }

  /// 获取 API Key（用于 URL 查询参数）
  /// NASTool API 要求将 apikey 添加到 URL 查询参数中
  String? get apiKey => _isCookieAuth ? null : _sessionToken;

  /// 登录
  ///
  /// 调用 /user/login 端点获取 API Key
  ///
  /// 返回格式:
  /// ```json
  /// {
  ///   "code": 0,
  ///   "success": true,
  ///   "data": {
  ///     "token": "...",     // JWT token (不使用)
  ///     "apikey": "...",    // API Key (使用此字段)
  ///     "userinfo": {...}
  ///   }
  /// }
  /// ```
  Future<NasToolLoginResult> login(String username, String password) async {
    try {
      final url = Uri.parse('$baseUrl/api/v1/user/login');

      // 调试日志：登录请求（不记录用户名，日志会落盘到 app.log）
      if (kDebugMode) {
        logger.d('[NasToolAuth] Login Request - host: ${url.host}');
      }

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: {'username': username, 'password': password},
      );

      // 调试日志：登录响应。不要打印 body —— 其中含 apikey/凭据。
      if (kDebugMode) {
        logger.d('[NasToolAuth] Login Response - Status: ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // 检查返回结果
        final code = data['code'] as int? ?? -1;
        final success = data['success'] as bool? ?? false;

        // 优先获取 data.apikey（正确的认证方式）
        final responseData = data['data'] as Map<String, dynamic>?;
        final apiKey = responseData?['apikey'] as String?;

        if ((code == 0 || success) && apiKey != null) {
          // 登录成功，保存 API Key（直接使用，不加 Bearer 前缀）
          _sessionToken = apiKey;
          _username = username;
          _isCookieAuth = false;

          if (kDebugMode) {
            logger.i('[NasToolAuth] Login successful, token saved');
          }

          return NasToolLoginResult.success(
            token: apiKey,
            username: username,
          );
        } else if (code == 0 || success) {
          // 兼容旧版本：如果没有 apikey，尝试使用 token
          final token = responseData?['token'] as String? ?? data['token'] as String?;
          if (token != null) {
            _sessionToken = token;
            _username = username;
            _isCookieAuth = false;
            return NasToolLoginResult.success(
              token: token,
              username: username,
            );
          }

          // 如果都没有，尝试从 cookie 获取
          final cookies = response.headers['set-cookie'];
          if (cookies != null) {
            _sessionToken = cookies;
            _isCookieAuth = true;
            return NasToolLoginResult.success(
              token: null,
              username: username,
            );
          }

          return NasToolLoginResult.failure(appL10n.nastoolAuthLoginSuccessButNoAuthInfo);
        } else {
          final message = data['message'] as String? ??
                          data['msg'] as String? ??
                          appL10n.nastoolAuthLoginFailed;
          return NasToolLoginResult.failure(message);
        }
      } else if (response.statusCode == 401) {
        return NasToolLoginResult.failure(appL10n.nastoolAuthInvalidUsernamePassword);
      } else {
        return NasToolLoginResult.failure(
          appL10n.nastoolAuthRequestFailed(response.statusCode),
        );
      }
    } on SocketException catch (e) {
      return NasToolLoginResult.failure(appL10n.nastoolAuthCannotConnectServer(e.message));
    } on Exception catch (e) {
      return NasToolLoginResult.failure(appL10n.nastoolAuthLoginException(e));
    }
  }

  /// 登出
  Future<void> logout() async {
    if (!isAuthenticated) return;

    try {
      final url = Uri.parse('$baseUrl/api/v1/system/logout');
      await http.post(
        url,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
          ...authHeaders,
        },
      );
    } on Exception {
      // 忽略登出错误
    } finally {
      _sessionToken = null;
      _username = null;
    }
  }

  /// 验证会话是否有效
  Future<bool> validateSession() async {
    if (!isAuthenticated) return false;

    try {
      final url = Uri.parse('$baseUrl/api/v1/system/version');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
          ...authHeaders,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final dataField = data['data'] as Map<String, dynamic>?;
        return data['code'] == 0 || dataField?['version'] != null;
      }
      return false;
    } on Exception {
      return false;
    }
  }

  /// 设置 API Key（用于 API Key 认证）
  ///
  /// [apiKey] 为纯 API Key 值，直接使用不加前缀
  void setApiToken(String apiKey) {
    // 移除可能存在的 Bearer 前缀
    if (apiKey.startsWith('Bearer ')) {
      _sessionToken = apiKey.substring(7);
    } else {
      _sessionToken = apiKey;
    }
    _username = 'API Key';
    _isCookieAuth = false;
  }

  /// 验证 API Key 是否有效
  Future<bool> validateApiToken(String apiKey) async {
    try {
      final url = Uri.parse('$baseUrl/api/v1/system/version');

      // 直接使用 apiKey，不加前缀
      final pureApiKey = apiKey.startsWith('Bearer ') ? apiKey.substring(7) : apiKey;

      if (kDebugMode) {
        logger.d('[NasToolAuth] Validate API Token - URL: $url');
      }

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
          'Authorization': pureApiKey,
        },
      );

      if (kDebugMode) {
        logger.d('[NasToolAuth] Validate Response - Status: ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final dataField = data['data'] as Map<String, dynamic>?;
        if (data['code'] == 0 || dataField?['version'] != null) {
          // API Key 有效，设置认证信息
          _sessionToken = pureApiKey;
          _username = 'API Key';
          _isCookieAuth = false;
          if (kDebugMode) {
            logger.i('[NasToolAuth] API Token valid');
          }
          return true;
        }
      }

      if (kDebugMode) {
        logger.w('[NasToolAuth] API Token invalid');
      }
      return false;
    } on Exception catch (e) {
      if (kDebugMode) {
        logger.e('[NasToolAuth] Validate exception', e);
      }
      return false;
    }
  }

  /// 清除认证状态
  void clear() {
    _sessionToken = null;
    _username = null;
    _isCookieAuth = false;
  }
}

/// 登录结果
sealed class NasToolLoginResult {
  const NasToolLoginResult();

  const factory NasToolLoginResult.success({
    String? token,
    required String username,
  }) = NasToolLoginSuccess;

  const factory NasToolLoginResult.failure(String message) = NasToolLoginFailure;

  T when<T>({
    required T Function(String? token, String username) success,
    required T Function(String message) failure,
  });
}

class NasToolLoginSuccess extends NasToolLoginResult {
  const NasToolLoginSuccess({this.token, required this.username});

  final String? token;
  final String username;

  @override
  T when<T>({
    required T Function(String? token, String username) success,
    required T Function(String message) failure,
  }) => success(token, username);
}

class NasToolLoginFailure extends NasToolLoginResult {
  const NasToolLoginFailure(this.message);

  final String message;

  @override
  T when<T>({
    required T Function(String? token, String username) success,
    required T Function(String message) failure,
  }) => failure(message);
}
