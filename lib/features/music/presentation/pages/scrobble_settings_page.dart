import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
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

  /// 应用内 OAuth 状态：取到 token 后保存，等用户授权后用它换 sk。
  String? _pendingToken;
  // 取 token 时配对的凭证，第二步换 sk 必须用同一组（token 与 api_key 绑定）
  String? _pendingKey;
  String? _pendingSecret;
  bool _oauthBusy = false;

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

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// OAuth 第一步：校验 key/secret → 取 token → 打开授权页。
  /// 任意一步失败都给提示并保留手动粘贴兜底。
  Future<void> _startLastfmAuth() async {
    final l = AppLocalizations.of(context);
    final key = _lfApiKey.text.trim();
    final secret = _lfApiSecret.text.trim();
    if (key.isEmpty) {
      _toast(l.musicScrobbleLastfmApiKeyRequired);
      return;
    }
    if (secret.isEmpty) {
      _toast(l.musicScrobbleLastfmSecretRequired);
      return;
    }
    setState(() => _oauthBusy = true);
    try {
      final token = await _service.lastfmFetchToken(
        apiKey: key,
        apiSecret: secret,
      );
      if (token == null || token.isEmpty) {
        _toast(l.musicScrobbleLastfmTokenFailed);
        return;
      }
      _pendingToken = token;
      _pendingKey = key;
      _pendingSecret = secret;
      final url = _service.lastfmAuthorizeUrl(apiKey: key, token: token);
      await _openUrl(url);
      _toast(l.musicScrobbleLastfmAuthOpened);
    } finally {
      if (mounted) setState(() => _oauthBusy = false);
    }
  }

  /// OAuth 第三步：用户授权后取回 sk 并回填，成功后自动保存。
  Future<void> _completeLastfmAuth() async {
    final l = AppLocalizations.of(context);
    final token = _pendingToken;
    if (token == null || token.isEmpty) {
      _toast(l.musicScrobbleLastfmNeedToken);
      return;
    }
    // 用取 token 时配对的凭证换 sk，避免用户中途改了输入框导致 token/api_key 错配。
    final key = _pendingKey ?? _lfApiKey.text.trim();
    final secret = _pendingSecret ?? _lfApiSecret.text.trim();
    if (key.isEmpty || secret.isEmpty) return;
    setState(() => _oauthBusy = true);
    try {
      final sk = await _service.lastfmFetchSessionKey(
        apiKey: key,
        apiSecret: secret,
        token: token,
      );
      if (sk == null || sk.isEmpty) {
        _toast(l.musicScrobbleLastfmSessionFailed);
        return;
      }
      _lfSessionKey.text = sk;
      _pendingToken = null;
      _pendingKey = null;
      _pendingSecret = null;
      await _save();
      _toast(l.musicScrobbleLastfmAuthSuccess);
    } finally {
      if (mounted) setState(() => _oauthBusy = false);
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
          context.l10n.musicScrobblePageTitle,
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
              child: Text(context.l10n.musicScrobbleSaveButton),
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
                  title: Text(context.l10n.musicScrobbleEnableTitle),
                  subtitle: Text(
                    context.l10n.musicScrobbleEnableSubtitle,
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
                  context.l10n.musicScrobbleIntroTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.musicScrobbleIntroDesc,
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
              context.l10n.musicScrobbleListenBrainzHint,
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
              context.l10n.musicScrobbleLastFmHint,
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
        Text(
          context.l10n.musicScrobbleSessionKeyDesc,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.white60 : Colors.black54,
          ),
        ),
        const SizedBox(height: 8),
        // 应用内 OAuth：授权 → 我已授权完成（自动取回 sk）
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.tonalIcon(
              icon: _oauthBusy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.open_in_new_rounded, size: 16),
              label: Text(context.l10n.musicScrobbleAuthorizeButton),
              onPressed: _oauthBusy ? null : _startLastfmAuth,
            ),
            TextButton.icon(
              icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
              label: Text(context.l10n.musicScrobbleLastfmAuthCompleteButton),
              onPressed:
                  (_oauthBusy || _pendingToken == null) ? null : _completeLastfmAuth,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.musicScrobbleLastfmManualHint,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.paste_rounded, size: 18),
              tooltip: context.l10n.musicScrobblePasteTooltip,
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
