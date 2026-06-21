import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/network/doh_resolver.dart';
import 'package:my_nas/core/network/host_mapping_entry.dart';
import 'package:my_nas/core/network/hosts_resolver_service.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

/// 应用内 hosts 映射设置页
///
/// 类似系统 `/etc/hosts`：让 TMDB 等域名走指定 IP，绕过 DNS 污染。
/// 改动只影响 [ResolvedHttpClient] 发出的请求，不会影响系统其他 App。
class HostsMappingPage extends StatefulWidget {
  const HostsMappingPage({super.key});

  @override
  State<HostsMappingPage> createState() => _HostsMappingPageState();
}

class _HostsMappingPageState extends State<HostsMappingPage>
    with TabBarVisibilityMixin {
  late List<HostMappingEntry> _entries;
  DohProvider _dohProvider = DohProvider.cloudflare;
  bool _isResolving = false;

  @override
  void initState() {
    super.initState();
    hideTabBar();
    _entries = HostsResolverService.instance.list();
    HostsResolverService.instance.changes.listen((list) {
      if (mounted) {
        setState(() => _entries = list);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
      appBar: AppBar(
        leading: const RoundedBackButton(),
        backgroundColor: isDark ? AppColors.darkSurface : null,
        title: Text(context.l10n.hostsMappingPageTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: context.l10n.hostsMappingAddButton,
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showEditSheet(null),
          ),
        ],
      ),
      body: context.isDesktopLayout
          ? _buildDesktopBody(context)
          : Column(
              children: [
                _buildHeader(context, isDark),
                _buildDohBar(isDark),
                Expanded(
                  child: _entries.isEmpty
                      ? _buildEmpty(context, isDark)
                      : _buildList(isDark),
                ),
              ],
            ),
    );
  }

  // ===================== 桌面端 =====================

  Widget _buildDesktopBody(BuildContext context) {
    final t = DesignTokens.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(38, 32, 38, 96),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SetHead(
                icon: Icons.dns_rounded,
                title: context.l10n.hostsMappingDesktopTitle,
                subtitle: context.l10n.hostsMappingDesktopSubtitle,
                actions: [
                  AppButton(
                    label: context.l10n.hostsMappingAddButton,
                    icon: Icons.add_rounded,
                    variant: AppButtonVariant.primary,
                    onPressed: () => _showEditSheet(null),
                  ),
                ],
              ),
              SetSection(
                title: context.l10n.hostsMappingDohSection,
                children: [
                  SetRow(
                    title: context.l10n.hostsMappingDohProvider,
                    desc: context.l10n.hostsMappingDohProviderDesc,
                    last: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildDohDropdown(t),
                        const SizedBox(width: 12),
                        AppButton(
                          label: _isResolving ? context.l10n.hostsMappingResolving : context.l10n.hostsMappingResolveAll,
                          icon: _isResolving ? null : Icons.cloud_download_rounded,
                          onPressed: _isResolving ? null : _resolveAllViaDoh,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_entries.isEmpty)
                SetSection(
                  title: context.l10n.hostsMappingEntriesSection,
                  bottomMargin: false,
                  children: [
                    SetRow(
                      title: context.l10n.hostsMappingEmpty,
                      desc: context.l10n.hostsMappingEmptyDesc,
                      last: true,
                    ),
                  ],
                )
              else
                SetSection(
                  title: context.l10n.hostsMappingEntriesSection,
                  hint: '${_entries.length} ${context.l10n.hostsMappingEntriesSection}',
                  bottomMargin: false,
                  children: [
                    for (var i = 0; i < _entries.length; i++)
                      _buildDesktopEntryRow(
                        _entries[i],
                        last: i == _entries.length - 1,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDohDropdown(DesignTokens t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: t.insetBg,
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          border: Border.all(color: t.hairline, width: 0.5),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<DohProvider>(
            value: _dohProvider,
            isDense: true,
            dropdownColor: t.cardBg,
            style: TextStyle(fontSize: 12.5, color: t.text0),
            icon: Icon(Icons.expand_more_rounded, size: 16, color: t.text2),
            items: DohProvider.values
                .map(
                  (p) => DropdownMenuItem(
                    value: p,
                    child: Text(p.displayName),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _dohProvider = v);
            },
          ),
        ),
      );

  Widget _buildDesktopEntryRow(HostMappingEntry entry, {required bool last}) {
    final t = DesignTokens.of(context);
    final sourceLabel = entry.source == HostMappingSource.doh ? 'DoH' : context.l10n.hostsMappingSourceManual;
    return SetRow(
      title: entry.host,
      desc: entry.ip,
      last: last,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTag(sourceLabel, variant: TagVariant.accent),
          const SizedBox(width: 10),
          AppSwitch(
            value: entry.enabled,
            onChanged: (enabled) => HostsResolverService.instance
                .toggle(entry.host, enabled: enabled),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: context.l10n.hostsMappingEditTooltip,
            icon: Icon(Icons.edit_outlined, size: 18, color: t.text2),
            visualDensity: VisualDensity.compact,
            onPressed: () => _showEditSheet(entry),
          ),
          IconButton(
            tooltip: context.l10n.hostsMappingDeleteTooltip,
            icon: Icon(Icons.delete_outline_rounded, size: 18, color: t.text2),
            visualDensity: VisualDensity.compact,
            onPressed: () => _confirmDelete(entry),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.info.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, color: AppColors.info, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n.hostsMappingInfoText,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildDohBar(bool isDark) => Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceElevated : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.3)
                : AppColors.lightOutline.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.dns_rounded, color: AppColors.accent, size: 18),
            const SizedBox(width: 8),
            const Text('DoH', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            DropdownButtonHideUnderline(
              child: DropdownButton<DohProvider>(
                value: _dohProvider,
                isDense: true,
                items: DohProvider.values
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(p.displayName, style: const TextStyle(fontSize: 13)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _dohProvider = v);
                },
              ),
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: _isResolving ? null : _resolveAllViaDoh,
              icon: _isResolving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download_rounded, size: 16),
              label: Text(_isResolving ? context.l10n.hostsMappingResolving : context.l10n.hostsMappingResolveAll),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      );

  Widget _buildEmpty(BuildContext context, bool isDark) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dns_outlined,
              size: 64,
              color: isDark ? Colors.grey[700] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.hostsMappingEmpty,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.hostsMappingEmptyMobileDesc,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[600] : Colors.grey[500],
              ),
            ),
          ],
        ),
      );

  Widget _buildList(bool isDark) => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final entry = _entries[index];
          return _HostMappingTile(
            entry: entry,
            isDark: isDark,
            onToggle: (enabled) => HostsResolverService.instance
                .toggle(entry.host, enabled: enabled),
            onTap: () => _showEditSheet(entry),
            onDelete: () => _confirmDelete(entry),
          );
        },
      );

  Future<void> _showEditSheet(HostMappingEntry? existing) async {
    await showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HostMappingEditSheet(existing: existing),
    );
  }

  Future<void> _confirmDelete(HostMappingEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.hostsMappingDeleteConfirmTitle),
        content: Text(context.l10n.hostsMappingDeleteConfirmContent(entry.host)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.hostsMappingCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(context.l10n.hostsMappingDelete),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await HostsResolverService.instance.remove(entry.host);
    }
  }

  Future<void> _resolveAllViaDoh() async {
    setState(() => _isResolving = true);
    try {
      final results = await DohResolver.resolveAll(
        DohResolver.commonHosts,
        provider: _dohProvider,
      );
      if (results.isEmpty) {
        if (!mounted) return;
        context.showErrorToast(context.l10n.hostsMappingDohResolveFailed);
        return;
      }
      final now = DateTime.now();
      final entries = results.entries.map(
        (e) => HostMappingEntry(
          host: e.key,
          ip: e.value,
          source: HostMappingSource.doh,
          updatedAt: now,
        ),
      );
      await HostsResolverService.instance.upsertBatch(entries);
      if (!mounted) return;
      context.showSuccessToast(context.l10n.hostsMappingResolveSuccess(results.length));
    } on Exception catch (e, st) {
      if (!mounted) return;
      AppError.handleWithUI(context, e, st, 'DoH 解析失败', 'HostsMappingPage.resolveAll');
    } finally {
      if (mounted) setState(() => _isResolving = false);
    }
  }
}

class _HostMappingTile extends StatelessWidget {
  const _HostMappingTile({
    required this.entry,
    required this.isDark,
    required this.onToggle,
    required this.onTap,
    required this.onDelete,
  });

  final HostMappingEntry entry;
  final bool isDark;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final sourceColor = entry.source == HostMappingSource.doh
        ? AppColors.accent
        : AppColors.info;
    final sourceLabel = entry.source == HostMappingSource.doh ? 'DoH' : context.l10n.hostsMappingSourceManual;

    return Material(
      color: isDark ? AppColors.darkSurfaceElevated : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: sourceColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  sourceLabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: sourceColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.host,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.ip,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.l10n.hostsMappingDeleteTooltip,
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
              ),
              Switch(
                value: entry.enabled,
                onChanged: onToggle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HostMappingEditSheet extends StatefulWidget {
  const _HostMappingEditSheet({required this.existing});

  final HostMappingEntry? existing;

  @override
  State<_HostMappingEditSheet> createState() => _HostMappingEditSheetState();
}

class _HostMappingEditSheetState extends State<_HostMappingEditSheet> {
  late final TextEditingController _hostCtrl;
  late final TextEditingController _ipCtrl;

  @override
  void initState() {
    super.initState();
    _hostCtrl = TextEditingController(text: widget.existing?.host ?? '');
    _ipCtrl = TextEditingController(text: widget.existing?.ip ?? '');
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _ipCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isNew = widget.existing == null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isNew ? context.l10n.hostsMappingEditSheetAddTitle : context.l10n.hostsMappingEditSheetEditTitle,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _hostCtrl,
                  enabled: isNew, // 编辑时不允许改 host（host 是主键）
                  decoration: InputDecoration(
                    labelText: context.l10n.hostsMappingDomainLabel,
                    hintText: context.l10n.hostsMappingDomainHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _ipCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F\.:]')),
                  ],
                  decoration: InputDecoration(
                    labelText: context.l10n.hostsMappingIpLabel,
                    hintText: context.l10n.hostsMappingIpHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(context.l10n.hostsMappingCancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _handleSave,
                        child: Text(context.l10n.hostsMappingSave),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleSave() async {
    final l = AppLocalizations.of(context);
    final host = _hostCtrl.text.trim();
    final ip = _ipCtrl.text.trim();
    if (host.isEmpty || ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.hostsMappingDomainAndIpRequired), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (!_isValidIp(ip)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.hostsMappingInvalidIp), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    final entry = HostMappingEntry(
      host: host,
      ip: ip,
      source: widget.existing?.source ?? HostMappingSource.manual,
      enabled: widget.existing?.enabled ?? true,
    );
    await HostsResolverService.instance.upsert(entry);
    if (mounted) Navigator.pop(context);
  }

  bool _isValidIp(String s) => InternetAddress.tryParse(s) != null;
}
