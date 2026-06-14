import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/xmltv_parser.dart';

/// 电子节目单（EPG / XMLTV）provider：按 [epgUrl] 拉取并解析为
/// `channelId -> 按时间排序的节目列表`。
///
/// - 自动处理 gzip（URL 以 .gz 结尾，或字节以 0x1f 0x8b 开头）。
/// - 拉取成功后 keepAlive 缓存到会话，避免页面重建重复下载（EPG 体积大）。
/// - 任何失败都返回空 map，页面降级为「无节目」而非报错。
final liveEpgProvider = FutureProvider.autoDispose
    .family<Map<String, List<EpgProgramme>>, String>((ref, epgUrl) async {
  if (epgUrl.isEmpty) return const {};
  try {
    final dio = Dio();
    final resp = await dio.get<List<int>>(
      epgUrl,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    var bytes = resp.data ?? const <int>[];
    if (bytes.isEmpty) return const {};
    final isGzip = epgUrl.toLowerCase().endsWith('.gz') ||
        (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b);
    if (isGzip) {
      bytes = GZipDecoder().decodeBytes(bytes);
    }
    final xmlString = utf8.decode(bytes, allowMalformed: true);
    final map = XmltvParser.parse(xmlString);
    ref.keepAlive();
    return map;
  } on Object catch (e, st) {
    logger.e('EPG: 拉取/解析失败 $epgUrl', e, st);
    return const {};
  }
});
