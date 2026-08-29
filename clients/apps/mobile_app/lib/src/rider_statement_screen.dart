import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// The rider's own statement, from `GET /api/accounting/statements/mine`.
///
/// It sits behind the Earnings tab because it answers the question the earnings figures cannot: not
/// "what did I earn", which the ledger already shows, but "where do I stand with the platform" —
/// cash taken at the door, less whatever has been handed back, against what has been earned, and
/// the single number that settles the three.
///
/// **A rider is normally in debt here, and that is the hardest thing on this screen to say
/// honestly.** Every order is cash: the rider collects the whole basket at the door, so within
/// minutes of a delivery they are holding the shop's goods value and the platform's commission as
/// well as their own fee. The bottom line therefore points at the platform far more often than it
/// points at the rider, and a screen that renders that as a big red minus beside somebody's name is
/// telling them their wage is negative. It is not. So:
///
/// * The settling figure is drawn **unsigned**, with its direction spelled out in a sentence — "you
///   owe the platform" / "the platform owes you" — rather than left to a plus or a minus that the
///   reader has to interpret in the platform's vantage point. [NetDirection] is defined from the
///   PLATFORM's point of view by contract, and [NetDirection.selfLabel] flips it back; those labels
///   are English-only, so the wording here comes from [DeliveryStrings] instead and the mapping is
///   done in [_netHeadline].
/// * Debt is coloured caution, never critical. Owing collected cash is the ordinary state of a
///   working shift, not a fault, and an alarm colour on the ordinary state teaches riders to ignore
///   the colour.
/// * A sentence under the figure says why the debt exists, so a rider reading it at the end of a
///   shift is not left to guess whether they have been charged for something.
///
/// The signed arithmetic still appears — on the summary lines above the total, where each line
/// carries the server's own label, so a minus is attached to "cash collected" rather than floating
/// beside a person. That is the identity made visible without any of it being recomputed here: this
/// screen adds nothing up. Every figure is a string the ledger wrote (see [Money]), and a field the
/// server did not send renders as "—" rather than as 0.00 — "we were not told" and "nothing is
/// owed" are different sentences about somebody's pay.
class RiderStatementScreen extends StatefulWidget {
  const RiderStatementScreen({super.key, required this.api});

  /// The statements client. Only [StatementsApi.mine] is called from here, and that route names
  /// nobody — whose statement comes back is decided by the token. There is deliberately no path on
  /// this screen that could ask for anyone else's.
  final StatementsApi api;

  @override
  State<RiderStatementScreen> createState() => _RiderStatementScreenState();
}

/// Which month the statement covers. Statements are settled monthly, so these are calendar months
/// rather than the Earnings tab's rolling today/week windows — a rider comparing this screen with a
/// hand-over slip is comparing months.
enum _StatementPeriod { thisMonth, lastMonth }

class _RiderStatementScreenState extends State<RiderStatementScreen> {
  _StatementPeriod _period = _StatementPeriod.thisMonth;
  late Future<Statement> _statement = _load();

  /// The inclusive range for the selected period, in the reader's own calendar.
  ///
  /// "This month" ends today rather than at the end of the month: a range running into the future
  /// would be honest but reads as a period that has already closed, and the figures in it are still
  /// moving.
  (DateTime, DateTime) get _range {
    final DateTime now = DateTime.now();
    switch (_period) {
      case _StatementPeriod.thisMonth:
        return (DateTime(now.year, now.month), DateTime(now.year, now.month, now.day));
      case _StatementPeriod.lastMonth:
        // Day zero of this month is the last day of the previous one, which spares this from
        // knowing about month lengths, leap years or which end of December it is.
        final DateTime lastOfPrevious = DateTime(now.year, now.month, 0);
        return (DateTime(lastOfPrevious.year, lastOfPrevious.month), lastOfPrevious);
    }
  }

  /// Async on purpose, so that [StatementsApi.mine]'s synchronous [ArgumentError] on a bad range
  /// arrives as a failed future the builder can render, rather than as an exception thrown out of
  /// the widget that asked for the statement. The ranges above are always inside the server's
  /// limits, so this only matters the day somebody adds a period that is not.
  Future<Statement> _load() async {
    final (DateTime from, DateTime to) = _range;
    return widget.api.mine(from: from, to: to);
  }

  void _select(_StatementPeriod period) {
    if (_period == period) return;
    setState(() {
      _period = period;
      _statement = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _header(context, t),
            Expanded(
              child: FutureBuilder<Statement>(
                future: _statement,
                builder: (BuildContext context, AsyncSnapshot<Statement> snapshot) {
                  return switch (snapshot.connectionState) {
                    // A failed load draws the failure and nothing else. No zeroes, no empty
                    // summary, no "settled" — a rider must never read a network fault as a
                    // statement that their balance is clear.
                    ConnectionState.done when snapshot.hasError => Column(
                        children: <Widget>[
                          _periodSelector(t),
                          Expanded(
                            child: YdEmptyState(
                              icon: Icons.receipt_long_outlined,
                              title: t.riderStatementCouldNotLoad,
                            ),
                          ),
                        ],
                      ),
                    ConnectionState.done => _body(context, t, snapshot.data!),
                    _ => Column(
                        children: <Widget>[
                          _periodSelector(t),
                          const Expanded(
                            child: Center(
                              child: CircularProgressIndicator(color: DeliveryColors.brand),
                            ),
                          ),
                        ],
                      ),
                  };
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- chrome

  Widget _header(BuildContext context, DeliveryStrings t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 20,
        vertical: DeliverySpacing.md - DeliverySpacing.xs,
      ),
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: Row(
        children: <Widget>[
          YdBackButton(
            onPressed: () => Navigator.of(context).maybePop(),
            semanticLabel: t.back,
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Text(
              t.riderStatementTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: DeliveryColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The same border-filled track the Earnings tab uses for today/week, so the two money screens
  /// change period the same way.
  Widget _periodSelector(DeliveryStrings t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(DeliverySpacing.xs),
        decoration: BoxDecoration(
          color: DeliveryColors.border,
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _segment(t.riderStatementPeriodThisMonth, _StatementPeriod.thisMonth),
            ),
            const SizedBox(width: DeliverySpacing.xs),
            Expanded(
              child: _segment(t.riderStatementPeriodLastMonth, _StatementPeriod.lastMonth),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment(String label, _StatementPeriod value) {
    final bool selected = _period == value;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? DeliveryColors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(DeliveryRadius.sm),
          onTap: selected ? null : () => _select(value),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: DeliverySpacing.md,
              vertical: DeliverySpacing.sm,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? DeliveryColors.ink : DeliveryColors.muted,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------- body

  Widget _body(BuildContext context, DeliveryStrings t, Statement statement) {
    return RefreshIndicator(
      onRefresh: () async => setState(() => _statement = _load()),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: <Widget>[
          _periodSelector(t),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, DeliverySpacing.sm, 20, 0),
            child: _rangeCaption(context, t, statement),
          ),
          if (statement.isEmpty)
            // Not an error and not a failure to load: a rider who worked no shifts in the period
            // has an empty statement, and the screen says so in one sentence instead of drawing an
            // empty summary card that looks like a balance of zero.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, DeliverySpacing.lg, 20, 0),
              child: YdEmptyState(
                icon: Icons.receipt_long_outlined,
                title: t.riderStatementNothingYet,
                padding: EdgeInsets.zero,
              ),
            )
          else ...<Widget>[
            if (statement.lines.isNotEmpty) ...<Widget>[
              const SizedBox(height: DeliverySpacing.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _summaryCard(t, statement),
              ),
            ],
            const SizedBox(height: DeliverySpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _netCard(t, statement),
            ),
            if (statement.entries.isNotEmpty) ...<Widget>[
              const SizedBox(height: DeliverySpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  t.riderStatementOrders,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
              for (final StatementEntry entry in statement.entries)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      20, 0, 20, DeliverySpacing.md - DeliverySpacing.xs),
                  child: _entryRow(context, t, entry),
                ),
            ],
          ],
        ],
      ),
    );
  }

  /// The period the figures cover, and when they were worked out.
  ///
  /// Both come from the server's own answer rather than from the range this screen asked for: if
  /// the two ever disagree, the one that produced the numbers is the one worth printing.
  Widget _rangeCaption(BuildContext context, DeliveryStrings t, Statement statement) {
    final MaterialLocalizations dates = MaterialLocalizations.of(context);
    final List<String> lines = <String>[
      if (statement.from != null && statement.to != null)
        t.riderStatementRangeLine(
          dates.formatMediumDate(statement.from!),
          dates.formatMediumDate(statement.to!),
        ),
      if (statement.generatedAt != null)
        t.riderStatementGeneratedAt(dates.formatMediumDate(statement.generatedAt!)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final String line in lines)
          Text(
            line,
            style: const TextStyle(
              fontSize: 11,
              color: DeliveryColors.faint,
              height: 1.4,
            ),
          ),
      ],
    );
  }

  /// The identity, one row per ledger line, in the server's own words.
  ///
  /// The signs here are the server's directions rendered by [StatementLine.signedAmount], not
  /// arithmetic: a DEBIT line carries a minus because it takes away from what the rider is owed,
  /// and it is safe to draw one here precisely because the label beside it says what it is. The
  /// same minus on the bottom line would say something false about a person.
  Widget _summaryCard(DeliveryStrings t, Statement statement) {
    return YdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            t.riderStatementSummary.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.faint,
              height: 1.3,
            ),
          ),
          const SizedBox(height: DeliverySpacing.sm),
          for (int i = 0; i < statement.lines.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: DeliverySpacing.sm),
            _summaryLine(statement.lines[i]),
          ],
        ],
      ),
    );
  }

  Widget _summaryLine(StatementLine line) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
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
                    color: DeliveryColors.faint,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: DeliverySpacing.sm),
        Text(
          // A line the server sent no figure for reads as unknown. Never 0.00 — see [Money.parse].
          line.signedAmount ?? '—',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: switch (line.direction) {
              LedgerDirection.credit => DeliveryAccent.positive.color,
              LedgerDirection.debit => DeliveryColors.ink,
              LedgerDirection.unknown => DeliveryColors.muted,
            },
            height: 1.2,
          ),
        ),
      ],
    );
  }

  /// The one number that settles the period, said in words.
  ///
  /// Unsigned, deliberately. See the class doc: the sign lives in the sentence above the figure,
  /// where a rider cannot misread which pocket it belongs to.
  Widget _netCard(DeliveryStrings t, Statement statement) {
    final NetDirection direction = statement.net.direction;
    final Color accent = switch (direction) {
      NetDirection.weOwe => DeliveryAccent.positive.color,
      // Caution, not critical. Holding the platform's cash is the ordinary state of a shift, and
      // an alarm colour on the ordinary state trains riders to ignore the colour.
      NetDirection.theyOwe => DeliveryAccent.caution.color,
      NetDirection.settled => DeliveryColors.muted,
      // A direction this build could not read is a genuine fault and is the one case that earns
      // the alarm colour, because acting on an unreadable balance is how money goes missing.
      NetDirection.unknown => DeliveryAccent.critical.color,
    };

    return YdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            _netHeadline(t, direction),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: accent,
              height: 1.3,
            ),
          ),
          const SizedBox(height: DeliverySpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: Text(
                  // `unsigned` rather than `signedAmount`: the digits the ledger wrote, with the
                  // platform-vantage minus stripped off and replaced by the sentence above.
                  statement.net.amount?.unsigned ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.15,
                  ),
                ),
              ),
              if (statement.currency.isNotEmpty) ...<Widget>[
                const SizedBox(width: DeliverySpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    statement.currency,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: DeliveryColors.faint,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: DeliverySpacing.sm),
          Text(
            _netExplainer(t, direction),
            style: const TextStyle(
              fontSize: 12,
              color: DeliveryColors.muted,
              height: 1.5,
            ),
          ),
          // The server's own words about anything the figures cannot state — a trimmed entry list,
          // a commission line it had to omit. It is where a total that looks wrong is explained,
          // so it is rendered rather than swallowed.
          if (statement.note != null && statement.note!.isNotEmpty) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            SoftNote(icon: Icons.info_outline_rounded, text: statement.note!),
          ],
        ],
      ),
    );
  }

  /// [NetDirection] is written from the platform's point of view and its `selfLabel` — the flip a
  /// counterparty app needs — is English-only. These are the same four sentences in the reader's
  /// own language.
  static String _netHeadline(DeliveryStrings t, NetDirection direction) => switch (direction) {
        NetDirection.weOwe => t.riderStatementOwedToYou,
        NetDirection.theyOwe => t.riderStatementYouOwe,
        NetDirection.settled => t.riderStatementSettled,
        NetDirection.unknown => t.riderStatementDirectionUnclear,
      };

  static String _netExplainer(DeliveryStrings t, NetDirection direction) => switch (direction) {
        NetDirection.weOwe => t.riderStatementCreditNote,
        NetDirection.theyOwe => t.riderStatementDebtNote,
        NetDirection.settled => t.riderStatementSettledNote,
        NetDirection.unknown => t.riderStatementUnclearNote,
      };

  /// One order behind the summary — the row a rider points at when a figure is disputed.
  ///
  /// `gross` is what the customer paid and `net` is what is left for the rider, so the two together
  /// are the identity restated per order: this is what you took at the door, and this much of it
  /// was yours. Neither is derived from the other here.
  Widget _entryRow(BuildContext context, DeliveryStrings t, StatementEntry entry) {
    final String shortId =
        entry.orderId.length <= 8 ? entry.orderId : entry.orderId.substring(0, 8);
    final Money? gross = entry.gross;

    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
      decoration: BoxDecoration(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: DeliveryColors.brandSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.receipt_long_outlined,
                size: 16, color: DeliveryColors.brand),
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  t.riderOrderRef(shortId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
                if (entry.at != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    MaterialLocalizations.of(context).formatMediumDate(entry.at!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: DeliveryColors.faint,
                      height: 1.3,
                    ),
                  ),
                ],
                // Only when the server actually sent it. An order with no gross is an order whose
                // door-step total this app was not told; inventing one from the net would be the
                // arithmetic this screen exists not to do.
                if (gross != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    t.riderStatementCollectedLine(gross.amount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
          Text(
            entry.net?.amount ?? '—',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
