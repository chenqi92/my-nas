import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/source_form_page.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/atoms/app_card.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';

/// 添加数据源向导（设计稿 ops2.jsx AddSourceWizard）。
///
/// 选类型 → 进入既有 [SourceFormPage] 完成连接配置 / 测试 / 保存。表单页内置
/// 各类型的动态字段（主机 / 端口 / 账户 / 高级 autoConnect / 记住设备 /
/// 信任自签证书）、真实连接测试（登录 · 列目录 · 取版本 · OAuth）与凭据安全
/// 存储，因此本向导只负责选类型并把真实链路接上，不再造重复的假表单。
///
/// 类型清单由 [SourceType] 枚举驱动：`local` 由系统自动创建不在此显示；
/// 未实现的类型（当前为 NFS）以「规划」角标置灰，不可选。
class SourceWizardDialog extends StatefulWidget {
  const SourceWizardDialog({super.key});

  @override
  State<SourceWizardDialog> createState() => _SourceWizardDialogState();
}

class _SourceWizardDialogState extends State<SourceWizardDialog> {
  SourceType? _type;

  List<SourceType> get _availableTypes => [
    for (final t in SourceType.values)
      if (t.isAvailableOnCurrentPlatform) t,
  ];

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

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: GlassPanel(
          strong: true,
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(t: t, onClose: () => Navigator.of(context).pop()),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                child: _WizardSteps(t: t, current: _type == null ? 0 : 1),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
                child: Text(
                  l.srcWizardSubtitle,
                  style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                  child: _TypeGrid(
                    types: _availableTypes,
                    selected: _type,
                    onPick: (ty) => setState(() => _type = ty),
                  ),
                ),
              ),
              _Footer(t: t, onNext: _type != null ? _openForm : null),
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
      padding: const EdgeInsets.fromLTRB(20, 16, 14, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: Row(
        children: [
          Icon(Icons.lan_outlined, size: 17, color: t.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l.srcWizardTitle,
              style: TextStyle(
                fontSize: 15,
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
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          _step(i, labels[i]),
        ],
      ],
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
  const _Footer({required this.t, required this.onNext});
  final DesignTokens t;
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
          const Spacer(),
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

class _TypeGrid extends StatelessWidget {
  const _TypeGrid({
    required this.types,
    required this.selected,
    required this.onPick,
  });

  final List<SourceType> types;
  final SourceType? selected;
  final ValueChanged<SourceType> onPick;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: types.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 130,
        mainAxisExtent: 92,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (_, i) {
        final type = types[i];
        // 未实现的类型即「规划」态，置灰不可选。
        final plan = !type.isSupported;
        return Opacity(
          opacity: plan ? 0.55 : 1,
          child: AppCard(
            onTap: plan ? null : () => onPick(type),
            selected: type == selected,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: t.insetBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(type.icon, color: t.accentBright, size: 19),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      type.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: t.text0,
                      ),
                    ),
                  ],
                ),
                if (plan)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: AppTag(l.srcWizardPlanTag, variant: TagVariant.plan),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
