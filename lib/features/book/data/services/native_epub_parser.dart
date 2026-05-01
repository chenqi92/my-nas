// ignore_for_file: unused_field

import 'dart:io';
import 'dart:typed_data';

import 'package:epub_plus/epub_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:my_nas/core/utils/logger.dart';

/// 解析后的电子书
class ParsedEbook {
  ParsedEbook({
    required this.title,
    required this.chapters,
    required this.toc,
    this.author,
    this.coverImage,
  });

  final String title;
  final String? author;
  final List<EbookChapter> chapters;
  final List<TocItem> toc;
  final Uint8List? coverImage;
}

/// 电子书章节
class EbookChapter {
  EbookChapter({
    required this.index,
    required this.title,
    required this.htmlContent,
    required this.href,
  });

  final int index;
  final String title;
  final String htmlContent;
  final String href;
}

/// 目录项
class TocItem {
  TocItem({
    required this.title,
    required this.href,
    this.children = const [],
    this.depth = 0,
  });

  final String title;
  final String href;
  final List<TocItem> children;
  final int depth;
}

/// 原生 EPUB 解析器
///
/// 使用 epub_plus 库解析 EPUB 文件，提取章节内容和目录。
/// 比 WebView 方案更快，内存占用更低。
class NativeEpubParser {
  NativeEpubParser._();
  static final NativeEpubParser instance = NativeEpubParser._();

  EpubBook? _currentBook;
  String? _currentFilePath;

  /// 解析 EPUB 文件
  Future<ParsedEbook> parse(File epubFile) async {
    final stopwatch = Stopwatch()..start();

    try {
      // 读取文件
      final bytes = await epubFile.readAsBytes();

      // 在 isolate 中解析（避免阻塞 UI）
      final book = await compute(_parseEpubBytes, bytes);
      _currentBook = book;
      _currentFilePath = epubFile.path;

      stopwatch.stop();
      logger.i(
        'NativeEpubParser: 解析完成 ${book.title ?? "未知"}, '
        '${book.chapters.length} 章, '
        '耗时 ${stopwatch.elapsedMilliseconds}ms',
      );

      // 提取章节
      final chapters = _extractChapters(book);

      // 提取目录
      final toc = _extractToc(book);

      // 提取封面
      final coverImage = _extractCover(book);

      return ParsedEbook(
        title: book.title ?? epubFile.uri.pathSegments.last,
        author: book.author ?? book.authors.whereType<String>().join(', '),
        chapters: chapters,
        toc: toc,
        coverImage: coverImage,
      );
    } on Exception catch (e, st) {
      logger.e('NativeEpubParser: 解析失败', e, st);
      rethrow;
    }
  }

  /// 获取章节 HTML 内容
  String? getChapterHtml(int chapterIndex) {
    if (_currentBook == null) return null;

    final chapters = _currentBook!.chapters;
    if (chapterIndex >= chapters.length) return null;

    return chapters[chapterIndex].htmlContent;
  }

  /// 获取图片资源
  Uint8List? getImage(String href) {
    if (_currentBook == null) return null;

    // 标准化 href
    final normalizedHref = _normalizeHref(href);

    // 从内容中查找图片
    final images = _currentBook!.content?.images;
    if (images == null) return null;

    for (final entry in images.entries) {
      final key = entry.key;
      if (_normalizeHref(key) == normalizedHref || key.endsWith(normalizedHref)) {
        final imageFile = entry.value;
        // epub_plus 的图片是 EpubByteContentFile
        // ignore: avoid_dynamic_calls
        final content = (imageFile as dynamic).content;
        if (content is List<int>) {
          return Uint8List.fromList(content);
        }
      }
    }

    return null;
  }

  /// 释放资源
  void dispose() {
    _currentBook = null;
    _currentFilePath = null;
  }

  /// 提取章节列表
  List<EbookChapter> _extractChapters(EpubBook book) {
    final chapters = <EbookChapter>[];

    for (var i = 0; i < book.chapters.length; i++) {
      final chapter = book.chapters[i];
      chapters.add(EbookChapter(
        index: i,
        title: chapter.title ?? '第 ${i + 1} 章',
        htmlContent: _processHtmlContent(chapter.htmlContent ?? ''),
        href: '',
      ));
    }

    return chapters;
  }

  /// 提取目录
  List<TocItem> _extractToc(EpubBook book) {
    final schema = book.schema;
    if (schema == null) return [];

    final navigation = schema.navigation;
    if (navigation == null) return [];

    final navMap = navigation.navMap;
    if (navMap == null) return [];

    return _convertNavPoints(navMap.points, 0);
  }

  List<TocItem> _convertNavPoints(List<EpubNavigationPoint> points, int depth) {
    if (points.isEmpty) return [];

    return points.map((point) {
      // 从 navigationLabels 获取标题
      final title = point.navigationLabels.isNotEmpty
          ? (point.navigationLabels.first.text ?? '')
          : '';
      
      return TocItem(
        title: title,
        href: point.content?.source ?? '',
        depth: depth,
        children: _convertNavPoints(point.childNavigationPoints, depth + 1),
      );
    }).toList();
  }

  /// 提取封面图片
  Uint8List? _extractCover(EpubBook book) {
    // 从 coverImage 获取封面（类型是 image package 的 Image）
    final coverImage = book.coverImage;
    if (coverImage != null) {
      // 将 Image 编码为 PNG
      return Uint8List.fromList(img.encodePng(coverImage));
    }

    return null;
  }

  /// 处理 HTML 内容
  ///
  /// - 移除不需要的元素（script, style）
  /// - 处理图片路径
  String _processHtmlContent(String html) {
    // 移除 script 标签
    var processed = html.replaceAll(
      RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false),
      '',
    );

    // 移除 style 标签
    processed = processed.replaceAll(
      RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
      '',
    );

    // 移除 head 标签内容
    processed = processed.replaceAll(
      RegExp(r'<head[^>]*>[\s\S]*?</head>', caseSensitive: false),
      '',
    );

    // 只保留 body 内容
    final bodyMatch = RegExp(
      r'<body[^>]*>([\s\S]*)</body>',
      caseSensitive: false,
    ).firstMatch(processed);

    if (bodyMatch != null) {
      processed = bodyMatch.group(1) ?? processed;
    }

    return processed.trim();
  }

  /// 标准化 href
  String _normalizeHref(String href) {
    // 移除前导 ../ 和 ./
    var normalized = href;
    while (normalized.startsWith('../')) {
      normalized = normalized.substring(3);
    }
    while (normalized.startsWith('./')) {
      normalized = normalized.substring(2);
    }
    // 移除 fragment
    final fragmentIndex = normalized.indexOf('#');
    if (fragmentIndex != -1) {
      normalized = normalized.substring(0, fragmentIndex);
    }
    return normalized;
  }
}

/// 在 isolate 中解析 EPUB
Future<EpubBook> _parseEpubBytes(Uint8List bytes) async =>
    EpubReader.readBook(bytes);
