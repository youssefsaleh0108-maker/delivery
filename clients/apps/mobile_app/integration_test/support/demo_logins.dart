/// The demo logins' passwords, supplied when the suite is run — never compiled in.
///
/// <p><strong>Why they are not literals.</strong> They were, in these scenarios and in the realm
/// file beside them, and the repository was public: anybody could sign in to the dev environment
/// as any demo account, the back-office one included. Since 2026-09 each environment's values live
/// only in its `demo-logins` Secret on the box (deploy/k3s/README.md, "The demo logins"), and a
/// local compose stack's in infra/keycloak/realm-delivery-platform.json.
///
/// <p>Pass them the way the base URLs are passed — as dart-defines, one each, or all at once from a
/// file you write for the run and never commit:
///
/// ```
/// flutter test integration_test/order_lifecycle_test.dart \
///   --dart-define=API_BASE_URL=https://api-dev.youdrop.shop \
///   --dart-define=KEYCLOAK_ISSUER=https://iam-dev.youdrop.shop/realms/delivery-platform \
///   --dart-define-from-file=demo-logins.json   # {"DEMO_CUSTOMER_PASSWORD": "…", …}
/// ```
///
/// <p>A missing one fails the scenario that needs it, naming the define, before anything is typed —
/// rather than as a "wrong passcode" three screens later.
class DemoLogins {
  DemoLogins._();

  // One const read per define: String.fromEnvironment only takes a literal name.
  static const String _customer = String.fromEnvironment('DEMO_CUSTOMER_PASSWORD');
  static const String _rider = String.fromEnvironment('DEMO_RIDER_PASSWORD');
  static const String _merchant = String.fromEnvironment('DEMO_MERCHANT_PASSWORD');
  static const String _backoffice = String.fromEnvironment('DEMO_BACKOFFICE_PASSWORD');
  static const String _carrier = String.fromEnvironment('DEMO_CARRIER_PASSWORD');

  /// The password of the demo login [user]: customer, rider, merchant, backoffice or carrier.
  ///
  /// The four that sign in on the phone have six-digit passcodes, because the sign-in screen accepts
  /// nothing else; backoffice signs in through the portal and has a long password.
  static String passwordOf(String user) {
    final String value = switch (user) {
      'customer' => _customer,
      'rider' => _rider,
      'merchant' => _merchant,
      'backoffice' => _backoffice,
      'carrier' => _carrier,
      _ => throw ArgumentError.value(user, 'user', 'is not a demo login'),
    };
    if (value.isEmpty) {
      throw StateError('No password for the demo login "$user": pass '
          '--dart-define=DEMO_${user.toUpperCase()}_PASSWORD=<its value in the environment\'s '
          'demo-logins Secret>. See deploy/k3s/README.md, "The demo logins".');
    }
    return value;
  }
}
