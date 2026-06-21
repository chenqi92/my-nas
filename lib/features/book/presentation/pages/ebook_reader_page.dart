import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foliate_viewer/flutter_foliate_viewer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/core/widgets/keyboard_shortcuts.dart';
import 'package:my_nas/features/book/data/services/book_file_cache_service.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/features/book/presentation/pages/epub_comic_reader_page.dart';
import 'package:my_nas/features/reading/data/services/reader_settings_service.dart';
import 'package:my_nas/features/reading/data/services/reading_progress_service.dart';
import 'package:my_nas/features/reading/presentation/providers/reader_settings_provider.dart';
import 'package:my_nas/features/reading/presentation/widgets/page_flip_effect.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/providers/bottom_nav_visibility_provider.dart';
import 'package:my_nas/shared/services/native_tab_bar_service.dart';
import 'package:my_nas/shared/widgets/lottie_loading.dart';
import 'package:my_nas/shared/widgets/reader_settings_sheet.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 电子书阅读器状态（支持 EPUB、MOBI、AZW3 等格式）
sealed class EbookReaderState {}

class EbookReaderLoading extends EbookReaderState {
  EbookReaderLoading({this.message = 'Loading...'});

  final String message;
}

class EbookReaderLoaded extends EbookReaderState {
  EbookReaderLoaded({required this.filePath});

  final String filePath;
}

class EbookReaderError extends EbookReaderState {
  EbookReaderError(this.message);

  final String message;
}

/// 电子书阅读器 Provider（支持 EPUB、MOBI、AZW3 等格式）
final ebookReaderProvider =
    StateNotifierProvider.family<EbookReaderNotifier, EbookReaderState, BookItem>(
      (ref, book) => EbookReaderNotifier(book, ref),
    );

class EbookReaderNotifier extends StateNotifier<EbookReaderState> {
  EbookReaderNotifier(this.book, this._ref) : super(EbookReaderLoading()) {
    _loadBook();
  }

  final BookItem book;
  final Ref _ref;
  final BookFileCacheService _cacheService = BookFileCacheService();

  Future<void> _loadBook() async {
    try {
      await _cacheService.init();

      // 检查缓存
      final cachedFile = await _cacheService.getCachedFile(
        book.sourceId,
        book.path,
      );

      if (cachedFile != null && await cachedFile.exists()) {
        state = EbookReaderLoaded(filePath: cachedFile.path);
        return;
      }

      // 从网络或本地加载
      final uri = Uri.parse(book.url);

      if (uri.scheme == 'file') {
        // 本地文件
        final localPath = uri.toFilePath();
        if (await File(localPath).exists()) {
          state = EbookReaderLoaded(filePath: localPath);
          return;
        }
        throw Exception('File not found');
      }

      // 网络文件 - 需要下载并缓存（流式写入避免内存问题）
      state = EbookReaderLoading(message: 'Downloading...');

      final fileSystem = _getFileSystem();
      if (fileSystem != null) {
        // 使用流式写入，避免大文件占用过多内存
        final savedFile = await _cacheService.saveToCacheFromStream(
          book.sourceId,
          book.path,
          () => fileSystem.getFileStream(book.path),
        );
        if (savedFile == null) {
          throw Exception('Unable to save cache file');
        }
        state = EbookReaderLoaded(filePath: savedFile.path);
      } else {
        throw Exception('Unable to access file system');
      }
    } on Exception catch (e, st) {
      logger.e('加载电子书失败', e, st);
      state = EbookReaderError('Load failed: $e');
    }
  }

  NasFileSystem? _getFileSystem() {
    if (book.sourceId == null) return null;
    final connections = _ref.read(activeConnectionsProvider);
    final connection = connections[book.sourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      return null;
    }
    return connection.adapter.fileSystem;
  }
}

/// 电子书阅读器页面（支持 EPUB、MOBI、AZW3 等格式）
class EbookReaderPage extends ConsumerStatefulWidget {
  const EbookReaderPage({
    required this.book,
    this.forceComicReader = false,
    super.key,
  });

  final BookItem book;
  /// 强制使用漫画阅读器（EPUB 转换后跳转到 EpubComicReaderPage）
  final bool forceComicReader;

  @override
  ConsumerState<EbookReaderPage> createState() => _EbookReaderPageState();
}

class _EbookReaderPageState extends ConsumerState<EbookReaderPage> {
  final FoliateController _controller = FoliateController();
  final ReadingProgressService _progressService = ReadingProgressService();

  FoliateBookInfo? _bookInfo;
  FoliateLocation? _currentLocation;
  bool _showControls = false;
  bool _showToc = false;
  String? _initialCfi;
  List<FoliateTocItem> _tocItems = [];

  // 时间和电池状态
  Timer? _clockTimer;
  DateTime _currentTime = DateTime.now();
  int _batteryLevel = 100;
  bool _isCharging = false;

  /// 展平的目录列表（包含层级深度信息）
  List<(FoliateTocItem, int)> get _flattenedTocItems {
    final result = <(FoliateTocItem, int)>[];
    void flatten(List<FoliateTocItem> items, int depth) {
      for (final item in items) {
        result.add((item, depth));
        if (item.subitems.isNotEmpty) {
          flatten(item.subitems, depth + 1);
        }
      }
    }
    flatten(_tocItems, 0);
    return result;
  }

  // 进度保存防抖
  Timer? _saveProgressTimer;
  FoliateLocation? _pendingLocation;
  static const _saveProgressDebounce = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    // 隐藏原生 Tab Bar（iOS 玻璃风格）
    NativeTabBarService.instance.setTabBarVisible(false);
    // 隐藏 Flutter 导航栏（经典风格）
    // 使用 addPostFrameCallback 延迟执行，避免在 widget 树构建期间修改 provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      BottomNavVisibilityNotifier.instance?.hide();
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initWakelock();
    _loadProgress();
    _initClockAndBattery();
  }

  Future<void> _initClockAndBattery() async {
    // 每分钟更新一次时间
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });

    // 获取电池状态
    await _updateBatteryStatus();
  }

  Future<void> _updateBatteryStatus() async {
    try {
      final battery = Battery();
      // 使用 dynamic 接收避免平台兼容性问题（macOS 可能返回 String）
      final dynamic levelValue = await battery.batteryLevel;
      final level = _parseBatteryLevel(levelValue);
      final state = await battery.batteryState;
      if (mounted) {
        setState(() {
          _batteryLevel = level;
          _isCharging = state == BatteryState.charging ||
              state == BatteryState.full;
        });
      }
      // 监听电池状态变化
      battery.onBatteryStateChanged.listen((state) {
        if (mounted) {
          setState(() {
            _isCharging = state == BatteryState.charging ||
                state == BatteryState.full;
          });
          // 状态变化时也更新电量（使用 try-catch 防止类型错误）
          AppError.fireAndForget(
            Future(() async {
              try {
                final dynamic levelValue = await battery.batteryLevel;
                if (mounted) {
                  setState(() {
                    _batteryLevel = _parseBatteryLevel(levelValue);
                  });
                }
              } catch (e) {
                // 忽略电池电量获取错误
              }
            }),
            action: 'updateBatteryLevel',
          );
        }
      });
    } catch (e, st) {
      // 电池 API 可能在某些平台不可用，或返回类型不匹配
      AppError.ignore(e, st, '电池状态获取失败，可能平台不支持');
    }
  }

  /// 安全解析电池电量值，处理不同平台可能返回不同类型的情况
  int _parseBatteryLevel(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 100;
    if (value is double) return value.toInt();
    return 100;
  }

  Future<void> _initWakelock() async {
    final settings = ref.read(bookReaderSettingsProvider);
    if (settings.keepScreenOn) {
      await WakelockPlus.enable();
    }
  }

  @override
  void dispose() {
    // 页面关闭时立即保存待保存的进度
    _saveProgressTimer?.cancel();
    _clockTimer?.cancel();
    if (_pendingLocation != null) {
      _saveProgressImmediately(_pendingLocation!);
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    // 恢复导航栏可见性（通过 Provider 引用计数，由 MainScaffold 决定实际状态）
    BottomNavVisibilityNotifier.instance?.show();
    super.dispose();
  }

  Future<void> _loadProgress() async {
    await _progressService.init();
    final itemId = _progressService.generateItemId(
      widget.book.sourceId ?? 'local',
      widget.book.path,
    );
    final progress = _progressService.getProgress(itemId);
    if (progress?.cfi != null && progress!.cfi!.isNotEmpty) {
      setState(() {
        _initialCfi = progress.cfi;
      });
    }
  }

  /// 防抖保存进度（800ms 内的多次变化只保存最后一次）
  void _saveProgressDebounced(FoliateLocation location) {
    _pendingLocation = location;
    _saveProgressTimer?.cancel();
    _saveProgressTimer = Timer(_saveProgressDebounce, () {
      if (_pendingLocation != null) {
        _saveProgressImmediately(_pendingLocation!);
        _pendingLocation = null;
      }
    });
  }

  /// 立即保存进度
  Future<void> _saveProgressImmediately(FoliateLocation location) async {
    final itemId = _progressService.generateItemId(
      widget.book.sourceId ?? 'local',
      widget.book.path,
    );
    await _progressService.saveProgress(
      ReadingProgress(
        itemId: itemId,
        itemType: 'mobi',
        position: location.fraction,
        totalPositions: 1,
        lastReadAt: DateTime.now(),
        cfi: location.cfi,
      ),
    );
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (!_showControls) {
        _showToc = false;
      }
    });
  }

  /// 开始朗读当前章节
  /// 注意: Foliate (WebView) 阅读器的文本提取有限
  /// 建议用户切换到原生阅读器获得更好的 TTS 体验
  Future<void> _startTTS() async {
    // 显示建议对话框
    final useNative = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.ebookReaderTtsDialogTitle),
        content: Text(context.l10n.ebookReaderTtsDialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.ebookReaderTtsDialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.ebookReaderTtsDialogSwitch),
          ),
        ],
      ),
    );

    if ((useNative ?? false) && mounted) {
      // 返回并提示用户在设置中切换阅读器
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.ebookReaderParserSwitchToNative),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// 从 BookReaderSettings 创建 FoliateStyle
  FoliateStyle _createStyle(BookReaderSettings settings) => FoliateStyle.fromReaderSettings(
      fontSize: settings.fontSize,
      lineHeight: settings.lineHeight,
      paragraphSpacing: settings.paragraphSpacing,
      horizontalPadding: settings.horizontalPadding,
      // 不需要内部垂直边距，因为已有固定顶栏(28px)和底栏(20px)
      verticalPadding: 0,
      backgroundColor: settings.theme.backgroundColor,
      textColor: settings.theme.textColor,
      fontFamily: settings.fontFamily,
      pageTurnStyle: _mapPageTurnMode(settings.pageTurnMode),
    );

  /// 应用设置变化
  Future<void> _applySettings(BookReaderSettings settings) async {
    final style = _createStyle(settings);
    await _controller.applyStyle(style);
  }

  /// 显示设置面板
  void _showSettingsSheet() {
    showReaderSettingsSheet(
      context,
      title: context.l10n.ebookReaderSettingsTitle,
      icon: Icons.settings_rounded,
      contentBuilder: (context) => Consumer(
          builder: (context, ref, _) {
            final settings = ref.watch(bookReaderSettingsProvider);
            return _buildSettingsContent(settings, context);
          },
        ),
    );
  }

  /// 将 BookPageTurnMode 映射到 FoliatePageTurnStyle
  /// - scroll: 水平翻页（分页模式，左右滑动切换页面）
  /// - slide: 连续滚动（无页面边界，上下拖动查看更多内容）
  /// - simulation: 仿真翻页（JS 层实现，带阴影卷曲效果）
  /// - cover: 覆盖翻页（JS 层实现，新页面滑入覆盖）
  /// - none: 无动画，点击翻页
  FoliatePageTurnStyle _mapPageTurnMode(BookPageTurnMode mode) => switch (mode) {
        BookPageTurnMode.scroll => FoliatePageTurnStyle.slide, // 水平翻页
        BookPageTurnMode.slide => FoliatePageTurnStyle.scroll, // 连续滚动
        // 仿真和覆盖由 foliate-js 的 paginator.js 处理
        BookPageTurnMode.simulation => FoliatePageTurnStyle.simulation,
        BookPageTurnMode.cover => FoliatePageTurnStyle.cover,
        BookPageTurnMode.none => FoliatePageTurnStyle.noAnimation,
      };

  // 翻页模式配置（标签已移至本地化）
  static const _pageTurnModeConfigs = [
    (icon: Icons.swap_horiz_rounded, localizationKey: 'ebookReaderPageTurnModeHorizontal', mode: BookPageTurnMode.scroll),
    (icon: Icons.swap_vert_rounded, localizationKey: 'ebookReaderPageTurnModeScroll', mode: BookPageTurnMode.slide),
    (icon: Icons.auto_stories_rounded, localizationKey: 'ebookReaderPageTurnModeSimulation', mode: BookPageTurnMode.simulation),
    (icon: Icons.flip_rounded, localizationKey: 'ebookReaderPageTurnModeCover', mode: BookPageTurnMode.cover),
    (icon: Icons.article_rounded, localizationKey: 'ebookReaderPageTurnModeNone', mode: BookPageTurnMode.none),
  ];

  /// 获取本地化后的翻页模式列表
  List<({IconData icon, String label, BookPageTurnMode mode})> _getLocalizedPageTurnModes(BuildContext context) => _pageTurnModeConfigs
        .map((config) => (
          icon: config.icon,
          label: _getPageTurnModeLabel(context, config.localizationKey),
          mode: config.mode,
        ))
        .toList();

  /// 根据 localization key 获取翻页模式标签
  String _getPageTurnModeLabel(BuildContext context, String key) => switch (key) {
    'ebookReaderPageTurnModeHorizontal' => context.l10n.ebookReaderPageTurnModeHorizontal,
    'ebookReaderPageTurnModeScroll' => context.l10n.ebookReaderPageTurnModeScroll,
    'ebookReaderPageTurnModeSimulation' => context.l10n.ebookReaderPageTurnModeSimulation,
    'ebookReaderPageTurnModeCover' => context.l10n.ebookReaderPageTurnModeCover,
    'ebookReaderPageTurnModeNone' => context.l10n.ebookReaderPageTurnModeNone,
    _ => key,
  };

  int _getPageTurnModeIndex(BookPageTurnMode mode) => switch (mode) {
        BookPageTurnMode.scroll => 0,
        BookPageTurnMode.slide => 1,
        BookPageTurnMode.simulation => 2,
        BookPageTurnMode.cover => 3,
        BookPageTurnMode.none => 4,
      };

  /// 判断是否使用 Flutter 层面的翻页效果
  /// 现在 simulation 和 cover 由 foliate-js 的 paginator.js 处理，所以返回 false
  // ignore: unused_element
  bool _useFlutterPageFlip(BookPageTurnMode mode) => false;

  Widget _buildSettingsContent(BookReaderSettings settings, BuildContext context) {
    final settingsNotifier = ref.read(bookReaderSettingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 翻页方式
        SettingSectionTitle(title: context.l10n.ebookReaderSettingPageTurnMode),
        SettingPageTurnModePicker(
          modes: _getLocalizedPageTurnModes(context)
              .map((m) => (icon: m.icon, label: m.label))
              .toList(),
          selectedIndex: _getPageTurnModeIndex(settings.pageTurnMode),
          onSelect: (index) {
            final mode = _pageTurnModeConfigs[index].mode;
            settingsNotifier.setPageTurnMode(mode);
            // 仿真和覆盖翻页由 Flutter 处理，Foliate 使用滑动模式
            _controller.setPageTurnStyle(_mapPageTurnMode(mode));
          },
        ),
        const SizedBox(height: 24),

        // 字体选择（注意：Foliate 仅支持系统字体）
        SettingSectionTitle(
          title: context.l10n.ebookReaderSettingFont,
          trailing: AvailableFonts.getDisplayName(settings.fontFamily),
        ),
        SettingFontPicker(
          selectedFont: settings.fontFamily,
          onSelect: (fontFamily) {
            settingsNotifier.setFontFamily(fontFamily);
            // 同时调用 setFontFamily 和 applyStyle 确保字体生效
            _controller.setFontFamily(fontFamily);
            _applySettings(settings.copyWith(fontFamily: fontFamily));
          },
        ),
        const SizedBox(height: 24),

        // 字体大小
        SettingSliderRow(
          label: context.l10n.ebookReaderSettingFontSize,
          value: settings.fontSize,
          min: 12,
          max: 36,
          divisions: 12,
          valueLabel: '${settings.fontSize.toInt()}',
          onChanged: (value) {
            settingsNotifier.setFontSize(value);
            _controller.setFontSize(value / 18.0);
          },
        ),
        const SizedBox(height: 16),

        // 行高
        SettingSliderRow(
          label: context.l10n.ebookReaderSettingLineHeight,
          value: settings.lineHeight,
          min: 1,
          max: 3,
          divisions: 20,
          onChanged: (value) {
            settingsNotifier.setLineHeight(value);
            _controller.setLineHeight(value);
          },
        ),
        const SizedBox(height: 16),

        // 段落间距
        SettingSliderRow(
          label: context.l10n.ebookReaderSettingParagraphSpacing,
          value: settings.paragraphSpacing,
          max: 3,
          divisions: 15,
          onChanged: (value) {
            settingsNotifier.setParagraphSpacing(value);
            _applySettings(settings.copyWith(paragraphSpacing: value));
          },
        ),
        const SizedBox(height: 16),

        // 页边距
        SettingSliderRow(
          label: context.l10n.ebookReaderSettingPageMargin,
          value: settings.horizontalPadding,
          min: 8,
          max: 64,
          divisions: 14,
          valueLabel: '${settings.horizontalPadding.toInt()}',
          onChanged: (value) {
            settingsNotifier.setHorizontalPadding(value);
            _applySettings(settings.copyWith(horizontalPadding: value));
          },
        ),
        const SizedBox(height: 24),

        // 阅读主题
        SettingSectionTitle(title: context.l10n.ebookReaderSettingTheme),
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
                        _applySettings(settings.copyWith(theme: theme));
                      },
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 24),

        // 其他设置
        SettingSectionTitle(title: context.l10n.ebookReaderSettingOther),
        SettingSwitchRow(
          title: context.l10n.ebookReaderSettingKeepScreenOn,
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
          title: context.l10n.ebookReaderSettingShowProgress,
          value: settings.showProgress,
          onChanged: (value) => settingsNotifier.setShowProgress(value: value),
        ),

      ],
    );
  }

  Widget _buildThemeOption({
    required BookReaderTheme theme,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: theme.backgroundColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? AppColors.primary
                    : (isDark ? Colors.grey.shade600 : Colors.grey.shade300),
                width: isSelected ? 3 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Text(
                'Aa',
                style: TextStyle(
                  color: theme.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            theme.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? Colors.white70 : Colors.black54),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建键盘快捷键映射
  Map<ShortcutKey, VoidCallback> _buildKeyboardShortcuts(BookReaderSettings settings) {
    final isDark = settings.theme == BookReaderTheme.dark ||
        settings.theme == BookReaderTheme.black;

    return {
      // 导航
      CommonShortcuts.previous: _controller.prevPage,
      CommonShortcuts.next: _controller.nextPage,
      CommonShortcuts.previousPage: _controller.prevPage,
      CommonShortcuts.nextPage: _controller.nextPage,
      CommonShortcuts.first: () => _controller.goToFraction(0),
      CommonShortcuts.last: () => _controller.goToFraction(1),

      // 控制栏切换
      CommonShortcuts.playPause: _toggleControls,
      CommonShortcuts.toggleControls: _toggleControls,

      // 夜间模式
      CommonShortcuts.mute: () {
        final notifier = ref.read(bookReaderSettingsProvider.notifier);
        final newTheme = isDark ? BookReaderTheme.light : BookReaderTheme.dark;
        notifier.setTheme(newTheme);
        _applySettings(settings.copyWith(theme: newTheme));
      },

      // 设置
      CommonShortcuts.settings: _showSettingsSheet,

      // 退出
      CommonShortcuts.escape: () => Navigator.pop(context),
      CommonShortcuts.back: () => Navigator.pop(context),
    };
  }

  /// 显示快捷键帮助
  void _showKeyboardHelp() {
    KeyboardShortcutsHelpDialog.show(
      context,
      title: context.l10n.ebookReaderKeyboardHelpTitle,
      shortcuts: [
        (key: '←', description: context.l10n.ebookReaderKeyboardPrevPage),
        (key: '→', description: context.l10n.ebookReaderKeyboardNextPage),
        (key: 'Page Up', description: context.l10n.ebookReaderKeyboardPrevPage),
        (key: 'Page Down', description: context.l10n.ebookReaderKeyboardNextPage),
        (key: 'Home', description: context.l10n.ebookReaderKeyboardHome),
        (key: 'End', description: context.l10n.ebookReaderKeyboardEnd),
        (key: 'Space', description: context.l10n.ebookReaderKeyboardToggleControls),
        (key: 'M', description: context.l10n.ebookReaderKeyboardToggleDarkMode),
        (key: ',', description: context.l10n.ebookReaderKeyboardOpenSettings),
        (key: 'Esc', description: context.l10n.ebookReaderKeyboardExit),
        (key: '?', description: context.l10n.ebookReaderKeyboardHelp),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ebookReaderProvider(widget.book));
    final settings = ref.watch(bookReaderSettingsProvider);

    // 如果需要强制使用漫画阅读器，在文件加载完成后重定向
    if (widget.forceComicReader && state is EbookReaderLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // 跳转到漫画阅读器
        Navigator.pushReplacement<void, void>(
          context,
          MaterialPageRoute(
            builder: (context) => EpubComicReaderPage(
              book: widget.book,
              epubFile: File(state.filePath),
            ),
          ),
        );
      });
      // 显示加载提示
      return Scaffold(
        backgroundColor: settings.theme.backgroundColor,
        body: LottieLoading.book(
          message: context.l10n.ebookReaderOpeningComicReader,
        ),
      );
    }

    return KeyboardShortcuts(
      shortcuts: {
        ..._buildKeyboardShortcuts(settings),
        CommonShortcuts.help: _showKeyboardHelp,
      },
      child: Scaffold(
        backgroundColor: settings.theme.backgroundColor,
        body: switch (state) {
          EbookReaderLoading(:final message) => LottieLoading.book(
            message: message,
          ),
          EbookReaderError(:final message) => _buildError(message),
          EbookReaderLoaded(:final filePath) => _buildReader(filePath, settings),
        },
      ),
    );
  }

  Widget _buildError(String message) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 64, color: AppColors.error),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: AppColors.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.ebookReaderErrorButtonReturn),
          ),
        ],
      ),
    );

  Widget _buildReader(String filePath, BookReaderSettings settings) {
    final style = _createStyle(settings);
    final isDark = settings.theme == BookReaderTheme.dark ||
        settings.theme == BookReaderTheme.black;
    final useFlutterFlip = _useFlutterPageFlip(settings.pageTurnMode);

    // 构建阅读器核心内容
    Widget readerContent = ColoredBox(
      color: settings.theme.backgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            // 固定顶栏 - 显示书名，避免摄像头遮挡
            _buildFixedHeader(settings, isDark),
            // 阅读器内容
            Expanded(
              child: FoliateViewer(
                controller: _controller,
                bookSource: FileBookSource(File(filePath)),
                initialCfi: _initialCfi,
                style: style,
                // 当使用 Flutter 翻页效果时，禁用 WebView 原生手势
                disableNativeGestures: useFlutterFlip,
                loadingWidget: LottieLoading.book(
                  message: context.l10n.ebookReaderLoadingDefault,
                ),
                onBookLoaded: (info) {
                  setState(() {
                    _bookInfo = info;
                  });
                },
                onTocLoaded: (toc) {
                  if (mounted) {
                    setState(() {
                      _tocItems = toc;
                    });
                  }
                },
                onLocationChanged: (location) {
                  setState(() {
                    _currentLocation = location;
                  });
                  _saveProgressDebounced(location);
                },
                onError: (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error)),
                  );
                },
                onFootnoteOpen: () {
                  // 脚注打开时隐藏控制栏
                  if (_showControls) {
                    setState(() {
                      _showControls = false;
                      _showToc = false;
                    });
                  }
                },
                onFootnoteClose: () {
                  // 脚注关闭时可以做一些处理
                },
              ),
            ),
            // 固定底栏 - 显示进度信息
            if (settings.showProgress) _buildFixedFooter(settings, isDark),
          ],
        ),
      ),
    );

    // 如果使用 Flutter 翻页效果，用 PageFlipEffect 包裹
    if (useFlutterFlip) {
      readerContent = PageFlipEffect(
        mode: settings.pageTurnMode == BookPageTurnMode.simulation
            ? PageFlipMode.simulation
            : PageFlipMode.cover,
        backgroundColor: settings.theme.backgroundColor,
        onNextPage: () async {
          await _controller.nextPage();
        },
        onPrevPage: () async {
          await _controller.prevPage();
        },
        onTap: (details) => _handleTapForFlipMode(details, settings),
        // WebView 已通过 disableNativeGestures 禁用原生手势
        child: readerContent,
      );
    }

    return Stack(
      children: [
        // 主内容区域
        readerContent,

        // 透明点击层 - 仅在非 Flutter 翻页模式时使用
        if (!useFlutterFlip)
          Positioned.fill(
            child: _buildTapZones(settings),
          ),

        // 顶部控制栏（可隐藏）
        if (_showControls) _buildTopBar(settings),

        // 底部控制栏（可隐藏）
        if (_showControls) _buildBottomBar(settings),

        // 目录抽屉
        if (_showToc) _buildTocDrawer(settings),
      ],
    );
  }

  /// 处理 Flutter 翻页模式下的点击事件
  /// 注意：PageFlipEffect 内部已处理左侧25%和右侧25%的点击翻页
  /// 这里只需要处理中间区域的切换控制栏
  void _handleTapForFlipMode(TapUpDetails details, BookReaderSettings settings) {
    // PageFlipEffect 只在中间 50% 区域触发 onTap 回调
    // 左侧 25% 和右侧 25% 的点击由 PageFlipEffect 内部处理翻页
    _toggleControls();
  }

  /// 获取当前章节标题（直接使用 book.js 传递的 chapterTitle）
  String? get _currentChapterTitle => _currentLocation?.chapterTitle;

  /// 固定顶栏 - 显示当前章节标题
  Widget _buildFixedHeader(BookReaderSettings settings, bool isDark) => SizedBox(
      height: 28,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                // 优先显示当前章节标题，否则显示书名
                _currentChapterTitle ?? _bookInfo?.title ?? widget.book.name,
                style: TextStyle(
                  color: (isDark ? Colors.white : Colors.black87)
                      .withValues(alpha: 0.5),
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

  /// 固定底栏 - 显示进度信息、时间和电池
  Widget _buildFixedFooter(BookReaderSettings settings, bool isDark) {
    final progress = _currentLocation?.fraction ?? 0.0;
    final chapterCurrentPage = _currentLocation?.chapterCurrentPage ?? 0;
    final chapterTotalPages = _currentLocation?.chapterTotalPages ?? 0;

    final textColor = (isDark ? Colors.white : Colors.black87).withValues(alpha: 0.5);
    const textStyle = TextStyle(fontSize: 11);

    // 格式化时间 HH:mm
    final timeString =
        '${_currentTime.hour.toString().padLeft(2, '0')}:${_currentTime.minute.toString().padLeft(2, '0')}';

    return SizedBox(
      height: 20,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // 左侧：当前章节页数 x/y + 整本书进度百分比
            if (chapterTotalPages > 0) ...[
              Text(
                '$chapterCurrentPage/$chapterTotalPages',
                style: textStyle.copyWith(color: textColor),
              ),
              const SizedBox(width: 12),
            ],
            Text(
              '${(progress * 100).toStringAsFixed(1)}%',
              style: textStyle.copyWith(color: textColor),
            ),
            const Spacer(),
            // 右侧：时间和电池
            Text(
              timeString,
              style: textStyle.copyWith(color: textColor),
            ),
            const SizedBox(width: 6),
            _buildBatteryIcon(isDark, textColor),
          ],
        ),
      ),
    );
  }

  /// 构建电池图标
  Widget _buildBatteryIcon(bool isDark, Color textColor) {
    final batteryColor = _isCharging
        ? AppColors.success
        : _batteryLevel <= 20
            ? AppColors.error
            : textColor;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isCharging)
          Icon(
            Icons.bolt,
            size: 10,
            color: AppColors.success,
          ),
        Container(
          width: 22,
          height: 10,
          decoration: BoxDecoration(
            border: Border.all(color: textColor, width: 1),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (_batteryLevel / 100).clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: batteryColor,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
        ),
        Container(
          width: 2,
          height: 5,
          margin: const EdgeInsets.only(left: 1),
          decoration: BoxDecoration(
            color: textColor,
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(1)),
          ),
        ),
        const SizedBox(width: 3),
        Text(
          '$_batteryLevel%',
          style: TextStyle(fontSize: 10, color: textColor),
        ),
      ],
    );
  }

  /// 判断是否需要点击区域翻页
  /// 滚动模式是连续滚动，不需要点击翻页
  /// 其他模式（无动画、滑动、仿真、覆盖）都需要支持点击侧边翻页
  bool _needsTapToTurn(BookPageTurnMode mode) =>
      mode != BookPageTurnMode.scroll;

  /// 三区域点击处理
  /// 使用 Listener 只监听点击，不拦截滑动手势，让 WebView 正常处理滑动翻页
  Widget _buildTapZones(BookReaderSettings settings) => Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _tapDownPosition = event.localPosition;
        _tapDownTime = DateTime.now();
      },
      onPointerUp: (event) {
        if (_tapDownPosition == null || _tapDownTime == null) return;

        final distance = (event.localPosition - _tapDownPosition!).distance;
        final duration = DateTime.now().difference(_tapDownTime!);

        // 快速点击且移动距离小，才视为点击（不是滑动）
        if (distance < 15 && duration.inMilliseconds < 300) {
          final screenWidth = MediaQuery.of(context).size.width;
          final tapX = _tapDownPosition!.dx;
          final ratio = tapX / screenWidth;

          // 是否需要点击翻页（滑动/滚动模式由 WebView 处理翻页）
          final needsTapTurn = _needsTapToTurn(settings.pageTurnMode);

          if (needsTapTurn && ratio < 0.25) {
            // 左侧 25%: 上一页（仅在无动画模式）
            _controller.prevPage();
          } else if (needsTapTurn && ratio > 0.75) {
            // 右侧 25%: 下一页（仅在无动画模式）
            _controller.nextPage();
          } else if (ratio >= 0.25 && ratio <= 0.75) {
            // 中间 50%: 切换控制栏
            _toggleControls();
          }
        }
        _tapDownPosition = null;
        _tapDownTime = null;
      },
      onPointerCancel: (event) {
        _tapDownPosition = null;
        _tapDownTime = null;
      },
      // 使用 IgnorePointer 确保不阻止手势传递给下层 WebView
      child: const IgnorePointer(child: SizedBox.expand()),
    );

  // 点击检测相关变量
  Offset? _tapDownPosition;
  DateTime? _tapDownTime;

  Widget _buildTopBar(BookReaderSettings settings) {
    final isDark = settings.theme == BookReaderTheme.dark ||
        settings.theme == BookReaderTheme.black;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              (isDark ? Colors.black : Colors.white).withValues(alpha: 0.95),
              (isDark ? Colors.black : Colors.white).withValues(alpha: 0.6),
              Colors.transparent,
            ],
            stops: const [0.0, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Text(
                  _bookInfo?.title ?? widget.book.name,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 占位，保持标题居中
              const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BookReaderSettings settings) {
    final progress = _currentLocation?.fraction ?? 0.0;
    final isDark = settings.theme == BookReaderTheme.dark ||
        settings.theme == BookReaderTheme.black;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              (isDark ? Colors.black : Colors.white).withValues(alpha: 0.95),
              (isDark ? Colors.black : Colors.white).withValues(alpha: 0.6),
              Colors.transparent,
            ],
            stops: const [0.0, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 章节导航和进度信息
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 上一章按钮
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () async {
                          final success = await _controller.goToPreviousSection();
                          if (success) {
                            AppError.fireAndForget(HapticFeedback.lightImpact(), action: 'ebookReader.haptic');
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chevron_left,
                                size: 28,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              Text(
                                context.l10n.ebookReaderButtonPreviousChapter,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 进度条
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 6,
                              activeTrackColor: isDark ? Colors.white : Colors.black87,
                              inactiveTrackColor: isDark
                                  ? Colors.white.withValues(alpha: 0.3)
                                  : Colors.black.withValues(alpha: 0.15),
                              thumbColor: isDark ? Colors.white : Colors.black87,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 8,
                                elevation: 2,
                              ),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                              trackShape: const RoundedRectSliderTrackShape(),
                            ),
                            child: Slider(
                              value: progress.clamp(0.0, 1.0),
                              onChanged: _controller.goToFraction,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 下一章按钮
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () async {
                          final success = await _controller.goToNextSection();
                          if (success) {
                            AppError.fireAndForget(HapticFeedback.lightImpact(), action: 'ebookReader.haptic');
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.l10n.ebookReaderButtonNextChapter,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: 14,
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                size: 28,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 控制按钮
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _BottomBarButton(
                      icon: Icons.menu_book,
                      label: context.l10n.ebookReaderButtonTableOfContents,
                      isDark: isDark,
                      onPressed: () {
                        setState(() {
                          _showToc = !_showToc;
                        });
                      },
                    ),
                    _BottomBarButton(
                      icon: Icons.headphones,
                      label: context.l10n.ebookReaderButtonTextToSpeech,
                      isDark: isDark,
                      onPressed: _startTTS,
                    ),
                    _BottomBarButton(
                      icon: isDark ? Icons.light_mode : Icons.dark_mode,
                      label: isDark ? context.l10n.ebookReaderButtonDayMode : context.l10n.ebookReaderButtonNightMode,
                      isDark: isDark,
                      onPressed: () {
                        final notifier = ref.read(bookReaderSettingsProvider.notifier);
                        final newTheme = isDark
                            ? BookReaderTheme.light
                            : BookReaderTheme.dark;
                        notifier.setTheme(newTheme);
                        _applySettings(settings.copyWith(theme: newTheme));
                      },
                    ),
                    _BottomBarButton(
                      icon: Icons.settings_rounded,
                      label: context.l10n.ebookReaderButtonSettings,
                      isDark: isDark,
                      onPressed: _showSettingsSheet,
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

  Widget _buildTocDrawer(BookReaderSettings settings) {
    final isDark = settings.theme == BookReaderTheme.dark ||
        settings.theme == BookReaderTheme.black;

    return Positioned(
      top: 0,
      bottom: 0,
      left: 0,
      width: MediaQuery.of(context).size.width * 0.75,
      child: GestureDetector(
        onTap: () {}, // 阻止点击穿透
        child: Material(
          color: isDark ? Colors.grey[900] : Colors.white,
          elevation: 8,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.menu_book,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.ebookReaderTocTitle,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                        onPressed: () {
                          setState(() {
                            _showToc = false;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _tocItems.isEmpty
                      ? Center(
                          child: Text(
                            context.l10n.ebookReaderTocEmpty,
                            style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _flattenedTocItems.length,
                          itemBuilder: (context, index) {
                            final (item, depth) = _flattenedTocItems[index];
                            return ListTile(
                              contentPadding: EdgeInsets.only(
                                left: 16.0 + depth * 16.0, // 根据层级缩进
                                right: 16.0,
                              ),
                              title: Text(
                                item.label,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: depth > 0 ? 14 : 16, // 子目录字体稍小
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                if (item.href.isNotEmpty) {
                                  // 使用 goToHref 而不是 goToCfi
                                  _controller.goToHref(item.href);
                                }
                                setState(() {
                                  _showToc = false;
                                  _showControls = false;
                                });
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部栏按钮
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
    final color = isDark ? Colors.white : Colors.black87;
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
            Text(
              label,
              style: TextStyle(color: color, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
