/// Everything that is running out, worst first.
///
/// Figma `stock-alerts` 94:272 (phone) / 94:3530 (web). One grouped list: the shelves the server
/// says are OUT, then CRITICAL, then LOW, each row carrying how many are left, how fast they sell,
/// and a "Restock" button.
///
/// **Restock records a stock RECEIPT, nothing more.** The platform has no supplier, no purchase
/// order and no reorder point beyond `lowStockThreshold`, so the button cannot mean "order more
/// from the wholesaler" — it means "the goods arrived, write them onto the shelf", which is
/// `InventoryApi.adjust(delta:, reason: RECEIVED)`. A button that implied a purchase would be a
/// promise the backend cannot keep.
///
/// The service behind it (`/api/inventory`) is not deployed yet, so [InventoryApi] is nullable here
/// and every failure lands on a calm state rather than a crash: a host can mount this screen today
/// and get an honest "cannot load" instead of a red box.
library;

import 'dart:math' as math;

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'order_detail_screen.dart';

/// The stock-alerts page, pushed from Inventory or from the dashboard's low-stock card.
///
/// Host-agnostic like every screen in this package: no rail, no bottom bar, and no assumption of a
/// phone width — the portal hands it whatever is left beside its navigation, which can be 1400px,
/// and the Android app hands it 380.
class StockAlertsScreen extends StatefulWidget {
  const StockAlertsScreen({
    super.key,
    this.api,
    this.storeId,
    this.onBack,
  });

  /// Null until inventory-service ships, or wherever a host has not wired it. The screen then draws
  /// its unavailable state; it never pretends the shelves are fine, because it does not know.
  final InventoryApi? api;

  /// Scopes the query for a merchant whose account carries more than one shop. Null lets the
  /// server pick the caller's own store, which is what a single-shop merchant wants.
  final String? storeId;

  /// Supplied by a host that framed this screen itself. When null the header falls back to popping
  /// the route it was pushed on, and draws no back button at all if there is nothing to pop.
  final VoidCallback? onBack;

  @override
  State<StockAlertsScreen> createState() => _StockAlertsScreenState();
}

class _StockAlertsScreenState extends State<StockAlertsScreen> {
  /// Below this the page is on a phone: one column of tiles per row pair, and a pull gesture
  /// instead of a refresh button.
  ///
  /// Measured against this widget's own constraints rather than the window's — the portal gives the
  /// page the space beside its rail, so a half-width browser is as narrow as a handset here.
  static const double _phoneWidth = 600;

  /// The severity groups, in the order the frame stacks them. `ok` is last and normally empty; it
  /// exists so a row the server marks healthy is still drawn rather than silently dropped.
  static const List<StockSeverity> _groups = <StockSeverity>[
    StockSeverity.out,
    StockSeverity.critical,
    StockSeverity.warning,
    StockSeverity.ok,
  ];

  late Future<StockAlerts> _alerts = _load();

  /// The last answer that arrived, kept only so the header can say how many items need restocking
  /// while the list below it redraws. Never used to paint the list — that stays the future's job,
  /// so a failed refresh cannot leave stale rows looking current.
  StockAlerts? _last;

  Future<StockAlerts> _load() {
    final InventoryApi? api = widget.api;
    if (api == null) {
      // Unreachable: the caller checks for a null API before building a FutureBuilder. Kept
      // total anyway so this method has one return type and no `!`.
      return Future<StockAlerts>.value(const StockAlerts());
    }
    final Future<StockAlerts> pending = api.alerts(storeId: widget.storeId);
    // The subtitle's copy of the summary, updated out of band. The error is the FutureBuilder's to
    // render; swallowing it here would otherwise surface as an unhandled rejection.
    pending.then<void>(
      (StockAlerts alerts) {
        if (mounted) {
          setState(() => _last = alerts);
        }
      },
      onError: (Object _) {},
    );
    return pending;
  }

  /// Block body, not an arrow: an arrow returns the future out of the closure and setState asserts
  /// against that (debug only, which is worse — it ships).
  void _reload() {
    setState(() {
      _alerts = _load();
    });
  }

  /// The same reload, finishing only when the request does, because [RefreshIndicator] spins until
  /// the future it was given completes.
  Future<void> _refresh() {
    final Future<StockAlerts> pending = _load();
    setState(() {
      _alerts = pending;
    });
    return pending.then<void>((StockAlerts _) {}, onError: (Object _) {});
  }

  /// Opens the receipt sheet for one alert and, if something was received, reloads.
  ///
  /// The sheet owns the whole write — the quantity, the in-flight guard and the idempotency key —
  /// so there is no half-state to reconcile here: either it popped an adjustment or it did not.
  Future<void> _restock(StockAlert alert) async {
    final InventoryApi? api = widget.api;
    if (api == null) {
      return;
    }
    final DeliveryStrings t = DeliveryStrings.of(context);

    final StockAdjustment? done = await showModalBottomSheet<StockAdjustment>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: DeliveryColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(DeliveryRadius.sheet)),
      ),
      builder: (BuildContext context) => _RestockSheet(api: api, alert: alert),
    );
    if (done == null || !mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.invAdjusted)));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final VoidCallback? back =
        widget.onBack ?? (navigator.canPop() ? () => navigator.maybePop() : null);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < _phoneWidth;

        return Scaffold(
          backgroundColor: DeliveryColors.background,
          // No AppBar: the framing belongs to whichever app mounted this.
          body: Column(
            children: <Widget>[
              MerchantScreenHeader(
                title: t.invAlertsTitle,
                // Only once a real answer has arrived — "Nothing needs restocking" under a
                // spinner would be a guess, and the reassuring one.
                subtitle:
                    _last == null ? null : t.invAlertsCount(_last!.summary.total),
                onBack: back,
                backSemanticLabel: t.back,
                // The refresh button only exists where there is no pull gesture to replace it.
                trailing: narrow
                    ? null
                    : IconButton(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh, size: 20),
                        color: DeliveryColors.ink,
                        tooltip: t.refresh,
                      ),
              ),
              Expanded(child: _body(t, narrow: narrow)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(DeliveryStrings t, {required bool narrow}) {
    if (widget.api == null) {
      // Not an error and not an empty shelf — the feature is simply not there yet. Said plainly,
      // with no retry button, because retrying an API that does not exist is a loop.
      return YdEmptyState(
        icon: Icons.inventory_2_outlined,
        title: t.invAlertsCouldNotLoad,
        message: t.invAlertsEmptyHint,
      );
    }

    return FutureBuilder<StockAlerts>(
      future: _alerts,
      builder: (BuildContext context, AsyncSnapshot<StockAlerts> snapshot) {
        final Widget? placeholder = _placeholder(t, snapshot);
        final StockAlerts alerts = placeholder == null ? snapshot.data! : const StockAlerts();

        final Widget scroller = CustomScrollView(
          // Always scrollable, or the pull-to-refresh below is dead on exactly the two states
          // where a merchant wants to retry: nothing loaded, and nothing to show.
          physics: narrow ? const AlwaysScrollableScrollPhysics() : null,
          slivers: <Widget>[
            if (placeholder != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.lg),
                  child: placeholder,
                ),
              )
            else
              ..._sections(t, alerts, narrow: narrow),
          ],
        );

        // Capped and centred rather than stretched: a 1300px-wide alert row is a line the eye has
        // to track across, and this list is read in a hurry behind a counter.
        final Widget capped = Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: merchantMaxContentWidth),
            child: scroller,
          ),
        );

        if (!narrow) {
          return capped;
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          color: DeliveryColors.brand,
          child: capped,
        );
      },
    );
  }

  /// What goes where the list would be. Null means the request succeeded with rows to draw.
  Widget? _placeholder(DeliveryStrings t, AsyncSnapshot<StockAlerts> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(DeliverySpacing.xl),
          child: CircularProgressIndicator(color: DeliveryColors.brand),
        ),
      );
    }
    if (snapshot.hasError) {
      return YdEmptyState(
        icon: Icons.cloud_off_rounded,
        title: t.invAlertsCouldNotLoad,
        message: _messageFor(snapshot.error!, fallback: t.somethingWentWrong),
        action: YdPillButton.secondary(
          label: t.tryAgain,
          onPressed: _reload,
          size: YdPillButtonSize.compact,
          expand: false,
        ),
      );
    }
    if (snapshot.data!.isEmpty) {
      return YdEmptyState(
        icon: Icons.check_circle_outline,
        title: t.invAlertsEmpty,
        message: t.invAlertsEmptyHint,
      );
    }
    return null;
  }

  /// The tally band, then one titled group per severity, worst first.
  ///
  /// Rows keep the order the server sent them in inside their group. Re-sorting client-side would
  /// mean two shops looking at the same shelf in different orders the moment the ranking changes.
  List<Widget> _sections(DeliveryStrings t, StockAlerts alerts, {required bool narrow}) {
    final Map<StockSeverity, List<StockAlert>> grouped = <StockSeverity, List<StockAlert>>{
      for (final StockSeverity severity in _groups) severity: <StockAlert>[],
    };
    for (final StockAlert alert in alerts.items) {
      grouped[alert.severity]!.add(alert);
    }

    final List<Widget> slivers = <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          DeliverySpacing.lg,
          DeliverySpacing.lg,
          DeliverySpacing.lg,
          DeliverySpacing.sm,
        ),
        sliver: SliverToBoxAdapter(
          child: _AlertTally(summary: alerts.summary, narrow: narrow),
        ),
      ),
    ];

    for (final StockSeverity severity in _groups) {
      final List<StockAlert> rows = grouped[severity]!;
      if (rows.isEmpty) {
        continue;
      }
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            DeliverySpacing.lg,
            DeliverySpacing.md,
            DeliverySpacing.lg,
            DeliverySpacing.sm,
          ),
          sliver: SliverToBoxAdapter(
            child: _GroupHeader(severity: severity, count: rows.length),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.lg),
          sliver: SliverList.separated(
            itemCount: rows.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            itemBuilder: (BuildContext context, int index) => _AlertRow(
              alert: rows[index],
              narrow: narrow,
              onRestock: () => _restock(rows[index]),
            ),
          ),
        ),
      );
    }

    slivers.add(
      SliverToBoxAdapter(
        // Room under the last row for the gesture bar. `paddingOf`, not `viewPaddingOf`: a host
        // that already wrapped this in a SafeArea has spent the inset, and this must not spend it
        // twice.
        child: SizedBox(height: DeliverySpacing.lg + MediaQuery.paddingOf(context).bottom),
      ),
    );
    return slivers;
  }
}

// ---------------------------------------------------------------------------- severity colours

/// How a severity is painted, everywhere on this screen.
///
/// Two of the four are red on purpose: "out" and "critical" are the same kind of problem at two
/// distances, and the design separates them by weight rather than by hue — `out` fills its badge,
/// `critical` only tints it. Amber is the advisory one. Kept in a single function so a shelf cannot
/// change colour between the tally, the group header and the row.
DeliveryAccent _accentFor(StockSeverity severity) => switch (severity) {
      StockSeverity.out || StockSeverity.critical => DeliveryAccent.critical,
      StockSeverity.warning => DeliveryAccent.caution,
      StockSeverity.ok => DeliveryAccent.positive,
    };

/// Solid badge for the shelves that are already empty, tint for the rest.
bool _solidBadge(StockSeverity severity) => severity == StockSeverity.out;

IconData _iconFor(StockSeverity severity) => switch (severity) {
      StockSeverity.out => Icons.remove_shopping_cart_outlined,
      StockSeverity.critical => Icons.priority_high_rounded,
      StockSeverity.warning => Icons.trending_down_rounded,
      StockSeverity.ok => Icons.check_circle_outline,
    };

// ---------------------------------------------------------------------------- the tally band

/// The three counts the server sends above the list: out, critical, low.
///
/// Laid out with a computed tile width rather than a fixed one — two to a row on a handset, three
/// across wherever there is room — so the same widget reads at 380 and at the 720 cap.
class _AlertTally extends StatelessWidget {
  const _AlertTally({required this.summary, required this.narrow});

  final AlertSummary summary;
  final bool narrow;

  static const double _gap = DeliverySpacing.md - DeliverySpacing.xs;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    final List<({StockSeverity severity, String label, int value})> tiles =
        <({StockSeverity severity, String label, int value})>[
      (severity: StockSeverity.out, label: t.invStatusOut, value: summary.out),
      (severity: StockSeverity.critical, label: t.invStatusCritical, value: summary.critical),
      (severity: StockSeverity.warning, label: t.invStatusWarning, value: summary.warning),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int perRow = narrow ? 2 : 3;
        // Floored, so rounding never pushes the last tile onto its own run.
        final double width =
            math.max(0, (constraints.maxWidth - _gap * (perRow - 1)) / perRow).floorToDouble();

        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: <Widget>[
            for (final ({StockSeverity severity, String label, int value}) tile in tiles)
              SizedBox(
                width: width,
                child: MerchantMetricCard.accent(
                  icon: _iconFor(tile.severity),
                  label: tile.label,
                  value: '${tile.value}',
                  accent: _accentFor(tile.severity),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------- group header

/// "Out of stock  3" — the severity's own word, with how many sit under it.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.severity, required this.count});

  final StockSeverity severity;
  final int count;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final DeliveryAccent accent = _accentFor(severity);

    return Row(
      children: <Widget>[
        Icon(_iconFor(severity), size: 16, color: accent.color),
        const SizedBox(width: DeliverySpacing.sm),
        Flexible(
          child: Text(
            severity.labelIn(t),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
              height: 1.3,
            ),
          ),
        ),
        const SizedBox(width: DeliverySpacing.sm),
        // The bare number, in the group's colour. No sentence to translate — a count beside its
        // own heading needs none, and every plural form of "3 items" is already on the header.
        YdBadge(label: '$count', color: accent.color, background: accent.tint),
      ],
    );
  }
}

// ---------------------------------------------------------------------------- one alert

/// One shelf that needs attention.
///
/// The derived figures — velocity, hours of cover, last sold — are null until there is a week of
/// sales behind them, and null renders as its own sentence rather than as a zero: "we cannot tell
/// yet" and "this never sells" must not look the same to somebody deciding what to order.
class _AlertRow extends StatelessWidget {
  const _AlertRow({
    required this.alert,
    required this.narrow,
    required this.onRestock,
  });

  final StockAlert alert;
  final bool narrow;
  final VoidCallback onRestock;

  static const double _thumb = 48;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final DeliveryAccent accent = _accentFor(alert.severity);
    final bool solid = _solidBadge(alert.severity);

    final Widget button = MerchantActionButton(
      label: t.invRestock,
      onPressed: onRestock,
      primary: true,
    );

    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _thumbnail(t, accent),
              const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      alert.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.ink,
                        height: 1.25,
                      ),
                    ),
                    if (alert.categoryName != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        alert.categoryName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: DeliveryColors.faint,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              YdBadge(
                label: alert.severity.labelIn(t),
                color: solid ? DeliveryColors.white : accent.color,
                background: solid ? accent.color : accent.tint,
                uppercase: false,
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          // The two numbers that decide whether this is urgent, side by side.
          Wrap(
            spacing: DeliverySpacing.lg,
            runSpacing: DeliverySpacing.sm,
            children: <Widget>[
              _Stat(
                label: t.invAvailable,
                value: '${alert.available}',
                emphasis: accent.color,
              ),
              _Stat(label: t.invThreshold, value: '${alert.lowStockThreshold}'),
            ],
          ),
          const SizedBox(height: DeliverySpacing.sm),
          _meta(t),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          // The button keeps the end of the card at both widths. On a handset it has the row to
          // itself; wider, there is room beside the meta line, and a Wrap would only leave it
          // stranded under a half-empty line.
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: narrow ? SizedBox(width: double.infinity, child: button) : button,
          ),
        ],
      ),
    );
  }

  /// The product photo, or a severity-tinted glyph where there is none. Never a broken frame.
  Widget _thumbnail(DeliveryStrings t, DeliveryAccent accent) {
    if (alert.listImageUrl == null) {
      return Tooltip(
        message: t.noPhoto,
        child: Container(
          width: _thumb,
          height: _thumb,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.tint,
            borderRadius: BorderRadius.circular(merchantChipRadius),
          ),
          child: Icon(
            _iconFor(alert.severity),
            size: 20,
            color: accent.color,
            semanticLabel: t.noPhoto,
          ),
        ),
      );
    }
    return SizedBox.square(
      dimension: _thumb,
      child: DeliveryProductImage(
        url: alert.listImageUrl,
        borderRadius: BorderRadius.circular(merchantChipRadius),
      ),
    );
  }

  /// How fast it sells, how long the rest lasts, when it last moved.
  ///
  /// A [Wrap] of separate [Text] widgets rather than one joined sentence: the pieces reflow at 380
  /// without a truncated middle, and nothing is glued together with a separator that would have to
  /// be translated.
  Widget _meta(DeliveryStrings t) {
    final List<String> parts = <String>[
      if (alert.velocityPerDay != null)
        t.invVelocity(alert.velocityPerDay!.toStringAsFixed(1))
      else
        t.invNoVelocityYet,
      if (alert.hoursOfCover != null) t.invHoursOfCover(alert.hoursOfCover!.round().toString()),
      if (alert.lastSoldAt != null) t.invLastSold(merchantTimeAgo(alert.lastSoldAt, t)),
    ];

    return Wrap(
      spacing: DeliverySpacing.md - DeliverySpacing.xs,
      runSpacing: DeliverySpacing.xs,
      children: <Widget>[
        for (final String part in parts)
          Text(
            part,
            style: const TextStyle(
              fontSize: 12,
              color: DeliveryColors.muted,
              height: 1.3,
            ),
          ),
      ],
    );
  }
}

/// A small label-over-value pair — the row's two hard numbers.
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.emphasis});

  /// Already localised by the caller.
  final String label;
  final String value;

  /// Paints the figure in a severity colour. Only "Available" uses it: the threshold is a setting,
  /// not a problem.
  final Color? emphasis;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            color: DeliveryColors.faint,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: emphasis ?? DeliveryColors.ink,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------- the receipt sheet

/// "The goods arrived" — a quantity, a note, and one `RECEIVED` movement.
///
/// The reason is fixed and shown rather than chosen. This sheet exists on the alerts screen, where
/// the only thing a merchant does to an empty shelf is put stock back on it; offering DAMAGED or
/// THEFT here would be a different job on the wrong screen, and those live on the inventory item's
/// own adjust sheet.
///
/// The idempotency key is generated ONCE, in [initState], and reused by every retry — a key made
/// per attempt defeats the whole point and receives the delivery twice.
class _RestockSheet extends StatefulWidget {
  const _RestockSheet({required this.api, required this.alert});

  final InventoryApi api;
  final StockAlert alert;

  @override
  State<_RestockSheet> createState() => _RestockSheetState();
}

class _RestockSheetState extends State<_RestockSheet> {
  final TextEditingController _qty = TextEditingController();
  final TextEditingController _note = TextEditingController();

  late final String _key = _idempotencyKey();

  bool _saving = false;

  /// The server's own words when it refuses, shown under the field rather than in a snackbar: a
  /// snackbar over a sheet is covered by the keyboard and gone before it is read.
  String? _error;

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    final DeliveryStrings t = DeliveryStrings.of(context);
    final int? qty = int.tryParse(_qty.text.trim());
    if (qty == null || qty <= 0) {
      setState(() => _error = t.invAdjustQuantity);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final String note = _note.text.trim();
      final StockAdjustment result = await widget.api.adjust(
        widget.alert.productId,
        delta: qty,
        reason: AdjustmentReason.received,
        note: note.isEmpty ? null : note,
        idempotencyKey: _key,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = _messageFor(e, fallback: t.somethingWentWrong);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Padding(
      // Lifts the sheet clear of the keyboard. `viewInsetsOf` is the right one here — this is the
      // soft keyboard's overlap, not a system inset an ancestor could already have spent.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          DeliverySpacing.lg,
          DeliverySpacing.md - DeliverySpacing.xs,
          DeliverySpacing.lg,
          DeliverySpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: DeliveryColors.border,
                  borderRadius: BorderRadius.circular(DeliveryRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: DeliverySpacing.md),
            Text(
              t.invRestock,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: DeliveryColors.ink,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.alert.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: DeliveryColors.muted,
                height: 1.3,
              ),
            ),
            const SizedBox(height: DeliverySpacing.md),
            Wrap(
              spacing: DeliverySpacing.lg,
              runSpacing: DeliverySpacing.sm,
              children: <Widget>[
                _Stat(
                  label: t.invAvailable,
                  value: '${widget.alert.available}',
                  emphasis: _accentFor(widget.alert.severity).color,
                ),
                _Stat(label: t.invThreshold, value: '${widget.alert.lowStockThreshold}'),
              ],
            ),
            const SizedBox(height: DeliverySpacing.md),
            _label(t.invAdjustQuantity),
            const SizedBox(height: DeliverySpacing.sm),
            TextField(
              controller: _qty,
              autofocus: true,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
              // Digits only, so "3.5 crates" can never reach an integer field and be silently
              // rejected server-side.
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.next,
              onChanged: (String _) {
                if (_error != null) {
                  setState(() => _error = null);
                }
              },
              decoration: _boxDecoration(),
              style: const TextStyle(fontSize: 15, color: DeliveryColors.ink),
            ),
            const SizedBox(height: DeliverySpacing.md),
            // The reason is stated, not chosen: this sheet only ever records a receipt.
            _label(t.invAdjustReason),
            const SizedBox(height: DeliverySpacing.sm),
            YdBadge(
              label: AdjustmentReason.received.labelIn(t),
              color: DeliveryAccent.positive.color,
              background: DeliveryAccent.positive.tint,
              icon: Icons.inventory_2_outlined,
              uppercase: false,
              fontSize: 12,
            ),
            const SizedBox(height: DeliverySpacing.md),
            _label(t.invAdjustNote),
            const SizedBox(height: DeliverySpacing.sm),
            TextField(
              controller: _note,
              enabled: !_saving,
              maxLines: 2,
              textInputAction: TextInputAction.done,
              decoration: _boxDecoration(),
              style: const TextStyle(fontSize: 15, color: DeliveryColors.ink),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              Text(
                _error!,
                style: TextStyle(
                  fontSize: 12,
                  color: DeliveryAccent.critical.color,
                  height: 1.3,
                ),
              ),
            ],
            const SizedBox(height: DeliverySpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: YdPillButton.secondary(
                    label: t.cancel,
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
                Expanded(
                  child: YdPillButton(
                    label: t.invAdjustSave,
                    onPressed: _saving ? null : _save,
                    busy: _saving,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: DeliveryColors.muted,
          height: 1.3,
        ),
      );
}

/// A key unique to one user action, so a retried receipt does not stock the shelf twice.
///
/// Not a UUID: this package does not depend on `uuid`, and the header only has to be unique among
/// the requests one merchant makes. Milliseconds plus 64 bits of randomness is comfortably that.
String _idempotencyKey() {
  final math.Random random = math.Random();
  final String suffix = List<String>.generate(
    4,
    (int _) => random.nextInt(0x10000).toRadixString(16).padLeft(4, '0'),
  ).join();
  return 'restock-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-$suffix';
}

/// The bordered field the merchant forms draw.
InputDecoration _boxDecoration() {
  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: DeliveryColors.white,
    contentPadding:
        const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
    border: border(DeliveryColors.border),
    enabledBorder: border(DeliveryColors.border),
    focusedBorder: border(DeliveryColors.brand, 1.5),
    errorBorder: border(DeliveryAccent.critical.color),
    focusedErrorBorder: border(DeliveryAccent.critical.color, 1.5),
    errorStyle: TextStyle(fontSize: 11, color: DeliveryAccent.critical.color),
  );
}

/// Pulls the human-readable half out of an RFC 9457 problem response.
///
/// A file-private copy of `product_list_screen.dart`'s extractor. The spec calls for promoting it
/// once into `order_detail_screen.dart` beside `merchantMoney`; that is a shared-file edit and is
/// deliberately left to whoever wires these screens together, so this screen does not race another
/// agent for the same lines.
String _messageFor(Object error, {required String fallback}) {
  if (error is DioException) {
    final Object? body = error.response?.data;
    if (body is Map<String, dynamic>) {
      final String? detail = body['detail'] as String?;
      final String? correlationId = body['correlationId'] as String?;
      if (detail != null) {
        return correlationId == null ? detail : '$detail (ref: $correlationId)';
      }
    }
  }
  return fallback;
}
