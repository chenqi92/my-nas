import 'dart:async';

import 'package:dio/dio.dart';
import 'package:my_nas/core/translation/token_bucket.dart';
import 'package:my_nas/core/translation/translation_provider.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 默认 provider：调用 Google Translate 公共 API（免费 / 无需 key）。
///
/// 该端点是 translate.google.com 网页内部使用的反向工程接口，没有官方
/// 文档承诺；个人用量基本稳定，频繁请求会被 429。内部用 [TokenBucket]
/// 限速到默认 5 QPS，可由调用方覆盖。
class GoogleFreeTranslationProvider implements TranslationProvider {
  GoogleFreeTranslationProvider({Dio? dio, TokenBucket? bucket})
      : _dio = dio ?? Dio(),
        _bucket = bucket ?? _defaultBucket;

  static final TokenBucket _defaultBucket = TokenBucket(
    capacity: 5,
    refillPerSecond: 5,
  );

  final Dio _dio;
  final TokenBucket _bucket;

  @override
  String get id => 'google_free';

  @override
  String get displayName => 'Google 翻译（免费）';

  @override
  Future<List<String?>> translate({
    required List<String> texts,
    required String targetLangBcp47,
    String? sourceLangBcp47,
  }) async {
    final out = <String?>[];
    for (final t in texts) {
      out.add(await _translateOne(t, sourceLangBcp47 ?? 'auto', targetLangBcp47));
    }
    return out;
  }

  Future<String?> _translateOne(String text, String sl, String tl) async {
    if (text.trim().isEmpty) return null;
    await _bucket.acquire();
    try {
      final resp = await _dio.get<dynamic>(
        'https://translate.googleapis.com/translate_a/single',
        queryParameters: {
          'client': 'gtx',
          'sl': sl,
          'tl': tl,
          'dt': 't',
          'q': text,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
      final data = resp.data;
      // 返回结构：[[[translatedText, sourceText, ...], ...], null, ...]
      if (data is List && data.isNotEmpty && data.first is List) {
        final segments = (data.first as List).cast<dynamic>();
        final buf = StringBuffer();
        for (final seg in segments) {
          if (seg is List && seg.isNotEmpty && seg.first is String) {
            buf.write(seg.first as String);
          }
        }
        final translated = buf.toString().trim();
        return translated.isEmpty ? null : translated;
      }
    } on Exception catch (e) {
      logger.w('GoogleTranslate: 失败 "$text": $e');
    }
    return null;
  }
}
