import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/platform_share.dart';

/// The phone's own share sheet, which is how a merchant's shop link reaches WhatsApp.
///
/// The Kotlin half cannot be run here, so what is pinned is the contract the Dart half promises to
/// every screen that uses it — above all that it **never throws**. Each caller treats false as "do
/// the other thing" and copies the link instead, so a phone with no chooser, a web build and a test
/// that never registered the channel all end up with the link in the merchant's hands rather than
/// with an unhandled exception in the middle of a tap.
void main() {
  const MethodChannel channel = MethodChannel('com.delivery.mobile_app/share');
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  test('it asks the host to share the text it was given', () async {
    final List<MethodCall> calls = <MethodCall>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      return true;
    });

    expect(await PlatformShare.text('https://www.youdrop.shop/s/falafel-king'), isTrue);
    expect(calls.single.method, 'shareText');
    expect((calls.single.arguments as Map<Object?, Object?>)['text'],
        'https://www.youdrop.shop/s/falafel-king');
  });

  test('a phone with nothing to share to says so rather than throwing', () async {
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async => false);

    expect(await PlatformShare.text('https://www.youdrop.shop/s/falafel-king'), isFalse);
  });

  test('a host that failed outright is a false, not an exception', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      throw PlatformException(code: 'no_activity');
    });

    expect(await PlatformShare.text('https://www.youdrop.shop/s/falafel-king'), isFalse);
  });

  test('with no channel registered at all — every non-Android build — it is a false', () async {
    expect(await PlatformShare.text('https://www.youdrop.shop/s/falafel-king'), isFalse);
  });
}
