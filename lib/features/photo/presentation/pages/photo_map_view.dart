import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/photo/data/services/photo_database_service.dart';
import 'package:my_nas/features/photo/data/services/photo_location_index_service.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_list_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class PhotoMapView extends ConsumerStatefulWidget {
  const PhotoMapView({
    required this.photos,
    required this.onOpenPhoto,
    super.key,
  });

  final List<PhotoEntity> photos;
  final void Function(List<PhotoEntity> photos, int initialIndex) onOpenPhoto;

  @override
  ConsumerState<PhotoMapView> createState() => _PhotoMapViewState();
}

class _PhotoMapViewState extends ConsumerState<PhotoMapView> {
  final _mapController = MapController();
  final _indexService = PhotoLocationIndexService();
  final _attemptedKeys = <String>{};
  late List<PhotoEntity> _locatedPhotos;
  PhotoLocationIndexProgress? _progress;
  PhotoLocationIndexResult? _result;
  bool _indexing = false;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _locatedPhotos = widget.photos.where((photo) => photo.hasLocation).toList();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startIndexing());
  }

  @override
  void didUpdateWidget(PhotoMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final allowed = widget.photos.map((photo) => photo.uniqueKey).toSet();
    final locatedByKey = <String, PhotoEntity>{
      for (final photo in _locatedPhotos)
        if (allowed.contains(photo.uniqueKey)) photo.uniqueKey: photo,
      for (final photo in widget.photos)
        if (photo.hasLocation) photo.uniqueKey: photo,
    };
    _locatedPhotos = locatedByKey.values.toList();
    if (!_indexing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startIndexing());
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _startIndexing() async {
    if (!mounted || _indexing) return;
    final pending = widget.photos
        .where(
          (photo) =>
              !photo.locationScanned &&
              !_attemptedKeys.contains(photo.uniqueKey),
        )
        .toList();
    if (pending.isEmpty) return;
    _attemptedKeys.addAll(pending.map((photo) => photo.uniqueKey));

    setState(() {
      _indexing = true;
      _result = null;
    });
    final result = await _indexService.indexPending(
      pending,
      fileSystemForSource: (sourceId) =>
          ref.read(activeConnectionsProvider)[sourceId]?.adapter.fileSystem,
      shouldCancel: () => _cancelled,
      onProgress: (progress) {
        if (!mounted) return;
        setState(() => _progress = progress);
      },
      onLocationFound: (photo) {
        if (!mounted) return;
        setState(() {
          _locatedPhotos = [
            ..._locatedPhotos.where(
              (existing) => existing.uniqueKey != photo.uniqueKey,
            ),
            photo,
          ];
        });
        if (_locatedPhotos.length == 1) {
          _moveAfterMapBuild(LatLng(photo.latitude!, photo.longitude!), 11);
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _indexing = false;
      _result = result;
    });
    if (_locatedPhotos.isNotEmpty) {
      final camera = _initialCamera(_locatedPhotos);
      _moveAfterMapBuild(camera.center, camera.zoom);
    }
    await ref.read(photoListProvider.notifier).reloadFromDatabase();
  }

  void _moveAfterMapBuild(LatLng center, double zoom) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _locatedPhotos.isNotEmpty) {
        _mapController.move(center, zoom);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    if (_locatedPhotos.isEmpty) {
      return SizedBox(
        height: math.max(460, MediaQuery.sizeOf(context).height - 240),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.map_outlined, size: 46, color: t.text3),
                const SizedBox(height: 14),
                Text(
                  l.photoMapNoLocationsTitle,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: t.text0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l.photoMapNoLocationsHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
                ),
                if (_indexing && _progress != null) ...[
                  const SizedBox(height: 18),
                  LinearProgressIndicator(value: _progress!.fraction),
                  const SizedBox(height: 8),
                  Text(
                    l.photoMapIndexing(_progress!.scanned, _progress!.total),
                    style: TextStyle(fontSize: 12, color: t.text2),
                  ),
                ],
                if (!_indexing && (_result?.failed ?? 0) > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    l.photoMapIndexFailures(_result!.failed),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: t.warn),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final camera = _initialCamera(_locatedPhotos);
    final markers = [
      for (var index = 0; index < _locatedPhotos.length; index++)
        _marker(context, _locatedPhotos[index], index),
    ];
    return SizedBox(
      height: math.max(520, MediaQuery.sizeOf(context).height - 205),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: camera.center,
                initialZoom: camera.zoom,
                minZoom: 2,
                maxZoom: 19,
                keepAlive: true,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.kkape.mynas',
                  maxNativeZoom: 19,
                ),
                MarkerClusterLayerWidget(
                  options: MarkerClusterLayerOptions(
                    markers: markers,
                    maxClusterRadius: 48,
                    size: const Size(42, 42),
                    padding: const EdgeInsets.all(36),
                    maxZoom: 19,
                    markerChildBehavior: true,
                    builder: (context, clusterMarkers) => DecoratedBox(
                      decoration: BoxDecoration(
                        color: t.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x44000000),
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          '${clusterMarkers.length}',
                          style: TextStyle(
                            color: t.accentContrast,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      'OpenStreetMap contributors',
                      onTap: () => launchUrl(
                        Uri.parse('https://www.openstreetmap.org/copyright'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 12,
              left: 12,
              child: _MapStatusCard(
                locatedCount: _locatedPhotos.length,
                progress: _indexing ? _progress : null,
                failures: _result?.failed ?? 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Marker _marker(BuildContext context, PhotoEntity photo, int index) => Marker(
    key: ValueKey(photo.uniqueKey),
    point: LatLng(photo.latitude!, photo.longitude!),
    width: 40,
    height: 46,
    alignment: Alignment.topCenter,
    child: Tooltip(
      message: photo.fileName,
      child: Semantics(
        button: true,
        label:
            '${AppLocalizations.of(context).photoMapOpenPhoto}: ${photo.fileName}',
        child: InkResponse(
          onTap: () => widget.onOpenPhoto(_locatedPhotos, index),
          radius: 24,
          child: const Icon(
            Icons.location_on_rounded,
            size: 40,
            color: Color(0xFFE64A35),
            shadows: [Shadow(color: Color(0x66000000), blurRadius: 5)],
          ),
        ),
      ),
    ),
  );
}

class _MapStatusCard extends StatelessWidget {
  const _MapStatusCard({
    required this.locatedCount,
    required this.progress,
    required this.failures,
  });

  final int locatedCount;
  final PhotoLocationIndexProgress? progress;
  final int failures;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.panelBgStrong.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.hairline),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10)],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.photoMapLocatedCount(locatedCount),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: t.text0,
              ),
            ),
            if (progress != null) ...[
              const SizedBox(height: 5),
              SizedBox(
                width: 180,
                child: LinearProgressIndicator(value: progress!.fraction),
              ),
              const SizedBox(height: 4),
              Text(
                l.photoMapIndexing(progress!.scanned, progress!.total),
                style: TextStyle(fontSize: 11, color: t.text2),
              ),
            ] else if (failures > 0) ...[
              const SizedBox(height: 4),
              Text(
                l.photoMapIndexFailures(failures),
                style: TextStyle(fontSize: 11, color: t.warn),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

({LatLng center, double zoom}) _initialCamera(List<PhotoEntity> photos) {
  var minLatitude = 90.0;
  var maxLatitude = -90.0;
  var minLongitude = 180.0;
  var maxLongitude = -180.0;
  for (final photo in photos) {
    minLatitude = math.min(minLatitude, photo.latitude!);
    maxLatitude = math.max(maxLatitude, photo.latitude!);
    minLongitude = math.min(minLongitude, photo.longitude!);
    maxLongitude = math.max(maxLongitude, photo.longitude!);
  }
  final span = math.max(maxLatitude - minLatitude, maxLongitude - minLongitude);
  final zoom = switch (span) {
    > 100 => 2.5,
    > 40 => 3.5,
    > 15 => 4.5,
    > 5 => 6.0,
    > 1 => 8.0,
    > 0.2 => 10.0,
    _ => 12.0,
  };
  return (
    center: LatLng(
      (minLatitude + maxLatitude) / 2,
      (minLongitude + maxLongitude) / 2,
    ),
    zoom: zoom,
  );
}
