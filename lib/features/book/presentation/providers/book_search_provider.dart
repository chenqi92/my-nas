import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/book/data/services/sources/book_content_service.dart';
import 'package:my_nas/features/book/data/services/sources/book_search_service.dart';
import 'package:my_nas/features/book/domain/entities/book_source.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'book_search_provider.g.dart';

/// 书籍搜索服务 Provider
@riverpod
BookSearchService bookSearchService(Ref ref) => BookSearchService.instance;

/// 书籍内容服务 Provider
@riverpod
BookContentService bookContentService(Ref ref) => BookContentService.instance;

/// 搜索状态
class BookSearchState {
  const BookSearchState({
    this.keyword = '',
    this.results = const [],
    this.isLoading = false,
    this.error,
    this.isComplete = false,
    this.completedSources = 0,
    this.totalSources = 0,
  });

  final String keyword;
  final List<OnlineBook> results;
  final bool isLoading;
  final String? error;
  final bool isComplete;
  final int completedSources;
  final int totalSources;

  BookSearchState copyWith({
    String? keyword,
    List<OnlineBook>? results,
    bool? isLoading,
    String? error,
    bool? isComplete,
    int? completedSources,
    int? totalSources,
  }) =>
      BookSearchState(
        keyword: keyword ?? this.keyword,
        results: results ?? this.results,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        isComplete: isComplete ?? this.isComplete,
        completedSources: completedSources ?? this.completedSources,
        totalSources: totalSources ?? this.totalSources,
      );
}

/// 书籍搜索状态管理 Provider
@riverpod
class BookSearch extends _$BookSearch {
  StreamSubscription<OnlineBook>? _subscription;

  @override
  BookSearchState build() {
    ref.onDispose(() {
      _subscription?.cancel();
    });
    return const BookSearchState();
  }

  /// 开始搜索
  Future<void> search(String keyword) async {
    if (keyword.trim().isEmpty) return;

    // 取消之前的搜索
    await _subscription?.cancel();

    // 重置状态
    state = BookSearchState(
      keyword: keyword,
      isLoading: true,
    );

    final searchService = ref.read(bookSearchServiceProvider);
    final results = <OnlineBook>[];
    final seen = <String>{};

    try {
      // 启动进度更新定时器
      Timer? progressTimer;
      progressTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (state.isLoading) {
          state = state.copyWith(
            completedSources: searchService.completedSources,
            totalSources: searchService.totalSources,
          );
        }
      });
      
      _subscription = searchService.search(keyword).listen(
        (book) {
          // 去重
          final key = book.uniqueKey;
          if (!seen.contains(key)) {
            seen.add(key);
            results.add(book);
            // 更新状态（包含进度）
            state = state.copyWith(
              results: List.from(results),
              completedSources: searchService.completedSources,
              totalSources: searchService.totalSources,
            );
          }
        },
        onError: (Object e) {
          progressTimer?.cancel();
          state = state.copyWith(
            isLoading: false,
            error: e.toString(),
          );
        },
        onDone: () {
          progressTimer?.cancel();
          state = state.copyWith(
            isLoading: false,
            isComplete: true,
            completedSources: searchService.totalSources,
            totalSources: searchService.totalSources,
          );
        },
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// 取消搜索
  void cancel() {
    _subscription?.cancel();
    state = state.copyWith(isLoading: false);
  }

  /// 清空结果
  void clear() {
    _subscription?.cancel();
    state = const BookSearchState();
  }
}

/// 书籍详情 Provider
@riverpod
Future<BookInfo?> bookInfo(Ref ref, OnlineBook book) async {
  final contentService = ref.watch(bookContentServiceProvider);
  return contentService.getBookInfo(book);
}

/// 章节目录 Provider
@riverpod
Future<List<OnlineChapter>> chapterList(
  Ref ref,
  BookSource source,
  String bookUrl, {
  String? tocUrl,
}) async {
  final contentService = ref.watch(bookContentServiceProvider);
  return contentService.getChapterList(source, bookUrl, tocUrl: tocUrl);
}

/// 章节内容 Provider
@riverpod
Future<String?> chapterContent(
  Ref ref,
  BookSource source,
  OnlineChapter chapter,
) async {
  final contentService = ref.watch(bookContentServiceProvider);
  return contentService.getChapterContent(source, chapter);
}
