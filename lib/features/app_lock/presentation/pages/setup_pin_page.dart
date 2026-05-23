import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/features/app_lock/presentation/providers/app_lock_provider.dart';
import 'package:my_nas/features/app_lock/presentation/widgets/pin_keypad.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

/// 设置 PIN（首次启用应用锁）
///
/// 流程：输入 → 确认 → 可选启用生物识别 → 完成
class SetupPinPage extends ConsumerStatefulWidget {
  const SetupPinPage({super.key});

  @override
  ConsumerState<SetupPinPage> createState() => _SetupPinPageState();
}

enum _SetupStep { enterPin, confirmPin }

class _SetupPinPageState extends ConsumerState<SetupPinPage> {
  static const _minLength = 4;
  static const _maxLength = 6;

  _SetupStep _step = _SetupStep.enterPin;
  String _firstPin = '';
  String _currentInput = '';
  bool _mismatchError = false;

  void _onDigit(int d) {
    if (_currentInput.length >= _maxLength) return;
    setState(() {
      _currentInput += d.toString();
      _mismatchError = false;
    });
    if (_currentInput.length >= _minLength) {
      // 输够最小长度后不自动提交；用户可以继续输入直到 6 位或手动确认。
      // 等待 800ms 后如果还停在当前长度则视为确认。
      unawaited(_maybeAutoCommit(_currentInput.length));
    }
  }

  void _onDelete() {
    if (_currentInput.isEmpty) return;
    setState(() {
      _currentInput = _currentInput.substring(0, _currentInput.length - 1);
      _mismatchError = false;
    });
  }

  Future<void> _maybeAutoCommit(int snapshotLength) async {
    if (snapshotLength == _maxLength) {
      unawaited(_commit());
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    if (_currentInput.length == snapshotLength &&
        _currentInput.length >= _minLength) {
      unawaited(_commit());
    }
  }

  Future<void> _commit() async {
    final l = AppLocalizations.of(context);
    if (_step == _SetupStep.enterPin) {
      _firstPin = _currentInput;
      setState(() {
        _step = _SetupStep.confirmPin;
        _currentInput = '';
      });
      return;
    }

    // confirmPin
    if (_currentInput != _firstPin) {
      _firstPin = '';
      setState(() {
        _mismatchError = true;
        _currentInput = '';
        _step = _SetupStep.enterPin;
      });
      _showSnack(l.appLockSetupMismatch);
      return;
    }

    final notifier = ref.read(appLockProvider.notifier);
    final ok = await notifier.savePin(_firstPin);
    if (!mounted) return;
    if (!ok) {
      _showSnack(l.appLockSetupMismatch);
      return;
    }

    final biometricAvailable = await notifier.isBiometricAvailable();
    if (!mounted) return;

    var enableBiometric = false;
    if (biometricAvailable) {
      enableBiometric = await _askBiometric() ?? false;
    }
    if (!mounted) return;

    await notifier.enableLock(biometricEnabled: enableBiometric);
    if (!mounted) return;

    _showSnack(l.appLockSetupSuccess);
    Navigator.of(context).pop();
  }

  Future<bool?> _askBiometric() {
    final l = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l.appLockSetupAskBiometric),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.appLockSetupBiometricSkip),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.appLockSetupBiometricEnable),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = _step == _SetupStep.enterPin
        ? l.appLockSetupTitle
        : l.appLockSetupConfirmTitle;
    final subtitle = _step == _SetupStep.enterPin
        ? l.appLockSetupSubtitle
        : l.appLockSetupConfirmSubtitle;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      appBar: AppBar(
        leading: const RoundedBackButton(),
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(title),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.xl),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            PinDots(
              length: _currentInput.length,
              maxLength: _maxLength,
              error: _mismatchError,
            ),
            const Spacer(),
            PinKeypad(
              onDigit: _onDigit,
              onDelete: _onDelete,
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}
