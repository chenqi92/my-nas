// ignore_for_file: unused_element

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/ui_style.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/features/book/domain/entities/book_source.dart';
import 'package:my_nas/features/book/presentation/pages/book_list_page.dart';
import 'package:my_nas/features/book/presentation/pages/online_book_detail_page.dart';
import 'package:my_nas/features/book/presentation/providers/book_search_provider.dart';
import 'package:my_nas/features/book/presentation/providers/online_book_shelf_provider.dart';
import 'package:my_nas/features/book/data/services/online_book_shelf_service.dart';
import 'package:my_nas/features/book/data/services/sources/book_source_manager_service.dart';
import 'package:my_nas/features/comic/presentation/pages/comic_list_page.dart';
import 'package:my_nas/features/note/presentation/pages/note_list_page.dart';
import 'package:my_nas/features/note/presentation/widgets/note_tree_widget.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_glass_app_bar.dart';

/// 图书搜索模式
enum BookSearchMode {
  local('本地'),
  online('书源');

  const BookSearchMode(this.label);
  final String label;
}

/// 当前选中的阅读 Tab
final readingTabProvider = StateProvider<int>((ref) => 0);

/// 阅读内容类型
enum ReadingContentType {
  book(Icons.menu_book_rounded, '图书'),
  comic(Icons.collections_bookmark_rounded, '漫画'),
  note(Icons.note_alt_rounded, '笔记');

  const ReadingContentType(this.icon, this.label);
  final IconData icon;
  final String label;
}

class ReadingPage extends ConsumerStatefulWidget {
  const ReadingPage({super.key});

  @override
  ConsumerState<ReadingPage> createState() => _ReadingPageState();
}

class _ReadingPageState extends ConsumerState<ReadingPage> {
  late PageController _pageController;
  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;
  BookSearchMode _bookSearchMode = BookSearchMode.local;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: ref.read(readingTabProvider),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onTabChanged(int index) {
    ref.read(readingTabProvider.notifier).state = index;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentTab = ref.watch(readingTabProvider);
    final uiStyle = ref.watch(uiStyleProvider);
    final safeTop = MediaQuery.of(context).padding.top;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    // iOS 26 玻璃模式：悬浮布局
    if (uiStyle.isGlass) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
        body: Stack(
          children: [
            // 主内容区域
            _buildReadingContentWithLargeTitle(context, isDark, currentTab, safeTop),
            if (_showSearch)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => setState(() => _showSearch = false),
                ),
              ),
            // 悬浮按钮组或搜索栏（右上角）
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              top: _showSearch && keyboardInset > 0 ? null : safeTop + 8,
              right: 16,
              bottom: _showSearch && keyboardInset > 0 ? keyboardInset + 12 : null,
              child: _showSearch
                  ? _buildFloatingSearchBar(context, isDark, currentTab)
                  : _buildFloatingButtons(context, isDark, currentTab),
            ),
          ],
        ),
      );
    }

    // 经典模式：传统布局
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: Column(
        children: [
          // 统一的顶栏
          _buildAppBar(context, isDark, currentTab),
          // 内容区域
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(), // 禁用手势滑动
              onPageChanged: (index) {
                ref.read(readingTabProvider.notifier).state = index;
              },
              children: [
                // 图书页面内容 - 根据搜索模式显示不同内容
                _buildBookContent(isDark),
                // 漫画页面内容
                const ComicListContent(),
                // 笔记页面内容
                const NoteListContent(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建图书内容区域
  Widget _buildBookContent(bool isDark) {
    // 如果在书源搜索模式且正在搜索或有结果
    if (_showSearch && _bookSearchMode == BookSearchMode.online) {
      return _buildOnlineSearchResults(isDark);
    }
    // 如果在在线模式（非搜索），显示在线书架
    if (_bookSearchMode == BookSearchMode.online) {
      return _buildOnlineBookShelf(isDark);
    }
    return const BookListContent();
  }

  /// 构建在线书架内容
  Widget _buildOnlineBookShelf(bool isDark) {
    final shelfState = ref.watch(onlineBookShelfProvider);
    
    return shelfState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('加载失败', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.read(onlineBookShelfProvider.notifier).refresh(),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.cloud_off_rounded,
                    size: 36,
                    color: AppColors.primary.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '在线书架为空',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '搜索并添加在线书籍开始阅读',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[500] : Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }
        
        // 显示在线书架书籍网格
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 140,
            childAspectRatio: 0.6,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return _buildOnlineShelfCard(item, isDark);
          },
        );
      },
    );
  }

  /// 构建在线书架卡片
  Widget _buildOnlineShelfCard(OnlineBookShelfItem item, bool isDark) {
    return GestureDetector(
      onTap: () async {
        // 从书源管理器加载完整的书源规则
        final fullSource = await BookSourceManagerService.instance.getSourceById(item.sourceId);
        if (fullSource == null) {
          if (mounted) {
            context.showErrorToast('书源不存在，可能已被删除');
          }
          return;
        }
        
        // 使用完整的书源创建 OnlineBook 并打开详情页
        final book = OnlineBook(
          name: item.name,
          author: item.author,
          bookUrl: item.bookUrl,
          coverUrl: item.coverUrl,
          intro: item.intro,
          source: fullSource,
        );
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => OnlineBookDetailPage(book: book),
            ),
          );
        }
      },
      onLongPress: () => _showDeleteConfirmation(item, isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: item.coverUrl != null && item.coverUrl!.isNotEmpty
                    ? Image.network(
                        item.coverUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (_, __, ___) => _buildShelfPlaceholder(item, isDark),
                      )
                    : _buildShelfPlaceholder(item, isDark),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 书名
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          // 作者
          Text(
            item.author.isNotEmpty ? item.author : '佚名',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// 书架占位符
  Widget _buildShelfPlaceholder(OnlineBookShelfItem item, bool isDark) {
    return Container(
      color: isDark ? Colors.grey[850] : Colors.grey[100],
      child: Center(
        child: Icon(
          Icons.menu_book_rounded,
          size: 32,
          color: isDark ? Colors.grey[600] : Colors.grey[400],
        ),
      ),
    );
  }

  /// 显示删除确认对话框
  void _showDeleteConfirmation(OnlineBookShelfItem item, bool isDark) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? Colors.grey[850] : null,
        title: const Text('删除书籍'),
        content: Text('确定要将《${item.name}》从书架中移除吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await OnlineBookShelfService.instance.removeBook(item.id);
                ref.read(onlineBookShelfProvider.notifier).onBookRemoved();
                if (mounted) {
                  this.context.showSuccessToast('已从书架移除');
                }
              } catch (e, st) {
                AppError.handleWithUI(this.context, e, st, '删除失败');
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 构建书源搜索结果
  Widget _buildOnlineSearchResults(bool isDark) {
    final searchState = ref.watch(bookSearchProvider);

    // 空状态（没有搜索）
    if (searchState.keyword.isEmpty && searchState.results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_rounded,
              size: 64,
              color: isDark ? Colors.grey[700] : Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              '输入关键词搜索书源',
              style: TextStyle(
                color: isDark ? Colors.grey[500] : Colors.grey[600],
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    // 加载中
    if (searchState.isLoading && searchState.results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.amber),
            const SizedBox(height: 16),
            Text(
              '正在搜索书源...',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    // 错误状态
    if (searchState.error != null && searchState.results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            Text(
              '搜索出错: ${searchState.error}',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // 无结果
    if (searchState.results.isEmpty && searchState.isComplete) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.menu_book_rounded,
              size: 64,
              color: isDark ? Colors.grey[700] : Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              '未找到相关书籍',
              style: TextStyle(
                color: isDark ? Colors.grey[500] : Colors.grey[600],
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    // 结果列表
    return Column(
      children: [
        // 状态栏
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '找到 ${searchState.results.length} 本书',
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  fontSize: 13,
                ),
              ),
              if (searchState.isLoading)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.amber,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // 结果网格
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              childAspectRatio: 0.6,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: searchState.results.length,
            itemBuilder: (context, index) {
              final book = searchState.results[index];
              return _buildOnlineBookCard(book, isDark);
            },
          ),
        ),
      ],
    );
  }

  /// 构建在线书籍卡片
  Widget _buildOnlineBookCard(OnlineBook book, bool isDark) {
    return GestureDetector(
      onTap: () {
        // 打开书籍详情页
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => OnlineBookDetailPage(book: book),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: book.coverUrl != null && book.coverUrl!.isNotEmpty
                    ? Image.network(
                        book.coverUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (_, __, ___) => _buildBookPlaceholder(book, isDark),
                      )
                    : _buildBookPlaceholder(book, isDark),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 书名和作者 - 优化布局
          SizedBox(
            height: 40, // 紧凑高度
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                // 书名 - 过滤日期格式的无效名称
                Text(
                  _filterDisplayName(book.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                // 作者 - 更柔和的样式
                Text(
                  book.author.isNotEmpty ? book.author : '佚名',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark 
                        ? Colors.grey[400] 
                        : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  /// 过滤显示名称 - 移除纯日期格式的无效名称
  String _filterDisplayName(String name) {
    // 如果名称只是日期格式，返回"未知书名"
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(name.trim())) {
      return '未知书名';
    }
    // 如果名称以日期开头，尝试移除日期部分
    final datePrefix = RegExp(r'^\d{4}-\d{2}-\d{2}\s*');
    if (datePrefix.hasMatch(name)) {
      final cleaned = name.replaceFirst(datePrefix, '').trim();
      return cleaned.isNotEmpty ? cleaned : '未知书名';
    }
    return name;
  }

  /// 书籍封面占位符
  Widget _buildBookPlaceholder(OnlineBook book, bool isDark) {
    return Container(
      color: isDark ? Colors.grey[850] : Colors.grey[100],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.menu_book_rounded,
              size: 32,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                book.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// iOS 26 悬浮搜索栏（玻璃模式）
  Widget _buildFloatingSearchBar(BuildContext context, bool isDark, int currentTab) {
    final screenWidth = MediaQuery.of(context).size.width;
    final available = screenWidth - 96; // padding + gap + close button
    final searchWidth = available.clamp(220.0, 480.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 玻璃搜索栏
        GlassFloatingSearchBar(
          controller: _searchController,
          hintText: currentTab == 0 && _bookSearchMode == BookSearchMode.online
              ? '搜索书源...'
              : '搜索${ReadingContentType.values[currentTab].label}...',
          width: searchWidth,
          onChanged: (query) {
            setState(() {}); // 触发重建以更新模式切换可见性
            _performSearch(query, currentTab);
          },
          onClose: () => _closeSearch(currentTab),
        ),
        // 图书模式下显示本地/书源切换
        if (currentTab == 0) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...BookSearchMode.values.map((mode) {
                final isSelected = _bookSearchMode == mode;
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _bookSearchMode = mode);
                      ref.read(bookListProvider.notifier).setSearchQuery('');
                      ref.read(bookSearchProvider.notifier).clear();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.amber.withValues(alpha: isDark ? 0.3 : 0.2)
                            : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05)),
                        borderRadius: BorderRadius.circular(12),
                        border: isSelected ? Border.all(color: Colors.amber, width: 1.5) : null,
                      ),
                      child: Text(
                        mode.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          color: isSelected ? Colors.amber[700] : (isDark ? Colors.white70 : Colors.black54),
                        ),
                      ),
                    ),
                  ),
                );
              }),
              // 书源模式下显示搜索按钮
              if (_bookSearchMode == BookSearchMode.online && _searchController.text.isNotEmpty) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _performOnlineSearch(_searchController.text),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_rounded, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text('搜索', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  /// iOS 26 悬浮按钮组
  Widget _buildFloatingButtons(BuildContext context, bool isDark, int currentTab) =>
    GlassButtonGroup(
      children: [
        // 搜索按钮（仅在图书页显示）
        if (currentTab == 0)
          GlassGroupIconButton(
            icon: Icons.search_rounded,
            tooltip: '搜索',
            onPressed: () => _triggerSearch(currentTab),
          ),
        // 本地/在线切换按钮（仅在图书页显示）
        if (currentTab == 0)
          GlassGroupIconButton(
            icon: _bookSearchMode == BookSearchMode.online 
                ? Icons.cloud_rounded 
                : Icons.folder_rounded,
            tooltip: _bookSearchMode == BookSearchMode.online 
                ? '查看本地图书' 
                : '查看在线书架',
            onPressed: () {
              setState(() {
                _bookSearchMode = _bookSearchMode == BookSearchMode.online
                    ? BookSearchMode.local
                    : BookSearchMode.online;
              });
            },
          ),
        // 内容类型切换
        GlassGroupPopupMenuButton<int>(
          icon: ReadingContentType.values[currentTab].icon,
          tooltip: '切换内容类型',
          itemBuilder: (context) => ReadingContentType.values.asMap().entries.map((entry) {
            final index = entry.key;
            final type = entry.value;
            final isSelected = index == currentTab;

            return PopupMenuItem<int>(
              value: index,
              child: Row(
                children: [
                  Icon(
                    type.icon,
                    size: 20,
                    color: isSelected
                        ? AppColors.primary
                        : (isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[600]),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    type.label,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : (isDark ? AppColors.darkOnSurface : Colors.black87),
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  if (isSelected) ...[
                    const Spacer(),
                    Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
          onSelected: _onTabChanged,
        ),
      ],
    );

  /// iOS 26 带大标题的阅读内容
  Widget _buildReadingContentWithLargeTitle(
    BuildContext context,
    bool isDark,
    int currentTab,
    double safeTop,
  ) => PageView(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      onPageChanged: (index) {
        ref.read(readingTabProvider.notifier).state = index;
      },
      children: [
        // 图书页面 - 带大标题的滚动布局
        _buildScrollableContent(
          context, isDark, currentTab, safeTop,
          child: _bookSearchMode == BookSearchMode.online 
              ? _buildOnlineBookShelf(isDark) 
              : const BookListContent(),
        ),
        // 漫画页面
        _buildScrollableContent(
          context, isDark, currentTab, safeTop,
          child: const ComicListContent(),
        ),
        // 笔记页面
        _buildScrollableContent(
          context, isDark, currentTab, safeTop,
          child: const NoteListContent(),
        ),
      ],
    );

  /// 构建带大标题的可滚动内容 - 标题和内容一起滚动
  Widget _buildScrollableContent(
    BuildContext context,
    bool isDark,
    int currentTab,
    double safeTop, {
    required Widget child,
  }) {
    return CustomScrollView(
      slivers: [
        // 顶部安全区留白
        SliverPadding(
          padding: EdgeInsets.only(top: safeTop + 8),
          sliver: const SliverToBoxAdapter(child: SizedBox.shrink()),
        ),
        // 大标题 - 作为 Sliver 可以滚动
        SliverToBoxAdapter(
          child: _buildLargeTitle(context, isDark, currentTab, hasFloatingButtons: true),
        ),
        // 内容填充剩余空间
        SliverFillRemaining(
          hasScrollBody: true,
          child: child,
        ),
      ],
    );
  }

  /// iOS 26 大标题区域（非 Sliver 版本）
  Widget _buildLargeTitle(
    BuildContext context,
    bool isDark,
    int currentTab, {
    bool hasFloatingButtons = false,
  }) {
    // 获取各类数据统计
    final bookState = ref.watch(bookListProvider);
    final comicState = ref.watch(comicListProvider);
    final noteState = ref.watch(notePageProvider);

    final bookCount = bookState is BookListLoaded ? bookState.totalCount : 0;
    final comicCount = comicState is ComicListLoaded ? comicState.comics.length : 0;
    final noteCount = noteState is NotePageLoaded ? _countNotes(noteState.treeNodes) : 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 大标题 - 需要避开浮动按钮
          Padding(
            padding: EdgeInsets.only(right: hasFloatingButtons ? 150 : 0),
            child: Text(
              _getGreeting(),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 统计信息 - 横向排列
          Row(
            children: [
              _buildStatChip(
                icon: Icons.menu_book_rounded,
                label: '$bookCount 本',
                color: Colors.amber[700]!,
                isDark: isDark,
                isActive: currentTab == 0,
              ),
              const SizedBox(width: 12),
              _buildStatChip(
                icon: Icons.collections_bookmark_rounded,
                label: '$comicCount 部',
                color: Colors.orange[600]!,
                isDark: isDark,
                isActive: currentTab == 1,
              ),
              const SizedBox(width: 12),
              _buildStatChip(
                icon: Icons.note_alt_rounded,
                label: '$noteCount 篇',
                color: Colors.green[600]!,
                isDark: isDark,
                isActive: currentTab == 2,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 统计信息小标签
  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    bool isActive = false,
  }) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: isActive ? color : (isDark ? Colors.grey[500] : Colors.grey[400])),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: isActive
                ? (isDark ? Colors.white : Colors.black87)
                : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
          ),
        ),
      ],
    );

  /// 计算笔记数量（只计算文件，不计算文件夹）
  int _countNotes(List<NoteTreeNode> nodes) {
    var count = 0;
    for (final node in nodes) {
      if (node.type == NoteTreeNodeType.file) {
        count++;
      }
      if (node.children.isNotEmpty) {
        count += _countNotes(node.children);
      }
    }
    return count;
  }

  Widget _buildAppBar(BuildContext context, bool isDark, int currentTab) {
    final uiStyle = ref.watch(uiStyleProvider);

    // 玻璃模式下的染色
    final tintColor = uiStyle.isGlass
        ? (isDark
            ? Colors.amber.withValues(alpha: 0.15)
            : Colors.amber.withValues(alpha: 0.08))
        : null;

    // 当搜索栏显示且是图书模式时，需要更高的高度来容纳模式切换
    final headerHeight = (_showSearch && currentTab == 0) ? 110.0 : 84.0;

    return AdaptiveGlassHeader(
      height: headerHeight,
      backgroundColor: uiStyle.isGlass
          ? tintColor
          : (isDark
              ? const Color(0xFF2E2A1A) // 深琥珀棕色调
              : Colors.amber.withValues(alpha: 0.08)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 16, 16),
        child: Row(
          children: [
            // 问候语和当前类型标题（搜索时隐藏）
            if (!_showSearch)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getGreeting(),
                      style: context.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          ReadingContentType.values[currentTab].icon,
                          size: 14,
                          color: Colors.amber[700],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          ReadingContentType.values[currentTab].label,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            // 搜索栏或操作按钮组
            if (_showSearch)
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 搜索栏 - 与照片页面完全一致的简单 Row 样式
                    Row(
                      children: [
                        // 返回按钮
                        IconButton(
                          onPressed: () {
                            _closeSearch(currentTab);
                          },
                          icon: Icon(
                            Icons.arrow_back,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        // 搜索输入框
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                            decoration: InputDecoration(
                              hintText: currentTab == 0 && _bookSearchMode == BookSearchMode.online
                                  ? '搜索书源...'
                                  : '搜索${ReadingContentType.values[currentTab].label}...',
                              hintStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[400]),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            textInputAction: TextInputAction.search,
                            onChanged: (value) {
                              setState(() {});
                              _performSearch(value, currentTab);
                            },
                            onSubmitted: (value) {
                              debugPrint('📚 onSubmitted: value="$value", currentTab=$currentTab, _bookSearchMode=$_bookSearchMode');
                              if (currentTab == 0 && _bookSearchMode == BookSearchMode.online) {
                                _performOnlineSearch(value);
                              } else {
                                _performSearch(value, currentTab);
                              }
                            },
                          ),
                        ),
                        // 清除按钮
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                              _performSearch('', currentTab);
                              ref.read(bookSearchProvider.notifier).clear();
                            },
                            icon: Icon(
                              Icons.close,
                              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    // 图书模式下显示本地/书源切换
                    if (currentTab == 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 12, top: 8),
                        child: Row(
                          children: [
                            ...BookSearchMode.values.map((mode) {
                              final isSelected = _bookSearchMode == mode;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() => _bookSearchMode = mode);
                                    // 切换模式时清空搜索结果（保留输入内容）
                                    ref.read(bookListProvider.notifier).setSearchQuery('');
                                    ref.read(bookSearchProvider.notifier).clear();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? (isDark ? Colors.amber.withValues(alpha: 0.3) : Colors.amber.withValues(alpha: 0.2))
                                          : (isDark ? Colors.grey[800] : Colors.grey[200]),
                                      borderRadius: BorderRadius.circular(12),
                                      border: isSelected
                                          ? Border.all(color: Colors.amber, width: 1.5)
                                          : null,
                                    ),
                                    child: Text(
                                      mode.label,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                        color: isSelected
                                            ? Colors.amber[700]
                                            : (isDark ? Colors.white70 : Colors.black54),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                            // 书源模式下额外显示搜索按钮
                            if (_bookSearchMode == BookSearchMode.online && _searchController.text.isNotEmpty)
                              GestureDetector(
                                onTap: () {
                                  debugPrint('📚 Search button tapped');
                                  _performOnlineSearch(_searchController.text);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.amber,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.search_rounded, size: 14, color: Colors.white),
                                      SizedBox(width: 4),
                                      Text(
                                        '搜索',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              )
            else
              GlassButtonGroup(
                children: [
                  // 搜索按钮
                  GlassGroupIconButton(
                    icon: Icons.search_rounded,
                    tooltip: '搜索',
                    onPressed: () => _triggerSearch(currentTab),
                  ),
                  // 本地/在线切换按钮（仅在图书页显示）
                  if (currentTab == 0)
                    GlassGroupIconButton(
                      icon: _bookSearchMode == BookSearchMode.online 
                          ? Icons.cloud_rounded 
                          : Icons.folder_rounded,
                      tooltip: _bookSearchMode == BookSearchMode.online 
                          ? '查看本地图书' 
                          : '查看在线书架',
                      onPressed: () {
                        setState(() {
                          _bookSearchMode = _bookSearchMode == BookSearchMode.online 
                              ? BookSearchMode.local 
                              : BookSearchMode.online;
                        });
                      },
                    ),
                  // 类型切换按钮
                  GlassGroupDynamicButton(
                    icon: ReadingContentType.values[currentTab].icon,
                    tooltip: '切换内容类型',
                    showDropdownIndicator: true,
                    onPressed: () => _showTypeSwitcherMenu(context, isDark, currentTab),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// 触发搜索
  void _triggerSearch(int currentTab) {
    setState(() => _showSearch = true);
  }

  /// 关闭搜索
  void _closeSearch(int currentTab) {
    setState(() => _showSearch = false);
    _searchController.clear();
    // 清空搜索结果
    switch (currentTab) {
      case 0: // 图书
        ref.read(bookListProvider.notifier).setSearchQuery('');
        ref.read(bookSearchProvider.notifier).clear();
      case 1: // 漫画
        ref.read(comicListProvider.notifier).setSearchQuery('');
      case 2: // 笔记
        // 笔记暂不支持搜索
        break;
    }
  }

  /// 执行搜索
  void _performSearch(String query, int currentTab) {
    switch (currentTab) {
      case 0: // 图书
        if (_bookSearchMode == BookSearchMode.local) {
          ref.read(bookListProvider.notifier).setSearchQuery(query);
        } else {
          // 书源搜索 - 只在按回车时触发
          // onChanged会频繁调用，所以这里不执行书源搜索
        }
      case 1: // 漫画
        ref.read(comicListProvider.notifier).setSearchQuery(query);
      case 2: // 笔记
        ref.read(notePageProvider.notifier).setSearchQuery(query);
    }
  }

  /// 执行书源搜索（按回车时调用）
  void _performOnlineSearch(String query) {
    debugPrint('📚 _performOnlineSearch called with query: "$query"');
    if (query.trim().isEmpty) {
      debugPrint('📚 _performOnlineSearch: query is empty, returning');
      return;
    }
    debugPrint('📚 _performOnlineSearch: calling bookSearchProvider.search()');
    ref.read(bookSearchProvider.notifier).search(query.trim());
  }

  /// 触发刷新
  void _triggerRefresh(int currentTab) {
    switch (currentTab) {
      case 0: // 图书
        ref.read(bookListProvider.notifier).forceRefresh();
      case 1: // 漫画
        ref.read(comicListProvider.notifier).forceRefresh();
      case 2: // 笔记
        ref.read(notePageProvider.notifier).loadTree();
    }
  }

  /// 显示类型切换菜单
  void _showTypeSwitcherMenu(BuildContext context, bool isDark, int currentTab) {
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final screenWidth = MediaQuery.of(context).size.width;

    showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        screenWidth - 200,
        offset.dy + 50,
        16,
        0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: ReadingContentType.values.asMap().entries.map((entry) {
        final index = entry.key;
        final type = entry.value;
        final isSelected = index == currentTab;

        return PopupMenuItem<int>(
          value: index,
          child: Row(
            children: [
              Icon(
                type.icon,
                size: 20,
                color: isSelected
                    ? AppColors.primary
                    : (isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[600]),
              ),
              const SizedBox(width: 12),
              Text(
                type.label,
                style: TextStyle(
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? AppColors.darkOnSurface : Colors.black87),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              if (isSelected) ...[
                const Spacer(),
                Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
              ],
            ],
          ),
        );
      }).toList(),
    ).then((value) {
      if (value != null) {
        _onTabChanged(value);
      }
    });
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return '夜深了';
    if (hour < 9) return '早上好';
    if (hour < 12) return '上午好';
    if (hour < 14) return '中午好';
    if (hour < 18) return '下午好';
    if (hour < 22) return '晚上好';
    return '夜深了';
  }

  Widget _buildTypeSwitcher(BuildContext context, bool isDark, int currentTab) {
    final uiStyle = ref.watch(uiStyleProvider);

    final popupButton = PopupMenuButton<int>(
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: EdgeInsets.zero,
      itemBuilder: (context) => ReadingContentType.values.asMap().entries.map((entry) {
        final index = entry.key;
        final type = entry.value;
        final isSelected = index == currentTab;

        return PopupMenuItem<int>(
          value: index,
          child: Row(
            children: [
              Icon(
                type.icon,
                size: 20,
                color: isSelected
                    ? AppColors.primary
                    : (isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[600]),
              ),
              const SizedBox(width: 12),
              Text(
                type.label,
                style: TextStyle(
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? AppColors.darkOnSurface : Colors.black87),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              if (isSelected) ...[
                const Spacer(),
                Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
              ],
            ],
          ),
        );
      }).toList(),
      onSelected: _onTabChanged,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ReadingContentType.values[currentTab].icon,
            size: 22,
            color: isDark ? Colors.white : Colors.black87,
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.arrow_drop_down_rounded,
            size: 20,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ],
      ),
    );

    // 玻璃模式下使用浮动玻璃按钮样式
    if (uiStyle.isGlass) {
      final glassStyle = GlassTheme.getStyle(uiStyle, isDark: isDark);
      final bgColor = isDark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.black.withValues(alpha: 0.06);
      final borderColor = isDark
          ? Colors.white.withValues(alpha: glassStyle.borderOpacity * 0.8)
          : Colors.black.withValues(alpha: glassStyle.borderOpacity * 0.4);

      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor, width: 0.5),
            ),
            child: popupButton,
          ),
        ),
      );
    }

    // 经典模式
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
          ),
          child: popupButton,
        ),
      ),
    );
  }
}
