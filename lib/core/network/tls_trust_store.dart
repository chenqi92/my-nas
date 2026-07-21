import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:my_nas/core/utils/hive_utils.dart';
import 'package:my_nas/core/utils/logger.dart';

/// Endpoint-scoped TOFU certificate pins for user-approved self-signed TLS.
///
/// System-valid certificates never reach [allowsInvalidCertificate]. For an
/// invalid/self-signed certificate, the first fingerprint for host:port is
/// recorded and subsequent changes are rejected instead of being accepted by
/// a process-wide `badCertificateCallback`.
class TlsTrustStore {
  const TlsTrustStore._();

  static const _storageKey = 'tls_self_signed_pins_v1';
  static final Map<String, String> _pins = {};
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

  static bool allowsInvalidCertificate(
    X509Certificate certificate,
    String host,
    int port, {
    required bool allowSelfSigned,
  }) {
    if (!allowSelfSigned || !_loaded) return false;

    final key = '${host.trim().toLowerCase()}:$port';
    final fingerprint = sha256.convert(certificate.der).toString();
    final pinned = _pins[key];
    if (pinned != null) {
      final matches = pinned == fingerprint;
      if (!matches) {
        logger.e('TlsTrustStore: $key 的证书指纹发生变化，已阻止连接');
      }
      return matches;
    }

    _pins[key] = fingerprint;
    logger.i('TlsTrustStore: 首次信任并固定自签名证书 $key');
    unawaited(_persist());
    return true;
  }

  static Future<void> removePin(String host, int port) async {
    await load();
    _pins.remove('${host.trim().toLowerCase()}:$port');
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
