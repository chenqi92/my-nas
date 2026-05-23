import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/features/app_lock/presentation/providers/app_lock_provider.dart';
import 'package:my_nas/features/app_lock/presentation/widgets/pin_keypad.dart';
import 'package:my_nas/l10n/app_localizations.dart';

/// 解锁页（全屏遮罩）
///
/// 不允许 pop —— 用户必须通过 PIN / 生物识别解锁才能继续使用 App。
class UnlockPage extends ConsumerStatefulWidget {
  const UnlockPage({super.key, this.allowBiometricAutoTrigger = true});

  /// 进页时是否自动触发生物识别。设置流程中关闭应用锁时调 false
  final bool allowBiometricAutoTrigger;

  @override
  ConsumerState<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends ConsumerState<UnlockPage> {
  static const _maxLength = 6;
  String _input = '';
  bool _wrongPin = false;
  Timer? _countdownTicker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_maybeAutoTriggerBiometric());
    });
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    super.dispose();
  }

  Future<void> _maybeAutoTriggerBiometric() async {
    if (!widget.allowBiometricAutoTrigger) return;
    final state = ref.read(appLockProvider);
    if (!state.settings.biometricEnabled) return;
    await ref.read(appLockProvider.notifier).tryUnlockWithBiometric();
  }

  void _onDigit(int d) {
    final state = ref.read(appLockProvider);
    if (state.isLockedOut) return;
    if (_input.length >= _maxLength) return;
    setState(() {
      _input += d.toString();
      _wrongPin = false;
    });
    if (_input.length >= 4) {
      unawaited(_trySubmit());
    }
  }

  void _onDelete() {
    if (_input.isEmpty) return;
    setState(() {
      _input = _input.substring(0, _input.length - 1);
      _wrongPin = false;
    });
  }

  Future<void> _onBiometric() async {
    final ok = await ref
        .read(appLockProvider.notifier)
        .tryUnlockWithBiometric();
    if (!mounted) return;
    if (!ok) {
      await HapticFeedback.lightImpact();
    }
  }

  Future<void> _trySubmit() async {
    final pin = _input;
    final ok = await ref.read(appLockProvider.notifier).tryUnlockWithPin(pin);
    if (!mounted) return;
    if (!ok) {
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        _wrongPin = true;
        _input = '';
      });
    } else {
      setState(() => _input = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(appLockProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showBiometric = state.settings.biometricEnabled;
    final isLockedOut = state.isLockedOut;

    final subtitle = isLockedOut
        ? l.appLockUnlockLockedOut(state.lockoutRemaining.inSeconds)
        : _wrongPin
        ? l.appLockUnlockWrongPin
        : l.appLockUnlockTitle;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.xxxl),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.lock_rounded,
                  size: 32,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: _wrongPin || isLockedOut
                      ? AppColors.error
                      : (isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              PinDots(
                length: _input.length,
                maxLength: _maxLength,
                error: _wrongPin,
              ),
              const Spacer(),
              PinKeypad(
                onDigit: _onDigit,
                onDelete: _onDelete,
                onBiometric: showBiometric ? _onBiometric : null,
                disabled: isLockedOut,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
