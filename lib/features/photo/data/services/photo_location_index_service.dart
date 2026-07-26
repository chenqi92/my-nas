import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/photo/data/services/photo_database_service.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path/path.dart' as p;

class PhotoCoordinate {
  const PhotoCoordinate({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

class PhotoLocationIndexProgress {
  const PhotoLocationIndexProgress({
    required this.scanned,
    required this.total,
    required this.found,
    this.currentName,
  });

  final int scanned;
  final int total;
  final int found;
  final String? currentName;

  double get fraction => total == 0 ? 1 : scanned / total;
}

class PhotoLocationIndexResult {
  const PhotoLocationIndexResult({
    required this.scanned,
    required this.found,
    required this.skipped,
    required this.failed,
  });

  final int scanned;
  final int found;
  final int skipped;
  final int failed;
}

typedef PhotoFileSystemResolver = NasFileSystem? Function(String sourceId);

/// Incrementally extracts GPS coordinates from JPEG APP1/EXIF headers.
///
/// Only the first 128 KiB is requested. JPEG APP1 blocks are limited to 64 KiB,
/// so this includes the complete EXIF payload without downloading full photos.
class PhotoLocationIndexService {
  PhotoLocationIndexService({PhotoDatabaseService? database})
    : _database = database ?? PhotoDatabaseService();

  static const int maxHeaderBytes = 128 * 1024;
  static const int _parallelReads = 4;

  final PhotoDatabaseService _database;

  static PhotoCoordinate? decodeJpegCoordinate(Uint8List bytes) {
    try {
      final exif = img.decodeJpgExif(bytes);
      if (exif == null) return null;
      final gps = exif.gpsIfd;
      final latitude = _decodeCoordinate(
        gps.data[0x0002],
        gps.data[0x0001]?.toString(),
        negativeReference: 'S',
      );
      final longitude = _decodeCoordinate(
        gps.data[0x0004],
        gps.data[0x0003]?.toString(),
        negativeReference: 'W',
      );
      if (latitude == null || longitude == null) return null;
      if (latitude < -90 || latitude > 90) return null;
      if (longitude < -180 || longitude > 180) return null;
      return PhotoCoordinate(latitude: latitude, longitude: longitude);
    } on Object {
      return null;
    }
  }

  static double? _decodeCoordinate(
    img.IfdValue? value,
    String? reference, {
    required String negativeReference,
  }) {
    if (value == null || value.length == 0) return null;
    final absolute = value.length >= 3
        ? value.toDouble(0) + value.toDouble(1) / 60 + value.toDouble(2) / 3600
        : value.toDouble();
    if (!absolute.isFinite) return null;
    final normalizedReference = reference?.trim().toUpperCase();
    return normalizedReference == negativeReference ? -absolute : absolute;
  }

  Future<PhotoCoordinate?> readCoordinate(
    NasFileSystem fileSystem,
    PhotoEntity photo,
  ) async {
    final extension = p.extension(photo.filePath).toLowerCase();
    if (extension != '.jpg' && extension != '.jpeg') return null;

    final available = photo.size > 0
        ? photo.size.clamp(0, maxHeaderBytes)
        : maxHeaderBytes;
    if (available == 0) return null;
    final stream = await fileSystem.getFileStream(
      photo.filePath,
      range: FileRange(start: 0, end: available),
    );
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      final remaining = maxHeaderBytes - bytes.length;
      if (remaining <= 0) break;
      bytes.add(
        chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
      );
      if (bytes.length >= maxHeaderBytes) break;
    }
    return decodeJpegCoordinate(bytes.takeBytes());
  }

  Future<PhotoLocationIndexResult> indexPending(
    List<PhotoEntity> photos, {
    required PhotoFileSystemResolver fileSystemForSource,
    void Function(PhotoLocationIndexProgress progress)? onProgress,
    void Function(PhotoEntity photo)? onLocationFound,
    bool Function()? shouldCancel,
  }) async {
    final pending = photos.where((photo) => !photo.locationScanned).toList();
    var scanned = 0;
    var found = 0;
    var skipped = 0;
    var failed = 0;

    onProgress?.call(
      PhotoLocationIndexProgress(scanned: 0, total: pending.length, found: 0),
    );

    for (var offset = 0; offset < pending.length; offset += _parallelReads) {
      if (shouldCancel?.call() ?? false) break;
      final end = (offset + _parallelReads).clamp(0, pending.length);
      final batch = pending.sublist(offset, end);
      await Future.wait([
        for (final photo in batch)
          _indexOne(photo, fileSystemForSource: fileSystemForSource)
              .then((coordinate) {
                if (coordinate == null) {
                  skipped++;
                } else {
                  found++;
                  onLocationFound?.call(
                    photo.copyWith(
                      latitude: coordinate.latitude,
                      longitude: coordinate.longitude,
                      locationScanned: true,
                    ),
                  );
                }
              })
              .onError((error, stackTrace) {
                failed++;
                logger.w(
                  'PhotoLocationIndexService: GPS 读取失败 ${photo.filePath}',
                  error,
                  stackTrace,
                );
              })
              .whenComplete(() {
                scanned++;
                onProgress?.call(
                  PhotoLocationIndexProgress(
                    scanned: scanned,
                    total: pending.length,
                    found: found,
                    currentName: photo.fileName,
                  ),
                );
              }),
      ]);
    }

    return PhotoLocationIndexResult(
      scanned: scanned,
      found: found,
      skipped: skipped,
      failed: failed,
    );
  }

  Future<PhotoCoordinate?> _indexOne(
    PhotoEntity photo, {
    required PhotoFileSystemResolver fileSystemForSource,
  }) async {
    final extension = p.extension(photo.filePath).toLowerCase();
    if (extension != '.jpg' && extension != '.jpeg') {
      await _database.updateLocation(photo.sourceId, photo.filePath);
      return null;
    }

    final fileSystem = fileSystemForSource(photo.sourceId);
    if (fileSystem == null) {
      throw StateError('Source ${photo.sourceId} is not connected.');
    }
    final coordinate = await readCoordinate(fileSystem, photo);
    await _database.updateLocation(
      photo.sourceId,
      photo.filePath,
      latitude: coordinate?.latitude,
      longitude: coordinate?.longitude,
    );
    return coordinate;
  }
}
