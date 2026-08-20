import 'package:flutter/material.dart';

/// The rose-red / white brand system.
///
/// Fire-engine red originally, rose since 2026-08-12. Orange was tried the same day and reverted at
/// the owner's request — the token *names* are from that attempt and were kept deliberately, since
/// `brand` stays true whatever colour it holds and `red` did not.
///
/// Every surface in the platform reads from these values — the three Flutter clients through this
/// file, and the Keycloak login page through the matching custom properties in
/// `infra/keycloak/themes/delivery/login/resources/css/delivery.css`. **Those two lists must be
/// changed together**, or the sign-in page stops matching the app it signs you into.
///
/// Picked against WCAG contrast rather than by eye:
///
/// | pairing                  | old red | rose |
/// | ------------------------ | ------- | ---- |
/// | white on primary         |    4.98 | 5.78 |
/// | primary on the soft tint |    4.30 | 5.11 |
/// | muted on the background  |    4.10 | 4.69 |
///
/// The middle row is the one that mattered: red-on-tint failed AA for body text and rose does not.
///
/// For the record, since it is the reason a brand colour cannot simply be picked from a mood board:
/// the orange that was tried scored 5.18 and 4.76 on the first two rows — passing, but worse than
/// rose — and the *brighter* orange it was derived from scored **2.80**, which fails outright and
/// would have made every button in the platform unreadable.
abstract final class DeliveryColors {
  /// Primary buttons, active nav state, brand accents.
  ///
  /// One value, not two: rose clears AA both on white and as text on white, so unlike an orange
  /// brand it needs no separate darker variant for anything carrying text.
  static const Color brand = Color(0xFFC41D4E);

  /// Gradients, header fills, hover/pressed states.
  static const Color brandDark = Color(0xFF8E1235);

  /// Badges, subtle tinted backgrounds, empty-state icon rings.
  static const Color brandSoft = Color(0xFFFDEDF1);

  /// Borders on brand-tinted surfaces (e.g. dropzones).
  static const Color brandLine = Color(0xFFF1C6D3);

  /// Primary text.
  static const Color ink = Color(0xFF241319);

  /// Secondary / help text.
  ///
  /// Carries caption text at 11–12px, so it is picked to clear AA on both the page background and
  /// white rather than to sit prettily between them.
  static const Color muted = Color(0xFF7E6A73);

  /// Card and input borders.
  static const Color border = Color(0xFFEAD9DF);

  /// App / page background.
  static const Color background = Color(0xFFFCF6F8);

  /// Cards, surfaces, primary-button text.
  static const Color white = Color(0xFFFFFFFF);
}

/// The semantic accents, added 2026-08-12 to soften the interface.
///
/// <p>The brand is one colour and that is right for buttons, nav and identity — but an interface
/// that is one colour everywhere makes every element look equally important, which is the opposite of
/// friendly. These carry <em>meaning</em> instead: a count of things that are fine is green whoever
/// is looking at it, and a count of things that need attention is amber.
///
/// Each is a pair. The strong value is for the glyph and the number; [tintOf] gives the soft fill
/// behind it. Never use the strong value as a large fill behind text — they are picked for legibility
/// *on* white and on their own tint, not underneath body copy.
/// Every value below was darkened from the obvious "friendly" shade until it cleared 3:1 both on
/// white and on its own 12% tint. The first attempt used a brighter green and a proper amber, and
/// both failed — amber badly, at 2.68 on white. A cheerful palette nobody can read is a worse
/// outcome than the flat interface it replaced.
enum DeliveryAccent {
  /// Healthy, live, complete.
  positive(Color(0xFF25834B)),

  /// Needs a look, but nothing is broken — pending, near a limit, waiting on somebody.
  ///
  /// The darkest of the five relative to its hue, because amber is the colour that most often gets
  /// shipped illegible: at the brightness people reach for it lands near 2.7 on white.
  caution(Color(0xFFB86E0C)),

  /// Stopped, failed, refused.
  critical(Color(0xFFD4483B)),

  /// Categorical rather than judgemental: a count that is neither good nor bad.
  neutral(Color(0xFF6C5CE0)),

  /// Informational, and the one that reads as "in motion".
  info(Color(0xFF2582C2));

  const DeliveryAccent(this.color);

  final Color color;

  /// The soft fill this accent sits on. 12% is the lightest tint that still reads as a surface
  /// rather than as a rendering artefact on a low-quality screen.
  Color get tint => color.withValues(alpha: 0.12);

  /// A slightly stronger tint for a border on that fill.
  Color get line => color.withValues(alpha: 0.28);
}

/// Elevation as a shadow, not as a grey.
///
/// One shadow, used everywhere a card lifts off the page. Cards in this system are separated by
/// light and space rather than by borders — borders on every card produce the boxed-in look the
/// softer layout is meant to get away from.
abstract final class DeliveryShadows {
  static List<BoxShadow> get card => <BoxShadow>[
        BoxShadow(
          color: DeliveryColors.ink.withValues(alpha: 0.05),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ];

  /// For something that should read as lifted above the cards around it — a sheet, a picked-up
  /// item, the mark on the splash screen.
  static List<BoxShadow> get raised => <BoxShadow>[
        BoxShadow(
          color: DeliveryColors.ink.withValues(alpha: 0.10),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}

/// Order status colours.
///
/// Appendix A defines this palette semantically — "placed = blue-gray, preparing = amber,
/// delivered = green, offline = neutral gray" — without giving hex values, so the exact shades
/// below were chosen here and should be confirmed against the Phase 2 screens when those are
/// signed off. The *mapping* is the part that matters and is fixed: a status must not change
/// colour meaning between the Backoffice tables, the Merchant Portal and in-app tracking.
///
/// `inTransit` deliberately reuses the brand colour rather than introducing a sixth, because
/// in-transit is the state the brand naturally draws the eye to.
enum DeliveryStatusColor {
  placed(Color(0xFF546E7A), 'Placed'),
  preparing(Color(0xFFF59E0B), 'Preparing'),
  inTransit(DeliveryColors.brand, 'In transit'),
  delivered(Color(0xFF2E7D32), 'Delivered'),
  offline(Color(0xFF9E9E9E), 'Offline');

  const DeliveryStatusColor(this.color, this.label);

  final Color color;
  final String label;
}

/// Whether a shop is taking orders, and how that reads on a card.
///
/// Declared here rather than imported from `delivery_core` on purpose: this package deliberately
/// depends on nothing but Flutter, so it can be dropped into any of the three clients without
/// dragging the wire models along. Callers map their own transport enum onto this one.
///
/// The colours carry the meaning and must not be re-picked per screen — `busy` is amber because it
/// is a warning you can proceed through, `closed` is grey because it is not a warning at all, it is
/// an absence.
enum DeliveryStoreState {
  open(Color(0xFF2E7D32), 'Open'),
  busy(Color(0xFFF59E0B), 'Busy'),
  closingSoon(Color(0xFFEF6C00), 'Closing soon'),
  closed(Color(0xFF9E9E9E), 'Closed');

  const DeliveryStoreState(this.color, this.label);

  final Color color;
  final String label;

  /// Closed is the only state that stops a basket. The other two are advisory.
  bool get acceptsOrders => this != DeliveryStoreState.closed;
}

/// Spacing scale. Everything is a multiple of 4 so layouts stay on a consistent rhythm across
/// three separately-built clients.
abstract final class DeliverySpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class DeliveryRadius {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 16;
  static const double pill = 999;
}

abstract final class DeliveryTypography {
  /// Appendix A: Inter, with a system fallback for platforms where it is not bundled.
  static const String fontFamily = 'Inter';
  static const List<String> fontFamilyFallback = <String>[
    '-apple-system',
    'Segoe UI',
    'Roboto',
    'sans-serif',
  ];
}
