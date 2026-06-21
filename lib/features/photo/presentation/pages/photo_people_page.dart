import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/photo/data/services/face_database_service.dart';
import 'package:my_nas/features/photo/data/services/face_recognition_service.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/stream_image.dart';

/// 人物分组页面
class PhotoPeoplePage extends ConsumerStatefulWidget {
  const PhotoPeoplePage({super.key, this.initialPerson});

  /// 若指定，进入页面后自动打开该人物的照片（用于桌面端人物头像直达）。
  final PersonEntity? initialPerson;

  @override
  ConsumerState<PhotoPeoplePage> createState() => _PhotoPeoplePageState();
}

class _PhotoPeoplePageState extends ConsumerState<PhotoPeoplePage>
    with ConsumerTabBarVisibilityMixin {
  final FaceDatabaseService _faceDb = FaceDatabaseService();
  final FaceRecognitionService _faceService = FaceRecognitionService();

  bool _isLoading = true;
  bool _isScanning = false;
  bool _isClustering = false;
  String? _errorMessage;

  List<PersonEntity> _persons = [];
  Map<int, FaceEntity?> _representativeFaces = {};
  ({int totalFaces, int totalPersons, int unassignedFaces})? _stats;

  FaceProcessProgress? _scanProgress;
  StreamSubscription<FaceProcessProgress>? _progressSubscription;

  @override
  void initState() {
    super.initState();
    hideTabBar();
    _loadData();
    // 桌面端从人物头像直达：进入后自动打开该人物的照片
    final initial = widget.initialPerson;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showPersonPhotos(initial);
      });
    }
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _faceDb.init();
      final persons = await _faceDb.getAllPersons();
      final stats = await _faceDb.getStats();

      // 加载代表头像
      final faces = <int, FaceEntity?>{};
      for (final person in persons) {
        if (person.representativeFaceId != null) {
          final personFaces = await _faceDb.getFacesByPersonId(person.id);
          if (personFaces.isNotEmpty) {
            faces[person.id] = personFaces.firstWhere(
              (f) => f.id == person.representativeFaceId,
              orElse: () => personFaces.first,
            );
          }
        }
      }

      setState(() {
        _persons = persons;
        _representativeFaces = faces;
        _stats = stats;
        _isLoading = false;
      });
    } on Exception catch (e) {
      setState(() {
        _errorMessage = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _startScan() async {
    final connections = ref.read(activeConnectionsProvider);
    final connectedSources = connections.values
        .where((c) => c.status == SourceStatus.connected)
        .toList();

    if (connectedSources.isEmpty) {
      context.showWarningToast(context.l10n.photoPeoplePageConnectNasFirst);
      return;
    }

    setState(() {
      _isScanning = true;
      _scanProgress = null;
    });

    _progressSubscription = _faceService.progressStream.listen((progress) {
      setState(() => _scanProgress = progress);

      if (progress.status == FaceProcessStatus.completed ||
          progress.status == FaceProcessStatus.cancelled ||
          progress.status == FaceProcessStatus.error) {
        setState(() => _isScanning = false);
        _startClustering();
      }
    });

    final fileSystem = connectedSources.first.adapter.fileSystem;
    await _faceService.processAllPhotos(fileSystem);
  }

  Future<void> _startClustering() async {
    setState(() => _isClustering = true);

    try {
      await _faceService.clusterFaces();
      await _loadData();
    } finally {
      setState(() => _isClustering = false);
    }
  }

  void _cancelScan() {
    _faceService.cancel();
  }

  Future<void> _renamePerson(PersonEntity person) async {
    final controller = TextEditingController(text: person.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.photoPeoplePageNamingTitle),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: context.l10n.photoPeoplePageNamingHint,
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.photoPeoplePageScanCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(context.l10n.photoPeoplePageMergeConfirmButton),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      await _faceDb.updatePersonName(person.id, newName);
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
      appBar: AppBar(
        title: Text(context.l10n.photoPeoplePageTitle),
        backgroundColor: isDark ? AppColors.darkSurface : null,
        actions: [
          if (!_isScanning && !_isClustering)
            IconButton(
              onPressed: _startScan,
              icon: const Icon(Icons.face_retouching_natural),
              tooltip: context.l10n.photoPeoplePageScanTooltip,
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
              onPressed: _loadData,
              child: Text(context.l10n.photoPeoplePageRetry),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        // 扫描进度
        if (_isScanning || _scanProgress != null)
          SliverToBoxAdapter(child: _buildScanProgress(isDark)),

        // 聚类进度
        if (_isClustering)
          SliverToBoxAdapter(child: _buildClusteringProgress(isDark)),

        // 统计信息
        SliverToBoxAdapter(child: _buildStatsCard(isDark)),

        // 人物网格
        if (_persons.isEmpty)
          SliverFillRemaining(child: _buildEmptyState(isDark))
        else
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.8,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildPersonCard(
                  _persons[index],
                  isDark,
                ),
                childCount: _persons.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildScanProgress(bool isDark) {
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
                    progress?.status == FaceProcessStatus.completed
                        ? Icons.check_circle
                        : progress?.status == FaceProcessStatus.error
                            ? Icons.error
                            : Icons.cancel_rounded,
                    color: progress?.status == FaceProcessStatus.completed
                        ? AppColors.success
                        : progress?.status == FaceProcessStatus.error
                            ? AppColors.error
                            : AppColors.warning,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isScanning
                        ? context.l10n.photoPeoplePageScanningFaces
                        : progress?.status == FaceProcessStatus.completed
                            ? context.l10n.photoPeoplePageScanComplete
                            : progress?.status == FaceProcessStatus.cancelled
                                ? context.l10n.photoPeoplePageScanCancelled
                                : context.l10n.photoPeoplePageScanError,
                    style: context.textTheme.titleMedium,
                  ),
                ),
                if (_isScanning)
                  TextButton(
                    onPressed: _cancelScan,
                    child: Text(context.l10n.photoPeoplePageScanCancel),
                  ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress.progress),
              const SizedBox(height: 8),
              Text(
                context.l10n.photoPeoplePageScanProgressText(
                  progress.processed,
                  progress.total,
                  progress.facesFound,
                ),
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

  Widget _buildClusteringProgress(bool isDark) => Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: isDark ? AppColors.darkSurfaceElevated : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              context.l10n.photoPeoplePageAnalyzing,
              style: context.textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );

  Widget _buildStatsCard(bool isDark) {
    final stats = _stats;
    if (stats == null) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.all(16),
      color: isDark ? AppColors.darkSurfaceElevated : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _buildStatItem(context.l10n.photoPeoplePageStatsLabelPeople, '${stats.totalPersons}', Icons.person_rounded, isDark),
            const SizedBox(width: 24),
            _buildStatItem(context.l10n.photoPeoplePageStatsLabelFaces, '${stats.totalFaces}', Icons.face, isDark),
            const SizedBox(width: 24),
            _buildStatItem(
              context.l10n.photoPeoplePageStatsLabelUnassigned,
              '${stats.unassignedFaces}',
              Icons.help_outline_rounded,
              isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    bool isDark,
  ) =>
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

  Widget _buildEmptyState(bool isDark) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.face_retouching_natural,
              size: 64,
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.photoPeoplePageEmptyStateTitle,
              style: context.textTheme.titleMedium?.copyWith(
                color: isDark ? Colors.white : null,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.photoPeoplePageEmptyStateDescription,
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _startScan,
              icon: const Icon(Icons.face_retouching_natural),
              label: Text(context.l10n.photoPeoplePageScanButton),
            ),
          ],
        ),
      );

  Widget _buildPersonCard(PersonEntity person, bool isDark) {
    final face = _representativeFaces[person.id];
    final connections = ref.watch(activeConnectionsProvider);

    return GestureDetector(
      onTap: () => _showPersonPhotos(person),
      onLongPress: () => _showPersonOptions(person),
      onSecondaryTap: () => _showPersonOptions(person),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceElevated : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 头像
            Flexible(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                child: face != null
                    ? _buildFaceImage(face, connections, isDark)
                    : ColoredBox(
                        color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                        child: Center(
                          child: Icon(
                            Icons.person_rounded,
                            size: 48,
                            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                          ),
                        ),
                      ),
              ),
            ),
            // 名字和数量
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    person.displayName,
                    style: context.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    context.l10n.photoPeoplePagePhotoCountLabel(person.photoCount),
                    style: context.textTheme.bodySmall?.copyWith(
                      color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
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

  Widget _buildFaceImage(
    FaceEntity face,
    Map<String, SourceConnection> connections,
    bool isDark,
  ) {
    final connection = connections[face.photoSourceId];
    final fileSystem = connection?.adapter.fileSystem;

    return StreamImage(
      path: face.photoPath,
      fileSystem: fileSystem,
      placeholder: ColoredBox(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
        child: const Icon(Icons.person_rounded),
      ),
      errorWidget: ColoredBox(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
        child: const Icon(Icons.person_rounded),
      ),
      cacheKey: '${face.photoPath}_face_${face.id}',
    );
  }

  Future<void> _showPersonPhotos(PersonEntity person) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PersonPhotosPage(person: person),
      ),
    );
  }

  void _showPersonOptions(PersonEntity person) {
    showAdaptiveModalSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: Text(context.l10n.photoPeoplePageRename),
              onTap: () {
                Navigator.pop(context);
                _renamePerson(person);
              },
            ),
            ListTile(
              leading: const Icon(Icons.merge),
              title: Text(context.l10n.photoPeoplePageMerge),
              onTap: () {
                Navigator.pop(context);
                _mergePerson(person);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_rounded, color: AppColors.error),
              title: Text(context.l10n.photoPeoplePageDelete, style: TextStyle(color: AppColors.error)),
              onTap: () {
                Navigator.pop(context);
                _deletePerson(person);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _mergePerson(PersonEntity person) async {
    final otherPersons = _persons.where((p) => p.id != person.id).toList();
    if (otherPersons.isEmpty) {
      context.showInfoToast(context.l10n.photoPeoplePageMergeNoOthersHint);
      return;
    }

    final targetPerson = await showDialog<PersonEntity>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.photoPeoplePageMergeSelectTitle),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: otherPersons.length,
            itemBuilder: (context, index) {
              final p = otherPersons[index];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                title: Text(p.displayName),
                subtitle: Text(context.l10n.photoPeoplePagePhotoCountLabel(p.photoCount)),
                onTap: () => Navigator.pop(context, p),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.photoPeoplePageScanCancel),
          ),
        ],
      ),
    );

    if (targetPerson != null) {
      await _faceDb.mergePersons(targetPerson.id, person.id);
      await _loadData();
      if (mounted) {
        context.showSuccessToast(
          context.l10n.photoPeoplePageMergeSuccess(
            person.displayName,
            targetPerson.displayName,
          ),
        );
      }
    }
  }

  Future<void> _deletePerson(PersonEntity person) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.photoPeoplePageDeleteConfirmTitle),
        content: Text(
          context.l10n.photoPeoplePageDeleteConfirmMessage(
            person.displayName,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.photoPeoplePageScanCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(context.l10n.photoPeoplePageDelete),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await _faceDb.deletePerson(person.id);
      await _loadData();
    }
  }
}

/// 人物相册页：显示该 [person] 的所有人脸所在照片
///
/// 通过 [FaceDatabaseService.getFacesByPersonId] 查出该人物的所有 face，
/// 按 photoSourceId+photoPath 去重后用 [StreamImage] 渲染缩略网格。
class _PersonPhotosPage extends ConsumerStatefulWidget {
  const _PersonPhotosPage({required this.person});

  final PersonEntity person;

  @override
  ConsumerState<_PersonPhotosPage> createState() => _PersonPhotosPageState();
}

class _PersonPhotosPageState extends ConsumerState<_PersonPhotosPage> {
  final FaceDatabaseService _faceDb = FaceDatabaseService();
  bool _loading = true;
  List<({String sourceId, String path})> _photos = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final faces = await _faceDb.getFacesByPersonId(widget.person.id);
    // 同一张照片可能有多个 face（多人脸），按 sourceId+path 去重
    final seen = <String>{};
    final photos = <({String sourceId, String path})>[];
    for (final face in faces) {
      final key = '${face.photoSourceId}|${face.photoPath}';
      if (seen.add(key)) {
        photos.add((sourceId: face.photoSourceId, path: face.photoPath));
      }
    }
    if (!mounted) return;
    setState(() {
      _photos = photos;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final connections = ref.watch(activeConnectionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.person.displayName),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _photos.isEmpty
              ? Center(child: Text(context.l10n.photoPeoplePhotosPageEmptyMessage))
              : GridView.builder(
                  padding: const EdgeInsets.all(4),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                  ),
                  itemCount: _photos.length,
                  itemBuilder: (_, index) {
                    final photo = _photos[index];
                    final connection = connections[photo.sourceId];
                    final fileSystem = connection?.adapter.fileSystem;

                    return AspectRatio(
                      aspectRatio: 1,
                      child: StreamImage(
                        path: photo.path,
                        fileSystem: fileSystem,
                        cacheKey: 'person_${widget.person.id}_$index',
                        placeholder: ColoredBox(
                          color: isDark
                              ? AppColors.darkSurfaceVariant
                              : AppColors.lightSurfaceVariant,
                          child: const Icon(Icons.image_rounded),
                        ),
                        errorWidget: ColoredBox(
                          color: isDark
                              ? AppColors.darkSurfaceVariant
                              : AppColors.lightSurfaceVariant,
                          child: const Icon(Icons.broken_image),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
