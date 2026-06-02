import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/photo/data/services/photo_database_service.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_list_page.dart';
import 'package:my_nas/features/photo/presentation/widgets/desktop_photo_viewer.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_page_scaffold.dart';
import 'package:my_nas/shared/widgets/stream_image.dart';

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
        ? '${state.totalCount} 张 · ${state.dateGroups.length} 个时间分组'
        : '人脸识别 · EXIF · 重复检测 · 自动增量扫描';

    return DesktopPageScaffold(
      title: '照片',
      subtitle: subtitle,
      actions: AppSegmented<String>(
        value: _view,
        onChanged: (v) => setState(() => _view = v),
        dense: true,
        options: const [
          AppSegmentedOption(value: 'timeline', label: '时间线'),
          AppSegmentedOption(value: 'albums', label: '相册'),
          AppSegmentedOption(value: 'map', label: '地图'),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                '人脸聚类 · 128 维特征',
                style: TextStyle(fontSize: 12, color: t.text2),
              ),
              if (_view == 'map') ...[
                const Spacer(),
                const AppTag('即将推出', variant: TagVariant.plan),
              ],
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 8,
              separatorBuilder: (_, _) => const SizedBox(width: 18),
              itemBuilder: (_, _) => Column(
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: t.insetBg,
                      border: Border.all(color: t.hairline),
                    ),
                    child: Icon(Icons.person_outline_rounded,
                        size: 36, color: t.text3),
                  ),
                  const SizedBox(height: 8),
                  Text('未识别', style: TextStyle(fontSize: 11.5, color: t.text3)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          if (_view == 'map')
            const DesktopComingSoon(
              icon: Icons.map_outlined,
              message: '按 GPS EXIF 在地图上聚合照片足迹（规划中）。',
            )
          else
            _PhotoBody(state: state, ref: ref),
        ],
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
    final photos = (state as PhotoListLoaded).allPhotos;
    if (photos.isEmpty) {
      return const DesktopComingSoon(
        icon: Icons.photo_library_outlined,
        message: '照片库为空，扫描「照片」媒体库后会出现在这里。',
      );
    }
    final connections = ref.watch(activeConnectionsProvider);
    return GlassPanel(
      padding: const EdgeInsets.all(10),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 150,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: photos.length,
        itemBuilder: (_, i) {
          final p = photos[i];
          final fs = connections[p.sourceId]?.adapter.fileSystem;
          return _PhotoTile(
            photo: p,
            fileSystem: fs,
            onTap: () => showDesktopPhotoViewer(
              context,
              photos: photos,
              initialIndex: i,
            ),
          );
        },
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photo,
    required this.fileSystem,
    required this.onTap,
  });
  final PhotoEntity photo;
  final NasFileSystem? fileSystem;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final placeholder = ColoredBox(
      color: t.insetBg,
      child: Icon(Icons.photo_rounded, size: 20, color: t.text3),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          StreamImage(
            url: photo.thumbnailUrl,
            path: photo.filePath,
            fileSystem: fileSystem,
            placeholder: placeholder,
            errorWidget: placeholder,
            cacheKey: photo.uniqueKey,
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(onTap: onTap),
          ),
        ],
      ),
    );
  }
}
