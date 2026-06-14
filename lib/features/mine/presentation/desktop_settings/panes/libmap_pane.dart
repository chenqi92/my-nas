import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/media_library_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';

/// 桌面「设置 · 媒体库映射」详情 pane。
///
/// 对齐设计稿 `settings.jsx` 的 `PaneLibMap`：把源里的目录标记为
/// 视频 / 音乐 / 照片 / 漫画 / 图书 库（SRC-30）。每行展示目录路径（mono）+
/// 所属源 + 库类型标签，并内联「启用」开关（[MediaLibraryConfigNotifier.togglePath]，
/// 仅切换 isEnabled、无数据删除副作用）。库类型切换 / 取消映射涉及跨库移动 +
/// 级联删除已索引数据 + 重扫描（[MediaLibraryConfigNotifier.removePath]），副作用
/// 复杂，仍打开现有 [MediaLibraryPage] 完成；外壳负责滚动与 padding + maxWidth 居中。
class LibMapPane extends ConsumerWidget {
  const LibMapPane({super.key});

  /// 设计稿在「目录 → 库」中只暴露 5 类媒体库（不含笔记）。
  static const List<MediaType> _libTypes = [
    MediaType.video,
    MediaType.music,
    MediaType.photo,
    MediaType.comic,
    MediaType.book,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(mediaLibraryConfigProvider);
    final sources = ref.watch(sourcesProvider).valueOrNull ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetHead(
          icon: Icons.folder_outlined,
          title: '媒体库映射',
          subtitle:
              '把源里的目录标记为 视频 / 音乐 / 照片 / 漫画 / 图书 库（SRC-30）。映射后供扫描、搜索与播放使用。',
          actions: [
            AppButton(
              label: '管理映射',
              icon: Icons.add_rounded,
              onPressed: () => _openManager(context),
            ),
          ],
        ),
        ...configAsync.when(
          loading: () => const [
            SetSection(
              title: '目录 → 库',
              bottomMargin: false,
              children: [
                SetRow(title: '加载中…', last: true),
              ],
            ),
          ],
          error: (e, _) => [
            SetSection(
              title: '目录 → 库',
              bottomMargin: false,
              children: [
                SetRow(
                  title: '加载失败',
                  desc: '$e',
                  last: true,
                ),
              ],
            ),
          ],
          data: (config) => _buildSections(context, config, sources),
        ),
      ],
    );
  }

  List<Widget> _buildSections(
    BuildContext context,
    MediaLibraryConfig config,
    List<SourceEntity> sources,
  ) {
    // 汇总全部库类型下的目录映射，按类型顺序拼成单一列表。
    final rows = <_LibMapEntry>[
      for (final type in _libTypes)
        for (final p in config.getPathsForType(type))
          _LibMapEntry(type: type, path: p),
    ];

    final sourceName = {for (final s in sources) s.id: s.displayName};

    return [
      SetSection(
        title: '目录 → 库',
        hint: rows.isEmpty ? '暂无映射' : '${rows.length} 条映射',
        children: rows.isEmpty
            ? [
                SetRow(
                  title: '尚未配置目录映射',
                  desc: '点击「管理映射」选择源里的目录并标记为对应库',
                  last: true,
                  trailing: AppButton(
                    label: '去配置',
                    icon: Icons.arrow_forward_rounded,
                    variant: AppButtonVariant.ghost,
                    onPressed: () => _openManager(context),
                  ),
                ),
              ]
            : [
                for (var i = 0; i < rows.length; i++)
                  _MapRow(
                    entry: rows[i],
                    sourceName: sourceName[rows[i].path.sourceId],
                    last: i == rows.length - 1,
                    onEdit: () => _openManager(context),
                  ),
              ],
      ),
      // 设计稿 <Note>：删除源时级联删除其全部目录映射与已索引媒体。
      const SetSection(
        bottomMargin: false,
        children: [
          SetRow(
            title: '级联删除',
            desc:
                '删除某个源时，其全部目录映射与已索引媒体会一并删除（数据来源链：源 → 映射 → 扫描 → 库）。',
            last: true,
          ),
        ],
      ),
    ];
  }

  void _openManager(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MediaLibraryPage()),
    );
  }
}

/// 一条「目录 → 库」映射（库类型 + 目录条目）。
class _LibMapEntry {
  const _LibMapEntry({required this.type, required this.path});
  final MediaType type;
  final MediaLibraryPath path;
}

/// 单行映射：folder 图标 + 目录路径（mono）+ 源名 + 库类型标签 + 内联启用开关。
///
/// 「启用」开关内联接通 [MediaLibraryConfigNotifier.togglePath]（仅切换
/// isEnabled，不删除任何已索引数据）。库类型切换 / 取消映射的破坏性副作用
/// 仍走「编辑映射」按钮打开 [MediaLibraryPage]。
class _MapRow extends ConsumerWidget {
  const _MapRow({
    required this.entry,
    required this.sourceName,
    required this.last,
    required this.onEdit,
  });

  final _LibMapEntry entry;
  final String? sourceName;
  final bool last;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final src = sourceName ?? '未知源';
    return SetRow(
      last: last,
      leading: Icon(Icons.folder_outlined, size: 17, color: t.text3),
      title: entry.path.path,
      desc: entry.path.isEnabled ? src : '$src · 已停用',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTag(
            entry.type.displayName,
            icon: _typeIcon(entry.type),
            variant: TagVariant.accent,
          ),
          const SizedBox(width: 12),
          AppSwitch(
            value: entry.path.isEnabled,
            onChanged: (v) => ref
                .read(mediaLibraryConfigProvider.notifier)
                .togglePath(entry.type, entry.path.id, enabled: v),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: onEdit,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: Icon(Icons.tune_rounded, size: 16, color: t.text2),
            tooltip: '切换库类型 / 取消映射',
          ),
        ],
      ),
    );
  }

  IconData _typeIcon(MediaType type) => switch (type) {
        MediaType.video => Icons.movie_outlined,
        MediaType.music => Icons.music_note_rounded,
        MediaType.photo => Icons.photo_outlined,
        MediaType.comic => Icons.auto_stories_outlined,
        MediaType.book => Icons.menu_book_outlined,
        MediaType.note => Icons.sticky_note_2_outlined,
      };
}
