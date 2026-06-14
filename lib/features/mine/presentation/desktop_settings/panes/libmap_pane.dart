import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/l10n/app_localizations.dart';
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
    final l = AppLocalizations.of(context);
    final configAsync = ref.watch(mediaLibraryConfigProvider);
    final sources = ref.watch(sourcesProvider).valueOrNull ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetHead(
          icon: Icons.folder_outlined,
          title: l.paneLibmapTitle,
          subtitle: l.paneLibmapSubtitle,
          actions: [
            AppButton(
              label: l.paneLibmapManage,
              icon: Icons.add_rounded,
              onPressed: () => _openManager(context),
            ),
          ],
        ),
        ...configAsync.when(
          loading: () => [
            SetSection(
              title: l.paneLibmapSectionDirToLib,
              bottomMargin: false,
              children: [
                SetRow(title: l.paneLibmapLoading, last: true),
              ],
            ),
          ],
          error: (e, _) => [
            SetSection(
              title: l.paneLibmapSectionDirToLib,
              bottomMargin: false,
              children: [
                SetRow(
                  title: l.paneLibmapLoadFailed,
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
    final l = AppLocalizations.of(context);
    // 汇总全部库类型下的目录映射，按类型顺序拼成单一列表。
    final rows = <_LibMapEntry>[
      for (final type in _libTypes)
        for (final p in config.getPathsForType(type))
          _LibMapEntry(type: type, path: p),
    ];

    final sourceName = {for (final s in sources) s.id: s.displayName};

    return [
      SetSection(
        title: l.paneLibmapSectionDirToLib,
        hint: rows.isEmpty
            ? l.paneLibmapNoMappings
            : l.paneLibmapMappingsCount(rows.length),
        children: rows.isEmpty
            ? [
                SetRow(
                  title: l.paneLibmapEmptyTitle,
                  desc: l.paneLibmapEmptyDesc,
                  last: true,
                  trailing: AppButton(
                    label: l.paneLibmapGoConfigure,
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
      SetSection(
        bottomMargin: false,
        children: [
          SetRow(
            title: l.paneLibmapCascadeTitle,
            desc: l.paneLibmapCascadeDesc,
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
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final src = sourceName ?? l.paneLibmapUnknownSource;
    return SetRow(
      last: last,
      leading: Icon(Icons.folder_outlined, size: 17, color: t.text3),
      title: entry.path.path,
      desc: entry.path.isEnabled ? src : l.paneLibmapSourceDisabled(src),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 库类型内联切换（设计稿期望就地改类型）。切换会清除原库已索引数据，
          // 故经确认弹窗后再执行。
          PopupMenuButton<MediaType>(
            tooltip: l.libmapEditTypeTooltip,
            position: PopupMenuPosition.under,
            onSelected: (newType) {
              if (newType == entry.type) return;
              _confirmChangeType(context, ref, newType);
            },
            itemBuilder: (_) => [
              for (final type in LibMapPane._libTypes)
                PopupMenuItem<MediaType>(
                  value: type,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_typeIcon(type), size: 16, color: t.text2),
                      const SizedBox(width: 8),
                      Text(type.displayName),
                      if (type == entry.type) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.check_rounded, size: 15, color: t.accent),
                      ],
                    ],
                  ),
                ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTag(
                  entry.type.displayName,
                  icon: _typeIcon(entry.type),
                  variant: TagVariant.accent,
                ),
                Icon(Icons.arrow_drop_down_rounded, size: 18, color: t.text3),
              ],
            ),
          ),
          const SizedBox(width: 8),
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
            tooltip: l.paneLibmapEditTooltip,
          ),
        ],
      ),
    );
  }

  /// 切换库类型：确认后清除原库已索引数据（[MediaLibraryConfigNotifier.removePath]
  /// 会级联删除）并把该目录加入新库，提示用户重新扫描。
  Future<void> _confirmChangeType(
    BuildContext context,
    WidgetRef ref,
    MediaType newType,
  ) async {
    final l = AppLocalizations.of(context);
    final from = entry.type.displayName;
    final to = newType.displayName;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.libmapEditConfirmTitle),
        content: Text(l.libmapEditConfirmBody(entry.path.path, from, to)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.libmapEditCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.libmapEditConfirmOk),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final notifier = ref.read(mediaLibraryConfigProvider.notifier);
    await notifier.removePath(entry.type, entry.path.id);
    await notifier.addPath(
      newType,
      MediaLibraryPath(
        sourceId: entry.path.sourceId,
        path: entry.path.path,
        name: entry.path.name,
      ),
    );
    if (context.mounted) context.showSuccessToast(l.libmapEditChanged(to));
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
