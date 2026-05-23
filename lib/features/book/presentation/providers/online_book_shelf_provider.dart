import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/online_book_shelf_service.dart';

/// 在线书架状态 Provider
final onlineBookShelfProvider = StateNotifierProvider<OnlineBookShelfNotifier, AsyncValue<List<OnlineBookShelfItem>>>((ref) => OnlineBookShelfNotifier());

/// 在线书架状态管理器
class OnlineBookShelfNotifier extends StateNotifier<AsyncValue<List<OnlineBookShelfItem>>> {
  OnlineBookShelfNotifier() : super(const AsyncValue.loading()) {
    _load();
  }

  final _service = OnlineBookShelfService.instance;

  /// 加载书架数据
  Future<void> _load() async {
    try {
      logger.d('在线书架Provider: 开始加载数据...');
      final items = await _service.getAll();
      logger.i('在线书架Provider: 加载完成，共 ${items.length} 本书');
      state = AsyncValue.data(items);
    } catch (e, st) {
      logger.e('在线书架Provider: 加载失败', e, st);
      state = AsyncValue.error(e, st);
    }
  }

  /// 刷新书架数据
  Future<void> refresh() async {
    await _load();
  }

  /// 添加书籍后刷新
  Future<void> onBookAdded() async {
    await _load();
  }

  /// 删除书籍后刷新
  Future<void> onBookRemoved() async {
    await _load();
  }

  /// 获取书架中的书籍数量
  int get count => state.valueOrNull?.length ?? 0;

  /// 搜索书架
  List<OnlineBookShelfItem> search(String query) {
    final items = state.valueOrNull ?? [];
    if (query.isEmpty) return items;
    
    final lowerQuery = query.toLowerCase();
    return items.where((item) => 
      item.name.toLowerCase().contains(lowerQuery) ||
      item.author.toLowerCase().contains(lowerQuery)
    ).toList();
  }
}
