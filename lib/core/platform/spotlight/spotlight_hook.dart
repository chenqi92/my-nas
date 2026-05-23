import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_channel.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_indexer.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_item.dart';

/// 给"非 Riverpod 感知"的服务用的静态 hook。
///
/// 用法：业务侧 deleteXxx 完成后 fire-and-forget 调用——
/// upsert 走 isEnabled 门控；delete 不门控（domain 空时为 no-op）。
class SpotlightHook {
  SpotlightHook._();

  /// 与 [SpotlightSettingsNotifier] 共享的 settings key。
  static const String _enabledKey = 'spotlight_index_enabled';

  static bool get _isEnabled {
    if (!SpotlightChannel.isSupported) return false;
    if (!Hive.isBoxOpen('settings')) return false;
    final box = Hive.box<dynamic>('settings');
    return (box.get(_enabledKey, defaultValue: false) as bool?) ?? false;
  }

  /// 数据被删除后从 Spotlight 移除对应条目（不门控，删空也无副作用）。
  static void afterDelete(SpotlightItemKind kind, Iterable<String> rawIds) {
    if (!SpotlightChannel.isSupported) return;
    final ids = rawIds
        .map((raw) => SpotlightIndexer.buildId(kind, raw))
        .toList(growable: false);
    if (ids.isEmpty) return;
    AppError.fireAndForget(
      SpotlightChannel.deleteItems(ids),
      action: 'SpotlightHook.afterDelete.${kind.wireName}',
    );
  }

  /// 单条笔记 upsert——MediaFavoritesService.add(note) 触发。
  static void afterUpsertNote({required String rawId, required String title}) {
    if (!_isEnabled) return;
    final item = SpotlightItem(
      id: SpotlightIndexer.buildId(SpotlightItemKind.note, rawId),
      kind: SpotlightItemKind.note,
      title: title,
    );
    AppError.fireAndForget(
      SpotlightChannel.upsertItems([item]),
      action: 'SpotlightHook.afterUpsertNote',
    );
  }
}
