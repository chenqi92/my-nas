import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/router/app_router.dart' show rootNavigatorKey;
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/book/data/services/book_database_service.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/features/book/presentation/pages/book_list_page.dart';
import 'package:my_nas/features/book/presentation/utils/book_navigator.dart';
import 'package:my_nas/features/comic/presentation/pages/comic_list_page.dart';
import 'package:my_nas/features/comic/presentation/pages/comic_reader_page.dart';
import 'package:my_nas/features/note/presentation/pages/note_list_page.dart';
import 'package:my_nas/features/note/presentation/widgets/note_tree_widget.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_page_scaffold.dart';
import 'package:my_nas/shared/widgets/stream_image.dart';

/// 桌面端「阅读」——聚合漫画 / 图书 / 笔记三库真实数据。
class ReadingDesktopPage extends ConsumerStatefulWidget {
  const ReadingDesktopPage({super.key});

  @override
  ConsumerState<ReadingDesktopPage> createState() =>
      _ReadingDesktopPageState();
}

class _ReadingDesktopPageState extends ConsumerState<ReadingDesktopPage> {
  String _tab = '全部';

  static const _tabs = ['全部', '漫画', '图书', '笔记'];

  @override
  Widget build(BuildContext context) {
    final comicState = ref.watch(comicListProvider);
    final bookState = ref.watch(bookListProvider);
    final noteState = ref.watch(notePageProvider);

    final comics =
        comicState is ComicListLoaded ? comicState.comics : const <ComicItem>[];
    final books =
        bookState is BookListLoaded ? bookState.allBooks : const <BookEntity>[];
    final notes = noteState is NotePageLoaded
        ? noteState.treeNodes
        : const <NoteTreeNode>[];

    final showComics = _tab == '全部' || _tab == '漫画';
    final showBooks = _tab == '全部' || _tab == '图书';
    final showNotes = _tab == '全部' || _tab == '笔记';

    return DesktopPageScaffold(
      title: '阅读',
      subtitle: '漫画 ${comics.length} · 图书 ${books.length} · '
          '笔记 ${notes.length} — 统一阅读进度（共享书签）',
      actions: Row(
        children: [
          for (final tab in _tabs)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: AppChip(
                label: tab,
                active: tab == _tab,
                compact: true,
                onTap: () => setState(() => _tab = tab),
              ),
            ),
          const SizedBox(width: 12),
          const AppChip(
            label: '在线书源',
            icon: Icons.language_rounded,
            compact: true,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showComics && comics.isNotEmpty) ...[
            if (_tab == '全部') const _SectionHeader('漫画'),
            _ComicShelf(comics: comics, ref: ref, onOpen: _openComic),
            const SizedBox(height: 22),
          ],
          if (showBooks && books.isNotEmpty) ...[
            if (_tab == '全部') const _SectionHeader('图书'),
            _BookShelf(books: books, onOpen: _openBook),
            const SizedBox(height: 22),
          ],
          if (showNotes && notes.isNotEmpty) ...[
            if (_tab == '全部') const _SectionHeader('笔记'),
            _NoteList(nodes: notes),
          ],
          if (_isEmpty(showComics, comics, showBooks, books, showNotes, notes))
            DesktopComingSoon(
              icon: switch (_tab) {
                '笔记' => Icons.edit_note_rounded,
                '漫画' => Icons.collections_bookmark_outlined,
                '图书' => Icons.menu_book_outlined,
                _ => Icons.auto_stories_outlined,
              },
              message: switch (_tab) {
                '笔记' => '映射「笔记」目录后，此处显示 Markdown 笔记树。',
                '漫画' => '映射「漫画」媒体库后，此处显示漫画书架（封面 + 页数）。',
                '图书' => '映射「图书」媒体库后，此处显示图书书架 + EPUB / PDF / TXT。',
                _ => '聚合视图：漫画 + 图书 + 笔记 一并展示。先到「数据源」映射对应媒体库。',
              },
            ),
        ],
      ),
    );
  }

  bool _isEmpty(
    bool showComics,
    List<ComicItem> comics,
    bool showBooks,
    List<BookEntity> books,
    bool showNotes,
    List<NoteTreeNode> notes,
  ) {
    final c = showComics && comics.isNotEmpty;
    final b = showBooks && books.isNotEmpty;
    final n = showNotes && notes.isNotEmpty;
    return !c && !b && !n;
  }

  Future<void> _openBook(BookEntity book) async {
    final connection = ref.read(activeConnectionsProvider)[book.sourceId];
    if (connection == null) return;
    final file = FileItem(
      name: book.fileName,
      path: book.filePath,
      size: book.size,
      isDirectory: false,
      modifiedTime: book.modifiedTime,
    );
    final url = await connection.adapter.fileSystem.getFileUrl(file.path);
    await BookDatabaseService().updateLastReadTime(book.sourceId, book.filePath);
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    await BookNavigator.instance.openBook(
      ctx,
      BookItem.fromFileItem(file, url, sourceId: book.sourceId),
    );
  }

  void _openComic(ComicItem comic) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    Navigator.of(ctx).push(
      MaterialPageRoute<void>(builder: (_) => ComicReaderPage(comic: comic)),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: t.text0,
        ),
      ),
    );
  }
}

class _ComicShelf extends StatelessWidget {
  const _ComicShelf({
    required this.comics,
    required this.ref,
    required this.onOpen,
  });
  final List<ComicItem> comics;
  final WidgetRef ref;
  final ValueChanged<ComicItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final connections = ref.watch(activeConnectionsProvider);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: 0.62,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: comics.length,
      itemBuilder: (_, i) {
        final c = comics[i];
        final fs = connections[c.sourceId]?.adapter.fileSystem;
        return _Cover(
          title: c.folderName,
          subtitle: '${c.pageCount} 页',
          streamPath: c.coverPath,
          fileSystem: fs,
          cacheKey: '${c.sourceId}_${c.coverPath}',
          onTap: () => onOpen(c),
        );
      },
    );
  }
}

class _BookShelf extends StatelessWidget {
  const _BookShelf({required this.books, required this.onOpen});
  final List<BookEntity> books;
  final ValueChanged<BookEntity> onOpen;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: 0.62,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: books.length,
      itemBuilder: (_, i) {
        final b = books[i];
        return _Cover(
          title: b.displayName,
          subtitle: b.displayAuthor,
          localPath: b.coverPath,
          badge: b.format.name.toUpperCase(),
          onTap: () => onOpen(b),
        );
      },
    );
  }
}

class _NoteList extends StatelessWidget {
  const _NoteList({required this.nodes});
  final List<NoteTreeNode> nodes;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        children: [
          for (final node in nodes)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              child: Row(
                children: [
                  Icon(
                    node.type == NoteTreeNodeType.folder
                        ? Icons.folder_outlined
                        : node.isTaskFile
                            ? Icons.checklist_rounded
                            : Icons.description_outlined,
                    size: 17,
                    color: node.type == NoteTreeNodeType.folder
                        ? t.accentBright
                        : t.text2,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      node.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: t.text0,
                      ),
                    ),
                  ),
                  if (node.type == NoteTreeNodeType.folder)
                    Text(
                      '${node.children.length} 项',
                      style: TextStyle(fontSize: 11.5, color: t.text3),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({
    required this.title,
    required this.subtitle,
    this.localPath,
    this.streamPath,
    this.fileSystem,
    this.cacheKey,
    this.badge,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String? localPath;
  final String? streamPath;
  final NasFileSystem? fileSystem;
  final String? cacheKey;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final placeholder = ColoredBox(
      color: t.insetBg,
      child: Icon(Icons.menu_book_outlined, size: 22, color: t.text3),
    );
    Widget cover;
    if (localPath != null &&
        localPath!.isNotEmpty &&
        File(localPath!).existsSync()) {
      cover = Image.file(
        File(localPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      );
    } else if (streamPath != null && streamPath!.isNotEmpty) {
      cover = StreamImage(
        path: streamPath,
        fileSystem: fileSystem,
        placeholder: placeholder,
        errorWidget: placeholder,
        cacheKey: cacheKey,
      );
    } else {
      cover = placeholder;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                cover,
                if (badge != null)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: AppTag(badge!, variant: TagVariant.neutral),
                  ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(onTap: onTap),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: t.text0,
          ),
        ),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: t.text2),
        ),
      ],
    );
  }
}
