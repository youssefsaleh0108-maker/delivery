import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Registering a device for push, on a device where push cannot work.
///
/// [DeviceTokenRegistrar] promises, in its own words, that "every failure is swallowed. Push is an
/// enhancement — a denied permission, a device with no Play Services, or a Firebase project that
/// has not been configured yet must not stop somebody using the app."
///
/// It broke that promise on the one failure most likely to happen, because the failure occurred
/// before the code that swallows it: `FirebaseMessaging.instance` was resolved in the constructor's
/// INITIALISER LIST, which runs ahead of the constructor body and far ahead of the try/catch in
/// register(). `FirebaseMessaging.instance` throws whenever `Firebase.initializeApp()` did not
/// succeed — a build with no google-services.json, a device with no Play Services or an outdated
/// copy of them.
///
/// What that cost is why this test exists rather than a comment. The app builds this class through
/// a `late final`, first touched when a session is adopted, which happens inside the sign-in
/// screen's own `try` — whose catch-all renders "We could not reach the server. Check your
/// connection and try again." So on any such device a COMPLETELY SUCCESSFUL sign-in — token
/// issued, session valid, network perfectly fine — told the person their connection was broken,
/// and retrying could never clear it.
///
/// This test process never calls `Firebase.initializeApp()`, so it reproduces exactly that device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DeviceTokenRegistrar build() => DeviceTokenRegistrar(
        dio: Dio(BaseOptions(baseUrl: 'http://localhost:1')),
        issuer: 'http://localhost:1/realms/delivery-platform',
      );

  test('constructing it does not need Firebase to have come up', () {
    // The original failure was HERE, before register() existed to catch anything: the initialiser
    // list resolved FirebaseMessaging.instance, and constructing the object threw.
    expect(build, returnsNormally);
  });

  test('register() swallows a Firebase that never initialised', () async {
    // The promise in the class doc, stated as an assertion. Completing — rather than throwing — is
    // the whole behaviour: whoever called this is midway through adopting a valid session, and an
    // exception here is attributed to them.
    await expectLater(build().register(), completes);
  });

  test('and it stays swallowed on a second call', () async {
    // register() is documented as "safe to call on every sign-in", and a lazily-resolved handle is
    // exactly the shape that can throw on the first call and behave differently on the next. It
    // must be uneventful every time.
    final DeviceTokenRegistrar registrar = build();
    await expectLater(registrar.register(), completes);
    await expectLater(registrar.register(), completes);
  });
}
