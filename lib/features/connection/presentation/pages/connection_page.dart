import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/router/routes.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/connection/presentation/providers/connection_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';

class ConnectionPage extends ConsumerStatefulWidget {
  const ConnectionPage({super.key});

  @override
  ConsumerState<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends ConsumerState<ConnectionPage>
    with SingleTickerProviderStateMixin, ConsumerTabBarVisibilityMixin {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '5000');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();

  bool _obscurePassword = true;
  bool _useSsl = true;
  bool _rememberLogin = false;
  bool _rememberDevice = false;
  NasAdapterType _selectedType = NasAdapterType.synology;

  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    hideTabBar();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _handleConnect() async {
    if (!_formKey.currentState!.validate()) return;

    await ref.read(connectionStateProvider.notifier).connect(
          type: _selectedType,
          host: _hostController.text.trim(),
          port: int.parse(_portController.text.trim()),
          username: _usernameController.text.trim(),
          password: _passwordController.text,
          useSsl: _useSsl,
          verifySSL: false,
          rememberLogin: _rememberLogin,
          rememberDevice: _rememberDevice,
        );
  }

  Future<void> _handleVerify2FA() async {
    if (_otpController.text.isEmpty) return;
    await ref
        .read(connectionStateProvider.notifier)
        .verify2FA(_otpController.text.trim(), rememberDevice: _rememberDevice);
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionStateProvider);

    ref.listen<NasConnectionState>(connectionStateProvider, (previous, next) {
      if (next is ConnectionConnected) {
        context.go(Routes.files);
      } else if (next is ConnectionError) {
        context.showErrorSnackBar(next.message);
      }
    });

    return Scaffold(
      body: Stack(
        children: [
          // 动态渐变背景
          _buildAnimatedBackground(),
          // 主内容
          SafeArea(
            child: Center(
              child: ScrollConfiguration(
                behavior:
                    ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  padding: AppSpacing.screenPadding,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildLogo()
                            .animate()
                            .fadeIn(duration: 600.ms)
                            .slideY(begin: -0.2, end: 0),
                        const SizedBox(height: AppSpacing.xxxl),
                        if (connectionState is ConnectionRequires2FAState)
                          _build2FACard(connectionState)
                              .animate()
                              .fadeIn(duration: 400.ms)
                              .scale(begin: const Offset(0.95, 0.95))
                        else
                          _buildLoginCard(connectionState)
                              .animate()
                              .fadeIn(duration: 600.ms, delay: 200.ms)
                              .slideY(begin: 0.1, end: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBackground() => AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) => DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0F0F1A),
                Color(0xFF1A1A2E),
                Color(0xFF16213E),
                Color(0xFF0F0F1A),
              ],
              stops: [0.0, 0.3, 0.7, 1.0],
            ),
          ),
          child: Stack(
            children: [
              // 动态光晕效果
              Positioned(
                top: -100 + (50 * _animationController.value),
                right: -100,
                child: Container(
                  width: 400,
                  height: 400,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.primary.withValues(alpha: 0.3),
                        AppColors.primary.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -150 + (30 * _animationController.value),
                left: -100,
                child: Container(
                  width: 350,
                  height: 350,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.secondary.withValues(alpha: 0.25),
                        AppColors.secondary.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).size.height * 0.4,
                left: MediaQuery.of(context).size.width * 0.3,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.accent.withValues(alpha: 0.15),
                        AppColors.accent.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
    );

  Widget _buildLogo() => Column(
      children: [
        // 品牌图标
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.4),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Image.asset(
              'assets/logo.png',
              width: 100,
              height: 100,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        // 品牌名称
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [AppColors.primaryLight, AppColors.accentLight],
          ).createShader(bounds),
          child: Text(
            'MyNAS',
            style: context.textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 2,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          context.l10n.connPageTagline,
          style: context.textTheme.bodyLarge?.copyWith(
            color: AppColors.darkOnSurfaceVariant,
          ),
        ),
      ],
    );

  Widget _buildLoginCard(NasConnectionState state) {
    final isLoading = state is ConnectionLoading;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: AppColors.glassLight,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.glassStroke,
            ),
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // NAS 类型选择器
                _buildNasTypeSelector(),
                const SizedBox(height: AppSpacing.xl),

                // 主机地址
                _buildTextField(
                  controller: _hostController,
                  label: context.l10n.connPageHostLabel,
                  hint: context.l10n.connPageHostHint,
                  icon: Icons.dns_outlined,
                  enabled: !isLoading,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return context.l10n.connPageHostError;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),

                // 端口
                _buildTextField(
                  controller: _portController,
                  label: context.l10n.connPagePortLabel,
                  hint: context.l10n.connPagePortHint,
                  icon: Icons.tag,
                  enabled: !isLoading,
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return context.l10n.connPagePortError;
                    }
                    final port = int.tryParse(value);
                    if (port == null || port < 1 || port > 65535) {
                      return context.l10n.connPagePortInvalidError;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),

                // 用户名
                _buildTextField(
                  controller: _usernameController,
                  label: context.l10n.connPageUsernameLabel,
                  icon: Icons.person_outline,
                  enabled: !isLoading,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return context.l10n.connPageUsernameError;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),

                // 密码
                _buildTextField(
                  controller: _passwordController,
                  label: context.l10n.connPagePasswordLabel,
                  icon: Icons.lock_outline,
                  enabled: !isLoading,
                  obscureText: _obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppColors.darkOnSurfaceVariant,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  onFieldSubmitted: (_) => _handleConnect(),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return context.l10n.connPagePasswordError;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),

                // HTTPS 开关
                _buildSslSwitch(isLoading),
                const SizedBox(height: AppSpacing.md),

                // 记住登录和设备开关
                _buildRememberOptions(isLoading),
                const SizedBox(height: AppSpacing.xl),

                // 连接按钮
                _buildConnectButton(isLoading, state),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon, String? hint,
    bool enabled = true,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    void Function(String)? onFieldSubmitted,
    String? Function(String?)? validator,
  }) => TextFormField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      style: const TextStyle(color: AppColors.darkOnSurface),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: AppColors.darkOnSurfaceVariant),
        hintStyle: TextStyle(color: AppColors.darkOnSurfaceVariant.withValues(alpha: 0.5)),
        prefixIcon: Icon(icon, color: AppColors.darkOnSurfaceVariant),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppColors.darkSurfaceVariant.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: AppColors.darkOutline.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: AppColors.primary,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
      ),
    );

  Widget _buildNasTypeSelector() => Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.darkSurfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.darkOutline.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          _buildTypeOption(
            type: NasAdapterType.synology,
            label: context.l10n.connPageNasTypeSynology,
            icon: Icons.storage_rounded,
          ),
          _buildTypeOption(
            type: NasAdapterType.ugreen,
            label: context.l10n.connPageNasTypeUGreen,
            icon: Icons.storage_rounded,
            comingSoon: true, // 绿联 API 系逆向工程获得，暂不开放
          ),
          _buildTypeOption(
            type: NasAdapterType.webdav,
            label: context.l10n.connPageNasTypeWebDAV,
            icon: Icons.cloud_outlined,
          ),
        ],
      ),
    );

  Widget _buildTypeOption({
    required NasAdapterType type,
    required String label,
    required IconData icon,
    bool comingSoon = false,
  }) {
    final isSelected = !comingSoon && _selectedType == type;
    final isDisabled = comingSoon;
    
    return Expanded(
      child: GestureDetector(
        onTap: isDisabled
            ? null
            : () {
                setState(() {
                  _selectedType = type;
                  _portController.text = switch (type) {
                    NasAdapterType.synology => '5000',
                    NasAdapterType.webdav => '5005',
                    _ => '5000',
                  };
                });
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(vertical: comingSoon ? 8 : 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: isDisabled
                        ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.4)
                        : isSelected
                            ? Colors.white
                            : AppColors.darkOnSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: isDisabled
                          ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.4)
                          : isSelected
                              ? Colors.white
                              : AppColors.darkOnSurfaceVariant,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              if (comingSoon) ...[
                const SizedBox(height: 2),
                Text(
                  context.l10n.connPageComingSoon,
                  style: TextStyle(
                    color: AppColors.darkOnSurfaceVariant.withValues(alpha: 0.4),
                    fontSize: 9,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSslSwitch(bool isLoading) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.darkSurfaceVariant.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            _useSsl ? Icons.lock_outline : Icons.lock_open_outlined,
            color: _useSsl ? AppColors.success : AppColors.warning,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.connPageUseHttps,
                  style: TextStyle(
                    color: AppColors.darkOnSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _useSsl ? context.l10n.connPageSecureConnection : context.l10n.connPageInsecureConnection,
                  style: TextStyle(
                    color: AppColors.darkOnSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _useSsl,
            onChanged: isLoading ? null : (v) => setState(() => _useSsl = v),
            activeTrackColor: AppColors.primary,
          ),
        ],
      ),
    );

  Widget _buildRememberOptions(bool isLoading) => Column(
      children: [
        // 记住登录
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.darkSurfaceVariant.withValues(alpha: 0.3),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.person_pin_rounded,
                color: _rememberLogin ? AppColors.primary : AppColors.darkOnSurfaceVariant,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.connPageRememberLogin,
                      style: TextStyle(
                        color: AppColors.darkOnSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      context.l10n.connPageRememberLoginDesc,
                      style: TextStyle(
                        color: AppColors.darkOnSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _rememberLogin,
                onChanged: isLoading
                    ? null
                    : (v) => setState(() => _rememberLogin = v),
                activeTrackColor: AppColors.primary,
              ),
            ],
          ),
        ),
        // 记住设备
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.darkSurfaceVariant.withValues(alpha: 0.3),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            border: Border(
              top: BorderSide(
                color: AppColors.darkOutline.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.devices_rounded,
                color: _rememberDevice ? AppColors.accent : AppColors.darkOnSurfaceVariant,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.connPageRememberDevice,
                      style: TextStyle(
                        color: AppColors.darkOnSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      context.l10n.connPageRememberDeviceDesc,
                      style: TextStyle(
                        color: AppColors.darkOnSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _rememberDevice,
                onChanged: isLoading
                    ? null
                    : (v) => setState(() => _rememberDevice = v),
                activeTrackColor: AppColors.accent,
              ),
            ],
          ),
        ),
      ],
    );

  Widget _buildConnectButton(bool isLoading, NasConnectionState state) => Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: isLoading ? null : AppColors.primaryGradient,
        color: isLoading ? AppColors.darkSurfaceVariant : null,
        boxShadow: isLoading
            ? null
            : [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : _handleConnect,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: isLoading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.darkOnSurface,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        (state as ConnectionLoading).message ?? context.l10n.connPageConnectingStatus,
                        style: const TextStyle(
                          color: AppColors.darkOnSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.login_rounded, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        context.l10n.connPageConnectButton,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );

  Widget _build2FACard(ConnectionRequires2FAState state) => ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: AppColors.glassLight,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.glassStroke,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 图标
              Container(
                width: 72,
                height: 72,
                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.accentGradient,
                ),
                child: const Icon(
                  Icons.security_rounded,
                  size: 36,
                  color: Colors.white,
                ),
              ),
              Text(
                context.l10n.connPageTwoFactorTitle,
                style: context.textTheme.titleLarge?.copyWith(
                  color: AppColors.darkOnSurface,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.l10n.connPageTwoFactorDesc,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: AppColors.darkOnSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),

              // OTP 输入框
              _buildTextField(
                controller: _otpController,
                label: context.l10n.connPageOtpLabel,
                hint: context.l10n.connPageOtpHint,
                icon: Icons.pin_outlined,
                keyboardType: TextInputType.number,
                onFieldSubmitted: (_) => _handleVerify2FA(),
              ),
              const SizedBox(height: AppSpacing.md),

              // 记住此设备选项
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.darkSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.devices_rounded,
                      color: _rememberDevice
                          ? AppColors.accent
                          : AppColors.darkOnSurfaceVariant,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.connPageRememberDevice,
                            style: TextStyle(
                              color: AppColors.darkOnSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            context.l10n.connPageRememberDeviceDesc2FA,
                            style: TextStyle(
                              color: AppColors.darkOnSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _rememberDevice,
                      onChanged: (v) => setState(() => _rememberDevice = v),
                      activeTrackColor: AppColors.accent,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // 验证按钮
              Container(
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: AppColors.accentGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _handleVerify2FA,
                    borderRadius: BorderRadius.circular(16),
                    child: Center(
                      child: Text(
                        context.l10n.connPageVerifyButton,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 返回按钮
              TextButton(
                onPressed: () {
                  ref.read(connectionStateProvider.notifier).disconnect();
                  _otpController.clear();
                },
                child: Text(
                  context.l10n.connPageBackButton,
                  style: TextStyle(
                    color: AppColors.darkOnSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
}
