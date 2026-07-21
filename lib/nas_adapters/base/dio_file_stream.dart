import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// Opens a binary response and enforces the streaming contract used by NAS
/// adapters. Some NAS APIs return an HTML/JSON login page with HTTP 200; those
/// responses must never be passed to a media decoder as file bytes.
Future<Stream<List<int>>> openDioFileStream(
  Dio dio,
  String url, {
  FileRange? range,
  void Function()? onSessionInvalid,
}) async {
  final headers = <String, dynamic>{};
  if (range != null) {
    final end = range.end == null ? '' : '${range.end! - 1}';
    headers['Range'] = 'bytes=${range.start}-$end';
  }

  final response = await dio.get<ResponseBody>(
    url,
    options: Options(
      responseType: ResponseType.stream,
      headers: headers,
      validateStatus: (status) => status != null && status < 600,
    ),
  );
  final status = response.statusCode ?? 0;
  if (status == 401 || status == 403) {
    onSessionInvalid?.call();
    throw StateError('文件会话已失效（HTTP $status）');
  }
  if (status < 200 || status >= 300) {
    throw StateError('文件流请求失败（HTTP $status）');
  }
  final body = response.data;
  if (body == null || status == 204) {
    throw StateError('文件流响应为空');
  }

  final contentType = response.headers
      .value(Headers.contentTypeHeader)
      ?.toLowerCase();
  final expectedDocument = _isExpectedDocumentResponse(
    url,
    contentType,
    response.headers,
  );
  if (_isErrorContentType(contentType) &&
      !expectedDocument) {
    onSessionInvalid?.call();
    throw StateError('服务器返回了错误页面（$contentType）');
  }

  var skipBytes = 0;
  int? takeBytes;
  if (range != null) {
    if (status == 206) {
      final contentRange = response.headers.value('content-range');
      if (contentRange == null ||
          !contentRange.toLowerCase().startsWith('bytes ${range.start}-')) {
        throw StateError('服务器返回了无效的 Content-Range');
      }
    } else if (status == 200) {
      // A number of NAS firmwares ignore Range. Preserve correctness by
      // slicing the full response locally instead of returning the wrong data.
      skipBytes = range.start;
    }
    if (range.end != null) takeBytes = range.end! - range.start;
  }

  return _validateAndSlice(
    body.stream,
    skipBytes: skipBytes,
    takeBytes: takeBytes,
    inspectErrorPayload: !expectedDocument,
    onErrorPayload: onSessionInvalid,
  );
}

bool _isErrorContentType(String? contentType) {
  if (contentType == null) return false;
  return contentType.contains('application/json') ||
      contentType.contains('text/html') ||
      contentType.contains('application/problem+json');
}

bool _isExpectedDocumentResponse(
  String url,
  String? contentType,
  Headers headers,
) {
  final disposition = headers.value('content-disposition')?.toLowerCase();
  if (disposition?.contains('attachment') ?? false) return true;
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  final candidates = <String>[
    uri.path.toLowerCase(),
    ...uri.queryParameters.values.map((value) => value.toLowerCase()),
  ];
  if (contentType?.contains('json') ?? false) {
    return candidates.any((value) => value.endsWith('.json'));
  }
  if (contentType?.contains('html') ?? false) {
    return candidates.any(
      (value) => value.endsWith('.html') || value.endsWith('.htm'),
    );
  }
  return false;
}

Stream<List<int>> _validateAndSlice(
  Stream<List<int>> input, {
  required int skipBytes,
  required int? takeBytes,
  required bool inspectErrorPayload,
  void Function()? onErrorPayload,
}) async* {
  var remainingSkip = skipBytes;
  var remainingTake = takeBytes;
  var inspected = false;

  await for (var chunk in input) {
    if (inspectErrorPayload && !inspected && chunk.isNotEmpty) {
      inspected = true;
      final prefix = utf8.decode(
        chunk.take(512).toList(growable: false),
        allowMalformed: true,
      );
      if (_looksLikeErrorPayload(prefix)) {
        onErrorPayload?.call();
        throw StateError('服务器返回了登录页或 API 错误，而不是文件内容');
      }
    }

    if (remainingSkip >= chunk.length) {
      remainingSkip -= chunk.length;
      continue;
    }
    if (remainingSkip > 0) {
      chunk = chunk.sublist(remainingSkip);
      remainingSkip = 0;
    }
    if (remainingTake != null) {
      if (remainingTake <= 0) break;
      if (chunk.length > remainingTake) {
        yield chunk.sublist(0, remainingTake);
        break;
      }
      remainingTake -= chunk.length;
    }
    if (chunk.isNotEmpty) yield chunk;
  }

  if (remainingSkip > 0) {
    throw StateError('服务器返回的文件短于请求的 Range 起点');
  }
}

bool _looksLikeErrorPayload(String prefix) {
  final value = prefix.trimLeft().toLowerCase();
  if (value.startsWith('<!doctype html') ||
      value.startsWith('<html')) {
    return true;
  }
  if (!value.startsWith('{')) return false;
  return value.contains('"error"') ||
      value.contains('"message"') ||
      value.contains('"msg"') ||
      value.contains('"code"') ||
      value.contains('"success"');
}
