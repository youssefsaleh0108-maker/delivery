import 'dart:math' as math;

import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.1 relative luminance.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG contrast ratio between two opaque colours, 1.0 (identical) to 21.0 (black on white).
double contrast(Color a, Color b) {
  final double x = _luminance(a);
  final double y = _luminance(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  // Appendix A says the theme file should mirror the token table directly rather than re-deriving
  // colours from the mockups by eye. This test is what stops that drifting: if someone "tidies" a
  // hex value, the build says so.
  group('Appendix A design tokens', () {
    test('brand colours match the approved table exactly', () {
      // Rose-red since 2026-08-12. If you change one of these, change the matching custom
      // property in infra/keycloak/themes/delivery/login/resources/css/delivery.css too — the
      // login page is the one surface in the platform that cannot read this file.
      expect(DeliveryColors.brand, const Color(0xFFC41D4E));
      expect(DeliveryColors.brandDark, const Color(0xFF8E1235));
      expect(DeliveryColors.brandSoft, const Color(0xFFFDEDF1));
      expect(DeliveryColors.brandLine, const Color(0xFFF1C6D3));
      expect(DeliveryColors.ink, const Color(0xFF241319));
      expect(DeliveryColors.muted, const Color(0xFF7E6A73));
      expect(DeliveryColors.border, const Color(0xFFEAD9DF));
      expect(DeliveryColors.background, const Color(0xFFFCF6F8));
      expect(DeliveryColors.white, const Color(0xFFFFFFFF));
    });

    test('text on brand surfaces clears WCAG AA', () {
      // The palette was picked against these numbers rather than by eye, so they are worth
      // holding: a future tweak that looks nicer but drops body text below 4.5 should fail here
      // rather than ship.
      expect(contrast(DeliveryColors.white, DeliveryColors.brand), greaterThan(4.5));
      expect(contrast(DeliveryColors.brand, DeliveryColors.white), greaterThan(4.5));
      expect(contrast(DeliveryColors.brand, DeliveryColors.brandSoft), greaterThan(4.5));
      expect(contrast(DeliveryColors.ink, DeliveryColors.background), greaterThan(4.5));
      // Carries caption text at 11-12px, which is exactly where a marginal ratio hurts most.
      expect(contrast(DeliveryColors.muted, DeliveryColors.background), greaterThan(4.5));
      expect(contrast(DeliveryColors.muted, DeliveryColors.white), greaterThan(4.5));
    });

    test('in-transit reuses the brand red rather than a sixth colour', () {
      expect(DeliveryStatusColor.inTransit.color, DeliveryColors.brand);
    });

    test('every status has a distinct colour', () {
      final Set<int> colours = DeliveryStatusColor.values
          .map((DeliveryStatusColor s) => s.color.toARGB32())
          .toSet();
      expect(colours.length, DeliveryStatusColor.values.length);
    });
  });

  group('theme', () {
    test('primary buttons are solid red with white text', () {
      final ThemeData theme = DeliveryTheme.light();
      final ButtonStyle? style = theme.elevatedButtonTheme.style;

      expect(style?.backgroundColor?.resolve(<WidgetState>{}), DeliveryColors.brand);
      expect(style?.foregroundColor?.resolve(<WidgetState>{}), DeliveryColors.white);
    });

    test('secondary buttons are white with a 1.5px red border', () {
      final ThemeData theme = DeliveryTheme.light();
      final ButtonStyle? style = theme.outlinedButtonTheme.style;

      expect(style?.backgroundColor?.resolve(<WidgetState>{}), DeliveryColors.white);
      expect(style?.foregroundColor?.resolve(<WidgetState>{}), DeliveryColors.brand);
      expect(style?.side?.resolve(<WidgetState>{})?.width, 1.5);
    });

    test('scaffold uses the page background token', () {
      expect(DeliveryTheme.light().scaffoldBackgroundColor, DeliveryColors.background);
    });
  });

  group('the semantic accents', () {
    test('every accent is legible on white and on its own tint', () {
      // These carry numbers and short labels at 10–24px. An accent that looks friendly and cannot
      // be read is a worse outcome than the flat interface it replaced.
      for (final DeliveryAccent accent in DeliveryAccent.values) {
        expect(contrast(accent.color, DeliveryColors.white), greaterThan(3.0),
            reason: '${accent.name} on white');
        // Composited over white, because that is what a 12% alpha tint actually renders as.
        final Color onWhite = Color.alphaBlend(accent.tint, DeliveryColors.white);
        expect(contrast(accent.color, onWhite), greaterThan(3.0),
            reason: '${accent.name} on its own tint');
      }
    });

    test('the accents are distinguishable from each other', () {
      // Two accents that read as the same colour convey nothing. Compared by hue rather than by
      // contrast: same-lightness colours can be far apart and still look identical.
      final List<double> hues = DeliveryAccent.values
          .map((DeliveryAccent a) => HSLColor.fromColor(a.color).hue)
          .toList();
      for (int i = 0; i < hues.length; i++) {
        for (int j = i + 1; j < hues.length; j++) {
          final double gap = (hues[i] - hues[j]).abs();
          expect(gap > 25 && gap < 335, isTrue,
              reason: '${DeliveryAccent.values[i].name} and ${DeliveryAccent.values[j].name} '
                  'are ${gap.toStringAsFixed(0)}° apart');
        }
      }
    });

    test('positive and critical are not the only difference between two states', () {
      // Colour alone fails for the ~8% of men with red-green colour blindness, which is why every
      // component pairing these also carries a word: StatePill has a label, StatTile has one under
      // the number. This pins the intent so a future "cleaner" version cannot drop the text.
      const StatePill pill = StatePill(label: 'Suspended', accent: DeliveryAccent.critical);
      expect(pill.label, isNotEmpty);
    });
  });

  group('navigation bar sizing', () {
    /// Five destinations, which is what the customer app carries and what the compact sizing is
    /// for. On a 375pt phone that is 75pt each.
    Future<void> pumpBar(WidgetTester tester) async {
      tester.view.physicalSize = const Size(375, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: DeliveryTheme.light(),
        home: Scaffold(
          bottomNavigationBar: NavigationBar(
            selectedIndex: 0,
            onDestinationSelected: (int _) {},
            destinations: const <Widget>[
              NavigationDestination(icon: Icon(Icons.storefront_outlined), label: 'Shops'),
              NavigationDestination(icon: Icon(Icons.pedal_bike_outlined), label: 'Butler'),
              NavigationDestination(icon: Icon(Icons.shopping_bag_outlined), label: 'Basket'),
              NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
              NavigationDestination(icon: Icon(Icons.person_outline_rounded), label: 'Account'),
            ],
          ),
        ),
      ));
    }

    testWidgets('the bar is shorter than the Material default', (WidgetTester tester) async {
      await pumpBar(tester);

      // Material's default is 80. The point of the theme override is that it is not that.
      expect(tester.getSize(find.byType(NavigationBar)).height, lessThan(70));
    });

    testWidgets('every destination still clears the 48pt touch target',
        (WidgetTester tester) async {
      await pumpBar(tester);

      // Smaller glyphs must not mean smaller targets: the tappable area is the whole destination,
      // and shrinking the bar past this point would trade accessibility for tidiness.
      final Size bar = tester.getSize(find.byType(NavigationBar));
      expect(bar.height, greaterThanOrEqualTo(48));
      expect(bar.width / 5, greaterThanOrEqualTo(48));
    });

    test('the label style is small enough for five of them', () {
      // Asserted on the style rather than by measuring rendered text: widget tests substitute a
      // fixed-width test font where every glyph is a full em box, so "Account" measures nearly
      // twice what Inter gives and any wrap assertion would be testing the test font.
      final TextStyle? style = DeliveryTheme.light()
          .navigationBarTheme
          .labelTextStyle
          ?.resolve(<WidgetState>{});

      expect(style?.fontSize, lessThanOrEqualTo(11));
    });
  });

  testWidgets('status badge renders its label', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      home: const Scaffold(
        body: DeliveryStatusBadge(status: DeliveryStatusColor.delivered),
      ),
    ));

    expect(find.text('Delivered'), findsOneWidget);
  });

  group('DeliveryLogo', () {
    testWidgets('occupies exactly the size it is given', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: DeliveryLogo(size: 96))),
      ));

      expect(tester.getSize(find.byType(DeliveryLogo)), const Size(96, 96));
    });

    testWidgets('is decorative unless given a label', (WidgetTester tester) async {
      // An unlabelled mark announced as an anonymous graphic is noise; the same mark next to the
      // app's name would be read twice.
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: DeliveryLogo(size: 40)),
      ));
      // Scoped to the logo: Material puts its own ExcludeSemantics in a Scaffold, so an unscoped
      // finder passes for the wrong reason.
      expect(
        find.descendant(
          of: find.byType(DeliveryLogo),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: DeliveryLogo(size: 40, semanticLabel: 'Delivery')),
      ));
      expect(find.bySemanticsLabel('Delivery'), findsOneWidget);
    });

    testWidgets('the wordmark puts the mark before the name', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: DeliveryWordmark(title: 'Delivery Backoffice')),
      ));

      final Rect mark = tester.getRect(find.byType(DeliveryLogo));
      final Rect name = tester.getRect(find.text('Delivery Backoffice'));
      expect(name.left, greaterThan(mark.right));
    });
  });

  group('ChipStrip layout', () {
    /// Pumps a strip of two icon-only chips. No image URLs: a widget test cannot fetch one, and
    /// the icon is the fallback the strip is built to show anyway.
    Future<void> pump(WidgetTester tester, ChipStripLayout layout) {
      return tester.pumpWidget(MaterialApp(
        theme: DeliveryTheme.light(),
        home: Scaffold(
          body: ChipStrip<String>(
            values: const <String>['Coffee', 'Groceries'],
            labelOf: (String v) => v,
            iconOf: (String _) => Icons.local_cafe_rounded,
            selected: 'Coffee',
            layout: layout,
            onSelected: (String? _) {},
          ),
        ),
      ));
    }

    testWidgets('stacked puts the label below the picture', (WidgetTester tester) async {
      await pump(tester, ChipStripLayout.stacked);

      final Rect icon = tester.getRect(find.byIcon(Icons.local_cafe_rounded).first);
      final Rect label = tester.getRect(find.text('Coffee'));

      expect(label.top, greaterThan(icon.bottom), reason: 'label should sit under the picture');
      // Centred on the same column, which is what makes the strip read as a grid of tiles.
      expect(label.center.dx, closeTo(icon.center.dx, 1));
    });

    testWidgets('pill keeps the label beside the glyph', (WidgetTester tester) async {
      await pump(tester, ChipStripLayout.pill);

      final Rect icon = tester.getRect(find.byIcon(Icons.local_cafe_rounded).first);
      final Rect label = tester.getRect(find.text('Coffee'));

      expect(label.left, greaterThan(icon.right), reason: 'the filter pills must not change');
      expect(label.center.dy, closeTo(icon.center.dy, 1));
    });

    testWidgets('every stacked chip shares one baseline', (WidgetTester tester) async {
      await pump(tester, ChipStripLayout.stacked);

      final Rect first = tester.getRect(find.byIcon(Icons.local_cafe_rounded).at(0));
      final Rect second = tester.getRect(find.byIcon(Icons.local_cafe_rounded).at(1));

      // A one-line label next to a two-line one must not shift the tiles out of alignment.
      expect(first.top, closeTo(second.top, 0.5));
      expect(first.height, closeTo(second.height, 0.5));
    });
  });
}
