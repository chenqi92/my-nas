import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:uuid/uuid.dart';

/// 直播源配置
///
/// 包含一个 M3U 播放列表的基本信息和解析后的频道列表
class LiveStreamSource {
  LiveStreamSource({
    String? id,
    required this.name,
    this.iconUrl,
    required this.playlistUrl,
    this.channels = const [],
    this.sortOrder = 0,
    this.isEnabled = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 从 Map 创建
  factory LiveStreamSource.fromMap(Map<String, dynamic> map) =>
      LiveStreamSource(
        id: map['id'] as String?,
        name: map['name'] as String? ?? '',
        iconUrl: map['iconUrl'] as String?,
        playlistUrl: map['playlistUrl'] as String? ?? '',
        channels: (map['channels'] as List<dynamic>?)
                ?.map(
                  (e) => LiveChannel.fromMap(e as Map<String, dynamic>),
                )
                .toList() ??
            [],
        sortOrder: map['sortOrder'] as int? ?? 0,
        isEnabled: map['isEnabled'] as bool? ?? true,
        createdAt: map['createdAt'] != null
            ? DateTime.tryParse(map['createdAt'] as String)
            : null,
        updatedAt: map['updatedAt'] != null
            ? DateTime.tryParse(map['updatedAt'] as String)
            : null,
      );

  /// 唯一标识
  final String id;

  /// 源名称
  final String name;

  /// 图标 URL (可选)
  final String? iconUrl;

  /// M3U 播放列表 URL
  final String playlistUrl;

  /// 解析后的频道列表
  final List<LiveChannel> channels;

  /// 排序顺序
  final int sortOrder;

  /// 是否启用
  final bool isEnabled;

  /// 创建时间
  final DateTime createdAt;

  /// 更新时间
  final DateTime updatedAt;

  /// 频道数量
  int get channelCount => channels.length;

  /// 获取所有分类
  Set<String> get categories => channels
      .map((c) => c.category)
      .where((c) => c != null && c.isNotEmpty)
      .cast<String>()
      .toSet();

  /// 转为 Map
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'iconUrl': iconUrl,
        'playlistUrl': playlistUrl,
        'channels': channels.map((c) => c.toMap()).toList(),
        'sortOrder': sortOrder,
        'isEnabled': isEnabled,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// 复制并修改
  LiveStreamSource copyWith({
    String? id,
    String? name,
    String? iconUrl,
    String? playlistUrl,
    List<LiveChannel>? channels,
    int? sortOrder,
    bool? isEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      LiveStreamSource(
        id: id ?? this.id,
        name: name ?? this.name,
        iconUrl: iconUrl ?? this.iconUrl,
        playlistUrl: playlistUrl ?? this.playlistUrl,
        channels: channels ?? this.channels,
        sortOrder: sortOrder ?? this.sortOrder,
        isEnabled: isEnabled ?? this.isEnabled,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveStreamSource &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 直播频道
///
/// 单个可播放的直播流
class LiveChannel {
  const LiveChannel({
    required this.id,
    required this.name,
    required this.streamUrl,
    this.logoUrl,
    this.category,
    this.epgUrl,
    this.headers,
    this.tvgId,
    this.tvgName,
  });

  /// 从 Map 创建
  factory LiveChannel.fromMap(Map<String, dynamic> map) => LiveChannel(
        id: map['id'] as String? ?? '',
        name: map['name'] as String? ?? '',
        streamUrl: map['streamUrl'] as String? ?? '',
        logoUrl: map['logoUrl'] as String?,
        category: map['category'] as String?,
        epgUrl: map['epgUrl'] as String?,
        headers: (map['headers'] as Map<String, dynamic>?)?.cast<String, String>(),
        tvgId: map['tvgId'] as String?,
        tvgName: map['tvgName'] as String?,
      );

  /// 唯一标识
  final String id;

  /// 频道名称
  final String name;

  /// 直播流 URL
  final String streamUrl;

  /// 频道 Logo URL
  final String? logoUrl;

  /// 分类 (如: 央视、卫视、体育、电影)
  final String? category;

  /// 电子节目单 URL
  final String? epgUrl;

  /// 自定义请求头
  final Map<String, String>? headers;

  /// TVG ID (用于 EPG 匹配)
  final String? tvgId;

  /// TVG 名称
  final String? tvgName;

  /// 获取显示名称
  String get displayName => tvgName ?? name;

  /// 获取分类显示名称
  String get categoryDisplayName => category ?? appL10n.livePageUncategorized;

  /// 转为 Map
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'streamUrl': streamUrl,
        'logoUrl': logoUrl,
        'category': category,
        'epgUrl': epgUrl,
        'headers': headers,
        'tvgId': tvgId,
        'tvgName': tvgName,
      };

  /// 复制并修改
  LiveChannel copyWith({
    String? id,
    String? name,
    String? streamUrl,
    String? logoUrl,
    String? category,
    String? epgUrl,
    Map<String, String>? headers,
    String? tvgId,
    String? tvgName,
  }) =>
      LiveChannel(
        id: id ?? this.id,
        name: name ?? this.name,
        streamUrl: streamUrl ?? this.streamUrl,
        logoUrl: logoUrl ?? this.logoUrl,
        category: category ?? this.category,
        epgUrl: epgUrl ?? this.epgUrl,
        headers: headers ?? this.headers,
        tvgId: tvgId ?? this.tvgId,
        tvgName: tvgName ?? this.tvgName,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveChannel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 直播源设置
///
/// 包含所有直播源的配置
class LiveStreamSettings {
  const LiveStreamSettings({
    this.sources = const [],
  });

  /// 从 Map 创建
  factory LiveStreamSettings.fromMap(Map<String, dynamic> map) {
    final sourcesData = map['sources'] as List<dynamic>? ?? [];
    return LiveStreamSettings(
      sources: sourcesData
          .map((s) => LiveStreamSource.fromMap(s as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 默认空配置
  factory LiveStreamSettings.empty() => const LiveStreamSettings();

  /// 所有直播源
  final List<LiveStreamSource> sources;

  /// 获取启用的源（已排序）
  List<LiveStreamSource> get enabledSources {
    final enabled = sources.where((s) => s.isEnabled).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return enabled;
  }

  /// 获取所有源（已排序）
  List<LiveStreamSource> get sortedSources {
    final sorted = List<LiveStreamSource>.from(sources)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return sorted;
  }

  /// 获取所有启用源的频道
  List<LiveChannel> get allChannels =>
      enabledSources.expand((s) => s.channels).toList();

  /// 获取所有分类
  Set<String> get allCategories =>
      enabledSources.expand((s) => s.categories).toSet();

  /// 按分类获取频道
  Map<String, List<LiveChannel>> get channelsByCategory {
    final result = <String, List<LiveChannel>>{};
    for (final channel in allChannels) {
      final category = channel.category ?? appL10n.livePageUncategorized;
      result.putIfAbsent(category, () => []).add(channel);
    }
    return result;
  }

  /// 转为 Map
  Map<String, dynamic> toMap() => {
        'sources': sources.map((s) => s.toMap()).toList(),
      };

  /// 添加源
  LiveStreamSettings addSource(LiveStreamSource source) {
    final maxOrder = sources.fold<int>(
      -1,
      (max, s) => s.sortOrder > max ? s.sortOrder : max,
    );
    final newSource = source.copyWith(sortOrder: maxOrder + 1);
    return LiveStreamSettings(sources: [...sources, newSource]);
  }

  /// 更新源
  LiveStreamSettings updateSource(LiveStreamSource source) {
    final newSources = sources.map((s) {
      if (s.id == source.id) {
        return source.copyWith(updatedAt: DateTime.now());
      }
      return s;
    }).toList();
    return LiveStreamSettings(sources: newSources);
  }

  /// 删除源
  LiveStreamSettings removeSource(String sourceId) {
    final newSources = sources.where((s) => s.id != sourceId).toList();
    return LiveStreamSettings(sources: newSources);
  }

  /// 切换源启用状态
  LiveStreamSettings toggleEnabled(String sourceId, {bool? enabled}) {
    final newSources = sources.map((s) {
      if (s.id == sourceId) {
        return s.copyWith(isEnabled: enabled ?? !s.isEnabled);
      }
      return s;
    }).toList();
    return LiveStreamSettings(sources: newSources);
  }

  /// 重新排序
  LiveStreamSettings reorder(int oldIndex, int newIndex) {
    final sorted = sortedSources;
    final item = sorted.removeAt(oldIndex);
    sorted.insert(newIndex, item);

    final newSources = <LiveStreamSource>[];
    for (var i = 0; i < sorted.length; i++) {
      newSources.add(sorted[i].copyWith(sortOrder: i));
    }
    return LiveStreamSettings(sources: newSources);
  }
}
