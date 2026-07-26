import 'dart:async';

import 'package:flutter/material.dart';
import 'package:my_nas/app/router/app_router.dart';
import 'package:my_nas/core/network/tls_trust_store.dart';
import 'package:my_nas/l10n/app_localizations.dart';

/// Hosts the global, queued HTTPS certificate trust prompt.
class TlsTrustPromptHost extends StatefulWidget {
  const TlsTrustPromptHost({required this.child, super.key});

  final Widget child;

  @override
  State<TlsTrustPromptHost> createState() => _TlsTrustPromptHostState();
}

class _TlsTrustPromptHostState extends State<TlsTrustPromptHost> {
  bool _dialogOpen = false;
  Timer? _navigatorRetryTimer;

  @override
  void initState() {
    super.initState();
    TlsTrustStore.pendingRequest.addListener(_onPendingRequestChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPendingRequest());
  }

  @override
  void dispose() {
    _navigatorRetryTimer?.cancel();
    TlsTrustStore.pendingRequest.removeListener(_onPendingRequestChanged);
    super.dispose();
  }

  void _onPendingRequestChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPendingRequest());
  }

  Future<void> _showPendingRequest() async {
    if (!mounted || _dialogOpen) return;
    final request = TlsTrustStore.pendingRequest.value;
    if (request == null) return;

    final navigatorContext = rootNavigatorKey.currentContext;
    if (navigatorContext == null) {
      _navigatorRetryTimer?.cancel();
      _navigatorRetryTimer = Timer(
        const Duration(milliseconds: 250),
        _showPendingRequest,
      );
      return;
    }

    _dialogOpen = true;
    try {
      final approved = await showDialog<bool>(
        context: navigatorContext,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (dialogContext) => _TlsTrustDialog(request: request),
      );
      await TlsTrustStore.resolveTrustRequest(
        request,
        approved: approved ?? false,
      );
    } finally {
      _dialogOpen = false;
      if (mounted && TlsTrustStore.pendingRequest.value != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _showPendingRequest(),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _TlsTrustDialog extends StatelessWidget {
  const _TlsTrustDialog({required this.request});

  final TlsTrustRequest request;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final certificate = request.certificate;
    final warningColor = request.certificateChanged
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    final expires = MaterialLocalizations.of(
      context,
    ).formatMediumDate(certificate.endValidity.toLocal());

    return PopScope(
      canPop: false,
      child: AlertDialog(
        scrollable: true,
        icon: Icon(
          request.certificateChanged
              ? Icons.gpp_bad_outlined
              : Icons.verified_user_outlined,
          color: warningColor,
          size: 36,
        ),
        title: Text(
          request.certificateChanged
              ? l10n.tlsTrustChangedDialogTitle
              : l10n.tlsTrustDialogTitle,
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                request.certificateChanged
                    ? l10n.tlsTrustChangedDialogMessage(certificate.endpoint)
                    : l10n.tlsTrustDialogMessage(certificate.endpoint),
              ),
              const SizedBox(height: 16),
              _CertificateField(
                label: l10n.tlsTrustFingerprint,
                value: TlsTrustStore.formatFingerprint(certificate.fingerprint),
                selectable: true,
              ),
              if (certificate.subject.isNotEmpty) ...[
                const SizedBox(height: 10),
                _CertificateField(
                  label: l10n.tlsTrustCertificateSubject,
                  value: certificate.subject,
                ),
              ],
              const SizedBox(height: 10),
              _CertificateField(label: l10n.tlsTrustValidity, value: expires),
              const SizedBox(height: 16),
              Text(
                l10n.tlsTrustSaveAndRetryHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.tlsTrustCancel),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.lock_outline_rounded, size: 18),
            label: Text(l10n.tlsTrustAndContinue),
          ),
        ],
      ),
    );
  }
}

class _CertificateField extends StatelessWidget {
  const _CertificateField({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600);
    final valueStyle = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(height: 3),
        if (selectable)
          SelectableText(value, style: valueStyle)
        else
          Text(value, style: valueStyle),
      ],
    );
  }
}
