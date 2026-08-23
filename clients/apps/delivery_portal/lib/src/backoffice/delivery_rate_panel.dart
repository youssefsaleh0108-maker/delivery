import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

/// Delivery rates per provider, shown on the connector card that can change them (Phase 6).
///
/// Deliberately on the Settings screen rather than on a monitoring page of its own. The person
/// ramping a vendor makes the change here, and the consequence of the last change is the single
/// most useful thing to put in front of them before they make the next one. A dashboard they have
/// to remember to open separately is a dashboard nobody checks at the moment it matters.
///
/// Only shown for connectors that have a real choice of provider. SMTP-only email has nothing to
/// compare against, and a success rate with one row is a number without a question attached.
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
            child: LinearProgressIndicator(),
          );
        }
        if (snapshot.hasError) {
          return Text(
            'Delivery rates unavailable: ${snapshot.error}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DeliveryColors.muted),
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
                Text('Accepted / delivered',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: DeliveryColors.muted)),
                const Spacer(),
                for (final int hours in <int>[1, 24, 168])
                  Padding(
                    padding: const EdgeInsets.only(left: DeliverySpacing.xs),
                    child: ChoiceChip(
                      label: Text(hours == 168 ? '7d' : '${hours}h'),
                      selected: _windowHours == hours,
                      onSelected: (_) => _setWindow(hours),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: DeliverySpacing.xs),
            if (rates.isEmpty)
              Text(
                'Nothing sent on this channel in the last '
                '${_windowHours == 168 ? "7 days" : "$_windowHours hours"}.',
                style:
                    Theme.of(context).textTheme.bodySmall?.copyWith(color: DeliveryColors.muted),
              )
            else
              for (final ProviderDeliveryRate rate in rates)
                _RateRow(rate: rate),
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
        ? DeliveryColors.muted
        : rate.isHealthy
            ? const Color(0xFF2E7D32)
            : DeliveryColors.brand;

    // Delivery is its own three-state axis. "Not measured" is the common case — most SMS traffic
    // produces no carrier receipt at all — and it must not be coloured, or read, like failure.
    final Color deliveryColour = !rate.hasDeliveryData
        ? DeliveryColors.muted
        : rate.isDeliveryHealthy
            ? const Color(0xFF2E7D32)
            : DeliveryColors.brand;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 150,
                child: Text(rate.provider,
                    style: Theme.of(context).textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  rate.hasData ? '${rate.successRate!.toStringAsFixed(1)}%' : '—',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: colour, fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(DeliveryRadius.pill),
                  child: LinearProgressIndicator(
                    value: rate.hasData ? (rate.successRate! / 100) : 0,
                    minHeight: 6,
                    backgroundColor: DeliveryColors.background,
                    valueColor: AlwaysStoppedAnimation<Color>(colour),
                  ),
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              // The denominator, because a 100% success rate over three messages is not evidence.
              Text(
                'accepted ${rate.sent}/${rate.sent + rate.failed}'
                '${rate.inFlight > 0 ? ' (+${rate.inFlight} in flight)' : ''}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DeliveryColors.muted),
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
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: deliveryColour,
                          fontWeight:
                              rate.hasDeliveryData ? FontWeight.w600 : FontWeight.normal,
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
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: DeliveryColors.muted),
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
