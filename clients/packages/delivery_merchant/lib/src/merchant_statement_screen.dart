import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

// For `merchantMaxContentWidth` and `MerchantDivider` — the column width and the hairline every
// merchant page shares.
import 'order_detail_screen.dart';

/// The shop's own statement: what the platform's ledger says it owes them over a range they pick,
/// and the orders it added up to get there.
///
/// This is the second money page a merchant has, and it answers a different question from the
/// first. [MerchantPayoutScreen] shows *which account is on file*; this shows *what the figure
/// against that account is*. Reached through `/api/accounting/statements/mine`, which resolves the
/// shop from the token — there is no ref parameter anywhere on this screen or in the client behind
/// it, because a shop can only ever be shown itself.
///
/// **The sentence under the headline number is the most important thing on the page.** The ledger
/// records a balance; the platform has no payout mechanism, so nothing has been transferred and
/// nothing is scheduled to be. A shop reading "2,121.80 owed to you" and concluding money is on its
/// way will chase a bank transfer that was never going to arrive, and will do it on the phone to
/// somebody who has to explain the difference. So the disclaimer sits directly under the figure it
/// qualifies, in the same card, at body size — not as a footnote at the bottom of a scroll, and not
/// in a tooltip. It reads on the first paint on a 360dp phone, which is what the test pins.
///
/// **Nothing here is computed.** Every amount on screen is the string the ledger wrote, handed
/// through [Money.amount] unchanged. The screen never sums the lines, never checks that
/// gross − commission = net, and never fills a missing figure in with a zero: a shop that could
/// tie a total to its own till against a number this client invented would be tying it to nothing.
/// A figure the server did not send renders as a dash.
///
/// The date range is the shop's, not ours, because the question is "does this match my week" and
/// only the shop knows which week that is. Four presets cover what a merchant actually asks for and
/// the picker covers the rest.
class MerchantStatementScreen extends StatefulWidget {
  const MerchantStatementScreen({
    super.key,
    required this.api,
    this.onBack,
    this.today,
  });

  final StatementsApi api;

  /// How the host leaves. Null draws no back affordance — a host that mounted this in a rail is
  /// already showing the way out.
  final VoidCallback? onBack;

  /// The day the ranges are measured back from. Injected only so a test can pin a range without
  /// racing midnight; every real caller leaves it null and gets the device's own clock.
  final DateTime? today;

  @override
  State<MerchantStatementScreen> createState() => _MerchantStatementScreenState();
}

/// The ranges a shop actually asks for, plus the one it has to draw itself.
enum _Preset { thisMonth, lastMonth, last7, last30, custom }

class _MerchantStatementScreenState extends State<MerchantStatementScreen> {
  /// How far back the picker will go.
  ///
  /// 365 days rather than "forever": the server refuses a range longer than
  /// [StatementsApi.maxRangeDays] and the client throws before it even asks, so a picker whose
  /// earliest date is a year ago cannot produce a range either of them will reject. The alternative
  /// — an open picker plus an error afterwards — teaches a shop owner that the screen is broken.
  static const int _pickerHorizon = 365;

  late final DateTime _today = _dayOf(widget.today ?? DateTime.now());

  _Preset _preset = _Preset.thisMonth;
  late DateTime _from = DateTime(_today.year, _today.month);
  late DateTime _to = _today;

  Statement? _statement;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Statement statement = await widget.api.mine(from: _from, to: _to);
      if (!mounted) return;
      setState(() {
        _statement = statement;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // The old statement goes with it. Leaving August's figures on screen under a September
        // heading because September failed is the one thing worse than an error on a money page.
        _statement = null;
        _error = e;
        _loading = false;
      });
    }
  }

  /// Surfaces the server's own explanation, the way every other merchant screen does.
  static String _serverMessage(Object error) {
    final RegExpMatch? detail =
        RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(error.toString());
    return detail?.group(1) ?? error.toString();
  }

  static DateTime _dayOf(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  void _choose(_Preset preset) {
    if (preset == _Preset.custom) {
      _pickRange();
      return;
    }
    final DateTime start = switch (preset) {
      _Preset.thisMonth => DateTime(_today.year, _today.month),
      _Preset.lastMonth => DateTime(_today.year, _today.month - 1),
      _Preset.last7 => _today.subtract(const Duration(days: 6)),
      _Preset.last30 => _today.subtract(const Duration(days: 29)),
      // Handled above; the switch is exhaustive so the compiler keeps it that way.
      _Preset.custom => _from,
    };
    // Last month ends on its own last day, not today — otherwise "Last month" would quietly
    // include this one and the shop would be reconciling a period nobody asked for.
    final DateTime end = preset == _Preset.lastMonth
        ? DateTime(_today.year, _today.month, 0)
        : _today;

    setState(() {
      _preset = preset;
      _from = start;
      _to = end;
    });
    _load();
  }

  Future<void> _pickRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: _today.subtract(const Duration(days: _pickerHorizon)),
      lastDate: _today,
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _preset = _Preset.custom;
      _from = _dayOf(picked.start);
      _to = _dayOf(picked.end);
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final MerchantStatementWords w = MerchantStatementWords.of(context);
    final MaterialLocalizations dates = MaterialLocalizations.of(context);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: Column(
        children: <Widget>[
          YdScreenHeader(
            title: w.title,
            subtitle: '${dates.formatShortDate(_from)} – ${dates.formatShortDate(_to)}',
            onBack: widget.onBack,
            backSemanticLabel: t.back,
          ),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: merchantMaxContentWidth),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    DeliverySpacing.lg,
                    DeliverySpacing.md,
                    DeliverySpacing.lg,
                    DeliverySpacing.lg + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: <Widget>[
                    _presets(w),
                    const SizedBox(height: DeliverySpacing.md),
                    ..._body(t, w, dates),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- the range

  Widget _presets(MerchantStatementWords w) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final _Preset preset in _Preset.values) ...<Widget>[
            YdChip(
              label: w.presetLabel(preset.index),
              icon: preset == _Preset.custom ? Icons.date_range_outlined : null,
              selected: _preset == preset,
              onTap: () => _choose(preset),
            ),
            const SizedBox(width: DeliverySpacing.sm),
          ],
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- the body

  List<Widget> _body(
    DeliveryStrings t,
    MerchantStatementWords w,
    MaterialLocalizations dates,
  ) {
    if (_loading) {
      return const <Widget>[
        Padding(
          padding: EdgeInsets.all(DeliverySpacing.xl),
          child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
        ),
      ];
    }

    final Object? error = _error;
    if (error != null) {
      // No figure of any kind here. A money page that answers a failed request with a number —
      // even a zero, even a stale one — has told the shop something the ledger never said.
      return <Widget>[
        YdCard.bordered(
          child: YdEmptyState(
            icon: Icons.cloud_off_rounded,
            title: w.couldNotLoad,
            message: _serverMessage(error),
            action: YdPillButton.secondary(
              label: t.tryAgain,
              onPressed: _load,
              size: YdPillButtonSize.compact,
              expand: false,
            ),
          ),
        ),
      ];
    }

    final Statement? statement = _statement;
    if (statement == null) return const <Widget>[];

    if (statement.isEmpty) {
      // Deliberately not the net card with a 0.00 in it. "Nothing was recorded for you in these
      // dates" and "you are square with the platform" are different claims, and the ledger has only
      // made the first one.
      return <Widget>[
        YdCard.bordered(
          child: YdEmptyState(
            icon: Icons.receipt_long_outlined,
            title: w.noneInRange,
            message: w.noneInRangeBody,
          ),
        ),
      ];
    }

    return <Widget>[
      _netCard(w, statement),
      if (statement.note != null && statement.note!.isNotEmpty) ...<Widget>[
        const SizedBox(height: DeliverySpacing.md),
        _serverNote(statement.note!),
      ],
      if (statement.lines.isNotEmpty) ...<Widget>[
        const SizedBox(height: DeliverySpacing.md),
        _summaryCard(w, statement),
      ],
      if (statement.entries.isNotEmpty) ...<Widget>[
        const SizedBox(height: DeliverySpacing.md),
        _entriesCard(w, dates, statement),
      ],
      if (statement.generatedAt != null) ...<Widget>[
        const SizedBox(height: DeliverySpacing.md),
        Text(
          w.asAt('${dates.formatShortDate(statement.generatedAt!)} '
              '${dates.formatTimeOfDay(TimeOfDay.fromDateTime(statement.generatedAt!))}'),
          style: const TextStyle(fontSize: 11, color: DeliveryColors.faint, height: 1.35),
        ),
      ],
    ];
  }

  // ------------------------------------------------------------ the headline

  /// The bottom line, in words first and digits second.
  ///
  /// The contract signs the net from the platform's point of view, which is exactly backwards for
  /// the person reading it here — so the sign is dropped entirely and the direction is spelled out.
  /// A shop owner should not have to work out whether a minus in front of their own balance means
  /// they are owed or they owe.
  Widget _netCard(MerchantStatementWords w, Statement statement) {
    final Money? amount = statement.net.amount;

    return YdCard.bordered(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            w.directionWord(statement.net.direction),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.muted,
              height: 1.3,
            ),
          ),
          const SizedBox(height: DeliverySpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Flexible(
                child: Text(
                  // Unsigned on purpose — the words above carry the direction. An unreadable or
                  // missing figure is a dash, never a zero.
                  amount == null ? w.unknownFigure : amount.unsigned,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.15,
                  ),
                ),
              ),
              if (statement.currency.isNotEmpty) ...<Widget>[
                const SizedBox(width: DeliverySpacing.sm),
                Text(
                  statement.currency,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.muted,
                    height: 1.2,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: DeliverySpacing.md),
          _NotAPaymentNotice(text: w.notAPayment),
          const SizedBox(height: DeliverySpacing.sm),
          Text(
            w.tieToTill,
            style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.45),
          ),
        ],
      ),
    );
  }

  /// The server's own sentence about this statement, when it sent one.
  ///
  /// Rendered rather than dropped: it is where the accounting service explains a total that would
  /// otherwise look wrong — a commission line it could not attribute, a list of orders it trimmed.
  Widget _serverNote(String note) => YdCard.bordered(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.info_outline, size: 16, color: DeliveryColors.muted),
            const SizedBox(width: DeliverySpacing.sm),
            Expanded(
              child: Text(
                note,
                style: const TextStyle(
                  fontSize: 12,
                  color: DeliveryColors.muted,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      );

  // -------------------------------------------------------------- the summary

  Widget _summaryCard(MerchantStatementWords w, Statement statement) {
    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          YdSectionHeader(title: w.summary),
          const SizedBox(height: DeliverySpacing.sm),
          for (final StatementLine line in statement.lines) _summaryLine(w, line),
          const SizedBox(height: DeliverySpacing.sm),
          Text(
            w.summaryLegend,
            style: const TextStyle(fontSize: 11, color: DeliveryColors.faint, height: 1.35),
          ),
        ],
      ),
    );
  }

  /// One summary row. The label, the note and the percentage in "Platform commission (12.5%)" are
  /// all the server's words: the rate lives where it is applied, and a client that formatted its
  /// own would go stale the day one shop is moved off the standard rate.
  Widget _summaryLine(MerchantStatementWords w, StatementLine line) {
    final bool away = line.direction == LedgerDirection.debit;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.xs + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  line.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
                if (line.note != null && line.note!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    line.note!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: DeliveryColors.muted,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            flex: 3,
            child: Text(
              line.signedAmount ?? w.unknownFigure,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: away ? DeliveryColors.muted : DeliveryColors.ink,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- the orders

  /// Order by order, which is the half of this screen a shop can actually check.
  ///
  /// The server trims a very long list and says so in [Statement.note], which is rendered above —
  /// this list shows what arrived and does not claim to be complete on its own.
  Widget _entriesCard(
    MerchantStatementWords w,
    MaterialLocalizations dates,
    Statement statement,
  ) {
    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          YdSectionHeader(title: w.ordersBehind),
          const SizedBox(height: DeliverySpacing.sm),
          _entryRow(
            order: w.orderColumn,
            gross: w.totalColumn,
            commission: w.commissionColumn,
            net: w.yoursColumn,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.muted,
              height: 1.3,
            ),
          ),
          const MerchantDivider(),
          const SizedBox(height: DeliverySpacing.xs),
          for (final StatementEntry entry in statement.entries)
            _entryRow(
              // The same first-eight rule the order cards and the order detail header use, so the
              // row a merchant is looking at here is the row they can find in their queue.
              order: '#${_shortId(entry.orderId)}',
              subtitle: entry.at == null ? null : dates.formatShortDate(entry.at!),
              gross: entry.gross?.amount ?? w.unknownFigure,
              commission: entry.commission?.amount ?? w.unknownFigure,
              net: entry.net?.amount ?? w.unknownFigure,
            ),
          if (statement.entries.any((StatementEntry e) => e.at != null)) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Text(
              // The accounting service has no delivered-at column on its ledger legs, so the
              // instant it can give for a merchant entry is when settlement was written — which is
              // however long the event bus took after the rider closed the order. A shop
              // reconciling by day would otherwise find an order on the wrong side of midnight and
              // go looking for a mistake that is only a lag.
              w.entriesDateNote,
              style: const TextStyle(
                fontSize: 11,
                color: DeliveryColors.faint,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _entryRow({
    required String order,
    required String gross,
    required String commission,
    required String net,
    String? subtitle,
    TextStyle? style,
  }) {
    const TextStyle figure = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: DeliveryColors.ink,
      height: 1.3,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.xs + 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  order,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style ?? figure,
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: DeliveryColors.faint,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (final String value in <String>[gross, commission, net])
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: DeliverySpacing.xs),
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style ?? figure,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _shortId(String id) => id.length <= 8 ? id : id.substring(0, 8);
}

/// The unmissable half of this screen, drawn as a block rather than as a line of small print.
///
/// Its own widget so it cannot be quietly demoted to a caption by a later layout change, and so a
/// test can assert it is on screen by type as well as by text.
class _NotAPaymentNotice extends StatelessWidget {
  const _NotAPaymentNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
      decoration: BoxDecoration(
        color: DeliveryAccent.info.tint,
        borderRadius: BorderRadius.circular(merchantChipRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 16, color: DeliveryAccent.info.color),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                // Ink rather than the accent: per the palette rule in `tokens.dart`, accent text at
                // body size does not clear AA on its own tint, and this is the one paragraph on the
                // page that has to be readable.
                color: DeliveryColors.ink,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The words this screen needs, in the two languages the app ships.
///
/// **Why these are not in `delivery_l10n` like every other string in this package.** They should
/// be, and the day somebody opens that package for another reason they should move. This change was
/// scoped to `delivery_merchant` alone — `delivery_l10n` is a shared package with two other client
/// surfaces being written against it in parallel, and adding keys to its ARB files plus the three
/// generated Dart files from here is precisely the kind of edit that lands as a conflict in
/// somebody else's branch. The alternative was to ship the most consequential sentence on the
/// merchant surface in English only, in a market where the settings screen has an Arabic toggle on
/// it. That was worse. So the strings live here, translated, with this note attached.
///
/// The line labels themselves — "Goods sold", "Platform commission (12.5%)" — are the *server's*
/// words and arrive in English regardless. Nothing on the client can fix that; it needs the
/// accounting service to render its own labels per locale, and it is worth doing before this screen
/// is put in front of an Arabic-speaking shop.
class MerchantStatementWords {
  const MerchantStatementWords._({
    required this.title,
    required this.notAPayment,
    required this.tieToTill,
    required this.summary,
    required this.summaryLegend,
    required this.ordersBehind,
    required this.entriesDateNote,
    required this.orderColumn,
    required this.totalColumn,
    required this.commissionColumn,
    required this.yoursColumn,
    required this.noneInRange,
    required this.noneInRangeBody,
    required this.couldNotLoad,
    required this.owedToYou,
    required this.youOwe,
    required this.settled,
    required this.unclear,
    required this.unknownFigure,
    required this.presetThisMonth,
    required this.presetLastMonth,
    required this.presetLast7,
    required this.presetLast30,
    required this.presetCustom,
    required this.asAtTemplate,
  });

  final String title;

  /// The sentence this screen exists to get right. See the class doc on [MerchantStatementScreen].
  final String notAPayment;

  final String tieToTill;
  final String summary;
  final String summaryLegend;
  final String ordersBehind;

  /// Why a row's date can sit a little after the day the shop remembers handing the order over.
  final String entriesDateNote;

  final String orderColumn;
  final String totalColumn;
  final String commissionColumn;
  final String yoursColumn;
  final String noneInRange;
  final String noneInRangeBody;
  final String couldNotLoad;

  final String owedToYou;
  final String youOwe;
  final String settled;
  final String unclear;

  /// What stands in for a figure the server did not send. Never a zero — see [Money.parse].
  final String unknownFigure;

  final String presetThisMonth;
  final String presetLastMonth;
  final String presetLast7;
  final String presetLast30;
  final String presetCustom;

  final String asAtTemplate;

  String asAt(String when) => asAtTemplate.replaceFirst('{when}', when);

  /// The direction told to the shop itself.
  ///
  /// [NetDirection] carries an English `selfLabel` already; this switch exists so the Arabic build
  /// gets one too. [NetDirection.unknown] stays "unclear" rather than collapsing into "settled" —
  /// claiming nobody is waiting on money is not a safe default for the person waiting on it.
  String directionWord(NetDirection direction) => switch (direction) {
        NetDirection.weOwe => owedToYou,
        NetDirection.theyOwe => youOwe,
        NetDirection.settled => settled,
        NetDirection.unknown => unclear,
      };

  /// Indexed by `_Preset.index`, which is private to this library — the enum is an implementation
  /// detail of the screen and the words are not.
  String presetLabel(int index) => <String>[
        presetThisMonth,
        presetLastMonth,
        presetLast7,
        presetLast30,
        presetCustom,
      ][index];

  static const MerchantStatementWords en = MerchantStatementWords._(
    title: 'Your statement',
    notAPayment:
        'This is what the platform\'s ledger records for these dates. It is not a payment. '
        'There is no payout yet, so no money has been transferred to you and none is scheduled — '
        'settling up is still arranged with the platform directly.',
    tieToTill: 'Every order the ledger counted is listed below, so you can check it against '
        'your own till.',
    summary: 'How it adds up',
    summaryLegend:
        'A + is counted in your favour. A - is what the platform kept out of it.',
    ordersBehind: 'Order by order',
    entriesDateNote: 'The date is when the platform settled the order, which can fall a little '
        'after you handed it over.',
    orderColumn: 'Order',
    totalColumn: 'Customer paid',
    commissionColumn: 'Commission',
    yoursColumn: 'Yours',
    noneInRange: 'No orders in these dates',
    noneInRangeBody:
        'The ledger recorded nothing for your shop in this range. That is not the same as a '
        'balance of zero — pick a different range to see a period you traded in.',
    couldNotLoad: 'Could not load your statement',
    owedToYou: 'Owed to you',
    youOwe: 'You owe the platform',
    settled: 'Settled',
    unclear: 'Unclear',
    unknownFigure: '—',
    presetThisMonth: 'This month',
    presetLastMonth: 'Last month',
    presetLast7: 'Last 7 days',
    presetLast30: 'Last 30 days',
    presetCustom: 'Pick dates',
    asAtTemplate: 'Figures as the ledger stood on {when}.',
  );

  static const MerchantStatementWords ar = MerchantStatementWords._(
    title: 'كشف حسابك',
    notAPayment: 'هذا ما يسجّله دفتر المنصّة لهذه التواريخ، وهو ليس دفعة. '
        'لا يوجد صرف بعد، فلم يُحوَّل إليك أي مبلغ ولا يوجد تحويل مجدول — '
        'وتسوية المستحقّات ما زالت تتم مع المنصّة مباشرة.',
    tieToTill: 'كل طلب احتسبه الدفتر مذكور بالأسفل، لتقارنه بصندوقك.',
    summary: 'كيف تكوّن المبلغ',
    summaryLegend: 'علامة + مبلغ محسوب لصالحك، وعلامة - مبلغ اقتطعته المنصّة منه.',
    ordersBehind: 'طلباً طلباً',
    entriesDateNote: 'التاريخ هو وقت تسوية المنصّة للطلب، وقد يقع بعد تسليمك له بقليل.',
    orderColumn: 'الطلب',
    totalColumn: 'دفع العميل',
    commissionColumn: 'العمولة',
    yoursColumn: 'لك',
    noneInRange: 'لا طلبات في هذه التواريخ',
    noneInRangeBody: 'لم يسجّل الدفتر شيئاً لمتجرك في هذه الفترة. '
        'وهذا لا يعني أن رصيدك صفر — اختر فترة أخرى لترى مدّة كان فيها بيع.',
    couldNotLoad: 'تعذّر تحميل كشف حسابك',
    owedToYou: 'مستحق لك',
    youOwe: 'عليك للمنصّة',
    settled: 'مُسوّى',
    unclear: 'غير واضح',
    unknownFigure: '—',
    presetThisMonth: 'هذا الشهر',
    presetLastMonth: 'الشهر الماضي',
    presetLast7: 'آخر 7 أيام',
    presetLast30: 'آخر 30 يوماً',
    presetCustom: 'اختر التواريخ',
    asAtTemplate: 'الأرقام كما كان عليها الدفتر في {when}.',
  );

  /// Falls back to English for any locale this build does not translate, which is the same thing
  /// the generated strings do.
  static MerchantStatementWords of(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ar' ? ar : en;
}
