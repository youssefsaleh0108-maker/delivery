import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../order_detail_screen.dart';
import 'service_words.dart';

/// A step a provider can take on a service order.
enum SvcStep {
  /// A new order, declined for a reason from the picklist.
  decline,

  /// A new order, accepted — which a service order takes straight into production.
  accept,

  /// An accepted order put into production, for a server that leaves acceptance as its own step.
  startProduction,

  /// The work is done: ready at the counter, or for a rider.
  markReady,

  /// The customer collected their pickup at the counter.
  collected,

  /// A pickup nobody came for, cancelled once the customer's time to collect is up.
  cancelNotCollected,
}

/// The steps [order] offers its shop right now, in the order a card draws them.
///
/// Strictly from what the server offered. A button for a step the server did not offer would be a
/// transition the state machine refuses — and a Collected button on a pickup the server has not
/// marked ready is a customer told their cards were collected when they were not.
///
/// A CANCEL the server offers is drawn only where it means something to a counter: on a new order it
/// is Decline, which asks for a reason, and on a pickup waiting past its time it is "Cancel as not
/// collected". Anywhere else it stays undrawn — cancelling work in production is support's call in
/// this version (no refunds or disputes), and a bare cancel would reach the customer with no reason.
List<SvcStep> svcStepsFor(DeliveryOrder order) {
  final List<OrderAction> offered = order.availableActions;
  return <SvcStep>[
    if (order.status == OrderStatus.placed && offered.contains(OrderAction.cancel)) SvcStep.decline,
    if (offered.contains(OrderAction.accept)) SvcStep.accept,
    if (offered.contains(OrderAction.prepare)) SvcStep.startProduction,
    if (offered.contains(OrderAction.ready)) SvcStep.markReady,
    if (offered.contains(OrderAction.collected)) SvcStep.collected,
    if (order.canCancelAsNotCollected) SvcStep.cancelNotCollected,
  ];
}

/// What came of a step, as far as the screen that offered it is concerned.
enum SvcStepResult {
  /// Something was sent: it went through, or the server refused it. Either way the order on screen is
  /// out of date, and the screen reads it again.
  reload,

  /// The provider closed the sheet or the dialog, and nothing was sent.
  dismissed,
}

/// A provider's steps on a service order, each with the sheet, the dialog and the sentence it needs.
///
/// One place for the queue's cards and the order detail both: a decline that asks for a reason on one
/// screen and not the other is how a customer ends up told nothing.
class SvcOrderSteps {
  const SvcOrderSteps(this.api);

  final OrderApi api;

  /// Runs [step] on [order]. [onSending] is called once the provider has confirmed and the request is
  /// about to go, so a card shows its spinner then and not behind an open sheet.
  Future<SvcStepResult> run(
    BuildContext context,
    DeliveryOrder order,
    SvcStep step, {
    VoidCallback? onSending,
  }) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String Function(DateTime) when = svcWhenFormatter(context);

    switch (step) {
      case SvcStep.accept:
        onSending?.call();
        return _act(messenger, t, order, OrderAction.accept, (DeliveryOrder moved) {
          final DateTime? promised = moved.estimatedReadyAt;
          return promised == null ? t.svcAccepted : t.svcAcceptedReadyBy(when(promised));
        });
      case SvcStep.startProduction:
        onSending?.call();
        return _act(messenger, t, order, OrderAction.prepare, (_) => t.saved);
      case SvcStep.markReady:
        onSending?.call();
        return _act(messenger, t, order, OrderAction.ready, (_) => t.svcMarkedReady);
      case SvcStep.decline:
        final DeclineReason? reason = await showModalBottomSheet<DeclineReason>(
          context: context,
          isScrollControlled: true,
          backgroundColor: DeliveryColors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(DeliveryRadius.lg)),
          ),
          builder: (_) => const _DeclineSheet(),
        );
        if (reason == null) return SvcStepResult.dismissed;
        onSending?.call();
        return _service(messenger, t, () => api.decline(order.id, reason),
            done: t.svcOrderDeclined, failed: t.svcDecline);
      case SvcStep.collected:
        onSending?.call();
        return _service(messenger, t, () => api.collected(order.id),
            done: t.svcOrderCollected, failed: t.svcActionCollected);
      case SvcStep.cancelNotCollected:
        final String? note = await showDialog<String>(
          context: context,
          builder: (_) => const _NotCollectedDialog(),
        );
        if (note == null) return SvcStepResult.dismissed;
        onSending?.call();
        return _service(messenger, t, () => api.cancelNotCollected(order.id, note: note),
            done: t.svcOrderCancelledNotCollected, failed: t.svcCancelNotCollected);
    }
  }

  /// One of the order's own actions (`POST /api/orders/{id}/{action}`).
  Future<SvcStepResult> _act(
    ScaffoldMessengerState messenger,
    DeliveryStrings t,
    DeliveryOrder order,
    OrderAction action,
    String Function(DeliveryOrder moved) done,
  ) async {
    String message;
    try {
      message = done(await api.act(order.id, action));
    } on DioException catch (e) {
      // 422 means the order moved on since it was drawn: another device at the counter acted first.
      message = e.response?.statusCode == 422
          ? t.orderAlreadyMovedRefreshing
          : t.actionFailed(merchantActionLabel(action, t).toLowerCase());
    } catch (_) {
      message = t.actionFailed(merchantActionLabel(action, t).toLowerCase());
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
    return SvcStepResult.reload;
  }

  /// A step only a service order takes, whose refusal arrives as a value with a code.
  Future<SvcStepResult> _service(
    ScaffoldMessengerState messenger,
    DeliveryStrings t,
    Future<ServiceOrderActionResult> Function() send, {
    required String done,
    required String failed,
  }) async {
    String message;
    try {
      message = switch (await send()) {
        ServiceOrderUpdated() => done,
        ServiceOrderActionRefused(:final ServiceOrderRefusal refusal) =>
          svcStepRefusalWords(refusal, t),
      };
    } on DioException catch (e) {
      message = e.response?.statusCode == 422
          ? t.orderAlreadyMovedRefreshing
          : t.actionFailed(failed.toLowerCase());
    } catch (_) {
      message = t.actionFailed(failed.toLowerCase());
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
    return SvcStepResult.reload;
  }
}

/// One step's button, in the colours the orders frame gives each: Accept and Collected green, the
/// work's own steps brand, Decline recessed, and the not-collected cancel quietly outlined.
///
/// Green is the positive accent's darker stop, not the frame's emerald: white words on emerald-500
/// measure 2.5:1, and this is the button a shop taps in a hurry.
class SvcStepButton extends StatelessWidget {
  const SvcStepButton({
    super.key,
    required this.step,
    required this.onPressed,
    this.busy = false,
  });

  final SvcStep step;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String label = switch (step) {
      SvcStep.decline => t.svcDecline,
      SvcStep.accept => t.svcAcceptOrder,
      SvcStep.startProduction => merchantActionLabel(OrderAction.prepare, t),
      SvcStep.markReady => merchantActionLabel(OrderAction.ready, t),
      SvcStep.collected => t.svcActionCollected,
      SvcStep.cancelNotCollected => t.svcCancelNotCollected,
    };
    final (Color fill, Color ink, Color? edge) = switch (step) {
      SvcStep.accept || SvcStep.collected => (
          DeliveryAccent.positive.onTint,
          DeliveryColors.white,
          null,
        ),
      SvcStep.startProduction || SvcStep.markReady => (
          DeliveryColors.brand,
          DeliveryColors.white,
          null,
        ),
      SvcStep.decline => (DeliveryColors.border, DeliveryColors.muted, null),
      SvcStep.cancelNotCollected => (
          DeliveryColors.white,
          DeliveryAccent.critical.onTint,
          DeliveryColors.border,
        ),
    };
    final bool enabled = onPressed != null && !busy;

    return Semantics(
      button: true,
      enabled: enabled,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        child: Material(
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DeliveryRadius.sm),
            side: edge == null ? BorderSide.none : BorderSide(color: edge),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: DeliverySpacing.sm,
                vertical: DeliverySpacing.sm,
              ),
              child: Center(
                child: busy
                    ? SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(ink),
                        ),
                      )
                    : Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: ink,
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

/// A row of step buttons sharing the width equally, or nothing when the order offers none.
class SvcStepRow extends StatelessWidget {
  const SvcStepRow({super.key, required this.steps, required this.onStep, this.busy = false});

  final List<SvcStep> steps;
  final void Function(SvcStep step) onStep;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();
    return Row(
      children: <Widget>[
        for (int i = 0; i < steps.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: SvcStepButton(
              step: steps[i],
              busy: busy,
              onPressed: busy ? null : () => onStep(steps[i]),
            ),
          ),
        ],
      ],
    );
  }
}

/// "Why are you declining?" — the picklist, and a Decline that stays off until a reason is picked.
///
/// A code rather than the provider's words: the customer may read Arabic while the provider tapped an
/// English label, and a refusal is where free text goes wrong.
class _DeclineSheet extends StatefulWidget {
  const _DeclineSheet();

  @override
  State<_DeclineSheet> createState() => _DeclineSheetState();
}

class _DeclineSheetState extends State<_DeclineSheet> {
  DeclineReason? _chosen;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(
          DeliverySpacing.lg,
          DeliverySpacing.lg,
          DeliverySpacing.lg,
          DeliverySpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              t.svcDeclineTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: DeliveryColors.ink,
              ),
            ),
            const SizedBox(height: DeliverySpacing.xs),
            Text(
              t.svcDeclineBody,
              style: const TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.35),
            ),
            const SizedBox(height: DeliverySpacing.md),
            for (final DeclineReason reason in DeclineReason.picklist)
              _ReasonRow(
                label: reason.labelIn(t),
                selected: reason == _chosen,
                onTap: () => setState(() => _chosen = reason),
              ),
            const SizedBox(height: DeliverySpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: YdPillButton.secondary(
                    label: t.cancel,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: DeliverySpacing.sm),
                Expanded(
                  child: YdPillButton(
                    label: t.svcDeclineConfirm,
                    onPressed: _chosen == null ? null : () => Navigator.of(context).pop(_chosen),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
          child: Row(
            children: <Widget>[
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? DeliveryColors.brand : DeliveryColors.faint,
              ),
              const SizedBox(width: DeliverySpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: DeliveryColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Cancel this uncollected order?", with an optional note for the customer.
///
/// Pops the note — empty when the shop wrote none — or null when the shop keeps the order. The field
/// stops at the length the cancel reason leaves for it, so the shop sees where its words end.
class _NotCollectedDialog extends StatefulWidget {
  const _NotCollectedDialog();

  @override
  State<_NotCollectedDialog> createState() => _NotCollectedDialogState();
}

class _NotCollectedDialogState extends State<_NotCollectedDialog> {
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return AlertDialog(
      title: Text(t.svcCancelNotCollectedTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(t.svcCancelNotCollectedBody),
            const SizedBox(height: DeliverySpacing.md),
            TextField(
              controller: _note,
              maxLength: OrderApi.notCollectedNoteMaxLength,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(labelText: t.svcCancelNotCollectedNote),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.svcKeepOrder),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_note.text.trim()),
          child: Text(t.svcCancelNotCollected),
        ),
      ],
    );
  }
}
