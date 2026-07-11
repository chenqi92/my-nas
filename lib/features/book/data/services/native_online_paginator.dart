import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 在线书籍分页后的页面
class OnlineBookPage {
  const OnlineBookPage({
    required this.pageIndex,
    required this.chapterIndex,
    required this.content,
    required this.progress,
  });

  /// 页面索引（章节内）
  final int pageIndex;

  /// 所属章节索引
  final int chapterIndex;

  /// 该页纯文本内容
  final String content;

  /// 章节内进度 (0.0 - 1.0)
  final double progress;
}

/// 章节分页结果
class ChapterPaginationResult {
  const ChapterPaginationResult({
    required this.pages,
    required this.totalPages,
    required this.chapterIndex,
  });

  final List<OnlineBookPage> pages;
  final int totalPages;
  final int chapterIndex;
}

/// 在线书籍分页器
///
/// 将纯文本内容按段落分页，用于在线书源内容的渲染。
/// 与 NativeEpubPaginator 不同，这里处理的是纯文本而非 HTML。
class NativeOnlinePaginator {
  NativeOnlinePaginator._();
  static final NativeOnlinePaginator instance = NativeOnlinePaginator._();

  static const _maxChapterChars = 2 * 1024 * 1024;

  /// 对章节内容进行分页
  ///
  /// [content] - 章节纯文本内容
  /// [chapterIndex] - 章节索引
  /// [viewportSize] - 可用视口大小
  /// [baseStyle] - 基础文本样式
  /// [horizontalPadding] - 水平内边距
  /// [verticalPadding] - 垂直内边距
  Future<ChapterPaginationResult> paginateChapter({
    required String content,
    required int chapterIndex,
    required Size viewportSize,
    required TextStyle baseStyle,
    double horizontalPadding = 24,
    double verticalPadding = 16,
  }) async {
    if (content.isEmpty) {
      return ChapterPaginationResult(
        pages: [
          OnlineBookPage(
            pageIndex: 0,
            chapterIndex: chapterIndex,
            content: appL10n.bookPaginatorNoContent,
            progress: 1.0,
          ),
        ],
        totalPages: 1,
        chapterIndex: chapterIndex,
      );
    }
    if (content.length > _maxChapterChars) {
      throw Exception('章节内容过大，已拒绝同步分页: ${content.length} chars');
    }

    // 计算可用内容区域
    final contentWidth = viewportSize.width - horizontalPadding * 2;
    final contentHeight = viewportSize.height - verticalPadding * 2;

    return Isolate.run<ChapterPaginationResult>(
      () => _paginateChapterInIsolate(
        content: content,
        chapterIndex: chapterIndex,
        contentWidth: contentWidth,
        contentHeight: contentHeight,
        fontSize: baseStyle.fontSize ?? 18,
        lineHeight: baseStyle.height ?? 1.5,
      ),
    );
  }

  static ChapterPaginationResult _paginateChapterInIsolate({
    required String content,
    required int chapterIndex,
    required double contentWidth,
    required double contentHeight,
    required double fontSize,
    required double lineHeight,
  }) {
    final stopwatch = Stopwatch()..start();
    final pageContents = _paginateText(
      content: content,
      contentWidth: contentWidth,
      contentHeight: contentHeight,
      fontSize: fontSize,
      lineHeight: lineHeight,
    );
    final pages = <OnlineBookPage>[];
    for (var i = 0; i < pageContents.length; i++) {
      pages.add(
        OnlineBookPage(
          pageIndex: i,
          chapterIndex: chapterIndex,
          content: pageContents[i],
          progress: (i + 1) / pageContents.length,
        ),
      );
    }

    stopwatch.stop();
    logger.d(
      'NativeOnlinePaginator: 分页完成, '
      '章节 $chapterIndex, ${pages.length} 页, '
      '耗时 ${stopwatch.elapsedMilliseconds}ms',
    );
    return ChapterPaginationResult(
      pages: pages,
      totalPages: pages.length,
      chapterIndex: chapterIndex,
    );
  }

  /// 对文本进行分页
  static List<String> _paginateText({
    required String content,
    required double contentWidth,
    required double contentHeight,
    required double fontSize,
    required double lineHeight,
  }) {
    // 按段落分割（两个换行符或更多）
    final paragraphs = content
        .split(RegExp(r'\n\n+'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    if (paragraphs.isEmpty) {
      // 如果没有明显的段落分隔，尝试按单个换行分割
      final lines = content
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.isEmpty) {
        return [content];
      }
      return _paginateParagraphs(
        paragraphs: lines,
        contentWidth: contentWidth,
        contentHeight: contentHeight,
        fontSize: fontSize,
        lineHeight: lineHeight,
      );
    }

    return _paginateParagraphs(
      paragraphs: paragraphs,
      contentWidth: contentWidth,
      contentHeight: contentHeight,
      fontSize: fontSize,
      lineHeight: lineHeight,
    );
  }

  /// 对段落列表进行分页
  static List<String> _paginateParagraphs({
    required List<String> paragraphs,
    required double contentWidth,
    required double contentHeight,
    required double fontSize,
    required double lineHeight,
  }) {
    final pages = <String>[];
    var currentPageParagraphs = <String>[];
    var currentHeight = 0.0;

    final lineHeightPx = fontSize * lineHeight;

    for (final paragraph in paragraphs) {
      // 估算段落高度
      final paragraphHeight = _estimateParagraphHeight(
        paragraph: paragraph,
        contentWidth: contentWidth,
        fontSize: fontSize,
        lineHeightPx: lineHeightPx,
      );

      // 如果加入这个段落会超出页面高度
      if (currentHeight + paragraphHeight > contentHeight &&
          currentPageParagraphs.isNotEmpty) {
        // 保存当前页
        pages.add(currentPageParagraphs.join('\n\n'));
        currentPageParagraphs = [];
        currentHeight = 0;
      }

      currentPageParagraphs.add(paragraph);
      currentHeight += paragraphHeight;
    }

    // 保存最后一页
    if (currentPageParagraphs.isNotEmpty) {
      pages.add(currentPageParagraphs.join('\n\n'));
    }

    return pages.isEmpty ? [paragraphs.join('\n\n')] : pages;
  }

  /// 估算段落高度
  static double _estimateParagraphHeight({
    required String paragraph,
    required double contentWidth,
    required double fontSize,
    required double lineHeightPx,
  }) {
    if (paragraph.isEmpty) {
      return lineHeightPx;
    }

    final lineCount = _estimateLineCount(
      text: paragraph,
      contentWidth: contentWidth,
      fontSize: fontSize,
    );

    // 段落后加一些间距（对应 paragraphSpacing）
    const paragraphSpacing = 16.0;

    return lineCount * lineHeightPx + paragraphSpacing;
  }

  static int _estimateLineCount({
    required String text,
    required double contentWidth,
    required double fontSize,
  }) {
    final unitsPerLine = math.max(1.0, contentWidth / fontSize);
    var units = 0.0;
    for (final rune in text.runes) {
      if (rune == 10 || rune == 13) {
        units += unitsPerLine;
      } else if (rune >= 0x2E80) {
        units += 1.0;
      } else {
        units += 0.56;
      }
    }
    return math.max(1, (units / unitsPerLine).ceil());
  }

  /// 根据进度获取页面索引
  int getPageIndexFromProgress(double progress, int totalPages) {
    if (progress <= 0) return 0;
    if (progress >= 1) return totalPages - 1;
    return (progress * totalPages).floor().clamp(0, totalPages - 1);
  }
}
