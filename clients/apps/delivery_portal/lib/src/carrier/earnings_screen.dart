import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// What the company has been paid, and what the work in flight is worth.
///
/// The second question a delivery company opens an app to ask, and the one the platform was
/// previously answering only in its own books.
///
/// Earned and expected are kept apart deliberately. They are different promises: one is money owed
/// for work finished, the other is money that only exists if every rider currently out there
/// completes. Adding them into a single headline figure would flatter the number and mislead
/// somebody deciding whether they can afford another van.
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key, required this.api});

  final OrderApi api;

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  late Future<CarrierEarnings> _earnings = widget.api.carrierEarnings();

  void _reload() => setState(() => _earnings = widget.api.carrierEarnings());

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.earningsTitle),
        actions: <Widget>[
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh), tooltip: t.refresh),
        ],
      ),
      body: FutureBuilder<CarrierEarnings>(
        future: _earnings,
        builder: (BuildContext context, AsyncSnapshot<CarrierEarnings> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
          }
          if (snapshot.hasError) {
            // Not attached to a company yet — a 404, and an expected state for a freshly created
            // carrier account rather than a failure worth showing a stack trace for.
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(DeliverySpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.help_outline, size: 40, color: DeliveryColors.muted),
                    const SizedBox(height: DeliverySpacing.md),
                    Text(t.noCompanyYet, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: DeliverySpacing.xs),
                    Text(t.askThePlatformToAttachYou,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            );
          }
          final CarrierEarnings e = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.all(DeliverySpacing.lg),
            children: <Widget>[
              SoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    StatRow(
                      tiles: <Widget>[
                        StatTile(
                          label: t.earned,
                          value: e.earned.toStringAsFixed(2),
                          icon: Icons.payments_outlined,
                          accent: DeliveryAccent.positive,
                        ),
                        StatTile(
                          label: t.expected,
                          value: e.expected.toStringAsFixed(2),
                          icon: Icons.schedule,
                          // Info, not positive: this is not money yet.
                          accent: DeliveryAccent.info,
                          footnote: t.expectedNote,
                        ),
                        StatTile(
                          label: t.jobsDelivered,
                          value: '${e.delivered}',
                          icon: Icons.check_circle_outline,
                          accent: DeliveryAccent.positive,
                        ),
                        StatTile(
                          label: t.jobsInFlight,
                          value: '${e.active}',
                          icon: Icons.local_shipping_outlined,
                          accent: DeliveryAccent.neutral,
                        ),
                      ],
                    ),
                    const SizedBox(height: DeliverySpacing.sm),
                    Text(
                      t.earningsWindowNote(e.windowDays, e.cutPercentage.toStringAsFixed(0)),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),

              // Only when there is something to say. A zero here would be a line about a benefit
              // the company never received, which reads as a benefit being withheld.
              if (e.savedByOffers > 0) ...<Widget>[
                const SizedBox(height: DeliverySpacing.lg),
                SoftCard(
                  accent: DeliveryColors.brand,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Icon(Icons.redeem_rounded,
                              size: 18, color: DeliveryColors.brand),
                          const SizedBox(width: DeliverySpacing.xs),
                          Text(t.savedByOffers,
                              style: Theme.of(context).textTheme.titleSmall),
                          const Spacer(),
                          Text(e.savedByOffers.toStringAsFixed(2),
                              style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: DeliverySpacing.xs),
                      Text(t.savedByOffersNote,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
