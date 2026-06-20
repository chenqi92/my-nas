import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 可浏览的连接（统一 NAS 和媒体服务器）
class BrowsableConnection {
  const BrowsableConnection._({
    required this.sourceId,
    required this.fileSystem,
    required this.status,
    required this.isMediaServer,
  });

  factory BrowsableConnection.fromNas(SourceConnection conn) => BrowsableConnection._(
        sourceId: conn.source.id,
        fileSystem: conn.adapter.fileSystem,
        status: conn.status,
        isMediaServer: false,
      );

  factory BrowsableConnection.fromMediaServer(MediaServerConnection conn) =>
      BrowsableConnection._(
        sourceId: conn.source.id,
        fileSystem: conn.adapter.virtualFileSystem,
        status: conn.status,
        isMediaServer: true,
      );

  final String sourceId;
  final NasFileSystem fileSystem;
  final SourceStatus status;
  final bool isMediaServer;
}

/// 当前路径
final currentPathProvider = StateProvider<String>((ref) => '/');

/// 当前选中的源ID（用于文件浏览器）
final selectedSourceIdProvider = StateProvider<String?>((ref) => null);

/// 获取当前选中的源连接（NAS）
final selectedSourceConnectionProvider = Provider<SourceConnection?>((ref) {
  final selectedId = ref.watch(selectedSourceIdProvider);
  if (selectedId == null) return null;

  final connections = ref.watch(activeConnectionsProvider);
  return connections[selectedId];
});

/// 获取当前选中的可浏览连接（统一 NAS 和媒体服务器）
final selectedBrowsableConnectionProvider = Provider<BrowsableConnection?>((ref) {
  final selectedId = ref.watch(selectedSourceIdProvider);
  if (selectedId == null) return null;

  // 先检查 NAS 连接
  final nasConnections = ref.watch(activeConnectionsProvider);
  final nasConn = nasConnections[selectedId];
  if (nasConn != null && nasConn.status == SourceStatus.connected) {
    return BrowsableConnection.fromNas(nasConn);
  }

  // 再检查媒体服务器连接
  final mediaConnections = ref.watch(activeMediaServerConnectionsProvider);
  final mediaConn = mediaConnections[selectedId];
  if (mediaConn != null && mediaConn.status == SourceStatus.connected) {
    return BrowsableConnection.fromMediaServer(mediaConn);
  }

  return null;
});

/// 获取所有已连接的源列表（NAS）
final connectedSourcesProvider = Provider<List<(SourceEntity, SourceConnection)>>((ref) {
  final sources = ref.watch(sourcesProvider).valueOrNull ?? [];
  final connections = ref.watch(activeConnectionsProvider);

  final result = <(SourceEntity, SourceConnection)>[];
  for (final source in sources) {
    final connection = connections[source.id];
    if (connection != null && connection.status == SourceStatus.connected) {
      result.add((source, connection));
    }
  }
  return result;
});

/// 获取所有可浏览的已连接源列表（包括 NAS 和媒体服务器）
final browsableSourcesProvider = Provider<List<(SourceEntity, BrowsableConnection)>>((ref) {
  final sources = ref.watch(sourcesProvider).valueOrNull ?? [];
  final nasConnections = ref.watch(activeConnectionsProvider);
  final mediaConnections = ref.watch(activeMediaServerConnectionsProvider);

  final result = <(SourceEntity, BrowsableConnection)>[];
  for (final source in sources) {
    // 检查 NAS 连接
    final nasConn = nasConnections[source.id];
    if (nasConn != null && nasConn.status == SourceStatus.connected) {
      result.add((source, BrowsableConnection.fromNas(nasConn)));
      continue;
    }

    // 检查媒体服务器连接
    final mediaConn = mediaConnections[source.id];
    if (mediaConn != null && mediaConn.status == SourceStatus.connected) {
      result.add((source, BrowsableConnection.fromMediaServer(mediaConn)));
    }
  }
  return result;
});

/// 当前选中的连接是否支持写操作
final supportsWriteOperationsProvider = Provider<bool>((ref) {
  final connection = ref.watch(selectedBrowsableConnectionProvider);
  // 媒体服务器不支持写操作
  return connection != null && !connection.isMediaServer;
});

/// 获取当前选中的源实体
final selectedSourceEntityProvider = Provider<SourceEntity?>((ref) {
  final selectedId = ref.watch(selectedSourceIdProvider);
  if (selectedId == null) return null;

  final sources = ref.watch(sourcesProvider).valueOrNull ?? [];
  return sources.where((s) => s.id == selectedId).firstOrNull;
});

/// 文件列表状态
final fileListProvider =
    StateNotifierProvider<FileListNotifier, FileListState>(FileListNotifier.new);

/// 视图模式
final viewModeProvider = StateProvider<ViewMode>((ref) => ViewMode.grid);

/// 排序方式
final sortModeProvider = StateProvider<SortMode>((ref) => SortMode.name);

/// 排序方向
final sortAscendingProvider = StateProvider<bool>((ref) => true);

/// 多选模式
final multiSelectModeProvider = StateProvider<bool>((ref) => false);

/// 选中的文件路径集合
final selectedFilesProvider = StateProvider<Set<String>>((ref) => {});

enum ViewMode { list, grid }

enum SortMode { name, size, date, type }

/// 文件列表状态
sealed class FileListState {
  const FileListState();
}

class FileListLoading extends FileListState {
  const FileListLoading();
}

class FileListLoaded extends FileListState {
  const FileListLoaded({
    required this.files,
    required this.path,
  });
  final List<FileItem> files;
  final String path;
}

class FileListError extends FileListState {
  const FileListError({
    required this.message,
    this.failedPath,
    this.hasCustomPath = false,
  });
  final String message;

  /// 加载失败的路径
  final String? failedPath;

  /// 是否尝试加载的是自定义配置路径（非根目录）
  final bool hasCustomPath;
}

/// 未连接到 NAS 的状态
class FileListNotConnected extends FileListState {
  const FileListNotConnected();
}

/// 文件列表管理
class FileListNotifier extends StateNotifier<FileListState> {
  FileListNotifier(this._ref) : super(const FileListLoading());

  final Ref _ref;

  /// 获取当前选中的 NAS 连接（用于写操作）
  SourceConnection? _getSelectedNasConnection() {
    final connection = _ref.read(selectedSourceConnectionProvider);
    if (connection != null && connection.status == SourceStatus.connected) {
      return connection;
    }
    return null;
  }

  /// 加载源配置的初始路径
  ///
  /// 根据源的 extraConfig 中的配置（如 shareName、path）确定初始路径
  Future<void> loadInitialDirectory() async {
    final source = _ref.read(selectedSourceEntityProvider);
    final initialPath = source?.initialBrowsePath ?? '/';
    await loadDirectory(initialPath);
  }

  Future<void> loadDirectory(String path) async {
    state = const FileListLoading();

    // 首先尝试使用选中的源
    var connection = _ref.read(selectedBrowsableConnectionProvider);

    // 如果没有选中的源，自动选择第一个已连接的源
    if (connection == null || connection.status != SourceStatus.connected) {
      final browsableSources = _ref.read(browsableSourcesProvider);
      if (browsableSources.isEmpty) {
        state = const FileListNotConnected();
        return;
      }
      // 自动选择第一个已连接的源
      final (source, conn) = browsableSources.first;
      _ref.read(selectedSourceIdProvider.notifier).state = source.id;
      connection = conn;
    }

    try {
      // 添加超时保护,防止长时间卡住
      final files = await connection.fileSystem
          .listDirectory(path)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException(
              '加载目录超时 (30秒)',
              const Duration(seconds: 30),
            ),
          );

      // 排序
      final sortMode = _ref.read(sortModeProvider);
      final ascending = _ref.read(sortAscendingProvider);
      final sortedFiles = _sortFiles(files, sortMode, ascending);

      _ref.read(currentPathProvider.notifier).state = path;
      state = FileListLoaded(files: sortedFiles, path: path);
    } on Exception catch (e, stack) {
      // 捕获所有类型的错误(包括Error和Exception)
      final errorMessage = e is TimeoutException
          ? '加载目录超时，请检查网络连接或目录访问权限'
          : '加载目录失败: $e $stack';

      // 检查当前源是否配置了自定义路径
      final source = _ref.read(selectedSourceEntityProvider);
      final hasCustomPath = source?.hasCustomBrowsePath ?? false;

      state = FileListError(
        message: errorMessage,
        failedPath: path,
        hasCustomPath: hasCustomPath && path != '/',
      );
    }
  }

  /// 返回根目录（忽略源配置的初始路径）
  Future<void> loadRootDirectory() async {
    await loadDirectory('/');
  }

  Future<void> refresh() async {
    final currentPath = _ref.read(currentPathProvider);
    await loadDirectory(currentPath);
  }

  Future<void> navigateUp() async {
    final currentPath = _ref.read(currentPathProvider);
    if (currentPath == '/' || currentPath.isEmpty) return;

    final parentPath = _getParentPath(currentPath);
    if (parentPath == null) return;

    await loadDirectory(parentPath);
  }

  /// 获取父目录路径，正确处理跨平台路径分隔符
  String? _getParentPath(String currentPath) {
    // 检测是否是 Windows 路径（包含驱动器字母如 C: 或 D:）
    final isWindowsPath = currentPath.length >= 2 &&
        currentPath[1] == ':' &&
        RegExp('^[A-Za-z]').hasMatch(currentPath);

    if (isWindowsPath) {
      // Windows 路径处理
      final normalized = currentPath.replaceAll('/', r'\');
      // 移除末尾的 \
      final trimmed = normalized.endsWith(r'\')
          ? normalized.substring(0, normalized.length - 1)
          : normalized;

      // 如果已经是驱动器根目录（如 C:），返回根目录列表
      if (trimmed.length == 2 && trimmed[1] == ':') {
        return '/';
      }

      final lastSep = trimmed.lastIndexOf(r'\');
      if (lastSep <= 2) {
        // 返回驱动器根目录
        return '${trimmed.substring(0, 2)}\\';
      }
      return trimmed.substring(0, lastSep);
    } else {
      // Unix 路径处理
      final parts = currentPath.split('/').where((p) => p.isNotEmpty).toList();
      if (parts.isEmpty) return null;

      parts.removeLast();
      return parts.isEmpty ? '/' : '/${parts.join('/')}';
    }
  }

  Future<void> createFolder(String name) async {
    final connection = _getSelectedNasConnection();
    if (connection == null) {
      throw UnsupportedError('当前连接不支持创建文件夹');
    }

    final currentPath = _ref.read(currentPathProvider);
    final newPath = currentPath == '/' ? '/$name' : '$currentPath/$name';

    await connection.adapter.fileSystem.createDirectory(newPath);
    await refresh();
  }

  Future<void> delete(String path, {bool skipRefresh = false}) async {
    final connection = _getSelectedNasConnection();
    if (connection == null) {
      throw UnsupportedError('当前连接不支持删除操作');
    }

    await connection.adapter.fileSystem.delete(path);
    if (!skipRefresh) await refresh();
  }

  Future<void> rename(String oldPath, String newName) async {
    final connection = _getSelectedNasConnection();
    if (connection == null) {
      throw UnsupportedError('当前连接不支持重命名操作');
    }

    // 检测是否是 Windows 路径
    final isWindowsPath = oldPath.length >= 2 &&
        oldPath[1] == ':' &&
        RegExp('^[A-Za-z]').hasMatch(oldPath);

    String newPath;
    if (isWindowsPath) {
      final normalized = oldPath.replaceAll('/', r'\');
      final lastSep = normalized.lastIndexOf(r'\');
      final parentPath = lastSep > 0 ? normalized.substring(0, lastSep) : normalized;
      newPath = '$parentPath\\$newName';
    } else {
      final lastSep = oldPath.lastIndexOf('/');
      final parentPath = lastSep > 0 ? oldPath.substring(0, lastSep) : '';
      newPath = '$parentPath/$newName';
    }

    await connection.adapter.fileSystem.rename(oldPath, newPath);
    await refresh();
  }

  Future<void> uploadFile(
    String localPath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    final connection = _getSelectedNasConnection();
    if (connection == null) return;

    final currentPath = _ref.read(currentPathProvider);
    await connection.adapter.fileSystem.upload(
      localPath,
      currentPath,
      fileName: fileName,
      onProgress: onProgress,
    );
    await refresh();
  }

  Future<void> copyTo(String sourcePath, String destPath,
      {bool skipRefresh = false}) async {
    final connection = _getSelectedNasConnection();
    if (connection == null) {
      throw UnsupportedError('当前连接不支持复制操作');
    }

    await connection.adapter.fileSystem.copy(sourcePath, destPath);
    if (!skipRefresh) await refresh();
  }

  Future<void> moveTo(String sourcePath, String destPath,
      {bool skipRefresh = false}) async {
    final connection = _getSelectedNasConnection();
    if (connection == null) {
      throw UnsupportedError('当前连接不支持移动操作');
    }

    await connection.adapter.fileSystem.move(sourcePath, destPath);
    if (!skipRefresh) await refresh();
  }

  List<FileItem> _sortFiles(
    List<FileItem> files,
    SortMode mode,
    bool ascending,
  ) {
    final sorted = [...files];

    // 先分离文件夹和文件
    final directories = sorted.where((f) => f.isDirectory).toList();
    final regularFiles = sorted.where((f) => !f.isDirectory).toList();

    int compare(FileItem a, FileItem b) {
      final result = switch (mode) {
        SortMode.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        SortMode.size => a.size.compareTo(b.size),
        SortMode.date => (a.modifiedTime ?? DateTime(0))
            .compareTo(b.modifiedTime ?? DateTime(0)),
        SortMode.type =>
          (a.extension ?? '').compareTo(b.extension ?? ''),
      };
      return ascending ? result : -result;
    }

    directories.sort(compare);
    regularFiles.sort(compare);

    // 文件夹始终在前
    return [...directories, ...regularFiles];
  }
}
