import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/features/book/data/services/sources/book_source_manager_service.dart';
import 'package:my_nas/features/book/domain/entities/book_source.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'book_source_provider.g.dart';

/// 书源管理服务 Provider
@riverpod
BookSourceManagerService bookSourceManager(Ref ref) => BookSourceManagerService.instance;

/// 书源列表 Provider
@riverpod
class BookSources extends _$BookSources {
  @override
  Future<List<BookSource>> build() async {
    final manager = ref.watch(bookSourceManagerProvider);
    await manager.init();
    
    // 监听变更事件
    final subscription = manager.events.listen((_) {
      ref.invalidateSelf();
    });
    
    ref.onDispose(subscription.cancel);
    
    return manager.getSources();
  }

  /// 添加书源
  Future<void> addSource(BookSource source) async {
    final manager = ref.read(bookSourceManagerProvider);
    await manager.addSource(source);
  }

  /// 批量添加书源
  Future<int> addSources(List<BookSource> sources) async {
    final manager = ref.read(bookSourceManagerProvider);
    return manager.addSources(sources);
  }

  /// 更新书源
  Future<void> updateSource(BookSource source) async {
    final manager = ref.read(bookSourceManagerProvider);
    await manager.updateSource(source);
  }

  /// 删除书源
  Future<void> removeSource(String sourceId) async {
    final manager = ref.read(bookSourceManagerProvider);
    await manager.removeSource(sourceId);
  }

  /// 切换启用状态
  Future<void> toggleSource(String sourceId, {required bool enabled}) async {
    final manager = ref.read(bookSourceManagerProvider);
    await manager.toggleSource(sourceId, enabled: enabled);
  }

  /// 重新排序
  Future<void> reorderSources(int oldIndex, int newIndex) async {
    final manager = ref.read(bookSourceManagerProvider);
    await manager.reorderSources(oldIndex, newIndex);
  }

  /// 从JSON导入
  Future<List<BookSource>> importFromJson(String json) async {
    final manager = ref.read(bookSourceManagerProvider);
    return manager.importFromJson(json);
  }

  /// 从URL导入
  Future<List<BookSource>> importFromUrl(String url) async {
    final manager = ref.read(bookSourceManagerProvider);
    return manager.importFromUrl(url);
  }
}

/// 已启用的书源列表 Provider
@riverpod
Future<List<BookSource>> enabledBookSources(Ref ref) async {
  final sources = await ref.watch(bookSourcesProvider.future);
  return sources.where((s) => s.enabled).toList();
}

/// 书源分组 Provider
@riverpod
Future<Map<String, List<BookSource>>> bookSourceGroups(Ref ref) async {
  final sources = await ref.watch(bookSourcesProvider.future);
  final grouped = <String, List<BookSource>>{};
  
  for (final source in sources) {
    final groups = source.groups;
    if (groups.isEmpty) {
      grouped.putIfAbsent(appL10n.bookSourceUngrouped, () => []).add(source);
    } else {
      for (final group in groups) {
        grouped.putIfAbsent(group, () => []).add(source);
      }
    }
  }
  
  return grouped;
}
