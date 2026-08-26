import 'package:flutter/material.dart';

/// The crimson brand system, matched to the owner's 2026-08 Figma redesign
/// (figma.com/design/4lIJm9HXkQtTQHqhBIpNfB, "YouDrop").
///
/// Third palette this file has carried: fire-engine red, then rose (2026-08-12, picked against
/// WCAG), now the Figma crimson — applied as designed, at the owner's explicit request. The token
/// *names* survive every repaint on purpose; `brand` stays true whatever colour it holds.
///
/// Every surface in the platform reads from these values — the three Flutter clients through this
/// file, and the Keycloak login page through the matching custom properties in
/// `infra/keycloak/themes/delivery/login/resources/css/delivery.css`. **Those two lists must be
/// changed together**, or the sign-in page stops matching the app it signs you into.
///
/// Contrast, measured not asserted:
///
/// | pairing                  | rose (previous) | figma crimson |
/// | ------------------------ | --------------- | ------------- |
/// | white on primary         |            5.78 | 4.70          |
/// | primary on the soft tint |            5.11 | 4.28          |
///
/// White-on-primary still clears AA. Primary-on-tint no longer does for body text (4.28 < 4.5,
/// fine for 18px+/14px-bold). The design was applied exactly as drawn and the owner was told;
/// until it is revisited in Figma, do not put body-sized brand text on [brandSoft] — use [ink].
abstract final class DeliveryColors {
  /// Primary buttons, active nav state, brand accents, and — new in this design — whole-screen
  /// hero backgrounds (welcome, pending-approval).
  ///
  /// Figma: the fill on `unified-welcome` and every primary button.
  static const Color brand = Color(0xFFE11D48);

  /// Gradients, header fills, hover/pressed states.
  ///
  /// Tailwind rose-800, the darker stop the design pairs with the primary.
  static const Color brandDark = Color(0xFF9F1239);

  /// Badges, subtle tinted backgrounds, empty-state icon rings.
  ///
  /// Rose-50: the tint the design uses on the overwhelming majority of screens (status pills,
  /// Edit chips, icon rings). A handful of frames stray to rose-100/red-100; the inventory
  /// treats those as design slips rather than a second token.
  static const Color brandSoft = Color(0xFFFFF1F2);

  /// A stronger wash where the soft tint would disappear — selected chips, pressed tints.
  static const Color brandSoftStrong = Color(0xFFFFE4E6);

  /// Borders on brand-tinted surfaces (e.g. dropzones).
  static const Color brandLine = Color(0xFFFDA4AF);

  /// Primary text. Slate-900 — the design draws every neutral on the slate ramp.
  static const Color ink = Color(0xFF0F172A);

  /// Secondary / help text (slate-600).
  ///
  /// Carries caption text at 11–12px, so it is picked to clear AA on both the page background and
  /// white rather than to sit prettily between them.
  static const Color muted = Color(0xFF475569);

  /// The third text tier the design adds below [muted]: placeholders, timestamps, de-emphasised
  /// meta (slate-400). Decorative sizes only — 3.0:1 on white, it does not clear AA for body text.
  static const Color faint = Color(0xFF94A3B8);

  /// Card and input borders (slate-200).
  static const Color border = Color(0xFFE2E8F0);

  /// The lighter border weight the design gives auth inputs at rest (slate-100).
  static const Color borderFaint = Color(0xFFF1F5F9);

  /// App / page background (slate-50).
  static const Color background = Color(0xFFF8FAFC);

  /// The dark shell the web consoles and marketing bands sit on: sidebar background.
  static const Color shell = Color(0xFF111827);

  /// Raised elements on [shell] — the active nav item, the sidebar footer card.
  static const Color shellRaised = Color(0xFF1F2937);

  /// The darkest shell stop: page-width dark banners, the tracking pill.
  static const Color shellDeep = Color(0xFF0F172A);

  /// Secondary text on the dark shell.
  static const Color onShellMuted = Color(0xFF9CA3AF);

  /// Cards, surfaces, primary-button text.
  static const Color white = Color(0xFFFFFFFF);

  /// Text and icons on [brand] that the design renders in the rose wash rather than pure white —
  /// taglines, card subtitles on the welcome screen. 3.91:1 on brand: large/bold text only.
  static const Color onBrandSoft = Color(0xFFFFE4E6);

  /// Translucent white card fill used on brand-coloured screens (role cards, language pill).
  ///
  /// Figma: `rgba(255,255,255,0.15)` with a `rgba(255,255,255,0.2)` border.
  static const Color onBrandSurface = Color(0x26FFFFFF);

  /// Border for [onBrandSurface] cards.
  static const Color onBrandBorder = Color(0x33FFFFFF);
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
  /// Healthy, live, complete. Emerald-500, per the Figma redesign.
  ///
  /// The previous values here were darkened until they cleared 3:1 on white; the design's are
  /// brighter and do not all clear it (this green is 2.5:1 on white). Applied as designed at the
  /// owner's request — so the old rule hardens into: the strong value is for glyphs and numbers ON
  /// the tint, never for text on bare white at body sizes.
  positive(Color(0xFF10B981)),

  /// Needs a look, but nothing is broken — pending, near a limit, waiting on somebody.
  caution(Color(0xFFF59E0B)),

  /// Stopped, failed, refused.
  critical(Color(0xFFEF4444)),

  /// Categorical rather than judgemental: a count that is neither good nor bad.
  ///
  /// Kept from the previous system — the design never paints purple, but existing call sites do,
  /// and a categorical colour that matches nothing else in the palette is doing its job.
  neutral(Color(0xFF6C5CE0)),

  /// Informational, and the one that reads as "in motion". Blue-500.
  info(Color(0xFF3B82F6));

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
/// `inTransit` was the brand colour until the 2026-08 Figma redesign, which paints "ON THE WAY"
/// blue on every surface that shows it. Blue also reads better here: on the redesigned screens the
/// brand crimson is everywhere, and a status that shares it stops standing for anything.
enum DeliveryStatusColor {
  placed(Color(0xFF546E7A), 'Placed'),
  preparing(Color(0xFFF59E0B), 'Preparing'),
  inTransit(Color(0xFF3B82F6), 'In transit'),
  delivered(Color(0xFF10B981), 'Delivered'),
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

/// Corner radii, from the Figma redesign's measured geometry.
///
/// Read off the frames rather than estimated: chips/tags 8–10, inputs/buttons/images 12, cards 16,
/// sheet tops 24, and the customer app's tall CTAs fully rounded. (The 32px corner every mobile
/// frame carries is the drawn phone bezel, not an app surface — adopting it as a token was an
/// early misreading, corrected here.)
abstract final class DeliveryRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;

  /// Bottom-sheet and modal tops.
  static const double sheet = 24;

  static const double pill = 999;
}

abstract final class DeliveryTypography {
  /// Rubik, per the 2026-08 Figma redesign — bundled in this package (see pubspec), so the
  /// family resolves identically on every platform instead of falling back per-device.
  ///
  /// The `packages/` prefix is how Flutter addresses a font declared in a dependency package;
  /// without it the clients would each need their own copy of the files.
  static const String fontFamily = 'packages/delivery_design_system/Rubik';
  static const List<String> fontFamilyFallback = <String>[
    '-apple-system',
    'Segoe UI',
    'Roboto',
    'sans-serif',
  ];
}
