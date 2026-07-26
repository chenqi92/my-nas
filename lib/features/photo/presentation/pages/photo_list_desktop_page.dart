import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/router/app_router.dart' show rootNavigatorKey;
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/photo/data/services/face_database_service.dart';
import 'package:my_nas/features/photo/data/services/photo_database_service.dart';
import 'package:my_nas/features/photo/domain/entities/photo_item.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_duplicates_page.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_list_page.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_people_page.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_viewer_page.dart';
import 'package:my_nas/features/photo/presentation/providers/photo_favorites_provider.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_page_scaffold.dart';
import 'package:my_nas/shared/widgets/stream_image.dart';

/// 已聚类的人物列表（人脸库）。无数据/未聚类时为空。
final _desktopPersonsProvider = FutureProvider<List<PersonEntity>>(
  (ref) => FaceDatabaseService().getAllPersons(),
);

/// 桌面端「照片」——接 photoListProvider 真实数据，时间线响应式网格。
class PhotoListDesktopPage extends ConsumerStatefulWidget {
  const PhotoListDesktopPage({super.key});

  @override
  ConsumerState<PhotoListDesktopPage> createState() =>
      _PhotoListDesktopPageState();
}

class _PhotoListDesktopPageState extends ConsumerState<PhotoListDesktopPage> {
  String _view = 'timeline';
  final _searchController = TextEditingController();

  /// 相册视图中钻取的文件夹路径；null 表示展示文件夹一览。
  String? _albumFolder;

  @override
  void dispose() {
    _searchController.dispose();
    ref.read(photoListProvider.notifier).setSearchQuery('');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    final state = ref.watch(photoListProvider);
    final subtitle = state is PhotoListLoaded
        ? l.photoPagePhotoCount(state.totalCount)
        : l.photoPageSubtitleFeatures;
    final hasPhotos = state is PhotoListLoaded && state.allPhotos.isNotEmpty;
    // 人物来自真实人脸库聚类；未聚类/无结果时不展示该行，不再伪造「未识别」头像。
    final persons =
        ref.watch(_desktopPersonsProvider).valueOrNull ??
        const <PersonEntity>[];
    final sourceFilter = state is PhotoListLoaded
        ? state.sourceFilter
        : PhotoSourceFilter.all;
    if (state is PhotoListLoaded &&
        _searchController.text != state.searchQuery) {
      _searchController.value = TextEditingValue(
        text: state.searchQuery,
        selection: TextSelection.collapsed(offset: state.searchQuery.length),
      );
    }

    return DesktopPageScaffold(
      title: l.photoPageTitle,
      subtitle: subtitle,
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 190,
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l.photoListSearchPhotos,
                prefixIcon: const Icon(Icons.search_rounded, size: 17),
                suffixIcon:
                    state is PhotoListLoaded && state.searchQuery.isNotEmpty
                    ? IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).deleteButtonTooltip,
                        onPressed: () {
                          _searchController.clear();
                          ref
                              .read(photoListProvider.notifier)
                              .setSearchQuery('');
                        },
                        icon: const Icon(Icons.close_rounded, size: 16),
                      )
                    : null,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) =>
                  ref.read(photoListProvider.notifier).setSearchQuery(value),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute<void>(
                builder: (_) => desktopPhotoFullManagerPage(),
              ),
            ),
            icon: const Icon(Icons.manage_search_rounded, size: 16),
            label: Text(l.paneAdvancedManageButton),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: l.maintPhotoTitle,
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const PhotoDuplicatesPage()),
            ),
          ),
          const SizedBox(width: 4),
          if (hasPhotos)
            _SourceFilterButton(
              value: sourceFilter,
              onChanged: (f) =>
                  ref.read(photoListProvider.notifier).setSourceFilter(f),
            ),
          const SizedBox(width: 10),
          AppSegmented<String>(
            value: _view,
            onChanged: (v) => setState(() {
              _view = v;
              _albumFolder = null;
            }),
            dense: true,
            options: [
              AppSegmentedOption(
                value: 'timeline',
                label: l.photoPageTabTimeline,
              ),
              AppSegmentedOption(value: 'albums', label: l.photoPageTabAlbums),
            ],
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPhotos && _view == 'timeline' && persons.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  l.photoPagePeopleTitle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: t.text0,
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  l.photoPagePeopleSubtitle(persons.length),
                  style: TextStyle(fontSize: 12, color: t.text2),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => _openPeople(context),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Text(
                      l.photoPageAllPeople,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: t.accentBright,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: persons.length,
                separatorBuilder: (_, _) => const SizedBox(width: 18),
                itemBuilder: (_, i) {
                  final p = persons[i];
                  return InkWell(
                    onTap: () => _openPerson(context, p),
                    child: SizedBox(
                      width: 84,
                      child: Column(
                        children: [
                          Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: t.insetBg,
                              border: Border.all(color: t.hairline),
                            ),
                            child: Icon(
                              Icons.person_rounded,
                              size: 36,
                              color: t.text2,
                            ),
                          ),
                          const SizedBox(height: 9),
                          Text(
                            p.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: t.text1,
                            ),
                          ),
                          Text(
                            l.photoPagePersonPhotoCount(p.photoCount),
                            style: TextStyle(fontSize: 11, color: t.text2),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_view == 'albums')
            if (_albumFolder != null)
              _AlbumDetail(
                state: state,
                ref: ref,
                folder: _albumFolder!,
                onBack: () => setState(() => _albumFolder = null),
              )
            else
              _AlbumGrid(
                state: state,
                ref: ref,
                onOpen: (folder) => setState(() => _albumFolder = folder),
              )
          else
            _PhotoBody(state: state, ref: ref),
        ],
      ),
    );
  }

  void _openPeople(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PhotoPeoplePage()));
  }

  void _openPerson(BuildContext context, PersonEntity person) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoPeoplePage(initialPerson: person),
      ),
    );
  }
}

/// 来源筛选枚举的本地化展示文案（避免把通用词「全部」放进全局 form 映射）。
String _localizedSourceFilter(AppLocalizations l, PhotoSourceFilter f) =>
    switch (f) {
      PhotoSourceFilter.all => l.photoSourceFilterAll,
      PhotoSourceFilter.local => l.photoSourceFilterLocal,
      PhotoSourceFilter.remote => l.photoSourceFilterRemote,
    };

/// 来源筛选（全部 / 本机 / NAS）紧凑下拉。
class _SourceFilterButton extends StatelessWidget {
  const _SourceFilterButton({required this.value, required this.onChanged});
  final PhotoSourceFilter value;
  final ValueChanged<PhotoSourceFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    return PopupMenuButton<PhotoSourceFilter>(
      tooltip: l.photoPageSourceFilterTooltip,
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final f in PhotoSourceFilter.values)
          PopupMenuItem(value: f, child: Text(_localizedSourceFilter(l, f))),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: t.chipBg,
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list_rounded, size: 14, color: t.text2),
            const SizedBox(width: 6),
            Text(
              _localizedSourceFilter(l, value),
              style: TextStyle(fontSize: 12.5, color: t.text1),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoBody extends StatelessWidget {
  const _PhotoBody({required this.state, required this.ref});
  final PhotoListState state;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (state is PhotoListLoading) {
      return const SizedBox(
        height: 320,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state is! PhotoListLoaded) {
      return DesktopComingSoon(
        icon: Icons.photo_library_outlined,
        message: l.photoPageNoLibraryHint,
      );
    }
    // 用 displayPhotos 让来源/时间筛选生效（而非恒取 allPhotos）。
    final photos = (state as PhotoListLoaded).displayPhotos;
    if (photos.isEmpty) {
      return DesktopComingSoon(
        icon: Icons.photo_library_outlined,
        message: l.photoPageNoFilteredPhotos,
      );
    }
    final connections = ref.watch(activeConnectionsProvider);

    // 按年月分组，对齐设计稿的时间线标签（"2024 年 6 月 · X 张"）。
    // 无有效拍摄/修改时间的照片（dateKey 退化到 1970）单独归「未知日期」，
    // 不再错误地堆到「1970 年 1 月」。
    const unknownKey = '未知';
    final groups = <String, List<PhotoEntity>>{};
    for (final p in photos) {
      final d = p.dateKey;
      final key = d.year <= 1970
          ? unknownKey
          : '${d.year}-${d.month.toString().padLeft(2, '0')}';
      groups.putIfAbsent(key, () => []).add(p);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        if (a == b) return 0;
        if (a == unknownKey) return 1; // 未知日期排最后
        if (b == unknownKey) return -1;
        return b.compareTo(a); // 新→旧
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final key in keys) ...[
          const SizedBox(height: 24),
          _TimelineLabel(monthKey: key, count: groups[key]!.length),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 130,
              crossAxisSpacing: 5,
              mainAxisSpacing: 5,
            ),
            itemCount: groups[key]!.length,
            itemBuilder: (_, i) {
              final p = groups[key]![i];
              final fs = connections[p.sourceId]?.adapter.fileSystem;
              return _PhotoTile(
                photo: p,
                fileSystem: fs,
                onTap: () => _openDesktopFullPhotoViewer(
                  context,
                  ref,
                  photos: photos,
                  initialIndex: photos.indexOf(p),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

/// 取文件路径的父目录（相册/文件夹分组键）。
String _folderPathOf(String filePath) {
  final i = filePath.lastIndexOf('/');
  return i > 0 ? filePath.substring(0, i) : '/';
}

/// 文件夹展示名：取末段路径；根目录用本地化文案。
String _folderLabel(BuildContext context, String folderPath) {
  if (folderPath == '/' || folderPath.isEmpty) {
    return AppLocalizations.of(context).photoPageAlbumRoot;
  }
  final i = folderPath.lastIndexOf('/');
  return i >= 0 ? folderPath.substring(i + 1) : folderPath;
}

/// 相册（文件夹）一览：把 displayPhotos 按父目录分组成文件夹卡片。
class _AlbumGrid extends StatelessWidget {
  const _AlbumGrid({
    required this.state,
    required this.ref,
    required this.onOpen,
  });
  final PhotoListState state;
  final WidgetRef ref;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (state is! PhotoListLoaded) {
      return DesktopComingSoon(
        icon: Icons.photo_library_outlined,
        message: l.photoPageNoLibraryHint,
      );
    }
    final photos = (state as PhotoListLoaded).displayPhotos;
    if (photos.isEmpty) {
      return DesktopComingSoon(
        icon: Icons.photo_library_outlined,
        message: l.photoPageNoFilteredPhotos,
      );
    }
    final connections = ref.watch(activeConnectionsProvider);
    final groups = <String, List<PhotoEntity>>{};
    for (final p in photos) {
      groups.putIfAbsent(_folderPathOf(p.filePath), () => []).add(p);
    }
    final folders = groups.keys.toList()..sort();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.82,
      ),
      itemCount: folders.length,
      itemBuilder: (_, i) {
        final folder = folders[i];
        final items = groups[folder]!;
        final cover = items.first;
        final fs = connections[cover.sourceId]?.adapter.fileSystem;
        return _AlbumCard(
          folder: folder,
          cover: cover,
          fileSystem: fs,
          count: items.length,
          onTap: () => onOpen(folder),
        );
      },
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({
    required this.folder,
    required this.cover,
    required this.fileSystem,
    required this.count,
    required this.onTap,
  });
  final String folder;
  final PhotoEntity cover;
  final NasFileSystem? fileSystem;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    final placeholder = ColoredBox(
      color: t.insetBg,
      child: Icon(Icons.folder_rounded, size: 28, color: t.text3),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: StreamImage(
                  url: cover.thumbnailUrl,
                  path: cover.filePath,
                  fileSystem: fileSystem,
                  placeholder: placeholder,
                  errorWidget: placeholder,
                  cacheKey: cover.uniqueKey,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _folderLabel(context, folder),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: t.text0,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l.photoPagePhotoCount(count),
              style: TextStyle(fontSize: 11.5, color: t.text2),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个文件夹内的照片网格（从相册一览钻取进来）。
class _AlbumDetail extends StatelessWidget {
  const _AlbumDetail({
    required this.state,
    required this.ref,
    required this.folder,
    required this.onBack,
  });
  final PhotoListState state;
  final WidgetRef ref;
  final String folder;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    final photos = state is PhotoListLoaded
        ? (state as PhotoListLoaded).displayPhotos
              .where((p) => _folderPathOf(p.filePath) == folder)
              .toList()
        : const <PhotoEntity>[];
    final connections = ref.watch(activeConnectionsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              onPressed: onBack,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                _folderLabel(context, folder),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: t.text0,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Text(
              l.photoPagePhotoCount(photos.length),
              style: TextStyle(fontSize: 12, color: t.text2),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 130,
            crossAxisSpacing: 5,
            mainAxisSpacing: 5,
          ),
          itemCount: photos.length,
          itemBuilder: (_, i) {
            final p = photos[i];
            final fs = connections[p.sourceId]?.adapter.fileSystem;
            return _PhotoTile(
              photo: p,
              fileSystem: fs,
              onTap: () => _openDesktopFullPhotoViewer(
                context,
                ref,
                photos: photos,
                initialIndex: i,
              ),
            );
          },
        ),
      ],
    );
  }
}

/// 搜索、多选与批量上传/下载/删除的完整管理目标。
@visibleForTesting
PhotoListPage desktopPhotoFullManagerPage() => const PhotoListPage();

/// 把桌面时间线的数据库实体投影为完整查看器数据。
@visibleForTesting
List<PhotoItem> desktopPhotoViewerItems(List<PhotoEntity> photos) => [
  for (final photo in photos)
    PhotoItem(
      name: photo.fileName,
      path: photo.filePath,
      url: '',
      sourceId: photo.sourceId,
      thumbnailUrl: photo.thumbnailUrl,
      size: photo.size,
      modifiedAt: photo.modifiedTime,
    ),
];

Future<void> _openDesktopFullPhotoViewer(
  BuildContext context,
  WidgetRef ref, {
  required List<PhotoEntity> photos,
  required int initialIndex,
}) async {
  final connections = ref.read(activeConnectionsProvider);
  final navigator = rootNavigatorKey.currentState;
  if (navigator == null) return;
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => PhotoViewerPage(
        photos: desktopPhotoViewerItems(photos),
        initialIndex: initialIndex,
        getPhotoUrl: (path, sourceId) async {
          final fileSystem = connections[sourceId]?.adapter.fileSystem;
          if (fileSystem == null) return null;
          try {
            return await fileSystem.getFileUrl(path);
          } on Object {
            return null;
          }
        },
        getFileSystem: (sourceId) => connections[sourceId]?.adapter.fileSystem,
        onPhotoDeleted: (_) {
          ref.read(photoListProvider.notifier).forceRefresh();
          ref.invalidate(photoFavoritesProvider);
        },
      ),
    ),
  );
}

class _TimelineLabel extends StatelessWidget {
  const _TimelineLabel({required this.monthKey, required this.count});
  final String monthKey;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    final String label;
    if (monthKey == '未知') {
      label = l.photoPageUnknownDate;
    } else {
      final parts = monthKey.split('-');
      label = l.photoPageYearMonth(int.parse(parts[0]), int.parse(parts[1]));
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: t.text0,
            ),
          ),
          TextSpan(
            text: l.photoPageTimelineCount(count),
            style: TextStyle(fontSize: 12.5, color: t.text2),
          ),
        ],
      ),
    );
  }
}

class _PhotoTile extends ConsumerStatefulWidget {
  const _PhotoTile({
    required this.photo,
    required this.fileSystem,
    required this.onTap,
  });
  final PhotoEntity photo;
  final NasFileSystem? fileSystem;
  final VoidCallback onTap;

  @override
  ConsumerState<_PhotoTile> createState() => _PhotoTileState();
}

class _PhotoTileState extends ConsumerState<_PhotoTile> {
  bool _hover = false;

  PhotoItem _toPhotoItem() => PhotoItem(
    name: widget.photo.fileName,
    path: widget.photo.filePath,
    url: '',
    sourceId: widget.photo.sourceId,
    thumbnailUrl: widget.photo.thumbnailUrl,
    size: widget.photo.size,
    modifiedAt: widget.photo.modifiedTime,
  );

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final favKey = photoFavoriteKey(
      widget.photo.sourceId,
      widget.photo.filePath,
    );
    final isFav = ref.watch(
      photoFavoritesProvider.select((favs) => favs.contains(favKey)),
    );
    final placeholder = ColoredBox(
      color: t.insetBg,
      child: Icon(Icons.photo_rounded, size: 20, color: t.text3),
    );
    final tile = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          StreamImage(
            url: widget.photo.thumbnailUrl,
            path: widget.photo.filePath,
            fileSystem: widget.fileSystem,
            placeholder: placeholder,
            errorWidget: placeholder,
            cacheKey: widget.photo.uniqueKey,
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(onTap: widget.onTap),
          ),
          // 收藏角标：对齐设计稿 .photo-cell .fav（右上 6px 白色心形 + drop-shadow）。
          // 已收藏始终显示实心；未收藏仅在 hover 时显示半透明描边心形。
          if (isFav || _hover)
            Positioned(
              top: 6,
              right: 6,
              child: _FavBadge(
                isFavorite: isFav,
                onTap: () => ref
                    .read(photoFavoritesProvider.notifier)
                    .toggle(_toPhotoItem()),
              ),
            ),
        ],
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: _hover
                ? const [
                    BoxShadow(
                      color: Color(0xCC000000),
                      blurRadius: 24,
                      spreadRadius: -8,
                      offset: Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: tile,
        ),
      ),
    );
  }
}

/// 照片网格右上角的收藏角标。点击切换收藏，且不冒泡触发打开大图。
class _FavBadge extends StatelessWidget {
  const _FavBadge({required this.isFavorite, required this.onTap});
  final bool isFavorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: 15,
          // 已收藏纯白实心；未收藏（hover 态）用半透明白描边。
          color: isFavorite
              ? Colors.white
              : Colors.white.withValues(alpha: 0.85),
          // 对齐设计稿 .fav 的 drop-shadow(0 1px 3px rgba(0,0,0,.6))。
          shadows: const [
            Shadow(
              color: Color(0x99000000),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
    ),
  );
}
