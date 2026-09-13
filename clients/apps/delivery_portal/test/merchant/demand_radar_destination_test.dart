import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/portal_shell.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The merchant web reaches the Demand Radar through the Merchant Hub rail.
///
/// The rail's order is load-bearing: the dashboard's "see all orders" link is `jump(2)`. So the
/// radar is appended after the merchant suite rather than slotted in beside the analytics it belongs
/// with, and this pins both halves of that — the new page is last, and Orders is still third.
void main() {
  test('the Demand Radar is the last Merchant Hub page, and Orders is still the third', () {
    final DeliveryStrings t = lookupDeliveryStrings(const Locale('en'));
    final List<PortalDestination> hub = PortalArea.merchant_.destinations;

    expect(hub[2].label(t), t.navOrders);
    expect(hub.last.label(t), t.heatmapTitle);
  });
}
