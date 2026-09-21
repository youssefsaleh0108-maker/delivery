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
export 'src/demand_radar_screen.dart';
export 'src/delivery_screen.dart';
// The merchant suite: the register, the shelves and the people who work them. Each of these is
// mounted by both hosts like the screens above, and the POS trio is exported together because a
// sale walks terminal -> checkout -> receipt and a host has to be able to name all three.
export 'src/inventory_screen.dart';
export 'src/merchant_categories_screen.dart';
export 'src/pos/pos_checkout_screen.dart';
export 'src/pos/pos_receipt_screen.dart';
export 'src/pos/pos_terminal_screen.dart';
export 'src/staff_screen.dart';
export 'src/stock_alerts_screen.dart';
export 'src/stock_count_screen.dart';
// Merchant Blitz: the shelf-photo scan and the review behind it. The review is exported with the
// scan because the scan pushes it and a host's tests have to be able to name both; the photo source
// seam is exported so a host (or a test) can stand in for the camera.
export 'src/catalog_scan_review_screen.dart';
export 'src/merchant_blitz_screen.dart';
// Where every photo comes from — Blitz's shelves, a customer's search by photo, a merchant's find by
// photo — so a host, or a test, can stand in for the camera and the gallery; and the sheet that asks
// for one photo to read and says where it goes, shared by the customer's search and the merchant's find.
export 'src/photo_find_sheet.dart';
export 'src/photo_pick_sheet.dart';
export 'src/photo_source.dart';
// The shop's own daily series as a page. Exported as well as reachable from settings, so a host
// with room for it in a rail can mount it directly instead of hiding it one tap into a menu.
export 'src/merchant_analytics_screen.dart';
// The bank record behind the settings row. Exported like the analytics page and for the same
// reason: a host with room for it can mount it directly.
export 'src/merchant_payout_screen.dart';
export 'src/merchant_settings_screen.dart';
// The shop's own statement — what the ledger says it is owed over a range, and the orders behind
// it. Exported for the same reason as the two above, and for one more: it is the page a host will
// want to put somewhere a merchant can find without going through Settings.
export 'src/merchant_statement_screen.dart';
// The order detail screen and, with it, the small parts the three merchant frames share —
// `MerchantMetricCard`, `MerchantTileGrid`, `MerchantStatusTag`, `merchantMaxContentWidth` and the
// rest. Exported because they are the package's own vocabulary: a host mounting these screens in
// its own shell has to be able to name them, and so do the tests, without reaching into `src/`.
export 'src/order_detail_screen.dart';
export 'src/orders_screen.dart';
export 'src/product_form_screen.dart';
export 'src/product_list_screen.dart';
// A shop's conversations with its customers, and one conversation. Mounted by the mobile shell from
// Settings and by the portal's merchant rail; the customer app opens the same thread screen from a
// shop's page, so both ends of one conversation are one widget and cannot drift apart.
export 'src/shop_inbox_screen.dart';
export 'src/shop_thread_screen.dart';
// The number both hosts put on their way into that inbox, kept current without a push.
export 'src/shop_unread_count.dart';
// A shop's own page, as something it can hand out: the link, the QR code and the printable poster.
// Both halves are exported because the two hosts mount different ones — the portal puts the card on
// its My shop page, since a nav-rail tab for one QR code is a tab nobody returns to, and the phone
// opens the screen from its Settings list, Shop Profile being two taps further in.
export 'src/shop_share.dart';
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
// The services marketplace's provider side (Figma 126:51, 126:133, 126:200): a services shop's order
// queue and order detail, mounted by the phone's shell in services mode and by the portal's services
// rail like every page above. The files interface is exported because a host hands the order detail
// its implementation.
export 'src/services/service_dashboard_screen.dart';
export 'src/services/service_offer_form_screen.dart';
export 'src/services/service_offers_screen.dart';
export 'src/services/service_order_detail_screen.dart';
export 'src/services/service_orders_screen.dart';
