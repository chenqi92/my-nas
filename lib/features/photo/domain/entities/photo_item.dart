import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 照片项实体
class PhotoItem {
  const PhotoItem({
    required this.name,
    required this.path,
    required this.url,
    this.sourceId = '',
    this.thumbnailUrl,
    this.size = 0,
    this.width,
    this.height,
    this.takenAt,
    this.modifiedAt,
    this.latitude,
    this.longitude,
    this.cameraMake,
    this.cameraModel,
    this.isLivePhoto = false,
    this.livePhotoVideoPath,
  });

  /// 从文件项创建照片项
  factory PhotoItem.fromFileItem(
    FileItem file,
    String url, {
    String? thumbnailUrl,
    String sourceId = '',
  }) =>
      PhotoItem(
        name: file.name,
        path: file.path,
        url: url,
        sourceId: sourceId,
        thumbnailUrl: thumbnailUrl ?? file.thumbnailUrl,
        size: file.size,
        modifiedAt: file.modifiedTime,
        isLivePhoto: file.isLivePhoto,
        livePhotoVideoPath: file.livePhotoVideoPath,
      );

  final String name;
  final String path;
  final String url;
  final String sourceId; // 数据源ID
  final String? thumbnailUrl;
  final int size;
  final int? width;
  final int? height;
  final DateTime? takenAt;
  final DateTime? modifiedAt;
  final double? latitude;
  final double? longitude;
  final String? cameraMake;
  final String? cameraModel;

  /// 是否为 iOS Live Photo（实况照片）
  final bool isLivePhoto;

  /// Live Photo 的视频路径
  final String? livePhotoVideoPath;

  /// 显示的文件大小
  String get displaySize {
    if (size <= 0) return appL10n.photoItemDisplaySizeUnknown;
    const units = ['B', 'KB', 'MB', 'GB'];
    var unitIndex = 0;
    var displaySize = size.toDouble();
    while (displaySize >= 1024 && unitIndex < units.length - 1) {
      displaySize /= 1024;
      unitIndex++;
    }
    return '${displaySize.toStringAsFixed(displaySize < 10 ? 1 : 0)} ${units[unitIndex]}';
  }

  /// 显示的分辨率
  String? get displayResolution {
    if (width == null || height == null) return null;
    return '$width × $height';
  }

  /// 是否有 GPS 信息
  bool get hasLocation => latitude != null && longitude != null;

  /// 相机信息
  String? get cameraInfo {
    if (cameraMake == null && cameraModel == null) return null;
    return [cameraMake, cameraModel].whereType<String>().join(' ');
  }

  PhotoItem copyWith({
    String? name,
    String? path,
    String? url,
    String? sourceId,
    String? thumbnailUrl,
    int? size,
    int? width,
    int? height,
    DateTime? takenAt,
    DateTime? modifiedAt,
    double? latitude,
    double? longitude,
    String? cameraMake,
    String? cameraModel,
    bool? isLivePhoto,
    String? livePhotoVideoPath,
  }) =>
      PhotoItem(
        name: name ?? this.name,
        path: path ?? this.path,
        url: url ?? this.url,
        sourceId: sourceId ?? this.sourceId,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        size: size ?? this.size,
        width: width ?? this.width,
        height: height ?? this.height,
        takenAt: takenAt ?? this.takenAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        cameraMake: cameraMake ?? this.cameraMake,
        cameraModel: cameraModel ?? this.cameraModel,
        isLivePhoto: isLivePhoto ?? this.isLivePhoto,
        livePhotoVideoPath: livePhotoVideoPath ?? this.livePhotoVideoPath,
      );
}

/// 时间线分组粒度
enum PhotoGroupGranularity { day, month, year }

/// 照片分组（按日期）
/// 支持泛型以兼容 PhotoItem 和 PhotoEntity
class PhotoGroup<T> {
  const PhotoGroup({
    required this.date,
    required this.photos,
    this.granularity = PhotoGroupGranularity.day,
  });

  final DateTime date;
  final List<T> photos;
  final PhotoGroupGranularity granularity;

  /// 格式化日期标题（根据粒度显示不同格式）
  String get dateTitle {
    // 1970 年表示未知日期
    if (date.year <= 1970) {
      return appL10n.photoGroupDateTitleUnknown;
    }

    final now = DateTime.now();

    // 按年分组
    if (granularity == PhotoGroupGranularity.year) {
      if (date.year == now.year) return appL10n.photoGroupDateTitleThisYear;
      return appL10n.photoGroupDateTitleYear(date.year);
    }

    // 按月分组
    if (granularity == PhotoGroupGranularity.month) {
      if (date.year == now.year && date.month == now.month) return appL10n.photoGroupDateTitleThisMonth;
      if (date.year == now.year) return appL10n.photoGroupDateTitleMonth(date.month);
      return appL10n.photoGroupDateTitleYearMonth(date.year, date.month);
    }

    // 按天分组（原有逻辑）
    final today = DateTime(now.year, now.month, now.day);
    final groupDate = DateTime(date.year, date.month, date.day);
    final diff = today.difference(groupDate).inDays;

    if (diff == 0) return appL10n.photoGroupDateTitleToday;
    if (diff == 1) return appL10n.photoGroupDateTitleYesterday;
    if (diff < 7) return appL10n.photoGroupDateTitleDaysAgo(diff);
    if (date.year == now.year) {
      return appL10n.photoGroupDateTitleMonthDay(date.month, date.day);
    }
    return appL10n.photoGroupDateTitleFull(date.year, date.month, date.day);
  }
}
