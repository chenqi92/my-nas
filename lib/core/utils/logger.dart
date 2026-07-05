import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart' as pkg_logger;
import 'package:path_provider/path_provider.dart';

final logger = AppLogger();

class AppLogger {
  factory AppLogger() => _instance;
  AppLogger._internal();
  static final AppLogger _instance = AppLogger._internal();

  final _logger = pkg_logger.Logger(
    printer: pkg_logger.PrettyPrinter(
      dateTimeFormat: pkg_logger.DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  File? _logFile;
  bool _initialized = false;
  final _logBuffer = <String>[];
  Future<void>? _flushFuture;

  static final _sensitiveAssignmentPattern = RegExp(
    r'''(["']?(?:cookie|authorization|x-api-key|xapikey|api[_-]?key|access[_-]?token|refresh[_-]?token|token|password|secret|sid|session)["']?\s*[:=]\s*)(["']?)([^,\n\r}\]]*)''',
    caseSensitive: false,
  );
  static final _sensitiveQueryPattern = RegExp(
    r'([?&](?:api[_-]?key|x-api-key|access[_-]?token|refresh[_-]?token|token|password|secret)=)[^&\s]+',
    caseSensitive: false,
  );

  /// 初始化文件日志
  /// 在应用启动时调用，会清空之前的日志文件
  Future<void> initFileLogging() async {
    if (_initialized) return;

    try {
      final directory = await getApplicationCacheDirectory();
      final logsDir = Directory('${directory.path}/logs');

      // 确保 logs 目录存在
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }

      _logFile = File('${logsDir.path}/app.log');

      // 清空并重新创建日志文件
      if (await _logFile!.exists()) {
        await _logFile!.delete();
      }
      await _logFile!.create();

      _initialized = true;

      // 写入启动信息
      final now = DateTime.now();
      final header =
          '''
========================================
MyNAS Log Started at $now
Platform: ${Platform.operatingSystem}
========================================
''';
      await _logFile!.writeAsString(header);

      if (kDebugMode) {
        print('[Logger] File logging initialized: ${_logFile!.path}');
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        print('[Logger] Failed to initialize file logging: $e');
      }
    }
  }

  String _sanitize(String value) {
    var sanitized = value.replaceAllMapped(_sensitiveAssignmentPattern, (
      match,
    ) {
      final prefix = match.group(1) ?? '';
      final quote = match.group(2) ?? '';
      return '$prefix$quote<redacted>$quote';
    });
    sanitized = sanitized.replaceAllMapped(
      _sensitiveQueryPattern,
      (match) => '${match.group(1)}<redacted>',
    );
    return sanitized;
  }

  Object? _sanitizeObject(Object? value) {
    if (value == null) return null;
    return _sanitize(value.toString());
  }

  /// 写入到文件（使用缓冲和批量写入）
  void _writeToFile(
    String level,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (_logFile == null || !_initialized) return;
    if (!kDebugMode && level == 'DEBUG') return;

    final now = DateTime.now();
    final timestamp =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';

    final buffer = StringBuffer()
      ..writeln('[$timestamp] [$level] ${_sanitize(message)}');

    if (error != null) {
      buffer.writeln('  Error: ${_sanitize(error.toString())}');
    }

    if (stackTrace != null) {
      buffer.writeln('  StackTrace:');
      for (final line in stackTrace.toString().split('\n').take(10)) {
        buffer.writeln('    $line');
      }
    }

    _logBuffer.add(buffer.toString());
    _scheduleFlush();
  }

  void _scheduleFlush() {
    _flushFuture ??= _flushBuffer().whenComplete(() {
      _flushFuture = null;
      if (_logBuffer.isNotEmpty) {
        _scheduleFlush();
      }
    });
    unawaited(_flushFuture);
  }

  /// 异步刷新缓冲区
  Future<void> _flushBuffer() async {
    if (_logFile == null) return;

    try {
      while (_logBuffer.isNotEmpty) {
        final content = _logBuffer.join();
        _logBuffer.clear();
        await _logFile!.writeAsString(content, mode: FileMode.append);
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        print('[Logger] Failed to write log: $e');
      }
    }
  }

  /// 获取日志文件路径
  String? get logFilePath => _logFile?.path;

  /// 关闭文件日志
  Future<void> close() async {
    await _flushFuture;
    await _flushBuffer();
    _initialized = false;
  }

  void d(String message, [Object? error, StackTrace? stackTrace]) {
    if (!kDebugMode) return;
    final sanitizedMessage = _sanitize(message);
    final sanitizedError = _sanitizeObject(error);
    _logger.d(sanitizedMessage, error: sanitizedError, stackTrace: stackTrace);
    _writeToFile('DEBUG', sanitizedMessage, sanitizedError, stackTrace);
  }

  void i(String message, [Object? error, StackTrace? stackTrace]) {
    final sanitizedMessage = _sanitize(message);
    final sanitizedError = _sanitizeObject(error);
    if (kDebugMode) {
      _logger.i(
        sanitizedMessage,
        error: sanitizedError,
        stackTrace: stackTrace,
      );
    }
    _writeToFile('INFO', sanitizedMessage, sanitizedError, stackTrace);
  }

  void w(String message, [Object? error, StackTrace? stackTrace]) {
    final sanitizedMessage = _sanitize(message);
    final sanitizedError = _sanitizeObject(error);
    if (kDebugMode) {
      _logger.w(
        sanitizedMessage,
        error: sanitizedError,
        stackTrace: stackTrace,
      );
    }
    _writeToFile('WARN', sanitizedMessage, sanitizedError, stackTrace);
  }

  void e(String message, [Object? error, StackTrace? stackTrace]) {
    final sanitizedMessage = _sanitize(message);
    final sanitizedError = _sanitizeObject(error);
    if (kDebugMode) {
      _logger.e(
        sanitizedMessage,
        error: sanitizedError,
        stackTrace: stackTrace,
      );
    }
    _writeToFile('ERROR', sanitizedMessage, sanitizedError, stackTrace);
  }

  void f(String message, [Object? error, StackTrace? stackTrace]) {
    final sanitizedMessage = _sanitize(message);
    final sanitizedError = _sanitizeObject(error);
    if (kDebugMode) {
      _logger.f(
        sanitizedMessage,
        error: sanitizedError,
        stackTrace: stackTrace,
      );
    }
    _writeToFile('FATAL', sanitizedMessage, sanitizedError, stackTrace);
  }
}
