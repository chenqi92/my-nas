import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/router/app_router.dart' show rootNavigatorKey;
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/book/data/services/book_database_service.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/features/book/presentation/pages/book_list_page.dart';
import 'package:my_nas/features/book/presentation/pages/book_sources_page.dart';
import 'package:my_nas/features/book/presentation/utils/book_navigator.dart';
import 'package:my_nas/features/comic/presentation/pages/comic_list_page.dart';
import 'package:my_nas/features/comic/presentation/pages/comic_reader_page.dart';
import 'package:my_nas/features/note/presentation/pages/note_list_page.dart';
import 'package:my_nas/features/note/presentation/widgets/note_tree_widget.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';
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
    final l = AppLocalizations.of(context);
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
      title: l.readingPageTitle,
      subtitle: l.readingPageSubtitle(
        comics.length,
        books.length,
        notes.length,
      ),
      actions: Row(
        children: [
          for (final tab in _tabs)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: AppChip(
                label: _tabLabel(l, tab),
                active: tab == _tab,
                compact: false,
                onTap: () => setState(() => _tab = tab),
              ),
            ),
          const SizedBox(width: 12),
          AppChip(
            label: l.readingPageOnlineSources,
            icon: Icons.language_rounded,
            compact: false,
            onTap: () => _pushPage(const BookSourcesPage()),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showComics && comics.isNotEmpty) ...[
            if (_tab == '全部') _SectionHeader(l.readingPageSectionComic),
            _ComicShelf(comics: comics, ref: ref, onOpen: _openComic),
            const SizedBox(height: 22),
          ],
          if (showBooks && books.isNotEmpty) ...[
            if (_tab == '全部') _SectionHeader(l.readingPageSectionBook),
            _BookShelf(books: books, onOpen: _openBook),
            const SizedBox(height: 22),
          ],
          if (showNotes && notes.isNotEmpty) ...[
            if (_tab == '全部') _SectionHeader(l.readingPageSectionNote),
            _NoteList(
              nodes: notes,
              onOpen: () => _pushPage(const NoteListPage()),
            ),
          ],
          if (_isEmpty(showComics, comics, showBooks, books, showNotes, notes))
            _emptyOrStatus(comicState, bookState, noteState),
        ],
      ),
    );
  }

  String _tabLabel(AppLocalizations l, String tab) => switch (tab) {
        '漫画' => l.readingPageTabComic,
        '图书' => l.readingPageTabBook,
        '笔记' => l.readingPageTabNote,
        _ => l.readingPageTabAll,
      };

  /// 空内容时区分三态：加载中 → 转圈；出错 → 错误 + 重试；真空 → 引导文案。
  Widget _emptyOrStatus(
    ComicListState comicState,
    BookListState bookState,
    NotePageState noteState,
  ) {
    final l = AppLocalizations.of(context);
    final anyLoading = comicState is ComicListLoading ||
        bookState is BookListLoading ||
        noteState is NotePageLoading;
    final anyError = comicState is ComicListError ||
        bookState is BookListError ||
        noteState is NotePageError;
    if (anyLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (anyError) {
      final t = DesignTokens.of(context);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 38, color: t.err),
              const SizedBox(height: 12),
              Text(l.readingPageLoadPartialFailed,
                  style: TextStyle(fontSize: 13, color: t.text2)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  ref
                    ..invalidate(comicListProvider)
                    ..invalidate(bookListProvider)
                    ..invalidate(notePageProvider);
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(l.readingPageRetry),
              ),
            ],
          ),
        ),
      );
    }
    return DesktopComingSoon(
      icon: switch (_tab) {
        '笔记' => Icons.edit_note_rounded,
        '漫画' => Icons.collections_bookmark_outlined,
        '图书' => Icons.menu_book_outlined,
        _ => Icons.auto_stories_outlined,
      },
      message: switch (_tab) {
        '笔记' => l.readingPageEmptyNote,
        '漫画' => l.readingPageEmptyComic,
        '图书' => l.readingPageEmptyBook,
        _ => l.readingPageEmptyAll,
      },
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
    final l = AppLocalizations.of(context);
    final connection = ref.read(activeConnectionsProvider)[book.sourceId];
    if (connection == null) {
      rootNavigatorKey.currentContext?.showErrorToast(
        l.readingPageSourceNotConnected,
      );
      return;
    }
    try {
      final file = FileItem(
        name: book.fileName,
        path: book.filePath,
        size: book.size,
        isDirectory: false,
        modifiedTime: book.modifiedTime,
      );
      final url = await connection.adapter.fileSystem.getFileUrl(file.path);
      await BookDatabaseService()
          .updateLastReadTime(book.sourceId, book.filePath);
      final ctx = rootNavigatorKey.currentContext;
      if (ctx == null) return;
      await BookNavigator.instance.openBook(
        ctx,
        BookItem.fromFileItem(file, url, sourceId: book.sourceId),
      );
    } on Object catch (e) {
      rootNavigatorKey.currentContext?.showErrorToast(
        l.readingPageOpenBookFailed(e.toString()),
      );
    }
  }

  void _openComic(ComicItem comic) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    Navigator.of(ctx).push(
      MaterialPageRoute<void>(builder: (_) => ComicReaderPage(comic: comic)),
    );
  }

  void _pushPage(Widget page) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 18),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.015 * 20,
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
    final l = AppLocalizations.of(context);
    final connections = ref.watch(activeConnectionsProvider);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.62,
        crossAxisSpacing: 18,
        mainAxisSpacing: 18,
      ),
      itemCount: comics.length,
      itemBuilder: (_, i) {
        final c = comics[i];
        final fs = connections[c.sourceId]?.adapter.fileSystem;
        return _Cover(
          title: c.folderName,
          subtitle: l.readingPageComicPageCount(c.pageCount),
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
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.62,
        crossAxisSpacing: 18,
        mainAxisSpacing: 18,
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
  const _NoteList({required this.nodes, required this.onOpen});
  final List<NoteTreeNode> nodes;

  /// 打开完整笔记页（新建/查看/展开均在此完成）。
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    return GlassPanel(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l.readingPageMarkdownNotes,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: t.text0,
                ),
              ),
              const Spacer(),
              AppChip(
                label: l.readingPageCreate,
                icon: Icons.add_rounded,
                compact: true,
                onTap: onOpen,
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < nodes.length; i++)
            _NoteRow(
              node: nodes[i],
              isLast: i == nodes.length - 1,
              onTap: onOpen,
            ),
        ],
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.node,
    required this.isLast,
    required this.onTap,
  });
  final NoteTreeNode node;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final isFolder = node.type == NoteTreeNodeType.folder;
    // 真实 model 无每条笔记的阅读进度字段，避免伪造百分比：右侧只显示可派生的
    // 文件夹子项数（详见 data-blocked），文件行则给副文本占位。
    final detail = isFolder
        ? l.readingPageNoteItemCount(node.children.length)
        : node.isTaskFile
            ? l.readingPageNoteTaskList
            : 'Markdown';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: t.hairline)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: t.insetBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isFolder
                  ? Icons.folder_outlined
                  : node.isTaskFile
                      ? Icons.checklist_rounded
                      : Icons.menu_book_rounded,
              size: 16,
              color: t.accentBright,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: t.text0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: t.text2),
                ),
              ],
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }
}

class _Cover extends StatefulWidget {
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
  State<_Cover> createState() => _CoverState();
}

class _CoverState extends State<_Cover> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final placeholder = ColoredBox(
      color: t.insetBg,
      child: Icon(Icons.menu_book_outlined, size: 22, color: t.text3),
    );
    Widget cover;
    if (widget.localPath != null &&
        widget.localPath!.isNotEmpty &&
        File(widget.localPath!).existsSync()) {
      cover = Image.file(
        File(widget.localPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      );
    } else if (widget.streamPath != null && widget.streamPath!.isNotEmpty) {
      cover = StreamImage(
        path: widget.streamPath,
        fileSystem: widget.fileSystem,
        placeholder: placeholder,
        errorWidget: placeholder,
        cacheKey: widget.cacheKey,
      );
    } else {
      cover = placeholder;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AnimatedScale(
              scale: _hover ? 1.012 : 1,
              duration: const Duration(milliseconds: 220),
              curve: DesignTokens.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: DesignTokens.easeOut,
                transform: Matrix4.translationValues(0, _hover ? -5 : 0, 0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: _hover ? 0.55 : 0.4),
                      blurRadius: _hover ? 28 : 16,
                      offset: const Offset(0, 12),
                    ),
                    if (_hover)
                      BoxShadow(
                        color: t.accent.withValues(alpha: 0.25),
                        blurRadius: 28,
                        offset: const Offset(0, 8),
                      ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      cover,
                      if (widget.badge != null)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: AppTag(widget.badge!,
                              variant: TagVariant.neutral),
                        ),
                      if (_hover)
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0x8C000000)],
                              stops: [0.4, 1],
                            ),
                          ),
                        ),
                      // 设计稿封面底部有 accent 进度条；但漫画/图书 model 无逐项
                      // 阅读进度字段，无法真实填充，故省略（data-blocked）。
                      Material(
                        color: Colors.transparent,
                        child: InkWell(onTap: widget.onTap),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: t.text0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            widget.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: t.text2),
          ),
        ],
      ),
    );
  }
}
