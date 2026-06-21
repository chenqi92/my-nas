import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/features/music/data/services/scrobble/music_scrobble_service.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';
import 'package:url_launcher/url_launcher.dart';

/// Scrobble 设置页：开关 + ListenBrainz token / Last.fm 三件套。
class ScrobbleSettingsPage extends ConsumerStatefulWidget {
  const ScrobbleSettingsPage({super.key});

  @override
  ConsumerState<ScrobbleSettingsPage> createState() =>
      _ScrobbleSettingsPageState();
}

class _ScrobbleSettingsPageState
    extends ConsumerState<ScrobbleSettingsPage> {
  final _service = MusicScrobbleService.instance;

  late TextEditingController _lbToken;
  late TextEditingController _lfApiKey;
  late TextEditingController _lfApiSecret;
  late TextEditingController _lfSessionKey;

  bool _enabled = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _lbToken = TextEditingController();
    _lfApiKey = TextEditingController();
    _lfApiSecret = TextEditingController();
    _lfSessionKey = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _lbToken.dispose();
    _lfApiKey.dispose();
    _lfApiSecret.dispose();
    _lfSessionKey.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _service.init();
    final s = _service.settings;
    _enabled = s.enabled;
    _lbToken.text = s.listenbrainzToken ?? '';
    _lfApiKey.text = s.lastfmApiKey ?? '';
    _lfApiSecret.text = s.lastfmApiSecret ?? '';
    _lfSessionKey.text = s.lastfmSessionKey ?? '';
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _save() async {
    final next = ScrobbleSettings(
      enabled: _enabled,
      listenbrainzToken: _lbToken.text.trim().isEmpty
          ? null
          : _lbToken.text.trim(),
      lastfmApiKey:
          _lfApiKey.text.trim().isEmpty ? null : _lfApiKey.text.trim(),
      lastfmApiSecret:
          _lfApiSecret.text.trim().isEmpty ? null : _lfApiSecret.text.trim(),
      lastfmSessionKey: _lfSessionKey.text.trim().isEmpty
          ? null
          : _lfSessionKey.text.trim(),
    );
    await _service.applySettings(next);
    if (mounted) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.musicScrobbleSettingsSaved)),
      );
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      appBar: AppBar(
        leading: const RoundedBackButton(),
        backgroundColor: isDark ? AppColors.darkSurface : null,
        title: Text(
          'Scrobble 上报',
          style: TextStyle(
            color: isDark ? AppColors.darkOnSurface : null,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: IconThemeData(
          color: isDark ? AppColors.darkOnSurface : null,
        ),
        actions: [
          if (_loaded)
            TextButton(
              onPressed: _save,
              child: const Text('保存'),
            ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: AppSpacing.paddingMd,
              children: [
                _buildIntro(isDark),
                const SizedBox(height: AppSpacing.lg),
                SwitchListTile(
                  title: const Text('启用 Scrobble 上报'),
                  subtitle: const Text(
                    '听满 30s 且 ≥ 50% 或 ≥ 240s 时上报到下方已配置的服务',
                  ),
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
                const SizedBox(height: AppSpacing.lg),
                _buildListenBrainzSection(isDark),
                const SizedBox(height: AppSpacing.lg),
                _buildLastFmSection(isDark),
              ],
            ),
    );
  }

  Widget _buildIntro(bool isDark) => Container(
        padding: AppSpacing.paddingMd,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  '什么是 Scrobble',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '把你正在听的歌曲上报到外部服务（Last.fm / ListenBrainz），它们会记录你的听歌历史并提供分析、推荐。两者可同时启用，留空对应字段即关闭该服务。',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black87,
                height: 1.5,
              ),
            ),
          ],
        ),
      );

  Widget _buildListenBrainzSection(bool isDark) => _Section(
      title: 'ListenBrainz',
      isDark: isDark,
      children: [
        InkWell(
          onTap: () => _openUrl('https://listenbrainz.org/profile/'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '在 listenbrainz.org → Settings → Profile 复制 user token',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _lbToken,
          decoration: const InputDecoration(
            labelText: 'User token',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
        ),
      ],
    );

  Widget _buildLastFmSection(bool isDark) => _Section(
      title: 'Last.fm',
      isDark: isDark,
      children: [
        InkWell(
          onTap: () => _openUrl('https://www.last.fm/api/account/create'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '在 last.fm/api/account/create 创建应用拿到 API key + secret',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _lfApiKey,
          decoration: const InputDecoration(
            labelText: 'API key',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _lfApiSecret,
          decoration: const InputDecoration(
            labelText: 'API secret',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Session key 需要授权流程后获取',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('授权'),
              onPressed: () {
                final key = _lfApiKey.text.trim();
                if (key.isEmpty) {
                  final l = AppLocalizations.of(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.musicScrobbleLastfmApiKeyRequired)),
                  );
                  return;
                }
                _openUrl(
                  'https://www.last.fm/api/auth/?api_key=$key',
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.paste_rounded, size: 18),
              tooltip: '从剪贴板粘贴',
              onPressed: () async {
                final data = await Clipboard.getData('text/plain');
                if (data?.text != null) {
                  _lfSessionKey.text = data!.text!.trim();
                }
              },
            ),
          ],
        ),
        TextField(
          controller: _lfSessionKey,
          decoration: const InputDecoration(
            labelText: 'Session key (sk)',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
        ),
      ],
    );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.isDark,
    required this.children,
  });

  final String title;
  final bool isDark;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: AppSpacing.paddingMd,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );
}
