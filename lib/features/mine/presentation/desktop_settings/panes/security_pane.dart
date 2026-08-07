import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/app_lock/domain/app_lock_settings.dart';
import 'package:my_nas/features/app_lock/presentation/pages/setup_pin_page.dart';
import 'package:my_nas/features/app_lock/presentation/providers/app_lock_provider.dart';
import 'package:my_nas/features/app_lock/presentation/widgets/app_lock_gate.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
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
        SetHead(
          icon: Icons.shield_outlined,
          title: l.paneSecurityHeadTitle,
          subtitle: l.paneSecurityHeadSubtitle,
        ),
        SetSection(
          title: l.paneSecuritySectionAppLock,
          hint: 'app_lock_settings',
          children: [
            SetRow(
              title: l.paneSecurityEnableTitle,
              desc: l.paneSecurityEnableDesc,
              last: !settings.enabled,
              trailing: AppSwitch(
                value: settings.enabled,
                onChanged: (v) => _onToggleEnabled(value: v),
              ),
            ),
            if (settings.enabled)
              SetRow(
                title: l.paneSecurityPinTitle,
                desc: l.paneSecurityPinDesc,
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
                      label: l.paneSecurityChangePin,
                      icon: Icons.password_rounded,
                      dense: true,
                      onPressed: _onChangePin,
                    ),
                  ],
                ),
              ),
            if (settings.enabled && _biometricAvailable)
              SetRow(
                title: l.paneSecurityBiometricTitle,
                desc: l.paneSecurityBiometricDesc,
                trailing: AppSwitch(
                  value: settings.biometricEnabled,
                  onChanged: (v) => ref
                      .read(appLockProvider.notifier)
                      .setBiometricEnabled(value: v),
                ),
              ),
            if (settings.enabled)
              SetRow(
                title: l.paneSecurityAutoLockTitle,
                desc: l.paneSecurityAutoLockDesc,
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
        // 应用切换器遮蔽依赖 secure_application，仅在支持的平台
        // （iOS / Android / Windows）渲染；macOS / Linux 不支持则整段不显示。
        if (AppLockGate.supportsSecureApplication)
          SetSection(
            title: l.paneSecuritySectionPrivacy,
            children: [
              SetRow(
                title: l.paneSecurityAppSwitcherMaskTitle,
                desc: l.paneSecurityAppSwitcherMaskDesc,
                last: true,
                trailing: _appSwitcherMaskTrailing(l, settings.enabled),
              ),
            ],
          ),
      ],
    );
  }

  /// 应用切换器遮蔽随应用锁自动开启（无独立开关）：
  /// 在支持的平台（iOS / Android / Windows）下，启用应用锁即生效。
  Widget _appSwitcherMaskTrailing(AppLocalizations l, bool lockEnabled) => AppTag(
    lockEnabled
        ? l.paneSecurityAppSwitcherMaskOn
        : l.paneSecurityAppSwitcherMaskOff,
    variant: lockEnabled ? TagVariant.free : TagVariant.limit,
  );

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
      // 启用 → 桌面弹窗里设置 PIN（实际启用在 PinSetupView 内完成）
      await _openPinSetup();
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
    await _openPinSetup();
  }

  /// 桌面端用居中弹窗承载 PIN 设置（对齐设计稿 `openSheet("changePin")`），
  /// 替代旧的整页跳转。设置成功后由 [PinSetupView] 回调关闭弹窗。
  Future<void> _openPinSetup() async {
    await showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SingleChildScrollView(
            child: PinSetupView(
              onCompleted: () => Navigator.of(sheetCtx).pop(),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _verifyCurrentPin() async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    try {
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
    } finally {
      controller.dispose();
    }
  }
}
