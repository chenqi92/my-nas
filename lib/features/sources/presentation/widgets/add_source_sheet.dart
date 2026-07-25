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
  const AddSourceSheet({this.source, super.key});

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

  bool get _allowsEmptyCredentials => switch (_sourceType) {
    SourceType.ftp ||
    SourceType.smb ||
    SourceType.webdav ||
    SourceType.upnp ||
    SourceType.jellyfin ||
    SourceType.emby => true,
    _ => false,
  };

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
                  _isEditing
                      ? context.l10n.sourcesAddEditTitleEdit
                      : context.l10n.sourcesAddEditTitleAdd,
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
                      context.l10n.sourcesSourceTypeLabel,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    _buildSourceTypeSelector(),
                    const SizedBox(height: 24),

                    // 名称
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: context.l10n.sourcesNameFieldLabel,
                        hintText: _sourceType == SourceType.local
                            ? context.l10n.sourcesNameFieldHintLocal
                            : context.l10n.sourcesNameFieldHintRemote,
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
                                    ? context.l10n.sourcesLocalStorageInfoMobile
                                    : context
                                          .l10n
                                          .sourcesLocalStorageInfoDesktop,
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
                          labelText: context.l10n.sourcesHostFieldLabel,
                          hintText: _sourceType == SourceType.smb
                              ? context.l10n.sourcesHostFieldHintSmb
                              : context.l10n.sourcesHostFieldHintOther,
                          helperText: _sourceType == SourceType.smb
                              ? context.l10n.sourcesSmbHelperText
                              : null,
                          prefixIcon: const Icon(Icons.dns_outlined),
                        ),
                        keyboardType: TextInputType.url,
                        validator: (value) {
                          if (_sourceType != SourceType.local &&
                              (value == null || value.isEmpty)) {
                            return context.l10n.sourcesHostFieldValidationEmpty;
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
                                decoration: InputDecoration(
                                  labelText: context.l10n.sourcesPortFieldLabel,
                                  prefixIcon: const Icon(Icons.numbers),
                                ),
                                keyboardType: TextInputType.number,
                                validator: (value) {
                                  if (_sourceType != SourceType.local) {
                                    if (value == null || value.isEmpty) {
                                      return context
                                          .l10n
                                          .sourcesPortFieldValidationEmpty;
                                    }
                                    final port = int.tryParse(value);
                                    if (port == null ||
                                        port < 1 ||
                                        port > 65535) {
                                      return context
                                          .l10n
                                          .sourcesPortFieldValidationInvalid;
                                    }
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Column(
                              children: [
                                Text(context.l10n.sourcesSslLabel),
                                Switch(
                                  value: _useSsl,
                                  onChanged: (v) => setState(() {
                                    final oldDefault = _defaultPortForSsl(
                                      _sourceType,
                                      _useSsl,
                                    );
                                    final current = int.tryParse(
                                      _portController.text,
                                    );
                                    _useSsl = v;
                                    if (current == oldDefault) {
                                      _portController.text = _defaultPortForSsl(
                                        _sourceType,
                                        v,
                                      ).toString();
                                    }
                                  }),
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
                        decoration: InputDecoration(
                          labelText: context.l10n.sourcesUsernameFieldLabel,
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                        validator: (value) {
                          if (_sourceType != SourceType.local &&
                              !_allowsEmptyCredentials &&
                              (value == null || value.isEmpty)) {
                            return context
                                .l10n
                                .sourcesUsernameFieldValidationEmpty;
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
                          labelText: _isEditing
                              ? context.l10n.sourcesPasswordFieldLabelEdit
                              : context.l10n.sourcesPasswordFieldLabel,
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () {
                              setState(
                                () => _obscurePassword = !_obscurePassword,
                              );
                            },
                          ),
                        ),
                        validator: (value) {
                          if (_sourceType != SourceType.local &&
                              !_allowsEmptyCredentials &&
                              !_isEditing &&
                              (value == null || value.isEmpty)) {
                            return context
                                .l10n
                                .sourcesPasswordFieldValidationEmpty;
                          }
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 24),

                    // 选项
                    if (_sourceType != SourceType.local)
                      SwitchListTile(
                        title: Text(context.l10n.sourcesAutoConnectTitle),
                        subtitle: Text(context.l10n.sourcesAutoConnectSubtitle),
                        value: _autoConnect,
                        onChanged: (v) => setState(() => _autoConnect = v),
                        contentPadding: EdgeInsets.zero,
                      ),
                    if (_sourceType != SourceType.local)
                      SwitchListTile(
                        title: Text(context.l10n.sourcesRememberDeviceTitle),
                        subtitle: Text(
                          context.l10n.sourcesRememberDeviceSubtitle,
                        ),
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
                            Icon(
                              Icons.error_outline_rounded,
                              color: AppColors.error,
                            ),
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
                            : Text(
                                _isEditing
                                    ? context.l10n.sourcesSubmitButtonSave
                                    : context.l10n.sourcesSubmitButtonAdd,
                              ),
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
                _useSsl = type.defaultUseSsl;
                _errorMessage = null;
              });
            }
          },
          avatar: Icon(_getSourceTypeIcon(type), size: 18),
        );
      }).toList(),
    );
  }

  IconData _getSourceTypeIcon(SourceType type) => type.icon;

  int _defaultPortForSsl(SourceType type, bool useSsl) => switch (type) {
    SourceType.synology => useSsl ? 5001 : 5000,
    SourceType.qnap => useSsl ? 443 : 8080,
    SourceType.webdav => useSsl ? 443 : 80,
    SourceType.jellyfin || SourceType.emby => useSsl ? 8920 : 8096,
    _ => type.defaultPort,
  };

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
            ? context.l10n.sourcesLocalStorageName
            : _nameController.text.trim(),
        type: _sourceType,
        host: isLocal ? 'localhost' : _hostController.text.trim(),
        port: isLocal ? 0 : int.parse(_portController.text.trim()),
        username: isLocal ? 'local' : _usernameController.text.trim(),
        useSsl: !isLocal && _useSsl,
        autoConnect: _autoConnect,
        rememberDevice: _rememberDevice,
        extraConfig: _sourceType == SourceType.ftp
            ? {'encryption': _useSsl ? '显式 TLS (FTPES)' : '无加密'}
            : widget.source?.extraConfig,
      );

      final password = isLocal ? '' : _passwordController.text;

      if (_isEditing) {
        // 更新源
        await ref.read(sourcesProvider.notifier).updateSource(source);

        // 如果输入了新密码，保存凭证（本地存储除外）
        if (!isLocal && password.isNotEmpty) {
          final manager = ref.read(sourceManagerProvider);
          await manager.saveCredentialRequired(
            source.id,
            SourceCredential(password: password),
          );
        }

        if (mounted) {
          Navigator.pop(context);
          context.showSuccessToast(context.l10n.sourcesSuccessUpdated);
        }
      } else {
        // 先尝试连接，只有连接成功才保存源
        final connection = await ref
            .read(activeConnectionsProvider.notifier)
            .connectNew(source, password: password);

        if (connection.status == SourceStatus.connected) {
          // 连接成功，保存源和凭证
          await _addNewSourceWithCredential(source, password);
          if (mounted) {
            Navigator.pop(context);
            context.showSuccessToast(
              context.l10n.sourcesSuccessConnected(source.displayName),
            );
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
                await _addNewSourceWithCredential(source, password);
                if (mounted) {
                  Navigator.pop(context);
                  context.showSuccessToast(
                    context.l10n.sourcesSuccessConnected(source.displayName),
                  );
                }
              } else {
                // 2FA失败，断开临时连接
                await ref
                    .read(activeConnectionsProvider.notifier)
                    .disconnect(source.id);
                setState(() {
                  _errorMessage =
                      verified.errorMessage ??
                      context.l10n.sourcesTwoFaVerificationFailed;
                });
              }
            } else {
              // 用户取消2FA，断开临时连接
              await ref
                  .read(activeConnectionsProvider.notifier)
                  .disconnect(source.id);
            }
          }
        } else {
          // 连接失败，断开临时连接
          await ref
              .read(activeConnectionsProvider.notifier)
              .disconnect(source.id);
          setState(() {
            _errorMessage =
                connection.errorMessage ?? context.l10n.sourcesConnectionFailed;
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

  Future<void> _addNewSourceWithCredential(
    SourceEntity source,
    String password,
  ) async {
    final manager = ref.read(sourceManagerProvider);
    var credentialStored = false;

    if (source.type != SourceType.local) {
      final existingCredential = await manager.getCredential(source.id);
      await manager.saveCredentialRequired(
        source.id,
        SourceCredential(
          password: password,
          deviceId: existingCredential?.deviceId,
        ),
      );
      credentialStored = true;
    }

    try {
      await ref.read(sourcesProvider.notifier).addSource(source);
    } on Exception {
      if (credentialStored) await manager.removeCredential(source.id);
      rethrow;
    }
  }

  Future<TwoFAResult?> _show2FADialog() async =>
      showTwoFASheet(context, initialRememberDevice: _rememberDevice);

  /// 将错误转换为友好的错误消息
  String _getErrorMessage(Object e) {
    final message = e.toString();

    // Keychain/安全存储错误
    if (e is PlatformException) {
      if (e.code == 'Unexpected security result code' ||
          (e.message?.contains('-34018') ?? false) ||
          (e.message?.contains('entitlement') ?? false)) {
        return context.l10n.sourcesSecurityStorageUnavailable;
      }
    }

    // 网络相关错误
    if (message.contains('Operation not permitted')) {
      return context.l10n.sourcesNetworkPermissionDenied;
    }
    if (message.contains('Connection refused')) {
      return context.l10n.sourcesConnectionRefused;
    }
    if (message.contains('Connection timed out')) {
      return context.l10n.sourcesConnectionTimeout;
    }
    if (message.contains('SocketException')) {
      return context.l10n.sourcesNetworkConnectionFailed;
    }
    if (message.contains('HandshakeException')) {
      return context.l10n.sourcesSslHandshakeFailed;
    }

    return message;
  }
}
