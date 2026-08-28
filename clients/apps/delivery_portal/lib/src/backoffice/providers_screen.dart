import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../shell/shell.dart';

/// Who carries orders: the platform's own fleet, the delivery companies, and merchants' drivers.
///
/// This is the operating surface for the delivery marketplace. Onboard a company, staff it, and
/// stop it when it stops performing — all of which existed only over the API until now.
///
/// Drawn as `backoffice-carriers` (Figma 3:2940): a wrapping grid of 260px cards rather than a
/// table, because a carrier is read as a whole — its state, its size and its score together — where
/// an order or a partner is scanned down a column. Each card carries the two decisions the design
/// draws; everything else a carrier needs (its payout account, its logins, its roster) opens in the
/// drawer behind the first of them.
class ProvidersScreen extends StatefulWidget {
  const ProvidersScreen({super.key, required this.api, this.notificationApi});

  final DeliveryProviderApi api;

  /// The in-app inbox behind the header bell, exactly as the other Backoffice frames carry it.
  ///
  /// This screen kept a greyed bell and a "coming soon" chip after the inbox went live on the
  /// other five — the feed existed, this frame just never asked for it.
  final NotificationApi? notificationApi;

  @override
  State<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends State<ProvidersScreen> {
  late Future<Paged<DeliveryProviderInfo>> _page = widget.api.all(size: 50);

  /// Scores by provider id, loaded once for the page rather than per card.
  ///
  /// One aggregate query serves the whole register, so asking per card would be dozens of requests
  /// for the same answer. A failure here leaves the cards without scores rather than without cards:
  /// the ranking is context, the register is the page.
  late Future<Map<String, CarrierScore>> _scores = _loadScores();

  String? _busyId;

  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// Per-carrier rosters, held rather than created in `build`.
  ///
  /// A FutureBuilder whose future is constructed inline fires a fresh request on every rebuild —
  /// and this page rebuilds on every score arriving, every busy flag and every snackbar. That was
  /// N requests per repaint for answers that had not changed. Cleared by [_reload], which is the
  /// only moment they can actually be stale.
  final Map<String, Future<List<String>>> _riderFutures = <String, Future<List<String>>>{};
  final Map<String, Future<List<String>>> _staffFutures = <String, Future<List<String>>>{};

  Future<List<String>> _ridersOf(String id) =>
      _riderFutures.putIfAbsent(id, () => widget.api.riders(id));

  Future<List<String>> _staffOf(String id) =>
      _staffFutures.putIfAbsent(id, () => widget.api.staff(id));

  Future<Map<String, CarrierScore>> _loadScores() async {
    try {
      final List<CarrierScore> all = await widget.api.scores();
      return <String, CarrierScore>{for (final CarrierScore s in all) s.providerId: s};
    } catch (_) {
      return <String, CarrierScore>{};
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _page = widget.api.all(size: 50);
      _scores = _loadScores();
      _riderFutures.clear();
      _staffFutures.clear();
    });
  }

  /// Attaches a login that may administer this carrier.
  ///
  /// The last step of onboarding, and the one that was only possible with curl: a carrier could be
  /// registered, have its payout account verified and be given riders, and still have no way to
  /// sign in and see any of it.
  Future<void> _addStaff(DeliveryProviderInfo provider) async {
    final String? userRef = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const _AddStaffDialog(),
    );
    if (userRef == null || userRef.isEmpty) return;

    await _run(provider.id, () => widget.api.addStaff(provider.id, userRef),
        'That account can now administer ${provider.name}');
  }

  /// Runs a write and reloads, turning whatever went wrong into one sentence.
  ///
  /// Catches everything rather than only [DioException]: a failure that is not an HTTP failure
  /// would otherwise leave a button looking like it simply does nothing.
  /// @param success the message to show, or null when the action reports its own outcome.
  Future<void> _run(String id, Future<void> Function() action, String? success) async {
    setState(() => _busyId = id);
    try {
      await action();
      if (!mounted) return;
      if (success != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      }
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_messageFor(e))));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  static String _messageFor(Object error) {
    if (error is DioException) {
      final dynamic body = error.response?.data;
      if (body is Map && body['detail'] is String) return body['detail'] as String;
      if (error.response?.statusCode == 409) return 'That handle is already taken';
    }
    return 'That did not work: $error';
  }

  Future<void> _onboard() async {
    final _NewProvider? draft = await showDialog<_NewProvider>(
      context: context,
      builder: (BuildContext context) => const _OnboardDialog(),
    );
    if (draft == null) return;

    await _run(
      'new',
      () => widget.api
          .register(
            slug: draft.slug,
            name: draft.name,
            contactName: draft.contactName,
            contactPhone: draft.contactPhone,
            accountRef: draft.accountRef,
          )
          .then((_) {}),
      'Delivery company onboarded',
    );
  }

  /// Asks the bank again about a carrier's payout account.
  ///
  /// Reports what came back rather than assuming it worked. A re-check that still cannot confirm
  /// the account is the normal outcome when the account is genuinely wrong, and a blanket "done"
  /// would read as the opposite.
  Future<void> _verifyPayout(DeliveryProviderInfo provider) async {
    await _run(
      provider.id,
      () async {
        final DeliveryProviderInfo checked = await widget.api.verifyPayout(provider.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(checked.payoutState == PayoutState.verified
              ? '${checked.name}: the bank confirmed ${checked.accountRef}'
              : '${checked.name}: still unconfirmed'
                  '${checked.payoutDetail == null ? '' : ' — ${checked.payoutDetail}'}'),
        ));
      },
      // The per-outcome message above is the useful one; this would only talk over it.
      null,
    );
  }

  Future<void> _addRider(DeliveryProviderInfo provider) async {
    final String? riderRef = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const _AddRiderDialog(),
    );
    if (riderRef == null || riderRef.isEmpty) return;

    await _run(provider.id, () => widget.api.assignRider(provider.id, riderRef),
        'Rider moved to ${provider.name}');
  }

  @override
  Widget build(BuildContext context) {
    return ConsolePage(
      header: ConsoleTopbar(
        title: 'Fleet Carriers',
        subtitle: 'Manage logistic companies and delivery partners',
        actions: <Widget>[
          // Real, and filtering what is already loaded. The design draws only the global search on
          // this frame; a register of carriers with no way to find one in it is the kind of
          // fidelity that costs an operator a minute every time.
          ConsoleSearchField(
            hintText: 'Search carriers...',
            controller: _search,
            onChanged: (String v) => setState(() => _query = v),
          ),
          ConsoleBell(api: widget.notificationApi),
          // Not drawn on this frame, and it has to be here: onboarding a company is the only way a
          // carrier enters the register at all, and it lived on a floating button before.
          ConsoleButton(
            label: 'Onboard a company',
            icon: Icons.add,
            tone: ConsoleButtonTone.solid,
            onPressed: _busy ? null : _onboard,
          ),
        ],
      ),
      children: <Widget>[
        FutureBuilder<Paged<DeliveryProviderInfo>>(
          future: _page,
          builder: (BuildContext context, AsyncSnapshot<Paged<DeliveryProviderInfo>> snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const ConsoleCard(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: DeliverySpacing.xl),
                    child: CircularProgressIndicator(color: DeliveryColors.brand),
                  ),
                ),
              );
            }
            if (snapshot.hasError) {
              return ConsoleCard(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.lg),
                    child: Text('Could not load providers: ${snapshot.error}',
                        style: ConsoleText.cellStrong),
                  ),
                ),
              );
            }

            final List<DeliveryProviderInfo> providers = snapshot.data!.content;
            // The platform's own fleet first — it is the default carrier and the one an operator
            // checks against — then companies, then merchants' own drivers.
            final List<DeliveryProviderInfo> sorted = <DeliveryProviderInfo>[
              ...providers.where((DeliveryProviderInfo p) => p.kind == ProviderKind.platform),
              ...providers.where((DeliveryProviderInfo p) => p.kind == ProviderKind.external),
              ...providers.where((DeliveryProviderInfo p) => p.kind == ProviderKind.merchant),
            ];

            final String q = _query.trim().toLowerCase();
            final List<DeliveryProviderInfo> shown = q.isEmpty
                ? sorted
                : sorted
                    .where((DeliveryProviderInfo p) =>
                        p.name.toLowerCase().contains(q) || p.slug.toLowerCase().contains(q))
                    .toList();

            if (shown.isEmpty) {
              return ConsoleCard(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.lg),
                    child: Text(
                      providers.isEmpty
                          ? 'No delivery providers yet.'
                          : 'No carrier matches that search.',
                      style: ConsoleText.cellStrong,
                    ),
                  ),
                ),
              );
            }

            // Nested rather than combined into one future: the register renders as soon as it
            // arrives, and the scores fill in behind it. An operator opening this page to suspend a
            // carrier should not wait on a ranking they did not ask for.
            return FutureBuilder<Map<String, CarrierScore>>(
              future: _scores,
              builder:
                  (BuildContext context, AsyncSnapshot<Map<String, CarrierScore>> scores) {
                final Map<String, CarrierScore> byId =
                    scores.data ?? const <String, CarrierScore>{};
                return Wrap(
                  spacing: ConsoleMetrics.pageGap,
                  runSpacing: ConsoleMetrics.pageGap,
                  children: <Widget>[
                    for (final DeliveryProviderInfo p in shown)
                      SizedBox(width: _cardWidth, child: _card(p, byId[p.id])),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }

  /// The design's fixed card width (3:2995). Fixed rather than fractional on purpose: four across
  /// at 1440 and three at 1100 is the design's own behaviour, and a card that stretches would put
  /// its two buttons a hand's width apart.
  static const double _cardWidth = 260;

  bool get _busy => _busyId != null;

  // -------------------------------------------------------------------- the card

  Widget _card(DeliveryProviderInfo p, CarrierScore? score) {
    final bool busy = _busyId == p.id;
    final DeliveryAccent accent = _accentFor(p);
    final bool suspended = p.status == ProviderStatus.suspended;

    return Container(
      padding: const EdgeInsets.all(ConsoleMetrics.cardPadding),
      decoration: ConsoleSurface.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
                decoration: BoxDecoration(
                  color: DeliveryColors.brandSoft,
                  borderRadius: BorderRadius.circular(DeliveryRadius.md),
                ),
                child: Icon(_iconFor(p.kind), size: 24, color: DeliveryColors.brand),
              ),
              const Spacer(),
              ConsoleStatusPill(label: p.status.label, accent: accent),
            ],
          ),
          const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),

          Text(
            p.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
            ),
          ),
          const SizedBox(height: DeliverySpacing.xs),
          Text(
            // The design's "Partner since Jan 10, 2025" where the register carries a date, and
            // what the carrier *is* where it does not — never an invented date.
            p.createdAt == null
                ? '${p.kind.label} · ${p.slug}'
                : 'Partner since ${_date(p.createdAt!)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: DeliveryColors.faint),
          ),

          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          const Divider(height: 1, color: DeliveryColors.border),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: _stat('Riders', _riderCount(p))),
              // The design's right-hand figure is a live order count, which no endpoint answers
              // per carrier. The Delivery Score is the other number an operator reads a carrier
              // by, it is real, and it belongs in crimson for the same reason.
              _stat(
                'Delivery score',
                score == null
                    ? const ConsoleNoValue(tooltip: 'No score for this provider yet')
                    : Text(
                        score.provisional ? '${score.score}?' : '${score.score}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: score.provisional
                              ? DeliveryColors.faint
                              : DeliveryColors.brand,
                        ),
                      ),
                alignEnd: true,
              ),
            ],
          ),

          // The one warning that must not wait for somebody to open the drawer: a carrier the
          // platform cannot pay is silent until an order has already been delivered.
          if (_payoutTrouble(p) != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            _CardNote(text: _payoutTrouble(p)!, accent: _payoutAccent(p)),
          ],

          const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
          Row(
            children: <Widget>[
              Expanded(
                child: ConsoleButton(
                  label: 'Manage',
                  tone: ConsoleButtonTone.tinted,
                  busy: busy,
                  onPressed: () => _openDrawer(p, score),
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              Expanded(
                // Suspension is the platform's, and reinstatement is too — a suspended provider
                // cannot resume itself, which is the whole difference from pausing. The in-house
                // fleet is exempt: stopping it would stop every order that has no other carrier.
                child: ConsoleButton(
                  label: suspended ? 'Reinstate' : 'Suspend',
                  tone: ConsoleButtonTone.outlined,
                  onPressed: busy || (p.isInHouse && !suspended)
                      ? null
                      : () => _run(
                            p.id,
                            () => (suspended
                                    ? widget.api.reinstate(p.id)
                                    : widget.api.suspend(p.id))
                                .then((_) {}),
                            '${p.name} ${suspended ? 'reinstated' : 'suspended'}',
                          ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// One half of the card's stats row: a faint caption over a bold figure.
  Widget _stat(String label, Widget value, {bool alignEnd = false}) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: const TextStyle(fontSize: 12, color: DeliveryColors.faint)),
        const SizedBox(height: 2),
        value,
      ],
    );
  }

  /// The roster's size, loaded per card.
  ///
  /// A separate request each rather than one joined list: rosters are small, an operator opens
  /// this page to look at one carrier, and the joined endpoint does not exist.
  Widget _riderCount(DeliveryProviderInfo p) {
    if (p.isInHouse) {
      // Membership is opt-in, so the in-house roster is empty by definition — every rider who has
      // not been moved elsewhere belongs to it. Saying that beats showing "0".
      return const Tooltip(
        message: 'Every rider not assigned to another fleet',
        child: Text(
          'All',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: DeliveryColors.ink),
        ),
      );
    }
    return FutureBuilder<List<String>>(
      future: _ridersOf(p.id),
      builder: (BuildContext context, AsyncSnapshot<List<String>> snapshot) {
        if (!snapshot.hasData) {
          return const Text('…',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                  color: DeliveryColors.faint));
        }
        final int count = snapshot.data!.length;
        return Text(
          '$count',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            // A carrier with no riders cannot take work at all. Worth reading as a state rather
            // than as a zero.
            color: count == 0 ? DeliveryAccent.caution.color : DeliveryColors.ink,
          ),
        );
      },
    );
  }

  static String? _payoutTrouble(DeliveryProviderInfo p) {
    if (p.accountRef == null && p.kind == ProviderKind.external) {
      return 'No payout account — every payment to this carrier will fail.';
    }
    if (p.accountRef != null && p.payoutState.needsAttention) {
      return 'The bank has not confirmed this account.';
    }
    return null;
  }

  static DeliveryAccent _payoutAccent(DeliveryProviderInfo p) =>
      p.accountRef == null ? DeliveryAccent.critical : DeliveryAccent.caution;

  // -------------------------------------------------------------------- the drawer

  Future<void> _openDrawer(DeliveryProviderInfo p, CarrierScore? score) async {
    await showConsoleDrawer<void>(
      context: context,
      title: p.name,
      subtitle: '${p.kind.label} · ${p.slug}',
      badge: ConsoleStatusPill(label: p.status.label, accent: _accentFor(p)),
      builder: (BuildContext drawerContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ConsoleDrawerSection(
            title: 'Delivery score',
            first: true,
            child: _scoreDetail(score),
          ),
          ConsoleDrawerSection(
            title: 'Payout',
            trailing: p.accountRef == null
                ? null
                : ConsoleButton(
                    label: p.payoutState.needsAttention
                        ? 'Check with the bank'
                        : 'Re-check account',
                    onPressed: _busy
                        ? null
                        : () {
                            Navigator.of(drawerContext).pop();
                            _verifyPayout(p);
                          },
                  ),
            child: _payoutDetail(p),
          ),
          // Only companies have logins. A merchant's own fleet is administered by the merchant in
          // their own portal, and the in-house fleet from this page.
          if (p.kind == ProviderKind.external)
            ConsoleDrawerSection(
              title: 'Logins',
              trailing: ConsoleButton(
                label: 'Give someone access',
                onPressed: _busy
                    ? null
                    : () {
                        Navigator.of(drawerContext).pop();
                        _addStaff(p);
                      },
              ),
              child: _staff(p),
            ),
          ConsoleDrawerSection(
            title: 'Riders',
            trailing: p.isInHouse
                ? null
                : ConsoleButton(
                    label: 'Add a rider',
                    onPressed: _busy
                        ? null
                        : () {
                            Navigator.of(drawerContext).pop();
                            _addRider(p);
                          },
                  ),
            child: _riders(p),
          ),
        ],
      ),
    );
  }

  Widget _scoreDetail(CarrierScore? score) {
    if (score == null) {
      return const Text(
        'No score yet — this carrier has not been ranked.',
        style: ConsoleText.body,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(
              '${score.score}',
              style: ConsoleText.kpiValue.copyWith(
                // A provisional score is an assumption, not a measurement, and painting it in the
                // brand colour would dress up "we have no idea yet" as "this carrier is good".
                color: score.provisional ? DeliveryColors.faint : DeliveryColors.brand,
              ),
            ),
            const SizedBox(width: DeliverySpacing.sm),
            if (score.provisional)
              // A measured state, not an unbuilt one: the score is answered, it is just answered
              // from too few orders to lean on. The quiet pill, not the coming-soon chip.
              const ConsoleQuietChip(label: 'Provisional')
            else
              Text('out of 100', style: ConsoleText.meta),
          ],
        ),
        const SizedBox(height: DeliverySpacing.sm),
        Text(
          score.provisional
              ? 'Only ${score.orders} orders so far, so this is mostly an assumption.'
              // The parts, not just the verdict: this is what an operator quotes back to a carrier
              // that asks why it is being sent less work.
              : '${(score.completionRate * 100).round()}% of ${score.orders} delivered'
                  '${score.timeToClaim == null ? '' : ' · claims in ${score.timeToClaim!.inMinutes}m'}'
                  '${score.timeOnRoad == null ? '' : ' · ${score.timeOnRoad!.inMinutes}m on the road'}',
          style: ConsoleText.body,
        ),
      ],
    );
  }

  Widget _payoutDetail(DeliveryProviderInfo p) {
    if (p.accountRef == null) {
      if (p.kind != ProviderKind.external) {
        return const Text('Not paid through this register.', style: ConsoleText.body);
      }
      // Worth saying plainly: a carrier with no payout account is one whose every delivery payment
      // will fail, and it will not show until an order is delivered.
      return const _CardNote(
        text: 'No payout account. Every delivery payment to this carrier will fail, and it will '
            'not show until an order has already been delivered.',
        accent: DeliveryAccent.critical,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ConsoleFactGrid(
          facts: <ConsoleFact>[
            ConsoleFact(
              'Account',
              '${p.accountRef} · ${p.payoutState.label.toLowerCase()}',
              mark: p.payoutState.needsAttention
                  ? const ConsoleFactMark.unverified()
                  : const ConsoleFactMark.verified(),
            ),
            if (p.contactName != null) ConsoleFact('Contact', p.contactName!),
            if (p.contactPhone != null) ConsoleFact('Phone', p.contactPhone!),
          ],
        ),
        if (p.payoutState.needsAttention) ...<Widget>[
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          // Deliberately not phrased as a bad account. It usually is not one — it is an account
          // set while the bank could not be reached, and saying otherwise would send an operator to
          // chase a carrier about a problem at our end.
          _CardNote(
            text: 'The bank has not confirmed this account'
                '${p.payoutDetail == null ? '' : ': ${p.payoutDetail}'}. '
                'Payments to this carrier may fail.',
            accent: DeliveryAccent.caution,
          ),
        ],
      ],
    );
  }

  /// The roster, as removable chips.
  Widget _riders(DeliveryProviderInfo p) {
    if (p.isInHouse) {
      return const Text('Every rider not assigned to another fleet', style: ConsoleText.body);
    }
    return FutureBuilder<List<String>>(
      future: _ridersOf(p.id),
      builder: (BuildContext context, AsyncSnapshot<List<String>> snapshot) {
        if (!snapshot.hasData) {
          return const Text('Loading riders…', style: ConsoleText.body);
        }
        final List<String> riders = snapshot.data!;
        if (riders.isEmpty) {
          return const Text('No riders yet — this carrier cannot take work until it has some',
              style: ConsoleText.body);
        }
        return Wrap(
          spacing: DeliverySpacing.sm,
          runSpacing: DeliverySpacing.sm,
          children: <Widget>[
            for (final String rider in riders)
              _RefChip(
                label: _shortRef(rider),
                tooltip: rider,
                icon: Icons.pedal_bike_outlined,
                onRemove: _busy
                    ? null
                    : () => _run(p.id, () => widget.api.releaseRider(rider),
                        'Rider returned to the in-house fleet'),
              ),
          ],
        );
      },
    );
  }

  /// Who can sign in and run this company.
  ///
  /// Separate from the rider roster because they are different jobs: a rider carries orders, a
  /// staff login pauses the company and reads its payout state. Until this existed a carrier could
  /// be fully onboarded and still have no way to see any of it.
  Widget _staff(DeliveryProviderInfo p) {
    return FutureBuilder<List<String>>(
      future: _staffOf(p.id),
      builder: (BuildContext context, AsyncSnapshot<List<String>> snapshot) {
        if (!snapshot.hasData) {
          return const Text('Loading logins…', style: ConsoleText.body);
        }
        final List<String> staff = snapshot.data!;
        if (staff.isEmpty) {
          return const _CardNote(
            // Worth saying plainly: this is the step everyone forgets, and its symptom from the
            // carrier's side is a portal that says they belong to no company.
            text: 'Nobody can sign in for this carrier yet. They cannot see their score, their '
                'riders, or take themselves out of rotation.',
            accent: DeliveryAccent.caution,
          );
        }
        return Wrap(
          spacing: DeliverySpacing.sm,
          runSpacing: DeliverySpacing.sm,
          children: <Widget>[
            for (final String user in staff)
              _RefChip(
                label: _shortRef(user),
                tooltip: user,
                icon: Icons.badge_outlined,
                onRemove: _busy
                    ? null
                    : () => _run(p.id, () => widget.api.removeStaff(user),
                        'That account can no longer administer ${p.name}'),
              ),
          ],
        );
      },
    );
  }

  static String _shortRef(String ref) =>
      ref.length <= 12 ? ref : '${ref.substring(0, 8)}…';

  static IconData _iconFor(ProviderKind kind) => switch (kind) {
        ProviderKind.platform => Icons.pedal_bike_rounded,
        ProviderKind.external => Icons.local_shipping_rounded,
        ProviderKind.merchant => Icons.storefront_rounded,
      };

  /// Colour by state, not by kind: an operator scanning this list is looking for what is stopped,
  /// and colouring by category would spend the signal on something they can already read.
  static DeliveryAccent _accentFor(DeliveryProviderInfo p) => switch (p.status) {
        ProviderStatus.active => DeliveryAccent.positive,
        ProviderStatus.paused => DeliveryAccent.caution,
        ProviderStatus.suspended => DeliveryAccent.critical,
      };

  /// The design's date spelling — "Jan 10, 2025".
  static String _date(DateTime at) {
    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[at.month - 1]} ${at.day.toString().padLeft(2, '0')}, ${at.year}';
  }
}

/// A tinted line inside a card or a drawer section, for the one sentence that changes what an
/// operator should do next.
class _CardNote extends StatelessWidget {
  const _CardNote({required this.text, required this.accent});

  final String text;
  final DeliveryAccent accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.sm + 2),
      decoration: BoxDecoration(
        color: accent.tint,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 14, color: accent.color),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: DeliveryColors.ink, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// A Keycloak subject as something a person can look at: shortened, with the whole of it on hover
/// and a cross to take it off.
class _RefChip extends StatelessWidget {
  const _RefChip({
    required this.label,
    required this.tooltip,
    required this.icon,
    this.onRemove,
  });

  final String label;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DeliverySpacing.sm + 2,
          vertical: DeliverySpacing.xs + 2,
        ),
        decoration: BoxDecoration(
          color: DeliveryColors.background,
          border: Border.all(color: DeliveryColors.border),
          borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: DeliveryColors.faint),
            const SizedBox(width: DeliverySpacing.sm - 2),
            Text(label,
                style: const TextStyle(fontSize: 12, color: DeliveryColors.ink)),
            if (onRemove != null) ...<Widget>[
              const SizedBox(width: DeliverySpacing.sm - 2),
              InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                child: const Icon(Icons.close, size: 14, color: DeliveryColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------- dialogs

class _NewProvider {
  const _NewProvider(this.slug, this.name, this.contactName, this.contactPhone, this.accountRef);

  final String slug;
  final String name;
  final String? contactName;
  final String? contactPhone;
  final String? accountRef;
}

/// The console's dialog frame: white, radius 16, a bold title and the design's buttons.
class _ConsoleDialog extends StatelessWidget {
  const _ConsoleDialog({
    required this.title,
    required this.child,
    required this.actions,
    this.width = 460,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: DeliveryColors.white,
      surfaceTintColor: DeliveryColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
      title: Text(title, style: ConsoleText.cardTitle),
      content: SizedBox(width: width, child: child),
      actions: actions,
    );
  }
}

/// The console's text input: a labelled box on the page background, with the design's radius.
class _ConsoleField extends StatelessWidget {
  const _ConsoleField({
    required this.label,
    required this.controller,
    this.helper,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String? helper;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: ConsoleText.fieldLabel),
          const SizedBox(height: DeliverySpacing.sm - 2),
          TextField(
            controller: controller,
            autofocus: autofocus,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            style: ConsoleText.cell,
            cursorColor: DeliveryColors.brand,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: DeliveryColors.background,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: DeliverySpacing.md - 2,
                vertical: DeliverySpacing.sm + 2,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                borderSide: const BorderSide(color: DeliveryColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                borderSide: const BorderSide(color: DeliveryColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                borderSide: const BorderSide(color: DeliveryColors.brand),
              ),
            ),
          ),
          if (helper != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs + 2),
            Text(helper!, style: ConsoleText.meta),
          ],
        ],
      ),
    );
  }
}

class _OnboardDialog extends StatefulWidget {
  const _OnboardDialog();

  @override
  State<_OnboardDialog> createState() => _OnboardDialogState();
}

class _OnboardDialogState extends State<_OnboardDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _slug = TextEditingController();
  final TextEditingController _contact = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _account = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _contact.dispose();
    _phone.dispose();
    _account.dispose();
    super.dispose();
  }

  /// Derives a handle from the name as it is typed, until somebody edits the handle themselves.
  bool _slugTouched = false;

  void _onNameChanged(String value) {
    if (_slugTouched) return;
    _slug.text = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  void _submit() {
    final String name = _name.text.trim();
    final String slug = _slug.text.trim();
    if (name.isEmpty || slug.isEmpty) {
      setState(() => _error = 'A carrier needs a name and a handle');
      return;
    }
    if (!RegExp(r'^[a-z0-9][a-z0-9-]*$').hasMatch(slug)) {
      setState(() => _error = 'A handle is lower-case letters, digits and hyphens');
      return;
    }
    Navigator.of(context).pop(_NewProvider(
      slug,
      name,
      _blank(_contact.text),
      _blank(_phone.text),
      _blank(_account.text),
    ));
  }

  static String? _blank(String v) => v.trim().isEmpty ? null : v.trim();

  @override
  Widget build(BuildContext context) {
    return _ConsoleDialog(
      title: 'Onboard a delivery company',
      actions: <Widget>[
        ConsoleButton(
          label: 'Cancel',
          tone: ConsoleButtonTone.outlined,
          onPressed: () => Navigator.of(context).pop(),
        ),
        ConsoleButton(
          label: 'Onboard',
          tone: ConsoleButtonTone.solid,
          onPressed: _submit,
        ),
      ],
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _ConsoleField(
              label: 'Name',
              controller: _name,
              autofocus: true,
              onChanged: _onNameChanged,
            ),
            _ConsoleField(
              label: 'Handle',
              controller: _slug,
              helper: 'Appears in config and URLs. Lower-case, no spaces.',
              onChanged: (_) => _slugTouched = true,
            ),
            _ConsoleField(
              label: 'Payout account',
              controller: _account,
              // The failure this avoids is silent and late: registration succeeds, the split
              // computes, and only the bank leg fails once an order is actually delivered.
              helper: 'Must already exist at the bank, or every payment to them fails',
            ),
            _ConsoleField(label: 'Contact (optional)', controller: _contact),
            _ConsoleField(label: 'Phone (optional)', controller: _phone),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(fontSize: 13, color: DeliveryAccent.critical.color)),
          ],
        ),
      ),
    );
  }
}

/// Asks for the account that should be able to administer a carrier.
class _AddStaffDialog extends StatefulWidget {
  const _AddStaffDialog();

  @override
  State<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<_AddStaffDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ConsoleDialog(
      title: 'Give someone access',
      width: 420,
      actions: <Widget>[
        ConsoleButton(
          label: 'Cancel',
          tone: ConsoleButtonTone.outlined,
          onPressed: () => Navigator.of(context).pop(),
        ),
        ConsoleButton(
          label: 'Give access',
          tone: ConsoleButtonTone.solid,
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'They will be able to see this carrier\'s score and riders, and take it out of '
            'rotation. They cannot see any other carrier.',
            style: TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.35),
          ),
          const SizedBox(height: DeliverySpacing.md),
          _ConsoleField(
            label: 'Account id',
            controller: _controller,
            autofocus: true,
            // The Keycloak subject, which is what every other reference in this system uses.
            helper: 'The user\'s Keycloak subject (sub)',
            onSubmitted: (String v) => Navigator.of(context).pop(v.trim()),
          ),
        ],
      ),
    );
  }
}

class _AddRiderDialog extends StatefulWidget {
  const _AddRiderDialog();

  @override
  State<_AddRiderDialog> createState() => _AddRiderDialogState();
}

class _AddRiderDialogState extends State<_AddRiderDialog> {
  final TextEditingController _ref = TextEditingController();

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ConsoleDialog(
      title: 'Move a rider to this fleet',
      width: 420,
      actions: <Widget>[
        ConsoleButton(
          label: 'Cancel',
          tone: ConsoleButtonTone.outlined,
          onPressed: () => Navigator.of(context).pop(),
        ),
        ConsoleButton(
          label: 'Move',
          tone: ConsoleButtonTone.solid,
          onPressed: () => Navigator.of(context).pop(_ref.text.trim()),
        ),
      ],
      child: _ConsoleField(
        label: 'Rider id',
        controller: _ref,
        autofocus: true,
        // A rider works for one fleet at a time, so this is a move rather than an addition.
        helper: 'Their Keycloak subject. They leave whichever fleet they are in now.',
      ),
    );
  }
}
