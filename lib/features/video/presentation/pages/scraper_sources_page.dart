import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';
import 'package:my_nas/features/video/presentation/providers/scraper_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

/// 刮削源管理页面
/// - 点击需要配置的卡片弹出配置弹框
/// - 长按拖拽调整顺序
class ScraperSourcesPage extends ConsumerStatefulWidget {
  const ScraperSourcesPage({super.key});

  @override
  ConsumerState<ScraperSourcesPage> createState() => _ScraperSourcesPageState();
}

class _ScraperSourcesPageState extends ConsumerState<ScraperSourcesPage>
    with ConsumerTabBarVisibilityMixin {
  String? _testingSourceId;
  bool _isReorderMode = false;

  @override
  void initState() {
    super.initState();
    hideTabBar();
  }

  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(scraperSourcesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
      appBar: AppBar(
        leading: const RoundedBackButton(),
        title: Text(context.l10n.videoScraperSourcesPageTitle),
        centerTitle: false,
        backgroundColor: isDark ? AppColors.darkSurface : null,
        actions: [
          // 排序模式切换按钮
          IconButton(
            icon: Icon(_isReorderMode ? Icons.done_rounded : Icons.reorder),
            onPressed: () {
              setState(() {
                _isReorderMode = !_isReorderMode;
              });
            },
            tooltip: _isReorderMode ? context.l10n.videoScraperReorderModeDone : context.l10n.videoScraperReorderModeAdjust,
          ),
        ],
      ),
      body: sourcesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text(context.l10n.videoScraperLoadFailed(e)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.read(scraperSourcesProvider.notifier).refresh(),
                child: Text(context.l10n.videoScraperRetry),
              ),
            ],
          ),
        ),
        data: (sources) => _buildContent(sources, isDark),
      ),
    );
  }

  Widget _buildContent(List<ScraperSourceEntity> sources, bool isDark) {
    // 构建排序后的类型列表
    final sortedTypes = _getSortedTypes(sources);

    if (_isReorderMode) {
      return _buildReorderableList(sources, sortedTypes, isDark);
    }

    return _buildNormalList(sources, sortedTypes, isDark);
  }

  /// 构建普通列表（非排序模式）
  Widget _buildNormalList(
    List<ScraperSourceEntity> sources,
    List<ScraperType> sortedTypes,
    bool isDark,
  ) => ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sortedTypes.length,
        itemBuilder: (context, index) {
          final type = sortedTypes[index];
          final source = sources.where((s) => s.type == type).firstOrNull;

          return _ScraperTypeCard(
            key: ValueKey(type),
            index: index,
            type: type,
            source: source,
            isDark: isDark,
            isTesting: source != null && _testingSourceId == source.id,
            isReorderMode: false,
            onTap: () => _handleTap(type, source),
            onToggle: (enabled) => _handleToggle(type, source, enabled),
            onTest: source != null ? () => _testConnection(source) : null,
          );
        },
      );

  /// 构建可排序列表（排序模式）
  Widget _buildReorderableList(
    List<ScraperSourceEntity> sources,
    List<ScraperType> sortedTypes,
    bool isDark,
  ) => ReorderableListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sortedTypes.length,
        onReorder: (oldIndex, newIndex) => _handleReorder(sources, sortedTypes, oldIndex, newIndex),
        proxyDecorator: (child, index, animation) => AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final elevation = Tween<double>(begin: 0, end: 8).evaluate(animation);
            return Material(
              elevation: elevation,
              borderRadius: BorderRadius.circular(16),
              child: child,
            );
          },
          child: child,
        ),
        itemBuilder: (context, index) {
          final type = sortedTypes[index];
          final source = sources.where((s) => s.type == type).firstOrNull;

          return _ScraperTypeCard(
            key: ValueKey(type),
            index: index,
            type: type,
            source: source,
            isDark: isDark,
            isTesting: source != null && _testingSourceId == source.id,
            isReorderMode: true,
            onTap: () => _handleTap(type, source),
            onToggle: (enabled) => _handleToggle(type, source, enabled),
            onTest: source != null ? () => _testConnection(source) : null,
          );
        },
      );

  List<ScraperType> _getSortedTypes(List<ScraperSourceEntity> sources) {
    final configuredTypes = sources.map((s) => s.type).toList();
    final unconfiguredTypes = ScraperType.values.where((t) => !configuredTypes.contains(t)).toList();
    return [...configuredTypes, ...unconfiguredTypes];
  }

  void _handleReorder(
    List<ScraperSourceEntity> sources,
    List<ScraperType> sortedTypes,
    int oldIndex,
    int newIndex,
  ) {
    var adjustedNewIndex = newIndex;
    if (oldIndex < adjustedNewIndex) {
      adjustedNewIndex -= 1;
    }

    final type = sortedTypes[oldIndex];
    final sourceIndex = sources.indexWhere((s) => s.type == type);
    if (sourceIndex == -1) return;

    final targetType = sortedTypes[adjustedNewIndex];
    final targetSourceIndex = sources.indexWhere((s) => s.type == targetType);
    if (targetSourceIndex == -1) return;

    ref.read(scraperSourcesProvider.notifier).reorderSources(sourceIndex, targetSourceIndex);
  }

  void _handleTap(ScraperType type, ScraperSourceEntity? source) {
    final needsConfig = type.requiresApiKey || type.requiresApiUrl || type.requiresCookie;
    if (!needsConfig) return;

    _showConfigSheet(type, source);
  }

  Future<void> _handleToggle(ScraperType type, ScraperSourceEntity? source, bool enabled) async {
    final needsConfig = type.requiresApiKey || type.requiresApiUrl || type.requiresCookie;

    if (source != null) {
      if (enabled && !source.isConfigured && needsConfig) {
        _showConfigSheet(type, source);
      } else {
        await ref.read(scraperSourcesProvider.notifier).toggleSource(source.id, enabled: enabled);
      }
    } else if (enabled) {
      if (needsConfig) {
        _showConfigSheet(type, null);
      } else {
        await _createAndEnableSource(type);
      }
    }
  }

  Future<void> _createAndEnableSource(ScraperType type) async {
    final newSource = ScraperSourceEntity(
      name: '',
      type: type,
      isEnabled: true,
    );
    await ref.read(scraperSourcesProvider.notifier).addSource(newSource);
  }

  void _showConfigSheet(ScraperType type, ScraperSourceEntity? source) {
    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _VideoScraperConfigSheet(
        type: type,
        source: source,
        onSave: (config) => _saveConfig(type, source, config),
        onTest: source != null ? () => _testConnection(source) : null,
        isTesting: source != null && _testingSourceId == source.id,
      ),
    );
  }

  Future<void> _saveConfig(
    ScraperType type,
    ScraperSourceEntity? existingSource,
    _VideoScraperConfigData config,
  ) async {
    String? apiUrl;
    Map<String, dynamic>? extraConfig;

    final apiKey = config.apiKey;
    final cookie = config.cookie;
    final configApiUrl = config.apiUrl;
    final imageProxy = config.imageProxy;
    final hasApiKey = apiKey != null && apiKey.isNotEmpty;
    final hasCookie = cookie != null && cookie.isNotEmpty;
    final hasConfigApiUrl = configApiUrl != null && configApiUrl.isNotEmpty;

    if (type == ScraperType.tmdb) {
      apiUrl = config.tmdbApiUrl;
      if (imageProxy != null && imageProxy.isNotEmpty) {
        extraConfig = {'imageProxy': imageProxy};
      }
    } else {
      apiUrl = hasConfigApiUrl ? configApiUrl : null;
    }

    if (existingSource != null) {
      final updated = existingSource.copyWith(
        apiKey: hasApiKey ? apiKey : null,
        apiUrl: apiUrl,
        cookie: hasCookie ? cookie : null,
        extraConfig: extraConfig ?? existingSource.extraConfig,
      );
      await ref.read(scraperSourcesProvider.notifier).updateSource(updated);
    } else {
      final newSource = ScraperSourceEntity(
        name: '',
        type: type,
        isEnabled: true,
        apiKey: hasApiKey ? apiKey : null,
        apiUrl: apiUrl,
        cookie: hasCookie ? cookie : null,
        extraConfig: extraConfig,
      );
      await ref.read(scraperSourcesProvider.notifier).addSource(newSource);
    }

    if (mounted) {
      Navigator.pop(context);
      context.showSuccessToast(context.l10n.videoScraperConfigSaved(type.displayName));
    }
  }

  Future<void> _testConnection(ScraperSourceEntity source) async {
    if (_testingSourceId != null) return;

    setState(() => _testingSourceId = source.id);

    try {
      final success = await ref.read(scraperSourcesProvider.notifier).testConnection(source);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? context.l10n.videoScraperConnectionSuccess : context.l10n.videoScraperConnectionFailed),
          backgroundColor: success ? AppColors.success : AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).videoScraperTestConnectionFailed(e)),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _testingSourceId = null);
    }
  }
}

/// 刮削源卡片
class _ScraperTypeCard extends StatelessWidget {
  const _ScraperTypeCard({
    super.key,
    required this.index,
    required this.type,
    required this.source,
    required this.isDark,
    required this.isTesting,
    required this.isReorderMode,
    required this.onTap,
    required this.onToggle,
    required this.onTest,
  });

  final int index;
  final ScraperType type;
  final ScraperSourceEntity? source;
  final bool isDark;
  final bool isTesting;
  final bool isReorderMode;
  final VoidCallback onTap;
  final void Function(bool) onToggle;
  final VoidCallback? onTest;

  bool get _isEnabled => source?.isEnabled ?? false;
  bool get _isConfigured => source?.isConfigured ?? false;
  bool get _needsConfig => type.requiresApiKey || type.requiresApiUrl || type.requiresCookie;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: isDark ? AppColors.darkSurfaceElevated : Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 1,
        shadowColor: type.themeColor.withValues(alpha: 0.3),
        child: InkWell(
          onTap: _needsConfig && !isReorderMode ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // 排序模式下显示拖动手柄
                if (isReorderMode) ...[
                  ReorderableDragStartListener(
                    index: index,
                    child: Icon(
                      Icons.drag_handle,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],

                // 图标
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _isEnabled
                        ? type.themeColor.withValues(alpha: 0.15)
                        : (isDark ? Colors.grey[800] : Colors.grey[200]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    type.icon,
                    size: 24,
                    color: _isEnabled
                        ? type.themeColor
                        : (isDark ? Colors.grey[600] : Colors.grey[400]),
                  ),
                ),
                const SizedBox(width: 12),

                // 名称和描述
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            type.displayName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: _isEnabled
                                  ? null
                                  : (isDark ? Colors.grey[500] : Colors.grey[600]),
                            ),
                          ),
                          if (_isConfigured) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                context.l10n.videoScraperCardConfigured,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getDescription(context),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark ? Colors.grey[500] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),

                // 配置按钮（如果需要配置，排序模式下不显示）
                if (_needsConfig && !isReorderMode)
                  IconButton(
                    onPressed: onTap,
                    icon: Icon(
                      Icons.settings_outlined,
                      color: isDark ? Colors.grey[500] : Colors.grey[400],
                      size: 22,
                    ),
                    tooltip: context.l10n.videoScraperCardConfigure,
                    visualDensity: VisualDensity.compact,
                  ),

                // 启用开关（排序模式下不显示）
                if (!isReorderMode)
                  Switch(
                    value: _isEnabled,
                    onChanged: onToggle,
                    activeTrackColor: type.themeColor.withValues(alpha: 0.5),
                    activeThumbColor: type.themeColor,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getDescription(BuildContext context) {
    if (!_needsConfig) return context.l10n.videoScraperCardBuiltIn;
    if (type.requiresApiKey) return context.l10n.videoScraperCardRequiresApiKey;
    if (type.requiresApiUrl) return context.l10n.videoScraperCardRequiresApiUrl;
    if (type.requiresCookie) return context.l10n.videoScraperCardRequiresCookie;
    return type.description;
  }
}

/// 配置数据
class _VideoScraperConfigData {
  String? apiKey;
  String? apiUrl;
  String? cookie;
  String? tmdbApiUrl;
  String? imageProxy;
}

/// 配置弹框
class _VideoScraperConfigSheet extends StatefulWidget {
  const _VideoScraperConfigSheet({
    required this.type,
    required this.source,
    required this.onSave,
    required this.onTest,
    required this.isTesting,
  });

  final ScraperType type;
  final ScraperSourceEntity? source;
  final void Function(_VideoScraperConfigData) onSave;
  final VoidCallback? onTest;
  final bool isTesting;

  @override
  State<_VideoScraperConfigSheet> createState() => _VideoScraperConfigSheetState();
}

class _VideoScraperConfigSheetState extends State<_VideoScraperConfigSheet> {
  static const _tmdbCustomSentinel = '__custom__';
  static const _tmdbPresetUrls = <String>{
    'https://api.themoviedb.org/3',
    'https://api.tmdb.org/3',
    'https://tmdb.nastool.cn/3',
    'https://tmdb.nastool.workers.dev/3',
    'https://tmdb.cub.red/3',
    'https://api.tmdb.cdn.kvxd.workers.dev/3',
  };

  final _apiKeyController = TextEditingController();
  final _apiUrlController = TextEditingController();
  final _cookieController = TextEditingController();
  final _imageProxyController = TextEditingController();
  final _tmdbCustomUrlController = TextEditingController();
  String _tmdbApiUrlSelection = 'https://api.themoviedb.org/3';
  bool _obscureApiKey = true;
  bool _obscureCookie = true;

  @override
  void initState() {
    super.initState();
    if (widget.source != null) {
      _apiKeyController.text = widget.source!.apiKey ?? '';
      _apiUrlController.text = widget.source!.apiUrl ?? '';
      _cookieController.text = widget.source!.cookie ?? '';
      if (widget.type == ScraperType.tmdb) {
        final savedUrl = widget.source!.apiUrl ?? 'https://api.themoviedb.org/3';
        if (_tmdbPresetUrls.contains(savedUrl)) {
          _tmdbApiUrlSelection = savedUrl;
        } else {
          _tmdbApiUrlSelection = _tmdbCustomSentinel;
          _tmdbCustomUrlController.text = savedUrl;
        }
        _imageProxyController.text = widget.source!.extraConfig?['imageProxy'] as String? ?? '';
      }
    }
  }

  /// 当前实际使用的 TMDB API URL（预设直接返回；自定义返回用户输入）
  String get _effectiveTmdbApiUrl {
    if (_tmdbApiUrlSelection == _tmdbCustomSentinel) {
      return _tmdbCustomUrlController.text.trim();
    }
    return _tmdbApiUrlSelection;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiUrlController.dispose();
    _cookieController.dispose();
    _imageProxyController.dispose();
    _tmdbCustomUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurface.withValues(alpha: 0.95)
                  : AppColors.lightSurface.withValues(alpha: 0.98),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(
                  color: isDark ? AppColors.glassStroke : AppColors.lightOutline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Column(
              children: [
                // 拖动指示器
                const SheetDragHandle(),
                // 标题栏
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: widget.type.themeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(widget.type.icon, color: widget.type.themeColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.type.displayName,
                              style: context.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isDark ? AppColors.darkOnSurface : null,
                              ),
                            ),
                            Text(
                              widget.type.description,
                              style: context.textTheme.bodySmall?.copyWith(
                                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: isDark
                      ? AppColors.darkOutline.withValues(alpha: 0.2)
                      : AppColors.lightOutline.withValues(alpha: 0.3),
                ),
                // 表单内容
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      // API Key
                      if (widget.type.requiresApiKey || widget.type == ScraperType.doubanApi) ...[
                        _buildTextField(
                          label: context.l10n.videoScraperApiKeyLabel,
                          hint: widget.type == ScraperType.tmdb ? context.l10n.videoScraperApiKeyTmdbHint : context.l10n.videoScraperApiKeyOptionalHint,
                          controller: _apiKeyController,
                          isRequired: widget.type.requiresApiKey,
                          isObscure: _obscureApiKey,
                          onToggleObscure: () => setState(() => _obscureApiKey = !_obscureApiKey),
                          isDark: isDark,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // TMDB 特有配置
                      if (widget.type == ScraperType.tmdb) ...[
                        _buildTmdbApiUrlDropdown(isDark),
                        const SizedBox(height: 16),
                        _buildTextField(
                          label: context.l10n.videoScraperImageProxyLabel,
                          hint: context.l10n.videoScraperImageProxyHint,
                          controller: _imageProxyController,
                          isRequired: false,
                          isUrl: true,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // API URL
                      if (widget.type.requiresApiUrl) ...[
                        _buildTextField(
                          label: context.l10n.videoScraperApiUrlLabel,
                          hint: context.l10n.videoScraperApiUrlHint,
                          controller: _apiUrlController,
                          isRequired: true,
                          isUrl: true,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Cookie
                      if (widget.type.requiresCookie) ...[
                        _buildTextField(
                          label: context.l10n.videoScraperCookieLabel,
                          hint: context.l10n.videoScraperCookieHint,
                          controller: _cookieController,
                          isRequired: true,
                          isObscure: _obscureCookie,
                          onToggleObscure: () => setState(() => _obscureCookie = !_obscureCookie),
                          isMultiline: true,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
                // 底部按钮
                Container(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                    border: Border(
                      top: BorderSide(
                        color: isDark
                            ? AppColors.darkOutline.withValues(alpha: 0.2)
                            : AppColors.lightOutline.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (widget.onTest != null)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: widget.isTesting ? null : widget.onTest,
                            icon: widget.isTesting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.wifi_tethering_rounded, size: 18),
                            label: Text(widget.isTesting ? context.l10n.videoScraperTestConnectionTesting : context.l10n.videoScraperTestConnectionButton),
                          ),
                        ),
                      if (widget.onTest != null) const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _handleSave,
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: Text(context.l10n.videoScraperSaveButton),
                          style: FilledButton.styleFrom(
                            backgroundColor: widget.type.themeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleSave() {
    // 验证必填项
    final l = AppLocalizations.of(context);
    if (widget.type.requiresApiKey && _apiKeyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.videoScraperConfigValidateApiKeyEmpty), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (widget.type.requiresApiUrl && _apiUrlController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.videoScraperApiUrlRequired), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (widget.type.requiresCookie && _cookieController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.videoScraperConfigValidateCookieEmpty), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    // TMDB 选择"自定义"但未填写 URL → 拦截
    if (widget.type == ScraperType.tmdb &&
        _tmdbApiUrlSelection == _tmdbCustomSentinel &&
        _tmdbCustomUrlController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.videoScraperCustomApiUrlRequired), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    widget.onSave(_VideoScraperConfigData()
      ..apiKey = _apiKeyController.text.trim()
      ..apiUrl = _apiUrlController.text.trim()
      ..cookie = _cookieController.text.trim()
      ..tmdbApiUrl = _effectiveTmdbApiUrl
      ..imageProxy = _imageProxyController.text.trim());
  }

  Widget _buildTmdbApiUrlDropdown(bool isDark) {
    final options = [
      ('https://api.themoviedb.org/3', context.l10n.videoScraperTmdbOfficialLabel, context.l10n.videoScraperTmdbOfficialDesc),
      ('https://api.tmdb.org/3', context.l10n.videoScraperTmdbBackupLabel, 'api.tmdb.org'),
      ('https://tmdb.nastool.cn/3', context.l10n.videoScraperNastoolLabel, context.l10n.videoScraperNastoolDesc),
      ('https://tmdb.nastool.workers.dev/3', context.l10n.videoScraperWorkersLabel, 'tmdb.nastool.workers.dev'),
      ('https://tmdb.cub.red/3', context.l10n.videoScraperCubRedLabel, 'tmdb.cub.red'),
      ('https://api.tmdb.cdn.kvxd.workers.dev/3', 'KVXD Workers', 'api.tmdb.cdn.kvxd.workers.dev'),
      (_tmdbCustomSentinel, context.l10n.videoScraperCustomLabel, context.l10n.videoScraperCustomDesc),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.videoScraperTmdbApiServerLabel,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.grey[300] : Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkBackground : AppColors.lightSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _tmdbApiUrlSelection,
              isExpanded: true,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              borderRadius: BorderRadius.circular(10),
              dropdownColor: isDark ? Colors.grey[850] : Colors.white,
              items: options.map((option) {
                final (value, label, description) = option;
                return DropdownMenuItem<String>(
                  value: value,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: const TextStyle(fontSize: 14)),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey[500] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) setState(() => _tmdbApiUrlSelection = value);
              },
            ),
          ),
        ),
        if (_tmdbApiUrlSelection == _tmdbCustomSentinel) ...[
          const SizedBox(height: 12),
          _buildTextField(
            label: context.l10n.videoScraperCustomApiUrlLabel,
            hint: context.l10n.videoScraperCustomApiUrlExample,
            controller: _tmdbCustomUrlController,
            isRequired: true,
            isUrl: true,
            isDark: isDark,
          ),
        ],
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required bool isDark,
    bool isRequired = false,
    bool isObscure = false,
    bool isUrl = false,
    bool isMultiline = false,
    VoidCallback? onToggleObscure,
  }) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
              if (isRequired) ...[
                const SizedBox(width: 4),
                const Text('*', style: TextStyle(color: AppColors.error, fontSize: 13)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            obscureText: isObscure,
            maxLines: isMultiline ? 3 : 1,
            keyboardType: isUrl ? TextInputType.url : TextInputType.text,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(fontSize: 13, color: isDark ? Colors.grey[600] : Colors.grey[400]),
              filled: true,
              fillColor: isDark ? AppColors.darkBackground : AppColors.lightSurface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: widget.type.themeColor, width: 2),
              ),
              suffixIcon: onToggleObscure != null
                  ? IconButton(
                      icon: Icon(
                        isObscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        size: 20,
                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                      ),
                      onPressed: onToggleObscure,
                    )
                  : null,
            ),
          ),
        ],
      );
}
