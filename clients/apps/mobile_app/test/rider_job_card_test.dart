import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/rider_job_card.dart';

import 'payment_test.dart' show orderJson;

/// The rider's offer card, on its own.
///
/// The screen around it runs two periodic timers, so it cannot be pumped and settled; the card can.
/// What is worth pinning here is not the styling but the two things a rider acts on: whether they
/// are told to collect money, and whether the button that moves the job on is the one they hit.
///
/// Rewritten for the 2026-08 redesign, which changed both of those in ways the old assertions
/// could not see. The card no longer says "Already paid" — a prepaid job carries the item-count tag
/// in the slot a cash job uses for the amount to collect, so the money line is present exactly when
/// there is money to collect. And the actions are [RiderButton]s rather than Material's
/// [FilledButton]/[TextButton], with Cancel gone from the card entirely: the design moves it onto
/// the detail screen, which is the same intent the old test had — a rider must not cancel a job by
/// brushing a list — enforced one step harder.
void main() {
  DeliveryOrder order({
    String? method,
    String? status,
    List<String> actions = const <String>['DELIVER'],
    String? storeName = 'Rose Cafe',
    String? notes,
  }) {
    final Map<String, dynamic> json = orderJson(method: method, status: status);
    json['availableActions'] = actions;
    json['storeName'] = storeName;
    json['notes'] = notes;
    json['items'] = <dynamic>[
      <String, dynamic>{
        'productId': 'p1',
        'productName': 'Flat white',
        'unitPrice': 12.25,
        'qty': 2,
        'lineTotal': 24.50,
      },
    ];
    return DeliveryOrder.fromJson(json);
  }

  Future<List<OrderAction>> pumpCard(WidgetTester tester, DeliveryOrder o,
      {bool busy = false, Locale? locale}) async {
    final List<OrderAction> taps = <OrderAction>[];
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      theme: DeliveryTheme.light(),
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocaleController.supported,
      home: Scaffold(
        body: SingleChildScrollView(
          child: RiderJobCard(order: o, busy: busy, onAction: taps.add),
        ),
      ),
    ));
    // pump, not pumpAndSettle: a busy card spins a CircularProgressIndicator, and settling on an
    // indefinite animation never returns.
    await tester.pump();
    return taps;
  }

  testWidgets('an unpaid cash order says how much to collect', (WidgetTester tester) async {
    await pumpCard(tester, order(method: 'CASH', status: 'DUE'));

    expect(find.textContaining('24.50'), findsOneWidget);
    expect(find.textContaining('Collect'), findsOneWidget);
  });

  testWidgets('a card order does not send the rider asking for money',
      (WidgetTester tester) async {
    await pumpCard(tester, order(method: 'CARD', status: 'AUTHORIZATION_PENDING'));

    expect(find.textContaining('Collect'), findsNothing);
    // The slot is not left empty either — it carries the load instead, which is the other thing
    // that decides whether a rider takes the job.
    expect(find.text('2 items'), findsOneWidget);
  });

  testWidgets('the shop, the door and the load all read on one card',
      (WidgetTester tester) async {
    // Prepaid, so the tag slot carries the load. On a cash job that slot carries the amount to
    // collect instead — deliberately, and covered above: money at the door outranks a count.
    await pumpCard(
      tester,
      order(
        method: 'CARD',
        status: 'AUTHORIZATION_PENDING',
        notes: 'Second buzzer, blue door',
      ),
    );

    expect(find.text('Rose Cafe'), findsOneWidget);
    expect(find.text('12 Rose Street'), findsOneWidget);
    expect(find.text('2 items'), findsOneWidget);
    expect(find.text('Second buzzer, blue door'), findsOneWidget);
  });

  testWidgets('a job with no shop named still lays out', (WidgetTester tester) async {
    // Butler errands become ordinary orders with no store behind them, and this board shows them.
    await pumpCard(tester, order(storeName: null));

    expect(tester.takeException(), isNull);
    expect(find.text('12 Rose Street'), findsOneWidget);
  });

  testWidgets('the step forward is the only thing on the card that can be tapped',
      (WidgetTester tester) async {
    final List<OrderAction> taps = await pumpCard(
        tester, order(actions: <String>['DELIVER', 'CANCEL']));

    // Cancel is offered by the server on this order and is still not drawn here: one button, and
    // it is the one that moves the job forward. That is how a rider stops cancelling a job by
    // accident on a phone held in one hand.
    expect(find.byType(RiderButton), findsOneWidget);

    await tester.tap(find.byType(RiderButton));
    await tester.pump();
    expect(taps, <OrderAction>[OrderAction.deliver]);
  });

  testWidgets('in Arabic it reads right-to-left and says the same things',
      (WidgetTester tester) async {
    await pumpCard(tester, order(method: 'CASH', status: 'DUE'),
        locale: const Locale('ar'));

    expect(Directionality.of(tester.element(find.byType(RiderJobCard))), TextDirection.rtl);
    // The tag and the route labels are the text this card gained in the redesign, and untranslated
    // ones are how a screen ends up half-Arabic without anyone noticing.
    expect(find.textContaining('حصّل'), findsOneWidget);
    expect(find.textContaining('الاستلام من'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a card mid-action refuses further taps', (WidgetTester tester) async {
    final List<OrderAction> taps = await pumpCard(tester, order(), busy: true);

    await tester.tap(find.byType(RiderButton));
    await tester.pump();
    expect(taps, isEmpty);
  });
}
