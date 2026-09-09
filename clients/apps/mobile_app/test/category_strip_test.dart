import 'package:delivery_core/delivery_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/category_strip.dart';

/// The category row on the customer home, and whether it is tall enough for what is in it.
///
/// It was not. The strip reserved a hand-written `SizedBox(height: 96)` while a card occupies
/// 80.1 inside 20 pixels of list padding — 100.1 in total — so Flutter drew the yellow-and-black
/// overflow banner across all five categories and clipped every label through the middle. At the
/// DEFAULT font size, on the first screen of the app, against a real backend.
///
/// Nothing caught it because nothing could mount just this row: the height lived beside the widget
/// as a literal, and the only way to see the two together was to build the entire home screen. So
/// the fix was to make the arithmetic addressable, and this is the test that could not be written
/// before.
void main() {
  /// Pumps the strip at a given system font scale and reports anything Flutter threw laying it out.
  Future<Object?> layOutAt(WidgetTester tester, double textScale) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MaterialApp(
            home: Scaffold(
              body: CategoryStrip(
                verticals: StoreVertical.values,
                // The longest label in the product, because the shortest one proves nothing.
                labelOf: (StoreVertical v) => 'Flowers & Gifts',
                onSelected: (_) {},
                gutter: 24,
              ),
            ),
          ),
        ),
      ),
    );
    return tester.takeException();
  }

  testWidgets('the strip is tall enough for a card at the default font size', (
    WidgetTester tester,
  ) async {
    // A RenderFlex overflow surfaces here as a thrown FlutterError. Null means the row laid out
    // cleanly, which is the entire claim.
    expect(await layOutAt(tester, 1.0), isNull);
  });

  testWidgets('and stays tall enough as the reader turns the system font up', (
    WidgetTester tester,
  ) async {
    // The same defect, further along the accessibility slider: a height that ignores the text
    // scaler clips anybody who has enlarged their font rather than growing for them. 1.3 and 1.5
    // are ordinary Android settings, not extremes.
    for (final double scale in <double>[1.15, 1.3, 1.5]) {
      expect(await layOutAt(tester, scale), isNull,
          reason: 'the category row overflowed at text scale $scale');
    }
  });

  testWidgets('the reserved height actually covers what a card occupies', (
    WidgetTester tester,
  ) async {
    // The direct statement of the bug: the box has to be at least as big as the thing inside it,
    // plus the padding the list puts around it. Asserting the relationship rather than a number
    // means the test still means something after somebody edits the card.
    late BuildContext context;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.0)),
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext c) {
              context = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final double card = CategoryStripMetrics.cardHeight(context);
    final double strip = CategoryStripMetrics.stripHeight(context);
    final double padding = CategoryStripMetrics.listPaddingTop +
        CategoryStripMetrics.listPaddingBottom;

    expect(strip, greaterThanOrEqualTo(card + padding));
    // And the old literal is on record as too small, so nobody reintroduces it believing it fits.
    expect(strip, greaterThan(96));
  });
}
