import 'dart:io';

import 'package:flutter/services.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_item.dart';

/// MethodChannel 薄封装：仅做参数序列化与平台守卫。
///
/// 业务侧不要直接用这个类，请用 [SpotlightIndexer]（带"是否启用"门控）。
class SpotlightChannel {
  SpotlightChannel._();

  static const MethodChannel _channel =
      MethodChannel('com.kkape.mynas/spotlight');

  /// 反向回调（点 Spotlight 结果时由 native 调起）。
  static MethodChannel get channel => _channel;

  /// 仅在 macOS 上有效；其他平台所有方法均 no-op，返回 0/null。
  static bool get isSupported => Platform.isMacOS;

  static Future<int> upsertItems(List<SpotlightItem> items) async {
    if (!isSupported || items.isEmpty) return 0;
    final result = await _channel.invokeMethod<int>(
      'upsertItems',
      items.map((it) => it.toChannelMap()).toList(),
    );
    return result ?? 0;
  }

  static Future<void> deleteItems(List<String> ids) async {
    if (!isSupported || ids.isEmpty) return;
    await _channel.invokeMethod<void>('deleteItems', ids);
  }

  static Future<void> deleteAll() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('deleteAll');
  }

  /// 读取 cold-start 时 native 暂存的待处理 deep link id（消费即清空）。
  static Future<String?> consumePendingDeepLink() async {
    if (!isSupported) return null;
    return _channel.invokeMethod<String>('consumePendingDeepLink');
  }
}
