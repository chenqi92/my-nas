import 'package:media_kit/media_kit.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/shared/providers/language_preference_provider.dart';

/// 音轨自动选择服务
///
/// 根据用户语言偏好自动选择最佳音轨
class AudioTrackService {
  factory AudioTrackService() => _instance ??= AudioTrackService._();
  AudioTrackService._();

  static AudioTrackService? _instance;

  /// 用户语言偏好设置
  LanguagePreference? _languagePreference;

  /// 设置语言偏好
  void setLanguagePreference(LanguagePreference preference) {
    _languagePreference = preference;
    logger.d('AudioTrackService: 语言偏好已更新');
  }

  /// 获取音频语言优先级列表
  List<LanguageOption> get _audioLanguages =>
      _languagePreference?.audioLanguages ?? [LanguageOption.auto];

  /// 从音轨列表中选择最佳音轨
  ///
  /// 根据用户的 audioLanguages 偏好列表选择最匹配的音轨
  /// 如果没有匹配的音轨，返回 null（使用默认音轨）
  AudioTrack? selectBestAudioTrack(List<AudioTrack> tracks) {
    if (tracks.isEmpty) return null;

    // 过滤掉 "no" 类型的音轨
    final validTracks = tracks.where((t) => t.id != 'no').toList();
    if (validTracks.isEmpty) return null;

    final preferredLanguages = _audioLanguages;

    // 如果是自动模式，使用默认优先级
    if (preferredLanguages.length == 1 && preferredLanguages.first == LanguageOption.auto) {
      return _selectWithDefaultPriority(validTracks);
    }

    // 按用户偏好顺序查找匹配的音轨
    for (final option in preferredLanguages) {
      if (option == LanguageOption.auto || option == LanguageOption.original) {
        continue;
      }

      for (final track in validTracks) {
        if (_matchesLanguageOption(track, option)) {
          logger.i('AudioTrackService: 选择音轨 ${track.title ?? track.id} (${track.language})');
          return track;
        }
      }
    }

    // 没有匹配的，返回第一个有效音轨
    logger.d('AudioTrackService: 无匹配偏好，使用默认音轨');
    return validTracks.first;
  }

  /// 使用默认优先级选择音轨（中文 > 英文 > 日文 > 其他）
  AudioTrack? _selectWithDefaultPriority(List<AudioTrack> tracks) {
    // 优先级顺序：中文 > 英文 > 日文 > 其他
    final priorities = [
      LanguageOption.zhCN,
      LanguageOption.en,
      LanguageOption.ja,
    ];

    for (final option in priorities) {
      for (final track in tracks) {
        if (_matchesLanguageOption(track, option)) {
          logger.i('AudioTrackService: 默认选择音轨 ${track.title ?? track.id} (${track.language})');
          return track;
        }
      }
    }

    // 没有匹配的，返回第一个音轨
    return tracks.first;
  }

  /// 检查音轨是否匹配语言选项
  bool _matchesLanguageOption(AudioTrack track, LanguageOption option) {
    final lang = (track.language ?? '').toLowerCase();
    final title = (track.title ?? '').toLowerCase();

    // 同时检查 language 和 title 字段
    final combined = '$lang $title';

    switch (option) {
      case LanguageOption.auto:
        return false;
      case LanguageOption.original:
        return false;
      case LanguageOption.zhCN:
        return combined.contains('chi') ||
            combined.contains('zh') ||
            combined.contains('chs') ||
            combined.contains('简') ||
            combined.contains('中文') ||
            combined.contains('chinese') ||
            combined.contains('mandarin');
      case LanguageOption.zhTW:
        return combined.contains('cht') ||
            combined.contains('繁') ||
            combined.contains('粤') ||
            combined.contains('cantonese');
      case LanguageOption.en:
        return combined.contains('eng') ||
            combined.contains('en') ||
            combined.contains('english');
      case LanguageOption.ja:
        return combined.contains('jpn') ||
            combined.contains('jap') ||
            combined.contains('jp') ||
            combined.contains('日') ||
            combined.contains('japanese');
      case LanguageOption.ko:
        return combined.contains('kor') ||
            combined.contains('ko') ||
            combined.contains('韩') ||
            combined.contains('korean');
      case LanguageOption.fr:
        return combined.contains('fre') ||
            combined.contains('fra') ||
            combined.contains('fr') ||
            combined.contains('french') ||
            combined.contains('français');
      case LanguageOption.de:
        return combined.contains('ger') ||
            combined.contains('deu') ||
            combined.contains('de') ||
            combined.contains('german') ||
            combined.contains('deutsch');
      case LanguageOption.es:
        return combined.contains('spa') ||
            combined.contains('es') ||
            combined.contains('spanish') ||
            combined.contains('español');
      case LanguageOption.pt:
        return combined.contains('por') ||
            combined.contains('pt') ||
            combined.contains('portuguese') ||
            combined.contains('português');
      case LanguageOption.ru:
        return combined.contains('rus') ||
            combined.contains('ru') ||
            combined.contains('russian') ||
            combined.contains('русский');
      case LanguageOption.it:
        return combined.contains('ita') ||
            combined.contains('it') ||
            combined.contains('italian') ||
            combined.contains('italiano');
      case LanguageOption.th:
        return combined.contains('tha') ||
            combined.contains('th') ||
            combined.contains('thai') ||
            combined.contains('ไทย');
      case LanguageOption.vi:
        return combined.contains('vie') ||
            combined.contains('vi') ||
            combined.contains('vietnamese') ||
            combined.contains('tiếng việt');
    }
  }

  /// 获取音轨语言显示名称
  String getTrackDisplayName(AudioTrack track) {
    // 优先使用 title
    if (track.title != null && track.title!.isNotEmpty) {
      return track.title!;
    }

    // 其次使用 language
    if (track.language != null && track.language!.isNotEmpty) {
      return _getLanguageDisplayName(track.language!);
    }

    // 最后使用 id
    return '音轨 ${track.id}';
  }

  /// 将语言代码转换为显示名称
  String _getLanguageDisplayName(String langCode) {
    final code = langCode.toLowerCase();
    return switch (code) {
      'chi' || 'zh' || 'zho' || 'chs' || 'cht' => appL10n.langZh,
      'eng' || 'en' => appL10n.langEn,
      'jpn' || 'ja' || 'jap' => appL10n.langJa,
      'kor' || 'ko' => appL10n.langKo,
      'fre' || 'fra' || 'fr' => appL10n.langFr,
      'ger' || 'deu' || 'de' => appL10n.langDe,
      'spa' || 'es' => appL10n.langEs,
      'por' || 'pt' => appL10n.langPt,
      'rus' || 'ru' => appL10n.langRu,
      'ita' || 'it' => appL10n.langIt,
      'tha' || 'th' => appL10n.langTh,
      'vie' || 'vi' => appL10n.langVi,
      _ => langCode,
    };
  }
}
