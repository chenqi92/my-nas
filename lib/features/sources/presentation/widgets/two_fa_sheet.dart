import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

/// 二次验证弹框结果类型
enum TwoFAResultType {
  /// 验证成功
  verified,
  /// 用户取消验证
  cancelled,
  /// 用户选择跳过验证，先保存源
  skipped,
}

/// 二次验证弹框结果
class TwoFAResult {
  const TwoFAResult({
    required this.otpCode,
    required this.rememberDevice,
    this.resultType = TwoFAResultType.verified,
  });

  final String otpCode;
  final bool rememberDevice;
  final TwoFAResultType resultType;
}

/// 显示二次验证底部弹框
///
/// 返回 [TwoFAResult]，如果用户取消则返回 null
Future<TwoFAResult?> showTwoFASheet(
  BuildContext context, {
  bool initialRememberDevice = true, // 默认记住设备
  String? sourceName,
}) async => showAdaptiveModalSheet<TwoFAResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: false,
    enableDrag: true,
    builder: (context) => _TwoFASheet(
      initialRememberDevice: initialRememberDevice,
      sourceName: sourceName,
    ),
  );

/// 显示带在线验证功能的二次验证底部弹框
///
/// [onVerify] 回调用于验证OTP码，返回 true 表示验证成功，false 表示失败
/// [allowSkip] 如果为 true，允许用户跳过验证先保存源
///
/// 返回 [TwoFAResult]：
/// - resultType == verified: 验证成功
/// - resultType == skipped: 用户选择跳过验证
/// - null: 用户取消
Future<TwoFAResult?> showTwoFASheetWithVerify(
  BuildContext context, {
  required Future<bool> Function(String otpCode, bool rememberDevice) onVerify,
  bool initialRememberDevice = true,
  String? sourceName,
  bool allowSkip = true,
}) async => showAdaptiveModalSheet<TwoFAResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: false,
    enableDrag: true,
    builder: (context) => _TwoFASheetWithVerify(
      onVerify: onVerify,
      initialRememberDevice: initialRememberDevice,
      sourceName: sourceName,
      allowSkip: allowSkip,
    ),
  );

class _TwoFASheet extends StatefulWidget {
  const _TwoFASheet({
    this.initialRememberDevice = true, // 默认记住设备
    this.sourceName,
  });

  final bool initialRememberDevice;
  final String? sourceName;

  @override
  State<_TwoFASheet> createState() => _TwoFASheetState();
}

class _TwoFASheetState extends State<_TwoFASheet> with SingleTickerProviderStateMixin {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  late bool _rememberDevice;
  bool _hasError = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _rememberDevice = widget.initialRememberDevice;
    _controllers = List.generate(6, (_) => TextEditingController());
    _focusNodes = List.generate(6, (_) => FocusNode());

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    );
    _animationController.forward();

    // 自动聚焦第一个输入框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    _animationController.dispose();
    super.dispose();
  }

  String get _otpCode => _controllers.map((c) => c.text).join();

  void _onCodeChanged(int index, String value) {
    if (_hasError) {
      setState(() => _hasError = false);
    }

    if (value.length == 1 && index < 5) {
      // 移动到下一个输入框
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      // 删除时移动到上一个输入框
      _focusNodes[index - 1].requestFocus();
    }

    // 检查是否完成
    if (_otpCode.length == 6) {
      _submit();
    }
  }

  void _onKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_controllers[index].text.isEmpty && index > 0) {
        _focusNodes[index - 1].requestFocus();
        _controllers[index - 1].clear();
      }
    }
  }

  void _submit() {
    final code = _otpCode;
    if (code.length != 6) {
      setState(() => _hasError = true);
      HapticFeedback.heavyImpact();
      return;
    }
    Navigator.pop(
      context,
      TwoFAResult(
        otpCode: code,
        rememberDevice: _rememberDevice,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: DraggableScrollableSheet(
        initialChildSize: 0.58,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        builder: (context, scrollController) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkSurface.withValues(alpha: 0.95)
                    : Colors.white.withValues(alpha: 0.95),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(
                  color: isDark
                      ? AppColors.darkOutline.withValues(alpha: 0.2)
                      : AppColors.lightOutline.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  // 拖动指示器
                  const SheetDragHandle(),
                  // 内容
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      children: [
                        // 安全图标
                        Center(
                          child: ScaleTransition(
                            scale: _scaleAnimation,
                            child: Container(
                              width: 80,
                              height: 80,
                              margin: const EdgeInsets.only(bottom: 20),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppColors.accent,
                                    AppColors.accent.withValues(alpha: 0.7),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.accent.withValues(alpha: 0.3),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.shield_rounded,
                                size: 40,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        // 标题
                        Text(
                          '二次验证',
                          style: context.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        // 副标题
                        Text(
                          widget.sourceName != null
                              ? '正在连接「${widget.sourceName}」\n请输入验证器应用中的验证码'
                              : '请输入验证器应用中的验证码',
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        // 记住设备选项 - 移到验证码输入框之前，紧凑样式
                        GestureDetector(
                          onTap: () => setState(() => _rememberDevice = !_rememberDevice),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: _rememberDevice
                                  ? AppColors.accent.withValues(alpha: 0.1)
                                  : (isDark
                                      ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
                                      : AppColors.lightSurfaceVariant.withValues(alpha: 0.3)),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _rememberDevice
                                    ? AppColors.accent.withValues(alpha: 0.5)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _rememberDevice ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                  size: 20,
                                  color: _rememberDevice
                                      ? AppColors.accent
                                      : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '记住此设备',
                                  style: context.textTheme.bodyMedium?.copyWith(
                                    color: _rememberDevice
                                        ? AppColors.accent
                                        : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
                                    fontWeight: _rememberDevice ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // PIN 码输入框
                        _buildPinCodeFields(isDark),
                        if (_hasError) ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                '请输入完整的 6 位验证码',
                                style: context.textTheme.bodySmall?.copyWith(color: AppColors.error),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 24),
                        // 验证按钮
                        FilledButton(
                          onPressed: _submit,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            backgroundColor: AppColors.accent,
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.verified_user_rounded, size: 20),
                              SizedBox(width: 8),
                              Text(
                                '验证',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 取消按钮
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                          child: Text(
                            '取消',
                            style: TextStyle(
                              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                            ),
                          ),
                        ),
                        // 底部安全区域
                        SizedBox(height: MediaQuery.of(context).padding.bottom),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPinCodeFields(bool isDark) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) => Container(
          width: 48,
          height: 56,
          margin: EdgeInsets.only(
            left: index == 0 ? 0 : 8,
            right: index == 2 ? 8 : 0, // 在第3位后加点间距
          ),
          child: KeyboardListener(
            focusNode: FocusNode(),
            onKeyEvent: (event) => _onKeyEvent(index, event),
            child: TextField(
              controller: _controllers[index],
              focusNode: _focusNodes[index],
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 1,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: _focusNodes[index].hasFocus
                    ? (isDark
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.primary.withValues(alpha: 0.08))
                    : (isDark
                        ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
                        : AppColors.lightSurfaceVariant.withValues(alpha: 0.5)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: _hasError
                        ? AppColors.error
                        : (isDark
                            ? AppColors.darkOutline.withValues(alpha: 0.3)
                            : AppColors.lightOutline.withValues(alpha: 0.3)),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: _hasError ? AppColors.error : AppColors.primary,
                    width: 2,
                  ),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(1),
              ],
              onChanged: (value) => _onCodeChanged(index, value),
            ),
          ),
        )),
    );
}

/// 带在线验证功能的二次验证弹框
class _TwoFASheetWithVerify extends StatefulWidget {
  const _TwoFASheetWithVerify({
    required this.onVerify,
    this.initialRememberDevice = true,
    this.sourceName,
    this.allowSkip = true,
  });

  final Future<bool> Function(String otpCode, bool rememberDevice) onVerify;
  final bool initialRememberDevice;
  final String? sourceName;
  final bool allowSkip;

  @override
  State<_TwoFASheetWithVerify> createState() => _TwoFASheetWithVerifyState();
}

class _TwoFASheetWithVerifyState extends State<_TwoFASheetWithVerify>
    with SingleTickerProviderStateMixin {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  late bool _rememberDevice;
  bool _hasError = false;
  bool _isVerifying = false;
  String? _errorMessage;

  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _rememberDevice = widget.initialRememberDevice;
    _controllers = List.generate(6, (_) => TextEditingController());
    _focusNodes = List.generate(6, (_) => FocusNode());

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    );
    // 抖动动画
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _animationController.forward();

    // 自动聚焦第一个输入框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    _animationController.dispose();
    super.dispose();
  }

  String get _otpCode => _controllers.map((c) => c.text).join();

  void _onCodeChanged(int index, String value) {
    if (_hasError) {
      setState(() {
        _hasError = false;
        _errorMessage = null;
      });
    }

    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    // 检查是否完成
    if (_otpCode.length == 6) {
      _submit();
    }
  }

  void _onKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_controllers[index].text.isEmpty && index > 0) {
        _focusNodes[index - 1].requestFocus();
        _controllers[index - 1].clear();
      }
    }
  }

  Future<void> _submit() async {
    final code = _otpCode;
    if (code.length != 6) {
      _showError('请输入完整的 6 位验证码');
      return;
    }

    setState(() {
      _isVerifying = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      final success = await widget.onVerify(code, _rememberDevice);
      if (!mounted) return;

      if (success) {
        Navigator.pop(
          context,
          TwoFAResult(
            otpCode: code,
            rememberDevice: _rememberDevice,
            resultType: TwoFAResultType.verified,
          ),
        );
      } else {
        _showError('验证码错误，请重新输入');
        _clearAndShake();
      }
    } on Exception catch (e) {
      if (!mounted) return;
      _showError('验证失败: $e');
      _clearAndShake();
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  void _showError(String message) {
    setState(() {
      _hasError = true;
      _errorMessage = message;
    });
    HapticFeedback.heavyImpact();
  }

  void _clearAndShake() {
    // 清空所有输入框
    for (final controller in _controllers) {
      controller.clear();
    }
    // 重置动画并播放抖动
    _animationController
      ..reset()
      ..forward();
    // 聚焦第一个输入框
    _focusNodes[0].requestFocus();
  }

  void _handleCancel() {
    if (widget.allowSkip) {
      // 显示确认对话框
      showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('取消验证'),
          content: const Text('您可以选择先保存连接源，之后再进行二次验证。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('返回验证'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('先保存'),
            ),
          ],
        ),
      ).then((skip) {
        if ((skip ?? false) && mounted) {
          Navigator.pop(
            context,
            TwoFAResult(
              otpCode: '',
              rememberDevice: _rememberDevice,
              resultType: TwoFAResultType.skipped,
            ),
          );
        }
      });
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: DraggableScrollableSheet(
        initialChildSize: 0.58,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        builder: (context, scrollController) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkSurface.withValues(alpha: 0.95)
                    : Colors.white.withValues(alpha: 0.95),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(
                  color: isDark
                      ? AppColors.darkOutline.withValues(alpha: 0.2)
                      : AppColors.lightOutline.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  // 拖动指示器
                  const SheetDragHandle(),
                  // 内容
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      children: [
                        // 安全图标
                        Center(
                          child: ScaleTransition(
                            scale: _scaleAnimation,
                            child: Container(
                              width: 80,
                              height: 80,
                              margin: const EdgeInsets.only(bottom: 20),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppColors.accent,
                                    AppColors.accent.withValues(alpha: 0.7),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        AppColors.accent.withValues(alpha: 0.3),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.shield_rounded,
                                size: 40,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        // 标题
                        Text(
                          '二次验证',
                          style: context.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? AppColors.darkOnSurface
                                : AppColors.lightOnSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        // 副标题
                        Text(
                          widget.sourceName != null
                              ? '正在连接「${widget.sourceName}」\n请输入验证器应用中的验证码'
                              : '请输入验证器应用中的验证码',
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        // 记住设备选项
                        GestureDetector(
                          onTap: () => setState(
                              () => _rememberDevice = !_rememberDevice),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: _rememberDevice
                                  ? AppColors.accent.withValues(alpha: 0.1)
                                  : (isDark
                                      ? AppColors.darkSurfaceVariant
                                          .withValues(alpha: 0.3)
                                      : AppColors.lightSurfaceVariant
                                          .withValues(alpha: 0.3)),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _rememberDevice
                                    ? AppColors.accent.withValues(alpha: 0.5)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _rememberDevice
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  size: 20,
                                  color: _rememberDevice
                                      ? AppColors.accent
                                      : (isDark
                                          ? AppColors.darkOnSurfaceVariant
                                          : AppColors.lightOnSurfaceVariant),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '记住此设备',
                                  style: context.textTheme.bodyMedium?.copyWith(
                                    color: _rememberDevice
                                        ? AppColors.accent
                                        : (isDark
                                            ? AppColors.darkOnSurfaceVariant
                                            : AppColors.lightOnSurfaceVariant),
                                    fontWeight: _rememberDevice
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // PIN 码输入框 - 带抖动动画
                        AnimatedBuilder(
                          animation: _shakeAnimation,
                          builder: (context, child) => Transform.translate(
                            offset: Offset(_hasError ? _shakeAnimation.value : 0, 0),
                            child: child,
                          ),
                          child: _buildPinCodeFields(isDark),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline_rounded,
                                  color: AppColors.error, size: 16),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  _errorMessage!,
                                  style: context.textTheme.bodySmall
                                      ?.copyWith(color: AppColors.error),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 24),
                        // 验证按钮
                        FilledButton(
                          onPressed: _isVerifying ? null : _submit,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            backgroundColor: AppColors.accent,
                          ),
                          child: _isVerifying
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.verified_user_rounded, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      '验证',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 12),
                        // 取消按钮
                        TextButton(
                          onPressed: _isVerifying ? null : _handleCancel,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                          child: Text(
                            widget.allowSkip ? '稍后验证' : '取消',
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.darkOnSurfaceVariant
                                  : AppColors.lightOnSurfaceVariant,
                            ),
                          ),
                        ),
                        // 底部安全区域
                        SizedBox(
                            height: MediaQuery.of(context).padding.bottom),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPinCodeFields(bool isDark) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          6,
          (index) => Container(
            width: 48,
            height: 56,
            margin: EdgeInsets.only(
              left: index == 0 ? 0 : 8,
              right: index == 2 ? 8 : 0,
            ),
            child: KeyboardListener(
              focusNode: FocusNode(),
              onKeyEvent: (event) => _onKeyEvent(index, event),
              child: TextField(
                controller: _controllers[index],
                focusNode: _focusNodes[index],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 1,
                enabled: !_isVerifying,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? AppColors.darkOnSurface
                      : AppColors.lightOnSurface,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: _focusNodes[index].hasFocus
                      ? (isDark
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : AppColors.primary.withValues(alpha: 0.08))
                      : (isDark
                          ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
                          : AppColors.lightSurfaceVariant
                              .withValues(alpha: 0.5)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _hasError
                          ? AppColors.error
                          : (isDark
                              ? AppColors.darkOutline.withValues(alpha: 0.3)
                              : AppColors.lightOutline.withValues(alpha: 0.3)),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _hasError ? AppColors.error : AppColors.primary,
                      width: 2,
                    ),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(1),
                ],
                onChanged: (value) => _onCodeChanged(index, value),
              ),
            ),
          ),
        ),
      );
}
