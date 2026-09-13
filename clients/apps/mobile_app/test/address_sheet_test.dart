import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/address_sheet.dart';
import 'package:mobile_app/src/delivery_address.dart';

/// Saving an address from the sheet, and who receives gifts there.
///
/// A gift checkout remembers the recipient's name and phone with the address they live at. Saved
/// addresses are matched by their line, so the sheet saving an edit replaces the saved one — and it
/// used to rebuild it without the recipient, forgetting them over a new door note.
void main() {
  const MethodChannel storageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (MethodCall call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
  });

  const String momsDoor = 'Mar Mikhael, Facing Municipality, Beirut';

  Future<DeliveryAddressStore> momsAddress() async {
    final DeliveryAddressStore store = DeliveryAddressStore(ownerId: 'test-user');
    await store.select(const DeliveryAddress(
      line: momsDoor,
      label: 'Mom',
      notes: 'Second floor',
      recipientName: 'Mona (Mom)',
      recipientPhone: '+96171234567',
    ));
    return store;
  }

  Future<void> openSheet(WidgetTester tester, DeliveryAddressStore store) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocaleController.supported,
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showAddressSheet(context, store),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('saving a new door note keeps who receives gifts there', (WidgetTester tester) async {
    final DeliveryAddressStore store = await momsAddress();
    await openSheet(tester, store);

    await tester.enterText(find.widgetWithText(TextFormField, 'Second floor'), 'Third floor');
    await tester.tap(find.text(en.deliverHere));
    await tester.pumpAndSettle();

    expect(store.selected?.notes, 'Third floor');
    expect(store.selected?.recipientName, 'Mona (Mom)');
    expect(store.selected?.recipientPhone, '+96171234567');
    expect(store.recents, hasLength(1));
    expect(store.recents.single.recipientPhone, '+96171234567');
  });

  testWidgets('a different line is a different door, and starts with no recipient',
      (WidgetTester tester) async {
    final DeliveryAddressStore store = await momsAddress();
    await openSheet(tester, store);

    await tester.enterText(find.widgetWithText(TextFormField, momsDoor), 'Hamra, Bliss Street, Beirut');
    await tester.tap(find.text(en.deliverHere));
    await tester.pumpAndSettle();

    expect(store.selected?.line, 'Hamra, Bliss Street, Beirut');
    expect(store.selected?.recipientName, isNull);
    expect(store.selected?.recipientPhone, isNull);
    // Mom's own address still knows her.
    expect(store.recents.firstWhere((DeliveryAddress a) => a.line == momsDoor).recipientName,
        'Mona (Mom)');
  });
}
