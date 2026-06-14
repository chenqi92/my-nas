import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/sync/cloud_sync_service.dart';
import 'package:my_nas/core/utils/hive_utils.dart';

/// 云同步「自动同步」总开关。开启后由 [cloudSyncSchedulerProvider] 在 app
/// 运行期间按 [cloudSyncIntervalProvider] 的周期自动触发同步。
/// 持久化于 settings box，默认关闭。
final cloudSyncAutoEnabledProvider =
    StateNotifierProvider<CloudSyncAutoEnabledNotifier, bool>(
  (ref) => CloudSyncAutoEnabledNotifier(),
);

class CloudSyncAutoEnabledNotifier extends StateNotifier<bool> {
  CloudSyncAutoEnabledNotifier() : super(false) {
    _load();
  }

  static const _key = 'cloud_sync_auto_enabled';

  Future<void> _load() async {
    try {
      final box = await HiveUtils.getSettingsBox();
      final v = box.get(_key) as bool?;
      if (v != null) state = v;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载云同步自动同步开关失败，使用默认值');
    }
  }

  Future<void> setEnabled({required bool enabled}) async {
    state = enabled;
    try {
      final box = await HiveUtils.getSettingsBox();
      await box.put(_key, enabled);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '保存云同步自动同步开关失败');
    }
  }
}

/// 云同步自动同步周期（分钟）。仅在 [cloudSyncAutoEnabledProvider] 开启时生效。
/// 持久化于 settings box，默认 30 分钟。
final cloudSyncIntervalProvider =
    StateNotifierProvider<CloudSyncIntervalNotifier, int>(
  (ref) => CloudSyncIntervalNotifier(),
);

class CloudSyncIntervalNotifier extends StateNotifier<int> {
  CloudSyncIntervalNotifier() : super(_defaultMinutes) {
    _load();
  }

  static const _key = 'cloud_sync_interval_minutes';
  static const _defaultMinutes = 30;

  Future<void> _load() async {
    try {
      final box = await HiveUtils.getSettingsBox();
      final v = box.get(_key) as int?;
      if (v != null && v > 0) state = v;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载云同步周期设置失败，使用默认值');
    }
  }

  Future<void> setMinutes(int minutes) async {
    if (minutes <= 0) return;
    state = minutes;
    try {
      final box = await HiveUtils.getSettingsBox();
      await box.put(_key, minutes);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '保存云同步周期设置失败');
    }
  }
}

/// 云同步自动调度器。监听 [cloudSyncAutoEnabledProvider] 与
/// [cloudSyncIntervalProvider]，在「开启 且 周期>0」时维护一个
/// [Timer.periodic]，每个周期触发一次 [CloudSyncService.syncNow]
/// （服务内部有 `_syncing` 并发保护，重复触发会被忽略）。
///
/// 该 provider 只持有一个 timer：设置变更时先 cancel 再按新参数重建，
/// provider 被销毁时（[Ref.onDispose]）一并 cancel，避免泄漏。
///
/// 注意：定时仅在 app 运行时生效，不做后台 / 系统级调度。app 退出后
/// 不会继续同步；重新进入并激活此 provider 后才会恢复周期同步。
///
/// 激活方式：在桌面外壳 build 中 `ref.watch(cloudSyncSchedulerProvider)`
/// 读一次即可（其本身轻量，只持有一个 timer）。
final cloudSyncSchedulerProvider = Provider<void>((ref) {
  Timer? timer;

  void cancel() {
    timer?.cancel();
    timer = null;
  }

  void rebuild() {
    cancel();
    final enabled = ref.read(cloudSyncAutoEnabledProvider);
    final minutes = ref.read(cloudSyncIntervalProvider);
    if (!enabled || minutes <= 0) return;
    timer = Timer.periodic(Duration(minutes: minutes), (_) {
      AppError.fireAndForget(
        CloudSyncService.instance.syncNow(),
        action: 'cloudSync.autoTick',
      );
    });
  }

  ref
    ..listen<bool>(cloudSyncAutoEnabledProvider, (prev, next) => rebuild())
    ..listen<int>(cloudSyncIntervalProvider, (prev, next) => rebuild())
    ..onDispose(cancel);

  rebuild();
});
