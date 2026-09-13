import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'address_sheet.dart';
import 'basket_quote.dart';
import 'split_complete_screen.dart';
import 'cart.dart';
import 'delivery_address.dart';
import 'delivery_terms_book.dart';
import 'order_outbox.dart';
import 'order_placement.dart';

/// Review the basket and place the order.
///
/// Laid out as the 2026-08 Figma redesign draws it (`customer-checkout`, node 3:471): a 56px white
/// header, a 24px body of three stacked sections — saved addresses as radio cards, the payment
/// strip, the order note — and a sticky white summary bar carrying the total on the start side and
/// the pill CTA on the end.
///
/// **The total is the server's.** A [BasketQuoter] asks Order Manager about this basket, delivered
/// to the chosen address, at the chosen tier, with the basket's promo code (`POST
/// /api/orders/quote`), and asks again whenever the address or the tier changes. So the total on
/// the button includes what this screen could not show before placement: the EXPRESS premium, the
/// fee for the address's area, and what a promo code is worth at that fee. The server still prices
/// again at placement — a merchant can re-price mid-session — and the confirmation shows ITS total.
///
/// Without an answer — the platform unreachable — a one-shop basket falls back to what the phone
/// knows: the shop's terms for the address's area as last learned ([DeliveryTermsBook]), or the
/// shop's flat fee for an address with no area. A queued checkout asserts its total to the server,
/// so it is queued at the quote's total when there is one, and otherwise only when that fallback is
/// exactly what Order Manager will charge — never for Express, an unlearned area fee, or a promo
/// quoted at another fee.
///
/// **A basket from several shops** is placed as one checkout (`OrderApi.placeCheckout`): every
/// shop's order or none, under the basket's one key. Every shop's delivery circle is checked before
/// anything is sent; the USD/LBP cash split is not offered, because there is no one order total to
/// split; and it is never queued for later — see [_whyItCannotWait].
///
/// The basket recap the previous layout carried is gone, as in the design: the Basket screen this
/// is pushed from lists every line immediately before, and the money — the part that must not be a
/// surprise — is in the sticky bar the whole time.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.api,
    required this.cart,
    required this.addresses,
    this.zoneApi,
    this.geocodingApi,
    this.promo,
    this.transferApi,
    this.splitApi,
    this.outbox,
    this.connectivity,
    this.deliveryTerms,
  });

  final OrderApi api;
  final Cart cart;
  final DeliveryAddressStore addresses;

  /// The money surface: the locked rate, the wallet methods, and where the approved payment
  /// intent is recorded after placement. Optional so a test can pump this screen without a
  /// server; the screen then falls back to the display rate and cash-only.
  final TransferApi? transferApi;

  /// Closes the group split plan over the placed order and shows the All-Shares-Paid screen.
  /// Optional like [transferApi]; without it a split basket still checks out, just without the
  /// ceremony.
  final SplitApi? splitApi;

  /// Passed straight through to the address sheet so the area picker appears when a new address is
  /// added from here. Optional so a test can pump this screen without a server.
  final DeliveryZoneApi? zoneApi;

  /// Passed straight through to the address sheet for the place search. Optional for the same
  /// reason as [zoneApi].
  final GeocodingApi? geocodingApi;

  /// The promo quote the basket validated, carried here so the code travels with the order and
  /// the sticky bar can show the same advisory total the basket showed. Only ever a VALID quote —
  /// the basket does not hand over a refused one. The discount that is billed is recomputed by
  /// the server at placement.
  final PromoQuote? promo;

  /// Where a checkout goes when the platform cannot be reached: kept on the phone and sent when the
  /// connection returns (Figma 121:279). Null — a test that passes none — offers no queue, only
  /// the error it always showed.
  final OrderOutbox? outbox;

  /// Whether the platform is reachable. When it is already known not to be, placing goes straight
  /// to the queue offer instead of spending a twenty-second timeout proving it again.
  final ValueListenable<bool>? connectivity;

  /// What each shop charges to reach each area, as the platform last said.
  ///
  /// Where this screen's delivery fee comes from when the chosen address has an area. Null (a test
  /// that passes none) leaves the shop's flat fee on screen, and queues nothing whose total needs
  /// the area's fee.
  final DeliveryTermsBook? deliveryTerms;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  /// The address line the customer is delivering to, identifying one of the saved addresses.
  ///
  /// The line rather than an index: the recents list reorders itself whenever an address is picked,
  /// so an index would quietly come to mean a different address.
  String? _addressLine;

  /// Cash by default — the one method that moves real money. Card and wallet are selectable too,
  /// authorising against the DEV payment provider, and the strip labels them as test payments so
  /// nobody mistakes a dev authorisation for a charge.
  PaymentMethod _payment = PaymentMethod.cash;

  // The old cash/card/wallet strip left with the Lebanese redesign: the method rows below offer
  // cash and whichever wallet transfers a connector will actually carry.

  // ------------------------------------------------------------- the Lebanese money surface

  /// The transfer service's LOCKED rate and rider-change promise. Null until fetched; the
  /// screen then leans on the display rate and draws no lock it cannot promise.
  TransferRate? _rate;

  /// Wallet methods some connector will actually carry (WHISH/OMT wire names). Empty until
  /// fetched, and empty keeps those rows undrawn — a method that shows and then fails is worse
  /// than one that never showed.
  List<String> _walletMethods = const <String>[];

  /// The wallet method chosen INSTEAD of a card/wallet row, or null when paying cash. Rides on
  /// top of [_payment]: the order itself is placed as the dev-provider wallet payment, and the
  /// transfer ledger records which instrument actually carried it.
  String? _walletChoice;

  /// The USD half of the cash split. Text so the field can be blank (= all USD).
  final TextEditingController _splitUsd = TextEditingController();

  Future<void> _loadMoney() async {
    final TransferApi? api = widget.transferApi;
    if (api == null) return;
    try {
      final TransferRate rate = await api.rate();
      final List<String> methods = await api.methods();
      if (!mounted) return;
      setState(() {
        _rate = rate;
        _walletMethods = methods.where((String m) => m != 'CASH_ON_DELIVERY').toList();
      });
    } catch (_) {
      // Cash-only, display rate. The screen stays usable.
    }
  }

  /// The opaque instrument handle a real processor's SDK would mint on the device. The DEV
  /// provider deliberately never reads it, so a fixed marker is the honest value — there is no
  /// card to tokenise.
  static const String _devInstrumentToken = 'dev-test-instrument';

  /// How fast the customer asked for it. Standard by default, and sent explicitly either way —
  /// an absent tier means STANDARD on the server, but saying so is what keeps this screen and the
  /// order agreeing when that default ever changes.
  ///
  /// The premium is priced entirely server-side from `delivery.orders.express-surcharge` and
  /// snapshotted onto the order at placement — by the contract there is never a surcharge field on
  /// the request. The checkout's quote includes it once the tier is chosen, so the total on the
  /// button is the one charged; the tier card itself only says a surcharge applies rather than
  /// restating a figure, and the receipt itemises the order's own `expressSurcharge`.
  DeliveryTier _tier = DeliveryTier.standard;

  /// The two tiers, in the order the server declares them.
  static const List<DeliveryTier> _tiers = <DeliveryTier>[
    DeliveryTier.standard,
    DeliveryTier.express,
  ];

  bool _placing = false;

  /// The server's price for this checkout as it stands: this basket, to the chosen address, at the
  /// chosen tier, with the basket's code. See the class comment.
  late final BasketQuoter _quoter = BasketQuoter(widget.api);

  @override
  void initState() {
    super.initState();
    // Pre-selects the address chosen on the home screen. Retyping it here was the whole reason that
    // header existed, and re-asking would invite the two answers to differ.
    final DeliveryAddress? chosen = widget.addresses.selected;
    _addressLine = chosen?.line;
    _followAreaTerms();
    // The door instructions saved with the address, seeded into the note that travels with the
    // order — the order is the only thing the rider ever sees, so anything left only on the address
    // never reaches the door it describes.
    if (chosen?.notes != null && chosen!.notes!.isNotEmpty) {
      _notes.text = chosen.notes!;
    }
    widget.addresses.addListener(_onAddressesChanged);
    _loadMoney();
    // Asked before listening, so the ask's own notification does not rebuild an unbuilt screen.
    _askForQuote();
    _quoter.addListener(_onQuote);
  }

  void _onQuote() {
    if (mounted) setState(() {});
  }

  void _askForQuote() {
    _quoter.ask(questionFor(widget.cart,
        zoneId: _address?.zoneId, tier: _tier, promoCode: widget.promo?.code));
  }

  @override
  void dispose() {
    _quoter.removeListener(_onQuote);
    _quoter.dispose();
    widget.addresses.removeListener(_onAddressesChanged);
    _phone.dispose();
    _notes.dispose();
    _splitUsd.dispose();
    super.dispose();
  }

  /// Follows the store when the address sheet saves a new address.
  ///
  /// The sheet selects what it saved, so the newly added address is the one this screen should now
  /// be delivering to — the customer opened it in order to use it.
  void _onAddressesChanged() {
    if (!mounted) return;
    _choose(widget.addresses.selected?.line);
  }

  /// Points the screen at an address, and re-seeds the note that goes with it.
  ///
  /// The note follows the address rather than the session: "second buzzer, blue door" describes one
  /// door, and carrying it across to a different one is worse than losing it.
  void _choose(String? line) {
    setState(() {
      _addressLine = line;
      final DeliveryAddress? address = _address;
      _notes.text = address?.notes ?? '';
      // Another address can be another area, and another delivery fee.
      _followAreaTerms();
    });
    _askForQuote();
  }

  /// The shop's terms for the chosen address's area, as [CheckoutScreen.deliveryTerms] last had
  /// them, and the `storeId|zoneId` they answer for. Both null for an address with no area.
  ZoneTerms? _areaTerms;
  String? _areaTermsFor;

  /// Takes the book's last answer for the chosen address now, and asks the platform for a fresh
  /// one behind it. Called when the screen opens and whenever the address changes; an answer for
  /// an address the customer has since moved away from is dropped.
  void _followAreaTerms() {
    final DeliveryTermsBook? book = widget.deliveryTerms;
    final String? storeId = widget.cart.storeId;
    final String? zoneId = _address?.zoneId;
    if (book == null || storeId == null || zoneId == null) {
      _areaTerms = null;
      _areaTermsFor = null;
      return;
    }
    final String pair = '$storeId|$zoneId';
    _areaTerms = book.known(storeId, zoneId);
    _areaTermsFor = pair;
    book.learn(storeId, zoneId).then((ZoneTerms? learned) {
      if (!mounted || _areaTermsFor != pair) return;
      setState(() => _areaTerms = learned);
    });
  }

  /// What Order Manager will charge to deliver this basket to the chosen address, before any
  /// waiver — or null when this phone cannot know it.
  ///
  /// An address with an area is priced by the shop's terms for that area, which only the platform
  /// can say. One without is priced at the shop's flat fee, which the basket's shop card carries.
  /// No shop card, no terms for the area, or an area the shop does not serve: null, never a guess.
  double? get _serverDeliveryFee {
    final DeliveryAddress? address = _address;
    final String? storeId = widget.cart.storeId;
    final StoreCard? shop = widget.cart.store;
    if (address == null || storeId == null || shop == null) return null;
    final String? zoneId = address.zoneId;
    if (zoneId == null) return shop.deliveryFee;
    final ZoneTerms? terms = _areaTerms;
    if (terms == null || !terms.served || _areaTermsFor != '$storeId|$zoneId') return null;
    return terms.deliveryFee;
  }

  /// The address the radio list currently names, or null when nothing is chosen yet.
  DeliveryAddress? get _address {
    final String? line = _addressLine;
    if (line == null) return null;
    for (final DeliveryAddress a in widget.addresses.recents) {
      if (a.line == line) return a;
    }
    // Selected but absent from recents cannot normally happen — selecting promotes into recents —
    // but a stale line must not silently resolve to somebody else's address.
    final DeliveryAddress? selected = widget.addresses.selected;
    return selected?.line == line ? selected : null;
  }

  Future<void> _addAddress() async {
    await showAddressSheet(context, widget.addresses,
        zoneApi: widget.zoneApi, geocodingApi: widget.geocodingApi);
    // The listener has already taken the sheet's answer; this only repaints if it saved nothing.
    if (mounted) setState(() {});
  }

  Future<void> _place() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final DeliveryAddress? address = _address;
    if (address == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.addressRequired)));
      return;
    }
    if (!_form.currentState!.validate()) return;

    // Every shop's delivery circle, honoured before promising — the rule every checkout shares
    // (isOutsideDeliveryRadius): an address with no pin passes, because the zones still gate it. On
    // a basket from several shops, the shop that cannot reach the address is the one named.
    for (final String storeId in widget.cart.storeIds) {
      final StoreCard? shop = widget.cart.storeFor(storeId);
      if (isOutsideDeliveryRadius(shop, address)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t.custOutsideDeliveryArea(shop!.name,
                (shop.deliveryRadiusMetres! / 1000).toStringAsFixed(1)))));
        return;
      }
    }

    // Read before the await below: re-selecting the address notifies the store, which re-seeds this
    // field, and reading it afterwards would send the address's saved note instead of what the
    // customer actually typed. Door instructions and nothing else: a gift basket never checks out
    // here, and its card travels from the gift checkout as the gift's own message.
    final String notes = _notes.text.trim();

    // One attempt per basket. Its key lives on the cart rather than on this screen, so backing out
    // after a try whose answer was lost and checking out again is recognised as the same attempt:
    // the server answers with the order that try may already have placed, instead of placing a
    // second. Every retry below — and a queued send hours later — carries this same submission.
    final OrderSubmission submission = OrderSubmission(
      idempotencyKey: widget.cart.checkoutKey,
      items: widget.cart.toOrderLines(),
      deliveryAddress: address.line,
      // The area comes from the address that was picked, so the two can no longer disagree the
      // way they could when the line was a free-text box sitting over a remembered zone id.
      deliveryZoneId: address.zoneId,
      contactPhone: _phone.text.trim(),
      notes: notes,
      paymentMethod: _payment,
      // Always sent, never inferred. The surcharge that follows from it is the server's to
      // price and the receipt's to itemise.
      deliveryTier: _tier,
      // The canonical code the server quoted, never raw field text. The discount is recomputed
      // at placement against the basket the server priced itself.
      promoCode: widget.promo?.code,
      // Non-cash goes to the DEV provider, which ignores the token by design — there is no
      // card SDK to mint a real one. A decline comes back as a 402 and the order is not placed.
      paymentInstrumentToken: _payment.needsProvider ? _devInstrumentToken : null,
      // The pin from the place picker, when the address has one. This is what gives the
      // tracking service a real point to measure the rider's ETA against.
      deliveryLatitude: address.latitude,
      deliveryLongitude: address.longitude,
    );

    // Already known to be unreachable: offer the queue now rather than prove it with a timeout.
    // Nothing leaves the phone this time — but an earlier try of this same basket may have, and
    // then the offer must not say the order hasn't gone through.
    if (widget.outbox != null && widget.connectivity?.value == false) {
      await widget.addresses.select(address);
      if (!mounted) return;
      await _offerToQueue(submission, unconfirmed: widget.cart.checkoutUnconfirmed);
      return;
    }

    setState(() => _placing = true);
    try {
      // Re-selects it unchanged, which promotes it to the top of the recents for next time.
      //
      // Unchanged is the point. Checkout used to write this screen's notes field back onto the
      // saved address, so an order-specific "ring twice, they are expecting me" quietly replaced
      // the door instructions the address had been carrying.
      await widget.addresses.select(address);

      // One order for a one-shop basket; one checkout — every shop's order or none — for a basket
      // from several. Null when the answer was dealt with where it came.
      final ({Object outcome, List<DeliveryOrder> orders})? placed = widget.cart.isMultiShop
          ? await _sendCheckout(submission, t)
          : await _sendOrder(submission, t);
      if (placed == null) return;
      // The approved payment intent, into the transfer ledger with the locked rate — which
      // instrument actually carries the money (cash split, Whish, OMT), a fact the order's own
      // cash/wallet field is too coarse to hold. Best-effort by design: the order exists either
      // way, and cash collection reads the ledger only when a row is there to read. One intent per
      // order, because each is collected at its own door.
      final TransferApi? transfers = widget.transferApi;
      if (transfers != null) {
        for (final DeliveryOrder order in placed.orders) {
          try {
            await transfers.initiate(
              orderId: order.id,
              method: _walletChoice ?? 'CASH_ON_DELIVERY',
              amountUsd: order.totalAmount,
              // The USD/LBP split is offered for a one-shop basket only: several orders have no
              // one total to split.
              splitUsd: _payment == PaymentMethod.cash && placed.orders.length == 1
                  ? _splitUsdValue
                  : null,
            );
          } catch (_) {
            // The ledger missed one intent; the order and its payment method stand.
          }
        }
      }
      // A group split closes over its order and gets its All-Shares-Paid moment. Read before
      // clear() wipes it with the rest of the basket's order-scoped state. Only ever one order: a
      // basket from several shops is never split.
      final String? planId = widget.cart.splitPlanId;
      if (planId != null && widget.splitApi != null && placed.orders.length == 1) {
        final DeliveryOrder order = placed.orders.single;
        try {
          final SplitPlan plan =
              await widget.splitApi!.attachOrder(planId, order.id);
          if (mounted) {
            await Navigator.of(context).push<void>(MaterialPageRoute<void>(
              builder: (BuildContext ctx) => SplitCompleteScreen(
                plan: plan,
                onTrack: () => Navigator.of(ctx).pop(),
              ),
            ));
          }
        } catch (_) {
          // The order stands; the ceremony can be skipped, the ledger cannot.
        }
      }
      // Placed: the attempt has its answer, and the next basket is a new one under a new key.
      widget.cart.settleCheckout();
      if (!mounted) return;
      Navigator.of(context).pop(placed.outcome);
    } on DioException catch (e) {
      // First, and whether or not this screen is still up: a send that may have placed the order
      // pins the basket's key, so nothing the customer does to the basket next can place a second
      // order beside it (see [Cart.checkoutUnconfirmed]).
      final bool mayHavePlaced = OrderApi.mayHavePlaced(e);
      if (mayHavePlaced) widget.cart.markCheckoutUnconfirmed(submission.idempotencyKey);
      if (!mounted) return;
      setState(() => _placing = false);

      // The platform could not be reached, or the answer never came. The order may not exist — or
      // it may, with the confirmation lost on the way back — so this is not a failure to report as
      // one. The basket and its key stay, and the customer can have this same attempt sent when
      // the connection returns; the offer says whether it may already have gone through.
      if (widget.outbox != null && ConnectivityService.outcomeUnknown(e)) {
        await _offerToQueue(submission, unconfirmed: widget.cart.checkoutUnconfirmed);
        return;
      }

      // No queue to offer, or a server error after the request arrived: still never "it didn't go
      // through". Trying again is safe — it sends this same attempt.
      if (mayHavePlaced) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t.offlineUnconfirmedRetry)));
        return;
      }

      // A refusal: 422 (an item went, the shop closed), 402 (the payment was declined), 400. The
      // sentence every checkout shares — the server's own detail where it sent one.
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(placementRefusalMessage(e, t))));
    }
  }

  /// Sends a one-shop basket as the single order it is. Null when the answer was dealt with here.
  Future<({Object outcome, List<DeliveryOrder> orders})?> _sendOrder(
      OrderSubmission submission, DeliveryStrings t) async {
    final PlaceOrderResult result = await widget.api.place(submission);
    if (result is OrderPlaced) {
      return (outcome: result.order, orders: <DeliveryOrder>[result.order]);
    }
    if (result is OrderAlreadyPlaced) return _earlierAttempt(result.orderId, t);
    _unexpectedPriceChange(t);
    return null;
  }

  /// Sends a basket from several shops as one checkout: every shop's order, or none. Null when the
  /// answer was dealt with here.
  ///
  /// A shop that refuses — closed, not delivering to the address, under its minimum — is thrown,
  /// and the refusal sentence every checkout shares ([placementRefusalMessage]) is the server's,
  /// which names the shop.
  Future<({Object outcome, List<DeliveryOrder> orders})?> _sendCheckout(
      OrderSubmission submission, DeliveryStrings t) async {
    final PlaceCheckoutResult result = await widget.api.placeCheckout(submission);
    if (result is CheckoutPlaced) return (outcome: result, orders: result.orders);
    if (result is CheckoutAlreadyPlaced) return _earlierAttempt(result.orderId, t);
    _unexpectedPriceChange(t);
    return null;
  }

  /// An earlier try of this basket went through before the customer changed it. That order is the
  /// truth; placing the changed basket as well is the duplicate the key prevents. It is read to be
  /// shown — or, when it cannot be read, the basket it came from is settled and the screen closes.
  Future<({Object outcome, List<DeliveryOrder> orders})?> _earlierAttempt(
      String orderId, DeliveryStrings t) async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.offlineAlreadyPlaced)));
    }
    DeliveryOrder? existing;
    try {
      existing = await widget.api.read(orderId);
    } catch (_) {
      existing = null;
    }
    if (existing == null) {
      // It exists; it just could not be fetched to show. The basket it came from is done.
      widget.cart.settleCheckout();
      if (mounted) Navigator.of(context).pop();
      return null;
    }
    return (outcome: existing, orders: <DeliveryOrder>[existing]);
  }

  /// A price-changed answer, which only ever comes back to a request that asserts a total — and this
  /// screen sends none: the customer is looking at the total, and the confirmation shows the
  /// server's own.
  void _unexpectedPriceChange(DeliveryStrings t) {
    if (!mounted) return;
    setState(() => _placing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.couldNotPlaceOrder)));
  }

  /// Offers to keep this checkout on the phone and send it when the connection returns.
  ///
  /// Only for a checkout the outbox can place later exactly as agreed: [_whyItCannotWait] says what
  /// is refused and why, and the dialog names the reason rather than offering a queue that could
  /// only fail later — or come back at a total nobody changed.
  ///
  /// [unconfirmed] is true when a send of this attempt may already have placed the order
  /// ([Cart.checkoutUnconfirmed]). The dialog then never says the order hasn't gone through: it
  /// says it may have, points at Orders, and offers the queue as sending it again — which the
  /// server answers with the existing order if there is one. The queued checkout carries the same
  /// knowledge, as [PendingOrder.maybePlaced].
  ///
  /// What is queued is this exact [submission] — the key of the attempt that just went unanswered —
  /// so if that attempt did reach the server, the outbox's send is answered with the order it placed
  /// instead of placing another. It carries the total on this screen's button as the total the
  /// customer agreed to; if the server's is different when it is sent, the customer is asked again.
  /// The basket is cleared, and the attempt handed to the outbox, only once the checkout is safely
  /// written to the phone.
  Future<void> _offerToQueue(OrderSubmission submission, {required bool unconfirmed}) async {
    final OrderOutbox? outbox = widget.outbox;
    if (outbox == null) return;
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String? refusal = _whyItCannotWait(submission, t);
    final bool queueable = refusal == null;
    // Read before the dialog: the area's terms can land while it is up, and what is queued must be
    // the total the customer tapped on.
    final double? expectedTotal = _assertableTotal;
    final String explanation =
        refusal ?? (unconfirmed ? t.offlineQueueResendBody : t.offlineQueueBody);
    const TextStyle bodyStyle = TextStyle(fontSize: 14, color: DeliveryColors.muted, height: 1.4);

    final bool? queue = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: DeliveryColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
        title: Text(unconfirmed ? t.offlineUnconfirmedTitle : t.offlineQueueTitle,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: DeliveryColors.ink)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // What matters most when it is true, so it comes first: the order may exist already.
            if (unconfirmed) ...<Widget>[
              Text(t.offlineUnconfirmedLead,
                  style: bodyStyle.copyWith(
                      color: DeliveryColors.ink, fontWeight: FontWeight.w600)),
              const SizedBox(height: DeliverySpacing.sm),
            ],
            Text(explanation, style: bodyStyle),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(foregroundColor: DeliveryColors.muted),
            child: Text(queueable ? t.notNow : t.close),
          ),
          if (queueable)
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: DeliveryColors.brand,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DeliveryRadius.md)),
              ),
              child: Text(t.offlineQueueAction),
            ),
        ],
      ),
    );
    if (queue != true || !mounted) return;

    final PendingOrder pending = PendingOrder(
      submission: submission,
      // The total Order Manager will charge, as far as anything on the phone can know — so a
      // PRICE_CHANGED later means a price really changed.
      expectedTotal: expectedTotal!,
      storeId: widget.cart.storeId,
      storeName: widget.cart.store?.name ?? '',
      splitUsd: _splitUsdValue,
      createdAt: DateTime.now(),
      maybePlaced: unconfirmed,
    );
    try {
      await outbox.enqueue(pending);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t.offlineQueueSaveFailed)));
      }
      return;
    }
    // The outbox carries the attempt, key and all, from here; the basket starts a new one.
    widget.cart.settleCheckout();
    if (!mounted) return;
    Navigator.of(context).pop(pending);
  }

  /// Why this checkout cannot wait for the connection, in the customer's words — or null when it
  /// can.
  ///
  /// * From several shops: its orders are placed together, as one checkout, while online.
  /// * Not cash: a card or wallet hold needs the payment provider while the customer waits.
  /// * Split with friends: the plan closes over its order the moment it exists, which the outbox
  ///   does not do.
  /// * Without the server's quote for this checkout, anything the phone cannot price exactly as
  ///   Order Manager will ([_assertableTotal]): EXPRESS, whose premium is server configuration; an
  ///   area whose fee it never learned; a promo quoted at another fee. Queued, those would come back
  ///   PRICE_CHANGED although nothing had changed. With the quote, the total is the server's own.
  String? _whyItCannotWait(OrderSubmission submission, DeliveryStrings t) {
    // First, because nothing else could make it queueable: a basket from several shops is placed as
    // one checkout of several orders, which the outbox — one order per queued item — does not send.
    // Refused whole rather than queued shop by shop, which could place part of the basket.
    if (widget.cart.isMultiShop) return t.multiCartCannotWait;
    if (submission.paymentMethod != PaymentMethod.cash) return t.offlineQueueCashOnly;
    // After cash: a split basket already pays cash, and telling its host to "choose cash" would be
    // advice they cannot follow.
    if (widget.cart.splitPlanId != null) return t.offlineQueueUnavailable;
    // With the server's quote for exactly this checkout, its total — Express premium, area fee and
    // code included — is known, and it is the total the queue asserts.
    if (_quotedTotal != null) return null;
    if (submission.deliveryTier != DeliveryTier.standard) return t.offlineQueueStandardOnly;
    if (_assertableTotal == null) return t.offlineQueueTotalUnknown;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<CartLine> lines = widget.cart.lines;

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(
        title: t.checkout,
        onBack: () => Navigator.of(context).maybePop(),
        backSemanticLabel: t.back,
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(DeliverySpacing.lg),
              children: <Widget>[
                _rateBanner(t),
                const SizedBox(height: _sectionGap),
                _addressSection(t),
                const SizedBox(height: _sectionGap),
                _tierSection(t),
                const SizedBox(height: _sectionGap),
                _paymentSection(t),
                const SizedBox(height: _sectionGap),
                Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _notesSection(t),
                      const SizedBox(height: _sectionGap),
                      // Not drawn in the redesign, kept because the order carries it: a rider with
                      // no number to ring has to guess at a closed door. Written in the design's
                      // own section language rather than as a leftover Material field.
                      _fieldSection(
                        title: t.contactPhoneOptional,
                        child: TextFormField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          style: _fieldTextStyle,
                          decoration: _boxDecoration(t.contactPhoneOptional),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: DeliverySpacing.sm),
              ],
            ),
          ),
          _summaryBar(t, lines),
        ],
      ),
    );
  }

  /// 20px between top-level body sections, per the frame.
  static const double _sectionGap = 20;

  static const TextStyle _fieldTextStyle =
      TextStyle(fontSize: 13, color: DeliveryColors.ink, height: 1.4);

  /// The design's plain input box: white, 1px [DeliveryColors.border], radius 12, 12px padding,
  /// 13px placeholder in [DeliveryColors.faint].
  InputDecoration _boxDecoration(String hint) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: DeliveryColors.white,
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: DeliveryColors.faint, height: 1.4),
      contentPadding: const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
      border: border(DeliveryColors.border, 1),
      enabledBorder: border(DeliveryColors.border, 1),
      focusedBorder: border(DeliveryColors.brand, 1.5),
      errorBorder: border(DeliveryAccent.critical.color, 1),
      focusedErrorBorder: border(DeliveryAccent.critical.color, 1.5),
    );
  }

  // ------------------------------------------------------------------ section 1: where it goes

  Widget _addressSection(DeliveryStrings t) {
    final List<DeliveryAddress> saved = widget.addresses.recents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Title row: heading on the start side, the add action on the end — the design's inline
        // brand text link rather than a button, at SemiBold 13.
        YdSectionHeader(
          title: t.deliveryAddress,
          fontSize: 15,
          trailing: Semantics(
            button: true,
            child: InkWell(
              onTap: _addAddress,
              borderRadius: BorderRadius.circular(DeliveryRadius.sm),
              child: Padding(
                padding: const EdgeInsetsDirectional.all(DeliverySpacing.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.add_rounded, size: 14, color: DeliveryColors.brand),
                    const SizedBox(width: 2),
                    Text(
                      t.addANewAddress,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: DeliveryColors.brand,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        if (saved.isEmpty)
          // Nothing saved yet: the one card is the way to make one, so it says so rather than
          // showing an empty section with an action hidden in the title row.
          YdCard(
            onTap: _addAddress,
            child: Row(
              children: <Widget>[
                const Icon(Icons.add_location_alt_outlined,
                    size: 20, color: DeliveryColors.brand),
                const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
                Expanded(
                  child: Text(
                    t.chooseAnAddress,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: DeliveryColors.ink,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          for (int i = 0; i < saved.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            _addressCard(saved[i]),
          ],
      ],
    );
  }

  /// One saved address as the design's radio card: 16px padding, radius 16, a 20px radio with a
  /// 2px ring and a 10px dot when chosen, then a bold label over a 12px detail line.
  Widget _addressCard(DeliveryAddress address) {
    final bool selected = address.line == _addressLine;
    final String detail = _detail(address);

    return Semantics(
      selected: selected,
      button: true,
      child: YdCard(
        onTap: () => _choose(address.line),
        child: Row(
          children: <Widget>[
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? DeliveryColors.brand : DeliveryColors.border,
                  width: 2,
                ),
              ),
              child: selected
                  ? Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: DeliveryColors.brand,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    address.label == null || address.label!.isEmpty
                        ? address.line
                        : address.label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: DeliveryColors.ink,
                      height: 1.25,
                    ),
                  ),
                  if (detail.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: DeliveryColors.muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The street, area and door notes behind an address — everything the bold label does not carry.
  String _detail(DeliveryAddress address) => <String>[
        if (address.label != null && address.label!.isNotEmpty) address.line,
        if (address.zoneName != null && address.zoneName!.isNotEmpty) address.zoneName!,
        if (address.notes != null && address.notes!.isNotEmpty) address.notes!,
      ].join(' · ');

  // ------------------------------------------------------------------ section 2: how fast

  /// The delivery tier: the same two-up card strip the payment section uses, because it is the
  /// same kind of decision — one of a short list, made once, in the same geometry.
  ///
  /// Express carries a caption saying a surcharge applies rather than a figure. The premium is a
  /// server config value snapshotted at placement and no endpoint publishes it beforehand, so the
  /// amount appears where the server first states it: on the receipt, itemised as its own line.
  Widget _tierSection(DeliveryStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          t.custDeliverySpeed,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
            height: 1.25,
          ),
        ),
        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (int i = 0; i < _tiers.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: _payCard(
                  icon: _tiers[i] == DeliveryTier.express
                      ? Icons.bolt_rounded
                      : Icons.schedule_rounded,
                  label: _tiers[i] == DeliveryTier.express
                      ? t.deliveryTierExpress
                      : t.deliveryTierStandard,
                  caption: _tiers[i] == DeliveryTier.express
                      ? t.custExpressSurchargeApplies
                      : null,
                  selected: _tier == _tiers[i],
                  onTap: () {
                    setState(() => _tier = _tiers[i]);
                    // Express changes the total by its premium; the quote says by how much.
                    _askForQuote();
                  },
                ),
              ),
            ],
          ],
        ),
        if (_tier == DeliveryTier.express) ...<Widget>[
          const SizedBox(height: DeliverySpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.info_outline, size: 14, color: DeliveryColors.muted),
              const SizedBox(width: DeliverySpacing.xs + 2),
              Expanded(
                child: Text(
                  t.custExpressNote,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DeliveryColors.muted,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ------------------------------------------------------------------ section 3: how it is paid

  /// The payment strip: equal cards in the design's geometry, cash first.
  ///
  /// Card and wallet are selectable and authorise against the DEV payment provider — no real
  /// money moves — so each carries a "Test payment" caption, and choosing one puts the fuller
  /// sentence under the strip. Presenting a dev authorisation as a live charge would be a lie
  /// told in the shape of a feature; presenting it as a test payment is exactly what a tester
  /// needs.
  /// The current LBP-per-USD figure the screen renders with: the transfer service's LOCKED rate
  /// when it answered, the display rate until then.
  double get _lbpRate => _rate?.lbpPerUsd ?? MarketRates.instance.lbpPerUsd;

  /// The frame's amber lock banner: the platform rate, promised.
  Widget _rateBanner(DeliveryStrings t) {
    final double rate = _lbpRate;
    if (rate <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF3D7),
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        border: Border.all(color: const Color(0xFFF2DFA4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.lock_rounded, size: 18, color: Color(0xFFB8860B)),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  t.custPlatformRate(_groupLbp(rate)),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t.custRateLocked,
                  style: const TextStyle(
                      fontSize: 11.5, color: DeliveryColors.muted, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _groupLbp(double amount) {
    final String digits = amount.round().toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  /// What delivery adds on this screen: nothing when an offer waives it; otherwise the fee Order
  /// Manager will charge when this phone knows it, and the shop's flat fee when it does not.
  ///
  /// With a promo code, the flat fee stays. The basket had the server quote the code against the
  /// fee it knew, and the code is only known to be worth that at that fee: a free-delivery code is
  /// worth the whole fee, whatever it is. Setting another fee beside that quote would mix two prices
  /// into a total neither of them gives — and such a checkout is not queued ([_assertableTotal]).
  double get _deliveryFeeCharged {
    if (widget.cart.deliveryIsFree) return 0;
    final double? fee = _serverDeliveryFee;
    if (fee == null || widget.promo != null) return widget.cart.deliveryFee;
    return fee;
  }

  /// The server's total for this checkout as it stands — when it has answered this very question and
  /// would accept the checkout.
  double? get _quotedTotal {
    final BasketQuote? quote = _quoter.quote;
    return quote != null && quote.placeable ? quote.totalAmount : null;
  }

  /// The total on the summary bar and the button: the server's quote — kept on screen while a newer
  /// one is on its way — or, without one, what the phone reckons for a one-shop basket. Null for a
  /// basket from several shops the server has not priced: a sum of shop cards' fees is not its total.
  double? get _displayTotal {
    final double? shown = _quoter.shown?.totalAmount;
    if (shown != null) return shown;
    return widget.cart.isMultiShop ? null : _orderTotal;
  }

  /// What the phone reckons the total is without the server: the goods and [_deliveryFeeCharged],
  /// less the basket's code. The fallback for [_displayTotal], and the base of [_assertableTotal].
  double get _orderTotal {
    final double promoDiscount = widget.promo?.discount ?? 0;
    return (widget.cart.subtotal + _deliveryFeeCharged - promoDiscount)
        .clamp(0, double.infinity)
        .toDouble();
  }

  /// The total a queued checkout may assert as the one the customer agreed to — or null when this
  /// phone cannot price it exactly as Order Manager will, in which case it is not queued.
  ///
  /// The server's quote for this very checkout is exactly that, and wins whenever there is one. Only
  /// without it does the rest of this apply.
  ///
  /// Three things must be known. The tier's premium: STANDARD carries none, and the EXPRESS
  /// surcharge is never published before an order exists. The delivery fee: [_serverDeliveryFee].
  /// And that this screen's total is built on that fee — which, with a promo quoted at a different
  /// one, it is not (see [_deliveryFeeCharged]).
  double? get _assertableTotal {
    final double? quoted = _quotedTotal;
    if (quoted != null) return quoted;
    if (widget.cart.isMultiShop) return null;
    if (_tier != DeliveryTier.standard) return null;
    final double? fee = _serverDeliveryFee;
    if (fee == null) return null;
    final double charged = widget.cart.deliveryIsFree ? 0 : fee;
    if (_cents(charged) != _cents(_deliveryFeeCharged)) return null;
    return _orderTotal;
  }

  static int _cents(double amount) => (amount * 100).round();

  /// The USD half of the cash split: what was typed, clamped into [0, total]. Blank = all USD.
  double get _splitUsdValue {
    final double total = _displayTotal ?? _orderTotal;
    final double typed = double.tryParse(_splitUsd.text.trim()) ?? total;
    return typed.clamp(0, total).toDouble();
  }

  /// The frame's Lebanese Split Payment card, drawn for cash only — a wallet transfer has no
  /// notes to mix. USD side is typed; the lira side is COMPUTED at the locked rate, because two
  /// editable halves that must sum is an argument waiting to happen.
  Widget _splitCard(DeliveryStrings t) {
    final double total = _displayTotal ?? _orderTotal;
    final double rate = _lbpRate;
    if (total <= 0 || rate <= 0) return const SizedBox.shrink();
    final double usdPart = _splitUsdValue;
    final double lbpInUsd = total - usdPart;
    final double lbpFace = (lbpInUsd * rate / 1000).round() * 1000;
    final int pctUsd = total == 0 ? 100 : ((usdPart / total) * 100).round();

    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            t.custSplitPayment,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            t.custSplitBlurb,
            style: const TextStyle(
                fontSize: 12.5, color: DeliveryColors.muted, height: 1.4),
          ),
          const SizedBox(height: DeliverySpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      t.custPayInUsd,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DeliveryColors.muted,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _splitUsd,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixText: '\$ ',
                        hintText: total.toStringAsFixed(2),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DeliverySpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      t.custPayInLbp,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DeliveryColors.muted,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: lbpInUsd > 0
                                ? DeliveryColors.brand
                                : DeliveryColors.border),
                        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                      ),
                      child: Text(
                        'LBP ${_groupLbp(lbpFace)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: lbpInUsd > 0
                              ? DeliveryColors.brand
                              : DeliveryColors.faint,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md),
          Row(
            children: <Widget>[
              Text(
                t.custPctUsd(pctUsd),
                style: const TextStyle(
                    fontSize: 11, color: DeliveryColors.faint, height: 1.2),
              ),
              const Spacer(),
              Text(
                t.custPctLbp(100 - pctUsd),
                style: const TextStyle(
                    fontSize: 11, color: DeliveryColors.faint, height: 1.2),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 1 : usdPart / total,
              minHeight: 6,
              backgroundColor: DeliveryColors.brandSoft,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(DeliveryColors.brand),
            ),
          ),
          if ((_rate?.riderChangeLimitLbp ?? 0) > 0) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsetsDirectional.all(DeliverySpacing.sm + 2),
              decoration: BoxDecoration(
                color: DeliveryColors.brandSoft,
                borderRadius: BorderRadius.circular(DeliveryRadius.sm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.payments_outlined,
                      size: 15, color: DeliveryColors.brand),
                  const SizedBox(width: DeliverySpacing.sm),
                  Expanded(
                    child: Text(
                      t.custRiderChange(
                          _groupLbp(_rate!.riderChangeLimitLbp)),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: DeliveryColors.brand,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _paymentSection(DeliveryStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          t.custLocalPaymentMethods,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
            height: 1.25,
          ),
        ),
        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        // The frame's rows with radio circles: cash first, then whichever wallet transfers a
        // connector will actually carry. Whish/OMT ride the dev provider's order rail while the
        // transfer ledger records the real instrument — the test note below says so.
        _methodRow(
          t,
          icon: Icons.payments_outlined,
          label: t.custCashUsdLbp,
          selected: _payment == PaymentMethod.cash,
          onTap: () => setState(() {
            _payment = PaymentMethod.cash;
            _walletChoice = null;
          }),
        ),
        if (_walletMethods.contains('WHISH')) ...<Widget>[
          const SizedBox(height: DeliverySpacing.sm),
          _methodRow(
            t,
            icon: Icons.account_balance_wallet_outlined,
            label: t.custWhishTransfer,
            selected: _walletChoice == 'WHISH',
            onTap: () => setState(() {
              _payment = PaymentMethod.wallet;
              _walletChoice = 'WHISH';
            }),
          ),
        ],
        if (_walletMethods.contains('OMT')) ...<Widget>[
          const SizedBox(height: DeliverySpacing.sm),
          _methodRow(
            t,
            icon: Icons.currency_exchange,
            label: t.custOmtTransfer,
            selected: _walletChoice == 'OMT',
            onTap: () => setState(() {
              _payment = PaymentMethod.wallet;
              _walletChoice = 'OMT';
            }),
          ),
        ],
        if (_payment == PaymentMethod.cash && !widget.cart.isMultiShop) ...<Widget>[
          const SizedBox(height: DeliverySpacing.md),
          _splitCard(t),
        ],
        if (_payment.needsProvider) ...<Widget>[
          const SizedBox(height: DeliverySpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.science_outlined, size: 14, color: DeliveryColors.muted),
              const SizedBox(width: DeliverySpacing.xs + 2),
              Expanded(
                child: Text(
                  t.paymentTestModeNote,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DeliveryColors.muted,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _methodRow(DeliveryStrings t,
      {required IconData icon,
      required String label,
      required bool selected,
      required VoidCallback onTap}) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? DeliveryColors.brand : DeliveryColors.border,
                width: selected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
            ),
            child: Row(
              children: <Widget>[
                Icon(icon,
                    size: 20,
                    color:
                        selected ? DeliveryColors.brand : DeliveryColors.muted),
                const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected ? DeliveryColors.ink : DeliveryColors.muted,
                      height: 1.25,
                    ),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected ? DeliveryColors.brand : DeliveryColors.faint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _payCard({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback? onTap,
    String? caption,
  }) {
    final Color foreground = selected ? DeliveryColors.ink : DeliveryColors.muted;

    return Semantics(
      button: onTap != null,
      selected: selected,
      child: Material(
        color: DeliveryColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          side: BorderSide(
            color: selected ? DeliveryColors.brand : DeliveryColors.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: DeliverySpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: foreground,
                          height: 1.2,
                        ),
                      ),
                      if (caption != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: DeliveryColors.faint,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ section 4: the note

  Widget _notesSection(DeliveryStrings t) {
    return _fieldSection(
      title: t.custOrderNotes,
      child: TextFormField(
        controller: _notes,
        maxLines: 3,
        minLines: 2,
        style: _fieldTextStyle,
        decoration: _boxDecoration(t.custOrderNotesHint),
      ),
    );
  }

  Widget _fieldSection({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
            height: 1.25,
          ),
        ),
        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        child,
      ],
    );
  }

  // ------------------------------------------------------------------ the sticky summary

  Widget _summaryBar(DeliveryStrings t, List<CartLine> lines) {
    // The same total the button carries: the server's quote for this checkout, or the phone's own
    // reckoning while it has none — a dash for a basket from several shops. The server recomputes at
    // placement and the confirmation shows ITS total.
    final double? payable = _displayTotal;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(top: BorderSide(color: DeliveryColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(DeliverySpacing.lg),
          child: Row(
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    t.custTotalPrice,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DeliveryColors.faint,
                      height: 1.3,
                    ),
                  ),
                  Text(
                    payable == null ? '—' : payable.toStringAsFixed(2),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: DeliveryColors.brand,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              YdPillButton(
                // The frame prints the total on the button.
                label: payable == null
                    ? t.checkout
                    : t.custPlaceOrderAmount('\$${payable.toStringAsFixed(2)}'),
                expand: false,
                busy: _placing,
                onPressed: _placing || lines.isEmpty ? null : _place,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
