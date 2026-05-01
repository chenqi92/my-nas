import 'dart:async' show StreamSubscription;
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/services/media_scan_progress_service.dart';
import 'package:my_nas/core/services/performance_mode_service.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/book_database_service.dart';
import 'package:my_nas/features/book/presentation/pages/book_list_page.dart';
import 'package:my_nas/features/comic/data/services/comic_library_cache_service.dart';
import 'package:my_nas/features/comic/presentation/pages/comic_list_page.dart';
import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:my_nas/features/music/data/services/music_scrape_service.dart';
import 'package:my_nas/features/music/presentation/pages/music_list_page.dart';
import 'package:my_nas/features/photo/data/services/photo_database_service.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_list_page.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/sources/presentation/widgets/folder_picker_sheet.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/data/services/video_scanner_service.dart';
import 'package:my_nas/features/video/presentation/pages/video_list_page.dart';
import 'package:my_nas/nas_adapters/local/local_adapter.dart';
import 'package:my_nas/nas_adapters/mobile/services/file_import_service.dart';
import 'package:my_nas/nas_adapters/smb/smb_pool_config.dart';

class MediaLibraryPage extends ConsumerStatefulWidget {
  const MediaLibraryPage({super.key});

  @override
  ConsumerState<MediaLibraryPage> createState() => _MediaLibraryPageState();
}

class _MediaLibraryPageState extends ConsumerState<MediaLibraryPage>
    with ConsumerTabBarVisibilityMixin {
  bool _isPerformanceMode = false;
  StreamSubscription<bool>? _performanceModeSub;

  @override
  void initState() {
    super.initState();
    hideTabBar();
    _isPerformanceMode = PerformanceModeService().isEnabled;
    _performanceModeSub = PerformanceModeService().stream.listen((enabled) {
      if (mounted) {
        setState(() => _isPerformanceMode = enabled);
      }
    });
  }

  @override
  void dispose() {
    _performanceModeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 判断是否为移动端
    final isMobile = !kIsWeb && (Platform.isIOS || Platform.isAndroid);

    // 移动端始终使用固定Tab（平均分割），桌面端根据屏幕宽度决定
    final useScrollableTab =
        !isMobile && MediaQuery.of(context).size.width < 500;

    return DefaultTabController(
      length: MediaType.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('媒体库'),
          actions: [
            // 性能模式开关
            _buildPerformanceModeButton(context, isMobile),
          ],
          bottom: TabBar(
            isScrollable: useScrollableTab,
            tabAlignment: useScrollableTab
                ? TabAlignment.start
                : TabAlignment.fill,
            padding: useScrollableTab
                ? const EdgeInsets.symmetric(horizontal: 8)
                : EdgeInsets.zero,
            labelPadding: useScrollableTab
                ? const EdgeInsets.symmetric(horizontal: 12)
                : const EdgeInsets.symmetric(horizontal: 4),
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.3)
                : null,
            labelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.normal,
            ),
            tabs: MediaType.values
                .map(
                  (type) => Tab(
                    iconMargin: const EdgeInsets.only(bottom: 4),
                    icon: Icon(_getMediaTypeIcon(type), size: 20),
                    text: type.displayName,
                  ),
                )
                .toList(),
          ),
        ),
        body: TabBarView(
          children: MediaType.values
              .map((type) => _MediaTypeTab(mediaType: type))
              .toList(),
        ),
      ),
    );
  }

  /// 构建性能模式开关按钮
  Widget _buildPerformanceModeButton(BuildContext context, bool isMobile) {
    final theme = Theme.of(context);

    return Tooltip(
      message: _isPerformanceMode ? '性能模式已开启' : '性能模式已关闭',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _togglePerformanceMode(context, isMobile),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _isPerformanceMode
                ? AppColors.warning.withValues(alpha: 0.15)
                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isPerformanceMode
                  ? AppColors.warning.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isPerformanceMode ? Icons.rocket_launch : Icons.rocket_outlined,
                size: 18,
                color: _isPerformanceMode ? AppColors.warning : null,
              ),
              const SizedBox(width: 4),
              Text(
                '性能',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: _isPerformanceMode ? FontWeight.bold : FontWeight.normal,
                  color: _isPerformanceMode ? AppColors.warning : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 切换性能模式
  Future<void> _togglePerformanceMode(BuildContext context, bool isMobile) async {
    final newValue = !_isPerformanceMode;

    // 如果是移动端开启性能模式，显示警告
    if (newValue && isMobile) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.warning),
              SizedBox(width: 8),
              Text('开启性能模式'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('性能模式会大幅提高刮削速度，但可能导致：'),
              const SizedBox(height: 12),
              _buildWarningItem(Icons.thermostat, '设备发热'),
              _buildWarningItem(Icons.battery_alert, '电池消耗加快'),
              _buildWarningItem(Icons.memory, '内存占用增加'),
              const SizedBox(height: 12),
              Text(
                '建议在充电时使用',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
              child: const Text('开启'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    await PerformanceModeService().setEnabled(newValue);

    if (context.mounted) {
      context.showSuccessToast(
        newValue
            ? '性能模式已开启 (${SmbPoolConfig.maxBackgroundTasks} 并发)'
            : '性能模式已关闭 (${SmbPoolConfig.maxBackgroundTasks} 并发)',
        action: () => _showConfigDetails(context),
        actionLabel: '详情',
      );
    }
  }

  /// 显示配置详情
  void _showConfigDetails(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _isPerformanceMode ? Icons.rocket_launch : Icons.settings,
              color: _isPerformanceMode ? AppColors.warning : null,
            ),
            const SizedBox(width: 8),
            Text(_isPerformanceMode ? '性能模式配置' : '普通模式配置'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildConfigRow('刮削并发数', '${SmbPoolConfig.maxBackgroundTasks}'),
            _buildConfigRow('SMB 连接数', '${SmbPoolConfig.maxConnections}'),
            _buildConfigRow('专用连接数', '${SmbPoolConfig.maxDedicatedConnections}'),
            _buildConfigRow('传输块大小', '${SmbPoolConfig.streamChunkSize ~/ 1024}KB'),
            _buildConfigRow('CPU 核心数', '${SmbPoolConfig.cpuCores}'),
            _buildConfigRow('平台', SmbPoolConfig.isDesktop ? '桌面端' : '移动端'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningItem(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppColors.warning),
        const SizedBox(width: 8),
        Text(text),
      ],
    ),
  );

  Widget _buildConfigRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: _isPerformanceMode ? AppColors.warning : null,
          ),
        ),
      ],
    ),
  );

  IconData _getMediaTypeIcon(MediaType type) => switch (type) {
    MediaType.video => Icons.movie_filter_outlined,
    MediaType.music => Icons.library_music_outlined,
    MediaType.photo => Icons.photo_album_outlined,
    MediaType.comic => Icons.collections_bookmark_outlined,
    MediaType.book => Icons.menu_book_outlined,
    MediaType.note => Icons.edit_note_outlined,
  };
}

class _MediaTypeTab extends ConsumerWidget {
  const _MediaTypeTab({required this.mediaType});

  final MediaType mediaType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(mediaLibraryConfigProvider);
    final sourcesAsync = ref.watch(sourcesProvider);
    final connections = ref.watch(activeConnectionsProvider);

    return configAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('加载失败: $e')),
      data: (config) {
        final paths = config.getPathsForType(mediaType);

        return sourcesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('加载失败: $e')),
          data: (sources) {
            // 桌面端如果没有源则显示提示（本机源由系统自动创建）
            final isMobile = !kIsWeb && (Platform.isIOS || Platform.isAndroid);
            if (sources.isEmpty && !isMobile) {
              return _buildNoSourcesState(context);
            }

            return Column(
              children: [
                // 添加按钮
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _addPath(context, ref, sources, connections, paths),
                      icon: const Icon(Icons.add),
                      label: const Text('添加目录'),
                    ),
                  ),
                ),

                // 目录列表
                if (paths.isEmpty)
                  Expanded(child: _buildEmptyState(context))
                else
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: paths.length,
                      itemBuilder: (context, index) {
                        final path = paths[index];
                        final source = sources.firstWhere(
                          (s) => s.id == path.sourceId,
                          orElse: () => SourceEntity(
                            name: '未知源',
                            type: SourceType.synology,
                            host: '',
                            username: '',
                          ),
                        );
                        final connection = connections[path.sourceId];

                        return _PathCard(
                          path: path,
                          source: source,
                          connection: connection,
                          connections: connections,
                          mediaType: mediaType,
                          allPaths: paths,
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildNoSourcesState(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text('尚未添加任何源', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '请先在设置中添加 NAS 或其他源',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildEmptyState(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getEmptyIcon(),
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '未配置${mediaType.displayName}目录',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '点击上方按钮添加目录',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );

  IconData _getEmptyIcon() => switch (mediaType) {
    MediaType.video => Icons.movie_filter_outlined,
    MediaType.music => Icons.library_music_outlined,
    MediaType.photo => Icons.photo_album_outlined,
    MediaType.comic => Icons.collections_bookmark_outlined,
    MediaType.book => Icons.menu_book_outlined,
    MediaType.note => Icons.edit_note_outlined,
  };

  void _addPath(
    BuildContext context,
    WidgetRef ref,
    List<SourceEntity> sources,
    Map<String, SourceConnection> connections,
    List<MediaLibraryPath> existingPaths,
  ) {
    // 统一显示源选择对话框
    _showSourceSelectionDialog(
      context,
      ref,
      sources,
      connections,
      existingPaths,
    );
  }

  /// 显示源选择对话框
  void _showSourceSelectionDialog(
    BuildContext context,
    WidgetRef ref,
    List<SourceEntity> sources,
    Map<String, SourceConnection> connections,
    List<MediaLibraryPath> existingPaths,
  ) {
    // 过滤出支持文件系统的已连接源
    final connectedSources = sources.where((s) {
      final conn = connections[s.id];
      return conn?.status == SourceStatus.connected && s.supportsFileSystem;
    }).toList();

    if (connectedSources.isEmpty) {
      context.showSuccessToast('没有已连接的源，请先连接一个源');
      return;
    }

    // 分离本机源和远程源
    final localSource = connectedSources.firstWhereOrNull(
      (s) => s.type == SourceType.local,
    );
    final remoteSources = connectedSources.where(
      (s) => s.type != SourceType.local,
    ).toList();

    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '选择数据源',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),

            // 本机源（移动端自动添加系统媒体库，桌面端选择目录）
            if (localSource != null) ...[
              Builder(builder: (context) {
                // 检查本机是否已添加到此媒体库
                final alreadyAdded = existingPaths.any((p) =>
                    p.sourceId == localSource.id);
                return ListTile(
                  leading: Icon(
                    localSource.type.icon,
                    color: localSource.type.themeColor,
                  ),
                  title: Text(localSource.displayName),
                  subtitle: Text(localSource.type.description),
                  trailing: alreadyAdded
                      ? const Chip(label: Text('已添加'))
                      : const Icon(Icons.chevron_right),
                  enabled: !alreadyAdded,
                  onTap: alreadyAdded
                      ? null
                      : () => _handleLocalSourceSelection(
                            context,
                            ref,
                            localSource,
                            connections,
                          ),
                );
              }),
            ],

            // 远程源（需要选择目录）
            if (remoteSources.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '远程存储',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.snippet_folder_outlined),
                title: const Text('选择目录...'),
                subtitle: const Text('从 NAS 或网络存储选择'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  _showFolderPicker(context, ref, remoteSources, connections);
                },
              ),
            ],

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// 处理选择本机源
  void _handleLocalSourceSelection(
    BuildContext context,
    WidgetRef ref,
    SourceEntity localSource,
    Map<String, SourceConnection> connections,
  ) {
    final isMobile = !kIsWeb && (Platform.isIOS || Platform.isAndroid);

    if (isMobile) {
      // 移动端：根据媒体类型自动选择路径
      Navigator.pop(context);
      _addLocalSourceToLibrary(context, ref, localSource, connections);
    } else {
      // 桌面端：显示文件夹选择器
      Navigator.pop(context);
      _showFolderPicker(context, ref, [localSource], connections);
    }
  }

  /// 添加本机源到媒体库（移动端）
  ///
  /// 根据媒体类型选择正确的路径前缀，并按需请求权限：
  /// - photo/video → /gallery（系统相册）- 需要相册权限
  /// - music → /music（系统音乐库）- 需要音乐库权限
  /// - book/comic/note → 显示导入选项（从 Files App 导入）
  Future<void> _addLocalSourceToLibrary(
    BuildContext context,
    WidgetRef ref,
    SourceEntity localSource,
    Map<String, SourceConnection> connections,
  ) async {
    // ignore: avoid_print
    print('🟠 MediaLibrary: _addLocalSourceToLibrary 开始, mediaType=$mediaType');
    try {
      // 获取 LocalAdapter 以请求权限
      final conn = connections[localSource.id];
      final adapter = conn?.adapter;
      // ignore: avoid_print
      print('🟠 MediaLibrary: adapter=${adapter?.runtimeType}');

      // 根据媒体类型请求对应权限
      if (adapter is LocalAdapter) {
        var hasPermission = true;

        switch (mediaType) {
          case MediaType.photo:
          case MediaType.video:
            // 请求相册权限
            // ignore: avoid_print
            print('🟠 MediaLibrary: 请求相册权限...');
            hasPermission = await adapter.requestGalleryPermission();
            // ignore: avoid_print
            print('🟠 MediaLibrary: 相册权限结果=$hasPermission');
            if (!hasPermission && context.mounted) {
              context.showErrorToast('需要相册访问权限才能添加本机相册');
              return;
            }
          case MediaType.music:
            // 请求音乐库权限
            hasPermission = await adapter.requestMusicPermission();
            if (!hasPermission && context.mounted) {
              context.showErrorToast('需要音乐库访问权限才能添加本机音乐');
              return;
            }
          case MediaType.book:
          case MediaType.comic:
          case MediaType.note:
            // 显示文件导入选项对话框
            if (context.mounted) {
              await _showFileImportOptions(context, ref, localSource, connections);
            }
            return; // 导入流程在对话框中处理完成
        }
      }

      // 根据媒体类型选择路径前缀（photo/video/music）
      final (path, displayName) = switch (mediaType) {
        MediaType.photo || MediaType.video => ('/gallery', '本机相册'),
        MediaType.music => ('/music', '本机音乐'),
        MediaType.book || MediaType.comic || MediaType.note => ('/files', '本机文件'),
      };

      final newPath = MediaLibraryPath(
        sourceId: localSource.id,
        path: path,
        name: displayName,
      );

      await ref.read(mediaLibraryConfigProvider.notifier).addPath(mediaType, newPath);

      // 触发扫描
      // ignore: avoid_print
      print('🟠 MediaLibrary: 触发扫描, path="${newPath.path}", sourceId="${newPath.sourceId}"');
      _autoScanPath(ref, mediaType, newPath, connections);

      if (context.mounted) {
        context.showSuccessToast('已添加$displayName，正在扫描...');
      }
    } on Exception catch (e, st) {
      // ignore: avoid_print
      print('🟠 MediaLibrary: ❌ 添加本机失败: $e');
      logger.e('添加本机失败', e, st);
      if (context.mounted) {
        context.showErrorToast('添加失败: $e');
      }
    }
  }

  /// 显示文件导入选项对话框（book/comic/note）
  Future<void> _showFileImportOptions(
    BuildContext context,
    WidgetRef ref,
    SourceEntity localSource,
    Map<String, SourceConnection> connections,
  ) async {
    final importType = switch (mediaType) {
      MediaType.book => FileImportType.book,
      MediaType.comic => FileImportType.comic,
      _ => FileImportType.document,
    };

    final typeDisplayName = switch (mediaType) {
      MediaType.book => '书籍',
      MediaType.comic => '漫画',
      _ => '文档',
    };

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '添加本机$typeDisplayName',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),

            // 从文件 App 导入
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.snippet_folder_outlined, color: Colors.blue),
              ),
              title: const Text('从文件导入'),
              subtitle: Text('从 iCloud、其他云盘或本地选择$typeDisplayName文件'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                Navigator.pop(context);
                await _importFilesFromFilesApp(context, ref, localSource, connections, importType);
              },
            ),

            // 扫描已有文件（如果已有导入的文件）
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.refresh, color: AppColors.success),
              ),
              title: const Text('扫描已有文件'),
              subtitle: const Text('扫描之前导入到应用的文件'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                Navigator.pop(context);
                await _addFilesPathToLibrary(context, ref, localSource, connections, importType);
              },
            ),

            const SizedBox(height: 8),

            // 提示信息
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '导入的文件会保存到应用目录，可在"文件" App 中管理',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// 从 Files App 导入文件
  ///
  /// 首次导入时先添加路径，然后在卡片上显示导入进度（非阻塞）
  Future<void> _importFilesFromFilesApp(
    BuildContext context,
    WidgetRef ref,
    SourceEntity localSource,
    Map<String, SourceConnection> connections,
    FileImportType importType,
  ) async {
    final typeDisplayName = switch (importType) {
      FileImportType.book => '书籍',
      FileImportType.comic => '漫画',
      FileImportType.document => '文件',
    };

    try {
      // 首先打开文件选择器（不阻塞，也不显示进度）
      // 进度将在路径卡片上显示
      final importedFiles = await FileImportService.instance.importFiles(
        type: importType,
        allowMultiple: true,
        // 首次导入不使用进度回调（因为卡片还不存在）
        // 文件复制过程在后台进行
      );

      if (importedFiles.isEmpty) {
        if (context.mounted) {
          context.showInfoToast('未选择文件');
        }
        return;
      }

      // 添加路径到媒体库并扫描
      await _addFilesPathToLibrary(context, ref, localSource, connections, importType);

      if (context.mounted) {
        context.showSuccessToast('已导入 ${importedFiles.length} 个$typeDisplayName，正在扫描...');
      }
    } on Exception catch (e, st) {
      logger.e('导入文件失败', e, st);
      if (context.mounted) {
        context.showErrorToast('导入失败: $e');
      }
    }
  }

  /// 添加文件路径到媒体库
  Future<void> _addFilesPathToLibrary(
    BuildContext context,
    WidgetRef ref,
    SourceEntity localSource,
    Map<String, SourceConnection> connections,
    FileImportType importType,
  ) async {
    try {
      // 获取虚拟路径前缀
      // 注意：MobileCompositeFileSystem 会将 /documents/xxx 映射到 /files/documents/xxx
      // 所以这里需要使用 /files 前缀，确保路径格式一致
      final subPath = FileImportService.instance.getVirtualPathPrefix(importType);
      final virtualPathPrefix = '/files$subPath';
      final displayName = switch (importType) {
        FileImportType.book => '本机书籍',
        FileImportType.comic => '本机漫画',
        FileImportType.document => '本机文档',
      };

      final newPath = MediaLibraryPath(
        sourceId: localSource.id,
        path: virtualPathPrefix,
        name: displayName,
      );

      // 检查是否已添加（同时检查新旧格式路径）
      final configAsync = ref.read(mediaLibraryConfigProvider);
      final existingPaths = configAsync.valueOrNull?.getPathsForType(mediaType) ?? [];

      // 检查新格式路径
      final newFormatExists = existingPaths.any(
        (p) => p.sourceId == localSource.id && p.path == virtualPathPrefix,
      );

      // 检查旧格式路径（没有 /files 前缀）
      final oldFormatPath = existingPaths.firstWhere(
        (p) => p.sourceId == localSource.id && p.path == subPath,
        orElse: () => MediaLibraryPath(sourceId: '', path: '', name: ''),
      );

      // 如果存在旧格式路径，先删除它
      if (oldFormatPath.sourceId.isNotEmpty) {
        await ref.read(mediaLibraryConfigProvider.notifier).removePath(mediaType, oldFormatPath.id);
        logger.i('MediaLibraryPage: 已删除旧格式路径 ${oldFormatPath.path}');
      }

      if (!newFormatExists) {
        await ref.read(mediaLibraryConfigProvider.notifier).addPath(mediaType, newPath);
      }

      // 触发扫描
      _autoScanPath(ref, mediaType, newPath, connections);

      if (context.mounted) {
        context.showSuccessToast('正在扫描$displayName...');
      }
    } on Exception catch (e, st) {
      logger.e('添加文件路径失败', e, st);
      if (context.mounted) {
        context.showErrorToast('添加失败: $e');
      }
    }
  }

  /// 显示目录选择器
  void _showFolderPicker(
    BuildContext context,
    WidgetRef ref,
    List<SourceEntity> sources,
    Map<String, SourceConnection> connections,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FolderPickerSheet(
        sources: sources,
        connections: connections,
        onSelect: (sourceId, path, name) async {
          final newPath = MediaLibraryPath(
            sourceId: sourceId,
            path: path,
            name: name,
          );
          await ref
              .read(mediaLibraryConfigProvider.notifier)
              .addPath(mediaType, newPath);
          if (context.mounted) {
            Navigator.pop(context);
            context.showSnackBar('已添加目录: $path，正在扫描...');

            // 添加后自动扫描该路径
            _autoScanPath(ref, mediaType, newPath, connections);
          }
        },
      ),
    );
  }

  /// 自动扫描新添加的路径
  ///
  /// 使用 scanSinglePath 只扫描新添加的路径，不会触发其他路径的扫描
  void _autoScanPath(
    WidgetRef ref,
    MediaType type,
    MediaLibraryPath path,
    Map<String, SourceConnection> connections,
  ) {
    switch (type) {
      case MediaType.video:
        AppError.fireAndForget(
          VideoScannerService().scanFilesOnly(
            paths: [path],
            connections: connections,
          ).then((_) async {
            await ref.read(videoListProvider.notifier).reloadFromCache();
            // 扫描完成后自动触发后台刮削（使用最新连接状态）
            final currentConnections = ref.read(activeConnectionsProvider);
            final hasConnected = currentConnections.values
                .any((c) => c.status == SourceStatus.connected);
            logger.d(
              'VideoScan: 扫描完成，准备刮削 - '
              '连接数: ${currentConnections.length}, '
              '有可用连接: $hasConnected',
            );
            if (hasConnected) {
              AppError.fireAndForget(
                VideoScannerService().scrapeMetadata(connections: currentConnections),
                action: 'mediaLibrary.video.scrapeAfterScan',
              );
            } else {
              logger.w('VideoScan: 没有可用连接，跳过刮削');
            }
          }),
          action: 'mediaLibrary.video.scanFilesOnly',
        );
      case MediaType.music:
        // 使用 scanSinglePath 只扫描新添加的路径，不触发其他路径扫描
        AppError.fireAndForget(
          ref
              .read(musicListProvider.notifier)
              .scanSinglePath(path: path, connections: connections),
          action: 'mediaLibrary.music.scanSinglePath',
        );
      case MediaType.photo:
        // 使用 scanSinglePath 只扫描新添加的路径
        AppError.fireAndForget(
          ref
              .read(photoListProvider.notifier)
              .scanSinglePath(path: path, connections: connections),
          action: 'mediaLibrary.photo.scanSinglePath',
        );
      case MediaType.comic:
        // 使用 scanSinglePath 只扫描新添加的路径
        AppError.fireAndForget(
          ref
              .read(comicListProvider.notifier)
              .scanSinglePath(path: path, connections: connections),
          action: 'mediaLibrary.comic.scanSinglePath',
        );
      case MediaType.book:
        // 使用 scanSinglePath 只扫描新添加的路径
        AppError.fireAndForget(
          ref
              .read(bookListProvider.notifier)
              .scanSinglePath(path: path, connections: connections),
          action: 'mediaLibrary.book.scanSinglePath',
        );
      case MediaType.note:
        break;
    }
  }
}

/// 路径卡片 - 显示扫描进度、统计信息和操作按钮
class _PathCard extends ConsumerStatefulWidget {
  const _PathCard({
    required this.path,
    required this.source,
    required this.connection,
    required this.connections,
    required this.mediaType,
    required this.allPaths,
  });

  final MediaLibraryPath path;
  final SourceEntity source;
  final SourceConnection? connection;
  final Map<String, SourceConnection> connections;
  final MediaType mediaType;
  final List<MediaLibraryPath> allPaths;

  @override
  ConsumerState<_PathCard> createState() => _PathCardState();
}

class _PathCardState extends ConsumerState<_PathCard> {
  // 进度更新节流：最小间隔 150ms，避免 UI 卡顿
  static const _progressThrottleMs = 150;
  DateTime _lastProgressUpdate = DateTime.now();

  // 扫描状态（所有媒体类型统一使用）
  bool _isScanning = false;
  double _scanProgress = 0;
  String? _scanDescription;
  int _scannedCount = 0;  // 扫描时的实时数量

  // 视频专用：刮削状态
  bool _isScraping = false;
  double _scrapeProgress = 0;

  // 音乐专用：刮削状态
  bool _isMusicScraping = false;
  double _musicScrapeProgress = 0;
  String? _musicScrapeDescription;
  int _musicScrapeSuccess = 0;
  int _musicScrapeSkip = 0;
  int _musicScrapeFail = 0;

  // 导入状态（本机书籍/漫画/文档）
  bool _isImporting = false;
  double _importProgress = 0;
  String? _importDescription;
  int _importedCount = 0;
  int _importTotalCount = 0;

  // 统计信息
  int _itemCount = 0;
  int _scrapedCount = 0;  // 视频专用：已刮削数量
  int _pendingScrapeCount = 0;  // 视频专用：待刮削数量
  int _retryableCount = 0;  // 视频专用：可重试数量（失败+无TMDB）

  StreamSubscription<VideoScanProgress>? _videoProgressSub;
  StreamSubscription<ScrapeStats>? _scrapeStatsSub;
  StreamSubscription<MediaScanProgress>? _mediaScanProgressSub;
  StreamSubscription<MusicScrapeProgress>? _musicScrapeProgressSub;

  /// 检查是否应该更新进度 UI（节流）
  ///
  /// 对于完成/错误等状态变化总是立即更新，
  /// 对于进行中的进度更新则节流处理
  bool _shouldUpdateProgress({bool forceUpdate = false}) {
    if (forceUpdate) {
      _lastProgressUpdate = DateTime.now();
      return true;
    }
    final now = DateTime.now();
    if (now.difference(_lastProgressUpdate).inMilliseconds >= _progressThrottleMs) {
      _lastProgressUpdate = now;
      return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _loadStats();

    if (widget.mediaType == MediaType.video) {
      // 视频类型：使用 VideoScannerService
      // 注意：刮削是全局的，所以使用全局状态
      _isScraping = VideoScannerService().isScraping;
      // 初始扫描状态：默认为 false，依赖 progressStream 更新
      _isScanning = false;

      if (_isScraping) {
        _loadInitialScrapeStats();
      }

      _videoProgressSub = VideoScannerService().progressStream.listen((progress) {
        if (mounted) {
          // 检查进度事件是否属于当前目录
          final isMyProgress = progress.sourceId == widget.path.sourceId &&
              progress.pathPrefix == widget.path.path;

          if (isMyProgress) {
            // 完成/错误状态强制更新，进行中状态节流更新
            final isTerminalPhase = progress.phase == VideoScanPhase.completed ||
                progress.phase == VideoScanPhase.error;
            if (!_shouldUpdateProgress(forceUpdate: isTerminalPhase)) return;

            setState(() {
              _isScanning = progress.phase == VideoScanPhase.scanning ||
                  progress.phase == VideoScanPhase.savingToDb;
              _scanProgress = progress.progress;
              _scanDescription = progress.description;
              _scannedCount = progress.scannedCount;

              if (isTerminalPhase) {
                _isScanning = false;
              }
            });
          }
        }
      });
      _scrapeStatsSub = VideoScannerService().scrapeStatsStream.listen((globalStats) async {
        if (!mounted) return;
        // 节流：避免过于频繁的数据库查询和 UI 更新
        if (!_shouldUpdateProgress()) return;

        final sourceId = widget.path.sourceId;
        final pathPrefix = widget.path.path;
        // 获取当前目录的刮削统计（而不是使用全局统计）
        final pathStats = await VideoScannerService().getScrapeStats(
          sourceId: sourceId,
          pathPrefix: pathPrefix,
        );
        final retryable = await VideoScannerService().getRetryableCount(
          sourceId: sourceId,
          pathPrefix: pathPrefix,
        );

        if (mounted) {
          setState(() {
            // 关键修复：当前目录的刮削状态应基于：
            // 1. 全局正在刮削 AND 当前目录有待刮削内容
            // 2. 或者当前目录正在被刮削中（scraping > 0）
            final isGlobalScraping = VideoScannerService().isScraping;
            _isScraping = isGlobalScraping &&
                (pathStats.pending > 0 || pathStats.scraping > 0);
            _itemCount = pathStats.total;
            _scrapedCount = pathStats.completed;
            _pendingScrapeCount = pathStats.pending;
            _retryableCount = retryable;
            // 使用当前目录的进度
            _scrapeProgress = pathStats.progress;
          });
        }
      });
    } else {
      // 其他媒体类型：使用 MediaScanProgressService
      final progressService = MediaScanProgressService();
      _isScanning = progressService.isScanning(
        widget.mediaType,
        widget.path.sourceId,
        widget.path.path,
      );

      _mediaScanProgressSub = progressService.progressStream.listen((progress) {
        if (mounted) {
          // 只处理属于当前目录和媒体类型的进度事件
          final isMyProgress = progress.mediaType == widget.mediaType &&
              progress.sourceId == widget.path.sourceId &&
              progress.pathPrefix == widget.path.path;

          if (isMyProgress) {
            // 完成/错误状态强制更新，进行中状态节流更新
            final isTerminalPhase = progress.phase == MediaScanPhase.completed ||
                progress.phase == MediaScanPhase.error;
            if (!_shouldUpdateProgress(forceUpdate: isTerminalPhase)) return;

            setState(() {
              _isScanning = progress.phase == MediaScanPhase.scanning ||
                  progress.phase == MediaScanPhase.processing ||
                  progress.phase == MediaScanPhase.saving;
              _scanProgress = progress.progress;
              _scanDescription = progress.description;
              _scannedCount = progress.scannedCount;

              if (isTerminalPhase) {
                _isScanning = false;
                // 完成后重新加载统计
                _loadStats();
              }
            });
          }
        }
      });
    }

    // 音乐类型：订阅刮削进度
    if (widget.mediaType == MediaType.music) {
      // 检查是否正在刮削当前目录
      final scrapeService = MusicScrapeService();
      _isMusicScraping = scrapeService.isScrapingPath(
        widget.path.sourceId,
        widget.path.path,
      );

      _musicScrapeProgressSub = scrapeService.progressStream.listen((progress) {
        if (!mounted) return;

        // 只处理属于当前目录的进度事件
        final isMyProgress = progress.sourceId == widget.path.sourceId &&
            progress.pathPrefix == widget.path.path;

        if (isMyProgress) {
          // 完成/取消/错误状态强制更新，进行中状态节流更新
          final isTerminalPhase = progress.phase == MusicScrapePhase.completed ||
              progress.phase == MusicScrapePhase.cancelled ||
              progress.phase == MusicScrapePhase.error;
          if (!_shouldUpdateProgress(forceUpdate: isTerminalPhase)) return;

          setState(() {
            _isMusicScraping = progress.phase == MusicScrapePhase.preparing ||
                progress.phase == MusicScrapePhase.scraping;
            _musicScrapeProgress = progress.progress;
            _musicScrapeDescription = progress.currentTrack ?? progress.description;
            _musicScrapeSuccess = progress.successCount;
            _musicScrapeSkip = progress.skipCount;
            _musicScrapeFail = progress.failCount;

            if (isTerminalPhase) {
              _isMusicScraping = false;
              // 完成后重新加载统计
              _loadStats();
            }
          });
        }
      });
    }
  }

  Future<void> _loadInitialScrapeStats() async {
    final sourceId = widget.path.sourceId;
    final pathPrefix = widget.path.path;

    // 获取当前目录的统计数据
    final pathStats = await VideoScannerService().getScrapeStats(
      sourceId: sourceId,
      pathPrefix: pathPrefix,
    );
    final retryable = await VideoScannerService().getRetryableCount(
      sourceId: sourceId,
      pathPrefix: pathPrefix,
    );

    if (mounted) {
      setState(() {
        _itemCount = pathStats.total;
        _scrapedCount = pathStats.completed;
        _pendingScrapeCount = pathStats.pending;
        _retryableCount = retryable;
        // 使用当前目录的进度（而非全局进度）
        _scrapeProgress = pathStats.progress;
        // 关键修复：只有当前目录有待刮削内容时才显示刮削中状态
        final isGlobalScraping = VideoScannerService().isScraping;
        _isScraping = isGlobalScraping && 
            (pathStats.pending > 0 || pathStats.scraping > 0);
      });
    }
  }

  @override
  void dispose() {
    _videoProgressSub?.cancel();
    _scrapeStatsSub?.cancel();
    _mediaScanProgressSub?.cancel();
    _musicScrapeProgressSub?.cancel();
    super.dispose();
  }

  /// 获取非视频类型的扫描进度信息（已废弃，现在使用 MediaScanProgressService）
  /// 保留用于兼容性，但不再监听 provider 状态
  /// 返回: (是否正在扫描, 进度, 描述, 已扫描数量)
  (bool isLoading, double progress, String? description, int scannedCount) _getOtherMediaScanState() => (_isScanning, _scanProgress, _scanDescription, _scannedCount);

  // 以下代码保留用于引用但不再使用
  // ignore: unused_element
  (bool, double, String?, int) _legacyGetOtherMediaScanState() {
    switch (widget.mediaType) {
      case MediaType.music:
        final state = ref.watch(musicListProvider);
        if (state is MusicListLoading) {
          final desc = state.currentFolder ??
              (state.phase == MusicScanPhase.metadata ? '提取元数据...' : '扫描文件...');
          return (true, state.metadataProgress > 0 ? state.metadataProgress : state.progress, desc, state.scannedCount);
        }
        return (false, 0, null, 0);
      case MediaType.photo:
        final state = ref.watch(photoListProvider);
        if (state is PhotoListLoading) {
          final desc = state.currentFolder ?? '扫描照片...';
          return (true, state.progress, desc, state.scannedCount);
        }
        return (false, 0, null, 0);
      case MediaType.book:
        final state = ref.watch(bookListProvider);
        if (state is BookListLoading) {
          final desc = state.currentFolder ?? '扫描书籍...';
          return (true, state.progress, desc, state.scannedCount);
        }
        return (false, 0, null, 0);
      case MediaType.comic:
        final state = ref.watch(comicListProvider);
        if (state is ComicListLoading) {
          final desc = state.currentFolder ?? '扫描漫画...';
          return (true, state.progress, desc, state.scannedCount);
        }
        return (false, 0, null, 0);
      default:
        return (false, 0, null, 0);
    }
  }

  /// 获取实时的媒体数量（扫描中使用扫描数量，否则使用数据库数量）
  int _getDisplayCount(bool isScanning, int scannedCount) {
    if (isScanning) {
      // 所有类型统一使用 _scannedCount
      if (_scannedCount > 0) return _scannedCount;
      if (scannedCount > 0) return scannedCount;
    }
    return _itemCount;
  }

  Future<void> _loadStats() async {
    try {
      final sourceId = widget.path.sourceId;
      final pathPrefix = widget.path.path;

      switch (widget.mediaType) {
        case MediaType.video:
          final stats = await VideoScannerService().getScrapeStats(
            sourceId: sourceId,
            pathPrefix: pathPrefix,
          );
          final retryable = await VideoScannerService().getRetryableCount(
            sourceId: sourceId,
            pathPrefix: pathPrefix,
          );
          if (mounted) {
            setState(() {
              _itemCount = stats.total;
              _scrapedCount = stats.completed;
              _pendingScrapeCount = stats.pending;
              _retryableCount = retryable;
            });
          }
        case MediaType.music:
          final count = await MusicDatabaseService().getCount(
            sourceId: sourceId,
            pathPrefix: pathPrefix,
          );
          if (mounted) setState(() => _itemCount = count);
        case MediaType.photo:
          final count = await PhotoDatabaseService().getCount(
            sourceId: sourceId,
            pathPrefix: pathPrefix,
          );
          if (mounted) setState(() => _itemCount = count);
        case MediaType.book:
          final count = await BookDatabaseService().getCount(
            sourceId: sourceId,
            pathPrefix: pathPrefix,
          );
          if (mounted) setState(() => _itemCount = count);
        case MediaType.comic:
          final count = await ComicLibraryCacheService().getCount(
            sourceId: sourceId,
            pathPrefix: pathPrefix,
          );
          if (mounted) setState(() => _itemCount = count);
        case MediaType.note:
          break;
      }
    } on Exception {
      // 忽略错误
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.connection?.status == SourceStatus.connected;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 获取非视频类型的扫描进度
    final (otherIsScanning, otherProgress, otherDescription, otherScannedCount) =
        widget.mediaType != MediaType.video ? _getOtherMediaScanState() : (false, 0.0, null, 0);

    // 合并扫描状态：视频用 _isScanning，其他用 provider 状态
    final isCurrentlyScanning = widget.mediaType == MediaType.video ? _isScanning : otherIsScanning;
    final currentProgress = widget.mediaType == MediaType.video ? _scanProgress : otherProgress;
    final currentDescription = widget.mediaType == MediaType.video ? _scanDescription : otherDescription;

    // 获取显示的数量（扫描时实时更新）
    final displayCount = _getDisplayCount(isCurrentlyScanning, otherScannedCount);
    final isVideo = widget.mediaType == MediaType.video;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：图标、名称+数量、连接状态、更多按钮
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (widget.path.isEnabled ? _getMediaColor() : Colors.grey)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getMediaIcon(),
                    color: widget.path.isEnabled ? _getMediaColor() : Colors.grey,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 名称 + 数量
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.path.displayName,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: widget.path.isEnabled ? null : Colors.grey,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (displayCount > 0 || isCurrentlyScanning) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: (isCurrentlyScanning ? AppColors.primary : _getMediaColor())
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isCurrentlyScanning && displayCount == 0
                                    ? '...'
                                    : '$displayCount',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isCurrentlyScanning ? AppColors.primary : _getMediaColor(),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.path.path,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // 连接状态指示
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isConnected ? AppColors.success : AppColors.disabled)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isConnected ? Icons.cloud_done : Icons.cloud_off,
                        size: 10,
                        color: isConnected ? AppColors.success : AppColors.disabled,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        widget.source.displayName,
                        style: TextStyle(
                          fontSize: 9,
                          color: isConnected ? AppColors.success : AppColors.disabled,
                        ),
                      ),
                    ],
                  ),
                ),
                // 更多按钮
                _buildMoreButton(context, isCurrentlyScanning),
              ],
            ),

            // 视频专用：刮削统计行（已刮削/待处理）
            if (isVideo && _itemCount > 0) ...[
              const SizedBox(height: 8),
              _buildVideoStatsRow(theme, isDark),
            ],

            // 扫描进度
            if (isCurrentlyScanning) ...[
              const SizedBox(height: 8),
              _buildProgressRow(
                theme: theme,
                isDark: isDark,
                progress: currentProgress,
                description: currentDescription ?? '正在扫描...',
                color: AppColors.primary,
              ),
            ],

            // 导入进度（本机书籍/漫画/文档）
            if (_isImporting) ...[
              const SizedBox(height: 8),
              _buildProgressRow(
                theme: theme,
                isDark: isDark,
                progress: _importProgress,
                description: _importTotalCount > 1
                    ? '正在导入 ($_importedCount/$_importTotalCount): ${_importDescription ?? ''}'
                    : '正在导入: ${_importDescription ?? ''}',
                color: Colors.blue,
              ),
            ],

            // 视频刮削进度
            if (isVideo && _isScraping) ...[
              const SizedBox(height: 6),
              _buildProgressRow(
                theme: theme,
                isDark: isDark,
                progress: _scrapeProgress,
                description: '正在刮削元数据...',
                color: AppColors.warning,
              ),
            ],

            // 音乐刮削进度
            if (widget.mediaType == MediaType.music && _isMusicScraping) ...[
              const SizedBox(height: 6),
              _buildProgressRow(
                theme: theme,
                isDark: isDark,
                progress: _musicScrapeProgress,
                description: _musicScrapeDescription ?? '正在刮削...',
                color: AppColors.fileAudio,
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '成功: $_musicScrapeSuccess  跳过: $_musicScrapeSkip  失败: $_musicScrapeFail',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.grey[500] : Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ],

            // 视频专用：刮削按钮（当有待刮削内容时显示）
            if (isVideo &&
                _pendingScrapeCount > 0 &&
                !_isScraping &&
                isConnected) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _startScraping,
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                  label: Text('刮削元数据 ($_pendingScrapeCount 待处理)', style: const TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.warning,
                    side: BorderSide(color: AppColors.warning),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],

            // 视频专用：重试按钮（当有失败或无TMDB数据的内容时显示）
            if (isVideo &&
                _retryableCount > 0 &&
                _pendingScrapeCount == 0 &&
                !_isScraping &&
                isConnected) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _retryScraping,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text('重试刮削 ($_retryableCount 失败/无数据)', style: const TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 视频专用：刮削统计行（更紧凑的样式）
  Widget _buildVideoStatsRow(ThemeData theme, bool isDark) => Row(
    children: [
      // 已刮削
      _buildCompactStatChip(
        icon: Icons.check_circle_outline,
        label: '已刮削',
        value: _scrapedCount,
        color: AppColors.success,
        isDark: isDark,
      ),
      const SizedBox(width: 8),
      // 待处理
      _buildCompactStatChip(
        icon: Icons.pending_outlined,
        label: '待处理',
        value: _pendingScrapeCount,
        color: _pendingScrapeCount > 0 ? AppColors.warning : AppColors.disabled,
        isDark: isDark,
      ),
    ],
  );

  Widget _buildCompactStatChip({
    required IconData icon,
    required String label,
    required int value,
    required Color color,
    required bool isDark,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          '$label $value',
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );

  Widget _buildProgressRow({
    required ThemeData theme,
    required bool isDark,
    required double progress,
    required String description,
    required Color color,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          // 圆形指示器：始终显示为不停转动的 loading 效果
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              description,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (progress > 0)
            Text(
              '${(progress * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
      if (progress > 0) ...[
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
          color: color,
        ),
      ],
    ],
  );

  Widget _buildMoreButton(BuildContext context, bool isCurrentlyScanning) => PopupMenuButton<String>(
    onSelected: (value) => _handleMenuAction(value, context),
    itemBuilder: (context) {
      final isConnected = widget.connection?.status == SourceStatus.connected;
      final items = <PopupMenuEntry<String>>[
        // 扫描按钮
        PopupMenuItem(
          value: 'scan',
          enabled: isConnected && !isCurrentlyScanning,
          child: Row(
            children: [
              Icon(
                isCurrentlyScanning ? Icons.hourglass_empty : Icons.refresh_rounded,
                color: isConnected && !isCurrentlyScanning ? null : Colors.grey,
              ),
              const SizedBox(width: 12),
              Text(isCurrentlyScanning ? '扫描中...' : '扫描'),
            ],
          ),
        ),
      ];

      // 视频专用：刮削按钮
      if (widget.mediaType == MediaType.video) {
        items.add(PopupMenuItem(
          value: 'scrape',
          enabled: isConnected && !_isScraping && _itemCount > 0,
          child: Row(
            children: [
              Icon(
                _isScraping ? Icons.hourglass_empty : Icons.auto_fix_high_rounded,
                color: isConnected && !_isScraping && _itemCount > 0
                    ? AppColors.warning
                    : AppColors.disabled,
              ),
              const SizedBox(width: 12),
              Text(
                _isScraping ? '刮削中...' : '刮削元数据',
                style: TextStyle(
                  color: isConnected && !_isScraping && _itemCount > 0
                      ? AppColors.warning
                      : AppColors.disabled,
                ),
              ),
            ],
          ),
        ));

        // 停止刮削
        if (_isScraping) {
          items.add(PopupMenuItem(
            value: 'stop_scrape',
            child: Row(
              children: [
                Icon(Icons.stop_rounded, color: AppColors.error),
                SizedBox(width: 12),
                Text('停止刮削', style: TextStyle(color: AppColors.error)),
              ],
            ),
          ));
        }
      }

      // 音乐专用：批量刮削按钮（仅在扫描完成后显示）
      if (widget.mediaType == MediaType.music && _itemCount > 0) {
        items.add(PopupMenuItem(
          value: 'music_scrape',
          enabled: isConnected && !isCurrentlyScanning && !_isMusicScraping,
          child: Row(
            children: [
              Icon(
                _isMusicScraping ? Icons.hourglass_empty : Icons.auto_fix_high_rounded,
                color: isConnected && !isCurrentlyScanning && !_isMusicScraping
                    ? AppColors.fileAudio
                    : AppColors.disabled,
              ),
              const SizedBox(width: 12),
              Text(
                _isMusicScraping ? '刮削中...' : '批量刮削',
                style: TextStyle(
                  color: isConnected && !isCurrentlyScanning && !_isMusicScraping
                      ? AppColors.fileAudio
                      : AppColors.disabled,
                ),
              ),
            ],
          ),
        ));

        // 停止音乐刮削
        if (_isMusicScraping) {
          items.add(PopupMenuItem(
            value: 'stop_music_scrape',
            child: Row(
              children: [
                Icon(Icons.stop_rounded, color: AppColors.error),
                SizedBox(width: 12),
                Text('停止刮削', style: TextStyle(color: AppColors.error)),
              ],
            ),
          ));
        }
      }

      // 本机书籍/漫画/文档：导入更多文件
      final isMobile = !kIsWeb && (Platform.isIOS || Platform.isAndroid);
      final isLocalSource = widget.source.type == SourceType.local;
      final isImportableType = widget.mediaType == MediaType.book ||
          widget.mediaType == MediaType.comic ||
          widget.mediaType == MediaType.note;

      if (isMobile && isLocalSource && isImportableType) {
        final importLabel = switch (widget.mediaType) {
          MediaType.book => _isImporting ? '正在导入...' : '导入更多书籍',
          MediaType.comic => _isImporting ? '正在导入...' : '导入更多漫画',
          _ => _isImporting ? '正在导入...' : '导入更多文件',
        };
        items.add(PopupMenuItem(
          value: 'import_more',
          enabled: !_isImporting,
          child: Row(
            children: [
              Icon(
                _isImporting ? Icons.hourglass_empty : Icons.add_circle_outline,
                color: _isImporting ? Colors.grey : Colors.blue,
              ),
              const SizedBox(width: 12),
              Text(
                importLabel,
                style: TextStyle(color: _isImporting ? Colors.grey : Colors.blue),
              ),
            ],
          ),
        ));
      }

      items.addAll([
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'toggle',
          child: Row(
            children: [
              Icon(widget.path.isEnabled ? Icons.visibility_off : Icons.visibility),
              const SizedBox(width: 12),
              Text(widget.path.isEnabled ? '停用' : '启用'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, color: AppColors.error),
              SizedBox(width: 12),
              Text('删除', style: TextStyle(color: AppColors.error)),
            ],
          ),
        ),
      ]);

      return items;
    },
  );

  Future<void> _handleMenuAction(String value, BuildContext context) async {
    switch (value) {
      case 'scan':
        await _scanPath();
      case 'scrape':
        await _startScraping();
      case 'stop_scrape':
        _stopScraping();
      case 'music_scrape':
        await _startMusicScraping(context);
      case 'stop_music_scrape':
        _stopMusicScraping();
      case 'import_more':
        await _importMoreFiles(context);
      case 'toggle':
        await ref
            .read(mediaLibraryConfigProvider.notifier)
            .togglePath(widget.mediaType, widget.path.id, enabled: !widget.path.isEnabled);
      case 'delete':
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除目录'),
            content: Text('确定要从媒体库中移除 "${widget.path.displayName}" 吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (confirm ?? false) {
          await ref
              .read(mediaLibraryConfigProvider.notifier)
              .removePath(widget.mediaType, widget.path.id);
        }
    }
  }

  Future<void> _scanPath() async {
    // 注意：不在这里设置 _isScanning = true
    // 因为进度会通过 progressStream 实时更新

    try {
      var count = 0;
      switch (widget.mediaType) {
        case MediaType.video:
          count = await VideoScannerService().scanFilesOnly(
            paths: [widget.path],
            connections: widget.connections,
          );
          if (!mounted) return;
          await ref.read(videoListProvider.notifier).reloadFromCache();
          await _loadStats();
          if (mounted) {
            context.showSuccessToast('扫描完成，共 $count 个视频，开始刮削元数据...');
          }
          // 扫描完成后自动触发后台刮削（使用最新连接状态）
          if (!mounted) return;
          final currentConnections = ref.read(activeConnectionsProvider);
          if (currentConnections.values.any((c) => c.status == SourceStatus.connected)) {
            AppError.fireAndForget(
              VideoScannerService().scrapeMetadata(connections: currentConnections),
              action: 'mediaLibrary.video.scrapeMetadata',
            );
          }
        case MediaType.music:
          // 使用单目录扫描
          if (!mounted) return;
          count = await ref.read(musicListProvider.notifier).scanSinglePath(
            path: widget.path,
            connections: widget.connections,
          );
          await _loadStats();
          if (mounted) {
            context.showSuccessToast('扫描完成，共 $count 首音乐');
          }
        case MediaType.photo:
          if (!mounted) return;
          count = await ref.read(photoListProvider.notifier).scanSinglePath(
            path: widget.path,
            connections: widget.connections,
          );
          await _loadStats();
          if (mounted) {
            context.showSuccessToast('扫描完成，共 $count 张照片');
          }
        case MediaType.comic:
          if (!mounted) return;
          count = await ref.read(comicListProvider.notifier).scanSinglePath(
            path: widget.path,
            connections: widget.connections,
          );
          await _loadStats();
          if (mounted) {
            context.showSuccessToast('扫描完成，共 $count 本漫画');
          }
        case MediaType.book:
          if (!mounted) return;
          count = await ref.read(bookListProvider.notifier).scanSinglePath(
            path: widget.path,
            connections: widget.connections,
          );
          await _loadStats();
          if (mounted) {
            context.showSuccessToast('扫描完成，共 $count 本书');
          }
        case MediaType.note:
          break;
      }
    // ignore: avoid_catches_without_on_clauses
    } catch (e, st) {
      // 使用通用 catch 捕获所有类型（SMB 库可能抛出 String 类型异常）
      if (mounted) {
        context.handleError(e, st, '扫描失败');
      }
    }
    // 不需要在 finally 中重置 _isScanning，因为它通过 progressStream 管理
  }

  Future<void> _startScraping() async {
    // 检查是否已在刮削中
    if (VideoScannerService().isScraping) {
      context.showInfoToast('刮削任务正在进行中...');
      return;
    }

    // 获取最新的连接状态（而不是使用可能过时的 widget.connections）
    final connections = ref.read(activeConnectionsProvider);

    // 检查是否有可用连接
    final hasConnected = connections.values.any((c) => c.status == SourceStatus.connected);
    if (!hasConnected) {
      if (mounted) {
        context.showWarningToast('没有可用连接，请先连接源');
      }
      return;
    }

    setState(() => _isScraping = true);

    try {
      // 直接等待刮削完成（不使用 unawaited）
      await VideoScannerService().scrapeMetadata(
        connections: connections,
      );

      await _loadStats();
      await ref.read(videoListProvider.notifier).reloadFromCache();
      if (mounted) {
        setState(() => _isScraping = false);
        context.showSuccessToast('元数据刮削完成');
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _isScraping = false);
        context.showErrorToast('刮削失败: $e');
      }
    }
  }

  void _stopScraping() {
    VideoScannerService().stopScraping();
    setState(() => _isScraping = false);
    context.showInfoToast('正在停止刮削...');
  }

  /// 重试刮削失败和无 TMDB 数据的视频
  Future<void> _retryScraping() async {
    // 检查是否已在刮削中
    if (VideoScannerService().isScraping) {
      context.showInfoToast('刮削任务正在进行中...');
      return;
    }

    // 获取最新的连接状态（而不是使用可能过时的 widget.connections）
    final connections = ref.read(activeConnectionsProvider);

    // 检查是否有可用连接
    final hasConnected = connections.values.any((c) => c.status == SourceStatus.connected);
    if (!hasConnected) {
      if (mounted) {
        context.showWarningToast('没有可用连接，请先连接源');
      }
      return;
    }

    setState(() => _isScraping = true);

    try {
      context.showInfoToast('开始重试刮削 $_retryableCount 个视频...');

      await VideoScannerService().retryScrapeFailedVideos(
        connections: connections,
      );

      if (!mounted) return;

      await _loadStats();
      await _loadInitialScrapeStats();
      await ref.read(videoListProvider.notifier).reloadFromCache();

      if (!mounted) return;

      setState(() => _isScraping = false);
      context.showSuccessToast('重试刮削完成');
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _isScraping = false);
        context.showErrorToast('重试刮削失败: $e');
      }
    }
  }

  /// 启动音乐批量刮削（后台执行，不阻塞用户操作）
  Future<void> _startMusicScraping(BuildContext context) async {
    // 检查连接状态
    if (widget.connection == null ||
        widget.connection!.status != SourceStatus.connected) {
      context.showWarningToast('请先连接源');
      return;
    }

    // 检查是否有音乐
    if (_itemCount == 0) {
      context.showInfoToast('没有可刮削的音乐，请先扫描');
      return;
    }

    // 检查是否已在刮削中
    final scrapeService = MusicScrapeService();
    if (scrapeService.isScraping) {
      context.showInfoToast('刮削任务正在进行中...');
      return;
    }

    // 启动后台刮削
    setState(() => _isMusicScraping = true);
    context.showSuccessToast('开始后台刮削，共 $_itemCount 首音乐');

    // 在后台执行刮削
    AppError.fireAndForget(
      scrapeService.startScraping(
        sourceId: widget.path.sourceId,
        pathPrefix: widget.path.path,
        connection: widget.connection!,
      ),
      action: 'mediaLibrary.music.startScraping',
    );
  }

  /// 停止音乐刮削
  void _stopMusicScraping() {
    MusicScrapeService().stopScraping();
    setState(() => _isMusicScraping = false);
    context.showInfoToast('正在停止刮削...');
  }

  /// 导入更多文件（本机书籍/漫画/文档）
  ///
  /// 导入进度在卡片上显示，不阻塞用户操作
  Future<void> _importMoreFiles(BuildContext context) async {
    // 避免重复导入
    if (_isImporting) {
      context.showInfoToast('正在导入中...');
      return;
    }

    final importType = switch (widget.mediaType) {
      MediaType.book => FileImportType.book,
      MediaType.comic => FileImportType.comic,
      _ => FileImportType.document,
    };

    final typeDisplayName = switch (widget.mediaType) {
      MediaType.book => '书籍',
      MediaType.comic => '漫画',
      _ => '文件',
    };

    try {
      // 导入文件（文件选择器阶段不显示进度）
      final importedFiles = await FileImportService.instance.importFiles(
        type: importType,
        allowMultiple: true,
        onProgress: (current, total, fileName, copied, fileSize) {
          // 首次收到进度时开始显示导入状态
          if (mounted) {
            setState(() {
              _isImporting = true;
              _importedCount = current;
              _importTotalCount = total;
              _importDescription = fileName;
              // 计算当前文件的进度
              _importProgress = fileSize > 0 ? copied / fileSize : 0;
            });
          }
        },
      );

      // 导入完成，重置状态
      if (mounted) {
        setState(() {
          _isImporting = false;
          _importProgress = 0;
          _importDescription = null;
          _importedCount = 0;
          _importTotalCount = 0;
        });
      }

      if (importedFiles.isEmpty) {
        if (context.mounted) {
          context.showInfoToast('未选择文件');
        }
        return;
      }

      // 扫描新导入的文件
      await _scanPath();

      if (context.mounted) {
        context.showSuccessToast('已导入 ${importedFiles.length} 个$typeDisplayName');
      }
    } on Exception catch (e, st) {
      // 重置导入状态
      if (mounted) {
        setState(() {
          _isImporting = false;
          _importProgress = 0;
          _importDescription = null;
        });
      }

      logger.e('导入文件失败', e, st);
      if (context.mounted) {
        context.showErrorToast('导入失败: $e');
      }
    }
  }

  Color _getMediaColor() => switch (widget.mediaType) {
    MediaType.video => AppColors.fileVideo,
    MediaType.music => AppColors.fileAudio,
    MediaType.photo => AppColors.fileImage,
    MediaType.comic => AppColors.accent,
    MediaType.book => AppColors.tertiary,
    MediaType.note => AppColors.secondary,
  };

  IconData _getMediaIcon() => switch (widget.mediaType) {
    MediaType.video => Icons.video_library_rounded,
    MediaType.music => Icons.library_music_rounded,
    MediaType.photo => Icons.photo_library_rounded,
    MediaType.comic => Icons.collections_bookmark_rounded,
    MediaType.book => Icons.library_books_rounded,
    MediaType.note => Icons.note_rounded,
  };
}
