import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/book/domain/entities/book_source.dart';
import 'package:my_nas/features/book/presentation/pages/online_book_detail_page.dart';
import 'package:my_nas/features/book/presentation/providers/book_search_provider.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_glass_container.dart';
import 'package:my_nas/app/theme/ui_style.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

/// 在线书籍搜索页面
class OnlineBookSearchPage extends ConsumerStatefulWidget {
  const OnlineBookSearchPage({super.key});

  @override
  ConsumerState<OnlineBookSearchPage> createState() => _OnlineBookSearchPageState();
}

class _OnlineBookSearchPageState extends ConsumerState<OnlineBookSearchPage>
    with TabBarVisibilityMixin {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    hideTabBar();
    // 自动聚焦搜索框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final searchState = ref.watch(bookSearchProvider);
    final uiStyle = ref.watch(uiStyleProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      appBar: AppBar(
        leading: const RoundedBackButton(),
        title: _buildSearchField(isDark),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (searchState.isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_rounded),
              onPressed: _clearSearch,
            ),
        ],
      ),
      body: _buildBody(searchState, isDark, uiStyle),
    );
  }

  Widget _buildSearchField(bool isDark) {
    return TextField(
      controller: _searchController,
      focusNode: _focusNode,
      decoration: InputDecoration(
        hintText: '搜索书名或作者',
        border: InputBorder.none,
        hintStyle: TextStyle(
          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
        ),
      ),
      style: TextStyle(
        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
        fontSize: 16,
      ),
      textInputAction: TextInputAction.search,
      onSubmitted: _handleSearch,
    );
  }

  Widget _buildBody(BookSearchState searchState, bool isDark, UIStyle uiStyle) {
    // 空状态 - 尚未搜索
    if (searchState.keyword.isEmpty && searchState.results.isEmpty) {
      return _buildEmptyState(isDark);
    }

    // 错误状态
    if (searchState.error != null) {
      return _buildErrorState(searchState.error!, isDark);
    }

    // 搜索中但无结果
    if (searchState.results.isEmpty && searchState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 搜索完成但无结果
    if (searchState.results.isEmpty && searchState.isComplete) {
      return _buildNoResultsState(isDark);
    }

    // 显示结果
    return _buildResultsList(searchState.results, isDark, uiStyle, searchState);
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_rounded,
            size: 64,
            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '搜索在线书籍',
            style: context.textTheme.titleMedium?.copyWith(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '输入书名或作者名开始搜索',
            style: context.textTheme.bodyMedium?.copyWith(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 64,
            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '未找到相关书籍',
            style: context.textTheme.titleMedium?.copyWith(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '尝试其他关键词或添加更多书源',
            style: context.textTheme.bodyMedium?.copyWith(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error, bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
          const SizedBox(height: 16),
          Text('搜索失败: $error'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _handleSearch(_searchController.text),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList(
    List<OnlineBook> books,
    bool isDark,
    UIStyle uiStyle,
    BookSearchState searchState,
  ) {
    final isLoading = searchState.isLoading;
    return Column(
      children: [
        // 结果统计
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          child: Row(
            children: [
              Text(
                '搜索结果: ${books.length} 本',
                style: context.textTheme.bodySmall?.copyWith(
                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                ),
              ),
              if (isLoading) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
                const SizedBox(width: 4),
                Text(
                  searchState.totalSources > 0
                      ? '${searchState.completedSources}/${searchState.totalSources} 书源'
                      : '搜索中...',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
        // 结果列表
        Expanded(
          child: ListView.builder(
            padding: AppSpacing.paddingMd,
            itemCount: books.length,
            itemBuilder: (context, index) {
              final book = books[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _BookCard(
                  book: book,
                  isDark: isDark,
                  uiStyle: uiStyle,
                  onTap: () => _openBookDetail(book),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _handleSearch(String keyword) {
    if (keyword.trim().isEmpty) return;
    ref.read(bookSearchProvider.notifier).search(keyword.trim());
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(bookSearchProvider.notifier).clear();
    _focusNode.requestFocus();
  }

  void _openBookDetail(OnlineBook book) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => OnlineBookDetailPage(book: book),
      ),
    );
  }
}

/// 书籍卡片
class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.book,
    required this.isDark,
    required this.uiStyle,
    required this.onTap,
  });

  final OnlineBook book;
  final bool isDark;
  final UIStyle uiStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AdaptiveGlassContainer(
      uiStyle: uiStyle,
      isDark: isDark,
      cornerRadius: 12,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 封面
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 60,
                    height: 80,
                    child: book.coverUrl != null && book.coverUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: book.coverUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => _buildPlaceholder(),
                            errorWidget: (_, __, ___) => _buildPlaceholder(),
                          )
                        : _buildPlaceholder(),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                // 信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 书名
                      Text(
                        book.name,
                        style: context.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // 作者
                      if (book.author.isNotEmpty)
                        Text(
                          book.author,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 4),
                      // 分类/最新章节
                      Row(
                        children: [
                          if (book.kind != null && book.kind!.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                book.kind!.split(',').first,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              book.lastChapter ?? '',
                              style: context.textTheme.bodySmall?.copyWith(
                                color: isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : AppColors.lightOnSurfaceVariant,
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // 书源
                      Text(
                        '来源: ${book.source.displayName}',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.7)
                              : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.7),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                // 箭头
                Icon(
                  Icons.chevron_right_rounded,
                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
      child: Icon(
        Icons.auto_stories_rounded,
        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
        size: 24,
      ),
    );
  }
}
