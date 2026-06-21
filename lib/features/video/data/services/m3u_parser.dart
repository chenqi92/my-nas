import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/domain/entities/live_stream_models.dart';
import 'package:uuid/uuid.dart';

/// M3U 播放列表解析器
///
/// 支持 M3U 和 M3U8 格式的 IPTV 播放列表解析
class M3UParser {
  const M3UParser._();

  /// 解析 M3U 内容为频道列表
  ///
  /// [content] M3U 文件内容
  /// 返回解析后的 [LiveChannel] 列表
  static List<LiveChannel> parse(String content) {
    final channels = <LiveChannel>[];
    final lines = content.split('\n');

    String? currentName;
    String? currentLogo;
    String? currentCategory;
    String? currentTvgId;
    String? currentTvgName;
    // 播放列表级 EPG（XMLTV）地址，取自 #EXTM3U 头的 url-tvg / x-tvg-url。
    String? playlistEpgUrl;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      // 跳过空行
      if (line.isEmpty) continue;

      // #EXTM3U 头部：捕获 EPG（XMLTV）地址供电子节目单使用。
      if (line.startsWith('#EXTM3U')) {
        playlistEpgUrl = _extractAttribute(line, 'url-tvg') ??
            _extractAttribute(line, 'x-tvg-url');
        continue;
      }

      // 解析 #EXTINF 行
      if (line.startsWith('#EXTINF:')) {
        currentName = _extractChannelName(line);
        currentLogo = _extractAttribute(line, 'tvg-logo');
        currentCategory = _extractAttribute(line, 'group-title');
        currentTvgId = _extractAttribute(line, 'tvg-id');
        currentTvgName = _extractAttribute(line, 'tvg-name');
        continue;
      }

      // 跳过其他 # 开头的行
      if (line.startsWith('#')) continue;

      // 这是 URL 行
      if (currentName != null && _isValidUrl(line)) {
        final channel = LiveChannel(
          id: _generateId(line),
          name: currentName,
          streamUrl: line,
          logoUrl: currentLogo,
          category: currentCategory,
          tvgId: currentTvgId,
          tvgName: currentTvgName,
          epgUrl: playlistEpgUrl,
        );
        channels.add(channel);
      }

      // 重置状态
      currentName = null;
      currentLogo = null;
      currentCategory = null;
      currentTvgId = null;
      currentTvgName = null;
    }

    logger.d('M3UParser: 解析完成，共 ${channels.length} 个频道');
    return channels;
  }

  /// 提取频道名称
  ///
  /// 格式: #EXTINF:-1 tvg-id="xxx" tvg-logo="xxx" group-title="xxx",频道名
  static String _extractChannelName(String line) {
    final commaIndex = line.lastIndexOf(',');
    if (commaIndex != -1 && commaIndex < line.length - 1) {
      return line.substring(commaIndex + 1).trim();
    }
    return appL10n.m3uParserUnknownChannel;
  }

  /// 提取属性值
  ///
  /// 支持格式: attr="value" 或 attr='value'
  static String? _extractAttribute(String line, String attr) {
    // 尝试双引号格式
    var regex = RegExp('$attr="([^"]*)"', caseSensitive: false);
    var match = regex.firstMatch(line);
    if (match != null) {
      final value = match.group(1);
      return value?.isNotEmpty ?? false ? value : null;
    }

    // 尝试单引号格式
    regex = RegExp("$attr='([^']*)'", caseSensitive: false);
    match = regex.firstMatch(line);
    if (match != null) {
      final value = match.group(1);
      return value?.isNotEmpty ?? false ? value : null;
    }

    return null;
  }

  /// 生成频道 ID
  ///
  /// 基于 URL 生成唯一标识
  static String _generateId(String url) {
    // 使用 URL 的哈希值 + UUID 确保唯一性
    final hash = url.hashCode.toRadixString(16);
    final uuid = const Uuid().v4().substring(0, 8);
    return 'ch_${hash}_$uuid';
  }

  /// 检查是否为有效 URL
  static bool _isValidUrl(String line) => line.startsWith('http://') ||
        line.startsWith('https://') ||
        line.startsWith('rtmp://') ||
        line.startsWith('rtsp://') ||
        line.startsWith('mms://') ||
        line.startsWith('udp://') ||
        line.startsWith('rtp://');

  /// 获取所有分类
  static Set<String> getCategories(List<LiveChannel> channels) => channels
        .map((c) => c.category)
        .where((c) => c != null && c.isNotEmpty)
        .cast<String>()
        .toSet();

  /// 按分类分组频道
  static Map<String, List<LiveChannel>> groupByCategory(
    List<LiveChannel> channels,
  ) {
    final result = <String, List<LiveChannel>>{};
    for (final channel in channels) {
      final category = channel.category ?? appL10n.m3uParserUncategorized;
      result.putIfAbsent(category, () => []).add(channel);
    }
    return result;
  }
}
