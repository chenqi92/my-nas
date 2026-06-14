import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/hive_utils.dart';

/// 视频后端手动选择偏好。
///
/// - [auto]：维持现有按能力（HDR / 杜比视界）自动判定。
/// - [mediaKit]：强制使用 media_kit 后端。
/// - [native]：强制使用原生播放器（iOS/macOS AVPlayer）。
enum VideoBackendPreference { auto, mediaKit, native }

/// 「视频后端」手动选择偏好。持久化于 settings box，默认 [VideoBackendPreference.auto]。
///
/// 非自动时由播放逻辑强制该后端；自动时维持现有按能力判定（见
/// `video_player_provider.dart`）。
final videoBackendProvider =
    StateNotifierProvider<VideoBackendNotifier, VideoBackendPreference>(
  (ref) => VideoBackendNotifier(),
);

class VideoBackendNotifier extends StateNotifier<VideoBackendPreference> {
  VideoBackendNotifier() : super(VideoBackendPreference.auto) {
    _load();
  }

  static const _key = 'video_backend_pref';

  Future<void> _load() async {
    try {
      final box = await HiveUtils.getSettingsBox();
      final raw = box.get(_key) as String?;
      if (raw != null) {
        state = VideoBackendPreference.values.firstWhere(
          (e) => e.name == raw,
          orElse: () => VideoBackendPreference.auto,
        );
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载视频后端偏好失败，使用默认值');
    }
  }

  Future<void> setPreference(VideoBackendPreference preference) async {
    state = preference;
    try {
      final box = await HiveUtils.getSettingsBox();
      await box.put(_key, preference.name);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '保存视频后端偏好失败');
    }
  }
}
