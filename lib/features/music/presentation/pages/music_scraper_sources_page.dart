import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/music/data/services/music_scraper_factory.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/presentation/providers/music_scraper_provider.dart';

/// 音乐刮削源管理页面
/// - 点击需要配置的卡片弹出配置弹框
/// - 长按拖拽调整顺序
class MusicScraperSourcesPage extends ConsumerStatefulWidget {
  const MusicScraperSourcesPage({super.key});

  @override
  ConsumerState<MusicScraperSourcesPage> createState() => _MusicScraperSourcesPageState();
}

class _MusicScraperSourcesPageState extends ConsumerState<MusicScraperSourcesPage>
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
    final state = ref.watch(musicScraperSourcesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
      appBar: AppBar(
        title: const Text('音乐刮削源'),
        centerTitle: false,
        backgroundColor: isDark ? AppColors.darkSurface : null,
        actions: [
          // 排序模式切换按钮
          IconButton(
            icon: Icon(_isReorderMode ? Icons.done : Icons.reorder),
            onPressed: () {
              setState(() {
                _isReorderMode = !_isReorderMode;
              });
            },
            tooltip: _isReorderMode ? '完成排序' : '调整顺序',
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelpDialog(context),
            tooltip: '帮助',
          ),
        ],
      ),
      body: _buildBody(state, isDark),
    );
  }

  Widget _buildBody(MusicScraperSourcesState state, bool isDark) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text('加载失败: ${state.error}'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.read(musicScraperSourcesProvider.notifier).load(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return _buildScraperList(state, isDark);
  }

  Widget _buildScraperList(MusicScraperSourcesState state, bool isDark) {
    if (_isReorderMode) {
      // 排序模式只列出已配置的源——未配置的类型没有 priority 概念
      return _buildReorderableList(state.sources, isDark);
    }
    final sortedTypes = _getSortedTypes(state.sources);
    return _buildNormalList(state.sources, sortedTypes, isDark);
  }

  /// 构建普通列表（非排序模式）
  Widget _buildNormalList(
    List<MusicScraperSourceEntity> sources,
    List<MusicScraperType> sortedTypes,
    bool isDark,
  ) => ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sortedTypes.length,
        itemBuilder: (context, index) {
          final type = sortedTypes[index];
          final source = sources.where((s) => s.type == type).firstOrNull;

          return _MusicScraperTypeCard(
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
  ///
  /// 仅列出已配置的源（即 [sources] 自身，已按 priority 排序）。
  /// 未配置的类型没有 priority 概念，不参与拖动。
  Widget _buildReorderableList(
    List<MusicScraperSourceEntity> sources,
    bool isDark,
  ) {
    final hiddenTypes = _hiddenTypes;
    final reorderable = sources
        .where((s) => !hiddenTypes.contains(s.type))
        .toList();

    if (reorderable.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            '暂无已配置的刮削源可排序',
            style: TextStyle(
              color: isDark ? Colors.grey[500] : Colors.grey[600],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            '拖动调整刮削优先级（数值越靠前越先尝试）；未配置的源不参与排序',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[500] : Colors.grey[600],
            ),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: reorderable.length,
            onReorder: (oldIndex, newIndex) =>
                _handleReorder(reorderable, oldIndex, newIndex),
            proxyDecorator: (child, index, animation) => AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                final elevation =
                    Tween<double>(begin: 0, end: 8).evaluate(animation);
                return Material(
                  elevation: elevation,
                  borderRadius: BorderRadius.circular(16),
                  child: child,
                );
              },
              child: child,
            ),
            itemBuilder: (context, index) {
              final source = reorderable[index];
              return _MusicScraperTypeCard(
                key: ValueKey(source.id),
                index: index,
                type: source.type,
                source: source,
                isDark: isDark,
                isTesting: _testingSourceId == source.id,
                isReorderMode: true,
                onTap: () => _handleTap(source.type, source),
                onToggle: (enabled) => _handleToggle(source.type, source, enabled),
                onTest: () => _testConnection(source),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 暂不对外开放的类型
  static const Set<MusicScraperType> _hiddenTypes = {
    MusicScraperType.musicTagWeb,
  };

  /// 获取排序后的类型列表（普通模式）
  List<MusicScraperType> _getSortedTypes(List<MusicScraperSourceEntity> sources) {
    final configuredTypes = sources
        .map((s) => s.type)
        .where((t) => !_hiddenTypes.contains(t))
        .toList();
    final unconfiguredTypes = MusicScraperType.values
        .where((t) => !configuredTypes.contains(t) && !_hiddenTypes.contains(t))
        .toList();
    return [...configuredTypes, ...unconfiguredTypes];
  }

  /// 处理重排序
  ///
  /// [reorderable] 是排序模式下展示的已配置源列表，因为 hiddenTypes 的存在，
  /// 它的索引可能与 provider 中的 `state.sources` 索引不一致——必须用 id 回查。
  void _handleReorder(
    List<MusicScraperSourceEntity> reorderable,
    int oldIndex,
    int newIndex,
  ) {
    // ReorderableListView 约定：oldIndex < newIndex 时 newIndex 比实际大 1
    var adjustedNewIndex = newIndex;
    if (oldIndex < adjustedNewIndex) {
      adjustedNewIndex -= 1;
    }
    if (oldIndex == adjustedNewIndex) return;

    final sources = ref.read(musicScraperSourcesProvider).sources;
    final fromIndex = sources.indexWhere((s) => s.id == reorderable[oldIndex].id);
    final toIndex =
        sources.indexWhere((s) => s.id == reorderable[adjustedNewIndex].id);
    if (fromIndex == -1 || toIndex == -1) return;

    ref.read(musicScraperSourcesProvider.notifier).reorder(fromIndex, toIndex);
  }

  /// 处理点击
  void _handleTap(MusicScraperType type, MusicScraperSourceEntity? source) {
    final needsConfig = type.requiresApiKey || type.supportsCookie || type.requiresServerUrl;
    if (!needsConfig) return;

    _showConfigSheet(type, source);
  }

  /// 处理启用/禁用切换
  Future<void> _handleToggle(MusicScraperType type, MusicScraperSourceEntity? source, bool enabled) async {
    final needsConfig = type.requiresApiKey || type.requiresServerUrl;
    final isImplemented = MusicScraperFactory.isImplemented(type);

    if (!isImplemented) return;

    // 启用高风险刮削源前要求显式确认
    if (enabled && type.requiresRiskAcknowledgement) {
      final acknowledged = await _confirmRiskAcknowledgement(type);
      if (!acknowledged) return;
    }

    if (source != null) {
      if (enabled && !source.isConfigured && needsConfig) {
        _showConfigSheet(type, source);
      } else {
        await ref.read(musicScraperSourcesProvider.notifier).toggleSource(source.id, isEnabled: enabled);
      }
    } else if (enabled) {
      if (needsConfig) {
        _showConfigSheet(type, null);
      } else {
        await _createAndEnableSource(type);
      }
    }
  }

  /// 启用高风险刮削源前的二次确认
  Future<bool> _confirmRiskAcknowledgement(MusicScraperType type) async {
    final notice = type.riskNotice;
    if (notice == null) return true;

    final isHigh = type.riskLevel == MusicScraperRiskLevel.antiCircumvention;
    final title = isHigh ? '启用前请知悉（较高风险）' : '启用前请知悉';

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isHigh ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
              color: isHigh ? AppColors.error : Colors.orange,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '即将启用：${type.displayName}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(notice, style: const TextStyle(height: 1.5)),
              const SizedBox(height: 12),
              const Text(
                '本应用仅获取元数据 / 封面 / 歌词写入你本地的音频文件， '
                '不下载也不传播音频本体。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: isHigh ? AppColors.error : null,
            ),
            child: const Text('我已知悉，启用'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  /// 创建并启用源
  Future<void> _createAndEnableSource(MusicScraperType type) async {
    final newSource = MusicScraperSourceEntity(
      name: '',
      type: type,
      isEnabled: true,
      priority: 999,
    );
    await ref.read(musicScraperSourcesProvider.notifier).addSource(newSource);
  }

  /// 显示配置弹框
  void _showConfigSheet(MusicScraperType type, MusicScraperSourceEntity? source) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _MusicScraperConfigSheet(
        type: type,
        source: source,
        onSave: (config) => _saveConfig(type, source, config),
        onTest: source != null ? () => _testConnection(source) : null,
        isTesting: source != null && _testingSourceId == source.id,
      ),
    );
  }

  /// 保存配置
  Future<void> _saveConfig(
    MusicScraperType type,
    MusicScraperSourceEntity? existingSource,
    _MusicScraperConfigData config,
  ) async {
    Map<String, dynamic>? extraConfig;
    if (type == MusicScraperType.musicTagWeb) {
      final username = config.username;
      final password = config.password;
      extraConfig = {
        'serverUrl': config.serverUrl,
        'username': username != null && username.isNotEmpty ? username : null,
        'password': password != null && password.isNotEmpty ? password : null,
        'preferredSource': config.preferredSource,
      };
    }

    final apiKey = config.apiKey;
    final cookie = config.cookie;
    final hasApiKey = apiKey != null && apiKey.isNotEmpty;
    final hasCookie = cookie != null && cookie.isNotEmpty;

    if (existingSource != null) {
      final updated = existingSource.copyWith(
        apiKey: hasApiKey ? apiKey : null,
        cookie: hasCookie ? cookie : null,
        extraConfig: extraConfig ?? existingSource.extraConfig,
      );
      await ref.read(musicScraperSourcesProvider.notifier).updateSource(updated);
    } else {
      final newSource = MusicScraperSourceEntity(
        name: '',
        type: type,
        isEnabled: true,
        priority: 999,
        apiKey: hasApiKey ? apiKey : null,
        cookie: hasCookie ? cookie : null,
        extraConfig: extraConfig,
      );
      await ref.read(musicScraperSourcesProvider.notifier).addSource(newSource);
    }

    if (mounted) {
      Navigator.pop(context);
      context.showSuccessToast('${type.displayName} 配置已保存');
    }
  }

  /// 测试连接
  Future<void> _testConnection(MusicScraperSourceEntity source) async {
    if (_testingSourceId != null) return;

    setState(() => _testingSourceId = source.id);

    try {
      final manager = ref.read(musicScraperManagerProvider);
      await manager.init();
      final scraper = await manager.getScraper(source.id);
      final success = scraper != null && await scraper.testConnection();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '连接成功' : '连接失败'),
          backgroundColor: success ? AppColors.success : AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on Exception catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('连接失败: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _testingSourceId = null);
    }
  }

  /// 显示帮助对话框
  void _showHelpDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刮削源说明'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('推荐配置（按合规优先级）：',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('1. MusicBrainz - 开放音乐数据库，CC0 元数据 + 封面（默认启用）'),
              Text('2. AcoustID - 声纹识别（需要 API Key，建议使用）'),
              SizedBox(height: 12),
              Text('以下为商业平台刮削源（默认禁用）：',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
              SizedBox(height: 8),
              Text('• QQ音乐 / 酷狗 / 酷我 / 咪咕：使用未公开 API，违反平台 ToS'),
              Text('• 网易云音乐：使用加密请求绕过限制，存在不正当竞争争议'),
              SizedBox(height: 8),
              Text(
                '启用上述商业平台刮削源前请知悉相关法律风险。本应用仅获取元数据/封面/歌词写入你本地音频文件，'
                '不下载也不传播音频本体；请仅用于管理你合法获取的音乐，并自行承担合规责任。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              SizedBox(height: 16),
              Text('功能说明：', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• 元数据：歌曲名、艺术家、专辑等'),
              Text('• 封面：专辑封面图片'),
              Text('• 歌词：歌词文本（LRC 格式）'),
              Text('• 声纹：通过音频指纹识别歌曲'),
              SizedBox(height: 16),
              Text('API Key 获取：', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• AcoustID: acoustid.org/api-key'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

/// 刮削源类型卡片
class _MusicScraperTypeCard extends StatelessWidget {
  const _MusicScraperTypeCard({
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
  final MusicScraperType type;
  final MusicScraperSourceEntity? source;
  final bool isDark;
  final bool isTesting;
  final bool isReorderMode;
  final VoidCallback onTap;
  final void Function(bool) onToggle;
  final VoidCallback? onTest;

  bool get _isEnabled => source?.isEnabled ?? false;
  bool get _isConfigured => source?.isConfigured ?? false;
  bool get _needsConfig => type.requiresApiKey || type.supportsCookie || type.requiresServerUrl;
  bool get _isImplemented => MusicScraperFactory.isImplemented(type);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: isDark ? AppColors.darkSurfaceElevated : Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 1,
        shadowColor: type.themeColor.withValues(alpha: 0.3),
        child: InkWell(
          onTap: _needsConfig && _isImplemented && !isReorderMode ? onTap : null,
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
                    color: (_isEnabled && _isImplemented)
                        ? type.themeColor.withValues(alpha: 0.15)
                        : (isDark ? Colors.grey[800] : Colors.grey[200]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    type.icon,
                    size: 24,
                    color: (_isEnabled && _isImplemented)
                        ? type.themeColor
                        : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 12),

                // 名称和能力标签
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
                              color: (_isEnabled && _isImplemented)
                                  ? null
                                  : (isDark ? Colors.grey[500] : Colors.grey[600]),
                            ),
                          ),
                          if (!_isImplemented) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '即将支持',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ] else if (_isConfigured) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '已配置',
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
                      _buildCapabilityChips(context),
                    ],
                  ),
                ),

                // 配置按钮（如果需要配置，排序模式下不显示）
                if (_needsConfig && _isImplemented && !isReorderMode)
                  IconButton(
                    onPressed: onTap,
                    icon: Icon(
                      Icons.settings_outlined,
                      color: isDark ? Colors.grey[500] : Colors.grey[400],
                      size: 22,
                    ),
                    tooltip: '配置',
                    visualDensity: VisualDensity.compact,
                  ),

                // 启用开关（排序模式下不显示）
                if (!isReorderMode)
                  Switch(
                    value: _isEnabled,
                    onChanged: _isImplemented ? onToggle : null,
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

  /// 构建能力标签
  Widget _buildCapabilityChips(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chips = <Widget>[];

    if (type.supportsMetadata) {
      chips.add(_buildChip(context, '元数据', colorScheme.primaryContainer));
    }
    if (type.supportsCover) {
      chips.add(_buildChip(context, '封面', colorScheme.secondaryContainer));
    }
    if (type.supportsLyrics) {
      chips.add(_buildChip(context, '歌词', colorScheme.tertiaryContainer));
    }
    if (type.supportsFingerprint) {
      chips.add(_buildChip(context, '声纹', colorScheme.errorContainer));
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: chips,
    );
  }

  Widget _buildChip(BuildContext context, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
              ),
        ),
      );
}

/// 配置数据
class _MusicScraperConfigData {
  String? apiKey;
  String? cookie;
  String? serverUrl;
  String? username;
  String? password;
  String preferredSource = 'netease';
}

/// 配置弹框
class _MusicScraperConfigSheet extends StatefulWidget {
  const _MusicScraperConfigSheet({
    required this.type,
    required this.source,
    required this.onSave,
    required this.onTest,
    required this.isTesting,
  });

  final MusicScraperType type;
  final MusicScraperSourceEntity? source;
  final void Function(_MusicScraperConfigData) onSave;
  final VoidCallback? onTest;
  final bool isTesting;

  @override
  State<_MusicScraperConfigSheet> createState() => _MusicScraperConfigSheetState();
}

class _MusicScraperConfigSheetState extends State<_MusicScraperConfigSheet> {
  final _apiKeyController = TextEditingController();
  final _cookieController = TextEditingController();
  final _serverUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String _preferredSource = 'netease';
  bool _obscureApiKey = true;
  bool _obscureCookie = true;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    if (widget.source != null) {
      _apiKeyController.text = widget.source!.apiKey ?? '';
      _cookieController.text = widget.source!.cookie ?? '';
      if (widget.type == MusicScraperType.musicTagWeb) {
        _serverUrlController.text = widget.source!.extraConfig?['serverUrl'] as String? ?? '';
        _usernameController.text = widget.source!.extraConfig?['username'] as String? ?? '';
        _passwordController.text = widget.source!.extraConfig?['password'] as String? ?? '';
        _preferredSource = widget.source!.extraConfig?['preferredSource'] as String? ?? 'netease';
      }
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _cookieController.dispose();
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
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
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.3)
                        : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
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
                              _getTypeDescription(),
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
                      if (widget.type.requiresApiKey) ...[
                        _buildTextField(
                          label: 'API Key',
                          hint: _getApiKeyHint(),
                          controller: _apiKeyController,
                          isRequired: true,
                          isObscure: _obscureApiKey,
                          onToggleObscure: () => setState(() => _obscureApiKey = !_obscureApiKey),
                          isDark: isDark,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Cookie
                      if (widget.type.supportsCookie) ...[
                        _buildTextField(
                          label: 'Cookie（可选）',
                          hint: '登录后可获取更多内容',
                          controller: _cookieController,
                          isRequired: false,
                          isObscure: _obscureCookie,
                          onToggleObscure: () => setState(() => _obscureCookie = !_obscureCookie),
                          isMultiline: true,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '从浏览器开发者工具复制 Cookie',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey[500] : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Music Tag Web 配置
                      if (widget.type.requiresServerUrl) ...[
                        _buildTextField(
                          label: '服务器地址',
                          hint: '例如: http://192.168.1.100:8002',
                          controller: _serverUrlController,
                          isRequired: true,
                          isUrl: true,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Music Tag Web 服务器的地址和端口',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey[500] : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                label: '用户名',
                                hint: '默认: admin',
                                controller: _usernameController,
                                isRequired: false,
                                isDark: isDark,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildTextField(
                                label: '密码',
                                hint: '服务器密码',
                                controller: _passwordController,
                                isRequired: false,
                                isObscure: _obscurePassword,
                                onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
                                isDark: isDark,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildPreferredSourceDropdown(isDark),
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
                            label: Text(widget.isTesting ? '测试中...' : '测试连接'),
                          ),
                        ),
                      if (widget.onTest != null) const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _handleSave,
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('保存'),
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

  String _getTypeDescription() {
    final capabilities = <String>[];
    if (widget.type.supportsMetadata) capabilities.add('元数据');
    if (widget.type.supportsCover) capabilities.add('封面');
    if (widget.type.supportsLyrics) capabilities.add('歌词');
    if (widget.type.supportsFingerprint) capabilities.add('声纹识别');
    return capabilities.isEmpty ? '音乐刮削源' : '支持: ${capabilities.join('、')}';
  }

  String _getApiKeyHint() => switch (widget.type) {
        MusicScraperType.acoustId => '从 acoustid.org 获取',
        _ => '请输入 API Key',
      };

  void _handleSave() {
    // 验证必填项
    if (widget.type.requiresApiKey && _apiKeyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写 API Key'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (widget.type.requiresServerUrl && _serverUrlController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写服务器地址'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    widget.onSave(_MusicScraperConfigData()
      ..apiKey = _apiKeyController.text.trim()
      ..cookie = _cookieController.text.trim()
      ..serverUrl = _serverUrlController.text.trim()
      ..username = _usernameController.text.trim()
      ..password = _passwordController.text.trim()
      ..preferredSource = _preferredSource);
  }

  Widget _buildPreferredSourceDropdown(bool isDark) {
    const options = [
      ('netease', '网易云音乐'),
      ('qmusic', 'QQ音乐'),
      ('kugou', '酷狗音乐'),
      ('kuwo', '酷我音乐'),
      ('migu', '咪咕音乐'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '首选音乐源',
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
              value: _preferredSource,
              isExpanded: true,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              borderRadius: BorderRadius.circular(10),
              dropdownColor: isDark ? Colors.grey[850] : Colors.white,
              items: options.map((option) {
                final (value, label) = option;
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(label, style: const TextStyle(fontSize: 14)),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) setState(() => _preferredSource = value);
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '搜索时优先使用的音乐平台',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey[500] : Colors.grey[600],
          ),
        ),
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
            maxLines: isObscure ? 1 : (isMultiline ? 3 : 1),
            keyboardType: isUrl ? TextInputType.url : TextInputType.text,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(fontSize: 13, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
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
