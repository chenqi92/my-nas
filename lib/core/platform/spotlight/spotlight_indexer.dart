import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_channel.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_item.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_settings.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 业务侧统一入口：自动按 [spotlightEnabledProvider] 门控、并守卫平台。
///
/// 写入/删除均 fire-and-forget——索引失败不阻塞主流程，错误由
/// [AppError.fireAndForget] 兜底上报。
class SpotlightIndexer {
  SpotlightIndexer(this._ref);

  final Ref _ref;

  bool get _enabled =>
      SpotlightChannel.isSupported && _ref.read(spotlightEnabledProvider);

  /// 构造 Spotlight 全局唯一 id：`mynas://<kind>/<rawId>`。
  ///
  /// 业务侧的 rawId 可能含 `|`、`/` 等字符，统一编码避免与 Uri 冲突。
  static String buildId(SpotlightItemKind kind, String rawId) {
    final encoded = Uri.encodeComponent(rawId);
    return 'mynas://${kind.wireName}/$encoded';
  }

  /// 批量 upsert——按业务 chunk 调用，单次 ≤500 较稳妥。
  void upsert(List<SpotlightItem> items) {
    if (!_enabled || items.isEmpty) return;
    AppError.fireAndForget(
      () async {
        final count = await SpotlightChannel.upsertItems(items);
        logger.d('Spotlight upsert ${items.length} -> indexed $count');
      }(),
      action: 'SpotlightIndexer.upsert',
    );
  }

  /// 删除——传 Spotlight 全局 id（[buildId] 产物）。
  void deleteByIds(List<String> ids) {
    if (!_enabled || ids.isEmpty) return;
    AppError.fireAndForget(
      SpotlightChannel.deleteItems(ids),
      action: 'SpotlightIndexer.deleteByIds',
    );
  }

  /// 按 (kind, rawIds) 删除（业务侧无需知道 buildId 规则）。
  void delete(SpotlightItemKind kind, Iterable<String> rawIds) {
    final ids = rawIds.map((raw) => buildId(kind, raw)).toList(growable: false);
    deleteByIds(ids);
  }

  /// 清空本 App 所有索引——关掉 Spotlight 开关 / 用户手动清理时使用。
  ///
  /// 注意此方法忽略 _enabled 守卫（关开关时必然 enabled=false 但要清空）。
  Future<void> clearAll() async {
    if (!SpotlightChannel.isSupported) return;
    await SpotlightChannel.deleteAll();
  }
}

final spotlightIndexerProvider = Provider<SpotlightIndexer>(
  SpotlightIndexer.new,
);
