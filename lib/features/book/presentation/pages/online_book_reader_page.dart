import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/debug_log.dart';
import 'package:my_nas/features/book/data/services/native_online_paginator.dart';
import 'package:my_nas/features/book/domain/entities/book_source.dart';
import 'package:my_nas/features/book/presentation/providers/book_search_provider.dart';
import 'package:my_nas/features/book/presentation/providers/tts_provider.dart';
import 'package:my_nas/features/book/presentation/widgets/floating_tts_control.dart';
import 'package:my_nas/features/book/presentation/widgets/online_page_content.dart';
import 'package:my_nas/features/reading/data/services/reader_settings_service.dart';
import 'package:my_nas/features/reading/presentation/providers/reader_settings_provider.dart';
import 'package:my_nas/features/reading/presentation/widgets/page_flip_effect.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/utils/form_l10n.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/reader_settings_sheet.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 在线书籍阅读页面
///
/// 使用原生 Flutter 渲染，支持分页、翻页效果、主题切换等高级功能。
class OnlineBookReaderPage extends ConsumerStatefulWidget {
  const OnlineBookReaderPage({
    super.key,
    required this.book,
    required this.chapters,
    required this.initialChapter,
  });

  final OnlineBook book;
  final List<OnlineChapter> chapters;
  final OnlineChapter initialChapter;

  @override
  ConsumerState<OnlineBookReaderPage> createState() =>
      _OnlineBookReaderPageState();
}

class _OnlineBookReaderPageState extends ConsumerState<OnlineBookReaderPage>
    with TabBarVisibilityMixin {
  // 章节状态
  late int _currentChapterIndex;
  String? _chapterContent;
  bool _isLoading = false;
  String? _error;

  // 分页状态
  final _paginator = NativeOnlinePaginator.instance;
  List<OnlineBookPage> _pages = [];
  int _currentPageIndex = 0;
  int _contentLoadGeneration = 0;
  int _paginationGeneration = 0;
  final PageController _pageController = PageController();

  // UI 状态
  bool _showControls = false;
  bool _showTTS = false;
  bool _userClosedTTS = false;

  // 防抖保存进度
  Timer? _saveProgressTimer;

  @override
  void initState() {
    super.initState();
    hideTabBar();
    _currentChapterIndex = widget.chapters.indexOf(widget.initialChapter);
    if (_currentChapterIndex == -1) _currentChapterIndex = 0;
    _loadContent();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initWakelock();
  }

  Future<void> _initWakelock() async {
    final settings = ref.read(bookReaderSettingsProvider);
    if (settings.keepScreenOn) {
      await WakelockPlus.enable();
    }
  }

  @override
  void dispose() {
    _saveProgressTimer?.cancel();
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _loadContent() async {
    final chapterIndex = _currentChapterIndex;
    if (chapterIndex < 0 || chapterIndex >= widget.chapters.length) {
      return;
    }
    final loadGeneration = ++_contentLoadGeneration;
    // 章节一旦切换，立即作废旧章节仍在运行的分页任务。
    _paginationGeneration++;

    setState(() {
      _isLoading = true;
      _error = null;
      _chapterContent = null;
      _pages = [];
      _currentPageIndex = 0;
    });

    try {
      final contentService = ref.read(bookContentServiceProvider);
      final content = await contentService.getChapterContent(
        widget.book.source,
        widget.chapters[chapterIndex],
      );

      if (!mounted ||
          loadGeneration != _contentLoadGeneration ||
          chapterIndex != _currentChapterIndex) {
        return;
      }

      if (content == null || content.isEmpty) {
        setState(() {
          _error = context.l10n.bookReaderErrorFailedLoadContent;
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _chapterContent = content;
      });

      // 延迟分页，等待布局完成
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            loadGeneration == _contentLoadGeneration &&
            chapterIndex == _currentChapterIndex) {
          _paginateContent(
            content: content,
            chapterIndex: chapterIndex,
            contentLoadGeneration: loadGeneration,
          );
        }
      });
    } catch (e, st) {
      debugLog('[阅读器] 加载异常: $e\n$st');
      if (mounted &&
          loadGeneration == _contentLoadGeneration &&
          chapterIndex == _currentChapterIndex) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _paginateContent({
    String? content,
    int? chapterIndex,
    int? contentLoadGeneration,
  }) async {
    final targetContent = content ?? _chapterContent;
    if (targetContent == null || targetContent.isEmpty) return;
    final targetChapterIndex = chapterIndex ?? _currentChapterIndex;
    final expectedContentGeneration =
        contentLoadGeneration ?? _contentLoadGeneration;
    final generation = ++_paginationGeneration;

    final settings = ref.read(bookReaderSettingsProvider);
    final size = MediaQuery.of(context).size;

    // 计算实际可用区域（减去固定Header/Footer）
    final headerHeight = 40.0;
    final footerHeight = settings.showProgress ? 32.0 : 0.0;
    final safeArea = MediaQuery.of(context).padding;
    final availableHeight =
        size.height -
        headerHeight -
        footerHeight -
        safeArea.top -
        safeArea.bottom;

    try {
      final result = await _paginator.paginateChapter(
        content: targetContent,
        chapterIndex: targetChapterIndex,
        viewportSize: Size(size.width, availableHeight),
        baseStyle: TextStyle(
          fontSize: settings.fontSize,
          height: settings.lineHeight,
        ),
        horizontalPadding: settings.horizontalPadding,
        verticalPadding: settings.verticalPadding,
      );

      if (!mounted ||
          generation != _paginationGeneration ||
          expectedContentGeneration != _contentLoadGeneration ||
          targetChapterIndex != _currentChapterIndex) {
        return;
      }

      setState(() {
        _pages = result.pages;
        _currentPageIndex = 0;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted ||
          generation != _paginationGeneration ||
          expectedContentGeneration != _contentLoadGeneration ||
          targetChapterIndex != _currentChapterIndex) {
        return;
      }
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _pages = [];
      });
      return;
    }

    // 重置 PageController
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
  }

  void _goToPage(int page) {
    final targetPage = page.clamp(0, _pages.length - 1);
    _pageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _previousChapter() {
    if (_currentChapterIndex > 0) {
      setState(() => _currentChapterIndex--);
      _loadContent();
    }
  }

  void _nextChapter() {
    if (_currentChapterIndex < widget.chapters.length - 1) {
      setState(() => _currentChapterIndex++);
      _loadContent();
    }
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  Future<void> _startTTS() async {
    if (_pages.isEmpty) return;

    final ttsNotifier = ref.read(ttsProvider.notifier);
    await ttsNotifier.init();

    // 获取当前页面的文本内容
    final currentContent = _pages[_currentPageIndex].content;
    if (currentContent.isEmpty) return;

    // 按段落分割
    final paragraphs = currentContent
        .split(RegExp(r'\n\n+'))
        .where((p) => p.trim().isNotEmpty)
        .toList();

    _userClosedTTS = false;
    setState(() => _showTTS = true);

    await ttsNotifier.speakParagraphs(
      paragraphs,
      onParagraphChanged: (paragraphIndex) {
        debugLog('TTS: 当前段落 $paragraphIndex');
      },
      onAllComplete: () {
        final settings = ref.read(ttsProvider).settings;
        // 自动翻页或切换章节
        if (!_userClosedTTS && settings.autoPlayNextChapter) {
          if (_currentPageIndex < _pages.length - 1) {
            _goToPage(_currentPageIndex + 1);
            Future.delayed(const Duration(milliseconds: 300), _startTTS);
          } else if (_currentChapterIndex < widget.chapters.length - 1) {
            _nextChapter();
            Future.delayed(const Duration(milliseconds: 500), _startTTS);
          }
        }
      },
    );
  }

  void _showChapterList() {
    showAdaptiveModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => _ChapterListSheet(
          chapters: widget.chapters,
          currentIndex: _currentChapterIndex,
          scrollController: scrollController,
          onSelect: (index) {
            Navigator.pop(context);
            setState(() => _currentChapterIndex = index);
            _loadContent();
          },
        ),
      ),
    );
  }

  void _showSettingsSheet() {
    showReaderSettingsSheet(
      context,
      title: context.l10n.bookReaderSettingsTitle,
      icon: Icons.settings_rounded,
      contentBuilder: (context) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(bookReaderSettingsProvider);
          return _buildSettingsContent(settings);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(bookReaderSettingsProvider);
    final currentChapter = widget.chapters[_currentChapterIndex];

    return Scaffold(
      backgroundColor: settings.theme.backgroundColor,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            // 内容区域
            _buildContent(settings),
            // 控制栏
            if (_showControls) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildTopBar(settings, currentChapter),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomBar(settings),
              ),
            ],
            // TTS 浮动控制栏
            if (_showTTS)
              FloatingTTSControl(
                onClose: () {
                  _userClosedTTS = true;
                  setState(() => _showTTS = false);
                },
                backgroundColor: settings.theme.backgroundColor,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BookReaderSettings settings) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: settings.theme.textColor),
            const SizedBox(height: 16),
            Text(
              context.l10n.bookReaderLoadingState,
              style: TextStyle(color: settings.theme.textColor),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              context.l10n.bookReaderLoadFailedState,
              style: TextStyle(color: settings.theme.textColor),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: Text(context.l10n.bookReaderButtonBack),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _loadContent,
                  child: Text(context.l10n.bookReaderButtonRetry),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (_pages.isEmpty) {
      return Center(
        child: Text(
          context.l10n.bookReaderEmptyContent,
          style: TextStyle(
            color: settings.theme.textColor.withValues(alpha: 0.7),
          ),
        ),
      );
    }

    // 判断是否使用翻页效果
    final useFlipEffect =
        settings.pageTurnMode == BookPageTurnMode.simulation ||
        settings.pageTurnMode == BookPageTurnMode.cover;

    Widget pageView = PageView.builder(
      controller: _pageController,
      physics: useFlipEffect ? const NeverScrollableScrollPhysics() : null,
      itemCount: _pages.length,
      onPageChanged: (page) {
        setState(() => _currentPageIndex = page);
      },
      itemBuilder: (context, index) =>
          SimplePageContent(content: _pages[index].content, settings: settings),
    );

    // 包装翻页效果
    if (useFlipEffect) {
      pageView = PageFlipEffect(
        mode: settings.pageTurnMode == BookPageTurnMode.simulation
            ? PageFlipMode.simulation
            : PageFlipMode.cover,
        backgroundColor: settings.theme.backgroundColor,
        onNextPage: () async {
          if (_currentPageIndex < _pages.length - 1) {
            _goToPage(_currentPageIndex + 1);
          } else if (_currentChapterIndex < widget.chapters.length - 1) {
            _nextChapter();
          }
        },
        onPrevPage: () async {
          if (_currentPageIndex > 0) {
            _goToPage(_currentPageIndex - 1);
          } else if (_currentChapterIndex > 0) {
            _previousChapter();
          }
        },
        onTap: (details) => _toggleControls(),
        child: pageView,
      );
    }

    return SafeArea(
      child: Column(
        children: [
          // 固定顶栏
          _buildFixedHeader(settings),
          // 翻页内容
          Expanded(child: pageView),
          // 固定底栏
          if (settings.showProgress) _buildFixedFooter(settings),
        ],
      ),
    );
  }

  Widget _buildFixedHeader(BookReaderSettings settings) {
    final textColor = settings.theme.textColor.withValues(alpha: 0.5);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.chapters[_currentChapterIndex].name,
              style: TextStyle(color: textColor, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${_currentPageIndex + 1}/${_pages.length}',
            style: TextStyle(color: textColor, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildFixedFooter(BookReaderSettings settings) {
    final textColor = settings.theme.textColor.withValues(alpha: 0.5);
    final progress = _pages.isNotEmpty
        ? ((_currentPageIndex + 1) / _pages.length * 100).toStringAsFixed(1)
        : '0.0';
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            context.l10n.bookReaderPageDisplay(_currentPageIndex + 1),
            style: TextStyle(color: textColor, fontSize: 11),
          ),
          Text('$progress%', style: TextStyle(color: textColor, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildTopBar(BookReaderSettings settings, OnlineChapter chapter) =>
      Container(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
          ),
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            chapter.name,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.list_rounded, color: Colors.white),
              onPressed: _showChapterList,
              tooltip: context.l10n.bookReaderTableOfContentsTooltip,
            ),
          ],
        ),
      );

  Widget _buildBottomBar(BookReaderSettings settings) {
    final isDark =
        settings.theme == BookReaderTheme.dark ||
        settings.theme == BookReaderTheme.black;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 进度条
              if (_pages.isNotEmpty)
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    overlayColor: Colors.white24,
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                  ),
                  child: Slider(
                    value: _currentPageIndex.toDouble(),
                    min: 0,
                    max: (_pages.length - 1).toDouble().clamp(
                      0,
                      double.infinity,
                    ),
                    onChanged: (value) => _goToPage(value.round()),
                  ),
                ),
              // 页码
              Text(
                '${_currentPageIndex + 1} / ${_pages.length}',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 12),
              // 控制按钮 - 与本地阅读器一致（4个按钮）
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _BottomBarButton(
                    icon: Icons.menu_book_rounded,
                    label: context.l10n.bookReaderTableOfContentsButton,
                    isDark: isDark,
                    onPressed: _showChapterList,
                  ),
                  _BottomBarButton(
                    icon: Icons.headphones_rounded,
                    label: context.l10n.bookReaderReadAloudButton,
                    isDark: isDark,
                    onPressed: _startTTS,
                  ),
                  _BottomBarButton(
                    icon: isDark ? Icons.light_mode : Icons.dark_mode,
                    label: isDark
                        ? context.l10n.bookReaderDayModeButton
                        : context.l10n.bookReaderNightModeButton,
                    isDark: isDark,
                    onPressed: () {
                      final notifier = ref.read(
                        bookReaderSettingsProvider.notifier,
                      );
                      final newTheme = isDark
                          ? BookReaderTheme.light
                          : BookReaderTheme.dark;
                      notifier.setTheme(newTheme);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _paginateContent();
                      });
                    },
                  ),
                  _BottomBarButton(
                    icon: Icons.settings_rounded,
                    label: context.l10n.bookReaderSettingsButton,
                    isDark: isDark,
                    onPressed: _showSettingsSheet,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsContent(BookReaderSettings settings) {
    final settingsNotifier = ref.read(bookReaderSettingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 字体大小
        SettingSliderRow(
          label: context.l10n.bookReaderFontSizeLabel,
          value: settings.fontSize,
          min: 12,
          max: 36,
          divisions: 12,
          valueLabel: '${settings.fontSize.toInt()}',
          onChanged: (value) {
            settingsNotifier.setFontSize(value);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _paginateContent();
            });
          },
        ),
        const SizedBox(height: 16),

        // 行高
        SettingSliderRow(
          label: context.l10n.bookReaderLineHeightLabel,
          value: settings.lineHeight,
          min: 1,
          max: 3,
          divisions: 20,
          onChanged: (value) {
            settingsNotifier.setLineHeight(value);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _paginateContent();
            });
          },
        ),
        const SizedBox(height: 16),

        // 页边距
        SettingSliderRow(
          label: context.l10n.bookReaderHorizontalPaddingLabel,
          value: settings.horizontalPadding,
          min: 8,
          max: 64,
          divisions: 14,
          valueLabel: '${settings.horizontalPadding.toInt()}',
          onChanged: (value) {
            settingsNotifier.setHorizontalPadding(value);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _paginateContent();
            });
          },
        ),
        const SizedBox(height: 24),

        // 阅读主题
        SettingSectionTitle(title: context.l10n.bookReaderThemeSectionTitle),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: BookReaderTheme.values
                .map(
                  (theme) => Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _buildThemeOption(
                      theme: theme,
                      isSelected: settings.theme == theme,
                      onTap: () {
                        settingsNotifier.setTheme(theme);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _paginateContent();
                        });
                      },
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 24),

        // 翻页模式
        SettingSectionTitle(
          title: context.l10n.bookReaderPageTurnModeSectionTitle,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildPageModeChip(
              context.l10n.bookReaderPageTurnModeSlide,
              BookPageTurnMode.slide,
              settings,
              settingsNotifier,
            ),
            _buildPageModeChip(
              context.l10n.bookReaderPageTurnModeCover,
              BookPageTurnMode.cover,
              settings,
              settingsNotifier,
            ),
            _buildPageModeChip(
              context.l10n.bookReaderPageTurnModeSimulation,
              BookPageTurnMode.simulation,
              settings,
              settingsNotifier,
            ),
            _buildPageModeChip(
              context.l10n.bookReaderPageTurnModeNone,
              BookPageTurnMode.none,
              settings,
              settingsNotifier,
            ),
          ],
        ),
        const SizedBox(height: 24),

        // 其他设置
        SettingSectionTitle(
          title: context.l10n.bookReaderOtherSettingsSectionTitle,
        ),
        SettingSwitchRow(
          title: context.l10n.bookReaderKeepScreenOnToggle,
          value: settings.keepScreenOn,
          onChanged: (value) {
            settingsNotifier.setKeepScreenOn(value: value);
            if (value) {
              WakelockPlus.enable();
            } else {
              WakelockPlus.disable();
            }
          },
        ),
        SettingSwitchRow(
          title: context.l10n.bookReaderShowProgressToggle,
          value: settings.showProgress,
          onChanged: (value) {
            settingsNotifier.setShowProgress(value: value);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _paginateContent();
            });
          },
        ),
      ],
    );
  }

  Widget _buildThemeOption({
    required BookReaderTheme theme,
    required bool isSelected,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected
              ? AppColors.primary
              : Colors.grey.withValues(alpha: 0.3),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Center(
        child: Text(
          localizeFormText(context, theme.label),
          style: TextStyle(
            color: theme.textColor,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    ),
  );

  Widget _buildPageModeChip(
    String label,
    BookPageTurnMode mode,
    BookReaderSettings settings,
    BookReaderSettingsNotifier notifier,
  ) {
    final isSelected = settings.pageTurnMode == mode;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => notifier.setPageTurnMode(mode),
    );
  }
}

/// 底部控制栏按钮（与本地阅读器一致）
class _BottomBarButton extends StatelessWidget {
  const _BottomBarButton({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const color = Colors.white;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

/// 章节列表弹框
class _ChapterListSheet extends StatelessWidget {
  const _ChapterListSheet({
    required this.chapters,
    required this.currentIndex,
    required this.scrollController,
    required this.onSelect,
  });

  final List<OnlineChapter> chapters;
  final int currentIndex;
  final ScrollController scrollController;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // 拖拽指示器
          const SheetDragHandle(bottomPadding: 0),
          // 标题
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              context.l10n.bookReaderChapterListTitle,
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark
                    ? AppColors.darkOnSurface
                    : AppColors.lightOnSurface,
              ),
            ),
          ),
          // 章节列表
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              itemCount: chapters.length,
              itemBuilder: (context, index) {
                final chapter = chapters[index];
                final isSelected = index == currentIndex;
                return ListTile(
                  title: Text(
                    chapter.name,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : (isDark
                                ? AppColors.darkOnSurface
                                : AppColors.lightOnSurface),
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_rounded, color: AppColors.primary)
                      : null,
                  onTap: () => onSelect(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
