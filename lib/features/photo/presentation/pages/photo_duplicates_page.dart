import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/photo/data/services/photo_database_service.dart';
import 'package:my_nas/features/photo/data/services/photo_hash_service.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/widgets/stream_image.dart';

/// 重复照片管理页面
class PhotoDuplicatesPage extends ConsumerStatefulWidget {
  const PhotoDuplicatesPage({super.key});

  @override
  ConsumerState<PhotoDuplicatesPage> createState() => _PhotoDuplicatesPageState();
}

class _PhotoDuplicatesPageState extends ConsumerState<PhotoDuplicatesPage>
    with ConsumerTabBarVisibilityMixin {
  final PhotoDatabaseService _db = PhotoDatabaseService();
  final PhotoHashService _hashService = PhotoHashService();

  // 状态
  bool _isLoading = true;
  bool _isScanning = false;
  bool _isFindingSimilar = false;
  String? _errorMessage;

  // 重复照片数据 - 基于文件名+大小的快速检测
  Map<String, List<PhotoEntity>> _nameSizeDuplicates = {};
  ({int duplicateGroups, int totalDuplicatePhotos})? _nameSizeStats;

  // 重复照片数据 - 仅基于文件名（同名）
  Map<String, List<PhotoEntity>> _nameDuplicates = {};
  ({int duplicateGroups, int totalDuplicatePhotos})? _nameStats;

  // 重复照片数据 - 基于哈希的深度检测
  Map<String, List<PhotoEntity>> _hashDuplicates = {};
  ({int fileHashDuplicates, int perceptualHashDuplicates, int totalDuplicatePhotos})? _hashStats;

  // 相似照片数据 - 基于 pHash 汉明距离
  List<List<PhotoEntity>> _similarGroups = [];

  // 哈希计算状态
  ({int total, int hashed, int pending, int failed})? _hashCalcStats;

  // 相似照片查找进度
  ({int processed, int total})? _similarProgress;

  // 选中的照片（用于删除）
  final Set<String> _selectedPhotos = {}; // 存储 uniqueKey

  // 拖动选择相关状态
  bool _isDragging = false;
  bool _dragSelectMode = true; // true=选中模式, false=取消选中模式
  String? _lastDraggedKey; // 上一个拖动经过的照片 key，避免重复处理
  final Map<String, GlobalKey> _photoKeys = {}; // 照片的 GlobalKey 映射

  // 扫描进度
  HashProgress? _scanProgress;
  StreamSubscription<HashProgress>? _progressSubscription;

  // 当前显示模式: 0=快速检测, 1=完全相同, 2=视觉相似, 3=同名
  int _currentMode = 0;

  // 相似度阈值（汉明距离）
  int _similarityThreshold = 8;

  /// 当前模式下是否有重复数据
  bool get _hasAnyDuplicates => switch (_currentMode) {
        0 => _nameSizeDuplicates.isNotEmpty,
        1 => _hashDuplicates.isNotEmpty,
        2 => _similarGroups.isNotEmpty,
        3 => _nameDuplicates.isNotEmpty,
        _ => false,
      };

  @override
  void initState() {
    super.initState();
    hideTabBar();
    // 仅加载数据，不自动开始扫描（需要用户手动点击）
    _loadDuplicates();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadDuplicates({bool autoStartScan = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _db.init();

      // 优先加载快速检测结果（基于文件名+大小）
      final nameSizeStats = await _db.getNameSizeDuplicateStats();
      final nameSizeDups = await _db.getPotentialDuplicatesByNameAndSize();

      // 同时加载哈希检测结果（跨数据源）
      final hashStats = await _db.getDuplicateStats();
      final hashDups = await _db.getDuplicatesByFileHash(crossSource: true);

      // 加载哈希计算状态
      final hashCalcStats = await _db.getHashStats();

      if (!mounted) return;
      setState(() {
        _nameSizeStats = nameSizeStats;
        _nameSizeDuplicates = nameSizeDups;
        _hashStats = hashStats;
        _hashDuplicates = hashDups;
        _hashCalcStats = hashCalcStats;
        _isLoading = false;
      });

      // 如果有待处理的照片且需要自动开始扫描
      if (autoStartScan && hashCalcStats.pending > 0 && !_isScanning) {
        // 延迟一帧确保 UI 已更新
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startScan();
        });
      }
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = AppLocalizations.of(context).dedupLoadFailed('$e');
        _isLoading = false;
      });
    }
  }

  /// 加载同名（仅文件名）重复结果
  Future<void> _loadNameDuplicates() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _db.init();
      final nameStats = await _db.getNameDuplicateStats();
      final nameDups = await _db.getDuplicatesByFileName();

      if (!mounted) return;
      setState(() {
        _nameStats = nameStats;
        _nameDuplicates = nameDups;
        _isLoading = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = AppLocalizations.of(context).dedupLoadFailed('$e');
        _isLoading = false;
      });
    }
  }

  Future<void> _startScan() async {
    // 获取第一个可用的文件系统
    final connections = ref.read(activeConnectionsProvider);
    final connectedSources = connections.values
        .where((c) => c.status == SourceStatus.connected)
        .toList();

    if (connectedSources.isEmpty) {
      context.showWarningToast(AppLocalizations.of(context).dedupConnectNasFirst);
      return;
    }

    setState(() {
      _isScanning = true;
      _scanProgress = null;
    });

    _progressSubscription = _hashService.progressStream.listen((progress) {
      setState(() => _scanProgress = progress);

      if (progress.status == HashStatus.completed ||
          progress.status == HashStatus.cancelled ||
          progress.status == HashStatus.error) {
        _loadDuplicates();
        setState(() => _isScanning = false);
      }
    });

    // 使用第一个连接的文件系统
    final fileSystem = connectedSources.first.adapter.fileSystem;
    await _hashService.processAllPhotos(fileSystem);
  }

  Future<void> _findSimilarPhotos() async {
    setState(() {
      _isFindingSimilar = true;
      _similarProgress = null;
    });

    try {
      final groups = await _hashService.findSimilarPhotos(
        threshold: _similarityThreshold,
        onProgress: (processed, total) {
          setState(() {
            _similarProgress = (processed: processed, total: total);
          });
        },
      );

      setState(() {
        _similarGroups = groups;
        _isFindingSimilar = false;
        _similarProgress = null;
      });
    } on Exception catch (e) {
      setState(() {
        _errorMessage = AppLocalizations.of(context).dedupFindSimilarFailed('$e');
        _isFindingSimilar = false;
        _similarProgress = null;
      });
    }
  }

  void _cancelScan() {
    _hashService.cancel();
  }

  void _selectAllExceptFirst(List<PhotoEntity> photos) {
    setState(() {
      // 保留第一张（最新的），选中其他所有
      for (var i = 1; i < photos.length; i++) {
        _selectedPhotos.add(photos[i].uniqueKey);
      }
    });
  }

  /// 一键全选所有推荐删除的照片（每组保留第一张）
  void _selectAllRecommended() {
    setState(() {
      _selectedPhotos.clear();
      // 根据当前模式选择对应的数据
      switch (_currentMode) {
        case 0: // 快速检测
          for (final photos in _nameSizeDuplicates.values) {
            for (var i = 1; i < photos.length; i++) {
              _selectedPhotos.add(photos[i].uniqueKey);
            }
          }
        case 1: // 精确匹配
          for (final photos in _hashDuplicates.values) {
            for (var i = 1; i < photos.length; i++) {
              _selectedPhotos.add(photos[i].uniqueKey);
            }
          }
        case 2: // 视觉相似
          for (final photos in _similarGroups) {
            for (var i = 1; i < photos.length; i++) {
              _selectedPhotos.add(photos[i].uniqueKey);
            }
          }
        case 3: // 同名
          for (final photos in _nameDuplicates.values) {
            for (var i = 1; i < photos.length; i++) {
              _selectedPhotos.add(photos[i].uniqueKey);
            }
          }
      }
    });
  }

  void _clearSelection() {
    setState(_selectedPhotos.clear);
  }

  /// 获取或创建照片的 GlobalKey
  GlobalKey _getPhotoKey(String uniqueKey) => _photoKeys.putIfAbsent(uniqueKey, GlobalKey.new);

  /// 开始拖动选择
  void _onDragStart(String photoKey) {
    final isCurrentlySelected = _selectedPhotos.contains(photoKey);
    setState(() {
      _isDragging = true;
      // 根据第一个触摸的照片状态决定模式：如果已选中则切换为取消模式，否则为选中模式
      _dragSelectMode = !isCurrentlySelected;
      _lastDraggedKey = photoKey;
      // 立即处理第一个照片
      if (_dragSelectMode) {
        _selectedPhotos.add(photoKey);
      } else {
        _selectedPhotos.remove(photoKey);
      }
    });
  }

  /// 拖动过程中更新选择
  void _onDragUpdate(Offset globalPosition) {
    if (!_isDragging) return;

    // 检查当前位置下是哪个照片
    for (final entry in _photoKeys.entries) {
      final key = entry.value;
      final context = key.currentContext;
      if (context == null) continue;

      final box = context.findRenderObject() as RenderBox?;
      if (box == null) continue;

      final position = box.localToGlobal(Offset.zero);
      final size = box.size;
      final rect = Rect.fromLTWH(position.dx, position.dy, size.width, size.height);

      if (rect.contains(globalPosition)) {
        final photoKey = entry.key;
        // 避免重复处理同一个照片
        if (photoKey != _lastDraggedKey) {
          setState(() {
            _lastDraggedKey = photoKey;
            if (_dragSelectMode) {
              _selectedPhotos.add(photoKey);
            } else {
              _selectedPhotos.remove(photoKey);
            }
          });
        }
        break;
      }
    }
  }

  /// 结束拖动选择
  void _onDragEnd() {
    setState(() {
      _isDragging = false;
      _lastDraggedKey = null;
    });
  }

  /// 构建可拖动选择的照片网格
  Widget _buildDragSelectPhotoGrid({
    required List<PhotoEntity> photos,
    required Map<String, SourceConnection> connections,
    required bool isDark,
    required bool showSourceLabel,
  }) {
    final l = AppLocalizations.of(context);
    return Listener(
      onPointerDown: (event) {
        // 检查点击位置对应哪个照片
        for (final photo in photos) {
          final key = _photoKeys[photo.uniqueKey];
          if (key == null) continue;
          final context = key.currentContext;
          if (context == null) continue;
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) continue;
          final position = box.localToGlobal(Offset.zero);
          final size = box.size;
          final rect = Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
          if (rect.contains(event.position)) {
            _onDragStart(photo.uniqueKey);
            break;
          }
        }
      },
      onPointerMove: (event) => _onDragUpdate(event.position),
      onPointerUp: (_) => _onDragEnd(),
      onPointerCancel: (_) => _onDragEnd(),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: photos.asMap().entries.map((entry) {
          final photoIndex = entry.key;
          final photo = entry.value;
          final isSelected = _selectedPhotos.contains(photo.uniqueKey);
          final connection = connections[photo.sourceId];
          final fileSystem = connection?.adapter.fileSystem;
          final photoKey = _getPhotoKey(photo.uniqueKey);

          return Container(
            key: photoKey,
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: isSelected
                  ? Border.all(color: AppColors.error, width: 3)
                  : null,
            ),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(isSelected ? 5 : 8),
                  child: StreamImage(
                    url: photo.thumbnailUrl,
                    path: photo.filePath,
                    fileSystem: fileSystem,
                    placeholder: ColoredBox(
                      color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                      child: const Center(child: Icon(Icons.photo_rounded)),
                    ),
                    errorWidget: ColoredBox(
                      color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                      child: const Center(child: Icon(Icons.broken_image)),
                    ),
                    cacheKey: photo.filePath,
                  ),
                ),
                // 第一张标记为"保留"
                if (photoIndex == 0)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        l.dedupKeepRecommended,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                // 选中标记
                if (isSelected)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_rounded, color: Colors.white, size: 16),
                    ),
                  ),
                // 数据源标识（跨数据源时显示）
                if (showSourceLabel && photos.map((p) => p.sourceId).toSet().length > 1)
                  Positioned(
                    top: photoIndex == 0 ? 24 : 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        photo.sourceId.length > 8
                            ? '${photo.sourceId.substring(0, 8)}...'
                            : photo.sourceId,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                // 文件大小
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.7),
                          Colors.transparent,
                        ],
                      ),
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                    ),
                    child: Text(
                      photo.displaySize,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _deleteSelected() async {
    if (_selectedPhotos.isEmpty) return;

    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.dedupDeleteConfirmTitle),
        content: Text(l.dedupDeleteConfirmMessage(_selectedPhotos.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.dedupCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(l.dedupDelete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final connections = ref.read(activeConnectionsProvider);
      var deleted = 0;
      var failed = 0;

      for (final uniqueKey in _selectedPhotos.toList()) {
        // 解析 uniqueKey (sourceId_filePath)
        final parts = uniqueKey.split('_');
        if (parts.length < 2) continue;

        final sourceId = parts.first;
        final filePath = parts.sublist(1).join('_');

        final connection = connections[sourceId];
        if (connection == null) {
          failed++;
          continue;
        }

        try {
          // 从 NAS 删除文件
          await connection.adapter.fileSystem.delete(filePath);
          // 从数据库删除记录
          await _db.delete(sourceId, filePath);
          deleted++;
        } on Exception catch (e) {
          logger.w('删除失败: $filePath - $e');
          failed++;
        }
      }

      _selectedPhotos.clear();
      await _loadDuplicates();

      if (mounted) {
        context.showSnackBar(
          failed > 0
              ? l.dedupDeleteResultWithFailed(deleted, failed)
              : l.dedupDeleteResult(deleted),
        );
      }
    } on Exception catch (e) {
      setState(() {
        _errorMessage = AppLocalizations.of(context).dedupDeleteFailed('$e');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
      appBar: AppBar(
        title: Text(l.dedupPageTitle),
        backgroundColor: isDark ? AppColors.darkSurface : null,
        actions: [
          if (_selectedPhotos.isNotEmpty) ...[
            TextButton(
              onPressed: _clearSelection,
              child: Text(l.dedupClearSelection(_selectedPhotos.length)),
            ),
            IconButton(
              onPressed: _deleteSelected,
              icon: Icon(Icons.delete_rounded, color: AppColors.error),
              tooltip: l.dedupDeleteSelected,
            ),
          ] else if (_hasAnyDuplicates) ...[
            IconButton(
              onPressed: _selectAllRecommended,
              icon: const Icon(Icons.checklist_rounded),
              tooltip: l.dedupSelectAllRecommended,
            ),
          ],
          if (!_isScanning)
            IconButton(
              onPressed: _startScan,
              icon: const Icon(Icons.play_circle_outline_rounded),
              tooltip: l.dedupStartScan,
            ),
        ],
      ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: TextStyle(color: AppColors.error)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadDuplicates,
              child: Text(AppLocalizations.of(context).dedupRetry),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        // 扫描进度卡片
        if (_isScanning || _scanProgress != null)
          SliverToBoxAdapter(child: _buildScanProgressCard(isDark)),

        // 模式切换选项卡
        SliverToBoxAdapter(child: _buildModeTabBar(isDark)),

        // 统计信息卡片
        SliverToBoxAdapter(child: _buildStatsCard(isDark)),

        // 相似照片查找进度
        if (_currentMode == 2 && _isFindingSimilar)
          SliverToBoxAdapter(child: _buildFindingSimilarCard(isDark)),

        // 根据模式显示不同内容
        ..._buildContentByMode(isDark),
      ],
    );
  }

  List<Widget> _buildContentByMode(bool isDark) {
    switch (_currentMode) {
      case 0: // 快速检测
        if (_nameSizeDuplicates.isEmpty) {
          return [SliverFillRemaining(child: _buildEmptyState(isDark))];
        }
        return [
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final entry = _nameSizeDuplicates.entries.elementAt(index);
                return _buildDuplicateGroup(entry.key, entry.value, isDark);
              },
              childCount: _nameSizeDuplicates.length,
            ),
          ),
        ];

      case 1: // 精确匹配（MD5）
        if (_hashDuplicates.isEmpty) {
          return [SliverFillRemaining(child: _buildEmptyState(isDark))];
        }
        return [
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final entry = _hashDuplicates.entries.elementAt(index);
                return _buildDuplicateGroup(entry.key, entry.value, isDark);
              },
              childCount: _hashDuplicates.length,
            ),
          ),
        ];

      case 2: // 视觉相似
        if (_isFindingSimilar) {
          return [const SliverToBoxAdapter(child: SizedBox.shrink())];
        }
        if (_similarGroups.isEmpty) {
          return [SliverFillRemaining(child: _buildEmptyState(isDark))];
        }
        return [
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final group = _similarGroups[index];
                return _buildSimilarGroup(index, group, isDark);
              },
              childCount: _similarGroups.length,
            ),
          ),
        ];

      case 3: // 同名（仅文件名）
        if (_nameDuplicates.isEmpty) {
          return [SliverFillRemaining(child: _buildEmptyState(isDark))];
        }
        return [
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final entry = _nameDuplicates.entries.elementAt(index);
                return _buildDuplicateGroup(entry.key, entry.value, isDark);
              },
              childCount: _nameDuplicates.length,
            ),
          ),
        ];

      default:
        return [SliverFillRemaining(child: _buildEmptyState(isDark))];
    }
  }

  Widget _buildFindingSimilarCard(bool isDark) {
    final l = AppLocalizations.of(context);
    final progress = _similarProgress;
    final hasProgress = progress != null && progress.total > 0;

    return Card(
      margin: const EdgeInsets.all(16),
      color: isDark ? AppColors.darkSurfaceElevated : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l.dedupAnalyzingSimilarity,
                    style: context.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (hasProgress) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress.processed / progress.total,
              ),
              const SizedBox(height: 8),
              Text(
                l.dedupAnalyzedGroups(progress.processed, progress.total),
                style: context.textTheme.bodySmall?.copyWith(
                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSimilarGroup(int index, List<PhotoEntity> photos, bool isDark) {
    final l = AppLocalizations.of(context);
    final connections = ref.watch(activeConnectionsProvider);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDark ? AppColors.darkSurfaceElevated : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 组头部
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    l.dedupSimilarCount(photos.length),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _selectAllExceptFirst(photos),
                  icon: const Icon(Icons.select_all, size: 18),
                  label: Text(l.dedupSelectOthers),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
          ),
          // 照片网格（支持拖动选择）
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: _buildDragSelectPhotoGrid(
              photos: photos,
              connections: connections,
              isDark: isDark,
              showSourceLabel: false,
            ),
          ),
          // 文件路径
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: photos.map((photo) {
                final isSelected = _selectedPhotos.contains(photo.uniqueKey);
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off,
                        size: 16,
                        color: isSelected ? AppColors.error : AppColors.disabled,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          photo.filePath,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                            decoration: isSelected ? TextDecoration.lineThrough : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// 模式切换选项卡
  Widget _buildModeTabBar(bool isDark) {
    final l = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceElevated : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildModeTab(
              title: l.dedupModeQuick,
              subtitle: l.dedupModeQuickSubtitle,
              isSelected: _currentMode == 0,
              count: _nameSizeStats?.duplicateGroups ?? 0,
              isDark: isDark,
              onTap: () => setState(() => _currentMode = 0),
            ),
          ),
          Expanded(
            child: _buildModeTab(
              title: l.dedupModeExact,
              subtitle: l.dedupModeExactSubtitle,
              isSelected: _currentMode == 1,
              count: _hashStats?.fileHashDuplicates ?? 0,
              isDark: isDark,
              onTap: () => setState(() => _currentMode = 1),
            ),
          ),
          Expanded(
            child: _buildModeTab(
              title: l.dedupModeSimilar,
              subtitle: l.dedupModeSimilarSubtitle,
              isSelected: _currentMode == 2,
              count: _similarGroups.length,
              isDark: isDark,
              onTap: () {
                setState(() => _currentMode = 2);
                // 如果还没有查找过相似照片，自动开始查找
                if (_similarGroups.isEmpty && !_isFindingSimilar) {
                  _findSimilarPhotos();
                }
              },
            ),
          ),
          Expanded(
            child: _buildModeTab(
              title: l.dedupModeSameName,
              subtitle: l.dedupModeSameNameSubtitle,
              isSelected: _currentMode == 3,
              count: _nameStats?.duplicateGroups ?? 0,
              isDark: isDark,
              onTap: () {
                setState(() => _currentMode = 3);
                // 选中时若未加载则触发加载
                if (_nameDuplicates.isEmpty && _nameStats == null) {
                  _loadNameDuplicates();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab({
    required String title,
    required String subtitle,
    required bool isSelected,
    required int count,
    required bool isDark,
    required VoidCallback onTap,
  }) => GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? AppColors.darkSurface : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? AppColors.primary
                        : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.15)
                          : (isDark ? AppColors.darkOutline : AppColors.lightOutline),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? AppColors.primary
                            : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey[500] : Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );

  Widget _buildScanProgressCard(bool isDark) {
    final l = AppLocalizations.of(context);
    final progress = _scanProgress;

    return Card(
      margin: const EdgeInsets.all(16),
      color: isDark ? AppColors.darkSurfaceElevated : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_isScanning)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    progress?.status == HashStatus.completed
                        ? Icons.check_circle
                        : progress?.status == HashStatus.error
                            ? Icons.error
                            : Icons.cancel_rounded,
                    color: progress?.status == HashStatus.completed
                        ? AppColors.success
                        : progress?.status == HashStatus.error
                            ? AppColors.error
                            : AppColors.warning,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isScanning
                        ? l.dedupScanning
                        : progress?.status == HashStatus.completed
                            ? l.dedupScanCompleted
                            : progress?.status == HashStatus.cancelled
                                ? l.dedupScanCancelled
                                : l.dedupScanError,
                    style: context.textTheme.titleMedium,
                  ),
                ),
                if (_isScanning)
                  TextButton(
                    onPressed: _cancelScan,
                    child: Text(l.dedupCancel),
                  ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress.progress,
                backgroundColor: isDark
                    ? AppColors.darkOutline
                    : AppColors.lightOutline,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 8),
              Text(
                progress.failed > 0
                    ? l.dedupProcessedWithFailed(
                        progress.processed, progress.total, progress.failed)
                    : l.dedupProcessed(progress.processed, progress.total),
                style: context.textTheme.bodySmall?.copyWith(
                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                ),
              ),
              if (progress.currentFile.isNotEmpty)
                Text(
                  progress.currentFile,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: isDark ? Colors.grey[500] : Colors.grey[500],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(bool isDark) {
    final l = AppLocalizations.of(context);
    final calcStats = _hashCalcStats;
    final needsScan = (calcStats?.pending ?? 0) > 0 || (calcStats?.failed ?? 0) > 0;

    // 根据当前模式显示对应的统计
    if (_currentMode == 1) {
      // 精确匹配模式
      final stats = _hashStats;
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: isDark ? AppColors.darkSurfaceElevated : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildStatItem(
                    l.dedupStatDuplicateGroups,
                    '${stats?.fileHashDuplicates ?? 0}',
                    Icons.collections_rounded,
                    isDark,
                  ),
                  const SizedBox(width: 24),
                  _buildStatItem(
                    l.dedupStatAffectedPhotos,
                    '${stats?.totalDuplicatePhotos ?? 0}',
                    Icons.photo_library_rounded,
                    isDark,
                  ),
                ],
              ),
              // 哈希计算状态
              if (calcStats != null) ...[
                const SizedBox(height: 12),
                _buildHashStatusHint(calcStats, needsScan, isDark),
              ],
            ],
          ),
        ),
      );
    } else if (_currentMode == 2) {
      // 视觉相似模式
      final totalSimilarPhotos = _similarGroups.fold(0, (sum, g) => sum + g.length);
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: isDark ? AppColors.darkSurfaceElevated : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildStatItem(
                    l.dedupStatSimilarGroups,
                    '${_similarGroups.length}',
                    Icons.compare_rounded,
                    isDark,
                  ),
                  const SizedBox(width: 24),
                  _buildStatItem(
                    l.dedupStatAffectedPhotos,
                    '$totalSimilarPhotos',
                    Icons.photo_library_rounded,
                    isDark,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 相似度阈值设置
              Row(
                children: [
                  Text(
                    l.dedupSimilarityThreshold,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                      ),
                      child: Slider(
                        value: _similarityThreshold.toDouble(),
                        min: 1,
                        max: 15,
                        divisions: 14,
                        label: _getThresholdLabel(_similarityThreshold),
                        onChanged: (value) {
                          setState(() => _similarityThreshold = value.round());
                        },
                        onChangeEnd: (value) {
                          // 阈值变化后重新查找
                          _findSimilarPhotos();
                        },
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getThresholdColor(_similarityThreshold).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _getThresholdLabel(_similarityThreshold),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _getThresholdColor(_similarityThreshold),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Colors.purple),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l.dedupSimilarInfo,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 哈希计算状态
              if (calcStats != null && needsScan) ...[
                const SizedBox(height: 8),
                _buildHashStatusHint(calcStats, needsScan, isDark),
              ],
            ],
          ),
        ),
      );
    } else if (_currentMode == 3) {
      // 同名模式（仅文件名）
      final stats = _nameStats;
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: isDark ? AppColors.darkSurfaceElevated : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildStatItem(
                    l.dedupStatDuplicateGroups,
                    '${stats?.duplicateGroups ?? 0}',
                    Icons.collections_rounded,
                    isDark,
                  ),
                  const SizedBox(width: 24),
                  _buildStatItem(
                    l.dedupStatAffectedPhotos,
                    '${stats?.totalDuplicatePhotos ?? 0}',
                    Icons.photo_library_rounded,
                    isDark,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l.dedupSameNameInfo,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      final stats = _nameSizeStats;
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: isDark ? AppColors.darkSurfaceElevated : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildStatItem(
                    l.dedupStatDuplicateGroups,
                    '${stats?.duplicateGroups ?? 0}',
                    Icons.collections_rounded,
                    isDark,
                  ),
                  const SizedBox(width: 24),
                  _buildStatItem(
                    l.dedupStatAffectedPhotos,
                    '${stats?.totalDuplicatePhotos ?? 0}',
                    Icons.photo_library_rounded,
                    isDark,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l.dedupQuickInfo,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildStatItem(String label, String value, IconData icon, bool isDark) =>
      Expanded(
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : null,
              ),
            ),
            Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ],
        ),
      );

  Widget _buildHashStatusHint(
    ({int total, int hashed, int pending, int failed}) calcStats,
    bool needsScan,
    bool isDark,
  ) {
    final l = AppLocalizations.of(context);
    final statusText = needsScan
        ? l.dedupScannedProgress(calcStats.hashed, calcStats.total) +
            (calcStats.pending > 0 ? l.dedupScanPendingSuffix(calcStats.pending) : '') +
            (calcStats.failed > 0 ? l.dedupScanFailedSuffix(calcStats.failed) : '')
        : l.dedupScanAllCompleted(calcStats.total);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: needsScan
            ? AppColors.warning.withValues(alpha: 0.1)
            : AppColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            needsScan ? Icons.info_outline : Icons.check_circle_outline,
            size: 16,
            color: needsScan ? AppColors.warning : AppColors.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ),
          if (needsScan && !_isScanning)
            TextButton(
              onPressed: _startScan,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 32),
              ),
              child: Text(l.dedupStartScan),
            ),
        ],
      ),
    );
  }

  String _getThresholdLabel(int threshold) {
    final l = AppLocalizations.of(context);
    if (threshold <= 3) return l.dedupThresholdStrict;
    if (threshold <= 6) return l.dedupThresholdRather;
    if (threshold <= 10) return l.dedupThresholdModerate;
    return l.dedupThresholdLoose;
  }

  Color _getThresholdColor(int threshold) {
    if (threshold <= 3) return AppColors.success;
    if (threshold <= 6) return AppColors.primary;
    if (threshold <= 10) return AppColors.warning;
    return AppColors.error;
  }

  Widget _buildEmptyState(bool isDark) {
    final l = AppLocalizations.of(context);
    final (title, subtitle) = switch (_currentMode) {
      0 => (l.dedupEmptyQuickTitle, l.dedupEmptyQuickSubtitle),
      1 => (l.dedupEmptyExactTitle, l.dedupEmptyExactSubtitle),
      2 => (l.dedupEmptySimilarTitle, l.dedupEmptySimilarSubtitle),
      3 => (l.dedupEmptySameNameTitle, l.dedupEmptySameNameSubtitle),
      _ => (l.dedupEmptyNoData, ''),
    };

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 64,
            color: AppColors.success,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: context.textTheme.titleMedium?.copyWith(
              color: isDark ? Colors.white : null,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: context.textTheme.bodyMedium?.copyWith(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (_currentMode == 2) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _findSimilarPhotos,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l.dedupReanalyze),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDuplicateGroup(
    String hash,
    List<PhotoEntity> photos,
    bool isDark,
  ) {
    final l = AppLocalizations.of(context);
    final connections = ref.watch(activeConnectionsProvider);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDark ? AppColors.darkSurfaceElevated : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 组头部
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    l.dedupSameCount(photos.length),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _selectAllExceptFirst(photos),
                  icon: const Icon(Icons.select_all, size: 18),
                  label: Text(l.dedupSelectOthers),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
          ),
          // 照片网格（支持拖动选择）
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: _buildDragSelectPhotoGrid(
              photos: photos,
              connections: connections,
              isDark: isDark,
              // 精确(MD5) 与 同名 模式都可能跨源，需显示来源以便区分。
              showSourceLabel: _currentMode == 1 || _currentMode == 3,
            ),
          ),
          // 文件路径信息
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: photos.map((photo) {
                final isSelected = _selectedPhotos.contains(photo.uniqueKey);
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off,
                        size: 16,
                        color: isSelected ? AppColors.error : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          photo.filePath,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                            decoration: isSelected ? TextDecoration.lineThrough : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
