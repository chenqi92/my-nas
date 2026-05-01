import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 设备信息帮助类
class DeviceInfoHelper {
  DeviceInfoHelper._();

  static final DeviceInfoHelper _instance = DeviceInfoHelper._();
  static DeviceInfoHelper get instance => _instance;

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final Connectivity _connectivity = Connectivity();

  String? _deviceId;
  String? _deviceModel;
  String? _deviceBrand;
  String? _osName;
  String? _osVersion;
  String? _appVersion;
  String? _screenResolution;
  bool _initialized = false;

  String? get deviceId => _deviceId;
  String? get deviceModel => _deviceModel;
  String? get deviceBrand => _deviceBrand;
  String? get osName => _osName;
  String? get osVersion => _osVersion;
  String? get appVersion => _appVersion;
  String? get screenResolution => _screenResolution;

  /// 初始化设备信息
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await _loadDeviceInfo();
      await _loadAppVersion();
      _loadScreenResolution();
      _initialized = true;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '设备信息初始化失败不影响核心功能');
      if (kDebugMode) {
        print('[DeviceInfoHelper] Failed to initialize: $e');
      }
    }
  }

  /// 获取当前网络类型
  Future<String?> getNetworkType() async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (results.isEmpty) return 'none';
      return results.map(_connectivityToString).join(',');
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '获取网络类型失败返回空值');
      return null;
    }
  }

  String _connectivityToString(ConnectivityResult result) => switch (result) {
        ConnectivityResult.wifi => 'wifi',
        ConnectivityResult.mobile => 'mobile',
        ConnectivityResult.ethernet => 'ethernet',
        ConnectivityResult.vpn => 'vpn',
        ConnectivityResult.bluetooth => 'bluetooth',
        ConnectivityResult.other => 'other',
        ConnectivityResult.none => 'none',
      };

  /// 加载屏幕分辨率
  void _loadScreenResolution() {
    try {
      final view = PlatformDispatcher.instance.implicitView;
      if (view != null) {
        final size = view.physicalSize;
        final ratio = view.devicePixelRatio;
        _screenResolution = '${size.width.toInt()}x${size.height.toInt()}@${ratio.toStringAsFixed(1)}x';
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载屏幕分辨率失败不影响核心功能');
      if (kDebugMode) {
        print('[DeviceInfoHelper] Failed to load screen resolution: $e');
      }
    }
  }

  Future<void> _loadDeviceInfo() async {
    if (kIsWeb) {
      final webInfo = await _deviceInfo.webBrowserInfo;
      _deviceId = webInfo.userAgent?.hashCode.toString();
      _deviceModel = webInfo.browserName.name;
      _deviceBrand = webInfo.vendor;
      _osName = 'Web';
      _osVersion = webInfo.appVersion;
    } else if (Platform.isAndroid) {
      final androidInfo = await _deviceInfo.androidInfo;
      _deviceId = androidInfo.id;
      _deviceModel = androidInfo.model;
      _deviceBrand = androidInfo.brand;
      _osName = 'Android';
      _osVersion = androidInfo.version.release;
    } else if (Platform.isIOS) {
      final iosInfo = await _deviceInfo.iosInfo;
      _deviceId = iosInfo.identifierForVendor;
      _deviceModel = iosInfo.utsname.machine;
      _deviceBrand = 'Apple';
      _osName = 'iOS';
      _osVersion = iosInfo.systemVersion;
    } else if (Platform.isMacOS) {
      final macInfo = await _deviceInfo.macOsInfo;
      _deviceId = macInfo.systemGUID;
      _deviceModel = macInfo.model;
      _deviceBrand = 'Apple';
      _osName = 'macOS';
      _osVersion = '${macInfo.majorVersion}.${macInfo.minorVersion}.${macInfo.patchVersion}';
    } else if (Platform.isWindows) {
      final windowsInfo = await _deviceInfo.windowsInfo;
      _deviceId = windowsInfo.deviceId;
      _deviceModel = windowsInfo.productName;
      _deviceBrand = windowsInfo.registeredOwner;
      _osName = 'Windows';
      _osVersion = '${windowsInfo.majorVersion}.${windowsInfo.minorVersion}.${windowsInfo.buildNumber}';
    } else if (Platform.isLinux) {
      final linuxInfo = await _deviceInfo.linuxInfo;
      _deviceId = linuxInfo.machineId;
      _deviceModel = linuxInfo.prettyName;
      _deviceBrand = linuxInfo.name;
      _osName = 'Linux';
      _osVersion = linuxInfo.versionId;
    }
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载应用版本失败使用默认值');
      if (kDebugMode) {
        print('[DeviceInfoHelper] Failed to load app version: $e');
      }
      _appVersion = '1.0.0';
    }
  }
}
