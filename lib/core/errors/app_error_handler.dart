import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:my_nas/core/errors/exceptions.dart';
import 'package:my_nas/core/errors/failures.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 统一错误处理工具类
///
/// 提供统一的错误处理、上报和UI提示功能，确保错误处理的一致性和可追踪性。
///
/// ## 使用方式
///
/// ### 1. 基本错误处理（上报到服务器）
/// ```dart
/// try {
///   await someOperation();
/// } catch (e, st) {
///   AppError.handle(e, st, action: 'loadVideo');
/// }
/// ```
///
/// ### 2. 带UI提示的错误处理
/// ```dart
/// try {
///   await someOperation();
/// } catch (e, st) {
///   AppError.handleWithUI(context, e, st, message: '加载失败');
/// }
/// ```
///
/// ### 3. 安全执行（自动捕获并上报）
/// ```dart
/// final result = await AppError.guard(
///   () => fetchData(),
///   action: 'fetchUserData',
///   fallback: defaultValue,
/// );
/// ```
///
/// ### 4. 不需要上报的错误（仅本地日志）
/// ```dart
/// try {
///   await someOperation();
/// } catch (e, st) {
///   AppError.ignore(e, st, reason: '用户取消操作');
/// }
/// ```
///
/// @author cq
/// @date 2025-12-12
class AppError {
  AppError._();

  // ============================================================
  // 核心方法
  // ============================================================

  /// 处理错误并写入本地日志
  ///
  /// [error] 错误对象
  /// [stackTrace] 堆栈跟踪
  /// [action] 触发错误的操作描述（如 'loadVideo', 'saveFile'）
  /// [extraData] 额外的上下文数据（仅用于本地日志输出）
  static void handle(
    Object error, [
    StackTrace? stackTrace,
    String? action,
    Map<String, dynamic>? extraData,
  ]) {
    final st = stackTrace ?? StackTrace.current;
    final errorInfo = _extractErrorInfo(error);

    // 不需要上报/记录的（用户取消、校验等）：仅 debug 级日志
    if (!isReportable(error)) {
      logger.w('[AppError] 忽略上报: ${errorInfo.type} - ${errorInfo.message}', error, st);
      return;
    }

    // 根据严重程度决定日志级别
    final isFatal = _categorizeError(error) == ErrorCategory.fatal;
    final tag = '[${action ?? 'Unknown'}] ${errorInfo.message}'
        '${extraData != null ? ' | extra=$extraData' : ''}';

    if (isFatal) {
      logger.f(tag, error, st);
    } else {
      logger.e(tag, error, st);
    }
  }

  /// 处理错误并显示UI提示
  ///
  /// [context] BuildContext
  /// [error] 错误对象
  /// [stackTrace] 堆栈跟踪
  /// [message] 用户友好的错误提示（可选，默认根据错误类型生成）
  /// [action] 触发错误的操作描述
  /// [showSnackBar] 是否显示SnackBar，默认true
  /// [extraData] 额外的上下文数据
  static void handleWithUI(
    BuildContext context,
    Object error, [
    StackTrace? stackTrace,
    String? message,
    String? action,
    bool showSnackBar = true,
    Map<String, dynamic>? extraData,
  ]) {
    // 先处理并上报错误
    handle(error, stackTrace, action, extraData);

    // 显示用户友好的提示
    if (showSnackBar && context.mounted) {
      final userMessage = message ?? getUserFriendlyMessage(error, context);
      context.showErrorSnackBar(userMessage);
    }
  }

  /// 安全执行异步操作
  ///
  /// 自动捕获异常并上报，返回结果或fallback值。
  ///
  /// [operation] 要执行的异步操作
  /// [action] 操作描述
  /// [fallback] 发生错误时的默认返回值
  /// [onError] 错误发生时的回调（在上报之后调用）
  /// [extraData] 额外的上下文数据
  /// [shouldRethrow] 是否重新抛出异常，默认false
  static Future<T?> guard<T>(
    Future<T> Function() operation, {
    String? action,
    T? fallback,
    void Function(Object error, StackTrace stackTrace)? onError,
    Map<String, dynamic>? extraData,
    bool shouldRethrow = false,
  }) async {
    try {
      return await operation();
    } catch (e, st) {
      handle(e, st, action, extraData);
      onError?.call(e, st);

      if (shouldRethrow) {
        Error.throwWithStackTrace(e, st);
      }

      return fallback;
    }
  }

  /// 安全执行同步操作
  static T? guardSync<T>(
    T Function() operation, {
    String? action,
    T? fallback,
    void Function(Object error, StackTrace stackTrace)? onError,
    Map<String, dynamic>? extraData,
    bool shouldRethrow = false,
  }) {
    try {
      return operation();
    } catch (e, st) {
      handle(e, st, action, extraData);
      onError?.call(e, st);

      if (shouldRethrow) {
        Error.throwWithStackTrace(e, st);
      }

      return fallback;
    }
  }

  /// 忽略错误（仅记录本地日志，不上报）
  ///
  /// 用于明确标记不需要上报的错误，便于代码审查。
  ///
  /// [error] 错误对象
  /// [stackTrace] 堆栈跟踪
  /// [reason] 忽略原因（必填，便于后续审查）
  static void ignore(
    Object error, [
    StackTrace? stackTrace,
    String? reason,
  ]) {
    final st = stackTrace ?? StackTrace.current;
    final errorInfo = _extractErrorInfo(error);

    logger.d(
      '[AppError.ignore] ${errorInfo.type}: ${errorInfo.message}'
      '${reason != null ? ' (原因: $reason)' : ''}',
      error,
      st,
    );
  }

  /// 包装 unawaited 异步操作，确保异常被捕获
  ///
  /// 替代直接使用 unawaited()，确保后台操作的异常不会丢失。
  ///
  /// ```dart
  /// // 替代: unawaited(someBackgroundTask());
  /// AppError.fireAndForget(someBackgroundTask(), action: 'backgroundSync');
  /// ```
  static void fireAndForget(
    Future<void> future, {
    String? action,
    Map<String, dynamic>? extraData,
  }) {
    future.catchError((Object e, StackTrace st) {
      handle(e, st, action ?? 'fireAndForget', extraData);
      return null;
    });
  }

  // ============================================================
  // 错误分类和判断
  // ============================================================

  /// 判断错误是否需要上报
  ///
  /// 返回 true 表示需要上报到服务器
  static bool isReportable(Object error) {
    final category = _categorizeError(error);

    switch (category) {
      // 始终需要上报
      case ErrorCategory.server:
      case ErrorCategory.fatal:
      case ErrorCategory.security:
      case ErrorCategory.data:
      case ErrorCategory.resource:
        return true;

      // 网络错误：仅上报服务器错误，不上报连接问题
      case ErrorCategory.network:
        if (error is DioException) {
          // 服务器返回错误需要上报
          if (error.response?.statusCode != null) {
            final statusCode = error.response!.statusCode!;
            return statusCode >= 500; // 5xx 服务器错误需要上报
          }
          // 连接超时、无网络等不上报（用户可感知）
          return false;
        }
        return true;

      // 用户操作相关：通常不上报
      case ErrorCategory.userAction:
      case ErrorCategory.validation:
      case ErrorCategory.cancelled:
        return false;

      // 未知错误：默认上报
      case ErrorCategory.unknown:
        return true;
    }
  }

  /// 获取用户友好的错误提示
  static String getUserFriendlyMessage(Object error, [BuildContext? context]) {
    final category = _categorizeError(error);
    final l = context != null ? context.l10n : appL10n;

    switch (category) {
      case ErrorCategory.network:
        if (error is DioException) {
          return switch (error.type) {
            DioExceptionType.connectionTimeout => l.errorNetworkConnectionTimeout,
            DioExceptionType.sendTimeout => l.errorNetworkSendTimeout,
            DioExceptionType.receiveTimeout => l.errorNetworkReceiveTimeout,
            DioExceptionType.connectionError => l.errorNetworkConnectionFailed,
            DioExceptionType.badResponse => _getHttpErrorMessage(error.response?.statusCode, context),
            DioExceptionType.cancel => l.errorNetworkRequestCancelled,
            _ => l.errorNetworkGeneric,
          };
        }
        if (error is SocketException) {
          return l.errorNetworkConnectionFailed;
        }
        return l.errorNetworkGeneric;

      case ErrorCategory.server:
        return l.errorServerGeneric;

      case ErrorCategory.validation:
        if (error is ValidationException || error is ValidationFailure) {
          return error.toString();
        }
        return l.errorValidationInput;

      case ErrorCategory.security:
        return l.errorAuthenticationFailed;

      case ErrorCategory.resource:
        if (error is FileSystemException) {
          return l.errorFileOperationFailed(error.message);
        }
        return l.errorResourceAccessFailed;

      case ErrorCategory.data:
        return l.errorDataProcessingFailed;

      case ErrorCategory.cancelled:
        return l.errorOperationCancelled;

      case ErrorCategory.userAction:
        return l.errorOperationFailed;

      case ErrorCategory.fatal:
        return l.errorFatalCritical;

      case ErrorCategory.unknown:
        return l.errorUnknown;
    }
  }

  /// 获取HTTP状态码对应的错误提示
  static String _getHttpErrorMessage(int? statusCode, [BuildContext? context]) {
    final l = context != null ? context.l10n : appL10n;
    if (statusCode == null) return l.errorServerResponseAbnormal;

    return switch (statusCode) {
      400 => l.errorHttpBadRequest,
      401 => l.errorHttpUnauthorized,
      403 => l.errorHttpForbidden,
      404 => l.errorHttpNotFound,
      408 => l.errorHttpRequestTimeout,
      429 => l.errorHttpTooManyRequests,
      >= 500 && < 600 => l.errorHttpServerError,
      _ => l.errorHttpFailure(statusCode),
    };
  }

  // ============================================================
  // 私有辅助方法
  // ============================================================

  /// 错误分类
  static ErrorCategory _categorizeError(Object error) {
    // AppException 系列
    if (error is ServerException) return ErrorCategory.server;
    if (error is NetworkException) return ErrorCategory.network;
    if (error is AuthException) return ErrorCategory.security;
    if (error is ValidationException) return ErrorCategory.validation;
    if (error is ConnectionException) return ErrorCategory.network;
    if (error is CacheException) return ErrorCategory.data;

    // Failure 系列
    if (error is ServerFailure) return ErrorCategory.server;
    if (error is NetworkFailure) return ErrorCategory.network;
    if (error is AuthFailure) return ErrorCategory.security;
    if (error is ValidationFailure) return ErrorCategory.validation;
    if (error is ConnectionFailure) return ErrorCategory.network;
    if (error is CacheFailure) return ErrorCategory.data;

    // Dio 异常
    if (error is DioException) {
      if (error.type == DioExceptionType.cancel) {
        return ErrorCategory.cancelled;
      }
      if (error.response?.statusCode != null) {
        final code = error.response!.statusCode!;
        if (code >= 500) return ErrorCategory.server;
        if (code == 401 || code == 403) return ErrorCategory.security;
        if (code == 400 || code == 422) return ErrorCategory.validation;
      }
      return ErrorCategory.network;
    }

    // 系统异常
    if (error is SocketException) return ErrorCategory.network;
    if (error is HttpException) return ErrorCategory.network;
    if (error is FileSystemException) return ErrorCategory.resource;
    if (error is FormatException) return ErrorCategory.data;
    if (error is TypeError) return ErrorCategory.data;
    if (error is StateError) return ErrorCategory.fatal;
    if (error is OutOfMemoryError) return ErrorCategory.resource;
    if (error is StackOverflowError) return ErrorCategory.fatal;

    // 用户取消
    if (error.toString().toLowerCase().contains('cancel')) {
      return ErrorCategory.cancelled;
    }

    return ErrorCategory.unknown;
  }

  /// 提取错误信息
  static _ErrorInfo _extractErrorInfo(Object error) {
    String type;
    String message;
    String? code;

    if (error is AppException) {
      // ignore: no_runtimeType_toString
      type = error.runtimeType.toString();
      message = error.message ?? error.toString();
      if (error is ServerException) {
        code = error.statusCode?.toString();
      }
    } else if (error is Failure) {
      // ignore: no_runtimeType_toString
      type = error.runtimeType.toString();
      message = error.message ?? error.toString();
      if (error is ServerFailure) {
        code = error.statusCode?.toString();
      }
    } else if (error is DioException) {
      type = 'DioException.${error.type.name}';
      message = error.message ?? error.toString();
      code = error.response?.statusCode?.toString();
    } else if (error is Exception) {
      // ignore: no_runtimeType_toString
      type = error.runtimeType.toString();
      message = error.toString();
    } else if (error is Error) {
      // ignore: no_runtimeType_toString
      type = error.runtimeType.toString();
      message = error.toString();
    } else {
      type = 'Unknown';
      message = error.toString();
    }

    return _ErrorInfo(type: type, message: message, code: code);
  }
}

/// 错误分类枚举
enum ErrorCategory {
  /// 服务器错误（5xx）
  server,

  /// 网络错误（连接、超时等）
  network,

  /// 数据验证错误
  validation,

  /// 安全/认证错误
  security,

  /// 数据处理错误（解析、格式等）
  data,

  /// 资源错误（文件、内存等）
  resource,

  /// 用户操作相关
  userAction,

  /// 用户取消操作
  cancelled,

  /// 致命错误
  fatal,

  /// 未知错误
  unknown,
}

/// 错误信息结构
class _ErrorInfo {
  const _ErrorInfo({
    required this.type,
    required this.message,
    this.code,
  });

  final String type;
  final String message;
  final String? code;
}

/// AppError 扩展 - 提供更便捷的链式调用
extension AppErrorContext on BuildContext {
  /// 在当前上下文处理错误
  ///
  /// ```dart
  /// } catch (e, st) {
  ///   context.handleError(e, st, message: '加载失败');
  /// }
  /// ```
  void handleError(
    Object error, [
    StackTrace? stackTrace,
    String? message,
    String? action,
  ]) {
    AppError.handleWithUI(this, error, stackTrace, message, action);
  }
}
