import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';

/// 上传目标选择结果
class UploadTarget {
  const UploadTarget({
    required this.sourceId,
    required this.sourceName,
    required this.path,
    required this.pathDisplayName,
  });

  /// 目标源 ID
  final String sourceId;

  /// 目标源名称
  final String sourceName;

  /// 目标路径
  final String path;

  /// 路径显示名称
  final String pathDisplayName;
}

/// 上传目标选择器
class TargetPickerSheet extends ConsumerStatefulWidget {
  const TargetPickerSheet({
    super.key,
    required this.mediaType,
    this.title = '选择上传目标',
  });

  /// 媒体类型（用于筛选对应的媒体库）
  final MediaType mediaType;

  /// 标题
  final String title;

  /// 显示选择器
  static Future<UploadTarget?> show(
    BuildContext context, {
    required MediaType mediaType,
    String title = '选择上传目标',
  }) => showAdaptiveModalSheet<UploadTarget>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => TargetPickerSheet(
        mediaType: mediaType,
        title: title,
      ),
    );

  @override
  ConsumerState<TargetPickerSheet> createState() => _TargetPickerSheetState();
}

class _TargetPickerSheetState extends ConsumerState<TargetPickerSheet> {
  String? _selectedSourceId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final connections = ref.watch(activeConnectionsProvider);
    final libraryConfig = ref.watch(mediaLibraryConfigProvider);

    // 获取已连接的存储类源（排除本机源）
    final storageConnections = connections.entries
        .where((e) =>
            e.value.status == SourceStatus.connected &&
            e.value.source.type.category.isStorageCategory &&
            !_isLocalSource(e.value.source.type))
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // 拖动手柄
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 标题
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  widget.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(),

          // 内容
          Expanded(
            child: storageConnections.isEmpty
                ? _buildEmptyState(context)
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: storageConnections.length,
                    itemBuilder: (context, index) {
                      final entry = storageConnections[index];
                      return _buildSourceItem(
                        context,
                        entry.value,
                        libraryConfig.valueOrNull,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  bool _isLocalSource(SourceType type) => type == SourceType.local;

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '没有可用的上传目标',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '请先连接到 NAS 或云存储',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceItem(
    BuildContext context,
    SourceConnection connection,
    MediaLibraryConfig? libraryConfig,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final source = connection.source;
    final isExpanded = _selectedSourceId == source.id;

    // 获取该源下对应媒体类型的媒体库
    final libraries = libraryConfig
            ?.getPathsForType(widget.mediaType)
            .where((lib) => lib.sourceId == source.id)
            .toList() ??
        [];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          // 源标题
          ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                source.type.icon,
                color: colorScheme.primary,
                size: 22,
              ),
            ),
            title: Text(source.name),
            subtitle: Text(
              source.host,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: Icon(
              isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            ),
            onTap: () {
              setState(() {
                _selectedSourceId = isExpanded ? null : source.id;
              });
            },
          ),

          // 展开的媒体库列表
          if (isExpanded) ...[
            const Divider(height: 1),
            if (libraries.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '该源没有配置${_getMediaTypeName(widget.mediaType)}媒体库',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ...libraries.map((lib) => _buildLibraryItem(context, source, lib)),

            // 选择自定义路径选项
            ListTile(
              leading: const SizedBox(width: 24),
              title: const Text('选择其他目录...'),
              trailing: const Icon(Icons.folder_open_rounded, size: 20),
              onTap: () => _showDirectoryPicker(context, connection),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLibraryItem(
    BuildContext context,
    SourceEntity source,
    MediaLibraryPath library,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      leading: const SizedBox(width: 24),
      title: Text(library.displayName),
      subtitle: Text(
        library.path,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        final target = UploadTarget(
          sourceId: source.id,
          sourceName: source.name,
          path: library.path,
          pathDisplayName: library.displayName,
        );
        Navigator.pop(context, target);
      },
    );
  }

  Future<void> _showDirectoryPicker(
    BuildContext context,
    SourceConnection connection,
  ) async {
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _DirectoryBrowserPage(connection: connection),
        fullscreenDialog: true,
      ),
    );

    if (path != null && path.isNotEmpty && mounted) {
      final target = UploadTarget(
        sourceId: connection.source.id,
        sourceName: connection.source.name,
        path: path,
        pathDisplayName: path,
      );
      Navigator.pop(context, target);
    }
  }

  String _getMediaTypeName(MediaType type) => switch (type) {
        MediaType.photo => '照片',
        MediaType.music => '音乐',
        MediaType.video => '视频',
        MediaType.book => '图书',
        MediaType.comic => '漫画',
        MediaType.note => '笔记',
      };
}

/// 目录浏览选择页
///
/// 通过 [NasFileSystem.listDirectory] 浏览远端目录树，只显示文件夹。
/// 提供"返回上一级"、"新建文件夹"、"选择此目录"操作。
class _DirectoryBrowserPage extends StatefulWidget {
  const _DirectoryBrowserPage({required this.connection});

  final SourceConnection connection;

  @override
  State<_DirectoryBrowserPage> createState() => _DirectoryBrowserPageState();
}

class _DirectoryBrowserPageState extends State<_DirectoryBrowserPage> {
  String _currentPath = '/';
  List<FileItem> _entries = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDirectory(_currentPath);
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await widget.connection.adapter.fileSystem.listDirectory(path);
      if (!mounted) return;
      setState(() {
        _currentPath = path;
        _entries = entries.where((e) => e.isDirectory).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _loading = false;
      });
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'directoryPicker.list', {'path': path});
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _parentPath(String path) {
    if (path == '/' || path.isEmpty) return '/';
    final trimmed = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final lastSep = trimmed.lastIndexOf('/');
    if (lastSep <= 0) return '/';
    return trimmed.substring(0, lastSep);
  }

  String _joinPath(String base, String name) {
    if (base.endsWith('/')) return '$base$name';
    return '$base/$name';
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final folderName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '文件夹名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (folderName == null || folderName.isEmpty) return;
    if (!mounted) return;

    try {
      final newPath = _joinPath(_currentPath, folderName);
      await widget.connection.adapter.fileSystem.createDirectory(newPath);
      await _loadDirectory(_currentPath);
    } on Exception catch (e, st) {
      if (mounted) {
        AppError.handleWithUI(context, e, st, '创建失败', 'directoryPicker.create');
      } else {
        AppError.handle(e, st, 'directoryPicker.create');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final atRoot = _currentPath == '/' || _currentPath.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.connection.source.name),
        actions: [
          IconButton(
            tooltip: '新建文件夹',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _createFolder,
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _currentPath),
            child: const Text('选择此处'),
          ),
        ],
      ),
      body: Column(
        children: [
          // 当前路径条
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                const Icon(Icons.folder_open_rounded, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentPath,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (!atRoot)
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: const Text('返回上一级'),
              onTap: () => _loadDirectory(_parentPath(_currentPath)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
                              const SizedBox(height: 12),
                              Text('加载失败: $_error', textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: () => _loadDirectory(_currentPath),
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _entries.isEmpty
                        ? const Center(child: Text('当前目录为空'))
                        : ListView.builder(
                            itemCount: _entries.length,
                            itemBuilder: (_, index) {
                              final item = _entries[index];
                              return ListTile(
                                leading: const Icon(Icons.folder_rounded),
                                title: Text(item.name),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _loadDirectory(
                                  _joinPath(_currentPath, item.name),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
