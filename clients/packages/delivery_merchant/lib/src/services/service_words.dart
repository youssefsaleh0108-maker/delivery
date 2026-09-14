/// The provider screens' shared words: prices and their LBP line, packs, an order's chip, how long
/// until something, when something is due, and why the server refused a step.
///
/// One file because the dashboard, the offers list, the queue and the order detail all print the same
/// facts, and a pack that reads "500 cards" on one screen and "cards × 500" on the next is two
/// screens disagreeing about one offer.
library;

import 'dart:math' as math;

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import '../order_detail_screen.dart';

/// "$15.00" in the reader's language; Arabic writes the sign after the figure.
String svcUsd(double amount, DeliveryStrings t) => t.svcPriceUsd(merchantMoney(amount));

/// "1,350,000 LBP" at the platform's rate, rounded to the thousand — or null when there is no rate.
///
/// Always converted, never typed: the provider orders frame printed 1,350,000 LBP beside $16.00, which
/// at the platform's 90,000 is 1,440,000. And never an invented rate: no figure is better than a wrong
/// one.
String? svcLbp(double usd, DeliveryStrings t) {
  final int? pounds = MarketRates.instance.lbpRounded(usd);
  return pounds == null ? null : t.svcPriceLbp(svcThousands(pounds));
}

/// 1350000 as "1,350,000".
String svcThousands(int amount) {
  final String digits = amount.abs().toString();
  final StringBuffer out = StringBuffer(amount < 0 ? '-' : '');
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// How an offer is sold: "500 cards", "Per sqm" — or null for a single piece at a fixed price, which
/// needs no line of its own.
String? svcPackLine(ServiceTerms? terms, DeliveryStrings t) {
  final String? unit = terms?.unitLabel;
  if (terms == null || unit == null) return null;
  if (terms.pricingType == ServicePricingType.perUnit) return t.svcUnitPer(unit);
  return t.svcUnitPack(svcThousands(terms.unitSize), unit);
}

/// The price an offer's row shows: "From $15.00" for a starting price — the catalogue's own sum of the
/// price and the cheapest required choices — and the price itself otherwise.
String svcOfferPrice(Product offer, DeliveryStrings t) {
  if (offer.service?.pricingType == ServicePricingType.from) {
    return t.svcFromPrice(svcUsd(offer.fromPrice ?? offer.price, t));
  }
  return svcUsd(offer.price, t);
}

/// What a service order earns the shop before commission: its subtotal.
///
/// Not the total, which carries a delivery fee the shop never receives. A server that sends no
/// subtotal still sent every line's total, and their sum is the same figure.
double svcShopAmount(DeliveryOrder order) =>
    order.subtotal ??
    order.items.fold<double>(0, (double sum, OrderLine line) => sum + line.lineTotal);

/// The job's name as a counter says it: the offer, or "3 × Logo design" for several single pieces.
String svcJobTitle(OrderLine line, DeliveryStrings t) {
  final ServiceOrderLine? terms = line.service;
  if ((terms == null || terms.unitLabel == null) && line.qty > 1) {
    return t.lineQuantity(line.qty, line.productName);
  }
  return line.productName;
}

/// What exactly to make: "1,000 cards · Matte finish" — packs × pack size in the offer's unit, then
/// the options as the server joined them. Null when there is nothing beyond the name.
String? svcJobDetail(OrderLine line, DeliveryStrings t) {
  final ServiceOrderLine? terms = line.service;
  final String? unit = terms?.unitLabel;
  final List<String> parts = <String>[
    if (terms != null && unit != null) t.svcUnitPack(svcThousands(terms.units), unit),
    if (line.optionsSummary != null) line.optionsSummary!,
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// The chip a service order carries, in words a counter uses: NEW, IN PRODUCTION, READY, COLLECTED,
/// DECLINED, NOT COLLECTED.
///
/// Its own mapping rather than the goods queue's status labels: a service order's PREPARING is a print
/// run in production, its DELIVERED at a counter is a collection, and its cancellations are three
/// different stories the shop needs told apart.
({String label, MerchantStatusTone tone}) svcOrderChip(DeliveryOrder order, DeliveryStrings t) {
  MerchantStatusTone accent(DeliveryAccent a) => MerchantStatusTone(a.onTint, a.tint);
  const MerchantStatusTone brand = MerchantStatusTone(DeliveryColors.brand, DeliveryColors.brandSoft);
  return switch (order.status) {
    OrderStatus.placed => (label: t.svcChipNew, tone: accent(DeliveryAccent.caution)),
    OrderStatus.accepted => (label: t.svcChipAccepted, tone: brand),
    OrderStatus.preparing => (label: t.svcChipInProduction, tone: brand),
    OrderStatus.ready => (label: t.svcChipReady, tone: accent(DeliveryAccent.info)),
    OrderStatus.pickedUp => (label: t.svcChipOnTheWay, tone: accent(DeliveryAccent.info)),
    OrderStatus.delivered => (
        label: order.isPickup ? t.svcChipCollected : t.svcChipDelivered,
        tone: accent(DeliveryAccent.positive),
      ),
    OrderStatus.cancelled => (
        label: order.declineReason != null
            ? t.svcChipDeclined
            : order.wasCancelledAsNotCollected
                ? t.svcChipNotCollected
                : t.svcChipCancelled,
        tone: accent(DeliveryAccent.critical),
      ),
  };
}

/// The chip itself, on the design's badge geometry.
class SvcOrderChip extends StatelessWidget {
  const SvcOrderChip({super.key, required this.order});

  final DeliveryOrder order;

  @override
  Widget build(BuildContext context) {
    final ({String label, MerchantStatusTone tone}) chip =
        svcOrderChip(order, DeliveryStrings.of(context));
    return YdBadge(
      label: chip.label,
      color: chip.tone.color,
      background: chip.tone.background,
      uppercase: false,
      fontSize: 10,
    );
  }
}

/// "Pickup" or "Delivery", as a quiet chip. Null for a fulfilment this build does not know: a chip
/// that guesses would tell a counter to expect a rider who is not coming.
Widget? svcFulfilmentChip(DeliveryOrder order, DeliveryStrings t) {
  final String? label = switch (order.fulfilment) {
    Fulfilment.pickup => t.svcChipPickup,
    Fulfilment.delivery => t.svcChipDelivery,
    Fulfilment.unknown => null,
  };
  if (label == null) return null;
  return YdBadge(
    label: label,
    icon: order.isPickup ? Icons.storefront_outlined : Icons.two_wheeler_outlined,
    color: DeliveryColors.muted,
    background: DeliveryColors.background,
    uppercase: false,
    fontSize: 10,
  );
}

/// An offer's state as its row's chip: ACTIVE, PAUSED or DRAFT. Null for an archived offer, which no
/// provider screen lists.
Widget? svcOfferStatusChip(ProductStatus status, DeliveryStrings t) => switch (status) {
      ProductStatus.active => YdBadge(
          label: t.svcOfferActive,
          color: DeliveryAccent.positive.onTint,
          background: DeliveryAccent.positive.tint,
          uppercase: false,
          fontSize: 10,
        ),
      ProductStatus.paused => YdBadge(
          label: t.svcOfferPaused,
          color: DeliveryColors.muted,
          background: DeliveryColors.border,
          uppercase: false,
          fontSize: 10,
        ),
      ProductStatus.draft => YdBadge(
          label: t.svcOfferDraft,
          color: DeliveryAccent.caution.onTint,
          background: DeliveryAccent.caution.tint,
          uppercase: false,
          fontSize: 10,
        ),
      ProductStatus.archived => null,
    };

/// "2d 5h", "5h 12m", "12m": how long until something, to the minute. Never "0m" — a countdown with
/// under a minute left says one.
String svcDuration(Duration left, DeliveryStrings t) {
  if (left.inDays >= 1) {
    return t.svcDurationDaysHours('${left.inDays}', '${left.inHours % 24}');
  }
  if (left.inHours >= 1) {
    return t.svcDurationHoursMinutes('${left.inHours}', '${left.inMinutes % 60}');
  }
  return t.svcDurationMinutes('${math.max(1, left.inMinutes)}');
}

/// A formatter for when something is due — the time alone for today, the date and the time otherwise
/// — in the reader's language, from the context's own localizations.
///
/// Made before a step awaits anything, so a step that finishes after its screen has gone can still say
/// when the work is promised.
String Function(DateTime) svcWhenFormatter(BuildContext context, {DateTime Function()? clock}) {
  final MaterialLocalizations words = MaterialLocalizations.of(context);
  final bool twentyFour = MediaQuery.alwaysUse24HourFormatOf(context);
  return (DateTime at) {
    final DateTime local = at.toLocal();
    final DateTime now = (clock ?? DateTime.now)();
    final String time =
        words.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: twentyFour);
    final bool today =
        local.year == now.year && local.month == now.month && local.day == now.day;
    return today ? time : '${words.formatShortMonthDay(local)} $time';
  };
}

/// Why the server refused a provider's step, in the provider's language.
///
/// Every one of these means the order on screen is out of date, which is why each ends in
/// "Refreshing" — and the screen does refresh.
String svcStepRefusalWords(ServiceOrderRefusal refusal, DeliveryStrings t) => switch (refusal) {
      ServiceOrderRefusal.notDeclinable ||
      ServiceOrderRefusal.reservedCancelReason =>
        t.svcRefusedNotDeclinable,
      ServiceOrderRefusal.notCollectable => t.svcRefusedNotCollectable,
      ServiceOrderRefusal.uncollectedTooSoon => t.svcRefusedTooSoon,
      _ => t.svcRefusedOther,
    };

/// "240 KB", "2.4 MB" — or null when the server did not say.
String? svcFileSize(int? bytes, DeliveryStrings t) {
  if (bytes == null || bytes < 0) return null;
  const int mb = 1024 * 1024;
  if (bytes < mb) return t.svcFileSizeKb('${math.max(1, (bytes / 1024).round())}');
  return t.svcFileSizeMb((bytes / mb).toStringAsFixed(1));
}

/// The turnaround choices the offer form offers, as whole-hour ranges.
///
/// Presets rather than free hours: "1–2 days" is what a customer reads and what a provider means, and
/// the order's promised time is acceptance plus the longest of them, so the longest has to be a
/// number somebody chose on purpose.
enum SvcTurnaround {
  sameDay(1, 8),
  oneToTwoDays(24, 48),
  threeToFiveDays(72, 120),
  aboutAWeek(120, 168);

  const SvcTurnaround(this.minHours, this.maxHours);

  final int minHours;
  final int maxHours;

  String labelIn(DeliveryStrings t) => switch (this) {
        SvcTurnaround.sameDay => t.svcTurnaroundSameDay,
        SvcTurnaround.oneToTwoDays => t.svcTurnaround1to2,
        SvcTurnaround.threeToFiveDays => t.svcTurnaround3to5,
        SvcTurnaround.aboutAWeek => t.svcTurnaroundWeek,
      };

  /// The preset these hours are, or null for hours no preset names (set some other way).
  static SvcTurnaround? matching(int? minHours, int? maxHours) {
    for (final SvcTurnaround preset in values) {
      if (preset.minHours == minHours && preset.maxHours == maxHours) return preset;
    }
    return null;
  }
}

/// A turnaround in words: the preset's name when it is one, "24–60 hours" when it is not, and null
/// when the offer promised none.
String? svcTurnaroundWords(int? minHours, int? maxHours, DeliveryStrings t) {
  if (minHours == null || maxHours == null) return null;
  return SvcTurnaround.matching(minHours, maxHours)?.labelIn(t) ??
      t.svcTurnaroundHours('$minHours', '$maxHours');
}

/// A customer's initials for the queue's avatar: "JD" for "Jean-Pierre D.". Null without a name.
///
/// Initials and never a photo: the order carries a display name the customer's own account gave, and
/// a picture of them is not something a print shop needs to see.
String? svcInitials(String? name) {
  final List<String> words =
      (name ?? '').trim().split(RegExp(r'\s+')).where((String w) => w.isNotEmpty).toList();
  if (words.isEmpty) return null;
  final String first = words.first.characters.first;
  final String second = words.length > 1 ? words[1].characters.first : '';
  return (first + second).toUpperCase();
}

/// The round initials tile beside a customer's name.
class SvcCustomerAvatar extends StatelessWidget {
  const SvcCustomerAvatar({super.key, required this.name, this.size = 32});

  final String? name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String? initials = svcInitials(name);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: DeliveryColors.brandSoft, shape: BoxShape.circle),
        child: initials == null
            ? Icon(Icons.person_outline, size: size * 0.55, color: DeliveryColors.brand)
            : Text(
                initials,
                style: TextStyle(
                  fontSize: size * 0.38,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.brand,
                  height: 1,
                ),
              ),
      ),
    );
  }
}
