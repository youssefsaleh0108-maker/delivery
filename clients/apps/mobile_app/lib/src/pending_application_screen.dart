import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// What an applicant sees between choosing a passcode and somebody deciding.
///
/// The account behind this holds APPLICANT and nothing else, so there is no shop and no job board
/// to show. Before this the application ended at a reference number and an instruction to wait for
/// an email — the applicant had no way in at all, and no way to tell whether anything was happening.
class PendingApplicationScreen extends StatefulWidget {
  const PendingApplicationScreen({
    super.key,
    required this.api,
    required this.session,
    required this.onSignOut,
    required this.onApproved,
  });

  final OnboardingApi api;
  final AuthSession session;
  final Future<void> Function() onSignOut;

  /// Called when the decision has landed and the token is out of date.
  ///
  /// The role lives in the access token, so an approval elsewhere does not reach a session already
  /// running. Signing out and back in is what picks it up, and saying so beats leaving somebody
  /// tapping refresh on a screen that will never change.
  final VoidCallback onApproved;

  @override
  State<PendingApplicationScreen> createState() => _PendingApplicationScreenState();
}

class _PendingApplicationScreenState extends State<PendingApplicationScreen> {
  late Future<OnboardingApplication?> _application = widget.api.mine();

  void _refresh() {
    setState(() => _application = widget.api.mine());
  }

  String _statusLabel(DeliveryStrings t, OnboardingStatus status) => switch (status) {
        OnboardingStatus.submitted => t.statusSubmitted,
        OnboardingStatus.inReview => t.statusInReview,
        OnboardingStatus.approved => t.statusApproved,
        OnboardingStatus.rejected => t.statusRejected,
        OnboardingStatus.provisioned => t.statusProvisioned,
        OnboardingStatus.failed => t.statusFailed,
      };

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: AppBar(
        backgroundColor: DeliveryColors.brand,
        foregroundColor: DeliveryColors.white,
        elevation: 0,
        title: Text(t.applicationPending,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: <Widget>[
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: t.checkAgain,
          ),
        ],
      ),
      body: FutureBuilder<OnboardingApplication?>(
        future: _application,
        builder: (BuildContext context, AsyncSnapshot<OnboardingApplication?> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
          }

          final OnboardingApplication? application = snapshot.data;

          // Approved and set up: the application is behind them, but this session's token still
          // says APPLICANT. Ask for a fresh sign-in rather than leaving them here.
          if (application == null || application.status == OnboardingStatus.provisioned) {
            return _approved(t, theme);
          }

          return ListView(
            padding: const EdgeInsets.all(DeliverySpacing.lg),
            children: <Widget>[
              const SizedBox(height: DeliverySpacing.md),
              const Icon(Icons.hourglass_top_rounded, size: 56, color: DeliveryColors.brand),
              const SizedBox(height: DeliverySpacing.md),
              Text(application.businessName,
                  textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
              const SizedBox(height: DeliverySpacing.xs),
              Text(t.weAreReadingIt,
                  textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
              const SizedBox(height: DeliverySpacing.lg),
              SoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(t.applicationStatus, style: theme.textTheme.bodySmall),
                    const SizedBox(height: DeliverySpacing.xs),
                    Text(_statusLabel(t, application.status),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: DeliverySpacing.sm),
                    Text(t.yourApplicationReference, style: theme.textTheme.bodySmall),
                    const SizedBox(height: DeliverySpacing.xs),
                    SelectableText(application.reference,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(height: DeliverySpacing.md),
              SoftNote(icon: Icons.info_outline, text: t.nextStepsPending),
              const SizedBox(height: DeliverySpacing.lg),
              OutlinedButton(onPressed: _refresh, child: Text(t.checkAgain)),
              const SizedBox(height: DeliverySpacing.sm),
              TextButton(
                onPressed: () => widget.onSignOut(),
                child: Text(t.signOut),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _approved(DeliveryStrings t, ThemeData theme) => ListView(
        padding: const EdgeInsets.all(DeliverySpacing.lg),
        children: <Widget>[
          const SizedBox(height: DeliverySpacing.xl),
          const Icon(Icons.check_circle, size: 56, color: Color(0xFF25834B)),
          const SizedBox(height: DeliverySpacing.md),
          Text(t.statusProvisioned,
              textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
          const SizedBox(height: DeliverySpacing.sm),
          Text(t.nextStepsPending,
              textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          const SizedBox(height: DeliverySpacing.lg),
          PrimaryAction(label: t.signOut, onPressed: widget.onApproved),
        ],
      );
}
