import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/shared/providers/media_favorites_provider.dart';
import 'package:my_nas/shared/services/media_favorites_service.dart';

/// "我的收藏"页面
///
/// 通过 TabBar 分类型展示用户在 5 个媒体列表（video/photo/note/book/comic）
/// 收藏的项目。每个 tab 列出对应类型的收藏，长按 / 滑动可取消收藏。
///
/// 数据源：[mediaFavoritesProvider]，由 [MediaFavoritesService] 单 Hive box 提供。
String _getTabLabel(BuildContext context, String keyName) => switch (keyName) {
      'favoritesTabVideo' => context.l10n.favoritesTabVideo,
      'favoritesTabPhoto' => context.l10n.favoritesTabPhoto,
      'favoritesTabNote' => context.l10n.favoritesTabNote,
      'favoritesTabBook' => context.l10n.favoritesTabBook,
      'favoritesTabComic' => context.l10n.favoritesTabComic,
      'favoritesTabMusic' => context.l10n.favoritesTabMusic,
      _ => keyName,
    };

class FavoritesPage extends ConsumerStatefulWidget {
  const FavoritesPage({super.key});

  @override
  ConsumerState<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends ConsumerState<FavoritesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// 与 _tabs 顺序一致——索引对应一个 MediaType
  static const _tabs = <_FavoriteTab>[
    _FavoriteTab(MediaType.video, 'favoritesTabVideo', Icons.movie_rounded),
    _FavoriteTab(MediaType.photo, 'favoritesTabPhoto', Icons.photo_rounded),
    _FavoriteTab(MediaType.note, 'favoritesTabNote', Icons.note_alt_rounded),
    _FavoriteTab(MediaType.book, 'favoritesTabBook', Icons.menu_book_rounded),
    _FavoriteTab(MediaType.comic, 'favoritesTabComic', Icons.collections_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.favoritesPageTitle),
        centerTitle: false,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _tabs
              .map((t) => Tab(icon: Icon(t.icon), text: _getTabLabel(context, t.label)))
              .toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs
            .map((t) => _FavoriteListView(type: t.type))
            .toList(),
      ),
    );
}

class _FavoriteTab {
  const _FavoriteTab(this.type, this.label, this.icon);
  final MediaType type;
  final String label;
  final IconData icon;
}

class _FavoriteListView extends ConsumerWidget {
  const _FavoriteListView({required this.type});

  final MediaType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncFavorites = ref.watch(mediaFavoritesProvider(type));

    return asyncFavorites.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(context.l10n.favoritesLoadFailed(e))),
      data: (items) {
        if (items.isEmpty) return _buildEmpty(context);
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) =>
              _FavoriteTile(item: items[index]),
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.favorite_border_rounded,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.favoritesEmptyMessage(_getMediaTypeLabel(context, type)),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.favoritesEmptyHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color:
                  theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  String _getMediaTypeLabel(BuildContext context, MediaType t) => switch (t) {
        MediaType.video => context.l10n.favoritesTabVideo,
        MediaType.photo => context.l10n.favoritesTabPhoto,
        MediaType.note => context.l10n.favoritesTabNote,
        MediaType.book => context.l10n.favoritesTabBook,
        MediaType.comic => context.l10n.favoritesTabComic,
        MediaType.music => context.l10n.favoritesTabMusic,
      };



}

class _FavoriteTile extends ConsumerWidget {
  const _FavoriteTile({required this.item});

  final MediaFavoriteItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey('fav_${item.type.id}_${item.sourceId}_${item.path}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        color: AppColors.error,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) async {
        await ref.read(mediaFavoritesActionsProvider).remove(
              type: item.type,
              sourceId: item.sourceId,
              path: item.path,
            );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.favoritesRemovedMessage(item.displayName))),
        );
      },
      child: ListTile(
        leading: Icon(_iconOf(item.type), color: theme.colorScheme.primary),
        title: Text(
          item.displayName.isNotEmpty ? item.displayName : context.l10n.favoritesUnnamedItem,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          context.l10n.favoritesItemSubtitle(item.sourceId, _formatDate(item.addedAt)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.favorite_rounded, color: AppColors.error),
          tooltip: context.l10n.favoritesRemoveTooltip,
          onPressed: () async {
            await ref.read(mediaFavoritesActionsProvider).remove(
                  type: item.type,
                  sourceId: item.sourceId,
                  path: item.path,
                );
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.favoritesRemovedMessage(item.displayName))),
            );
          },
        ),
      ),
    );
  }

  IconData _iconOf(MediaType t) => switch (t) {
        MediaType.video => Icons.movie_rounded,
        MediaType.photo => Icons.photo_rounded,
        MediaType.note => Icons.note_alt_rounded,
        MediaType.book => Icons.menu_book_rounded,
        MediaType.comic => Icons.collections_rounded,
        MediaType.music => Icons.music_note_rounded,
      };

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final yyyy = local.year.toString().padLeft(4, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd';
  }
}
