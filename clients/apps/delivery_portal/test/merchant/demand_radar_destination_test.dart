import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/portal_shell.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The merchant web reaches the Demand Radar through the Merchant Hub rail.
///
/// The rail's order is load-bearing: the dashboard's "see all orders" link is `jump(2)`. So the
/// radar is appended after the merchant suite rather than slotted in beside the analytics it belongs
/// with, and this pins both halves of that — the new page comes after the whole suite, and Orders is
/// still third. Pages appended after it, like the shop inbox, may follow it.
void main() {
  test('the Demand Radar comes after the whole merchant suite, and Orders is still the third', () {
    final DeliveryStrings t = lookupDeliveryStrings(const Locale('en'));
    final List<String> hub = <String>[
      for (final PortalDestination d in PortalArea.merchant_.destinations) d.label(t),
    ];

    expect(hub[2], t.navOrders);
    // Staff is the suite's last page: the radar was appended after it, not slotted in earlier.
    final int staff = hub.indexOf(t.navStaff);
    expect(staff, isNonNegative);
    expect(hub.indexOf(t.heatmapTitle), greaterThan(staff));
  });
}
