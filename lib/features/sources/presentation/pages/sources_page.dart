import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/file_browser/presentation/pages/file_browser_page.dart';
import 'package:my_nas/features/sources/data/services/network_discovery_service.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/source_form_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/sources/presentation/widgets/two_fa_sheet.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/utils/form_l10n.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

class SourcesPage extends ConsumerStatefulWidget {
  const SourcesPage({super.key, this.embedded = false});

  /// 嵌入式渲染（桌面 mine_page 内联使用）：去掉 Scaffold/AppBar，
  /// 改用紧凑工具栏，避免和外层 detail 容器叠 AppBar。
  final bool embedded;

  @override
  ConsumerState<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends ConsumerState<SourcesPage>
    with ConsumerTabBarVisibilityMixin {
  bool _isReorderMode = false;

  @override
  void initState() {
    super.initState();
    hideTabBar();
    // 启动网络发现
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(networkDiscoveryProvider.notifier).startDiscovery();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(sourcesProvider);
    final connections = ref.watch(activeConnectionsProvider);
    final mediaServerConnections = ref.watch(
      activeMediaServerConnectionsProvider,
    );
    final discoveryState = ref.watch(networkDiscoveryProvider);

    final body = sourcesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(context.l10n.sourcesPageLoadError(e.toString())),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.read(sourcesProvider.notifier).refresh(),
              child: Text(context.l10n.sourcesPageRetryButton),
            ),
          ],
        ),
      ),
      data: (allSources) {
        // 只显示存储类源（包括媒体服务器）
        final sources = allSources
            .where((s) => s.type.category.isStorageCategory)
            .toList();

        if (sources.isEmpty && discoveryState.devices.isEmpty) {
          return _buildEmptyState(context);
        }

        if (_isReorderMode) {
          return _buildReorderableList(
            sources,
            connections,
            mediaServerConnections,
          );
        }

        return _buildSourcesList(
          sources,
          connections,
          mediaServerConnections,
          discoveryState,
        );
      },
    );

    if (widget.embedded) {
      return Column(
        children: [
          _buildEmbeddedToolbar(discoveryState),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: const RoundedBackButton(),
        title: Text(context.l10n.sourcesPageTitle),
        actions: _buildActions(discoveryState, embedded: false),
      ),
      body: body,
    );
  }

  List<Widget> _buildActions(
    NetworkDiscoveryState discoveryState, {
    required bool embedded,
  }) {
    final iconSize = embedded ? 20.0 : 24.0;
    final density = embedded ? VisualDensity.compact : VisualDensity.standard;
    return [
      IconButton(
        icon: discoveryState.isDiscovering
            ? SizedBox(
                width: iconSize - 2,
                height: iconSize - 2,
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.radar, size: iconSize),
        onPressed: discoveryState.isDiscovering
            ? null
            : () =>
                  ref.read(networkDiscoveryProvider.notifier).startDiscovery(),
        tooltip: context.l10n.sourcesPageScanButton,
        visualDensity: density,
      ),
      IconButton(
        icon: Icon(
          _isReorderMode ? Icons.done_rounded : Icons.reorder,
          size: iconSize,
        ),
        onPressed: () => setState(() => _isReorderMode = !_isReorderMode),
        tooltip: _isReorderMode
            ? context.l10n.sourcesPageReorderComplete
            : context.l10n.sourcesPageReorderStart,
        visualDensity: density,
      ),
      IconButton(
        icon: Icon(Icons.add_rounded, size: iconSize),
        onPressed: () => _showAddSourceSheet(context),
        tooltip: context.l10n.sourcesPageAddSource,
        visualDensity: density,
      ),
    ];
  }

  Widget _buildEmbeddedToolbar(NetworkDiscoveryState discoveryState) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
    child: Row(
      children: [
        const Spacer(),
        ..._buildActions(discoveryState, embedded: true),
      ],
    ),
  );

  /// 构建包含发现设备和已配置源的列表
  Widget _buildSourcesList(
    List<SourceEntity> sources,
    Map<String, SourceConnection> connections,
    Map<String, MediaServerConnection> mediaServerConnections,
    NetworkDiscoveryState discoveryState,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      // 桌面下限宽 720 居中（macOS 系统设置 detail 风格），手机全宽。
      // 用 LayoutBuilder 取实际可用宽度，避免 embedded 模式下用 screenWidth
      // 算 padding 把内容挤到窄条里。
      final isDesktop = context.isDesktopLayout;
      final available = constraints.maxWidth;
      final horizontal = isDesktop && available > 720
          ? ((available - 720) / 2).clamp(16.0, double.infinity)
          : 16.0;
      return _buildSourcesListView(
        sources,
        connections,
        mediaServerConnections,
        discoveryState,
        horizontal: horizontal,
      );
    },
  );

  Widget _buildSourcesListView(
    List<SourceEntity> sources,
    Map<String, SourceConnection> connections,
    Map<String, MediaServerConnection> mediaServerConnections,
    NetworkDiscoveryState discoveryState, {
    required double horizontal,
  }) => ListView(
    padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 16),
    children: [
      // 发现的设备部分
      if (discoveryState.devices.isNotEmpty ||
          discoveryState.isDiscovering) ...[
        _buildSectionHeader(
          context,
          context.l10n.sourcesPageDiscoveredDevices,
          subtitle: discoveryState.isDiscovering
              ? context.l10n.sourcesPageDiscoveryScanning
              : context.l10n.sourcesPageDiscoveryHint,
          // 移除重复的loading指示器，仅保留AppBar中的雷达按钮loading
        ),
        const SizedBox(height: 8),
        ...discoveryState.devices.map(
          (device) => _DiscoveredDeviceCard(device: device),
        ),
        const SizedBox(height: 16),
      ],

      // 已配置的连接源部分
      if (sources.isNotEmpty) ...[
        _buildSectionHeader(
          context,
          context.l10n.sourcesPageConfiguredConnections,
        ),
        const SizedBox(height: 8),
        ...sources.map((source) {
          final connection = connections[source.id];
          final mediaServerConnection = mediaServerConnections[source.id];
          return _SourceCard(
            source: source,
            status:
                mediaServerConnection?.status ??
                connection?.status ??
                SourceStatus.disconnected,
          );
        }),
      ],
    ],
  );

  Widget _buildSectionHeader(
    BuildContext context,
    String title, {
    String? subtitle,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }

  Widget _buildReorderableList(
    List<SourceEntity> sources,
    Map<String, SourceConnection> connections,
    Map<String, MediaServerConnection> mediaServerConnections,
  ) => ReorderableListView.builder(
    padding: const EdgeInsets.all(16),
    itemCount: sources.length,
    onReorderItem: (oldIndex, newIndex) {
      ref.read(sourcesProvider.notifier).reorderSources(oldIndex, newIndex);
    },
    proxyDecorator: (child, index, animation) => AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final elevation = Tween<double>(begin: 0, end: 8).evaluate(animation);
        return Material(
          elevation: elevation,
          borderRadius: BorderRadius.circular(12),
          child: child,
        );
      },
      child: child,
    ),
    itemBuilder: (context, index) {
      final source = sources[index];
      final connection = connections[source.id];
      final mediaServerConnection = mediaServerConnections[source.id];
      return _ReorderableSourceCard(
        key: ValueKey(source.id),
        source: source,
        status:
            mediaServerConnection?.status ??
            connection?.status ??
            SourceStatus.disconnected,
      );
    },
  );

  Widget _buildEmptyState(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.cloud_off_outlined,
              size: 40,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            context.l10n.sourcesPageEmptyStateTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.sourcesPageEmptyStateDescription,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showAddSourceSheet(context),
            icon: const Icon(Icons.add_rounded),
            label: Text(context.l10n.sourcesPageAddSource),
          ),
        ],
      ),
    ),
  );

  void _showAddSourceSheet(BuildContext context) {
    // 获取所有存储类源的已支持类型
    final supportedTypes = SourceCategoryExtension.storageCategories
        .expand(SourceType.byCategory)
        .where((type) => type.isSupported)
        .toList();

    if (supportedTypes.isEmpty) {
      context.showInfoToast(context.l10n.sourcesPageNoSourceTypes);
      return;
    }

    // 显示底部弹窗让用户选择类型
    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _SourceTypeBottomSheet(types: supportedTypes),
    );
  }
}

/// 排序模式下的源卡片（带拖动手柄）
class _ReorderableSourceCard extends StatelessWidget {
  const _ReorderableSourceCard({
    required this.source,
    required this.status,
    super.key,
  });

  final SourceEntity source;
  final SourceStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // 拖动手柄
            ReorderableDragStartListener(
              index: 0, // 会被 ReorderableListView 覆盖
              child: Icon(
                Icons.drag_handle,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),

            // 图标 - 使用源类型的主题色
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: source.type.themeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(source.type.icon, color: source.type.themeColor),
            ),
            const SizedBox(width: 16),

            // 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.displayName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${source.type.displayName} • ${source.host}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            // 状态
            _buildStatusChip(context, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context, ThemeData theme) {
    final (label, color) = switch (status) {
      SourceStatus.connected => (
        context.l10n.sourcesPageStatusConnected,
        AppColors.success,
      ),
      SourceStatus.connecting => (
        context.l10n.sourcesPageStatusConnecting,
        AppColors.warning,
      ),
      SourceStatus.requires2FA => (
        context.l10n.sourcesPageStatusNeedsVerification,
        AppColors.warning,
      ),
      SourceStatus.error => (
        context.l10n.sourcesPageStatusError,
        AppColors.error,
      ),
      SourceStatus.disconnected => (
        context.l10n.sourcesPageStatusDisconnected,
        AppColors.lightOnSurfaceVariant,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _SourceCard extends ConsumerStatefulWidget {
  const _SourceCard({required this.source, required this.status});

  final SourceEntity source;
  final SourceStatus status;

  @override
  ConsumerState<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends ConsumerState<_SourceCard> {
  bool _isConnecting = false;
  String? _errorMessage;

  SourceStatus get _status => widget.status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          // 存储类源的处理
          if (_status == SourceStatus.connected) {
            // 已连接时打开文件浏览器
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => FileBrowserPage(
                  sourceId: widget.source.id,
                  sourceName: widget.source.displayName,
                ),
              ),
            );
          } else {
            // 未连接时，显示操作选项
            _showSourceOptions(context);
          }
        },
        onLongPress: () => _showSourceOptions(context),
        onSecondaryTap: () => _showSourceOptions(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 图标 - 使用源类型的主题色
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: widget.source.type.themeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getSourceIcon(),
                  color: widget.source.type.themeColor,
                ),
              ),
              const SizedBox(width: 16),

              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.source.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.source.type.displayName} • ${widget.source.host}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _errorMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.error,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              // 状态/操作
              if (_isConnecting)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                _buildStatusChip(context, theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context, ThemeData theme) {
    final (label, color) = switch (_status) {
      SourceStatus.connected => (
        context.l10n.sourcesPageStatusConnected,
        AppColors.success,
      ),
      SourceStatus.connecting => (
        context.l10n.sourcesPageStatusConnecting,
        AppColors.warning,
      ),
      SourceStatus.requires2FA => (
        context.l10n.sourcesPageStatusNeedsVerification,
        AppColors.warning,
      ),
      SourceStatus.error => (
        context.l10n.sourcesPageStatusError,
        AppColors.error,
      ),
      SourceStatus.disconnected => (
        context.l10n.sourcesPageStatusDisconnected,
        AppColors.lightOnSurfaceVariant,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  IconData _getSourceIcon() => widget.source.type.icon;

  void _showSourceOptions(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动指示器
          const SheetDragHandle(),
          // 存储类源显示"连接/断开"
          ListTile(
            leading: Icon(
              _status == SourceStatus.connected
                  ? Icons.link_off
                  : Icons.link_rounded,
            ),
            title: Text(
              _status == SourceStatus.connected
                  ? context.l10n.sourcesPageMenuDisconnect
                  : context.l10n.sourcesPageMenuConnect,
            ),
            onTap: () {
              Navigator.pop(context);
              if (_status == SourceStatus.connected) {
                _disconnect();
              } else {
                _connect();
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_rounded),
            title: Text(context.l10n.sourcesPageMenuEdit),
            onTap: () {
              Navigator.pop(context);
              _editSource();
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_rounded, color: AppColors.error),
            title: Text(
              context.l10n.sourcesPageMenuDelete,
              style: TextStyle(color: AppColors.error),
            ),
            onTap: () {
              Navigator.pop(context);
              _deleteSource();
            },
          ),
          // 底部安全区域
          SizedBox(height: bottomPadding > 0 ? bottomPadding : 16),
        ],
      ),
    );
  }

  Future<void> _connect() async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    String? usedPassword;

    try {
      final isMediaServer =
          widget.source.type.category == SourceCategory.mediaServers;
      // 本地存储不需要密码，直接连接
      if (widget.source.type == SourceType.local) {
        await ref
            .read(activeConnectionsProvider.notifier)
            .connect(widget.source, password: '', saveCredential: false);
      } else if (isMediaServer) {
        final manager = ref.read(sourceManagerProvider);
        final credential = await manager.getCredential(widget.source.id);
        var password = credential?.password;
        final hasToken =
            (credential?.apiKey?.isNotEmpty ?? false) ||
            (widget.source.apiKey?.isNotEmpty ?? false) ||
            (widget.source.accessToken?.isNotEmpty ?? false);
        if ((password?.isEmpty ?? true) && !hasToken) {
          if (!mounted) return;
          password = await _showPasswordDialog();
          if (password == null || password.isEmpty) return;
        }

        usedPassword = password;
        final connection = await ref
            .read(activeMediaServerConnectionsProvider.notifier)
            .connect(
              widget.source,
              password: password,
              apiKey: credential?.apiKey ?? widget.source.apiKey,
            );
        if (connection.status == SourceStatus.error) {
          setState(() => _errorMessage = connection.errorMessage);
        }
      } else {
        // 获取保存的凭证
        final manager = ref.read(sourceManagerProvider);
        final credential = await manager.getCredential(widget.source.id);

        final storedPassword = credential?.password ?? '';
        if (widget.source.usesPasswordAuthentication && credential == null) {
          // 如果没有保存的凭证，显示密码输入对话框
          if (mounted) {
            final password = await _showPasswordDialog();
            if (password == null || password.isEmpty) {
              setState(() => _isConnecting = false);
              return;
            }
            usedPassword = password;
            await ref
                .read(activeConnectionsProvider.notifier)
                .connect(widget.source, password: password);
          }
        } else {
          // 总是保存凭证，以便更新 deviceId
          usedPassword = storedPassword;
          await ref
              .read(activeConnectionsProvider.notifier)
              .connect(widget.source, password: storedPassword);
        }
      }

      final connection = ref.read(activeConnectionsProvider)[widget.source.id];

      // 处理需要 2FA 验证的情况
      if (connection?.status == SourceStatus.requires2FA) {
        if (mounted) {
          final result = await _show2FADialog();
          if (result != null && result.otpCode.isNotEmpty) {
            await ref
                .read(activeConnectionsProvider.notifier)
                .verify2FA(
                  widget.source.id,
                  result.otpCode,
                  rememberDevice: result.rememberDevice,
                  password: usedPassword,
                );
          }
        }
      } else if (connection?.status == SourceStatus.error) {
        setState(() {
          _errorMessage = connection?.errorMessage;
        });
      }
    } on Exception catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  Future<TwoFAResult?> _show2FADialog() async => showTwoFASheet(
    context,
    initialRememberDevice: widget.source.rememberDevice,
    sourceName: widget.source.displayName,
  );

  Future<String?> _showPasswordDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.sourcesPagePasswordDialogTitle),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(
            labelText: context.l10n.sourcesPagePasswordLabel,
            hintText: context.l10n.sourcesPagePasswordHint(
              widget.source.username,
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.sourcesPageCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(context.l10n.sourcesPageConnectButton),
          ),
        ],
      ),
    );
  }

  Future<void> _disconnect() async {
    if (widget.source.type.category == SourceCategory.mediaServers) {
      await ref
          .read(activeMediaServerConnectionsProvider.notifier)
          .disconnect(widget.source.id);
    } else {
      await ref
          .read(activeConnectionsProvider.notifier)
          .disconnect(widget.source.id);
    }
  }

  void _editSource() {
    SourceFormPage.openAdaptive<void>(
      context,
      sourceType: widget.source.type,
      existingSource: widget.source,
    );
  }

  Future<void> _deleteSource() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.sourcesPageDeleteTitle),
        content: Text(
          context.l10n.sourcesPageDeleteConfirm(widget.source.displayName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.sourcesPageCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(context.l10n.sourcesPageDeleteButton),
          ),
        ],
      ),
    );

    if ((confirm ?? false) && mounted) {
      try {
        await ref.read(sourcesProvider.notifier).removeSource(widget.source.id);
        if (mounted) {
          context.showSuccessToast(
            context.l10n.sourcesPageDeleteSuccess(widget.source.displayName),
          );
        }
      } on Exception catch (e) {
        if (mounted) {
          context.showErrorSnackBar(context.l10n.sourcesPageDeleteFailed(e));
        }
      }
    }
  }
}

/// 源类型选择底部弹窗
class _SourceTypeBottomSheet extends StatelessWidget {
  const _SourceTypeBottomSheet({required this.types});

  final List<SourceType> types;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 按分类分组
    final groupedTypes = <SourceCategory, List<SourceType>>{};
    for (final type in types) {
      groupedTypes.putIfAbsent(type.category, () => []).add(type);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 拖动条
            const SheetDragHandle(topPadding: 0, bottomPadding: 16),

            // 标题
            Text(
              context.l10n.sourcesPageAddTypeTitle,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.sourcesPageAddTypeSubtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // 按分类显示类型
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final category in groupedTypes.keys) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: Text(
                          localizeFormText(context, category.displayName),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      ...groupedTypes[category]!.map(
                        (type) => _buildTypeTile(context, type),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeTile(BuildContext context, SourceType type) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(type.icon, color: colorScheme.primary, size: 24),
        ),
        title: Text(
          type.displayName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          localizeFormText(context, type.description),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: colorScheme.onSurfaceVariant,
        ),
        onTap: () {
          Navigator.pop(context);
          SourceFormPage.openAdaptive<void>(context, sourceType: type);
        },
      ),
    );
  }
}

/// 发现的设备卡片 - 使用源类型专属颜色，便于快速区分不同协议
class _DiscoveredDeviceCard extends StatelessWidget {
  const _DiscoveredDeviceCard({required this.device});

  final DiscoveredDevice device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = device.type.themeColor;

    // 桌面端紧凑变体：hairline 边框 + 24 图标 + 文字链式 "添加"，与
    // macOS Finder 边栏 / Linear inbox 风格一致；移动端保留原"卡片 + 强调色"风格。
    if (context.isDesktopLayout) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            side: BorderSide(
              color: isDark
                  ? AppColors.darkOutlineVariant
                  : AppColors.lightOutlineVariant,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.card),
            onTap: () => _onDeviceTap(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(device.type.icon, color: accentColor, size: 16),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                device.name,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                context.l10n.sourcesPageDiscoveryBadge,
                                style: TextStyle(
                                  color: accentColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${device.host}:${device.port} · ${device.type.displayName}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  TextButton.icon(
                    onPressed: () => _onDeviceTap(context),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: Text(context.l10n.sourcesPageAddDeviceButton),
                    style: TextButton.styleFrom(
                      foregroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 移动端保留原 "卡片 + 强调色填充 + 雷达徽章" 风格
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: accentColor.withValues(alpha: 0.4), width: 1.5),
      ),
      color: accentColor.withValues(alpha: isDark ? 0.08 : 0.06),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                device.type.icon,
                color: accentColor.withValues(alpha: isDark ? 1.0 : 0.85),
                size: 24,
              ),
            ),
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? colorScheme.surface : Colors.white,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.radar, size: 12, color: Colors.white),
              ),
            ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                device.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                context.l10n.sourcesPageDiscoveryBadge,
                style: TextStyle(
                  color: accentColor.withValues(alpha: isDark ? 1.0 : 0.85),
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${device.host}:${device.port} • ${device.type.displayName}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: accentColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                context.l10n.sourcesPageAddDeviceButton,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        onTap: () => _onDeviceTap(context),
      ),
    );
  }

  void _onDeviceTap(BuildContext context) {
    SourceFormPage.openAdaptive<void>(
      context,
      sourceType: device.type,
      initialValues: {
        'name': device.name,
        'host': device.host,
        'port': device.port.toString(),
      },
    );
  }
}
