import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/media_server_adapters/jellyfin/api/jellyfin_api.dart';

/// Quick Connect 认证状态
enum QuickConnectStatus {
  /// 初始状态
  initial,

  /// 检查中
  checking,

  /// 不可用
  unavailable,

  /// 等待输入
  waitingForCode,

  /// 轮询中
  polling,

  /// 已授权
  authorized,

  /// 已过期
  expired,

  /// 错误
  error,
}

/// Quick Connect 认证结果
class QuickConnectResult {
  const QuickConnectResult({
    required this.success,
    this.accessToken,
    this.userId,
    this.errorMessage,
  });

  final bool success;
  final String? accessToken;
  final String? userId;
  final String? errorMessage;
}

/// Quick Connect 认证 Widget
///
/// 用于 Jellyfin 服务器的 Quick Connect 认证流程
class QuickConnectWidget extends StatefulWidget {
  const QuickConnectWidget({
    required this.serverUrl,
    required this.onResult,
    super.key,
  });

  /// 服务器 URL
  final String serverUrl;

  /// 认证结果回调
  final void Function(QuickConnectResult result) onResult;

  @override
  State<QuickConnectWidget> createState() => _QuickConnectWidgetState();
}

class _QuickConnectWidgetState extends State<QuickConnectWidget> {
  QuickConnectStatus _status = QuickConnectStatus.initial;
  String? _code;
  String? _secret;
  String? _errorMessage;
  Timer? _pollingTimer;
  int _remainingSeconds = 180; // 3 分钟超时
  JellyfinApi? _api;
  bool _isPolling = false; // 防止并发轮询
  bool _isOffline = false; // 网络离线状态

  // 指数退避参数
  int _pollAttempts = 0;
  static const int _basePollIntervalSeconds = 2;
  static const int _maxPollIntervalSeconds = 10;

  @override
  void initState() {
    super.initState();
    _initializeAndCheck();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  /// 初始化并检查
  Future<void> _initializeAndCheck() async {
    // 先检查网络
    if (!await _checkConnectivity()) {
      setState(() {
        _status = QuickConnectStatus.error;
        _errorMessage = context.l10n.quickConnectNetworkUnavailable;
        _isOffline = true;
      });
      return;
    }

    await _checkQuickConnectAvailability();
  }

  /// 检查网络连接
  Future<bool> _checkConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return !result.contains(ConnectivityResult.none);
    } on Exception catch (e) {
      logger.w('QuickConnect: 检查网络状态失败', e);
      return true; // 默认假设有网络
    }
  }

  /// 检查 Quick Connect 是否可用
  Future<void> _checkQuickConnectAvailability() async {
    setState(() {
      _status = QuickConnectStatus.checking;
      _isOffline = false;
    });

    try {
      _api = JellyfinApi();
      _api!.setBaseUrl(widget.serverUrl);

      final isEnabled = await _api!.isQuickConnectEnabled();

      if (!mounted) return;

      if (isEnabled) {
        await _initiateQuickConnect();
      } else {
        setState(() {
          _status = QuickConnectStatus.unavailable;
          _errorMessage = context.l10n.quickConnectServerNotSupported;
        });
      }
    } on Exception catch (e) {
      logger.e('QuickConnect: 检查可用性失败', e);
      if (mounted) {
        setState(() {
          _status = QuickConnectStatus.error;
          _errorMessage = context.l10n.quickConnectServerConnectionFailed;
        });
      }
    }
  }

  /// 发起 Quick Connect 认证
  Future<void> _initiateQuickConnect() async {
    try {
      final result = await _api!.initiateQuickConnect();

      if (!mounted) return;

      if (result != null) {
        setState(() {
          _status = QuickConnectStatus.waitingForCode;
          _code = result.code;
          _secret = result.secret;
          _remainingSeconds = 180;
        });

        // 开始轮询
        _startPolling();
      } else {
        setState(() {
          _status = QuickConnectStatus.error;
          _errorMessage = context.l10n.quickConnectCodeFetchFailed;
        });
      }
    } on Exception catch (e) {
      logger.e('QuickConnect: 初始化失败', e);
      if (mounted) {
        setState(() {
          _status = QuickConnectStatus.error;
          _errorMessage = context.l10n.quickConnectInitFailed;
        });
      }
    }
  }

  /// 计算下次轮询间隔（指数退避）
  int _getNextPollInterval() {
    final interval =
        (_basePollIntervalSeconds * pow(1.5, _pollAttempts)).round();
    return min(interval, _maxPollIntervalSeconds);
  }

  /// 开始轮询检查授权状态
  void _startPolling() {
    setState(() {
      _status = QuickConnectStatus.polling;
      _pollAttempts = 0;
    });

    _scheduleNextPoll();
  }

  /// 调度下一次轮询
  void _scheduleNextPoll() {
    if (!mounted || _secret == null) return;

    final interval = _getNextPollInterval();
    _pollingTimer = Timer(Duration(seconds: interval), _doPoll);
  }

  /// 执行轮询
  Future<void> _doPoll() async {
    if (!mounted || _secret == null) return;

    // 防止并发轮询
    if (_isPolling) return;
    _isPolling = true;

    try {
      // 更新剩余时间
      final interval = _getNextPollInterval();
      _remainingSeconds -= interval;

      if (_remainingSeconds <= 0) {
        if (mounted) {
          setState(() {
            _status = QuickConnectStatus.expired;
            _errorMessage = context.l10n.quickConnectCodeExpired;
          });
        }
        return;
      }

      // 检查网络
      if (!await _checkConnectivity()) {
        if (mounted) {
          setState(() {
            _isOffline = true;
          });
        }
        // 网络不可用时继续调度，等待网络恢复
        _pollAttempts++;
        _scheduleNextPoll();
        return;
      }

      // 网络恢复
      if (_isOffline && mounted) {
        setState(() {
          _isOffline = false;
        });
      }

      final result = await _api!.checkQuickConnect(_secret!);

      if (!mounted) return;

      if (result?.isAuthenticated ?? false) {
        // 使用 secret 完成认证
        final authResult = await _api!.authenticateWithQuickConnect(_secret!);

        if (authResult != null) {
          setState(() {
            _status = QuickConnectStatus.authorized;
          });

          widget.onResult(QuickConnectResult(
            success: true,
            accessToken: authResult.accessToken,
            userId: authResult.userId,
          ));
        } else {
          setState(() {
            _status = QuickConnectStatus.error;
            _errorMessage = '认证失败';
          });
        }
      } else {
        // 继续轮询，更新 UI
        if (mounted) {
          setState(() {});
          // 成功请求后重置退避
          _pollAttempts = 0;
          _scheduleNextPoll();
        }
      }
    } on Exception catch (e) {
      logger.w('QuickConnect: 轮询失败', e);
      // 轮询失败增加退避
      _pollAttempts++;
      if (mounted) {
        _scheduleNextPoll();
      }
    } finally {
      _isPolling = false;
    }
  }

  /// 复制代码到剪贴板
  Future<void> _copyCode() async {
    if (_code == null) return;

    await Clipboard.setData(ClipboardData(text: _code!));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.quickConnectCodeCopied),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// 重新开始
  Future<void> _restart() async {
    _pollingTimer?.cancel();
    setState(() {
      _status = QuickConnectStatus.initial;
      _code = null;
      _secret = null;
      _errorMessage = null;
      _remainingSeconds = 180;
      _pollAttempts = 0;
      _isPolling = false;
    });
    await _initializeAndCheck();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.qr_code_scanner,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Quick Connect',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildContent(theme),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    switch (_status) {
      case QuickConnectStatus.initial:
      case QuickConnectStatus.checking:
        return _buildLoadingState(theme, context.l10n.quickConnectCheckingAvailability);

      case QuickConnectStatus.unavailable:
        return _buildErrorState(theme, _errorMessage ?? '不可用', canRetry: false);

      case QuickConnectStatus.waitingForCode:
      case QuickConnectStatus.polling:
        return _buildCodeState(theme);

      case QuickConnectStatus.authorized:
        return _buildSuccessState(theme);

      case QuickConnectStatus.expired:
        return _buildErrorState(theme, _errorMessage ?? '已过期', canRetry: true);

      case QuickConnectStatus.error:
        return _buildErrorState(theme, _errorMessage ?? '发生错误', canRetry: true);
    }
  }

  Widget _buildLoadingState(ThemeData theme, String message) => Row(
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Text(
          message,
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );

  Widget _buildCodeState(ThemeData theme) {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    final timeString = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.quickConnectInputCodePrompt,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        // 代码显示
        InkWell(
          onTap: _copyCode,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _code ?? '',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.copy_rounded,
                  size: 20,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 状态和倒计时
        Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(
              context.l10n.quickConnectWaitingForAuth,
              style: theme.textTheme.bodySmall,
            ),
            const Spacer(),
            Icon(
              Icons.timer,
              size: 16,
              color: _remainingSeconds < 30
                  ? theme.colorScheme.error
                  : theme.colorScheme.outline,
            ),
            const SizedBox(width: 4),
            Text(
              timeString,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _remainingSeconds < 30
                    ? theme.colorScheme.error
                    : null,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 说明
        Text(
          context.l10n.quickConnectInstruction,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessState(ThemeData theme) => Row(
      children: [
        Icon(
          Icons.check_circle,
          color: Colors.green,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            context.l10n.quickConnectAuthSuccess,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );

  Widget _buildErrorState(ThemeData theme, String message, {required bool canRetry}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _isOffline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
              color: _isOffline
                  ? theme.colorScheme.outline
                  : theme.colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _isOffline
                      ? theme.colorScheme.outline
                      : theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ),
        if (canRetry) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _restart,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.l10n.quickConnectRetry),
          ),
        ],
      ],
    );
}
