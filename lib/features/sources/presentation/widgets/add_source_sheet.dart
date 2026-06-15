import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/sources/presentation/widgets/two_fa_sheet.dart';
import 'package:my_nas/shared/providers/source_defaults_provider.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

class AddSourceSheet extends ConsumerStatefulWidget {
  const AddSourceSheet({
    this.source,
    super.key,
  });

  final SourceEntity? source;

  @override
  ConsumerState<AddSourceSheet> createState() => _AddSourceSheetState();
}

class _AddSourceSheetState extends ConsumerState<AddSourceSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  late SourceType _sourceType;
  late bool _useSsl;
  late bool _autoConnect;
  late bool _rememberDevice;

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  /// 是否为移动端平台
  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  bool get _isEditing => widget.source != null;

  @override
  void initState() {
    super.initState();
    final source = widget.source;

    _nameController = TextEditingController(text: source?.name ?? '');
    _hostController = TextEditingController(text: source?.host ?? '');
    _portController = TextEditingController(
      text: source?.port.toString() ?? '5001',
    );
    _usernameController = TextEditingController(text: source?.username ?? '');
    _passwordController = TextEditingController();

    _sourceType = source?.type ?? SourceType.synology;
    _useSsl = source?.useSsl ?? true;
    // 新建源套用全局「新建源默认」开关；编辑时沿用源自身字段。
    _autoConnect = source?.autoConnect ?? ref.read(defaultAutoConnectProvider);
    _rememberDevice =
        source?.rememberDevice ?? ref.read(defaultRememberDeviceProvider);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // 拖动条（固定）
          const SheetDragHandle(bottomPadding: 0),

          // 标题栏（固定）
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  _isEditing ? '编辑源' : '添加源',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // 表单（可滚动区域）
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 源类型选择
                    Text(
                      '源类型',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    _buildSourceTypeSelector(),
                    const SizedBox(height: 24),

                    // 名称
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: '名称（可选）',
                        hintText: _sourceType == SourceType.local
                            ? '例如：本地文件'
                            : '给这个源起个名字',
                        prefixIcon: const Icon(Icons.label_outline),
                      ),
                    ),

                    // 本地存储提示
                    if (_sourceType == SourceType.local) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _isMobile
                                    ? '本地存储将访问设备媒体库（照片、音乐等）和应用文档目录'
                                    : '本地存储无需配置连接信息，将直接访问设备上的文件',
                                style: const TextStyle(color: Colors.blue),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // 远程源需要的字段
                    if (_sourceType != SourceType.local) ...[
                      const SizedBox(height: 16),

                      // 主机地址
                      TextFormField(
                        controller: _hostController,
                        decoration: InputDecoration(
                          labelText: '主机地址',
                          hintText: _sourceType == SourceType.smb
                              ? '192.168.1.100（仅 IP 地址，无需端口）'
                              : '192.168.1.100 或 nas.example.com',
                          helperText: _sourceType == SourceType.smb
                              ? 'SMB 使用端口 445，无需指定协议前缀'
                              : null,
                          prefixIcon: const Icon(Icons.dns_outlined),
                        ),
                        keyboardType: TextInputType.url,
                        validator: (value) {
                          if (_sourceType != SourceType.local &&
                              (value == null || value.isEmpty)) {
                            return '请输入主机地址';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // 端口和 SSL (不适用于 SMB)
                      if (_sourceType != SourceType.smb)
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _portController,
                                decoration: const InputDecoration(
                                  labelText: '端口',
                                  prefixIcon: Icon(Icons.numbers),
                                ),
                                keyboardType: TextInputType.number,
                                validator: (value) {
                                  if (_sourceType != SourceType.local) {
                                    if (value == null || value.isEmpty) {
                                      return '请输入端口';
                                    }
                                    final port = int.tryParse(value);
                                    if (port == null || port < 1 || port > 65535) {
                                      return '无效端口';
                                    }
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Column(
                              children: [
                                const Text('SSL'),
                                Switch(
                                  value: _useSsl,
                                  onChanged: (v) => setState(() => _useSsl = v),
                                ),
                              ],
                            ),
                          ],
                        ),
                      if (_sourceType != SourceType.smb)
                        const SizedBox(height: 16),

                      // 用户名
                      TextFormField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: '用户名',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) {
                          if (_sourceType != SourceType.local &&
                              (value == null || value.isEmpty)) {
                            return '请输入用户名';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // 密码
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: _isEditing ? '密码（留空保持不变）' : '密码',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () {
                              setState(() => _obscurePassword = !_obscurePassword);
                            },
                          ),
                        ),
                        validator: (value) {
                          if (_sourceType != SourceType.local &&
                              !_isEditing &&
                              (value == null || value.isEmpty)) {
                            return '请输入密码';
                          }
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 24),

                    // 选项
                    if (_sourceType != SourceType.local)
                      SwitchListTile(
                        title: const Text('自动连接'),
                        subtitle: const Text('启动时自动连接此源'),
                        value: _autoConnect,
                        onChanged: (v) => setState(() => _autoConnect = v),
                        contentPadding: EdgeInsets.zero,
                      ),
                    if (_sourceType != SourceType.local)
                      SwitchListTile(
                        title: const Text('记住设备'),
                        subtitle: const Text('跳过二次验证（如果支持）'),
                        value: _rememberDevice,
                        onChanged: (v) => setState(() => _rememberDevice = v),
                        contentPadding: EdgeInsets.zero,
                      ),

                    // 错误信息
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline_rounded, color: AppColors.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(color: AppColors.error),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // 提交按钮
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isLoading ? null : _submit,
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(_isEditing ? '保存' : '添加并连接'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceTypeSelector() {
    // 只显示已支持且在当前平台可用的源类型
    final supportedTypes = SourceType.values
        .where((t) => t.isSupported && t.isAvailableOnCurrentPlatform)
        .toList();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: supportedTypes.map((type) {
        final isSelected = _sourceType == type;

        return FilterChip(
          label: Text(type.displayName),
          selected: isSelected,
          onSelected: (selected) {
            if (selected && _sourceType != type) {
              setState(() {
                _sourceType = type;
                // 重置表单内容
                _nameController.clear();
                _hostController.clear();
                _usernameController.clear();
                _passwordController.clear();
                _portController.text = type.defaultPort.toString();
                _useSsl = type.defaultPort == 5001 || type.defaultPort == 443;
                _errorMessage = null;
              });
            }
          },
          avatar: Icon(
            _getSourceTypeIcon(type),
            size: 18,
          ),
        );
      }).toList(),
    );
  }

  IconData _getSourceTypeIcon(SourceType type) => type.icon;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 本地存储使用特殊的默认值
      final isLocal = _sourceType == SourceType.local;

      final source = SourceEntity(
        id: widget.source?.id,
        name: _nameController.text.trim().isEmpty && isLocal
            ? '本地存储'
            : _nameController.text.trim(),
        type: _sourceType,
        host: isLocal ? 'localhost' : _hostController.text.trim(),
        port: isLocal ? 0 : int.parse(_portController.text.trim()),
        username: isLocal ? 'local' : _usernameController.text.trim(),
        useSsl: !isLocal && _useSsl,
        autoConnect: _autoConnect,
        rememberDevice: _rememberDevice,
      );

      final password = isLocal ? '' : _passwordController.text;

      if (_isEditing) {
        // 更新源
        await ref.read(sourcesProvider.notifier).updateSource(source);

        // 如果输入了新密码，保存凭证（本地存储除外）
        if (!isLocal && password.isNotEmpty) {
          final manager = ref.read(sourceManagerProvider);
          await manager.saveCredential(
            source.id,
            SourceCredential(password: password),
          );
        }

        if (mounted) {
          Navigator.pop(context);
          context.showSuccessToast('源已更新');
        }
      } else {
        // 先尝试连接，只有连接成功才保存源
        final connection = await ref
            .read(activeConnectionsProvider.notifier)
            .connectNew(source, password: password);

        if (connection.status == SourceStatus.connected) {
          // 连接成功，保存源和凭证
          await ref.read(sourcesProvider.notifier).addSource(source);
          // 本地存储不需要保存凭证
          if (!isLocal) {
            final manager = ref.read(sourceManagerProvider);
            await manager.saveCredential(
              source.id,
              SourceCredential(password: password),
            );
          }
          if (mounted) {
            Navigator.pop(context);
            context.showSuccessToast('已连接到 ${source.displayName}');
          }
        } else if (connection.status == SourceStatus.requires2FA) {
          // 需要二次验证（本地存储不会触发此分支）
          if (mounted) {
            final result = await _show2FADialog();
            if (result != null && result.otpCode.isNotEmpty) {
              final verified = await ref
                  .read(activeConnectionsProvider.notifier)
                  .verify2FA(
                    source.id,
                    result.otpCode,
                    rememberDevice: result.rememberDevice,
                    password: password,
                  );

              if (verified.status == SourceStatus.connected) {
                // 2FA验证成功，保存源
                await ref.read(sourcesProvider.notifier).addSource(source);
                // 保存凭证时需要保留 verify2FA 返回的 deviceId
                if (!isLocal) {
                  final manager = ref.read(sourceManagerProvider);
                  // 先读取已保存的凭证（可能包含 deviceId）
                  final existingCredential = await manager.getCredential(source.id);
                  await manager.saveCredential(
                    source.id,
                    SourceCredential(
                      password: password,
                      deviceId: existingCredential?.deviceId,
                    ),
                  );
                }
                if (mounted) {
                  Navigator.pop(context);
                  context.showSuccessToast('已连接到 ${source.displayName}');
                }
              } else {
                // 2FA失败，断开临时连接
                await ref.read(activeConnectionsProvider.notifier).disconnect(source.id);
                setState(() {
                  _errorMessage = verified.errorMessage ?? '二次验证失败';
                });
              }
            } else {
              // 用户取消2FA，断开临时连接
              await ref.read(activeConnectionsProvider.notifier).disconnect(source.id);
            }
          }
        } else {
          // 连接失败，断开临时连接
          await ref.read(activeConnectionsProvider.notifier).disconnect(source.id);
          setState(() {
            _errorMessage = connection.errorMessage ?? '连接失败';
          });
        }
      }
    } on Exception catch (e) {
      setState(() {
        _errorMessage = _getErrorMessage(e);
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<TwoFAResult?> _show2FADialog() async => showTwoFASheet(
      context,
      initialRememberDevice: _rememberDevice,
    );

  /// 将错误转换为友好的错误消息
  String _getErrorMessage(Object e) {
    final message = e.toString();

    // Keychain/安全存储错误
    if (e is PlatformException) {
      if (e.code == 'Unexpected security result code' ||
          (e.message?.contains('-34018') ?? false) ||
          (e.message?.contains('entitlement') ?? false)) {
        return '安全存储不可用，无法保存登录信息。连接仍然成功，但下次需要重新输入密码。';
      }
    }

    // 网络相关错误
    if (message.contains('Operation not permitted')) {
      return '网络权限被拒绝，请检查系统设置';
    }
    if (message.contains('Connection refused')) {
      return '连接被拒绝，请检查地址和端口';
    }
    if (message.contains('Connection timed out')) {
      return '连接超时，请检查网络';
    }
    if (message.contains('SocketException')) {
      return '网络连接失败，请检查网络设置';
    }
    if (message.contains('HandshakeException')) {
      return 'SSL 握手失败，请检查 SSL 设置';
    }

    return message;
  }
}
