import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/app_lock/domain/app_lock_settings.dart';
import 'package:my_nas/features/app_lock/presentation/pages/setup_pin_page.dart';
import 'package:my_nas/features/app_lock/presentation/providers/app_lock_provider.dart';
import 'package:my_nas/features/app_lock/presentation/widgets/app_lock_gate.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';

/// 桌面「设置 / 隐私与安全」详情 pane。
///
/// 迁移自 `PrivacySecurityPage._buildDesktopBody`：应用锁开关、PIN、
/// 生物识别与自动锁定均直接读写 [appLockProvider]；「修改 PIN」打开
/// 现有的 [SetupPinPage]。
class SecurityPane extends ConsumerStatefulWidget {
  const SecurityPane({super.key});

  @override
  ConsumerState<SecurityPane> createState() => _SecurityPaneState();
}

class _SecurityPaneState extends ConsumerState<SecurityPane> {
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final ok = await ref.read(appLockProvider.notifier).isBiometricAvailable();
    if (mounted) setState(() => _biometricAvailable = ok);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final settings = ref.watch(appLockProvider).settings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SetHead(
          icon: Icons.shield_outlined,
          title: '隐私与安全',
          subtitle:
              '应用锁、PIN、生物识别与自动锁定。凭据通过系统安全存储；失败时静默降级，不阻塞使用。',
        ),
        SetSection(
          title: '应用锁',
          hint: 'app_lock_settings',
          children: [
            SetRow(
              title: '启用应用锁',
              desc: '启动与从后台恢复时要求验证',
              last: !settings.enabled,
              trailing: AppSwitch(
                value: settings.enabled,
                onChanged: (v) => _onToggleEnabled(value: v),
              ),
            ),
            if (settings.enabled)
              SetRow(
                title: 'PIN 码',
                desc: '4–6 位数字',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 4; i++) ...[
                      if (i > 0) const SizedBox(width: 9),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: t.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                    const SizedBox(width: 12),
                    AppButton(
                      label: '修改 PIN',
                      icon: Icons.password_rounded,
                      dense: true,
                      onPressed: _onChangePin,
                    ),
                  ],
                ),
              ),
            if (settings.enabled && _biometricAvailable)
              SetRow(
                title: '生物识别',
                desc: 'Face ID / Touch ID 解锁',
                trailing: AppSwitch(
                  value: settings.biometricEnabled,
                  onChanged: (v) => ref
                      .read(appLockProvider.notifier)
                      .setBiometricEnabled(value: v),
                ),
              ),
            if (settings.enabled)
              SetRow(
                title: '自动锁定',
                desc: '闲置超时后自动上锁',
                last: true,
                trailing: AppSegmented<AppLockTimeout>(
                  options: [
                    for (final timeout in AppLockTimeout.values)
                      AppSegmentedOption(
                        value: timeout,
                        label: _timeoutLabel(l, timeout),
                      ),
                  ],
                  value: settings.timeout,
                  onChanged: (v) =>
                      ref.read(appLockProvider.notifier).setTimeout(v),
                ),
              ),
          ],
        ),
        SetSection(
          title: '隐私',
          children: [
            SetRow(
              title: '应用切换器遮蔽',
              desc: '切到后台时模糊窗口内容，防窥屏（LOCK-05）',
              last: true,
              trailing: _appSwitcherMaskTrailing(settings.enabled),
            ),
          ],
        ),
      ],
    );
  }

  /// 应用切换器遮蔽随应用锁自动开启（无独立开关）：
  /// - 支持的平台（iOS / Android / Windows）下，启用应用锁即生效。
  /// - 不支持的平台（macOS / Linux）显示「即将推出」。
  Widget _appSwitcherMaskTrailing(bool lockEnabled) {
    if (!AppLockGate.supportsSecureApplication) {
      return const AppTag('即将推出', variant: TagVariant.plan);
    }
    return AppTag(
      lockEnabled ? '随应用锁开启' : '已关闭',
      variant: lockEnabled ? TagVariant.free : TagVariant.limit,
    );
  }

  String _timeoutLabel(AppLocalizations l, AppLockTimeout t) => switch (t) {
    AppLockTimeout.immediate => l.appLockTimeoutImmediate,
    AppLockTimeout.oneMinute => l.appLockTimeoutMinutes(1),
    AppLockTimeout.fiveMinutes => l.appLockTimeoutMinutes(5),
    AppLockTimeout.fifteenMinutes => l.appLockTimeoutMinutes(15),
    AppLockTimeout.onlyOnExit => l.appLockTimeoutOnExit,
  };

  Future<void> _onToggleEnabled({required bool value}) async {
    final notifier = ref.read(appLockProvider.notifier);
    if (value) {
      // 启用 → 跳设置 PIN 页
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SetupPinPage()),
      );
    } else {
      // 关闭 → 需要验证当前 PIN
      final ok = await _verifyCurrentPin();
      if (!mounted) return;
      if (ok) await notifier.disableLock();
    }
  }

  Future<void> _onChangePin() async {
    final ok = await _verifyCurrentPin();
    if (!mounted) return;
    if (!ok) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SetupPinPage()),
    );
  }

  Future<bool> _verifyCurrentPin() async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.appLockUnlockTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(counterText: ''),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.appLockCancel),
          ),
          FilledButton(
            onPressed: () async {
              final ok = await ref
                  .read(appLockProvider.notifier)
                  .tryUnlockWithPin(controller.text);
              if (!ctx.mounted) return;
              if (ok) {
                Navigator.of(ctx).pop(true);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(l.appLockUnlockWrongPin)),
                );
              }
            },
            child: Text(l.appLockDone),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
