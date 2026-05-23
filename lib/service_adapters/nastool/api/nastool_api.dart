import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/service_adapters/nastool/api/nastool_auth.dart';
import 'package:my_nas/service_adapters/nastool/models/models.dart';

/// NASTool API 客户端
///
/// 使用会话认证，支持 NASTool v3.x API
class NasToolApi {
  NasToolApi({required this.baseUrl});

  final String baseUrl;

  http.Client? _client;
  late final NasToolAuth _auth = NasToolAuth(baseUrl: baseUrl);

  http.Client get client {
    _client ??= http.Client();
    return _client!;
  }

  /// 是否已认证
  bool get isAuthenticated => _auth.isAuthenticated;

  /// 当前用户名
  String? get username => _auth.username;

  // ============================================================
  // 认证相关
  // ============================================================

  /// 登录
  Future<NasToolLoginResult> login(String username, String password) =>
      _auth.login(username, password);

  /// 登出
  Future<void> logout() => _auth.logout();

  /// 验证会话
  Future<bool> validateSession() => _auth.validateSession();

  /// 验证 API Token
  Future<bool> validateApiToken(String token) => _auth.validateApiToken(token);

  // ============================================================
  // 系统相关
  // ============================================================

  /// 获取系统版本
  Future<NtSystemVersion> getSystemVersion() async {
    final data = await _post('/system/version');
    return NtSystemVersion.fromJson(data);
  }

  /// 获取进度
  Future<NtSystemProgress?> getProgress(String type) async {
    final data = await _post('/system/progress', {'type': type});
    if (data['value'] == null) return null;
    return NtSystemProgress.fromJson(data);
  }

  /// 获取目录
  Future<List<NtPathInfo>> listPath(String dir, {String filter = 'ALL'}) async {
    final data = await _post('/system/path', {'dir': dir, 'filter': filter});
    final items = data['PathList'] as List? ?? data['result'] as List? ?? [];
    return items.map((e) => NtPathInfo.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 重启系统
  Future<void> restartSystem() async {
    await _post('/system/restart');
  }

  /// 升级系统
  Future<void> updateSystem() async {
    await _post('/system/update');
  }

  // ============================================================
  // 站点相关
  // ============================================================

  /// 获取站点列表
  Future<List<NtSite>> listSites() async {
    final data = await _post('/site/list');
    // API 返回格式: {"data": {"sites": [...]}}
    final items = data['sites'] as List? ?? data['result'] as List? ?? [];
    return items.map((e) => NtSite.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取站点详情
  Future<NtSite?> getSiteInfo(int id) async {
    final data = await _post('/site/info', {'id': id});
    if (data['result'] == null) return null;
    return NtSite.fromJson(data['result'] as Map<String, dynamic>);
  }

  /// 更新站点
  Future<void> updateSite({
    required String siteName,
    int? siteId,
    String? sitePri,
    String? siteRssUrl,
    String? siteSignUrl,
    String? siteCookie,
    String? siteNote,
    String? siteInclude,
  }) async {
    await _post('/site/update', {
      'site_name': siteName,
      'site_id': ?siteId,
      'site_pri': ?sitePri,
      'site_rssurl': ?siteRssUrl,
      'site_signurl': ?siteSignUrl,
      'site_cookie': ?siteCookie,
      'site_note': ?siteNote,
      'site_include': ?siteInclude,
    });
  }

  /// 删除站点
  Future<void> deleteSite(int id) async {
    await _post('/site/delete', {'id': id});
  }

  /// 测试站点
  Future<bool> testSite(int id) async {
    final data = await _post('/site/test', {'id': id});
    return data['code'] == 0;
  }

  /// 获取站点统计
  Future<List<NtSiteStatistics>> getSiteStatistics() async {
    final response = await _get('/site/statistics');
    if (response == null) return [];
    // API 返回格式: {"data": {"user_statistics": [...]}}
    final items = response is Map<String, dynamic>
        ? (response['user_statistics'] as List? ?? response['result'] as List? ?? <dynamic>[])
        : (response is List ? response : <dynamic>[]);
    return items.map((e) => NtSiteStatistics.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取站点索引器
  Future<List<NtSiteIndexer>> getSiteIndexers() async {
    final data = await _post('/site/indexers');
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtSiteIndexer.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ============================================================
  // 订阅相关
  // ============================================================

  /// 获取电影订阅
  Future<List<NtSubscribe>> getMovieSubscribes() async {
    final data = await _post('/subscribe/movie/list');
    return _parseSubscribeList(data, 'MOV');
  }

  /// 获取电视剧订阅
  Future<List<NtSubscribe>> getTvSubscribes() async {
    final data = await _post('/subscribe/tv/list');
    return _parseSubscribeList(data, 'TV');
  }

  /// 解析订阅列表（支持对象格式和数组格式）
  List<NtSubscribe> _parseSubscribeList(Map<String, dynamic> data, String type) {
    final result = data['result'];
    if (result == null) return [];

    // 如果是数组格式
    if (result is List) {
      return result
          .map((e) => NtSubscribe.fromJson(e as Map<String, dynamic>, type))
          .toList();
    }

    // 如果是对象格式（key 是 id）
    if (result is Map<String, dynamic>) {
      return result.values
          .map((e) => NtSubscribe.fromJson(e as Map<String, dynamic>, type))
          .toList();
    }

    return [];
  }

  /// 获取所有订阅
  Future<List<NtSubscribe>> getAllSubscribes() async {
    final movies = await getMovieSubscribes();
    final tvs = await getTvSubscribes();
    return [...movies, ...tvs];
  }

  /// 添加订阅
  Future<void> addSubscribe({
    required String name,
    required String type,
    String? year,
    String? keyword,
    int? season,
    String? mediaId,
    int? fuzzyMatch,
    String? rssSites,
    String? searchSites,
    int? overEdition,
    String? filterRestype,
    String? filterPix,
    String? filterTeam,
    int? filterRule,
    int? downloadSetting,
    String? savePath,
    int? totalEp,
    int? currentEp,
  }) async {
    await _post('/subscribe/add', {
      'name': name,
      'type': type,
      'year': ?year,
      'keyword': ?keyword,
      'season': ?season,
      'mediaid': ?mediaId,
      'fuzzy_match': ?fuzzyMatch,
      'rss_sites': ?rssSites,
      'search_sites': ?searchSites,
      'over_edition': ?overEdition,
      'filter_restype': ?filterRestype,
      'filter_pix': ?filterPix,
      'filter_team': ?filterTeam,
      'filter_rule': ?filterRule,
      'download_setting': ?downloadSetting,
      'save_path': ?savePath,
      'total_ep': ?totalEp,
      'current_ep': ?currentEp,
    });
  }

  /// 删除订阅
  Future<void> deleteSubscribe({
    String? name,
    String? type,
    String? year,
    int? season,
    int? rssId,
    String? tmdbId,
  }) async {
    await _post('/subscribe/delete', {
      'name': ?name,
      'type': ?type,
      'year': ?year,
      'season': ?season,
      'rssid': ?rssId,
      'tmdbid': ?tmdbId,
    });
  }

  /// 获取订阅详情
  Future<NtSubscribe?> getSubscribeInfo(int rssId, String type) async {
    final data = await _post('/subscribe/info', {'rssid': rssId, 'type': type});
    if (data['result'] == null) return null;
    return NtSubscribe.fromJson(data['result'] as Map<String, dynamic>, type);
  }

  /// 搜索订阅
  Future<void> searchSubscribe(int rssId, String type) async {
    await _post('/subscribe/search', {'rssid': rssId, 'type': type});
  }

  /// 获取订阅历史
  Future<List<NtSubscribeHistory>> getSubscribeHistory(String type) async {
    final data = await _post('/subscribe/history', {'type': type});
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtSubscribeHistory.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ============================================================
  // 搜索相关
  // ============================================================

  /// 搜索资源
  Future<void> searchKeyword({
    required String searchWord,
    int? unident,
    String? filters,
    String? tmdbId,
    String? mediaType,
  }) async {
    await _post('/search/keyword', {
      'search_word': searchWord,
      'unident': ?unident,
      'filters': ?filters,
      'tmdbid': ?tmdbId,
      'media_type': ?mediaType,
    });
  }

  /// 获取搜索结果
  Future<List<NtSearchResult>> getSearchResult() async {
    final data = await _post('/search/result');
    final result = data['result'];
    if (result == null) return [];
    
    // result 可能是 List 或 Map（对象格式，key 是搜索关键词）
    final List<dynamic> items;
    if (result is List) {
      items = result;
    } else if (result is Map<String, dynamic>) {
      items = result.values.toList();
    } else {
      return [];
    }
    return items.map((e) => NtSearchResult.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取媒体搜索结果（包含分组种子）
  Future<List<NtMediaSearchResult>> getMediaSearchResults() async {
    final data = await _post('/search/result');
    final result = data['result'];
    if (result == null) return [];
    
    // result 可能是 List 或 Map（对象格式，key 是搜索关键词）
    final List<dynamic> items;
    if (result is List) {
      items = result;
    } else if (result is Map<String, dynamic>) {
      items = result.values.toList();
    } else {
      return [];
    }
    return items.map((e) => NtMediaSearchResult.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ============================================================
  // 下载相关
  // ============================================================

  /// 下载资源
  Future<void> downloadItem({
    required String enclosure,
    required String title,
    String? site,
    String? description,
    String? pageUrl,
    String? size,
    String? seeders,
    double? uploadFactor,
    double? downloadFactor,
    String? dlDir,
  }) async {
    await _post('/download/item', {
      'enclosure': enclosure,
      'title': title,
      'site': ?site,
      'description': ?description,
      'page_url': ?pageUrl,
      'size': ?size,
      'seeders': ?seeders,
      'uploadvolumefactor': ?uploadFactor,
      'downloadvolumefactor': ?downloadFactor,
      'dl_dir': ?dlDir,
    });
  }

  /// 获取正在下载的任务
  Future<List<NtDownloadTask>> getDownloading() async {
    final data = await _post('/download/now');
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtDownloadTask.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取下载历史
  Future<List<NtDownloadHistory>> getDownloadHistory(int page) async {
    final data = await _post('/download/history', {'page': page});
    // API 返回格式可能是 {"data": {"Items": [...]}} 或 {"data": {"result": [...]}}
    final items = data['Items'] as List? ?? data['result'] as List? ?? [];
    return items.map((e) => NtDownloadHistory.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取下载进度
  Future<Map<String, dynamic>> getDownloadInfo(String ids) async => _post('/download/info', {'ids': ids});

  /// 开始下载
  Future<void> startDownload(String id) async {
    await _post('/download/start', {'id': id});
  }

  /// 暂停下载
  Future<void> stopDownload(String id) async {
    await _post('/download/stop', {'id': id});
  }

  /// 删除下载
  Future<void> removeDownload(String id) async {
    await _post('/download/remove', {'id': id});
  }

  /// 下载搜索结果
  Future<void> downloadSearchResult(String id, {String? dir, String? setting}) async {
    await _post('/download/search', {
      'id': id,
      'dir': ?dir,
      'setting': ?setting,
    });
  }

  /// 获取下载器列表
  Future<List<NtDownloadClient>> listDownloadClients({String? did}) async {
    final data = await _post('/download/client/list', {'did': ?did});
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtDownloadClient.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ============================================================
  // 媒体库相关
  // ============================================================

  /// 获取媒体库统计
  Future<NtLibraryStatistics> getLibraryStatistics() async {
    final data = await _post('/library/mediaserver/statistics');
    return NtLibraryStatistics.fromJson(data);
  }

  /// 获取媒体库空间
  Future<NtLibrarySpace> getLibrarySpace() async {
    final data = await _post('/library/space');
    return NtLibrarySpace.fromJson(data);
  }

  /// 获取播放历史
  Future<List<NtPlayHistory>> getPlayHistory() async {
    final data = await _post('/library/mediaserver/playhistory');
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtPlayHistory.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 开始媒体库同步
  Future<void> startLibrarySync() async {
    await _post('/library/sync/start');
  }

  /// 获取媒体库同步状态
  Future<Map<String, dynamic>> getLibrarySyncStatus() async => _post('/library/sync/status');

  // ============================================================
  // 媒体相关
  // ============================================================

  /// 搜索媒体
  Future<List<NtMediaDetail>> searchMedia(String keyword) async {
    final data = await _post('/media/search', {'keyword': keyword});
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtMediaDetail.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取媒体详情
  Future<NtMediaDetail?> getMediaDetail(String type, {String? tmdbId}) async {
    final data = await _post('/media/detail', {
      'type': type,
      'tmdbid': ?tmdbId,
    });
    if (data['data'] == null && data['title'] == null) return null;
    return NtMediaDetail.fromJson(data['data'] as Map<String, dynamic>? ?? data);
  }

  /// 获取电视剧季列表
  Future<List<NtTvSeason>> getTvSeasons(String tmdbId) async {
    final data = await _post('/media/tv/seasons', {'tmdbid': tmdbId});
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtTvSeason.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取相似媒体
  Future<List<NtMediaDetail>> getSimilarMedia(String type, String tmdbId, {int? page}) async {
    final data = await _post('/media/similar', {
      'type': type,
      'tmdbid': tmdbId,
      'page': ?page,
    });
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtMediaDetail.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取推荐媒体
  Future<List<NtMediaDetail>> getRecommendations(String type, String tmdbId, {int? page}) async {
    final data = await _post('/media/recommendations', {
      'type': type,
      'tmdbid': tmdbId,
      'page': ?page,
    });
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtMediaDetail.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ============================================================
  // 整理相关
  // ============================================================

  /// 获取转移历史
  Future<List<NtTransferHistory>> getTransferHistory({
    required int page,
    required int pageNum,
    String? keyword,
  }) async {
    final data = await _post('/organization/history/list', {
      'page': page,
      'pagenum': pageNum,
      'keyword': ?keyword,
    });
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtTransferHistory.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取转移统计
  Future<NtTransferStatistics> getTransferStatistics() async {
    final data = await _post('/organization/history/statistics');
    return NtTransferStatistics.fromJson(data);
  }

  /// 获取未识别列表
  Future<List<NtUnknownRecord>> listUnknown() async {
    final data = await _post('/organization/unknown/list');
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtUnknownRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 删除未识别记录
  Future<void> deleteUnknown(String id) async {
    await _post('/organization/unknown/delete', {'id': id});
  }

  // ============================================================
  // 推荐相关
  // ============================================================

  /// 获取推荐列表
  Future<List<NtMediaDetail>> getRecommendList({
    required String type,
    required String subtype,
    required int page,
  }) async {
    final data = await _post('/recommend/list', {
      'type': type,
      'subtype': subtype,
      'page': page,
    });
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtMediaDetail.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ============================================================
  // 用户相关
  // ============================================================

  /// 获取用户信息
  Future<NtUserInfo?> getUserInfo(String username) async {
    final data = await _post('/user/info', {'username': username});
    if (data['result'] == null) return null;
    return NtUserInfo.fromJson(data['result'] as Map<String, dynamic>);
  }

  /// 获取用户列表
  Future<List<NtUserInfo>> listUsers() async {
    final data = await _post('/user/list');
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtUserInfo.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 用户管理（添加/删除）
  Future<void> manageUser({
    required String oper,
    required String name,
    String? pris,
  }) async {
    await _post('/user/manage', {
      'oper': oper,
      'name': name,
      'pris': ?pris,
    });
  }

  // ============================================================
  // 刷流任务相关
  // ============================================================

  /// 获取刷流任务列表
  Future<List<NtBrushTask>> listBrushTasks() async {
    final data = await _post('/brushtask/list');
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtBrushTask.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取刷流任务详情
  Future<NtBrushTask?> getBrushTaskInfo(String id) async {
    final data = await _post('/brushtask/info', {'id': id});
    if (data['result'] == null) return null;
    return NtBrushTask.fromJson(data['result'] as Map<String, dynamic>);
  }

  /// 新增/修改刷流任务
  Future<void> updateBrushTask({
    String? id,
    required String name,
    required int site,
    required int interval,
    required int downloader,
    required int totalSize,
    required String state,
    String? savePath,
    String? label,
    String? rssUrl,
    String? transfer,
    String? sendMessage,
    String? free,
    String? hr,
    int? torrentSize,
    String? include,
    String? exclude,
    int? dlCount,
    int? peerCount,
    double? seedTime,
    double? hrSeedTime,
    double? seedRatio,
    int? seedSize,
    double? dlTime,
    int? avgUpSpeed,
    double? iaTime,
    int? pubDate,
    int? upSpeed,
    int? downSpeed,
  }) async {
    await _post('/brushtask/update', {
      'brushtask_id': ?id,
      'brushtask_name': name,
      'brushtask_site': site,
      'brushtask_interval': interval,
      'brushtask_downloader': downloader,
      'brushtask_totalsize': totalSize,
      'brushtask_state': state,
      'brushtask_savepath': ?savePath,
      'brushtask_label': ?label,
      'brushtask_rssurl': ?rssUrl,
      'brushtask_transfer': ?transfer,
      'brushtask_sendmessage': ?sendMessage,
      'brushtask_free': ?free,
      'brushtask_hr': ?hr,
      'brushtask_torrent_size': ?torrentSize,
      'brushtask_include': ?include,
      'brushtask_exclude': ?exclude,
      'brushtask_dlcount': ?dlCount,
      'brushtask_peercount': ?peerCount,
      'brushtask_seedtime': ?seedTime,
      'brushtask_hr_seedtime': ?hrSeedTime,
      'brushtask_seedratio': ?seedRatio,
      'brushtask_seedsize': ?seedSize,
      'brushtask_dltime': ?dlTime,
      'brushtask_avg_upspeed': ?avgUpSpeed,
      'brushtask_iatime': ?iaTime,
      'brushtask_pubdate': ?pubDate,
      'brushtask_upspeed': ?upSpeed,
      'brushtask_downspeed': ?downSpeed,
    });
  }

  /// 删除刷流任务
  Future<void> deleteBrushTask(String id) async {
    await _post('/brushtask/delete', {'id': id});
  }

  /// 立即运行刷流任务
  Future<void> runBrushTask(int id) async {
    await _post('/brushtask/run', {'id': id});
  }

  /// 获取刷流任务种子明细
  Future<List<NtBrushTorrent>> getBrushTaskTorrents(String id) async {
    final data = await _post('/brushtask/torrents', {'id': id});
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtBrushTorrent.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ============================================================
  // 配置相关
  // ============================================================

  /// 获取所有配置信息
  Future<NtConfigInfo> getConfigInfo() async {
    final data = await _post('/config/info');
    return NtConfigInfo.fromJson(data);
  }

  /// 保存配置
  Future<void> setConfig(String key, String value) async {
    await _post('/config/set', {'key': key, 'value': value});
  }

  /// 更新配置
  Future<void> updateConfig(String items) async {
    await _post('/config/update', {'items': items});
  }

  /// 配置目录
  Future<void> configDirectory({
    required String oper,
    required String key,
    required String value,
  }) async {
    await _post('/config/directory', {
      'oper': oper,
      'key': key,
      'value': value,
    });
  }

  /// 测试配置连通性
  Future<bool> testConfig(String command) async {
    final data = await _post('/config/test', {'command': command});
    return data['code'] == 0;
  }

  /// 恢复备份配置
  Future<void> restoreConfig(String fileName) async {
    await _post('/config/restore', {'file_name': fileName});
  }

  // ============================================================
  // 过滤规则相关
  // ============================================================

  /// 获取所有过滤规则
  Future<List<NtFilterRuleGroup>> listFilterRules() async {
    final data = await _post('/filterrule/list');
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtFilterRuleGroup.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 新增规则组
  Future<void> addFilterRuleGroup({
    required String name,
    required String isDefault,
  }) async {
    await _post('/filterrule/group/add', {
      'name': name,
      'default': isDefault,
    });
  }

  /// 删除规则组
  Future<void> deleteFilterRuleGroup(String id) async {
    await _post('/filterrule/group/delete', {'id': id});
  }

  /// 设置默认规则组
  Future<void> setDefaultFilterRuleGroup(String id) async {
    await _post('/filterrule/group/default', {'id': id});
  }

  /// 恢复默认规则组
  Future<void> restoreFilterRuleGroup({
    required String groupIds,
    required String initRuleGroups,
  }) async {
    await _post('/filterrule/group/restore', {
      'groupids': groupIds,
      'init_rulegroups': initRuleGroups,
    });
  }

  /// 获取规则详情
  Future<NtFilterRule?> getFilterRuleInfo(int ruleId, int groupId) async {
    final data = await _post('/filterrule/rule/info', {
      'ruleid': ruleId,
      'groupid': groupId,
    });
    if (data['result'] == null) return null;
    return NtFilterRule.fromJson(data['result'] as Map<String, dynamic>);
  }

  /// 新增/修改规则
  Future<void> updateFilterRule({
    int? ruleId,
    required int groupId,
    required String name,
    required String priority,
    String? include,
    String? exclude,
    String? sizeLimit,
    String? free,
  }) async {
    await _post('/filterrule/rule/update', {
      'rule_id': ?ruleId,
      'group_id': groupId,
      'rule_name': name,
      'rule_pri': priority,
      'rule_include': ?include,
      'rule_exclude': ?exclude,
      'rule_sizelimit': ?sizeLimit,
      'rule_free': ?free,
    });
  }

  /// 删除规则
  Future<void> deleteFilterRule(int id) async {
    await _post('/filterrule/rule/delete', {'id': id});
  }

  /// 导入规则组
  Future<void> importFilterRule(String content) async {
    await _post('/filterrule/rule/import', {'content': content});
  }

  /// 分享规则组
  Future<String?> shareFilterRule(int id) async {
    final data = await _post('/filterrule/rule/share', {'id': id});
    return data['result'] as String?;
  }

  // ============================================================
  // 消息通知相关
  // ============================================================

  /// 获取消息渠道详情
  Future<NtMessageClient?> getMessageClientInfo(int cid) async {
    final data = await _post('/message/client/info', {'cid': cid});
    if (data['result'] == null) return null;
    return NtMessageClient.fromJson(data['result'] as Map<String, dynamic>);
  }

  /// 新增/修改消息渠道
  Future<void> updateMessageClient({
    int? cid,
    required String name,
    required String type,
    required String config,
    required String switches,
    required int interactive,
    required int enabled,
  }) async {
    await _post('/message/client/update', {
      'cid': ?cid,
      'name': name,
      'type': type,
      'config': config,
      'switchs': switches,
      'interactive': interactive,
      'enabled': enabled,
    });
  }

  /// 删除消息渠道
  Future<void> deleteMessageClient(int cid) async {
    await _post('/message/client/delete', {'cid': cid});
  }

  /// 设置消息渠道状态
  Future<void> setMessageClientStatus({
    required String flag,
    required int cid,
  }) async {
    await _post('/message/client/status', {'flag': flag, 'cid': cid});
  }

  /// 测试消息渠道配置
  Future<bool> testMessageClient({
    required String type,
    required String config,
  }) async {
    final data = await _post('/message/client/test', {
      'type': type,
      'config': config,
    });
    return data['code'] == 0;
  }

  // ============================================================
  // 插件相关
  // ============================================================

  /// 获取已安装插件
  Future<List<NtPlugin>> listPlugins() async {
    final data = await _post('/plugin/list');
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtPlugin.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取插件市场插件
  Future<List<NtPluginApp>> getPluginApps() async {
    final data = await _post('/plugin/apps');
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtPluginApp.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 安装插件
  Future<void> installPlugin(int id) async {
    await _post('/plugin/install', {'id': id});
  }

  /// 卸载插件
  Future<void> uninstallPlugin(int id) async {
    await _post('/plugin/uninstall', {'id': id});
  }

  /// 获取插件运行状态
  Future<NtPluginStatus?> getPluginStatus(int id) async {
    final data = await _post('/plugin/status', {'id': id});
    if (data['result'] == null) return null;
    return NtPluginStatus.fromJson(data['result'] as Map<String, dynamic>);
  }

  // ============================================================
  // 自定义 RSS 订阅相关
  // ============================================================

  /// 获取自定义 RSS 任务列表
  Future<List<NtRssTask>> listRssTasks() async {
    final data = await _post('/rss/list');
    // API 返回格式: {"data": {"tasks": [...], "parsers": [...]}}
    final items = data['tasks'] as List? ?? data['result'] as List? ?? [];
    return items.map((e) => NtRssTask.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取 RSS 任务详情
  Future<NtRssTask?> getRssTaskInfo(int id) async {
    final data = await _post('/rss/info', {'id': id});
    if (data['result'] == null) return null;
    return NtRssTask.fromJson(data['result'] as Map<String, dynamic>);
  }

  /// 新增/修改 RSS 任务
  Future<void> updateRssTask({
    int? id,
    required String name,
    required String address,
    required int parser,
    required int interval,
    required String uses,
    required String state,
    String? include,
    String? exclude,
    int? filterRule,
    String? note,
  }) async {
    await _post('/rss/update', {
      'id': ?id,
      'name': name,
      'address': address,
      'parser': parser,
      'interval': interval,
      'uses': uses,
      'state': state,
      'include': ?include,
      'exclude': ?exclude,
      'filterrule': ?filterRule,
      'note': ?note,
    });
  }

  /// 删除 RSS 任务
  Future<void> deleteRssTask(int id) async {
    await _post('/rss/delete', {'id': id});
  }

  /// 预览 RSS 任务
  Future<List<NtRssArticle>> previewRssTask(int id) async {
    final data = await _post('/rss/preview', {'id': id});
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtRssArticle.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取 RSS 解析器列表
  Future<List<NtRssParser>> listRssParsers() async {
    final data = await _post('/rss/parser/list');
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtRssParser.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取 RSS 解析器详情
  Future<NtRssParser?> getRssParserInfo(int id) async {
    final data = await _post('/rss/parser/info', {'id': id});
    if (data['result'] == null) return null;
    return NtRssParser.fromJson(data['result'] as Map<String, dynamic>);
  }

  /// 新增/修改 RSS 解析器
  Future<void> updateRssParser({
    required int id,
    required String name,
    required String type,
    required String format,
    String? params,
  }) async {
    await _post('/rss/parser/update', {
      'id': id,
      'name': name,
      'type': type,
      'format': format,
      'params': ?params,
    });
  }

  /// 删除 RSS 解析器
  Future<void> deleteRssParser(int id) async {
    await _post('/rss/parser/delete', {'id': id});
  }

  /// 获取 RSS 任务处理历史
  Future<List<NtRssHistory>> getRssItemHistory(int id) async {
    final data = await _post('/rss/item/history', {'id': id});
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtRssHistory.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 下载 RSS 条目
  Future<void> downloadRssItem({
    required int taskId,
    required String articles,
  }) async {
    await _post('/rss/item/download', {
      'taskid': taskId,
      'articles': articles,
    });
  }

  /// 设置 RSS 条目状态
  Future<void> setRssItemStatus({
    required String flag,
    required String articles,
  }) async {
    await _post('/rss/item/set', {'flag': flag, 'articles': articles});
  }

  /// 名称测试
  Future<bool> testRssName({
    required int taskId,
    required String title,
  }) async {
    final data = await _post('/rss/name/test', {
      'taskid': taskId,
      'title': title,
    });
    return data['code'] == 0;
  }

  // ============================================================
  // 服务相关
  // ============================================================

  /// 运行服务
  Future<void> runService(String item) async {
    await _post('/service/run', {'item': item});
  }

  /// 名称识别测试
  Future<NtNameTestResult?> testNameRecognition(String name) async {
    final data = await _post('/service/name/test', {'name': name});
    if (data['result'] == null) return null;
    return NtNameTestResult.fromJson(data['result'] as Map<String, dynamic>);
  }

  /// 网络连接性测试
  Future<NtNetworkTestResult> testNetwork(String url) async {
    final data = await _post('/service/network/test', {'url': url});
    return NtNetworkTestResult.fromJson(data);
  }

  /// 过滤规则测试
  Future<NtRuleTestResult?> testFilterRule({
    required String title,
    String? subtitle,
    double? size,
  }) async {
    final data = await _post('/service/rule/test', {
      'title': title,
      'subtitle': ?subtitle,
      'size': ?size,
    });
    if (data['result'] == null) return null;
    return NtRuleTestResult.fromJson(data['result'] as Map<String, dynamic>);
  }

  // ============================================================
  // 同步目录相关
  // ============================================================

  /// 获取同步目录列表
  Future<List<NtSyncDirectory>> listSyncDirectories() async {
    final data = await _post('/sync/directory/list');
    // API 返回格式: {"data": {"result": {"17": {...}, "18": {...}}}} - 对象格式
    final result = data['result'];
    if (result == null) return [];
    // 支持对象格式和数组格式
    final List<dynamic> items;
    if (result is Map<String, dynamic>) {
      items = result.values.toList();
    } else if (result is List) {
      items = result;
    } else {
      return [];
    }
    return items.map((e) => NtSyncDirectory.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取同步目录详情
  Future<NtSyncDirectory?> getSyncDirectoryInfo(int sid) async {
    final data = await _post('/sync/directory/info', {'sid': sid});
    if (data['result'] == null) return null;
    return NtSyncDirectory.fromJson(data['result'] as Map<String, dynamic>);
  }

  /// 新增/修改同步目录
  Future<void> updateSyncDirectory({
    int? sid,
    required String from,
    String? to,
    String? unknown,
    String? syncMode,
    String? compatibility,
    String? rename,
    String? enabled,
  }) async {
    await _post('/sync/directory/update', {
      'sid': ?sid,
      'from': from,
      'to': ?to,
      'unknown': ?unknown,
      'syncmod': ?syncMode,
      'compatibility': ?compatibility,
      'rename': ?rename,
      'enabled': ?enabled,
    });
  }

  /// 删除同步目录
  Future<void> deleteSyncDirectory(int sid) async {
    await _post('/sync/directory/delete', {'sid': sid});
  }

  /// 设置同步目录状态
  Future<void> setSyncDirectoryStatus({
    required int sid,
    required String flag,
    required int checked,
  }) async {
    await _post('/sync/directory/status', {
      'sid': sid,
      'flag': flag,
      'checked': checked,
    });
  }

  // ============================================================
  // 自动删种相关
  // ============================================================

  /// 获取自动删种任务列表
  Future<List<NtTorrentRemoverTask>> listTorrentRemoverTasks() async {
    final data = await _post('/torrentremover/task/list');
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtTorrentRemoverTask.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取自动删种任务详情
  Future<NtTorrentRemoverTask?> getTorrentRemoverTaskInfo(int tid) async {
    final data = await _post('/torrentremover/task/info', {'tid': tid});
    if (data['result'] == null) return null;
    return NtTorrentRemoverTask.fromJson(data['result'] as Map<String, dynamic>);
  }

  /// 新增/修改自动删种任务
  Future<void> updateTorrentRemoverTask({
    int? tid,
    required String name,
    required int action,
    required int interval,
    required int enabled,
    required int sameData,
    required int onlyNasTool,
    double? ratio,
    int? seedingTime,
    int? uploadAvs,
    String? size,
    String? savePathKey,
    String? trackerKey,
    String? downloader,
    String? qbState,
    String? qbCategory,
    String? trState,
    String? trErrorKey,
  }) async {
    await _post('/torrentremover/task/update', {
      'tid': ?tid,
      'name': name,
      'action': action,
      'interval': interval,
      'enabled': enabled,
      'samedata': sameData,
      'onlynastool': onlyNasTool,
      'ratio': ?ratio,
      'seeding_time': ?seedingTime,
      'upload_avs': ?uploadAvs,
      'size': ?size,
      'savepath_key': ?savePathKey,
      'tracker_key': ?trackerKey,
      'downloader': ?downloader,
      'qb_state': ?qbState,
      'qb_category': ?qbCategory,
      'tr_state': ?trState,
      'tr_error_key': ?trErrorKey,
    });
  }

  /// 删除自动删种任务
  Future<void> deleteTorrentRemoverTask(int tid) async {
    await _post('/torrentremover/task/delete', {'tid': tid});
  }

  // ============================================================
  // 识别词相关
  // ============================================================

  /// 新增识别词组
  Future<void> addWordsGroup({
    required String tmdbId,
    required String tmdbType,
  }) async {
    await _post('/words/group/add', {
      'tmdb_id': tmdbId,
      'tmdb_type': tmdbType,
    });
  }

  /// 删除识别词组
  Future<void> deleteWordsGroup(int gid) async {
    await _post('/words/group/delete', {'gid': gid});
  }

  /// 获取识别词详情
  Future<NtWordItem?> getWordItemInfo(int wid) async {
    final data = await _post('/words/item/info', {'wid': wid});
    if (data['result'] == null) return null;
    return NtWordItem.fromJson(data['result'] as Map<String, dynamic>);
  }

  /// 删除识别词
  Future<void> deleteWordItem(int id) async {
    await _post('/words/item/delete', {'id': id});
  }

  /// 设置识别词状态
  Future<void> setWordItemStatus(String idsInfo) async {
    await _post('/words/item/status', {'ids_info': idsInfo});
  }

  /// 导出识别词
  Future<String?> exportWordItems({
    required String note,
    required String idsInfo,
  }) async {
    final data = await _post('/words/item/export', {
      'note': note,
      'ids_info': idsInfo,
    });
    return data['result'] as String?;
  }

  /// 导入识别词
  Future<void> importWordItems({
    required String importCode,
    required String idsInfo,
  }) async {
    await _post('/words/item/import', {
      'import_code': importCode,
      'ids_info': idsInfo,
    });
  }

  /// 分析识别词
  Future<NtWordAnalyse?> analyseWordItems(String importCode) async {
    final data = await _post('/words/item/analyse', {'import_code': importCode});
    if (data['result'] == null) return null;
    return NtWordAnalyse.fromJson(data['result'] as Map<String, dynamic>);
  }

  // ============================================================
  // 站点补充接口
  // ============================================================

  /// 获取站点资源列表
  Future<List<NtSearchResult>> getSiteResources({
    required String id,
    int? page,
    String? keyword,
  }) async {
    final data = await _post('/site/resources', {
      'id': id,
      'page': ?page,
      'keyword': ?keyword,
    });
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtSearchResult.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取站点图标
  Future<String?> getSiteFavicon(String name) async {
    final data = await _post('/site/favicon', {'name': name});
    return data['result'] as String?;
  }

  /// 检查站点是否支持FREE/HR检测
  Future<bool> checkSite(String url) async {
    final data = await _post('/site/check', {'url': url});
    return data['code'] == 0;
  }

  /// 获取站点活动统计
  Future<Map<String, dynamic>> getSiteStatisticsActivity(String name) async {
    final data = await _post('/site/statistics/activity', {'name': name});
    return data;
  }

  /// 获取站点历史数据
  Future<Map<String, dynamic>> getSiteStatisticsHistory(int days) async {
    final data = await _post('/site/statistics/history', {'days': days});
    return data;
  }

  /// 获取站点做种分布
  Future<Map<String, dynamic>> getSiteStatisticsSeedInfo(String name) async {
    final data = await _post('/site/statistics/seedinfo', {'name': name});
    return data;
  }

  // ============================================================
  // 订阅补充接口
  // ============================================================

  /// 清理订阅缓存
  Future<void> clearSubscribeCache() async {
    await _post('/subscribe/cache/delete');
  }

  /// 删除订阅历史
  Future<void> deleteSubscribeHistory(int rssId) async {
    await _post('/subscribe/history/delete', {'rssid': rssId});
  }

  /// 历史重新订阅
  Future<void> redoSubscribe({
    required int rssId,
    required String type,
  }) async {
    await _post('/subscribe/redo', {'rssid': rssId, 'type': type});
  }

  /// 获取电影上映日期
  Future<String?> getMovieReleaseDate(String id) async {
    final data = await _post('/subscribe/movie/date', {'id': id});
    return data['result'] as String?;
  }

  /// 获取电视剧上映日期
  Future<String?> getTvReleaseDate({
    required String id,
    required int season,
    String? name,
  }) async {
    final data = await _post('/subscribe/tv/date', {
      'id': id,
      'season': season,
      'name': ?name,
    });
    return data['result'] as String?;
  }

  // ============================================================
  // 媒体整理补充接口
  // ============================================================

  /// 清空文件转移缓存
  Future<void> emptyTransferCache() async {
    await _post('/organization/cache/empty');
  }

  /// 清除所有整理历史
  Future<void> clearTransferHistory() async {
    await _post('/organization/history/clear');
  }

  /// 删除整理历史记录
  Future<void> deleteTransferHistory(String logIds) async {
    await _post('/organization/history/delete', {'logids': logIds});
  }

  /// 重新识别
  Future<void> redoUnknown({
    required String flag,
    required String ids,
  }) async {
    await _post('/organization/unknown/redo', {'flag': flag, 'ids': ids});
  }

  /// 手动识别
  Future<void> renameUnknown({
    String? logId,
    String? unknownId,
    required String syncMode,
    int? tmdb,
    String? title,
    String? year,
    String? type,
    int? season,
    String? episodeFormat,
    int? minFileSize,
  }) async {
    await _post('/organization/unknown/rename', {
      'logid': ?logId,
      'unknown_id': ?unknownId,
      'syncmod': syncMode,
      'tmdb': ?tmdb,
      'title': ?title,
      'year': ?year,
      'type': ?type,
      'season': ?season,
      'episode_format': ?episodeFormat,
      'min_filesize': ?minFileSize,
    });
  }

  /// 自定义识别
  Future<void> renameUnknownUdf({
    required String inPath,
    required String outPath,
    required String syncMode,
    int? tmdb,
    String? title,
    String? year,
    String? type,
    int? season,
    String? episodeFormat,
    String? episodeDetails,
    String? episodeOffset,
    int? minFileSize,
  }) async {
    await _post('/organization/unknown/renameudf', {
      'inpath': inPath,
      'outpath': outPath,
      'syncmod': syncMode,
      'tmdb': ?tmdb,
      'title': ?title,
      'year': ?year,
      'type': ?type,
      'season': ?season,
      'episode_format': ?episodeFormat,
      'episode_details': ?episodeDetails,
      'episode_offset': ?episodeOffset,
      'min_filesize': ?minFileSize,
    });
  }

  // ============================================================
  // 下载器补充接口
  // ============================================================

  /// 新增/修改下载器
  Future<void> addDownloadClient({
    String? did,
    required String name,
    required String type,
    required String enabled,
    required String transfer,
    required String onlyNasTool,
    required String rmtMode,
    required String config,
  }) async {
    await _post('/download/client/add', {
      'did': ?did,
      'name': name,
      'type': type,
      'enabled': enabled,
      'transfer': transfer,
      'only_nastool': onlyNasTool,
      'rmt_mode': rmtMode,
      'config': config,
    });
  }

  /// 设置下载器状态
  Future<void> checkDownloadClient({
    required String did,
    required String checked,
    required String flag,
  }) async {
    await _post('/download/client/check', {
      'did': did,
      'checked': checked,
      'flag': flag,
    });
  }

  /// 删除下载器
  Future<void> deleteDownloadClient(String did) async {
    await _post('/download/client/delete', {'did': did});
  }

  /// 测试下载器
  Future<bool> testDownloadClient({
    required String type,
    required String config,
  }) async {
    final data = await _post('/download/client/test', {
      'type': type,
      'config': config,
    });
    return data['code'] == 0;
  }

  /// 获取下载设置列表
  Future<List<Map<String, dynamic>>> listDownloadConfigs({String? sid}) async {
    final data = await _post('/download/config/list', {
      'sid': ?sid,
    });
    final items = data['result'] as List? ?? [];
    return items.cast<Map<String, dynamic>>();
  }

  /// 获取下载设置详情
  Future<Map<String, dynamic>?> getDownloadConfigInfo(String sid) async {
    final data = await _post('/download/config/info', {'sid': sid});
    return data['result'] as Map<String, dynamic>?;
  }

  /// 新增/修改下载设置
  Future<void> updateDownloadConfig({
    required String sid,
    required String name,
    String? category,
    String? tags,
    int? isPaused,
    int? uploadLimit,
    int? downloadLimit,
    int? ratioLimit,
    int? seedingTimeLimit,
    String? downloader,
  }) async {
    await _post('/download/config/update', {
      'sid': sid,
      'name': name,
      'category': ?category,
      'tags': ?tags,
      'is_paused': ?isPaused,
      'upload_limit': ?uploadLimit,
      'download_limit': ?downloadLimit,
      'ratio_limit': ?ratioLimit,
      'seeding_time_limit': ?seedingTimeLimit,
      'downloader': ?downloader,
    });
  }

  /// 删除下载设置
  Future<void> deleteDownloadConfig(String sid) async {
    await _post('/download/config/delete', {'sid': sid});
  }

  /// 获取下载保存目录
  Future<List<String>> getDownloadConfigDirectories({String? sid}) async {
    final data = await _post('/download/config/directory', {
      'sid': ?sid,
    });
    return (data['result'] as List?)?.cast<String>() ?? [];
  }

  // ============================================================
  // 媒体补充接口
  // ============================================================

  /// 清空 TMDB 缓存
  Future<void> clearMediaCache() async {
    await _post('/media/cache/clear');
  }

  /// 删除 TMDB 缓存
  Future<void> deleteMediaCache(String cacheKey) async {
    await _post('/media/cache/delete', {'cache_key': cacheKey});
  }

  /// 修改 TMDB 缓存标题
  Future<void> updateMediaCache({
    required String key,
    required String title,
  }) async {
    await _post('/media/cache/update', {'key': key, 'title': title});
  }

  /// 获取二级分类配置
  Future<List<String>> getMediaCategoryList(String type) async {
    final data = await _post('/media/category/list', {'type': type});
    return (data['result'] as List?)?.cast<String>() ?? [];
  }

  /// 获取演员参演作品
  Future<List<NtMediaDetail>> getMediaPerson({
    required String type,
    String? personId,
    int? page,
  }) async {
    final data = await _post('/media/person', {
      'type': type,
      'personid': ?personId,
      'page': ?page,
    });
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtMediaDetail.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 下载字幕
  Future<void> downloadSubtitle({
    required String path,
    required String name,
  }) async {
    await _post('/media/subtitle/download', {'path': path, 'name': name});
  }

  // ============================================================
  // 私有方法
  // ============================================================

  Future<Map<String, dynamic>> _post(String path, [Map<String, dynamic>? params]) async {
    final url = Uri.parse('$baseUrl/api/v1$path');

    final headers = <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'application/json',
      ..._auth.authHeaders,
    };

    final body = params?.map((k, v) => MapEntry(k, v.toString()));

    // 调试日志：请求信息
    if (kDebugMode) {
      logger.d('[NasToolApi] POST $url');
    }

    try {
      final response = await client.post(
        url,
        headers: headers,
        body: body,
      );

      // 调试日志：响应信息
      if (kDebugMode) {
        logger.d('[NasToolApi] Response ${response.statusCode}');
        // 打印响应体前500字符用于调试
        final bodyPreview = response.body.length > 500 
            ? '${response.body.substring(0, 500)}...(truncated)'
            : response.body;
        logger.d('[NasToolApi] Body: $bodyPreview');
      }

      if (response.statusCode == 401) {
        throw const NasToolApiException('认证失败，请重新登录');
      }

      if (response.statusCode == 403) {
        throw const NasToolApiException('没有权限执行此操作');
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw NasToolApiException('请求失败: ${response.statusCode}');
      }

      if (response.body.isEmpty) return {};

      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) {
        return {'result': json};
      }

      // NASTool API 返回格式: {"code": 0, "success": true, "data": {...}}
      // 提取 data 字段作为实际返回数据
      final data = json['data'];
      if (data is Map<String, dynamic>) {
        return data;
      } else if (data is List) {
        return {'result': data};
      }
      // 如果没有 data 字段，返回原始 json（兼容旧格式）
      return json;
    } on SocketException catch (e) {
      if (kDebugMode) {
        logger.e('[NasToolApi] SocketException', e);
      }
      throw NasToolApiException('无法连接服务器: ${e.message}');
    } on FormatException catch (e) {
      if (kDebugMode) {
        logger.e('[NasToolApi] FormatException', e);
      }
      throw const NasToolApiException('响应格式错误');
    }
  }

  Future<dynamic> _get(String path) async {
    final url = Uri.parse('$baseUrl/api/v1$path');

    final headers = <String, String>{
      'Accept': 'application/json',
      ..._auth.authHeaders,
    };

    // 调试日志：请求信息
    if (kDebugMode) {
      logger.d('[NasToolApi] GET $url');
    }

    try {
      final response = await client.get(url, headers: headers);

      // 调试日志：响应信息
      if (kDebugMode) {
        logger.d('[NasToolApi] Response ${response.statusCode}');
        // 打印响应体前500字符用于调试
        final bodyPreview = response.body.length > 500 
            ? '${response.body.substring(0, 500)}...(truncated)'
            : response.body;
        logger.d('[NasToolApi] Body: $bodyPreview');
      }

      if (response.statusCode == 401) {
        throw const NasToolApiException('认证失败，请重新登录');
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw NasToolApiException('请求失败: ${response.statusCode}');
      }

      if (response.body.isEmpty) return {};

      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) {
        return {'result': json};
      }

      // NASTool API 返回格式: {"code": 0, "success": true, "data": {...}}
      // 提取 data 字段作为实际返回数据
      final data = json['data'];
      if (data is Map<String, dynamic>) {
        return data;
      } else if (data is List) {
        return {'result': data};
      }
      // 如果没有 data 字段，返回原始 json（兼容旧格式）
      return json;
    } on SocketException catch (e) {
      if (kDebugMode) {
        logger.e('[NasToolApi] SocketException', e);
      }
      throw NasToolApiException('无法连接服务器: ${e.message}');
    }
  }

  /// 释放资源
  void dispose() {
    _client?.close();
    _client = null;
    _auth.clear();
  }
}

/// NASTool API 异常
class NasToolApiException implements Exception {
  const NasToolApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
