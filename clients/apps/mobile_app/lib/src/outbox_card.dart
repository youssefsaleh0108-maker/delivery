import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'order_outbox.dart';

/// The frame's "Sync Outbox Queue" (121:279): every checkout waiting to be sent, or hidden when
/// there are none. Shown on the Orders tab above the live orders, and on the cached catalog.
class OutboxSection extends StatelessWidget {
  const OutboxSection({super.key, required this.outbox});

  final OrderOutbox outbox;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: outbox,
      builder: (BuildContext context, _) {
        final List<PendingOrder> items = outbox.items;
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              DeliveryStrings.of(context).offlineOutboxTitle,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: DeliveryColors.ink,
                height: 1.25,
              ),
            ),
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            for (int i = 0; i < items.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
              OutboxCard(pending: items[i], outbox: outbox),
            ],
          ],
        );
      },
    );
  }
}

/// One queued checkout, in each state the frame implies but does not draw.
///
/// The frame draws only "queued": an amber-bordered radius-16 card, a refresh glyph in an amber
/// radius-12 chip, "Order #4521 — Queued", the shop and amount, and an amber promise to send when
/// the connection returns. The other states are required all the same, and each says what the
/// customer can do about it:
///
/// * sending — a spinner, and nothing to press: its outcome is not known yet;
/// * the price changed — the new total, and a button that sends at that total (never on its own);
/// * waited too long — whether they still want it;
/// * refused — the server's reason, retry and discard.
///
/// The reference is the queued attempt's own, taken from its idempotency key — the order has no
/// server number until it exists.
class OutboxCard extends StatelessWidget {
  const OutboxCard({super.key, required this.pending, required this.outbox});

  final PendingOrder pending;
  final OrderOutbox outbox;

  static String _money(double amount) => '\$${amount.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool failed = pending.status == PendingOrderStatus.failed;
    final DeliveryAccent accent = failed ? DeliveryAccent.critical : DeliveryAccent.caution;

    return YdCard.bordered(
      borderColor: accent.color,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // The frame's chip: a radius-12 amber square, 10px around an 18px glyph.
          Container(
            padding: const EdgeInsetsDirectional.all(10),
            decoration: BoxDecoration(
              color: failed ? accent.tint : DeliveryColors.cautionSoft,
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
            ),
            child: SizedBox(
              width: 18,
              height: 18,
              child: pending.status == PendingOrderStatus.sending
                  ? CircularProgressIndicator(strokeWidth: 2, color: accent.onTint)
                  : Icon(_icon, size: 18, color: accent.onTint),
            ),
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  t.offlineQueuedTitle(pending.reference),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: DeliverySpacing.xs),
                Text(
                  t.offlineQueuedStoreAmount(
                    pending.storeName.isEmpty ? t.tabShop : pending.storeName,
                    _money(pending.expectedTotal),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.35),
                ),
                const SizedBox(height: DeliverySpacing.xs),
                ..._state(context, t, accent),
              ],
            ),
          ),
          if (pending.status == PendingOrderStatus.queued)
            IconButton(
              tooltip: t.offlineDiscard,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18, color: DeliveryColors.faint),
              onPressed: () => confirmDiscard(context, outbox, pending),
            ),
        ],
      ),
    );
  }

  IconData get _icon => switch (pending.status) {
        PendingOrderStatus.failed => Icons.error_outline_rounded,
        PendingOrderStatus.needsReview => Icons.priority_high_rounded,
        _ => Icons.sync_rounded,
      };

  List<Widget> _state(BuildContext context, DeliveryStrings t, DeliveryAccent accent) {
    TextStyle line(Color color) =>
        TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color, height: 1.35);

    switch (pending.status) {
      case PendingOrderStatus.queued:
        return <Widget>[Text(t.offlineWillSend, style: line(accent.onTint))];
      case PendingOrderStatus.sending:
        return <Widget>[Text(t.offlineSending, style: line(accent.onTint))];
      case PendingOrderStatus.needsReview:
        final bool priced = pending.review == PendingReview.priceChanged && pending.newTotal != null;
        return <Widget>[
          Text(
            priced ? t.offlinePriceChanged(_money(pending.newTotal!)) : t.offlineStale,
            style: line(DeliveryColors.ink),
          ),
          const SizedBox(height: DeliverySpacing.sm),
          _actions(
            context,
            primary: priced ? t.offlineSendAt(_money(pending.newTotal!)) : t.offlineSendNow,
            onPrimary: () => outbox.confirm(pending.key),
          ),
        ];
      case PendingOrderStatus.failed:
        final String? reason = pending.error;
        return <Widget>[
          Text(
            reason == null || reason.isEmpty ? t.couldNotPlaceOrder : t.offlineFailed(reason),
            style: line(accent.onTint),
          ),
          const SizedBox(height: DeliverySpacing.sm),
          _actions(context, primary: t.tryAgain, onPrimary: () => outbox.retry(pending.key)),
        ];
    }
  }

  Widget _actions(BuildContext context,
      {required String primary, required VoidCallback onPrimary}) {
    return Wrap(
      spacing: DeliverySpacing.sm,
      runSpacing: DeliverySpacing.sm,
      children: <Widget>[
        YdPillButton(
          label: primary,
          expand: false,
          size: YdPillButtonSize.compact,
          onPressed: onPrimary,
        ),
        YdPillButton.secondary(
          label: DeliveryStrings.of(context).offlineDiscard,
          expand: false,
          size: YdPillButtonSize.compact,
          onPressed: () => confirmDiscard(context, outbox, pending),
        ),
      ],
    );
  }
}

/// Asks before dropping a queued checkout. It is the only copy of that order anywhere.
Future<void> confirmDiscard(BuildContext context, OrderOutbox outbox, PendingOrder pending) async {
  final DeliveryStrings t = DeliveryStrings.of(context);
  final bool? discard = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      backgroundColor: DeliveryColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
      title: Text(t.offlineDiscardTitle,
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700, color: DeliveryColors.ink)),
      content: Text(t.offlineDiscardBody,
          style: const TextStyle(fontSize: 14, color: DeliveryColors.muted, height: 1.4)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          style: TextButton.styleFrom(foregroundColor: DeliveryColors.muted),
          child: Text(t.keepIt),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: DeliveryColors.brand,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.md)),
          ),
          child: Text(t.offlineDiscard),
        ),
      ],
    ),
  );
  if (discard == true) await outbox.discard(pending.key);
}
