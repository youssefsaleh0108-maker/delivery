/// The till — pos-service (`/api/pos`).
///
/// A walk-in sale is not a delivery order and is modelled separately: it has no address, no rider
/// and no lifecycle beyond "rung up", but it does have tenders, change, a drawer and a receipt
/// number, none of which an order has.
///
/// **Money law.** Every USD figure is [Money] — the server's own 2-decimal string, never parsed to
/// a double. LBP figures are `int`, and so is `lbpPerUsd`. Every settled artifact ([PosSale],
/// [PosReceipt], [PosShift]) carries the rate it was rung at, and screens render THAT: a reprint
/// must agree with the drawer even after the platform rate moves. `MarketRates` is permitted only
/// on a still-open cart preview, where there is no settled figure to disagree with.
///
/// **Action law.** Buttons are drawn from [PosSale.availableActions], never re-derived from the
/// status. The server decides whether a sale can still be voided (its shift may have closed since)
/// and the client would get that wrong.
library;

import 'statement_models.dart';
import 'store_models.dart';

/// Where a sale is in its short life.
enum PosSaleStatus {
  open('OPEN', 'Open'),
  completed('COMPLETED', 'Completed'),
  voided('VOIDED', 'Voided'),
  partiallyRefunded('PARTIALLY_REFUNDED', 'Partly refunded'),
  refunded('REFUNDED', 'Refunded');

  const PosSaleStatus(this.wireValue, this.label);

  final String wireValue;
  final String label;

  /// Unknown statuses read as [open] — the state with the fewest destructive affordances.
  static PosSaleStatus fromWire(String? value) {
    for (final PosSaleStatus status in PosSaleStatus.values) {
      if (status.wireValue == value) {
        return status;
      }
    }
    return PosSaleStatus.open;
  }

  bool get isSettled => this != PosSaleStatus.open;
}

/// What the server says may still be done to this sale.
enum PosSaleAction {
  complete('COMPLETE', 'Charge'),
  voidSale('VOID', 'Void'),
  refund('REFUND', 'Refund'),
  reprint('REPRINT', 'Reprint receipt');

  const PosSaleAction(this.wireValue, this.label);

  final String wireValue;
  final String label;

  /// Null for anything unknown, and the unknown entry is DROPPED rather than defaulted: a button
  /// this build cannot implement must not appear, and guessing which one it is would be worse.
  static PosSaleAction? fromWire(String? value) {
    for (final PosSaleAction action in PosSaleAction.values) {
      if (action.wireValue == value) {
        return action;
      }
    }
    return null;
  }
}

/// How the customer paid.
enum PosTenderMethod {
  cashUsd('CASH_USD', 'Cash (USD)'),
  cashLbp('CASH_LBP', 'Cash (LBP)'),
  card('CARD', 'Card'),
  wallet('WALLET_APP', 'YouDrop wallet');

  const PosTenderMethod(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static PosTenderMethod fromWire(String? value) {
    for (final PosTenderMethod method in PosTenderMethod.values) {
      if (method.wireValue == value) {
        return method;
      }
    }
    return PosTenderMethod.cashUsd;
  }

  bool get isCash => this == PosTenderMethod.cashUsd || this == PosTenderMethod.cashLbp;
}

/// Which currency the drawer gives change in. Cash only — there is no change on a card.
enum ChangeCurrency {
  usd('USD', 'USD'),
  lbp('LBP', 'LBP');

  const ChangeCurrency(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static ChangeCurrency fromWire(String? value) =>
      value == 'LBP' ? ChangeCurrency.lbp : ChangeCurrency.usd;
}

/// How the receipt leaves the till.
enum ReceiptChannel {
  print_('PRINT', 'Print'),
  sms('SMS', 'SMS'),
  whatsapp('WHATSAPP', 'WhatsApp'),
  email('EMAIL', 'Email'),
  none('NONE', 'No receipt');

  const ReceiptChannel(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static ReceiptChannel fromWire(String? value) {
    for (final ReceiptChannel channel in ReceiptChannel.values) {
      if (channel.wireValue == value) {
        return channel;
      }
    }
    return ReceiptChannel.none;
  }

  /// Everything but printing needs somewhere to send it.
  bool get needsContact => this == ReceiptChannel.sms ||
      this == ReceiptChannel.whatsapp ||
      this == ReceiptChannel.email;
}

/// One line on the basket.
class PosSaleLine {
  const PosSaleLine({
    required this.id,
    required this.productName,
    required this.unitPrice,
    required this.lineTotal,
    this.productId,
    this.sku,
    Money? baseUnitPrice,
    this.qty = 1,
    this.refundedQty = 0,
    this.options = const <ChosenOption>[],
    this.optionsSummary = '',
  }) : _baseUnitPrice = baseUnitPrice;

  final String id;

  /// Null for an open item — a price typed at the till for something not in the catalogue.
  final String? productId;

  final String productName;
  final String? sku;

  final Money? _baseUnitPrice;

  /// The catalogue price before the chosen options moved it. Falls back to [unitPrice] so a screen
  /// never has to null-check a figure it is about to draw.
  Money get baseUnitPrice => _baseUnitPrice ?? unitPrice;

  /// What one of these was actually rung at, options included.
  final Money unitPrice;

  /// Server-computed `unitPrice * qty`. Not multiplied here — see the money law.
  final Money lineTotal;

  final int qty;
  final int refundedQty;
  final List<ChosenOption> options;

  /// The server's own one-line rendering of [options], so the till and the receipt agree.
  final String optionsSummary;

  bool get isOpenItem => productId == null;

  /// How many of this line are still refundable.
  int get refundableQty => qty - refundedQty;

  factory PosSaleLine.fromJson(Map<String, dynamic> json) => PosSaleLine(
        id: json['id'] as String,
        productId: json['productId'] as String?,
        productName: json['productName'] as String? ?? json['name'] as String? ?? '',
        sku: json['sku'] as String?,
        baseUnitPrice: Money.parse(json['baseUnitPrice']),
        unitPrice: Money.parse(json['unitPrice']) ?? const Money('0.00'),
        lineTotal: Money.parse(json['lineTotal']) ?? const Money('0.00'),
        qty: (json['qty'] as num?)?.toInt() ?? 1,
        refundedQty: (json['refundedQty'] as num?)?.toInt() ?? 0,
        options: (json['options'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic o) => ChosenOption.fromJson(o as Map<String, dynamic>))
            .toList(),
        optionsSummary: json['optionsSummary'] as String? ?? '',
      );
}

/// One tender that was actually applied, as the server recorded it.
///
/// The change figures are the server's arithmetic, including the LBP rounding a drawer with no
/// note under 1,000 forces. A client that recomputed them would eventually disagree with the till
/// by a thousand pounds.
class PosPayment {
  const PosPayment({
    required this.id,
    required this.method,
    required this.applied,
    this.tendered,
    this.tenderedLbp,
    this.change = const Money('0.00'),
    this.changeLbp = 0,
    this.cashRoundingLbp = 0,
    this.reference,
    this.recordedAt,
  });

  final String id;
  final PosTenderMethod method;

  /// How much of the total this tender settled.
  final Money applied;

  /// What the customer handed over, when that is a different number.
  final Money? tendered;
  final int? tenderedLbp;

  final Money change;
  final int changeLbp;

  /// What was lost to rounding LBP change to a note that exists. Shown on the receipt so the
  /// drawer reconciles.
  final int cashRoundingLbp;

  final String? reference;
  final DateTime? recordedAt;

  factory PosPayment.fromJson(Map<String, dynamic> json) => PosPayment(
        id: json['id'] as String,
        method: PosTenderMethod.fromWire(json['method'] as String?),
        applied: Money.parse(json['applied']) ?? const Money('0.00'),
        tendered: Money.parse(json['tendered']),
        tenderedLbp: (json['tenderedLbp'] as num?)?.toInt(),
        change: Money.parse(json['change']) ?? const Money('0.00'),
        changeLbp: (json['changeLbp'] as num?)?.toInt() ?? 0,
        cashRoundingLbp: (json['cashRoundingLbp'] as num?)?.toInt() ?? 0,
        reference: json['reference'] as String?,
        recordedAt: DateTime.tryParse(json['recordedAt'] as String? ?? ''),
      );
}

/// A tender the client is ABOUT to apply — the request side of checkout.
///
/// Sealed with one variant per method because the fields genuinely differ: cash in dollars needs a
/// change currency, cash in pounds is an integer, and a card has a reference but never change.
/// Modelling this as one bag of nullable fields is how a card payment ends up claiming to have
/// given change.
sealed class PosTender {
  const PosTender();

  const factory PosTender.cashUsd({
    required Money tendered,
    ChangeCurrency changeIn,
  }) = PosCashUsdTender;

  const factory PosTender.cashLbp({required int tenderedLbp}) = PosCashLbpTender;

  const factory PosTender.card({required Money amount, String? reference}) = PosCardTender;

  const factory PosTender.wallet({required Money amount, required String reference}) =
      PosWalletTender;

  Map<String, dynamic> toJson();
}

class PosCashUsdTender extends PosTender {
  const PosCashUsdTender({required this.tendered, this.changeIn = ChangeCurrency.usd});

  final Money tendered;
  final ChangeCurrency changeIn;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'method': PosTenderMethod.cashUsd.wireValue,
        'tendered': tendered.amount,
        'changeIn': changeIn.wireValue,
      };
}

class PosCashLbpTender extends PosTender {
  const PosCashLbpTender({required this.tenderedLbp});

  final int tenderedLbp;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'method': PosTenderMethod.cashLbp.wireValue,
        'tenderedLbp': tenderedLbp,
      };
}

class PosCardTender extends PosTender {
  const PosCardTender({required this.amount, this.reference});

  final Money amount;
  final String? reference;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'method': PosTenderMethod.card.wireValue,
        'amount': amount.amount,
        if (reference != null) 'reference': reference,
      };
}

class PosWalletTender extends PosTender {
  const PosWalletTender({required this.amount, required this.reference});

  final Money amount;
  final String reference;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'method': PosTenderMethod.wallet.wireValue,
        'amount': amount.amount,
        'reference': reference,
      };
}

/// A walk-in sale, whole. Every mutating call returns one of these — one shape, one `setState`,
/// no client-side merging of a basket.
///
/// Every money field defaults to `0.00` and every int to 0 on parse, so a server that predates a
/// field still yields a renderable sale rather than an exception at the till.
class PosSale {
  const PosSale({
    required this.id,
    required this.storeId,
    required this.status,
    this.cashierRef = '',
    this.registerId,
    this.shiftId,
    this.receiptNo,
    this.receiptLabel,
    this.subtotal = const Money('0.00'),
    this.discount = const Money('0.00'),
    this.discountNote,
    this.tax = const Money('0.00'),
    this.total = const Money('0.00'),
    this.paid = const Money('0.00'),
    this.outstanding = const Money('0.00'),
    this.refunded = const Money('0.00'),
    this.lbpPerUsd = 0,
    this.totalLbpExact = 0,
    this.totalLbpFace = 0,
    this.vatRateBp = 0,
    this.lines = const <PosSaleLine>[],
    this.payments = const <PosPayment>[],
    this.availableActions = const <PosSaleAction>[],
    this.openedAt,
    this.completedAt,
    this.voidedAt,
    this.voidReason,
    this.customerPhone,
  });

  final String id;
  final String storeId;
  final PosSaleStatus status;

  /// The cashier's `sub`. An owner rings up sales too, so this is not a staff member id.
  final String cashierRef;

  final String? registerId;
  final String? shiftId;

  /// Assigned at completion, never before — an abandoned basket must not burn a receipt number.
  final int? receiptNo;

  /// The printed form, e.g. `W-0234`, with the store's own prefix.
  final String? receiptLabel;

  final Money subtotal;
  final Money discount;
  final String? discountNote;
  final Money tax;
  final Money total;
  final Money paid;

  /// What is still to be tendered. Checkout refuses unless this reaches exactly zero.
  final Money outstanding;

  final Money refunded;

  /// The rate LOCKED when this sale opened. Render this, not the live market rate.
  final int lbpPerUsd;

  /// The total in pounds at that rate, and the same figure rounded to a note that exists.
  final int totalLbpExact;
  final int totalLbpFace;

  /// VAT in basis points — 1100 is 11%. An integer so a tax rate cannot drift.
  final int vatRateBp;

  final List<PosSaleLine> lines;
  final List<PosPayment> payments;

  /// Server-computed. Draw buttons from this and nothing else.
  final List<PosSaleAction> availableActions;

  final DateTime? openedAt;
  final DateTime? completedAt;
  final DateTime? voidedAt;
  final String? voidReason;
  final String? customerPhone;

  bool get isOpen => status == PosSaleStatus.open;

  bool get isEmpty => lines.isEmpty;

  /// A COUNT, not money — summing quantities is arithmetic the client is allowed to do.
  int get itemCount => lines.fold(0, (int sum, PosSaleLine line) => sum + line.qty);

  bool can(PosSaleAction action) => availableActions.contains(action);

  factory PosSale.fromJson(Map<String, dynamic> json) => PosSale(
        id: json['id'] as String,
        storeId: json['storeId'] as String? ?? '',
        status: PosSaleStatus.fromWire(json['status'] as String?),
        cashierRef: json['cashierRef'] as String? ?? '',
        registerId: json['registerId'] as String?,
        shiftId: json['shiftId'] as String?,
        receiptNo: (json['receiptNo'] as num?)?.toInt(),
        receiptLabel: json['receiptLabel'] as String?,
        subtotal: Money.parse(json['subtotal']) ?? const Money('0.00'),
        discount: Money.parse(json['discount']) ?? const Money('0.00'),
        discountNote: json['discountNote'] as String?,
        tax: Money.parse(json['tax']) ?? const Money('0.00'),
        total: Money.parse(json['total']) ?? const Money('0.00'),
        paid: Money.parse(json['paid']) ?? const Money('0.00'),
        outstanding: Money.parse(json['outstanding']) ?? const Money('0.00'),
        refunded: Money.parse(json['refunded']) ?? const Money('0.00'),
        lbpPerUsd: (json['lbpPerUsd'] as num?)?.toInt() ?? 0,
        totalLbpExact: (json['totalLbpExact'] as num?)?.toInt() ?? 0,
        totalLbpFace: (json['totalLbpFace'] as num?)?.toInt() ?? 0,
        vatRateBp: (json['vatRateBp'] as num?)?.toInt() ?? 0,
        lines: (json['lines'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic l) => PosSaleLine.fromJson(l as Map<String, dynamic>))
            .toList(),
        payments: (json['payments'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic p) => PosPayment.fromJson(p as Map<String, dynamic>))
            .toList(),
        availableActions: (json['availableActions'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic a) => PosSaleAction.fromWire(a as String?))
            .whereType<PosSaleAction>()
            .toList(),
        openedAt: DateTime.tryParse(json['openedAt'] as String? ?? ''),
        completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
        voidedAt: DateTime.tryParse(json['voidedAt'] as String? ?? ''),
        voidReason: json['voidReason'] as String?,
        customerPhone: json['customerPhone'] as String?,
      );
}

/// A sale as a history row: enough to list it, without its lines or payments.
class PosSaleSummary {
  const PosSaleSummary({
    required this.id,
    required this.status,
    this.receiptLabel,
    this.receiptNo,
    this.total = const Money('0.00'),
    this.refunded = const Money('0.00'),
    this.itemCount = 0,
    this.method,
    this.cashierRef,
    this.cashierName,
    this.completedAt,
    this.openedAt,
    this.lbpPerUsd = 0,
    this.totalLbpExact = 0,
  });

  final String id;
  final PosSaleStatus status;
  final String? receiptLabel;
  final int? receiptNo;
  final Money total;
  final Money refunded;
  final int itemCount;

  /// The dominant tender. Null on a split payment — the row shows "Split" rather than a lie.
  final PosTenderMethod? method;

  final String? cashierRef;
  final String? cashierName;
  final DateTime? completedAt;
  final DateTime? openedAt;
  final int lbpPerUsd;
  final int totalLbpExact;

  factory PosSaleSummary.fromJson(Map<String, dynamic> json) => PosSaleSummary(
        id: json['id'] as String,
        status: PosSaleStatus.fromWire(json['status'] as String?),
        receiptLabel: json['receiptLabel'] as String?,
        receiptNo: (json['receiptNo'] as num?)?.toInt(),
        total: Money.parse(json['total']) ?? const Money('0.00'),
        refunded: Money.parse(json['refunded']) ?? const Money('0.00'),
        itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
        method: json['method'] == null
            ? null
            : PosTenderMethod.fromWire(json['method'] as String?),
        cashierRef: json['cashierRef'] as String?,
        cashierName: json['cashierName'] as String?,
        completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
        openedAt: DateTime.tryParse(json['openedAt'] as String? ?? ''),
        lbpPerUsd: (json['lbpPerUsd'] as num?)?.toInt() ?? 0,
        totalLbpExact: (json['totalLbpExact'] as num?)?.toInt() ?? 0,
      );
}

/// One line being sent back, on the request side of a refund.
class PosRefundLine {
  const PosRefundLine({required this.lineId, required this.qty});

  final String lineId;
  final int qty;

  Map<String, dynamic> toJson() => <String, dynamic>{'lineId': lineId, 'qty': qty};

  factory PosRefundLine.fromJson(Map<String, dynamic> json) => PosRefundLine(
        lineId: json['lineId'] as String,
        qty: (json['qty'] as num?)?.toInt() ?? 0,
      );
}

/// What a refund actually returned.
class PosRefund {
  const PosRefund({
    required this.id,
    required this.saleId,
    this.amount = const Money('0.00'),
    this.amountLbp = 0,
    this.method = PosTenderMethod.cashUsd,
    this.restocked = true,
    this.reason,
    this.lines = const <PosRefundLine>[],
    this.refundedAt,
    this.sale,
  });

  final String id;
  final String saleId;
  final Money amount;
  final int amountLbp;
  final PosTenderMethod method;
  final bool restocked;
  final String? reason;
  final List<PosRefundLine> lines;
  final DateTime? refundedAt;

  /// The sale as it now stands, when the server sends it — saves a refetch to redraw the screen.
  final PosSale? sale;

  factory PosRefund.fromJson(Map<String, dynamic> json) => PosRefund(
        id: json['id'] as String,
        saleId: json['saleId'] as String? ?? '',
        amount: Money.parse(json['amount']) ?? const Money('0.00'),
        amountLbp: (json['amountLbp'] as num?)?.toInt() ?? 0,
        method: PosTenderMethod.fromWire(json['method'] as String?),
        restocked: json['restocked'] as bool? ?? true,
        reason: json['reason'] as String?,
        lines: (json['lines'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic l) => PosRefundLine.fromJson(l as Map<String, dynamic>))
            .toList(),
        refundedAt: DateTime.tryParse(json['refundedAt'] as String? ?? ''),
        sale: json['sale'] == null
            ? null
            : PosSale.fromJson(json['sale'] as Map<String, dynamic>),
      );
}

/// The printed artifact. Everything on it is the server's — a reprint is a reproduction, not a
/// recalculation.
class PosReceipt {
  const PosReceipt({
    required this.saleId,
    this.receiptLabel,
    this.receiptNo,
    this.storeName,
    this.storeAddress,
    this.storePhone,
    this.footer,
    this.cashierName,
    this.lines = const <PosSaleLine>[],
    this.payments = const <PosPayment>[],
    this.subtotal = const Money('0.00'),
    this.discount = const Money('0.00'),
    this.tax = const Money('0.00'),
    this.total = const Money('0.00'),
    this.refunded = const Money('0.00'),
    this.lbpPerUsd = 0,
    this.totalLbpExact = 0,
    this.totalLbpFace = 0,
    this.vatRateBp = 0,
    this.issuedAt,
    this.htmlUrl,
  });

  final String saleId;
  final String? receiptLabel;
  final int? receiptNo;
  final String? storeName;
  final String? storeAddress;
  final String? storePhone;

  /// The merchant's own footer line — "Thank you", a returns policy, an Instagram handle.
  final String? footer;

  final String? cashierName;
  final List<PosSaleLine> lines;
  final List<PosPayment> payments;
  final Money subtotal;
  final Money discount;
  final Money tax;
  final Money total;
  final Money refunded;
  final int lbpPerUsd;
  final int totalLbpExact;
  final int totalLbpFace;
  final int vatRateBp;
  final DateTime? issuedAt;

  /// Server-rendered thermal-width HTML, for the Print button. Null when the server did not offer
  /// one, in which case the client's own rendering is all there is.
  final String? htmlUrl;

  int get itemCount => lines.fold(0, (int sum, PosSaleLine line) => sum + line.qty);

  factory PosReceipt.fromJson(Map<String, dynamic> json) => PosReceipt(
        saleId: (json['saleId'] ?? json['id']) as String,
        receiptLabel: json['receiptLabel'] as String?,
        receiptNo: (json['receiptNo'] as num?)?.toInt(),
        storeName: json['storeName'] as String?,
        storeAddress: json['storeAddress'] as String?,
        storePhone: json['storePhone'] as String?,
        footer: json['footer'] as String?,
        cashierName: json['cashierName'] as String?,
        lines: (json['lines'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic l) => PosSaleLine.fromJson(l as Map<String, dynamic>))
            .toList(),
        payments: (json['payments'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic p) => PosPayment.fromJson(p as Map<String, dynamic>))
            .toList(),
        subtotal: Money.parse(json['subtotal']) ?? const Money('0.00'),
        discount: Money.parse(json['discount']) ?? const Money('0.00'),
        tax: Money.parse(json['tax']) ?? const Money('0.00'),
        total: Money.parse(json['total']) ?? const Money('0.00'),
        refunded: Money.parse(json['refunded']) ?? const Money('0.00'),
        lbpPerUsd: (json['lbpPerUsd'] as num?)?.toInt() ?? 0,
        totalLbpExact: (json['totalLbpExact'] as num?)?.toInt() ?? 0,
        totalLbpFace: (json['totalLbpFace'] as num?)?.toInt() ?? 0,
        vatRateBp: (json['vatRateBp'] as num?)?.toInt() ?? 0,
        issuedAt: DateTime.tryParse(json['issuedAt'] as String? ?? ''),
        htmlUrl: json['htmlUrl'] as String?,
      );
}

/// A till. A shop with two counters has two, and a shift belongs to one of them.
class PosRegister {
  const PosRegister({required this.id, required this.name, this.active = true, this.openShiftId});

  final String id;
  final String name;
  final bool active;

  /// Non-null when somebody is already on this register.
  final String? openShiftId;

  bool get isBusy => openShiftId != null;

  factory PosRegister.fromJson(Map<String, dynamic> json) => PosRegister(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        active: json['active'] as bool? ?? true,
        openShiftId: json['openShiftId'] as String?,
      );
}

/// What one tender method took over a shift — the Z-report's rows.
class PosTenderTotal {
  const PosTenderTotal({
    required this.method,
    this.amount = const Money('0.00'),
    this.amountLbp = 0,
    this.count = 0,
  });

  final PosTenderMethod method;
  final Money amount;
  final int amountLbp;
  final int count;

  factory PosTenderTotal.fromJson(Map<String, dynamic> json) => PosTenderTotal(
        method: PosTenderMethod.fromWire(json['method'] as String?),
        amount: Money.parse(json['amount']) ?? const Money('0.00'),
        amountLbp: (json['amountLbp'] as num?)?.toInt() ?? 0,
        count: (json['count'] as num?)?.toInt() ?? 0,
      );
}

/// A cashier's session at a register: what was in the drawer at the start, what should be in it
/// now, and what was actually counted.
///
/// Both currencies get their own expected/counted/variance triple, because a drawer holds both and
/// converting one into the other to compare them would invent a discrepancy.
class PosShift {
  const PosShift({
    required this.id,
    required this.storeId,
    this.registerId,
    this.registerName,
    this.cashierRef,
    this.cashierName,
    this.openingFloat = const Money('0.00'),
    this.openingFloatLbp = 0,
    this.expected,
    this.expectedLbp,
    this.counted,
    this.countedLbp,
    this.variance,
    this.varianceLbp,
    this.salesTotal = const Money('0.00'),
    this.salesCount = 0,
    this.byMethod = const <PosTenderTotal>[],
    this.openedAt,
    this.closedAt,
  });

  final String id;
  final String storeId;
  final String? registerId;
  final String? registerName;
  final String? cashierRef;
  final String? cashierName;
  final Money openingFloat;
  final int openingFloatLbp;

  /// Null while the shift is open — the figure only exists once the drawer is closed against it.
  final Money? expected;
  final int? expectedLbp;
  final Money? counted;
  final int? countedLbp;
  final Money? variance;
  final int? varianceLbp;

  final Money salesTotal;
  final int salesCount;
  final List<PosTenderTotal> byMethod;
  final DateTime? openedAt;
  final DateTime? closedAt;

  bool get isOpen => closedAt == null;

  factory PosShift.fromJson(Map<String, dynamic> json) => PosShift(
        id: json['id'] as String,
        storeId: json['storeId'] as String? ?? '',
        registerId: json['registerId'] as String?,
        registerName: json['registerName'] as String?,
        cashierRef: json['cashierRef'] as String?,
        cashierName: json['cashierName'] as String?,
        openingFloat: Money.parse(json['openingFloat']) ?? const Money('0.00'),
        openingFloatLbp: (json['openingFloatLbp'] as num?)?.toInt() ?? 0,
        expected: Money.parse(json['expected']),
        expectedLbp: (json['expectedLbp'] as num?)?.toInt(),
        counted: Money.parse(json['counted']),
        countedLbp: (json['countedLbp'] as num?)?.toInt(),
        variance: Money.parse(json['variance']),
        varianceLbp: (json['varianceLbp'] as num?)?.toInt(),
        salesTotal: Money.parse(json['salesTotal']) ?? const Money('0.00'),
        salesCount: (json['salesCount'] as num?)?.toInt() ?? 0,
        byMethod: (json['byMethod'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic m) => PosTenderTotal.fromJson(m as Map<String, dynamic>))
            .toList(),
        openedAt: DateTime.tryParse(json['openedAt'] as String? ?? ''),
        closedAt: DateTime.tryParse(json['closedAt'] as String? ?? ''),
      );
}

/// The till's takings over a window — the POS half of the dashboard.
class PosSummary {
  const PosSummary({
    this.days = 1,
    this.total = const Money('0.00'),
    this.refunded = const Money('0.00'),
    this.net = const Money('0.00'),
    this.transactions = 0,
    this.itemsSold = 0,
    this.byMethod = const <PosTenderTotal>[],
  });

  final int days;
  final Money total;
  final Money refunded;
  final Money net;
  final int transactions;
  final int itemsSold;
  final List<PosTenderTotal> byMethod;

  static const PosSummary empty = PosSummary();

  /// What one method took, or null when it took nothing — the dashboard's cash/card split.
  PosTenderTotal? forMethod(PosTenderMethod method) {
    for (final PosTenderTotal total in byMethod) {
      if (total.method == method) {
        return total;
      }
    }
    return null;
  }

  factory PosSummary.fromJson(Map<String, dynamic> json) => PosSummary(
        days: (json['days'] as num?)?.toInt() ?? 1,
        total: Money.parse(json['total']) ?? const Money('0.00'),
        refunded: Money.parse(json['refunded']) ?? const Money('0.00'),
        net: Money.parse(json['net']) ?? const Money('0.00'),
        transactions: (json['transactions'] as num?)?.toInt() ?? 0,
        itemsSold: (json['itemsSold'] as num?)?.toInt() ?? 0,
        byMethod: (json['byMethod'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic m) => PosTenderTotal.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}

/// How this shop's till behaves. Read before the first sale; the rate and VAT here are what a new
/// sale locks in.
class PosSettings {
  const PosSettings({
    this.vatRateBp = 0,
    this.pricesTaxInclusive = true,
    this.receiptPrefix = '',
    this.receiptFooter,
    this.cashierDiscountMax = const Money('0.00'),
    this.lbpPerUsd = 0,
  });

  final int vatRateBp;
  final bool pricesTaxInclusive;

  /// Prefixes the printed receipt number, e.g. `W` in `W-0234`.
  final String receiptPrefix;

  final String? receiptFooter;

  /// The largest discount a cashier may apply without POS_REFUNDS_VOIDS.
  final Money cashierDiscountMax;

  final int lbpPerUsd;

  static const PosSettings defaults = PosSettings();

  factory PosSettings.fromJson(Map<String, dynamic> json) => PosSettings(
        vatRateBp: (json['vatRateBp'] as num?)?.toInt() ?? 0,
        pricesTaxInclusive: json['pricesTaxInclusive'] as bool? ?? true,
        receiptPrefix: json['receiptPrefix'] as String? ?? '',
        receiptFooter: json['receiptFooter'] as String?,
        cashierDiscountMax: Money.parse(json['cashierDiscountMax']) ?? const Money('0.00'),
        lbpPerUsd: (json['lbpPerUsd'] as num?)?.toInt() ?? 0,
      );
}
