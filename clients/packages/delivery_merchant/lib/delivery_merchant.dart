/// The merchant area, as widgets rather than as an app.
///
/// These screens were the merchant section of `delivery_portal` until a merchant could apply and be
/// signed in from the phone. At that point the phone became the only device some shops have, and a
/// second copy of, say, the zone pricing page would have meant the next pricing change landed in
/// one of them. So the pages live here and both hosts mount them: the portal in its navigation
/// rail, the Android app in its own navigation.
///
/// Nothing here builds a Scaffold with a rail or a bottom bar, and nothing here assumes a mouse or
/// a wide window — that framing belongs to whichever app is hosting the screen.
library;

export 'src/dashboard_screen.dart';
export 'src/delivery_screen.dart';
export 'src/orders_screen.dart';
export 'src/product_form_screen.dart';
export 'src/product_list_screen.dart';
export 'src/store_screen.dart';
// Exported although the WhatsApp screen is the only thing that mounts it today: the portal's tests
// drive the draft panel directly, and reaching into another package's `src/` to do that is the lint
// this export exists to avoid.
export 'src/whatsapp_draft_panel.dart';
export 'src/whatsapp_screen.dart';
export 'src/zones_screen.dart';
