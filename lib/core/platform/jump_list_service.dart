import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/logger.dart';

/// Windows 任务栏 Jump List 项。
/// args 走 deep link 协议（mynas://...），由 go_router 的 redirect 处理。
class JumpListItem {
  const JumpListItem({
    required this.label,
    required this.args,
    this.iconPath,
    this.iconIndex = 0,
    this.tooltip,
  });

  final String label;
  final String args;
  final String? iconPath;
  final int iconIndex;
  final String? tooltip;

  Map<String, Object?> toMap() => {
        'label': label,
        'args': args,
        if (iconPath != null) 'iconPath': iconPath,
        'iconIndex': iconIndex,
        if (tooltip != null) 'tooltip': tooltip,
      };
}

/// Windows JumpList 服务。
///
/// 在非 Windows 平台所有方法均为 no-op；调用方无需做平台判定。
/// MethodChannel 协议见 windows/runner/jumplist_channel.cpp。
class JumpListService {
  factory JumpListService() => _instance;
  JumpListService._();

  static final JumpListService _instance = JumpListService._();

  static const MethodChannel _channel = MethodChannel('my_nas/jump_list');

  bool _initialized = false;
  final StreamController<String> _deepLinkController =
      StreamController<String>.broadcast();

  /// 启动时通过命令行参数传入的 deep link（如 jump list / secondary 实例转发）。
  /// 由 main(args) 设置，控制器初始化后消费一次。
  String? _pendingInitialArg;

  /// 由 native 转发过来的 deep link（来自 secondary 实例 / Jump List 拉起）。
  Stream<String> get deepLinkStream => _deepLinkController.stream;

  /// 由 main(args) 在解析到 mynas:// 形式的启动参数时调用。
  void registerInitialArg(String url) {
    if (url.isEmpty) return;
    _pendingInitialArg = url;
  }

  /// 由 controller 在 init 时取走（最多一次）。
  String? consumeInitialArg() {
    final v = _pendingInitialArg;
    _pendingInitialArg = null;
    return v;
  }

  /// 设置 native → Dart 回调。仅在 Windows 注册。
  void init() {
    if (_initialized || !Platform.isWindows) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLink') {
        final url = call.arguments;
        if (url is String && url.isNotEmpty) {
          logger.i('JumpListService: incoming deep link: $url');
          _deepLinkController.add(url);
        }
      }
      return null;
    });
  }

  /// 配置 Tasks 分组（应用级固定项）。
  Future<void> setTasks(List<JumpListItem> tasks) async {
    if (!Platform.isWindows) return;
    await AppError.guard(
      () => _channel.invokeMethod<void>(
        'setTasks',
        tasks.map((e) => e.toMap()).toList(),
      ),
      action: 'JumpListService.setTasks',
    );
  }

  /// 配置 Recent 分组（动态变化项，由播放历史推送）。
  Future<void> setRecent(List<JumpListItem> recent) async {
    if (!Platform.isWindows) return;
    await AppError.guard(
      () => _channel.invokeMethod<void>(
        'setRecent',
        recent.map((e) => e.toMap()).toList(),
      ),
      action: 'JumpListService.setRecent',
    );
  }

  /// 清空 Jump List（包括 Tasks 和 Recent）。
  Future<void> clear() async {
    if (!Platform.isWindows) return;
    await AppError.guard(
      () => _channel.invokeMethod<void>('clear'),
      action: 'JumpListService.clear',
    );
  }
}
