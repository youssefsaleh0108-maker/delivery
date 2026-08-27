import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'application_documents_step.dart';
import 'one_time_code.dart';
import 'payout_details_step.dart';

/// What an applicant sees between sending an application and somebody deciding.
///
/// <p>The account behind this holds APPLICANT and nothing else, so there is no shop and no job
/// board to show. Before this the application ended at a reference number and an instruction to
/// wait for an email — the applicant had no way in at all, and no way to tell whether anything was
/// happening.
///
/// <p>Figma draws two of these. `merchant-pending-approval` (22:1107) is the light one: a checklist
/// of what has happened and what has not, and an amber note explaining that the account works while
/// the decision is pending. `rider-pending-approval` (22:651) is the brand-filled one: a
/// confirmation, a timeline of what comes next, and a white button back out. Both are here, chosen
/// by the kind of application the server returns, because both are drawn and the two audiences
/// genuinely want different things — a shop wants to start setting up, a rider wants to know when
/// they can ride.
///
/// <p>Every state on both is read from the application rather than illustrated. Nothing is ticked
/// because the design ticks it: the documents line follows what the reviewer has actually decided,
/// and both screens now carry the applicant's real documents and bank details — replaceable and
/// correctable for as long as the application is undecided, because this screen is exactly where
/// somebody stuck on a refused photograph goes to get unstuck.
class PendingApplicationScreen extends StatefulWidget {
  const PendingApplicationScreen({
    super.key,
    required this.api,
    required this.documentsApi,
    required this.session,
    required this.onSignOut,
    required this.onApproved,
    this.onExplore,
  });

  final OnboardingApi api;

  /// The applicant's own documents and bank details — readable here, and writable for as long as
  /// the application is undecided, because this screen is where a refused document gets replaced.
  final DocumentsApi documentsApi;

  final AuthSession session;
  final Future<void> Function() onSignOut;

  /// Called when the decision has landed and the token is out of date.
  ///
  /// The role lives in the access token, so an approval elsewhere does not reach a session already
  /// running. Signing out and back in is what picks it up, and saying so beats leaving somebody
  /// tapping refresh on a screen that will never change.
  final VoidCallback onApproved;

  /// Enters the role's own shell — the design's "Explore Dashboard".
  ///
  /// <p>Pending partners who already carry their role never reach this screen: the router sends
  /// them straight to their shell with a banner, and the server refuses only the committing acts.
  /// The people who *do* reach it hold APPLICANT and nothing else, and for them there is no shell
  /// to enter — so this is null there and the drawn button carries the one action that is real,
  /// which is asking the server again. It becomes the dashboard the moment the router has somewhere
  /// to send them.
  final VoidCallback? onExplore;

  @override
  State<PendingApplicationScreen> createState() =>
      _PendingApplicationScreenState();
}

/// How one line of the checklist stands.
enum _Mark {
  /// Happened.
  done,

  /// Happening now.
  current,

  /// Not yet, and not started.
  locked,

  /// Went wrong.
  failed,
}

class _PendingApplicationScreenState extends State<PendingApplicationScreen> {
  late Future<OnboardingApplication?> _application = widget.api.mine();

  /// Fetched lazily, only once an application is known to exist — the endpoints 404 for anybody
  /// without one, and an eagerly-fired future nobody ever listens to is an unhandled error.
  Future<List<ApplicantDocument>>? _documents;
  Future<PayoutDetails?>? _payout;

  void _refresh() {
    setState(() {
      _application = widget.api.mine();
      _documents = null;
      _payout = null;
    });
  }

  void _reloadDocuments() {
    setState(() => _documents = widget.documentsApi.myDocuments());
  }

  void _reloadPayout() {
    setState(() => _payout = widget.documentsApi.myPayout());
  }

  String _statusLabel(DeliveryStrings t, OnboardingStatus status) =>
      switch (status) {
        OnboardingStatus.submitted => t.statusSubmitted,
        OnboardingStatus.inReview => t.statusInReview,
        OnboardingStatus.approved => t.statusApproved,
        OnboardingStatus.rejected => t.statusRejected,
        OnboardingStatus.provisioned => t.statusProvisioned,
        OnboardingStatus.failed => t.statusFailed,
      };

  /// What the papers this kind of applicant is expected to produce are — riders one list,
  /// everybody else the registered-business list, mirroring the service's `DocumentKind`.
  List<ApplicantDocumentKind> _expectedKinds(OnboardingApplication a) =>
      expectedDocumentKinds(rider: a.kind == OnboardingKind.rider);

  /// How the checklist's documents line stands, read from the real documents rather than
  /// illustrated. No data (still loading, or the fetch failed) renders as locked — the state the
  /// line was born with — rather than as a claim.
  _Mark _documentsMark(
      List<ApplicantDocument>? documents, List<ApplicantDocumentKind> expected) {
    if (documents == null || documents.isEmpty) return _Mark.locked;
    if (documents.any((ApplicantDocument d) =>
        d.status == ApplicantDocumentStatus.rejected)) {
      return _Mark.failed;
    }
    final Set<ApplicantDocumentKind> approved = <ApplicantDocumentKind>{
      for (final ApplicantDocument d in documents)
        if (d.status == ApplicantDocumentStatus.approved && d.kind != null)
          d.kind!,
    };
    if (expected.every(approved.contains)) return _Mark.done;
    return _Mark.current;
  }

  /// The documents card, with its own loading and failed states so the rest of the screen never
  /// waits on it. [onBrand] flips the spinner to white for the rider's brand-filled surface.
  Widget _documentsSection(DeliveryStrings t, OnboardingApplication a,
      AsyncSnapshot<List<ApplicantDocument>> snapshot,
      {bool onBrand = false}) {
    if (snapshot.connectionState != ConnectionState.done) {
      return Padding(
        padding: const EdgeInsets.all(DeliverySpacing.lg),
        child: Center(
            child: CircularProgressIndicator(
                color: onBrand ? DeliveryColors.white : DeliveryColors.brand)),
      );
    }
    if (snapshot.hasError) {
      return YdCard.bordered(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(t.wizDocCouldNotLoad,
                style: const TextStyle(
                    fontSize: 13, color: DeliveryColors.muted)),
            const SizedBox(height: DeliverySpacing.sm),
            OutlinedButton(
              onPressed: _reloadDocuments,
              child: Text(t.tryAgain),
            ),
          ],
        ),
      );
    }
    return ApplicantDocumentsCard(
      api: widget.documentsApi,
      documents: snapshot.data ?? const <ApplicantDocument>[],
      kinds: _expectedKinds(a),
      canUpload: !a.status.isDecided,
      onChanged: _reloadDocuments,
    );
  }

  /// The bank-details card, same contract.
  Widget _payoutSection(DeliveryStrings t, OnboardingApplication a,
      {bool onBrand = false}) {
    _payout ??= widget.documentsApi.myPayout();
    return FutureBuilder<PayoutDetails?>(
      future: _payout,
      builder:
          (BuildContext context, AsyncSnapshot<PayoutDetails?> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.all(DeliverySpacing.lg),
            child: Center(
                child: CircularProgressIndicator(
                    color:
                        onBrand ? DeliveryColors.white : DeliveryColors.brand)),
          );
        }
        if (snapshot.hasError) {
          return YdCard.bordered(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(t.wizPayoutCouldNotLoad,
                    style: const TextStyle(
                        fontSize: 13, color: DeliveryColors.muted)),
                const SizedBox(height: DeliverySpacing.sm),
                OutlinedButton(
                  onPressed: _reloadPayout,
                  child: Text(t.tryAgain),
                ),
              ],
            ),
          );
        }
        return PayoutDetailsCard(
          api: widget.documentsApi,
          payout: snapshot.data,
          canEdit: !a.status.isDecided,
          onChanged: _reloadPayout,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return FutureBuilder<OnboardingApplication?>(
      future: _application,
      builder: (BuildContext context,
          AsyncSnapshot<OnboardingApplication?> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: DeliveryColors.background,
            body: Center(
                child: CircularProgressIndicator(color: DeliveryColors.brand)),
          );
        }

        final OnboardingApplication? application = snapshot.data;

        // Approved and set up: the application is behind them, but this session's token still says
        // APPLICANT. Ask for a fresh sign-in rather than leaving them here.
        if (application == null ||
            application.status == OnboardingStatus.provisioned) {
          return _approved(t);
        }

        // A shop is shown the checklist, a rider the timeline. `OnboardingKind` names the two the
        // server distinguishes; anything that is not a shop is somebody who wants to ride.
        return application.kind == OnboardingKind.merchant
            ? _merchantReview(t, application)
            : _riderSubmitted(t, application);
      },
    );
  }

  // ------------------------------------------------------------------ the light one

  Widget _merchantReview(DeliveryStrings t, OnboardingApplication a) {
    final bool decided = a.status == OnboardingStatus.approved ||
        a.status == OnboardingStatus.provisioned;
    final bool broken = a.status == OnboardingStatus.rejected ||
        a.status == OnboardingStatus.failed;

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: <Widget>[
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(DeliverySpacing.lg),
                    child: Column(
                      children: <Widget>[
                        Container(
                          width: 80,
                          height: 80,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: DeliveryColors.brandSoft,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.schedule,
                              size: 40, color: DeliveryColors.brand),
                        ),
                        const SizedBox(height: DeliverySpacing.lg),
                        Text(
                          t.authApplicationUnderReview,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: DeliveryColors.ink,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: DeliverySpacing.sm),
                        Text(
                          t.authApplicationUnderReviewBlurb,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: DeliveryColors.muted,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: DeliverySpacing.lg),
                        _ExplorationNote(),
                        const SizedBox(height: DeliverySpacing.lg),
                        Builder(builder: (BuildContext context) {
                          _documents ??= widget.documentsApi.myDocuments();
                          return FutureBuilder<List<ApplicantDocument>>(
                            future: _documents,
                            builder: (BuildContext context,
                                AsyncSnapshot<List<ApplicantDocument>>
                                    snapshot) {
                              final List<ApplicantDocument>? docs =
                                  snapshot.connectionState ==
                                              ConnectionState.done &&
                                          !snapshot.hasError
                                      ? snapshot.data
                                      : null;
                              return Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  YdCard.bordered(
                                    radius: 20,
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          t.authApplicationChecklist,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: DeliveryColors.ink,
                                            height: 1.2,
                                          ),
                                        ),
                                        const SizedBox(
                                            height: DeliverySpacing.md),
                                        _ChecklistLine(
                                          label:
                                              t.authChecklistAccountCreated,
                                          mark: _Mark.done,
                                        ),
                                        // Read from the real documents now that a pipeline
                                        // exists — done only once every expected paper is
                                        // approved, failed the moment one is refused.
                                        _ChecklistLine(
                                          label: t.authChecklistDocuments,
                                          mark: _documentsMark(
                                              docs, _expectedKinds(a)),
                                        ),
                                        _ChecklistLine(
                                          label: t.authChecklistAudit,
                                          mark: broken
                                              ? _Mark.failed
                                              : decided
                                                  ? _Mark.done
                                                  : _Mark.current,
                                        ),
                                        _ChecklistLine(
                                          label: t.authChecklistActivation,
                                          mark: _Mark.locked,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: DeliverySpacing.md),
                                  _StatusCard(
                                    statusLabel: _statusLabel(t, a.status),
                                    reference: a.reference,
                                  ),
                                  const SizedBox(height: DeliverySpacing.md),
                                  _documentsSection(t, a, snapshot),
                                ],
                              );
                            },
                          );
                        }),
                        const SizedBox(height: DeliverySpacing.md),
                        _payoutSection(t, a),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(DeliverySpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        AuthPrimaryButton(
                          label: widget.onExplore == null
                              ? t.checkAgain
                              : t.authExploreDashboard,
                          trailingIcon: widget.onExplore == null
                              ? Icons.refresh
                              : Icons.arrow_forward,
                          onPressed: widget.onExplore ?? _refresh,
                        ),
                        const SizedBox(height: DeliverySpacing.sm),
                        Center(
                          child: TextButton(
                            onPressed: () => widget.onSignOut(),
                            child: Text(t.signOut),
                          ),
                        ),
                      ],
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

  // ------------------------------------------------------------------ the brand one

  Widget _riderSubmitted(DeliveryStrings t, OnboardingApplication a) {
    final bool reading = a.status == OnboardingStatus.submitted ||
        a.status == OnboardingStatus.inReview;

    return Scaffold(
      backgroundColor: DeliveryColors.brand,
      body: SafeArea(
        child: CustomScrollView(
          slivers: <Widget>[
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(DeliverySpacing.lg),
                    child: Column(
                      children: <Widget>[
                        Container(
                          width: 120,
                          height: 120,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: DeliveryColors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.schedule,
                              size: 56, color: DeliveryColors.brand),
                        ),
                        const SizedBox(height: DeliverySpacing.xl),
                        Text(
                          t.authApplicationSubmitted,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: DeliveryColors.white,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                        Text(
                          t.authApplicationSubmittedBlurb,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: DeliveryColors.onBrandSoft,
                            height: 20 / 14,
                          ),
                        ),
                        const SizedBox(height: DeliverySpacing.xl),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: DeliveryColors.white,
                            borderRadius:
                                BorderRadius.circular(DeliveryRadius.lg),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                t.authWhatToExpectNext.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: DeliveryColors.ink,
                                  height: 1.2,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const SizedBox(height: DeliverySpacing.md),
                              _TimelineLine(
                                label: t.authExpectVerification,
                                active: reading,
                              ),
                              _TimelineLine(
                                label: t.authExpectBackgroundCheck,
                                active: false,
                              ),
                              _TimelineLine(
                                label: t.authExpectTrainingInvite,
                                active: false,
                              ),
                              const SizedBox(height: DeliverySpacing.sm),
                              const Divider(
                                  height: 1, color: DeliveryColors.border),
                              const SizedBox(height: DeliverySpacing.md),
                              _StatusCard(
                                statusLabel: _statusLabel(t, a.status),
                                reference: a.reference,
                                bare: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: DeliverySpacing.md),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: DeliveryColors.white.withValues(alpha: 0.1),
                            borderRadius:
                                BorderRadius.circular(DeliveryRadius.md),
                          ),
                          child: Row(
                            children: <Widget>[
                              const Icon(Icons.notifications_none,
                                  size: 18, color: DeliveryColors.white),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  t.authWeWillNotifyYou,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: DeliveryColors.white,
                                    height: 16 / 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: DeliverySpacing.md),
                        // The verification the timeline's first line talks about is these
                        // documents. The cards are the light surface's own — white holds up on
                        // the brand fill — and Replace stays live until somebody decides.
                        Builder(builder: (BuildContext context) {
                          _documents ??= widget.documentsApi.myDocuments();
                          return FutureBuilder<List<ApplicantDocument>>(
                            future: _documents,
                            builder: (BuildContext context,
                                    AsyncSnapshot<List<ApplicantDocument>>
                                        snapshot) =>
                                _documentsSection(t, a, snapshot,
                                    onBrand: true),
                          );
                        }),
                        const SizedBox(height: DeliverySpacing.md),
                        _payoutSection(t, a, onBrand: true),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(DeliverySpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        AuthPrimaryButton(
                          label: widget.onExplore == null
                              ? t.checkAgain
                              : t.authExploreDashboard,
                          onWhite: true,
                          onPressed: widget.onExplore ?? _refresh,
                        ),
                        const SizedBox(height: DeliverySpacing.sm),
                        Center(
                          child: TextButton(
                            onPressed: () => widget.onSignOut(),
                            style: TextButton.styleFrom(
                                foregroundColor: DeliveryColors.white),
                            child: Text(t.signOut),
                          ),
                        ),
                      ],
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

  // ------------------------------------------------------------------ decided

  Widget _approved(DeliveryStrings t) => Scaffold(
        backgroundColor: DeliveryColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(DeliverySpacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                YdEmptyState(
                  icon: Icons.check_circle_outline,
                  title: t.statusProvisioned,
                  message: t.nextStepsPending,
                ),
                const SizedBox(height: DeliverySpacing.lg),
                AuthPrimaryButton(
                  label: t.signOut,
                  onPressed: widget.onApproved,
                ),
              ],
            ),
          ),
        ),
      );
}

/// The amber "Exploration Mode Active" banner (Figma `warning-banner` 22:1121).
///
/// The design letters the whole banner in amber-500 on amber-100, which measures under 2:1 and is
/// not readable. `tokens.dart` states the rule this runs into — the strong accent is for glyphs and
/// numbers on its own tint, never for body text — so the glyph keeps the amber and the words are
/// [DeliveryColors.ink]. Everything else about it is as drawn.
class _ExplorationNote extends StatelessWidget {
  const _ExplorationNote();

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.md),
      decoration: BoxDecoration(
        color: DeliveryAccent.caution.tint,
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
        border: Border.all(color: DeliveryAccent.caution.color),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline,
              size: 20, color: DeliveryAccent.caution.color),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  t.authExplorationModeActive,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t.authExplorationModeBlurb,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DeliveryColors.muted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of the merchant checklist (Figma 22:1129): a 24px round tile carrying the state's
/// glyph, then the label in the weight that state is drawn at.
class _ChecklistLine extends StatelessWidget {
  const _ChecklistLine({required this.label, required this.mark});

  final String label;
  final _Mark mark;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color tile, Color glyph, Color text, FontWeight weight) =
        switch (mark) {
      _Mark.done => (
          Icons.check,
          DeliveryAccent.positive.tint,
          DeliveryAccent.positive.color,
          DeliveryColors.ink,
          FontWeight.w500,
        ),
      _Mark.current => (
          Icons.autorenew,
          DeliveryColors.brandSoft,
          DeliveryColors.brand,
          DeliveryColors.brand,
          FontWeight.w600,
        ),
      _Mark.locked => (
          Icons.lock_outline,
          DeliveryColors.border,
          DeliveryColors.muted,
          DeliveryColors.faint,
          FontWeight.w400,
        ),
      _Mark.failed => (
          Icons.close,
          DeliveryAccent.critical.tint,
          DeliveryAccent.critical.color,
          DeliveryColors.ink,
          FontWeight.w600,
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: tile, shape: BoxShape.circle),
            child: Icon(icon, size: 14, color: glyph),
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: weight,
                color: text,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of the rider timeline (Figma 22:671): a filled brand dot for the step in progress, a
/// hollow one for the steps that have not started.
class _TimelineLine extends StatelessWidget {
  const _TimelineLine({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: <Widget>[
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? DeliveryColors.brand : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: active ? DeliveryColors.brand : DeliveryColors.border,
                width: 2,
              ),
            ),
            child: active
                ? const Icon(Icons.circle, size: 6, color: DeliveryColors.white)
                : null,
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? DeliveryColors.ink : DeliveryColors.muted,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The status and reference the applicant actually needs.
///
/// The redesign draws neither — both pending frames are illustrations of a happy path, with no
/// state on them at all. They are kept because the reference is the only thing an applicant can
/// quote when they write in, and the status is the only part of this screen that ever changes.
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.statusLabel,
    required this.reference,
    this.bare = false,
  });

  final String statusLabel;
  final String reference;

  /// Drops the card shell, for when this already sits inside one.
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    final Widget body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                t.applicationStatus,
                style: const TextStyle(
                    fontSize: 12, color: DeliveryColors.muted, height: 1.3),
              ),
              const SizedBox(height: 2),
              Text(
                statusLabel,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.ink,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: DeliverySpacing.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              t.yourApplicationReference,
              style: const TextStyle(
                  fontSize: 12, color: DeliveryColors.muted, height: 1.3),
            ),
            const SizedBox(height: 2),
            SelectableText(
              reference,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: DeliveryColors.ink,
                fontFamily: 'monospace',
                height: 1.3,
              ),
            ),
          ],
        ),
      ],
    );

    return bare ? body : YdCard.bordered(child: body);
  }
}
