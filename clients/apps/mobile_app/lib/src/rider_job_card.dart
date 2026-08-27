import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// The rider board's cards and the small parts they are assembled from.
///
/// Two cards live here because the 2026-08 Figma redesign draws two, and they are deliberately
/// different shapes rather than one card in two states:
///
/// * [RiderJobCard] is the *offer* card (`offer-card`, frame 3:1163). It sells a job — payout
///   first, then where it runs between, then one full-width button that takes it.
/// * [RiderTaskCard] is the *task* card (`task-card`, frame 3:1255). It tracks a job already
///   taken — status and age first, then the reference and the money, then the two stops as
///   labelled fields, then a split action row.
///
/// The parts below ([RiderButton], [RiderRouteRow], [RiderTag], [RiderHairline]) are shared with
/// the order-detail and earnings screens so that a rose button on one rider screen is the same
/// object as a rose button on the next.
///
/// Everything reads its geometry from `tokens.dart`; the design's raw hexes map onto it exactly
/// (`#e11d48` brand, `#10b981` positive, `#94a3b8` faint, `#fff1f2` brandSoft, and so on).

/// How a [RiderButton] is painted. The redesign uses three fills and no others.
enum RiderButtonStyle {
  /// Brand fill, white label. The step-forward action.
  filled,

  /// The page background as a fill, muted label. The design's grey secondary
  /// (`nav-btn`, `#f8fafc` on white).
  soft,

  /// Transparent with a 1px brand outline and a brand label (`secondary-cta`, `logout-btn`).
  outlined,
}

/// The redesign's rider button: a **12px-radius rectangle**, not a pill.
///
/// Deliberately not [YdPillButton] — the customer surface's CTAs are fully rounded and the rider
/// surface's are [DeliveryRadius.md]. They are different objects in the design and swapping one
/// for the other is visible on every rider screen at once.
///
/// [trailing] carries the [YdComingSoon] chip on the affordances that have no backend yet, so an
/// inert button still looks like the button the design drew.
class RiderButton extends StatelessWidget {
  const RiderButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = RiderButtonStyle.filled,
    this.fontSize = 14,
    this.fontWeight = FontWeight.w600,
    this.verticalPadding = 12,
    this.busy = false,
    this.trailing,
  });

  final String label;

  /// Null disables the button — which is also how an inert affordance is drawn.
  final VoidCallback? onPressed;

  final RiderButtonStyle style;
  final double fontSize;
  final FontWeight fontWeight;

  /// The design's three button heights are expressed as vertical padding: 10 (split row),
  /// 12 (accept), 14 (the tall CTAs).
  final double verticalPadding;

  final bool busy;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !busy;

    final Color background = switch (style) {
      RiderButtonStyle.filled =>
        enabled ? DeliveryColors.brand : DeliveryColors.brandLine,
      RiderButtonStyle.soft => DeliveryColors.background,
      RiderButtonStyle.outlined => Colors.transparent,
    };
    final Color foreground = switch (style) {
      RiderButtonStyle.filled => DeliveryColors.white,
      RiderButtonStyle.soft => DeliveryColors.muted,
      RiderButtonStyle.outlined => DeliveryColors.brand,
    };
    final BorderSide side = style == RiderButtonStyle.outlined
        ? const BorderSide(color: DeliveryColors.brand)
        : BorderSide.none;

    final BorderRadius corners = BorderRadius.circular(DeliveryRadius.md);

    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(borderRadius: corners, side: side),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: Padding(
            padding: EdgeInsetsDirectional.symmetric(
              horizontal: DeliverySpacing.md,
              vertical: verticalPadding,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (busy)
                  SizedBox.square(
                    dimension: fontSize + 2,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(foreground),
                    ),
                  )
                else
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: fontWeight,
                        color: foreground,
                        height: 1.2,
                      ),
                    ),
                  ),
                if (trailing != null && !busy) ...<Widget>[
                  const SizedBox(width: DeliverySpacing.sm),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The neutral tag the offer card hangs off the end of its payout row
/// (`distance-tag`: [DeliveryColors.background] fill, [DeliveryRadius.sm], 12px semibold muted).
class RiderTag extends StatelessWidget {
  const RiderTag({super.key, required this.label, this.color, this.background});

  final String label;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: DeliverySpacing.sm,
        vertical: DeliverySpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background ?? DeliveryColors.background,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color ?? DeliveryColors.muted,
          height: 1.2,
        ),
      ),
    );
  }
}

/// The 1px rule the redesign puts between the sections of every multi-part card.
class RiderHairline extends StatelessWidget {
  const RiderHairline({super.key});

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, thickness: 1, color: DeliveryColors.border);
}

/// One stop on a route: an 8px dot, a 10px gap, and a two-line text group.
///
/// The design draws two dialects of this and uses them in different places, so both are here:
///
/// * [RiderRouteRow] — title over detail (offer card): 13px semibold over 11px regular.
/// * [RiderRouteRow.labelled] — caption over value (task card): 11px regular uppercase caption
///   over a 14px semibold value.
class RiderRouteRow extends StatelessWidget {
  const RiderRouteRow({
    super.key,
    required this.dot,
    required this.title,
    this.detail,
  })  : caption = null,
        labelled = false;

  const RiderRouteRow.labelled({
    super.key,
    required this.dot,
    required String this.caption,
    required this.title,
  })  : detail = null,
        labelled = true;

  /// [DeliveryColors.brand] for a pickup, [DeliveryColors.ink] for a drop-off.
  final Color dot;

  final String title;
  final String? detail;
  final String? caption;
  final bool labelled;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (labelled)
                Text(
                  caption!.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: DeliveryColors.faint,
                    height: 1.3,
                  ),
                ),
              Text(
                title,
                maxLines: labelled ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: labelled ? 14 : 13,
                  fontWeight: FontWeight.w600,
                  color: DeliveryColors.ink,
                  height: 1.3,
                ),
              ),
              if (detail != null && detail!.isNotEmpty)
                Text(
                  detail!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: DeliveryColors.muted,
                    height: 1.35,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The status chip's colour, taken from the one widget that owns the status→colour mapping.
///
/// [OrderStatusBadge] is the single place the platform decides what a status *means* in colour, and
/// the rule is that the answer must not change between the rider app, the merchant queue and the
/// back-office. This reads that decision back out rather than restating it, so the rider chip can
/// wear the redesign's flat 8px shape ([YdStatusPill]) without forking the mapping — which is how
/// "ON THE WAY" ends up blue here exactly as the design draws it.
DeliveryStatusColor riderStatusColour(String wire) {
  final Color colour = OrderStatusBadge.colorFor(wire);
  return DeliveryStatusColor.values.firstWhere(
    (DeliveryStatusColor s) => s.color == colour,
    orElse: () => DeliveryStatusColor.offline,
  );
}

/// How long ago something happened, in the rider's language.
///
/// The design puts a countdown ("10 mins left") beside the status chip. There is no delivery SLA
/// anywhere in the data model, so a countdown here would be an invented number; the *age* of the
/// job is real, is what a rider is actually judging, and fills the same slot.
String? riderAgeLabel(DeliveryStrings t, DateTime? since) {
  if (since == null) return null;
  final Duration elapsed = DateTime.now().difference(since);
  if (elapsed.isNegative) return null;
  if (elapsed.inMinutes < 60) return t.riderMinutesAgo(elapsed.inMinutes);
  return t.riderHoursAgo(elapsed.inHours);
}

/// How far away something is, in the rider's language: kilometres past a kilometre, metres below.
///
/// Takes the server's metres and never invents them — callers pass a distance the tracking API
/// actually returned.
String riderDistanceLabel(DeliveryStrings t, double metres) => metres >= 1000
    ? t.riderKmUnit((metres / 1000).toStringAsFixed(1))
    : t.riderMetreUnit(metres.round().toString());

/// Localised strings for the wave-2 rider wiring, resolved from the same keys the l10n fragment
/// carries (`l10n-fragments2/rider2.json` and the API layer's `core.json`).
///
/// This extension exists so the wiring compiles and speaks both languages *before* the fragment is
/// merged into the shared .arb files. Every member matches its fragment key by name and by value,
/// and Dart resolves instance members ahead of extension members — so the moment the finish agent
/// merges and regenerates `DeliveryStrings`, the generated getters take over at every call site
/// and this extension goes dormant. It can then be deleted.
extension RiderWave2Strings on DeliveryStrings {
  bool get _ar => localeName.startsWith('ar');
  String _s(String en, String ar) => _ar ? ar : en;

  // ---------------------------------------------------------------- earnings + cash-out
  String riderBalanceLine(String balance, String available) => _s(
      'Balance $balance · available for cash-out $available',
      'الرصيد $balance · المتاح للسحب $available');
  String riderEarningsBreakdown(String earnings, String tips) =>
      _s('$earnings delivery pay · $tips tips', '$earnings أجرة توصيل · $tips إكراميات');
  String get riderCashOutTitle => _s('Cash out', 'سحب الرصيد');
  String get riderCashOutAvailable => _s('Available to cash out', 'المتاح للسحب');
  String riderCashOutMinimum(String amount) =>
      _s('Minimum $amount', 'الحد الأدنى $amount');
  String get riderCashOutManualNote => _s(
      'Payouts are handed over by the platform team — nothing transfers automatically.',
      'تُسلَّم الدفعات يدوياً من فريق المنصة — لا يُحوَّل شيء تلقائياً.');
  String get riderCashOutRequest => _s('Request cash-out', 'طلب سحب');
  String get riderCashOutAmountLabel => _s('Amount', 'المبلغ');
  String get riderCashOutAlreadyOpen => _s('A cash-out request is already on its way.',
      'هناك طلب سحب قيد المعالجة بالفعل.');
  String get riderCashOutFailed =>
      _s('The cash-out could not be requested.', 'تعذّر طلب السحب.');
  String riderCashOutOpenLine(String amount) => _s(
      '$amount requested — waiting on the payout', '$amount مطلوبة — بانتظار التسليم');
  String get riderCashOutLastRefused =>
      _s('Your last cash-out was refused.', 'رُفض طلب السحب الأخير.');
  String get riderCashOutHistory => _s('Recent requests', 'الطلبات الأخيرة');
  String riderTipLine(String tip) => _s('+$tip tip', '+$tip إكرامية');
  String riderReimbursedLine(String amount) =>
      _s('+$amount reimbursed', '+$amount مستردّة');

  // ---------------------------------------------------------------- duty + presence
  String riderLastSeen(String when) => _s('Last seen $when', 'آخر ظهور $when');
  String get riderDutyChangeFailed =>
      _s('Could not update your duty state.', 'تعذّر تحديث حالة الدوام.');
  String get riderDutyNotYetDeclared =>
      _s('You have not gone on duty yet.', 'لم تبدأ الدوام بعد.');
  String get dutyOnDuty => _s('On duty', 'على رأس العمل');
  String get dutyOffDuty => _s('Off duty', 'خارج الدوام');
  String get presenceSignalLost => _s('Signal lost', 'انقطعت الإشارة');

  // ---------------------------------------------------------------- eta
  String get riderEtaCaption => _s('Live ETA', 'الوقت المتوقع للوصول');
  String riderEtaAway(String distance) =>
      _s('$distance away', 'على بُعد $distance');
  String riderEtaArrivingAt(String time) =>
      _s('arriving about $time', 'الوصول نحو $time');
  String riderKmUnit(String km) => _s('$km km', '$km كم');
  String riderMetreUnit(String m) => _s('$m m', '$m م');
  String riderEtaComputedBy(String provider) =>
      _s('Estimated by $provider', 'التقدير من $provider');
  String get etaWaitingFirstFix => _s("Waiting for the rider's first GPS fix",
      'بانتظار أول إشارة GPS من السائق');
  String get etaPositionOutOfDate =>
      _s("The rider's position is out of date", 'موقع السائق غير محدَّث');
  String get etaNoMapPoint =>
      _s('No map point to measure to', 'لا توجد نقطة على الخريطة للقياس إليها');
  String get etaRouteServiceDown =>
      _s('The route service did not answer', 'خدمة المسارات لم تستجب');
  String get etaNothingOnItsWay =>
      _s('Nothing is on its way', 'لا يوجد شيء في الطريق');
  String get etaUnavailable =>
      _s('No estimate available', 'لا يتوفر تقدير للوصول');
  String get etaHeadingToShop => _s('Heading to the shop', 'في الطريق إلى المتجر');
  String get etaOnTheWayToYou => _s('On the way to you', 'في الطريق إليك');
  String get etaStraightLineNote => _s(
      'Rough estimate — measured in a straight line, not by road',
      'تقدير تقريبي — يُقاس بخط مستقيم لا عبر الطرقات');

  // ---------------------------------------------------------------- money labels
  String get cashOutRequested => _s('Requested', 'مطلوب');
  String get cashOutPaid => _s('Paid', 'مدفوع');
  String get cashOutRefused => _s('Refused', 'مرفوض');
  String get paidByPlatform => _s('Paid by the platform', 'تدفعها المنصة');
  String get paidByYourCompany => _s('Paid by your company', 'تدفعها شركتك');
  String get paidElsewhere => _s('Paid elsewhere', 'تُدفع خارج المنصة');
  String get ratingNewRider => _s('New', 'جديد');

  // ---------------------------------------------------------------- chat
  String get riderChatTitle => _s('Customer chat', 'محادثة الزبون');
  String get riderChatHint => _s('Type a message…', 'اكتب رسالة…');
  String get riderChatSend => _s('Send', 'إرسال');
  String get riderChatClosed =>
      _s('This conversation has closed.', 'أُغلقت هذه المحادثة.');
  String get riderChatEmpty => _s('No messages yet.', 'لا رسائل بعد.');
  String get riderChatCouldNotLoad =>
      _s('Could not load the conversation', 'تعذّر تحميل المحادثة');
  String get riderChatSendFailed =>
      _s('The message was not sent.', 'لم تُرسَل الرسالة.');
  String get riderChatReconnecting => _s('Reconnecting…', 'جارٍ إعادة الاتصال…');
}

/// The sentence for an ETA the server declined to number.
String riderEtaReasonLabel(DeliveryStrings t, EtaUnavailableReason reason) =>
    switch (reason) {
      EtaUnavailableReason.noFix => t.etaWaitingFirstFix,
      EtaUnavailableReason.staleFix => t.etaPositionOutOfDate,
      EtaUnavailableReason.noDestination => t.etaNoMapPoint,
      EtaUnavailableReason.providerUnavailable => t.etaRouteServiceDown,
      EtaUnavailableReason.orderComplete => t.etaNothingOnItsWay,
      EtaUnavailableReason.unknown => t.etaUnavailable,
    };

/// Which stretch of the journey an estimate covers, in the rider's language.
String riderEtaLegLabel(DeliveryStrings t, EtaLeg leg) => switch (leg) {
      EtaLeg.toPickup => t.etaHeadingToShop,
      EtaLeg.toDropoff => t.etaOnTheWayToYou,
    };

/// Where a cash-out request has got to, in the rider's language.
String riderCashOutStatusLabel(DeliveryStrings t, CashOutStatus status) =>
    switch (status) {
      CashOutStatus.requested => t.cashOutRequested,
      CashOutStatus.paid => t.cashOutPaid,
      CashOutStatus.rejected => t.cashOutRefused,
      CashOutStatus.unknown => status.label,
    };

/// Who owes a job line, in the rider's language.
String riderPayerLabel(DeliveryStrings t, EarningsPayer payer) => switch (payer) {
      EarningsPayer.platform => t.paidByPlatform,
      EarningsPayer.carrier => t.paidByYourCompany,
      EarningsPayer.unknown => t.paidElsewhere,
    };

/// An offer on the board: what it pays, where it runs between, and the button that takes it.
///
/// Figma `offer-card` (3:1188). Its own file so it can be pumped on its own — the screen around it
/// runs two periodic timers, which a widget test cannot settle, and the layout risk is all in here.
class RiderJobCard extends StatelessWidget {
  const RiderJobCard({
    super.key,
    required this.order,
    required this.busy,
    required this.onAction,
  });

  final DeliveryOrder order;
  final bool busy;
  final void Function(OrderAction) onAction;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    // Server-supplied actions only — the rider is never offered a step the state machine would
    // refuse, including CLAIM on an order another rider already took.
    final List<OrderAction> forward = order.availableActions
        .where((OrderAction a) => a != OrderAction.cancel)
        .toList();

    return YdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // The payout, first and largest — it is the fact a rider decides on. It renders the
          // order's delivery fee, which is the real money attached to this job.
          Row(
            children: <Widget>[
              Text(
                order.deliveryFee.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: DeliveryAccent.positive.color,
                  height: 1.2,
                ),
              ),
              const Spacer(),
              // The design's slot for a neutral distance tag. There are no coordinates in the data
              // model, so it carries the one fact that changes what happens at the door instead:
              // a rider who arrives thinking an order is prepaid either leaves without the money or
              // has an argument on a doorstep.
              if (order.collectsCashOnDelivery)
                RiderTag(
                  label: t.collectCash(order.totalAmount.toStringAsFixed(2)),
                  color: DeliveryAccent.caution.color,
                  background: DeliveryAccent.caution.tint,
                )
              else
                RiderTag(
                  label: t.itemCountWithDot(
                    order.items.fold<int>(0, (int a, OrderLine l) => a + l.qty),
                  ),
                ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          const RiderHairline(),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          if (order.storeName != null && order.storeName!.isNotEmpty) ...<Widget>[
            RiderRouteRow(
              dot: DeliveryColors.brand,
              title: order.storeName!,
              detail: t.pickUpFrom,
            ),
            const SizedBox(height: DeliverySpacing.sm),
          ],
          RiderRouteRow(
            dot: DeliveryColors.ink,
            title: order.deliveryAddress,
            detail: order.contactPhone,
          ),
          if (order.notes != null && order.notes!.isNotEmpty) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(DeliverySpacing.sm),
              decoration: BoxDecoration(
                color: DeliveryColors.background,
                borderRadius: BorderRadius.circular(DeliveryRadius.sm),
              ),
              child: Text(
                order.notes!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: DeliveryColors.muted,
                  height: 1.35,
                ),
              ),
            ),
          ],
          for (final OrderAction action in forward) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            SizedBox(
              width: double.infinity,
              child: RiderButton(
                // The board's headline action is a claim, and the design names it for what it does
                // to the rider's day rather than for the transition it fires.
                label: action == OrderAction.claim
                    ? t.riderAcceptDelivery
                    : action.labelIn(t),
                busy: busy,
                onPressed: busy ? null : () => onAction(action),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A job the rider has already taken: how far along it is, how old, and the two ways on.
///
/// Figma `task-card` (3:1269). The step-forward action deliberately is *not* here — the design
/// moves it onto the detail screen behind "View Details", so a rider cannot mark an order
/// picked up by brushing a list they were scrolling.
class RiderTaskCard extends StatelessWidget {
  const RiderTaskCard({
    super.key,
    required this.order,
    required this.onOpen,
  });

  final DeliveryOrder order;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final DeliveryStatusColor status = riderStatusColour(order.status.wire);
    final String? age = riderAgeLabel(t, order.placedAt);

    return YdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              YdStatusPill(status: status, label: order.status.labelIn(t)),
              const Spacer(),
              if (age != null)
                Text(
                  age,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: status.color,
                    height: 1.2,
                  ),
                ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  t.riderOrderRef(order.shortId),
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
                order.deliveryFee.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: DeliveryAccent.positive.color,
                  height: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          const RiderHairline(),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          if (order.storeName != null && order.storeName!.isNotEmpty) ...<Widget>[
            RiderRouteRow.labelled(
              dot: DeliveryColors.brand,
              caption: t.pickUpFrom,
              title: order.storeName!,
            ),
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          ],
          RiderRouteRow.labelled(
            dot: DeliveryColors.ink,
            caption: t.dropOffAt,
            title: order.deliveryAddress,
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          Row(
            children: <Widget>[
              // Turn-by-turn needs coordinates and a routing engine, neither of which exists yet.
              Expanded(
                child: RiderButton(
                  label: t.riderNavigate,
                  style: RiderButtonStyle.soft,
                  fontSize: 13,
                  verticalPadding: 10,
                  onPressed: null,
                  trailing: YdComingSoon(label: t.riderComingSoon),
                ),
              ),
              const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
              Expanded(
                child: RiderButton(
                  label: t.riderViewDetails,
                  fontSize: 13,
                  verticalPadding: 10,
                  onPressed: onOpen,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
