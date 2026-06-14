import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/hive_utils.dart';

/// 刮削默认项（用户级偏好），持久化于 settings box。
///
/// 在「设置 › 刮削源」里配置，刮削页（手动 / 整季）初始化刮削选项时读取这些默认值，
/// 替代页面内硬编码的初始 `true`。三项默认值均为 true，保持改动前行为不变：
/// - [generateNfo]：刮削时在媒体目录写入 .nfo
/// - [downloadPoster]：刮削时下载海报到媒体目录
/// - [downloadFanart]：刮削时下载背景图到媒体目录
class ScrapeDefaults {
  const ScrapeDefaults({
    this.generateNfo = true,
    this.downloadPoster = true,
    this.downloadFanart = true,
  });

  final bool generateNfo;
  final bool downloadPoster;
  final bool downloadFanart;

  ScrapeDefaults copyWith({
    bool? generateNfo,
    bool? downloadPoster,
    bool? downloadFanart,
  }) =>
      ScrapeDefaults(
        generateNfo: generateNfo ?? this.generateNfo,
        downloadPoster: downloadPoster ?? this.downloadPoster,
        downloadFanart: downloadFanart ?? this.downloadFanart,
      );
}

final scrapeDefaultsProvider =
    StateNotifierProvider<ScrapeDefaultsNotifier, ScrapeDefaults>(
  (ref) => ScrapeDefaultsNotifier(),
);

class ScrapeDefaultsNotifier extends StateNotifier<ScrapeDefaults> {
  ScrapeDefaultsNotifier() : super(const ScrapeDefaults()) {
    _load();
  }

  static const _keyGenerateNfo = 'scrape_default_generate_nfo';
  static const _keyDownloadPoster = 'scrape_default_download_poster';
  static const _keyDownloadFanart = 'scrape_default_download_fanart';

  Future<void> _load() async {
    try {
      final box = await HiveUtils.getSettingsBox();
      state = ScrapeDefaults(
        generateNfo: box.get(_keyGenerateNfo) as bool? ?? true,
        downloadPoster: box.get(_keyDownloadPoster) as bool? ?? true,
        downloadFanart: box.get(_keyDownloadFanart) as bool? ?? true,
      );
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载刮削默认项设置失败，使用默认值');
    }
  }

  Future<void> setGenerateNfo({required bool enabled}) async {
    state = state.copyWith(generateNfo: enabled);
    await _put(_keyGenerateNfo, enabled);
  }

  Future<void> setDownloadPoster({required bool enabled}) async {
    state = state.copyWith(downloadPoster: enabled);
    await _put(_keyDownloadPoster, enabled);
  }

  Future<void> setDownloadFanart({required bool enabled}) async {
    state = state.copyWith(downloadFanart: enabled);
    await _put(_keyDownloadFanart, enabled);
  }

  Future<void> _put(String key, bool value) async {
    try {
      final box = await HiveUtils.getSettingsBox();
      await box.put(key, value);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '保存刮削默认项设置失败');
    }
  }
}
