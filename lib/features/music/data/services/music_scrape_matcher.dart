import 'package:my_nas/features/music/domain/entities/music_scraper_result.dart';

/// 自动音乐刮削的候选匹配器。
///
/// 搜索接口返回的第一项不一定是同一首歌（同名歌曲尤其常见）。自动刮削不能
/// 像手动选择一样让用户复核，因此宁可漏掉，也不能把明显不相干的元数据写回。
class MusicScrapeMatcher {
  const MusicScrapeMatcher._();

  /// 每个源拉取少量候选后在本地按标题、歌手、专辑和时长综合排序。
  static const int autoScrapeLimit = 5;

  static MusicScraperItem? bestMatch(
    List<MusicScraperItem> items, {
    required String title,
    String? artist,
    String? album,
    int? durationMs,
  }) {
    final normalizedTitle = normalize(title);
    final normalizedArtist = normalize(artist);
    final normalizedAlbum = normalize(album);
    if (normalizedTitle.isEmpty) return null;

    final candidates = items.where((item) {
      final itemTitle = normalize(item.title);
      if (!_compatible(itemTitle, normalizedTitle)) return false;

      // 已从标签或「歌手 - 标题」文件名得到歌手时，拒绝另一个明确歌手的
      // 同名曲；候选未提供歌手则保留，让标题/时长继续参与判断。
      final itemArtist = normalize(item.artist);
      if (normalizedArtist.isNotEmpty &&
          itemArtist.isNotEmpty &&
          !_compatible(itemArtist, normalizedArtist)) {
        return false;
      }
      return true;
    }).toList();

    if (candidates.isEmpty) return null;
    candidates.sort(
      (a, b) =>
          _score(
            b,
            title: normalizedTitle,
            artist: normalizedArtist,
            album: normalizedAlbum,
            durationMs: durationMs,
          ).compareTo(
            _score(
              a,
              title: normalizedTitle,
              artist: normalizedArtist,
              album: normalizedAlbum,
              durationMs: durationMs,
            ),
          ),
    );
    return candidates.first;
  }

  static int _score(
    MusicScraperItem item, {
    required String title,
    required String artist,
    required String album,
    required int? durationMs,
  }) {
    var score = 0;
    final itemTitle = normalize(item.title);
    final itemArtist = normalize(item.artist);
    final itemAlbum = normalize(item.album);

    if (itemTitle == title) {
      score += 40;
    } else if (_compatible(itemTitle, title)) {
      score += 20;
    }

    if (artist.isNotEmpty && itemArtist.isNotEmpty) {
      score += itemArtist == artist ? 30 : 15;
    }
    if (album.isNotEmpty && itemAlbum.isNotEmpty) {
      if (itemAlbum == album) {
        score += 15;
      } else if (_compatible(itemAlbum, album)) {
        score += 8;
      }
    }

    final candidateDuration = item.durationMs;
    if (durationMs != null &&
        durationMs > 0 &&
        candidateDuration != null &&
        candidateDuration > 0) {
      final difference = (candidateDuration - durationMs).abs();
      if (difference < 2000) {
        score += 50;
      } else if (difference < 5000) {
        score += 30;
      } else if (difference < 10000) {
        score += 10;
      } else {
        score -= 20;
      }
    }

    // 搜索源自身的相关度只用于同等文本候选间的轻量排序，不能盖过身份字段。
    score += ((item.score ?? 0).clamp(0, 1) * 5).round();
    return score;
  }

  static bool _compatible(String left, String right) =>
      left == right || left.contains(right) || right.contains(left);

  /// 去掉版本括号、空白和常见分隔符，供不同刮削源的文本比较。
  static String normalize(String? value) {
    if (value == null) return '';
    return value
        .replaceAll(RegExp(r'\([^)]*\)|（[^）]*）|\[[^\]]*\]|【[^】]*】'), '')
        .toLowerCase()
        .replaceAll(RegExp(r'[\s·•・_\-–—]+'), '')
        .trim();
  }
}
