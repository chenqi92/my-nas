import 'dart:io';

import 'package:flutter/material.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/book_file_cache_service.dart';
import 'package:my_nas/features/book/data/services/manga_detector.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/features/book/presentation/pages/book_reader_page.dart';
import 'package:my_nas/features/book/presentation/pages/ebook_reader_page.dart';
import 'package:my_nas/features/book/presentation/pages/epub_comic_reader_page.dart';
import 'package:my_nas/features/book/presentation/pages/native_ebook_reader_page.dart';
import 'package:my_nas/features/book/presentation/pages/pdf_reader_page.dart';
import 'package:my_nas/features/reading/data/services/reader_settings_service.dart';
import 'package:my_nas/l10n/app_localizations.dart';

/// 图书导航工具
///
/// 统一处理图书打开逻辑，根据格式和内容类型选择合适的阅读器
class BookNavigator {
  BookNavigator._();
  static final BookNavigator instance = BookNavigator._();

  final BookFileCacheService _cacheService = BookFileCacheService();
  final MangaDetector _mangaDetector = MangaDetector.instance;

  /// 打开图书
  ///
  /// 根据格式和内容类型选择合适的阅读器：
  /// - 检测到漫画 -> EpubComicReaderPage
  /// - EPUB/MOBI/AZW3 -> EbookReaderPage
  /// - PDF -> PdfReaderPage
  /// - TXT -> BookReaderPage
  Future<void> openBook(
    BuildContext context,
    BookItem book, {
    bool checkManga = true,
  }) async {
    logger.d('BookNavigator: 打开图书 ${book.name} (${book.format})');

    // 初始化缓存服务
    await _cacheService.init();

    // 获取缓存文件（如果有）
    final cachedFile = await _cacheService.getCachedFile(
      book.sourceId,
      book.path,
    );

    // 检测是否为漫画
    if (checkManga && _shouldCheckManga(book)) {
      final isManga = await _mangaDetector.isManga(book, cachedFile: cachedFile);

      if (isManga) {
        logger.i('BookNavigator: 检测到漫画，使用漫画阅读器');
        await _openAsManga(context, book, cachedFile);
        return;
      }
    }

    // 根据格式选择阅读器
    await _openByFormat(context, book);
  }

  /// 强制使用漫画阅读器打开
  Future<void> openAsManga(BuildContext context, BookItem book) async {
    await _cacheService.init();
    final cachedFile = await _cacheService.getCachedFile(
      book.sourceId,
      book.path,
    );
    await _openAsManga(context, book, cachedFile);
  }

  /// 强制使用普通阅读器打开
  Future<void> openAsBook(BuildContext context, BookItem book) async {
    await _openByFormat(context, book);
  }

  /// 判断是否应该检测漫画
  bool _shouldCheckManga(BookItem book) => book.format == BookFormat.epub ||
           book.format == BookFormat.mobi ||
           book.format == BookFormat.azw3;

  /// 使用漫画阅读器打开
  Future<void> _openAsManga(
    BuildContext context,
    BookItem book,
    File? cachedFile,
  ) async {
    if (book.format != BookFormat.epub) {
      // MOBI/AZW3 需要先转换为 EPUB
      // 使用 EbookReaderPage 处理转换
      if (!context.mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (context) => EbookReaderPage(
            book: book,
            forceComicReader: true,
          ),
        ),
      );
      return;
    }

    // EPUB 格式可以直接使用漫画阅读器
    if (cachedFile != null) {
      if (!context.mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (context) => EpubComicReaderPage(
            book: book,
            epubFile: cachedFile,
          ),
        ),
      );
    } else {
      // 没有缓存，需要先下载
      // 使用 EbookReaderPage 下载后再跳转
      // 或者显示提示
      if (!context.mounted) return;
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.bookDownloadingMangaFile),
          duration: const Duration(seconds: 2),
        ),
      );
      // 回退到普通 EPUB 阅读器处理下载
      await _openByFormat(context, book);
    }
  }

  /// 根据格式选择阅读器
  Future<void> _openByFormat(
    BuildContext context,
    BookItem book,
  ) async {
    if (!context.mounted) return;

    switch (book.format) {
      case BookFormat.epub:
      case BookFormat.mobi:
      case BookFormat.azw3:
        // 直接从设置服务读取阅读器引擎配置
        final settingsService = ReaderSettingsService();
        await settingsService.init();
        final settings = settingsService.getBookSettings();
        final engine = settings.epubEngine;

        logger.d('BookNavigator: 使用 ${engine.name} 引擎打开 ${book.format.name}');

        if (engine == EpubReaderEngine.native) {
          // 使用原生 Flutter 阅读器
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (context) => NativeEbookReaderPage(book: book),
            ),
          );
        } else {
          // 使用 WebView (Foliate) 阅读器
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (context) => EbookReaderPage(book: book),
            ),
          );
        }
      case BookFormat.pdf:
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (context) => PdfReaderPage(book: book),
          ),
        );
      case BookFormat.txt:
      case BookFormat.unknown:
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (context) => BookReaderPage(book: book),
          ),
        );
    }
  }
}

/// 便捷扩展方法
extension BookNavigatorExtension on BuildContext {
  /// 打开图书
  Future<void> openBook(BookItem book, {bool checkManga = true}) =>
      BookNavigator.instance.openBook(this, book, checkManga: checkManga);

  /// 强制使用漫画阅读器打开
  Future<void> openAsManga(BookItem book) =>
      BookNavigator.instance.openAsManga(this, book);

  /// 强制使用普通阅读器打开
  Future<void> openAsBook(BookItem book) =>
      BookNavigator.instance.openAsBook(this, book);
}
