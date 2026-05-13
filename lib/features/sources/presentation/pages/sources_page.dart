import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/features/file_browser/presentation/pages/file_browser_page.dart';
import 'package:my_nas/features/sources/data/services/network_discovery_service.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/source_form_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/sources/presentation/widgets/two_fa_sheet.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';

class SourcesPage extends ConsumerStatefulWidget {
  const SourcesPage({super.key});

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
    final discoveryState = ref.watch(networkDiscoveryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('连接源'),
        actions: [
          // 刷新发现按钮
          IconButton(
            icon: discoveryState.isDiscovering
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.radar),
            onPressed: discoveryState.isDiscovering
                ? null
                : () => ref.read(networkDiscoveryProvider.notifier).startDiscovery(),
            tooltip: '扫描局域网设备',
          ),
          // 排序模式切换按钮
          IconButton(
            icon: Icon(_isReorderMode ? Icons.done : Icons.reorder),
            onPressed: () {
              setState(() {
                _isReorderMode = !_isReorderMode;
              });
            },
            tooltip: _isReorderMode ? '完成排序' : '调整顺序',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddSourceSheet(context),
            tooltip: '添加源',
          ),
        ],
      ),
      body: sourcesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text('加载失败: $e'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.read(sourcesProvider.notifier).refresh(),
                child: const Text('重试'),
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
            return _buildReorderableList(sources, connections);
          }

          return _buildSourcesList(sources, connections, discoveryState);
        },
      ),
    );
  }

  /// 构建包含发现设备和已配置源的列表
  Widget _buildSourcesList(
    List<SourceEntity> sources,
    Map<String, SourceConnection> connections,
    NetworkDiscoveryState discoveryState,
  ) {
    // ignore: unused_local_variable
    final theme = Theme.of(context);

    // 桌面下限宽 720 居中（macOS 系统设置 detail 风格），手机全宽。
    final isDesktop = context.isDesktopLayout;
    final horizontal = isDesktop
        ? ((context.screenWidth - 720) / 2).clamp(16.0, double.infinity)
        : 16.0;

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 16),
      children: [
        // 发现的设备部分
        if (discoveryState.devices.isNotEmpty || discoveryState.isDiscovering) ...[
          _buildSectionHeader(
            context,
            '发现的设备',
            subtitle: discoveryState.isDiscovering
                ? '正在扫描...'
                : '点击添加到连接源',
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
          _buildSectionHeader(context, '已配置的连接'),
          const SizedBox(height: 8),
          ...sources.map((source) {
            final connection = connections[source.id];
            return _SourceCard(
              source: source,
              connection: connection,
            );
          }),
        ],
      ],
    );
  }

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
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildReorderableList(
    List<SourceEntity> sources,
    Map<String, SourceConnection> connections,
  ) => ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sources.length,
      onReorder: (oldIndex, newIndex) {
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
        return _ReorderableSourceCard(
          key: ValueKey(source.id),
          source: source,
          connection: connection,
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
              '尚未添加任何源',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '添加 NAS、WebDAV 或 SMB 源\n以开始浏览您的媒体文件',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _showAddSourceSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('添加源'),
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
      context.showInfoToast('暂无可用的连接源类型');
      return;
    }

    // 显示底部弹窗让用户选择类型
    showModalBottomSheet<void>(
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
    required this.source, super.key,
    this.connection,
  });

  final SourceEntity source;
  final SourceConnection? connection;

  SourceStatus get _status =>
      connection?.status ?? SourceStatus.disconnected;

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
              child: Icon(
                source.type.icon,
                color: source.type.themeColor,
              ),
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
            _buildStatusChip(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(ThemeData theme) {
    final (label, color) = switch (_status) {
      SourceStatus.connected => ('已连接', AppColors.success),
      SourceStatus.connecting => ('连接中', AppColors.warning),
      SourceStatus.requires2FA => ('需要验证', AppColors.warning),
      SourceStatus.error => ('错误', AppColors.error),
      SourceStatus.disconnected => ('未连接', AppColors.lightOnSurfaceVariant),
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
  const _SourceCard({
    required this.source,
    this.connection,
  });

  final SourceEntity source;
  final SourceConnection? connection;

  @override
  ConsumerState<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends ConsumerState<_SourceCard> {
  bool _isConnecting = false;
  String? _errorMessage;

  SourceStatus get _status =>
      widget.connection?.status ?? SourceStatus.disconnected;

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
                _buildStatusChip(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(ThemeData theme) {
    final (label, color) = switch (_status) {
      SourceStatus.connected => ('已连接', AppColors.success),
      SourceStatus.connecting => ('连接中', AppColors.warning),
      SourceStatus.requires2FA => ('需要验证', AppColors.warning),
      SourceStatus.error => ('错误', AppColors.error),
      SourceStatus.disconnected => ('未连接', AppColors.lightOnSurfaceVariant),
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

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动指示器
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[600]
                  : Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 存储类源显示"连接/断开"
          ListTile(
            leading: Icon(
              _status == SourceStatus.connected ? Icons.link_off : Icons.link,
            ),
            title: Text(
              _status == SourceStatus.connected ? '断开连接' : '连接',
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
            leading: const Icon(Icons.edit),
            title: const Text('编辑'),
            onTap: () {
              Navigator.pop(context);
              _editSource();
            },
          ),
          ListTile(
            leading: Icon(Icons.delete, color: AppColors.error),
            title: Text('删除', style: TextStyle(color: AppColors.error)),
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
      // 本地存储不需要密码，直接连接
      if (widget.source.type == SourceType.local) {
        await ref.read(activeConnectionsProvider.notifier).connect(
              widget.source,
              password: '',
              saveCredential: false,
            );
      } else {
        // 获取保存的凭证
        final manager = ref.read(sourceManagerProvider);
        final credential = await manager.getCredential(widget.source.id);

        if (credential == null) {
          // 如果没有保存的凭证，显示密码输入对话框
          if (mounted) {
            final password = await _showPasswordDialog();
            if (password == null || password.isEmpty) {
              setState(() => _isConnecting = false);
              return;
            }
            usedPassword = password;
            await ref.read(activeConnectionsProvider.notifier).connect(
                  widget.source,
                  password: password,
                );
          }
        } else {
          // 总是保存凭证，以便更新 deviceId
          usedPassword = credential.password;
          await ref.read(activeConnectionsProvider.notifier).connect(
                widget.source,
                password: credential.password,
              );
        }
      }

      final connection =
          ref.read(activeConnectionsProvider)[widget.source.id];

      // 处理需要 2FA 验证的情况
      if (connection?.status == SourceStatus.requires2FA) {
        if (mounted) {
          final result = await _show2FADialog();
          if (result != null && result.otpCode.isNotEmpty) {
            await ref.read(activeConnectionsProvider.notifier).verify2FA(
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
        title: const Text('输入密码'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(
            labelText: '密码',
            hintText: '${widget.source.username} 的密码',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('连接'),
          ),
        ],
      ),
    );
  }

  Future<void> _disconnect() async {
    await ref
        .read(activeConnectionsProvider.notifier)
        .disconnect(widget.source.id);
  }

  void _editSource() {
    // 使用新的表单页面进行编辑
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) => SourceFormPage(
          sourceType: widget.source.type,
          existingSource: widget.source,
        ),
      ),
    );
  }

  Future<void> _deleteSource() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除源'),
        content: Text('确定要删除 "${widget.source.displayName}" 吗？\n相关的媒体库配置也会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if ((confirm ?? false) && mounted) {
      try {
        await ref.read(sourcesProvider.notifier).removeSource(widget.source.id);
        if (mounted) {
          context.showSuccessToast('已删除 "${widget.source.displayName}"');
        }
      } on Exception catch (e) {
        if (mounted) {
          context.showErrorSnackBar('删除失败: $e');
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
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 标题
            Text(
              '添加连接源',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '选择要添加的连接源类型',
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
                          category.displayName,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      ...groupedTypes[category]!
                          .map((type) => _buildTypeTile(context, type)),
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
        side: BorderSide(
          color: colorScheme.outline.withValues(alpha: 0.2),
        ),
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
          child: Icon(
            type.icon,
            color: colorScheme.primary,
            size: 24,
          ),
        ),
        title: Text(
          type.displayName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          type.description,
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
          Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (context) => SourceFormPage(
                sourceType: type,
              ),
            ),
          );
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
    // 使用源类型的主题色，而不是统一的琥猥色
    final accentColor = device.type.themeColor;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: accentColor.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      color: accentColor.withValues(alpha: isDark ? 0.08 : 0.06),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            // 主图标容器
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
            // 发现徽章 - 雷达图标
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
                child: const Icon(
                  Icons.radar,
                  size: 12,
                  color: Colors.white,
                ),
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
            // 新发现标签
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '发现',
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
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add,
                size: 16,
                color: Colors.white,
              ),
              SizedBox(width: 4),
              Text(
                '添加',
                style: TextStyle(
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
    // 导航到表单页面，预填发现的设备信息
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) => SourceFormPage(
          sourceType: device.type,
          initialValues: {
            'name': device.name,
            'host': device.host,
            'port': device.port.toString(),
          },
        ),
      ),
    );
  }
}
