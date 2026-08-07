import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';

class _Pbkdf2Request {
  const _Pbkdf2Request({required this.material, required this.salt});

  final String material;
  final Uint8List salt;
}

Uint8List _derivePbkdf2InIsolate(_Pbkdf2Request request) {
  final params = Pbkdf2Parameters(
    request.salt,
    FallbackBoxKey.iterations,
    FallbackBoxKey.keyLengthBytes,
  );
  final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(params);
  return kdf.process(Uint8List.fromList(utf8.encode(request.material)));
}

/// 本地降级加密 box 的 AES key 派生
///
/// 仅在系统 Keychain / SecureStorage 不可用时作为降级方案使用，
/// 安全级别低于系统 Keychain。
///
/// 派生方式：PBKDF2-HMAC-SHA256(设备主机名 + domain, 随机 salt, 10 万次)。
/// salt 为每安装随机生成一次并持久化在独立的明文 box 中。
///
/// 相比旧版单次 SHA-256(主机名 + 固定 salt) 的改进与边界：
/// - 旧版同主机名的所有安装派生出同一个 key，攻击者可离线预计算
///   「主机名 → key」表，一次计算即可解开任意设备上的 box。随机 salt
///   使跨设备预计算失效，每台设备必须单独暴力破解。
/// - 只拿到 box 文件（例如排除了 salt 的备份、单个泄漏的 box）时无法
///   派生出 key。
/// - 10 万次迭代使单设备暴力破解的成本大幅上升。
/// - 边界：能读取应用完整数据目录的本地攻击者同时拿到 salt 和 box，
///   仍可还原凭证。无系统 Keychain 时这是无密钥本地存储的固有限制，
///   本方案目的是避免明文持久化并消除跨设备预计算，而非抵抗此类攻击。
abstract final class FallbackBoxKey {
  /// PBKDF2 迭代次数
  static const iterations = 100000;

  /// 派生出的 AES key 长度（HiveAesCipher 要求 256 位）
  static const keyLengthBytes = 32;

  static const _saltLengthBytes = 32;
  static const _saltBoxName = 'fallback_key_salt_v1';
  static const _saltKey = 'salt';

  static Box<String>? _saltBox;
  static Future<Box<String>>? _saltBoxInit;

  /// 派生指定 domain 的降级 box key
  ///
  /// [domain] 用于隔离不同用途的 box（如 auth / app_lock），
  /// 相同 salt 下不同 domain 派生出不同 key。
  static Future<List<int>> derive(String domain) async {
    final salt = await _getOrCreateSalt();
    final material = '${Platform.localHostname}|$domain|v2';
    final key = await compute<_Pbkdf2Request, Uint8List>(
      _derivePbkdf2InIsolate,
      _Pbkdf2Request(material: material, salt: salt),
    );
    return key;
  }

  /// 旧版派生方式，仅用于迁移已有 box
  ///
  /// 对应 v1 的 `sha256(主机名|domain|v1)`。新代码不要调用。
  static List<int> deriveLegacy(String legacyMaterial) =>
      sha256.convert(utf8.encode(legacyMaterial)).bytes;

  /// 读取或首次生成每安装随机 salt
  ///
  /// salt 本身不是机密（它的作用是消除跨设备预计算），因此存在
  /// 明文 box 中。生成失败时回退到主机名派生的确定性 salt，
  /// 保证降级路径始终可用。
  static Future<Uint8List> _getOrCreateSalt() async {
    try {
      final box = await _getSaltBox();
      final existing = box.get(_saltKey);
      if (existing != null) {
        final decoded = base64Decode(existing);
        if (decoded.length == _saltLengthBytes) return decoded;
      }
      final salt = _generateSalt();
      await box.put(_saltKey, base64Encode(salt));
      return salt;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'salt box 不可用，回退到确定性 salt');
      return Uint8List.fromList(
        sha256.convert(utf8.encode('${Platform.localHostname}|salt-v2')).bytes,
      );
    }
  }

  static Future<Box<String>> _getSaltBox() async {
    final box = _saltBox;
    if (box != null && box.isOpen) return box;
    return _saltBoxInit ??= _openSaltBox();
  }

  static Future<Box<String>> _openSaltBox() async {
    try {
      final box = await Hive.openBox<String>(_saltBoxName);
      _saltBox = box;
      return box;
    } finally {
      _saltBoxInit = null;
    }
  }

  static Uint8List _generateSalt() {
    final random = Random.secure();
    final bytes = Uint8List(_saltLengthBytes);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  /// 打开降级 box，必要时从 v1 key 迁移
  ///
  /// 先用 v2 key 打开；失败说明 box 是用 v1 key 加密的，改用
  /// [legacyMaterial] 派生的旧 key 读出全部条目，再用 v2 key 重写。
  /// 迁移失败时删除旧 box 重新开（凭证可通过重新登录恢复）。
  static Future<Box<String>> openBox(
    String boxName, {
    required String domain,
    required String legacyMaterial,
  }) async {
    final key = await derive(domain);
    try {
      return await Hive.openBox<String>(
        boxName,
        encryptionCipher: HiveAesCipher(key),
      );
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'v2 key 打开 $boxName 失败，尝试从 v1 迁移');
      return _migrateFromLegacy(boxName, key, legacyMaterial);
    }
  }

  static Future<Box<String>> _migrateFromLegacy(
    String boxName,
    List<int> newKey,
    String legacyMaterial,
  ) async {
    Map<String, String>? salvaged;
    try {
      final legacy = await Hive.openBox<String>(
        boxName,
        encryptionCipher: HiveAesCipher(deriveLegacy(legacyMaterial)),
      );
      salvaged = {
        for (final k in legacy.keys)
          if (legacy.get(k) case final String v) '$k': v,
      };
      await legacy.deleteFromDisk();
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'fallbackBoxKey.migrate', {'box': boxName});
      try {
        await Hive.deleteBoxFromDisk(boxName);
      } on Exception catch (e2, st2) {
        AppError.ignore(e2, st2, '删除损坏的 $boxName 失败');
      }
    }

    final box = await Hive.openBox<String>(
      boxName,
      encryptionCipher: HiveAesCipher(newKey),
    );
    if (salvaged != null && salvaged.isNotEmpty) {
      await box.putAll(salvaged);
    }
    return box;
  }
}
