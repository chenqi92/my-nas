import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/shared/pages/favorites_page.dart';
import 'package:my_nas/shared/providers/media_favorites_provider.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';

/// 桌面「设置 · 我的收藏」详情 pane。
///
/// 对应设计稿 `settings_panes.jsx` 的 `PaneFavorites`：跨类型聚合收藏 tiles
/// （影视 / 照片 / 音乐 / 图书 / 漫画 / 笔记 + 计数 + chevron）。
///
/// 计数接真实状态：
/// - 影视 / 照片 / 图书 / 漫画 / 笔记 → [mediaFavoritesProvider]（单 Hive box）。
/// - 音乐 → [musicFavoritesProvider]（StateNotifier，同步到「我喜欢」歌单）。
///
/// tile 点击进入聚合收藏页 [FavoritesPage]。
class FavoritesPane extends ConsumerWidget {
  const FavoritesPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final musicCount = ref.watch(musicFavoritesProvider).favorites.length;

    final tiles = <_FavTile>[
      _FavTile(
        type: MediaType.video,
        label: '影视',
        icon: Icons.movie_outlined,
        count: _countOf(ref, MediaType.video),
      ),
      _FavTile(
        type: MediaType.photo,
        label: '照片',
        icon: Icons.photo_outlined,
        count: _countOf(ref, MediaType.photo),
      ),
      _FavTile(
        type: MediaType.music,
        label: '音乐',
        icon: Icons.music_note_outlined,
        count: musicCount,
      ),
      _FavTile(
        type: MediaType.book,
        label: '图书',
        icon: Icons.menu_book_outlined,
        count: _countOf(ref, MediaType.book),
      ),
      _FavTile(
        type: MediaType.comic,
        label: '漫画',
        icon: Icons.collections_bookmark_outlined,
        count: _countOf(ref, MediaType.comic),
      ),
      _FavTile(
        type: MediaType.note,
        label: '笔记',
        icon: Icons.note_alt_outlined,
        count: _countOf(ref, MediaType.note),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SetHead(
          icon: Icons.favorite_outline_rounded,
          title: '我的收藏',
          subtitle: '跨类型聚合的收藏内容。音乐收藏自动同步到「我喜欢」歌单。',
        ),

        // ---- 收藏聚合 ----
        SetSection(
          title: '收藏聚合',
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 12.0;
                  const minTile = 150.0;
                  final cols =
                      ((constraints.maxWidth + spacing) / (minTile + spacing))
                          .floor()
                          .clamp(1, tiles.length);
                  final tileWidth =
                      (constraints.maxWidth - spacing * (cols - 1)) / cols;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final tile in tiles)
                        SizedBox(
                          width: tileWidth,
                          child: _FavTileCard(
                            tile: tile,
                            onTap: () => _openFavorites(context),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 读取某媒体类型的收藏数量（未加载完成时回退为 0）。
  int _countOf(WidgetRef ref, MediaType type) =>
      ref.watch(mediaFavoritesProvider(type)).maybeWhen(
            data: (items) => items.length,
            orElse: () => 0,
          );

  void _openFavorites(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const FavoritesPage()),
    );
  }
}

/// 一个收藏聚合 tile 的数据。
class _FavTile {
  const _FavTile({
    required this.type,
    required this.label,
    required this.icon,
    required this.count,
  });

  final MediaType type;
  final String label;
  final IconData icon;
  final int count;
}

/// 设计稿 `.toggle-tile`：图标方块 + 标题/计数 + chevron 的可点击卡片。
class _FavTileCard extends StatefulWidget {
  const _FavTileCard({required this.tile, required this.onTap});

  final _FavTile tile;
  final VoidCallback onTap;

  @override
  State<_FavTileCard> createState() => _FavTileCardState();
}

class _FavTileCardState extends State<_FavTileCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final tile = widget.tile;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: DesignTokens.ease,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            color: _hovering ? t.cardBgHover : t.insetBg,
            borderRadius: BorderRadius.circular(DesignTokens.radius),
            border: Border.all(
              color: _hovering ? t.cardBorder : t.hairline,
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: t.chipBgActive,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(tile.icon, size: 16, color: t.accentBright),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tile.label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: t.text0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${tile.count} 项',
                      style: TextStyle(fontSize: 12, color: t.text2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 18, color: t.text3),
            ],
          ),
        ),
      ),
    );
  }
}
