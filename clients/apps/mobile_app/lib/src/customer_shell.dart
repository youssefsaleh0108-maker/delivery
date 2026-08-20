import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'account_screen.dart';
import 'butler_screen.dart';
import 'cart.dart';
import 'cart_screen.dart';
import 'customer_nav_bar.dart';
import 'delivery_address.dart';
import 'my_orders_screen.dart';
import 'notification_inbox.dart';
import 'store_home_screen.dart';

/// The Customer surface: shops, basket, orders, notifications.
class CustomerShell extends StatefulWidget {
  const CustomerShell({
    super.key,
    required this.storeApi,
    required this.orderApi,
    required this.notificationApi,
    required this.butlerApi,
    required this.zoneApi,
    required this.offerApi,
    required this.session,
    required this.locale,
    required this.onSignOut,
  });

  final StoreApi storeApi;
  final OrderApi orderApi;
  final NotificationApi notificationApi;
  final ButlerApi butlerApi;
  final DeliveryZoneApi zoneApi;
  final OfferApi offerApi;
  final AuthSession session;

  /// Passed to the home screen for the language toggle in the app bar.
  final LocaleController locale;
  final Future<void> Function() onSignOut;

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  // The tabs, named. Both the IndexedStack and the bar below are ordered by these, and checkout
  // jumps to Orders by number once an order is placed.
  static const int _ordersTab = 3;

  /// One cart for the whole session, owned here so the badge and the basket screen cannot disagree.
  final Cart _cart = Cart();

  /// The basket the delivery quote was last asked about.
  ///
  /// Only the shop and the subtotal matter — those are what an offer's scope and minimum are
  /// tested against. Comparing against it is also what stops a loop: refreshing the quote notifies
  /// the cart, which calls this again, and without a signature that has not changed it would ask
  /// the server forever.
  String? _quotedFor;

  /// The delivery address, owned here for the same reason: the home header shows it and checkout
  /// uses it, and those two must never disagree.
  final DeliveryAddressStore _addresses = DeliveryAddressStore();

  /// Owned here for the same reason: the unread badge has to stay right while the user is on the
  /// Browse tab, so the poll cannot live inside the notifications screen.
  late final NotificationInbox _inbox = NotificationInbox(widget.notificationApi);

  int _index = 0;

  /// Re-asks the server what this basket qualifies for, when the basket has actually changed.
  ///
  /// Crossing an offer's minimum is exactly the moment the customer should see the fee disappear,
  /// so this follows the subtotal rather than only firing when the Basket tab opens.
  void _requoteDelivery() {
    final String signature = '${_cart.storeId}|${_cart.subtotal.toStringAsFixed(2)}';
    if (signature == _quotedFor) {
      return;
    }
    _quotedFor = signature;
    _cart.refreshWaiver(widget.offerApi);
  }

  @override
  void initState() {
    super.initState();
    _inbox.start();
    _addresses.load();
    // The quote follows the basket rather than the screen, so the fee has already disappeared by
    // the time the customer opens the Basket tab to look at it.
    _cart.addListener(_requoteDelivery);
  }

  @override
  void dispose() {
    _cart.removeListener(_requoteDelivery);
    _cart.dispose();
    _addresses.dispose();
    _inbox.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      // Both drive badges in the bar below, so both have to rebuild it.
      animation: Listenable.merge(<Listenable>[_cart, _inbox, _addresses]),
      builder: (BuildContext context, _) {
        return Scaffold(
          body: IndexedStack(
            index: _index,
            children: <Widget>[
              // IndexedStack, not a switch: it keeps each tab's scroll position and in-flight
              // requests alive, so switching to the basket and back does not refetch the catalog.
              StoreHomeScreen(
                storeApi: widget.storeApi,
                zoneApi: widget.zoneApi,
                orderApi: widget.orderApi,
                cart: _cart,
                addresses: _addresses,
                inbox: _inbox,
                locale: widget.locale,
                session: widget.session,
                onSignOut: widget.onSignOut,
              ),
              ButlerScreen(
                addresses: _addresses,
                zoneApi: widget.zoneApi,
                api: widget.butlerApi,
                orderApi: widget.orderApi,
                storeApi: widget.storeApi,
                cart: _cart,
              ),
              CartScreen(
                cart: _cart,
                addresses: _addresses,
                orderApi: widget.orderApi,
                offerApi: widget.offerApi,
                zoneApi: widget.zoneApi,
                onOrderPlaced: () => setState(() => _index = _ordersTab),
              ),
              MyOrdersScreen(
                api: widget.orderApi,
                storeApi: widget.storeApi,
                cart: _cart,
              ),
              AccountScreen(
                session: widget.session,
                zoneApi: widget.zoneApi,
                addresses: _addresses,
                onSignOut: widget.onSignOut,
              ),
            ],
          ),
          // Not a NavigationBar: the basket is the one destination that has to be findable without
          // looking, and five equal icons make it exactly as findable as Account. See
          // [CustomerNavBar].
          bottomNavigationBar: CustomerNavBar(
            index: _index,
            basketCount: _cart.itemCount,
            onSelected: (int i) => setState(() => _index = i),
          ),
        );
      },
    );
  }
}
