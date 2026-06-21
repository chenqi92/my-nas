import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/music/data/services/music_scraper_factory.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_form_config.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/presentation/providers/music_scraper_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/utils/form_l10n.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

/// 音乐刮削源表单页面
class MusicScraperFormPage extends ConsumerStatefulWidget {
  const MusicScraperFormPage({
    required this.type,
    super.key,
    this.existingSource,
  });

  /// 刮削源类型
  final MusicScraperType type;

  /// 编辑模式时的现有源
  final MusicScraperSourceEntity? existingSource;

  bool get isEditMode => existingSource != null;

  @override
  ConsumerState<MusicScraperFormPage> createState() => _MusicScraperFormPageState();
}

class _MusicScraperFormPageState extends ConsumerState<MusicScraperFormPage>
    with ConsumerTabBarVisibilityMixin {
  late final MusicScraperFormConfig _formConfig;
  late final GlobalKey<FormState> _formKey;
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, dynamic> _formValues;

  bool _isSubmitting = false;
  bool _isTesting = false;
  bool _obscurePasswords = true;

  @override
  void initState() {
    super.initState();
    hideTabBar();
    _formConfig = MusicScraperFormConfig.forType(widget.type);
    _formKey = GlobalKey<FormState>();
    _controllers = {};
    _formValues = {};

    _initializeFormValues();
  }

  void _initializeFormValues() {
    for (final section in _formConfig.sections) {
      for (final field in section.fields) {
        String initialValue;

        if (widget.existingSource != null) {
          // 编辑模式：从现有源获取值
          final extracted = MusicScraperFormConfig.extractFormDataFromSource(widget.existingSource!);
          initialValue = extracted[field.key]?.toString() ?? '';
        } else {
          // 创建模式：使用默认值
          initialValue = field.defaultValue ?? '';
        }

        _formValues[field.key] = initialValue;

        // 为文本类型字段创建控制器
        if (field.type != MusicScraperFormFieldType.toggle) {
          _controllers[field.key] = TextEditingController(text: initialValue);
        }
      }
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
        leading: const RoundedBackButton(),
        title: Text(widget.isEditMode ? context.l10n.musicScraperFormPageTitleEdit(widget.type.displayName) : context.l10n.musicScraperFormPageTitleAdd(widget.type.displayName)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 16 + bottomInset + 80, // 为底部按钮留出空间
          ),
          children: [
            // 类型说明卡片
            _buildTypeInfoCard(theme),
            const SizedBox(height: 16),

            // 表单分组
            ..._formConfig.sections.map(_buildSection),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(theme),
    );
  }

  Widget _buildTypeInfoCard(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final isImplemented = MusicScraperFactory.isImplemented(widget.type);

    return Card(
      color: widget.type.themeColor.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              widget.type.icon,
              size: 40,
              color: widget.type.themeColor,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        widget.type.displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (!isImplemented) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            context.l10n.musicScraperFormPageComingSoon,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.type.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildCapabilityRow(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapabilityRow(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final caps = <Widget>[];

    if (widget.type.supportsMetadata) {
      caps.add(_buildCapabilityChip(context.l10n.musicScraperFormPageCapabilityMetadata, colorScheme.primaryContainer, theme));
    }
    if (widget.type.supportsCover) {
      caps.add(_buildCapabilityChip(context.l10n.musicScraperFormPageCapabilityCover, colorScheme.secondaryContainer, theme));
    }
    if (widget.type.supportsLyrics) {
      caps.add(_buildCapabilityChip(context.l10n.musicScraperFormPageCapabilityLyrics, colorScheme.tertiaryContainer, theme));
    }
    if (widget.type.supportsFingerprint) {
      caps.add(_buildCapabilityChip(context.l10n.musicScraperFormPageCapabilityFingerprint, colorScheme.errorContainer, theme));
    }

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: caps,
    );
  }

  Widget _buildCapabilityChip(String label, Color color, ThemeData theme) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall,
        ),
      );

  Widget _buildSection(MusicScraperFormSection section) {
    final theme = Theme.of(context);

    // 跳过没有字段的section（只有描述的说明性section）
    if (section.fields.isEmpty && section.description != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Card(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      localizeFormText(context, section.description),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          localizeFormText(context, section.title),
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (section.description != null) ...[
          const SizedBox(height: 4),
          Text(
            localizeFormText(context, section.description),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        ...section.fields.map(_buildField),
      ],
    );
  }

  Widget _buildField(MusicScraperFormField field) {
    switch (field.type) {
      case MusicScraperFormFieldType.toggle:
        return _buildToggleField(field);
      case MusicScraperFormFieldType.number:
        return _buildNumberField(field);
      case MusicScraperFormFieldType.password:
        return _buildPasswordField(field);
      case MusicScraperFormFieldType.url:
        return _buildUrlField(field);
      case MusicScraperFormFieldType.text:
        return _buildTextField(field);
    }
  }

  Widget _buildTextField(MusicScraperFormField field) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          controller: _controllers[field.key],
          decoration: InputDecoration(
            labelText: localizeFormText(context, field.label),
            hintText: localizeFormText(context, field.placeholder),
            helperText: localizeFormText(context, field.helpText),
            helperMaxLines: 3,
            border: const OutlineInputBorder(),
          ),
          validator: (value) {
            if (field.required && (value == null || value.isEmpty)) {
              return context.l10n.musicScraperFormPageValidationFieldRequired(localizeFormText(context, field.label));
            }
            return field.validator?.call(value);
          },
          onChanged: (value) => _formValues[field.key] = value,
        ),
      );

  Widget _buildPasswordField(MusicScraperFormField field) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          controller: _controllers[field.key],
          obscureText: _obscurePasswords,
          decoration: InputDecoration(
            labelText: localizeFormText(context, field.label),
            hintText: localizeFormText(context, field.placeholder),
            helperText: localizeFormText(context, field.helpText),
            helperMaxLines: 3,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscurePasswords ? Icons.visibility_rounded : Icons.visibility_off_rounded),
              onPressed: () {
                setState(() {
                  _obscurePasswords = !_obscurePasswords;
                });
              },
            ),
          ),
          validator: (value) {
            if (field.required && (value == null || value.isEmpty)) {
              return context.l10n.musicScraperFormPageValidationFieldRequired(localizeFormText(context, field.label));
            }
            return field.validator?.call(value);
          },
          onChanged: (value) => _formValues[field.key] = value,
        ),
      );

  Widget _buildNumberField(MusicScraperFormField field) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          controller: _controllers[field.key],
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: localizeFormText(context, field.label),
            hintText: localizeFormText(context, field.placeholder),
            helperText: localizeFormText(context, field.helpText),
            helperMaxLines: 3,
            border: const OutlineInputBorder(),
          ),
          validator: (value) {
            if (field.required && (value == null || value.isEmpty)) {
              return context.l10n.musicScraperFormPageValidationFieldRequired(localizeFormText(context, field.label));
            }
            if (value != null && value.isNotEmpty && int.tryParse(value) == null) {
              return context.l10n.musicScraperFormPageValidationNumberInvalid;
            }
            return field.validator?.call(value);
          },
          onChanged: (value) => _formValues[field.key] = value,
        ),
      );

  Widget _buildUrlField(MusicScraperFormField field) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          controller: _controllers[field.key],
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: localizeFormText(context, field.label),
            hintText: localizeFormText(context, field.placeholder),
            helperText: localizeFormText(context, field.helpText),
            helperMaxLines: 3,
            border: const OutlineInputBorder(),
          ),
          validator: (value) {
            if (field.required && (value == null || value.isEmpty)) {
              return context.l10n.musicScraperFormPageValidationFieldRequired(localizeFormText(context, field.label));
            }
            if (value != null && value.isNotEmpty) {
              final uri = Uri.tryParse(value);
              if (uri == null || !uri.hasScheme) {
                return context.l10n.musicScraperFormPageValidationUrlInvalid;
              }
            }
            return field.validator?.call(value);
          },
          onChanged: (value) => _formValues[field.key] = value,
        ),
      );

  Widget _buildToggleField(MusicScraperFormField field) {
    final value = _formValues[field.key] == 'true';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SwitchListTile(
        title: Text(localizeFormText(context, field.label)),
        subtitle: field.helpText != null ? Text(localizeFormText(context, field.helpText)) : null,
        value: value,
        onChanged: (newValue) {
          setState(() {
            _formValues[field.key] = newValue.toString();
          });
        },
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final isImplemented = MusicScraperFactory.isImplemented(widget.type);

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: colorScheme.outlineVariant,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // 测试连接按钮
            if (_formConfig.testConnectionSupported && isImplemented)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isTesting || _isSubmitting ? null : _testConnection,
                  icon: _isTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: Text(context.l10n.musicScraperFormPageTestButton),
                ),
              ),
            if (_formConfig.testConnectionSupported && isImplemented) const SizedBox(width: 16),

            // 保存按钮
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _isSubmitting || _isTesting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(widget.isEditMode ? context.l10n.musicScraperFormPageSaveButton : context.l10n.musicScraperFormPageAddButton),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testConnection() async {
    // 同步表单值
    _syncFormValues();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isTesting = true;
    });

    try {
      final manager = ref.read(musicScraperManagerProvider);
      await manager.init();

      // 创建临时源进行测试
      final source = MusicScraperFormConfig.createSourceFromFormData(
        widget.type,
        _formValues,
      );

      final scraper = MusicScraperFactory.create(source);
      final success = await scraper.testConnection();
      scraper.dispose();

      if (!mounted) return;

      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? l.musicScraperConnectionSuccessful : l.musicScraperConnectionFailed),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
    } on Exception catch (e) {
      if (!mounted) return;

      context.showErrorToast(context.l10n.musicScraperFormPageTestFailed(e));
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    // 同步表单值
    _syncFormValues();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // 创建刮削源实体
      final source = MusicScraperFormConfig.createSourceFromFormData(
        widget.type,
        _formValues,
      );

      if (widget.isEditMode) {
        // 编辑模式：更新现有源
        final updatedSource = widget.existingSource!.copyWith(
          name: source.name,
          apiKey: source.apiKey,
          cookie: source.cookie,
        );
        await ref.read(musicScraperSourcesProvider.notifier).updateSource(updatedSource);
      } else {
        // 创建模式：添加新源
        await ref.read(musicScraperSourcesProvider.notifier).addSource(source);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isEditMode ? context.l10n.musicScraperFormPageSourceUpdated : context.l10n.musicScraperFormPageSourceAdded),
        ),
      );

      Navigator.pop(context);
    } on Exception catch (e) {
      if (!mounted) return;

      context.showErrorToast(context.l10n.musicScraperFormPageOperationFailed(e));
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  /// 从控制器同步表单值
  void _syncFormValues() {
    for (final entry in _controllers.entries) {
      _formValues[entry.key] = entry.value.text;
    }
  }
}
