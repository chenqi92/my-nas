import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' show SubtitleTrack;
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/translation/translation_provider.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/subtitle_translation/subtitle_format.dart';
import 'package:my_nas/features/video/data/services/subtitle_translation/subtitle_translation_service.dart';
import 'package:my_nas/features/video/presentation/providers/subtitle_translation_settings_provider.dart';
import 'package:my_nas/features/video/presentation/providers/video_player_provider.dart';

/// 翻译字幕协调器：UI 调一次 [translateCurrent]，剩下的丢给 service 后台处理，
/// 并把进度 / 注入回播放器。
class SubtitleTranslationController {
  SubtitleTranslationController(this._ref);

  final Ref _ref;
  SubtitleTranslationListener? _listener;

  /// 把当前选中的外部字幕翻译为 [targetLang]。
  /// 返回 true 表示已成功启动会话（可能命中缓存，会话立即完成）。
  Future<bool> translateCurrent({
    required TranslationLang targetLang,
  }) async {
    final current = _ref.read(currentSubtitleProvider);
    if (current == null) {
      logger.w('SubtitleTranslation: 当前没有选中外部字幕，无法翻译');
      return false;
    }
    final format = SubtitleFormat.fromExtension(current.format);
    if (format == null) {
      logger.w('SubtitleTranslation: 不支持的字幕格式 ${current.format}');
      return false;
    }

    final settings = _ref.read(subtitleTranslationSettingsProvider);
    final service = SubtitleTranslationService.instance;

    final content = await service.fetchContent(current.url);
    if (content == null || content.trim().isEmpty) {
      logger.w('SubtitleTranslation: 拉取字幕内容失败 ${current.url}');
      return false;
    }

    _ref.read(subtitleTranslationProgressProvider.notifier).state = 0;

    final playerState = _ref.read(videoPlayerControllerProvider);
    final session = await service.start(
      subtitleContent: content,
      format: format,
      targetLang: targetLang.bcp47,
      bilingual: settings.bilingual,
      useCache: settings.useCache,
      providerId: settings.providerId,
      initialAnchor: playerState.actualPosition,
    );
    if (session == null) {
      _ref.read(subtitleTranslationProgressProvider.notifier).state = null;
      return false;
    }

    final id = 'translated:${targetLang.bcp47}:${session.sessionId}';
    _ref.read(currentTranslatedSubtitleIdProvider.notifier).state = id;
    _ref.read(currentEmbeddedSubtitleIdProvider.notifier).state = null;

    // 立刻注入当前内容（未翻译段保留原文，让用户立刻看到状态）
    await _injectSnapshot(session, targetLang);

    _removeListener();
    void onUpdate(SubtitleTranslationSession s, SubtitleTranslationProgress p) {
      if (s.sessionId != session.sessionId) return;
      _ref.read(subtitleTranslationProgressProvider.notifier).state = p.ratio;
      AppError.fireAndForget(
        _injectSnapshot(s, targetLang),
        action: 'subtitleTranslation.injectSnapshot',
      );
      if (p.completed) {
        logger.i('SubtitleTranslation: 全部完成，done=${p.done}/${p.total}, failed=${p.failed}');
      }
    }
    service.addListener(onUpdate);
    _listener = onUpdate;
    return true;
  }

  Future<void> _injectSnapshot(
    SubtitleTranslationSession session,
    TranslationLang targetLang,
  ) async {
    final notifier = _ref.read(videoPlayerControllerProvider.notifier);
    await notifier.setInlineSubtitleData(
      session.currentContent(),
      title: appL10n.subtitleTranslatedLabel(targetLang.displayName),
    );
  }

  void cancel() {
    SubtitleTranslationService.instance.cancelActive();
    _removeListener();
    _ref.read(subtitleTranslationProgressProvider.notifier).state = null;
    _ref.read(currentTranslatedSubtitleIdProvider.notifier).state = null;
  }

  void _removeListener() {
    final l = _listener;
    if (l != null) {
      SubtitleTranslationService.instance.removeListener(l);
      _listener = null;
    }
  }

  void dispose() {
    _removeListener();
  }
}

final subtitleTranslationControllerProvider =
    Provider.autoDispose<SubtitleTranslationController>((ref) {
  final controller = SubtitleTranslationController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

/// 标记：当前 [SubtitleTrack] 是否是"翻译字幕"。仅供 UI 高亮判断。
bool isTranslatedSubtitleTrack(SubtitleTrack? track) {
  if (track == null) return false;
  final title = track.title ?? '';
  return title.contains('(翻译)');
}
