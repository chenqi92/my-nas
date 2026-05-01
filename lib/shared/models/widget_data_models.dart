/// 小组件数据模型
library;

// ignore_for_file: unused_field, unused_element

import 'dart:typed_data';

/// 存储小组件数据
class StorageWidgetData {
  const StorageWidgetData({
    required this.totalBytes,
    required this.usedBytes,
    required this.nasName,
    required this.adapterType,
    required this.lastUpdated,
    this.isConnected = true,
  });

  final int totalBytes;
  final int usedBytes;
  final String nasName;
  final String adapterType;
  final DateTime? lastUpdated; // 可空：未连接时为 null
  final bool isConnected;

  /// 使用百分比 (0.0 - 1.0)
  double get usagePercent => totalBytes > 0 ? usedBytes / totalBytes : 0;

  /// 使用百分比整数 (0 - 100)
  int get usagePercentInt => (usagePercent * 100).round();

  /// 是否存储空间紧张 (>90%)
  bool get isLowSpace => usagePercent > 0.9;

  /// 是否有有效的存储信息
  bool get hasValidData => totalBytes > 0;

  Map<String, dynamic> toJson() => {
        'totalBytes': totalBytes,
        'usedBytes': usedBytes,
        'nasName': nasName,
        'adapterType': adapterType,
        'lastUpdated': lastUpdated?.millisecondsSinceEpoch,
        'isConnected': isConnected,
      };

  factory StorageWidgetData.fromJson(Map<String, dynamic> json) {
    final lastUpdatedMs = json['lastUpdated'] as int?;
    return StorageWidgetData(
      totalBytes: json['totalBytes'] as int? ?? 0,
      usedBytes: json['usedBytes'] as int? ?? 0,
      nasName: json['nasName'] as String? ?? 'NAS',
      adapterType: json['adapterType'] as String? ?? 'unknown',
      lastUpdated: lastUpdatedMs != null
          ? DateTime.fromMillisecondsSinceEpoch(lastUpdatedMs)
          : null,
      isConnected: json['isConnected'] as bool? ?? false,
    );
  }

  /// 空数据（未连接状态）
  static const empty = StorageWidgetData(
    totalBytes: 0,
    usedBytes: 0,
    nasName: '',
    adapterType: 'unknown',
    lastUpdated: null,
    isConnected: false,
  );

  /// 占位数据（用于 Widget 预览）
  static StorageWidgetData get placeholder => StorageWidgetData(
        totalBytes: 1000000000000, // 1 TB
        usedBytes: 650000000000, // 650 GB
        nasName: 'My NAS',
        adapterType: 'synology',
        lastUpdated: DateTime.now(),
      );

  // ignore: prefer_constructors_over_static_methods
  static StorageWidgetData? _emptyInstance;

  const StorageWidgetData._internal({
    required this.totalBytes,
    required this.usedBytes,
    required this.nasName,
    required this.adapterType,
    required DateTime? lastUpdated,
    required this.isConnected,
  }) : lastUpdated = lastUpdated ?? const _DefaultDateTime();
}

/// 用于 const 构造函数的默认时间
class _DefaultDateTime implements DateTime {
  const _DefaultDateTime();

  @override
  DateTime add(Duration duration) => DateTime.now().add(duration);

  @override
  int compareTo(DateTime other) => DateTime.now().compareTo(other);

  @override
  int get day => DateTime.now().day;

  @override
  Duration difference(DateTime other) => DateTime.now().difference(other);

  @override
  int get hour => DateTime.now().hour;

  @override
  bool isAfter(DateTime other) => DateTime.now().isAfter(other);

  @override
  bool isAtSameMomentAs(DateTime other) =>
      DateTime.now().isAtSameMomentAs(other);

  @override
  bool isBefore(DateTime other) => DateTime.now().isBefore(other);

  @override
  bool get isUtc => false;

  @override
  int get microsecond => DateTime.now().microsecond;

  @override
  int get microsecondsSinceEpoch => DateTime.now().microsecondsSinceEpoch;

  @override
  int get millisecond => DateTime.now().millisecond;

  @override
  int get millisecondsSinceEpoch => DateTime.now().millisecondsSinceEpoch;

  @override
  int get minute => DateTime.now().minute;

  @override
  int get month => DateTime.now().month;

  @override
  int get second => DateTime.now().second;

  @override
  DateTime subtract(Duration duration) => DateTime.now().subtract(duration);

  @override
  String get timeZoneName => DateTime.now().timeZoneName;

  @override
  Duration get timeZoneOffset => DateTime.now().timeZoneOffset;

  @override
  String toIso8601String() => DateTime.now().toIso8601String();

  @override
  DateTime toLocal() => DateTime.now().toLocal();

  @override
  DateTime toUtc() => DateTime.now().toUtc();

  @override
  int get weekday => DateTime.now().weekday;

  @override
  int get year => DateTime.now().year;
}

/// 下载任务摘要（用于小组件）
class DownloadTaskSummary {
  const DownloadTaskSummary({
    required this.id,
    required this.fileName,
    required this.progress,
    required this.status,
  });

  final String id;
  final String fileName;
  final double progress;
  final String status;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'progress': progress,
        'status': status,
      };

  factory DownloadTaskSummary.fromJson(Map<String, dynamic> json) =>
      DownloadTaskSummary(
        id: json['id'] as String? ?? '',
        fileName: json['fileName'] as String? ?? '',
        progress: (json['progress'] as num?)?.toDouble() ?? 0,
        status: json['status'] as String? ?? 'pending',
      );
}

/// 下载小组件数据
class DownloadWidgetData {
  const DownloadWidgetData({
    required this.activeTasks,
    required this.completedCount,
    required this.totalCount,
    required this.lastUpdated,
  });

  final List<DownloadTaskSummary> activeTasks;
  final int completedCount;
  final int totalCount;
  final DateTime lastUpdated;

  /// 活跃任务数量
  int get activeCount => activeTasks.length;

  /// 是否有活跃下载
  bool get hasActiveDownloads => activeTasks.isNotEmpty;

  /// 总体进度 (0.0 - 1.0)
  double get overallProgress {
    if (activeTasks.isEmpty) return 0;
    final sum = activeTasks.fold<double>(0, (sum, t) => sum + t.progress);
    return sum / activeTasks.length;
  }

  /// 当前下载的文件名
  String? get currentFileName =>
      activeTasks.isNotEmpty ? activeTasks.first.fileName : null;

  Map<String, dynamic> toJson() => {
        'activeTasks': activeTasks.map((t) => t.toJson()).toList(),
        'completedCount': completedCount,
        'totalCount': totalCount,
        'lastUpdated': lastUpdated.millisecondsSinceEpoch,
      };

  factory DownloadWidgetData.fromJson(Map<String, dynamic> json) =>
      DownloadWidgetData(
        activeTasks: (json['activeTasks'] as List<dynamic>?)
                ?.map(
                  (e) =>
                      DownloadTaskSummary.fromJson(e as Map<String, dynamic>),
                )
                .toList() ??
            [],
        completedCount: json['completedCount'] as int? ?? 0,
        totalCount: json['totalCount'] as int? ?? 0,
        lastUpdated: DateTime.fromMillisecondsSinceEpoch(
          json['lastUpdated'] as int? ?? 0,
        ),
      );

  /// 空数据
  static DownloadWidgetData get empty => DownloadWidgetData(
        activeTasks: const [],
        completedCount: 0,
        totalCount: 0,
        lastUpdated: DateTime.now(),
      );

  /// 占位数据
  static DownloadWidgetData get placeholder => DownloadWidgetData(
        activeTasks: const [
          DownloadTaskSummary(
            id: '1',
            fileName: 'movie.mkv',
            progress: 0.45,
            status: 'downloading',
          ),
        ],
        completedCount: 3,
        totalCount: 5,
        lastUpdated: DateTime.now(),
      );
}

/// 媒体播放小组件数据
class MediaWidgetData {
  const MediaWidgetData({
    this.title,
    this.artist,
    this.album,
    this.coverImagePath,
    this.coverImageData,
    required this.isPlaying,
    required this.progress,
    this.currentTime = 0,
    this.totalTime = 0,
    this.themeColor,
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? coverImagePath;
  final Uint8List? coverImageData;
  final bool isPlaying;
  final double progress;
  final int currentTime; // 秒
  final int totalTime; // 秒
  final int? themeColor; // ARGB

  /// 是否有正在播放的内容
  bool get hasContent => title != null && title!.isNotEmpty;

  /// 是否有封面
  bool get hasCover =>
      (coverImagePath != null && coverImagePath!.isNotEmpty) ||
      (coverImageData != null && coverImageData!.isNotEmpty);

  Map<String, dynamic> toJson() => {
        'title': title,
        'artist': artist,
        'album': album,
        'coverImagePath': coverImagePath,
        'isPlaying': isPlaying,
        'progress': progress,
        'currentTime': currentTime,
        'totalTime': totalTime,
        'themeColor': themeColor,
        // coverImageData 不序列化到 JSON，单独处理
      };

  factory MediaWidgetData.fromJson(Map<String, dynamic> json) =>
      MediaWidgetData(
        title: json['title'] as String?,
        artist: json['artist'] as String?,
        album: json['album'] as String?,
        coverImagePath: json['coverImagePath'] as String?,
        isPlaying: json['isPlaying'] as bool? ?? false,
        progress: (json['progress'] as num?)?.toDouble() ?? 0,
        currentTime: json['currentTime'] as int? ?? 0,
        totalTime: json['totalTime'] as int? ?? 0,
        themeColor: json['themeColor'] as int?,
      );

  /// 空数据
  static const empty = MediaWidgetData(
    isPlaying: false,
    progress: 0,
  );

  /// 占位数据
  static const placeholder = MediaWidgetData(
    title: 'Song Title',
    artist: 'Artist Name',
    album: 'Album Name',
    isPlaying: true,
    progress: 0.45,
    currentTime: 120,
    totalTime: 300,
  );
}

/// 快捷操作项
/// 注意：id 必须与路由路径一致 (例如 /music, /video, /reading)
enum QuickAccessType {
  music('music', '音乐'),
  video('video', '视频'),
  reading('reading', '图书'), // 对应路由 /reading
  photo('photo', '相册'),
  files('files', '文件'); // 对应路由 /files

  const QuickAccessType(this.id, this.label);

  final String id;
  final String label;

  /// URL Scheme - 与路由路径一致
  String get urlScheme => 'mynas://$id';

  /// SF Symbol 名称 (iOS/macOS)
  String get sfSymbolName {
    switch (this) {
      case QuickAccessType.music:
        return 'music.note';
      case QuickAccessType.video:
        return 'play.rectangle';
      case QuickAccessType.reading:
        return 'book';
      case QuickAccessType.photo:
        return 'photo';
      case QuickAccessType.files:
        return 'folder';
    }
  }

  /// Material Icon 名称 (Android)
  String get materialIconName {
    switch (this) {
      case QuickAccessType.music:
        return 'music_note';
      case QuickAccessType.video:
        return 'play_circle';
      case QuickAccessType.reading:
        return 'book';
      case QuickAccessType.photo:
        return 'photo_library';
      case QuickAccessType.files:
        return 'folder';
    }
  }
}

/// 快捷操作小组件数据
class QuickAccessWidgetData {
  const QuickAccessWidgetData({
    required this.items,
    this.nasName,
    this.isConnected = false,
  });

  final List<QuickAccessType> items;
  final String? nasName;
  final bool isConnected;

  Map<String, dynamic> toJson() => {
        'items': items.map((e) => e.id).toList(),
        'nasName': nasName,
        'isConnected': isConnected,
      };

  factory QuickAccessWidgetData.fromJson(Map<String, dynamic> json) =>
      QuickAccessWidgetData(
        items: (json['items'] as List<dynamic>?)
                ?.map(
                  (e) => QuickAccessType.values.firstWhere(
                    (t) => t.id == e,
                    orElse: () => QuickAccessType.files,
                  ),
                )
                .toList() ??
            QuickAccessType.values,
        nasName: json['nasName'] as String?,
        isConnected: json['isConnected'] as bool? ?? false,
      );

  /// 默认数据（显示所有快捷操作）
  static const defaultData = QuickAccessWidgetData(
    items: [
      QuickAccessType.music,
      QuickAccessType.video,
      QuickAccessType.reading,
    ],
  );
}

/// 小组件主题数据
/// 用于同步应用配色方案到原生小组件
class ThemeWidgetData {
  const ThemeWidgetData({
    required this.presetId,
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.secondary,
    required this.accent,
    required this.music,
    required this.video,
    required this.photo,
    required this.book,
    required this.download,
    required this.darkBackground,
    required this.darkSurface,
    required this.darkSurfaceVariant,
    required this.success,
    required this.warning,
    required this.error,
  });

  /// 配色方案ID
  final String presetId;

  /// 主色 (ARGB)
  final int primary;
  final int primaryLight;
  final int primaryDark;

  /// 次要色 (ARGB)
  final int secondary;

  /// 强调色 (ARGB)
  final int accent;

  /// 功能性颜色 (ARGB)
  final int music;
  final int video;
  final int photo;
  final int book;
  final int download;

  /// 深色背景 (ARGB)
  final int darkBackground;
  final int darkSurface;
  final int darkSurfaceVariant;

  /// 状态颜色 (ARGB)
  final int success;
  final int warning;
  final int error;

  Map<String, dynamic> toJson() => {
        'presetId': presetId,
        'primary': primary,
        'primaryLight': primaryLight,
        'primaryDark': primaryDark,
        'secondary': secondary,
        'accent': accent,
        'music': music,
        'video': video,
        'photo': photo,
        'book': book,
        'download': download,
        'darkBackground': darkBackground,
        'darkSurface': darkSurface,
        'darkSurfaceVariant': darkSurfaceVariant,
        'success': success,
        'warning': warning,
        'error': error,
      };

  factory ThemeWidgetData.fromJson(Map<String, dynamic> json) =>
      ThemeWidgetData(
        presetId: json['presetId'] as String? ?? 'teal',
        primary: json['primary'] as int? ?? 0xFF14B8A6,
        primaryLight: json['primaryLight'] as int? ?? 0xFF2DD4BF,
        primaryDark: json['primaryDark'] as int? ?? 0xFF0D9488,
        secondary: json['secondary'] as int? ?? 0xFF06B6D4,
        accent: json['accent'] as int? ?? 0xFF06B6D4,
        music: json['music'] as int? ?? 0xFF8B5CF6,
        video: json['video'] as int? ?? 0xFFEC4899,
        photo: json['photo'] as int? ?? 0xFF10B981,
        book: json['book'] as int? ?? 0xFFF59E0B,
        download: json['download'] as int? ?? 0xFF3B82F6,
        darkBackground: json['darkBackground'] as int? ?? 0xFF0D0D0D,
        darkSurface: json['darkSurface'] as int? ?? 0xFF1A1A1A,
        darkSurfaceVariant: json['darkSurfaceVariant'] as int? ?? 0xFF242424,
        success: json['success'] as int? ?? 0xFF22C55E,
        warning: json['warning'] as int? ?? 0xFFF59E0B,
        error: json['error'] as int? ?? 0xFFEF4444,
      );

  /// 默认主题 (Teal)
  static const defaultTheme = ThemeWidgetData(
    presetId: 'teal',
    primary: 0xFF14B8A6,
    primaryLight: 0xFF2DD4BF,
    primaryDark: 0xFF0D9488,
    secondary: 0xFF06B6D4,
    accent: 0xFF06B6D4,
    music: 0xFF8B5CF6,
    video: 0xFFEC4899,
    photo: 0xFF10B981,
    book: 0xFFF59E0B,
    download: 0xFF3B82F6,
    darkBackground: 0xFF0D0D0D,
    darkSurface: 0xFF1A1A1A,
    darkSurfaceVariant: 0xFF242424,
    success: 0xFF22C55E,
    warning: 0xFFF59E0B,
    error: 0xFFEF4444,
  );
}
