import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/sync/syncable_module.dart';
import 'package:my_nas/features/book/data/services/sources/book_source_manager_service.dart';
import 'package:my_nas/features/book/domain/entities/book_source.dart';

/// 同步书源（用户自行导入的 Legado 兼容书源）。
///
/// 策略：
/// - exportData = 全部书源
/// - importData = 按 bookSourceUrl 主键合并；冲突 last-`lastUpdateTime`-wins
/// - localUpdatedAt = max(lastUpdateTime)
///
/// 不同步：assets/ 内置（按规则禁止内置）；不会泄露任何凭证字段——书源
/// 的 `loginUrl` / `loginUi` 是公开规则，本身不含用户登录态。
class BookSourcesSyncModule implements SyncableModule {
  BookSourcesSyncModule();

  final BookSourceManagerService _service = BookSourceManagerService.instance;

  @override
  String get key => 'book_sources';

  @override
  String get displayName => appL10n.syncModuleReadingSources;

  @override
  Future<DateTime?> getLocalUpdatedAt() async {
    await _service.init();
    final list = await _service.getSources();
    if (list.isEmpty) return null;
    var maxTs = 0;
    for (final s in list) {
      if (s.lastUpdateTime > maxTs) maxTs = s.lastUpdateTime;
    }
    if (maxTs == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(maxTs);
  }

  @override
  Future<Map<String, dynamic>> exportData() async {
    await _service.init();
    final list = await _service.getSources();
    return {
      'version': 1,
      'sources': list.map((s) => s.toJson()).toList(),
    };
  }

  @override
  Future<void> importData(Map<String, dynamic> data) async {
    await _service.init();
    final list = (data['sources'] as List?) ?? const [];
    final remote = <BookSource>[];
    for (final raw in list.cast<Map<dynamic, dynamic>>()) {
      try {
        remote.add(BookSource.fromJson(Map<String, dynamic>.from(raw)));
      } on Exception catch (_) {
        continue;
      }
    }
    if (remote.isEmpty) return;

    final locals = await _service.getSources();
    final localByUrl = {for (final s in locals) s.bookSourceUrl: s};

    final toAdd = <BookSource>[];
    for (final r in remote) {
      final l = localByUrl[r.bookSourceUrl];
      if (l == null) {
        toAdd.add(r);
        continue;
      }
      // 远端更新 → 覆盖；保持本地 customOrder
      if (r.lastUpdateTime > l.lastUpdateTime) {
        await _service.updateSource(
          r.copyWith(id: l.id, customOrder: l.customOrder),
        );
      }
    }
    if (toAdd.isNotEmpty) {
      await _service.addSources(toAdd);
    }
  }
}
