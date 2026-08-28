import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/carrier/settings_screen.dart';
import 'package:delivery_portal/src/shell/console_controls.dart';
import 'package:delivery_portal/src/shell/shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Company Preferences — Figma `carrier-settings` (3:3878).
///
/// The most speculative frame in the carrier set, and now nearly all of it has a backend: the
/// logo, the dispatch regions, the operating hours and the partner API keys. These tests hold the
/// line that matters on a settings page — a control either does what it looks like it does, or
/// says plainly that it cannot, and the difference is never left for the reader to guess.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.responses, {this.failing = const <String>{}});

  /// `METHOD suffix`, `METHOD =suffix` (the path must end there), or a bare suffix. Longest match
  /// wins, so a specific route beats the collection it hangs off.
  final Map<String, Object> responses;
  final Set<String> failing;

  final List<String> calls = <String>[];
  final List<Object?> bodies = <Object?>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    bodies.add(options.data);

    for (final String path in failing) {
      if (options.path.contains(path)) {
        return ResponseBody.fromString('{"message":"no"}', 404);
      }
    }

    final List<String> matches = responses.keys.where((String key) {
      String suffix = key;
      final int space = key.indexOf(' ');
      if (space >= 0) {
        if (options.method != key.substring(0, space)) return false;
        suffix = key.substring(space + 1);
      }
      if (suffix.startsWith('=')) return options.path.endsWith(suffix.substring(1));
      return options.path.contains(suffix);
    }).toList()
      ..sort((String a, String b) => b.length.compareTo(a.length));

    if (matches.isEmpty) return ResponseBody.fromString('{}', 404);

    final Object body = responses[matches.first]!;
    if (body is int) return ResponseBody.fromString('{}', body);
    return ResponseBody.fromString(jsonEncode(body), 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _company({
  String? accountRef,
  String payoutState = 'NONE',
  String? contactName = 'Cara Haddad',
}) =>
    <String, dynamic>{
      'id': 'p1',
      'slug': 'swift',
      'name': 'Swift Couriers Services Co.',
      'kind': 'EXTERNAL',
      'status': 'ACTIVE',
      'canTakeWork': true,
      'accountRef': accountRef,
      'contactName': contactName,
      'contactPhone': '+96170000000',
      'payoutState': payoutState,
    };

Map<String, dynamic> _payout({String iban = 'LB62099400000001001901229114'}) =>
    <String, dynamic>{
      'accountHolder': 'Swift Couriers Services Co.',
      'iban': iban,
      'verificationState': 'CHECKSUM_ONLY',
    };

Map<String, dynamic> _profile({
  String? logoUrl,
  List<String> regions = const <String>['Beirut'],
  Map<String, dynamic> hours = const <String, dynamic>{
    'MONDAY': <String, dynamic>{'open': '08:00', 'close': '22:00'},
  },
}) =>
    <String, dynamic>{
      'providerId': 'p1',
      'logoUrl': logoUrl,
      'dispatchRegions': regions,
      'operatingHours': hours,
      'updatedBy': 'kc-boss',
      'updatedAt': '2026-08-10T09:00:00Z',
    };

Map<String, dynamic> _key({
  String id = 'k1',
  String prefix = 'ydk_AAAABBBB',
  String? label = 'dispatch box',
  String? lastUsedAt,
  bool revoked = false,
}) =>
    <String, dynamic>{
      'id': id,
      'keyPrefix': prefix,
      'label': label,
      'createdAt': '2026-08-01T09:00:00Z',
      'lastUsedAt': lastUsedAt,
      'revoked': revoked,
      'revokedAt': revoked ? '2026-08-12T09:00:00Z' : null,
    };

late _StubAdapter _adapter;

typedef CarrierApis = ({
  DeliveryProviderApi provider,
  DocumentsApi documents,
  ProviderProfileApi profiles,
  PartnerApiKeysApi keys,
});

CarrierApis _api({
  Map<String, dynamic>? company,
  Map<String, dynamic>? payout,
  Map<String, dynamic>? profile,
  List<Map<String, dynamic>>? keys,
  Set<String> failing = const <String>{},
}) {
  final Map<String, Object> routes = <String, Object>{
    '/my-company': company ?? _company(),
    'GET =/profile': profile ?? _profile(),
    'PUT =/profile': profile ?? _profile(),
    '/profile/logo/presign': <String, dynamic>{
      'fileId': 'f1',
      'uploadUrl': 'https://storage.example/upload/f1',
      'objectKey': 'logos/f1.png',
      'contentType': 'image/png',
      'expiresAt': '2026-08-16T10:00:00Z',
      'maxSizeBytes': 5 * 1024 * 1024,
    },
    '/profile/logo/confirm': _profile(logoUrl: 'https://cdn.example/logo.png'),
    'GET =/api/partner-keys': keys ?? <Map<String, dynamic>>[_key()],
    'POST =/api/partner-keys': <String, dynamic>{
      'id': 'k2',
      'secret': 'ydk_0123456789012345678901234567890123456789012',
      'keyPrefix': 'ydk_01234567',
      'label': 'new box',
      'createdAt': '2026-08-16T09:00:00Z',
    },
    'DELETE /api/partner-keys/': 204,
  };

  _adapter = _StubAdapter(routes, failing: failing);
  // The payout route is stateful — a PUT stores what was sent and answers it back, like the
  // server does — so it is layered over the map rather than sitting in it.
  final _StubAdapter adapter = _PayoutAwareAdapter(_adapter, payout);
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;
  return (
    provider: DeliveryProviderApi(dio),
    documents: DocumentsApi(dio),
    profiles: ProviderProfileApi(dio),
    keys: PartnerApiKeysApi(dio),
  );
}

/// The payout endpoints, which are a tiny store rather than a fixed answer.
class _PayoutAwareAdapter extends _StubAdapter {
  _PayoutAwareAdapter(this.inner, this.payout) : super(inner.responses, failing: inner.failing);

  final _StubAdapter inner;
  Object? payout;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    if (options.path.contains('/applications/mine/payout')) {
      inner.calls.add('${options.method} ${options.path}');
      inner.bodies.add(options.data);

      if (options.method == 'PUT') {
        final Map<String, dynamic> sent = options.data as Map<String, dynamic>;
        payout = <String, dynamic>{
          'accountHolder': sent['accountHolder'],
          'iban': (sent['iban'] as String).replaceAll(' ', '').toUpperCase(),
          'verificationState': 'CHECKSUM_ONLY',
        };
      }
      if (payout == null) return ResponseBody.fromString('{}', 404);
      return ResponseBody.fromString(jsonEncode(payout), 200, headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType]
      });
    }
    return inner.fetch(options, requestStream, cancelFuture);
  }
}

LocaleController _locale() => LocaleController(
      read: () async => null,
      write: (String _) async {},
    );

Widget _wrap(Widget child) => MaterialApp(
      locale: const Locale('en'),
      theme: DeliveryTheme.light(),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    );

/// What the injected uploader was asked to PUT, so a test can assert the middle step of the
/// three-step upload without a network.
final List<({String url, int bytes, String contentType})> _puts =
    <({String url, int bytes, String contentType})>[];

Future<void> pump(
  WidgetTester tester,
  CarrierApis apis, {
  LocaleController? locale,
  double width = 1180,
  /// The portal shell still builds this screen with two APIs; false mounts it that way.
  bool wired = true,
  PickedLogo? logo,
}) async {
  tester.view.physicalSize = Size(width, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  _puts.clear();

  await tester.pumpWidget(_wrap(
    CarrierSettingsScreen(
      api: apis.provider,
      locale: locale ?? _locale(),
      documentsApi: apis.documents,
      profileApi: wired ? apis.profiles : null,
      keysApi: wired ? apis.keys : null,
      pickLogo: (BuildContext context) async => logo,
      putBytes: (String url, Uint8List bytes, String contentType) async {
        _puts.add((url: url, bytes: bytes.length, contentType: contentType));
      },
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('draws the design four cards', (WidgetTester tester) async {
    await pump(tester, _api());

    expect(find.text('Company Preferences'), findsOneWidget);
    expect(find.text('Carrier Identity'), findsOneWidget);
    expect(find.text('Payout Details'), findsOneWidget);
    expect(find.text('Configuration Preferences'), findsOneWidget);
    expect(find.text('API Integration Endpoint'), findsOneWidget);
  });

  testWidgets('shows the company record it really has', (WidgetTester tester) async {
    await pump(tester, _api());

    expect(find.text('Registered Legal Name'), findsOneWidget);
    expect(find.text('Swift Couriers Services Co.'), findsOneWidget);
    expect(find.text('Cara Haddad'), findsOneWidget);
    expect(find.text('+96170000000'), findsOneWidget);
  });

  testWidgets('nothing on the page is chipped as coming later any more',
      (WidgetTester tester) async {
    await pump(tester, _api());

    expect(find.byType(ConsoleComingSoonChip), findsNothing);
  });

  testWidgets('a bank step never done reads "Not set yet", not an invented number',
      (WidgetTester tester) async {
    // The payout endpoint answers 404. A masked string that looked like a real IBAN would be the
    // app inventing one.
    await pump(tester, _api());

    expect(find.text('Not set yet'), findsNWidgets(2));
    expect(find.widgetWithText(ConsoleTintButton, 'Add bank account'), findsOneWidget);
    expect(find.textContaining('•'), findsNothing);
  });

  testWidgets('a stored IBAN is shown masked, never in full', (WidgetTester tester) async {
    await pump(tester, _api(payout: _payout()));

    expect(find.text('Swift Couriers Services Co.'), findsWidgets);
    // First four, last four, dots between — recognisable, not copyable.
    expect(find.text('LB62 •••••••••••••••••••• 9114'), findsOneWidget);
    expect(find.textContaining('LB62099400000001001901229114'), findsNothing);
    // The bank check's own verdict rides along.
    expect(find.text('Format checked'), findsOneWidget);
    expect(find.widgetWithText(ConsoleTintButton, 'Update bank account'), findsOneWidget);
  });

  testWidgets('the bank the account sits behind is a stated absence, not a blank box',
      (WidgetTester tester) async {
    // The one field on this frame with nothing behind it anywhere on the platform.
    await pump(tester, _api());

    expect(find.text('Not recorded — the platform stores the account, not the bank'),
        findsOneWidget);
  });

  testWidgets('the dialog PUTs holder and IBAN together and re-reads the record',
      (WidgetTester tester) async {
    await pump(tester, _api());

    await tester.tap(find.widgetWithText(ConsoleTintButton, 'Add bank account'));
    await tester.pumpAndSettle();

    // Dead until both fields carry something — the pair replaces the record together.
    final Finder save = find.widgetWithText(ConsolePrimaryButton, 'Save bank account');
    expect(tester.widget<ConsolePrimaryButton>(save).onPressed, isNull);

    final Finder fields =
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), 'Swift Couriers Services Co.');
    await tester.enterText(fields.at(1), 'LB62 0994 0000 0001 0019 0122 9114');
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(
      _adapter.calls.any(
          (String c) => c.startsWith('PUT') && c.contains('/applications/mine/payout')),
      isTrue,
    );
    // Sent as typed — the server normalises, not the client.
    expect(
      _adapter.bodies.any((Object? b) =>
          b is Map && b['iban'] == 'LB62 0994 0000 0001 0019 0122 9114'),
      isTrue,
    );
    // The card now shows the stored account, masked.
    expect(find.text('LB62 •••••••••••••••••••• 9114'), findsOneWidget);
  });

  testWidgets('an unverified payout account is visible on the card', (WidgetTester tester) async {
    await pump(tester, _api(company: _company(payoutState: 'UNCONFIRMED')));

    expect(find.widgetWithText(ConsoleStatusPill, 'Unconfirmed'), findsOneWidget);
  });

  testWidgets('the language toggle is live', (WidgetTester tester) async {
    final LocaleController locale = _locale();
    await pump(tester, _api(), locale: locale);

    expect(locale.isArabic, isFalse);
    await tester.tap(find.text('العربية'));
    await tester.pumpAndSettle();
    expect(locale.isArabic, isTrue);
  });

  // ------------------------------------------------------------------- logo

  testWidgets('the logo goes up in the three steps the contract describes',
      (WidgetTester tester) async {
    await pump(
      tester,
      _api(),
      logo: PickedLogo(bytes: Uint8List.fromList(<int>[1, 2, 3, 4]), contentType: 'image/png'),
    );

    await tester.tap(find.widgetWithText(ConsoleTintButton, 'Upload Logo'));
    await tester.pumpAndSettle();

    expect(_adapter.calls.any((String c) => c.contains('/profile/logo/presign')), isTrue);
    // The bytes go straight to storage, with exactly the content type the URL was signed for.
    expect(_puts.single.url, 'https://storage.example/upload/f1');
    expect(_puts.single.contentType, 'image/png');
    expect(_adapter.calls.any((String c) => c.contains('/profile/logo/confirm')), isTrue);

    // And the card now offers to replace what it has rather than to upload a first one.
    expect(find.widgetWithText(ConsoleTintButton, 'Replace Logo'), findsOneWidget);
  });

  testWidgets('a file over the service limit never leaves the browser',
      (WidgetTester tester) async {
    await pump(
      tester,
      _api(),
      logo: PickedLogo(
        bytes: Uint8List(6 * 1024 * 1024),
        contentType: 'image/png',
      ),
    );

    await tester.tap(find.widgetWithText(ConsoleTintButton, 'Upload Logo'));
    await tester.pumpAndSettle();

    expect(_puts, isEmpty);
    expect(_adapter.calls.any((String c) => c.contains('/profile/logo/confirm')), isFalse);
    expect(find.textContaining('larger than the 5MB limit'), findsOneWidget);
  });

  // -------------------------------------------------------- regions and hours

  testWidgets('the regions and hours editors save as one form', (WidgetTester tester) async {
    await pump(tester, _api());

    // What the company already had.
    expect(find.text('Beirut'), findsOneWidget);
    expect(find.text('Monday'), findsOneWidget);

    // Nothing to save until something changes.
    expect(
      tester
          .widget<ConsolePrimaryButton>(
              find.widgetWithText(ConsolePrimaryButton, 'Save Settings Configuration'))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byKey(const ValueKey<String>('region-field')), 'Jounieh');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ConsoleButton, 'Add region'));
    await tester.pumpAndSettle();
    expect(find.text('Jounieh'), findsOneWidget);

    await tester.tap(find.widgetWithText(ConsolePrimaryButton, 'Save Settings Configuration'));
    await tester.pumpAndSettle();

    final Object? sent = _adapter.bodies.lastWhere(
        (Object? b) => b is Map && b.containsKey('dispatchRegions'),
        orElse: () => null);
    expect(sent, isNotNull);
    final Map<String, dynamic> body = sent! as Map<String, dynamic>;
    expect(body['dispatchRegions'], <String>['Beirut', 'Jounieh']);
    // PUT semantics: the whole form goes, and a day nobody ticked is simply absent — which is how
    // this contract spells "closed".
    expect((body['operatingHours'] as Map<String, dynamic>).keys, <String>['MONDAY']);
    expect((body['operatingHours'] as Map<String, dynamic>)['MONDAY'],
        <String, dynamic>{'open': '08:00', 'close': '22:00'});
  });

  testWidgets('a removed region is really removed from what is sent',
      (WidgetTester tester) async {
    await pump(tester, _api());

    await tester.tap(find.byTooltip('Remove Beirut'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ConsolePrimaryButton, 'Save Settings Configuration'));
    await tester.pumpAndSettle();

    final Map<String, dynamic> body = _adapter.bodies.lastWhere(
        (Object? b) => b is Map && b.containsKey('dispatchRegions'))! as Map<String, dynamic>;
    expect(body['dispatchRegions'], isEmpty);
  });

  testWidgets('closing before opening is refused here, before any request goes out',
      (WidgetTester tester) async {
    await pump(tester, _api());

    await tester.enterText(find.byKey(const ValueKey<String>('hours-MONDAY-to')), '07:00');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ConsolePrimaryButton, 'Save Settings Configuration'));
    await tester.pumpAndSettle();

    expect(find.text('Monday: opening has to be before closing.'), findsOneWidget);
    expect(_adapter.calls.any((String c) => c.startsWith('PUT') && c.contains('/profile')),
        isFalse);
  });

  testWidgets('a time that is not HH:mm is refused the same way', (WidgetTester tester) async {
    await pump(tester, _api());

    await tester.enterText(find.byKey(const ValueKey<String>('hours-MONDAY-from')), '9am');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ConsolePrimaryButton, 'Save Settings Configuration'));
    await tester.pumpAndSettle();

    expect(find.textContaining('24-hour HH:mm'), findsWidgets);
    expect(_adapter.calls.any((String c) => c.startsWith('PUT') && c.contains('/profile')),
        isFalse);
  });

  testWidgets('ticking a closed day opens it with times to correct', (WidgetTester tester) async {
    await pump(tester, _api());

    expect(find.text('Closed'), findsNWidgets(6));
    await tester.tap(find.byKey(const ValueKey<String>('hours-TUESDAY-open?')));
    await tester.pumpAndSettle();

    expect(find.text('Closed'), findsNWidgets(5));
    await tester.tap(find.widgetWithText(ConsolePrimaryButton, 'Save Settings Configuration'));
    await tester.pumpAndSettle();

    final Map<String, dynamic> body = _adapter.bodies.lastWhere(
        (Object? b) => b is Map && b.containsKey('operatingHours'))! as Map<String, dynamic>;
    expect((body['operatingHours'] as Map<String, dynamic>).keys.toList(),
        <String>['MONDAY', 'TUESDAY']);
  });

  // --------------------------------------------------------------- api keys

  testWidgets('the key listing shows the prefix and its provenance, never a secret',
      (WidgetTester tester) async {
    await pump(tester, _api());

    expect(find.text('ydk_AAAABBBB…'), findsOneWidget);
    expect(find.text('ydk_AAAABBBB · dispatch box'), findsOneWidget);
    expect(find.textContaining('never used'), findsOneWidget);
    expect(find.text('No API key has been issued'), findsNothing);
  });

  testWidgets('a company with no keys says so rather than showing a masked shape',
      (WidgetTester tester) async {
    await pump(tester, _api(keys: const <Map<String, dynamic>>[]));

    expect(find.text('No API key has been issued'), findsOneWidget);
  });

  testWidgets('creating a key shows the secret once, with the warning and a copy',
      (WidgetTester tester) async {
    await pump(tester, _api());

    await tester.tap(find.widgetWithText(ConsoleTintButton, 'Create key'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'new box');
    await tester.tap(find.widgetWithText(ConsolePrimaryButton, 'Create key'));
    await tester.pumpAndSettle();

    expect(find.text('ydk_0123456789012345678901234567890123456789012'), findsOneWidget);
    expect(find.textContaining('only time'), findsOneWidget);
    expect(find.widgetWithText(ConsoleButton, 'Copy the key'), findsOneWidget);

    await tester.tap(find.widgetWithText(ConsolePrimaryButton, 'I have copied it'));
    await tester.pumpAndSettle();

    // And it is gone for good: the listing that replaces it carries prefixes only.
    expect(find.text('ydk_0123456789012345678901234567890123456789012'), findsNothing);
    expect(
      _adapter.calls
          .any((String c) => c.startsWith('POST') && c.endsWith('/api/partner-keys')),
      isTrue,
    );
  });

  testWidgets('revoking asks first, then revokes', (WidgetTester tester) async {
    await pump(tester, _api());

    await tester.tap(find.byTooltip('Revoke this key'));
    await tester.pumpAndSettle();
    expect(find.textContaining('stops working the moment it is revoked'), findsOneWidget);

    await tester.tap(find.widgetWithText(ConsoleSoftButton, 'Revoke key'));
    await tester.pumpAndSettle();

    expect(
      _adapter.calls.any((String c) => c.startsWith('DELETE') && c.contains('/api/partner-keys/k1')),
      isTrue,
    );
  });

  testWidgets('a revoked key stays in the listing, flagged and unrevokable',
      (WidgetTester tester) async {
    await pump(tester, _api(keys: <Map<String, dynamic>>[
      _key(id: 'k9', prefix: 'ydk_CCCCDDDD', label: null, revoked: true),
    ]));

    expect(find.text('ydk_CCCCDDDD'), findsOneWidget);
    expect(find.widgetWithText(ConsoleSmallBadge, 'Revoked'), findsOneWidget);
    expect(find.byTooltip('Revoke this key'), findsNothing);
    // The header field is about a key that works, and none does.
    expect(find.text('No API key has been issued'), findsOneWidget);
  });

  // ----------------------------------------------------------------- shell

  testWidgets('the header search narrows the page to the cards that match',
      (WidgetTester tester) async {
    await pump(tester, _api());

    await tester.enterText(find.byType(TextField).first, 'region');
    await tester.pumpAndSettle();

    expect(find.text('Configuration Preferences'), findsOneWidget);
    expect(find.text('Payout Details'), findsNothing);
  });

  testWidgets('without the new clients the controls say so rather than pretending',
      (WidgetTester tester) async {
    await pump(tester, _api(), wired: false);

    expect(
      tester
          .widget<ConsoleTintButton>(find.widgetWithText(ConsoleTintButton, 'Upload Logo'))
          .onPressed,
      isNull,
    );
    expect(find.text('Logo upload is not wired up in this build'), findsOneWidget);
    expect(find.text('Operating hours are not wired up in this build.'), findsOneWidget);
    expect(find.text('Partner API keys are not wired up in this build.'), findsOneWidget);
    expect(
      tester
          .widget<ConsolePrimaryButton>(
              find.widgetWithText(ConsolePrimaryButton, 'Save Settings Configuration'))
          .onPressed,
      isNull,
    );
  });

  // Two columns at 1180 and 1020, one below 980. An overflow fails the test.
  for (final double width in <double>[1180, 1020, 764]) {
    testWidgets('lays out at a ${width.toInt()}px content column', (WidgetTester tester) async {
      await pump(tester, _api(), width: width);
      expect(tester.takeException(), isNull);
    });
  }
}
