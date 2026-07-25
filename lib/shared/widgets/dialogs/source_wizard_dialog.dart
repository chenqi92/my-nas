import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/sources/data/services/network_discovery_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/source_form_page.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/atoms/app_card.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';

/// 添加数据源向导（设计稿 ops2.jsx AddSourceWizard）。
///
/// 选类型 → 进入既有 [SourceFormPage] 完成连接配置 / 测试 / 保存。表单页内置
/// 各类型的动态字段（主机 / 端口 / 账户 / 高级 autoConnect / 记住设备 /
/// 信任自签证书）、真实连接测试（登录 · 列目录 · 取版本 · OAuth）与凭据安全
/// 存储，因此本向导只负责选类型并把真实链路接上，不再造重复的假表单。
///
/// 打开弹窗时会复用 [networkDiscoveryProvider] 的局域网发现状态：发现入口始终
/// 可见，扫描到的设备可直接预填表单。类型清单由 [SourceType] 枚举驱动：
/// `local` 由系统自动创建不在此显示；未实现的类型（当前为 NFS）以「规划」
/// 角标置灰，不可选。
class SourceWizardDialog extends ConsumerStatefulWidget {
  const SourceWizardDialog({super.key});

  @override
  ConsumerState<SourceWizardDialog> createState() => _SourceWizardDialogState();
}

class _SourceWizardDialogState extends ConsumerState<SourceWizardDialog> {
  SourceType? _type;

  List<SourceType> get _availableTypes => [
    for (final t in SourceType.values)
      if (t.isAvailableOnCurrentPlatform) t,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final discovery = ref.read(networkDiscoveryProvider);
      // 数据源页通常已经发起过扫描；仅在从其它入口首次打开时自动扫描，
      // 避免清空仍然有效的发现结果。
      if (!discovery.isDiscovering &&
          discovery.lastDiscoveryTime == null &&
          discovery.error == null) {
        ref.read(networkDiscoveryProvider.notifier).startDiscovery();
      }
    });
  }

  void _openForm() {
    final type = _type;
    if (type == null) return;
    // 保留本向导，叠加表单 Dialog；保存成功后 popTwice 一并关闭二者。
    SourceFormPage.openAdaptive<SourceEntity>(
      context,
      sourceType: type,
      popTwice: true,
    );
  }

  void _openDiscoveredDevice(DiscoveredDevice device) {
    if (!device.type.isSupported) return;
    SourceFormPage.openAdaptive<SourceEntity>(
      context,
      sourceType: device.type,
      initialValues: {
        'name': device.name,
        'host': device.host,
        'port': device.port.toString(),
      },
      popTwice: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    final discovery = ref.watch(networkDiscoveryProvider);
    final storageTypes = _availableTypes
        .where((type) => type.category.isStorageCategory)
        .toList();
    final serviceTypes = _availableTypes
        .where((type) => type.category.isServiceCategory)
        .toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 780),
        child: GlassPanel(
          strong: true,
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(t: t, onClose: () => Navigator.of(context).pop()),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
                // 选择卡片只是当前步骤内的状态，不应提前把进度跳到第 2 步。
                child: _WizardSteps(t: t, current: 0),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
                child: Text(
                  l.srcWizardSubtitle,
                  style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 16, 28, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DiscoveryPanel(
                        state: discovery,
                        onScan: discovery.isDiscovering
                            ? null
                            : () => ref
                                  .read(networkDiscoveryProvider.notifier)
                                  .startDiscovery(),
                        onAdd: _openDiscoveredDevice,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        l.srcWizardManualTitle,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: t.text0,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        l.srcWizardManualHint,
                        style: TextStyle(
                          fontSize: 12,
                          color: t.text2,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _TypeSection(
                        title: l.srcWizardStorageGroup,
                        types: storageTypes,
                        selected: _type,
                        onPick: (ty) => setState(() => _type = ty),
                      ),
                      const SizedBox(height: 20),
                      _TypeSection(
                        title: l.srcWizardServiceGroup,
                        types: serviceTypes,
                        selected: _type,
                        onPick: (ty) => setState(() => _type = ty),
                      ),
                    ],
                  ),
                ),
              ),
              _Footer(
                t: t,
                selected: _type,
                onNext: _type != null ? _openForm : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.t, required this.onClose});
  final DesignTokens t;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 16, 18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.lan_outlined, size: 18, color: t.accentBright),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l.srcWizardTitle,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: t.text0,
              ),
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close_rounded, size: 16, color: t.text2),
          ),
        ],
      ),
    );
  }
}

/// 步骤指示器（设计稿 ops2.jsx wizard-steps）：1 选择类型 / 2 连接信息 /
/// 3 测试连接 / 4 库映射。[current] 为当前步索引（0 起），小于它的为已完成。
class _WizardSteps extends StatelessWidget {
  const _WizardSteps({required this.t, required this.current});
  final DesignTokens t;
  final int current;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final labels = [
      l.srcWizardStepType,
      l.srcWizardStepConnection,
      l.srcWizardStepTest,
      l.srcWizardStepMapping,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 540) {
          return Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              for (var i = 0; i < labels.length; i++) _step(i, labels[i]),
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              _step(i, labels[i]),
              if (i < labels.length - 1)
                Expanded(
                  child: Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: i < current
                        ? t.accent.withValues(alpha: 0.5)
                        : t.hairline,
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _step(int i, String label) {
    final isOn = i == current;
    final isDone = i < current;
    final Color numberBg;
    final Color numberFg;
    final Color labelColor;
    final bool border;
    if (isOn) {
      numberBg = t.accent;
      numberFg = t.accentContrast;
      labelColor = t.text0;
      border = false;
    } else if (isDone) {
      numberBg = t.accent.withValues(alpha: 0.2);
      numberFg = t.accentBright;
      labelColor = t.text3;
      border = false;
    } else {
      numberBg = t.insetBg;
      numberFg = t.text3;
      labelColor = t.text3;
      border = true;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: numberBg,
            shape: BoxShape.circle,
            border: border ? Border.all(color: t.hairline) : null,
          ),
          child: isDone
              ? Icon(Icons.check_rounded, size: 12, color: numberFg)
              : Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: numberFg,
                  ),
                ),
        ),
        const SizedBox(width: 9),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: labelColor,
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.t,
    required this.selected,
    required this.onNext,
  });

  final DesignTokens t;
  final SourceType? selected;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.hairline)),
      ),
      child: Row(
        children: [
          Icon(
            selected == null
                ? Icons.info_outline_rounded
                : Icons.check_circle_rounded,
            size: 15,
            color: selected == null ? t.text3 : t.accentBright,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              selected == null
                  ? l.srcWizardSelectHint
                  : l.srcWizardSelectedType(selected!.displayName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected == null
                    ? FontWeight.w400
                    : FontWeight.w600,
                color: selected == null ? t.text3 : t.text1,
              ),
            ),
          ),
          const Spacer(),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.arrow_forward_rounded, size: 14),
            label: Text(l.srcWizardNext),
          ),
        ],
      ),
    );
  }
}

class _DiscoveryPanel extends StatelessWidget {
  const _DiscoveryPanel({
    required this.state,
    required this.onScan,
    required this.onAdd,
  });

  final NetworkDiscoveryState state;
  final VoidCallback? onScan;
  final ValueChanged<DiscoveredDevice> onAdd;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final devices = state.devices;
    final statusText = state.error != null
        ? l.paneSourcesDiscoveryError(state.error!)
        : state.isDiscovering
        ? l.paneSourcesDiscoveryScanning
        : devices.isNotEmpty
        ? l.paneSourcesDiscoveryFound(devices.length)
        : state.lastDiscoveryTime != null
        ? l.paneSourcesDiscoveryEmpty
        : l.paneSourcesDiscoveryIdle;

    return Container(
      key: const Key('source-wizard-discovery'),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.065),
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        border: Border.all(color: t.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: state.isDiscovering
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: t.accentBright,
                        ),
                      )
                    : Icon(
                        Icons.radar_rounded,
                        size: 19,
                        color: t.accentBright,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l.paneSourcesDiscoveryTitle,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: t.text0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: state.error == null ? t.text2 : t.err,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AppChip(
                label: state.isDiscovering
                    ? l.paneSourcesScanning
                    : l.paneSourcesScan,
                icon: Icons.refresh_rounded,
                compact: true,
                onTap: onScan,
              ),
            ],
          ),
          if (state.isDiscovering) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: t.hairline,
                color: t.accentBright,
              ),
            ),
          ],
          for (final device in devices) ...[
            const SizedBox(height: 10),
            _DiscoveredDeviceRow(device: device, onAdd: () => onAdd(device)),
          ],
        ],
      ),
    );
  }
}

class _DiscoveredDeviceRow extends StatelessWidget {
  const _DiscoveredDeviceRow({required this.device, required this.onAdd});

  final DiscoveredDevice device;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final supported = device.type.isSupported;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(DesignTokens.radius),
        border: Border.all(color: t.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: t.insetBg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(device.type.icon, size: 17, color: t.accentBright),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.text0,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${device.host}:${device.port} · '
                  '${device.type.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: t.text2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!supported)
            AppTag(l.srcWizardPlanTag, variant: TagVariant.plan)
          else
            AppChip(
              label: l.paneSourcesAddShort,
              icon: Icons.add_rounded,
              compact: true,
              onTap: onAdd,
            ),
        ],
      ),
    );
  }
}

class _TypeSection extends StatelessWidget {
  const _TypeSection({
    required this.title,
    required this.types,
    required this.selected,
    required this.onPick,
  });

  final String title;
  final List<SourceType> types;
  final SourceType? selected;
  final ValueChanged<SourceType> onPick;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: t.text2,
          ),
        ),
        const SizedBox(height: 9),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: types.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 224,
            mainAxisExtent: 72,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemBuilder: (_, i) {
            final type = types[i];
            final plan = !type.isSupported;
            final isSelected = type == selected;
            return Semantics(
              button: !plan,
              enabled: !plan,
              selected: isSelected,
              label: type.displayName,
              child: Opacity(
                opacity: plan ? 0.55 : 1,
                child: AppCard(
                  onTap: plan ? null : () => onPick(type),
                  selected: isSelected,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? t.accent.withValues(alpha: 0.14)
                              : t.insetBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          type.icon,
                          color: isSelected ? t.accent : t.accentBright,
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          type.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            color: t.text0,
                          ),
                        ),
                      ),
                      if (plan)
                        AppTag(l.srcWizardPlanTag, variant: TagVariant.plan)
                      else if (isSelected)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 17,
                          color: t.accent,
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
