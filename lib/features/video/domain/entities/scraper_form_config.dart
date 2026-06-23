import 'package:my_nas/features/video/domain/entities/scraper_source.dart';

/// 刮削源表单字段类型
enum ScraperFormFieldType {
  text,
  password,
  number,
  url,
  toggle,
  dropdown,
}

/// 下拉选项
class ScraperFormOption {
  const ScraperFormOption({
    required this.value,
    required this.label,
    this.description,
  });

  /// 选项值
  final String value;

  /// 显示文本
  final String label;

  /// 描述文本
  final String? description;
}

/// 刮削源表单字段配置
class ScraperFormField {
  const ScraperFormField({
    required this.key,
    required this.label,
    this.placeholder,
    this.helpText,
    this.required = true,
    this.type = ScraperFormFieldType.text,
    this.defaultValue,
    this.validator,
    this.options,
  });

  /// 字段键名
  final String key;

  /// 字段标签
  final String label;

  /// 占位文本
  final String? placeholder;

  /// 帮助文本
  final String? helpText;

  /// 是否必填
  final bool required;

  /// 字段类型
  final ScraperFormFieldType type;

  /// 默认值
  final String? defaultValue;

  /// 自定义验证器
  final String? Function(String?)? validator;

  /// 下拉选项（仅 dropdown 类型使用）
  final List<ScraperFormOption>? options;
}

/// 刮削源表单分组配置
class ScraperFormSection {
  const ScraperFormSection({
    required this.title,
    required this.fields,
    this.description,
  });

  /// 分组标题
  final String title;

  /// 分组描述
  final String? description;

  /// 分组内的字段
  final List<ScraperFormField> fields;
}

/// 刮削源类型表单配置
class ScraperFormConfig {
  const ScraperFormConfig({
    required this.type,
    required this.sections,
    this.testConnectionSupported = true,
  });

  /// 刮削源类型
  final ScraperType type;

  /// 表单分组
  final List<ScraperFormSection> sections;

  /// 是否支持测试连接
  final bool testConnectionSupported;

  /// 获取指定刮削源类型的表单配置
  static ScraperFormConfig forType(ScraperType type) => switch (type) {
        ScraperType.tmdb => _getTmdbConfig(),
        ScraperType.doubanApi => _getDoubanApiConfig(),
        ScraperType.doubanWeb => _getDoubanWebConfig(),
      };

  // === TMDB 配置 ===
  static ScraperFormConfig _getTmdbConfig() => const ScraperFormConfig(
        type: ScraperType.tmdb,
        sections: [
          ScraperFormSection(
            title: '基本信息',
            fields: [
              ScraperFormField(
                key: 'name',
                label: '名称',
                placeholder: 'TMDB',
                required: false,
                helpText: '自定义名称，留空使用默认名称',
              ),
            ],
          ),
          ScraperFormSection(
            title: 'API 配置',
            description: '在 themoviedb.org 注册账号并申请 API Key',
            fields: [
              ScraperFormField(
                key: 'apiKey',
                label: 'API Key',
                type: ScraperFormFieldType.password,
                placeholder: '输入 TMDB API Key',
                helpText: '在 TMDB 网站的 API 设置页面获取',
              ),
              // 仅内置 TMDB 官方端点；第三方代理会把用户 API Key 路由到他人
              // 服务器，不再硬编码（合规要求），需要代理的用户用「自定义」填写。
              ScraperFormField(
                key: 'apiUrl',
                label: 'API 服务器',
                type: ScraperFormFieldType.dropdown,
                defaultValue: 'https://api.themoviedb.org/3',
                helpText: '选择 TMDB 官方端点，或填写自定义代理地址',
                required: false,
                options: [
                  ScraperFormOption(
                    value: 'https://api.themoviedb.org/3',
                    label: 'TMDB 官方',
                    description: 'api.themoviedb.org（默认）',
                  ),
                  ScraperFormOption(
                    value: 'https://api.tmdb.org/3',
                    label: 'TMDB 备用',
                    description: 'api.tmdb.org',
                  ),
                ],
              ),
            ],
          ),
          ScraperFormSection(
            title: '图片代理',
            description: '默认使用 TMDB 官方图片服务器，国内访问可能较慢',
            fields: [
              ScraperFormField(
                key: 'imageProxy',
                label: '图片代理地址',
                type: ScraperFormFieldType.url,
                placeholder: '留空使用官方源 image.tmdb.org',
                required: false,
                helpText: '自定义图片代理地址，如 https://images.tmdb.org 或其他代理服务',
              ),
            ],
          ),
        ],
      );

  // === 豆瓣 API 配置 ===
  static ScraperFormConfig _getDoubanApiConfig() => const ScraperFormConfig(
        type: ScraperType.doubanApi,
        sections: [
          ScraperFormSection(
            title: '基本信息',
            fields: [
              ScraperFormField(
                key: 'name',
                label: '名称',
                placeholder: '豆瓣 API',
                required: false,
                helpText: '自定义名称，留空使用默认名称',
              ),
            ],
          ),
          ScraperFormSection(
            title: 'API 配置',
            description: '使用第三方豆瓣 API 服务（如 NeoDB）',
            fields: [
              ScraperFormField(
                key: 'apiUrl',
                label: 'API 地址',
                type: ScraperFormFieldType.url,
                placeholder: 'https://api.example.com',
                helpText: '第三方豆瓣 API 服务地址',
              ),
              ScraperFormField(
                key: 'apiKey',
                label: 'API Key',
                type: ScraperFormFieldType.password,
                placeholder: '如果需要的话',
                required: false,
                helpText: '部分 API 服务需要 Key',
              ),
            ],
          ),
        ],
      );

  // === 豆瓣网页配置 ===
  static ScraperFormConfig _getDoubanWebConfig() => const ScraperFormConfig(
        type: ScraperType.doubanWeb,
        sections: [
          ScraperFormSection(
            title: '基本信息',
            fields: [
              ScraperFormField(
                key: 'name',
                label: '名称',
                placeholder: '豆瓣网页',
                required: false,
                helpText: '自定义名称，留空使用默认名称',
              ),
            ],
          ),
          ScraperFormSection(
            title: 'Cookie 配置',
            description: '通过解析豆瓣网页获取数据，需要登录后的 Cookie',
            fields: [
              ScraperFormField(
                key: 'cookie',
                label: 'Cookie',
                type: ScraperFormFieldType.password,
                placeholder: '从浏览器复制登录后的 Cookie',
                helpText: '登录豆瓣后，从浏览器开发者工具获取 Cookie\n'
                    '频繁请求可能触发验证码或被封禁',
              ),
            ],
          ),
          ScraperFormSection(
            title: '请求设置',
            description: '控制请求频率避免被封禁',
            fields: [
              ScraperFormField(
                key: 'requestInterval',
                label: '请求间隔（秒）',
                type: ScraperFormFieldType.number,
                defaultValue: '3',
                required: false,
                helpText: '两次请求之间的最小间隔，建议不低于 3 秒',
              ),
            ],
          ),
        ],
      );

  /// 从表单数据创建刮削源实体
  static ScraperSourceEntity createSourceFromFormData(
    ScraperType type,
    Map<String, dynamic> formData,
  ) {
    final name = formData['name'] as String?;

    // 处理 TMDB 的图片代理配置
    Map<String, dynamic>? extraConfig;
    if (type == ScraperType.tmdb) {
      final imageProxy = formData['imageProxy'] as String?;
      if (imageProxy != null && imageProxy.isNotEmpty) {
        extraConfig = {'imageProxy': imageProxy};
      }
    } else if (type == ScraperType.doubanWeb) {
      final requestInterval = int.tryParse(formData['requestInterval']?.toString() ?? '');
      if (requestInterval != null && requestInterval > 0) {
        extraConfig = {'requestInterval': requestInterval};
      }
    }

    return ScraperSourceEntity(
      name: (name?.isNotEmpty ?? false) ? name! : type.displayName,
      type: type,
      apiKey: formData['apiKey'] as String?,
      apiUrl: formData['apiUrl'] as String?,
      cookie: formData['cookie'] as String?,
      extraConfig: extraConfig,
      isEnabled: true,
      priority: 0, // 将由 manager 设置
    );
  }

  /// 从刮削源实体提取表单数据
  static Map<String, dynamic> extractFormDataFromSource(ScraperSourceEntity source) => {
        'name': source.name != source.type.displayName ? source.name : '',
        'apiKey': source.apiKey ?? '',
        'apiUrl': source.apiUrl ?? (source.type == ScraperType.tmdb ? 'https://api.themoviedb.org/3' : ''),
        'cookie': source.cookie ?? '',
        'requestInterval': source.requestInterval.toString(),
        'imageProxy': source.extraConfig?['imageProxy'] as String? ?? '',
      };
}
