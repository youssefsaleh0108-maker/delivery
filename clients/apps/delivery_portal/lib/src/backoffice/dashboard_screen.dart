import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import '../shell/console_controls.dart';
import '../shell/shell.dart';
import 'service_order_detail.dart';
import 'services_admin_parts.dart';

/// The cross-merchant orders ledger — Figma `backoffice-orders` (3:2817).
///
/// Read-only by design. Backoffice can cancel an order for support reasons, and that is exposed
/// through the server-supplied actions on the row's detail dialog — but there is no way to accept,
/// prepare or deliver on a merchant's or rider's behalf, because doing so would put the platform's
/// name on a claim about the physical world it cannot verify.
///
/// The top-line counters this screen used to carry have moved to `overview_screen.dart`, which is
/// where the redesign puts them. What is left here is the ledger and its filters, which is what the
/// design draws: a row of state pills over a seven-column table.
///
/// The class keeps its name. It is referenced from `portal_shell.dart` and from the old Backoffice
/// deep links, and renaming it would be a wide change for a screen that has always been the orders
/// page whatever the file is called.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.api,
    this.notificationApi,
    this.attachmentApi,
    this.openLink = openExternalLink,
  });

  final OrderApi api;

  /// The operator's own in-app inbox, behind the header's bell. Optional so the screen can be
  /// rendered on its own — a null one draws the bell greyed rather than polling nothing.
  final NotificationApi? notificationApi;

  /// A service order's files, through back office's audited read. Optional so the screen renders on
  /// its own; without it a service order's detail draws no files block rather than a dead button.
  final OrderAttachmentApi? attachmentApi;

  /// Opens a customer's file in a new browser tab. A parameter so a test can see what was opened.
  final void Function(String url) openLink;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const Duration _pollInterval = Duration(seconds: 10);

  /// The state filters, in the design's order: the four pills it draws, then the rest of the
  /// lifecycle.
  ///
  /// The design shows four; the platform has seven states and the ledger has always been able to
  /// filter to any of them. Dropping three would be removing a working control to match a mock, so
  /// they follow the drawn four in the same pill language.
  static const List<OrderStatus?> _pillFilters = <OrderStatus?>[
    null,
    OrderStatus.preparing,
    OrderStatus.pickedUp,
    OrderStatus.delivered,
    OrderStatus.placed,
    OrderStatus.accepted,
    OrderStatus.ready,
    OrderStatus.cancelled,
  ];

  Timer? _poll;
  List<DeliveryOrder> _orders = <DeliveryOrder>[];
  OrderStatus? _filter;
  Object? _error;
  bool _loading = true;

  /// Client-side, over the page already loaded. There is no search parameter on `/api/orders`, and
  /// a box that silently searched only the current page while looking like it searched the ledger
  /// would be worse than one that says what it is — hence the placeholder naming the two fields it
  /// actually matches.
  final TextEditingController _search = TextEditingController();

  /// The design's "Today" chip, as a real two-state filter over the loaded page.
  bool _todayOnly = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(_pollInterval, (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// The kind and fulfilment filters, sent to the server with the state — "every service pickup
  /// waiting at a counter" is [OrderKind.service], [Fulfilment.pickup] and [OrderStatus.ready]. Null is
  /// every kind, and both fulfilments.
  OrderKind? _kind;
  Fulfilment? _fulfilment;

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final Paged<DeliveryOrder> page = await widget.api
          .all(status: _filter, kind: _kind, fulfilment: _fulfilment, size: 50);
      if (!mounted) return;
      setState(() {
        _orders = page.content;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _error = e;
        _loading = false;
      });
    }
  }

  void _applyFilter(OrderStatus? status) {
    setState(() => _filter = status);
    _refresh();
  }

  void _applyKind(OrderKind? kind) {
    setState(() => _kind = kind);
    _refresh();
  }

  void _applyFulfilment(Fulfilment? fulfilment) {
    setState(() => _fulfilment = fulfilment);
    _refresh();
  }

  /// What the table actually shows: the loaded page, narrowed by the two client-side controls.
  List<DeliveryOrder> get _visible {
    final String q = _search.text.trim().toLowerCase();
    final DateTime start = DateTime.now();
    final DateTime today = DateTime(start.year, start.month, start.day);

    return _orders.where((DeliveryOrder o) {
      if (_todayOnly && (o.placedAt == null || o.placedAt!.isBefore(today))) {
        return false;
      }
      if (q.isEmpty) return true;
      final String haystack = <String>[
        o.id,
        o.customerId,
        o.merchantId,
        o.storeName ?? '',
        o.riderId ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final List<DeliveryOrder> rows = _visible;

    return ConsolePage(
      header: ConsoleTopbar(
        title: 'Orders Ledger',
        subtitle: 'Monitor active deliveries and order history',
        actions: <Widget>[
          ConsoleBell(api: widget.notificationApi),
          ConsoleIconAction(
            icon: Icons.refresh,
            tooltip: 'Refresh · updates every ${_pollInterval.inSeconds}s',
            onPressed: () => _refresh(),
          ),
        ],
      ),
      children: <Widget>[
        _filterRow(),
        _table(rows),
      ],
    );
  }

  /// Figma `filter-row` (3:2871): the search and date controls left, the state pills right.
  Widget _filterRow() {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: ConsoleMetrics.pageGap,
      runSpacing: DeliverySpacing.md - DeliverySpacing.xs,
      children: <Widget>[
        Wrap(
          spacing: DeliverySpacing.md - DeliverySpacing.xs,
          runSpacing: DeliverySpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            ConsoleSearchField(
              hintText: 'Search Order ID, Customer...',
              controller: _search,
              width: 272,
              onChanged: (_) => setState(() {}),
            ),
            _TodayButton(
              selected: _todayOnly,
              onPressed: () => setState(() => _todayOnly = !_todayOnly),
            ),
            // Server-side, unlike the two controls before them: `GET /api/orders` takes a kind and a
            // fulfilment, so these narrow the whole ledger rather than the page already loaded.
            ConsoleSelect(
              label: _kind == OrderKind.service ? t.svcBoKindService : t.svcBoKindAll,
              icon: Icons.design_services_outlined,
              options: <ConsoleOption>[
                ConsoleOption(label: t.svcBoKindAll, value: null),
                ConsoleOption(label: t.svcBoKindService, value: OrderKind.service.wire),
              ],
              onSelected: (String? wire) =>
                  _applyKind(wire == null ? null : OrderKind.fromWire(wire)),
            ),
            ConsoleSelect(
              label: switch (_fulfilment) {
                Fulfilment.pickup => t.svcBoFulfilmentPickup,
                Fulfilment.delivery => t.svcBoFulfilmentDelivery,
                _ => t.svcBoFulfilmentAll,
              },
              icon: Icons.local_shipping_outlined,
              options: <ConsoleOption>[
                ConsoleOption(label: t.svcBoFulfilmentAll, value: null),
                ConsoleOption(label: t.svcBoFulfilmentPickup, value: Fulfilment.pickup.wire),
                ConsoleOption(label: t.svcBoFulfilmentDelivery, value: Fulfilment.delivery.wire),
              ],
              onSelected: (String? wire) =>
                  _applyFulfilment(wire == null ? null : Fulfilment.fromWire(wire)),
            ),
          ],
        ),
        ConsoleFilterPills(
          labels: <String>[
            'All',
            for (final OrderStatus? s in _pillFilters.skip(1)) s!.label,
          ],
          selectedIndex: _pillFilters.indexOf(_filter),
          onSelected: (int i) => _applyFilter(_pillFilters[i]),
        ),
      ],
    );
  }

  /// Figma `table-card` (3:2890). Column widths are the design's.
  Widget _table(List<DeliveryOrder> rows) {
    if (_error != null) {
      return _ErrorCard(error: _error!, onRetry: () => _refresh());
    }
    if (_loading && _orders.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: DeliverySpacing.xxl),
        child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
      );
    }

    return ConsoleTable(
      minWidth: 980,
      columns: const <ConsoleColumn>[
        ConsoleColumn(label: 'Order ID', width: 120),
        ConsoleColumn(label: 'Customer', flex: 1),
        ConsoleColumn(label: 'Merchant', flex: 1),
        ConsoleColumn(label: 'Rider Assigned', width: 180),
        ConsoleColumn(label: 'Status', width: 130),
        ConsoleColumn(label: 'Amount', width: 100),
        ConsoleColumn(label: 'Date', width: 120, alignRight: true),
      ],
      empty: const Text('No orders match this filter.', style: ConsoleText.cellMuted),
      footer: rows.isEmpty
          ? null
          : Text(
              'Showing ${rows.length} of the ${_orders.length} most recent orders.',
              style: ConsoleText.meta,
            ),
      rows: <ConsoleTableRow>[
        for (final DeliveryOrder order in rows)
          ConsoleTableRow(
            onTap: () => _openDetail(order),
            cells: <Widget>[
              Text('#${order.shortId}', style: ConsoleText.cellLink),
              Text(
                _short(order.customerId),
                overflow: TextOverflow.ellipsis,
                style: ConsoleText.cellStrong,
              ),
              Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      order.storeName ?? _short(order.merchantId),
                      overflow: TextOverflow.ellipsis,
                      style: ConsoleText.cellMuted,
                    ),
                  ),
                  if (order.isService) ...<Widget>[
                    const SizedBox(width: DeliverySpacing.sm),
                    ConsoleSmallBadge(
                      label: DeliveryStrings.of(context).svcBoServiceTag,
                      accent: DeliveryAccent.neutral,
                    ),
                  ],
                ],
              ),
              Text(
                // A pickup never gets a rider, so "Unassigned" would read as a job nobody took.
                order.isPickup
                    ? DeliveryStrings.of(context).svcBoFulfilPickup
                    : order.riderId == null
                        ? 'Unassigned'
                        : _short(order.riderId!),
                overflow: TextOverflow.ellipsis,
                style: ConsoleText.cell,
              ),
              ConsoleStatusPill.status(
                _paletteFor(order.status),
                label: _statusLabel(DeliveryStrings.of(context), order),
              ),
              Text(_money(order.totalAmount), style: ConsoleText.cellStrong),
              Text(
                order.placedAt == null ? '—' : _when(order.placedAt!),
                style: ConsoleText.cellMuted,
              ),
            ],
          ),
      ],
    );
  }

  /// The drill-down the design implies by painting the order id as a link.
  ///
  /// Also the only place a support cancellation can be started from — deliberately behind a click
  /// and a typed reason rather than an icon in the row. A one-click cancel in a table that refreshes
  /// itself every ten seconds is a mis-click waiting to become somebody's undelivered dinner.
  Future<void> _openDetail(DeliveryOrder order) async {
    final bool? changed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => _OrderDetailDialog(
        order: order,
        api: widget.api,
        attachmentApi: widget.attachmentApi,
        openLink: widget.openLink,
      ),
    );
    if (changed ?? false) await _refresh();
  }
}

/// The design's date chip, as a working control.
///
/// Figma draws it as a static "Today" with a calendar glyph, which reads as a range picker; the
/// platform has no date parameter on `/api/orders`, so this filters the loaded page to orders placed
/// today and tints when it is on. Selected state borrows the brand tint the design uses for its
/// other "on" controls.
class _TodayButton extends StatelessWidget {
  const _TodayButton({required this.selected, required this.onPressed});

  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final Color foreground = selected ? DeliveryColors.brand : DeliveryColors.muted;

    return Tooltip(
      message: selected ? 'Showing orders placed today' : 'Show only orders placed today',
      child: Material(
        color: selected ? DeliveryColors.brandSoft : DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(DeliveryRadius.sm),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DeliverySpacing.md - 2,
              vertical: DeliverySpacing.sm,
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? DeliveryColors.brand : DeliveryColors.border,
              ),
              borderRadius: BorderRadius.circular(DeliveryRadius.sm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.calendar_today_outlined, size: 16, color: foreground),
                const SizedBox(width: DeliverySpacing.sm),
                Text('Today', style: ConsoleText.controlLabel.copyWith(color: foreground)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One order, and the one thing Backoffice may do to it — which is not the same thing at every
/// point in its life.
///
/// Before a rider has it that is a cancellation. Once a rider has it, cancelling is refused for
/// everybody, and what support has instead is closing the order as not delivered: the customer
/// refused it at the door, nobody was there, the goods are gone. That collects nothing from the
/// customer and decides, explicitly, whether the shop and the delivery are still paid — so it is a
/// form of its own rather than the same button with different words. Which of the two is offered
/// comes from the server ([DeliveryOrder.availableActions]); this screen never decides it.
class _OrderDetailDialog extends StatefulWidget {
  const _OrderDetailDialog({
    required this.order,
    required this.api,
    required this.attachmentApi,
    required this.openLink,
  });

  final DeliveryOrder order;
  final OrderApi api;
  final OrderAttachmentApi? attachmentApi;
  final void Function(String url) openLink;

  @override
  State<_OrderDetailDialog> createState() => _OrderDetailDialogState();
}

class _OrderDetailDialogState extends State<_OrderDetailDialog> {
  final TextEditingController _reason = TextEditingController();
  bool _sending = false;
  bool _confirming = false;
  Object? _failure;

  /// Both on, which is the owner's default: the shop made the goods and the rider carried them,
  /// and the platform bears the shortfall unless somebody decides otherwise on this order.
  bool _payShop = true;
  bool _payDelivery = true;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _canCancel => widget.order.availableActions.contains(OrderAction.cancel);

  /// Offered by the server on an order a rider already has, and only to Backoffice.
  bool get _canClose =>
      widget.order.availableActions.contains(OrderAction.closeNotDelivered);

  /// An errand has no shop, so there is no shop's share to pay and no switch to offer.
  bool get _hasShop => !widget.order.kind.isErrand;

  Future<void> _cancel() async {
    final String reason = _reason.text.trim();
    // The server takes an empty reason. This screen does not offer one: a cancellation with no
    // recorded why is a support case nobody can reconstruct afterwards.
    if (reason.isEmpty) return;

    await _send(() => widget.api.act(widget.order.id, OrderAction.cancel, reason: reason));
  }

  /// Closes an order the rider has, with the two decisions exactly as they are switched here. The
  /// server requires both, so nothing is paid because a field was left out.
  Future<void> _close() async {
    final String reason = _reason.text.trim();
    if (reason.isEmpty) return;

    await _send(() => widget.api.closeNotDelivered(
          widget.order.id,
          reason: reason,
          compensateMerchant: _hasShop && _payShop,
          compensateCarrier: _payDelivery,
        ));
  }

  Future<void> _send(Future<DeliveryOrder> Function() request) async {
    setState(() {
      _sending = true;
      _failure = null;
    });
    try {
      await request();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _failure = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final DeliveryOrder o = widget.order;
    final int units = o.items.fold<int>(0, (int a, OrderLine l) => a + l.qty);

    return Dialog(
      backgroundColor: DeliveryColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ConsoleMetrics.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: Text('Order #${o.shortId}', style: ConsoleText.cardTitle)),
                  ConsoleStatusPill.status(_paletteFor(o.status), label: _statusLabel(t, o)),
                ],
              ),
              const SizedBox(height: ConsoleMetrics.kpiGap),
              _DetailRow(label: 'Merchant', value: o.storeName ?? _short(o.merchantId)),
              _DetailRow(label: 'Customer', value: _short(o.customerId)),
              _DetailRow(
                label: 'Rider',
                value: o.isPickup
                    ? t.svcBoFulfilPickup
                    : o.riderId == null
                        ? 'Unassigned'
                        : _short(o.riderId!),
              ),
              _DetailRow(label: 'Items', value: '$units in ${o.items.length} lines'),
              _DetailRow(label: 'Total', value: _money(o.totalAmount)),
              _DetailRow(label: 'Payment', value: '${o.paymentMethod.label} · ${o.paymentStatus.label}'),
              // A pickup has no address to go to: it waits at the shop.
              _DetailRow(
                label: 'Address',
                value: o.isPickup
                    ? t.svcBoFulfilPickup
                    : o.deliveryAddress.isEmpty
                        ? '—'
                        : o.deliveryAddress,
              ),
              _DetailRow(
                label: 'Placed',
                value: o.placedAt == null ? '—' : _when(o.placedAt!, withClock: true),
              ),
              if (o.cancelReason != null && o.cancelReason!.isNotEmpty)
                _DetailRow(
                  label: o.closedAfterPickup ? 'Closed because' : 'Cancelled because',
                  // A provider's decline is stored as a code; it is said in words, as the customer
                  // reads it.
                  value: o.declineReason?.labelIn(t) ?? o.cancelReason!,
                ),
              // An order closed while a rider had it is a cancellation, and its own kind of one:
              // nothing was collected, and somebody may still have been paid. Both are said here,
              // because "Cancelled" alone does not explain a payment on the statement.
              if (o.closedAfterPickup)
                _DetailRow(label: 'Closed after pickup', value: _whoWasPaid(o)),
              if (o.isService) ...<Widget>[
                const SizedBox(height: DeliverySpacing.sm),
                const Divider(height: 1, color: DeliveryColors.border),
                const SizedBox(height: ConsoleMetrics.kpiGap),
                ServiceOrderDetail(
                  order: o,
                  orderApi: widget.api,
                  attachmentApi: widget.attachmentApi,
                  openLink: widget.openLink,
                ),
              ],
              if (_canCancel || _canClose) ...<Widget>[
                const SizedBox(height: ConsoleMetrics.kpiGap),
                const Divider(height: 1, color: DeliveryColors.border),
                const SizedBox(height: ConsoleMetrics.kpiGap),
                Text(
                  _canClose ? 'Close as not delivered' : 'Support cancellation',
                  style: ConsoleText.fieldLabel,
                ),
                const SizedBox(height: DeliverySpacing.sm),
                Text(
                  _canClose
                      ? 'The rider has this order, so it cannot be cancelled. Closing it collects '
                          'nothing from the customer; whatever is left switched on below is paid '
                          'by the platform. Say why — it is kept on the order.'
                      : 'The customer and the shop are both told. Say why — it is kept on the '
                          'order.',
                  style: ConsoleText.meta,
                ),
                const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                TextField(
                  controller: _reason,
                  enabled: !_sending,
                  style: ConsoleText.control,
                  cursorColor: DeliveryColors.brand,
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: _canClose
                        ? 'Why it was not delivered'
                        : 'Reason for cancelling',
                    hintStyle: const TextStyle(fontSize: 13, color: DeliveryColors.faint),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: DeliverySpacing.md - 2,
                      vertical: DeliverySpacing.sm + 2,
                    ),
                    border: _fieldBorder(DeliveryColors.border),
                    enabledBorder: _fieldBorder(DeliveryColors.border),
                    focusedBorder: _fieldBorder(DeliveryColors.brand),
                    disabledBorder: _fieldBorder(DeliveryColors.borderFaint),
                  ),
                ),
              ],
              if (_canClose) ...<Widget>[
                const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                if (_hasShop)
                  _PayToggle(
                    id: 'merchant',
                    label: 'Pay the shop its share',
                    detail: 'The goods were made and handed to the rider.',
                    value: _payShop,
                    onChanged: _sending
                        ? null
                        : (bool on) => setState(() => _payShop = on),
                  ),
                _PayToggle(
                  id: 'carrier',
                  label: 'Pay the delivery fee',
                  detail: 'The rider went to the shop and to the door.',
                  value: _payDelivery,
                  onChanged: _sending
                      ? null
                      : (bool on) => setState(() => _payDelivery = on),
                ),
              ],
              if (_failure != null) ...<Widget>[
                const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                Text(
                  _canClose
                      ? 'Could not close this order. $_failure'
                      : 'Could not cancel this order. $_failure',
                  style: TextStyle(fontSize: 13, color: DeliveryAccent.critical.color),
                ),
              ],
              const SizedBox(height: ConsoleMetrics.kpiGap),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  _DialogButton(
                    label: 'Close',
                    onPressed: _sending ? null : () => Navigator.of(context).pop(false),
                  ),
                  if (_canCancel || _canClose) ...<Widget>[
                    const SizedBox(width: DeliverySpacing.sm),
                    if (_confirming)
                      _DialogButton(
                        label: _sending
                            ? (_canClose ? 'Closing…' : 'Cancelling…')
                            : (_canClose ? 'Yes, close it' : 'Yes, cancel it'),
                        destructive: true,
                        onPressed: _sending || _reason.text.trim().isEmpty
                            ? null
                            : (_canClose ? _close : _cancel),
                      )
                    else
                      _DialogButton(
                        label: _canClose ? 'Close as not delivered' : 'Cancel order',
                        destructive: true,
                        onPressed: _reason.text.trim().isEmpty
                            ? null
                            : () => setState(() => _confirming = true),
                      ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        borderSide: BorderSide(color: color),
      );

  /// What the platform paid out on an order that was closed after pickup, in the order the form
  /// asks it — and "nobody" when both were switched off, which is a decision somebody made and
  /// should read as one.
  static String _whoWasPaid(DeliveryOrder order) {
    final List<String> paid = <String>[
      if (order.compensateMerchant) 'the shop its share',
      if (order.compensateCarrier) 'the delivery fee',
    ];
    if (paid.isEmpty) {
      return 'Nothing was collected, and nobody was paid';
    }
    return 'Nothing was collected; the platform paid ${paid.join(' and ')}';
  }
}

/// One of the two decisions on the close form: paid, or not paid, said as a sentence rather than a
/// bare switch. Both start on — the owner's default — and either can be switched off for this one
/// order.
class _PayToggle extends StatelessWidget {
  const _PayToggle({
    required this.id,
    required this.label,
    required this.detail,
    required this.value,
    required this.onChanged,
  });

  /// Names the switch for a test and for a screenshot diff, rather than counting them off in
  /// layout order.
  final String id;
  final String label;
  final String detail;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(label, style: ConsoleText.controlLabel),
                Text(detail, style: ConsoleText.meta),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Switch(
            key: ValueKey<String>('close-not-delivered-pay-$id'),
            value: value,
            onChanged: onChanged,
            activeThumbColor: DeliveryColors.brand,
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 130, child: Text(label, style: ConsoleText.controlLabel)),
          Expanded(child: Text(value, style: ConsoleText.body)),
        ],
      ),
    );
  }
}

/// The console's button, in the two weights this screen needs.
///
/// Local rather than shared: the design's dialogs are not drawn in the console frames, so this is
/// the page's own reading of its button language — the filter pill's geometry (radius 8, 14 across,
/// 8 down, SemiBold 13) in either the quiet or the destructive tier.
class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final bool on = onPressed != null;
    final Color foreground = !on
        ? DeliveryColors.faint
        : destructive
            ? DeliveryAccent.critical.color
            : DeliveryColors.muted;
    final Color fill = on && destructive ? DeliveryAccent.critical.tint : DeliveryColors.white;

    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DeliverySpacing.md - 2,
            vertical: DeliverySpacing.sm,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: on && destructive ? DeliveryAccent.critical.line : DeliveryColors.border,
            ),
            borderRadius: BorderRadius.circular(DeliveryRadius.sm),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: foreground),
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // A 403 is this account: the ledger is BACKOFFICE-only, and asking again would only be refused.
    final bool refused = refusalStatus(error) == 403;
    return Container(
      padding: const EdgeInsets.all(ConsoleMetrics.cardPadding),
      decoration: ConsoleSurface.card(),
      child: Row(
        children: <Widget>[
          Icon(
            refused ? Icons.lock_outline : Icons.error_outline,
            size: 18,
            color: DeliveryAccent.critical.color,
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Text(
              refused
                  ? DeliveryStrings.of(context).svcBoLedgerRefused
                  : 'Could not load orders. $error',
              style: ConsoleText.cellMuted,
            ),
          ),
          if (!refused) _DialogButton(label: 'Retry', onPressed: onRetry),
        ],
      ),
    );
  }
}

/// A service order's status in its kind's own words ("In production", "Collected"); every other
/// order's as the ledger has always shown it.
String _statusLabel(DeliveryStrings t, DeliveryOrder order) =>
    order.isService ? serviceOrderStatusLabel(t, order) : order.status.label;

/// The lifecycle's colour, mirroring `OrderStatusBadge` in the design system so a status reads the
/// same here, in the merchant portal and on the customer's tracking screen.
DeliveryStatusColor _paletteFor(OrderStatus status) => switch (status) {
      OrderStatus.placed || OrderStatus.accepted => DeliveryStatusColor.placed,
      OrderStatus.preparing || OrderStatus.ready => DeliveryStatusColor.preparing,
      OrderStatus.pickedUp => DeliveryStatusColor.inTransit,
      OrderStatus.delivered => DeliveryStatusColor.delivered,
      OrderStatus.cancelled => DeliveryStatusColor.offline,
    };

String _short(String id) => id.length <= 8 ? id : id.substring(0, 8);

/// Amounts as the platform sends them: grouped, to the cent, and with no currency symbol, because
/// nothing on the wire names a currency.
String _money(double amount) {
  final String fixed = amount.toStringAsFixed(2);
  final int dot = fixed.indexOf('.');
  final String digits = fixed.substring(0, dot);
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return '$out${fixed.substring(dot)}';
}

/// The design's Date cell: a clock time for today, "Yesterday", then a date.
String _when(DateTime t, {bool withClock = false}) {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime day = DateTime(t.year, t.month, t.day);
  final String clock = _clock(t);

  if (day == today) return clock;
  if (day == today.subtract(const Duration(days: 1))) {
    return withClock ? 'Yesterday $clock' : 'Yesterday';
  }
  final String date = '${_month(t.month)} ${t.day}';
  return withClock ? '$date, $clock' : date;
}

String _clock(DateTime t) {
  final int hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final String minute = t.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
}

String _month(int month) => const <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][month - 1];
