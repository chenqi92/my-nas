import 'package:my_nas/features/sources/domain/entities/source_entity.dart';

/// 表单字段类型
enum SourceFormFieldType {
  text,
  password,
  number,
  url,
  toggle,
  select,
  keyValueList, // 键值对列表，用于自定义请求头等
}

/// 表单字段配置
class SourceFormField {
  const SourceFormField({
    required this.key,
    required this.label,
    this.placeholder,
    this.helpText,
    this.required = true,
    this.type = SourceFormFieldType.text,
    this.defaultValue,
    this.options,
    this.validator,
    this.visibilityCondition,
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
  final SourceFormFieldType type;

  /// 默认值
  final String? defaultValue;

  /// 选项列表（用于下拉选择）
  final List<String>? options;

  /// 自定义验证器
  final String? Function(String?)? validator;

  /// 可见性条件（基于其他字段的值）
  final bool Function(Map<String, dynamic>)? visibilityCondition;
}

/// 表单分组配置
class SourceFormSection {
  const SourceFormSection({
    required this.title,
    required this.fields,
    this.collapsible = false,
    this.defaultExpanded = true,
    this.description,
  });

  /// 分组标题
  final String title;

  /// 分组描述
  final String? description;

  /// 分组内的字段
  final List<SourceFormField> fields;

  /// 是否可折叠
  final bool collapsible;

  /// 默认是否展开
  final bool defaultExpanded;
}

/// 源类型表单配置
class SourceFormConfig {
  const SourceFormConfig({
    required this.type,
    required this.sections,
    this.testConnectionSupported = true,
    this.oauthRequired = false,
  });

  /// 源类型
  final SourceType type;

  /// 表单分组
  final List<SourceFormSection> sections;

  /// 是否支持测试连接
  final bool testConnectionSupported;

  /// 是否需要 OAuth 认证流程
  final bool oauthRequired;

  /// 获取指定源类型的表单配置
  static SourceFormConfig forType(SourceType type) {
    switch (type) {
      // === NAS 设备 ===
      case SourceType.synology:
        return _getSynologyConfig();
      case SourceType.qnap:
        return _getQnapConfig();
      case SourceType.ugreen:
        return _getUgreenConfig();
      case SourceType.fnos:
        return _getFnosConfig();

      // === 通用协议 ===
      case SourceType.webdav:
        return _getWebdavConfig();
      case SourceType.smb:
        return _getSmbConfig();
      case SourceType.ftp:
        return _getFtpConfig();
      case SourceType.sftp:
        return _getSftpConfig();
      case SourceType.s3:
        return _getS3Config();
      case SourceType.nfs:
        return _getNfsConfig();
      case SourceType.upnp:
        return _getUpnpConfig();

      // === 本地存储 ===
      case SourceType.local:
        return _getLocalConfig();

      // === 下载工具 ===
      case SourceType.qbittorrent:
        return _getQbittorrentConfig();
      case SourceType.transmission:
        return _getTransmissionConfig();
      case SourceType.aria2:
        return _getAria2Config();

      // === 媒体追踪 ===
      case SourceType.trakt:
        return _getTraktConfig();

      // === 媒体管理 ===
      case SourceType.nastool:
        return _getNastoolConfig();
      case SourceType.moviepilot:
        return _getMoviepilotConfig();
      case SourceType.jellyfin:
        return _getJellyfinConfig();
      case SourceType.emby:
        return _getEmbyConfig();
      case SourceType.plex:
        return _getPlexConfig();

      // === PT 站点 ===
      case SourceType.ptSite:
        return _getPTSiteConfig();

      // === 字幕站点 ===
      case SourceType.opensubtitles:
        return _getOpenSubtitlesConfig();
    }
  }

  // === NAS 设备配置 ===

  static SourceFormConfig _getSynologyConfig() => SourceFormConfig(
    type: SourceType.synology,
    sections: [
      _basicInfoSection(),
      SourceFormSection(
        title: '连接配置',
        fields: [
          const SourceFormField(
            key: 'host',
            label: '主机地址',
            placeholder: '192.168.1.100 或 your-nas.synology.me',
            helpText: '支持 IP 地址或 QuickConnect ID',
          ),
          SourceFormField(
            key: 'port',
            label: '端口',
            type: SourceFormFieldType.number,
            defaultValue: SourceType.synology.defaultPort.toString(),
          ),
          const SourceFormField(
            key: 'useSsl',
            label: '使用 HTTPS',
            type: SourceFormFieldType.toggle,
            defaultValue: 'true',
          ),
        ],
      ),
      _credentialSection(),
      _advancedSection(),
    ],
  );

  static SourceFormConfig _getQnapConfig() => SourceFormConfig(
    type: SourceType.qnap,
    sections: [
      _basicInfoSection(),
      SourceFormSection(
        title: '连接配置',
        fields: [
          const SourceFormField(
            key: 'host',
            label: '主机地址',
            placeholder: '192.168.1.100',
          ),
          SourceFormField(
            key: 'port',
            label: '端口',
            type: SourceFormFieldType.number,
            defaultValue: SourceType.qnap.defaultPort.toString(),
          ),
          const SourceFormField(
            key: 'useSsl',
            label: '使用 HTTPS',
            type: SourceFormFieldType.toggle,
            defaultValue: 'false',
          ),
        ],
      ),
      _credentialSection(),
      _advancedSection(),
    ],
  );

  static SourceFormConfig _getUgreenConfig() => SourceFormConfig(
    type: SourceType.ugreen,
    sections: [
      _basicInfoSection(),
      SourceFormSection(
        title: '连接配置',
        fields: [
          const SourceFormField(
            key: 'host',
            label: '主机地址',
            placeholder: '192.168.1.100',
          ),
          SourceFormField(
            key: 'port',
            label: '端口',
            type: SourceFormFieldType.number,
            defaultValue: SourceType.ugreen.defaultPort.toString(),
          ),
          const SourceFormField(
            key: 'useSsl',
            label: '使用 HTTPS',
            type: SourceFormFieldType.toggle,
            defaultValue: 'false',
          ),
        ],
      ),
      _credentialSection(),
      _advancedSection(),
    ],
  );

  static SourceFormConfig _getFnosConfig() => SourceFormConfig(
    type: SourceType.fnos,
    sections: [
      _basicInfoSection(),
      SourceFormSection(
        title: '连接配置',
        fields: [
          const SourceFormField(
            key: 'host',
            label: '主机地址',
            placeholder: '192.168.1.100',
          ),
          SourceFormField(
            key: 'port',
            label: '端口',
            type: SourceFormFieldType.number,
            defaultValue: SourceType.fnos.defaultPort.toString(),
          ),
          const SourceFormField(
            key: 'useSsl',
            label: '使用 HTTPS',
            type: SourceFormFieldType.toggle,
            defaultValue: 'false',
          ),
        ],
      ),
      _credentialSection(),
      _advancedSection(),
    ],
  );

  // === 通用协议配置 ===

  static SourceFormConfig _getWebdavConfig() => SourceFormConfig(
    type: SourceType.webdav,
    sections: [
      _basicInfoSection(),
      SourceFormSection(
        title: '连接配置',
        fields: [
          const SourceFormField(
            key: 'host',
            label: '服务器地址',
            placeholder: 'webdav.example.com',
            helpText: '不需要包含协议前缀（http/https）',
          ),
          SourceFormField(
            key: 'port',
            label: '端口',
            type: SourceFormFieldType.number,
            defaultValue: SourceType.webdav.defaultPort.toString(),
          ),
          const SourceFormField(
            key: 'useSsl',
            label: '使用 HTTPS',
            type: SourceFormFieldType.toggle,
            defaultValue: 'true',
          ),
          const SourceFormField(
            key: 'basePath',
            label: '基础路径',
            placeholder: '/dav 或 /webdav',
            required: false,
            helpText: '可选，WebDAV 服务的基础路径',
          ),
        ],
      ),
      _credentialSection(optional: true),
      _advancedSection(),
    ],
  );

  static SourceFormConfig _getSmbConfig() => SourceFormConfig(
    type: SourceType.smb,
    sections: [
      _basicInfoSection(),
      SourceFormSection(
        title: '连接配置',
        description: 'SMB 协议使用固定端口 445',
        fields: [
          const SourceFormField(
            key: 'host',
            label: '主机地址',
            placeholder: '192.168.1.100',
            helpText: '仅支持 IP 地址',
          ),
          const SourceFormField(
            key: 'shareName',
            label: '共享名称',
            placeholder: 'share 或 share/folder',
            required: false,
            helpText: '可选，留空显示所有共享，可包含子目录如 share/music',
          ),
        ],
      ),
      _credentialSection(optional: true),
      _advancedSection(),
    ],
  );

  static SourceFormConfig _getFtpConfig() => SourceFormConfig(
    type: SourceType.ftp,
    sections: [
      _basicInfoSection(),
      SourceFormSection(
        title: '连接配置',
        fields: [
          const SourceFormField(
            key: 'host',
            label: '主机地址',
            placeholder: '192.168.1.100 或 ftp.example.com',
          ),
          SourceFormField(
            key: 'port',
            label: '端口',
            type: SourceFormFieldType.number,
            defaultValue: SourceType.ftp.defaultPort.toString(),
          ),
          const SourceFormField(
            key: 'encryption',
            label: '加密方式',
            type: SourceFormFieldType.select,
            options: ['无加密', '隐式 TLS (FTPS)', '显式 TLS (FTPES)'],
            defaultValue: '无加密',
            helpText: 'FTPS 使用端口 990，FTPES 使用端口 21',
          ),
          const SourceFormField(
            key: 'path',
            label: '初始目录',
            placeholder: '/home/user 或 /public',
            required: false,
            helpText: '可选，连接后默认进入的目录',
          ),
        ],
      ),
      _credentialSection(optional: true),
      _advancedSection(),
    ],
  );

  static SourceFormConfig _getSftpConfig() => SourceFormConfig(
    type: SourceType.sftp,
    sections: [
      _basicInfoSection(),
      SourceFormSection(
        title: '连接配置',
        fields: [
          const SourceFormField(
            key: 'host',
            label: '主机地址',
            placeholder: '192.168.1.100 或 server.example.com',
          ),
          SourceFormField(
            key: 'port',
            label: '端口',
            type: SourceFormFieldType.number,
            defaultValue: SourceType.sftp.defaultPort.toString(),
          ),
          const SourceFormField(
            key: 'path',
            label: '初始目录',
            placeholder: '/home/user 或 /var/data',
            required: false,
            helpText: '可选，连接后默认进入的目录',
          ),
        ],
      ),
      SourceFormSection(
        title: '认证配置',
        fields: [
          const SourceFormField(
            key: 'username',
            label: '用户名',
            placeholder: 'root',
          ),
          const SourceFormField(
            key: 'authMethod',
            label: '认证方式',
            type: SourceFormFieldType.select,
            options: ['密码', 'SSH 密钥'],
            defaultValue: '密码',
          ),
          SourceFormField(
            key: 'password',
            label: '密码',
            type: SourceFormFieldType.password,
            visibilityCondition: (values) => values['authMethod'] != 'SSH 密钥',
          ),
          SourceFormField(
            key: 'privateKey',
            label: 'SSH 私钥',
            type: SourceFormFieldType.password,
            helpText: '粘贴 PEM 格式的私钥内容',
            visibilityCondition: (values) => values['authMethod'] == 'SSH 密钥',
          ),
          SourceFormField(
            key: 'privateKeyPassphrase',
            label: '私钥密码',
            type: SourceFormFieldType.password,
            required: false,
            helpText: '仅加密私钥需要填写',
            visibilityCondition: (values) => values['authMethod'] == 'SSH 密钥',
          ),
        ],
      ),
      _advancedSection(),
    ],
  );

  static SourceFormConfig _getNfsConfig() => SourceFormConfig(
    type: SourceType.nfs,
    sections: [
      _basicInfoSection(),
      SourceFormSection(
        title: '连接配置',
        fields: [
          const SourceFormField(
            key: 'host',
            label: '主机地址',
            placeholder: '192.168.1.100',
          ),
          const SourceFormField(
            key: 'exportPath',
            label: '导出路径',
            placeholder: '/volume1/share',
            helpText: 'NFS 服务器导出的共享路径',
          ),
          const SourceFormField(
            key: 'nfsVersion',
            label: 'NFS 版本',
            type: SourceFormFieldType.select,
            options: ['自动', 'NFSv3', 'NFSv4'],
            defaultValue: '自动',
          ),
        ],
      ),
      _advancedSection(),
    ],
  );

  static SourceFormConfig _getS3Config() => SourceFormConfig(
    type: SourceType.s3,
    sections: [
      _basicInfoSection(),
      SourceFormSection(
        title: '连接配置',
        fields: [
          const SourceFormField(
            key: 'host',
            label: 'S3 Endpoint',
            placeholder: 's3.amazonaws.com 或 minio.example.com',
            helpText: '只填写域名或 IP，不包含 http://、https:// 和路径',
          ),
          SourceFormField(
            key: 'port',
            label: '端口',
            type: SourceFormFieldType.number,
            defaultValue: SourceType.s3.defaultPort.toString(),
          ),
          const SourceFormField(
            key: 'useSsl',
            label: '使用 HTTPS',
            type: SourceFormFieldType.toggle,
            defaultValue: 'true',
          ),
          const SourceFormField(
            key: 'bucket',
            label: 'Bucket',
            placeholder: 'photos',
          ),
          const SourceFormField(
            key: 'region',
            label: 'Region',
            placeholder: 'us-east-1',
            defaultValue: 'us-east-1',
            required: false,
          ),
          const SourceFormField(
            key: 'rootPrefix',
            label: '根目录前缀',
            placeholder: 'backup/photos',
            helpText: '可选，将此数据源限制在 Bucket 的指定前缀下',
            required: false,
          ),
          const SourceFormField(
            key: 'pathStyle',
            label: '使用 Path-style 地址',
            type: SourceFormFieldType.toggle,
            defaultValue: 'true',
            helpText: 'MinIO 等自托管服务通常开启；AWS 可按需关闭',
          ),
        ],
      ),
      const SourceFormSection(
        title: '访问凭据',
        fields: [
          SourceFormField(
            key: 'username',
            label: 'Access Key',
          ),
          SourceFormField(
            key: 'password',
            label: 'Secret Key',
            type: SourceFormFieldType.password,
          ),
          SourceFormField(
            key: 'sessionToken',
            label: 'Session Token',
            type: SourceFormFieldType.password,
            required: false,
            helpText: '仅临时凭据需要填写',
          ),
        ],
      ),
      _advancedSection(),
    ],
  );

  static SourceFormConfig _getUpnpConfig() => SourceFormConfig(
    type: SourceType.upnp,
    testConnectionSupported: false,
    sections: [
      SourceFormSection(
        title: 'UPnP/DLNA 设备',
        description: '自动发现局域网内的媒体设备，无需手动配置',
        fields: [
          const SourceFormField(
            key: 'name',
            label: '名称',
            placeholder: 'DLNA 媒体服务器',
            required: false,
            helpText: '可选，用于标识此设备',
          ),
        ],
      ),
    ],
  );

  // === 本地存储配置 ===

  static SourceFormConfig _getLocalConfig() => SourceFormConfig(
    type: SourceType.local,
    testConnectionSupported: false,
    sections: [
      SourceFormSection(
        title: '基本信息',
        fields: [
          const SourceFormField(
            key: 'name',
            label: '名称',
            placeholder: '本地存储',
            required: false,
          ),
        ],
      ),
      SourceFormSection(
        title: '存储位置',
        description: '选择要访问的本地文件夹',
        fields: [
          const SourceFormField(
            key: 'localPath',
            label: '文件夹路径',
            placeholder: '点击选择文件夹',
            helpText: '将自动请求存储权限',
          ),
        ],
      ),
    ],
  );

  // === 下载工具配置 ===

  static SourceFormConfig _getQbittorrentConfig() => SourceFormConfig(
    type: SourceType.qbittorrent,
    sections: [
      _basicInfoSection(),
      SourceFormSection(
        title: '连接配置',
        fields: [
          const SourceFormField(
            key: 'host',
            label: '主机地址',
            placeholder: '192.168.1.100',
          ),
          SourceFormField(
            key: 'port',
            label: '端口',
            type: SourceFormFieldType.number,
            defaultValue: SourceType.qbittorrent.defaultPort.toString(),
          ),
          const SourceFormField(
            key: 'useSsl',
            label: '使用 HTTPS',
            type: SourceFormFieldType.toggle,
            defaultValue: 'false',
          ),
        ],
      ),
      SourceFormSection(
        title: '认证方式',
        description: 'qBittorrent v5.2+ 支持 API Key 认证',
        fields: [
          const SourceFormField(
            key: 'authType',
            label: '认证类型',
            type: SourceFormFieldType.select,
            options: ['用户名密码', 'API Key'],
            defaultValue: '用户名密码',
          ),
          SourceFormField(
            key: 'username',
            label: '用户名',
            placeholder: 'admin',
            visibilityCondition: (values) => values['authType'] != 'API Key',
          ),
          SourceFormField(
            key: 'password',
            label: '密码',
            type: SourceFormFieldType.password,
            visibilityCondition: (values) => values['authType'] != 'API Key',
          ),
          SourceFormField(
            key: 'apiKey',
            label: 'API Key',
            type: SourceFormFieldType.password,
            placeholder: 'qbt_xxxxxxxxxxxxxxxxxxxxxxxx',
            helpText: '32 字符，以 qbt_ 开头',
            visibilityCondition: (values) => values['authType'] == 'API Key',
          ),
        ],
      ),
      _advancedSection(defaultAutoConnect: false),
    ],
  );

  static SourceFormConfig _getTransmissionConfig() => SourceFormConfig(
    type: SourceType.transmission,
    sections: [
      _basicInfoSection(),
      SourceFormSection(
        title: '连接配置',
        fields: [
          const SourceFormField(
            key: 'host',
            label: '主机地址',
            placeholder: '192.168.1.100',
          ),
          SourceFormField(
            key: 'port',
            label: '端口',
            type: SourceFormFieldType.number,
            defaultValue: SourceType.transmission.defaultPort.toString(),
          ),
          const SourceFormField(
            key: 'useSsl',
            label: '使用 HTTPS',
            type: SourceFormFieldType.toggle,
            defaultValue: 'false',
          ),
          const SourceFormField(
            key: 'rpcPath',
            label: 'RPC 路径',
            placeholder: '/transmission/rpc',
            defaultValue: '/transmission/rpc',
            required: false,
          ),
        ],
      ),
      _credentialSection(),
      _advancedSection(defaultAutoConnect: false),
    ],
  );

  static SourceFormConfig _getAria2Config() => SourceFormConfig(
    type: SourceType.aria2,
    sections: [
      _basicInfoSection(),
      SourceFormSection(
        title: '连接配置',
        fields: [
          const SourceFormField(
            key: 'host',
            label: '主机地址',
            placeholder: '192.168.1.100',
          ),
          SourceFormField(
            key: 'port',
            label: 'RPC 端口',
            type: SourceFormFieldType.number,
            defaultValue: SourceType.aria2.defaultPort.toString(),
          ),
          const SourceFormField(
            key: 'useSsl',
            label: '使用 HTTPS',
            type: SourceFormFieldType.toggle,
            defaultValue: 'false',
          ),
        ],
      ),
      const SourceFormSection(
        title: '认证信息',
        fields: [
          SourceFormField(
            key: 'rpcSecret',
            label: 'RPC 密钥',
            type: SourceFormFieldType.password,
            placeholder: '你的 RPC 密钥',
            helpText: 'aria2 配置文件中的 rpc-secret 值',
            required: false,
          ),
        ],
      ),
      _advancedSection(defaultAutoConnect: false),
    ],
  );

  // === 媒体追踪配置 ===

  static SourceFormConfig _getTraktConfig() => SourceFormConfig(
    type: SourceType.trakt,
    oauthRequired: true,
    sections: [
      _basicInfoSection(),
      const SourceFormSection(
        title: 'OAuth 配置',
        description: '请在 trakt.tv 创建应用获取以下信息',
        fields: [
          SourceFormField(
            key: 'clientId',
            label: 'Client ID',
            placeholder: '从 Trakt 应用设置获取',
          ),
          SourceFormField(
            key: 'clientSecret',
            label: 'Client Secret',
            type: SourceFormFieldType.password,
          ),
        ],
      ),
      const SourceFormSection(
        title: '同步设置',
        collapsible: true,
        defaultExpanded: false,
        fields: [
          SourceFormField(
            key: 'syncWatchedHistory',
            label: '同步观看历史',
            type: SourceFormFieldType.toggle,
            defaultValue: 'true',
          ),
          SourceFormField(
            key: 'syncRatings',
            label: '同步评分',
            type: SourceFormFieldType.toggle,
            defaultValue: 'true',
          ),
          SourceFormField(
            key: 'syncWatchlist',
            label: '同步待看列表',
            type: SourceFormFieldType.toggle,
            defaultValue: 'true',
          ),
        ],
      ),
    ],
  );

  // === 媒体管理配置 ===

  static SourceFormConfig _getNastoolConfig() => SourceFormConfig(
    type: SourceType.nastool,
    sections: [
      _basicInfoSection(),
      SourceFormSection(
        title: '连接配置',
        fields: [
          const SourceFormField(
            key: 'host',
            label: '主机地址',
            placeholder: '192.168.1.100',
          ),
          SourceFormField(
            key: 'port',
            label: '端口',
            type: SourceFormFieldType.number,
            defaultValue: SourceType.nastool.defaultPort.toString(),
          ),
          const SourceFormField(
            key: 'useSsl',
            label: '使用 HTTPS',
            type: SourceFormFieldType.toggle,
            defaultValue: 'false',
          ),
        ],
      ),
      _credentialSection(),
      _advancedSection(defaultAutoConnect: false),
    ],
  );

  static SourceFormConfig _getMoviepilotConfig() => SourceFormConfig(
    type: SourceType.moviepilot,
    sections: [
      _basicInfoSection(),
      SourceFormSection(
        title: '连接配置',
        fields: [
          const SourceFormField(
            key: 'host',
            label: '主机地址',
            placeholder: '192.168.1.100',
          ),
          SourceFormField(
            key: 'port',
            label: '端口',
            type: SourceFormFieldType.number,
            defaultValue: SourceType.moviepilot.defaultPort.toString(),
          ),
          const SourceFormField(
            key: 'useSsl',
            label: '使用 HTTPS',
            type: SourceFormFieldType.toggle,
            defaultValue: 'false',
          ),
        ],
      ),
      const SourceFormSection(
        title: '认证信息',
        fields: [
          SourceFormField(
            key: 'apiToken',
            label: 'API Token',
            type: SourceFormFieldType.password,
            helpText: '在 MoviePilot 设置中获取',
          ),
        ],
      ),
      _advancedSection(defaultAutoConnect: false),
    ],
  );

  static SourceFormConfig _getJellyfinConfig() => SourceFormConfig(
    type: SourceType.jellyfin,
    sections: [
      _basicInfoSection(),
      SourceFormSection(
        title: '连接配置',
        fields: [
          const SourceFormField(
            key: 'host',
            label: '服务器地址',
            placeholder: '192.168.1.100 或 jellyfin.example.com',
            helpText: '支持 IP 地址或域名',
          ),
          SourceFormField(
            key: 'port',
            label: '端口',
            type: SourceFormFieldType.number,
            defaultValue: SourceType.jellyfin.defaultPort.toString(),
          ),
          const SourceFormField(
            key: 'useSsl',
            label: '使用 HTTPS',
            type: SourceFormFieldType.toggle,
            defaultValue: 'false',
            helpText: '如服务器启用了 SSL，请开启此选项',
          ),
          const SourceFormField(
            key: 'basePath',
            label: '反向代理基础路径',
            placeholder: '/jellyfin',
            required: false,
            helpText: '仅通过反向代理子路径访问时填写',
          ),
        ],
      ),
      SourceFormSection(
        title: '认证方式',
        description: '支持用户名密码、API Key 或 Quick Connect 认证',
        fields: [
          const SourceFormField(
            key: 'authType',
            label: '认证类型',
            type: SourceFormFieldType.select,
            options: ['用户名密码', 'API Key', 'Quick Connect'],
            defaultValue: '用户名密码',
            helpText: 'Quick Connect 需要先在服务器上启用此功能',
          ),
          SourceFormField(
            key: 'username',
            label: '用户名',
            visibilityCondition: (values) => values['authType'] == '用户名密码',
          ),
          SourceFormField(
            key: 'password',
            label: '密码',
            type: SourceFormFieldType.password,
            required: false,
            visibilityCondition: (values) => values['authType'] == '用户名密码',
          ),
          SourceFormField(
            key: 'apiKey',
            label: 'API Key',
            type: SourceFormFieldType.password,
            helpText: '在 Jellyfin 控制面板 → API 密钥 中生成',
            visibilityCondition: (values) => values['authType'] == 'API Key',
          ),
        ],
      ),
      const SourceFormSection(
        title: '连接模式',
        description: '选择媒体数据的获取方式',
        collapsible: true,
        defaultExpanded: false,
        fields: [
          SourceFormField(
            key: 'connectionMode',
            label: '数据模式',
            type: SourceFormFieldType.select,
            options: ['直连模式', '库模式'],
            defaultValue: '直连模式',
            helpText:
                '直连模式：实时从服务器获取数据\n'
                '库模式：预缓存元数据到本地，支持离线浏览',
          ),
          SourceFormField(
            key: 'syncInterval',
            label: '同步间隔',
            type: SourceFormFieldType.select,
            options: ['手动', '每小时', '每天', '每周'],
            defaultValue: '每天',
            helpText: '库模式下自动同步元数据的频率',
          ),
        ],
      ),
      const SourceFormSection(
        title: '播放设置',
        collapsible: true,
        defaultExpanded: false,
        fields: [
          SourceFormField(
            key: 'preferDirectPlay',
            label: '优先直接播放',
            type: SourceFormFieldType.toggle,
            defaultValue: 'true',
            helpText: '关闭后优先使用转码播放，适合网络带宽不足时使用',
          ),
          SourceFormField(
            key: 'maxBitrate',
            label: '最大码率 (Mbps)',
            type: SourceFormFieldType.number,
            defaultValue: '120',
            required: false,
            helpText: '限制转码时的最大码率，0 表示不限制',
          ),
        ],
      ),
      _advancedSection(defaultAutoConnect: false),
    ],
  );

  static SourceFormConfig _getEmbyConfig() => SourceFormConfig(
    type: SourceType.emby,
    sections: [
      _basicInfoSection(),
      SourceFormSection(
        title: '连接配置',
        fields: [
          const SourceFormField(
            key: 'host',
            label: '服务器地址',
            placeholder: '192.168.1.100 或 emby.example.com',
            helpText: '支持 IP 地址或域名',
          ),
          SourceFormField(
            key: 'port',
            label: '端口',
            type: SourceFormFieldType.number,
            defaultValue: SourceType.emby.defaultPort.toString(),
          ),
          const SourceFormField(
            key: 'useSsl',
            label: '使用 HTTPS',
            type: SourceFormFieldType.toggle,
            defaultValue: 'false',
            helpText: '如服务器启用了 SSL，请开启此选项',
          ),
          const SourceFormField(
            key: 'basePath',
            label: '反向代理基础路径',
            placeholder: '/emby',
            required: false,
            helpText: '仅通过反向代理子路径访问时填写',
          ),
        ],
      ),
      SourceFormSection(
        title: '认证方式',
        description: '支持用户名密码或 API Key 认证',
        fields: [
          const SourceFormField(
            key: 'authType',
            label: '认证类型',
            type: SourceFormFieldType.select,
            options: ['用户名密码', 'API Key'],
            defaultValue: '用户名密码',
            helpText: 'API Key 可在 Emby 控制面板 → API 密钥中生成',
          ),
          SourceFormField(
            key: 'username',
            label: '用户名',
            visibilityCondition: (values) => values['authType'] != 'API Key',
          ),
          SourceFormField(
            key: 'password',
            label: '密码',
            type: SourceFormFieldType.password,
            required: false,
            visibilityCondition: (values) => values['authType'] != 'API Key',
          ),
          SourceFormField(
            key: 'apiKey',
            label: 'API Key',
            type: SourceFormFieldType.password,
            helpText: '在 Emby 控制面板 → API 密钥 中生成',
            visibilityCondition: (values) => values['authType'] == 'API Key',
          ),
        ],
      ),
      const SourceFormSection(
        title: '连接模式',
        description: '选择媒体数据的获取方式',
        collapsible: true,
        defaultExpanded: false,
        fields: [
          SourceFormField(
            key: 'connectionMode',
            label: '数据模式',
            type: SourceFormFieldType.select,
            options: ['直连模式', '库模式'],
            defaultValue: '直连模式',
            helpText:
                '直连模式：实时从服务器获取数据\n'
                '库模式：预缓存元数据到本地，支持离线浏览',
          ),
          SourceFormField(
            key: 'syncInterval',
            label: '同步间隔',
            type: SourceFormFieldType.select,
            options: ['手动', '每小时', '每天', '每周'],
            defaultValue: '每天',
            helpText: '库模式下自动同步元数据的频率',
          ),
        ],
      ),
      const SourceFormSection(
        title: '播放设置',
        collapsible: true,
        defaultExpanded: false,
        fields: [
          SourceFormField(
            key: 'preferDirectPlay',
            label: '优先直接播放',
            type: SourceFormFieldType.toggle,
            defaultValue: 'true',
            helpText: '关闭后优先使用转码播放，适合网络带宽不足时使用',
          ),
          SourceFormField(
            key: 'maxBitrate',
            label: '最大码率 (Mbps)',
            type: SourceFormFieldType.number,
            defaultValue: '120',
            required: false,
            helpText: '限制转码时的最大码率，0 表示不限制',
          ),
        ],
      ),
      _advancedSection(defaultAutoConnect: false),
    ],
  );

  static SourceFormConfig _getPlexConfig() => SourceFormConfig(
    type: SourceType.plex,
    sections: [
      _basicInfoSection(),
      SourceFormSection(
        title: '连接配置',
        fields: [
          const SourceFormField(
            key: 'host',
            label: '服务器地址',
            placeholder: '192.168.1.100 或 plex.example.com',
            helpText: '支持 IP 地址或域名',
          ),
          SourceFormField(
            key: 'port',
            label: '端口',
            type: SourceFormFieldType.number,
            defaultValue: SourceType.plex.defaultPort.toString(),
          ),
          const SourceFormField(
            key: 'useSsl',
            label: '使用 HTTPS',
            type: SourceFormFieldType.toggle,
            defaultValue: 'false',
            helpText: '如服务器启用了 SSL，请开启此选项',
          ),
          const SourceFormField(
            key: 'basePath',
            label: '反向代理基础路径',
            placeholder: '/plex',
            required: false,
            helpText: '仅通过反向代理子路径访问时填写',
          ),
        ],
      ),
      SourceFormSection(
        title: '认证方式',
        description: '支持 PIN 码授权或手动输入 Token',
        fields: [
          const SourceFormField(
            key: 'authType',
            label: '认证类型',
            type: SourceFormFieldType.select,
            options: ['PIN 码授权', '手动输入 Token'],
            defaultValue: 'PIN 码授权',
            helpText:
                'PIN 码授权：在 plex.tv/link 上输入 PIN 码完成授权\n'
                '手动输入 Token：手动获取并输入 X-Plex-Token',
          ),
          SourceFormField(
            key: 'plexToken',
            label: 'Plex Token',
            type: SourceFormFieldType.password,
            helpText:
                '获取方式：登录 Plex Web → 打开任意媒体 → '
                '在地址栏 URL 中找到 X-Plex-Token=xxx 参数',
            visibilityCondition: (values) => values['authType'] == '手动输入 Token',
          ),
        ],
      ),
      const SourceFormSection(
        title: '连接模式',
        description: '选择媒体数据的获取方式',
        collapsible: true,
        defaultExpanded: false,
        fields: [
          SourceFormField(
            key: 'connectionMode',
            label: '数据模式',
            type: SourceFormFieldType.select,
            options: ['直连模式', '库模式'],
            defaultValue: '直连模式',
            helpText:
                '直连模式：实时从服务器获取数据\n'
                '库模式：预缓存元数据到本地，支持离线浏览',
          ),
          SourceFormField(
            key: 'syncInterval',
            label: '同步间隔',
            type: SourceFormFieldType.select,
            options: ['手动', '每小时', '每天', '每周'],
            defaultValue: '每天',
            helpText: '库模式下自动同步元数据的频率',
          ),
        ],
      ),
      const SourceFormSection(
        title: '播放设置',
        collapsible: true,
        defaultExpanded: false,
        fields: [
          SourceFormField(
            key: 'preferDirectPlay',
            label: '优先直接播放',
            type: SourceFormFieldType.toggle,
            defaultValue: 'true',
            helpText: '关闭后优先使用转码播放，适合网络带宽不足时使用',
          ),
          SourceFormField(
            key: 'maxBitrate',
            label: '最大码率 (Mbps)',
            type: SourceFormFieldType.number,
            defaultValue: '120',
            required: false,
            helpText: '限制转码时的最大码率，建议设置为视频码率的 2 倍以确保直接播放',
          ),
        ],
      ),
      _advancedSection(defaultAutoConnect: false),
    ],
  );

  // === PT 站点配置 ===

  /// 通用 PT 站点配置
  /// 支持 Cookie 认证和自定义请求头认证
  static SourceFormConfig _getPTSiteConfig() => SourceFormConfig(
    type: SourceType.ptSite,
    sections: [
      // 基本信息 - 站点名称
      const SourceFormSection(
        title: '基本信息',
        fields: [
          SourceFormField(
            key: 'name',
            label: '站点名称',
            placeholder: '例如：馒头、瓷器、彩虹岛',
            helpText: '自定义站点名称，便于识别',
          ),
        ],
      ),
      // 站点配置
      const SourceFormSection(
        title: '站点配置',
        fields: [
          SourceFormField(
            key: 'host',
            label: '站点地址',
            placeholder: 'example.com',
            helpText: '站点域名，不需要 http:// 前缀',
          ),
          SourceFormField(
            key: 'useSsl',
            label: '使用 HTTPS',
            type: SourceFormFieldType.toggle,
            defaultValue: 'true',
          ),
        ],
      ),
      // 认证方式选择
      const SourceFormSection(
        title: '认证方式',
        description: '选择站点的认证方式',
        fields: [
          SourceFormField(
            key: 'authType',
            label: '认证类型',
            type: SourceFormFieldType.select,
            options: ['Cookie', '自定义请求头'],
            defaultValue: 'Cookie',
            helpText: '大部分站点使用 Cookie，馒头等站点使用自定义请求头',
          ),
          // Cookie 认证
          SourceFormField(
            key: 'cookie',
            label: 'Cookie',
            type: SourceFormFieldType.password,
            placeholder: '从浏览器复制完整的 Cookie',
            required: false,
            helpText: '登录站点后，从浏览器开发者工具获取 Cookie',
            visibilityCondition: _isCookieAuthType,
          ),
          // 自定义请求头
          SourceFormField(
            key: 'customHeaders',
            label: '自定义请求头',
            type: SourceFormFieldType.keyValueList,
            required: false,
            helpText:
                '馒头站点需要添加 x-api-key 和 authorization 两个请求头\n'
                '获取方式：登录馒头网站 → 按 F12 打开开发者工具 → '
                'Network → 刷新页面 → 找到任意 API 请求 → 复制请求头中的值',
            visibilityCondition: _isCustomHeadersAuthType,
          ),
        ],
      ),
      // RSS 订阅
      const SourceFormSection(
        title: 'RSS 订阅',
        collapsible: true,
        defaultExpanded: false,
        description: '配置 RSS 订阅获取最新资源',
        fields: [
          SourceFormField(
            key: 'rssUrl',
            label: 'RSS 订阅地址',
            placeholder: 'https://...',
            required: false,
            helpText: '从站点 RSS 页面获取完整订阅地址',
          ),
          SourceFormField(
            key: 'enableRssDetail',
            label: 'RSS 解析种子详情',
            type: SourceFormFieldType.toggle,
            defaultValue: 'true',
          ),
          SourceFormField(
            key: 'enableNotification',
            label: '发送站点未读消息通知',
            type: SourceFormFieldType.toggle,
            defaultValue: 'true',
          ),
        ],
      ),
      const SourceFormSection(
        title: '签到设置',
        collapsible: true,
        defaultExpanded: false,
        description: '站点提供签到接口时填写；未配置则不会显示签到按钮',
        fields: [
          SourceFormField(
            key: 'checkInPath',
            label: '签到接口路径',
            placeholder: '/attendance.php 或完整 URL',
            required: false,
          ),
          SourceFormField(
            key: 'checkInMethod',
            label: '请求方式',
            type: SourceFormFieldType.select,
            options: ['GET', 'POST'],
            defaultValue: 'GET',
            required: false,
          ),
        ],
      ),
      // 下载设置
      const SourceFormSection(
        title: '下载设置',
        collapsible: true,
        defaultExpanded: false,
        fields: [
          SourceFormField(
            key: 'enableBrowserEmulation',
            label: '开启浏览器仿真',
            type: SourceFormFieldType.toggle,
            defaultValue: 'true',
            helpText: '模拟浏览器请求，降低被检测风险',
          ),
          SourceFormField(
            key: 'userAgent',
            label: 'User-Agent',
            defaultValue:
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
                'AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/120.0.0.0 Safari/537.36',
            required: false,
            helpText: '自定义请求的 User-Agent，留空使用默认值',
          ),
          SourceFormField(
            key: 'useProxy',
            label: '使用代理服务器',
            type: SourceFormFieldType.toggle,
            defaultValue: 'false',
          ),
          SourceFormField(
            key: 'downloadSubtitle',
            label: '从详情页下载字幕',
            type: SourceFormFieldType.toggle,
            defaultValue: 'false',
          ),
          SourceFormField(
            key: 'addSiteTag',
            label: '下载器添加站点标签',
            type: SourceFormFieldType.toggle,
            defaultValue: 'false',
          ),
        ],
      ),
      // 流控规则
      const SourceFormSection(
        title: '流控规则',
        collapsible: true,
        defaultExpanded: false,
        description: '控制请求频率避免被封禁',
        fields: [
          SourceFormField(
            key: 'rateLimitMinutes',
            label: '单位时间（分钟）',
            type: SourceFormFieldType.number,
            defaultValue: '10',
          ),
          SourceFormField(
            key: 'rateLimitCount',
            label: '单位时间内访问次数',
            type: SourceFormFieldType.number,
            defaultValue: '10',
          ),
          SourceFormField(
            key: 'requestInterval',
            label: '访问间隔（秒）',
            type: SourceFormFieldType.number,
            defaultValue: '5',
          ),
        ],
      ),
      // 高级选项 - PT 站点只保留记住设备选项
      const SourceFormSection(
        title: '高级选项',
        collapsible: true,
        defaultExpanded: false,
        fields: [
          SourceFormField(
            key: 'rememberDevice',
            label: '记住设备（跳过二次验证）',
            type: SourceFormFieldType.toggle,
            defaultValue: 'false',
            helpText: '某些站点可能需要二次验证',
          ),
        ],
      ),
    ],
  );

  /// Cookie 认证类型条件判断
  static bool _isCookieAuthType(Map<String, dynamic> values) =>
      values['authType'] != '自定义请求头';

  /// 自定义请求头认证类型条件判断
  static bool _isCustomHeadersAuthType(Map<String, dynamic> values) =>
      values['authType'] == '自定义请求头';

  // === 字幕站点配置 ===

  /// OpenSubtitles 配置
  /// 用户名密码可选（用于获取更高配额），API Key 可选（默认使用内置）
  static SourceFormConfig _getOpenSubtitlesConfig() => const SourceFormConfig(
    type: SourceType.opensubtitles,
    testConnectionSupported: true,
    sections: [
      // 基本信息
      SourceFormSection(
        title: '基本信息',
        fields: [
          SourceFormField(
            key: 'name',
            label: '名称',
            placeholder: 'OpenSubtitles',
            defaultValue: 'OpenSubtitles',
            required: false,
            helpText: '显示在源列表中的名称',
          ),
        ],
      ),
      // 账号配置（可选，用于获取更高配额）
      SourceFormSection(
        title: '账号配置',
        description: '可选：登录后可获取更高的下载配额（每天 10→20 次）',
        fields: [
          SourceFormField(
            key: 'username',
            label: '用户名',
            required: false,
            helpText: 'OpenSubtitles 账号用户名',
          ),
          SourceFormField(
            key: 'password',
            label: '密码',
            type: SourceFormFieldType.password,
            required: false,
          ),
        ],
      ),
      // 下载设置
      SourceFormSection(
        title: '下载设置',
        collapsible: true,
        defaultExpanded: false,
        fields: [
          SourceFormField(
            key: 'preferredLanguages',
            label: '首选语言',
            placeholder: 'zh-cn,zh-tw,en',
            required: false,
            helpText: '按优先级排序的语言代码，用逗号分隔\n常用：zh-cn(简体中文), zh-tw(繁体中文), en(英文)',
          ),
          SourceFormField(
            key: 'excludeAiTranslated',
            label: '排除AI翻译字幕',
            type: SourceFormFieldType.toggle,
            defaultValue: 'false',
            helpText: '开启后将不显示AI生成的翻译字幕',
          ),
          SourceFormField(
            key: 'excludeMachineTranslated',
            label: '排除机器翻译字幕',
            type: SourceFormFieldType.toggle,
            defaultValue: 'false',
            helpText: '开启后将不显示机器翻译的字幕',
          ),
          SourceFormField(
            key: 'preferHearingImpaired',
            label: '优先显示SDH字幕',
            type: SourceFormFieldType.toggle,
            defaultValue: 'false',
            helpText: '为听障人士优化的字幕，包含音效描述',
          ),
        ],
      ),
      // 高级设置（自定义 API Key）
      SourceFormSection(
        title: '高级设置',
        collapsible: true,
        defaultExpanded: false,
        description: '默认使用内置 API Key，一般无需配置',
        fields: [
          SourceFormField(
            key: 'apiKey',
            label: '自定义 API Key',
            type: SourceFormFieldType.password,
            required: false,
            placeholder: '留空使用内置 API Key',
            helpText: '如需使用自己的 API Key，可在 opensubtitles.com 申请',
          ),
        ],
      ),
    ],
  );

  // === 通用分组模板 ===

  static SourceFormSection _basicInfoSection() => const SourceFormSection(
    title: '基本信息',
    fields: [
      SourceFormField(
        key: 'name',
        label: '名称',
        placeholder: '自定义名称',
        required: false,
        helpText: '留空将使用主机地址作为名称',
      ),
    ],
  );

  static SourceFormSection _credentialSection({bool optional = false}) =>
      SourceFormSection(
        title: '账户信息',
        fields: [
          SourceFormField(key: 'username', label: '用户名', required: !optional),
          SourceFormField(
            key: 'password',
            label: '密码',
            type: SourceFormFieldType.password,
            required: !optional,
          ),
        ],
      );

  static SourceFormSection _advancedSection({bool defaultAutoConnect = true}) =>
      SourceFormSection(
        title: '高级选项',
        collapsible: true,
        defaultExpanded: false,
        fields: [
          SourceFormField(
            key: 'autoConnect',
            label: '启动时自动连接',
            type: SourceFormFieldType.toggle,
            defaultValue: defaultAutoConnect.toString(),
          ),
          const SourceFormField(
            key: 'rememberDevice',
            label: '记住设备（跳过二次验证）',
            type: SourceFormFieldType.toggle,
            defaultValue: 'false',
          ),
        ],
      );
}
