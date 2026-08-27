/// One order, in full: where it is in the flow, who it is for, and what it adds up to.
///
/// New in the 2026-08 redesign (Figma `merchant-order-detail`, 3:2104). Nothing here is a new
/// capability — every field was already on [DeliveryOrder] and every button already came from
/// `availableActions` — it is the queue card's contents given the room to be read, which is what a
/// merchant needs the moment an order stops being routine.
///
/// The screen is pushed from the queue rather than exported from the package's library file, so
/// the only route in is the card the merchant tapped. The pieces above it are the parts the three
/// merchant frames share and are used from the dashboard and the queue as well.
library;

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// The width past which the phone design stops growing and starts centring.
///
/// These screens are drawn for a 402dp handset and mounted by two hosts — the portal gives them
/// most of a 1400px window. Stretching a 16px-padded card list to 1300px does not make it more
/// readable, it makes every row a line the eye has to track across; so the column is capped at the
/// design's own comfortable measure and centred in whatever is left.
const double merchantMaxContentWidth = 720;

/// The 10px radius the redesign gives icon chips and in-card action buttons.
///
/// Deliberately a local constant rather than a new [DeliveryRadius] member: the token scale names
/// 8 (`sm`) and 12 (`md`) and the design sits between them here, so this records the measurement
/// without pretending the platform has a fifth radius step.
const double merchantChipRadius = 10;

/// Two decimal places, in one place.
///
/// Not a currency format: amounts arrive already in the store's own currency and the symbol
/// belongs to the store, not to a screen.
String merchantMoney(double amount) => amount.toStringAsFixed(2);

/// "10 mins ago", from the shared relative-time strings.
///
/// Returns an empty string when the order carries no timestamp, so a caller can drop the slot
/// rather than print a placeholder — a made-up time on an order card is worse than no time.
String merchantTimeAgo(DateTime? at, DeliveryStrings t) {
  if (at == null) return '';
  final Duration since = DateTime.now().difference(at);
  if (since.isNegative || since.inSeconds < 60) return t.justNow;
  if (since.inMinutes < 60) return t.minutesAgo(since.inMinutes);
  if (since.inHours < 24) return t.hoursAgo(since.inHours);
  return t.daysAgo(since.inDays);
}

/// The colour pair a status is painted in on the merchant surfaces.
class MerchantStatusTone {
  const MerchantStatusTone(this.color, this.background);

  final Color color;
  final Color background;
}

/// How the redesign paints each order state on a merchant screen.
///
/// The design draws a brand-tinted `New` and an amber `Preparing` on both the dashboard and the
/// queue, which is a departure from [DeliveryStatusColor]'s blue-grey `placed` — that palette is
/// still what the customer's tracking and the backoffice tables use. Kept in one function on
/// purpose: the whole point of Appendix A's rule is that a status cannot change colour between two
/// screens the same person looks at, and three copies of a switch is how that starts.
MerchantStatusTone merchantStatusTone(OrderStatus status) => switch (status) {
      OrderStatus.placed =>
        const MerchantStatusTone(DeliveryColors.brand, DeliveryColors.brandSoft),
      OrderStatus.accepted || OrderStatus.preparing => MerchantStatusTone(
          DeliveryAccent.caution.color, DeliveryAccent.caution.tint),
      OrderStatus.ready || OrderStatus.pickedUp =>
        MerchantStatusTone(DeliveryAccent.info.color, DeliveryAccent.info.tint),
      OrderStatus.delivered => MerchantStatusTone(
          DeliveryAccent.positive.color, DeliveryAccent.positive.tint),
      OrderStatus.cancelled => MerchantStatusTone(
          DeliveryAccent.critical.color, DeliveryAccent.critical.tint),
    };

/// The design's status tag: 8px/4px padding, radius 8, SemiBold 11 on its own tint.
///
/// Built on [YdBadge], whose geometry is that measurement already. Title case rather than the
/// badge's default caps, because that is how the merchant frames draw it.
class MerchantStatusTag extends StatelessWidget {
  const MerchantStatusTag({super.key, required this.status, required this.label});

  final OrderStatus status;

  /// Already localised by the caller.
  final String label;

  @override
  Widget build(BuildContext context) {
    final MerchantStatusTone tone = merchantStatusTone(status);
    return YdBadge(
      label: label,
      color: tone.color,
      background: tone.background,
      uppercase: false,
    );
  }
}

/// The redesign's KPI tile (Figma `metric-card` 3:1764).
///
/// A tinted icon chip, a 12px muted label and a Bold 22 value in a bordered radius-16 card.
class MerchantMetricCard extends StatelessWidget {
  const MerchantMetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
    required this.iconBackground,
    this.footnote,
    this.trend,
    this.onTap,
  });

  /// The brand-tinted chip the design gives the orders tile.
  const MerchantMetricCard.brand({
    Key? key,
    required IconData icon,
    required String label,
    required String value,
    String? footnote,
    Widget? trend,
    VoidCallback? onTap,
  }) : this(
          key: key,
          icon: icon,
          label: label,
          value: value,
          iconColor: DeliveryColors.brand,
          iconBackground: DeliveryColors.brandSoft,
          footnote: footnote,
          trend: trend,
          onTap: onTap,
        );

  /// A semantic-accent chip — the emerald money tile, and the queue tiles below it.
  MerchantMetricCard.accent({
    Key? key,
    required IconData icon,
    required String label,
    required String value,
    required DeliveryAccent accent,
    String? footnote,
    Widget? trend,
    VoidCallback? onTap,
  }) : this(
          key: key,
          icon: icon,
          label: label,
          value: value,
          iconColor: accent.color,
          iconBackground: accent.tint,
          footnote: footnote,
          trend: trend,
          onTap: onTap,
        );

  final IconData icon;

  /// Already localised by the caller.
  final String label;
  final String value;

  final Color iconColor;
  final Color iconBackground;

  /// The extra line the portal's dashboard puts under some figures ("last 14 days"). The design
  /// does not draw one; the tile simply grows when a caller has something to say.
  final String? footnote;

  /// How this figure compares with the one before it, drawn under the value.
  ///
  /// A figure on its own is a fact; a figure with "50% up on yesterday" under it is information,
  /// and it is the reason a merchant opens a dashboard rather than the orders list. Optional
  /// because most tiles here count a queue, and a queue has nothing to be compared with.
  final Widget? trend;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return YdCard.bordered(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: const EdgeInsetsDirectional.all(DeliverySpacing.sm),
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(merchantChipRadius),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(height: DeliverySpacing.sm),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: DeliveryColors.faint,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
              height: 1.2,
            ),
          ),
          if (trend != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            trend!,
          ],
          if (footnote != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            Text(
              footnote!,
              maxLines: 2,
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
    );
  }
}

/// Lays tiles out two to a row, which is the grid every merchant frame draws.
///
/// [IntrinsicHeight] rather than a stretched [Row]: inside a scroll view the row's height is
/// unbounded, and stretching against an unbounded constraint is an infinite height — a crash on
/// first paint rather than a cosmetic problem.
class MerchantTileGrid extends StatelessWidget {
  const MerchantTileGrid({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < tiles.length; i += 2) {
      final Widget first = tiles[i];
      final Widget? second = i + 1 < tiles.length ? tiles[i + 1] : null;
      if (rows.isNotEmpty) {
        rows.add(const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs));
      }
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: first),
              const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
              // An odd tile keeps its half of the row rather than spreading across it, so a
              // three-tile section still reads as a grid and not as a grid with one wide anomaly.
              Expanded(child: second ?? const SizedBox.shrink()),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }
}

/// The redesign's screen header: white, hairline underneath, back button then title.
///
/// Left-aligned with a 12px gap, exactly as `merchant-order-detail` draws it, which is why this is
/// not [YdScreenHeader] — that one centres its title between balanced slots. The 32px circle
/// itself is the shared [YdBackButton].
class MerchantScreenHeader extends StatelessWidget {
  const MerchantScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.backSemanticLabel,
    this.trailing,
  });

  /// Already localised by the caller.
  final String title;
  final String? subtitle;

  final VoidCallback? onBack;
  final String? backSemanticLabel;

  /// The end slot the design leaves empty and the portal needs for its refresh control.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(
        DeliverySpacing.lg,
        DeliverySpacing.md - DeliverySpacing.xs,
        DeliverySpacing.lg,
        DeliverySpacing.md,
      ),
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: Row(
        children: <Widget>[
          if (onBack != null) ...<Widget>[
            YdBackButton(onPressed: onBack!, semanticLabel: backSemanticLabel),
            const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
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
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// The action buttons the redesign draws under an order: equal widths, radius from the caller.
///
/// The label and the call are the same thing on purpose — a button that says one word and posts
/// another is how a state machine and a screen start disagreeing. The one rename the design makes
/// is `Cancel` → `Reject`, which is what the merchant is actually doing to an order they never
/// accepted; the wire action underneath is unchanged.
class MerchantActionButton extends StatelessWidget {
  const MerchantActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.primary,
    this.radius = merchantChipRadius,
    this.verticalPadding = 10,
    this.fontSize = 13,
    this.busy = false,
    this.outlined = false,
  });

  /// Already localised by the caller.
  final String label;
  final VoidCallback? onPressed;

  /// Filled brand when true, the recessed secondary otherwise.
  final bool primary;

  final double radius;
  final double verticalPadding;
  final double fontSize;
  final bool busy;

  /// The secondary dialect the order-detail frame draws: white with a [DeliveryColors.border]
  /// hairline, rather than the queue card's recessed background fill.
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !busy;
    final Color background = primary
        ? (enabled ? DeliveryColors.brand : DeliveryColors.brandLine)
        : (outlined ? DeliveryColors.white : DeliveryColors.background);
    final Color foreground = primary
        ? DeliveryColors.white
        : (enabled ? DeliveryColors.muted : DeliveryColors.faint);

    final BorderRadius corners = BorderRadius.circular(radius);

    return Semantics(
      button: true,
      // 48dp minimum, whatever the caller's padding works out to.
      //
      // The detail frame's own buttons (16px padding on 14px text) already measure just over this;
      // the queue card's tighter dialect (10px on 13px) comes out around 36, and 36 is not enough
      // for the control that accepts or rejects somebody's dinner, tapped in a hurry behind a
      // counter. A floor here rather than at each call site: the number is a property of a button
      // under a thumb, not of one screen.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: corners,
            side: !primary && outlined
                ? const BorderSide(color: DeliveryColors.border)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: DeliverySpacing.md,
                vertical: verticalPadding,
              ),
              child: Center(
                child: busy
                    ? SizedBox.square(
                        dimension: fontSize + 3,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(foreground),
                        ),
                      )
                    : Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                          color: foreground,
                          height: 1.2,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What a merchant-facing action is called on these screens.
String merchantActionLabel(OrderAction action, DeliveryStrings t) =>
    action == OrderAction.cancel ? t.merchReject : action.labelIn(t);

/// The 1px hairline the receipt card rules between its blocks.
class MerchantDivider extends StatelessWidget {
  const MerchantDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 1, child: ColoredBox(color: DeliveryColors.border));
}

/// One order in full — Figma `merchant-order-detail` (3:2104).
class MerchantOrderDetailScreen extends StatefulWidget {
  const MerchantOrderDetailScreen({
    super.key,
    required this.api,
    required this.order,
    this.onChanged,
  });

  final OrderApi api;

  /// The order as the list had it. Kept as the first paint so the screen opens on content rather
  /// than on a spinner, then refreshed against the server.
  final DeliveryOrder order;

  /// Told whenever this screen moves the order along, so the queue behind it can reload rather
  /// than sit on a status the merchant has just changed.
  final ValueChanged<DeliveryOrder>? onChanged;

  @override
  State<MerchantOrderDetailScreen> createState() => _MerchantOrderDetailScreenState();
}

class _MerchantOrderDetailScreenState extends State<MerchantOrderDetailScreen> {
  /// The four steps the design draws. `PLACED` is before all of them and `CANCELLED` is off the
  /// track entirely — both leave every bar grey, which is truthful about an order that has not
  /// started and one that never will.
  static const List<OrderStatus> _flow = <OrderStatus>[
    OrderStatus.accepted,
    OrderStatus.preparing,
    OrderStatus.ready,
    OrderStatus.pickedUp,
  ];

  late DeliveryOrder _order = widget.order;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final DeliveryOrder fresh = await widget.api.read(_order.id);
      if (!mounted) return;
      setState(() => _order = fresh);
    } catch (_) {
      // The list's copy stays on screen. It is seconds old and every figure on it came from the
      // same server — replacing a readable order with an error because a refresh failed would
      // lose the merchant the thing they opened this for.
    }
  }

  Future<void> _act(OrderAction action) async {
    setState(() => _busy = true);
    final DeliveryStrings t = DeliveryStrings.of(context);
    try {
      final DeliveryOrder updated = await widget.api.act(
        _order.id,
        action,
        // Not translated: the reason is stored against the order and read by Backoffice staff and
        // support, not shown back to the merchant who triggered it.
        reason: action == OrderAction.cancel ? 'Cancelled by merchant' : null,
      );
      if (!mounted) return;
      setState(() => _order = updated);
      widget.onChanged?.call(updated);
    } on DioException catch (e) {
      if (!mounted) return;
      // 422 means the order moved on since this screen was drawn — somebody else acted first.
      final String message = e.response?.statusCode == 422
          ? t.orderAlreadyMovedRefreshing
          : t.actionFailed(merchantActionLabel(action, t).toLowerCase());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            MerchantScreenHeader(
              // The design writes "Order #DV-7893" on one line; the reference is the part that
              // identifies this screen, so it leads and the word sits under it as the subtitle.
              title: '#${_order.shortId}',
              subtitle: t.orderDetails,
              onBack: () => Navigator.of(context).maybePop(),
              backSemanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _reload,
                color: DeliveryColors.brand,
                child: Align(
                  alignment: AlignmentDirectional.topCenter,
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: merchantMaxContentWidth),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md + DeliverySpacing.xs),
                      children: <Widget>[
                        _flowCard(t),
                        const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
                        _customerCard(t),
                        const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
                        _receiptCard(t),
                        if (_order.availableActions.isNotEmpty) ...<Widget>[
                          const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
                          _actions(t),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------- flow

  Widget _flowCard(DeliveryStrings t) {
    final int current = _flow.indexOf(_order.status);
    // Delivered is past the last drawn step, not missing from the track: everything is behind it.
    final int reached = _order.status == OrderStatus.delivered ? _flow.length - 1 : current;

    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  t.merchFlowStatus,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              Text(
                _order.status.labelIn(t),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: merchantStatusTone(_order.status).color,
                  height: 1.25,
                ),
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.xs),
            child: Row(
              children: <Widget>[
                for (int i = 0; i < _flow.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: DeliverySpacing.xs),
                  Expanded(child: _step(i, reached, t)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(int index, int reached, DeliveryStrings t) {
    final bool done = index <= reached;
    final bool isCurrent = index == reached && _order.status != OrderStatus.delivered;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          height: 4,
          decoration: BoxDecoration(
            color: done ? DeliveryColors.brand : DeliveryColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: DeliverySpacing.xs),
        Text(
          _stepLabel(_flow[index], t),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            fontWeight: done ? FontWeight.w600 : FontWeight.w400,
            color: isCurrent
                ? DeliveryColors.brand
                : (done ? DeliveryColors.ink : DeliveryColors.faint),
            height: 1.2,
          ),
        ),
      ],
    );
  }

  /// The design labels the last step "Picked Up" — the merchant's view of an order leaving the
  /// shop — where the shared status enum calls the same state "On the way", which is the
  /// customer's. Both are the truth from where they are standing.
  String _stepLabel(OrderStatus status, DeliveryStrings t) => switch (status) {
        OrderStatus.accepted => t.stepAccepted,
        OrderStatus.preparing => t.stepPreparing,
        OrderStatus.ready => t.stepReady,
        OrderStatus.pickedUp => t.merchStepPickedUp,
        _ => status.labelIn(t),
      };

  // ---------------------------------------------------------------- customer

  Widget _customerCard(DeliveryStrings t) {
    final String? phone = _order.contactPhone;

    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _sectionLabel(t.merchCustomerDetails),
          const SizedBox(height: DeliverySpacing.sm),
          // The design puts the customer's name here in Bold 16. The order payload carries a
          // customer *id* and nothing else, so the address leads instead — inventing a name, or
          // printing a UUID where a person should be, are both worse than not saying it.
          Text(
            _order.deliveryAddress.isEmpty
                ? t.deliverTo
                : '${t.deliverTo}: ${_order.deliveryAddress}',
            style: const TextStyle(
              fontSize: 13,
              color: DeliveryColors.muted,
              height: 1.4,
            ),
          ),
          if (phone != null && phone.isNotEmpty) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: DeliverySpacing.md - DeliverySpacing.xs,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: DeliveryColors.background,
                  borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.phone, size: 14, color: DeliveryColors.ink),
                    const SizedBox(width: 6),
                    Text(
                      phone,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DeliveryColors.ink,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- receipt

  Widget _receiptCard(DeliveryStrings t) {
    final String? notes = _order.notes;
    final bool hasNotes = notes != null && notes.trim().isNotEmpty;

    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _sectionLabel(t.merchItemsBreakdown),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          for (int i = 0; i < _order.items.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: DeliverySpacing.sm),
            _itemRow(_order.items[i], t),
          ],
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          const MerchantDivider(),
          if (hasNotes) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            Text(
              t.merchSpecialInstructions,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.faint,
                height: 1.25,
              ),
            ),
            const SizedBox(height: DeliverySpacing.xs),
            Text(
              '“${notes.trim()}”',
              style: const TextStyle(
                fontSize: 13,
                color: DeliveryColors.muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            const MerchantDivider(),
          ],
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          // A waiver on this order is the merchant's own money, so it is said on the receipt
          // rather than left to be noticed in a payout statement at the end of the month.
          if (_order.merchantFeeWaived || _order.deliveryFeeWaived) ...<Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.redeem_rounded, size: 15, color: DeliveryColors.brand),
                const SizedBox(width: DeliverySpacing.xs),
                Expanded(
                  child: Text(
                    _order.merchantFeeWaived
                        ? t.noCommissionOnThisOrder
                        : t.deliveryPaidByPlatform,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: DeliveryColors.brand,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: DeliverySpacing.sm),
          ],
          _totalRow(t.subtotal, merchantMoney(_order.goodsSubtotal)),
          const SizedBox(height: 6),
          _totalRow(
            t.deliveryFeeLabelMerchant,
            merchantMoney(_order.deliveryFeeCharged),
          ),
          const SizedBox(height: DeliverySpacing.sm + 2),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  t.merchGrandTotal,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              Text(
                merchantMoney(_order.totalAmount),
                maxLines: 1,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.brand,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _itemRow(OrderLine line, DeliveryStrings t) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Text(
            t.lineQuantity(line.qty, line.productName),
            style: const TextStyle(
              fontSize: 14,
              color: DeliveryColors.ink,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(width: DeliverySpacing.sm),
        Text(
          merchantMoney(line.lineTotal),
          maxLines: 1,
          textAlign: TextAlign.end,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: DeliveryColors.ink,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _totalRow(String label, String value) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: DeliveryColors.muted,
              height: 1.3,
            ),
          ),
        ),
        const SizedBox(width: DeliverySpacing.sm),
        Text(
          value,
          maxLines: 1,
          textAlign: TextAlign.end,
          style: const TextStyle(
            fontSize: 13,
            color: DeliveryColors.ink,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: DeliveryColors.faint,
          height: 1.2,
        ),
      );

  // ----------------------------------------------------------------- actions

  /// Buttons come from `availableActions`, which the service computed — rendering anything else
  /// would offer a merchant a transition the state machine would refuse.
  Widget _actions(DeliveryStrings t) {
    final List<OrderAction> actions = _order.availableActions;

    return Row(
      children: <Widget>[
        for (int i = 0; i < actions.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: MerchantActionButton(
              label: merchantActionLabel(actions[i], t),
              onPressed: _busy ? null : () => _act(actions[i]),
              primary: actions[i] != OrderAction.cancel,
              radius: DeliveryRadius.md,
              verticalPadding: DeliverySpacing.md,
              fontSize: 14,
              busy: _busy,
              outlined: true,
            ),
          ),
        ],
      ],
    );
  }
}
