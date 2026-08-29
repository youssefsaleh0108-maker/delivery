/// Counterparty statements — what the platform owes a shop, a rider or a delivery company over a
/// date range, and what it has already sent them.
///
/// One parse of the statement contract for all three consumers (the Backoffice and carrier console,
/// the merchant app, the rider app), because a statement that reads 2121.80 in one app and 2,121.8
/// in another is a support ticket about a bug that does not exist.
library;

/// A money amount exactly as the server wrote it.
///
/// The wire carries money as a STRING with two decimals and this class keeps it a string. It is
/// deliberately never parsed into a double: a double cannot hold 0.10, and the error compounds the
/// moment anything adds two of them together. This is somebody's pay — the only safe thing a client
/// can do with it is show the digits the ledger computed, unchanged.
///
/// Everything the screens need to render a figure is here, so no screen has to reach for arithmetic
/// of its own.
class Money {
  const Money(this.amount);

  /// The server's own text: `"2121.80"`, `"-19.50"`, `"0.00"`. Never reformatted, never rounded,
  /// never widened or trimmed. Display this.
  final String amount;

  /// Reads a money field, or null when the server sent nothing usable.
  ///
  /// Null rather than `Money('0.00')`, and the distinction is the whole point: "we were not told"
  /// and "nothing is owed" are different statements about somebody's pay, and only one of them is
  /// safe to print next to a currency symbol. Callers must render the null case as unknown — a
  /// dash, a spinner, anything but a zero.
  static Money? parse(Object? value) {
    if (value is String && value.trim().isNotEmpty) return Money(value.trim());
    // Numbers are refused rather than stringified. A JSON number has already been through a double
    // by the time it reaches here, so its digits can no longer be trusted to be the ledger's.
    return null;
  }

  /// The shape the ledger emits: an optional sign, whole digits, and at most two decimals.
  ///
  /// More than two decimals is refused rather than rounded — silently rounding money is the exact
  /// failure this class exists to prevent.
  static final RegExp _shape = RegExp(r'^([+-]?)(\d+)(?:\.(\d{1,2}))?$');

  /// The amount in minor units — cents — or null when the text is not a figure this client can
  /// read.
  ///
  /// An `int`, chosen over `double` and over any decimal package: two decimal places times a
  /// realistic ledger total fits an int with room to spare, and int arithmetic is exact, so
  /// comparing and sorting cannot drift. Use it to compare, sort or test for zero. Do NOT use it to
  /// display — [amount] is what goes on screen, because rebuilding the text from an int would
  /// invent formatting decisions the server already made.
  int? get minorUnits {
    final RegExpMatch? match = _shape.firstMatch(amount);
    if (match == null) return null;
    final int? whole = int.tryParse(match.group(2)!);
    final int? fraction = int.tryParse((match.group(3) ?? '0').padRight(2, '0'));
    if (whole == null || fraction == null) return null;
    final int units = whole * 100 + fraction;
    return match.group(1) == '-' ? -units : units;
  }

  /// Whether this client could read the figure at all. False for a shape it does not recognise —
  /// which is still shown as-is, never replaced by a guess.
  bool get isReadable => minorUnits != null;

  /// True only when the figure is readable and it is nothing. An unreadable amount is not zero.
  bool get isZero => minorUnits == 0;

  /// True only when the server itself wrote a minus. An unreadable amount is not negative.
  bool get isNegative => (minorUnits ?? 0) < 0;

  /// The digits with any sign the server wrote stripped off, for a screen that draws its own.
  String get unsigned =>
      amount.startsWith('-') || amount.startsWith('+') ? amount.substring(1) : amount;

  /// The amount with a sign, given which way the line moves.
  ///
  /// The two signs are composed rather than concatenated: a CREDIT of `-5.00` is a credit that went
  /// backwards, and prefixing it would render `+-5.00`. Composing them is not arithmetic on the
  /// value — the digits are handed straight through — it only decides which of two characters goes
  /// in front of them.
  ///
  /// [LedgerDirection.unknown] gets no sign at all. A direction this build cannot read must not be
  /// guessed into a plus.
  String signedFor(LedgerDirection direction) {
    if (direction == LedgerDirection.unknown) return amount;
    final bool serverSaidNegative = amount.startsWith('-');
    final bool negative = serverSaidNegative != (direction == LedgerDirection.debit);
    return '${negative ? '-' : '+'}$unsigned';
  }

  @override
  String toString() => amount;
}

/// Which commercial party a statement is about.
///
/// Mirrors the contract's counterparty kinds. `fromWire` returns null rather than falling back,
/// because every kind here is a different pocket: reading an unknown kind as MERCHANT would file a
/// rider's pay under a shop's payout. Models keep the server's raw string alongside, so a kind this
/// build predates is still displayed and still openable.
enum CounterpartyKind {
  /// A shop. The platform collects the customer's cash and owes the shop the goods value less
  /// commission.
  merchant('MERCHANT', 'Shop'),

  /// A person who delivers. Owed delivery fees, minus any platform cash they are still carrying.
  rider('RIDER', 'Rider'),

  /// A delivery company whose riders carried jobs.
  carrier('CARRIER', 'Delivery company'),

  /// The platform's own side of the ledger — commission earned, subsidies paid.
  platform('PLATFORM', 'Platform');

  const CounterpartyKind(this.wire, this.label);

  final String wire;
  final String label;

  /// Null for a kind this build does not know. See the enum doc for why there is no fallback.
  static CounterpartyKind? fromWire(String? value) {
    for (final CounterpartyKind k in CounterpartyKind.values) {
      if (k.wire == value) return k;
    }
    return null;
  }
}

/// Which way a single statement line moves, from the reader's point of view.
enum LedgerDirection {
  /// Adds to what the counterparty is owed.
  credit('CREDIT', 'Credit'),

  /// Takes away from it — commission, a deduction, cash already handed over.
  debit('DEBIT', 'Debit'),

  /// A direction this build does not know. Rendered without a sign and never as a credit: a
  /// deduction shown as money coming in is a figure somebody will budget against.
  unknown('UNKNOWN', 'Unknown');

  const LedgerDirection(this.wire, this.label);

  final String wire;
  final String label;

  static LedgerDirection fromWire(String? value) => LedgerDirection.values.firstWhere(
        (LedgerDirection d) => d.wire == value,
        orElse: () => LedgerDirection.unknown,
      );
}

/// Which way the bottom line points, always from the PLATFORM's point of view.
///
/// The contract fixes the vantage point so the three apps cannot each pick their own. A merchant
/// reading their own statement sees [weOwe] and must be shown it as money coming to them, which is
/// what [selfLabel] is for.
enum NetDirection {
  /// The platform owes the counterparty.
  weOwe('WE_OWE', 'We owe them', 'Owed to you'),

  /// The counterparty owes the platform — a rider carrying more cash than they have earned, say.
  theyOwe('THEY_OWE', 'They owe us', 'You owe'),

  /// Nothing outstanding either way.
  settled('SETTLED', 'Settled', 'Settled'),

  /// A direction this build does not know.
  ///
  /// Deliberately not folded into [settled]. "Settled" is a claim that nobody is waiting on money;
  /// making it the fallback would answer a question this client cannot actually answer, and the
  /// person it misleads is the one owed the money.
  unknown('UNKNOWN', 'Unclear', 'Unclear');

  const NetDirection(this.wire, this.label, this.selfLabel);

  final String wire;

  /// Operator wording, for the Backoffice and carrier console.
  final String label;

  /// The same fact told to the counterparty themselves, for the merchant and rider apps.
  final String selfLabel;

  static NetDirection fromWire(String? value) => NetDirection.values.firstWhere(
        (NetDirection d) => d.wire == value,
        orElse: () => NetDirection.unknown,
      );

  /// True only for a stated [settled]. An unreadable direction is not a settled one.
  bool get isSettled => this == settled;

  /// Which sign the bottom line carries for the counterparty reading it. [weOwe] is money towards
  /// them; [theyOwe] is money away.
  LedgerDirection get asLineDirection => switch (this) {
        NetDirection.weOwe => LedgerDirection.credit,
        NetDirection.theyOwe => LedgerDirection.debit,
        NetDirection.settled => LedgerDirection.credit,
        NetDirection.unknown => LedgerDirection.unknown,
      };
}

/// One summary row of a statement — "Goods sold", "Platform commission (12.5%)".
///
/// The label and the note are the server's words, not this client's. The percentage in a commission
/// label is computed where the rate lives; a client that formatted its own would go stale the day
/// the rate changes for one shop.
class StatementLine {
  const StatementLine({
    required this.label,
    required this.direction,
    this.amount,
    this.note,
  });

  final String label;

  /// Null when the server sent no figure. See [Money.parse] — this must not render as zero.
  final Money? amount;

  final LedgerDirection direction;

  /// Free text under the figure — "45 orders". Null when there is nothing to add.
  final String? note;

  /// The figure with its sign, ready to draw. Null when there was no figure.
  String? get signedAmount => amount?.signedFor(direction);

  factory StatementLine.fromJson(Map<String, dynamic> json) => StatementLine(
        label: json['label'] as String? ?? '',
        amount: Money.parse(json['amount']),
        direction: LedgerDirection.fromWire(json['direction'] as String?),
        note: json['note'] as String?,
      );
}

/// One order behind the summary — the row somebody points at in a dispute.
class StatementEntry {
  const StatementEntry({
    required this.orderId,
    this.at,
    this.gross,
    this.commission,
    this.net,
    this.paymentMethod,
  });

  final String orderId;

  /// When the order settled. Null when the server did not say.
  final DateTime? at;

  /// What the customer paid, what was taken off it, and what is left for the counterparty.
  ///
  /// All three nullable and none derived from the others. The client does not check that
  /// `gross - commission == net`, let alone compute a missing one: the ledger is the authority on
  /// its own arithmetic, and a client that recomputes it eventually disagrees with it.
  final Money? gross;
  final Money? commission;
  final Money? net;

  /// `CASH` on every order today — every order is collected at the door. Kept because the day it
  /// stops being true, a statement that never said so is unreadable.
  final String? paymentMethod;

  factory StatementEntry.fromJson(Map<String, dynamic> json) => StatementEntry(
        orderId: json['orderId'] as String? ?? '',
        at: _instant(json['at']),
        gross: Money.parse(json['gross']),
        commission: Money.parse(json['commission']),
        net: Money.parse(json['net']),
        paymentMethod: json['paymentMethod'] as String?,
      );
}

/// The bottom line: an amount and which way it points.
class StatementNet {
  const StatementNet({required this.direction, this.amount});

  /// Null when the server sent no figure — rendered as unknown, never as nothing owed.
  final Money? amount;

  final NetDirection direction;

  /// The figure signed from the counterparty's own point of view: positive when it is coming to
  /// them. Null when there was no figure.
  String? get signedAmount => amount?.signedFor(direction.asLineDirection);

  /// Whether there is genuinely nothing outstanding. Requires the server to have said so AND the
  /// figure to be a readable zero — either half alone is a guess.
  bool get isSettled => direction.isSettled && (amount?.isZero ?? false);

  factory StatementNet.fromJson(Map<String, dynamic> json) => StatementNet(
        amount: Money.parse(json['amount']),
        direction: NetDirection.fromWire(json['direction'] as String?),
      );

  /// The shape used when the server sends no net block at all.
  static const StatementNet unknown =
      StatementNet(amount: null, direction: NetDirection.unknown);
}

/// One counterparty's statement over a date range.
///
/// The same shape whether it was fetched by an operator for somebody else or by the counterparty
/// for themselves — the routes differ in who may call them, not in what comes back.
class Statement {
  const Statement({
    required this.kindWire,
    required this.ref,
    required this.name,
    required this.currency,
    required this.lines,
    required this.entries,
    required this.net,
    this.kind,
    this.from,
    this.to,
    this.generatedAt,
    this.note,
  });

  /// The typed kind, or null for one this build does not know. [kindWire] always holds the server's
  /// string either way, so an unknown kind is still displayable and still refetchable.
  final CounterpartyKind? kind;
  final String kindWire;

  /// The counterparty's identifier, as used in the statement routes.
  final String ref;

  /// Their trading name. Empty when the server could not resolve one — which is exactly the
  /// omnibus-bucket problem the identity work fixes, so it is left empty rather than filled with
  /// the ref, which would make an unresolved statement look resolved.
  final String name;

  /// Inclusive calendar dates in the platform timezone, parsed as dates and NOT shifted to local
  /// time: a statement headed "1 August" must say August wherever it is opened. Null when the
  /// server omitted them.
  final DateTime? from;
  final DateTime? to;

  final String currency;

  /// The instant the figures were computed — an instant, so this one IS local.
  final DateTime? generatedAt;

  final List<StatementLine> lines;
  final List<StatementEntry> entries;
  final StatementNet net;

  /// Anything the figures cannot state on their own. Null when there is nothing to say. Render it:
  /// it is where the server explains a total that would otherwise look wrong.
  final String? note;

  /// No activity in the range. Not an error and not a failure to load — a shop that sold nothing
  /// last week has an empty statement, and the screen should say so plainly.
  bool get isEmpty => lines.isEmpty && entries.isEmpty;

  factory Statement.fromJson(Map<String, dynamic> json) => Statement(
        kind: CounterpartyKind.fromWire(json['kind'] as String?),
        kindWire: json['kind'] as String? ?? '',
        ref: json['ref'] as String? ?? '',
        name: json['name'] as String? ?? '',
        from: _calendarDate(json['from']),
        to: _calendarDate(json['to']),
        currency: json['currency'] as String? ?? '',
        generatedAt: _instant(json['generatedAt']),
        lines: _list(json['lines'], StatementLine.fromJson),
        entries: _list(json['entries'], StatementEntry.fromJson),
        // No net block at all becomes an unknown one, never a settled zero. See
        // [NetDirection.unknown].
        net: json['net'] is Map
            ? StatementNet.fromJson(Map<String, dynamic>.from(json['net'] as Map))
            : StatementNet.unknown,
        note: json['note'] as String?,
      );
}

/// One row of the Backoffice's counterparty list: who had activity, and the headline number.
class CounterpartySummary {
  const CounterpartySummary({
    required this.kindWire,
    required this.ref,
    required this.name,
    required this.direction,
    required this.orders,
    this.kind,
    this.net,
    this.recipient,
    this.lastSentAt,
  });

  /// See [Statement.kind] — typed when known, and always available raw for opening the row.
  final CounterpartyKind? kind;
  final String kindWire;

  final String ref;
  final String name;

  /// The headline figure. Null when the server sent none; see [Money.parse].
  final Money? net;

  final NetDirection direction;

  /// How many orders are behind the figure. Zero when the server did not say — a count, not money,
  /// and a missing count misstates nothing that a reader would act on.
  final int orders;

  /// Where a statement would be sent. Null when no address is known — and the send route answers
  /// 409 in exactly that case unless one is supplied, so a screen should ask for one rather than
  /// offer a button that will fail.
  final String? recipient;

  /// When a statement was last sent to them, or null if never. Null is ordinary: nobody has been
  /// sent anything until somebody sends it.
  final DateTime? lastSentAt;

  /// Whether pressing send would need an address typed in first.
  bool get needsRecipient => recipient == null || recipient!.isEmpty;

  /// Whether anything has ever been sent.
  bool get everSent => lastSentAt != null;

  /// The headline figure signed from the counterparty's point of view. Null when there is none.
  String? get signedNet => net?.signedFor(direction.asLineDirection);

  factory CounterpartySummary.fromJson(Map<String, dynamic> json) => CounterpartySummary(
        kind: CounterpartyKind.fromWire(json['kind'] as String?),
        kindWire: json['kind'] as String? ?? '',
        ref: json['ref'] as String? ?? '',
        name: json['name'] as String? ?? '',
        net: Money.parse(json['net']),
        direction: NetDirection.fromWire(json['direction'] as String?),
        orders: (json['orders'] as num?)?.toInt() ?? 0,
        recipient: json['recipient'] as String?,
        lastSentAt: _instant(json['lastSentAt']),
      );
}

/// Money in the range that belongs to nobody the ledger could name.
///
/// The reason this block is in the contract at all: settlement resolved every genuinely onboarded
/// merchant to one omnibus bucket, so figures existed that no counterparty row accounted for. A
/// listing that quietly dropped them would balance on screen and not in the bank.
class UnattributedTotal {
  const UnattributedTotal({required this.orders, this.amount, this.note});

  /// Null when the server sent no figure. Not zero — "we could not total it" must never render as
  /// "there is none", which is the very claim that hid this problem.
  final Money? amount;

  final int orders;

  /// The server's explanation of what is in here. Render it beside the figure.
  final String? note;

  /// Whether there is genuinely nothing unattributed: a readable zero and no orders behind it.
  bool get isClean => (amount?.isZero ?? false) && orders == 0;

  factory UnattributedTotal.fromJson(Map<String, dynamic> json) => UnattributedTotal(
        amount: Money.parse(json['amount']),
        orders: (json['orders'] as num?)?.toInt() ?? 0,
        note: json['note'] as String?,
      );
}

/// The Backoffice listing: everyone with activity in the range, plus what could not be attributed.
class CounterpartyListing {
  const CounterpartyListing({
    required this.currency,
    required this.counterparties,
    this.from,
    this.to,
    this.unattributed,
  });

  /// Inclusive calendar dates, as sent. See [Statement.from].
  final DateTime? from;
  final DateTime? to;

  final String currency;
  final List<CounterpartySummary> counterparties;

  /// Null when the server did not send the block at all — an older build, say.
  ///
  /// Null rather than an empty total, because an empty total is a claim that everything was
  /// attributed, and that claim is what nobody noticed was false.
  final UnattributedTotal? unattributed;

  /// Nobody traded in the range. Not an error.
  bool get isEmpty => counterparties.isEmpty;

  factory CounterpartyListing.fromJson(Map<String, dynamic> json) => CounterpartyListing(
        from: _calendarDate(json['from']),
        to: _calendarDate(json['to']),
        currency: json['currency'] as String? ?? '',
        counterparties: _list(json['counterparties'], CounterpartySummary.fromJson),
        unattributed: json['unattributed'] is Map
            ? UnattributedTotal.fromJson(
                Map<String, dynamic>.from(json['unattributed'] as Map))
            : null,
      );
}

/// The receipt for a statement that went out.
///
/// [dispatchId] is the handle to quote when somebody says they never got it.
class StatementDispatch {
  const StatementDispatch({required this.sentTo, required this.dispatchId, this.sentAt});

  final String sentTo;
  final DateTime? sentAt;
  final String dispatchId;

  factory StatementDispatch.fromJson(Map<String, dynamic> json) => StatementDispatch(
        sentTo: json['sentTo'] as String? ?? '',
        sentAt: _instant(json['sentAt']),
        dispatchId: json['dispatchId'] as String? ?? '',
      );
}

/// An instant, moved to the reader's own clock.
DateTime? _instant(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

/// A calendar date, deliberately NOT moved. `2026-08-01` parses to midnight where the reader is and
/// stays the first of August; running it through `toLocal()` would land some readers on July 31st.
DateTime? _calendarDate(Object? value) => value is String ? DateTime.tryParse(value) : null;

/// A JSON array of objects, or an empty list for anything else — including the null an empty
/// statement may carry. Nothing to show is not a parse failure.
///
/// Every object in the array is kept. The looser `Map<dynamic, dynamic>` test and the copy are
/// there because a decoder that hands back an untyped map would otherwise have its rows silently
/// filtered out, and a statement quietly missing a line still shows a total — one that no longer
/// matches the lines above it.
List<T> _list<T>(Object? value, T Function(Map<String, dynamic>) parse) {
  if (value is! List) return <T>[];
  return value
      .whereType<Map<dynamic, dynamic>>()
      .map((Map<dynamic, dynamic> row) => parse(Map<String, dynamic>.from(row)))
      .toList(growable: false);
}
