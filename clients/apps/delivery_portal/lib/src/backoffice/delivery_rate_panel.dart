import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

import '../shell/shell.dart';

/// Delivery rates per provider, shown on the connector card that can change them (Phase 6).
///
/// Deliberately on the Settings screen rather than on a monitoring page of its own. The person
/// ramping a vendor makes the change here, and the consequence of the last change is the single
/// most useful thing to put in front of them before they make the next one. A dashboard they have
/// to remember to open separately is a dashboard nobody checks at the moment it matters.
///
/// Only shown for connectors that have a real choice of provider. SMTP-only email has nothing to
/// compare against, and a success rate with one row is a number without a question attached.
///
/// Restyled for the 2026-08 redesign into the console's language — the window switch is the
/// design's segmented trough, the type is the console ramp, and the three states below now read
/// from [DeliveryAccent] rather than from the two hard-coded greens this file used to carry. The
/// numbers, the windows and the wording are unchanged.
class DeliveryRatePanel extends StatefulWidget {
  const DeliveryRatePanel({
    super.key,
    required this.channel,
    required this.api,
  });

  /// SMS, EMAIL or PUSH — matches `notification_log.channel`.
  final String channel;
  final DeliveryRateApi api;

  @override
  State<DeliveryRatePanel> createState() => _DeliveryRatePanelState();
}

class _DeliveryRatePanelState extends State<DeliveryRatePanel> {
  /// The windows the panel offers, and the labels the trough shows for them.
  static const List<int> _windows = <int>[1, 24, 168];
  static const List<String> _windowLabels = <String>['1h', '24h', '7d'];

  int _windowHours = 24;
  late Future<List<ProviderDeliveryRate>> _rates = _load();

  Future<List<ProviderDeliveryRate>> _load() =>
      widget.api.forChannel(widget.channel, windowHours: _windowHours);

  void _setWindow(int hours) {
    // Block body, not an arrow — see the note in settings_screen.dart.
    setState(() {
      _windowHours = hours;
      _rates = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ProviderDeliveryRate>>(
      future: _rates,
      builder: (BuildContext context, AsyncSnapshot<List<ProviderDeliveryRate>> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: DeliverySpacing.sm),
            child: LinearProgressIndicator(
              color: DeliveryColors.brand,
              backgroundColor: DeliveryColors.border,
            ),
          );
        }
        if (snapshot.hasError) {
          return Text(
            'Delivery rates unavailable: ${snapshot.error}',
            style: ConsoleText.cellMuted,
          );
        }

        final List<ProviderDeliveryRate> rates = snapshot.data!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                // Was "Delivery rate" when only acceptance could be measured, which overstated what
                // the number meant. Now both are shown, so the heading names both.
                const Expanded(
                  child: Text('Accepted / delivered', style: ConsoleText.kpiLabel),
                ),
                ConsoleFilterTabs(
                  tabs: <ConsoleFilterTab>[
                    for (final String label in _windowLabels) ConsoleFilterTab(label: label),
                  ],
                  selectedIndex: _windows.indexOf(_windowHours),
                  onSelected: (int i) => _setWindow(_windows[i]),
                ),
              ],
            ),
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            if (rates.isEmpty)
              Text(
                'Nothing sent on this channel in the last '
                '${_windowHours == 168 ? "7 days" : "$_windowHours hours"}.',
                style: ConsoleText.cellMuted,
              )
            else
              for (final ProviderDeliveryRate rate in rates) _RateRow(rate: rate),
          ],
        );
      },
    );
  }
}

class _RateRow extends StatelessWidget {
  const _RateRow({required this.rate});

  final ProviderDeliveryRate rate;

  @override
  Widget build(BuildContext context) {
    // Three states, not two. "No completed sends yet" is not a failure and must not be coloured
    // like one — during the first minutes of a ramp it is the expected state.
    final Color colour = !rate.hasData
        ? DeliveryColors.faint
        : rate.isHealthy
            ? DeliveryAccent.positive.color
            : DeliveryAccent.critical.color;

    // Delivery is its own three-state axis. "Not measured" is the common case — most SMS traffic
    // produces no carrier receipt at all — and it must not be coloured, or read, like failure.
    final Color deliveryColour = !rate.hasDeliveryData
        ? DeliveryColors.faint
        : rate.isDeliveryHealthy
            ? DeliveryAccent.positive.color
            : DeliveryAccent.critical.color;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 150,
                child: Text(
                  rate.provider,
                  style: ConsoleText.cellStrong,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  rate.hasData ? '${rate.successRate!.toStringAsFixed(1)}%' : '—',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colour,
                  ),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(DeliveryRadius.pill),
                  child: LinearProgressIndicator(
                    value: rate.hasData ? (rate.successRate! / 100) : 0,
                    minHeight: 6,
                    backgroundColor: DeliveryColors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(colour),
                  ),
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              // The denominator, because a 100% success rate over three messages is not evidence.
              Text(
                'accepted ${rate.sent}/${rate.sent + rate.failed}'
                '${rate.inFlight > 0 ? ' (+${rate.inFlight} in flight)' : ''}',
                style: ConsoleText.meta,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 150, top: 2),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 70,
                  child: Text(
                    rate.hasDeliveryData
                        ? '${rate.deliveryRate!.toStringAsFixed(1)}%'
                        : 'not measured',
                    style: TextStyle(
                      fontSize: 13,
                      color: deliveryColour,
                      fontWeight: rate.hasDeliveryData ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    rate.hasDeliveryData
                        // Awaiting is stated beside the rate rather than folded into it: 12
                        // delivered out of 1000 accepted is not a 1.2% delivery rate, it is 988
                        // receipts that never arrived, and the two call for opposite responses.
                        ? 'delivered ${rate.delivered}/${rate.delivered + rate.undelivered}'
                            '${rate.awaitingReceipt > 0 ? ' (+${rate.awaitingReceipt} awaiting receipt)' : ''}'
                        : 'no carrier receipts — acceptance above is not proof of delivery',
                    style: ConsoleText.meta,
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
