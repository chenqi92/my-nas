import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/photo/data/services/face_database_service.dart';
import 'package:my_nas/features/photo/data/services/photo_database_service.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_list_page.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_people_page.dart';
import 'package:my_nas/features/photo/presentation/widgets/desktop_photo_viewer.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
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

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final state = ref.watch(photoListProvider);
    final subtitle = state is PhotoListLoaded
        ? '${state.totalCount} 张照片'
        : '人脸识别 · EXIF · 重复检测 · 自动增量扫描';
    final hasPhotos = state is PhotoListLoaded && state.allPhotos.isNotEmpty;
    // 人物来自真实人脸库聚类；未聚类/无结果时不展示该行，不再伪造「未识别」头像。
    final persons = ref.watch(_desktopPersonsProvider).valueOrNull ??
        const <PersonEntity>[];
    final sourceFilter = state is PhotoListLoaded
        ? state.sourceFilter
        : PhotoSourceFilter.all;

    return DesktopPageScaffold(
      title: '照片',
      subtitle: subtitle,
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasPhotos)
            _SourceFilterButton(
              value: sourceFilter,
              onChanged: (f) =>
                  ref.read(photoListProvider.notifier).setSourceFilter(f),
            ),
          const SizedBox(width: 10),
          AppSegmented<String>(
            value: _view,
            onChanged: (v) => setState(() => _view = v),
            dense: true,
            options: const [
              AppSegmentedOption(value: 'timeline', label: '时间线'),
              AppSegmentedOption(value: 'albums', label: '相册'),
              AppSegmentedOption(value: 'map', label: '地图'),
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
                  '人物',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: t.text0,
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  '${persons.length} 人 · 人脸聚类',
                  style: TextStyle(fontSize: 12, color: t.text2),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => _openPeople(context),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    child: Text(
                      '全部人物',
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
                    onTap: () => _openPeople(context),
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
                            child: Icon(Icons.person_rounded,
                                size: 36, color: t.text2),
                          ),
                          const SizedBox(height: 9),
                          Text(
                            p.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: t.text1),
                          ),
                          Text(
                            '${p.photoCount} 张',
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
          if (_view == 'map')
            const DesktopComingSoon(
              icon: Icons.map_outlined,
              message: '按 GPS EXIF 在地图上聚合照片足迹（规划中）。',
            )
          else if (_view == 'albums')
            const DesktopComingSoon(
              icon: Icons.photo_album_outlined,
              message: '按相册/文件夹分组浏览（规划中）。当前可用「时间线」视图。',
            )
          else
            _PhotoBody(state: state, ref: ref),
        ],
      ),
    );
  }

  void _openPeople(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PhotoPeoplePage()),
    );
  }
}

/// 来源筛选（全部 / 本机 / NAS）紧凑下拉。
class _SourceFilterButton extends StatelessWidget {
  const _SourceFilterButton({required this.value, required this.onChanged});
  final PhotoSourceFilter value;
  final ValueChanged<PhotoSourceFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return PopupMenuButton<PhotoSourceFilter>(
      tooltip: '来源筛选',
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final f in PhotoSourceFilter.values)
          PopupMenuItem(value: f, child: Text(f.label)),
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
            Text(value.label,
                style: TextStyle(fontSize: 12.5, color: t.text1)),
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
    if (state is PhotoListLoading) {
      return const SizedBox(
        height: 320,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state is! PhotoListLoaded) {
      return const DesktopComingSoon(
        icon: Icons.photo_library_outlined,
        message: '映射「照片」媒体库后，此处显示响应式网格 + 时间分组。',
      );
    }
    // 用 displayPhotos 让来源/时间筛选生效（而非恒取 allPhotos）。
    final photos = (state as PhotoListLoaded).displayPhotos;
    if (photos.isEmpty) {
      return const DesktopComingSoon(
        icon: Icons.photo_library_outlined,
        message: '没有符合当前筛选的照片。',
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
                onTap: () => showDesktopPhotoViewer(
                  context,
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

class _TimelineLabel extends StatelessWidget {
  const _TimelineLabel({required this.monthKey, required this.count});
  final String monthKey;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final String label;
    if (monthKey == '未知') {
      label = '未知日期';
    } else {
      final parts = monthKey.split('-');
      label = '${parts[0]} 年 ${int.parse(parts[1])} 月';
    }
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: t.text0,
          ),
        ),
        TextSpan(
          text: '  · $count 张',
          style: TextStyle(fontSize: 12.5, color: t.text2),
        ),
      ]),
    );
  }
}

class _PhotoTile extends StatefulWidget {
  const _PhotoTile({
    required this.photo,
    required this.fileSystem,
    required this.onTap,
  });
  final PhotoEntity photo;
  final NasFileSystem? fileSystem;
  final VoidCallback onTap;

  @override
  State<_PhotoTile> createState() => _PhotoTileState();
}

class _PhotoTileState extends State<_PhotoTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
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
