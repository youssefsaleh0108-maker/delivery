import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import '../shell/shell.dart';

/// What the company has been paid, and what the work in flight is worth.
///
/// The second question a delivery company opens an app to ask, and the one the platform was
/// previously answering only in its own books.
///
/// Earned and expected are kept apart deliberately. They are different promises: one is money owed
/// for work finished, the other is money that only exists if every rider currently out there
/// completes. Adding them into a single headline figure would flatter the number and mislead
/// somebody deciding whether they can afford another van.
///
/// Like the job board, this page has no frame of its own in the 2026-08 Figma set. It is built from
/// the console's KPI row so that the four figures land on the same grid, at the same sizes, as the
/// four on the dashboard — the point of a design system being that a number does not change
/// meaning when it changes page.
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

    return FutureBuilder<CarrierEarnings>(
      future: _earnings,
      builder: (BuildContext context, AsyncSnapshot<CarrierEarnings> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            color: DeliveryColors.background,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(color: DeliveryColors.brand),
          );
        }
        if (snapshot.hasError) {
          // Not attached to a company yet — a 404, and an expected state for a freshly created
          // carrier account rather than a failure worth showing a stack trace for.
          return Container(
            color: DeliveryColors.background,
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.all(DeliverySpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.help_outline, size: 40, color: DeliveryColors.faint),
                  const SizedBox(height: DeliverySpacing.md),
                  Text(t.noCompanyYet, style: ConsoleText.cardTitle),
                  const SizedBox(height: DeliverySpacing.xs),
                  Text(t.askThePlatformToAttachYou,
                      textAlign: TextAlign.center, style: ConsoleText.pageSubtitle),
                ],
              ),
            ),
          );
        }

        return _page(snapshot.data!, t);
      },
    );
  }

  Widget _page(CarrierEarnings e, DeliveryStrings t) {
    return ConsolePage(
      header: ConsoleTopbar(
        title: t.earningsTitle,
        subtitle: t.earningsWindowNote(e.windowDays, e.cutPercentage.toStringAsFixed(0)),
        actions: <Widget>[
          ConsoleIconAction(
            icon: Icons.refresh,
            tooltip: t.refresh,
            onPressed: _reload,
          ),
          const ConsoleIconAction(
            icon: Icons.notifications_none,
            tooltip: 'Notifications — coming soon',
          ),
        ],
      ),
      children: <Widget>[
        ConsoleKpiRow(
          cards: <Widget>[
            ConsoleKpiCard(
              label: t.earned,
              value: e.earned.toStringAsFixed(2),
              icon: Icons.payments_outlined,
              footnote: Text(
                'After the platform\'s ${e.cutPercentage.toStringAsFixed(0)}% cut',
                style: const TextStyle(fontSize: 13, color: DeliveryColors.faint),
              ),
            ),
            ConsoleKpiCard(
              label: t.expected,
              value: e.expected.toStringAsFixed(2),
              icon: Icons.schedule,
              // Not money yet, and the footnote is the whole reason this figure sits apart from
              // the one beside it rather than being added to it.
              footnote: Text(
                t.expectedNote,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: DeliveryColors.faint),
              ),
            ),
            ConsoleKpiCard(
              label: t.jobsDelivered,
              value: '${e.delivered}',
              icon: Icons.check_circle_outline,
            ),
            ConsoleKpiCard(
              label: t.jobsInFlight,
              value: '${e.active}',
              icon: Icons.local_shipping_outlined,
            ),
          ],
        ),

        // Only when there is something to say. A zero here would be a line about a benefit the
        // company never received, which reads as a benefit being withheld.
        if (e.savedByOffers > 0)
          ConsoleCard(
            title: t.savedByOffers,
            trailing: Text(
              e.savedByOffers.toStringAsFixed(2),
              style: ConsoleText.kpiValue.copyWith(fontSize: 24, color: DeliveryColors.brand),
            ),
            child: Text(
              t.savedByOffersNote,
              style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.4),
            ),
          ),
      ],
    );
  }
}
