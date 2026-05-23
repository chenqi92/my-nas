/// 媒体搜索结果（包含种子分组）
class NtMediaSearchResult {
  const NtMediaSearchResult({
    required this.key,
    required this.title,
    this.year,
    this.type,
    this.vote,
    this.tmdbId,
    this.backdrop,
    this.poster,
    this.overview,
    this.image,
    this.fav,
    required this.torrents,
  });

  factory NtMediaSearchResult.fromJson(Map<String, dynamic> json) {
    final torrents = <NtTorrentGroup>[];
    
    // 解析 torrent_dict - 可能是 List 或 Map
    final torrentDict = json['torrent_dict'];
    if (torrentDict is List) {
      for (final item in torrentDict) {
        if (item is List && item.length >= 2) {
          final type = item[0] as String?;
          final groups = item[1];
          if (groups is Map<String, dynamic>) {
            for (final entry in groups.entries) {
              final groupName = entry.key;
              final groupData = entry.value as Map<String, dynamic>?;
              if (groupData != null) {
                torrents.add(NtTorrentGroup.fromJson(groupData, type, groupName));
              }
            }
          }
        }
      }
    } else if (torrentDict is Map<String, dynamic>) {
      for (final entry in torrentDict.entries) {
        final type = entry.key;
        final groups = entry.value;
        if (groups is Map<String, dynamic>) {
          for (final groupEntry in groups.entries) {
            final groupName = groupEntry.key;
            final groupData = groupEntry.value as Map<String, dynamic>?;
            if (groupData != null) {
              torrents.add(NtTorrentGroup.fromJson(groupData, type, groupName));
            }
          }
        }
      }
    }

    return NtMediaSearchResult(
      key: _parseInt(json['key']) ?? 0,
      title: json['title'] as String? ?? '',
      year: json['year']?.toString(),
      type: json['type'] as String?,
      vote: json['vote']?.toString(),
      tmdbId: json['tmdbid']?.toString(),
      backdrop: json['backdrop'] as String?,
      poster: json['poster'] as String? ?? json['image'] as String?,
      overview: json['overview'] as String?,
      image: json['image'] as String?,
      fav: json['fav']?.toString(),
      torrents: torrents,
    );
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  final int key;
  final String title;
  final String? year;
  final String? type;
  final String? vote;
  final String? tmdbId;
  final String? backdrop;
  final String? poster;
  final String? overview;
  final String? image;
  final String? fav;
  final List<NtTorrentGroup> torrents;

  /// 获取封面图
  String? get coverImage => poster ?? image;

  /// 是否已收藏
  bool get isFavorite => fav == '1';
}

/// 种子分组（按质量）
class NtTorrentGroup {
  const NtTorrentGroup({
    required this.type,
    required this.groupName,
    this.resolution,
    this.resType,
    required this.totalCount,
    required this.items,
  });

  factory NtTorrentGroup.fromJson(Map<String, dynamic> json, String? type, String groupName) {
    final items = <NtTorrentItem>[];
    
    // 解析 group_torrents
    final groupTorrents = json['group_torrents'] as Map<String, dynamic>?;
    if (groupTorrents != null) {
      for (final entry in groupTorrents.entries) {
        final torrentData = entry.value as Map<String, dynamic>?;
        if (torrentData != null) {
          items.add(NtTorrentItem.fromJson(torrentData, entry.key));
        }
      }
    }

    final groupInfo = json['group_info'] as Map<String, dynamic>?;

    return NtTorrentGroup(
      type: type ?? 'MOV',
      groupName: groupName,
      resolution: groupInfo?['respix'] as String?,
      resType: groupInfo?['restype'] as String?,
      totalCount: json['group_total'] as int? ?? items.length,
      items: items,
    );
  }

  final String type;
  final String groupName;
  final String? resolution;
  final String? resType;
  final int totalCount;
  final List<NtTorrentItem> items;

  /// 显示标题（如 "1080p WEB-DL"）
  String get displayTitle {
    final parts = <String>[];
    if (resolution != null) parts.add(resolution!);
    if (resType != null) parts.add(resType!);
    return parts.isNotEmpty ? parts.join(' ') : groupName;
  }
}

/// 单个种子项
class NtTorrentItem {
  const NtTorrentItem({
    required this.key,
    required this.title,
    this.site,
    this.siteName,
    this.enclosure,
    this.size,
    this.seeders,
    this.peers,
    this.pageUrl,
    this.videoEncode,
    this.audioEncode,
    this.uploadFactor,
    this.downloadFactor,
    this.freeDate,
    this.labels,
  });

  factory NtTorrentItem.fromJson(Map<String, dynamic> json, String key) {
    // 解析 unique_info
    final uniqueInfo = json['unique_info'] as Map<String, dynamic>?;

    return NtTorrentItem(
      key: key,
      title: json['torrent_name'] as String? ?? json['title'] as String? ?? '',
      site: json['indexer'] as String?,
      siteName: json['site'] as String?,
      enclosure: json['enclosure'] as String?,
      size: _parseInt(json['size'] ?? uniqueInfo?['size']),
      seeders: _parseInt(json['seeders']),
      peers: _parseInt(json['peers']),
      pageUrl: json['page_url'] as String?,
      videoEncode: uniqueInfo?['video_encode'] as String?,
      audioEncode: uniqueInfo?['audio_encode'] as String?,
      uploadFactor: _parseDouble(json['uploadvolumefactor']),
      downloadFactor: _parseDouble(json['downloadvolumefactor']),
      freeDate: json['freedate'] as String?,
      labels: (json['labels'] as List?)?.map((e) => e.toString()).toList(),
    );
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) {
      // 处理带单位的大小字符串 "3962g"
      final match = RegExp(r'^(\d+(?:\.\d+)?)([kmgt])?', caseSensitive: false).firstMatch(value);
      if (match != null) {
        var num = double.tryParse(match.group(1)!) ?? 0;
        final unit = match.group(2)?.toLowerCase();
        switch (unit) {
          case 'k': num *= 1024;
          case 'm': num *= 1024 * 1024;
          case 'g': num *= 1024 * 1024 * 1024;
          case 't': num *= 1024 * 1024 * 1024 * 1024;
        }
        return num.toInt();
      }
      return int.tryParse(value);
    }
    return null;
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  final String key;
  final String title;
  final String? site;
  final String? siteName;
  final String? enclosure;
  final int? size;
  final int? seeders;
  final int? peers;
  final String? pageUrl;
  final String? videoEncode;
  final String? audioEncode;
  final double? uploadFactor;
  final double? downloadFactor;
  final String? freeDate;
  final List<String>? labels;

  /// 是否免费
  bool get isFree => downloadFactor == 0;

  /// 是否2x上传
  bool get is2xUpload => uploadFactor == 2;

  /// 显示站点名
  String get displaySite => siteName ?? site ?? '未知';

  /// 格式化大小
  String get formattedSize {
    if (size == null) return '未知';
    final s = size!;
    if (s < 1024) return '$s B';
    if (s < 1024 * 1024) return '${(s / 1024).toStringAsFixed(1)} KB';
    if (s < 1024 * 1024 * 1024) return '${(s / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(s / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
