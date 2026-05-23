import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/domain/entities/scraper_form_config.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';
import 'package:my_nas/features/video/presentation/providers/scraper_provider.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

/// 刮削源表单页面
class ScraperFormPage extends ConsumerStatefulWidget {
  const ScraperFormPage({
    required this.type,
    super.key,
    this.existingSource,
  });

  /// 刮削源类型
  final ScraperType type;

  /// 编辑模式时的现有源
  final ScraperSourceEntity? existingSource;

  bool get isEditMode => existingSource != null;

  @override
  ConsumerState<ScraperFormPage> createState() => _ScraperFormPageState();
}

class _ScraperFormPageState extends ConsumerState<ScraperFormPage>
    with ConsumerTabBarVisibilityMixin {
  late final ScraperFormConfig _formConfig;
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
    _formConfig = ScraperFormConfig.forType(widget.type);
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
          final extracted = ScraperFormConfig.extractFormDataFromSource(widget.existingSource!);
          initialValue = extracted[field.key]?.toString() ?? '';
        } else {
          // 创建模式：使用默认值
          initialValue = field.defaultValue ?? '';
        }

        _formValues[field.key] = initialValue;

        // 为文本类型字段创建控制器
        if (field.type != ScraperFormFieldType.toggle) {
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
        title: Text(widget.isEditMode ? '编辑${widget.type.displayName}' : '添加${widget.type.displayName}'),
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

    return Card(
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _getTypeIcon(widget.type),
              size: 40,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.type.displayName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getTypeDescription(widget.type),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(ScraperFormSection section) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          section.title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (section.description != null) ...[
          const SizedBox(height: 4),
          Text(
            section.description!,
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

  Widget _buildField(ScraperFormField field) {
    switch (field.type) {
      case ScraperFormFieldType.toggle:
        return _buildToggleField(field);
      case ScraperFormFieldType.number:
        return _buildNumberField(field);
      case ScraperFormFieldType.password:
        return _buildPasswordField(field);
      case ScraperFormFieldType.url:
        return _buildUrlField(field);
      case ScraperFormFieldType.text:
        return _buildTextField(field);
      case ScraperFormFieldType.dropdown:
        return _buildDropdownField(field);
    }
  }

  Widget _buildTextField(ScraperFormField field) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: _controllers[field.key],
        decoration: InputDecoration(
          labelText: field.label,
          hintText: field.placeholder,
          helperText: field.helpText,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
        validator: (value) {
          if (field.required && (value == null || value.isEmpty)) {
            return '${field.label}不能为空';
          }
          return field.validator?.call(value);
        },
        onChanged: (value) => _formValues[field.key] = value,
      ),
    );

  Widget _buildPasswordField(ScraperFormField field) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: _controllers[field.key],
        obscureText: _obscurePasswords,
        decoration: InputDecoration(
          labelText: field.label,
          hintText: field.placeholder,
          helperText: field.helpText,
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
            return '${field.label}不能为空';
          }
          return field.validator?.call(value);
        },
        onChanged: (value) => _formValues[field.key] = value,
      ),
    );

  Widget _buildNumberField(ScraperFormField field) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: _controllers[field.key],
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: field.label,
          hintText: field.placeholder,
          helperText: field.helpText,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
        validator: (value) {
          if (field.required && (value == null || value.isEmpty)) {
            return '${field.label}不能为空';
          }
          if (value != null && value.isNotEmpty && int.tryParse(value) == null) {
            return '请输入有效的数字';
          }
          return field.validator?.call(value);
        },
        onChanged: (value) => _formValues[field.key] = value,
      ),
    );

  Widget _buildUrlField(ScraperFormField field) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: _controllers[field.key],
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: field.label,
          hintText: field.placeholder,
          helperText: field.helpText,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
        validator: (value) {
          if (field.required && (value == null || value.isEmpty)) {
            return '${field.label}不能为空';
          }
          if (value != null && value.isNotEmpty) {
            final uri = Uri.tryParse(value);
            if (uri == null || !uri.hasScheme) {
              return '请输入有效的 URL（包含 http:// 或 https://）';
            }
          }
          return field.validator?.call(value);
        },
        onChanged: (value) => _formValues[field.key] = value,
      ),
    );

  Widget _buildToggleField(ScraperFormField field) {
    final value = _formValues[field.key] == 'true';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SwitchListTile(
        title: Text(field.label),
        subtitle: field.helpText != null ? Text(field.helpText!) : null,
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

  Widget _buildDropdownField(ScraperFormField field) {
    final options = field.options ?? [];
    final currentValue = _formValues[field.key] as String? ?? field.defaultValue ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        initialValue: options.any((o) => o.value == currentValue) ? currentValue : options.firstOrNull?.value,
        decoration: InputDecoration(
          labelText: field.label,
          helperText: field.helpText,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
        items: options.map((option) => DropdownMenuItem<String>(
          value: option.value,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(option.label),
              if (option.description != null)
                Text(
                  option.description!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        )).toList(),
        onChanged: (value) {
          if (value != null) {
            setState(() {
              _formValues[field.key] = value;
            });
          }
        },
        validator: (value) {
          if (field.required && (value == null || value.isEmpty)) {
            return '${field.label}不能为空';
          }
          return field.validator?.call(value);
        },
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    final colorScheme = theme.colorScheme;

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
            if (_formConfig.testConnectionSupported)
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
                  label: const Text('测试'),
                ),
              ),
            if (_formConfig.testConnectionSupported) const SizedBox(width: 16),

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
                label: Text(widget.isEditMode ? '保存' : '添加'),
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
      final credential = ScraperCredential(
        apiKey: _formValues['apiKey'] as String?,
        cookie: _formValues['cookie'] as String?,
      );

      final success =
          await ref.read(scraperSourcesProvider.notifier).testConnectionWithCredential(
                widget.type,
                credential,
                apiUrl: _formValues['apiUrl'] as String?,
                requestInterval:
                    int.tryParse(_formValues['requestInterval']?.toString() ?? '') ?? 0,
              );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '连接成功' : '连接失败'),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
    } on Exception catch (e) {
      if (!mounted) return;

      context.showErrorToast('测试失败: $e');
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
      final source = ScraperFormConfig.createSourceFromFormData(
        widget.type,
        _formValues,
      );

      if (widget.isEditMode) {
        // 编辑模式：更新现有源
        final updatedSource = widget.existingSource!.copyWith(
          name: source.name,
          apiKey: source.apiKey,
          apiUrl: source.apiUrl,
          cookie: source.cookie,
          requestInterval: source.requestInterval,
        );
        await ref.read(scraperSourcesProvider.notifier).updateSource(updatedSource);
      } else {
        // 创建模式：添加新源
        await ref.read(scraperSourcesProvider.notifier).addSource(source);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isEditMode ? '已更新刮削源' : '已添加刮削源'),
        ),
      );

      Navigator.pop(context);
    } on Exception catch (e) {
      if (!mounted) return;

      context.showErrorToast('操作失败: $e');
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

  IconData _getTypeIcon(ScraperType type) => switch (type) {
        ScraperType.tmdb => Icons.movie_outlined,
        ScraperType.doubanApi => Icons.api,
        ScraperType.doubanWeb => Icons.language,
      };

  String _getTypeDescription(ScraperType type) => switch (type) {
        ScraperType.tmdb => '全球最大的影视数据库，提供丰富的电影和电视剧信息',
        ScraperType.doubanApi => '通过第三方 API 服务获取豆瓣影视数据',
        ScraperType.doubanWeb => '直接解析豆瓣网页获取数据，需要登录后的 Cookie',
      };
}
