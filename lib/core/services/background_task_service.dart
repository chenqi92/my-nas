// ignore_for_file: unreachable_from_main

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 后台任务类型
enum BackgroundTaskType {
  /// 视频刮削
  videoScrape,

  /// 视频扫描
  videoScan,
}

/// 后台任务状态
enum BackgroundTaskState {
  /// 空闲
  idle,

  /// 运行中
  running,

  /// 暂停
  paused,

  /// 完成
  completed,

  /// 错误
  error,
}

/// 后台任务进度信息
class BackgroundTaskProgress {
  const BackgroundTaskProgress({
    required this.taskType,
    required this.state,
    this.current = 0,
    this.total = 0,
    this.message,
  });

  factory BackgroundTaskProgress.fromJson(Map<String, dynamic> json) => BackgroundTaskProgress(
      taskType: BackgroundTaskType.values[json['taskType'] as int],
      state: BackgroundTaskState.values[json['state'] as int],
      current: json['current'] as int? ?? 0,
      total: json['total'] as int? ?? 0,
      message: json['message'] as String?,
    );

  final BackgroundTaskType taskType;
  final BackgroundTaskState state;
  final int current;
  final int total;
  final String? message;

  double get progress => total > 0 ? current / total : 0;

  Map<String, dynamic> toJson() => {
        'taskType': taskType.index,
        'state': state.index,
        'current': current,
        'total': total,
        'message': message,
      };
}

/// 后台任务服务
///
/// 负责管理前台服务，确保刮削/扫描任务可以在后台继续运行。
///
/// 工作原理：
/// - Android: 使用 Foreground Service 保持应用进程存活
/// - iOS: 使用 Background Task API (有时间限制，约30秒-几分钟)
/// - 桌面平台: 无需特殊处理，应用在后台时不会被暂停
///
/// 设计说明：
/// 由于后台服务运行在独立的 Isolate 中，无法直接访问主 Isolate 的对象，
/// 因此我们采用以下策略：
/// 1. 前台服务仅用于保持进程存活和显示通知
/// 2. 实际的刮削逻辑仍在主 Isolate 中执行
/// 3. 通过 sendDataToMain/sendDataToTask 进行通信更新进度
class BackgroundTaskService {
  factory BackgroundTaskService() => _instance ??= BackgroundTaskService._();

  BackgroundTaskService._();

  static BackgroundTaskService? _instance;

  bool _isInitialized = false;
  bool _isServiceRunning = false;

  /// 当前任务进度
  BackgroundTaskProgress? _currentProgress;

  /// 进度流控制器
  final _progressController =
      StreamController<BackgroundTaskProgress>.broadcast();

  /// 进度流
  Stream<BackgroundTaskProgress> get progressStream =>
      _progressController.stream;

  /// 是否正在运行后台服务
  bool get isServiceRunning => _isServiceRunning;

  /// 当前任务进度
  BackgroundTaskProgress? get currentProgress => _currentProgress;

  /// 初始化后台任务服务
  ///
  /// 必须在 runApp 之前调用 initCommunicationPort
  Future<void> init() async {
    if (_isInitialized) return;

    // 桌面平台不需要前台服务
    if (!_isMobilePlatform) {
      _isInitialized = true;
      logger.d('BackgroundTaskService: 桌面平台无需前台服务');
      return;
    }

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'mynas_background_task',
        channelName: appL10n.bgTaskNotificationChannelName,
        channelDescription: appL10n.bgTaskNotificationChannelDesc,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
        showWhen: false,
        enableVibration: false,
        playSound: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // 每5秒触发一次 onRepeatEvent（用于更新通知）
        eventAction: ForegroundTaskEventAction.repeat(5000),
        // 开机自启动（恢复未完成的任务）
        autoRunOnBoot: true,
        // 应用更新后自动重启
        autoRunOnMyPackageReplaced: true,
        // 允许唤醒锁（防止CPU休眠）
        allowWakeLock: true,
        // 允许WiFi锁（保持网络连接）
        allowWifiLock: true,
      ),
    );

    // 注册数据回调
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);

    _isInitialized = true;
    logger.i('BackgroundTaskService: 初始化完成');
  }

  /// 接收来自 TaskHandler 的数据
  void _onReceiveTaskData(Object data) {
    if (data is Map<String, dynamic>) {
      if (data.containsKey('taskType')) {
        _currentProgress = BackgroundTaskProgress.fromJson(data);
        _progressController.add(_currentProgress!);
      }
    }
  }

  /// 请求必要的权限
  Future<bool> requestPermissions() async {
    if (!_isMobilePlatform) return true;

    // Android 13+ 需要通知权限
    final notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (Platform.isAndroid) {
      // 请求忽略电池优化
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    }

    return true;
  }

  /// 启动后台服务
  ///
  /// [taskType] 任务类型
  /// [initialMessage] 初始通知消息
  Future<bool> startService({
    required BackgroundTaskType taskType,
    String? initialMessage,
  }) async {
    if (!_isMobilePlatform) {
      _isServiceRunning = true;
      _currentProgress = BackgroundTaskProgress(
        taskType: taskType,
        state: BackgroundTaskState.running,
        message: initialMessage,
      );
      _progressController.add(_currentProgress!);
      return true;
    }

    if (_isServiceRunning) {
      logger.d('BackgroundTaskService: 服务已在运行中');
      return true;
    }

    final title = _getNotificationTitle(taskType);
    final text = initialMessage ?? _getDefaultMessage(taskType);

    final result = await FlutterForegroundTask.startService(
      notificationTitle: title,
      notificationText: text,
      notificationIcon: null, // 使用默认图标
      notificationButtons: [
        NotificationButton(id: 'stop', text: appL10n.bgTaskNotificationStopButton),
      ],
      callback: startBackgroundTaskCallback,
    );

    switch (result) {
      case ServiceRequestSuccess():
        _isServiceRunning = true;
        _currentProgress = BackgroundTaskProgress(
          taskType: taskType,
          state: BackgroundTaskState.running,
          message: initialMessage,
        );
        _progressController.add(_currentProgress!);
        logger.i('BackgroundTaskService: 前台服务已启动');
        return true;
      case ServiceRequestFailure(:final error):
        logger.w('BackgroundTaskService: 启动前台服务失败: $error');
        return false;
    }
  }

  /// 更新任务进度
  ///
  /// 同时更新通知栏显示和内部状态
  Future<void> updateProgress(BackgroundTaskProgress progress) async {
    _currentProgress = progress;
    _progressController.add(progress);

    if (!_isMobilePlatform || !_isServiceRunning) return;

    final title = _getNotificationTitle(progress.taskType);
    final text = progress.message ??
        '${progress.current}/${progress.total} (${(progress.progress * 100).toStringAsFixed(0)}%)';

    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );

    // 发送数据到 TaskHandler（如果需要）
    FlutterForegroundTask.sendDataToTask(progress.toJson());
  }

  /// 停止后台服务
  Future<void> stopService() async {
    if (!_isMobilePlatform) {
      _isServiceRunning = false;
      if (_currentProgress != null) {
        _currentProgress = BackgroundTaskProgress(
          taskType: _currentProgress!.taskType,
          state: BackgroundTaskState.idle,
        );
        _progressController.add(_currentProgress!);
      }
      return;
    }

    if (!_isServiceRunning) return;

    final result = await FlutterForegroundTask.stopService();
    switch (result) {
      case ServiceRequestSuccess():
        _isServiceRunning = false;
        if (_currentProgress != null) {
          _currentProgress = BackgroundTaskProgress(
            taskType: _currentProgress!.taskType,
            state: BackgroundTaskState.idle,
          );
          _progressController.add(_currentProgress!);
        }
        logger.i('BackgroundTaskService: 前台服务已停止');
      case ServiceRequestFailure(:final error):
        logger.w('BackgroundTaskService: 停止前台服务失败: $error');
    }
  }

  /// 检查服务是否正在运行
  Future<bool> checkServiceRunning() async {
    if (!_isMobilePlatform) return _isServiceRunning;
    _isServiceRunning = await FlutterForegroundTask.isRunningService;
    return _isServiceRunning;
  }

  /// 释放资源
  void dispose() {
    if (_isMobilePlatform) {
      FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    }
    _progressController.close();
  }

  /// 是否是移动平台
  /// 注意：仅 Android 支持 Foreground Service，iOS 的后台任务有严格的时间限制
  /// 因此只在 Android 上使用前台服务
  bool get _isMobilePlatform => Platform.isAndroid;

  String _getNotificationTitle(BackgroundTaskType taskType) {
    switch (taskType) {
      case BackgroundTaskType.videoScrape:
        return appL10n.bgTaskNotificationTitleVideoScrape;
      case BackgroundTaskType.videoScan:
        return appL10n.bgTaskNotificationTitleVideoScan;
    }
  }

  String _getDefaultMessage(BackgroundTaskType taskType) {
    switch (taskType) {
      case BackgroundTaskType.videoScrape:
        return appL10n.bgTaskDefaultMessageVideoScrape;
      case BackgroundTaskType.videoScan:
        return appL10n.bgTaskDefaultMessageVideoScan;
    }
  }
}

/// TaskHandler 的入口回调函数
///
/// 必须是顶级函数或静态函数
@pragma('vm:entry-point')
void startBackgroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(MediaLibraryTaskHandler());
}

/// 媒体库后台任务处理器
///
/// 运行在独立的 Isolate 中，主要负责：
/// 1. 保持前台服务存活
/// 2. 更新通知栏进度
/// 3. 与主 Isolate 通信
///
/// 注意：实际的刮削逻辑在主 Isolate 中执行，
/// 这里只是一个"保活"和"显示进度"的角色
class MediaLibraryTaskHandler extends TaskHandler {
  int _lastCurrent = 0;
  int _lastTotal = 0;
  String? _lastMessage;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('MediaLibraryTaskHandler: 任务开始 starter=$starter');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // 定期检查，如果主 Isolate 有更新进度，这里会收到
    // 目前主要用于保活，进度更新通过 sendDataToTask 实现
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map<String, dynamic>) {
      final current = data['current'] as int? ?? 0;
      final total = data['total'] as int? ?? 0;
      final message = data['message'] as String?;

      // 只有进度变化时才更新通知
      if (current != _lastCurrent ||
          total != _lastTotal ||
          message != _lastMessage) {
        _lastCurrent = current;
        _lastTotal = total;
        _lastMessage = message;

        final progress = total > 0 ? current / total : 0.0;
        final text = message ??
            '$current/$total (${(progress * 100).toStringAsFixed(0)}%)';

        FlutterForegroundTask.updateService(notificationText: text);
      }
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('MediaLibraryTaskHandler: 任务结束 isTimeout=$isTimeout');
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') {
      // 通知主 Isolate 停止任务
      FlutterForegroundTask.sendDataToMain({'command': 'stop'});
    }
  }

  @override
  void onNotificationPressed() {
    // 点击通知打开应用
    FlutterForegroundTask.launchApp('/video');
  }

  @override
  void onNotificationDismissed() {
    // 通知被滑动关闭时不做特殊处理
    // 服务会继续运行
  }
}
