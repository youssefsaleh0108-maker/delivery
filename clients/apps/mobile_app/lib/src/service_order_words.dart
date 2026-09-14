import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// How a service order reads to the customer who placed it: its status in words, the steps of its
/// timeline, when its work is promised, and why the platform refused it.
///
/// One file because more than one screen says these things — the Orders list's card, the tracking
/// screen, the order screen — and a card reading "Ready for pickup" over a page reading "Ready for
/// delivery" is the kind of disagreement a customer does not forgive. Kind-aware on purpose: the
/// shared [OrderStatusLabel] speaks a restaurant's language ("Preparing", "Ready for pickup" for a
/// rider's pickup), and a print run waiting at the counter is neither.

/// A dollar amount as every price on the phone is written: `$15.00`.
String svcUsd(double amount) => '\$${amount.toStringAsFixed(2)}';

/// A whole number with thousands grouped — `49,500` cards — so a pack count reads at a glance.
String svcCount(int value) {
  final String digits = value.abs().toString();
  final StringBuffer out = StringBuffer(value < 0 ? '-' : '');
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// The status of a service order in its customer's words.
///
/// A cancellation is named for what actually happened. A provider's decline and a pickup nobody came
/// for are both CANCELLED on the wire, and "Cancelled" alone would leave the customer wondering
/// whether they cancelled it themselves.
String serviceStatusLabel(DeliveryOrder order, DeliveryStrings t) => switch (order.status) {
      OrderStatus.placed => t.svcStatusWaiting,
      OrderStatus.accepted || OrderStatus.preparing => t.svcStatusInProgress,
      OrderStatus.ready => order.isPickup ? t.svcStatusReadyPickup : t.svcStatusReadyDelivery,
      OrderStatus.pickedUp => t.svcStatusOnTheWay,
      OrderStatus.delivered => order.isPickup ? t.svcStatusCollected : t.svcStatusCompleted,
      OrderStatus.cancelled => order.declineReason != null
          ? t.svcStatusDeclined
          : order.wasCancelledAsNotCollected
              ? t.svcStatusNotCollected
              : t.statusCancelled,
    };

/// How far along one step of a service order's timeline is.
enum ServiceStepState {
  /// Reached and behind the order.
  done,

  /// Where the order is now.
  current,

  /// Still ahead.
  pending,

  /// Where the order stopped: declined, not collected, or cancelled. Always the last step drawn.
  stopped,
}

/// One row of the tracking screen's timeline.
class ServiceTimelineStep {
  const ServiceTimelineStep({required this.label, required this.state});

  final String label;
  final ServiceStepState state;
}

/// The steps a service order takes, marked against where it is.
///
/// The path depends on how the customer gets the work: a pickup goes Placed → Accepted → In
/// production → Ready for pickup → Collected, and a delivery adds "Out for delivery" before
/// Delivered — the design's five rows fit neither exactly.
///
/// A cancelled order does not pretend to a future: the steps it reached, from its [history], are
/// done, and one stopped step says why it ended — the provider's decline with its reason in the
/// reader's language, a pickup never collected, or a plain cancellation. The rows it never reached
/// are not drawn as pending, because they are not going to happen.
List<ServiceTimelineStep> serviceTimeline(
    DeliveryOrder order, List<OrderStatusChange> history, DeliveryStrings t) {
  final bool pickup = order.isPickup;
  final List<(OrderStatus, String)> path = <(OrderStatus, String)>[
    (OrderStatus.placed, t.svcTimelinePlaced),
    (OrderStatus.accepted, t.svcTimelineAccepted),
    (OrderStatus.preparing, t.svcTimelineInProduction),
    (OrderStatus.ready, pickup ? t.svcStatusReadyPickup : t.svcStatusReadyDelivery),
    if (!pickup) (OrderStatus.pickedUp, t.svcTimelineOutForDelivery),
    (OrderStatus.delivered, pickup ? t.svcStatusCollected : t.stepDelivered),
  ];
  int indexOf(OrderStatus status) =>
      path.indexWhere(((OrderStatus, String) step) => step.$1 == status);

  // The furthest step the history proves was reached. Placed always was: the order exists.
  int furthest = 0;
  for (final OrderStatusChange change in history) {
    final int i = indexOf(change.status);
    if (i > furthest) furthest = i;
  }

  if (order.status == OrderStatus.cancelled) {
    return <ServiceTimelineStep>[
      for (int i = 0; i <= furthest; i++)
        ServiceTimelineStep(label: path[i].$2, state: ServiceStepState.done),
      ServiceTimelineStep(label: _stopLabel(order, t), state: ServiceStepState.stopped),
    ];
  }

  // Where the order says it is. A status with no row on this path — a pickup reported as picked
  // up — leaves the furthest proven step as the place it stands.
  final int at = indexOf(order.status);
  final int current = at < 0 ? furthest : at;
  final bool finished = order.status == OrderStatus.delivered;
  return <ServiceTimelineStep>[
    for (int i = 0; i < path.length; i++)
      ServiceTimelineStep(
        label: path[i].$2,
        state: i < current || (finished && i == current)
            ? ServiceStepState.done
            : i == current
                ? ServiceStepState.current
                : ServiceStepState.pending,
      ),
  ];
}

String _stopLabel(DeliveryOrder order, DeliveryStrings t) {
  final DeclineReason? declined = order.declineReason;
  if (declined != null) return t.svcDeclinedReason(declined.labelIn(t));
  if (order.wasCancelledAsNotCollected) return t.svcTimelineNotCollected;
  return t.statusCancelled;
}

/// A moment as a customer reads a promise: "Today, 5:00 PM", "Tomorrow, 2:00 PM", and further out
/// the date with its weekday — all in the reader's own locale and clock.
///
/// [now] is for tests; the screen reads the phone's clock.
String serviceWhenLabel(BuildContext context, DateTime at, {DateTime? now}) {
  final DeliveryStrings t = DeliveryStrings.of(context);
  final MaterialLocalizations dates = MaterialLocalizations.of(context);
  final DateTime local = at.toLocal();
  final DateTime clock = (now ?? DateTime.now()).toLocal();
  final DateTime today = DateTime(clock.year, clock.month, clock.day);
  final DateTime day = DateTime(local.year, local.month, local.day);
  final String time = dates.formatTimeOfDay(TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context));
  if (day == today) return t.svcTodayAt(time);
  // Built from the calendar rather than by adding 24 hours, which a daylight-saving night breaks.
  if (day == DateTime(today.year, today.month, today.day + 1)) return t.svcTomorrowAt(time);
  return t.svcDateAt(dates.formatMediumDate(local), time);
}

/// "18:00:00" or "18:00" as the reader's clock writes it ("6:00 PM"); null for anything else.
String? serviceClockLabel(BuildContext context, String? raw) {
  final List<String> parts = (raw ?? '').split(':');
  if (parts.length < 2) return null;
  final int? hour = int.tryParse(parts[0]);
  final int? minute = int.tryParse(parts[1]);
  if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return null;
  }
  return MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay(hour: hour, minute: minute),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context));
}

/// The turnaround an offer promises, in hours ("24–48 hours", "Up to 72 hours"); null when it
/// promises none, so nothing is drawn rather than a number nobody gave.
String? serviceTurnaroundLabel(int? minHours, int? maxHours, DeliveryStrings t) {
  if (maxHours == null || maxHours < 1) return null;
  if (minHours == null || minHours >= maxHours) return t.svcTurnaroundUpTo('$maxHours');
  return t.svcTurnaroundRange('$minHours', '$maxHours');
}

/// Why Order Manager refused a service order — or its file — in the customer's words.
///
/// The file codes read the same whether the upload was refused or the placement that named the file
/// was, which is why they share one enum. What the order screen never sends (Express, a gift, a
/// basket, a provider's step) and a code this build does not know are still refusals, said plainly:
/// nothing was placed, and the customer can change the order.
String serviceRefusalMessage(ServiceOrderRefusal refusal, DeliveryStrings t) => switch (refusal) {
      ServiceOrderRefusal.categoryClosed => t.svcRefusedCategoryClosed,
      ServiceOrderRefusal.offerNotOrderable => t.svcRefusedOfferNotOrderable,
      ServiceOrderRefusal.fulfilmentNotOffered => t.svcRefusedFulfilment,
      ServiceOrderRefusal.attachmentsUnavailable => t.svcRefusedAttachmentsUnavailable,
      ServiceOrderRefusal.fileWrongType => t.svcRefusedWrongType,
      ServiceOrderRefusal.fileEmpty => t.svcRefusedEmpty,
      ServiceOrderRefusal.fileTooLarge => t.svcRefusedTooLarge,
      ServiceOrderRefusal.tooManyFilesWaiting => t.svcRefusedTooManyWaiting,
      ServiceOrderRefusal.fileNotUploaded => t.svcRefusedNotUploaded,
      ServiceOrderRefusal.fileExpired => t.svcRefusedExpired,
      ServiceOrderRefusal.fileAlreadyAttached => t.svcRefusedAlreadyAttached,
      ServiceOrderRefusal.tooManyFiles => t.svcRefusedTooManyFiles,
      ServiceOrderRefusal.duplicateFile => t.svcRefusedDuplicate,
      ServiceOrderRefusal.filesNotAccepted => t.svcRefusedNotAccepted,
      ServiceOrderRefusal.fileRequired => t.svcFileRequired,
      ServiceOrderRefusal.unknownFile => t.svcRefusedUnknownFile,
      ServiceOrderRefusal.packsOutOfRange => t.svcRefusedPacks,
      ServiceOrderRefusal.oneServiceAtATime ||
      ServiceOrderRefusal.notAServiceOrder ||
      ServiceOrderRefusal.standardOnly ||
      ServiceOrderRefusal.notGiftable ||
      ServiceOrderRefusal.cashOnly ||
      ServiceOrderRefusal.notInBasket ||
      ServiceOrderRefusal.notOnBehalf ||
      ServiceOrderRefusal.declineReasonRequired ||
      ServiceOrderRefusal.notCollectable ||
      ServiceOrderRefusal.uncollectedTooSoon ||
      ServiceOrderRefusal.reservedCancelReason ||
      ServiceOrderRefusal.notDeclinable ||
      ServiceOrderRefusal.unknown =>
        t.svcRefusedGeneric,
    };
