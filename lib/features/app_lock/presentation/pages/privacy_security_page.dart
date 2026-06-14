import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/app_lock/domain/app_lock_settings.dart';
import 'package:my_nas/features/app_lock/presentation/pages/setup_pin_page.dart';
import 'package:my_nas/features/app_lock/presentation/providers/app_lock_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

class PrivacySecurityPage extends ConsumerStatefulWidget {
  const PrivacySecurityPage({super.key});

  @override
  ConsumerState<PrivacySecurityPage> createState() =>
      _PrivacySecurityPageState();
}

class _PrivacySecurityPageState extends ConsumerState<PrivacySecurityPage> {
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final ok = await ref
        .read(appLockProvider.notifier)
        .isBiometricAvailable();
    if (mounted) setState(() => _biometricAvailable = ok);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(appLockProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = state.settings;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      appBar: AppBar(
        leading: const RoundedBackButton(),
        title: Text(l.appLockSettingsTitle),
      ),
      body: context.isDesktopLayout
          ? _buildDesktopBody(context, l, settings)
          : ListView(
        padding: AppSpacing.paddingMd,
        children: [
          _SectionCard(
            isDark: isDark,
            children: [
              SwitchListTile(
                title: Text(l.appLockEnable),
                subtitle: Text(l.appLockEnableDescription),
                value: settings.enabled,
                onChanged: (v) => _onToggleEnabled(value: v),
              ),
            ],
          ),
          if (settings.enabled) ...[
            const SizedBox(height: AppSpacing.lg),
            _SectionCard(
              isDark: isDark,
              children: [
                ListTile(
                  leading: const Icon(Icons.pin_rounded),
                  title: Text(l.appLockChangePin),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _onChangePin,
                ),
                if (_biometricAvailable)
                  SwitchListTile(
                    secondary: const Icon(Icons.fingerprint_rounded),
                    title: Text(l.appLockBiometricToggle),
                    value: settings.biometricEnabled,
                    onChanged: (v) => ref
                        .read(appLockProvider.notifier)
                        .setBiometricEnabled(value: v),
                  )
                else
                  ListTile(
                    leading: const Icon(Icons.fingerprint_rounded),
                    title: Text(l.appLockBiometricToggle),
                    subtitle: Text(l.appLockBiometricUnavailable),
                    enabled: false,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _SectionCard(
              isDark: isDark,
              children: [
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: Text(l.appLockTimeoutTitle),
                  subtitle: Text(_timeoutLabel(l, settings.timeout)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _onPickTimeout,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDesktopBody(
    BuildContext context,
    AppLocalizations l,
    AppLockSettings settings,
  ) {
    final t = DesignTokens.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(38, 32, 38, 96),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(
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
            ],
          ),
        ),
      ),
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

  Future<void> _onPickTimeout() async {
    final l = AppLocalizations.of(context);
    final current = ref.read(appLockProvider).settings.timeout;
    final picked = await showAdaptiveModalSheet<AppLockTimeout>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in AppLockTimeout.values)
              ListTile(
                title: Text(_timeoutLabel(l, t)),
                trailing: t == current
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(ctx).pop(t),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await ref.read(appLockProvider.notifier).setTimeout(picked);
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children, required this.isDark});

  final List<Widget> children;
  final bool isDark;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: isDark
          ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
          : AppColors.lightSurface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: isDark
            ? AppColors.darkOutline.withValues(alpha: 0.2)
            : AppColors.lightOutline.withValues(alpha: 0.3),
      ),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Column(children: children),
    ),
  );
}
