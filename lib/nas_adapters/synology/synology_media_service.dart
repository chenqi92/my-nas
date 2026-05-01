import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/synology/api/synology_api.dart';

/// Synology 媒体服务实现
///
/// 通过 Video Station / Audio Station 的 DSM API 暴露媒体库列表，
/// 通过 [SYNO.VideoStation.Streaming] 构造转码流 URL。
///
/// 注意：
/// - Video Station 与 Audio Station 在 DSM 7 上需要分别安装套件，未安装时
///   对应方法返回空列表，转码 URL 返回 null。
/// - DSM 7 后，Synology Photos 取代了 Photo Station，但 [getVideoLibraries]
///   不涉及照片库，因此不在此服务范围内。
class SynologyMediaService implements MediaService {
  SynologyMediaService(this._api);

  final SynologyApi _api;

  /// 缓存 SYNO.API.Info 的查询结果，避免重复探测
  Map<String, dynamic>? _availableApis;

  /// 探测 DSM 上可用的扩展 API 集合
  Future<Map<String, dynamic>> _ensureApiInfo() async {
    final cached = _availableApis;
    if (cached != null) return cached;

    try {
      final response = await _api.callExtensionApi(
        'SYNO.API.Info',
        'query',
        version: 1,
        params: {'query': 'all'},
      );
      final data = response['data'];
      _availableApis = data is Map<String, dynamic> ? data : <String, dynamic>{};
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'SynologyMediaService: 查询 API.Info 失败');
      _availableApis = <String, dynamic>{};
    }
    return _availableApis!;
  }

  bool _hasApi(Map<String, dynamic> apis, String apiName) =>
      apis.containsKey(apiName);

  @override
  Future<List<MediaLibrary>> getVideoLibraries() async {
    final apis = await _ensureApiInfo();
    if (!_hasApi(apis, 'SYNO.VideoStation.Library')) {
      logger.i('SynologyMediaService: Video Station 未安装，跳过');
      return const [];
    }

    try {
      final response = await _api.callExtensionApi(
        'SYNO.VideoStation.Library',
        'list',
        version: 1,
      );
      final data = response['data'];
      if (data is! Map<String, dynamic>) return const [];

      final libs = data['libraries'];
      if (libs is! List) return const [];

      return libs
          .whereType<Map<String, dynamic>>()
          .map((raw) => MediaLibrary(
                id: raw['id']?.toString() ?? '',
                name: (raw['title'] as String?) ??
                    (raw['name'] as String?) ??
                    'Untitled',
                type: MediaLibraryType.video,
              ))
          .where((lib) => lib.id.isNotEmpty)
          .toList();
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'SynologyMediaService.getVideoLibraries 失败');
      return const [];
    }
  }

  @override
  Future<List<MediaLibrary>> getMusicLibraries() async {
    final apis = await _ensureApiInfo();
    if (!_hasApi(apis, 'SYNO.AudioStation.Folder')) {
      logger.i('SynologyMediaService: Audio Station 未安装，跳过');
      return const [];
    }

    try {
      // Audio Station 没有"库"的概念，列出根级别的"库类型"作为入口：
      // shared / personal 两个根目录足够覆盖常见使用场景。
      // SYNO.AudioStation.Folder 用 library 参数区分共享 / 个人文件夹。
      final response = await _api.callExtensionApi(
        'SYNO.AudioStation.Folder',
        'list',
        version: 2,
        params: {
          'library': 'shared',
          'limit': 1, // 只是探测，不需要真实数据
        },
      );

      // 即便返回了 0 条文件夹，只要 success 为 true 就说明 Audio Station 可用，
      // 给一个固定的"音乐资源库"入口；如果服务器有"个人文件夹"再追加一项。
      final libraries = <MediaLibrary>[];
      if (response['success'] == true) {
        libraries.add(const MediaLibrary(
          id: 'audio_station_shared',
          name: '共享音乐文件夹',
          type: MediaLibraryType.music,
        ));
      }

      // 探测个人文件夹是否可用（部分用户可能没有授权）
      try {
        final personal = await _api.callExtensionApi(
          'SYNO.AudioStation.Folder',
          'list',
          version: 2,
          params: {
            'library': 'personal',
            'limit': 1,
          },
        );
        if (personal['success'] == true) {
          libraries.add(const MediaLibrary(
            id: 'audio_station_personal',
            name: '个人音乐文件夹',
            type: MediaLibraryType.music,
          ));
        }
      } on Exception {
        // 个人文件夹可能没权限，安静忽略
      }

      return libraries;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'SynologyMediaService.getMusicLibraries 失败');
      return const [];
    }
  }

  @override
  Future<String?> getTranscodedStreamUrl(
    String fileId,
    TranscodeOptions options,
  ) async {
    final apis = await _ensureApiInfo();
    if (!_hasApi(apis, 'SYNO.VideoStation.Streaming')) {
      logger.i('SynologyMediaService: Video Station Streaming 不可用');
      return null;
    }

    try {
      // 1. 用 fileId 打开一个 streaming session
      final openResp = await _api.callExtensionApi(
        'SYNO.VideoStation.Streaming',
        'open',
        version: 1,
        params: {
          'id': fileId,
          if (options.format != null) 'format': options.format,
          if (options.audioTrack != null) 'audio_track': options.audioTrack,
          if (options.subtitleTrack != null)
            'subtitle_track': options.subtitleTrack,
        },
      );

      final data = openResp['data'];
      if (data is! Map<String, dynamic>) return null;
      final sessionId = data['stream_id'] as String?;
      if (sessionId == null || sessionId.isEmpty) return null;

      // 2. 拼接直接命中 vtestreaming.cgi 的 URL（含 _sid 和 stream_id）
      final base = _api.baseUrl.endsWith('/')
          ? _api.baseUrl.substring(0, _api.baseUrl.length - 1)
          : _api.baseUrl;
      final query = <String, String>{
        'api': 'SYNO.VideoStation.Streaming',
        'method': 'stream',
        'version': '1',
        'id': sessionId,
        'format': options.format ?? 'raw',
        if (_api.sessionId != null) '_sid': _api.sessionId!,
      };
      final qs = query.entries
          .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      return '$base/webapi/VideoStation/vtestreaming.cgi?$qs';
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'SynologyMediaService.getTranscodedStreamUrl 失败');
      return null;
    }
  }
}
