import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../shell/console_controls.dart';
import '../shell/shell.dart';

/// The promo code register — the admin side of the promotions backend.
///
/// New as a screen because the capability is new: codes could until now only be minted by hand
/// against the API, which meant in practice they were not minted at all. This is where the
/// platform decides to give money away, so the table leads with what each code has actually cost
/// ([PromoCodeDetails.givenAway]) rather than with what it promises.
///
/// Two decisions, mirroring the server exactly: create, and deactivate. There is deliberately no
/// edit and no delete — redemptions reference the code, and what was already given away has to
/// survive the promotion being switched off — so this screen offers neither rather than faking
/// either with delete-and-recreate.
///
/// Built in the console's own table + drawer language (the merchants directory's shapes), because
/// the 2026-08 design set draws no promotions frame: a register is a table, and the detail that
/// does not fit in a 40px row goes in the drawer beside it.
class PromotionsScreen extends StatefulWidget {
  const PromotionsScreen({super.key, required this.api});

  final PromoApi api;

  @override
  State<PromotionsScreen> createState() => _PromotionsScreenState();
}

/// Which slice of the register is shown. Not statuses the server knows — reading aids over the
/// full list, computed from fields every row already carries.
enum _Tab { all, live, withdrawn }

class _PromotionsScreenState extends State<PromotionsScreen> {
  List<PromoCodeDetails> _codes = <PromoCodeDetails>[];
  _Tab _tab = _Tab.all;
  bool _loading = true;
  Object? _error;
  String? _busyId;

  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final List<PromoCodeDetails> loaded = await widget.api.codes();
      if (!mounted) return;
      setState(() {
        // Newest first: the code an operator just minted is the one they are looking for.
        _codes = loaded
          ..sort((PromoCodeDetails a, PromoCodeDetails b) =>
              (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
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

  List<PromoCodeDetails> get _visible {
    final String q = _query.trim().toLowerCase();
    return _codes.where((PromoCodeDetails c) {
      final bool inTab = switch (_tab) {
        _Tab.all => true,
        _Tab.live => c.live,
        _Tab.withdrawn => !c.active,
      };
      if (!inTab) return false;
      return q.isEmpty || c.code.toLowerCase().contains(q);
    }).toList();
  }

  int get _liveCount => _codes.where((PromoCodeDetails c) => c.live).length;

  @override
  Widget build(BuildContext context) {
    return ConsolePage(
      header: ConsoleTopbar(
        title: 'Promo Codes',
        subtitle: 'Mint and withdraw discount codes, and see what each one has cost',
        actions: <Widget>[
          // Drawn on every console frame and answered by nothing: there is no cross-entity search
          // endpoint. Rendered rather than removed, greyed rather than pretending.
          const ConsoleSearchField.global(
            hintText: 'Search backoffice...',
            enabled: false,
          ),
          const ConsoleIconAction(
            icon: Icons.notifications_none,
            tooltip: 'Notifications — no feed yet',
          ),
          const ConsoleComingSoonChip(),
          ConsoleIconAction(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      children: <Widget>[
        _controls(),
        _table(),
      ],
    );
  }

  /// The merchants directory's controls row, verbatim: tabs left, search and the primary action
  /// right, wrapping instead of overflowing on a narrow window.
  Widget _controls() {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: DeliverySpacing.md,
      runSpacing: DeliverySpacing.md,
      children: <Widget>[
        ConsoleFilterTabs(
          tabs: <ConsoleFilterTab>[
            const ConsoleFilterTab(label: 'All Codes'),
            // The count of codes taking money off orders right now — the number an operator
            // opens this page to check. Suppressed while loading rather than shown as zero.
            ConsoleFilterTab(label: 'Live Now', count: _loading ? null : _liveCount),
            const ConsoleFilterTab(label: 'Withdrawn'),
          ],
          selectedIndex: _tab.index,
          onSelected: (int i) => setState(() => _tab = _Tab.values[i]),
        ),
        Wrap(
          spacing: DeliverySpacing.md - DeliverySpacing.xs,
          runSpacing: DeliverySpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            ConsoleSearchField(
              hintText: 'Search codes...',
              controller: _search,
              width: 232,
              onChanged: (String v) => setState(() => _query = v),
            ),
            ConsolePrimaryButton(
              label: 'New Code',
              icon: Icons.add,
              onPressed: _loading ? null : _create,
            ),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------------- the table

  Widget _table() {
    if (_error != null) {
      return ConsoleCard(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.cloud_off, size: 28, color: DeliveryAccent.critical.color),
                const SizedBox(height: DeliverySpacing.sm),
                const Text('Could not load the promo codes.', style: ConsoleText.cardTitle),
                const SizedBox(height: DeliverySpacing.xs),
                Text('$_error', style: ConsoleText.meta, textAlign: TextAlign.center),
                const SizedBox(height: DeliverySpacing.md),
                ConsoleButton(label: 'Try again', onPressed: _refresh),
              ],
            ),
          ),
        ),
      );
    }

    if (_loading && _codes.isEmpty) {
      return const ConsoleCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: DeliverySpacing.xl),
            child: CircularProgressIndicator(color: DeliveryColors.brand),
          ),
        ),
      );
    }

    final List<PromoCodeDetails> rows = _visible;

    return ConsoleTable(
      minWidth: 1000,
      columns: const <ConsoleColumn>[
        ConsoleColumn(label: 'Code', flex: 1),
        ConsoleColumn(label: 'Worth', width: 150),
        ConsoleColumn(label: 'Window', width: 190),
        ConsoleColumn(label: 'Redemptions', width: 120),
        ConsoleColumn(label: 'Given Away', width: 110),
        ConsoleColumn(label: 'Status', width: 110),
        ConsoleColumn(label: 'Actions', width: 90, alignRight: true),
      ],
      rows: <ConsoleTableRow>[
        for (final PromoCodeDetails c in rows) _row(c),
      ],
      empty: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.sell_outlined, size: 28, color: DeliveryColors.faint),
            const SizedBox(height: DeliverySpacing.sm),
            Text(
              _codes.isEmpty
                  ? 'No promo code has been minted yet.'
                  : 'No code matches that filter.',
              style: ConsoleText.cellStrong,
            ),
          ],
        ),
      ),
    );
  }

  ConsoleTableRow _row(PromoCodeDetails c) {
    final bool busy = _busyId == c.id;
    final (String state, DeliveryAccent accent) = _stateOf(c);

    return ConsoleTableRow(
      onTap: () => _open(c),
      cells: <Widget>[
        ConsoleNameCell(
          name: c.code,
          secondary: c.kind.label,
          leading: ConsoleInitialTile(label: c.code),
        ),
        Text(_worth(c), overflow: TextOverflow.ellipsis, style: ConsoleText.cellMuted),
        Text(_window(c), overflow: TextOverflow.ellipsis, style: ConsoleText.cellMuted),
        Text(_redemptions(c), style: ConsoleText.cellMuted),
        Text(_money(c.givenAway), style: ConsoleText.cellStrong),
        ConsoleStatusPill(label: state, accent: accent),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (c.active)
              ConsoleRowAction(
                icon: Icons.block,
                tooltip: 'Withdraw this code',
                destructive: true,
                onPressed: busy ? null : () => _deactivate(c),
              )
            else
              // A withdrawn code stays a record — what it gave away survives it — and there is
              // deliberately nothing to press: the server has no delete and no reactivate.
              const ConsoleNoValue(tooltip: 'Withdrawn. What it gave away stays on the record.'),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------------- the drawer

  Future<void> _open(PromoCodeDetails c) async {
    final (String state, DeliveryAccent accent) = _stateOf(c);
    await showConsoleDrawer<void>(
      context: context,
      title: c.code,
      subtitle: c.kind.label,
      badge: ConsoleStatusPill(label: state, accent: accent),
      builder: (BuildContext drawerContext) => _CodeDetail(
        code: c,
        onDeactivate: c.active
            ? () {
                Navigator.of(drawerContext).pop();
                _deactivate(c);
              }
            : null,
      ),
    );
  }

  // -------------------------------------------------------------------- the decisions

  Future<void> _create() async {
    final _NewCode? made = await showDialog<_NewCode>(
      context: context,
      builder: (BuildContext context) => const _NewCodeDialog(),
    );
    if (made == null || !mounted) return;

    setState(() => _busyId = '__creating__');
    try {
      final PromoCodeDetails created = await widget.api.createCode(
        code: made.code,
        kind: made.kind,
        value: made.value,
        minSubtotal: made.minSubtotal,
        startsAt: made.startsAt,
        endsAt: made.endsAt,
        maxRedemptions: made.maxRedemptions,
        maxPerCustomer: made.maxPerCustomer,
      );
      _tell('${created.code} is minted${created.live ? ' and live' : ''}.');
      await _refresh();
    } catch (e) {
      _tell(_messageFrom(e), bad: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _deactivate(PromoCodeDetails c) async {
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: DeliveryColors.white,
        surfaceTintColor: DeliveryColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
        title: Text('Withdraw ${c.code}?', style: ConsoleText.cardTitle),
        content: const SizedBox(
          width: 420,
          // Said plainly: withdrawing is not retroactive, and it is also not reversible from
          // here — the server keeps no reactivate.
          child: Text(
            'It stops applying to new orders immediately and cannot be switched back on. '
            'Discounts already given stay given.',
            style: ConsoleText.pageSubtitle,
          ),
        ),
        actions: <Widget>[
          ConsoleButton(
            label: 'Cancel',
            tone: ConsoleButtonTone.outlined,
            onPressed: () => Navigator.pop(context, false),
          ),
          ConsoleButton(
            label: 'Withdraw',
            tone: ConsoleButtonTone.destructive,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    setState(() => _busyId = c.id);
    try {
      await widget.api.deactivate(c.id);
      _tell('${c.code} withdrawn. It no longer applies to new orders.');
      await _refresh();
    } catch (e) {
      _tell(_messageFrom(e), bad: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// The server's own words where it has any — "a promo code is 3-32 letters..." is actionable;
  /// a Dio exception is not.
  String _messageFrom(Object e) {
    if (e is DioException) {
      final Object? body = e.response?.data;
      if (body is Map) {
        if (body['message'] is String) return body['message'] as String;
        if (body['detail'] is String) return body['detail'] as String;
      }
    }
    return 'That did not go through. Try again.';
  }

  void _tell(String message, {bool bad = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: bad ? DeliveryAccent.critical.color : null,
    ));
  }

  // -------------------------------------------------------------------- reading a code out loud

  /// Live / Scheduled / Ended / Withdrawn — from fields the server sent, never guessed. `live`
  /// is the server's own verdict; the other three explain why it is not.
  static (String, DeliveryAccent) _stateOf(PromoCodeDetails c) {
    if (!c.active) return ('Withdrawn', DeliveryAccent.neutral);
    if (c.live) return ('Live', DeliveryAccent.positive);
    if (c.startsAt != null && c.startsAt!.isAfter(DateTime.now())) {
      return ('Scheduled', DeliveryAccent.info);
    }
    if (c.endsAt != null && c.endsAt!.isBefore(DateTime.now())) {
      return ('Ended', DeliveryAccent.neutral);
    }
    if (c.maxRedemptions != null && c.redeemedCount >= c.maxRedemptions!) {
      return ('Fully redeemed', DeliveryAccent.caution);
    }
    // Active, inside its window, not exhausted — and the server still says not live. Render the
    // server's verdict rather than arguing with it.
    return ('Not live', DeliveryAccent.neutral);
  }

  static String _worth(PromoCodeDetails c) {
    final String base = switch (c.kind) {
      PromoKind.percentOff => '${_trim(c.value ?? 0)}% off goods',
      PromoKind.amountOff => '${_money(c.value ?? 0)} off',
      PromoKind.freeDelivery => 'Free delivery',
    };
    return c.minSubtotal == null ? base : '$base over ${_money(c.minSubtotal!)}';
  }

  static String _window(PromoCodeDetails c) {
    if (c.startsAt == null && c.endsAt == null) return 'Always on';
    final String from = c.startsAt == null ? 'now' : _date(c.startsAt!);
    final String to = c.endsAt == null ? 'until withdrawn' : 'to ${_date(c.endsAt!)}';
    return '$from $to';
  }

  static String _redemptions(PromoCodeDetails c) =>
      c.maxRedemptions == null ? '${c.redeemedCount}' : '${c.redeemedCount} of ${c.maxRedemptions}';

  static String _money(double amount) => '\$${amount.toStringAsFixed(2)}';

  /// 12.5 → "12.5", 10.0 → "10" — a percent column of ".0"s reads like a spreadsheet error.
  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  static String _date(DateTime at) {
    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[at.month - 1]} ${at.day.toString().padLeft(2, '0')}, ${at.year}';
  }
}

/// Everything the register knows about one code, in the drawer its row opens.
class _CodeDetail extends StatelessWidget {
  const _CodeDetail({required this.code, required this.onDeactivate});

  final PromoCodeDetails code;

  /// Null once withdrawn — the drawer then carries the record and no button.
  final VoidCallback? onDeactivate;

  @override
  Widget build(BuildContext context) {
    final PromoCodeDetails c = code;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ConsoleDrawerSection(
          title: 'What it does',
          first: true,
          child: ConsoleFactGrid(
            facts: <ConsoleFact>[
              ConsoleFact('Kind', c.kind.label),
              ConsoleFact(
                'Value',
                switch (c.kind) {
                  PromoKind.percentOff =>
                    '${_PromotionsScreenState._trim(c.value ?? 0)}%',
                  PromoKind.amountOff => _PromotionsScreenState._money(c.value ?? 0),
                  PromoKind.freeDelivery => 'The delivery fee',
                },
              ),
              ConsoleFact(
                'Minimum basket',
                c.minSubtotal == null
                    ? 'None'
                    : _PromotionsScreenState._money(c.minSubtotal!),
                absent: c.minSubtotal == null,
              ),
            ],
          ),
        ),
        ConsoleDrawerSection(
          title: 'When it applies',
          child: ConsoleFactGrid(
            facts: <ConsoleFact>[
              ConsoleFact(
                'Starts',
                c.startsAt == null
                    ? 'The moment it was created'
                    : _PromotionsScreenState._date(c.startsAt!),
              ),
              ConsoleFact(
                'Ends',
                c.endsAt == null
                    ? 'When it is withdrawn'
                    : _PromotionsScreenState._date(c.endsAt!),
              ),
              ConsoleFact(
                'Total uses',
                c.maxRedemptions == null ? 'Unlimited' : '${c.maxRedemptions}',
                absent: c.maxRedemptions == null,
              ),
              ConsoleFact(
                'Per customer',
                c.maxPerCustomer == null ? 'Unlimited' : '${c.maxPerCustomer}',
                absent: c.maxPerCustomer == null,
              ),
            ],
          ),
        ),
        ConsoleDrawerSection(
          title: 'What it has cost',
          child: ConsoleFactGrid(
            facts: <ConsoleFact>[
              ConsoleFact('Redeemed', _PromotionsScreenState._redemptions(c)),
              ConsoleFact('Given away', _PromotionsScreenState._money(c.givenAway)),
            ],
          ),
        ),
        ConsoleDrawerSection(
          title: 'Record',
          child: ConsoleFactGrid(
            facts: <ConsoleFact>[
              ConsoleFact(
                'Created',
                c.createdAt == null
                    ? 'Not recorded'
                    : _PromotionsScreenState._date(c.createdAt!),
                absent: c.createdAt == null,
              ),
              ConsoleFact(
                'Created by',
                c.createdBy == null ? 'Not recorded' : _short(c.createdBy!),
                absent: c.createdBy == null,
              ),
            ],
          ),
        ),
        if (onDeactivate != null) ...<Widget>[
          const SizedBox(height: ConsoleMetrics.pageGap),
          const Divider(height: 1, color: DeliveryColors.border),
          const SizedBox(height: ConsoleMetrics.pageGap),
          ConsoleButton(
            label: 'Withdraw this code',
            icon: Icons.block,
            tone: ConsoleButtonTone.destructive,
            onPressed: onDeactivate,
          ),
        ],
      ],
    );
  }

  static String _short(String id) => id.length <= 8 ? id : '${id.substring(0, 8)}…';
}

/// What the create dialog hands back — already validated, ready for the API call.
class _NewCode {
  const _NewCode({
    required this.code,
    required this.kind,
    this.value,
    this.minSubtotal,
    this.startsAt,
    this.endsAt,
    this.maxRedemptions,
    this.maxPerCustomer,
  });

  final String code;
  final PromoKind kind;
  final double? value;
  final double? minSubtotal;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int? maxRedemptions;
  final int? maxPerCustomer;
}

/// Minting a code. Everything optional is genuinely optional — a blank window runs now-to-withdrawn
/// and blank caps are unlimited, matching the server's nulls exactly.
class _NewCodeDialog extends StatefulWidget {
  const _NewCodeDialog();

  @override
  State<_NewCodeDialog> createState() => _NewCodeDialogState();
}

class _NewCodeDialogState extends State<_NewCodeDialog> {
  /// The server's own pattern, checked here so the refusal happens before the round trip.
  static final RegExp _codeShape = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{2,31}$');

  final TextEditingController _code = TextEditingController();
  final TextEditingController _value = TextEditingController();
  final TextEditingController _minSubtotal = TextEditingController();
  final TextEditingController _maxRedemptions = TextEditingController();
  final TextEditingController _maxPerCustomer = TextEditingController();

  PromoKind _kind = PromoKind.percentOff;
  DateTime? _startsAt;
  DateTime? _endsAt;

  @override
  void dispose() {
    _code.dispose();
    _value.dispose();
    _minSubtotal.dispose();
    _maxRedemptions.dispose();
    _maxPerCustomer.dispose();
    super.dispose();
  }

  bool get _needsValue => _kind != PromoKind.freeDelivery;

  double? get _valueOrNull => double.tryParse(_value.text.trim());

  bool get _ready {
    if (!_codeShape.hasMatch(_code.text.trim())) return false;
    if (_needsValue) {
      final double? v = _valueOrNull;
      if (v == null || v <= 0) return false;
      if (_kind == PromoKind.percentOff && v > 100) return false;
    }
    if (_startsAt != null && _endsAt != null && !_endsAt!.isAfter(_startsAt!)) return false;
    return true;
  }

  _NewCode _build() => _NewCode(
        code: _code.text.trim(),
        kind: _kind,
        value: _needsValue ? _valueOrNull : null,
        minSubtotal: double.tryParse(_minSubtotal.text.trim()),
        startsAt: _startsAt,
        endsAt: _endsAt,
        maxRedemptions: int.tryParse(_maxRedemptions.text.trim()),
        maxPerCustomer: int.tryParse(_maxPerCustomer.text.trim()),
      );

  Future<void> _pickDate({required bool start}) async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: (start ? _startsAt : _endsAt) ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startsAt = picked;
      } else {
        // The end of that day, not its midnight start — an operator picking "ends Oct 12" means
        // the code works on Oct 12.
        _endsAt = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: DeliveryColors.white,
      surfaceTintColor: DeliveryColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
      title: const Text('New promo code', style: ConsoleText.cardTitle),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Customers type this at checkout. Every redemption is the platform\'s money.',
                style: ConsoleText.pageSubtitle,
              ),
              const SizedBox(height: DeliverySpacing.md),
              _field(
                controller: _code,
                label: 'Code',
                hint: 'WELCOME10',
                autofocus: true,
              ),
              const SizedBox(height: DeliverySpacing.md),
              const ConsoleSectionLabel('What it does'),
              const SizedBox(height: DeliverySpacing.sm),
              // Scale-down rather than overflow: three segments at an intrinsic width sit right
              // at the dialog's 440 in some fonts, and a switch that clips its third option loses
              // the option.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: ConsoleSegmented(
                  labels: <String>[
                    for (final PromoKind k in PromoKind.values) k.label,
                  ],
                  selectedIndex: _kind.index,
                  onSelected: (int i) => setState(() => _kind = PromoKind.values[i]),
                ),
              ),
              if (_needsValue) ...<Widget>[
                const SizedBox(height: DeliverySpacing.md),
                _field(
                  controller: _value,
                  label: _kind == PromoKind.percentOff
                      ? 'Percent off the goods (1–100)'
                      : 'Amount off the bill',
                  hint: _kind == PromoKind.percentOff ? '10' : '5.00',
                  number: true,
                ),
              ],
              const SizedBox(height: DeliverySpacing.md),
              _field(
                controller: _minSubtotal,
                label: 'Minimum basket — blank for none',
                hint: '20.00',
                number: true,
              ),
              const SizedBox(height: DeliverySpacing.md),
              const ConsoleSectionLabel('Window'),
              const SizedBox(height: DeliverySpacing.sm),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _dateButton(
                      label: _startsAt == null
                          ? 'Starts now'
                          : 'From ${_PromotionsScreenState._date(_startsAt!)}',
                      onPressed: () => _pickDate(start: true),
                    ),
                  ),
                  const SizedBox(width: DeliverySpacing.sm),
                  Expanded(
                    child: _dateButton(
                      label: _endsAt == null
                          ? 'Until withdrawn'
                          : 'To ${_PromotionsScreenState._date(_endsAt!)}',
                      onPressed: () => _pickDate(start: false),
                    ),
                  ),
                ],
              ),
              if (_startsAt != null && _endsAt != null && !_endsAt!.isAfter(_startsAt!)) ...<Widget>[
                const SizedBox(height: DeliverySpacing.xs),
                Text(
                  'The window ends before it starts.',
                  style: ConsoleText.meta.copyWith(color: DeliveryAccent.critical.color),
                ),
              ],
              const SizedBox(height: DeliverySpacing.md),
              const ConsoleSectionLabel('Caps — blank is unlimited'),
              const SizedBox(height: DeliverySpacing.sm),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _field(
                      controller: _maxRedemptions,
                      label: 'Total uses',
                      hint: '100',
                      number: true,
                    ),
                  ),
                  const SizedBox(width: DeliverySpacing.sm),
                  Expanded(
                    child: _field(
                      controller: _maxPerCustomer,
                      label: 'Per customer',
                      hint: '1',
                      number: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        ConsoleButton(
          label: 'Cancel',
          tone: ConsoleButtonTone.outlined,
          onPressed: () => Navigator.pop(context),
        ),
        ConsoleButton(
          label: 'Mint the code',
          tone: ConsoleButtonTone.solid,
          // Disabled rather than validated on submit, matching the decline dialogs: the server
          // would refuse it anyway, and finding out after pressing teaches nothing.
          onPressed: _ready ? () => Navigator.pop(context, _build()) : null,
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool number = false,
    bool autofocus = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: DeliveryColors.muted,
          ),
        ),
        const SizedBox(height: DeliverySpacing.xs),
        TextField(
          controller: controller,
          autofocus: autofocus,
          keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : null,
          style: ConsoleText.cell,
          cursorColor: DeliveryColors.brand,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 14, color: DeliveryColors.faint),
            isDense: true,
            filled: true,
            fillColor: DeliveryColors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DeliveryRadius.sm),
              borderSide: const BorderSide(color: DeliveryColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DeliveryRadius.sm),
              borderSide: const BorderSide(color: DeliveryColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DeliveryRadius.sm),
              borderSide: const BorderSide(color: DeliveryColors.brand),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _dateButton({required String label, required VoidCallback onPressed}) {
    return ConsoleButton(
      label: label,
      icon: Icons.event_outlined,
      tone: ConsoleButtonTone.outlined,
      onPressed: onPressed,
    );
  }
}
