import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/shared/services/update_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// 显示更新对话框
Future<void> showUpdateDialog(BuildContext context, UpdateInfo updateInfo) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => UpdateDialog(updateInfo: updateInfo),
  );

class UpdateDialog extends ConsumerStatefulWidget {
  const UpdateDialog({required this.updateInfo, super.key});

  final UpdateInfo updateInfo;

  @override
  ConsumerState<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<UpdateDialog> {
  final _service = UpdateService();

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = _service.status;

    return AlertDialog(
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 头部
            _buildHeader(isDark),
            // 内容
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 版本信息
                  _buildVersionInfo(isDark),
                  const SizedBox(height: AppSpacing.md),
                  // 更新说明
                  _buildReleaseNotes(isDark),
                  const SizedBox(height: AppSpacing.lg),
                  // 下载进度
                  if (status == UpdateStatus.downloading) _buildProgress(isDark),
                  // 安装中
                  if (status == UpdateStatus.installing) _buildInstalling(isDark),
                  // 错误信息
                  if (status == UpdateStatus.error) _buildError(isDark),
                  // 按钮
                  _buildActions(isDark, status),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.system_update_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            context.l10n.updateDialogTitle,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );

  Widget _buildVersionInfo(bool isDark) {
    final hasDownload = widget.updateInfo.downloadUrl.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
            : AppColors.lightSurfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildVersionBadge(context.l10n.updateDialogBadgeNewVersion, widget.updateInfo.version, AppColors.success),
          const SizedBox(width: AppSpacing.md),
          Icon(
            Icons.arrow_forward_rounded,
            size: 20,
            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasDownload ? context.l10n.updateDialogFileSizeLabel : context.l10n.updateDialogPlatformLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                  ),
                ),
                Text(
                  hasDownload
                      ? widget.updateInfo.fileSizeText
                      : _getPlatformDisplayName(),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getPlatformDisplayName() {
    if (Platform.isIOS) return 'iOS';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return context.l10n.updateDialogUnknownPlatform;
  }

  Widget _buildVersionBadge(String label, String version, Color color) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
          ),
        ),
        Text(
          'v$version',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );

  Widget _buildReleaseNotes(bool isDark) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.notes_rounded,
              size: 18,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            Text(
              context.l10n.updateDialogReleaseNotesTitle,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          constraints: const BoxConstraints(maxHeight: 150),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
                : AppColors.lightSurfaceVariant.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              widget.updateInfo.releaseNotes,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );

  Widget _buildProgress(bool isDark) => Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              context.l10n.updateDialogDownloading,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
            Text(
              '${(_service.downloadProgress * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _service.downloadProgress,
            backgroundColor: isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurfaceVariant,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );

  Widget _buildInstalling(bool isDark) => Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            context.l10n.updateDialogInstalling,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
            ),
          ),
        ],
      ),
    );

  Widget _buildError(bool isDark) => Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _service.errorMessage ?? context.l10n.updateDialogUnknownError,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );

  Widget _buildActions(bool isDark, UpdateStatus status) {
    // 下载中 - 显示取消按钮
    if (status == UpdateStatus.downloading) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _service.cancelDownload,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(context.l10n.updateDialogButtonCancelDownload),
        ),
      );
    }

    // 安装中 - 不显示按钮
    if (status == UpdateStatus.installing) {
      return const SizedBox.shrink();
    }

    // 准备安装
    if (status == UpdateStatus.readyToInstall) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: _buildGradientButton(
              onPressed: () async {
                final success = await _service.installUpdate();
                if (!success && mounted) {
                  context.showInfoToast(context.l10n.updateDialogToastManualInstall);
                }
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.install_desktop_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    context.l10n.updateDialogButtonInstallNow,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              context.l10n.updateDialogButtonInstallLater,
              style: TextStyle(
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }

    // 错误状态 - 显示重试按钮
    if (status == UpdateStatus.error) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                _service
                  ..reset()
                  ..checkForUpdates();
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.refresh_rounded, size: 20),
                  SizedBox(width: 8),
                  Text(context.l10n.updateDialogButtonRetry),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // 提供打开 GitHub Releases 的选项
          TextButton(
            onPressed: _openReleasesPage,
            child: Text(
              context.l10n.updateDialogButtonGitHubDownload,
              style: TextStyle(
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              context.l10n.updateDialogButtonClose,
              style: TextStyle(
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }

    // 默认状态 - 显示下载/更新按钮
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: _buildGradientButton(
            onPressed: _handlePrimaryAction,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _getPrimaryActionIcon(),
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _getPrimaryActionText(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        // iOS 提供额外的 GitHub 下载选项（用于侧载）
        if (Platform.isIOS && widget.updateInfo.downloadUrl.isEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: _openReleasesPage,
            child: Text(
              context.l10n.updateDialogButtonGitHubDownloadIPA,
              style: TextStyle(
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            context.l10n.updateDialogButtonRemindLater,
            style: TextStyle(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  IconData _getPrimaryActionIcon() {
    if (Platform.isIOS) {
      if (_service.config.hasAppStoreConfig) {
        return Icons.open_in_new_rounded;
      }
      return Icons.language_rounded;
    }
    return Icons.download_rounded;
  }

  String _getPrimaryActionText() {
    if (Platform.isIOS) {
      if (_service.config.hasAppStoreConfig) {
        return context.l10n.updateDialogButtonAppStore;
      }
      return context.l10n.updateDialogButtonViewDetails;
    }
    return context.l10n.updateDialogButtonDownloadNow;
  }

  Future<void> _handlePrimaryAction() async {
    if (Platform.isIOS) {
      if (_service.config.hasAppStoreConfig) {
        await _openAppStore();
      } else {
        await _openReleasesPage();
      }
    } else {
      await _service.downloadUpdate();
    }
  }

  Widget _buildGradientButton({
    required VoidCallback onPressed,
    required Widget child,
  }) => DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: child,
          ),
        ),
      ),
    );

  Future<void> _openAppStore() async {
    final appStoreUrl = _service.config.appStoreUrl;
    if (appStoreUrl == null) {
      await _openReleasesPage();
      return;
    }

    final uri = Uri.parse(appStoreUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _openReleasesPage() async {
    // 优先打开具体版本的页面
    final url = widget.updateInfo.htmlUrl.isNotEmpty
        ? widget.updateInfo.htmlUrl
        : _service.config.releasesUrl;

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (mounted) Navigator.pop(context);
  }
}

/// 检查更新按钮组件（用于设置页面）
class CheckUpdateTile extends ConsumerStatefulWidget {
  const CheckUpdateTile({required this.isDark, super.key});

  final bool isDark;

  @override
  ConsumerState<CheckUpdateTile> createState() => _CheckUpdateTileState();
}

class _CheckUpdateTileState extends ConsumerState<CheckUpdateTile> {
  final _service = UpdateService();

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final status = _service.status;
    final hasUpdate = _service.hasUpdate;
    // 与 mine 页其他 tile 对齐：桌面 32×32 / icon 18 / sm padding / 8 圆角
    final isDesktop = context.isDesktopLayout;
    final iconBox = isDesktop ? 32.0 : 40.0;
    final iconSize = isDesktop ? 18.0 : 20.0;
    final verticalPadding = isDesktop ? AppSpacing.sm : AppSpacing.md;
    final titleStyle = isDesktop
        ? context.textTheme.bodyMedium
        : context.textTheme.bodyLarge;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: status == UpdateStatus.checking
            ? null
            : () async {
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                await _service.checkForUpdates();
                if (!context.mounted) return;
                if (_service.hasUpdate && _service.updateInfo != null) {
                  await showUpdateDialog(context, _service.updateInfo!);
                } else if (_service.status == UpdateStatus.notAvailable) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(content: Text(context.l10n.updateDialogAlreadyLatest)),
                  );
                } else if (_service.status == UpdateStatus.error) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(content: Text(context.l10n.updateDialogCheckFailed(_service.errorMessage ?? ''))),
                  );
                }
              },
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: verticalPadding,
          ),
          child: Row(
            children: [
              Container(
                width: iconBox,
                height: iconBox,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(isDesktop ? 8 : 12),
                ),
                child: Icon(
                  hasUpdate ? Icons.system_update_rounded : Icons.update_rounded,
                  color: AppColors.primary,
                  size: iconSize,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.updateTileTitle,
                      style: titleStyle?.copyWith(
                        color: widget.isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getStatusText(status),
                      style: context.textTheme.bodySmall?.copyWith(
                        color: hasUpdate
                            ? AppColors.success
                            : (widget.isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
              if (status == UpdateStatus.checking)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (hasUpdate)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'v${_service.updateInfo?.version}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                )
              else if (!isDesktop)
                Icon(
                  Icons.chevron_right_rounded,
                  color: widget.isDark
                      ? AppColors.darkOnSurfaceVariant
                      : AppColors.lightOnSurfaceVariant,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _getStatusText(UpdateStatus status) {
    switch (status) {
      case UpdateStatus.idle:
        return context.l10n.updateTileStatusIdle;
      case UpdateStatus.checking:
        return context.l10n.updateTileStatusChecking;
      case UpdateStatus.available:
        return context.l10n.updateTileStatusAvailable;
      case UpdateStatus.notAvailable:
        return context.l10n.updateDialogAlreadyLatest;
      case UpdateStatus.downloading:
        return context.l10n.updateTileStatusDownloading;
      case UpdateStatus.readyToInstall:
        return context.l10n.updateTileStatusReadyToInstall;
      case UpdateStatus.installing:
        return context.l10n.updateTileStatusInstalling;
      case UpdateStatus.error:
        return context.l10n.updateTileStatusError;
    }
  }
}
