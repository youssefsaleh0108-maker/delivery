import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The basket bar's arrival, and the difference between subscribing and re-reading.
///
/// <p>On the shop page the bar is a `bottomNavigationBar`, and it used to be written as
/// `cart.isEmpty ? null : AnimatedBuilder(animation: cart, …)`. That reads as "listen to the cart
/// and draw the bar once there is something in it", and it is not what it does: the ternary runs
/// during `build()`, and the only subscriber was the builder it guards. When the first item went
/// in, the cart notified — the body, which had its own `AnimatedBuilder`, redrew and the product
/// row's quantity badge appeared — while the Scaffold's `bottomNavigationBar` argument was never
/// re-evaluated and stayed `null`.
///
/// <p>So a customer added their first item and no basket bar appeared. The item WAS in the cart.
/// The shop page simply offered no way forward from the screen they were on, until something
/// unrelated happened to rebuild the page and it silently turned up. That is the shape of bug a
/// screen tour cannot find and a purchase can: it was caught by an integration test walking an
/// order from a basket to a rider's hand, at the step after "added to the basket".
///
/// <p>These two cases are the same widget wired the two ways, so the test is about the wiring
/// rather than about the shop page. The first fails against the old arrangement; the second is
/// what makes the first mean something.
void main() {
  /// The broken shape: the emptiness test outside the subscription.
  Widget guardedOutside(ValueNotifier<int> cart) => MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: cart,
            builder: (BuildContext context, _) => Text('items ${cart.value}'),
          ),
          bottomNavigationBar: cart.value == 0
              ? null
              : AnimatedBuilder(
                  animation: cart,
                  builder: (BuildContext context, _) => const Text('View basket'),
                ),
        ),
      );

  /// The fixed shape: subscribe first, decide inside.
  Widget guardedInside(ValueNotifier<int> cart) => MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: cart,
            builder: (BuildContext context, _) => Text('items ${cart.value}'),
          ),
          bottomNavigationBar: AnimatedBuilder(
            animation: cart,
            builder: (BuildContext context, _) =>
                cart.value == 0 ? const SizedBox.shrink() : const Text('View basket'),
          ),
        ),
      );

  testWidgets('a bar guarded outside its own listener never arrives', (WidgetTester tester) async {
    final ValueNotifier<int> cart = ValueNotifier<int>(0);
    addTearDown(cart.dispose);
    await tester.pumpWidget(guardedOutside(cart));
    expect(find.text('View basket'), findsNothing);

    // The first item. Nothing else touches the page — exactly as when a product screen pops and
    // hands its result to `cart.addConfigured`.
    cart.value = 1;
    await tester.pump();

    // The body heard about it...
    expect(find.text('items 1'), findsOneWidget);
    // ...and the bar did not. This is the bug, stated as the thing it does.
    expect(find.text('View basket'), findsNothing,
        reason: 'If this now finds the bar, the pattern is no longer reproducing the defect and '
            'the case below no longer proves anything — check both together.');
  });

  testWidgets('and one guarded inside it arrives with the item', (WidgetTester tester) async {
    final ValueNotifier<int> cart = ValueNotifier<int>(0);
    addTearDown(cart.dispose);
    await tester.pumpWidget(guardedInside(cart));
    expect(find.text('View basket'), findsNothing);

    cart.value = 1;
    await tester.pump();

    expect(find.text('items 1'), findsOneWidget);
    expect(find.text('View basket'), findsOneWidget,
        reason: 'The basket bar must appear on the same frame as the item that caused it. This is '
            'the customer\'s only way from a shop page to checkout.');
  });

  testWidgets('and it leaves again when the last item does', (WidgetTester tester) async {
    final ValueNotifier<int> cart = ValueNotifier<int>(2);
    addTearDown(cart.dispose);
    await tester.pumpWidget(guardedInside(cart));
    expect(find.text('View basket'), findsOneWidget);

    // The mirror image, and the reason the fix returns SizedBox.shrink() rather than keeping a
    // bar that says nothing: an empty basket must not offer a way to check one out.
    cart.value = 0;
    await tester.pump();
    expect(find.text('View basket'), findsNothing);
  });
}
