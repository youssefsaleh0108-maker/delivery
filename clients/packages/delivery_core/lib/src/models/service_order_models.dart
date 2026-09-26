/// The service-order half of the Order Manager contract: what kind of order it is, how the customer
/// gets it, why a provider declined it, why the server refused it, and the terms its line was
/// ordered on.
///
/// Its own file for the reason gifts have one: an order carries all of these, but none of them is
/// about orders in general, and the screens that read them are the provider's and the Services tab's.
library;

import 'catalog_models.dart';

/// What kind of thing an order is, mirroring `com.delivery.order.domain.OrderKind`.
///
/// Read from the order rather than inferred from what it lacks: an errand has no merchant and no
/// lines, but so would a corrupt basket, and the two must not render alike.
enum OrderKind {
  /// A basket from a shop. Also what an order that does not say is: the server has sent a kind on
  /// every order since errands existed, and every order before them was a basket.
  catalog('CATALOG'),

  /// An errand where the rider buys something and is paid back for it.
  butlerBuy('BUTLER_BUY'),

  /// An errand where nothing is bought.
  butlerSend('BUTLER_SEND'),

  /// Work a services shop makes to order — a print run, an alteration, a repair. Exactly one line, a
  /// [Fulfilment] the customer chose, acceptance straight into production, and a shop that may
  /// decline.
  service('SERVICE'),

  /// Sent from a table in the shop's own room by a diner with no account: they scanned the card on
  /// the table, the menu opened in their browser, and they sent. Eaten where it was ordered.
  ///
  /// A kind of its own rather than a flag on [catalog], and the reason is money. The platform lent
  /// the restaurant an order pad; it did not sell the meal, carry it or collect for it, so this is
  /// the one kind that books nothing at all — no delivery fee, no rider fee, no commission. The
  /// server makes that a property of the kind (`OrderKind.settles()`) so settlement asks one
  /// question and gets one answer, and no screen here may imply otherwise.
  table('TABLE'),

  /// A kind this build does not know. Never read as one of the others — a new kind shown as a basket
  /// would get a basket's screens — and never sent.
  unknown(null);

  const OrderKind(this.wire);

  /// The server's spelling; null for [unknown].
  final String? wire;

  /// Whether nobody sold the goods: an errand the rider runs, which has no shop and so no shop's
  /// share of anything.
  bool get isErrand => this == butlerBuy || this == butlerSend;

  /// Whether the platform books anything for an order of this kind — mirroring
  /// `OrderKind.settles()`.
  ///
  /// False for exactly one kind. Asked here rather than compared against [table] wherever somebody
  /// remembers to, because "does money move" is the rule a later change is most likely to break by
  /// adding a total that quietly includes a ticket the platform is not a party to.
  bool get settles => this != table;

  /// [catalog] when the server sent no kind; [unknown] when it sent one this build does not know.
  static OrderKind fromWire(Object? value) {
    if (value == null) {
      return OrderKind.catalog;
    }
    for (final OrderKind kind in values) {
      if (kind.wire != null && kind.wire == value) {
        return kind;
      }
    }
    return OrderKind.unknown;
  }
}

/// How the customer gets an order, mirroring `com.delivery.order.domain.Fulfilment`.
///
/// Not [ServiceFulfilment], which is what an offer is sold with and can be both: an order is one or
/// the other, chosen when it was placed, and never changes.
enum Fulfilment {
  /// Carried to the customer's door by a rider. Every order that is not a service order, and what an
  /// order that does not say is — which every order placed before pickups existed does not.
  delivery('DELIVERY'),

  /// Collected by the customer at the shop that made it. Only ever a service order: no rider, no fee,
  /// no address and nothing to track, and it ends when the shop marks it collected.
  pickup('PICKUP'),

  /// Eaten at the table it was ordered from. Only ever an [OrderKind.table] order.
  ///
  /// Nobody fetches it and nobody carries it: the diner is already in the room and the food crosses
  /// the floor. It shares every structural absence with a [pickup] — no address, no pin, no area, no
  /// fee, no rider, no carrier, never picked up — but it is a separate value because a cash pickup
  /// means the shop is holding notes the platform is owed a commission on, and a table order owes the
  /// platform nothing. Two names, so that rule can never be read off the wrong one.
  dineIn('DINE_IN'),

  /// A fulfilment this build does not know. Neither a pickup nor a delivery, so no screen offers a
  /// counter's actions or a rider's tracking for it; and never sent.
  unknown(null);

  const Fulfilment(this.wire);

  /// The server's spelling; null for [unknown].
  final String? wire;

  /// Whether a rider carries it — what puts an order on a job board and gives it a carrier.
  ///
  /// The question every control that assumes a rider should ask, rather than testing for [delivery]:
  /// a pickup and a table order are both fetched by somebody already at the shop, and neither has a
  /// rider to show, claim, track or chase.
  bool get isCarried => this == delivery;

  /// Whether whoever eats it is already at the shop, which is what decides who ends the order —
  /// mirroring `Fulfilment.isCollectedInPerson()`.
  bool get isCollectedInPerson => this == pickup || this == dineIn;

  /// [delivery] when the server sent none; [unknown] for a value this build does not know.
  static Fulfilment fromWire(Object? value) {
    if (value == null) {
      return Fulfilment.delivery;
    }
    for (final Fulfilment fulfilment in values) {
      if (fulfilment.wire != null && fulfilment.wire == value) {
        return fulfilment;
      }
    }
    return Fulfilment.unknown;
  }
}

/// Why a provider declined a service order: the picklist its Decline sheet offers, mirroring
/// `com.delivery.order.domain.DeclineReason`.
///
/// A code rather than the provider's words, because the customer reading it may read Arabic while the
/// provider tapped an English label, and free text on a refusal is where rudeness gets in. The order
/// stores it as its cancel reason, `PROVIDER_DECLINED: TOO_BUSY`, which [fromCancelReason] reads back.
enum DeclineReason {
  /// "Too busy right now".
  tooBusy('TOO_BUSY'),

  /// "We can't do this job".
  cannotDo('CANNOT_DO'),

  /// "Problem with the file".
  fileProblem('FILE_PROBLEM'),

  /// "Other".
  other('OTHER'),

  /// A decline whose code this build does not know. Still a decline — the shop did decline — only not
  /// one whose reason this build can name. Never sent.
  unknown(null);

  const DeclineReason(this.wire);

  /// The server's spelling; null for [unknown].
  final String? wire;

  /// What every provider decline's cancel reason starts with.
  static const String cancelReasonPrefix = 'PROVIDER_DECLINED';

  /// What a Decline sheet offers, in the server's order: every reason but [unknown].
  static final List<DeclineReason> picklist = List<DeclineReason>.unmodifiable(
      values.where((DeclineReason reason) => reason != unknown));

  /// [unknown] for anything that is not one of the picklist's codes.
  static DeclineReason fromWire(Object? value) {
    for (final DeclineReason reason in values) {
      if (reason.wire != null && reason.wire == value) {
        return reason;
      }
    }
    return DeclineReason.unknown;
  }

  /// The decline an order's cancel reason records, or null when the order was not declined.
  ///
  /// Only Order Manager writes a reason that starts with [cancelReasonPrefix]: it refuses anybody's
  /// own words that do (RESERVED_CANCEL_REASON). So a reason that starts with it is a provider's
  /// decline whatever follows — the code when this build knows it, [unknown] when it does not.
  static DeclineReason? fromCancelReason(String? reason) {
    final String text = reason?.trim() ?? '';
    if (!text.toUpperCase().startsWith(cancelReasonPrefix)) {
      return null;
    }
    final String rest = text.substring(cancelReasonPrefix.length).trim();
    final String code = rest.startsWith(':') ? rest.substring(1).trim() : rest;
    return fromWire(code.toUpperCase());
  }

  /// The cancel reason this decline is sent as — `PROVIDER_DECLINED: TOO_BUSY`, the spelling Order
  /// Manager stores and every reader of the order recognises.
  ///
  /// Throws a [StateError] for [unknown]: there is no true reason to send for it.
  String get cancelReason {
    final String? code = wire;
    if (code == null) {
      throw StateError('A decline reason this app does not know cannot be sent.');
    }
    return '$cancelReasonPrefix: $code';
  }
}

/// Why Order Manager refused a service order, or refused to move one: the `code` on its 422.
///
/// Mirrors `ServiceOrderRefusedException.Refusal`, the attachment gate's one code for files that
/// cannot go with an order yet, and the order attachment service's `Refusal` — whose twelve codes
/// refuse a file a placement names just as they refuse its upload, so the words a screen has for an
/// upload's refusal fit a placement's too. A screen says each in the reader's own language; the
/// server's English sentence is for logs.
enum ServiceOrderRefusal {
  /// More than one line: a service is ordered one at a time.
  oneServiceAtATime('ONE_SERVICE_AT_A_TIME'),

  /// A quantity outside 1 to 99 packs.
  packsOutOfRange('PACKS_OUT_OF_RANGE'),

  /// A way of getting the work the offer is not sold with.
  fulfilmentNotOffered('FULFILMENT_NOT_OFFERED'),

  /// Pickup, files or instructions on an order for goods.
  notAServiceOrder('NOT_A_SERVICE_ORDER'),

  /// Express: a service order is made to its turnaround and delivered on the standard tier.
  standardOnly('STANDARD_ONLY'),

  /// Gift details on a service order.
  notGiftable('NOT_GIFTABLE'),

  /// A payment method other than cash.
  cashOnly('CASH_ONLY'),

  /// A service offer in a multi-shop checkout, or in a quote of several lines.
  notInBasket('NOT_IN_BASKET'),

  /// A merchant entering a service order on a customer's behalf.
  notOnBehalf('NOT_ON_BEHALF'),

  /// The shop is filed under a service category that is closed.
  categoryClosed('CATEGORY_CLOSED'),

  /// The offer cannot be ordered as it stands: it and its shop disagree, or it promises no turnaround.
  offerNotOrderable('OFFER_NOT_ORDERABLE'),

  /// A decline without a reason from the picklist.
  declineReasonRequired('DECLINE_REASON_REQUIRED'),

  /// "Collected" asked of an order that is not a pickup waiting at the counter — most often one that
  /// another device at the counter already marked collected. Read the order again.
  notCollectable('NOT_COLLECTABLE'),

  /// A shop cancelling an uncollected pickup before the customer's time to collect is up. The order's
  /// `uncollectedCancellableAt` says when it will be.
  uncollectedTooSoon('UNCOLLECTED_TOO_SOON'),

  /// A cancel reason that begins with a code only Order Manager writes. From a provider's app this is
  /// a decline that a server from before [notDeclinable] refused for an order no longer new —
  /// accepted meanwhile, say — so read it again.
  reservedCancelReason('RESERVED_CANCEL_REASON'),

  /// A decline sent for an order that can no longer be declined: accepted meanwhile, by another
  /// device at the counter, say. Read the order again.
  notDeclinable('NOT_DECLINABLE'),

  /// Files cannot go with an order yet, so an offer that needs one cannot be ordered.
  attachmentsUnavailable('ATTACHMENTS_UNAVAILABLE'),

  // A file the order names, refused with the code the order attachment service gives it
  // (`OrderAttachmentService.Refusal`): the wire values of delivery_core's `AttachmentRefusal`.

  /// A file that is not a PDF, JPEG or PNG.
  fileWrongType('WRONG_TYPE'),

  /// A file with no bytes at all.
  fileEmpty('EMPTY'),

  /// A file over the size limit.
  fileTooLarge('TOO_LARGE'),

  /// The customer already holds as many uploads waiting for an order as the server allows.
  tooManyFilesWaiting('TOO_MANY_WAITING'),

  /// A file whose upload never arrived in full: upload it again.
  fileNotUploaded('NOT_UPLOADED'),

  /// A file deleted because it was not ordered in time: upload it again.
  fileExpired('EXPIRED'),

  /// A file already on an order.
  fileAlreadyAttached('ALREADY_ATTACHED'),

  /// More files than one order may carry.
  tooManyFiles('TOO_MANY_FILES'),

  /// The same file named twice.
  duplicateFile('DUPLICATE_FILE'),

  /// Files named for an offer that takes none.
  filesNotAccepted('NOT_ACCEPTED'),

  /// No file named for an offer that needs one.
  fileRequired('REQUIRED'),

  /// A file that is not the customer's own, or does not exist: one answer for both.
  unknownFile('UNKNOWN_FILE'),

  /// A code this build does not know. Still a refusal — nothing was placed or moved — and
  /// [ServiceRefusalOutcome.code] keeps the server's spelling of it.
  unknown(null);

  const ServiceOrderRefusal(this.wire);

  /// The server's spelling; null for [unknown].
  final String? wire;

  /// The refusal [code] names, or null when it names none this build knows.
  static ServiceOrderRefusal? maybeFromWire(Object? code) {
    for (final ServiceOrderRefusal refusal in values) {
      if (refusal.wire != null && refusal.wire == code) {
        return refusal;
      }
    }
    return null;
  }
}

/// What every refused outcome of a service-order call carries — a placement's, a quote's, a provider's
/// step's — so one piece of a screen can put any of them into words.
abstract interface class ServiceRefusalOutcome {
  /// Why, as this build can name it.
  ServiceOrderRefusal get refusal;

  /// The code exactly as the server sent it: what a screen has to go on when [refusal] is
  /// [ServiceOrderRefusal.unknown].
  String get code;

  /// The server's English sentence, when it sent one. For logs and a client with no words of its
  /// own; never parsed, and never what a translated screen shows.
  String? get detail;
}

/// A service line's terms as they stood when the order was placed — Order Manager's
/// `ServiceLineResponse` — and how many packs were ordered.
///
/// A snapshot, not the offer: a provider editing the offer tomorrow changes nothing an order already
/// promised, so an order's screens read these rather than the product's current [ServiceTerms].
/// Parsed as those terms are: a term this build does not know reads as unknown, a number the server
/// did not send stays null so a screen shows a dash, and a pack is at least one unit.
class ServiceOrderLine {
  const ServiceOrderLine({
    required this.packs,
    required this.pricingType,
    required this.attachmentPolicy,
    this.unitSize = 1,
    this.unitLabel,
    this.turnaroundMinHours,
    this.turnaroundMaxHours,
    this.instructionsPrompt,
    this.instructions,
  });

  /// How many packs were ordered: the line's quantity, 1 to 99.
  final int packs;

  /// Units in one pack: 500 cards.
  final int unitSize;

  /// What one unit is called ("cards", "sqm"); null for a single unit sold at a fixed price.
  final String? unitLabel;

  final ServicePricingType pricingType;

  /// The turnaround promised, in whole hours. What the customer is told to expect once the order is
  /// accepted is the order's own `estimatedReadyAt`, which the server stamped — not hours added up on
  /// the phone.
  final int? turnaroundMinHours;
  final int? turnaroundMaxHours;

  final ServiceAttachmentPolicy attachmentPolicy;

  /// The question the provider put to the customer beside the instructions.
  final String? instructionsPrompt;

  /// What the customer told the provider about the work. **Null unless the caller may read it** —
  /// the shop, the customer and support, never a rider — and null when they wrote nothing.
  final String? instructions;

  /// Units ordered: [packs] × [unitSize]. Two packs of 500 is 1,000 cards.
  int get units => packs * unitSize;

  /// The snapshot, or null when [json] is not one: a goods line carries none. [packs] is the line's
  /// quantity.
  static ServiceOrderLine? maybeFromJson(Object? json, {required int packs}) {
    if (json is! Map) {
      return null;
    }
    final int? size = _intOrNull(json['unitSize']);
    return ServiceOrderLine(
      packs: packs,
      pricingType: ServicePricingType.fromWire(json['pricingType']),
      unitSize: size == null || size < 1 ? 1 : size,
      unitLabel: _textOrNull(json['unitLabel']),
      turnaroundMinHours: _intOrNull(json['turnaroundMinHours']),
      turnaroundMaxHours: _intOrNull(json['turnaroundMaxHours']),
      attachmentPolicy: ServiceAttachmentPolicy.fromWire(json['attachmentPolicy']),
      instructionsPrompt: _textOrNull(json['instructionsPrompt']),
      instructions: _textOrNull(json['instructions']),
    );
  }
}

int? _intOrNull(Object? value) => value is num ? value.toInt() : null;

String? _textOrNull(Object? value) => value is String && value.trim().isNotEmpty ? value : null;
