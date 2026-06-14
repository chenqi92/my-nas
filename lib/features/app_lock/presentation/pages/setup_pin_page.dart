import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/features/app_lock/presentation/providers/app_lock_provider.dart';
import 'package:my_nas/features/app_lock/presentation/widgets/pin_keypad.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

/// 设置 PIN（首次启用应用锁）整页形态。
///
/// 流程：输入 → 确认 → 可选启用生物识别 → 完成。内容与状态逻辑封装在
/// [PinSetupView]，桌面端可改用弹窗承载（见 `SecurityPane`），移动端走本整页。
class SetupPinPage extends StatelessWidget {
  const SetupPinPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      appBar: AppBar(
        leading: const RoundedBackButton(),
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(l.appLockSetupTitle),
      ),
      body: SafeArea(
        child: PinSetupView(
          fillHeight: true,
          onCompleted: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}

/// PIN 设置内容（输入 → 确认 → 可选生物识别），可嵌入整页或弹窗。
///
/// 成功保存并启用应用锁后回调 [onCompleted]（由宿主决定关闭整页或弹窗）。
/// [fillHeight] 为 true 时键盘吸底（整页用），false 时内容自适应高度（弹窗用）。
class PinSetupView extends ConsumerStatefulWidget {
  const PinSetupView({
    this.onCompleted,
    this.fillHeight = false,
    super.key,
  });

  final VoidCallback? onCompleted;
  final bool fillHeight;

  @override
  ConsumerState<PinSetupView> createState() => _PinSetupViewState();
}

enum _SetupStep { enterPin, confirmPin }

class _PinSetupViewState extends ConsumerState<PinSetupView> {
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
    widget.onCompleted?.call();
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
    final muted = isDark
        ? AppColors.darkOnSurfaceVariant
        : AppColors.lightOnSurfaceVariant;
    final title = _step == _SetupStep.enterPin
        ? l.appLockSetupTitle
        : l.appLockSetupConfirmTitle;
    final subtitle = _step == _SetupStep.enterPin
        ? l.appLockSetupSubtitle
        : l.appLockSetupConfirmSubtitle;

    final children = <Widget>[
      const SizedBox(height: AppSpacing.xl),
      // 弹窗形态无 AppBar，标题在内容里展示；整页形态标题在 AppBar，避免重复。
      if (!widget.fillHeight) ...[
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      Text(
        subtitle,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: muted),
      ),
      const SizedBox(height: AppSpacing.xl),
      PinDots(
        length: _currentInput.length,
        maxLength: _maxLength,
        error: _mismatchError,
      ),
      if (widget.fillHeight)
        const Spacer()
      else
        const SizedBox(height: AppSpacing.xl),
      PinKeypad(onDigit: _onDigit, onDelete: _onDelete),
      const SizedBox(height: AppSpacing.xl),
    ];

    return Column(
      mainAxisSize: widget.fillHeight ? MainAxisSize.max : MainAxisSize.min,
      children: children,
    );
  }
}
