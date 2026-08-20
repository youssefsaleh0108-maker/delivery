import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// Fees the platform absorbs to grow the marketplace.
///
/// The budget sits above the offers and above the button that creates one, and that ordering is the
/// point of the screen. Every offer here costs the platform exactly what somebody else stops paying,
/// so an operator about to promise free delivery across the city should see what the last thirty
/// days cost before committing to the next thirty.
///
/// English only, like the rest of the Backoffice. The string table is for the customer app and the
/// merchant portal, whose users are not necessarily the people running the platform.
class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key, required this.api});

  final OfferApi api;

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  late Future<_Data> _data = _load();
  bool _busy = false;

  Future<_Data> _load() async {
    final List<Object> results = await Future.wait<Object>(<Future<Object>>[
      widget.api.budget(),
      widget.api.all(),
    ]);
    return _Data(results[0] as OfferBudget, results[1] as List<FeeWaiverOffer>);
  }

  void _reload() => setState(() => _data = _load());

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_reason(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The server's own words. "An offer cannot end before it starts" is actionable; a Dio exception
  /// is not.
  String _reason(Object error) {
    if (error is DioException) {
      final Object? data = error.response?.data;
      if (data is Map && data['message'] is String) return data['message'] as String;
      if (data is Map && data['detail'] is String) return data['detail'] as String;
    }
    return 'That did not work: $error';
  }

  Future<void> _create() async {
    final _NewOffer? made = await showDialog<_NewOffer>(
      context: context,
      builder: (BuildContext context) => const _NewOfferDialog(),
    );
    if (made == null || !mounted) return;

    await _run(() => widget.api
        .create(
          audience: made.audience,
          title: made.title,
          subtitle: made.subtitle,
          minSubtotal: made.minSubtotal,
          endsAt: made.endsAt,
        )
        .then((_) {}));
  }

  Future<void> _withdraw(FeeWaiverOffer offer) async {
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Withdraw this offer?'),
        // Said plainly: an operator withdrawing an offer needs to know it is not retroactive.
        content: const Text('It stops applying to new orders. Orders already placed keep what '
            'they were promised.'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true), child: const Text('Withdraw')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    await _run(() => widget.api.withdraw(offer.id).then((_) {}));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Data>(
      future: _data,
      builder: (BuildContext context, AsyncSnapshot<_Data> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
        }
        if (snapshot.hasError) {
          return Center(child: Text('That did not work: ${snapshot.error}'));
        }
        final _Data data = snapshot.data!;

        return ListView(
          padding: const EdgeInsets.all(DeliverySpacing.lg),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Fee waivers', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: DeliverySpacing.xs),
                      Text(
                        'Fees the platform absorbs to grow the marketplace. Every one of these '
                        'costs you exactly what somebody else stops paying.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: DeliverySpacing.md),
                FilledButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: const Icon(Icons.add),
                  label: const Text('New offer'),
                ),
              ],
            ),
            const SizedBox(height: DeliverySpacing.lg),

            _Budget(budget: data.budget),
            const SizedBox(height: DeliverySpacing.lg),

            const SectionLabel('Offers'),
            if (data.offers.isEmpty)
              SoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('No offers yet', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: DeliverySpacing.xs),
                    Text(
                      'Create one to start waiving fees for customers, merchants or delivery '
                      'companies.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              )
            else
              ...data.offers.map((FeeWaiverOffer offer) => Padding(
                    padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
                    child: _OfferCard(
                      offer: offer,
                      busy: _busy,
                      onWithdraw: () => _withdraw(offer),
                    ),
                  )),
          ],
        );
      },
    );
  }
}

class _Data {
  const _Data(this.budget, this.offers);

  final OfferBudget budget;
  final List<FeeWaiverOffer> offers;
}

// ---------------------------------------------------------------------------- the money

class _Budget extends StatelessWidget {
  const _Budget({required this.budget});

  final OfferBudget budget;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Offer budget', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: DeliverySpacing.sm),
          StatRow(
            tiles: <Widget>[
              StatTile(
                label: 'Revenue earned',
                value: budget.earned.toStringAsFixed(2),
                icon: Icons.trending_up,
                accent: DeliveryAccent.positive,
              ),
              StatTile(
                label: 'Given away',
                value: budget.given.toStringAsFixed(2),
                icon: Icons.redeem_outlined,
                accent: DeliveryAccent.info,
              ),
              StatTile(
                label: 'Left to give',
                value: budget.remaining.toStringAsFixed(2),
                icon: Icons.savings_outlined,
                accent: budget.exhausted ? DeliveryAccent.caution : DeliveryAccent.neutral,
              ),
              StatTile(
                label: 'Kept',
                value: budget.kept.toStringAsFixed(2),
                icon: Icons.account_balance_outlined,
                // The number that pays the bills, and it can go negative. Shown as critical when it
                // does, because a platform paying to run itself needs to notice.
                accent: budget.kept < 0 ? DeliveryAccent.critical : DeliveryAccent.positive,
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.sm),
          UsageBar(
            label: 'Budget used',
            used: budget.given,
            total: budget.budget,
            // Caution rather than positive: a full bar here means the whole giveaway allowance has
            // gone, which is not a goal being met.
            accent: budget.exhausted ? DeliveryAccent.caution : DeliveryAccent.info,
          ),
          const SizedBox(height: DeliverySpacing.xs),
          Text(
            'Over the last ${budget.windowDays} days. At most '
            '${budget.capPercentage.toStringAsFixed(0)}% of revenue may be given away'
            '${budget.allowance > 0 ? ', plus a standing allowance of '
                '${budget.allowance.toStringAsFixed(2)}' : ''}; waivers stop when that is reached.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (budget.given > 0) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            // Broken out because the three cost different amounts and an operator deciding what to
            // withdraw needs to know which one is doing the spending.
            Text(
              'Customers ${budget.givenCustomer.toStringAsFixed(2)}   ·   '
              'Merchants ${budget.givenMerchant.toStringAsFixed(2)}   ·   '
              'Delivery companies ${budget.givenCarrier.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
          if (budget.exhausted) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            // Not a warning about something that might happen — a statement that waivers have
            // already stopped. An operator whose promotion quietly stopped working should find out
            // here rather than from a merchant.
            const SoftNote(
              text: 'The budget is spent. No further waivers will be granted until revenue '
                  'catches up.',
              accent: DeliveryAccent.caution,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------- one offer

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, required this.busy, required this.onWithdraw});

  final FeeWaiverOffer offer;
  final bool busy;
  final VoidCallback onWithdraw;

  static String audienceLabel(OfferAudience audience) => switch (audience) {
        OfferAudience.customer => 'Customers',
        OfferAudience.merchant => 'Merchants',
        OfferAudience.carrier => 'Delivery companies',
      };

  /// What the offer actually does, spelled out on every card.
  ///
  /// "Free delivery" and "no commission" are not interchangeable and cost the platform different
  /// amounts, so the effect is stated rather than left to whatever title an operator typed.
  static String effectLabel(OfferAudience audience) => switch (audience) {
        OfferAudience.customer =>
          'Free delivery — the customer is not charged the delivery fee, and the carrier is still '
              'paid in full.',
        OfferAudience.merchant =>
          'No commission — the merchant keeps the whole goods amount.',
        OfferAudience.carrier =>
          'No platform cut — the delivery company keeps the whole delivery fee.',
      };

  (String, DeliveryAccent) _state() {
    if (!offer.active) return ('Withdrawn', DeliveryAccent.neutral);
    if (offer.live) return ('Live', DeliveryAccent.positive);
    if (offer.startsAt.isAfter(DateTime.now())) return ('Scheduled', DeliveryAccent.info);
    return ('Ended', DeliveryAccent.neutral);
  }

  @override
  Widget build(BuildContext context) {
    final (String label, DeliveryAccent accent) = _state();
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(offer.title, style: Theme.of(context).textTheme.titleSmall),
                    Text(audienceLabel(offer.audience),
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              StatePill(label: label, accent: accent),
              if (offer.active) ...<Widget>[
                const SizedBox(width: DeliverySpacing.sm),
                TextButton(
                    onPressed: busy ? null : onWithdraw, child: const Text('Withdraw')),
              ],
            ],
          ),
          const SizedBox(height: DeliverySpacing.xs),
          Text(effectLabel(offer.audience), style: Theme.of(context).textTheme.bodySmall),
          if (offer.subtitle != null && offer.subtitle!.isNotEmpty)
            Text(offer.subtitle!, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: DeliverySpacing.xs),
          Text(
            'Minimum basket ${offer.minSubtotal.toStringAsFixed(2)}   ·   '
            'Runs until ${offer.endsAt == null ? 'withdrawn' : formatDate(offer.endsAt!)}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  static String formatDate(DateTime when) =>
      '${when.year}-${when.month.toString().padLeft(2, '0')}-'
      '${when.day.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------- creating one

class _NewOffer {
  const _NewOffer({
    required this.audience,
    required this.title,
    required this.minSubtotal,
    this.subtitle,
    this.endsAt,
  });

  final OfferAudience audience;
  final String title;
  final String? subtitle;
  final double minSubtotal;
  final DateTime? endsAt;
}

class _NewOfferDialog extends StatefulWidget {
  const _NewOfferDialog();

  @override
  State<_NewOfferDialog> createState() => _NewOfferDialogState();
}

class _NewOfferDialogState extends State<_NewOfferDialog> {
  OfferAudience _audience = OfferAudience.customer;
  final TextEditingController _title = TextEditingController();
  final TextEditingController _subtitle = TextEditingController();
  final TextEditingController _minimum = TextEditingController(text: '0');
  DateTime? _endsAt;

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _minimum.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New offer'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SectionLabel('Who stops paying'),
              // A segmented control rather than a dropdown: there are exactly three, they are not
              // interchangeable, and the effect of the chosen one is spelled out underneath.
              SegmentedButton<OfferAudience>(
                segments: const <ButtonSegment<OfferAudience>>[
                  ButtonSegment<OfferAudience>(
                      value: OfferAudience.customer, label: Text('Customers')),
                  ButtonSegment<OfferAudience>(
                      value: OfferAudience.merchant, label: Text('Merchants')),
                  ButtonSegment<OfferAudience>(
                      value: OfferAudience.carrier, label: Text('Delivery')),
                ],
                selected: <OfferAudience>{_audience},
                onSelectionChanged: (Set<OfferAudience> picked) =>
                    setState(() => _audience = picked.first),
              ),
              const SizedBox(height: DeliverySpacing.sm),
              SoftNote(text: _OfferCard.effectLabel(_audience)),
              const SizedBox(height: DeliverySpacing.md),
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
                // Rebuilds so the save button enables the moment there is something to save.
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: DeliverySpacing.sm),
              TextField(
                controller: _subtitle,
                decoration: const InputDecoration(labelText: 'Subtitle'),
              ),
              const SizedBox(height: DeliverySpacing.sm),
              TextField(
                controller: _minimum,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Minimum basket'),
              ),
              const SizedBox(height: DeliverySpacing.sm),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text('Runs until '
                        '${_endsAt == null ? 'withdrawn' : _OfferCard.formatDate(_endsAt!)}'),
                  ),
                  TextButton(
                    onPressed: () async {
                      final DateTime now = DateTime.now();
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        firstDate: now,
                        lastDate: now.add(const Duration(days: 365)),
                        initialDate: now.add(const Duration(days: 30)),
                      );
                      if (picked != null) setState(() => _endsAt = picked);
                    },
                    child: const Text('Pick an end date'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          // Disabled without a title: an untitled offer is one nobody can identify later when they
          // are trying to work out where the money went.
          onPressed: _title.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_NewOffer(
                    audience: _audience,
                    title: _title.text.trim(),
                    subtitle: _subtitle.text.trim().isEmpty ? null : _subtitle.text.trim(),
                    minSubtotal: double.tryParse(_minimum.text.trim()) ?? 0,
                    endsAt: _endsAt,
                  )),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
