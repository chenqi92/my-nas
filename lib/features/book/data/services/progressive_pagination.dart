import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/book_content_processor.dart';
import 'package:my_nas/features/book/data/services/readable_area_calculator.dart';
import 'package:my_nas/features/reading/data/services/reader_settings_service.dart';

/// 渐进式分页服务
/// 策略: 先快速估算分页,后台逐步优化
class ProgressivePagination {
  ProgressivePagination._();

  /// 第一阶段: 快速估算分页
  /// 使用字符数估算,快速给用户展示初始分页结果
  static Future<PaginationResult> quickPaginate({
    required String htmlContent,
    required List<BookChapter> chapters,
    required BuildContext context,
    required BookReaderSettings settings,
  }) async {
    // 使用优化的字符数估算
    final estimatedCharsPerPage =
        ReadableAreaCalculator.estimateCharsPerPage(context, settings);

    logger.i('快速分页: 估算每页字符数=$estimatedCharsPerPage');

    // 在 Isolate 中执行分页
    final result = await Isolate.run<PaginationResult>(
      () => _quickPaginateInIsolate(
        htmlContent,
        chapters,
        estimatedCharsPerPage,
      ),
    );

    logger.i('快速分页完成: ${result.pages.length} 页');
    return result;
  }

  /// Isolate 中的快速分页
  static PaginationResult _quickPaginateInIsolate(
    String htmlContent,
    List<BookChapter> chapters,
    int charsPerPage,
  ) {
    // 按段落分割
    final paragraphs = _splitHtmlIntoParagraphs(htmlContent);

    final pages = <String>[];
    final chapterPageMap = <int, int>{};

    var currentPageContent = StringBuffer();
    var currentCharCount = 0;
    var currentOffset = 0;

    // 记录每个章节对应的页码
    var chapterIndex = 0;

    for (final paragraph in paragraphs) {
      final paragraphLength = _estimateParagraphCharCount(paragraph);

      // 检查是否有章节在当前段落之前
      while (chapterIndex < chapters.length &&
          chapters[chapterIndex].offset <= currentOffset) {
        chapterPageMap[chapterIndex] = pages.length;
        chapterIndex++;
      }

      // 如果当前页已满,开始新页
      if (currentCharCount > 0 &&
          currentCharCount + paragraphLength > charsPerPage) {
        pages.add(currentPageContent.toString());
        currentPageContent = StringBuffer();
        currentCharCount = 0;
      }

      currentPageContent.write(paragraph);
      currentCharCount += paragraphLength;
      currentOffset += paragraph.length;
    }

    // 添加最后一页
    if (currentCharCount > 0) {
      pages.add(currentPageContent.toString());
    }

    // 确保至少有一页
    if (pages.isEmpty) {
      pages.add(htmlContent);
    }

    return PaginationResult(
      pages: pages,
      chapterPageMap: chapterPageMap,
    );
  }

  /// 第二阶段: 精确优化分页 (可选,后台执行)
  /// 检查并修复溢出或空余过多的页面
  static Future<PaginationResult> refinePagination({
    required PaginationResult initialResult,
    required BuildContext context,
    required BookReaderSettings settings,
    void Function(double progress)? onProgress,
  }) async {
    logger.i('开始精确优化分页...');

    final refinedPages = <String>[];
    final totalPages = initialResult.pages.length;

    for (var i = 0; i < totalPages; i++) {
      final page = initialResult.pages[i];

      // 检查页面溢出情况
      final overflowRatio = ReadableAreaCalculator.checkPageOverflow(
        page,
        // context 用于静态计算布局尺寸，不触发 setState/navigation
        // ignore: use_build_context_synchronously
        context,
        settings,
      );

      if (overflowRatio > 0.1) {
        // 页面溢出超过10%,需要拆分
        logger.d('页面 $i 溢出 ${(overflowRatio * 100).toStringAsFixed(1)}%, 拆分中...');

        final splitPages = await _splitOverflowPage(
          page,
          overflowRatio,
          context,
          settings,
        );
        refinedPages.addAll(splitPages);
      } else if (overflowRatio < -0.35 && i + 1 < totalPages) {
        // 页面空余超过35%,尝试合并下一页部分内容
        logger.d('页面 $i 空余 ${(-overflowRatio * 100).toStringAsFixed(1)}%, 尝试合并...');

        final merged = await _tryMergeWithNext(
          page,
          initialResult.pages[i + 1],
          context,
          settings,
        );

        refinedPages.add(merged.currentPage);

        if (merged.hasModifiedNext) {
          // 更新下一页内容
          initialResult.pages[i + 1] = merged.nextPage;
        }
      } else {
        // 页面大小合适,不需要调整
        refinedPages.add(page);
      }

      // 报告进度
      onProgress?.call((i + 1) / totalPages);
    }

    // 重新计算章节映射
    final newChapterMap = _recalculateChapterMap(
      refinedPages,
      initialResult.chapterPageMap,
      initialResult.pages.length,
      refinedPages.length,
    );

    logger.i('精确优化完成: ${initialResult.pages.length} -> ${refinedPages.length} 页');

    return PaginationResult(
      pages: refinedPages,
      chapterPageMap: newChapterMap,
    );
  }

  /// 拆分溢出的页面
  static Future<List<String>> _splitOverflowPage(
    String page,
    double overflowRatio,
    BuildContext context,
    BookReaderSettings settings,
  ) async {
    final paragraphs = _splitHtmlIntoParagraphs(page);
    if (paragraphs.length <= 1) {
      // 单段落无法拆分,返回原页
      return [page];
    }

    // 估算拆分点 (约在 60% 位置)
    final splitRatio = 0.6;
    final availableWidth =
        ReadableAreaCalculator.calculateAvailableWidth(context, settings);

    final firstPageContent = StringBuffer();
    final secondPageContent = StringBuffer();
    var firstPageHeight = 0.0;
    var splitIndex = 0;

    // 逐段添加,找到合适的拆分点
    for (var i = 0; i < paragraphs.length; i++) {
      final paraHeight = ReadableAreaCalculator.estimateParagraphHeight(
        paragraphs[i],
        availableWidth,
        settings,
      );

      if (firstPageHeight / (firstPageHeight + paraHeight) < splitRatio ||
          i == 0) {
        firstPageContent.write(paragraphs[i]);
        firstPageHeight += paraHeight;
        splitIndex = i + 1;
      } else {
        break;
      }
    }

    // 剩余段落放入第二页
    for (var i = splitIndex; i < paragraphs.length; i++) {
      secondPageContent.write(paragraphs[i]);
    }

    return [
      firstPageContent.toString(),
      if (secondPageContent.isNotEmpty) secondPageContent.toString(),
    ];
  }

  /// 尝试合并当前页和下一页
  static Future<_MergeResult> _tryMergeWithNext(
    String currentPage,
    String nextPage,
    BuildContext context,
    BookReaderSettings settings,
  ) async {
    final currentParagraphs = _splitHtmlIntoParagraphs(currentPage);
    final nextParagraphs = _splitHtmlIntoParagraphs(nextPage);

    if (nextParagraphs.isEmpty) {
      return _MergeResult(
        currentPage: currentPage,
        nextPage: nextPage,
        hasModifiedNext: false,
      );
    }

    final availableWidth =
        ReadableAreaCalculator.calculateAvailableWidth(context, settings);
    final availableHeight =
        ReadableAreaCalculator.calculateAvailableHeight(context, settings);

    // 尝试从下一页取一些段落
    final mergedContent = StringBuffer(currentPage);
    var mergedHeight = _estimatePageHeight(
      currentParagraphs,
      availableWidth,
      settings,
    );

    var takenCount = 0;

    for (final para in nextParagraphs) {
      final paraHeight = ReadableAreaCalculator.estimateParagraphHeight(
        para,
        availableWidth,
        settings,
      );

      if (mergedHeight + paraHeight <= availableHeight * 0.95) {
        mergedContent.write(para);
        mergedHeight += paraHeight;
        takenCount++;
      } else {
        break;
      }
    }

    // 如果至少取了一个段落,更新两页内容
    if (takenCount > 0) {
      final remainingNextContent = StringBuffer();
      for (var i = takenCount; i < nextParagraphs.length; i++) {
        remainingNextContent.write(nextParagraphs[i]);
      }

      return _MergeResult(
        currentPage: mergedContent.toString(),
        nextPage: remainingNextContent.toString(),
        hasModifiedNext: true,
      );
    }

    return _MergeResult(
      currentPage: currentPage,
      nextPage: nextPage,
      hasModifiedNext: false,
    );
  }

  /// 估算页面总高度
  static double _estimatePageHeight(
    List<String> paragraphs,
    double availableWidth,
    BookReaderSettings settings,
  ) {
    var totalHeight = 0.0;
    for (final para in paragraphs) {
      totalHeight += ReadableAreaCalculator.estimateParagraphHeight(
        para,
        availableWidth,
        settings,
      );
    }
    return totalHeight;
  }

  /// 重新计算章节映射
  static Map<int, int> _recalculateChapterMap(
    List<String> newPages,
    Map<int, int> oldChapterMap,
    int oldPageCount,
    int newPageCount,
  ) {
    final newMap = <int, int>{};

    // 简单按比例映射
    oldChapterMap.forEach((chapterIndex, oldPageIndex) {
      final ratio = oldPageIndex / oldPageCount;
      final newPageIndex = (ratio * newPageCount).round().clamp(0, newPageCount - 1);
      newMap[chapterIndex] = newPageIndex;
    });

    return newMap;
  }

  /// 分割 HTML 为段落
  static List<String> _splitHtmlIntoParagraphs(String html) {
    final paragraphs = <String>[];

    // 匹配块级元素
    final blockPattern = RegExp(
      '<(?:p|div|h[1-6]|blockquote|li|tr)[^>]*>.*?</(?:p|div|h[1-6]|blockquote|li|tr)>',
      caseSensitive: false,
      dotAll: true,
    );

    final matches = blockPattern.allMatches(html);

    if (matches.isEmpty) {
      // 没有块级元素,按换行分割
      final lines = html.split(RegExp(r'<br\s*/?>\s*'));
      for (final line in lines) {
        if (line.trim().isNotEmpty) {
          paragraphs.add('<p>$line</p>');
        }
      }
    } else {
      for (final match in matches) {
        paragraphs.add(match.group(0)!);
      }
    }

    return paragraphs;
  }

  /// 估算段落字符数 (用于快速分页)
  static int _estimateParagraphCharCount(String paragraphHtml) {
    // 移除 HTML 标签
    final plainText = paragraphHtml.replaceAll(RegExp('<[^>]+>'), '');
    return plainText.length;
  }
}

/// 合并结果
class _MergeResult {
  _MergeResult({
    required this.currentPage,
    required this.nextPage,
    required this.hasModifiedNext,
  });

  final String currentPage;
  final String nextPage;
  final bool hasModifiedNext;
}
