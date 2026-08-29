import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../shell/console_controls.dart';
import '../shell/shell.dart';

/// Counterparty statements. BACKOFFICE only.
///
/// The screen next door — Reconciliation — answers "what has not settled". This one answers the
/// question that comes after it: *who are we square with*, and has anybody actually been told. A
/// ledger that balances internally and has never put a figure in front of the shop it belongs to is
/// a ledger nobody outside this building has agreed with.
///
/// Three decisions shape it.
///
/// **The unattributed remainder is on the page, not behind a link.** Settlement resolved every
/// genuinely onboarded merchant into one omnibus bucket, so there are real figures that no
/// counterparty row accounts for. A list that quietly dropped them would balance on screen and not
/// in the bank — which is exactly how the omnibus problem survived as long as it did. So it is
/// drawn above the table, in money, with the server's own explanation beside it, and it disappears
/// only when the server says it is genuinely clean.
///
/// **Nothing here does arithmetic.** Every figure is the string the ledger wrote, rendered
/// unchanged; a missing one renders as a dash and never as `0.00`. See [Money] — "we were not told"
/// and "nothing is owed" are different statements about somebody's pay.
///
/// **Send is confirmed, and the confirmation names the address.** This is the only control in the
/// portal that puts a number in front of a business we do not employ. An operator has to see who it
/// is going to before it goes, because the mistake — a shop's figures mailed to a different shop —
/// cannot be recalled.
class StatementsScreen extends StatefulWidget {
  const StatementsScreen({super.key, required this.api, this.notificationApi});

  final StatementsApi api;

  /// The operator's own in-app inbox, behind the header's bell. Optional so the screen can be
  /// rendered on its own — a null one draws the bell greyed rather than polling nothing.
  final NotificationApi? notificationApi;

  @override
  State<StatementsScreen> createState() => _StatementsScreenState();
}

class _StatementsScreenState extends State<StatementsScreen> {
  /// Opens on the current month to date, which is the period an operator is asked about. A default
  /// of "everything" would be a different question and a much slower one — the listing builds a
  /// statement per counterparty behind the scenes.
  late DateTime _from = _startOfMonth(DateTime.now());
  late DateTime _to = DateTime.now();

  CounterpartyListing? _listing;
  bool _loading = true;
  Object? _error;

  /// What this session has sent, keyed by [_keyOf].
  ///
  /// Kept beside the server's `lastSentAt` rather than instead of it: the listing is rebuilt after a
  /// send, but if that refetch fails or lags, the operator still needs to see that the thing they
  /// just did happened. Only ever written on a dispatch the server confirmed — a failed send leaves
  /// no trace here, which is what stops it looking like a success.
  final Map<String, DateTime> _justSent = <String, DateTime>{};

  /// The row with a send in flight, so one press cannot become two.
  String? _sending;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// Counterparty AND period.
  ///
  /// The period is not decoration here. A dispatch is recorded against a range — the server's own
  /// 409 quotes the range it already sent — so "has this shop been told" is only answerable about
  /// one period at a time. Keyed on the counterparty alone, sending August then widening the
  /// picker to the whole year showed every period as already sent, including ones nobody had ever
  /// been told about. That is the one column on this screen whose entire job is to answer whether
  /// somebody outside the building has actually been informed.
  String _keyOf(CounterpartySummary row) => '${row.kindWire}/${row.ref}/$_from/$_to';

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final CounterpartyListing loaded =
          await widget.api.counterparties(from: _from, to: _to);
      if (!mounted) return;
      setState(() {
        _listing = loaded;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// The period, picked as a range because a statement is a period and not two dates that happen to
  /// be near each other.
  ///
  /// An over-long range is refused here with the old period left standing, rather than sent and
  /// bounced. [StatementsApi] would throw for it synchronously and the server would answer 400; a
  /// picker that silently blanks the screen for a rule nobody stated is worse than one that says
  /// what the rule is.
  Future<void> _pickPeriod() async {
    final DateTime today = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 3),
      lastDate: today,
      initialDateRange: DateTimeRange(start: _from, end: _to),
      helpText: 'Statement period',
      saveText: 'Use period',
    );
    if (picked == null || !mounted) return;

    final int days = picked.end.difference(picked.start).inDays + 1;
    if (days > StatementsApi.maxRangeDays) {
      _tell(
        'A statement covers at most ${StatementsApi.maxRangeDays} days and that period is $days. '
        'The period is unchanged.',
        bad: true,
      );
      return;
    }

    setState(() {
      _from = picked.start;
      _to = picked.end;
    });
    await _refresh();
  }

  // ------------------------------------------------------------------ drilling in

  /// The full statement behind one row, beside the list rather than over it.
  ///
  /// The request is made before the drawer opens so the future is created exactly once; building it
  /// inside the builder would refetch on every rebuild of the panel, and each of those is a real
  /// query against the ledger.
  void _open(CounterpartySummary row) {
    final Future<Statement> pending = widget.api.statement(
      kind: row.kindWire,
      ref: row.ref,
      from: _from,
      to: _to,
    );
    showConsoleDrawer<void>(
      context: context,
      title: _nameOf(row),
      subtitle: '${_date(_from)} → ${_date(_to)}',
      badge: ConsoleQuietChip(label: row.kind?.label ?? row.kindWire),
      width: 560,
      builder: (BuildContext _) => _StatementDetail(pending: pending),
    );
  }

  // -------------------------------------------------------------------- sending

  Future<void> _send(CounterpartySummary row) async {
    final _SendChoice? choice = await showDialog<_SendChoice>(
      context: context,
      builder: (BuildContext context) => _SendDialog(
        row: row,
        from: _from,
        to: _to,
        currency: _listing?.currency ?? '',
      ),
    );
    if (choice == null || !mounted) return;

    setState(() => _sending = _keyOf(row));
    try {
      final StatementDispatch receipt = await widget.api.sendStatement(
        kind: row.kindWire,
        ref: row.ref,
        from: _from,
        to: _to,
        recipient: choice.recipient,
      );
      if (!mounted) return;
      // Recorded from the receipt, not from the press: this is the moment the platform can say a
      // statement went out, and it is the only moment.
      _justSent[_keyOf(row)] = receipt.sentAt ?? DateTime.now();
      _tell('Statement sent to ${receipt.sentTo}.');
      await _refresh();
    } catch (e) {
      // No _justSent entry, no "Last sent" stamp, no success wording. A send that did not happen
      // must not leave the screen looking like one that did.
      if (mounted) _tell(_failureFrom(e), bad: true);
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  /// The server's own words where it has any.
  ///
  /// The two 409s are worth separating because they ask the operator for different things: one
  /// wants an address typed in, the other is telling them this exact period already went out and
  /// nothing was sent again. Re-sending deliberately is a server flag this client does not carry
  /// yet, so the message says what happened rather than offering a button that would not work.
  String _failureFrom(Object e) {
    if (e is DioException) {
      final Object? body = e.response?.data;
      if (body is Map) {
        final Object? code = body['code'];
        if (code == 'NO_RECIPIENT') {
          return 'Nothing was sent: no address is on file for them. '
              'Press Send again and type one in.';
        }
        if (code == 'ALREADY_SENT') {
          final Object? to = body['sentTo'];
          final Object? at = body['sentAt'];
          return 'Nothing was sent: this period already went out'
              '${to is String ? ' to $to' : ''}'
              '${at is String ? ' on ${_stamp(DateTime.tryParse(at)?.toLocal())}' : ''}.';
        }
        if (body['message'] is String) return 'Not sent: ${body['message']}';
        if (body['detail'] is String) return 'Not sent: ${body['detail']}';
      }
      final int? status = e.response?.statusCode;
      if (status != null) return 'Not sent — the server answered $status.';
    }
    return 'Not sent. Nothing has gone to them; try again.';
  }

  void _tell(String message, {bool bad = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: bad ? DeliveryAccent.critical.color : null,
      duration: Duration(seconds: bad ? 8 : 4),
    ));
  }

  // ---------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return ConsolePage(
      header: ConsoleTopbar(
        title: 'Statements',
        subtitle: 'What the platform owes each shop, rider and delivery company over a period — '
            'and what has actually been sent to them',
        actions: <Widget>[
          ConsoleFilterButton(
            label: '${_date(_from)} → ${_date(_to)}',
            icon: Icons.date_range_outlined,
            onPressed: _loading ? null : _pickPeriod,
          ),
          ConsoleBell(api: widget.notificationApi),
          ConsoleIconAction(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      children: _body(),
    );
  }

  List<Widget> _body() {
    if (_loading && _listing == null) {
      return <Widget>[
        const ConsoleCard(
          child: SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
          ),
        ),
      ];
    }
    if (_error != null) {
      return <Widget>[
        ConsoleCard(
          title: 'The statements could not be loaded',
          child: Text(
            '$_error',
            style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.5),
          ),
        ),
      ];
    }

    final CounterpartyListing listing = _listing!;
    return <Widget>[
      _Unattributed(total: listing.unattributed, currency: listing.currency),
      _table(listing),
    ];
  }

  Widget _table(CounterpartyListing listing) {
    final String currency = listing.currency;

    return ConsoleTable(
      minWidth: 1080,
      columns: <ConsoleColumn>[
        const ConsoleColumn(label: 'Counterparty', flex: 1),
        const ConsoleColumn(label: 'Kind', width: 140),
        const ConsoleColumn(label: 'Orders', width: 80, alignRight: true),
        ConsoleColumn(
          // The currency lives in the heading rather than on every row: it is the same for the
          // whole listing, and repeating it forty times would push the figures apart.
          label: currency.isEmpty ? 'Net' : 'Net ($currency)',
          width: 120,
          alignRight: true,
        ),
        const ConsoleColumn(label: 'Direction', width: 150),
        const ConsoleColumn(label: 'Last sent', width: 160),
        const ConsoleColumn(label: '', width: 120, alignRight: true),
      ],
      empty: const Text(
        'Nobody traded in this period. That is an answer, not a failure — widen the dates.',
        style: ConsoleText.cellMuted,
      ),
      rows: <ConsoleTableRow>[
        for (final CounterpartySummary row in listing.counterparties)
          ConsoleTableRow(
            onTap: () => _open(row),
            cells: <Widget>[
              ConsoleNameCell(
                name: _nameOf(row),
                // The ref under the name, because an unresolved counterparty is displayed by its
                // id and the operator needs to be able to tell those two apart at a glance.
                secondary: row.name.isEmpty ? 'no trading name on file' : row.ref,
              ),
              Text(row.kind?.label ?? row.kindWire, style: ConsoleText.cellMuted),
              Text('${row.orders}', style: ConsoleText.cell),
              Text(
                _amount(row.net),
                style: ConsoleText.cellStrong,
              ),
              ConsoleStatusPill(
                label: row.direction.label,
                accent: _accentFor(row.direction),
              ),
              _LastSent(when: _sentAtOf(row)),
              ConsoleButton(
                label: 'Send',
                icon: Icons.send_outlined,
                busy: _sending == _keyOf(row),
                // One send at a time across the whole table. Two in flight would race the refresh
                // that follows each of them and leave the "Last sent" column showing whichever
                // finished last rather than what is true.
                onPressed: _sending == null ? () => _send(row) : null,
              ),
            ],
          ),
      ],
      footer: Text(
        'Tap a row for the full statement. Figures are the ledger\'s own; a dash means the server '
        'sent no number, which is not the same as nothing owed.',
        style: ConsoleText.meta.copyWith(color: DeliveryColors.faint),
      ),
    );
  }

  /// The later of what the server knows and what this session did.
  DateTime? _sentAtOf(CounterpartySummary row) {
    final DateTime? mine = _justSent[_keyOf(row)];
    final DateTime? theirs = row.lastSentAt;
    if (mine == null) return theirs;
    if (theirs == null) return mine;
    return mine.isAfter(theirs) ? mine : theirs;
  }
}

/// Their trading name, or the ref when the ledger could not resolve one.
///
/// [Statement.name] is deliberately empty rather than filled with the ref, so that an unresolved
/// counterparty does not look resolved. The screen still has to draw something, and the ref is what
/// an operator can actually act on.
String _nameOf(CounterpartySummary row) => row.name.isEmpty ? row.ref : row.name;

/// A figure exactly as the server wrote it, or a dash.
///
/// Never `0.00` for a missing value: [Money.parse] returns null for "we were not told", and printing
/// a zero there is a confident claim about somebody's money that nobody made.
String _amount(Money? money) => money?.amount ?? '—';

DeliveryAccent _accentFor(NetDirection direction) => switch (direction) {
      // Ordinary business: we owe a shop for the food it sold. Informational, not a problem.
      NetDirection.weOwe => DeliveryAccent.info,
      // The one that needs chasing — a rider holding more cash than they have earned.
      NetDirection.theyOwe => DeliveryAccent.caution,
      NetDirection.settled => DeliveryAccent.positive,
      NetDirection.unknown => DeliveryAccent.neutral,
    };

DateTime _startOfMonth(DateTime when) => DateTime(when.year, when.month, 1);

/// `yyyy-MM-dd`, the same shape the contract uses on the wire, so a date on screen and a date in a
/// support conversation about the request are the same string.
String _date(DateTime when) => '${when.year.toString().padLeft(4, '0')}'
    '-${when.month.toString().padLeft(2, '0')}'
    '-${when.day.toString().padLeft(2, '0')}';

String _stamp(DateTime? when) {
  if (when == null) return 'an unknown date';
  return '${_date(when)} ${when.hour.toString().padLeft(2, '0')}:'
      '${when.minute.toString().padLeft(2, '0')}';
}

/// Short enough for a table cell, long enough to name an order in conversation.
String _shortId(String id) => id.length <= 8 ? id : id.substring(0, 8).toUpperCase();

// ----------------------------------------------------------------- the honest remainder

/// Money in the period that belongs to nobody the ledger could name.
///
/// Drawn above the table rather than under it, and in the caution tint, because it is the one figure
/// on this screen that no row accounts for. When the server reports a genuine zero this collapses to
/// a single quiet line — the absence of a problem is worth stating once, since a screen that says
/// nothing is indistinguishable from one that never checked.
class _Unattributed extends StatelessWidget {
  const _Unattributed({required this.total, required this.currency});

  final UnattributedTotal? total;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final UnattributedTotal? t = total;

    // Null means the server sent no block at all. Not the same as zero, and saying nothing here
    // would make exactly the claim — "it all adds up" — that hid the omnibus bucket for months.
    if (t == null) {
      return Text(
        'This build of the server sent no unattributed total, so the rows below may not account '
        'for everything collected in this period.',
        style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.5),
      );
    }

    if (t.isClean) {
      return Row(
        children: <Widget>[
          Icon(Icons.verified_outlined, size: 16, color: DeliveryAccent.positive.color),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              'Every figure in this period is attributed to a counterparty below.',
              style: ConsoleText.body.copyWith(color: DeliveryColors.muted),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(ConsoleMetrics.cardPadding),
      decoration: BoxDecoration(
        color: DeliveryAccent.caution.tint,
        border: Border.all(color: DeliveryAccent.caution.line),
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.help_outline, size: 20, color: DeliveryAccent.caution.color),
          const SizedBox(width: DeliverySpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('Not attributed to anybody', style: ConsoleText.cardTitle),
                const SizedBox(height: DeliverySpacing.xs),
                Text(
                  '${_amount(t.amount)}${currency.isEmpty ? '' : ' $currency'} across '
                  '${t.orders} ${t.orders == 1 ? 'order' : 'orders'} in this period belongs to no '
                  'counterparty the ledger could name.',
                  style: ConsoleText.body.copyWith(color: DeliveryColors.ink, height: 1.5),
                ),
                if (t.note != null) ...<Widget>[
                  const SizedBox(height: DeliverySpacing.sm),
                  Text(
                    t.note!,
                    style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.5),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LastSent extends StatelessWidget {
  const _LastSent({required this.when});

  final DateTime? when;

  @override
  Widget build(BuildContext context) {
    if (when == null) {
      // "Never" rather than a dash: nobody has been sent anything until somebody sends it, and that
      // is a fact, not a missing value.
      return const Text('Never', style: ConsoleText.cellMuted);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.mark_email_read_outlined, size: 14, color: DeliveryColors.muted),
        const SizedBox(width: DeliverySpacing.xs + 2),
        Flexible(
          child: Text(
            _stamp(when),
            overflow: TextOverflow.ellipsis,
            style: ConsoleText.cellMuted,
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------------- the drill-in

/// One counterparty's full statement: the summary lines, the bottom line, and the orders behind it.
class _StatementDetail extends StatelessWidget {
  const _StatementDetail({required this.pending});

  final Future<Statement> pending;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Statement>(
      future: pending,
      builder: (BuildContext context, AsyncSnapshot<Statement> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
          );
        }
        if (snapshot.hasError) {
          return Text(
            'The statement could not be loaded: ${snapshot.error}',
            style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.5),
          );
        }

        final Statement s = snapshot.data!;
        if (s.isEmpty) {
          return Text(
            'No activity in this period. A shop that sold nothing has an empty statement; that is '
            'not a fault.',
            style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.5),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ConsoleDrawerSection(
              title: 'Summary',
              first: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final StatementLine line in s.lines) _LineRow(line: line),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: DeliverySpacing.sm),
                    child: Divider(height: 1, color: DeliveryColors.border),
                  ),
                  _NetRow(net: s.net, currency: s.currency),
                ],
              ),
            ),
            // The server's own caveat. It is where a total that would otherwise look wrong is
            // explained — a commission line omitted because the counterparty was not the only
            // payee, say — so it is rendered whenever it exists rather than only on request.
            if (s.note != null)
              ConsoleDrawerSection(
                title: 'Note',
                child: Text(
                  s.note!,
                  style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.5),
                ),
              ),
            // "Itemised", not "Orders": entries.length counts the rows that came back, and the
            // server trims that list. Labelling it Orders put a client-invented figure beside the
            // table row's own server-sent order count for the same counterparty and period, where
            // the two could differ by an order of magnitude.
            ConsoleDrawerSection(
              title: 'Itemised',
              trailing: ConsoleQuietChip(label: '${s.entries.length}'),
              child: s.entries.isEmpty
                  ? Text(
                      'The totals above are not itemised for this period.',
                      style: ConsoleText.body.copyWith(color: DeliveryColors.muted),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        for (final StatementEntry e in s.entries) _EntryRow(entry: e),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});

  final StatementLine line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(line.label, style: ConsoleText.cell),
                if (line.note != null)
                  Text(line.note!, style: ConsoleText.meta.copyWith(color: DeliveryColors.muted)),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.md),
          Text(
            // The sign is composed by the model from the line's own direction, never concatenated
            // here — a credit the server wrote as negative must not render as "+-5.00".
            line.signedAmount ?? '—',
            style: ConsoleText.cellStrong.copyWith(
              color: line.direction == LedgerDirection.debit
                  ? DeliveryAccent.critical.color
                  : DeliveryColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _NetRow extends StatelessWidget {
  const _NetRow({required this.net, required this.currency});

  final StatementNet net;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            'Net',
            style: ConsoleText.cardTitle.copyWith(fontSize: 15),
          ),
        ),
        ConsoleStatusPill(
          label: net.direction.label,
          accent: _accentFor(net.direction),
        ),
        const SizedBox(width: DeliverySpacing.sm),
        Text(
          '${_amount(net.amount)}${currency.isEmpty ? '' : ' $currency'}',
          style: ConsoleText.kpiValue.copyWith(fontSize: 20),
        ),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final StatementEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('#${_shortId(entry.orderId)}', style: ConsoleText.cellLink),
                Text(
                  <String>[
                    if (entry.at != null) _stamp(entry.at),
                    if (entry.paymentMethod != null) entry.paymentMethod!,
                  ].join(' · '),
                  style: ConsoleText.meta.copyWith(color: DeliveryColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(_amount(entry.net), style: ConsoleText.cellStrong),
              Text(
                'of ${_amount(entry.gross)} · cut ${_amount(entry.commission)}',
                style: ConsoleText.meta.copyWith(color: DeliveryColors.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------------------ sending

/// What the operator agreed to. Null [recipient] means "use whoever the server resolved".
class _SendChoice {
  const _SendChoice(this.recipient);

  final String? recipient;
}

/// The confirmation. Its whole job is to name the address before anything leaves.
///
/// The resolved address is shown read-only and has to be swapped for deliberately, rather than
/// offered as a pre-filled editable box: a text field invites a stray keystroke, and the cost of one
/// here is a shop's figures arriving at somebody else's inbox.
///
/// A counterparty with no address on file starts in the typed-address state. The server answers 409
/// for that case, so offering a Send that could only fail would be a button that lies. Carriers are
/// always in this state today — a provider id is not a Keycloak subject, so there is genuinely
/// nothing to look up.
class _SendDialog extends StatefulWidget {
  const _SendDialog({
    required this.row,
    required this.from,
    required this.to,
    required this.currency,
  });

  final CounterpartySummary row;
  final DateTime from;
  final DateTime to;
  final String currency;

  @override
  State<_SendDialog> createState() => _SendDialogState();
}

class _SendDialogState extends State<_SendDialog> {
  late bool _typing = widget.row.needsRecipient;
  final TextEditingController _address = TextEditingController();

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  bool get _ready => !_typing || _address.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final CounterpartySummary row = widget.row;

    return AlertDialog(
      backgroundColor: DeliveryColors.white,
      surfaceTintColor: DeliveryColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
      title: Text('Send ${_nameOf(row)} their statement?', style: ConsoleText.cardTitle),
      content: SizedBox(
        width: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'They will be sent the figures for '
              '${_date(widget.from)} → ${_date(widget.to)}: '
              '${_amount(row.net)}${widget.currency.isEmpty ? '' : ' ${widget.currency}'} '
              'across ${row.orders} ${row.orders == 1 ? 'order' : 'orders'}, '
              '${row.direction.label.toLowerCase()}.',
              style: ConsoleText.body.copyWith(color: DeliveryColors.ink, height: 1.5),
            ),
            const SizedBox(height: DeliverySpacing.md),
            if (_typing) ...<Widget>[
              if (row.needsRecipient)
                Padding(
                  padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
                  child: Text(
                    'No address is on file for them, so one has to be typed in. Check it against '
                    'something other than this screen — nothing here can verify it.',
                    style: ConsoleText.body.copyWith(
                      color: DeliveryAccent.caution.color,
                      height: 1.5,
                    ),
                  ),
                ),
              TextField(
                controller: _address,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Send to',
                  hintText: 'name@example.com',
                ),
              ),
              if (!row.needsRecipient)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _typing = false),
                    child: Text('Use ${row.recipient} instead'),
                  ),
                ),
            ] else ...<Widget>[
              ConsoleReadOnlyField(label: 'Sends to', value: row.recipient!),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _typing = true),
                  child: const Text('Use a different address'),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        ConsoleButton(
          label: 'Cancel',
          tone: ConsoleButtonTone.outlined,
          onPressed: () => Navigator.of(context).pop(),
        ),
        ConsoleButton(
          label: 'Send statement',
          tone: ConsoleButtonTone.solid,
          icon: Icons.send_outlined,
          onPressed: _ready
              ? () => Navigator.of(context).pop(
                    _SendChoice(_typing ? _address.text.trim() : null),
                  )
              : null,
        ),
      ],
    );
  }
}
