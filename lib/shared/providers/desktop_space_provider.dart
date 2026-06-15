import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/hive_utils.dart';

/// 桌面端 sidebar 顶部双 space 切换的 state：
/// - [media]：影视 / 直播 / 音乐 / 照片 / 阅读 / 文件 / 概览（默认）
/// - [ops]：运维总览 / 下载器 / 传输队列 / PT / NAStool / 数据源
///
/// 持久化到 Hive `settings` box（key=`desktop_space`），重启保留用户上次所在区。
enum DesktopSpace { media, ops }

final desktopSpaceProvider =
    StateNotifierProvider<DesktopSpaceNotifier, DesktopSpace>(
  (ref) => DesktopSpaceNotifier(),
);

class DesktopSpaceNotifier extends StateNotifier<DesktopSpace> {
  DesktopSpaceNotifier() : super(DesktopSpace.media) {
    _load();
  }

  static const _key = 'desktop_space';

  /// 用户是否在持久化值加载完成前已主动切换过 space。
  /// 避免异步 _load() 回填覆盖用户刚点击的切换（冷启动竞态）。
  bool _userTouched = false;

  Future<void> _load() async {
    try {
      final box = await HiveUtils.getSettingsBox();
      final v = box.get(_key) as String?;
      if (_userTouched || v == null) return;
      for (final s in DesktopSpace.values) {
        if (s.name == v) {
          if (!_userTouched) state = s;
          return;
        }
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'load desktop_space');
    }
  }

  Future<void> set(DesktopSpace s) async {
    _userTouched = true;
    if (s == state) return;
    state = s;
    try {
      final box = await HiveUtils.getSettingsBox();
      await box.put(_key, s.name);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'save desktop_space');
    }
  }
}

/// 给定路由 path，返回它属于哪个 space（用于跨 space 链接时自动切换 sidebar）。
DesktopSpace? spaceOfRoute(String path) {
  if (kIsWeb) {
    // web 暂不区分
    return null;
  }
  const mediaRoutes = {
    '/home',
    '/video',
    '/live',
    '/music',
    '/photo',
    '/reading',
    '/files',
  };
  const opsRoutes = {
    '/ops',
    '/download',
    '/transfer',
    '/pt',
    '/nastool',
    '/sources',
  };
  for (final p in mediaRoutes) {
    if (path.startsWith(p)) return DesktopSpace.media;
  }
  for (final p in opsRoutes) {
    if (path.startsWith(p)) return DesktopSpace.ops;
  }
  return null;
}
