import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:my_nas/core/errors/exceptions.dart';
import 'package:my_nas/core/network/hosts_resolver_service.dart';
import 'package:my_nas/core/utils/hive_utils.dart';
import 'package:my_nas/core/utils/logger.dart';

/// Result of checking whether a failed HTTPS endpoint needs user trust.
enum TlsTrustDecision { notRequired, declined, trusted }

/// Certificate information shown in the one-tap trust prompt.
class TlsCertificateInfo {
  const TlsCertificateInfo({
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.subject,
    required this.issuer,
    required this.startValidity,
    required this.endValidity,
  });

  final String host;
  final int port;
  final String fingerprint;
  final String subject;
  final String issuer;
  final DateTime startValidity;
  final DateTime endValidity;

  String get endpoint => TlsTrustStore.endpointKey(host, port);
}

/// A single prompt request. Concurrent failures for the same certificate are
/// merged so the user only sees one dialog.
class TlsTrustRequest {
  const TlsTrustRequest({
    required this.certificate,
    required this.certificateChanged,
  });

  final TlsCertificateInfo certificate;
  final bool certificateChanged;
}

class _PendingTlsTrustRequest {
  _PendingTlsTrustRequest(this.request);

  final TlsTrustRequest request;
  final List<Completer<bool>> waiters = [];
}

/// Endpoint-scoped certificate pins for invalid/self-signed TLS certificates.
///
/// System-valid certificates never reach [allowsInvalidCertificate]. When
/// strict validation fails, [requestTrustForEndpoint] performs a credential-
/// free TLS handshake, queues one user confirmation, saves the exact SHA-256
/// fingerprint for host:port, and lets the caller retry automatically.
class TlsTrustStore {
  const TlsTrustStore._();

  static const _storageKey = 'tls_self_signed_pins_v1';
  static final Map<String, String> _pins = {};
  static final List<_PendingTlsTrustRequest> _requestQueue = [];
  static final ValueNotifier<TlsTrustRequest?> pendingRequest =
      ValueNotifier<TlsTrustRequest?>(null);

  static Future<void>? _loadFuture;
  static bool _loaded = false;

  static Future<void> load() => _loadFuture ??= _load();

  static Future<void> _load() async {
    try {
      final box = await HiveUtils.getSettingsBox();
      final raw = box.get(_storageKey);
      if (raw is Map) {
        _pins
          ..clear()
          ..addAll(raw.map((key, value) => MapEntry('$key', '$value')));
      }
    } on Exception catch (e) {
      logger.w('TlsTrustStore: 加载证书指纹失败', e);
    } finally {
      _loaded = true;
    }
  }

  /// Callback used by all HTTP stacks.
  ///
  /// 只放行用户已确认并固定的指纹。未固定的证书一律拒绝本次握手：
  /// 该回调是同步的，无法在此等待用户确认，因此由 [requestTrustForEndpoint]
  /// 的确认队列在连接失败后补上弹窗，用户同意后固定指纹并自动重试。
  ///
  /// [allowSelfSigned] 为 legacy 全局「信任自签名证书」开关。它**不再**静默固定
  /// 证书（首连即被 MITM 会被永久劫持），只决定是否主动把该端点排进确认队列，
  /// 以覆盖没有重试包装的调用方。
  static bool allowsInvalidCertificate(
    X509Certificate certificate,
    String host,
    int port, {
    required bool allowSelfSigned,
  }) {
    if (!_loaded) return false;

    final key = endpointKey(host, port);
    final fingerprint = sha256.convert(certificate.der).toString();
    final pinned = _pins[key];
    if (pinned != null) {
      final matches = pinned == fingerprint;
      if (!matches) {
        logger.e('TlsTrustStore: $key 的证书指纹发生变化，已阻止连接');
      }
      return matches;
    }

    if (allowSelfSigned) {
      logger.w('TlsTrustStore: $key 证书未固定，改为请求用户确认（不再静默信任）');
      _enqueueTrustFromSyncCallback(host, port);
    }
    return false;
  }

  /// 同步回调里发起确认请求：无法 await，故只排队，本次握手仍然失败。
  ///
  /// 同一端点在确认完成前只探测一次，避免重试风暴刷出多个弹窗。
  static final Set<String> _inFlightSyncPrompts = {};

  static void _enqueueTrustFromSyncCallback(String host, int port) {
    final key = endpointKey(host, port);
    if (!_inFlightSyncPrompts.add(key)) return;

    unawaited(
      requestTrustForEndpoint(Uri(scheme: 'https', host: host, port: port))
          .catchError((Object e, StackTrace st) {
        logger.w('TlsTrustStore: 请求确认 $key 的证书失败', e, st);
        return TlsTrustDecision.notRequired;
      }).whenComplete(() => _inFlightSyncPrompts.remove(key)),
    );
  }

  /// Inspects an HTTPS endpoint after a failed connection. A prompt is queued
  /// only when the system rejects its certificate. No application credentials
  /// or HTTP request are sent during this TLS-only probe.
  static Future<TlsTrustDecision> requestTrustForEndpoint(Uri endpoint) async {
    if (endpoint.scheme.toLowerCase() != 'https' || endpoint.host.isEmpty) {
      return TlsTrustDecision.notRequired;
    }

    await load();
    final certificate = await _inspectInvalidCertificate(endpoint);
    if (certificate == null) return TlsTrustDecision.notRequired;

    final pinned = _pins[certificate.endpoint];
    if (pinned == certificate.fingerprint) {
      // The HTTP stack should accept this on retry through the pin callback.
      return TlsTrustDecision.trusted;
    }

    final accepted = await _enqueueTrustRequest(
      TlsTrustRequest(
        certificate: certificate,
        certificateChanged: pinned != null,
      ),
    );
    return accepted ? TlsTrustDecision.trusted : TlsTrustDecision.declined;
  }

  /// Completes the currently displayed request and advances the prompt queue.
  static Future<void> resolveTrustRequest(
    TlsTrustRequest request, {
    required bool approved,
  }) async {
    final index = _requestQueue.indexWhere(
      (pending) => identical(pending.request, request),
    );
    if (index < 0) return;

    final pending = _requestQueue[index];
    if (approved) {
      final certificate = request.certificate;
      _pins[certificate.endpoint] = certificate.fingerprint;
      await _persist();
      logger.i('TlsTrustStore: 用户已信任并固定 HTTPS 证书 ${certificate.endpoint}');
    } else {
      logger.i(
        'TlsTrustStore: 用户拒绝信任 HTTPS 证书 ${request.certificate.endpoint}',
      );
    }

    _requestQueue.removeAt(index);
    for (final waiter in pending.waiters) {
      if (!waiter.isCompleted) waiter.complete(approved);
    }
    pendingRequest.value = _requestQueue.firstOrNull?.request;
  }

  static Future<bool> _enqueueTrustRequest(TlsTrustRequest request) {
    final existing = _requestQueue.cast<_PendingTlsTrustRequest?>().firstWhere(
          (pending) =>
              pending?.request.certificate.endpoint ==
                  request.certificate.endpoint &&
              pending?.request.certificate.fingerprint ==
                  request.certificate.fingerprint,
          orElse: () => null,
        );
    final pending = existing ?? _PendingTlsTrustRequest(request);
    final completer = Completer<bool>();
    pending.waiters.add(completer);

    if (existing == null) {
      _requestQueue.add(pending);
      pendingRequest.value ??= pending.request;
    }
    return completer.future;
  }

  static Future<TlsCertificateInfo?> _inspectInvalidCertificate(
    Uri endpoint,
  ) async {
    X509Certificate? rejectedCertificate;
    Socket? tcpSocket;
    SecureSocket? socket;
    try {
      bool acceptAndCapture(X509Certificate certificate) {
        rejectedCertificate = certificate;
        return true;
      }

      final mappedHost = HostsResolverService.instance.resolve(endpoint.host);
      if (mappedHost == null) {
        socket = await SecureSocket.connect(
          endpoint.host,
          endpoint.port,
          timeout: const Duration(seconds: 8),
          onBadCertificate: acceptAndCapture,
        );
      } else {
        tcpSocket = await Socket.connect(
          mappedHost,
          endpoint.port,
          timeout: const Duration(seconds: 8),
        );
        socket = await SecureSocket.secure(
          tcpSocket,
          host: endpoint.host,
          onBadCertificate: acceptAndCapture,
        ).timeout(const Duration(seconds: 8));
        tcpSocket = null;
      }
      final certificate = rejectedCertificate;
      if (certificate == null) return null;

      return TlsCertificateInfo(
        host: endpoint.host,
        port: endpoint.port,
        fingerprint: sha256.convert(certificate.der).toString(),
        subject: certificate.subject,
        issuer: certificate.issuer,
        startValidity: certificate.startValidity,
        endValidity: certificate.endValidity,
      );
    } on Exception catch (e, st) {
      logger.w(
        'TlsTrustStore: 无法读取 ${endpoint.host}:${endpoint.port} 的证书',
        e,
        st,
      );
      return null;
    } finally {
      socket?.destroy();
      tcpSocket?.destroy();
    }
  }

  /// Identifies certificate failures before Dio turns them into a generic
  /// network/server error.
  static bool isCertificateValidationError(Object? error) {
    if (error == null) return false;
    if (error is TlsCertificateException || error is HandshakeException) {
      return true;
    }
    final message = error.toString().toLowerCase();
    return message.contains('certificate_verify_failed') ||
        message.contains('certificate verify failed') ||
        message.contains('hostname mismatch') ||
        message.contains('bad certificate') ||
        message.contains('self signed certificate') ||
        message.contains('handshake error in client');
  }

  static bool isTrustDeclinedError(Object? error) {
    if (error == null) return false;
    if (error is TlsCertificateTrustDeclinedException) return true;
    return error.toString().contains('TlsCertificateTrustDeclinedException');
  }

  static String endpointKey(String host, int port) =>
      '${host.trim().toLowerCase()}:$port';

  static String formatFingerprint(String fingerprint) {
    final normalized = fingerprint.replaceAll(':', '').toUpperCase();
    return [
      for (var index = 0; index < normalized.length; index += 2)
        normalized.substring(
          index,
          index + 2 > normalized.length ? normalized.length : index + 2,
        ),
    ].join(':');
  }

  static Future<void> removePin(String host, int port) async {
    await load();
    _pins.remove(endpointKey(host, port));
    await _persist();
  }

  static Future<void> _persist() async {
    try {
      final box = await HiveUtils.getSettingsBox();
      await box.put(_storageKey, Map<String, String>.from(_pins));
      await box.flush();
    } on Exception catch (e) {
      logger.w('TlsTrustStore: 保存证书指纹失败', e);
    }
  }
}
