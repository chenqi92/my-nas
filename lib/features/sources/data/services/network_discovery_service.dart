import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';

/// 发现的设备信息
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.name,
    required this.host,
    required this.port,
    required this.type,
    this.serviceType,
    this.txtRecords,
  });

  final String name;
  final String host;
  final int port;
  final SourceType type;
  final String? serviceType;
  final Map<String, String>? txtRecords;

  @override
  String toString() => 'DiscoveredDevice($name, $host:$port, $type)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredDevice &&
          runtimeType == other.runtimeType &&
          host == other.host &&
          port == other.port;

  @override
  int get hashCode => host.hashCode ^ port.hashCode;
}

/// 网络发现状态
class NetworkDiscoveryState {
  const NetworkDiscoveryState({
    this.devices = const [],
    this.isDiscovering = false,
    this.lastDiscoveryTime,
    this.error,
  });

  final List<DiscoveredDevice> devices;
  final bool isDiscovering;
  final DateTime? lastDiscoveryTime;
  final String? error;

  NetworkDiscoveryState copyWith({
    List<DiscoveredDevice>? devices,
    bool? isDiscovering,
    DateTime? lastDiscoveryTime,
    String? error,
  }) =>
      NetworkDiscoveryState(
        devices: devices ?? this.devices,
        isDiscovering: isDiscovering ?? this.isDiscovering,
        lastDiscoveryTime: lastDiscoveryTime ?? this.lastDiscoveryTime,
        error: error,
      );
}

/// 网络发现服务 Provider
final networkDiscoveryProvider =
    StateNotifierProvider<NetworkDiscoveryNotifier, NetworkDiscoveryState>(
  (ref) => NetworkDiscoveryNotifier(),
);

/// 网络发现服务
/// 使用 bonsoir 包通过原生 API 发现局域网设备：
/// - iOS/macOS: Apple Bonjour
/// - Android: Network Service Discovery (NSD)
/// - Windows: Windows DNS-SD
/// - Linux: Avahi
class NetworkDiscoveryNotifier extends StateNotifier<NetworkDiscoveryState> {
  NetworkDiscoveryNotifier() : super(const NetworkDiscoveryState());

  /// mDNS 服务类型映射
  static const _serviceTypes = {
    '_smb._tcp': SourceType.smb,
    '_webdav._tcp': SourceType.webdav,
    '_webdavs._tcp': SourceType.webdav,
    '_ftp._tcp': SourceType.ftp,
    '_sftp-ssh._tcp': SourceType.sftp,
    '_nfs._tcp': SourceType.nfs,
    '_http._tcp': null, // 通用 HTTP，需要进一步判断
    '_https._tcp': null,
    // NAS 设备专用服务
    '_diskstation._tcp': SourceType.synology,
    '_synology._tcp': SourceType.synology,
    '_qnap._tcp': SourceType.qnap,
  };

  final Map<String, BonsoirDiscovery> _discoveries = {};
  final Map<String, StreamSubscription<BonsoirDiscoveryEvent>> _subscriptions = {};
  Timer? _discoveryTimer;
  bool _isStoppingAfterStreamError = false;

  /// 开始发现
  Future<void> startDiscovery() async {
    if (!mounted) return;
    if (state.isDiscovering) return;

    // 先停止任何现有的发现
    await stopDiscovery();
    if (!mounted) return;

    state = state.copyWith(isDiscovering: true, devices: [], error: null);
    logger.i('NetworkDiscovery: 开始发现局域网设备 (使用原生 API)');

    try {
      final devices = <DiscoveredDevice>{};

      // 为每个服务类型创建发现实例
      for (final entry in _serviceTypes.entries) {
        final serviceType = entry.key;
        final sourceType = entry.value;

        try {
          final discovery = BonsoirDiscovery(type: serviceType);
          await discovery.initialize();
          if (!mounted) {
            await discovery.stop();
            return;
          }

          // 监听发现事件
          // ignore: cancel_subscriptions - 已在 _subscriptions 中管理
          final subscription = discovery.eventStream?.listen(
            (event) =>
                _handleDiscoveryEvent(event, serviceType, sourceType, devices),
            onError: (Object error, StackTrace stackTrace) {
              _handleDiscoveryStreamError(serviceType, error, stackTrace);
            },
          );

          if (subscription != null) {
            _subscriptions[serviceType] = subscription;
          }

          await discovery.start();
          if (!mounted) {
            await subscription?.cancel();
            await discovery.stop();
            return;
          }
          _discoveries[serviceType] = discovery;

          logger.d('NetworkDiscovery: 开始监听服务类型 $serviceType');
        } on Exception catch (e) {
          logger.w('NetworkDiscovery: 初始化 $serviceType 发现失败', e);
        }
      }

      // 设置超时，在一段时间后停止发现并更新状态
      _discoveryTimer = Timer(const Duration(seconds: 10), () {
        AppError.fireAndForget(
          _finishDiscovery(),
          action: 'networkDiscovery.finishDiscovery',
        );
      });
    } on Exception catch (e, st) {
      logger.e('NetworkDiscovery: 发现失败', e, st);
      if (mounted) {
        state = state.copyWith(isDiscovering: false, error: e.toString());
      }
    }
  }

  /// Bonsoir 在 iOS 切换前后台时可能为所有服务流同时上报
  /// DefunctConnection。如果不提供 onError，这些错误会逃逸到
  /// PlatformDispatcher，被记为多次未捕获 FATAL。发现会话已不可用时
  /// 停止整个会话，保留已发现的设备，用户可手动重新扫描。
  void _handleDiscoveryStreamError(
    String serviceType,
    Object error,
    StackTrace stackTrace,
  ) {
    logger.w('NetworkDiscovery: $serviceType 发现连接中断', error, stackTrace);
    if (_isStoppingAfterStreamError) return;

    _isStoppingAfterStreamError = true;
    AppError.fireAndForget(
      _stopAfterDiscoveryStreamError(),
      action: 'networkDiscovery.stopAfterStreamError',
    );
  }

  Future<void> _stopAfterDiscoveryStreamError() async {
    try {
      await stopDiscovery();
    } finally {
      _isStoppingAfterStreamError = false;
    }
  }

  /// 处理发现事件
  void _handleDiscoveryEvent(
    BonsoirDiscoveryEvent event,
    String serviceType,
    SourceType? sourceType,
    Set<DiscoveredDevice> devices,
  ) {
    if (!mounted) return;

    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent():
        logger.d('NetworkDiscovery: 发现服务 ${event.service.name} ($serviceType)');
        // 服务发现后需要解析获取 IP 和端口
        final discovery = _discoveries[serviceType];
        if (discovery == null) return; // 发现服务已被清理
        event.service.resolve(discovery.serviceResolver);

      case BonsoirDiscoveryServiceResolvedEvent():
        final service = event.service;
        final host = service.host;
        final port = service.port;
        final name = service.name;

        if (host != null && host.isNotEmpty) {
          // 确定源类型
          final type = sourceType ?? _guessSourceType(name, port);
          if (type != null) {
            // 转换 TXT 记录
            Map<String, String>? txtRecords;
            final attributes = service.attributes;
            if (attributes.isNotEmpty) {
              txtRecords = Map<String, String>.from(attributes);
            }

            final device = DiscoveredDevice(
              name: name,
              host: host,
              port: port,
              type: type,
              serviceType: serviceType,
              txtRecords: txtRecords,
            );

            // 避免重复
            if (devices.add(device)) {
              logger.i('NetworkDiscovery: 解析设备 $device');
              // 更新状态
              state = state.copyWith(devices: devices.toList());
            }
          }
        }

      case BonsoirDiscoveryServiceLostEvent():
        logger.d('NetworkDiscovery: 服务离线 ${event.service.name}');
        // 从列表中移除
        final host = event.service.host;
        final port = event.service.port;
        if (host != null) {
          devices.removeWhere((d) => d.host == host && d.port == port);
          state = state.copyWith(devices: devices.toList());
        }

      default:
        // 忽略其他事件
        break;
    }
  }

  /// 完成发现
  Future<void> _finishDiscovery() async {
    if (!mounted) return;
    logger.i('NetworkDiscovery: 发现完成，共 ${state.devices.length} 个设备');
    state = state.copyWith(
      isDiscovering: false,
      lastDiscoveryTime: DateTime.now(),
    );
    // 超时不只是改 UI 状态；必须真正取消原生 mDNS 监听，
    // 否则后台切换时仍会收到过期会话的错误事件。
    await stopDiscovery();
  }

  /// 停止发现
  Future<void> stopDiscovery() async {
    _discoveryTimer?.cancel();
    _discoveryTimer = null;

    // 取消所有订阅
    for (final subscription in _subscriptions.values) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    // 停止所有发现实例
    for (final discovery in _discoveries.values) {
      try {
        await discovery.stop();
      } on Exception catch (e) {
        logger.w('NetworkDiscovery: 停止发现失败', e);
      }
    }
    _discoveries.clear();

    if (mounted && state.isDiscovering) {
      state = state.copyWith(isDiscovering: false);
    }
  }

  /// 根据名称和端口猜测源类型
  SourceType? _guessSourceType(String name, int port) {
    final nameLower = name.toLowerCase();

    // 根据名称关键词判断
    if (nameLower.contains('synology') || nameLower.contains('diskstation')) {
      return SourceType.synology;
    }
    if (nameLower.contains('qnap')) {
      return SourceType.qnap;
    }

    // 根据端口判断
    return switch (port) {
      5001 || 5000 => SourceType.synology,
      8080 => SourceType.qnap,
      445 => SourceType.smb,
      443 || 80 => SourceType.webdav,
      21 => SourceType.ftp,
      22 => SourceType.sftp,
      2049 => SourceType.nfs,
      _ => null,
    };
  }

  @override
  void dispose() {
    // dispose 不能是 async，使用 fireAndForget 异步停止扫描
    AppError.fireAndForget(stopDiscovery(), action: 'networkDiscovery.stopDiscovery');
    super.dispose();
  }
}
