import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'account_screen.dart';
import 'butler_screen.dart';
import 'cached_catalog_screen.dart';
import 'cart.dart';
import 'cart_screen.dart';
import 'customer_nav_bar.dart';
import 'delivery_address.dart';
import 'my_orders_screen.dart';
import 'notification_inbox.dart';
import 'offline_banner.dart';
import 'offline_catalog.dart';
import 'offline_store.dart';
import 'order_outbox.dart';
import 'profile_drawer.dart';
import 'rewards_screen.dart';
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
    this.promoApi,
    this.transferApi,
    this.splitApi,
    this.geocodingApi,
    this.trackingApi,
    this.trackingSocket,
    this.chatApi,
    this.prefsApi,
    this.profileApi,
    this.pointsApi,
    this.connectivity,
    this.offlineStore,
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

  // The capability APIs, optional like everywhere else — but this shell is the ONLY road from
  // main.dart to the customer screens, so a null here is a feature dark for every customer.
  // main.dart passes all five; the nullability exists for tests, not for the app.
  final PromoApi? promoApi;

  /// Checkout's money surface — rate lock, USD/LBP split, wallet methods.
  final TransferApi? transferApi;

  /// The group-split flow behind the basket's Split tab.
  final SplitApi? splitApi;
  final GeocodingApi? geocodingApi;
  final TrackingApi? trackingApi;

  /// The tracking service socket, threaded to the tracking panel for pushed positions.
  final UserQueueSocket? trackingSocket;
  final ChatApi? chatApi;
  final NotificationPrefsApi? prefsApi;

  /// The account's own picture, for the profile drawer and the home header. Null keeps the
  /// monogram.
  final ProfileApi? profileApi;

  /// The points ledger behind the Account tab's rewards screen. Null keeps the old account page —
  /// the fallback a test that constructs the shell without APIs lands on.
  final PointsApi? pointsApi;

  /// Whether the platform answers, fed by the app's own requests (Figma 121:279). Drives the
  /// offline banner, checkout's queue offer and the outbox. Null — a test — counts as online.
  final ConnectivityService? connectivity;

  /// Where queued checkouts and the offline shelf are kept. Null means the device's secure store;
  /// a test passes an in-memory one.
  final OfflineStore? offlineStore;
  final AuthSession session;

  /// Passed to the home screen for the language toggle in the app bar.
  final LocaleController locale;
  final Future<void> Function() onSignOut;

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> with WidgetsBindingObserver {
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
  ///
  /// Scoped to the signed-in person, so one account never inherits another one's saved addresses
  /// on a shared phone. See [DeliveryAddressStore] for what that used to do.
  late final DeliveryAddressStore _addresses =
      DeliveryAddressStore(ownerId: widget.session.subject);

  /// Owned here for the same reason: the unread badge has to stay right while the user is on the
  /// Browse tab, so the poll cannot live inside the notifications screen.
  late final NotificationInbox _inbox = NotificationInbox(widget.notificationApi);

  /// Stands in for [CustomerShell.connectivity] when none was given: always online.
  final ValueNotifier<bool> _assumedOnline = ValueNotifier<bool>(true);

  ValueListenable<bool> get _online => widget.connectivity ?? _assumedOnline;

  late final OfflineStore _offlineStore = widget.offlineStore ?? const SecureOfflineStore();

  /// Checkouts waiting for the connection. Owned here, like the cart, so the Orders tab, the
  /// cached catalog and checkout all see the same queue — and scoped to this account, so nobody
  /// else signing in on the phone can send them.
  late final OrderOutbox _outbox = OrderOutbox(
    api: widget.orderApi,
    store: _offlineStore,
    ownerId: widget.session.subject,
    connectivity: _online,
    transfers: widget.transferApi,
  );

  /// The shelf of recent purchases the cached catalog shows, refreshed whenever the app can.
  late final OfflineCatalog _catalog =
      OfflineCatalog(store: _offlineStore, ownerId: widget.session.subject);

  StreamSubscription<OutboxPlaced>? _placedFromOutbox;

  int _index = CustomerNavBar.homeIndex;

  /// Moves to a tab. The one place the index is written, so a screen that wants to send somebody
  /// to Orders says so by name and cannot be broken by the order changing again.
  void _open(int tab) => setState(() => _index = tab);

  /// Opens the Basket tab from anywhere — including from a screen pushed over this shell, which is
  /// where every "View basket" in the app lives.
  ///
  /// The shop page is pushed from Home, a category listing or an order, and the nav bar is
  /// underneath it. Switching the index alone would change a tab nobody can see. So this first
  /// pops everything above the shell's own route and then switches: the customer lands on the one
  /// basket with the bar under it, can check out from there, and checkout's jump to Orders works
  /// because nothing is left covering it. The Home tab keeps its scroll position under all of this
  /// (it is a child of the IndexedStack, not one of the routes being popped), so going back to
  /// shopping afterwards is one tap on Home.
  ///
  /// Pops to THIS route, not to the first one. The shell is not always the root: an applicant
  /// exploring as a customer has it pushed over their application status (main.dart's
  /// `_exploreAsCustomer`), and popping to the first route would throw them out of the shop
  /// altogether instead of into their basket.
  void _openBasket() {
    final ModalRoute<Object?>? shell = ModalRoute.of(context);
    Navigator.of(context)
        .popUntil((Route<dynamic> route) => route == shell || route.isFirst);
    _open(CustomerNavBar.basketIndex);
  }

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

  /// Re-saves the offline shelf. Silent and best effort; throttled inside unless [force]d.
  void _refreshCatalog({bool force = false}) {
    unawaited(_catalog.refresh(orders: widget.orderApi, stores: widget.storeApi, force: force));
  }

  /// Back online is the moment the shelf can catch up with anything bought meanwhile.
  void _onConnectivity() {
    if (_online.value) _refreshCatalog();
  }

  /// A queued checkout became an order: say so, whichever tab the customer is on.
  ///
  /// Differently when the order is an earlier try of the same basket rather than the checkout as
  /// queued (see [OutboxPlaced.earlierAttempt]) — "your queued order was placed" would describe a
  /// basket that was not.
  void _onQueuedOrderPlaced(OutboxPlaced placed) {
    if (!mounted) return;
    final DeliveryStrings t = DeliveryStrings.of(context);
    // Named by its shop, as its card was: the order's own number is on the Orders list now, and a
    // queued checkout never had one to repeat here.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(placed.earlierAttempt
            ? t.offlineAlreadyPlaced
            : t.offlineSent(
                placed.pending.storeName.isEmpty ? t.tabShop : placed.pending.storeName))));
    _refreshCatalog(force: true);
  }

  /// The offline banner's "Saved items".
  void _openCachedCatalog() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CachedCatalogScreen(
        catalog: _catalog,
        cart: _cart,
        connectivity: _online,
        outbox: _outbox,
        onOpenBasket: _openBasket,
      ),
    ));
  }

  @override
  void initState() {
    super.initState();
    _inbox.start();
    _addresses.load();
    // The quote follows the basket rather than the screen, so the fee has already disappeared by
    // the time the customer opens the Basket tab to look at it.
    _cart.addListener(_requoteDelivery);
    // Whatever was queued before the app last stopped is restored and, if the platform answers,
    // sent now.
    _outbox.load();
    _placedFromOutbox = _outbox.placed.listen(_onQueuedOrderPlaced);
    _catalog.load().then((_) => _refreshCatalog());
    _online.addListener(_onConnectivity);
    WidgetsBinding.instance.addObserver(this);
  }

  /// Coming back to the app is when a connection most often turns out to have returned — and a
  /// phone that suspended the app may never have run the re-check it had scheduled. So ask now, and
  /// give anything waiting in the outbox its chance: a send is always safe, because every copy of a
  /// queued checkout carries its one key.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(widget.connectivity?.recheck());
    unawaited(_outbox.drain());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _online.removeListener(_onConnectivity);
    _placedFromOutbox?.cancel();
    _outbox.dispose();
    _catalog.dispose();
    _assumedOnline.dispose();
    _cart.removeListener(_requoteDelivery);
    _cart.dispose();
    _addresses.dispose();
    _inbox.dispose();
    super.dispose();
  }

  /// One destination, chosen by its index in [CustomerNavBar].
  ///
  /// A switch rather than a list literal so the compiler is the thing that notices when a tab is
  /// added and this is not updated.
  Widget _tabAt(int tab) {
    switch (tab) {
      case CustomerNavBar.homeIndex:
        return StoreHomeScreen(
          storeApi: widget.storeApi,
          zoneApi: widget.zoneApi,
          orderApi: widget.orderApi,
          prefsApi: widget.prefsApi,
          cart: _cart,
          addresses: _addresses,
          inbox: _inbox,
          locale: widget.locale,
          session: widget.session,
          profileApi: widget.profileApi,
          splitApi: widget.splitApi,
          transferApi: widget.transferApi,
          onSignOut: widget.onSignOut,
          onOpenBasket: _openBasket,
        );
      case CustomerNavBar.ordersIndex:
        return MyOrdersScreen(
          api: widget.orderApi,
          storeApi: widget.storeApi,
          trackingApi: widget.trackingApi,
          trackingSocket: widget.trackingSocket,
          chatApi: widget.chatApi,
          cart: _cart,
          onOpenBasket: _openBasket,
          outbox: _outbox,
        );
      case CustomerNavBar.butlerIndex:
        return ButlerScreen(
          addresses: _addresses,
          zoneApi: widget.zoneApi,
          api: widget.butlerApi,
          orderApi: widget.orderApi,
          storeApi: widget.storeApi,
          trackingApi: widget.trackingApi,
          trackingSocket: widget.trackingSocket,
          chatApi: widget.chatApi,
          cart: _cart,
          onOpenBasket: _openBasket,
        );
      case CustomerNavBar.basketIndex:
        return CartScreen(
          cart: _cart,
          addresses: _addresses,
          orderApi: widget.orderApi,
          offerApi: widget.offerApi,
          zoneApi: widget.zoneApi,
          promoApi: widget.promoApi,
          transferApi: widget.transferApi,
          splitApi: widget.splitApi,
          profileApi: widget.profileApi,
          session: widget.session,
          geocodingApi: widget.geocodingApi,
          outbox: _outbox,
          connectivity: _online,
          onOrderPlaced: () {
            _open(CustomerNavBar.ordersIndex);
            // The purchase just made belongs on the offline shelf.
            _refreshCatalog(force: true);
          },
        );
      case CustomerNavBar.accountIndex:
        // The redesign splits what this tab used to hold: the tab itself shows Rewards & Points,
        // and account management lives in the profile drawer opened from the home header. The old
        // merged page remains only as the fallback when no points API was provided.
        if (widget.pointsApi != null) {
          return RewardsScreen(pointsApi: widget.pointsApi!);
        }
        return AccountScreen(
          session: widget.session,
          zoneApi: widget.zoneApi,
          addresses: _addresses,
          onSignOut: widget.onSignOut,
          locale: widget.locale,
          inbox: _inbox,
          prefsApi: widget.prefsApi,
          profileApi: widget.profileApi,
          onOpenOrders: () => _open(CustomerNavBar.ordersIndex),
        );
      default:
        // Unreachable: the loop above is bounded by tabCount. Kept because a switch over an int
        // has to be exhaustive somehow, and an empty box beats a crash if that ever stops holding.
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      // Both drive badges in the bar below, so both have to rebuild it.
      animation: Listenable.merge(<Listenable>[_cart, _inbox, _addresses]),
      builder: (BuildContext context, _) {
        return Scaffold(
          // The profile side menu, opened from the home header's avatar. On the SHELL's scaffold
          // rather than a screen's so it slides over everything, nav bar included, the way the
          // frame draws it.
          drawer: ProfileDrawer(
            session: widget.session,
            addresses: _addresses,
            zoneApi: widget.zoneApi,
            onSignOut: widget.onSignOut,
            locale: widget.locale,
            inbox: _inbox,
            profileApi: widget.profileApi,
            onOpenOrders: () => _open(CustomerNavBar.ordersIndex),
          ),
          // IndexedStack, not a switch: it keeps each tab's scroll position and in-flight requests
          // alive, so switching to the basket and back does not refetch the catalog.
          //
          // The order is the design's, and it is written down once in [CustomerNavBar]. The list
          // below is built by index rather than as a literal so the two cannot drift: a stack whose
          // third child is not Butler is a bar that opens the wrong screen, and nothing about the
          // code would look wrong.
          //
          // The offline banner wraps the stack rather than any one tab: it is true whichever tab is
          // showing, and above the stack it can never cover the nav bar below.
          body: OfflineBanner(
            connectivity: _online,
            onOpenSaved: _openCachedCatalog,
            child: IndexedStack(
              index: _index,
              children: <Widget>[
                for (int tab = 0; tab < CustomerNavBar.tabCount; tab++) _tabAt(tab),
              ],
            ),
          ),
          bottomNavigationBar: CustomerNavBar(
            index: _index,
            basketCount: _cart.itemCount,
            onSelected: _open,
          ),
        );
      },
    );
  }
}
