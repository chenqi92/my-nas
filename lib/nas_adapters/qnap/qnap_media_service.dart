import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/qnap/api/qnap_api.dart';

/// QNAP 媒体服务实现
///
/// QNAP 官方仅对 File Station / Authentication 提供有文档支撑的 HTTP API；
/// Music Station / Photo Station / Video Station 等独立套件的 API 既未公开文档，
/// 且 Photo Station / Qphoto / Qvideo 已于 2023 起停止维护（推荐迁移至 QuMagie）。
/// 因此本服务**不依赖**这些套件，而是构建在已经可用的 File Station API 之上：
///
/// - 媒体库：以共享文件夹为入口，借助 `get_list` 的 `type` 过滤（1=音乐/2=视频/
///   3=照片）判断该共享下是否含有对应媒体，含有则作为一个媒体库列出。
/// - 流地址：使用 File Station 文档中的 `get_viewer` 构造播放/转码 URL。
///
/// 所有方法在出错时优雅降级（返回空列表 / null），不影响其它已有功能。
class QnapMediaService implements MediaService {
  QnapMediaService(this._api);

  final QnapApi _api;

  @override
  Future<List<MediaLibrary>> getVideoLibraries() =>
      _collectLibraries(QnapMediaType.video, MediaLibraryType.video);

  @override
  Future<List<MediaLibrary>> getMusicLibraries() =>
      _collectLibraries(QnapMediaType.music, MediaLibraryType.music);

  /// 枚举包含指定媒体类型的共享文件夹，作为媒体库入口。
  ///
  /// 对每个共享文件夹仅探测前若干条（limit=1）是否存在该类型媒体，存在即收录。
  /// 任一探测失败都安静忽略，不中断整体结果；整体失败返回空列表。
  Future<List<MediaLibrary>> _collectLibraries(
    QnapMediaType mediaType,
    MediaLibraryType libraryType,
  ) async {
    try {
      final shares = await _api.listShareFolders();
      if (shares.isEmpty) return const [];

      final libraries = <MediaLibrary>[];
      for (final share in shares) {
        try {
          // 探测取多条而非 1 条：避免 type 过滤 + 目录后置过滤后恰好把唯一一条
          // 滤掉，导致含媒体的共享被误判为空。
          final files = await _api.listMediaFiles(
            folderPath: share.path,
            mediaType: mediaType,
            limit: 20,
          );
          if (files.isNotEmpty) {
            libraries.add(
              MediaLibrary(
                // 以共享路径作为库 id，后续可据此列出 / 播放其中的媒体
                id: share.path,
                name: share.name,
                type: libraryType,
              ),
            );
          }
        } on Exception catch (e, st) {
          AppError.ignore(
            e,
            st,
            'QnapMediaService: 探测共享 ${share.path} 的媒体失败，跳过',
          );
        }
      }

      logger.i(
        'QnapMediaService: ${libraryType.name} 媒体库 => ${libraries.length} 个',
      );
      return libraries;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'QnapMediaService._collectLibraries 失败');
      return const [];
    }
  }

  @override
  Future<String?> getTranscodedStreamUrl(
    String fileId,
    TranscodeOptions options,
  ) async {
    // QNAP 以路径标识文件，这里的 fileId 即媒体文件的完整路径。
    if (fileId.isEmpty) return null;

    try {
      // 将通用转码选项映射到 QNAP get_viewer 支持的 format。
      // 无法识别或未指定时传 null（返回原始流），避免臆造不支持的取值。
      final format = _resolveFormat(options);
      final url = _api.getMediaStreamUrl(fileId, format: format);
      logger.d('QnapMediaService: 流地址 => $fileId (format=$format)');
      return url;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'QnapMediaService.getTranscodedStreamUrl 失败');
      return null;
    }
  }

  /// 将 [TranscodeOptions] 映射为 QNAP `get_viewer` 支持的 format。
  ///
  /// File Station 文档中 get_viewer 的转码格式仅 mp4_360 / mp4_720 / flv_720。
  /// 优先采用显式 format，其次按 quality 推断分辨率，否则返回 null（原始流）。
  String? _resolveFormat(TranscodeOptions options) {
    final explicit = options.format;
    if (explicit != null && explicit.isNotEmpty) {
      const supported = {'mp4_360', 'mp4_720', 'flv_720'};
      if (supported.contains(explicit)) return explicit;
      // 常见简写映射
      switch (explicit.toLowerCase()) {
        case '360':
        case '360p':
          return 'mp4_360';
        case '720':
        case '720p':
          return 'mp4_720';
      }
    }

    final quality = options.quality?.toLowerCase();
    switch (quality) {
      case 'low':
      case '360':
      case '360p':
        return 'mp4_360';
      case 'medium':
      case 'high':
      case '720':
      case '720p':
        return 'mp4_720';
      default:
        return null;
    }
  }
}
