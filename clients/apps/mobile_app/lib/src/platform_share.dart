import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android's own share sheet, for the screens that have something to hand to somebody else.
///
/// **Why a channel of four lines rather than a package.** `share_plus` is the usual answer and it
/// is a plugin, a platform interface and five federated implementations to reach one
/// `ACTION_SEND` — for an app that ships to Android and to the web and needs it on one of them. The
/// Kotlin side of this is in `MainActivity`, beside the notification channels, where anybody
/// looking for what this app does natively will find it.
///
/// **What it is for.** A merchant showing a customer their shop's page: the sheet is what puts
/// WhatsApp one tap away, which is where a Lebanese shop's link actually goes. Every screen that
/// uses it passes it in as a callback and falls back to the clipboard, so the same widget builds
/// for the web portal unchanged — see `ShopShareCard.onShare`.
abstract final class PlatformShare {
  static const MethodChannel _channel = MethodChannel('com.delivery.mobile_app/share');

  /// Whether this build can open a share sheet at all.
  ///
  /// Android only. On the web there is no sheet — the Web Share API exists but is absent on the
  /// desktop browsers the portal is used in, and a button that works on a phone browser and
  /// silently does nothing on a laptop is worse than a button that always copies.
  static bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Opens the system chooser on [text], returning whether a sheet was opened.
  ///
  /// False means there was nothing to open it with, not that the person changed their mind: the
  /// chooser reports neither what was picked nor whether anything was. Callers treat false as "do
  /// the other thing" — copy to the clipboard and say so — so a phone with no sharing app still
  /// leaves the merchant holding the link.
  static Future<bool> text(String text) async {
    if (!available) return false;
    try {
      return await _channel.invokeMethod<bool>('shareText', <String, Object?>{
            'text': text,
          }) ??
          false;
    } on PlatformException catch (_) {
      // An activity that has gone away, or an OEM build with no chooser. The caller copies.
      return false;
    } on MissingPluginException catch (_) {
      // A host that does not register the channel — every non-Android build, and any test that
      // pumps these screens without one.
      return false;
    }
  }
}
