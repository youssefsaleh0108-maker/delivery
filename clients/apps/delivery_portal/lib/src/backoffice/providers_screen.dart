import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// Who carries orders: the platform's own fleet, the delivery companies, and merchants' drivers.
///
/// This is the operating surface for the delivery marketplace. Onboard a company, staff it, and
/// stop it when it stops performing — all of which existed only over the API until now.
class ProvidersScreen extends StatefulWidget {
  const ProvidersScreen({super.key, required this.api});

  final DeliveryProviderApi api;

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
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _onboard,
        backgroundColor: DeliveryColors.brand,
        foregroundColor: DeliveryColors.white,
        icon: const Icon(Icons.local_shipping_outlined),
        label: const Text('Onboard a company'),
      ),
      body: FutureBuilder<Paged<DeliveryProviderInfo>>(
        future: _page,
        builder: (BuildContext context, AsyncSnapshot<Paged<DeliveryProviderInfo>> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Could not load providers: ${snapshot.error}'));
          }

          final List<DeliveryProviderInfo> providers = snapshot.data!.content;
          // Nested rather than combined into one future: the register renders as soon as it
          // arrives, and the scores fill in behind it. An operator opening this page to suspend a
          // carrier should not wait on a ranking they did not ask for.
          // The platform's own fleet first — it is the default carrier and the one an operator
          // checks against — then companies, then merchants' own drivers.
          final List<DeliveryProviderInfo> sorted = <DeliveryProviderInfo>[
            ...providers.where((DeliveryProviderInfo p) => p.kind == ProviderKind.platform),
            ...providers.where((DeliveryProviderInfo p) => p.kind == ProviderKind.external),
            ...providers.where((DeliveryProviderInfo p) => p.kind == ProviderKind.merchant),
          ];

          final int taking = providers.where((DeliveryProviderInfo p) => p.canTakeWork).length;
          final int companies =
              providers.where((DeliveryProviderInfo p) => p.kind == ProviderKind.external).length;
          final int fleets =
              providers.where((DeliveryProviderInfo p) => p.kind == ProviderKind.merchant).length;
          final int stopped = providers
              .where((DeliveryProviderInfo p) => p.status == ProviderStatus.suspended)
              .length;
          final int unchecked = providers
              .where((DeliveryProviderInfo p) => p.payoutState.needsAttention)
              .length;

          return ListView(
            padding: const EdgeInsets.all(DeliverySpacing.lg),
            children: <Widget>[
              Text('Delivery providers', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: DeliverySpacing.xs),
              Text(
                'A merchant picks one of these to carry their orders; the in-house fleet is what '
                'everybody gets by default.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: DeliverySpacing.md),

              // The shape of the network before any of the detail: how much capacity is live,
              // where it comes from, and what has been stopped.
              StatRow(tiles: <Widget>[
                StatTile(
                  value: '$taking',
                  label: 'Taking work',
                  icon: Icons.check_circle_outline_rounded,
                  accent: DeliveryAccent.positive,
                  footnote: '${providers.length} total',
                ),
                StatTile(
                  value: '$companies',
                  label: 'Companies',
                  icon: Icons.local_shipping_outlined,
                  accent: DeliveryAccent.info,
                ),
                StatTile(
                  value: '$fleets',
                  label: 'Own fleets',
                  icon: Icons.storefront_outlined,
                  accent: DeliveryAccent.neutral,
                ),
                StatTile(
                  value: '$stopped',
                  label: 'Suspended',
                  icon: Icons.block_rounded,
                  accent: stopped == 0 ? DeliveryAccent.positive : DeliveryAccent.critical,
                ),
                // Carriers the platform believes it can pay and has never checked. Counted here
                // because the alternative is reading every card to find them, and an unpayable
                // carrier is silent until an order has already been delivered.
                StatTile(
                  value: '$unchecked',
                  label: 'Unchecked payout',
                  icon: Icons.account_balance_outlined,
                  accent: unchecked == 0 ? DeliveryAccent.positive : DeliveryAccent.caution,
                  footnote: unchecked == 0 ? 'all confirmed' : 'ask the bank',
                ),
              ]),
              const SizedBox(height: DeliverySpacing.lg),

              const SectionLabel('Carriers'),
              FutureBuilder<Map<String, CarrierScore>>(
                future: _scores,
                builder: (BuildContext context,
                    AsyncSnapshot<Map<String, CarrierScore>> scores) {
                  final Map<String, CarrierScore> byId =
                      scores.data ?? const <String, CarrierScore>{};
                  return Column(
                    children: <Widget>[
                      for (final DeliveryProviderInfo p in sorted) _card(p, byId[p.id]),
                    ],
                  );
                },
              ),
              const SizedBox(height: DeliverySpacing.xl * 2),
            ],
          );
        },
      ),
    );
  }

  bool get _busy => _busyId != null;

  Widget _card(DeliveryProviderInfo p, CarrierScore? score) {
    final bool busy = _busyId == p.id;

    final DeliveryAccent accent = _accentFor(p);

    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
      child: SoftCard(
        accent: accent.color,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accent.tint,
                    borderRadius: BorderRadius.circular(DeliveryRadius.md),
                  ),
                  child: Icon(_iconFor(p.kind), size: 20, color: accent.color),
                ),
                const SizedBox(width: DeliverySpacing.sm + 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(p.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      Text('${p.kind.label}  ·  ${p.slug}',
                          style: const TextStyle(
                              fontSize: 12.5, color: DeliveryColors.muted)),
                    ],
                  ),
                ),
                if (score != null) ...<Widget>[
                  _ScorePill(score: score),
                  const SizedBox(width: DeliverySpacing.xs),
                ],
                StatePill(label: p.status.label, accent: accent),
              ],
            ),
            if (score != null && score.orders > 0) ...<Widget>[
              const SizedBox(height: DeliverySpacing.xs),
              // The parts, not just the verdict: this is what an operator quotes back to a carrier
              // that asks why it is being sent less work.
              Text(
                '${(score.completionRate * 100).round()}% of ${score.orders} delivered'
                '${score.timeToClaim == null ? '' : ' · claims in ${score.timeToClaim!.inMinutes}m'}'
                '${score.timeOnRoad == null ? '' : ' · ${score.timeOnRoad!.inMinutes}m on the road'}',
                style: const TextStyle(fontSize: 12, color: DeliveryColors.muted),
              ),
            ],
            if (p.accountRef != null) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              Row(
                children: <Widget>[
                  Icon(
                    p.payoutState == PayoutState.verified
                        ? Icons.verified_outlined
                        : Icons.help_outline,
                    size: 15,
                    color: p.payoutState.needsAttention
                        ? DeliveryAccent.caution.color
                        : DeliveryAccent.positive.color,
                  ),
                  const SizedBox(width: DeliverySpacing.xs),
                  Expanded(
                    child: Text(
                      'Paid to ${p.accountRef} · ${p.payoutState.label.toLowerCase()}',
                      style: const TextStyle(fontSize: 12.5, color: DeliveryColors.muted),
                    ),
                  ),
                ],
              ),
              if (p.payoutState.needsAttention) ...<Widget>[
                const SizedBox(height: DeliverySpacing.xs),
                // Deliberately not phrased as a bad account. It usually is not one — it is an
                // account set while the bank could not be reached, and saying otherwise would send
                // an operator to chase a carrier about a problem at our end.
                SoftNote(
                  text: 'The bank has not confirmed this account'
                      '${p.payoutDetail == null ? '' : ': ${p.payoutDetail}'}. '
                      'Payments to this carrier may fail.',
                  accent: DeliveryAccent.caution,
                  icon: Icons.help_outline,
                ),
              ],
            ] else if (p.kind == ProviderKind.external) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              // Worth saying plainly: a carrier with no payout account is one whose every
              // delivery payment will fail, and it will not show until an order is delivered.
              const SoftNote(
                text: 'No payout account. Every delivery payment to this carrier will fail, and '
                    'it will not show until an order has already been delivered.',
                accent: DeliveryAccent.critical,
                icon: Icons.warning_amber_rounded,
              ),
            ],
            const SizedBox(height: DeliverySpacing.sm),
            _riders(p),
            // Only companies have logins. A merchant's own fleet is administered by the merchant in
            // their own portal, and the in-house fleet from this page.
            if (p.kind == ProviderKind.external) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              _staff(p),
            ],
            const SizedBox(height: DeliverySpacing.xs),
            Wrap(
              spacing: DeliverySpacing.xs,
              children: <Widget>[
                if (p.accountRef != null)
                  TextButton.icon(
                    onPressed: busy ? null : () => _verifyPayout(p),
                    icon: const Icon(Icons.account_balance_outlined, size: 18),
                    label: Text(p.payoutState.needsAttention
                        ? 'Check with the bank'
                        : 'Re-check account'),
                  ),
                if (p.kind == ProviderKind.external)
                  TextButton.icon(
                    onPressed: busy ? null : () => _addStaff(p),
                    icon: const Icon(Icons.badge_outlined, size: 18),
                    label: const Text('Give someone access'),
                  ),
                if (!p.isInHouse)
                  TextButton.icon(
                    onPressed: busy ? null : () => _addRider(p),
                    icon: const Icon(Icons.person_add_outlined, size: 18),
                    label: const Text('Add a rider'),
                  ),
                // Suspension is the platform's, and reinstatement is too — a suspended provider
                // cannot resume itself, which is the whole difference from pausing.
                if (p.status == ProviderStatus.suspended)
                  TextButton.icon(
                    onPressed: busy
                        ? null
                        : () => _run(p.id, () => widget.api.reinstate(p.id).then((_) {}),
                            '${p.name} reinstated'),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Reinstate'),
                  )
                else if (!p.isInHouse)
                  TextButton.icon(
                    onPressed: busy
                        ? null
                        : () => _run(p.id, () => widget.api.suspend(p.id).then((_) {}),
                            '${p.name} suspended'),
                    icon: const Icon(Icons.block, size: 18),
                    label: const Text('Suspend'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The roster, loaded per card.
  ///
  /// A separate request each rather than one joined list: rosters are small, an operator opens
  /// this page to look at one carrier, and the joined endpoint does not exist.
  Widget _riders(DeliveryProviderInfo p) {
    if (p.isInHouse) {
      // Membership is opt-in, so the in-house roster is empty by definition — every rider who has
      // not been moved elsewhere belongs to it. Saying that beats showing "0 riders".
      return const Text('Every rider not assigned to another fleet',
          style: TextStyle(fontSize: 12.5, color: DeliveryColors.muted));
    }
    return FutureBuilder<List<String>>(
      future: _ridersOf(p.id),
      builder: (BuildContext context, AsyncSnapshot<List<String>> snapshot) {
        if (!snapshot.hasData) {
          return const Text('Loading riders…',
              style: TextStyle(fontSize: 12.5, color: DeliveryColors.muted));
        }
        final List<String> riders = snapshot.data!;
        if (riders.isEmpty) {
          return const Text('No riders yet — this carrier cannot take work until it has some',
              style: TextStyle(fontSize: 12.5, color: DeliveryColors.muted));
        }
        return Wrap(
          spacing: DeliverySpacing.xs,
          runSpacing: DeliverySpacing.xs,
          children: <Widget>[
            for (final String rider in riders)
              Chip(
                label: Text(rider.length > 12 ? '${rider.substring(0, 8)}…' : rider,
                    style: const TextStyle(fontSize: 11.5)),
                visualDensity: VisualDensity.compact,
                onDeleted: _busy ? null : () => _run(p.id,
                    () => widget.api.releaseRider(rider), 'Rider returned to the in-house fleet'),
                deleteIcon: const Icon(Icons.close, size: 15),
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
          return const Text('Loading logins…',
              style: TextStyle(fontSize: 12.5, color: DeliveryColors.muted));
        }
        final List<String> staff = snapshot.data!;
        if (staff.isEmpty) {
          return const SoftNote(
            // Worth saying plainly: this is the step everyone forgets, and its symptom from the
            // carrier's side is a portal that says they belong to no company.
            text: 'Nobody can sign in for this carrier yet. They cannot see their score, their '
                'riders, or take themselves out of rotation.',
            accent: DeliveryAccent.caution,
            icon: Icons.badge_outlined,
          );
        }
        return Wrap(
          spacing: DeliverySpacing.xs,
          runSpacing: DeliverySpacing.xs,
          children: <Widget>[
            for (final String user in staff)
              Chip(
                avatar: const Icon(Icons.badge_outlined, size: 14),
                label: Text(user.length > 12 ? '${user.substring(0, 8)}…' : user,
                    style: const TextStyle(fontSize: 11.5)),
                visualDensity: VisualDensity.compact,
                onDeleted: _busy
                    ? null
                    : () => _run(p.id, () => widget.api.removeStaff(user),
                        'That account can no longer administer ${p.name}'),
                deleteIcon: const Icon(Icons.close, size: 15),
              ),
          ],
        );
      },
    );
  }

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
    return AlertDialog(
      title: const Text('Onboard a delivery company'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: _name,
                autofocus: true,
                onChanged: _onNameChanged,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: _slug,
                onChanged: (_) => _slugTouched = true,
                decoration: const InputDecoration(
                  labelText: 'Handle',
                  helperText: 'Appears in config and URLs. Lower-case, no spaces.',
                ),
              ),
              const SizedBox(height: DeliverySpacing.sm),
              TextField(
                controller: _account,
                decoration: const InputDecoration(
                  labelText: 'Payout account',
                  // The failure this avoids is silent and late: registration succeeds, the split
                  // computes, and only the bank leg fails once an order is actually delivered.
                  helperText: 'Must already exist at the bank, or every payment to them fails',
                ),
              ),
              const SizedBox(height: DeliverySpacing.sm),
              TextField(
                controller: _contact,
                decoration: const InputDecoration(labelText: 'Contact (optional)'),
              ),
              TextField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Phone (optional)'),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: DeliverySpacing.sm),
                Text(_error!, style: const TextStyle(color: DeliveryColors.brand)),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(onPressed: _submit, child: const Text('Onboard')),
      ],
    );
  }
}

/// The Delivery Score, as a pill beside the status.
///
/// Coloured by band rather than by a gradient: an operator is deciding whether to look closer, and
/// three answers — fine, watch, act — is what that decision needs.
class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.score});

  final CarrierScore score;

  @override
  Widget build(BuildContext context) {
    // A provisional score is an assumption, not a measurement, and colouring it green would dress
    // up "we have no idea yet" as "this carrier is good".
    final DeliveryAccent accent = score.provisional
        ? DeliveryAccent.neutral
        : (score.score >= 80
            ? DeliveryAccent.positive
            : (score.score >= 60 ? DeliveryAccent.caution : DeliveryAccent.critical));

    return Tooltip(
      message: score.provisional
          ? 'Provisional — only ${score.orders} orders so far, so this is mostly an assumption'
          : 'Based on ${score.orders} orders in the last 30 days',
      child: StatePill(
        label: score.provisional ? '${score.score}?' : '${score.score}',
        accent: accent,
        showDot: false,
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
    return AlertDialog(
      title: const Text('Give someone access'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'They will be able to see this carrier\'s score and riders, and take it out of '
            'rotation. They cannot see any other carrier.',
            style: TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.35),
          ),
          const SizedBox(height: DeliverySpacing.md),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Account id',
              // The Keycloak subject, which is what every other reference in this system uses.
              helperText: 'The user\'s Keycloak subject (sub)',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            onSubmitted: (String v) => Navigator.of(context).pop(v.trim()),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          style: FilledButton.styleFrom(backgroundColor: DeliveryColors.brand),
          child: const Text('Give access'),
        ),
      ],
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
    return AlertDialog(
      title: const Text('Move a rider to this fleet'),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _ref,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Rider id',
            // A rider works for one fleet at a time, so this is a move rather than an addition.
            helperText: 'Their Keycloak subject. They leave whichever fleet they are in now.',
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_ref.text.trim()),
          child: const Text('Move'),
        ),
      ],
    );
  }
}
