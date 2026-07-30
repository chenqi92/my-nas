import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:my_nas/core/utils/tv_capabilities.dart';

/// 平台能力检测工具
/// 用于检测当前平台支持的功能
class PlatformCapabilities {
  PlatformCapabilities._();

  /// 是否为桌面平台
  static bool get isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// 是否为移动平台
  static bool get isMobile =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  /// 是否为 Android TV / 电视盒子
  ///
  /// 依赖启动时 TvCapabilities.init() 的探测结果；注意 TV 设备的
  /// isMobile 也为 true（Android 平台），需要 TV 特化行为时先判本项。
  static bool get isTV => TvCapabilities.isAndroidTv;


  /// 是否为 Web 平台
  static bool get isWeb => kIsWeb;

  /// 是否支持保存到相册（仅 iOS/Android）
  static bool get canSaveToGallery => isMobile;

  /// 是否支持文件选择器保存（桌面端）
  static bool get canSaveWithPicker => isDesktop;

  /// 是否支持系统分享
  /// - iOS/Android: 完整支持
  /// - macOS: 支持
  /// - Windows: 有限支持（share_plus 在 Windows 上可能不工作）
  /// - Linux: 有限支持
  static bool get canShare {
    if (kIsWeb) return false;
    if (Platform.isIOS || Platform.isAndroid || Platform.isMacOS) return true;
    // Windows 和 Linux 的 share_plus 支持有限
    return Platform.isWindows || Platform.isLinux;
  }

  /// 是否支持完整的系统分享（iOS/Android/macOS）
  static bool get canShareNatively {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid || Platform.isMacOS;
  }

  /// 是否支持复制到剪贴板（所有平台）
  static bool get canCopyToClipboard => true;

  /// 获取下载选项列表
  static List<DownloadOption> get downloadOptions {
    final options = <DownloadOption>[];

    if (canSaveToGallery) {
      options.add(DownloadOption.saveToGallery);
    }

    if (canSaveWithPicker) {
      options.add(DownloadOption.saveWithPicker);
    }

    return options;
  }

  /// 获取分享选项列表
  static List<ShareOption> get shareOptions {
    final options = <ShareOption>[];

    if (canShare) {
      options.add(ShareOption.systemShare);
    }

    if (canCopyToClipboard) {
      options.add(ShareOption.copyLink);
    }

    return options;
  }

  /// 获取平台名称
  static String get platformName {
    if (kIsWeb) return 'Web';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }
}

/// 下载选项
enum DownloadOption {
  /// 保存到相册（移动端）
  saveToGallery,

  /// 使用文件选择器保存（桌面端）
  saveWithPicker,
}

/// 分享选项
enum ShareOption {
  /// 系统分享
  systemShare,

  /// 复制链接
  copyLink,
}
