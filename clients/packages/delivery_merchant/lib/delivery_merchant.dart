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
// The shop's own daily series as a page. Exported as well as reachable from settings, so a host
// with room for it in a rail can mount it directly instead of hiding it one tap into a menu.
export 'src/merchant_analytics_screen.dart';
// The bank record behind the settings row. Exported like the analytics page and for the same
// reason: a host with room for it can mount it directly.
export 'src/merchant_payout_screen.dart';
export 'src/merchant_settings_screen.dart';
// The order detail screen and, with it, the small parts the three merchant frames share —
// `MerchantMetricCard`, `MerchantTileGrid`, `MerchantStatusTag`, `merchantMaxContentWidth` and the
// rest. Exported because they are the package's own vocabulary: a host mounting these screens in
// its own shell has to be able to name them, and so do the tests, without reaching into `src/`.
export 'src/order_detail_screen.dart';
export 'src/orders_screen.dart';
export 'src/product_form_screen.dart';
export 'src/product_list_screen.dart';
export 'src/store_screen.dart';
// The map pin's own parts — the preview that sits in the shop-config frame's map slot and the
// picker behind it. Exported for the same reason the metric cards are: a host or a test has to be
// able to name them without reaching into another package's `src/`.
export 'src/store_pin_map.dart';
// Exported although the WhatsApp screen is the only thing that mounts it today: the portal's tests
// drive the draft panel directly, and reaching into another package's `src/` to do that is the lint
// this export exists to avoid.
export 'src/whatsapp_draft_panel.dart';
export 'src/whatsapp_screen.dart';
export 'src/zones_screen.dart';
