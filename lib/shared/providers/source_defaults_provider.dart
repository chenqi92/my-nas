import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/network/http_client.dart';
import 'package:my_nas/core/utils/hive_utils.dart';

/// 数据源相关的全局设置（持久化于 settings box）。
///
/// 三项独立持久化，默认值均与现状行为一致：
/// - 信任自签名证书：默认 true（历史上网络层恒放行自签名证书）。
/// - 新建源默认「自动连接」：默认 true（[SourceEntity.autoConnect] 默认即 true）。
/// - 新建源默认「记住 2FA 设备」：默认 false（[SourceEntity.rememberDevice] 默认即 false）。
///
/// 模式参考 [dynamicAmbientProvider] / glass_material_provider。

/// 信任 HTTPS 自签名证书（默认 true=保持现状）。
///
/// 写入时同步更新 [InsecureHttpClient.trustSelfSigned]（网络层在
/// badCertificateCallback 里同步读取该静态值），使开关实时生效，无需重建客户端。
final trustSelfSignedCertProvider =
    StateNotifierProvider<TrustSelfSignedCertNotifier, bool>(
  (ref) => TrustSelfSignedCertNotifier(),
);

class TrustSelfSignedCertNotifier extends StateNotifier<bool> {
  TrustSelfSignedCertNotifier() : super(InsecureHttpClient.trustSelfSigned) {
    _load();
  }

  static const _key = 'trust_self_signed_cert';

  Future<void> _load() async {
    try {
      final box = await HiveUtils.getSettingsBox();
      final v = box.get(_key) as bool?;
      if (v != null) {
        state = v;
        InsecureHttpClient.trustSelfSigned = v;
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载信任自签名证书设置失败，使用默认值');
    }
  }

  Future<void> setEnabled({required bool enabled}) async {
    state = enabled;
    InsecureHttpClient.trustSelfSigned = enabled;
    try {
      final box = await HiveUtils.getSettingsBox();
      await box.put(_key, enabled);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '保存信任自签名证书设置失败');
    }
  }
}

/// 新建源默认「启动时自动连接」（默认 true）。仅作为新建源时的初始值，
/// 不影响已存在的源（各源仍按自身字段配置）。
final defaultAutoConnectProvider =
    StateNotifierProvider<_BoolSettingNotifier, bool>(
  (ref) => _BoolSettingNotifier(
    key: 'source_default_auto_connect',
    defaultValue: true,
    failHint: '新建源默认自动连接',
  ),
);

/// 新建源默认「记住 2FA 设备」（默认 false）。仅作为新建源时的初始值，
/// 不影响已存在的源（各源仍按自身字段配置）。
final defaultRememberDeviceProvider =
    StateNotifierProvider<_BoolSettingNotifier, bool>(
  (ref) => _BoolSettingNotifier(
    key: 'source_default_remember_device',
    defaultValue: false,
    failHint: '新建源默认记住 2FA 设备',
  ),
);

class _BoolSettingNotifier extends StateNotifier<bool> {
  _BoolSettingNotifier({
    required this.key,
    required bool defaultValue,
    required this.failHint,
  }) : super(defaultValue) {
    _load();
  }

  final String key;
  final String failHint;

  Future<void> _load() async {
    try {
      final box = await HiveUtils.getSettingsBox();
      final v = box.get(key) as bool?;
      if (v != null) state = v;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载$failHint设置失败，使用默认值');
    }
  }

  Future<void> setEnabled({required bool enabled}) async {
    state = enabled;
    try {
      final box = await HiveUtils.getSettingsBox();
      await box.put(key, enabled);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '保存$failHint设置失败');
    }
  }
}
