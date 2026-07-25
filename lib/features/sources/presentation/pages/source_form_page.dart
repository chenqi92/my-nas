import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/features/pt_sites/data/services/pt_site_api.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/domain/entities/source_form_config.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/sources/presentation/widgets/plex_auth_widget.dart';
import 'package:my_nas/features/sources/presentation/widgets/quick_connect_widget.dart';
import 'package:my_nas/features/sources/presentation/widgets/two_fa_sheet.dart';
import 'package:my_nas/features/video/data/services/opensubtitles_service.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/media_server_adapters/emby/emby_adapter.dart';
import 'package:my_nas/media_server_adapters/jellyfin/jellyfin_adapter.dart';
import 'package:my_nas/media_server_adapters/plex/plex_adapter.dart';
import 'package:my_nas/service_adapters/aria2/api/aria2_api.dart';
import 'package:my_nas/service_adapters/base/service_adapter.dart';
import 'package:my_nas/service_adapters/moviepilot/api/moviepilot_api.dart';
import 'package:my_nas/service_adapters/nastool/api/nastool_api.dart';
import 'package:my_nas/service_adapters/qbittorrent/api/qbittorrent_api.dart';
import 'package:my_nas/service_adapters/trakt/api/trakt_api.dart';
import 'package:my_nas/service_adapters/transmission/api/transmission_api.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/providers/source_defaults_provider.dart';
import 'package:my_nas/shared/utils/form_l10n.dart';

/// 表单模式
enum SourceFormMode { create, edit }

/// 服务类源连接验证未实现的异常
///
/// 用于区分"调用了 _validateConnection 但该源类型尚未实现验证逻辑"和
/// "已实现但验证失败"两种情况。前者在 UI 上提示"暂不支持自动验证"，
/// 后者提示"连接失败"。
class _ConnectionValidationNotImplementedException implements Exception {
  const _ConnectionValidationNotImplementedException(this.sourceTypeName);
  final String sourceTypeName;

  @override
  String toString() =>
      appL10n.sourceFormValidationNotImplemented(sourceTypeName);
}

class _ConnectionRequiresAuthorizationException implements Exception {
  const _ConnectionRequiresAuthorizationException(this.sourceTypeName);
  final String sourceTypeName;

  @override
  String toString() =>
      appL10n.sourceFormConnectionTestRequiresAuth(sourceTypeName);
}

/// 源表单页面
///
/// 根据源类型动态生成表单，支持创建和编辑模式
class SourceFormPage extends ConsumerStatefulWidget {
  const SourceFormPage({
    required this.sourceType,
    super.key,
    this.existingSource,
    this.initialValues,
    this.popTwice = false,
  });

  /// 源类型
  final SourceType sourceType;

  /// 编辑模式时的现有源
  final SourceEntity? existingSource;

  /// 初始值（用于从发现的设备预填）
  final Map<String, String>? initialValues;

  /// 保存后是否需要返回两次（从类型选择页进入时为 true）
  final bool popTwice;

  /// 在桌面用 Dialog 弹出表单，移动端走整页 push。
  ///
  /// 与之前直接 `Navigator.push(MaterialPageRoute)` 相比，桌面端表单不再
  /// 占据整个 detail 区域 —— 上级若是 Dialog（如选类型 sheet），关闭它后
  /// 紧接着弹 form Dialog，体验连贯且都是弹窗形态。
  static Future<T?> openAdaptive<T>(
    BuildContext context, {
    required SourceType sourceType,
    SourceEntity? existingSource,
    Map<String, String>? initialValues,
    bool popTwice = false,
  }) {
    final page = SourceFormPage(
      sourceType: sourceType,
      existingSource: existingSource,
      initialValues: initialValues,
      popTwice: popTwice,
    );

    if (context.isDesktopLayout) {
      return showDialog<T>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => Dialog(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sheet),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
            child: page,
          ),
        ),
      );
    }
    return Navigator.push<T>(
      context,
      MaterialPageRoute<T>(builder: (_) => page),
    );
  }

  SourceFormMode get mode =>
      existingSource != null ? SourceFormMode.edit : SourceFormMode.create;

  @override
  ConsumerState<SourceFormPage> createState() => _SourceFormPageState();
}

class _SourceFormPageState extends ConsumerState<SourceFormPage>
    with ConsumerTabBarVisibilityMixin {
  late final SourceFormConfig _formConfig;
  late final GlobalKey<FormState> _formKey;
  late final Map<String, dynamic> _formValues;
  late final Map<String, TextEditingController> _controllers;
  late final Set<String> _expandedSections;
  late final Map<String, GlobalKey> _sectionKeys;

  bool _isSubmitting = false;
  bool _isTesting = false;
  bool _obscurePasswords = true;

  // Quick Connect 相关状态
  bool _quickConnectAuthorized = false;
  String? _quickConnectAccessToken;
  String? _quickConnectUserId;

  // Plex Auth 相关状态
  bool _plexAuthAuthorized = false;
  String? _plexAuthToken;

  @override
  void initState() {
    super.initState();
    hideTabBar();
    _formConfig = SourceFormConfig.forType(widget.sourceType);
    _formKey = GlobalKey<FormState>();
    _formValues = {};
    _controllers = {};
    _expandedSections = {};
    _sectionKeys = {};

    _initializeFormValues();

    // 编辑模式下异步加载保存的密码
    if (widget.mode == SourceFormMode.edit && widget.existingSource != null) {
      _loadSavedCredential();
    }
  }

  /// 从安全存储加载保存的密码
  Future<void> _loadSavedCredential() async {
    if (!mounted) return;

    final sourceManager = ref.read(sourceManagerProvider);
    final credential = await sourceManager.getCredential(
      widget.existingSource!.id,
    );

    if (!mounted) return;

    if (credential != null && credential.password.isNotEmpty) {
      // 更新密码字段的值和控制器
      setState(() {
        _formValues['password'] = credential.password;
        _controllers['password']?.text = credential.password;
      });
    }
  }

  void _initializeFormValues() {
    // 初始化默认值
    for (final section in _formConfig.sections) {
      if (section.defaultExpanded) {
        _expandedSections.add(section.title);
      }

      for (final field in section.fields) {
        dynamic initialValue;

        if (widget.existingSource != null) {
          // 编辑模式：从现有源获取值
          initialValue = _getValueFromSource(widget.existingSource!, field.key);
        } else if (widget.initialValues != null &&
            widget.initialValues!.containsKey(field.key)) {
          // 从发现的设备预填
          initialValue = widget.initialValues![field.key];
        } else if (field.key == 'autoConnect') {
          // 新建源：套用全局「新建源默认自动连接」开关
          initialValue = ref.read(defaultAutoConnectProvider).toString();
        } else if (field.key == 'rememberDevice') {
          // 新建源：套用全局「新建源默认记住 2FA 设备」开关
          initialValue = ref.read(defaultRememberDeviceProvider).toString();
        }

        // 如果没有现有值，使用默认值
        initialValue ??= field.defaultValue ?? '';

        _formValues[field.key] = initialValue;

        // 为文本类型字段创建控制器（仅支持 String 类型）
        if (field.type != SourceFormFieldType.toggle &&
            field.type != SourceFormFieldType.select &&
            field.type != SourceFormFieldType.keyValueList) {
          final textValue = initialValue is String ? initialValue : '';
          _controllers[field.key] = TextEditingController(text: textValue);
        }
      }
    }
  }

  dynamic _getValueFromSource(SourceEntity source, String key) {
    switch (key) {
      case 'name':
        return source.name;
      case 'host':
        return source.host;
      case 'port':
        return source.port.toString();
      case 'username':
        return source.username;
      case 'useSsl':
        return source.useSsl.toString();
      case 'autoConnect':
        return source.autoConnect.toString();
      case 'rememberDevice':
        return source.rememberDevice.toString();
      case 'apiKey':
        return source.apiKey;
      default:
        // 从 extraConfig 中获取，保持原始类型（List、Map 等）
        final value = source.extraConfig?[key];
        // 对于复杂类型（List、Map），直接返回
        if (value is List || value is Map) {
          return value;
        }
        return value?.toString();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      appBar: AppBar(
        // 桌面端 Dialog 内用关闭图标更贴合弹窗语义；移动端保持默认返回箭头
        leading: context.isDesktopLayout
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: context.l10n.sourceFormCloseButton,
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: Text(widget.sourceType.displayName),
        centerTitle: true,
        actions: [
          if (_formConfig.testConnectionSupported)
            TextButton(
              onPressed: _isTesting || _isSubmitting ? null : _testConnection,
              child: _isTesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.l10n.sourceFormTestButton),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 表单字段（扁平化，不使用分组卡片）
              for (final section in _formConfig.sections)
                _buildFormSection(section, theme),

              // Quick Connect 认证区块（仅 Jellyfin 创建模式）
              if (_shouldShowQuickConnect) ...[
                const SizedBox(height: 16),
                _buildQuickConnectSection(theme),
              ],

              // Plex PIN 认证区块（仅 Plex PIN 码授权模式）
              if (_shouldShowPlexAuth) ...[
                const SizedBox(height: 16),
                _buildPlexAuthSection(theme),
              ],

              const SizedBox(height: 24),

              // 提交按钮
              _buildSubmitButton(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormSection(SourceFormSection section, ThemeData theme) {
    final colorScheme = theme.colorScheme;

    // 过滤可见的字段
    final visibleFields = section.fields.where((field) {
      if (field.visibilityCondition == null) return true;
      return field.visibilityCondition!(_formValues);
    }).toList();

    if (visibleFields.isEmpty) {
      return const SizedBox.shrink();
    }

    // 如果是可折叠的高级设置区块
    if (section.collapsible) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Theme(
          // 确保 ExpansionTile 内容在收起时正确裁剪
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ClipRect(
            key: _sectionKeys.putIfAbsent(section.title, GlobalKey.new),
            child: ExpansionTile(
              title: Text(
                localizeFormText(context, section.title),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: section.description != null
                  ? Text(
                      localizeFormText(context, section.description),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    )
                  : null,
              initiallyExpanded: section.defaultExpanded,
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              onExpansionChanged: (expanded) {
                setState(() {
                  if (expanded) {
                    _expandedSections.add(section.title);
                    // 展开后滚动到该区块，确保内容可见
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      final key = _sectionKeys[section.title];
                      if (key?.currentContext != null) {
                        Scrollable.ensureVisible(
                          key!.currentContext!,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          alignmentPolicy:
                              ScrollPositionAlignmentPolicy.keepVisibleAtStart,
                        );
                      }
                    });
                  } else {
                    _expandedSections.remove(section.title);
                  }
                });
              },
              children: [
                // 使用 Column 包装所有子项，确保正确的布局和裁剪
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (int i = 0; i < visibleFields.length; i++) ...[
                        _buildFormField(visibleFields[i], theme),
                        if (i < visibleFields.length - 1)
                          const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 普通区块 - 只显示分组标题（如果有多个区块）
    final showTitle = _formConfig.sections.length > 1 && !section.collapsible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              localizeFormText(context, section.title),
              style: theme.textTheme.titleSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
        for (int i = 0; i < visibleFields.length; i++) ...[
          _buildFormField(visibleFields[i], theme),
          if (i < visibleFields.length - 1) const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _buildFormField(SourceFormField field, ThemeData theme) {
    switch (field.type) {
      case SourceFormFieldType.toggle:
        return _buildToggleField(field, theme);
      case SourceFormFieldType.select:
        return _buildSelectField(field, theme);
      case SourceFormFieldType.password:
        return _buildPasswordField(field, theme);
      case SourceFormFieldType.number:
        return _buildNumberField(field, theme);
      case SourceFormFieldType.keyValueList:
        return _buildKeyValueListField(field, theme);
      default:
        return _buildTextField(field, theme);
    }
  }

  Widget _buildTextField(SourceFormField field, ThemeData theme) =>
      TextFormField(
        controller: _controllers[field.key],
        decoration: InputDecoration(
          labelText: localizeFormText(context, field.label),
          hintText: localizeFormText(context, field.placeholder),
          helperText: localizeFormText(context, field.helpText),
          helperMaxLines: 2,
          prefixIcon: _getFieldIcon(field.key),
        ),
        validator: (value) {
          if (field.required && (value == null || value.isEmpty)) {
            return context.l10n.sourceFormFieldRequired(
              localizeFormText(context, field.label),
            );
          }
          return field.validator?.call(value);
        },
        onChanged: (value) {
          setState(() {
            _formValues[field.key] = value;
          });
        },
      );

  Widget _buildPasswordField(
    SourceFormField field,
    ThemeData theme,
  ) => TextFormField(
    controller: _controllers[field.key],
    obscureText: _obscurePasswords,
    decoration: InputDecoration(
      labelText: widget.mode == SourceFormMode.edit
          ? '${localizeFormText(context, field.label)}${context.l10n.sourceFormPasswordEditModeHint}'
          : localizeFormText(context, field.label),
      hintText: localizeFormText(context, field.placeholder),
      helperText: localizeFormText(context, field.helpText),
      helperMaxLines: 2,
      prefixIcon: _getFieldIcon(field.key),
      suffixIcon: IconButton(
        icon: Icon(
          _obscurePasswords
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
        ),
        onPressed: () {
          setState(() {
            _obscurePasswords = !_obscurePasswords;
          });
        },
      ),
    ),
    validator: (value) {
      if (field.required && (value == null || value.isEmpty)) {
        // 编辑模式下密码可以为空（保持不变）
        if (widget.mode == SourceFormMode.edit) {
          return null;
        }
        return context.l10n.sourceFormPasswordRequired(
          localizeFormText(context, field.label),
        );
      }
      return field.validator?.call(value);
    },
    onChanged: (value) {
      setState(() {
        _formValues[field.key] = value;
      });
    },
  );

  Widget _buildNumberField(SourceFormField field, ThemeData theme) =>
      TextFormField(
        controller: _controllers[field.key],
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: localizeFormText(context, field.label),
          hintText: localizeFormText(context, field.placeholder),
          helperText: localizeFormText(context, field.helpText),
          helperMaxLines: 2,
          prefixIcon: _getFieldIcon(field.key),
        ),
        validator: (value) {
          if (field.required && (value == null || value.isEmpty)) {
            return context.l10n.sourceFormFieldRequired(
              localizeFormText(context, field.label),
            );
          }
          if (value != null && value.isNotEmpty) {
            final number = int.tryParse(value);
            if (number == null) {
              return context.l10n.sourceFormInvalidNumber;
            }
            if (field.key == 'port' && (number < 1 || number > 65535)) {
              return context.l10n.sourcesPortFieldValidationInvalid;
            }
          }
          return field.validator?.call(value);
        },
        onChanged: (value) {
          setState(() {
            _formValues[field.key] = value;
          });
        },
      );

  Widget _buildToggleField(SourceFormField field, ThemeData theme) {
    final value = _formValues[field.key] == 'true';

    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(localizeFormText(context, field.label)),
      subtitle: field.helpText != null
          ? Text(localizeFormText(context, field.helpText))
          : null,
      value: value,
      onChanged: (newValue) {
        setState(() {
          if (field.key == 'useSsl') {
            _updateDefaultPortForSsl(newValue);
          }
          _formValues[field.key] = newValue.toString();
        });
      },
    );
  }

  Widget _buildSelectField(SourceFormField field, ThemeData theme) {
    final currentValue =
        (_formValues[field.key] as String?) ?? field.options?.first ?? '';

    return DropdownButtonFormField<String>(
      initialValue: currentValue.isNotEmpty ? currentValue : null,
      decoration: InputDecoration(
        labelText: localizeFormText(context, field.label),
        helperText: localizeFormText(context, field.helpText),
        helperMaxLines: 2,
        prefixIcon: _getFieldIcon(field.key),
      ),
      items: field.options
          ?.map(
            (option) => DropdownMenuItem(
              value: option,
              child: Text(localizeFormText(context, option)),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() {
            _formValues[field.key] = value;
            if (field.key == 'encryption') {
              _updateDefaultFtpPort(value);
            }
            // 当认证类型改变时，重置相应的认证状态
            if (field.key == 'authType') {
              if (widget.sourceType == SourceType.jellyfin) {
                _resetQuickConnect();
              } else if (widget.sourceType == SourceType.plex) {
                _resetPlexAuth();
              }
            }
          });
        }
      },
    );
  }

  void _updateDefaultPortForSsl(bool newUseSsl) {
    final oldUseSsl = _formValues['useSsl'] == 'true';
    final current = int.tryParse(_formValues['port']?.toString() ?? '');
    final oldDefault = _defaultPortForSsl(widget.sourceType, oldUseSsl);
    if (current != oldDefault) return;
    final next = _defaultPortForSsl(widget.sourceType, newUseSsl);
    _formValues['port'] = next.toString();
    _controllers['port']?.text = next.toString();
  }

  int _defaultPortForSsl(SourceType type, bool useSsl) => switch (type) {
    SourceType.synology => useSsl ? 5001 : 5000,
    SourceType.qnap => useSsl ? 443 : 8080,
    SourceType.webdav => useSsl ? 443 : 80,
    SourceType.jellyfin || SourceType.emby => useSsl ? 8920 : 8096,
    _ => type.defaultPort,
  };

  void _updateDefaultFtpPort(String encryption) {
    final current = int.tryParse(_formValues['port']?.toString() ?? '');
    if (current != 21 && current != 990) return;
    final next = encryption == '隐式 TLS (FTPS)' ? 990 : 21;
    _formValues['port'] = next.toString();
    _controllers['port']?.text = next.toString();
  }

  /// 构建键值对列表字段（用于自定义请求头等）
  Widget _buildKeyValueListField(SourceFormField field, ThemeData theme) {
    final colorScheme = theme.colorScheme;

    // 获取当前的键值对列表
    var items = <Map<String, String>>[];
    final existingValue = _formValues[field.key];
    if (existingValue is List) {
      // 从 JSON 反序列化时，Map 可能是 Map<String, dynamic>
      // 需要正确转换类型
      for (final item in existingValue) {
        if (item is Map) {
          items.add({
            'key': item['key']?.toString() ?? '',
            'value': item['value']?.toString() ?? '',
          });
        }
      }
    } else if (existingValue is String && existingValue.isNotEmpty) {
      // 尝试解析 JSON 格式（字符串值暂不支持，保持空列表）
      items = [];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行
        Row(
          children: [
            Expanded(
              child: Text(
                localizeFormText(context, field.label),
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  items.add({'key': '', 'value': ''});
                  _formValues[field.key] = items;
                });
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(context.l10n.sourceFormAddButton),
            ),
          ],
        ),
        if (field.helpText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              localizeFormText(context, field.helpText),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),

        // 键值对列表
        if (items.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Center(
              child: Text(
                context.l10n.sourceFormKeyValueEmptyHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          ...items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  // Key 输入框
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      initialValue: item['key'],
                      decoration: InputDecoration(
                        labelText: 'Key',
                        hintText: 'x-api-key',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          items[index]['key'] = value;
                          _formValues[field.key] = items;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Value 输入框
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      initialValue: item['value'],
                      decoration: InputDecoration(
                        labelText: 'Value',
                        hintText: context.l10n.sourceFormKeyValueValueHint,
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          items[index]['value'] = value;
                          _formValues[field.key] = items;
                        });
                      },
                    ),
                  ),
                  // 删除按钮
                  IconButton(
                    icon: Icon(
                      Icons.remove_circle_outline,
                      color: colorScheme.error,
                    ),
                    onPressed: () {
                      setState(() {
                        items.removeAt(index);
                        _formValues[field.key] = items;
                      });
                    },
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  /// 检查是否需要显示 Quick Connect 组件
  bool get _shouldShowQuickConnect =>
      widget.sourceType == SourceType.jellyfin &&
      _formValues['authType'] == 'Quick Connect' &&
      widget.mode == SourceFormMode.create;

  /// 构建 Quick Connect 认证区块
  Widget _buildQuickConnectSection(ThemeData theme) {
    if (!_shouldShowQuickConnect) {
      return const SizedBox.shrink();
    }

    // 构建服务器 URL
    final host = _formValues['host'] as String? ?? '';
    final portStr = _formValues['port'] as String? ?? '';
    final useSsl = _formValues['useSsl'] == 'true';

    if (host.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.l10n.sourceFormQuickConnectRequiresHostPort,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    final protocol = useSsl ? 'https' : 'http';
    final port = int.tryParse(portStr) ?? SourceType.jellyfin.defaultPort;
    final serverUrl = '$protocol://$host:$port';

    // 如果已经授权成功，显示成功状态
    if (_quickConnectAuthorized) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.sourceFormQuickConnectSuccessTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.sourceFormCompleteConfiguration,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _resetQuickConnect,
              child: Text(context.l10n.sourceFormReAuthenticateButton),
            ),
          ],
        ),
      );
    }

    return QuickConnectWidget(
      serverUrl: serverUrl,
      onResult: _handleQuickConnectResult,
    );
  }

  /// 处理 Quick Connect 认证结果
  void _handleQuickConnectResult(QuickConnectResult result) {
    if (result.success) {
      setState(() {
        _quickConnectAuthorized = true;
        _quickConnectAccessToken = result.accessToken;
        _quickConnectUserId = result.userId;
      });
      final l = AppLocalizations.of(context);
      _showSuccessSnackBar(l.sourceFormQuickConnectAuthSuccess);
    } else {
      _showErrorSnackBar(
        result.errorMessage ?? context.l10n.sourceFormQuickConnectAuthFailed,
      );
    }
  }

  /// 重置 Quick Connect 状态
  void _resetQuickConnect() {
    setState(() {
      _quickConnectAuthorized = false;
      _quickConnectAccessToken = null;
      _quickConnectUserId = null;
    });
  }

  /// 检查是否需要显示 Plex PIN 认证组件
  bool get _shouldShowPlexAuth =>
      widget.sourceType == SourceType.plex &&
      _formValues['authType'] == 'PIN 码授权' &&
      widget.mode == SourceFormMode.create;

  /// 构建 Plex PIN 认证区块
  Widget _buildPlexAuthSection(ThemeData theme) {
    if (!_shouldShowPlexAuth) {
      return const SizedBox.shrink();
    }

    // 如果已经授权成功，显示成功状态
    if (_plexAuthAuthorized) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.sourceFormPlexAuthSuccessTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.sourceFormCompleteConfiguration,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _resetPlexAuth,
              child: Text(context.l10n.sourceFormReauthorizeButton),
            ),
          ],
        ),
      );
    }

    return PlexAuthWidget(onResult: _handlePlexAuthResult);
  }

  /// 处理 Plex PIN 认证结果
  void _handlePlexAuthResult(PlexAuthResult result) {
    if (result.success) {
      setState(() {
        _plexAuthAuthorized = true;
        _plexAuthToken = result.authToken;
      });
      final l = AppLocalizations.of(context);
      _showSuccessSnackBar(l.sourceFormPlexAccountAuthSuccess);
    } else {
      final l = AppLocalizations.of(context);
      _showErrorSnackBar(result.errorMessage ?? l.sourceFormPlexAuthFailed);
    }
  }

  /// 重置 Plex 认证状态
  void _resetPlexAuth() {
    setState(() {
      _plexAuthAuthorized = false;
      _plexAuthToken = null;
    });
  }

  /// 根据字段 key 获取对应的图标
  Icon? _getFieldIcon(String key) {
    final iconData = switch (key) {
      'name' => Icons.label_outline,
      'host' => Icons.dns_outlined,
      'port' => Icons.numbers,
      'username' => Icons.person_outline,
      'password' => Icons.lock_outline,
      'apiKey' || 'apiToken' => Icons.key,
      'clientId' => Icons.apps_rounded,
      'clientSecret' => Icons.vpn_key,
      _ => null,
    };
    return iconData != null ? Icon(iconData) : null;
  }

  Widget _buildSubmitButton(ThemeData theme) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: _isSubmitting || _isTesting ? null : _submit,
      child: _isSubmitting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              widget.mode == SourceFormMode.edit
                  ? context.l10n.sourceFormSaveButton
                  : context.l10n.sourceFormAddAndConnectButton,
            ),
    ),
  );

  Future<void> _testConnection() async {
    _syncTextFieldValues();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // 检查 Quick Connect 认证状态
    if (_shouldShowQuickConnect && !_quickConnectAuthorized) {
      _showErrorSnackBar(context.l10n.sourceFormCompleteQuickConnectAuth);
      return;
    }

    // 检查 Plex PIN 认证状态
    if (_shouldShowPlexAuth && !_plexAuthAuthorized) {
      _showErrorSnackBar(context.l10n.sourceFormCompletePlexAuth);
      return;
    }

    setState(() {
      _isTesting = true;
    });

    try {
      final source = _buildSourceEntity();

      // PT 站点使用专用的测试方法
      if (source.type == SourceType.ptSite) {
        await _testPTSiteConnection(source);
        return;
      }

      // 服务类源使用专门的测试方法
      if (source.isServiceSource) {
        await _testServiceSourceConnection(source);
        return;
      }

      final password = _formValues['password'] as String? ?? '';

      final sourceManager = ref.read(sourceManagerProvider);

      // 使用 connect 方法测试连接，但不保存凭证
      final connection = await sourceManager.connect(
        source,
        password: password,
        saveCredential: false,
      );

      if (!mounted) return;

      switch (connection.status) {
        case SourceStatus.connected:
          final l = AppLocalizations.of(context);
          _showSuccessSnackBar(l.sourceFormConnectionTestSuccess);
          // 断开测试连接
          await sourceManager.disconnect(source.id);
        case SourceStatus.requires2FA:
          _showWarningSnackBar(context.l10n.sourceFormRequires2FA);
        case SourceStatus.error:
          _showErrorSnackBar(
            context.l10n.sourceFormConnectionFailed(
              connection.errorMessage ?? context.l10n.sourceFormUnknownError,
            ),
          );
        default:
          final l = AppLocalizations.of(context);
          _showErrorSnackBar(l.sourceFormConnectionStatusError);
      }
    } on Exception catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(
        AppLocalizations.of(context).sourceFormConnectionTestFailed(e),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  /// PT 站点专用的连接测试
  Future<void> _testPTSiteConnection(SourceEntity source) async {
    try {
      // 使用 PTSiteApiFactory 创建 API 实例并测试连接
      final api = PTSiteApiFactory.create(source);
      final connected = await api.testConnection();
      api.dispose();

      if (!mounted) return;

      if (connected) {
        _showSuccessSnackBar(context.l10n.sourceFormConnectionTestSuccess);
      } else {
        _showErrorSnackBar(context.l10n.sourceFormConnectionCheckFailed);
      }
    } on _ConnectionRequiresAuthorizationException catch (e) {
      if (!mounted) return;
      _showSuccessSnackBar(
        context.l10n.sourceFormConnectionTestRequiresAuth(e.sourceTypeName),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(
        AppLocalizations.of(context).sourceFormConnectionTestFailed(e),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  /// 服务类源专用的连接测试
  Future<void> _testServiceSourceConnection(SourceEntity source) async {
    try {
      final connected = await _validateServiceSourceConnection(source);

      if (!mounted) return;

      if (connected) {
        _showSuccessSnackBar(context.l10n.sourceFormConnectionTestSuccess);
      } else {
        _showErrorSnackBar(context.l10n.sourceFormConnectionCheckFailed);
      }
    } on Exception catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(
        AppLocalizations.of(context).sourceFormConnectionTestFailed(e),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  String? _extraString(SourceEntity source, String key) {
    final text = source.extraConfig?[key]?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  DateTime? _extraDateTime(SourceEntity source, String key) {
    final raw = source.extraConfig?[key];
    if (raw is DateTime) return raw;
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  /// 验证服务类源连接
  Future<bool> _validateServiceSourceConnection(SourceEntity source) async {
    switch (source.type) {
      case SourceType.nastool:
        final authType =
            _formValues['authType'] as String? ??
            context.l10n.sourceFormAuthTypeUsernamePassword;
        final api = NasToolApi(baseUrl: source.baseUrl);
        try {
          if (authType == 'API Token') {
            // API Token 认证
            final apiToken = _formValues['apiToken'] as String? ?? '';
            if (apiToken.isEmpty) return false;
            return await api.validateApiToken(apiToken);
          } else {
            // 用户名密码登录
            final username = source.username;
            final password = _formValues['password'] as String? ?? '';
            final result = await api.login(username, password);
            return result.when(success: (_, _) => true, failure: (_) => false);
          }
        } finally {
          api.dispose();
        }
      case SourceType.qbittorrent:
        final password = _formValues['password'] as String? ?? '';
        final apiKey = _formValues['apiKey'] as String?;
        final api = QBittorrentApi(
          baseUrl: source.baseUrl,
          username: source.username.isNotEmpty ? source.username : null,
          password: password.isNotEmpty ? password : null,
          apiKey: (apiKey?.isNotEmpty ?? false) ? apiKey : null,
        );
        try {
          return await api.login();
        } finally {
          api.dispose();
        }
      case SourceType.transmission:
        final trPassword = _formValues['password'] as String? ?? '';
        final rpcPath =
            _formValues['rpcPath'] as String? ?? '/transmission/rpc';
        final trApi = TransmissionApi(
          baseUrl: source.baseUrl,
          rpcPath: rpcPath,
          username: source.username.isNotEmpty ? source.username : null,
          password: trPassword.isNotEmpty ? trPassword : null,
        );
        try {
          return await trApi.connect();
        } finally {
          trApi.dispose();
        }
      case SourceType.aria2:
        final rpcSecret = _formValues['rpcSecret'] as String?;
        final aria2Api = Aria2Api(
          baseUrl: source.baseUrl,
          rpcSecret: (rpcSecret?.isNotEmpty ?? false) ? rpcSecret : null,
        );
        try {
          return await aria2Api.connect();
        } finally {
          aria2Api.dispose();
        }
      case SourceType.moviepilot:
        final mpApiToken = _formValues['apiToken'] as String? ?? '';
        final mpApi = MoviePilotApi(
          baseUrl: source.baseUrl,
          apiToken: mpApiToken,
        );
        try {
          return await mpApi.validateConnection();
        } finally {
          mpApi.dispose();
        }
      case SourceType.jellyfin:
        final jellyfinAuthType =
            _formValues['authType'] as String? ??
            context.l10n.sourceFormAuthTypeUsernamePassword;
        final jellyfinAdapter = JellyfinAdapter();
        try {
          ServiceConnectionConfig config;
          if (jellyfinAuthType == 'Quick Connect') {
            // Quick Connect 认证 - 使用已获取的 access token
            if (!_quickConnectAuthorized || _quickConnectAccessToken == null) {
              return false;
            }
            config = ServiceConnectionConfig(
              baseUrl: source.baseUrl,
              extraConfig: {
                'accessToken': _quickConnectAccessToken,
                'userId': _quickConnectUserId,
              },
              verifySSL: !ref.read(trustSelfSignedCertProvider),
            );
          } else if (jellyfinAuthType == 'API Key') {
            config = ServiceConnectionConfig(
              baseUrl: source.baseUrl,
              apiKey: _formValues['apiKey'] as String? ?? '',
              verifySSL: !ref.read(trustSelfSignedCertProvider),
            );
          } else {
            config = ServiceConnectionConfig(
              baseUrl: source.baseUrl,
              username: source.username,
              password: _formValues['password'] as String? ?? '',
              verifySSL: !ref.read(trustSelfSignedCertProvider),
            );
          }
          final result = await jellyfinAdapter.connect(config);
          return result.when(success: (_) => true, failure: (_) => false);
        } finally {
          await jellyfinAdapter.dispose();
        }
      case SourceType.plex:
        final plexAuthType =
            _formValues['authType'] as String? ??
            context.l10n.sourceFormAuthTypePinAuthorization;
        final plexAdapter = PlexAdapter();
        try {
          String? plexToken;
          if (plexAuthType == 'PIN 码授权') {
            // PIN 码授权 - 使用已获取的 auth token
            if (!_plexAuthAuthorized || _plexAuthToken == null) {
              return false;
            }
            plexToken = _plexAuthToken;
          } else {
            // 手动输入 Token
            plexToken = _formValues['plexToken'] as String? ?? '';
            if (plexToken.isEmpty) return false;
          }

          final config = ServiceConnectionConfig(
            baseUrl: source.baseUrl,
            apiKey: plexToken,
            verifySSL: !ref.read(trustSelfSignedCertProvider),
          );
          final result = await plexAdapter.connect(config);
          return result.when(success: (_) => true, failure: (_) => false);
        } finally {
          await plexAdapter.dispose();
        }
      case SourceType.emby:
        final embyAuthType =
            _formValues['authType'] as String? ??
            context.l10n.sourceFormAuthTypeUsernamePassword;
        final embyAdapter = EmbyAdapter();
        try {
          ServiceConnectionConfig config;
          if (embyAuthType == 'API Key') {
            final apiKey = _formValues['apiKey'] as String? ?? '';
            if (apiKey.isEmpty) return false;
            config = ServiceConnectionConfig(
              baseUrl: source.baseUrl,
              apiKey: apiKey,
              verifySSL: !ref.read(trustSelfSignedCertProvider),
            );
          } else {
            config = ServiceConnectionConfig(
              baseUrl: source.baseUrl,
              username: source.username,
              password: _formValues['password'] as String? ?? '',
              verifySSL: !ref.read(trustSelfSignedCertProvider),
            );
          }
          final result = await embyAdapter.connect(config);
          return result.when(success: (_) => true, failure: (_) => false);
        } finally {
          await embyAdapter.dispose();
        }
      case SourceType.opensubtitles:
        final username = source.username.trim();
        final password = _formValues['password'] as String? ?? '';
        final apiKey = source.apiKey?.trim();
        final service = OpenSubtitlesService(
          apiKey: (apiKey?.isNotEmpty ?? false)
              ? apiKey!
              : OpenSubtitlesService.defaultApiKey,
          username: username.isNotEmpty ? username : null,
          password: password.isNotEmpty ? password : null,
        );
        return service.validateConnection();
      case SourceType.trakt:
        final clientId = _extraString(source, 'clientId');
        final clientSecret = _extraString(source, 'clientSecret');
        if (clientId == null || clientSecret == null) return false;

        final accessToken =
            source.accessToken ?? _extraString(source, 'accessToken');
        final refreshToken =
            source.refreshToken ?? _extraString(source, 'refreshToken');
        final tokenExpiresAt =
            source.tokenExpiresAt ??
            _extraDateTime(source, 'tokenExpiresAt') ??
            _extraDateTime(source, 'expiresAt');

        final traktApi = TraktApi(
          clientId: clientId,
          clientSecret: clientSecret,
          accessToken: accessToken,
          refreshToken: refreshToken,
          tokenExpiresAt: tokenExpiresAt,
        );
        try {
          if (accessToken != null && accessToken.isNotEmpty) {
            return await traktApi.validateAuthenticatedConnection();
          }
          final appCredentialsValid = await traktApi.validateAppCredentials();
          if (!appCredentialsValid) return false;
          throw _ConnectionRequiresAuthorizationException(
            source.type.displayName,
          );
        } finally {
          traktApi.dispose();
        }
      default:
        // 其它未列出的服务类型同样标记为"未实现自动验证"，让 UI 给出友好提示
        throw _ConnectionValidationNotImplementedException(
          source.type.displayName,
        );
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showWarningSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_rounded, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.warning,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _syncTextFieldValues() {
    for (final entry in _controllers.entries) {
      _formValues[entry.key] = entry.value.text;
    }
  }

  Future<void> _submit() async {
    // Accessibility input, autofill and password replacement can update a
    // TextEditingController before TextFormField.onChanged is delivered.
    // Always use the controller as the source of truth before an external
    // action.
    _syncTextFieldValues();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // 检查 Quick Connect 认证状态
    if (_shouldShowQuickConnect && !_quickConnectAuthorized) {
      _showErrorSnackBar(context.l10n.sourceFormCompleteQuickConnectAuth);
      return;
    }

    // 检查 Plex PIN 认证状态
    if (_shouldShowPlexAuth && !_plexAuthAuthorized) {
      _showErrorSnackBar(context.l10n.sourceFormCompletePlexAuth);
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final source = _buildSourceEntity();
      final password = _formValues['password'] as String? ?? '';
      final sourcesNotifier = ref.read(sourcesProvider.notifier);
      final sourceManager = ref.read(sourceManagerProvider);

      if (widget.mode == SourceFormMode.edit) {
        // 编辑模式 - 直接保存
        await sourcesNotifier.updateSource(source);

        // 如果输入了新密码，更新凭证
        if (password.isNotEmpty) {
          await sourceManager.saveCredentialRequired(
            source.id,
            SourceCredential(password: password),
          );
        }

        if (!mounted) return;
        _showSuccessAndPop(source, context.l10n.sourceFormUpdateSuccess);
      } else {
        // 创建模式 - 先验证连接再保存源
        await _submitNewSource(source, password);
      }
    } on Exception catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(context.l10n.sourceFormSaveFailed(e.toString()));
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  /// 提交新源（创建模式）
  ///
  /// 流程：先验证连接 → 如果需要2FA则弹框验证 → 成功后再保存源
  Future<void> _submitNewSource(SourceEntity source, String password) async {
    final sourceManager = ref.read(sourceManagerProvider);

    // PT 站点使用专门的处理逻辑
    if (source.type == SourceType.ptSite) {
      await _submitPTSiteSource(source);
      return;
    }

    // 服务类源使用专门的处理逻辑（排除 PT 站点，因为已在上面处理）
    if (source.isServiceSource) {
      await _submitServiceSource(source);
      return;
    }

    // 先尝试连接验证（不保存凭证）
    final connection = await sourceManager.connect(
      source,
      password: password,
      saveCredential: false,
    );

    if (!mounted) return;

    switch (connection.status) {
      case SourceStatus.connected:
        // 连接成功，保存源和凭证
        await _saveSourceAndCredential(source, password);
        if (mounted) {
          // 再次连接以更新状态（这次保存凭证）
          await ref
              .read(activeConnectionsProvider.notifier)
              .connect(source, password: password);
          _showSuccessAndPop(
            source,
            context.l10n.sourceFormConnectSuccess(source.displayName),
          );
        }

      case SourceStatus.requires2FA:
        // 需要二次验证 - 弹出验证弹框
        await _handle2FAVerification(source, password);

      case SourceStatus.error:
        // 连接失败
        // 断开临时连接
        await sourceManager.disconnect(source.id);
        _showErrorSnackBar(
          context.l10n.sourceFormConnectionFailed(
            connection.errorMessage ?? context.l10n.sourceFormUnknownError,
          ),
        );

      default:
        // 其他状态
        await sourceManager.disconnect(source.id);
        _showErrorSnackBar(context.l10n.sourceFormConnectionStatusError);
    }
  }

  /// 提交服务类源
  Future<void> _submitServiceSource(SourceEntity source) async {
    try {
      // 验证连接
      final connected = await _validateServiceSourceConnection(source);

      if (!mounted) return;

      if (connected) {
        final password = _formValues['password'] as String? ?? '';
        await _addNewSourceWithCredential(source, password);

        if (source.type.category == SourceCategory.mediaServers) {
          try {
            final connection = await ref
                .read(activeMediaServerConnectionsProvider.notifier)
                .connect(
                  source,
                  password: password.isEmpty ? null : password,
                  apiKey: source.apiKey,
                );
            if (connection.status != SourceStatus.connected) {
              throw Exception(
                connection.errorMessage ??
                    context.l10n.sourceFormConnectionCheckFailed,
              );
            }
          } on Exception {
            // 保持“验证 + 保存 + 激活连接”为一个事务，避免留下无法使用的半成品源。
            await ref.read(sourcesProvider.notifier).removeSource(source.id);
            rethrow;
          }
        }

        if (mounted) {
          _showSuccessAndPop(
            source,
            context.l10n.sourceFormAddSuccess(source.displayName),
          );
        }
      } else {
        _showErrorSnackBar(context.l10n.sourceFormConnectionCheckFailed);
      }
    } on _ConnectionRequiresAuthorizationException catch (e) {
      if (!mounted) return;
      final password = _formValues['password'] as String? ?? '';
      await _addNewSourceWithCredential(source, password);
      if (mounted) {
        _showSuccessAndPop(
          source,
          context.l10n.sourceFormServiceAddedPendingAuth(
            source.displayName,
            e.sourceTypeName,
          ),
        );
      }
    } on _ConnectionValidationNotImplementedException catch (e) {
      // 该源类型不支持表单内一键自动验证。不应阻断添加：直接保存源，并提示
      // 用户稍后到对应授权入口完成连接。
      if (!mounted) return;
      final password = _formValues['password'] as String? ?? '';
      await _addNewSourceWithCredential(source, password);
      if (mounted) {
        _showSuccessAndPop(
          source,
          context.l10n.sourceFormServiceAddedPendingAuth(
            source.displayName,
            e.sourceTypeName,
          ),
        );
      }
    } on Exception catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(context.l10n.sourceFormConnectionFailed(e.toString()));
    }
  }

  /// 提交 PT 站点源
  Future<void> _submitPTSiteSource(SourceEntity source) async {
    final sourcesNotifier = ref.read(sourcesProvider.notifier);

    try {
      // 使用 PTSiteApiFactory 创建 API 实例并测试连接
      final api = PTSiteApiFactory.create(source);
      final connected = await api.testConnection();
      api.dispose();

      if (!mounted) return;

      if (connected) {
        // 连接成功，保存源
        await sourcesNotifier.addSource(source);
        if (mounted) {
          _showSuccessAndPop(
            source,
            context.l10n.sourceFormAddSuccess(source.displayName),
          );
        }
      } else {
        _showErrorSnackBar(context.l10n.sourceFormConnectionCheckFailed);
      }
    } on Exception catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(context.l10n.sourceFormConnectionFailed(e.toString()));
    }
  }

  /// 处理2FA验证流程
  Future<void> _handle2FAVerification(
    SourceEntity source,
    String password,
  ) async {
    final sourceManager = ref.read(sourceManagerProvider);

    // 弹出带在线验证的2FA弹框
    final result = await showTwoFASheetWithVerify(
      context,
      sourceName: source.displayName,
      initialRememberDevice: source.rememberDevice,
      onVerify: (otpCode, rememberDevice) async {
        // 在线验证OTP
        final verifyResult = await sourceManager.verify2FA(
          source.id,
          otpCode,
          rememberDevice: rememberDevice,
          password: password,
        );
        return verifyResult.status == SourceStatus.connected;
      },
    );

    if (!mounted) return;

    if (result == null) {
      // 用户直接关闭弹框（不保存）
      await sourceManager.disconnect(source.id);
      return;
    }

    switch (result.resultType) {
      case TwoFAResultType.verified:
        // 验证成功，保存源和凭证
        await _saveSourceAndCredential(source, password, result.rememberDevice);
        // 刷新连接状态（verify2FA 已经更新了底层状态为 connected）
        ref.read(activeConnectionsProvider.notifier).refresh();
        if (mounted) {
          _showSuccessAndPop(
            source,
            context.l10n.sourceFormConnectSuccess(source.displayName),
          );
        }

      case TwoFAResultType.skipped:
        // 用户选择跳过验证，保存源及凭证
        await _addNewSourceWithCredential(source, password);
        // 更新连接状态（状态为 requires2FA）
        ref.read(activeConnectionsProvider.notifier).refresh();
        if (mounted) {
          _showWarningSnackBar(context.l10n.sourceFormAddSuccessRequires2FA);
          Navigator.pop(context, source);
          if (widget.popTwice && mounted && Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        }

      case TwoFAResultType.cancelled:
        // 用户取消（理论上不会到这里，因为取消时 result 为 null）
        await sourceManager.disconnect(source.id);
    }
  }

  /// 保存源和凭证
  Future<void> _saveSourceAndCredential(
    SourceEntity source,
    String password, [
    bool? rememberDevice,
  ]) async {
    // 如果指定了 rememberDevice，更新源配置
    final sourceToSave = rememberDevice != null
        ? source.copyWith(rememberDevice: rememberDevice)
        : source;

    await _addNewSourceWithCredential(sourceToSave, password);
  }

  /// Saves the password before publishing a new source to the list.
  ///
  /// This prevents a failed Keychain write from leaving a source that looks
  /// configured but asks for its password on every subsequent visit.
  Future<void> _addNewSourceWithCredential(
    SourceEntity source,
    String password,
  ) async {
    final sourceManager = ref.read(sourceManagerProvider);
    var credentialStored = false;

    if (password.isNotEmpty || source.usesPasswordAuthentication) {
      final existingCredential = await sourceManager.getCredential(source.id);
      await sourceManager.saveCredentialRequired(
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
      if (credentialStored) {
        await sourceManager.removeCredential(source.id);
      }
      rethrow;
    }
  }

  /// 显示成功提示并返回
  void _showSuccessAndPop(SourceEntity source, String message) {
    _showSuccessSnackBar(message);
    Navigator.pop(context, source);
    if (widget.popTwice && mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  SourceEntity _buildSourceEntity() {
    final name = (_formValues['name'] as String? ?? '').trim();
    final host = (_formValues['host'] as String? ?? '').trim();
    final portStr = _formValues['port'] as String? ?? '';
    final port = int.tryParse(portStr) ?? widget.sourceType.defaultPort;
    final username = (_formValues['username'] as String? ?? '').trim();
    final useSsl = _formValues['useSsl'] == 'true';
    final autoConnect = _formValues['autoConnect'] == 'true';
    final rememberDevice = _formValues['rememberDevice'] == 'true';
    final apiKey = _formValues['apiKey'] as String?;

    // 收集额外配置
    final extraConfig = <String, dynamic>{};
    final standardKeys = {
      'name',
      'host',
      'port',
      'username',
      'password',
      'useSsl',
      'autoConnect',
      'rememberDevice',
      'apiKey',
    };
    final visibleKeys = _formConfig.sections
        .expand((section) => section.fields)
        .where(
          (field) =>
              field.visibilityCondition == null ||
              field.visibilityCondition!(_formValues),
        )
        .map((field) => field.key)
        .toSet();

    for (final entry in _formValues.entries) {
      if (!standardKeys.contains(entry.key) &&
          visibleKeys.contains(entry.key) &&
          entry.value != null) {
        extraConfig[entry.key] = entry.value;
      }
    }

    // 处理 Quick Connect 认证（Jellyfin）
    var accessToken = widget.existingSource?.accessToken;
    if (_quickConnectAuthorized && _quickConnectAccessToken != null) {
      accessToken = _quickConnectAccessToken;
      // 将 userId 存入 extraConfig
      if (_quickConnectUserId != null) {
        extraConfig['userId'] = _quickConnectUserId;
      }
    }

    // 处理 Plex PIN 认证
    // Plex 使用 apiKey 字段存储 auth token
    var plexApiKey = apiKey;
    if (_plexAuthAuthorized && _plexAuthToken != null) {
      plexApiKey = _plexAuthToken;
    } else if (widget.sourceType == SourceType.plex) {
      // 如果是手动输入 Token 模式
      plexApiKey = _formValues['plexToken'] as String?;
    }

    if (widget.sourceType == SourceType.trakt) {
      final existingAccessToken =
          widget.existingSource?.accessToken ??
          widget.existingSource?.extraConfig?['accessToken']?.toString();
      final existingRefreshToken =
          widget.existingSource?.refreshToken ??
          widget.existingSource?.extraConfig?['refreshToken']?.toString();
      final existingExpiresAt =
          widget.existingSource?.tokenExpiresAt ??
          (widget.existingSource == null
              ? null
              : _extraDateTime(widget.existingSource!, 'tokenExpiresAt'));

      if (existingAccessToken != null && existingAccessToken.isNotEmpty) {
        accessToken = existingAccessToken;
        extraConfig['accessToken'] = existingAccessToken;
      }
      if (existingRefreshToken != null && existingRefreshToken.isNotEmpty) {
        extraConfig['refreshToken'] = existingRefreshToken;
      }
      if (existingExpiresAt != null) {
        extraConfig['tokenExpiresAt'] = existingExpiresAt.toIso8601String();
      }
    }

    return SourceEntity(
      id: widget.existingSource?.id,
      name: name,
      type: widget.sourceType,
      host: host,
      port: port,
      username: username,
      useSsl: useSsl,
      autoConnect: autoConnect,
      rememberDevice: rememberDevice,
      apiKey: widget.sourceType == SourceType.plex
          ? (plexApiKey?.isNotEmpty ?? false ? plexApiKey : null)
          : (apiKey?.isNotEmpty ?? false ? apiKey : null),
      extraConfig: extraConfig.isNotEmpty ? extraConfig : null,
      lastConnected: widget.existingSource?.lastConnected,
      quickConnectId: widget.existingSource?.quickConnectId,
      accessToken: accessToken,
      refreshToken: widget.existingSource?.refreshToken,
      tokenExpiresAt: widget.existingSource?.tokenExpiresAt,
    );
  }
}
