import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/hive_utils.dart';
import 'package:my_nas/features/transfer/data/services/transfer_service.dart';

/// 「传输并发任务数」设置：同时进行的上传 / 下载 / 缓存任务上限（1-3）。
///
/// 持久化于 settings box（key `transfer_max_concurrent`），默认 3。状态与
/// [TransferService.maxConcurrentTransfers] 同步：构造 `_load` 时即写入静态字段
/// （启动即生效），[setValue] 同时写 Hive 与静态字段，[TransferService] 在下次
/// 调度队列时立即读取新值。
final transferConcurrencyProvider =
    StateNotifierProvider<TransferConcurrencyNotifier, int>(
  (ref) => TransferConcurrencyNotifier(),
);

class TransferConcurrencyNotifier extends StateNotifier<int> {
  TransferConcurrencyNotifier() : super(_defaultValue) {
    TransferService.maxConcurrentTransfers = state;
    _load();
  }

  static const _key = 'transfer_max_concurrent';
  static const _defaultValue = 3;
  static const _minValue = 1;
  static const _maxValue = 3;

  Future<void> _load() async {
    try {
      final box = await HiveUtils.getSettingsBox();
      final v = box.get(_key) as int?;
      if (v != null) {
        final clamped = v.clamp(_minValue, _maxValue);
        state = clamped;
        TransferService.maxConcurrentTransfers = clamped;
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载传输并发数设置失败，使用默认值');
    }
  }

  /// 设置并发上限（自动夹紧到 1-3），同步写入 Hive 与 [TransferService]。
  Future<void> setValue(int value) async {
    final clamped = value.clamp(_minValue, _maxValue);
    state = clamped;
    TransferService.maxConcurrentTransfers = clamped;
    try {
      final box = await HiveUtils.getSettingsBox();
      await box.put(_key, clamped);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '保存传输并发数设置失败');
    }
  }
}
