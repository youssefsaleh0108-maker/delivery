# The designs added to Figma, mapped to the code

Figma file `4lIJm9HXkQtTQHqhBIpNfB` ("YouDrop"). The frames below are the newest in the file
(node-id prefixes 112, 119 and 121) and nothing in the code cited them when this was written.
Each was read with Figma's design context and mapped against the real code by an analyst, so the
file paths, endpoints and gaps below are checked, not guessed. Sizes are honest estimates;
**questions** are product decisions the code cannot make.

**16 frames in 7 clusters.**

| Frame | Name | Size | Cluster |
|---|---|---|---|
| `121:198` | merchant-blitz | XL | Merchant blitz and demand heatmap |
| `121:8` | demand-heatmap | L | Merchant blitz and demand heatmap |
| `112:9` | web-carrier-reconciliation-overview | L | Carrier web: reconciliation overview, rider settlement, rider payroll |
| `112:235` | web-carrier-rider-settlement | L | Carrier web: reconciliation overview, rider settlement, rider payroll |
| `112:1162` | web-carrier-rider-payroll | XL | Carrier web: reconciliation overview, rider settlement, rider payroll |
| `112:1684` | customer-gift-hub | L | Customer: gift hub and gift checkout |
| `112:1830` | customer-gift-checkout | XL | Customer: gift hub and gift checkout |
| `112:1941` | customer-dekkane-browse | M | Customer: neighbourhood dekkane browse and shop, neighbourhood chat |
| `112:2041` | customer-dekkane-shop | L | Customer: neighbourhood dekkane browse and shop, neighbourhood chat |
| `121:102` | neighborhood-chat | XL | Customer: neighbourhood dekkane browse and shop, neighbourhood chat |
| `112:413` | web-carrier-riders-directory | M | Carrier web: riders directory, rider profile, attendance |
| `112:740` | web-carrier-rider-profile | L | Carrier web: riders directory, rider profile, attendance |
| `112:945` | web-carrier-rider-attendance | XL | Carrier web: riders directory, rider profile, attendance |
| `121:358` | multi-merchant-cart | XL | Customer: multi-merchant cart and offline mode |
| `121:279` | offline-mode | L | Customer: multi-merchant cart and offline mode |
| `119:4` | souk-landing-page | M | Souk landing page (web) |

## Merchant blitz and demand heatmap

### `121:198` merchant-blitz — XL

*Who:* A shop owner putting a catalogue online for the first time: an applicant or newly approved merchant. The frame is drawn inside the CUSTOMER shell (Home/Butler/Basket/Orders/Account nav, Account tab active). That implies a 'start selling' path from the customer Account tab. But every product endpoint needs the MERCHANT role (ProductController.java:147,154,163), so the scanning itself has to run as a merchant account.

*What:* Build the catalogue with no typing. The merchant photographs their shelves ('1. Scan Shop'). A vision service picks out products, names them and suggests prices from a Beirut wholesale price guide ('2. AI Menus'). The merchant reviews the result and publishes it as the shop's catalogue ('3. Start Selling').

*Reached from:* Design: customer shell, Account tab, back chevron. So the design intends a customer to reach Blitz from Account, as a 'start selling in minutes' funnel. Code reality: the catalogue API needs MERCHANT, and publishing needs MERCHANT without APPLICANT. Recommended: (1) MerchantShell Dashboard shows a 'Build your catalogue in minutes' card when the catalogue is empty; tapping it pushes MerchantBlitzScreen as a MaterialPageRoute (the same idiom as _openStockCount in merchant_shell.dart:314). (2) The InventoryScreen empty state has the same CTA. (3) MerchantSettingsScreen gets a 'Merchant Blitz' row next to Categories (the suite hangs management pages off Settings). (4) Optional: the customer AccountScreen gets a 'Sell on YouDrop' row. It calls POST /api/onboarding/applications/mine (kind MERCHANT), refreshes the token, and the role branch in main.dart moves the user to MerchantShell (pendingApproval=true), where Blitz can scan and save drafts but not publish until approval. The pushed route should NOT show the customer bottom nav; that nav in the frame contradicts the separate MerchantShell.

**Every element, and where its data comes from**

- Status bar (system chrome, not built).
- Header bar: circular back button (16px chevron, background-token fill) pops the route. Title 'Merchant Blitz' (Rubik Bold 18, ink). Subtitle 'Zero-effort catalog builder' (Regular 12, muted). Trailing 'Fast Setup' pill (Bold 11, brand text on brandSoft #FFF1F2, radius 8). Static strings.
- Progress strip (white, bottom border): three step labels. '1. Scan Shop ✓' is done (Bold 12, green #10B981), '2. AI Menus' is current (SemiBold 12, brand), '3. Start Selling' is upcoming (Medium 12, faint). Beside them a 6px track (border colour) with a brand fill. The fill is drawn 100% wide although step 2 is current, and the third label is clipped in the render. Treat the fill as progress (about 2/3 at step 2). Data: local wizard state (scan job status).
- Viewfinder card (270px tall, radius 16): live camera preview or the captured shelf photo, with four white 3px corner brackets (40px, radius 12 on the outer corner). Data: device camera. There is no camera package today; the apps only have file_selector.
- AI detection tags over the photo: dark pills (rgba(15,23,42,.85), radius 8) with a 6px green dot and 'Pepsi 1L — $1.20' / 'Lay's Classic — $0.80' (Bold 11, white). Each sits at the detected bounding box. Data: scan result items {name, suggestedPrice, bbox}. Tapping a tag should open that item's edit row. The design implies this but does not draw it.
- Horizontal scan line across the viewfinder at y=110. Animate it while the scan state is ANALYZING.
- Result counter row (green tint #ECFDF5, radius 12): '⚡ AI Catalog Scan Complete' (Bold 14, green) and '23 items' (ExtraBold 14). Data: scanJob.items.length. Implied non-success variants: 'Scanning…', 'Analysing photo…', 'We couldn't recognise any products', 'Scan failed — try again'.
- Explainer: 'Zero Manual Entry Required' (Bold 16, ink) plus a body paragraph (Regular 13, muted) about computer vision, name translation and matching to Beirut wholesale price guides. Static copy. The claims need product sign-off (see questions).
- Primary CTA 'Review & Publish Catalog' (brand fill, white Bold 15, radius 12, full width, 14px padding). It pushes a REVIEW screen, which has no frame. There the merchant sees every detected item with editable name, price and category and an include toggle, then bulk-creates and publishes. Disabled while the scan is running or when it found 0 items.
- Footer note 'Your shop online in 24 hours. Zero effort.' (Regular 11, faint, centred). This conflicts with manual partner approval (see questions).
- Customer bottom nav with Account active, drawn by CustomerNavBar/YdBottomNav. If the screen moves into MerchantShell it gets that shell's nav instead.
- Implied states not drawn: camera permission denied (fall back to picking from the gallery via file_selector), several shelf photos (one per aisle, which suits 'Scan Shop'), upload progress, analysis in progress (poll), a partial result, an offline error with retry, and after publish a per-item result. Items with no product photo stay DRAFT because Product.publish() needs an image. An applicant cannot publish at all until approved.

**Existing code that already covers part of it**

- clients/packages/delivery_core/lib/src/api/catalog_api.dart — create() :53, publish() :66, uploadImage() :190 (the three-step presign → PUT to MinIO → confirm flow, with ImagePrep downscaling), removeImage() :244, storeCategories() :123. Everything needed to create products one at a time.
- services/product-service/src/main/java/com/delivery/product/api/ProductController.java — POST /api/products (MERCHANT) :146, PUT /{id} :153, POST /{id}/publish needs MERCHANT and not APPLICANT :163.
- services/product-service/src/main/java/com/delivery/product/api/ProductImageController.java — POST /api/products/{productId}/images/presign :44, /{fileId}/confirm :68.
- services/product-service/src/main/java/com/delivery/product/api/dto/CatalogDtos.java:29 — ProductRequest: name @NotBlank ≤200, price ≥0.01 with 2 decimals, optional categoryId, storeId, sku, barcode.
- services/product-service/src/main/java/com/delivery/product/domain/Product.java:179-185 — publish() throws if imageRefs is empty. Products start as DRAFT (:99, :131).
- services/product-service/src/main/java/com/delivery/product/service/CatalogService.java:163 — publish turns the rule violation into CatalogRuleViolationException and emits PRODUCT_PUBLISHED through the outbox.
- services/onboarding-service/src/main/java/com/delivery/onboarding/process/CreatePartnerRecord.java:25-30 — a merchant gets no store at approval. Product Service provisions the shop when the first product is added, so a Blitz commit also creates the store.
- services/product-service/src/main/java/com/delivery/product/service/Thumbnailer.java, ThumbnailService.java, MinioImageObjectStore.java — server-side image handling and storage, reusable for cropping per-item product photos out of a shelf shot.
- services/product-service/src/main/java/com/delivery/product/geocoding/GeocodingProvider.java + MapboxGeocodingProvider/NominatimGeocodingProvider + MinIntervalRateLimiter.java — the provider-seam pattern to copy for a vision provider.
- services/product-service/src/main/java/com/delivery/product/api/MarketController.java:36 — GET /api/market/config {lbpPerUsd}. Prices are USD with an LBP hint.
- clients/packages/delivery_merchant/lib/src/product_form_screen.dart — the single-product editor. Its row fields and validation are the model for review rows.
- clients/packages/delivery_merchant/lib/src/product_list_screen.dart — screen conventions (FutureBuilder, _busy set, _messageFor RFC 9457 extractor at :793-814).
- clients/packages/delivery_core/lib/src/api/inventory_api.dart:66 — lookup(barcode). inventory-service is NOT deployed.
- clients/apps/mobile_app/lib/src/partner_choice_screen.dart:56 (applyAsMerchant 'Sell on YouDrop') + partner_application_screen.dart + main.dart:664-700 — the signed-out merchant application path.
- services/onboarding-service/src/main/java/com/delivery/onboarding/api/AccountOnboardingController.java:88 — POST /api/onboarding/applications/mine: a signed-in customer applies as MERCHANT. Roles change in Keycloak and the app must refresh its token.
- clients/apps/mobile_app/lib/src/account_screen.dart — the customer Account page (rows at :502-607). There is no 'sell on YouDrop' row today.
- clients/apps/mobile_app/lib/src/merchant_shell.dart — MerchantShell: tabs dashboard/pos/inventory/orders/settings, routes pushed from Settings.
- clients/packages/delivery_design_system/lib/src/yd_stepper.dart — the wizard progress bar, with a segmented mode.

**Missing in the clients**

- clients/packages/delivery_merchant/lib/src/merchant_blitz_screen.dart — MerchantBlitzScreen (this frame). Takes CatalogScanApi, CatalogApi and storeId. States: idle, capturing, uploading, analyzing, complete, failed. Host-agnostic per the MERCHANT_SUITE_SPEC screen conventions.
- clients/packages/delivery_merchant/lib/src/catalog_scan_review_screen.dart — the review-and-publish list (no frame; a designer needs to draw it). One row per detected item: thumbnail crop, name, price (USD with LBP hint), category dropdown from storeCategories(), include switch, 'price from guide' hint. Bottom CTA 'Publish N items'. Result sheet lists created, published, left as draft (no photo) and failed.
- A camera capture widget. Add the `camera` package, or `image_picker` for Android/iOS. file_selector (delivery_merchant pubspec.yaml:23-26) cannot open the camera. Keep the file_selector gallery pick as the web/permission-denied fallback. Permission strings are needed in AndroidManifest and Info.plist.
- clients/packages/delivery_core/lib/src/api/catalog_scan_api.dart — CatalogScanApi: startScan(storeId?) → {scanId, uploadUrl, fileId}; confirmPhoto(scanId, fileId); scan(scanId) (poll); updateItem(scanId, itemId, {...}); commit(scanId, itemIds, publish: bool). The upload reuses ImagePrep and the bare-Dio PUT idiom from CatalogApi.uploadImage.
- clients/packages/delivery_core/lib/src/models/catalog_scan_models.dart — CatalogScan {id, status enum PENDING_UPLOAD|ANALYZING|COMPLETE|FAILED, photos, items, failureReason}, DetectedItem {id, name, nameAr?, suggestedPrice?, priceSource?, confidence, bbox, cropImageRef?, categoryHint?, barcode?}, CommitResult {created, published, draftNoPhoto, failed[]}. Tolerant enum parsing per the suite's enum contract.
- An entry point. Recommended: a MerchantShell dashboard card shown when the catalogue is empty, plus the InventoryScreen empty state, plus a Settings row. Optional: a customer AccountScreen row 'Sell on YouDrop' that starts the merchant application (AccountOnboardingController) and hands off to Blitz after approval or token refresh.
- Export the new screens from delivery_merchant.dart. Optional portal wiring as an appended Merchant Hub destination or an action on ProductListScreen (web has no camera, so upload only).

**Missing in the backend**

- product-service — new entity CatalogScan (+ CatalogScanPhoto, DetectedItem) and migration V29__catalog_scans.sql. product-service is currently at V28__revoke_staff_invites.sql; check the next number against the live dev/qa DB and the merchant-suite plan before claiming it. Columns: id, merchant_id, store_id, status, created_at, completed_at, failure_reason. Photos hold object_key. Items hold name, name_ar, suggested_price numeric(12,2), price_source, confidence, bbox jsonb, crop_object_key, category_hint, barcode, committed_product_id.
- product-service — CatalogScanController /api/catalog-scans (MERCHANT): POST / (create a scan and presign a shelf-photo upload), POST /{id}/photos/{fileId}/confirm (verify the object and queue analysis), GET /{id} (status plus items, owner-scoped like CatalogOwnership), PUT /{id}/items/{itemId} (edits), POST /{id}/commit {itemIds, publish}. Commit creates the products in one transaction, attaches the crop as the product image, publishes where allowed (publish is refused for APPLICANT tokens and image-less items, returned per item, not as a 4xx) and records PRODUCT_CREATED/PUBLISHED outbox events per product.
- product-service — a VisionProvider seam like GeocodingProvider: a real vendor adapter plus a deterministic dev/fake provider, with credentials in Vault. Analysis runs async (executor or outbox-driven job) because a vision call takes seconds and must not hold an HTTP request. Rate-limit it per merchant (MinIntervalRateLimiter pattern) and cap photos per scan and scans per day.
- product-service — a price-guide source for 'matches them to active wholesale price guides in Beirut'. Nothing exists. It needs a price_guide table (normalized name/barcode → reference USD price, source, effective date), a backoffice import/CRUD endpoint, and matching logic. Otherwise drop the claim and leave prices empty for the merchant to fill.
- product-service — a bulk create endpoint, whether or not the AI part ships: POST /api/products/bulk (≤100 items, all-or-nothing validation). Scanning 23 items one by one costs 23 creates plus 23 presign/PUT/confirm triples, which breaks the shared Traefik platform-rate-limit (avg 20 / burst 40 per MERCHANT_SUITE_SPEC).
- product-service — crop generation: server-side crop of each bbox from the shelf photo through the Thumbnailer/MinioImageObjectStore path. Without it every AI product has no image and Product.publish() refuses all of them.
- product-service config — application.yml keys for the vision provider (off by default), plus Vault paths and a deploy note. No new service is needed; product-service is deployed on dev.

**Design-system pieces to reuse**

- YdStepper (yd_stepper.dart) for the progress strip. Pass the step label row, and use segmented mode if the designer wants three segments.
- YdBadge (yd_badge.dart) for 'Fast Setup' (brand accent; set uppercase:false or accept uppercase) and for the green success counter tint.
- YdBackButton / YdScreenHeader (yd_screen_header.dart) for the header. YdScreenHeader has title + back + trailing; if it has no subtitle slot, use MerchantScreenHeader from delivery_merchant/lib/src/order_detail_screen.dart or extend YdScreenHeader.
- ElevatedButton shaped by the theme (radius 12 rectangle; YdPillButton is the fully rounded customer pill, not this) for 'Review & Publish Catalog'.
- YdCard.bordered for review rows. YdEmptyState for failed or zero-item scans. YdComingSoon + merchbSoon for gating the AI step while the provider is off.
- Tokens: DeliveryColors.brand #E11D48, brandSoft #FFF1F2, ink #0F172A, muted #475569, faint #94A3B8, border #E2E8F0, background #F8FAFC, white. The green #10B981/#ECFDF5 needs a success token; check tokens.dart past line 97 and add one if it is missing rather than hard-coding hex. DeliveryRadius.lg for cards.
- CatalogApi.uploadImage/ImagePrep for the photo upload idiom. product_list_screen _messageFor for RFC 9457 errors. merchantMoney for USD formatting.

**Strings**

- merchBlitzTitle: 'Merchant Blitz'
- merchBlitzSubtitle: 'Zero-effort catalog builder'
- merchBlitzFastSetup: 'Fast Setup'
- merchBlitzStepScan: '1. Scan Shop' (done variant appends ✓ in code, not in the string)
- merchBlitzStepAi: '2. AI Menus'
- merchBlitzStepSell: '3. Start Selling'
- merchBlitzScanComplete: 'AI Catalog Scan Complete'
- merchBlitzItemCount: '{count, plural, =1{1 item} other{{count} items}}' (ICU plural; Arabic needs zero/one/two/few/many/other)
- merchBlitzScanning: 'Scanning your shelves…' / merchBlitzAnalyzing: 'Recognising products…'
- merchBlitzNoneFound: 'We couldn't recognise any products in this photo.'
- merchBlitzScanFailed: 'The scan didn't finish. Try again.'
- merchBlitzZeroEntryTitle: 'Zero Manual Entry Required'
- merchBlitzZeroEntryBody: the explainer paragraph (final wording after product sign-off on the vision/price-guide claims)
- merchBlitzReviewPublish: 'Review & Publish Catalog'
- merchBlitzFooter: 'Your shop online in 24 hours. Zero effort.' (or softened; see questions)
- merchBlitzAddPhoto: 'Add another shelf photo' / merchBlitzTakePhoto: 'Take photo' / merchBlitzChooseFromGallery: 'Choose from gallery'
- merchBlitzCameraDenied: 'Camera access is off. Choose a photo instead.'
- merchBlitzPublishN: 'Publish {count} items'
- merchBlitzResultDraftNoPhoto: '{count} items saved as drafts — add a photo to publish them.'
- merchBlitzResultAwaitingApproval: 'Saved. Your items go live once your shop is approved.'
- merchBlitzPriceFromGuide: 'Suggested from Beirut wholesale prices'
- merchBlitzEntryCard: 'Build your catalogue in minutes'
- Reuse: publish, tryAgain, needsAPhotoToPublish, couldNotPublishProduct, applyAsMerchant ('Sell on YouDrop'), merchbSoon ('Soon'). Every new key goes in BOTH app_en.arb and app_ar.arb.

**Tests that should prove it**

- delivery_merchant widget test merchant_blitz_screen_test.dart: each scan state renders (analyzing shows the scan line and a disabled CTA; complete shows '23 items' and an enabled CTA; failed shows retry; 0 items shows the empty copy). Uses a fake CatalogScanApi, as the other merchant tests fake their APIs.
- Widget test: permission denied or web falls back to the file_selector pick. Swap FileSelectorPlatform.instance the way the existing file_selector_platform_interface tests do.
- Widget test catalog_scan_review_screen_test.dart: editing price rejects ≤0 and more than 2 decimals (mirrors ProductRequest). The include toggle changes the 'Publish N items' count. The commit result lists 'left as draft — needs a photo' items. RTL and 48dp hit boxes. No overflow at 320px width.
- Host wiring test (mobile_app/test/merchant_shell_wiring_test.dart style): the Dashboard empty-catalogue card pushes MerchantBlitzScreen; with catalogue items the card is absent.
- delivery_core test: CatalogScanApi.startScan/confirm/poll/commit hit the right paths. The upload uses a bare Dio with no Authorization header (the presign rule in catalog_api.dart:224-236).
- product-service CatalogScanServiceTest: ownership (another merchant's scan → 404), status transitions, commit creates products under the caller's store and provisions the store if none exists, image-less items stay DRAFT, and an APPLICANT caller gets per-item 'not yet approved' results, not a 403 for the whole batch.
- product-service BulkProductCreateTest: all-or-nothing validation, ≤100 cap, sku uniqueness within the store (the V25 constraint), one outbox event per product.
- product-service VisionProviderSeamTest (like GeocodingSeamTest): provider off means the scan fails cleanly with a reason, and the fake provider gives deterministic items.
- API scenario infra/scenario-merchant-blitz.mjs (style of scenario-partner-onboarding.mjs): sign in as merchant, start a scan, PUT a fixture photo to the presigned URL, confirm, poll until COMPLETE (fake provider), commit with publish, then GET /api/stores/{id}/products shows the items as ACTIVE.

**Questions**

- Who is this for, and where does it live? The frame is in the customer shell, but the catalogue is merchant-only. Is Blitz a customer-to-merchant acquisition funnel (Account tab) or a MerchantShell tool? The recommendation is MerchantShell, with an optional customer entry that starts the application.
- Vision vendor: which provider, what cost per scan, and is a shop's shelf photo allowed to leave the platform (data-processing terms)? No AI or vision integration exists anywhere in services/ today.
- 'Matches them to active wholesale price guides in Beirut': there is no price-guide data. Who supplies it, who keeps it current, and in USD or LBP? Otherwise drop the claim.
- 'Translates names': is the product name stored in English, Arabic or both? Product has a single name field (CatalogDtos.ProductRequest), so Arabic needs a schema change or goes in the description.
- Product photos: Product.publish() needs ≥1 image. Are server-side crops from the shelf photo good enough as product images, or do AI items land as drafts until the merchant adds photos?
- 'Your shop online in 24 hours': partner applications need approval (APPLICANT cannot publish, ProductController.java:163). Is there an approval SLA, or does Blitz depend on auto-approval (AutoApprovalSettingsController)?
- Should detected items go into the store's own categories (V26 store_categories) or the platform taxonomy? The review screen needs a picker.
- The review/publish screen that 'Review & Publish Catalog' leads to has no frame. It needs a design.
- Barcodes: should the scan also read barcodes (the inventory lookup-by-barcode path exists but inventory-service is not deployed)?

### `121:8` demand-heatmap — L

*Who:* A merchant: shop owner or manager. The actions 'Add to Menu' / 'Stock This' only make sense for a shop. The frame is drawn inside the CUSTOMER shell with the Home tab active. That contradicts both the audience and privacy: customers must not browse other customers' order densities or search terms. Build it as a merchant screen.

*What:* 'Demand Radar — Real-time neighborhood pulses'. It shows where orders are being placed now across the merchant's city, as neighbourhood density blobs, and what nearby customers are searching for. The merchant can then add those items to the menu or stock them.

*Reached from:* Design: customer shell with the Home tab active, and a back chevron, which suggests a pushed page. For the correct audience: MerchantShell → Dashboard tab gets a 'Demand Radar' card (owner, or staff with MODIFY_INVENTORY_PRICING for the actions) that pushes DemandRadarScreen as a MaterialPageRoute. Also MerchantShell → Settings → 'Demand Radar' row beside 'Shop Analytics' (merchant_settings_screen.dart _openAnalytics pattern; Soon chip when DemandApi is null). 'View Details' pushes TrendingSearchesScreen. 'Add to Menu' pushes ProductFormScreen with initialName. 'Stock This' pushes the product form with 'Track stock' on (needs inventoryApi), or is inert with YdComingSoon until inventory-service deploys. Portal: append a 'Demand Radar' PortalDestination after the existing Merchant Hub entries (portal_shell.dart), never reordering them. It must NOT be reachable from the customer shell.

**Every element, and where its data comes from**

- Header bar: back button. Title 'Demand Radar' (Bold 18) with a 'LIVE' badge (green #10B981 on #DCFCE7, 6px dot, Bold 10). Subtitle 'Real-time neighborhood pulses' (Regular 12, muted). Trailing city pill 'Beirut' (brand on brandSoft). Data: the city is the region of the merchant's store (DeliveryZone.region, e.g. 'Beirut', 'Mount Lebanon', or Store.neighborhood's region). If the merchant serves several regions, the pill could open a region switcher; not drawn.
- Map card (white, 1px border, radius 16, 12px padding, faint drop shadow). Header row: 'Active Order Densities' (Bold 14) and 'Live Syncing' (SemiBold 11, brand). 'Live Syncing' should show last-updated or syncing state, turning to 'Last updated 2 min ago' or offline when polling fails.
- Map (220px, radius 12): basemap plus translucent density circles sized and coloured by level. 'Mar Mikhael (High)' is a large red blob with a solid core and a white label, 'Hamra (Med)' is amber with an ink label, 'Badaro' is a small teal blob with a muted label and no level. Data: aggregated order counts per neighbourhood or grid cell for a recent window (e.g. last 60 min), shown as relative levels (High/Med/Low), never raw counts. Implied interactions: pinch/pan, tap a blob for a tooltip (neighbourhood, level, trend).
- 'Trending Searches Near You' section header (Bold 15) with a 'View Details' text action (SemiBold 12, brand). The action pushes a full trending list (no frame) with time-window and neighbourhood filters.
- Trend rows (white, bordered, radius 12), three drawn: a 36px emoji tile on a tinted background (🍣 brandSoft, 💊 blue #EFF6FF, 🥖 amber #FEF3C7), the term in Bold 14 ('Sushi Platter', 'Panadol Extra', 'Fresh Baguette / Bread'), and a caption in Regular 12 muted ('47 local searches in last 1hr', '32 local searches nearby', '28 searches in Mar Mikhael'). The three captions phrase the window and scope inconsistently; normalise to one pattern with the neighbourhood optional. Data: trending search terms with count, window and neighbourhood, and an emoji/category for the tile (from the platform category of matching products, or a fallback glyph).
- Row action 'Add to Menu' (brand filled, radius 8, Bold 12 white). Pushes ProductFormScreen prefilled with the search term as the product name, owner/MODIFY_INVENTORY_PRICING only. When the store already sells a matching product, it becomes 'On your menu' or 'Edit' (not drawn; implied).
- Row action 'Stock This' (ink filled). Drawn for a pharmacy item: a grocery/pharmacy vertical versus food 'menu'. Intended meaning: add the product and start tracking stock (receive stock). It depends on inventory-service, which is NOT deployed. Until then it either behaves like Add to Menu or shows YdComingSoon.
- Bottom nav (customer shell, Home active). Wrong shell for this audience; see navigation.
- Implied states: loading (map skeleton, list shimmer); error with retry; basemap tiles unreachable (OsmBasemap/osmTiles fallback surface); an empty map ('No orders in the last hour'); an empty trending list ('Not enough searches nearby yet'), which is also the privacy threshold state; merchant with no store pin (centre on the region, or ask them to set the pin via StoreScreen).

**Existing code that already covers part of it**

- services/order-manager/src/main/resources/db/migration/orders/V25__order_route_points.sql + domain/Order.java:220-243 — every order stores pickup_lat/lng and dropoff_lat/lng (numeric 9,6). This is the raw material for order density. dropoff is null when the customer's address has no pin.
- services/order-manager/src/main/java/com/delivery/order/event/OrderEvents.java:81-230 — OrderSnapshot on order.placed/status_changed/delivered already carries dropoffLat/dropoffLng, so another service could project density from events.
- clients/apps/mobile_app/lib/src/checkout_screen.dart:273,289-290 — checkout sends deliveryZoneId (from the address) and deliveryLatitude/Longitude.
- services/order-manager/src/main/java/com/delivery/order/service/OrderService.java:178,312 + client/StoreClient.java:147 — deliveryZoneId is used ONLY to price the order (GET /api/delivery-zones/terms/{storeId}). It is NOT saved on Order and NOT in OrderSnapshot, so neighbourhood labels cannot come from existing orders.
- services/product-service/src/main/java/com/delivery/product/domain/DeliveryZone.java:14 + clients/packages/delivery_core/lib/src/models/zone_models.dart — a delivery zone is a NAMED area (name, region, sortOrder), 'not a polygon and not a coordinate'. DeliveryZoneApi.picker()/all() (delivery_zone_api.dart:16,24) list them. No geometry exists to map a lat/lng to a neighbourhood.
- services/product-service/src/main/java/com/delivery/product/domain/Store.java:188 (neighborhood) + StoreController GET /api/stores/neighborhoods :149 + StoreApi.neighborhoods() — shop neighbourhoods (supply side, not demand).
- services/order-manager/src/main/java/com/delivery/order/api/OrderController.java:136 GET /api/orders/merchant/daily + delivery_core aggregates_api.dart merchantDaily() + delivery_merchant merchant_analytics_screen.dart — the merchant's OWN daily series. The only merchant analytics today; nothing covers geography or other shops' demand.
- Search entry points (no logging anywhere): StoreController.java:129-139 GET /api/stores?search= → StoreService.storefront :93. ProductController.java:80-86 GET /api/products?search= → CatalogService.browseCatalog :48. StoreController.java:252 GET /api/stores/{id}/products?search= → CatalogService.browseStore :54. SearchPatterns.java only builds LIKE patterns. The client search box is store_home_screen.dart:88,120 (debounced).
- services/order-tracking/.../TrackingController.java:56 (rider position pings per order, STOMP /topic/orders/{id}/position) and RiderPresenceController /api/tracking/riders/roster :137 — rider (supply) positions. Useful only if the product later wants a supply-vs-demand overlay. There is no live demand topic.
- clients/packages/delivery_merchant/lib/src/store_pin_map.dart:108 osmTiles(MapTileWatch) and :825 CircleLayer; clients/apps/mobile_app/lib/src/carrier_zones_screen.dart:242,463 CircleLayer; clients/apps/mobile_app/lib/src/address_sheet.dart:1067 OsmBasemap (attribution plus a fallback when tiles fail; app-private, not in a package). flutter_map ^8.3.2 and latlong2 are already dependencies of delivery_merchant and mobile_app.
- clients/packages/delivery_merchant/lib/src/product_form_screen.dart — the target of 'Add to Menu' (needs a prefill parameter). clients/packages/delivery_core/lib/src/api/inventory_api.dart adjust()/updateItemSettings() — the target of 'Stock This' (inventory-service not deployed).
- clients/packages/delivery_merchant/lib/src/dashboard_screen.dart (MerchantDashboardScreen) and merchant_settings_screen.dart:348-358 (_openAnalytics push pattern) — natural entry points.
- clients/apps/delivery_portal/lib/src/portal_shell.dart:195-265 — Merchant Hub destinations. New ones are APPENDED, never reordered, because the dashboard relies on jump(2).

**Missing in the clients**

- clients/packages/delivery_merchant/lib/src/demand_radar_screen.dart — DemandRadarScreen(api: DemandApi, storeApi, catalogApi, storeId, access, onAddToMenu, onStockThis?, onBack). Map card and trending list. 60s silent poll like the dashboard, cancelled in dispose and paused when the route is not visible. The LIVE badge only shows while the last poll succeeded.
- A density map widget in delivery_merchant: flutter_map with osmTiles plus a CircleLayer per cell/neighbourhood (radius from level, colours from tokens with alpha) and MarkerLayer labels ('Mar Mikhael (High)'). Move OsmBasemap out of mobile_app/address_sheet.dart into delivery_merchant or the design system so attribution and fallback are not re-implemented.
- clients/packages/delivery_merchant/lib/src/trending_searches_screen.dart — the 'View Details' full list: window chips 1h/24h/7d, neighbourhood filter. No frame.
- clients/packages/delivery_core/lib/src/api/demand_api.dart — DemandApi: density({region, windowMinutes}) → DemandMap; trending({storeId, windowMinutes, zoneId?, limit}) → List<TrendingSearch>.
- clients/packages/delivery_core/lib/src/models/demand_models.dart — DemandMap {region, generatedAt, windowMinutes, cells: [DemandCell {zoneId?, label?, lat, lng, level enum HIGH|MEDIUM|LOW, radiusM?}]}; TrendingSearch {term, count, windowMinutes, zoneName?, categoryHint?, matchedProductId?}. Tolerant enums.
- ProductFormScreen: add optional initialName (and initialCategoryId) so 'Add to Menu' can prefill.
- A way in: a MerchantDashboardScreen 'Demand Radar' card (owner-only, like the Orders gate) and a MerchantSettingsScreen row next to 'Shop Analytics'. An appended portal Merchant Hub destination 'Demand Radar'.
- The customer search box (store_home_screen.dart) and product search must send the selected address's zoneId as a query parameter (e.g. &zoneId=) so searches can be placed by neighbourhood. Never send lat/lng or user ids in query strings.

**Missing in the backend**

- order-manager — migration V31__order_delivery_zone.sql (next after V30__carrier_order_indexes.sql; check against the live DB): add orders.delivery_zone_id uuid null, saved from PlaceOrderRequest.deliveryZoneId in OrderService (it is already received at :178), plus an index on (delivery_zone_id, created_at). Add deliveryZoneId to OrderSnapshot so projections get it. Old orders cannot be backfilled by zone. Density falls back to dropoff lat/lng grid cells.
- order-manager — DemandService + GET /api/orders/demand/density?region=&windowMinutes= (MERCHANT, also BACKOFFICE). Counts orders placed in the window (excluding CANCELLED) grouped by delivery_zone_id, falling back to a coarse grid (dropoff rounded to about 500m-1km cells) where the zone is null. Returns relative levels (tertiles against the region's own window) and applies a minimum-count threshold so a cell with 1-2 orders never shows (k-anonymity: this must not reveal a customer's home). An index on orders(created_at) may be needed (check V28/V30 indexes). A zone centre coordinate is needed to draw a zone blob: add center_lat/center_lng to product-service delivery_zones (see next item) or compute it as the average of dropoff pins per zone.
- product-service — migration (V29/V30, coordinate with the Blitz scan migration) adding optional center_lat, center_lng to delivery_zones, editable in the backoffice ZonesScreen, so named neighbourhoods like 'Mar Mikhael' can be placed on a map. DeliveryZoneController PUT /{id} accepts them.
- product-service — search capture: migration for search_events (id, term_normalized varchar(120), zone_id uuid null, vertical, result_count int, occurred_at, session_hash null). Recorded async, fire-and-forget off the request thread, from StoreController.browse, ProductController.browse and StoreController.products when search is non-blank and ≥2 chars. Normalise (lowercase, trim, Arabic/arabizi folding), never store the user id, keep 30 days (scheduled purge).
- product-service — GET /api/demand/trending?storeId=&windowMinutes=&zoneId=&limit= (MERCHANT, owner/staff via StoreAccess). Aggregates search_events in the zones the store covers (DeliveryZoneService coverage) or the store's region. Suppresses terms below N distinct searches. Ranks zero- or low-result searches up as the strongest 'unmet demand' signal. Marks matchedProductId when the caller's store already sells a match (SearchPatterns LIKE over its products).
- Gateway/ingress: expose /api/orders/demand/** and /api/demand/** through the existing templates. Both services are deployed on dev, so no new service.

**Design-system pieces to reuse**

- flutter_map CircleLayer/MarkerLayer as in store_pin_map.dart:825 and carrier_zones_screen.dart:242; osmTiles/MapTileWatch (store_pin_map.dart:108); OsmBasemap (address_sheet.dart:1067, move it to a package).
- YdBadge for 'LIVE' (green accent) and the 'Beirut' pill (brand); reuse keys carrBadgeLive 'LIVE' / live 'Live'.
- YdCard.bordered for the map card and trend rows. YdSectionHeader(title, actionLabel 'View Details', fontSize 15). YdEmptyState for empty/error. YdComingSoon.wrap + merchbSoon for 'Stock This' until inventory ships.
- YdScreenHeader/YdBackButton, or MerchantScreenHeader (order_detail_screen.dart), for the title + subtitle + trailing pill header.
- Buttons: small filled ElevatedButton variants, brand fill for Add to Menu and DeliveryColors.ink fill for Stock This (radius 8). Tokens: brand, brandSoft, ink, muted, faint, border, background. The green (#10B981/#DCFCE7), amber (#FEF3C7) and blue (#EFF6FF) tints need semantic tokens in tokens.dart if they are not already there; the heat levels map to brand (high) / amber (medium) / teal or green (low).
- Dashboard 60s silent-poll idiom and the 'keep last good numbers on failure' rule (dashboard_screen.dart, per surface-checklist MerchantDashboardScreen states).

**Strings**

- demandRadarTitle: 'Demand Radar'
- demandRadarSubtitle: 'Real-time neighborhood pulses'
- demandActiveOrderDensities: 'Active Order Densities'
- demandLiveSyncing: 'Live Syncing' / demandLastUpdated: 'Updated {minutes} min ago' / demandOffline: 'Can't refresh right now'
- demandLevelHigh: 'High' / demandLevelMedium: 'Med' / demandLevelLow: 'Low' / demandZoneWithLevel: '{zone} ({level})'
- demandTrendingNearYou: 'Trending Searches Near You'
- demandViewDetails: 'View Details'
- demandSearchesInWindow: '{count, plural, other{{count} local searches in the last hour}}' (one ICU pattern replacing the design's three phrasings)
- demandSearchesInZone: '{count, plural, other{{count} searches in {zone}}}'
- demandAddToMenu: 'Add to Menu'
- demandStockThis: 'Stock This'
- demandOnYourMenu: 'On your menu'
- demandNoOrdersYet: 'No orders nearby in the last hour.'
- demandNotEnoughSearches: 'Not enough searches nearby yet. Check back later.'
- demandMapUnavailable: 'The map can't load right now.'
- demandEntryCard: 'See what your neighbourhood wants'
- Reuse: live, carrBadgeLive, tryAgain, merchbSoon, navDashboard. The region name ('Beirut') comes from DeliveryZone.region data, not from l10n. Every new key goes in BOTH app_en.arb and app_ar.arb.

**Tests that should prove it**

- delivery_merchant widget test demand_radar_screen_test.dart: renders blobs and labels from a fake DemandApi. LIVE badge shows after a successful poll and hides after a failed one while the last good data stays. Empty-map and empty-trending copy. A tile failure shows the fallback surface with attribution. RTL mirroring. No overflow at 320px. 48dp action hit boxes.
- Widget test: 'Add to Menu' calls onAddToMenu with the term. An already-matched term shows 'On your menu'. An employee without MODIFY_INVENTORY_PRICING sees no actions. 'Stock This' shows the Soon chip when inventoryApi is null.
- Widget test: the poll timer is cancelled on dispose (the fake async test pattern from the dashboard tests).
- Host wiring test: the MerchantShell Dashboard card pushes DemandRadarScreen for an owner and is absent for an employee. Portal destination order is unchanged (jump(2) still opens Orders).
- delivery_core test demand_api_test.dart: paths and query params (zoneId, windowMinutes). Tolerant enum parsing of level. No PII in query strings.
- order-manager DemandServiceTest: groups by delivery_zone_id and falls back to grid cells for null zones. Cancelled orders are excluded. The window is respected in Asia/Beirut (DailyTradeService zone idiom). Cells under the threshold are suppressed. Levels are tertiles.
- order-manager OrderCheckoutTest/OrderRoutePointsTest extension: deliveryZoneId is now saved and appears in the OrderSnapshot.
- product-service SearchEventRecorderTest: blank/1-char searches are not recorded. Terms are normalised. Recording failure never fails the browse request. Retention purge works.
- product-service TrendingSearchServiceTest: k-threshold suppression, coverage-scoped zones, matchedProductId for the caller's own store only, and another merchant's store id → 404/403 (StoreAccess).
- product-service RepositoryQueryParseTest additions for the new native queries (the existing guard against Postgres bytea/LIKE pitfalls).
- API scenario infra/scenario-demand-radar.mjs: a customer places orders into two zones and searches 'sushi' N times with zoneId. The merchant GETs density (zones present with levels) and trending ('sushi' present, count ≥ threshold). A customer token gets 403 on both endpoints.

**Questions**

- Audience: confirm it is merchant-only. The frame's customer nav with Home active suggests customers see it, which would expose other customers' behaviour.
- Privacy: what minimum counts (orders per cell, searches per term) and what grid size are acceptable, so a blob or a '28 searches in Mar Mikhael' line cannot identify a household? Should raw counts be shown at all (the design shows counts for searches, levels for orders)?
- Scope of 'Near You': the merchant's covered zones (coverage table), their region, or a radius around the store pin (Store.latitude/longitude; can be null)?
- Should density count only orders placed on YouDrop, all verticals, or only the merchant's own vertical (Store.Vertical)? Showing a pharmacy the sushi demand is noise, yet the design mixes 🍣, 💊 and 🥖 in one list.
- 'Live': is a 60s poll acceptable, or does product want push (a STOMP topic like order-tracking's)? Push adds real infrastructure for little merchant value.
- 'Stock This' vs 'Add to Menu': is the label chosen by store vertical (restaurant vs grocery/pharmacy) or by whether the product exists in the catalogue? And 'Stock This' depends on inventory-service, which is not deployed.
- Emoji tiles: derive them from the category of matching products, from a curated term→emoji table, or drop them?
- Named neighbourhoods need map positions: who enters zone centre coordinates in the backoffice, and is the approximation acceptable for 'Mar Mikhael'-style labels?
- Is there a commercial angle (e.g. selling demand insight as a paid tier), which would change who can see what?

**Build order for this cluster**

- 0. Product decisions first. Confirm both screens are merchant-facing (both frames wrongly carry the customer nav). Settle the Blitz vision vendor and price-guide source, and the demand-radar privacy thresholds. Blitz's AI part cannot start without the vendor decision.
- 1. Demand, smallest slice: order-manager GET /api/orders/demand/density from the EXISTING dropoff_lat/lng (grid cells, threshold, levels), no migration. DemandApi.density + models, then DemandRadarScreen map-only behind a MerchantShell dashboard card. Widget, service and scenario tests.
- 2. Save the neighbourhood: order-manager V31 adds orders.delivery_zone_id (already received, currently only used for pricing) plus the OrderSnapshot field. product-service adds optional delivery_zones center_lat/lng with a backoffice edit. Density then groups by zone with named labels ('Mar Mikhael (High)').
- 3. Trending searches: product-service search_events migration, an async recorder in the three browse endpoints, and the customer app sending zoneId with searches. Then GET /api/demand/trending with k-threshold and matchedProductId, the trend list, and 'Add to Menu' → ProductFormScreen(initialName). TrendingSearchesScreen for 'View Details'. Settings row and appended portal destination.
- 4. 'Stock This': wire it once inventory-service is deployed (updateItemSettings + adjust). Until then render YdComingSoon.
- 5. Blitz without AI (useful alone): product-service POST /api/products/bulk (rate-limit safe) and a CatalogScanReviewScreen fed by a manually entered or pasted list, with per-item publish results (the image-required and APPLICANT rules surfaced per row).
- 6. Blitz capture: add the camera/image_picker dependency and permissions, the CatalogScan entity/migration/controller with presigned shelf-photo upload, and a VisionProvider seam with a deterministic fake provider. MerchantBlitzScreen states driven by polling. Server-side bbox crops attached as product images.
- 7. Real vision provider adapter plus Vault credentials, and the price-guide table with backoffice import and matching. Per-merchant scan quotas.
- 8. Optional acquisition funnel: customer AccountScreen 'Sell on YouDrop' row → POST /api/onboarding/applications/mine (MERCHANT) → token refresh → MerchantShell (pendingApproval) → Blitz saves drafts, publishing unlocks on approval.
- 9. Update docs/surface-checklist.md with every new screen, control and state, and add l10n keys to app_en.arb and app_ar.arb in the same slice as each screen.

**Cross-cutting**

- Both frames are drawn inside the CUSTOMER bottom nav (Home/Butler/Basket/Orders/Account), but the content is merchant-only. The code keeps merchants in a separate MerchantShell (merchant_shell.dart) with Dashboard/POS/Inventory/Orders/Settings. Build them as pushed routes from MerchantShell and do not copy the customer nav.
- Backend rules the design ignores: Product.publish() refuses a product with no image (Product.java:179-185), and POST /api/products/{id}/publish is `hasRole('MERCHANT') and !hasRole('APPLICANT')` (ProductController.java:163). So neither 'Review & Publish Catalog' nor 'Add to Menu' can publish instantly for a new or photo-less item. Surface per-item draft results rather than failing whole requests.
- Shared Traefik platform-rate-limit (avg 20 / burst 40, per MERCHANT_SUITE_SPEC) makes one-at-a-time bulk creation (23 creates plus 69 image calls) fail. Blitz needs a bulk endpoint.
- inventory-service and pos-service are NOT deployed. Anything 'Stock This'-shaped must degrade (YdComingSoon + merchbSoon) until they are.
- No AI/vision integration, no search logging and no price-guide data exist anywhere in services/. All three are new capabilities with vendor, cost and privacy implications. Follow the GeocodingProvider seam pattern (a real adapter plus a dev/fake provider, credentials in Vault, rate limiter).
- Geography: DeliveryZone is a named list with no geometry (DeliveryZone.java:14). Orders keep dropoff lat/lng (V25) but NOT the zone id (it is only used for pricing, OrderService.java:178). Neighbourhood-level maps need that saved plus zone centre coordinates.
- Migration numbering: product-service is at V28, order-manager at V30. The merchant suite and these two features may compete for the next numbers. Verify against the live dev/qa DBs as MERCHANT_SUITE_SPEC's 'Migration numbering' section requires.
- Maps: reuse flutter_map + the OSM tile helpers (store_pin_map.dart osmTiles, address_sheet.dart OsmBasemap). The OSM attribution is mandatory. Move OsmBasemap into a shared package instead of copying it.
- Design-system gaps: success/green, amber and blue tints are used in both frames. Add semantic tokens in tokens.dart (check whether they exist beyond line 97) instead of hex. The header with title + subtitle + trailing pill may need a YdScreenHeader subtitle slot.
- l10n: every string goes in BOTH app_en.arb and app_ar.arb with ICU plurals (Arabic plural forms). Region names come from DeliveryZone data, not ARB.
- Privacy: demand density and trending searches are aggregated behaviour of other users. Enforce server-side k-anonymity thresholds and coarse cells, never log user ids with search terms, never put location or PII in query strings, and set a retention purge.

## Carrier web: reconciliation overview, rider settlement, rider payroll

### `112:9` web-carrier-reconciliation-overview — L

*Who:* CARRIER-role staff (a company dispatcher or operations manager) in the delivery_portal carrier area. Not riders, not the Back Office.

*What:* Lets a delivery company's operations manager see how much cash each of its riders is holding from cash-on-delivery jobs, spot who is overdue or disputed, and record hand-overs. It is the carrier-scoped version of the Back Office 'Cash on hand' block in reconciliation_screen.dart.

*Reached from:* A new rail item in PortalArea.carrier_ (portal_shell.dart) labelled 'Reconciliation' (Icons.calculate_outlined / Icons.calculate, matching the design's calculator glyph), inserted right after 'Statement' (current index 3), so it sits at index 4. The carrier dashboard's onShowJobs uses jump(1), so nothing may be inserted before Jobs. 'View' on a row opens 112:235, either as a pushed page within the destination or as a showConsoleDrawer slide-over like CompanyScreen's _RiderDetail. The design's 8-item rail (Dashboard, Orders, Fleet, Reconciliation, Riders HR, Earnings, Coverage, Settings) does not match the shipped 7 (Dashboard, Jobs, Earnings, Statement, Company, Applicants, Settings). Only the Reconciliation item is in scope here.

**Every element, and where its data comes from**

- Sidebar (shared carrier chrome): brand tile 'YD', wordmark 'CARRIER BACKOFFICE', carrier pill (logo initials 'LE', company name 'Libanex Express', 'Beirut Hub • ID: #4051'), 8-item rail with Reconciliation selected, footer user card 'Kamal M. / Operations Manager' + log-out. Data: DeliveryProviderApi.myCompany() for name/id. The hub name has no source. The footer uses session.displayName + t.carrierPartner (the portal deliberately shows the access role, not a job title).
- Topbar title 'Rider Cash Reconciliation' + subtitle 'Match physical cash collections with riders and resolve dues'. Static strings.
- Live badge 'Beirut Live (34 Riders)', green dot. Data: the on-duty count from the tracking presence roster (TrackingApi). The carrier area does not pass TrackingApi today, so either wire it or drop the badge.
- Bell icon. ConsoleBell is exported from shell/shell.dart now, but every carrier page still draws an inert ConsoleIconAction; it needs NotificationApi threaded through.
- KPI 1 'TOTAL PENDING COLLECTION' amount (amber) + footnote 'Due from N riders'. Data: the sum of outstanding COLLECTED cash_float rows for this company's riders, plus a distinct holder count. New endpoint.
- KPI 2 'SETTLED TODAY' amount (green) + 'N settlements processed'. Data: REMITTED (or new hand-over) cash_float rows created today for this company's riders. New query.
- KPI 3 'DISPUTED AMOUNT' (red) + 'N open dispute claims'. Data: none. No dispute entity exists anywhere. CashFloatEntry.Kind.WRITTEN_OFF exists, but nothing writes it.
- KPI 4 'OVERDUE COLLECTION' (red, red card border) + 'N riders > 48h limit'. Data: outstanding rows older than a threshold. The Back Office uses a hard-coded client constant of 24h (_bankItWithin); the design says 48h, so make it server config.
- Table card header 'Rider Statements & Balances' + date chip 'Today: Oct 24, 2026' with a calendar icon. This implies a day picker scoping the collections/earnings columns; the outstanding balance is not day-scoped.
- Button 'Export CSV' (outlined, download icon). No CSV/download code exists anywhere in the portal or accounting-service.
- Button 'Settle Selected' (primary). Needs row selection, which ConsoleTable does not support (ConsoleTableRow has only cells + onTap).
- Table columns: RIDER NAME (28px initials avatar + name) | TOTAL COLLECTIONS | 'commission (15%)' | RIDER EARNINGS | BALANCE DUE (red when overdue) | LAST SETTLEMENT (relative: 'Yesterday', '3 days ago', or a date) | STATUS pill | ACTIONS. Data per rider: holderRef, name, collected in period, platform share (see questions), earned (rider_ledger JOB_EARNING, fleet CARRIER, carrier_ref = company), outstanding float, last remittance time, status.
- Status pills: 'Pending Match' (amber #fef3c7/#92400e), 'Settled' (green #ecfdf5/#065f46), 'Overdue 72h' (red #fef2f2/#991b1b, hours computed), 'Disputed' (blue #eff6ff/#1e40af). In the design the 'Pending Match' label is clipped at 110px.
- Row action 'Settle' (tint button, brand-soft). It opens a confirmation, then records the hand-over. The design shows it even on $0.00 'Settled' rows; it must be disabled there.
- Row action 'View' (outlined). Opens the rider settlement detail (112:235).
- States (implied, not drawn): loading spinner; 404 no company (reuse t.noCompanyYet / t.askThePlatformToAttachYou like EarningsScreen); 503 'could not be built just now'; empty 'Nobody on your fleet is holding cash' (the Back Office hides the block entirely when empty); an overdue SoftNote like the Back Office one.

**Existing code that already covers part of it**

- D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/reconciliation_screen.dart: the Back Office twin. _SummaryTiles ('Cash on hand' tile, age-coloured accent), _CashOnHand/_HolderRow (per-holder amount, orders, oldest, 'Overdue' StatePill, 'Banked' button), _remit() confirmation dialog ('Record a hand-over … cannot be undone'), _ago(), _money(). Platform-wide and BACKOFFICE only.
- D:/workspace/delivery/clients/packages/delivery_core/lib/src/api/accounting_api.dart: cashFloat() GET /api/accounting/float and remit(holderRef) POST /api/accounting/float/{holderRef}/remit. Both are BACKOFFICE-gated server-side.
- D:/workspace/delivery/clients/packages/delivery_core/lib/src/models/accounting_models.dart: CashHolder (holderRef, holderKind, amount, orders, oldest, age) and Remittance (isEmpty).
- D:/workspace/delivery/services/accounting-service/src/main/java/com/delivery/accounting/api/ReconciliationController.java: GET /float (outstandingByHolder) and POST /float/{holderRef}/remit. The class is @PreAuthorize(hasRole('BACKOFFICE')) and documents why a hand-over is platform-confirmed.
- D:/workspace/delivery/services/accounting-service/src/main/java/com/delivery/accounting/service/CashFloatService.java: remitAll(holderRef). Settles the whole balance or nothing and writes a CASH_REMITTANCE posting.
- D:/workspace/delivery/services/accounting-service/src/main/java/com/delivery/accounting/domain/CashFloatRepository.java: outstandingFor, outstandingTotalFor, totalForHolderBetween(kind), forHolderBetween, outstandingByHolder (all platform-wide, no carrier filter).
- D:/workspace/delivery/services/accounting-service/src/main/java/com/delivery/accounting/domain/CashFloatEntry.java: kinds COLLECTED/REMITTED/WRITTEN_OFF; HolderKind RIDER/PROVIDER ('PROVIDER is unused until delivery companies collect their own COD').
- D:/workspace/delivery/services/accounting-service/src/main/java/com/delivery/accounting/event/OrderEventListener.java:139-145: on a CASH order the holder is ALWAYS the rider (HolderKind.RIDER), on carrier fleets too. No carrier ref is stored on the float row.
- D:/workspace/delivery/services/accounting-service/src/main/java/com/delivery/accounting/service/CarrierCompanyClient.java: companyIdFor(bearerToken) resolves the caller's provider id from Order Manager /my-company with the caller's own token. This is the pattern for scoping carrier routes.
- D:/workspace/delivery/services/accounting-service/src/main/java/com/delivery/accounting/api/StatementController.java: the double role check (@PreAuthorize + requireRole), money-as-2dp-string, the 403/404/503 mapping for a carrier with no company.
- D:/workspace/delivery/services/accounting-service/src/main/resources/db/migration/accounting/V46__rider_earnings.sql: rider_ledger with carrier_ref and idx_rider_ledger_carrier ('The carrier's view of who did what'). The index exists, but RiderLedgerRepository has no query using carrier_ref.
- D:/workspace/delivery/services/order-manager/src/main/java/com/delivery/order/api/DeliveryProviderController.java: GET /api/delivery-providers/my-company/riders (CARRIER, own company only) returns ProviderRidersResponse(providerId, List<String> riders): refs only, no names.
- D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/company_screen.dart:816: nameOf(riderRef) takes the onboarding application's contactName and falls back to a short ref. This is the carrier's only rider-name source today.
- D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/statement_screen.dart + earnings_screen.dart: the carrier page pattern (ConsolePage/ConsoleTopbar/ConsoleKpiRow/ConsoleTable, 403/404 error card, date-range picker via ConsoleFilterButton).
- D:/workspace/delivery/clients/apps/delivery_portal/lib/src/shell/ (console_kpi_card.dart, console_table.dart incl. ConsoleNameCell/ConsoleRowAction, console_status_pill.dart, console_controls.dart ConsolePrimaryButton/ConsoleSoftButton/ConsoleTintButton/ConsoleAvatar, console_drawer.dart): all the chrome the frame needs except row selection.

**Missing in the clients**

- New screen D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/reconciliation_screen.dart (CarrierReconciliationScreen): ConsolePage + ConsoleTopbar (date chip via ConsoleFilterButton, refresh, bell), a 4-card ConsoleKpiRow, and a ConsoleTable with a selection column.
- ConsoleTable selection support: either a leading Checkbox cell plus header 'select all', or a `selected`/`onSelected` pair on ConsoleTableRow. The shell is shared, so add a widget test in test/shell.
- A new delivery_core client, CarrierReconciliationApi (or a 'carrier' section in AccountingApi, which today is documented as read-only BACKOFFICE): summary({day}), riders({day}), handover(riderRef, expectedAmount, method, note), exportCsv({day}). New models CarrierCashSummary, CarrierRiderBalance (use Money from statement_models.dart for amounts, not double), HandoverReceipt, and a status enum (holding, settled, overdue, disputed) with a label.
- A confirmation dialog for Settle, modelled on the Back Office _remit(): it names the rider, the amount and the order count, and says it cannot be undone. A bulk variant for Settle Selected lists the riders and the total.
- A CSV download helper: a web Blob plus anchor through package:web, as a conditional import next to shell/external_link_web.dart. Or open a server-signed CSV URL with openExternalLink.
- Rider name resolution: prefer names from the new server endpoint (accounting AccountDirectory.profileOf). Otherwise reuse the application map from CompanyScreen, which needs OnboardingApi.
- Wire a PortalDestination into PortalArea.carrier_ in portal_shell.dart and pass the new api through PortalApis.

**Missing in the backend**

- accounting-service, migration V50__carrier_cash_scope.sql: ALTER TABLE cash_float ADD carrier_ref varchar(64) (the company the job was carried for, set at collection) and a partial index (carrier_ref, holder_ref) WHERE entry_kind='COLLECTED' AND cleared_by IS NULL. Backfill carrier_ref from transactions.counterparty_ref of the order's PROVIDER_CREDIT leg (V47 columns), noting that a fee-less order has no such leg.
- accounting-service, OrderEventListener + SettlementService.CashHolder: carry deliveryProviderId into the float row when deliveryProviderAccount is non-null, so cash on a carrier job stays that company's responsibility even if the rider later changes fleet.
- accounting-service, new CarrierReconciliationController at /api/accounting/carrier, @PreAuthorize(hasRole('CARRIER')) + requireRole second lock. The company comes from CarrierCompanyClient.companyIdFor(token), never a parameter. Routes: GET /summary?day= (pendingTotal, pendingRiders, settledToday amount+count, overdueTotal, overdueRiders, overdueAfterHours, disputed amount+count or null) and GET /riders?day= (riderRef, name, collected, earned, outstanding, orders, oldest, lastSettledAt, status). Money goes on the wire as 2dp strings.
- accounting-service, CashFloatRepository: outstandingByHolderForCarrier(carrierRef), remittedBetweenForCarrier(carrierRef, from, to), lastRemittedAtByHolder(carrierRef). RiderLedgerRepository: earnedByRiderForCarrier(carrierRef, from, to) over JOB_EARNING with fleet CARRIER (uses the existing idx_rider_ledger_carrier).
- accounting-service config: delivery.accounting.float.overdue-after-hours (design 48). Move the Back Office's 24h client constant to read the same value.
- accounting-service, the hand-over action (PRODUCT DECISION FIRST, see questions). If carriers may take custody: POST /api/accounting/carrier/riders/{riderRef}/handover {expectedAmount, method, note} transfers the rider's outstanding COLLECTED rows to a PROVIDER holder (carrier_ref). That needs a migration: chk_float_kind + 'TRANSFERRED', and uq_float_order UNIQUE(order_id, entry_kind) widened to include holder_kind, because the provider copy of the same order would otherwise violate it. Rider and carrier statements need new lines ('Handed to your company' / 'Cash your company holds'). Back Office remit of the PROVIDER holder then closes it. Return 409 when outstanding != expectedAmount, so cash collected after the page loaded is not silently included.
- accounting-service, remitAll race fix before any carrier-facing settle: two concurrent calls read the same outstanding rows with no lock, and both can write a REMITTED row and a CASH_REMITTANCE posting. Add @Lock(PESSIMISTIC_WRITE) on outstandingFor, or a per-holder advisory lock.
- accounting-service, CSV: GET /api/accounting/carrier/riders.csv?day= (text/csv), or the client builds it from /riders.
- accounting-service, disputes (only if kept): migration cash_dispute(id, holder_ref, carrier_ref, order_id null, amount, reason, status OPEN/RESOLVED_RIDER/RESOLVED_COMPANY/WRITTEN_OFF, opened_by, resolved_by, timestamps) plus open/resolve endpoints. WRITTEN_OFF float rows are written only by the Back Office.
- accounting-service AccountDirectory.profileOf: already used by CounterpartyDirectory. Reuse it to return rider names in /riders.

**Design-system pieces to reuse**

- ConsolePage, ConsoleTopbar, ConsoleIconAction, ConsoleFilterButton (date chip), ConsoleKpiRow/ConsoleKpiCard (4 cards; the accent value colour needs a valueColor or footnote variant, since the design colours the value amber/green/red), ConsoleTable/ConsoleColumn/ConsoleTableRow, ConsoleNameCell or ConsoleAvatar (initials), ConsoleStatusPill (DeliveryAccent caution/positive/critical/info), ConsoleTintButton ('Settle'), ConsoleSoftButton ('View', 'Export CSV'), ConsolePrimaryButton ('Settle Selected'), showConsoleDrawer.
- delivery_design_system tokens.dart: DeliveryColors.brand #E11D48, brandSoft #FFF1F2, background #F8FAFC; DeliveryAccent.positive #10B981, caution #F59E0B, critical #EF4444, info #3B82F6; DeliverySpacing, DeliveryRadius.
- The Back Office reconciliation_screen.dart confirmation copy and the age-based accent logic (_floatAccent), ideally lifted into a shared helper.
- statement_models.dart Money (string money) and NetDirection wording rules.

**Strings**

- navReconciliation: 'Reconciliation'
- carrierReconTitle: 'Rider Cash Reconciliation'
- carrierReconSubtitle: 'Match physical cash collections with riders and resolve dues'
- carrierLiveRiders: '{zone} Live ({count} Riders)'
- carrierKpiPendingCollection: 'Total Pending Collection'
- carrierKpiDueFromRiders: 'Due from {count} riders'
- carrierKpiSettledToday: 'Settled Today'
- carrierKpiSettlementsProcessed: '{count} settlements processed'
- carrierKpiDisputedAmount: 'Disputed Amount'
- carrierKpiOpenDisputes: '{count} open dispute claims'
- carrierKpiOverdueCollection: 'Overdue Collection'
- carrierKpiRidersOverLimit: '{count} riders > {hours}h limit'
- carrierRiderBalancesTitle: 'Rider Statements & Balances'
- carrierTodayChip: 'Today: {date}'
- exportCsv: 'Export CSV'
- settleSelected: 'Settle Selected'
- colRiderName: 'Rider name'
- colTotalCollections: 'Total collections'
- colPlatformShare: 'Commission ({pct}%)' (see questions)
- colRiderEarnings: 'Rider earnings'
- colBalanceDue: 'Balance due'
- colLastSettlement: 'Last settlement'
- colStatus: 'Status'
- colActions: 'Actions'
- statusPendingMatch: 'Pending Match'
- statusSettled: 'Settled'
- statusOverdueHours: 'Overdue {hours}h'
- statusDisputed: 'Disputed'
- actionSettle: 'Settle'
- actionView: 'View'
- carrierSettleConfirmTitle: 'Record a hand-over'
- carrierSettleConfirmBody: 'Confirm {name} has handed over {amount} in cash, covering {orders} orders. This clears their whole balance and cannot be undone.'
- carrierSettleAmountChanged: 'This rider collected more cash since you opened the page. Reload and check the amount.'
- carrierNobodyHolding: 'Nobody on your fleet is holding cash right now.'
- Reuse: noCompanyYet, askThePlatformToAttachYou, refresh, cancel, yesterday / relative-time strings (need new: 'Yesterday', '{n} days ago')
- Note: the portal's console screens hard-code English 'in this wave'; these should still go into app_en.arb + app_ar.arb because the brief requires l10n.

**Tests that should prove it**

- Widget test, delivery_portal/test/carrier/reconciliation_screen_test.dart, using the _StubAdapter pattern from statement_screen_test.dart: the page calls /api/accounting/carrier/summary and /riders and never names a company or a rider in the query; the KPIs render the server's strings; overdue and disputed rows get the right pill and red balance; Settle is disabled on a zero balance; Settle opens a confirmation and Cancel sends nothing; Confirm POSTs /carrier/riders/{ref}/handover with expectedAmount; a 409 shows 'the amount changed, reload'; Settle Selected POSTs once per selected rider; 404 shows t.noCompanyYet; the empty fleet state shows; Export CSV produces a header plus one line per rider.
- Widget test, delivery_portal/test/shell: ConsoleTable selection (select all, select one, header state).
- Java, accounting-service api/CarrierReconciliationAccessTest (standalone MockMvc like StatementAccessTest): CARRIER only; BACKOFFICE, DELIVERY and MERCHANT get 403; the company comes from CarrierCompanyClient and never from a request parameter; NoCompanyException gives 403 with its sentence; an Order Manager outage gives 503, not an empty list.
- Java, CashFloatRepository carrier-scope test (a @DataJpaTest like SettlementHealthQueryTest): a rider who moved fleets leaves old cash with the old company; cleared rows are excluded; overdue threshold boundaries hold.
- Java, OrderEventListener/SettlementService test: a carrier COD order writes carrier_ref on the float row; an own-fleet order writes null.
- Java, CashFloatServiceTest: two concurrent remitAll/handover calls produce exactly one remittance and one posting; a stale expectedAmount gives 409.
- Java, migration test: the V50 backfill attributes historical carrier cash from PROVIDER_CREDIT legs.
- API scenario: extend infra/scenario-carrier-delivery.mjs. After the cash delivery, carrier GET /api/accounting/carrier/riders shows the rider owing exactly the order total; a second carrier's token cannot see it; the Back Office /float still lists it.

**Questions**

- CUSTODY MODEL (blocking): today a rider owes the PLATFORM all door cash, and only the Back Office can record a hand-over (ReconciliationController is BACKOFFICE-only, on the principle 'somebody at the platform confirming money physically arrived'). Is the carrier now the intermediate cash holder (rider hands cash to the Libanex hub, and Libanex owes the platform)? That is the HolderKind.PROVIDER path the code anticipates. If not, the carrier page must be read-only and the Settle / Settle Selected / Confirm Settlement buttons cannot exist.
- The design's arithmetic contradicts the ledger. It shows BALANCE DUE = commission (15% of cash) and RIDER EARNINGS = 85% of cash, i.e. the rider keeps the cash minus commission. The backend says the whole collected amount is platform money until remitted (the merchant is paid against it). The carrier earns only the delivery fee less a 10% delivery cut (delivery-commission-percentage default 10; goods commission 12.5%, application.yml:106). What should 'commission' and 'balance due' mean here?
- The commission column is not separable per rider. PLATFORM_COMMISSION blends goods commission and the delivery cut, and the carrier statement already says so ('not separable on orders that also have a shop on them'). Drop the column, or show 'Fee earned for the company' instead?
- Overdue threshold: 48h (design) or 24h (Back Office constant)? Should it be per carrier?
- Disputes: is this v1? Who opens a dispute (carrier, rider, or Back Office) and how is it resolved (write-off by the platform, or the rider repays)?
- The 'Today' date chip: does picking a day scope only collected/earned/settled-today, while the balance due always stays 'as of now'?
- 'Pending Match': what is being matched? There is no bank-matching step for rider cash. Suggest 'Holding cash'.
- Currency: the design uses '$'. The platform currency config defaults to USD. Confirm there is no LBP handling for Lebanon cash.

### `112:235` web-carrier-rider-settlement — L

*Who:* CARRIER-role staff (the operations manager at the hub counter), reached from 'View' on the reconciliation overview.

*What:* The drill-down for one rider: which unsettled cash jobs make up their balance, how the balance adds up, and the action that records the rider handing the cash bag to the company hub, plus a history of past settlements.

*Reached from:* Reached only from 112:9: the row 'View' button, or clicking the rider row. Show it as a full page inside the Reconciliation destination with a back affordance, or as a wide showConsoleDrawer (the design is a full page with the Reconciliation rail item still selected). Deep-linking by riderRef is not needed (the portal rail has no routes). After Confirm Settlement, return to or refresh 112:9.

**Every element, and where its data comes from**

- Topbar 'Rider Settlement Detail' + subtitle 'Reconcile daily cash bag with {riderName}', live badge, bell (same as 112:9).
- Rider header card: 54px initials avatar, name 'Youssef Kanaan', amber badge 'Unsettled Balance' (from outstanding > 0; otherwise 'Settled'), meta line '+961 71 492 813 • Beirut Central • Active since Jan 2026'. Data: name and phone come from the onboarding application (contactName; the phone field may be in the application details, not verified) or from Keycloak via accounting AccountDirectory. The zone comes from application details (CompanyScreen regionOf). 'Active since' comes from the application or joinedOn (CompanyScreen.joinedOn).
- Rating box: star '4.8' + '(142 deliveries)'. Data: OrderApi GET /api/riders/{riderId}/rating (isAuthenticated; average + ratings count) and/or RiderPerformanceApi.forRider(riderId) (CARRIER-scoped to own riders, 30-day window, delivered count). '142' is ambiguous: rating count, or deliveries?
- Left card 'Unsettled Deliveries (Today)': a table with ORDER # (brand link '#YD-9482'), CUSTOMER ('Youssef K.'), TOTAL CASH, COMM %, YOUDROP CUT, RIDER KEEP (green, right-aligned). Data: this rider's outstanding COLLECTED cash_float rows for this company (orderId, amount, createdAt). Customer names are not in accounting; they would come from Order Manager carrier orders (/api/orders/carrier returns OrderResponse; a customer-name field on the response is unverified). COMM % / YOUDROP CUT / RIDER KEEP have no backend equivalent (see questions). '(Today)' is wrong when cash is days old; show a 'collected' date column.
- Right card 'Reconciliation Summary': rows 'Total Cash Collected' $485.00; 'YouDrop Commission (15%)' -$72.75 (dark red); 'Rider Base Bonuses' +$15.00 (green); 'Deductions (Late Penalties)' -$5.00; a divider; 'Net to Rider Keep' $422.25 (brand, 18px); 'Cash Due to Libanex Hub' $72.75 (green, 18px). Only 'Total Cash Collected' has a real source (outstandingTotalFor scoped to the carrier). Bonuses and penalties do not exist anywhere in the backend.
- 'Payout Method' select: pill with banknote icon, 'Cash Handover', chevron. Options unknown. No method field exists on remittances (cash_float has none); RiderCashOut.paidVia is the only precedent ('MANUAL').
- 'Rider PIN / Signature Verification' obscured input '••••'. No rider PIN or signature exists anywhere (no endpoint, no field). Implementing it needs a rider credential the carrier's screen can verify, or a rider-side confirmation in the mobile app.
- Primary button 'Confirm Settlement' (full width). Records the hand-over for the whole outstanding balance. Needs a busy state, a 409 'amount changed' state, and a success SnackBar with the receipt (remittance id, amount, collections), like the Back Office.
- Card 'Settlement History Timeline': brand dots, items like 'Settlement Completed - Oct 23' / '$232.00 Cash handover matching verified by Admin Kamal.' and a final 'Rider Registered' / 'Successfully onboarded as Beirut Central Delivery Partner.' Data: past REMITTED/hand-over rows for this holder (amount, createdAt). 'verified by' needs a recorded_by column that does not exist (remitAll does not record the operator). The 'Registered' item comes from the onboarding application decision.
- Implied states: loading, a rider not on this company's fleet (404), nothing outstanding (summary zeroed and Confirm disabled with 'Nothing to settle'), history empty, error card.

**Existing code that already covers part of it**

- D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/company_screen.dart: _RiderDetail drawer (presence, today, 30-day performance, hours online, application section) and its data class (nameOf, regionOf, joinedOn, deliveredBy). It already joins onboarding applications, performance and tracking for one rider. The shipped shell does not pass performanceApi/trackingApi/onboardingApi (surface-checklist says these blocks are 'UNREACHABLE').
- D:/workspace/delivery/clients/packages/delivery_core/lib/src/api/rider_performance_api.dart: forRider(riderId) GET /api/orders/riders/{riderId}/performance (order-manager RiderPerformanceController: BACKOFFICE or CARRIER, carrier scoped to own riders). Returns Performance(claimed, delivered, cancelledAfterClaim, completionRate, windowDays).
- D:/workspace/delivery/clients/packages/delivery_core/lib/src/api/order_api.dart:253: GET /api/riders/{riderId}/rating. order-manager RiderRatingController.standing is isAuthenticated() and returns StandingResponse(riderId, average, ratings, stars).
- D:/workspace/delivery/services/accounting-service/src/main/java/com/delivery/accounting/domain/CashFloatRepository.java: outstandingFor(holder) (oldest first) and forHolderBetween(holder, kind, from, to) give the rows behind the left table and the history.
- D:/workspace/delivery/services/accounting-service/src/main/java/com/delivery/accounting/service/CashFloatService.java: remitAll(). All or nothing, returns Remittance(id, holderRef, amount, collections), and records no operator or method.
- D:/workspace/delivery/services/accounting-service/src/main/java/com/delivery/accounting/service/StatementService.java:142/255-258: the rider statement ('Cash collected from customers', 'Cash banked', 'Cash paid out to you'). Only the BACKOFFICE route /statements/RIDER/{ref} can build it for someone else.
- D:/workspace/delivery/clients/apps/mobile_app/lib/src/rider_statement_screen.dart: the rider's own 'Reconciliation' view. Its wording rules (debt is caution-coloured, never critical; unknown shown as '—') should carry over.
- D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/reconciliation_screen.dart:45: the _remit() confirmation and receipt SnackBar pattern.
- D:/workspace/delivery/services/accounting-service/src/main/java/com/delivery/accounting/domain/RiderCashOut.java: precedent for a decided_by/paid_via/payment_ref audit trail on a money hand-over.

**Missing in the clients**

- A new widget/page, CarrierRiderSettlementScreen (or a _RiderSettlement drawer), under delivery_portal/lib/src/carrier/. It holds the header card, the outstanding-deliveries ConsoleTable, the summary card, the method ConsoleSelect, the confirmation control and the timeline (ConsoleActivityRow may fit the timeline items).
- CarrierReconciliationApi.riderSettlement(riderRef) and history(riderRef), plus handover(riderRef, expectedAmount, method, note). Models: RiderSettlement (rider, outstanding entries, totals, lastSettledAt), SettlementEvent.
- Pass OnboardingApi, RiderPerformanceApi and OrderApi (rating) into the carrier area so the header can be filled. Or have the new accounting endpoint return name/phone and skip the client joins.
- If a PIN is kept: an obscured 4-digit field (the design system has YdOtpCells in yd_otp_cells.dart for mobile; on the portal a TextField obscureText, maxLength 4).

**Missing in the backend**

- accounting-service: GET /api/accounting/carrier/riders/{riderRef}/settlement returns 404 unless the rider has cash_float rows with carrier_ref = the caller's company or is on /my-company/riders. Response: rider name (AccountDirectory), outstanding entries (orderId, amount, collectedAt), totals as 2dp strings, lastSettledAt.
- accounting-service: GET /api/accounting/carrier/riders/{riderRef}/history returns hand-over/remittance rows (amount, at, recordedBy name, method, collections covered).
- accounting-service, migration: ADD recorded_by varchar(64), handover_method varchar(24), note text on cash_float REMITTED/TRANSFERRED rows. Or a new cash_handover table (id, holder_ref, carrier_ref, amount, method, recorded_by, verified_by_rider_at, created_at) that links to the remittance id. The Back Office remit should also start recording who did it.
- accounting-service: POST /api/accounting/carrier/riders/{riderRef}/handover {expectedAmount, method, note}, following the custody decision in 112:9, with the remitAll locking fix.
- If rider verification is required: no PIN exists. Options are (a) a rider-side confirm in the mobile rider app (a notification plus POST /api/rider/handovers/{id}/confirm, DELIVERY role, token subject must equal the holder) or (b) a rider PIN stored hashed in onboarding-service/Keycloak attributes and a verify endpoint. (a) fits the platform's 'the token decides' rule better.
- Bonuses/deductions (only if product wants them): there is no bonus or penalty engine. RiderLedgerEntry.EntryType.ADJUSTMENT exists but has no writer or endpoint, and adjustments are platform-payable, not carrier-payable.

**Design-system pieces to reuse**

- ConsoleCard, ConsoleAvatar (54px initials), ConsoleStatusPill ('Unsettled Balance' caution), ConsoleTable (compact, 6 columns, 16px padding), ConsoleSelect/ConsoleOption (payout method), ConsolePrimaryButton (full width), ConsoleActivityRow (timeline), ConsoleSectionLabel ('Payout Method', 'Rider PIN / Signature Verification').
- tokens: DeliveryColors.brand for order links and 'Net' figure, DeliveryAccent.positive for 'Rider keep' / 'Cash due', critical for deductions.
- CompanyScreen's rider data joins (nameOf/regionOf/joinedOn) and _RiderDetail performance/rating loading. Extract them into a shared carrier rider-profile loader rather than duplicating.
- The Back Office _remit dialog copy and the Remittance receipt model (accounting_models.dart).

**Strings**

- carrierSettlementTitle: 'Rider Settlement Detail'
- carrierSettlementSubtitle: 'Reconcile daily cash bag with {name}'
- badgeUnsettledBalance: 'Unsettled Balance'
- riderMetaLine: '{phone} • {zone} • Active since {month}'
- riderRatingDeliveries: '({count} deliveries)'
- unsettledDeliveriesTitle: 'Unsettled Deliveries' (drop '(Today)' or make it '(since {date})')
- colOrderNumber: 'Order #'
- colCustomer: 'Customer'
- colTotalCash: 'Total cash'
- colCommPct: 'Comm %'
- colYouDropCut: 'YouDrop cut'
- colRiderKeep: 'Rider keep'
- reconSummaryTitle: 'Reconciliation Summary'
- summaryTotalCashCollected: 'Total Cash Collected'
- summaryCommission: 'YouDrop Commission ({pct}%)'
- summaryBaseBonuses: 'Rider Base Bonuses'
- summaryDeductions: 'Deductions (Late Penalties)'
- summaryNetToRider: 'Net to Rider Keep'
- summaryCashDueToHub: 'Cash Due to {company}'
- payoutMethodLabel: 'Payout Method'
- payoutMethodCashHandover: 'Cash Handover'
- riderPinLabel: 'Rider PIN / Signature Verification'
- confirmSettlement: 'Confirm Settlement'
- settlementHistoryTitle: 'Settlement History Timeline'
- historySettlementCompleted: 'Settlement Completed - {date}'
- historySettlementDetail: '{amount} Cash handover matching verified by {name}.'
- historyRiderRegistered: 'Rider Registered'
- historyRiderRegisteredDetail: 'Successfully onboarded as {zone} Delivery Partner.'
- nothingToSettle: 'Nothing to settle — this rider is holding no cash.'
- settlementRecorded: 'Recorded {amount} from {name}.'

**Tests that should prove it**

- Widget test, carrier/rider_settlement_screen_test.dart: the header renders name, zone, rating and deliveries from stubbed responses; '—' when rating or performance fail (never 0.0); the table lists the outstanding entries with a collected date; Confirm is disabled when outstanding is 0; Confirm POSTs handover with expectedAmount equal to the displayed total and the chosen method; 409 shows the changed-amount message and reloads; success shows the receipt and adds a timeline item; the history is newest first; 'Registered' comes from the application.
- Java: CarrierRiderSettlementAccessTest. Another company's rider gives 404 (not 403, following /my-company semantics); the company is never taken from a parameter; DELIVERY/MERCHANT get 403.
- Java: handover service test. It clears exactly the rows present at expectedAmount; cash collected concurrently stays outstanding; recorded_by and method are persisted; idempotent on double submit.
- Java: StatementService test. After a custody transfer the rider statement shows the cash as handed to the company, the carrier statement shows the cash it holds, and both still balance (StatementRangeAndBalanceTest pattern).
- API scenario: in infra/scenario-carrier-delivery.mjs, the carrier records a hand-over for its rider; the rider's /statements/mine shows the hand-over; the Back Office /float shows the company (PROVIDER) as holder.

**Questions**

- The summary maths contradicts backend rules. 'Net to Rider Keep' ($422.25) means the rider keeps most of the cash; 'Cash Due to Libanex Hub' ($72.75) means the hub only receives commission. In the ledger the rider owes the whole $485 to the platform, and the merchant's share is paid against it. The rider's pay from a carrier is the carrier's own employment matter (PayableBy.CARRIER, 'shown and never paid'). What does the carrier actually collect at the counter?
- Bonuses and late-penalty deductions: who defines them, and are they the carrier's HR terms (then they belong to payroll 112:1162, not the cash reconciliation) or platform rules?
- Rider PIN/signature: carrier staff typing a rider's PIN on the carrier's own screen proves little. Is a rider-app confirmation acceptable instead? Which service owns a rider PIN, if one is required?
- Payout Method options besides 'Cash Handover' (bank deposit, OMT/Whish wallet)? Does any option trigger a real transfer, or are they all recorded-only (the ManualPayoutProvider precedent)?
- Partial settlement: the backend settles all or nothing (CashFloatService.remitAll). Must the counter support 'rider handed $300 of $485'? That needs partially-cleared collections, which the model explicitly does not support.
- Should carrier staff see customer names on orders (privacy)? The order short id may be enough.

### `112:1162` web-carrier-rider-payroll — XL

*Who:* CARRIER-role staff acting as the company's HR or payroll function. Reached from the 'Riders HR' rail item in the design.

*What:* The delivery company's own payroll for the riders it employs. Per pay period (bi-weekly in the design) it computes base pay, delivery bonus, tips and deductions into gross and net pay per rider, tracks payment status, produces payslips, and processes payments in bulk.

*Reached from:* The design puts it under the 'Riders HR' rail item, which the shipped portal does not have (the fleet page is 'Company', titled 'Riders Management', plus 'Applicants'). Options: (a) a new PortalDestination 'Payroll' (Icons.groups_2 / payments) placed after Company; or (b) a 'Payroll' tab inside CompanyScreen using its existing ConsoleFilterTabs. Either way, keep Jobs at index 1 for the dashboard's jump(1). 'Payslip' opens a drawer or a new browser tab.

**Every element, and where its data comes from**

- Topbar 'Rider Payroll & Earnings Management' + subtitle 'Approve payouts, calculate bonuses, and track payouts history', live badge, bell.
- Period picker 'Pay Period: October 1 - October 15, 2026' with a calendar icon and a chevron (dropdown of bi-weekly periods). Data: the carrier's pay calendar (does not exist). Could reuse a date-range picker like CarrierStatementScreen._pickPeriod; StatementsApi.maxRangeDays shows the range-guard pattern.
- Button 'Export Payslips' (outlined, download). No payslip rendering or export exists. StatementRenderer in accounting-service renders statements and might be adaptable.
- Button 'Process All Payments' (primary, check icon). No payment rail exists for carrier→rider pay. The platform never pays carrier riders (PayableBy.CARRIER).
- KPI 'TOTAL PAYROLL POOL' $12,450.00 / 'October first half' = sum of net pay for the period.
- KPI 'RIDERS ON PAYROLL' '28 Riders' (brand colour) / 'Active payroll accounts' = riders with a payslip in the period (/my-company/riders gives the roster).
- KPI 'AVERAGE RIDER EARNINGS' $445.00 / 'Per 15-day cycle' = pool / riders.
- KPI 'PAID OUT BONUSES' $890.00 (green) / 'Based on delivery speeds'. There is no delivery-speed bonus engine. Order Manager has timing data (CarrierScore timeToClaim/timeOnTheRoad) but no per-rider bonus rule.
- Table 'Rider Bi-Weekly Payroll Ledger' with columns RIDER NAME (avatar + name) | BASE PAY | DELIVERY BONUS (green) | TIPS | DEDUCTIONS (dark red, negative) | GROSS PAY (= base + bonus + tips in the design) | NET PAY (bold, = gross − deductions) | STATUS | ACTIONS.
- Status pills: 'Processing' (amber), 'Paid ✓' (green), 'Failed' (red). 'Failed' implies an automated disbursement that can fail; none exists.
- Row action 'Payslip' (outlined). Opens or downloads one rider's payslip.
- Implied states: loading; no company (404); no riders; period not yet run ('Draft' / 'Not processed'); a confirmation dialog for Process All Payments (irreversible); per-row failure reason.

**Existing code that already covers part of it**

- D:/workspace/delivery/services/accounting-service/src/main/java/com/delivery/accounting/domain/RiderLedgerEntry.java: JOB_EARNING rows on carrier fleets are PayableBy.CARRIER and Fleet.CARRIER, with carrier_ref, and the amount is what the platform paid the company for that job. TIP rows belong to the rider even on a carrier fleet (PLATFORM-payable online, IN_HAND cash). ADJUSTMENT exists and nothing writes it.
- D:/workspace/delivery/services/accounting-service/src/main/resources/db/migration/accounting/V46__rider_earnings.sql: idx_rider_ledger_carrier ('for the company that has to pay its own riders'). The index is ready, but RiderLedgerRepository has no carrier_ref query.
- D:/workspace/delivery/services/accounting-service/src/main/java/com/delivery/accounting/service/RiderEarningsService.java: per-rider statement(), recentJobs(), DayTotal/Total (earnings, tips, jobs). Scoped to one rider by token; nothing is carrier-scoped.
- D:/workspace/delivery/services/accounting-service/src/main/java/com/delivery/accounting/payout/RiderPayoutProvider.java + ManualPayoutProvider.java: the payout abstraction. Only MANUAL exists, and it is for platform→rider cash-outs.
- D:/workspace/delivery/clients/packages/delivery_core/lib/src/api/rider_money_api.dart + models/rider_money_models.dart: RiderJob (earned, tip, reimbursement, payableBy), CashOut (status REQUESTED/PAID/REJECTED). These are self-service rider and Back Office endpoints, not carrier ones.
- D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/earnings_screen.dart: company-level earnings (earned vs expected, cut %) from order-manager /api/orders/carrier/earnings. Not per rider.
- D:/workspace/delivery/services/order-manager/src/main/java/com/delivery/order/api/RiderPerformanceController.java: CARRIER-scoped per-rider delivered counts (/delivered-today, /{riderId}/performance). The input for any per-delivery bonus.
- D:/workspace/delivery/services/accounting-service/src/main/java/com/delivery/accounting/service/StatementRenderer.java + StatementDispatchService.java: existing statement rendering and email dispatch. A candidate base for payslip rendering and email.
- D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/company_screen.dart: the fleet roster and rider names (application contactName).

**Missing in the clients**

- A new screen, delivery_portal/lib/src/carrier/payroll_screen.dart (CarrierPayrollScreen): a period ConsoleFilterButton or ConsoleSelect of periods, a 4-card ConsoleKpiRow, a 9-column ConsoleTable (minWidth about 1100), the Export Payslips / Process All Payments buttons, and a Payslip row action (openExternalLink to a signed URL, or a drawer preview).
- A new delivery_core CarrierPayrollApi with models: PayPeriod, PayrollRun (status), Payslip (base, bonus, tipsInfo, deductions, gross, net, status, failureReason) and PayrollAdjustment. Amounts use the Money string type.
- A 'Process All Payments' confirmation dialog (irreversible, shows the total and rider count), plus a per-row mark-paid / mark-failed action if payments are recorded manually.
- Optional (v1 read-only alternative): a CarrierRiderEarningsScreen showing per-rider jobs and fee earned for the period from rider_ledger carrier_ref, with tips shown for information only.

**Missing in the backend**

- DECISION FIRST, the scope. The platform explicitly does not know or pay carrier employment terms (RiderLedgerEntry.PayableBy.CARRIER: 'the platform has never been shown' the contract). A full payroll is a new product area. A read-only per-rider earnings report is small.
- v1 (read-only, M): accounting-service GET /api/accounting/carrier/riders/earnings?from&to (CARRIER; company via CarrierCompanyClient) returns per rider: jobs, feeEarnedForCompany (sum of JOB_EARNING, fleet CARRIER, carrier_ref), tipsOnline and tipsInHand (informational), cashStillHeld (float). Needs new RiderLedgerRepository queries on carrier_ref (index exists) and names via AccountDirectory.
- Full payroll (XL), new tables in accounting-service (or a new carrier-HR service; accounting is the money owner and already deployed): carrier_pay_policy(carrier_ref, period_kind BIWEEKLY|MONTHLY, base_pay, currency, bonus_rule jsonb), carrier_pay_run(id, carrier_ref, period_from, period_to, status DRAFT|LOCKED|PROCESSING|PAID|PARTIAL, created_by, locked_at), carrier_payslip(id, run_id, rider_ref, base, bonus, deductions, gross, net, status PENDING|PAID|FAILED, paid_via, payment_ref, failure_reason, decided_by, decided_at; unique(run_id, rider_ref)), carrier_pay_adjustment(id, run_id, rider_ref, kind BONUS|DEDUCTION, amount, reason, created_by).
- Full payroll endpoints (CARRIER-only, company from token): GET/PUT /api/accounting/carrier/payroll/policy; GET /payroll/periods; GET /payroll?from&to (preview, computed live); POST /payroll/runs (lock a period); POST /payroll/runs/{id}/process (records payment via a carrier payout provider; manual today); POST /payroll/payslips/{id}/paid|failed; POST /payroll/runs/{id}/adjustments; GET /payroll/payslips/{id} (HTML/PDF via a StatementRenderer-style renderer); GET /payroll/runs/{id}/export (CSV or zip).
- Bonus 'based on delivery speeds': needs per-delivery timing per rider from order-manager (claim→delivered durations). A new CARRIER-scoped endpoint such as GET /api/orders/riders/{riderId}/timings?from&to, or reuse RiderPerformanceService with a window parameter.
- Deductions/late penalties: no source of 'late' events per rider. A definition of late and a data source in order-manager or order-tracking are needed.

**Design-system pieces to reuse**

- ConsolePage/ConsoleTopbar, ConsoleFilterButton (period), ConsoleKpiRow/ConsoleKpiCard, ConsoleTable + ConsoleNameCell/ConsoleAvatar, ConsoleStatusPill (caution 'Processing', positive 'Paid', critical 'Failed'), ConsoleSoftButton ('Payslip', 'Export Payslips'), ConsolePrimaryButton ('Process All Payments'), showConsoleDrawer (payslip preview).
- CarrierStatementScreen's date-range picker and range-guard SnackBar; statement_models.dart Money; the RiderCashOut state machine as the model for payslip status.
- accounting-service StatementRenderer/StatementDispatchService for payslip rendering and emailing.

**Strings**

- navPayroll: 'Payroll' (or navRidersHr: 'Riders HR')
- carrierPayrollTitle: 'Rider Payroll & Earnings Management'
- carrierPayrollSubtitle: 'Approve payouts, calculate bonuses, and track payouts history'
- payPeriodLabel: 'Pay Period: {from} - {to}'
- exportPayslips: 'Export Payslips'
- processAllPayments: 'Process All Payments'
- kpiTotalPayrollPool: 'Total Payroll Pool'
- kpiPeriodHalf: '{month} first half' / '{month} second half'
- kpiRidersOnPayroll: 'Riders on Payroll'
- kpiRidersCount: '{count} Riders'
- kpiActivePayrollAccounts: 'Active payroll accounts'
- kpiAverageRiderEarnings: 'Average Rider Earnings'
- kpiPerCycle: 'Per {days}-day cycle'
- kpiPaidOutBonuses: 'Paid Out Bonuses'
- kpiBonusesBasis: 'Based on delivery speeds'
- payrollLedgerTitle: 'Rider Bi-Weekly Payroll Ledger'
- colBasePay: 'Base pay'
- colDeliveryBonus: 'Delivery bonus'
- colTips: 'Tips'
- colDeductions: 'Deductions'
- colGrossPay: 'Gross pay'
- colNetPay: 'Net pay'
- statusProcessing: 'Processing'
- statusPaid: 'Paid'
- statusFailed: 'Failed'
- actionPayslip: 'Payslip'
- processAllConfirmTitle: 'Pay {count} riders {total}?'
- processAllConfirmBody: 'This records every payslip in this period as paid. It cannot be undone.'
- payrollEmptyPeriod: 'Nobody on your fleet worked in this period.'

**Tests that should prove it**

- Widget test, carrier/payroll_screen_test.dart: the period picker refetches with from/to and names no company; the KPIs match the table (pool = sum of net, average = pool / riders); gross = base + bonus (+ tips only if product keeps them) and net = gross − deductions render exactly as the server's strings; the status pills map correctly; Process All Payments confirms first, and Cancel sends nothing; a Failed row shows its reason; Payslip opens the signed URL; the empty period state; 404 shows no company.
- Java, accounting-service CarrierPayrollAccessTest: CARRIER only; a company can never read another's riders; the preview never includes rows where carrier_ref differs; TIP rows that are PLATFORM-payable are never counted into carrier-payable net pay (the double-pay guard the ledger was built around).
- Java, payroll run test: locking a period is idempotent (unique run per carrier and period); a payslip moves PENDING→PAID once only (like RiderCashOut.markPaid); adjustments after lock are refused or create a new revision.
- Java, RiderLedgerRepository carrier query test (@DataJpaTest): per-rider earnings for a carrier across a period boundary use earned_at, not created_at.
- API scenario: extend infra/scenario-carrier-delivery.mjs. After the delivered carrier job, GET /api/accounting/carrier/riders/earnings for the period lists the rider with 1 job and the PROVIDER_CREDIT amount.

**Questions**

- Is YouDrop offering payroll to carriers at all? The ledger's founding rule is that a carrier rider's pay is the carrier's private employment contract (PayableBy.CARRIER, 'shown and never paid'). Would payroll be record-keeping only (the carrier pays offline and marks paid), or a real disbursement? 'Failed' status and 'Process All Payments' imply a payment rail the platform does not have.
- TIPS in gross pay contradict the ledger. Tips belong to the rider and are either already in hand (cash) or paid by the platform (online), even on a carrier fleet. Adding them to carrier-paid gross would pay them twice. Show tips for information only and outside net pay?
- Where do base pay, the bonus rule ('based on delivery speeds') and deductions ('late penalties') come from? Is there a per-carrier policy screen (not in this cluster's frames)? What counts as 'late'?
- Pay calendar: fixed bi-weekly (1–15, 16–end), or carrier-configurable?
- Should cash a rider still holds (112:9) be deducted from net pay automatically? Many cash-heavy fleets net it; the platform's ledger would then need the carrier to have custody (see 112:9 custody question).
- Payslip format (PDF vs HTML) and legal content for Lebanon (employer details, NSSF)? Is Arabic required on the payslip?
- Minimum viable scope: would a read-only 'rider earnings by period' page (v1, size M) satisfy the need while payroll is decided?

**Build order for this cluster**

- 0. Get product decisions before building any settle or payroll write paths: (a) custody model: may carriers take cash from their riders (HolderKind.PROVIDER) or is the carrier view read-only; (b) what 'commission' / 'balance due' mean given the whole collected amount is platform money; (c) disputes in v1 or not; (d) payroll scope: read-only earnings report vs real payroll; (e) overdue threshold (48h vs 24h).
- 1. accounting-service V50 migration: add carrier_ref (plus recorded_by, handover_method, note) to cash_float, with a partial index; OrderEventListener/SettlementService.CashHolder write carrier_ref for carrier cash orders; backfill from PROVIDER_CREDIT counterparty_ref. Cover with repository and listener tests.
- 2. Fix the CashFloatService.remitAll concurrency race (pessimistic lock on outstanding rows) and start recording recorded_by on Back Office remits. Existing Back Office behaviour otherwise stays unchanged.
- 3. accounting-service CarrierReconciliationController, read-only: GET /carrier/summary, GET /carrier/riders, GET /carrier/riders/{ref}/settlement, GET /carrier/riders/{ref}/history. CARRIER + requireRole, company from CarrierCompanyClient, names via AccountDirectory, money as 2dp strings, overdue-after-hours from config. Add access tests.
- 4. delivery_core CarrierReconciliationApi + models (Money-based) with unit tests for parsing.
- 5. Portal: extend ConsoleTable with row selection (shell test), then build carrier/reconciliation_screen.dart read-only (KPIs, table, View) and add the 'Reconciliation' rail item after Statement. Add ARB keys en+ar and widget tests.
- 6. Portal: rider settlement detail (112:235) read-only (header from rating/performance/applications or the server name, outstanding table, history), reusing CompanyScreen's rider loaders extracted into a shared helper.
- 7. If custody is approved: widen chk_float_kind/uq_float_order for TRANSFERRED/PROVIDER rows; add POST /carrier/riders/{ref}/handover with expectedAmount (409 on drift); add statement lines for rider and carrier; then enable Settle, Settle Selected and Confirm Settlement in the UI with confirmation dialogs. Add the API scenario step to infra/scenario-carrier-delivery.mjs.
- 8. CSV export (server text/csv or client Blob helper next to external_link_web.dart).
- 9. Disputes (entity, endpoints, KPI, 'Disputed' pill), only if approved. Otherwise remove the KPI and pill from v1.
- 10. Payroll v1: GET /carrier/riders/earnings?from&to from rider_ledger carrier_ref (index already exists), with tips informational only, and a read-only portal page under a 'Payroll' item or a Company tab.
- 11. Full payroll (policy, runs, payslips, adjustments, manual processing, payslip rendering), only after step 0(d) approves it.

**Cross-cutting**

- Screenshots saved (1440x1000): D:/dev-cache/temp/claude/D--workspace-azkar/709fbe40-df14-4950-b9b5-9dbd338df9ab/scratchpad/figma/112-9_web-carrier-reconciliation-overview.png, .../112-235_web-carrier-rider-settlement.png, .../112-1162_web-carrier-rider-payroll.png
- Biggest contradiction: all three frames assume the carrier sits between the rider's cash and the platform, and that riders keep cash minus commission. The accounting-service rules are: every note taken at the door is a RIDER-held obligation to the PLATFORM (OrderEventListener:139-145); only the Back Office can record a hand-over (ReconciliationController is BACKOFFICE-only by design); the carrier is paid the delivery fee less a 10% cut via PROVIDER_CREDIT; the carrier's riders are paid by the carrier under a contract the platform never sees (PayableBy.CARRIER). The HolderKind.PROVIDER hook exists for exactly this, but it is unused and blocked by uq_float_order UNIQUE(order_id, entry_kind).
- The commission shown as 15% matches no config: goods commission is 12.5% (application.yml:106) and the delivery cut is 10% (SettlementService default). The platform's cut on a carrier order is not separable per order (see the carrier statement note), so any 'commission' column must come from the server or be dropped.
- Scoping rule for every new carrier route: the company is resolved from the caller's token via CarrierCompanyClient.companyIdFor (Order Manager /my-company). Never take a company id from the path. Use a 404 for a rider not on the caller's fleet. Use the double role check (@PreAuthorize + requireRole) as in StatementController. Map an Order Manager outage to 503, never to an empty list.
- Money on the wire: follow StatementController (2dp strings, the Money model in statement_models.dart). ReconciliationController and RiderEarningsController return raw BigDecimal numbers; do not copy that into new carrier endpoints.
- Carrier console chrome in the design differs from the shipped portal: an 8-item rail (Dashboard, Orders, Fleet, Reconciliation, Riders HR, Earnings, Coverage, Settings) vs 7 items (Dashboard, Jobs, Earnings, Statement, Company, Applicants, Settings); 'CARRIER BACKOFFICE' vs the 'Carrier Hub' wordmark; the carrier pill with hub and ID; a job title instead of the access role. Coverage/zones exist only in the mobile CarrierZonesScreen. Out of scope, but it needs a decision so these three pages are not built against a rail nobody plans to ship.
- Rider identity: carrier-facing endpoints return rider refs only (/my-company/riders gives List<String>). Names come from onboarding applications (CompanyScreen.nameOf), which fall back to a short ref for riders attached directly. accounting AccountDirectory.profileOf (Keycloak) is the better source for a server-built reconciliation row.
- The live badge ('Beirut Live (34 Riders)') and the bell appear on every frame. The carrier PortalArea passes neither TrackingApi nor NotificationApi, and every carrier page draws an inert bell even though ConsoleBell is now exported from shell/shell.dart.
- l10n: portal console screens hard-code English 'in this wave' (portal_shell.dart comments; 'Statement' has no key). This cluster should add proper app_en.arb/app_ar.arb keys (packages/delivery_l10n/lib/l10n). Existing reusable keys: noCompanyYet, askThePlatformToAttachYou, refresh, navEarnings, earningsTitle, riderStatement*.
- Deployment: everything needed is in accounting-service and order-manager, both deployed on dev. There is no dependency on the undeployed pos-service or inventory-service.
- Risk: the existing remitAll race (no row lock) can double-record a remittance and its CASH_REMITTANCE posting under concurrent clicks. Exposing Settle and Settle Selected to carriers makes that far more likely, so fix it first.
- No CSV, PDF or download facility exists in the portal or accounting-service. The only external-open helper is openExternalLink (shell/external_link_web.dart). Payslips and CSV need new plumbing.
- Test infrastructure to reuse: portal widget tests use a Dio _StubAdapter (test/carrier/statement_screen_test.dart); accounting API tests use standalone MockMvc (api/StatementAccessTest.java); service tests are in accounting/service (CashFloatServiceTest, RiderCounterpartyStatementTest, CarrierAndPlatformStatementTest); live API scenarios are node scripts in infra/ (scenario-carrier-delivery.mjs).

## Customer: gift hub and gift checkout (Figma 112:1684 customer-gift-hub, 112:1830 customer-gift-checkout)

### `112:1684` customer-gift-hub — L

*Who:* Customer (diaspora sender, usually outside Lebanon, paying for goods delivered to family in Lebanon). Mobile app, customer shell.

*What:* The landing page for sending a gift. It explains the promise (real essentials delivered the same day) and gives the sender four ways in: browse gift categories, reuse a recent recipient, pick a curated care bundle, or start from the how-it-works steps. It replaces the dead DiasporaScreen ('Send to Lebanon'), which no code path can reach today.

*Reached from:* Customer shell -> Home tab (StoreHomeScreen) -> new 'Send a gift' entry card (and ProfileDrawer -> 'Send a gift' row) -> Navigator.push(GiftHubScreen) over the shell. From the hub: category card -> ShopsListingScreen(initialVertical) -> StorePageScreen -> basket; recipient card -> recipient becomes the active address; bundle row -> ProductDetailScreen or add to cart -> Basket tab (CustomerShell._openBasket) -> GiftCheckoutScreen (112:1830). Back pops to Home. The drawn bottom nav (Home/Shops/Orders/Butler/Account) is not the shipped CustomerNavBar (Home/Butler/Basket/Orders/Account); keep the shipped bar.

**Every element, and where its data comes from**

- Screen header (white, bottom border #E2E8F0): round back button (#F8FAFC circle, 18px arrow-left) calls Navigator.maybePop; title 'Send a Gift' (Rubik Bold 18, ink); subtitle 'Diaspora Gifting Portal' (Medium 12, muted); trailing YouDrop logo chip (brandSoft pill with an 8px brand dot and You+Drop wordmark). Data: static l10n. YdScreenHeader already supports title, subtitle and trailing.
- Hero banner (16px margin, radius 16, 20px padding, full-bleed photo with a 40% black overlay): title 'Remittance Made Real' (ExtraBold 20, white) and body 'Support your loved ones in Lebanon. Choose real essentials, groceries, or hot meals delivered same-day.' (Medium 13, line height 18, white). Data: a bundled asset image plus l10n. Not tappable in the design. Alternative: feed it from BannerApi.live(), but there is no banner placement or slot concept, so a static asset is the honest v1.
- HOW IT WORKS section: uppercase label (Bold 14) over a white bordered card (radius 16, 16px padding, 12px gap) with three rows. Each row has a 28px brandSoft circle holding the step number in brand Bold 14, a title (Bold 13, ink) and a body (Regular 11, muted). Steps: 1 'Choose from local shops' / 'Select fresh groceries, sweets, pharmacy items or custom butler orders.'; 2 'Enter Lebanese address' / 'Deliver anywhere in Beirut, Tripoli, Sidon or Mount Lebanon.'; 3 'Same-day delivery' / 'Our reliable riders deliver with a beautifully printed custom note.' Static, not interactive. See questions: step 2 promises coverage and step 3 promises printing, and the product does neither.
- GIFT CATEGORIES: uppercase label, then a horizontal scroller of 100px-wide white cards (radius 16, 1px border, a 2px shadow at 2% opacity, 12px padding, 8px gap). Each card has a 40px image (radius 8) over a SemiBold 11 centered label. Five cards: Care Package, Groceries, Sweets & Pastries, Baby & Kids, Medicine & Health. Tapping one opens a filtered shop listing. Data: there is no gift taxonomy. The closest source is StoreVertical (RESTAURANT, COFFEE, GROCERY, CONVENIENCE, PHARMACY, ELECTRONICS, FLOWERS_GIFTS) and GET /api/categories/chips (CategoryChip: id, name, vertical, imageUrl). Proposed v1 mapping, done client-side: Groceries -> GROCERY; Medicine & Health -> PHARMACY; Care Package -> FLOWERS_GIFTS; Baby & Kids -> PHARMACY plus a 'baby' search (the seed tags CareFirst with 'Baby'); Sweets & Pastries -> RESTAURANT/COFFEE plus a 'sweets' search. Each tap pushes ShopsListingScreen(initialVertical: ...). Images: bundled assets, or CategoryChip.imageUrl where the vertical matches.
- RECENT RECIPIENTS: uppercase label, then cards (white, radius 12, 1px border, 12px padding). Each has a 36px brandSoft circle with brand Bold 12 initials, a name (Bold 13) and an area (Regular 11 muted). Samples: Teta Layla/Beirut, Cousin Rami/Tripoli, Mom/Mar Mikhael. The design lays three flex cards in one row and the text overflows ('Cousin Ra'), so build it as a horizontal scroller. Tapping a card makes that recipient active (DeliveryAddressStore.select) and remembers them for gift checkout. Data: no recipient entity exists. v1 source: DeliveryAddressStore.recents (device-local secure storage, per Keycloak sub, capped at 5), with label as the person's name and zoneName as the area. This is DiasporaScreen's model. Initials: the StoreMonogram widget DiasporaScreen already uses, or a small initials avatar.
- Implied empty state for recipients (not drawn): no labelled saved address yet, so show an 'Add a recipient' card that opens showAddressSheet(context, addresses, zoneApi:, geocodingApi:). Existing copy: custNoRecipientYet.
- FEATURED CARE BUNDLES: uppercase label, then full-width rows (white, radius 16, 1px border, 12px padding, 12px gap). Each row has a 64px image (radius 12); name (Bold 14 ink) and USD price (Bold 14 brand, e.g. $45/$30/$25) justified apart; a description (Regular 11 muted); and a 6px green dot with 'Same-day Deliverable' (SemiBold 10, #10B981). Samples: Family Essentials $45, Lebanese Breakfast $30, Sweet Treats $25. Tapping a row opens the product (ProductDetailScreen) or adds it to the cart and goes to gift checkout. Cart is one-store only, so a bundle from a second shop hits Cart.conflictsWith and needs the existing 'discard and start here' flow. Data: no bundle concept exists anywhere in the repo. It needs a new curated-products endpoint (see missingBackend). 'Same-day Deliverable' has to be derived from the store's availability (open now, and eta_max_minutes before closing), not hard-coded. An LBP secondary price is optional via MarketRates.instance.lbpParen(usd).
- Loading, empty and error states (implied, not drawn): the recipients and bundles sections each load on their own. Show skeleton cards while loading. If the bundles call fails, hide the section silently, as DiasporaScreen._loadRecent and the rest of the app do. Hide the section when the list is empty.
- Bottom navigation (drawn with Home active; tabs Home, Shops, Orders, Butler, Account): this does NOT match the shipped CustomerNavBar (homeIndex 0, butlerIndex 1, basketIndex 2, ordersIndex 3, accountIndex 4, with no Shops tab). Keep the real bar. The hub is a route pushed over the shell, as DiasporaScreen and every other customer detail screen are, so the bar is normally hidden. The nav in this frame is design chrome, not a new requirement.

**Existing code that already covers part of it**

- clients/apps/mobile_app/lib/src/diaspora_screen.dart: the 'Send to Lebanon' v1. Recipient = saved address labelled with the person's name (showAddressSheet), personal note up to 240 characters written to cart.giftNote, 'recent deliveries to X' from OrderApi.mine(size:30) matched on deliveryAddress, and a Start Order CTA that selects the address, pops and calls onStartOrder. Zero call sites, so it is UNREACHABLE (docs/surface-checklist.md:2077-2088).
- clients/apps/mobile_app/lib/src/cart.dart: Cart.giftNote (line 190) is the order-scoped gift note, cleared by clear(). The basket is locked to one store (conflictsWith/switchTo). Cart.waiver/deliveryIsFree come from OfferApi.preview.
- clients/apps/mobile_app/lib/src/delivery_address.dart: DeliveryAddress(line, label, notes, zoneId, zoneName, latitude, longitude). No phone field. DeliveryAddressStore: device-local, keyed per sub, _maxRecents = 5.
- clients/apps/mobile_app/lib/src/address_sheet.dart: showAddressSheet(context, store, {zoneApi, geocodingApi}), with Home/Work/Other label chips (Other allows a free-text label, i.e. the recipient's name), area picker, place search and map pin.
- clients/apps/mobile_app/lib/src/store_home_screen.dart: _openListing(vertical) pushes ShopsListingScreen(storeApi, orderApi, cart, initialVertical, chips, onOpenBasket). _openBanner handles only STORE and CATEGORY; URL banners are ignored (line ~1100). The FriendSplitScreen push at line ~513 is the pattern for pushing a feature screen from Home.
- clients/apps/mobile_app/lib/src/shops_listing_screen.dart and category_strip.dart: vertical-filtered listing and vertical cards.
- clients/apps/mobile_app/lib/src/customer_shell.dart: owns _cart and _addresses and exposes _open(tab) and _openBasket(). This is where the hub's onStartOrder/onOpenBasket callbacks get wired.
- clients/apps/mobile_app/lib/src/profile_drawer.dart: YdListRow menu (Notifications, Help, and so on) where a 'Send a gift' row can be added.
- clients/packages/delivery_core/lib/src/api/store_api.dart: browseWith(StoreFilters) (vertical, search, neighborhood, and so on), categoryChips() -> GET /api/categories/chips, banners(), products(storeId), read(idOrSlug).
- clients/packages/delivery_core/lib/src/models/store_models.dart: StoreVertical enum including flowersGifts('FLOWERS_GIFTS'), CategoryChip, StoreFilters, HomeBanner/BannerLinkKind (none, store, category, url).
- clients/packages/delivery_core/lib/src/util/market_rates.dart: MarketRates.instance.lbp(usd)/lbpParen(usd), rounded to 1000 LBP, and null when there is no rate.
- services/product-service/src/main/resources/db/migration/product/V11__stores.sql (chk_store_vertical includes FLOWERS_GIFTS) and V12__demo_storefront.sql (seeds 'Bloom & Wrap' FLOWERS_GIFTS with products Seasonal Bouquet, Dozen Red Roses, Orchid Plant and a $6 'Gift Wrapping' product; the store is deliberately outside its hours).
- services/product-service/.../api/BannerController.java: GET /api/banners, GET /api/categories/chips, PUT /api/categories/{id}/vertical.
- clients/packages/delivery_l10n/lib/l10n/app_en.arb:1955-1968 (app_ar.arb:1427-1440): custDiasporaTitle 'Send to Lebanon', custDiasporaSub 'Diaspora Gifting Portal', custDiasporaBanner 'Remittance made real', custDiasporaBlurb, custFamilyRecipient, custPersonalNote, custPersonalNoteHint, custWhatToSend (unused), custRecentDeliveriesTo, custStartOrder (BUG: English reads 'Select Items 0026 Start Order'), custPickRecipient (unused), custNoRecipientYet, custGiftNoteRides; plus verticalFlowersGifts at app_en.arb:769.

**Missing in the clients**

- New GiftHubScreen (mobile_app/lib/src/gift_hub_screen.dart) replacing DiasporaScreen. Either fold DiasporaScreen's recipient and note logic into it plus the gift checkout, or delete DiasporaScreen so two dead-or-alive variants do not coexist.
- Gift category model: a client-side const list of (l10n label, asset image, StoreVertical, optional search term) mapped to ShopsListingScreen. ShopsListingScreen currently takes initialVertical and chips; a pre-filled search would need a new optional parameter (initialSearch) that feeds StoreFilters.search.
- Recipient chips over DeliveryAddressStore.recents, filtered to addresses with a non-Home/Work label, plus an 'Add a recipient' card that opens showAddressSheet.
- Recipient phone persistence: extend DeliveryAddress with an optional phone (and optionally recipientName) in toJson/fromJson. This is backward compatible because older blobs lack the key. The alternative is a separate GiftRecipientStore under its own secure-storage key per sub.
- GiftingApi (or StoreApi.giftBundles()) in delivery_core, plus a GiftBundle model (productId, storeId, storeName, name, description, price, imageUrl, sameDay flag or store availability fields).
- Entry points: a 'Send a gift to Lebanon' card or banner on StoreHomeScreen (under the category strip), and a YdListRow in ProfileDrawer. CustomerShell passes onStartOrder: () => _open(CustomerNavBar.homeIndex) and onOpenBasket: _openBasket. Optionally teach _openBanner an in-app route for a gifting link kind.
- Bundled image assets: the hero photo and the five category thumbnails. Figma asset URLs expire in about 7 days, so the implementer must download the exact bytes (get_design_context on 112:1708 and 112:1736-1748) into mobile_app assets.
- l10n: new en and ar strings (see strings), plus fixing custStartOrder in app_en.arb:1965.

**Missing in the backend**

- product-service: curated 'featured care bundles'. Smallest honest option: a new migration adding products.gift_featured boolean DEFAULT false (plus optional gift_rank int), a public GET /api/storefront/gift-bundles returning featured products of ACTIVE stores only, with store availability and ETA so the client can compute 'Same-day Deliverable', and a backoffice PUT /api/products/{id}/gift-featured (ADMIN) plus a toggle in delivery_portal. Nothing like this exists today; grep for bundle/care package finds nothing.
- product-service (optional, only if the product team wants real gift categories rather than the vertical mapping): a gift_categories table (name, image_ref, vertical, search/tag, position) served at GET /api/storefront/gift-categories, managed from delivery_portal the way BannerService manages category chips.
- No backend is needed for recent recipients in v1 (device-local). A server-side address book with recipient name and phone would be a new entity somewhere (order-manager or a profile service). Not recommended for this slice; it is flagged as a known limitation.

**Design-system pieces to reuse**

- YdScreenHeader(title, subtitle, onBack, trailing, backSemanticLabel) for the header; the brand logo widget in delivery_design_system/lib/src/logo.dart for the YouDrop chip.
- YdCard.bordered for the how-it-works card, recipient cards and bundle rows (radius DeliveryRadius.lg = 16 / md = 12).
- YdSectionHeader (or the uppercase label style DiasporaScreen uses) for section labels.
- YdEmptyState / YdCard(onTap) for the add-recipient empty card.
- StoreMonogram (already used by diaspora_screen.dart) for recipient initials; ProductImage/NetImage for bundle thumbnails.
- Tokens: DeliveryColors.brand #E11D48, brandSoft #FFF1F2, ink #0F172A, muted #475569, faint #94A3B8, border #E2E8F0, background #F8FAFC, white; DeliverySpacing.md 16 (12 = md - xs, as the codebase writes it); DeliveryRadius sm 8, md 12, lg 16; DeliveryTypography Rubik. The 'Same-day Deliverable' green #10B981 should come from DeliveryAccent.positive (confirm its hex matches).
- showAddressSheet, DeliveryAddressStore, Cart, ShopsListingScreen, StorePageScreen, ProductDetailScreen, StoreApi.categoryChips/browseWith, MarketRates.

**Strings**

- giftHubTitle: 'Send a Gift' (or reuse custDiasporaTitle 'Send to Lebanon'; decide)
- custDiasporaSub: 'Diaspora Gifting Portal' (exists, reuse)
- custDiasporaBanner: 'Remittance made real' (exists; the design capitalises 'Remittance Made Real')
- giftHubBannerBody: 'Support your loved ones in Lebanon. Choose real essentials, groceries, or hot meals delivered same-day.' (new; the existing custDiasporaBlurb promises 'Pay in USD from abroad', which no payment rail delivers)
- giftHowItWorks: 'How it works'
- giftStep1Title: 'Choose from local shops' / giftStep1Body: 'Select fresh groceries, sweets, pharmacy items or custom butler orders.'
- giftStep2Title: 'Enter Lebanese address' / giftStep2Body: 'Deliver anywhere in Beirut, Tripoli, Sidon or Mount Lebanon.' (copy under review)
- giftStep3Title: 'Same-day delivery' / giftStep3Body: 'Our reliable riders deliver with a beautifully printed custom note.' (copy under review)
- giftCategories: 'Gift Categories'
- giftCatCarePackage: 'Care Package'; giftCatGroceries: 'Groceries'; giftCatSweets: 'Sweets & Pastries'; giftCatBabyKids: 'Baby & Kids'; giftCatMedicine: 'Medicine & Health'
- giftRecentRecipients: 'Recent Recipients'
- giftAddRecipient: 'Add a recipient' (+ reuse custNoRecipientYet as helper text)
- giftFeaturedBundles: 'Featured Care Bundles'
- giftSameDayDeliverable: 'Same-day Deliverable'
- FIX app_en.arb:1965 custStartOrder: 'Select Items 0026 Start Order' -> 'Select Items & Start Order' (and remove or use custWhatToSend and custPickRecipient, which nothing uses)
- All of the above also in app_ar.arb, then regenerate delivery_l10n/lib/generated

**Tests that should prove it**

- Widget test test/gift_hub_test.dart: renders header, hero, the three steps, five category cards, recipients and bundles from a fake Dio. Tapping 'Groceries' pushes ShopsListingScreen with initialVertical == StoreVertical.grocery; tapping 'Medicine & Health' gives pharmacy.
- Widget test: with DeliveryAddressStore holding labelled recents (secure-storage channel mocked, as in checkout_test.dart), the recipient cards show the label, the zoneName and initials. Tapping one calls select() and makes that address addresses.selected.
- Widget test: no labelled recents -> the 'Add a recipient' card shows and opens the address sheet.
- Widget test: bundles endpoint 500 -> the bundles section is hidden and the rest of the screen still renders. Empty list -> section hidden.
- Widget test: a bundle from store B while the cart holds store A shows the existing conflict/switch prompt and never throws StateError.
- Wiring test (pattern: test/merchant_shell_wiring_test.dart): CustomerShell -> Home entry card -> GiftHubScreen is on screen. This proves the screen is no longer unreachable, which is what surface-checklist flags.
- Arabic RTL test (pattern: test/arabic_rtl_test.dart): the hub renders in ar with no overflow and the scrollers are mirrored.
- Java (product-service) GiftBundleServiceTest: only gift_featured products of ACTIVE stores are returned, ordered by rank; a DRAFT or SUSPENDED store's product never leaks; the endpoint is public-read and the toggle is ADMIN-only (403 for MERCHANT/CUSTOMER).
- API scenario (infra/smoke-test-gift-bundles.js, following the smoke-test-banners.js pattern): an admin flags a product, the anonymous bundles call returns it, un-flagging removes it.
- Integration test integration_test/customer_test.dart: sign in as the customer, open the gift hub from Home, tap a category, reach a store.

**Questions**

- Is the hub a new screen replacing DiasporaScreen, or DiasporaScreen restyled? The spec assumes replacement, with DiasporaScreen's recipient and note logic moving into the hub and the gift checkout.
- Title: 'Send a Gift' (design) or 'Send to Lebanon' (existing custDiasporaTitle)? Arabic copy has to follow whichever wins.
- Gift categories: is a client-side mapping onto store verticals plus search acceptable, or does product want a curated gift taxonomy managed in the back office? Sweets & Pastries and Baby & Kids have no vertical.
- Featured bundles: who curates them (back office flags merchant products, or merchants mark their own), and is a 'bundle' just an ordinary product such as 'Family Essentials box $45' sold by one shop? A multi-shop care package is impossible under the one-store basket rule (Cart and OrderService both enforce one merchant and one shop).
- Step 2 promises delivery 'anywhere in Beirut, Tripoli, Sidon or Mount Lebanon', but coverage is per-store delivery zones and radius (OrderService.applyStoreTerms refuses unserved zones). Should the copy soften to 'in the areas our shops serve'?
- Step 3 promises a 'beautifully printed custom note'. Nothing prints: the note travels in order.notes and is shown as text to the merchant (delivery_merchant order_detail_screen.dart:807) and the rider (rider_order_detail_screen.dart:815). The existing copy custGiftNoteRides says 'read out at the door'. Which promise is true?
- Recent recipients are device-local (secure storage, 5 recents max) and vanish on reinstall or a new device. Is that acceptable for a diaspora user who may use several devices?
- Should the hub also be reachable from a back-office home banner? That needs a new BannerLinkKind (product-service BannerDtos plus client _openBanner), because URL banners are deliberately ignored today.

### `112:1830` customer-gift-checkout — XL

*Who:* Customer (diaspora sender) finishing a gift order for a recipient in Lebanon. Mobile app, customer shell.

*What:* A checkout built for gifts. It collects who receives the gift (name and Lebanese phone), where it goes, when it arrives, and the personal note. It offers premium gift wrapping, shows a USD summary with an approximate LBP figure, and places the order with an online payment ('Send Gift & Pay Securely'). It differs from the regular CheckoutScreen in several ways: no payment-method picker is drawn, no tier picker, recipient fields instead of the address radio list, and a delivery-date selector.

*Reached from:* Gift Hub (112:1684) -> shop or bundle -> basket (CustomerShell Basket tab via _openBasket) -> 'Proceed to Checkout' routes to GiftCheckoutScreen when the cart is marked as a gift (otherwise the normal CheckoutScreen). On success it pops with the placed DeliveryOrder, and CartScreen's onOrderPlaced sends the customer to the Orders tab (CustomerShell._open(CustomerNavBar.ordersIndex)). Back returns to the basket. A direct 'Checkout' from the hub for a single bundle can push the same screen after adding the bundle to the cart.

**Every element, and where its data comes from**

- Screen header: back button (maybePop), title 'Gift Details' (Bold 18), subtitle 'Diaspora Checkout' (Medium 12 muted), trailing YouDrop logo chip. Same composition as the hub.
- RECIPIENT INFORMATION card (white, radius 16, 16px padding, 12px gap; section label Bold 12 uppercase faint #94A3B8).
- Recipient Name field: label SemiBold 12 muted over a filled #F8FAFC input, radius 8, 12x10 padding, Regular 14 ink. Example 'Mona (Mom)'. Prefilled from the chosen recipient (DeliveryAddress.label). Required. Data destination: PlaceOrderRequest has NO recipient-name field. v1 can fold it into notes; the proper fix is a new gift field on the order (see missingBackend).
- Phone Number (Lebanon): a fixed '+961' prefix box, then a flex number field ('71 234 567'). Required; validate a Lebanese mobile or landline (8 digits for 3x/7x/81 mobiles, 7 digits plus area code for landlines). Sent as contactPhone '+96171234567'. Server: @Size(max=32) with no format check. Existing behaviour that works for gifting: the rider sees contactPhone (rider_order_detail_screen.dart:654) and so does the merchant (delivery_merchant order_detail_screen.dart:745), so the rider rings the recipient, not the sender. Persist it with the recipient (new DeliveryAddress.phone) so the next gift is prefilled.
- Delivery Address row: filled #F8FAFC box, 14px location-pin icon, single-line ellipsised address (Regular 13). Example 'Mar Mikhael, Facing Municipality, Beirut'. Tapping opens showAddressSheet(context, addresses, zoneApi:, geocodingApi:). Data: DeliveryAddressStore.selected, whose line, zoneId, latitude and longitude go to OrderApi.place (deliveryAddress, deliveryZoneId, deliveryLatitude/Longitude). Required (existing t.addressRequired snackbar). The shop delivery-radius haversine check from CheckoutScreen._place applies.
- Delivery Date segmented control, three equal pills: 'Today (Same-day)' (selected: brandSoft fill, 1px brand border, Bold 12 brand), 'Tomorrow' and 'Schedule' (unselected: #F8FAFC fill, Medium 12 muted). Backend has NO scheduling. DeliveryTier.java says 'Scheduled' has been floated and refused, and OrderService.applyStoreTerms rejects any order while the store is not accepting orders. So only 'Today' can be honoured. v1: render Tomorrow and Schedule disabled with YdComingSoon.wrap (the pattern profile_drawer.dart uses for Vouchers), or omit them. 'Schedule' would also need a date/time picker sheet that is not drawn.
- Personal note card (white, radius 16, 16px padding): title 'Attach a Personal Note (Printed & Delivered)' (Bold 13), then an 80px-tall filled #F8FAFC multi-line field (Regular 13, line height 18). Example 'Habibti Mom, wishing you a beautiful week ahead...'. Data: Cart.giftNote (set by the hub and restored when checkout reopens). On placement CheckoutScreen's existing rule prefixes '\u{1F381} ' to the gift note, then appends any typed door notes, joined by a newline into order.notes. Server cap is @Size(max=500) on notes, so enforce maxLength 240 on the gift note (DiasporaScreen does this already) and keep gift note plus door note within 500 or the placement fails with a 400.
- Premium Gift Wrapping card (white, radius 16, 16px padding, space-between): 20px gift icon, title 'Premium Gift Wrapping' (Bold 13), subtitle 'Festive box & handwritten card (+$3.00)' (Regular 11 muted), trailing 44x24 switch (on, brand track). Toggling adds a $3.00 line to the summary. Backend has NO platform add-on: prices come only from the catalog and the request contract forbids client-sent amounts (OrderDtos javadoc). The only wrapping that exists is Bloom & Wrap's $6 'Gift Wrapping' PRODUCT (V12 seed), usable only in that shop's basket. Needs either a server-priced gift-wrap option (config-priced like the EXPRESS surcharge) or per-store product options. Until then, hide the toggle.
- Order Summary card: title 'Order Summary' (Bold 13). Rows in Regular 13 muted with the amount right-aligned in SemiBold 13 ink: '{qty}x {product name}' from Cart.lines (unitPrice x qty, option deltas included), 'Premium Gift Wrapping $3.00' when on, 'Same-day Delivery Fee' showing 'FREE' in green when Cart.deliveryIsFree (OfferApi.preview waiver) and Cart.deliveryFeeCharged otherwise. A 1px divider. Then 'Total USD' (Bold 14) with '$48.00' (ExtraBold 18 brand) and '≈ LBP 4,300,000' (Regular 11 faint) under it. LBP comes from TransferApi.rate() lbpPerUsd (the locked rate) or MarketRates.instance.lbp(); hide it when there is no rate. The total is advisory: the server recomputes, and the confirmation shows the server's totalAmount, as CheckoutScreen documents. A carried promo (widget.promo) should still be subtracted as in CheckoutScreen._summaryBar. EXPRESS is not offered here, so send deliveryTier STANDARD explicitly.
- Primary CTA 'Send Gift & Pay Securely': full-width brand button, radius 12, 14px padding, Bold 16 white. It validates name, phone, address and the radius check, then places the order (OrderApi.place) with busy state and disables on double tap. On success: clear the cart (which also clears giftNote), pop the order, and CustomerShell sends the user to Orders (onOrderPlaced). Error mapping as in CheckoutScreen: 422 shows the server detail (e.g. 'Bloom & Wrap is closed and is not taking orders right now') or t.itemNoLongerAvailable; 402 shows the provider detail or t.custPaymentDeclined; 400 shows t.checkDeliveryDetails; anything else t.couldNotPlaceOrder.
- Payment (NOT drawn): 'Pay Securely' implies an online charge to the sender, but the platform has only CASH (collected by the rider at the door, which would bill the gift recipient), CARD/WALLET through the DEV payment provider (test only, 'dev-test-instrument' token), and WHISH/OMT through transfer-service's SimulatedWalletConnector. No foreign-card rail exists. The frame omits the method picker. The implementation must not silently default a gift to CASH. It needs a decision: a card or wallet rail with the t.paymentTestModeNote honesty label, a compact method row, or a server rule refusing CASH on gift orders.
- States: validation errors inline under name and phone (TextFormField validators); address missing -> snackbar; placing -> CTA busy; store closed or unserved -> 422 snackbar (common, because same-day depends on store hours); LBP line hidden when no rate; summary 'FREE' vs a fee; empty cart -> CTA disabled.
- Bottom nav drawn (Home active): the same mismatch as the hub. Checkout is a pushed route, and the real CheckoutScreen shows no nav bar; keep that.

**Existing code that already covers part of it**

- clients/apps/mobile_app/lib/src/checkout_screen.dart: the full regular checkout. _place() does the address-required check, the shop-radius haversine, the gift-note prefix (lines 248-257: the '\u{1F381} ' prefix branch is unreachable today because nothing sets giftNote), OrderApi.place with items, address, zone, contactPhone, notes, paymentMethod, tier, promo, token and pin, then TransferApi.initiate for the ledger intent, split-plan attach, cart.clear, and 422/402/400 error mapping. The rate banner uses TransferApi.rate()/MarketRates; _summaryBar holds the advisory total; _boxDecoration is the input style.
- clients/apps/mobile_app/lib/src/cart.dart: lines, subtotal, deliveryFee, deliveryFeeCharged, deliveryIsFree/waiver, total, toOrderLines(), giftNote, splitPlanId, clear().
- clients/apps/mobile_app/lib/src/diaspora_screen.dart: recipient and note capture (maxLength 240) feeding cart.giftNote and addresses.select(recipient). Unreachable.
- clients/apps/mobile_app/lib/src/address_sheet.dart and delivery_address.dart: recipient address capture and storage (no phone).
- clients/packages/delivery_core/lib/src/api/order_api.dart: place({items, deliveryAddress, contactPhone, notes, deliveryZoneId, paymentMethod, promoCode, paymentInstrumentToken, deliveryTier, deliveryLatitude, deliveryLongitude}) -> POST /api/orders; mine().
- clients/packages/delivery_core/lib/src/models/order_models.dart: DeliveryOrder has deliveryAddress, contactPhone, notes and storeName, and no gift fields.
- services/order-manager/src/main/java/com/delivery/order/api/dto/OrderDtos.java: PlaceOrderRequest (items; deliveryAddress @NotBlank max 500; deliveryZoneId; contactPhone max 32; notes max 500; paymentMethod default CASH; promoCode pattern; paymentInstrumentToken; lat/lng both-or-neither; deliveryTier default STANDARD). The contract says no client-sent prices, discounts or surcharges, ever. OrderResponse carries contactPhone, notes and the fee breakdown (deliveryFee, deliveryFeeCharged, deliveryFeeWaived, expressSurcharge, discountAmount).
- services/order-manager/src/main/java/com/delivery/order/service/OrderService.java: placement prices lines from the catalog, enforces one merchant and one shop, applyStoreTerms refuses closed stores ('... is closed and is not taking orders right now') and unserved zones, then applies the tier surcharge from DeliveryTierPolicy config, fee waivers and the promo re-evaluation.
- services/order-manager/src/main/java/com/delivery/order/domain/Order.java: contact_phone varchar(32), notes text. domain/DeliveryTier.java: STANDARD and EXPRESS only, 'Scheduled' explicitly refused. domain/Payment.java: Method CASH, CARD, WALLET (no wallet ledger). domain/OrderKind.java: CATALOG, BUTLER_BUY, BUTLER_SEND. Latest migration is V30__carrier_order_indexes.sql.
- services/transfer-service: TransferMethod WHISH/OMT via SimulatedWalletConnector (dev), rate endpoint used by TransferApi.rate().
- services/notifications-manager/.../event/OrderEventListener.java: every order notification goes to the event's customerId (the sender). No channel reaches the recipient's phone.
- Consumers of the gift data: clients/apps/mobile_app/lib/src/rider_order_detail_screen.dart (shows contactPhone at line 654 and notes at lines 815-878); clients/packages/delivery_merchant/lib/src/order_detail_screen.dart (phone at 745, notes quote at 807-836). clients/apps/mobile_app/lib/src/order_details_screen.dart (the customer's own receipt) shows neither notes nor contactPhone, so the sender cannot see the gift message they sent.
- clients/apps/mobile_app/test/checkout_test.dart: the recordingDio interceptor and secure-storage channel mock pattern for asserting the placement payload.

**Missing in the clients**

- New GiftCheckoutScreen (mobile_app/lib/src/gift_checkout_screen.dart) with the recipient form (Form + TextFormField validators), address row, date selector (Today only in v1), note field bound to cart.giftNote, optional wrap toggle, summary card and CTA.
- Extract CheckoutScreen._place's shared core (radius check, the placement call, transfer-intent recording, split attach, cart.clear, DioException-to-message mapping) into a reusable helper (e.g. lib/src/order_placement.dart) so gift checkout does not fork 150 lines of money logic. checkout_test.dart must stay green unchanged.
- Routing: CartScreen's 'Proceed to Checkout' pushes GiftCheckoutScreen instead of CheckoutScreen when the basket is a gift. Add a Cart.giftRecipient, or a bool isGift set by the hub, cleared in clear() alongside giftNote and splitPlanId.
- Lebanese phone formatter and validator utility (+961 prefix, digit grouping '71 234 567', normalising leading 0 or 961).
- DeliveryAddress.phone (optional, JSON backward compatible) so the recipient phone is remembered and prefilled.
- A payment affordance consistent with the product decision: at minimum a compact method row (card or wallet with the t.paymentTestModeNote label) rather than the implicit CASH default.
- DeliveryOrder model and OrderApi.place: new optional gift fields (recipientName, giftMessage, giftWrap) once order-manager exposes them. Render them on order_details_screen (customer), delivery_merchant order_detail_screen (a 'Gift for {name}' block and message, where the merchant would handwrite or print the card) and rider_order_detail_screen.
- l10n strings (en and ar), see strings.

**Missing in the backend**

- order-manager: gift details on the order. Migration V31__gift_orders.sql: orders.gift_recipient_name varchar(80) NULL, orders.gift_message varchar(240) NULL, orders.gift_wrap boolean NOT NULL DEFAULT false, orders.gift_wrap_fee numeric(10,2) NOT NULL DEFAULT 0. PlaceOrderRequest gets an optional nested GiftRequest(recipientName @Size(max=80), message @Size(max=240), wrap boolean), with no amount field, same rule as the tier. Order.forGift(...)/applyGift(...), plus OrderResponse fields giftRecipientName, giftMessage, giftWrap and giftWrapFee. This keeps the gift message out of the door-instructions notes field.
- order-manager: GiftWrapPolicy (config delivery.orders.gift-wrap-fee, e.g. 3.00) priced server-side at placement and added to the total the way DeliveryTierPolicy adds expressSurcharge. Order total and settlement change, so accounting-service needs to know who earns the wrap fee (the merchant who wraps, or the platform). Only if product keeps a platform-level toggle; the alternative is per-store product options (existing OptionGroup/priceSelection), which needs no order-manager change but cannot be a single platform $3 toggle.
- order-manager (policy decision): refuse CASH on gift orders (422 'A gift cannot be paid at the door'), or at least surface it, because CASH means the rider collects from the recipient.
- order-manager (separate epic, only if Tomorrow/Schedule stay): orders.scheduled_for timestamptz, a HELD or SCHEDULED pre-acceptance state, a scheduler that releases the order to the merchant and dispatch at the window, applyStoreTerms evaluated against the store's hours at the scheduled time (product-service store_hours via StoreClient), and the customer, merchant and rider UIs for scheduled orders. This touches order lifecycle, dispatch and notifications, so it is XL on its own.
- notifications-manager (optional): an SMS/WhatsApp 'A gift from {sender} is on its way' to the recipient's contactPhone when a gift order is accepted or picked up. Needs the order event payload to carry isGift and contactPhone, a new template, and consent considerations (the recipient never opted in). Today OrderEventListener notifies customerId only.
- Payments (product/infra decision, not code in this slice): a real card processor for foreign cards. Payment.Method CARD exists but only the DEV provider backs it.

**Design-system pieces to reuse**

- YdScreenHeader + logo chip; YdCard.bordered for the four cards (radius DeliveryRadius.lg 16, padding DeliverySpacing.md).
- CheckoutScreen._boxDecoration-style filled inputs (fill DeliveryColors.background #F8FAFC, radius DeliveryRadius.sm 8, 12x10 padding). Consider promoting it to a shared YdInputDecoration in delivery_design_system.
- YdChip or CheckoutScreen._payCard geometry for the three-way date selector (selected: brandSoft fill with a brand border).
- Material Switch with activeTrackColor DeliveryColors.brand and activeThumbColor white (the profile_drawer.dart biometrics row) for gift wrapping.
- YdComingSoon.wrap for the Tomorrow/Schedule pills until scheduling exists.
- YdPillButton(busy:) for the CTA. The design uses radius 12 rather than a pill; either accept the pill for consistency or add a radius variant. Design-system call.
- showAddressSheet, DeliveryAddressStore, Cart, OrderApi.place, TransferApi.rate/initiate, MarketRates, OfferApi preview via Cart.waiver, and the existing l10n keys deliveryAddress, addressRequired, itemNoLongerAvailable, custPaymentDeclined, checkDeliveryDetails, couldNotPlaceOrder, custPersonalNoteHint, custGiftNoteRides, paymentTestModeNote.
- Tokens: brand #E11D48, brandSoft #FFF1F2, ink #0F172A, muted #475569, faint #94A3B8, border #E2E8F0, background #F8FAFC; the green #10B981 for FREE via DeliveryAccent.positive (verify its hex).

**Strings**

- giftDetailsTitle: 'Gift Details'
- giftCheckoutSub: 'Diaspora Checkout'
- giftRecipientInfo: 'Recipient Information'
- giftRecipientName: 'Recipient Name' / giftRecipientNameRequired: 'Who is receiving it?'
- giftRecipientPhone: 'Phone Number (Lebanon)' / giftPhoneInvalid: 'Enter a Lebanese number, e.g. 71 234 567' (the +961 prefix is a constant, not translated)
- deliveryAddress: exists (reuse; the design says 'Delivery Address')
- giftDeliveryDate: 'Delivery Date'
- giftToday: 'Today (Same-day)'; giftTomorrow: 'Tomorrow'; giftSchedule: 'Schedule' (+ reuse authComingSoon for disabled pills)
- giftNoteTitle: 'Attach a Personal Note (Printed & Delivered)' (or reuse custPersonalNote 'Attach a personal note (delivered with the order)'; decide per the printing question). Hint: reuse custPersonalNoteHint
- giftWrapTitle: 'Premium Gift Wrapping' / giftWrapSubtitle(amount): 'Festive box & handwritten card (+{amount})'
- giftOrderSummary: 'Order Summary'
- giftLineQty(qty, name): '{qty}x {name}'
- giftSameDayFee: 'Same-day Delivery Fee'
- giftFree: 'FREE' (reuse an existing 'free' key if delivery_l10n already has one)
- giftTotalUsd: 'Total USD'
- giftApproxLbp(amount): '≈ LBP {amount}'
- giftSendAndPay: 'Send Gift & Pay Securely'
- giftCashNotAllowed: 'Gifts are paid online — the recipient is never asked to pay.' (only if the no-cash rule is adopted)
- giftForName(name): 'Gift for {name}' (merchant, rider and customer order-detail block, once the backend fields exist)
- All of the above also in app_ar.arb, then regenerate

**Tests that should prove it**

- Widget test test/gift_checkout_test.dart (recordingDio + secure-storage mock from checkout_test.dart): the placement payload carries deliveryAddress, deliveryZoneId and lat/lng from the recipient address; contactPhone normalised to '+96171234567'; notes starting with the gift emoji and the gift message (or the gift block once the backend lands); deliveryTier 'STANDARD'; and the agreed paymentMethod (never an implicit CASH if the rule is adopted).
- Widget test: empty recipient name or an invalid phone ('12', '+961 00') shows inline errors and sends no request; missing address shows the t.addressRequired snackbar and sends no request.
- Widget test: summary shows 'FREE' when Cart.waiver.deliveryFeeWaived is true and the fee otherwise; total = subtotal + fee (+ wrap) - promo; the LBP line is hidden when MarketRates.lbpPerUsd == 0 and shows '≈ LBP 4,300,000' for $48 at the matching rate (rounded to 1000).
- Widget test: 'Tomorrow' and 'Schedule' are not selectable in v1 (coming-soon), and 'Today' stays selected.
- Widget test: 422 with detail 'Bloom & Wrap is closed...' shows that detail; 402 shows t.custPaymentDeclined; the CTA shows busy and a double tap sends one request.
- Widget test: gift note longer than 240 characters is refused by the field, so the combined notes never exceed 500.
- Regression: test/checkout_test.dart still passes after extracting the shared placement helper.
- Arabic RTL test: gift checkout in ar; the +961 prefix stays LTR inside an RTL layout (wrap in Directionality/TextDirection.ltr).
- Java (order-manager) OrderServiceTest: a gift request persists recipientName and message; gift_wrap_fee comes from GiftWrapPolicy config and ignores anything the client sends; the total includes the wrap fee; a waived delivery fee does not waive the wrap fee; a message over 240 is rejected (400); a CASH gift is refused (422) if the rule is adopted; a non-gift order is unchanged (all gift columns default).
- Java: an OrderDtos compatibility test that the existing PlaceOrderRequest convenience constructors still compile and default gift to null; a Flyway migration smoke run (RepositoryQueryParseTest-style) for V31.
- Java (accounting-service, if the wrap fee ships): the settlement test attributes the wrap fee to the agreed party.
- API scenario infra/smoke-test-gift-order.js on dev: the customer places a gift order with recipient phone, message and wrap; GET as the customer returns the gift fields and the wrap fee; the merchant's GET /api/orders/merchant shows the message; the rider's view shows contactPhone.
- Integration test (integration_test/order_lifecycle_test.dart pattern): hub -> bundle -> basket -> gift checkout -> placed -> visible in My Orders with the gift message.

**Questions**

- Payment: 'Pay Securely' implies an online charge to the sender, but only CASH is real and CARD/WALLET/Whish/OMT are dev or simulated. Which rail do diaspora payers use (a foreign card processor? Whish or OMT from abroad?), and until it exists, may gift orders be placed with the test provider, or must cash be forbidden? Defaulting to CASH makes the recipient pay at the door, which defeats the feature.
- Delivery date: are Tomorrow and Schedule required for launch? They need an order-manager scheduling epic (DeliveryTier explicitly refuses 'Scheduled', and closed stores are refused at placement). Recommend shipping Today only.
- Premium Gift Wrapping: is it a platform fee ($3, server-configured, who earns it?) or a merchant product option? The seed has a $6 'Gift Wrapping' product at Bloom & Wrap only. The drawn copy promises a 'handwritten card', which is merchant labour.
- 'Printed & Delivered' note: who prints it? No print path exists; the merchant sees the note as text. Change the copy to the existing custGiftNoteRides, or have merchants handwrite or print from the order detail?
- Should the gift message be a separate order field (recommended: it keeps door instructions and the gift message apart, and lets merchant and rider render it distinctly) or keep riding in notes with the emoji prefix (current v1 code)?
- Should the recipient receive an SMS or WhatsApp that a gift is coming? They are not a platform user and have not consented; today only the sender is notified.
- 'Same-day Delivery Fee FREE' is drawn as a given. In reality it is free only when a FeeWaiver offer applies (OfferApi.preview). Confirm the summary shows the real fee otherwise.
- Should the gift checkout let the sender edit the cart lines or apply a promo code? Neither is drawn; CheckoutScreen carries the promo quote from the basket.

**Build order for this cluster**

- 0. Housekeeping (S): fix app_en.arb:1965 custStartOrder ('Select Items 0026 Start Order' -> 'Select Items & Start Order'), add the hub and checkout l10n keys in en and ar, regenerate delivery_l10n. Download the hero and category image assets from Figma before the URLs expire.
- 1. Make gifting reachable (S-M): build GiftHubScreen with the static sections (header, hero, how-it-works, gift categories mapped to StoreVertical -> ShopsListingScreen) and recent recipients from DeliveryAddressStore.recents with an add-recipient card. Wire it from a StoreHomeScreen entry card and a ProfileDrawer row through CustomerShell (onStartOrder -> Home, onOpenBasket -> _openBasket). Retire DiasporaScreen. Tests: gift_hub_test plus a shell wiring test.
- 2. Refactor with no behaviour change (S): extract CheckoutScreen._place's placement, transfer intent, split attach and error mapping into a shared helper. test/checkout_test.dart must pass unchanged.
- 3. Gift checkout v1 on today's backend (M): GiftCheckoutScreen with recipient name and +961 phone (validated, sent as contactPhone and remembered via a new optional DeliveryAddress.phone), address row (showAddressSheet), Today-only date (Tomorrow/Schedule as coming-soon), note bound to Cart.giftNote (max 240; still folded into notes with the existing prefix), summary from Cart (waiver FREE, LBP line via TransferApi/MarketRates), explicit STANDARD tier, and no wrap toggle. Route from CartScreen when Cart is marked as a gift. BLOCKED on the payment decision: do not ship with an implicit CASH default.
- 4. order-manager gift fields (M): V31__gift_orders.sql (gift_recipient_name, gift_message, gift_wrap, gift_wrap_fee), optional GiftRequest on PlaceOrderRequest, OrderResponse fields, OrderServiceTest coverage, and optionally the no-cash-for-gifts rule. Then the client: DeliveryOrder/OrderApi.place fields, send the gift block instead of the notes prefix, and render 'Gift for {name}' plus the message on the customer order_details_screen (which shows no notes today), merchant order_detail_screen and rider_order_detail_screen. Deploy order-manager to dev and run smoke-test-gift-order.js.
- 5. Featured care bundles (M): product-service migration (products.gift_featured and rank), public GET /api/storefront/gift-bundles (ACTIVE stores only, with availability and ETA for 'Same-day Deliverable'), ADMIN toggle plus a delivery_portal back-office switch, a delivery_core GiftingApi, and the hub's bundles section with loading, empty and error handling and the cart-conflict prompt.
- 6. Gift wrapping (S-M, after product decides): either a GiftWrapPolicy config fee in order-manager (server-priced, itemised as giftWrapFee, accounting-service attribution) plus the checkout toggle, or a merchant product option with no platform toggle.
- 7. Optional: recipient 'gift on its way' SMS via notifications-manager and sms-connector (template, event payload with isGift and contactPhone, consent review).
- 8. Separate epic, only if product insists: scheduled delivery (Tomorrow/Schedule). order-manager scheduled_for plus a held state, release scheduler, store-hours check at the window, merchant, rider and customer UI. Treat as XL on its own; do not fold it into the gift slices.

**Cross-cutting**

- The existing gift path is dead code: DiasporaScreen has zero call sites (docs/surface-checklist.md:2077), so Cart.giftNote is always null and CheckoutScreen's gift-note prefix branch (checkout_screen.dart:248-257) is unreachable. This cluster is what brings them to life. Replace DiasporaScreen instead of keeping two variants.
- Payment contradiction (highest risk): both frames promise 'Pay Securely' by a diaspora sender. The backend's only real method is CASH, collected by the rider from whoever opens the door (the gift recipient). CARD/WALLET run on the DEV provider and Whish/OMT on transfer-service's SimulatedWalletConnector. Neither frame draws a method picker. Gift orders must not silently default to CASH (PlaceOrderRequest defaults a null method to CASH).
- Scheduling contradiction: 'Tomorrow' and 'Schedule' have no backend. DeliveryTier.java explicitly refuses a 'Scheduled' tier, and OrderService.applyStoreTerms rejects orders to stores that are not accepting orders right now, so 'same-day' also depends on store hours (the seeded FLOWERS_GIFTS store Bloom & Wrap is deliberately closed).
- Pricing rule: order-manager accepts no client-sent prices, fees or surcharges (OrderDtos javadoc). Any gift-wrap charge has to be named by a flag and priced server-side (as EXPRESS is), or be a catalog product/option. It cannot be a client-computed +$3.
- 'Printed note' has no print pipeline. The note reaches the merchant and rider only as order.notes text (500-char server cap shared with door instructions), and the customer's own order_details_screen shows no notes at all.
- Recipients are device-local (DeliveryAddressStore in flutter_secure_storage, per Keycloak sub, max 5 recents). DeliveryAddress has no phone, and there is no server address book. Recipient name has no order field today (only contactPhone and notes).
- Notifications reach only the account holder (notifications-manager OrderEventListener -> customerId). The recipient learns about the gift only when the rider calls contactPhone.
- One-store basket (Cart and OrderService enforce one merchant and one shop): a care package mixing grocery and pharmacy goods is impossible, so 'bundles' must be single-shop products.
- Coverage promise ('anywhere in Beirut, Tripoli, Sidon or Mount Lebanon') conflicts with per-store delivery zones and radius enforced at placement.
- Design chrome drift: both frames draw a bottom nav of Home/Shops/Orders/Butler/Account. The shipped CustomerNavBar is Home/Butler/Basket/Orders/Account, and pushed screens hide it. Keep the shipped bar.
- Figma styling maps 1:1 to existing tokens (Rubik; #E11D48 brand, #FFF1F2 brandSoft, #0F172A ink, #475569 muted, #94A3B8 faint, #E2E8F0 border, #F8FAFC background; radii 8/12/16 = DeliveryRadius sm/md/lg; 16 = DeliverySpacing.md). No new tokens are needed; the green #10B981 should come from DeliveryAccent.positive.
- No Code Connect mappings or design annotations came back from Figma for either frame. The hub frame is 560px wide only because its category row overflows; build it for a 390 viewport with horizontal scrollers.
- Deployment: every backend slice touches only deployed services (order-manager, product-service, optionally notifications-manager and accounting-service). Nothing depends on the undeployed pos-service or inventory-service.

## Customer: neighbourhood dekkane browse and shop, neighbourhood chat

### `112:1941` customer-dekkane-browse — M

*Who:* Customer (mobile_app CustomerShell)

*What:* Lets a customer find the small local shops (dekkanes) around their delivery address: quick attribute filters, a map preview, and large shop cards showing trust badge, distance and power status. This is the redesign of HyperlocalScreen, which is built but unreachable. Audience: signed-in customers in the mobile app's customer shell.

*Reached from:* Home tab (StoreHomeScreen) → new 'Your Neighborhood' entry → push HyperlocalScreen over the CustomerShell (MaterialPageRoute; the shell's nav bar is hidden under pushed routes, as with ShopsListingScreen). Map pill → push NeighborhoodMapScreen. Card or pin → push StorePageScreen (dekkane layout, frame 112:2041), passing cart and onOpenBasket from the shell. Optionally a HomeBanner could also link here (BannerLinkKind today covers only store/category/url).

**Every element, and where its data comes from**

- Screen header: back button (18px arrow in a round #f8fafc disc), title 'Your Neighborhood' (18 bold ink), subtitle 'Local Beirut Dekkanes' (12 medium muted), YouDrop logo pill on the right (brandSoft background, rose dot, 'You'+'Drop'). Data: static strings; the city in the subtitle comes from the active address's DeliveryZone.region, or is dropped. Reuse YdScreenHeader(title, subtitle, onBack, trailing: the logo widget in delivery_design_system/lib/src/logo.dart).
- Location bar (white row, 16px pin, 'Achrafieh, Beirut' 14 semibold). Data: CustomerShell's DeliveryAddressStore current address, zoneName plus region (DeliveryAddress has zoneId/zoneName/latitude/longitude). Tap should open the existing address picker (address_sheet.dart). HyperlocalScreen does not receive `addresses` today, so it has to be passed in.
- Filter chip row, single-select in the design: All (selected, brand fill), Open Now, Has Generator ⚡, Delivers, New. Data per chip: Open Now = StoreCard.availability != closed (computed in Java by Store.availabilityAt, so it cannot be filtered in SQL); Has Generator = StoreCard.powerStatus == GENERATOR (the power_status column, V23); Delivers = no source today (see questions); New = no source on the card (Store.createdAt exists server-side but is not in StoreCardResponse). Reuse YdChip. This REPLACES the existing district chips (storeApi.neighborhoods()) and the arabizi YdSearchField, which the design no longer shows.
- Map preview: 100px, radius 16, a map image with a white 'Expand Interactive Map' pill (12 bold brand). Data: shop pins from GET /api/stores/nearby (NearbyStoreResponse carries latitude/longitude/distanceMetres), centred on the address point. flutter_map ^8.3.2 and latlong2 are already mobile_app dependencies (used in address_sheet.dart, rider_home_screen.dart, carrier_zones_screen.dart). Tap opens a new full-screen map with store pins, and tapping a pin opens StorePageScreen. Hide the preview when the address has no point (hasPoint false) or nearby returns nothing.
- Section label 'ACTIVE NEARBY SHOPS' (14 bold, uppercase).
- Shop card, repeated (white, border #e2e8f0, radius 16, soft shadow): 120px full-width cover (StoreCard.listCoverUrl, falling back to the CustomerPhoto vertical icon), name (15 bold), 'Trusted Local' badge (StoreCard.verifiedLocal; brandSoft bg, brand 10 bold), description line (StoreCard.tagline, else powerNote, else vertical label, following the current _shopRow), '★ 4.6' in amber #f59e0b (StoreCard.rating, 'New' via t.ratingNew when null), '•', '350m away' (NearbyStore.distanceMetres; the browse endpoint has no distance), '⚡ Generator Active' pill (powerStatus GENERATOR; brandSoft bg, brand 11 semibold). Tap pushes StorePageScreen, as HyperlocalScreen._open does. Keep the existing rule that a DARK shop is dimmed to 0.55 opacity, not hidden.
- States: loading (brand CircularProgressIndicator; exists), empty (YdEmptyState storefront icon + t.noShopsMatch / t.tryClearingAFilter; exists), first-page error (MISSING: HyperlocalScreen never reads PagedList.error; add YdEmptyState + YdPillButton t.tryAgain as StoreHomeScreen._errorState does), pull-to-refresh (exists), infinite scroll via shouldLoadMore (exists), no-address or no-point state (MISSING: fall back to the browse endpoint, without distance or map).
- Bottom nav drawn with Home, Shops (active), Orders, Butler, Account. It contradicts the shipped CustomerNavBar (Home, Butler, Basket, Orders, Account), and there is no Shops tab. Do not implement; the screen is a route pushed over the shell like every other shop list.

**Existing code that already covers part of it**

- clients/apps/mobile_app/lib/src/hyperlocal_screen.dart: complete older version of this screen (district chips, arabizi search, paged StoreCard rows with StorePowerChip, VerifiedLocalBadge, DARK dimming, empty state, opens StorePageScreen). Zero call sites (docs/surface-checklist.md line 2064: 'UNREACHABLE').
- clients/apps/mobile_app/lib/src/store_power_chip.dart: StorePowerChip (mains green / generator amber / dark grey / unknown draws nothing) and VerifiedLocalBadge (green).
- clients/packages/delivery_core/lib/src/api/store_api.dart: browse/browseWith(StoreFilters) with the neighborhood param (line 18-56), neighborhoods() GET /api/stores/neighborhoods (line 59), nearby(lat,lng,radius) (line 73, no client screen calls it), canDeliver (line 335).
- clients/packages/delivery_core/lib/src/models/store_models.dart: StoreCard carries neighborhood, verifiedLocal, powerStatus, powerNote, availability, rating, ratingCount, latitude/longitude, deliveryRadiusMetres; StoreFilters.neighborhood; offersOnly is the precedent for client-side filtering.
- clients/packages/delivery_core/lib/src/models/geo_models.dart:100: NearbyStore(store, latitude, longitude, distanceMetres).
- services/product-service/src/main/java/com/delivery/product/api/StoreController.java: GET /api/stores (browse, neighborhood param, lines 128-146), GET /api/stores/neighborhoods (149), GET /api/stores/nearby (177-205, PostGIS candidates capped at 500, clamped radius, authenticated only).
- services/product-service/src/main/java/com/delivery/product/domain/StoreRepository.java: findStorefrontWithStatus filters vertical/search/fee/eta/rating/neighborhood, pinned to ACTIVE; distinctNeighborhoods() returns ACTIVE shops only.
- services/product-service/src/main/resources/db/migration/product/V23__lebanese_market.sql: power_status, neighborhood VARCHAR(80) free text, verified_local ('deliberately NOT merchant-writable').
- clients/apps/mobile_app/lib/src/delivery_address.dart: DeliveryAddress zoneId/zoneName/lat/lng; DeliveryAddressStore is owned by customer_shell.dart.
- clients/packages/delivery_l10n/lib/l10n/app_en.arb lines 1950-1954 and app_ar.arb lines 1422-1426: custHyperlocalTitle/Sub, custDistricts, custAllDistricts, custSearchArabiziHint; custVerifiedLocal 'Verified Local' (1941); custPowerGenerator/Mains/Dark (1776-1778); custPowerDeclared (1942).

**Missing in the clients**

- Entry point: nothing opens HyperlocalScreen. Add one on StoreHomeScreen (store_home_screen.dart), e.g. a 'Your Neighborhood' section or tile near _featuredSection/_categoryStrip with a See all that pushes HyperlocalScreen. CustomerShell._tabAt(homeIndex) must hand StoreHomeScreen what HyperlocalScreen now needs (addresses, and chatApi for the chat entry in frame 121:102).
- HyperlocalScreen: new constructor param DeliveryAddressStore addresses; a location bar bound to it; the attribute chip row replacing district chips and search (decide whether districts survive; see questions); a map preview widget plus a new NeighborhoodMapScreen (flutter_map, OSM attribution as the other maps do); a large-cover shop card (new private widget, or StorefrontCard with coverHeight 120 if its layout can carry the badge, power pill and distance); a distance formatter (m under 1 km, else 1 decimal km, localised); a first-page error state.
- Data source switch: when the active address has a point, page from storeApi.nearby(lat, lng, radius) and draw distance; otherwise fall back to browseWith(StoreFilters(neighborhood: ...)) and hide distance and map.
- StoreFilters and store_api: add the new filter params (openNow, powerStatus, isNew/newSinceDays, delivers) once the backend takes them. Until then Open Now and Has Generator can be filtered client-side on StoreCard.availability/powerStatus, the way offersOnly is, at the cost of short pages.
- StoreCard: add createdAt (or isNew) once the backend exposes it.

**Missing in the backend**

- product-service: extend GET /api/stores/nearby with optional filters openNow, powerStatus, verifiedLocal, newSinceDays, neighborhood (and delivers if defined). StoreService.nearby already post-filters candidates in Java with StoreView (availability computed), so these are Java predicates, not SQL. Add createdAt/isNew to StoreCardResponse (Store.createdAt exists, Store.java:209).
- product-service BUG (blocks the whole feature on real data): StoreService.update (line ~505) does store.setNeighborhood(request.neighborhood()) unconditionally, but StoreApi.updateProfile (store_api.dart:237) never sends 'neighborhood' and the merchant form (delivery_merchant/lib/src/store_screen.dart:179) has no field for it. Every merchant profile save therefore writes null, and GET /api/stores/neighborhoods is empty in practice. Fix the client to send it (add a field to the merchant store form, ideally picked from delivery zones rather than typed free) and add a regression test.
- product-service: no write path exists for verified_local (no setter on Store, no endpoint), so 'Trusted Local' can never render. Add a BACKOFFICE-only PUT /api/stores/{id}/verified-local {verified: bool} with @PreAuthorize("hasRole('BACKOFFICE')") (the pattern BannerController uses), plus Store.grantVerifiedLocal/revoke. A portal back-office toggle is also needed; delivery_portal/lib/src/backoffice has no store-admin screen today (only catalog_screen.dart).
- No migration is needed for the browse itself. If 'New' should mean 'published recently', add stores.published_at in a new product migration (only created_at exists).

**Design-system pieces to reuse**

- YdScreenHeader (title, subtitle, onBack, trailing)
- YdChip (label, selected, onTap) with YdChip.minHeight for the row height
- YdCard / StorefrontCard (coverHeight param) for the shop card
- StorePowerChip, VerifiedLocalBadge (store_power_chip.dart)
- CustomerPhoto (product_detail_screen.dart) with iconForVertical fallback
- YdEmptyState, YdPillButton (compact) for the empty and error states
- PagedList + shouldLoadMore + RefreshIndicator pattern already in HyperlocalScreen
- flutter_map map setup from address_sheet.dart
- Tokens: DeliveryColors.brand #E11D48, brandSoft #FFF1F2, ink #0F172A, muted #475569, faint #94A3B8, border #E2E8F0, background #F8FAFC; DeliverySpacing.md/sm/lg; DeliveryRadius.md/lg/pill; DeliveryAccent.caution/positive

**Strings**

- reuse: custHyperlocalTitle (currently 'Neighborhood Dekkane'; the design says 'Your Neighborhood', so decide whether to change the value), custHyperlocalSub, custVerifiedLocal (design says 'Trusted Local'), custPowerGenerator, custPowerDeclared, noShopsMatch, tryClearingAFilter, tryAgain, back, ratingNew
- new: custNeighborhoodSubCity '{city} local dekkanes' / 'دكاكين {city} المحلية'
- new: custFilterAll 'All', custFilterOpenNow 'Open now', custFilterHasGenerator 'Has generator', custFilterDelivers 'Delivers', custFilterNew 'New'
- new: custExpandMap 'Expand interactive map'
- new: custActiveNearbyShops 'Active nearby shops'
- new: custDistanceMetres '{m} m away', custDistanceKm '{km} km away' (placeholders, ar translations)
- new: custGeneratorActive 'Generator active' (or reuse custPowerGenerator)
- new: custCouldNotLoadShops 'Could not load shops' (or reuse an existing couldNotLoad* key)
- new: custNoAddressPoint 'Pin your address to see how far each shop is'

**Tests that should prove it**

- Widget (mobile_app/test/hyperlocal_screen_test.dart, Dio adapter routes as in view_basket_test.dart): the first load calls /api/stores/nearby with the address point, and each chip changes the query or the visible set; 'Trusted Local' renders only when verifiedLocal is true; '⚡ Generator Active' only for GENERATOR, and nothing for UNKNOWN; a DARK shop is dimmed, not removed; distance formats as '350m' and '1.2 km'; the empty state shows t.noShopsMatch; a first-page 500 shows the error state and Try again refetches; with no address point, browse is called and no map or distance shows.
- Widget, reachability: tapping the new Home entry pushes HyperlocalScreen (the checklist flags it as having no call sites); add to widget_test.dart or a new test.
- Widget RTL: extend arabic_rtl_test.dart so the chips, the card row and the distance render mirrored with Arabic strings.
- Java (product-service NearbyStoreSearchTest): openNow excludes CLOSED stores (busy and closing-soon stay in); powerStatus=GENERATOR filter; newSinceDays window; neighborhood exact match; filters combine with the radius and the 500-candidate cap.
- Java (StorefrontOrderingTest or new): the neighborhood filter on browse; distinctNeighborhoods ignores DRAFT/SUSPENDED and null.
- Java regression: PUT /api/stores/{id} with the client's full payload keeps the neighborhood; the verified-local endpoint is refused for MERCHANT and CUSTOMER and accepted for BACKOFFICE, and the card reflects it.
- API scenario: log in as a customer, save an address with a point, GET /api/stores/nearby?latitude&longitude&radiusMetres=1500&powerStatus=GENERATOR, and assert every item has powerStatus GENERATOR and distanceMetres <= 1500.

**Questions**

- 'Has Generator' vs the data: power_status is what the lights are doing NOW (MAINS/GENERATOR/DARK), not whether a shop owns a generator. A shop on mains that has a generator would be excluded. Filter on GENERATOR only, on MAINS|GENERATOR ('has power now'), or add a has_generator capability column?
- 'Delivers': everything on YouDrop delivers. Does this mean 'delivers to my address' (radius via deliveryRadiusMetres/canDeliver + zone coverage), 'shop runs its own delivery', or something else?
- 'New': unrated (the existing t.ratingNew meaning) or recently joined? If joined, how many days, and from created_at or a new published_at?
- The design drops the district chips and arabizi search the current screen has. Is the neighbourhood now implied by the address (zone), or should district chips stay? Note that store.neighborhood is merchant free text and DeliveryZone.name is a curated list; they will not match without a mapping.
- 'Active nearby shops': should CLOSED/DARK shops be hidden (the heading suggests so) or dimmed (the current rule and the checklist note)?
- Nearby radius for 'your neighbourhood' (e.g. 1.5 km), and whether shops without a pin (excluded by /nearby by design) should still appear via the browse fallback.

### `112:2041` customer-dekkane-shop — L

*Who:* Customer (mobile_app, pushed from HyperlocalScreen)

*What:* The storefront of one neighbourhood dekkane: an inset photo hero with open/closing and power status, category chips, a 2-column inventory grid with USD and LBP prices and one-tap Add to Basket, and a floating 'Chat with <shopkeeper>' button. Audience: customers arriving from the dekkane browse. It is a restyle of the existing StorePageScreen plus a new customer-to-shop chat.

*Reached from:* Pushed from HyperlocalScreen cards and map pins (and from any existing entry to StorePageScreen when the layout is decided by store data). The chat FAB pushes StoreChatScreen. The merchant replies from the new inbox in the merchant shell. The basket bar calls the shell's onOpenBasket (pops to the shell and switches to the Basket tab) as today.

**Every element, and where its data comes from**

- Header: back, title = shop name (18 bold), subtitle = district 'Mar Mikhael' (StoreCard.neighborhood; omit when null), YouDrop logo pill. YdScreenHeader(subtitle, trailing). This DIFFERS from the current StorePageScreen, which uses a SliverAppBar hero with GlassCircleButtons (back/search/favourite). The design has no search or favourite control; decide whether to keep them in trailing.
- Hero card, inset 16px, radius 16: cover photo (StoreCard.coverUrl, full size, as today) under a 45% black overlay (the current code uses ink at 0.4). Top-left pill 'Open · Closes 10PM' (emerald #10b981, white 11 bold; from StoreCard.availability + Store.closesAt via store.closesAtLabel / t.closesAtLabel; StoreStatePill with a composed label; CLOSED/BUSY/CLOSING_SOON variants implied). Top-right pill '⚡ Generator Active' (brand fill; StoreCard.powerStatus; MAINS/DARK variants implied by StorePowerChip, nothing for UNKNOWN). Name (18 extrabold white). Line '★ 4.8 (234 reviews) · Family-run since 1985': rating + ratingCount (t.custRatingsCount exists) + tagline. There is no 'since' field; use tagline.
- Category chips: All (selected), Fresh, Dairy, Snacks, Drinks. Data: storeApi.aisles(storeId) → Aisle.name/categoryId; selecting one refetches products by aisle. Exists as the aisle chip row in StorePageScreen._shopTab, with the 'Everything' label vs the design's 'All'.
- Section label 'SHOP INVENTORY'.
- Product grid, 2 columns, 12px gaps, card radius 16, padding 12: 100px image radius 8 (Product.listImageUrl), name (13 bold, 1 line ellipsis), price '$3.50' (14 extrabold brand), LBP line 'LBP 313,000' (10 faint; MarketRates.instance.lbpParen(price) exists but formats a parenthetical, so a plain variant is needed), full-width 'Add to Basket' button (brand, 12 bold white). Tap Add calls the existing _add flow (option sheet when the product has option groups, then the one-store rule dialog basketFromShopReplace). The current screen draws a LIST of YdCard rows, not a grid. ShelfProductTile (storefront.dart:1033: name, price, imageUrl, quantityInBasket, onAdd/onRemove) is the grid tile to reuse or extend with a secondary price. After the first add, the button should turn into a quantity stepper (the existing row shows qty and remove); the design shows only the unadded state.
- Paging states: first-page spinner, empty (t.nothingOnShelves), load-more footer and its error retry already exist in _pagedProductList/_listFooter.
- Floating 'Chat with Abu Hassan' pill (emerald #10b981, 13 bold white, bottom-end 16px, above the nav). NEW CAPABILITY: no customer-to-shop chat exists. Label from the store or owner name; StoreCard has no owner display name, so use the store name. Opens a chat thread with the shop (see missingBackend). Hide when the capability or flag is off, and when the store has chat disabled.
- Implied but not drawn: StickyBasketBar when the cart is non-empty (exists; must not collide with the chat FAB, so stack the FAB above it); the power banner (custGeneratorBanner/custDarkBanner exist; the design shows the pill instead); a load-failure screen (couldNotLoadShop + tryAgain exists).
- Bottom nav drawn (Home, Shops, Orders, Butler, Account) contradicts CustomerNavBar and the pushed-route pattern. Ignore it.

**Existing code that already covers part of it**

- clients/apps/mobile_app/lib/src/store_page_screen.dart (1165 lines): hero (_hero, line 517) with cover + overlay + name + tag line including closing time; _statStrip (rating/eta/min order); _powerBanner (474); tabs Shop/Aisles/Offers/Buy again (_categoryTabs, 730); aisle chips with YdChip 'Everything' (_shopTab, 788); paged product rows with USD + LBP (862-986); _add with option sheet and one-store conflict dialog (248-345); StickyBasketBar with minimum-order blocking (442-465); favourite toggle; in-shop search.
- clients/packages/delivery_core/lib/src/api/store_api.dart: read (104), products (110), aisles (135), offers (142), productOptions (180).
- clients/packages/delivery_design_system/lib/src/storefront.dart: StoreStatePill (15), RatingChip (74), ShelfProductTile (1033), StickyBasketBar (940).
- clients/apps/mobile_app/lib/src/store_power_chip.dart: StorePowerChip.
- clients/packages/delivery_core/lib/src/util/market_rates.dart:51: MarketRates.lbpParen(usd).
- clients/apps/mobile_app/lib/src/cart.dart: Cart.add/addConfigured/conflictsWith/switchTo.
- Chat, for reference only (order-scoped, cannot be reused as-is): services/app-notification/.../domain/ChatConversation.java ('The merchant is deliberately not in it'), ChatParticipantRole.java (CUSTOMER, RIDER only), V21__order_chat.sql (order_id and rider_id NOT NULL, CHECK customer<>rider, uq_chat_open_per_order); clients/packages/delivery_core/lib/src/api/chat_api.dart (no create call: 'one opens when a rider is assigned, server-side'); clients/apps/mobile_app/lib/src/customer_chat_screen.dart (thread UI, polling every 4s, bubbles, closed bar, idempotent send).

**Missing in the clients**

- A dekkane layout for StorePageScreen: either a `layout: StorePageLayout.dekkane` switch (chosen when StoreCard.neighborhood != null or when opened from HyperlocalScreen) or a DekkaneShopScreen that reuses the state logic (_add, paging, cart rules) by extracting it into a controller. Pieces: YdScreenHeader with neighbourhood subtitle; the inset hero card with StoreStatePill + power pill; the 2-column grid using ShelfProductTile (extend it with an optional secondaryPrice/LBP line and a full-width add button variant); the 'All' label for the first aisle chip.
- A plain LBP formatter (MarketRates currently exposes lbpParen only) so the tile can show 'LBP 313,000' without parentheses, localised digits under ar.
- The chat FAB plus a StoreChatScreen: generalise CustomerChatScreen to take a conversation resolver (order → conversationForOrder, store → conversationForStore) and a title, rather than copy it.
- delivery_core ChatApi: conversationForStore(storeId) (get-or-create) and ChatConversation fields for kind/storeId/storeName; ChatRole gains MERCHANT.
- Merchant side: no chat inbox exists in delivery_merchant (only whatsapp_screen.dart mentions chat) or in the portal merchant web. Needed: a conversations list + thread screen in delivery_merchant, reachable from the merchant shell (mobile merchant_shell.dart and portal lib/src/merchant), with an unread badge from ChatApi.unreadCount.

**Missing in the backend**

- app-notification (owns /api/chat; ingress already routes /api/chat in deploy/k3s/overlays/{dev,qa}/ingress.yaml:118 and infra/traefik/dynamic/routes.yml:179): a store conversation type. Recommended migration V22__store_chat.sql: add kind ('ORDER'|'STORE') and store_id to chat_conversations, make order_id/rider_id nullable with per-kind CHECK constraints, add a unique (store_id, customer_id) WHERE kind='STORE', and allow sender_role 'MERCHANT'. Alternatively a separate store_conversations table; the chat_messages FK then needs its own table. The current security model (membership = two columns) must stay a two-column check: customer_id + store_id resolved to the store's merchant.
- app-notification: ChatService.openForStore(storeId, customerId) (get-or-create, idempotent), POST or GET /api/chat/stores/{storeId}/conversation; roleOf/counterpartOf for MERCHANT; conversationsFor(merchantId) listing store threads. It needs to know who owns the store: either call product-service (GET /api/stores/{id} carries merchantId?) or consume a store.owner projection event. Store staff (store_staff_api.dart exists client-side) may need access too; decide.
- app-notification: a closing policy for store threads (there is no order lifecycle to close them), e.g. never close, or close after N days idle; and a merchant-side 'mute/disable chat' per store (a product-service store flag, e.g. chat_enabled).
- notifications-manager ChatEventListener (chat.# queue): the push for a missed message must resolve a MERCHANT recipient and link to the merchant inbox (NotificationLinkTarget).
- No product-service change is needed for the shop page itself: StoreCardResponse/StoreResponse already carry neighborhood, powerStatus, availability, closesAt, rating, ratingCount.

**Design-system pieces to reuse**

- StorePageScreen state and flows (_add, paging, cart rules, favourite, search)
- YdScreenHeader, YdChip, StoreStatePill, StorePowerChip, ShelfProductTile, StickyBasketBar, CustomerPhoto
- CustomerChatScreen bubble/composer/closed-bar widgets (extract into a shared chat thread widget)
- RiderChatScreen's live-socket path (ChatApi.live(UserQueueSocket) + reconnecting strip) for a better merchant inbox than 4s polling
- Tokens: DeliveryColors.brand/brandSoft/ink/muted/faint/border/white, DeliveryAccent.positive (the emerald open pill and chat FAB), DeliveryRadius.lg (16) / md (8)

**Strings**

- reuse: closesAtLabel, custRatingsCount, custPowerGenerator, custGeneratorBanner, custDarkBanner, nothingOnShelves, couldNotLoadShop, tryAgain, everything (or add custAll), basketFromShopReplace, chatTypeMessage, chatSend, chatClosed, chatCouldNotSend, couldNotLoadChat, chatNoMessagesYet
- new: custShopInventory 'Shop inventory'
- new: custOpenClosesAt 'Open · Closes {time}'
- new: custAddToBasket 'Add to basket' (check for an existing add key first)
- new: custChatWithShop 'Chat with {name}'
- new: custShopChatTitle '{store}'
- new: merchChatInboxTitle 'Customer messages', merchChatEmpty, merchChatUnread
- new: custLbpAmount 'LBP {amount}'
- All need Arabic translations.

**Tests that should prove it**

- Widget: dekkane layout shows the neighbourhood subtitle; 'Open · Closes 10PM' comes from availability OPEN + closesAt; a CLOSED store shows the closed pill and still browses; the generator pill appears only for GENERATOR.
- Widget: the grid renders 2 columns; Add to Basket on a product without options calls cart.add; with options it opens ProductOptionsSheet; from another shop it shows the replace-basket dialog (the one-store rule); the LBP line shows only when a market rate is loaded.
- Widget: the aisle chip 'All' clears the aisle filter and the products call has no category param.
- Widget: the chat FAB is absent when chatApi is null or the store has chat disabled; tapping it calls conversationForStore and pushes the thread; the FAB and StickyBasketBar do not overlap (golden or layout assertion).
- Java (app-notification ChatServiceTest): openForStore is idempotent per (store, customer); the owning merchant can read and post; another merchant or customer gets ConversationNotFound (404, indistinguishable from not existing); a MessageView never exposes sender ids; the ORDER-kind invariants (uq_chat_open_per_order, CHECK) still hold.
- Java (notifications-manager ChatEventListenerTest): a store-chat message missed by the merchant pushes the merchant with the inbox link.
- API scenario: a customer GETs /api/chat/stores/{id}/conversation twice and receives the same id; the merchant token sees it in GET /api/chat/conversations; the merchant posts, and the customer's GET messages?afterSequence=n returns it.

**Questions**

- Should the dekkane layout replace StorePageScreen for every shop with a neighbourhood, or only when opened from the neighbourhood browse? And are the Offers/Buy again tabs, in-shop search and favourite dropped for dekkanes, as the design suggests?
- Customer-to-shop chat is a new trust surface. The existing chat model intentionally keeps merchants out of customer conversations. Is chat pre-order only (questions about stock), and may it reference an order? Who answers for a shop with staff (owner only, or staff via store_staff)? What are the response expectations, business hours, and closing rules?
- 'Chat with Abu Hassan' implies an owner display name, which is not in the data (StoreCard has the store name only). Add an optional 'shopkeeper name' to the store profile, or label with the store name?
- 'Family-run since 1985' has no field. Is tagline acceptable?

### `121:102` neighborhood-chat — XL

*Who:* Customer (mobile_app); moderators in the back office (implied)

*What:* A public, live community chat room per neighbourhood ('Mar Mikhael Chat'): residents talk to each other with name and avatar, and a system 'YouDrop Butler AI' posts shop or product recommendation cards with an inline Order CTA. Audience: customers in that neighbourhood. It is an entirely new feature: group chat, user-generated content between strangers, and an AI recommender, none of which exist.

*Reached from:* Home tab (StoreHomeScreen) → 'Neighborhood chat' entry (card or header action) → push NeighborhoodChatScreen for the room of the active address's zone. Also reachable from the HyperlocalScreen header and from a notification deep link. A recommendation card CTA pushes StorePageScreen (dekkane layout) with cart/onOpenBasket from the shell. The design's visible nav bar (Home active) would require making this a tab, which conflicts with the fixed 5-tab CustomerNavBar (tabCount = 5), so keep it as a pushed route.

**Every element, and where its data comes from**

- Header: back (16px chevron in a #f8fafc disc), title '{Neighbourhood} Chat' (18 bold), LIVE pill (#dcfce7 bg, emerald dot + 'LIVE' 10 bold #10b981; bound to socket-connected state), subtitle '1.2k neighbors active' (12 muted; presence count, no source today), a 'Community' tag on the right (brandSoft bg, brand 11 bold). YdScreenHeader(title, subtitle, trailing) plus a small LIVE badge (YdBadge with positive colours).
- Message row from a neighbour: 32px round avatar (profile avatar URL, onboarding-service /api/profile avatar), name 'Tania K.' (13 bold ink; first name + last initial), time '10:02 AM' (10 faint; MaterialLocalizations.formatTimeOfDay as CustomerChatScreen does), and a bubble (white, 1px border, radius 12 with square top-start corner, max width 280, 13 regular ink). All messages are drawn on the start side; the design shows no own-message variant, but one is implied (end-aligned brand bubble as in CustomerChatScreen._bubble).
- System message from 'YouDrop Butler AI' (brand name, 'System • Instantly' faint): a recommendation card (white, 1px brand border, radius 12, rose shadow, width 280) with a 50px image, name 'Hallab 1881 Kasr El Helou', '0.3km away • 25 mins' (distance + StoreCard.etaLabel), '★ 4.8 (1.2k+ ratings)' (emerald), and a full-width brand 'Order Knefeh Now' button pushing StorePageScreen (or the product detail). DESIGN BUG: the card's content row is fixed at 50px wide, so the Figma render shows only the image in a tall empty card. Implement the intended image-left, three-lines-right layout; do not copy the geometry.
- Composer bar (white, top border): camera button (attach photo; chat messages are text-only today), rounded input 'Type message or ask neighbor...' with a location glyph inside (share location? see questions), and a round brand send button (14px send glyph). Reuse the CustomerChatScreen composer (TextField min 1 / max 4 lines, TextInputAction.send, idempotent send with a reused clientMessageId).
- States implied: loading thread, empty room ('Be the first to say hello'), load error + retry, socket down (LIVE pill turns to a 'Reconnecting…' strip, as RiderChatScreen does), send failure snackbar, message too long (422 from ChatMessageText.normalise, 1000 code points), muted/banned (composer replaced by an explanatory bar, like _closedBar), not in any neighbourhood (no zone on the address, so pick an area first), and history paging upward.
- Moderation affordances (not drawn but required for UGC): long-press a message for Report / Block user / Copy; a room rules sheet; hidden-message placeholder.
- Bottom nav drawn with Home (active), Butler, Basket, Orders, Account, which MATCHES the shipped CustomerNavBar. The nav is visible, so the design treats this as a Home sub-page. In code it will be a pushed route (nav hidden) unless it becomes a tab; decide.

**Existing code that already covers part of it**

- clients/packages/delivery_core/lib/src/api/chat_api.dart: REST + STOMP patterns to copy (afterSequence cursor, clientMessageId idempotency, markRead cursor, unreadCount, live() on /user/queue/chat). All of it is two-party and order-scoped.
- clients/packages/delivery_core/lib/src/models/chat_models.dart: ChatRole, ChatMessageState, ChatMessage (mine, role, no sender identity), ChatConversation, ChatUnreadSummary, ChatFrame.
- clients/apps/mobile_app/lib/src/customer_chat_screen.dart: thread list (reversed ListView), bubble, composer, closed bar, 4s polling, 409/422 handling.
- clients/apps/mobile_app/lib/src/rider_chat_screen.dart: live frames via ChatApi.live(UserQueueSocket), reconnecting strip (riderChatReconnecting), refetch on reconnect.
- services/app-notification/src/main/java/com/delivery/appnotification/: ChatController (/api/chat/*), ChatService (sequence claim under row lock, post, thread, markRead), ChatMessageText (normalise: refuse too long / control chars, no truncation; ChatProperties.maxMessageLength 1000), ChatDelivery (after-commit STOMP to the recipient's user queue), config/WebSocketConfiguration (client SEND refused by design), api/ChatBackofficeController + domain/TranscriptAccess (audited support reads, V21 chat_transcript_access).
- services/notifications-manager/.../event/ChatEventListener.java: push for missed chat messages (chat.# queue, deduplicated by message id).
- services/onboarding-service/.../api/UserProfileController.java and UserSearchController.java: /api/profile (avatar; ProfileApi.myAvatarUrl/uploadAvatar/search).
- services/product-service/.../service/CrossSellService.java: the platform's stated stance that recommendations must be evidence-based ('every number on a rail filled that way would be invented'). There is no AI or LLM integration anywhere in services (grep found none).
- clients/packages/delivery_core/lib/src/api/delivery_zone_api.dart + models/zone_models.dart: DeliveryZone(id, name, region), the only curated neighbourhood list that exists.

**Missing in the clients**

- NeighborhoodChatScreen (mobile_app/lib/src/neighborhood_chat_screen.dart): room header with LIVE/presence, a paged thread (newest at the bottom, load older on scroll-up), multi-author bubbles with avatar/name/time, own-message variant, a system recommendation card widget, composer (text first; camera/location only if approved), long-press menu (report/block), muted/banned bar, reconnecting strip.
- A shared chat thread widget extracted from CustomerChatScreen and RiderChatScreen so the three screens do not drift.
- delivery_core: CommunityApi (or ChatApi methods): myRoom()/room(zoneId), join/leave, messages(roomId, afterSequence|beforeSequence), send(roomId, text, clientMessageId), report(messageId, reason), block(userId-handle), presence(roomId); live(roomId) subscribing to a room topic on the existing UserQueueSocket.
- Models: CommunityRoom(id, zoneId, name, activeCount, live), CommunityMessage(id, sequence, kind TEXT|SYSTEM_RECOMMENDATION|HIDDEN, author {handle, displayName, avatarUrl}, mine, text, sentAt, recommendation {storeId, productId?, name, imageUrl, distanceMetres, etaLabel, rating, ratingCount, ctaLabel}).
- Entry points: a Home entry (the design marks Home active), a header action on HyperlocalScreen, and a notification deep link. CustomerShell must pass chatApi/socket down (it already holds chatApi and trackingSocket).
- Back office (portal): a moderation queue screen (reported messages, hide, ban) under delivery_portal/lib/src/backoffice; none exists.

**Missing in the backend**

- app-notification (keeps /api/chat routing, no ingress change if under /api/chat/rooms): migration V23__community_chat.sql with community_rooms (id, zone_id unique, name, created_at), community_members (room_id, user_id varchar(64), display_name, avatar_url, joined_at, muted_until, banned_at, PK room+user), community_messages (id, room_id, sequence_no, sender_id, kind, body text, payload jsonb, client_message_id, created_at, hidden_at, hidden_by, UNIQUE room+seq and room+client id), community_reports (id, message_id, reporter_id, reason, created_at, UNIQUE message+reporter), community_blocks (user_id, blocked_user_id).
- app-notification endpoints: GET /api/chat/rooms/mine?zoneId (membership derived from the caller's delivery zone; the server must verify the zone rather than trust the client, or accept self-selection as a product decision); POST /api/chat/rooms/{id}/join; GET /api/chat/rooms/{id}/messages?afterSequence|beforeSequence&limit; POST /api/chat/rooms/{id}/messages (ChatMessageText.normalise, per-user rate limit, idempotent); POST /api/chat/rooms/messages/{id}/report; POST/DELETE /api/chat/rooms/blocks; GET /api/chat/rooms/{id}/presence. The message view exposes an opaque per-room handle + display name, never the Keycloak sub (same principle as MessageView).
- app-notification realtime: broadcast to a room topic (e.g. /topic/rooms.{id}) with a STOMP subscription interceptor that checks membership, extending WebSocketConfiguration (client SEND stays refused; posting stays REST). Presence counting from subscriptions.
- app-notification back office: extend ChatBackofficeController with GET reported messages, POST hide message, POST ban/mute member, audited like TranscriptAccess; hidden messages are tombstoned, not deleted.
- Display names: nothing in app-notification reads name claims today. Snapshot given_name + family_name initial from the JWT at join time, or fetch from onboarding-service's profile. The avatar URL comes from onboarding-service; check that it is not a private presigned URL that expires.
- Recommendation bot ('Butler AI'): no service exists, and an LLM integration would be new infrastructure, cost and a policy decision. A non-LLM first cut: a rule/keyword matcher over new messages (arabizi-aware, like custSearchArabiziHint) that calls product-service search and /api/stores/nearby (room zone centroid) and posts a SYSTEM_RECOMMENDATION message with real store data. Needs a cross-store product search endpoint (verify whether ProductController supports one) and a zone centroid (delivery zones have no geometry exposed to the client today).
- notifications-manager: decide the push policy for rooms (likely none, or mentions only). ChatEventListener must not push every room message to every member.
- Images (camera): a presigned upload flow (pattern: product-service StoreImageService presign/confirm) plus image moderation. Recommend deferring out of v1.

**Design-system pieces to reuse**

- CustomerChatScreen / RiderChatScreen thread, composer, closed bar and reconnecting strip (extract a shared widget)
- ChatApi.live + UserQueueSocket for realtime
- ChatMessageText.normalise and the sequence-under-row-lock pattern in ChatService
- ChatBackofficeController + TranscriptAccess audit pattern for moderation
- StoreCard/NearbyStore models for recommendation cards; RatingChip; YdPillButton for the CTA
- YdScreenHeader, YdBadge (LIVE, Community), YdEmptyState, StoreAvatar for the avatar fallback (monogram)
- Tokens: DeliveryColors.brand, brandSoft, ink, muted, faint, border, background, white; DeliveryAccent.positive (LIVE, rating line); DeliveryRadius.lg/pill

**Strings**

- reuse: chatSend, chatCouldNotSend, couldNotLoadChat, tryAgain, back, riderChatReconnecting (or a customer-side equivalent)
- new: communityRoomTitle '{area} chat'
- new: communityLive 'LIVE'
- new: communityActiveCount '{count, plural, one{1 neighbour active} other{{count} neighbours active}}'
- new: communityTag 'Community'
- new: communityComposerHint 'Type a message or ask a neighbour…'
- new: communityAttachPhoto, communityShareLocation (semantics labels)
- new: communityButlerName 'YouDrop Butler', communitySystemLabel 'System'
- new: communityOrderCta 'Order {item} now'
- new: communityDistanceEta '{distance} away • {eta}'
- new: communityEmpty 'No messages yet — say hello to your neighbours'
- new: communityCouldNotLoad
- new: communityPickArea 'Choose your area to join its chat'
- new: communityReport 'Report', communityReportSent 'Thanks — a moderator will review it'
- new: communityBlock 'Block', communityBlocked
- new: communityMuted 'You can’t post here right now'
- new: communityHidden 'This message was removed'
- new: communityRules 'Community rules'
- new: communityTooLong 'That message is too long'
- All need Arabic translations; the ICU plural needs Arabic plural forms.

**Tests that should prove it**

- Java (app-notification, new CommunityServiceTest): join only a room matching the member's zone; a post by a non-member is 404; a banned member is refused (403); rate limit; idempotent retry returns the same message; sequence is gapless under concurrent posts (row lock as ChatService); a hidden message returns as a HIDDEN tombstone with no body; views never contain sender_id.
- Java (WebSocketConfigurationTest extension): a SUBSCRIBE to /topic/rooms.{id} by a non-member is rejected; client SEND is still refused.
- Java (back-office moderation): hide/ban require BACKOFFICE and write an audit row; report is unique per (message, reporter).
- Java (recommendation bot, if built): a message mentioning 'knefe' produces at most one recommendation card per window, only for ACTIVE stores within radius, with real rating/eta/distance (no invented numbers, per the CrossSellService rule).
- Widget: renders multi-author bubbles with name/avatar/time; own messages end-aligned; the recommendation card CTA pushes StorePageScreen; long-press offers Report/Block and a blocked author's messages disappear; the composer is disabled for a muted member with an explanation; socket-down shows the reconnecting strip and hides LIVE; the empty room state; RTL layout (arabic_rtl_test.dart).
- API scenario: two customers in the same zone join, A posts, and B receives it via GET messages?afterSequence and the topic; a customer in another zone gets 404 on the room; B reports, and the moderator hides it, so both see the tombstone.

**Questions**

- Is a public neighbourhood chat in scope at all for v1? It is user-generated content between strangers, so the app stores require report/block/moderation, and Lebanon has privacy implications (first name + initial + photo shown to ~1k neighbours). Who moderates, and within what SLA?
- What defines 'your neighbourhood' room: the delivery zone of the active address (curated, recommended), store.neighborhood free text, or self-selection? Can a user be in several rooms (home + work address)?
- 'YouDrop Butler AI': is an LLM in scope (vendor, cost, data sent, Arabic/arabizi quality), or is a deterministic keyword-to-shop recommender acceptable? This touches the platform's evidence-only recommendation stance (CrossSellService). And is the 'Butler' brand tied to the Butler errand service (ButlerScreen)?
- Composer location glyph: share the user's precise location with the whole room? That is a strong privacy risk. Recommend dropping it or limiting to sharing a shop.
- Camera attachments in v1, or text only? Media needs storage, moderation and retention rules.
- Retention: how long are room messages kept, and can users delete their own?
- Where does '1.2k neighbors active' come from (live socket subscribers, members active in 24h, or all members)? Presence counts leak activity patterns in small rooms; show them only above a threshold?

**Build order for this cluster**

- 1. Unblock the data (S, product-service + merchant client). Add a neighbourhood field to the merchant store form (delivery_merchant/lib/src/store_screen.dart) and send 'neighborhood' from StoreApi.updateProfile. Today every profile save nulls it via StoreService.update, so the district list is always empty. Add a regression test. Add the BACKOFFICE-only PUT /api/stores/{id}/verified-local, Store grant/revoke, and a minimal portal back-office toggle; without it 'Trusted Local' can never show.
- 2. Make HyperlocalScreen reachable (S): an entry on StoreHomeScreen that pushes it with cart/orderApi/onOpenBasket, plus a reachability widget test. It ships value immediately on the existing district browse.
- 3. Restyle HyperlocalScreen to frame 112:1941 on existing data (M): header subtitle + logo, location bar from DeliveryAddressStore, large cover cards with Trusted Local / generator pill / rating, attribute chips (Open Now and Has Generator filtered client-side from StoreCard for now), first-page error state, l10n en+ar, widget + RTL tests.
- 4. Distance and map (M): extend GET /api/stores/nearby with openNow/powerStatus/verifiedLocal/newSinceDays/neighborhood filters (Java post-filters in StoreService.nearby), add createdAt/isNew to StoreCardResponse, switch the screen to nearby when the address has a point (distance label), add the map preview + NeighborhoodMapScreen with flutter_map. Browse stays the fallback without a point. NearbyStoreSearchTest additions.
- 5. Dekkane shop layout (M): a StorePageScreen variant for frame 112:2041 (inset hero with StoreStatePill + power pill, neighbourhood subtitle, 'All' aisle chip, 2-column ShelfProductTile grid with a plain LBP line, reusing the existing _add/one-store/option-sheet flows). The chat FAB stays hidden behind a flag.
- 6. Customer-to-shop chat (L): app-notification migration for STORE conversations (kind, store_id, MERCHANT role, per-kind CHECKs, unique store+customer), openForStore + GET /api/chat/stores/{storeId}/conversation, merchant ownership resolution from product-service, a closing/disable policy, notifications-manager merchant push; client ChatApi.conversationForStore, a generalised chat thread screen, the merchant inbox in delivery_merchant (mobile + portal merchant shells). Then turn on the FAB.
- 7. Neighbourhood chat (XL), only after the product/legal decisions on moderation, identity display, room definition, AI and media: rooms/members/messages/reports/blocks migration in app-notification, REST under /api/chat/rooms, a topic broadcast with membership-checked subscriptions, back-office moderation endpoints + portal queue, NeighborhoodChatScreen (text-only v1) with report/block, then presence. The recommendation bot comes last, starting with a deterministic keyword → nearby-shop recommender using real store data.

**Cross-cutting**

- Screenshots saved: D:/dev-cache/temp/claude/D--workspace-azkar/709fbe40-df14-4950-b9b5-9dbd338df9ab/scratchpad/figma/112-1941_customer-dekkane-browse.png, .../112-2041_customer-dekkane-shop.png, .../121-102_neighborhood-chat.png
- Bottom navs contradict each other and the code. Both dekkane frames draw Home, Shops, Orders, Butler, Account (there is no Shops tab), while the chat frame and the shipped CustomerNavBar (customer_nav_bar.dart: Home, Butler, Basket, Orders, Account, tabCount 5) agree. Treat all three screens as routes pushed over CustomerShell (nav hidden), as ShopsListingScreen and StorePageScreen are today.
- Colour and wording conflicts with shipped widgets. The design's generator pill is brand rose; StorePowerChip draws generator in amber (#B8860B on #FDF3D7). The design's 'Trusted Local' badge is rose; VerifiedLocalBadge is green with the string custVerifiedLocal 'Verified Local'. The design's rating star is amber #f59e0b; HyperlocalScreen draws it in brand. The title changes from 'Neighborhood Dekkane' to 'Your Neighborhood'. Decide once and apply everywhere power/verified chips appear (home cards, store page, dekkane screens).
- Two incompatible 'neighbourhood' vocabularies. stores.neighborhood is merchant free text (VARCHAR 80, exact-match filter) while DeliveryZone.name is the curated area list on customer addresses. The location bar, the district filter and the chat room all need one canonical key; recommend moving store.neighborhood to a zone id (or a validated pick from zones) before building the chat.
- Real-data blockers found while tracing: no client ever writes stores.neighborhood (and the profile PUT overwrites it with null), and no code path can set stores.verified_local. On dev, the district chips and trust badges will be empty until build step 1 lands.
- Chat architecture. The existing chat (app-notification, V21) is deliberately two-party and order-scoped, with the merchant explicitly excluded and sender identity never exposed. Shop chat and community chat each break one of those principles on purpose, so they need explicit product sign-off and their own membership rules rather than loosening ChatConversation.isParticipant.
- The Figma content is placeholder (Abu Hassan, Hallab, prices). The chat frame's recommendation card has a layout bug (content row fixed at 50px); implement the evident intent.
- l10n: every new string needs en + ar in clients/packages/delivery_l10n/lib/l10n/app_en.arb / app_ar.arb, then regenerate the generated AppLocalizations. Distances, LBP amounts and counts need locale-aware number formatting.
- Deployment: product-service and app-notification are both deployed on dev. Anything under /api/stores and /api/chat is already routed (deploy/k3s/overlays/*/ingress.yaml, infra/traefik/dynamic/routes.yml); a new /api/community prefix would need ingress changes in all overlays plus the traefik file, so keep new chat endpoints under /api/chat.

## Carrier web: riders directory, rider profile, attendance

### `112:413` web-carrier-riders-directory — M

*Who:* Carrier (delivery company) office staff: a dispatcher or operations manager holding the CARRIER realm role, signed in to the delivery_portal web console. Not riders, not Backoffice.

*What:* The company's rider roster as a card grid. It shows who rides for the company, what state each rider is in right now (active, on break, offline, suspended), their region, vehicle, rating and deliveries today, with search and zone/vehicle filters, and an entry point to add a rider and to open one rider's HR profile. Most of this already exists as a TABLE in CompanyScreen ('Riders Management', from the older Figma 3:3589). In the deployed build that page is largely dead, because the shell does not pass it four of its API clients.

*Reached from:* Carrier area of the delivery_portal rail (PortalArea.carrier_ in portal_shell.dart). Replace or rename destination index 4 (today t.navCompany 'Company' → CompanyScreen 'Riders Management') with 'Riders' (design: 'Riders HR'). Keep its index so the dashboard's onShowJobs jump(1) and others keep their meaning. 'Add Rider' opens the existing _WaitingList console drawer; 'Manage Profile' opens 112:740. The Applicants destination (index 5) stays as the full review queue.

**Every element, and where its data comes from**

- SIDEBAR (design 112:414, shared chrome). Brand tile 'YD', wordmark 'YouDrop / CARRIER BACKOFFICE', and a carrier pill: company monogram 'LE', name 'Libanex Express', and 'Beirut Hub • ID: #4051'. Nav: Dashboard, Orders, Fleet, Reconciliation, Riders HR (active, brandSoft bg, brand text), Earnings, Coverage, Settings. Footer card: avatar 'KM', 'Kamal M.', 'Operations Manager', log-out icon. DATA: company name comes from DeliveryProviderApi.myCompany().name. The hub/region line would come from ProviderProfile (ProviderProfileApi.profile(providerId)); '#4051' has no source, since provider ids are UUIDs and only the slug exists. The user name comes from AuthSession.displayName. The role line in the code is deliberately t.carrierPartner, NOT a job title (portal_shell.dart comment: the token carries no job title). The existing ConsoleSidebar in portal_shell.dart differs: wordmark 'Carrier Hub', no carrier pill, and 7 items (Dashboard, Jobs, Earnings, Statement, Company, Applicants, Settings). Treat this as a shell-cluster decision; for this cluster only the 'Riders HR' destination matters.
- TOPBAR. Title 'Riders HR Directory', subtitle 'Manage rider profile lifecycle, status and zone assignments'. Use ConsoleTopbar inside ConsolePage.
- LIVE BADGE 'Beirut Live (34 Riders)' (green dot, positive tint). 34 equals the Total Onboarded count, so it reads as fleet size, not on-duty count. City label: the first dispatch region from ProviderProfile, else omit the city. Count: myRiders().length, or roster ON_DUTY count if product says 'live' means on duty. Needs a product answer.
- BELL (topbar-right). ConsoleBell is now exported from shell/shell.dart (line 16), so it can replace the inert ConsoleIconAction every carrier page still draws. It needs a NotificationApi threaded into the carrier area; PortalApis.notification already exists.
- STAT CARD 1: 'TOTAL ONBOARDED RIDERS' 34, 'Registered company fleet'. DATA: DeliveryProviderApi.myRiders() (GET /api/delivery-providers/my-company/riders), list length.
- STAT CARD 2: 'ACTIVE ON DUTY' 18 (positive green), 'Delivering now live'. DATA: TrackingApi.roster(onDutyOnly:false) (GET /api/tracking/riders/roster), counting state == PresenceState.onDuty. The caption is wrong against backend semantics: ON_DUTY means 'declared available and pinging', not 'delivering'. Suggest the caption 'Available or on a job'.
- STAT CARD 3: 'ON BREAK' 5 (info blue), 'Temp offline status'. NO SOURCE. DutyState has only ON_DUTY and OFF_DUTY; PresenceState is ON_DUTY, STALE or OFF_DUTY (order-tracking domain/DutyState.java, PresenceState.java). STALE means 'signal lost' and must not be relabelled 'On break'. Either drop the card, show STALE as 'Signal lost' (caution), or build a real ON_BREAK duty state (see missingBackend).
- STAT CARD 4: 'OFFLINE / INACTIVE' 11 (muted), 'Ready for assignable shifts'. DATA: riders whose presence is OFF_DUTY, plus riders absent from the roster (never declared duty). The caption implies shift assignment, which does not exist.
- SEARCH FIELD 'Search riders by name, ID...' (260px). A client-side filter on the application contactName, the application reference or the 8-char short rider ref, same as CompanyScreen._matches. Use ConsoleSearchField (the in-card variant, not .global, since it sits in the filter card).
- ZONE FILTER 'Zone: All Beirut' (dropdown). NO rider-to-zone link exists in any service; backoffice/riders_screen.dart says so explicitly. The only available value is the free-text region the rider typed in their application: details keys workRegion/region/city/area, per _Fleet.regionOf. Either filter on distinct free-text regions, or build a real zone assignment against the company's CoverageZones (DeliveryProviderApi.myZones()). Use ConsoleSelect.
- VEHICLE FILTER 'Vehicle: Motorcycle' (dropdown). DATA: OnboardingApplication.details['vehicleType']. It is written by mobile_app partner_application_screen.dart:576 as the enum wire, and the website register uses MOTORCYCLE/CAR/VAN/TRUCK. Options: All plus the distinct values present. Use ConsoleSelect.
- BUTTON 'Add Rider' (brand, plus icon). Riders cannot be created directly: they apply, and a hire creates their Keycloak account (OnboardingApi.hire). Reuse CompanyScreen._WaitingList drawer ('Add a rider', approve in place), which is only enabled when OnboardingApi is passed. Irreversible, so keep t.hiringAlsoCreatesTheirAccount above the Approve button. Use ConsolePrimaryButton.
- RIDER CARD GRID. Wrapping cards 268px wide, 16px gap, white, 1px border, radius 16, padding 20. Per card:
-   - Card header id '#YK-884' (faint, 11px). The platform has no human badge code. Use OnboardingApplication.reference (exists on the model), else the uppercase 8-char Keycloak-sub short ref (CompanyScreen._shortRef).
-   - Status badge: 'Active' (positive), 'On Break' (info), 'Offline' (neutral), 'Suspended' (critical). DATA precedence as in CompanyScreen._statusCell: suspension (PartnerManagementApi.riderSuspension(providerId, applicationId).suspended), then roster presence, then 'On a job' when holding a non-terminal job from OrderApi.forCarrier, then unknown. Use ConsoleStatusPill.
-   - Avatar with initials (48px circle, brandSoft bg, brand text). Use ConsoleAvatar (console_controls.dart:476).
-   - Name 'Youssef Kanaan'. DATA: OnboardingApplication.contactName via OnboardingApi.forCompany(companyId, all:true), keyed on provisionedUserRef. Riders attached directly by Backoffice have no application and fall back to the short ref.
-   - Rating row: star, '4.8', '(14 Today)'. Rating DATA: OrderApi.riderRating(riderId) → RiderStanding.average (GET /api/riders/{riderId}/rating, @PreAuthorize isAuthenticated, so CARRIER may read it). Render null as 'New', never 0, as backoffice riders_screen.dart already does. '14 Today' DATA: RiderPerformanceApi.deliveredToday() (GET /api/orders/riders/delivered-today, CARRIER-scoped); a missing rider means 0. NOTE: CompanyScreen's comment and table footer 'Nothing on this platform rates a rider' are STALE; RiderRatingController exists in order-manager.
-   - Divider line.
-   - Zone row (map-pin, 'Beirut Central'): the free-text region from the application details, else '—'.
-   - Vehicle row (navigation icon, 'motorcycle'): details['vehicleType'], lower-cased label. Localise the enum label instead of printing the wire.
-   - Button 'Manage Profile' (outlined, full width). Opens the rider HR profile (frame 112:740). Clicking the whole card could do the same, mirroring ConsoleTableRow onTap.
- STATES (implied, not drawn). Loading: page spinner, as CompanyScreen does. 404 no company: Icons.help_outline + t.noCompanyYet + t.askThePlatformToAttachYou. Empty fleet: t.noRidersBlurb. Filtered-empty: 'No rider matches that.'. Partial enrichment failure: each derived field shows the faint '—' (_Unknown) rather than zero, and stat cards show '—' when their source failed. 503 from roster ('Fleet unavailable'): treat as unknown presence, not 'everyone offline'.

**Existing code that already covers part of it**

- D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/company_screen.dart — 'Riders Management' TABLE (Figma 3:3589). The _Fleet loader already joins myCompany + myScore + myRiders + forCarrier(size:100) + onboarding.forCompany + tracking.roster(onDutyOnly:false) + performance.deliveredToday + per-rider riderSuspension. It has nameOf/regionOf/joinedOn/isWorkingNow/deliveredBy, search, 'All / Working now' tabs, 'Add New Rider' → _WaitingList drawer (hire in place), the row eye → _RiderDetail drawer, and row suspend/reinstate → _StandingDialog. Below the table: the company score card and the pause/resume switch.
- D:/workspace/delivery/clients/apps/delivery_portal/lib/src/portal_shell.dart:367-373 — carrier destination index 4 (label t.navCompany 'Company') builds CompanyScreen(api: a.provider, orderApi: a.order) and does NOT pass onboardingApi, managementApi, trackingApi or performanceApi. All four exist on PortalApis (onboarding, partnerManagement, tracking, riderPerformance). This is why the checklist marks CompanyScreen UNREACHABLE: in the shipped build Region, Join Date, Status, Add Rider and Suspend are all dead.
- D:/workspace/delivery/clients/packages/delivery_core/lib/src/api/delivery_provider_api.dart — myCompany(), myRiders() (a List<String> of Keycloak subs only), myZones(), myScore().
- D:/workspace/delivery/clients/packages/delivery_core/lib/src/api/tracking_api.dart — roster({onDutyOnly}), riderDutyHours(riderId, days≤30), riderLocation().
- D:/workspace/delivery/clients/packages/delivery_core/lib/src/api/rider_performance_api.dart — deliveredToday(), forRider(riderId).
- D:/workspace/delivery/clients/packages/delivery_core/lib/src/api/order_api.dart:216-275 — riderRating(riderId) → RiderStanding; riderRatingComments is BACKOFFICE-only.
- D:/workspace/delivery/clients/packages/delivery_core/lib/src/api/partner_management_api.dart:80-91 — suspendRider / unsuspendRider / riderSuspension (carrier-scoped /api/onboarding/applications/for-company/{providerId}/{id}/...).
- D:/workspace/delivery/clients/packages/delivery_core/lib/src/models/onboarding_models.dart — OnboardingApplication (id, reference, contactName, contactEmail, contactPhone, createdAt, decidedAt, provisionedUserRef, details map).
- D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/riders_screen.dart — the Backoffice roster. It already does the N+1 riderRating fan-out and renders 'New' for unrated riders, a pattern to copy.
- D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/applicants_screen.dart — the fully wired hire/turn-down flow and applicant cards grid (a 1-3 across wrap, min 340px), a good layout reference for the card grid.
- D:/workspace/delivery/clients/apps/mobile_app/lib/src/carrier_shell.dart — mobile Fleet tab (read-only rider cards), the same roster on the phone.
- D:/workspace/delivery/services/order-manager/src/main/java/com/delivery/order/api/DeliveryProviderController.java:239 — GET /my-company/riders (CARRIER).
- D:/workspace/delivery/services/order-tracking/src/main/java/com/delivery/tracking/api/RiderPresenceController.java — GET /api/tracking/riders/roster (BACKOFFICE, CARRIER; carrier scope comes from membership, never the request).
- D:/workspace/delivery/services/order-manager/src/main/java/com/delivery/order/api/RiderRatingController.java:136 — GET /api/riders/{riderId}/rating, isAuthenticated.
- D:/workspace/delivery/clients/apps/delivery_portal/test/carrier/company_screen_test.dart — the _StubAdapter harness (path-suffix routing), plus wired:true/false and Arabic cases, to reuse for the new tests.

**Missing in the clients**

- Wire the four optional clients into CompanyScreen in portal_shell.dart (a.onboarding, a.partnerManagement, a.tracking, a.riderPerformance). A one-line change that revives most of the existing page. Do it first.
- A card-grid presentation of the roster: a new private _RiderCard widget in carrier/, or a new RidersDirectoryScreen that reuses the _Fleet loader. Extract _Fleet and _load() out of company_screen.dart into a shared carrier/fleet_roster.dart so the directory, the profile and attendance share one loader.
- A stats row of four ConsoleKpiCard in a ConsoleKpiRow, computed from the loaded _Fleet.
- Zone and vehicle ConsoleSelect filters. Parse details['vehicleType'] into a typed enum with localised labels; there is no Dart VehicleType enum in delivery_core today (mobile partner_application_screen has a private one).
- Rating per rider: add orderApi.riderRating fan-out to the loader, tolerate failures, and render 'New' when unrated. Delete the stale 'Rating is not recorded on this platform' footer and comments.
- Live badge and ConsoleBell in the topbar (pass notificationApi to the carrier destination).
- Navigation from a card to the profile page. The portal has no router: the shell swaps destination widgets by index. Either push a MaterialPageRoute inside the destination's Navigator, or hold the selected rider in the directory's state and render the profile in place with a back affordance.
- Rail label: rename the destination to 'Riders' via a new l10n key (the design says 'Riders HR'). Keep index 4 so the dashboard's jump(1) and other indices are unaffected.
- Decide whether the company score card and the pause/resume switch (currently under the table) survive on this page. The design drops them, but the product cannot lose the pause switch. Move them to Dashboard or Settings first (CompanyScreen's doc says they were kept deliberately).

**Missing in the backend**

- Nothing is strictly required for a v1 that uses existing endpoints. Riders without an application have no name; accept that.
- order-manager (recommended): GET /api/delivery-providers/my-company/riders/directory — one joined row per rider: riderRef, application reference, name, region, vehicleType, suspended flag, ratingAverage, ratingCount, deliveredToday, plus presence if order-manager can read it. Otherwise keep presence client-joined from order-tracking. Today the page fans out 3 + ~3N requests (a suspension per rider to onboarding-service, a rating per rider to order-manager); a 34-rider fleet is about 100 calls per load. The onboarding bits live in onboarding-service, so either order-manager calls onboarding (it already has service clients) or onboarding-service exposes a bulk GET /api/onboarding/applications/for-company/{providerId}/riders?include=standing.
- order-manager (optional): a bulk rating read, GET /api/riders/ratings?ids=... → List<StandingResponse>, to kill the per-rider rating N+1 (the Backoffice RidersScreen has the same problem).
- order-tracking (only if 'On Break' is kept): add an ON_BREAK value to DutyState. That needs a migration that ALTERs chk_presence_duty_state on rider_presence (V12) to allow it, PresenceService/DutySessionService semantics (does a break close the duty session or pause it? Breaks must not count toward hours online), a rider-app toggle in mobile_app rider_home_screen.dart (setDuty), and dispatch must treat ON_BREAK as not dispatchable.
- order-manager (only if the zone filter must be real): a rider_zone_assignments table (provider_id, rider_ref, zone_id → the provider's coverage zone), plus PUT /api/delivery-providers/my-company/riders/{riderRef}/zone and zone ids in the directory row. A Flyway migration in order-manager.

**Design-system pieces to reuse**

- ConsolePage, ConsoleTopbar, ConsoleSearchField, ConsoleSelect, ConsolePrimaryButton, ConsoleButton, ConsoleStatusPill, ConsoleAvatar, ConsoleKpiCard/ConsoleKpiRow, ConsoleCard, showConsoleDrawer, ConsoleBell (all in delivery_portal/lib/src/shell, exported from shell.dart / console_controls.dart).
- DeliveryColors.brand (#E11D48), brandSoft (#FFF1F2), ink (#0F172A), muted (#475569), faint (#94A3B8), border (#E2E8F0), background (#F8FAFC); DeliveryAccent.positive/caution/critical/info/neutral for the badges and stat values; DeliveryRadius and DeliverySpacing (delivery_design_system/lib/src/tokens.dart). Note DeliveryAccent.neutral is purple (#6C5CE0), while the design's 'Offline' badge is slate (#F1F5F9/#334155); use a borderFaint/muted neutral treatment rather than accent.neutral.
- CompanyScreen internals: _Fleet, _WaitingList, _StandingDialog, _Unknown, _shortRef, _date (extract them to shared files).
- The Yd* design-system widgets (YdCard, YdBadge, YdEmptyState) are mobile-oriented; the portal console uses the Console* family, so prefer Console* here and use YdEmptyState only if a richer empty state is wanted.

**Strings**

- navRiders 'Riders' (rail; the design says 'Riders HR')
- ridersDirectoryTitle 'Riders HR Directory'
- ridersDirectorySubtitle 'Manage rider profile lifecycle, status and zone assignments'
- ridersLiveBadge '{city} Live ({count} Riders)'
- ridersStatTotal 'Total onboarded riders' / ridersStatTotalNote 'Registered company fleet'
- ridersStatOnDuty 'Active on duty' / ridersStatOnDutyNote (reword: 'Available or on a job')
- ridersStatOnBreak 'On break' / 'Temporarily offline' (only if the state is built), else ridersStatSignalLost 'Signal lost'
- ridersStatOffline 'Offline / inactive' / ridersStatOfflineNote
- ridersSearchHint 'Search riders by name, ID...'
- ridersZoneFilter 'Zone: {zone}' / ridersZoneAll 'All zones'
- ridersVehicleFilter 'Vehicle: {vehicle}' / ridersVehicleAll 'All vehicles'
- vehicleMotorcycle / vehicleCar / vehicleVan / vehicleTruck / vehicleBicycle labels
- ridersAddRider 'Add Rider'
- ridersManageProfile 'Manage Profile'
- ridersDeliveredToday '({count} today)'
- riderRatingNew 'New'
- riderStatusActive 'Active' / riderStatusOnBreak 'On break' / riderStatusOffline 'Offline' / riderStatusSuspended 'Suspended' / riderStatusSignalLost 'Signal lost' / riderStatusOnAJob 'On a job'
- ridersNoMatch 'No rider matches that.'
- Existing keys to reuse: t.noRidersBlurb, t.noCompanyYet, t.askThePlatformToAttachYou, t.hiringAlsoCreatesTheirAccount, t.refresh
- All new keys go in both clients/packages/delivery_l10n/lib/l10n/app_en.arb and app_ar.arb. Note the portal console convention so far is inline English ('console screens are English-only in this wave'); new work should use ARB keys.

**Tests that should prove it**

- Widget test (delivery_portal/test/carrier/riders_directory_test.dart, reusing _StubAdapter): renders one card per /my-company/riders entry, with name from the application, reference badge, region and vehicle from details, rating from /api/riders/{id}/rating, and '(n Today)' from delivered-today. A rider absent from delivered-today shows 0; an unrated rider shows 'New', never 0.
- Widget test: the stat cards count ON_DUTY / OFF_DUTY (+ never declared) from the roster stub, and show '—' when the roster call fails. A roster 503 does not render as 'all offline'.
- Widget test: search narrows by name and by reference; the vehicle filter and the zone filter narrow the grid; filtered-empty copy appears.
- Widget test: status precedence is Suspended over presence over 'On a job'.
- Widget test: 'Add Rider' opens the waiting-list drawer and Approve calls POST .../for-company/{providerId}/{id}/approve; it is disabled with the explanatory tooltip when applications failed to load.
- Widget test: 'Manage Profile' navigates to the profile with the right rider id.
- Shell test (test/shell/console_shell_test.dart or a new carrier_shell_wiring_test.dart): the carrier Riders destination is built with the onboarding, partnerManagement, tracking and riderPerformance clients (a regression guard for the UNREACHABLE finding).
- Arabic/RTL case: the grid mirrors, and the vehicle/status labels are localised.
- Java (if the directory endpoint is added): a DeliveryProviderController/Service test that a CARRIER sees only riders of requireMyCompany(), that another company's rider never appears, and that a 404 is returned for non-carrier staff.
- Java (if bulk ratings are added): RiderRatingServiceTest covering unrated riders returning a null average and ids capped per request.
- API scenario (live test against dev): sign in as carrier/500005, GET /api/delivery-providers/my-company/riders and /api/tracking/riders/roster?onDutyOnly=false, and assert the card count equals the riders length.

**Questions**

- Is the card grid meant to REPLACE the existing 'Riders Management' table (Figma 3:3589, already built), or is it a second view? Two designs exist for the same page.
- 'On Break': is this a new rider-declared state the rider app must offer, or a relabelling of something existing? STALE (signal lost) must not be shown as a break.
- Zone: are riders to be assigned to the company's coverage zones (a new model), or is the free-text region from their application enough?
- Rider ID format '#YK-884' / 'BADGE ID: #YK-Beirut-884': is OnboardingApplication.reference acceptable, or does the company want its own badge codes (a new field)?
- Live badge '(34 Riders)': fleet size or on-duty count? And which city, given a company can have several dispatch regions?
- Where do the company score card and the pause/resume switch go if this page becomes a pure HR directory?
- Does 'Add Rider' ever mean inviting someone who has not applied (like the merchant staff invite flow in product-service), or always approving applicants?

### `112:740` web-carrier-rider-profile — L

*Who:* Carrier office staff (CARRIER role) managing one rider: HR/ops manager verifying papers, checking performance, and taking standing actions.

*What:* One rider's HR record: identity and contact, document verification, 30-day performance KPIs and a daily output chart, employment terms (start date, contract type, zone, base rate), and the lifecycle actions Edit Profile, Suspend Rider and Terminate Contract. Today the nearest thing is the read-only _RiderDetail drawer inside CompanyScreen (presence, today, 30-day performance, 7-day hours, application facts) plus the row-level suspend dialog.

*Reached from:* Reached from the directory (112:413) via 'Manage Profile' or a card click, inside the carrier 'Riders' destination. The portal has no URL routing, so push it within the destination or render it in place with a back button. The profile should link onward to Attendance (112:945), which the design does not draw.

**Every element, and where its data comes from**

- TOPBAR: 'Rider HR Profile' / 'Verify documentation, contract details and performance track', the live badge and the bell (same as the directory). No back or breadcrumb control is drawn; one is needed to return to the directory.
- IDENTITY CARD (360px left column). Avatar 'YK' 80px. Name 'Youssef Kanaan' (OnboardingApplication.contactName). 'BADGE ID: #YK-Beirut-884' (no source; use application.reference, see directory). Status badge 'On Duty / Active' (roster presence + suspension, as the directory).
- Bio details, label/value pairs: PHONE '+961 71 492 813' (application.contactPhone). EMAIL 'youssef.k@libanex.com'. We only hold the applicant's own contactEmail, and the design shows a company-domain address: no company email exists for riders. EMERGENCY CONTACT 'Salim Kanaan (Father) - 03 192 840': NO FIELD ANYWHERE. Nothing in services or clients mentions emergency contacts, and the rider wizard does not collect one.
- DOCUMENTS VERIFICATION CARD. Rows with a status badge: 'Lebanese National ID' Verified ✓, 'Motorcycle License' Verified ✓, 'Vehicle Insurance' Expiring ⚠. DATA: DocumentsApi.companyApplicantDocuments(providerId, applicationId) (GET /api/onboarding/applications/for-company/{providerId}/{id}/documents, CARRIER) → ReviewedDocument status pending/approved/rejected/superseded, plus viewUrl. CONTRADICTIONS: (1) The rider document set in onboarding-service DocumentKind.RIDER_DOCUMENTS is NATIONAL_ID, DRIVING_LICENCE and VEHICLE_REGISTRATION. There is no rider vehicle insurance (FLEET_INSURANCE is a company paper), so 'Vehicle Insurance' either maps to VEHICLE_REGISTRATION or needs a new DocumentKind VEHICLE_INSURANCE added to RIDER_DOCUMENTS. (2) 'Expiring' needs a document expiry date, and none exists: ApplicantDocument has no expiresAt, the only expiresAt is on the upload ticket. (3) The carrier's approve/refuse document endpoints are probably scoped to undecided applications (applicants_screen only offers them while undecided), so re-verifying a hired rider's paper may be refused by the server. Verify before promising actions here.
- PERFORMANCE GRID (4 stat cards):
-   - 'AVG RATING' '4.8 ★' (amber), '98% happy customers'. DATA: OrderApi.riderRating(riderId) → average. The '% happy' can be derived client-side from RiderStanding.stars as (4★ + 5★) / ratings. Show 'New' when unrated.
-   - 'DELIVERIES THIS MONTH' '186' (brand), 'Rank #3 in Beirut'. DATA: RiderPerformanceApi.forRider(riderId).delivered is a ROLLING 30-DAY window scoped to this company, not a calendar month: relabel it 'Deliveries, last 30 days' or add a month parameter. RANK: no source. It would need per-rider 30-day counts for the whole company (deliveredByRiderSinceForProvider exists in OrderRepository but only feeds 'today'). 'in Beirut' implies a city scope that does not exist.
-   - 'ON-TIME RATE' '94.2%' (positive), 'Target threshold > 90%'. NO SOURCE and no definition. Order has placedAt/acceptedAt/pickedUpAt/deliveredAt but no promised time or SLA (Order.java), so 'on time' cannot be computed honestly. Alternatives that exist: RiderPerformance.completionRate (delivered/claimed, null when nothing claimed, render '—').
-   - 'AVG DELIVERY TIME' '22 min', 'Beirut city average'. Per-rider: missing, though computable from pickedUpAt→deliveredAt. CarrierScore.avgSecondsOnRoad exists only at company level. 'city average' as a caption implies a comparison figure that does not exist.
- CHART CARD 'Delivery Output History (Last 30 Days)'. Bars labelled D1..D15: the design draws 15 bars under a 30-day title, so render one bar per day of the window. DATA: MISSING, a per-rider per-day delivered series. Render with ConsoleBarChart/ConsoleBar (console_controls.dart:517-586), or TrendChart from delivery_design_system. Needs an empty state ('No deliveries in the last 30 days') and a loading state.
- EMPLOYMENT DETAILS CARD (320px right column):
-   - START DATE 'Jan 15, 2026': OnboardingApplication.decidedAt (hire date), falling back to createdAt, as _Fleet.joinedOn.
-   - CONTRACT TYPE 'Full-time Commission': missing.
-   - ZONE ASSIGNMENT 'Beirut Central District': missing as a real assignment; the free-text region exists.
-   - BASE RATE / DEL '$1.50 Fresh USD': missing. RISK: rider pay today is computed in accounting-service (RiderEarningsService, rider ledger); a carrier-entered 'base rate' would be display-only unless accounting reads it, and a number that looks like pay but is not paid is dangerous.
- ACTIONS PANEL:
-   - 'Edit Profile' (outlined, edit icon). Edits the employment record, and maybe contact/emergency details. The carrier has NO endpoint to edit a rider's application: PartnerManagementApi.edit is PATCH /api/onboarding/applications/{id}, Backoffice. Identity (name/email) lives in Keycloak and the application.
-   - 'Suspend Rider' (caution outline, slash icon). EXISTS: _StandingDialog → PartnerManagementApi.suspendRider(providerId, applicationId, reason, note), with reinstate via unsuspendRider when already suspended. The label must flip to 'Reinstate Rider'. Disabled with a tooltip when the rider has no application (attached directly by Backoffice).
-   - 'Terminate Contract' (critical soft, trash icon). MISSING for carriers. DELETE /api/delivery-providers/riders/{riderRef} (DeliveryProviderApi.releaseRider) is @PreAuthorize BACKOFFICE, and it sends the rider back to the in-house platform fleet rather than ending anything. Needs a carrier-scoped endpoint and a typed confirmation dialog.
- STATES: loading per block (the drawer's 16px _Loading pattern), per-block 'Could not be read' failures, unrated → 'New', no application → the identity/documents/employment blocks degrade to the short ref and explanatory copy, 404 for a rider not on this fleet → 'Nobody you can see' page.

**Existing code that already covers part of it**

- D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/company_screen.dart:857-1140 — _RiderDetail drawer, the current rider profile: Presence (roster), Today (delivered today, delivered in the last 100 jobs), 'Performance, last 30 days' (RiderPerformanceApi.forRider: claimed, delivered, cancelledAfterClaim, completion), 'Hours online, last 7 days' (TrackingApi.riderDutyHours, zero-filled), and Application (email, phone, applied, joined, all details entries).
- D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/company_screen.dart:1251-1394 — _StandingDialog: typed SuspensionReason (FRAUD, ABUSE, NON_PAYMENT, POLICY_VIOLATION, PARTNER_REQUEST, OTHER) plus a note, as used by the design's Suspend Rider.
- D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/applicants_screen.dart — the document checklist rows (Waiting/Approved/Refused/Replaced badges, open-document link, approve/refuse with _DocumentReasonDialog), reusable for the Documents Verification card.
- D:/workspace/delivery/clients/packages/delivery_core/lib/src/api/documents_api.dart:166-200 — companyApplicantDocuments / approveCompanyApplicantDocument / rejectCompanyApplicantDocument / companyApplicantPayout (carrier-scoped).
- D:/workspace/delivery/clients/packages/delivery_core/lib/src/api/rider_performance_api.dart — forRider(riderId) (GET /api/orders/riders/{riderId}/performance, BACKOFFICE or CARRIER; carrier-scoped to own company work; a foreign rider returns zeros).
- D:/workspace/delivery/clients/packages/delivery_core/lib/src/models/performance_models.dart — RiderPerformance (windowDays, claimed, delivered, cancelledAfterClaim, completionRate?).
- D:/workspace/delivery/clients/packages/delivery_core/lib/src/api/order_api.dart:252 riderRating; D:/workspace/delivery/clients/packages/delivery_core/lib/src/models/rating_models.dart RiderStanding (average?, ratings, stars 1-5 histogram).
- D:/workspace/delivery/services/order-manager/src/main/java/com/delivery/order/api/RiderPerformanceController.java and service/RiderPerformanceService.java — the 30-day window and delivered-today; OrderRepository.deliveredByRiderSinceForProvider (per-rider counts since an instant, not per day).
- D:/workspace/delivery/services/order-manager/src/main/java/com/delivery/order/domain/Order.java:252-264 — placedAt/acceptedAt/pickedUpAt/deliveredAt/cancelledAt, the raw material for per-rider timings; no promised/SLA time.
- D:/workspace/delivery/services/onboarding-service/src/main/java/com/delivery/onboarding/domain/DocumentKind.java — RIDER_DOCUMENTS = NATIONAL_ID, DRIVING_LICENCE, VEHICLE_REGISTRATION.
- D:/workspace/delivery/services/onboarding-service/src/main/java/com/delivery/onboarding/api/PartnerManagementController.java:210-235 — carrier suspend/unsuspend/suspension.
- D:/workspace/delivery/services/order-manager/src/main/java/com/delivery/order/api/DeliveryProviderController.java:190 — DELETE /riders/{riderRef}, BACKOFFICE only (release to the in-house fleet).
- D:/workspace/delivery/clients/apps/delivery_portal/lib/src/shell/console_controls.dart:517-634 — ConsoleBar/ConsoleBarChart/ConsoleLegendSwatch for the output chart.

**Missing in the clients**

- A new RiderProfileScreen (carrier/rider_profile_screen.dart) laid out as three columns (360 / flex / 320) that stack below ~1100px. It replaces or complements the _RiderDetail drawer and takes riderId plus the shared fleet-roster entry.
- Identity card, documents card (lift the checklist row from applicants_screen into a shared widget), performance KPI grid (ConsoleKpiCard ×4), chart card (ConsoleBarChart), employment card, and actions panel.
- Derived client math: '% happy' = (stars[4] + stars[5]) / ratings, hidden when ratings == 0.
- A suspend/reinstate button bound to the existing _StandingDialog (extract it to a shared file).
- Terminate confirmation dialog: a typed reason, an explicit statement of consequences (off the fleet, no further work, in-flight jobs), and critical tone. Calls the new endpoint.
- Edit Profile dialog for the employment record: contract type select, base rate + currency, zone select from myZones(), badge code, emergency contact name/relation/phone, start date override.
- New delivery_core client methods: RiderPerformanceApi.dailyForRider(riderId, days) → List<RiderDay>; extend RiderPerformance with avgSecondsOnRoad / avgSecondsToDeliver; DeliveryProviderApi.riderProfile(riderRef) / saveRiderProfile(...) / terminateRider(riderRef, reason); models RiderEmploymentProfile, RiderDay.
- A back affordance to the directory, and an 'Attendance' entry (tab or button) to 112:945. The design has no control that leads to the attendance frame.

**Missing in the backend**

- order-manager: GET /api/orders/riders/{riderId}/performance/daily?days=30 (BACKOFFICE or CARRIER, scoped exactly like /performance: carrier resolved from the caller's membership, only this company's orders) → [{date, delivered}] grouped on delivered_at in the platform day zone, returning only days with work (client zero-fills, the same convention as HoursOnline). A new OrderRepository query grouped by rider and date(delivered_at AT TIME ZONE zone).
- order-manager: extend RiderPerformanceView with avgSecondsToDeliver (mean of deliveredAt − pickedUpAt over delivered orders in the window) and optionally avgSecondsAcceptToDoor. Null when none, same rule as completionRate.
- order-manager (only if the rank is wanted): GET /api/orders/riders/{riderId}/performance/rank → {rank, of} within the caller's company over the same 30-day window.
- On-time rate: NOT buildable without a product definition and a stored promise, e.g. the ETA quoted at accept time or a per-zone SLA minutes. Needs an order-manager column (promised_delivery_at) set at accept or dispatch, plus a migration. Recommend dropping the card or replacing it with Completion rate until then.
- order-manager (fleet owner): a new rider employment record, table fleet_rider_profiles (provider_id uuid, rider_ref varchar(64), badge_code, contract_type enum [FULL_TIME_COMMISSION, PART_TIME, FREELANCE, SALARIED], base_rate_minor bigint + currency char(3), coverage_zone_id uuid null (FK to the provider's coverage zone), emergency_name, emergency_relation, emergency_phone, start_date, updated_by, updated_at; PK (provider_id, rider_ref)). Plus a Flyway migration and GET/PUT /api/delivery-providers/my-company/riders/{riderRef}/profile (CARRIER, requireMyCompany; 404 unless the rider is on this fleet). Emergency contact is personal data, so exclude it from logs and from Backoffice/customer DTOs unless needed.
- order-manager: DELETE (or POST .../terminate) /api/delivery-providers/my-company/riders/{riderRef} (CARRIER, requireMyCompany, rider must be on this fleet), with a reason and an audit row. Decide the semantics: release to the in-house fleet (like the Backoffice release) or detach and disable. Also handle in-flight jobs (refuse while the rider holds a non-terminal job, or reassign), notify order-tracking membership (rider_presence.carrier_id and the carrier_membership row), and decide whether the onboarding application status changes. Emit an event so onboarding/tracking caches drop the rider.
- onboarding-service (only if 'Vehicle Insurance' and 'Expiring' are kept): add DocumentKind VEHICLE_INSURANCE to RIDER_DOCUMENTS; add a nullable expires_on date to applicant documents (migration), settable by the reviewer on approve, and a derived EXPIRING state (within N days); allow carrier re-review of documents for already-hired riders.

**Design-system pieces to reuse**

- ConsolePage/ConsoleTopbar, ConsoleCard, ConsoleKpiCard, ConsoleBarChart/ConsoleBar, ConsoleStatusPill, ConsoleAvatar (size 80), ConsolePrimaryButton / ConsoleSoftButton / ConsoleTintButton / ConsoleButton(tone: outlined), ConsoleFactGrid/ConsoleFact (console_identity.dart) for the label/value bio and employment lists, ConsoleNoValue/ConsoleInertNote for 'not recorded'.
- _StandingDialog, the applicants_screen document row and _DocumentReasonDialog (extract to shared carrier widgets).
- Tokens: DeliveryAccent.caution (#F59E0B) for the rating value and the suspend outline, positive for on-time/verified, critical for terminate (soft #FEF2F2 bg, #EF4444 text), DeliveryColors.brand for deliveries and the chart bars, faint for labels, and the ConsoleText styles (kpiLabel, cardTitle, body, meta).

**Strings**

- riderProfileTitle 'Rider HR Profile' / riderProfileSubtitle 'Verify documentation, contract details and performance track'
- riderBadgeId 'Badge ID: {code}'
- riderPhone 'Phone' / riderEmail 'Email' / riderEmergencyContact 'Emergency contact' / riderEmergencyContactValue '{name} ({relation}) - {phone}'
- riderDocumentsTitle 'Documents Verification'
- docNationalId 'Lebanese National ID' / docDrivingLicence 'Driving licence' / docVehicleRegistration 'Vehicle registration' / docVehicleInsurance 'Vehicle insurance' (if added)
- docVerified 'Verified' / docExpiring 'Expiring' / docPending 'Waiting' / docRefused 'Refused' / docNotUploaded 'Not uploaded'
- riderAvgRating 'Avg rating' / riderHappyCustomers '{percent}% happy customers' / riderRatingNew 'New'
- riderDeliveriesWindow 'Deliveries, last {days} days' (or 'Deliveries this month') / riderRank 'Rank #{rank} of {count}'
- riderCompletionRate 'Completion rate' (replacing 'On-time rate' until defined) / riderOnTimeTarget 'Target above {percent}%'
- riderAvgDeliveryTime 'Avg delivery time' / minutesShort '{n} min'
- riderOutputChartTitle 'Delivery output, last {days} days' / riderOutputEmpty 'No deliveries in this period'
- riderEmploymentTitle 'Employment Details' / riderStartDate 'Start date' / riderContractType 'Contract type' / riderZoneAssignment 'Zone assignment' / riderBaseRate 'Base rate / delivery' / notRecorded 'Not recorded'
- contractFullTimeCommission 'Full-time commission' (and the other enum labels)
- riderEditProfile 'Edit Profile' / riderSuspend 'Suspend Rider' / riderReinstate 'Reinstate Rider' / riderTerminate 'Terminate Contract'
- riderTerminateTitle 'End {name}''s contract?' / riderTerminateBody (consequences) / riderTerminateConfirm 'Terminate contract'
- riderViewAttendance 'Attendance'
- Existing: t.cancel, t.thatDidNotWork, the SuspensionReason labels (hard-coded English in partner_management_models; localise them)

**Tests that should prove it**

- Widget test (test/carrier/rider_profile_screen_test.dart, _StubAdapter): the identity card shows the application name/phone/email, the reference as badge id, and presence/suspension status.
- Widget test: the documents card maps NATIONAL_ID / DRIVING_LICENCE / VEHICLE_REGISTRATION statuses to badges; a missing expected document shows 'Not uploaded'; a failed document load shows the retry row.
- Widget test: an unrated rider shows 'New' and hides '% happy'; the rated case computes (4★ + 5★) / total.
- Widget test: completion shows '—' when nothing was claimed, never 0% or 100% (mirrors the existing drawer test).
- Widget test: the chart zero-fills 30 days from a sparse daily series, and shows empty copy when there is nothing.
- Widget test: Suspend opens _StandingDialog, requires a reason and POSTs suspendRider; a suspended rider shows 'Reinstate Rider' and POSTs unsuspendRider.
- Widget test: Terminate requires confirmation, POSTs the carrier terminate endpoint, and returns to the directory; a server refusal (rider holds a job) shows the server's message.
- Widget test: the employment card renders '—' for fields not recorded; Edit Profile saves via PUT and re-renders.
- Java (order-manager): RiderPerformanceService daily series — carrier scope excludes other companies' orders; day bucketing across midnight in the configured zone; days capped at 30 (400 above).
- Java (order-manager): the terminate endpoint returns 404 for a rider on another fleet, refuses when the rider holds an in-flight job, and writes an audit row. Also a membership-change event test.
- Java (order-manager): the fleet rider profile PUT validates the currency and the zone belongs to the caller's company; GET returns 404 for foreign riders.
- API scenario: as carrier/500005, GET /api/orders/riders/{id}/performance for an own rider (non-zero) and a foreign rider (zeros, no 404), and GET /api/riders/{id}/rating (200).

**Questions**

- Terminate Contract: release to the YouDrop in-house fleet (current Backoffice semantics), or fully detach and disable sign-in? What happens to jobs in flight and to the rider's ledger balance or cash float?
- Contract type and base rate: are they informational HR data, or must accounting-service pay riders from them? If paid, this becomes an accounting change (rider ledger rates), not a display field.
- On-time rate: what is the promise (quoted ETA at accept, merchant prep plus N minutes, per-zone SLA)? Until defined, can we show Completion rate instead?
- 'Deliveries this month': calendar month or rolling 30 days (what the server has)? Rank scope: company-wide or per region?
- Vehicle Insurance: add it as a required rider document? Who enters document expiry dates: the reviewer on approval, or OCR?
- Emergency contact: who collects it (the rider wizard, or the carrier on Edit Profile) and who may see it?
- May a carrier edit a rider's name/phone/email, or only its own employment fields? Today only Backoffice can edit an application (PATCH /api/onboarding/applications/{id}).
- The company-domain email in the design (youssef.k@libanex.com): do carriers issue rider emails, or should we show the rider's personal sign-in email?

### `112:945` web-carrier-rider-attendance — XL

*Who:* Carrier office staff (CARRIER role): an ops/HR manager reviewing one rider's attendance for a month, and recording manual corrections (sick leave, a missed clock-in).

*What:* Per-rider monthly attendance and shift log: a calendar coloured Present/Late/Absent against a weekly schedule, month aggregates (days worked, absences, times late, overtime), a table of clock-in/clock-out rows with scheduled shift, hours, status and notes, and a 'Manual Attendance Log' action. VERIFIED: there is NO shift, schedule, lateness, absence, leave or attendance model anywhere. What exists is order-tracking's duty model: riders declare ON_DUTY/OFF_DUTY from the rider app; duty_sessions rows (started_at, ended_at, end_reason RIDER/BACKOFFICE/EXPIRED) and the rider_duty_events audit log; and a per-day hours-online aggregate. That can honestly supply clock-in/clock-out and hours, but not 'scheduled', 'late', 'absent' or 'overtime'. (product-service has a StaffShift clock-in/out model, but only for merchant store staff.)

*Reached from:* Carrier 'Riders' destination → rider profile (112:740) → 'Attendance' (a new button or tab; not drawn in the design) → this screen. Optionally a fleet-wide 'Attendance' sub-tab on the directory later, which the design does not show.

**Every element, and where its data comes from**

- TOPBAR: 'Rider Attendance & Shift Logs' / 'Track daily check-ins, lates, absences, and shift overrides', the live badge and the bell.
- HEADER ROW: avatar 'YK' (36px), name 'Youssef Kanaan', subline 'Attendance & Clock logs for October 2026'. Name from the fleet roster entry (application contactName); the month is the selected period.
- BUTTON 'Manual Attendance Log' (brand, plus icon). Opens a form: date, status (present / absent-excused / sick / leave / late-excused), optional clock-in/clock-out times, note. NO BACKEND. duty_sessions must stay evidence-only (the V13 comments insist hours are only what there is evidence for), so manual entries need their own override table, never an edit of sessions.
- CALENDAR CARD. Title 'October 2026'. Month navigation (prev/next) is NOT drawn but is implied by 'for October 2026'; add chevrons. Legend: Present (green), Late (amber), Absent (red). Weekday header MON..SUN; 40px day cells coloured positive-soft (#ECFDF5 / #065F46), caution-soft (#FEF3C7 / #92400E), critical-soft (#FEF2F2 / #991B1B) or neutral grey (#F1F5F9 / #64748B). The greys fall on Sat/Sun, implying days the rider is not scheduled. Only three weeks are drawn; implement a full month grid with leading/trailing blanks and a 'today' marker, with future days unstyled. The week starts Monday (design); make it locale-aware (Lebanon commonly uses Monday). DATA: 'present' = any duty session touching the day (GET /api/tracking/riders/{riderId}/duty/hours returns per-day seconds and session counts, CARRIER-scoped, days ≤ 30). Late/absent/weekend-off need a schedule, which is MISSING.
- AGGREGATES CARD 'Attendance Aggregates' (380px): 'Days Worked' 22 Days (positive), 'Absences' 2 Days (critical), 'Times Late' 3 Days (caution), 'Overtime Accumulated' 8.5 Hours (ink). Days worked = count of days with seconds > 0 (derivable today). Absences, lates and overtime all need a schedule (MISSING). The design's sample numbers are inconsistent with its own calendar (22 days worked by Oct 21 with weekends off is impossible); ignore them.
- LOGS TABLE 'Recent Clock-In / Clock-Out Logs'. Columns: DATE (120), SCHEDULED SHIFT (180, e.g. 'Beirut Central Day (08:00 - 18:00)'), CLOCK IN (120), CLOCK OUT (120), HOURS (100, '10.1 hrs'), STATUS (100; badges On-Time / Late Check-in / Absent), NOTES (flex, e.g. 'Delayed at Cola Intersection Traffic', 'Worked overtime 15m', 'Requested sick leave'). DATA: clock in/out = the first session start and last session end of the day, or one row per session (a rider can go on and off duty several times a day, so decide which). The existing API returns only per-day totals, NOT individual session start/end, so a sessions endpoint is MISSING. Scheduled shift, status and notes are MISSING. Design bug: '18:02 PM' mixes 24h and AM/PM; use one format (24h in Lebanon consoles, locale-aware). Hours display: hoursOnline is server-rounded to 2dp; show 1dp as drawn, but sum from secondsOnline. Absent rows show '---' for times and '0.0 hrs'. Use ConsoleTable with minWidth ~900 and horizontal scroll.
- END-REASON NUANCE: a session closed by the EXPIRED sweep ends at the rider's last sighting, not a tap. Show it (e.g. 'Auto-closed: signal lost') rather than as a normal clock-out, and an open session shows 'On shift now'.
- STATES: loading; month with no sessions ('No duty recorded for this month. History starts when duty tracking began; nothing is backfilled.', which matches the V13 migration note); 404 (the rider is not linked to this fleet in tracking; see risks); 403 (carrier with no company); window-limit error if the client asks > 30 days of the current endpoint.

**Existing code that already covers part of it**

- D:/workspace/delivery/services/order-tracking/src/main/java/com/delivery/tracking/domain/DutySession.java — one row per shift: startedAt, endedAt (null while open), endReason RIDER/BACKOFFICE/EXPIRED; close() clamps end ≥ start.
- D:/workspace/delivery/services/order-tracking/src/main/java/com/delivery/tracking/domain/RiderDutyEvent.java — an append-only duty transition log with source RIDER/BACKOFFICE/SYSTEM.
- D:/workspace/delivery/services/order-tracking/src/main/java/com/delivery/tracking/service/DutySessionService.java — aggregate(riderId, days) splits sessions at midnight in the configured day zone and returns HoursOnline{riderId, zone, from, to, days:[DayOnline{date, secondsOnline, hoursOnline(2dp), sessions}]}. riderHours() is carrier-scoped via CarrierScopeResolver and rider_presence.carrier_id, with an identical 404 for foreign or unknown riders. expireAbandoned() auto-closes silent shifts at last sighting.
- D:/workspace/delivery/services/order-tracking/src/main/java/com/delivery/tracking/api/RiderPresenceController.java — GET /api/tracking/riders/{riderId}/duty/hours?days=1..30 (BACKOFFICE, CARRIER); GET /me/duty/hours (DELIVERY); POST /me/duty; GET /roster.
- D:/workspace/delivery/services/order-tracking/src/main/resources/db/migration/tracking/V13__duty_sessions.sql — the duty_sessions table, a one-open-session-per-rider unique index, and 'history starts at this migration, nothing backfilled'.
- D:/workspace/delivery/services/order-tracking/src/main/resources/db/migration/tracking/V12__rider_presence_and_routing.sql — rider_presence (rider_id, carrier_id, duty_state ON_DUTY/OFF_DUTY check constraint) and carrier_membership.
- D:/workspace/delivery/services/order-tracking/src/main/resources/application.yml:197 — delivery.tracking.duty-session.day-zone: UTC. Wrong for Lebanon (UTC+2/+3): days split at 02:00/03:00 local.
- D:/workspace/delivery/clients/packages/delivery_core/lib/src/api/tracking_api.dart:84 — riderDutyHours(riderId, days); models in tracking_models.dart (HoursOnline, DutyDay, RiderPresence, DutyState, PresenceState).
- D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/company_screen.dart:1026-1082 — the drawer's 'Hours online, last 7 days' block (zero-fill pattern, zone footnote).
- D:/workspace/delivery/clients/apps/mobile_app/lib/src/rider_home_screen.dart — the rider's duty toggle (TrackingApi.setDuty), the only source of clock-in/out today.
- D:/workspace/delivery/services/product-service/src/main/java/com/delivery/product/domain/staff/StaffShift.java (+ StoreStaffApi.clockIn/clockOut) — a precedent for a clock-in/out model with Source SELF/MANAGER/AUTO and a manager clocking someone out. It is for merchant staff, not riders, but the shape is worth mirroring.

**Missing in the clients**

- A new RiderAttendanceScreen (carrier/rider_attendance_screen.dart): header row, a month calendar widget (new _AttendanceCalendar: 7-column grid with a status-coloured cell per day, legend with ConsoleLegendSwatch, prev/next month), an aggregates ConsoleCard, a logs ConsoleTable, and a Manual Log dialog.
- New delivery_core methods: TrackingApi.riderDutySessions(riderId, from, to) → List<DutySessionView>; TrackingApi.riderAttendance(riderId, month) → RiderAttendanceMonth; TrackingApi.logAttendance(riderId, entry); shift-template CRUD (if schedules are built). Models: DutySessionView, AttendanceDay, AttendanceStatus enum (present, late, absent, excused, off, noSchedule), AttendanceTotals, ShiftTemplate.
- Until schedules exist, a v1 'duty log' mode: calendar shows present vs no duty (no late/absent colours); aggregates show Days on duty, Total hours, Shifts, Auto-closed shifts; the table shows sessions with the Scheduled/Status columns hidden. Say so on screen rather than faking.
- An entry point from the rider profile (an 'Attendance' tab or button) and a back affordance.

**Missing in the backend**

- order-tracking config: set delivery.tracking.duty-session.day-zone to Asia/Beirut (config-server / application.yml) before any attendance UI ships. Today every day boundary is 2-3 hours off for Lebanon, and it also changes the existing hours tiles.
- order-tracking: GET /api/tracking/riders/{riderId}/duty/sessions?from=YYYY-MM-DD&to=YYYY-MM-DD (BACKOFFICE, CARRIER, scoped exactly like riderHours; window ≤ 31 days) → [{id, startedAt, endedAt?, endReason?, secondsCounted}], using the same effectiveEnd rule so live and eventual figures agree. A new DutySessionRepository finder (findOverlapping already exists).
- order-tracking: raise or extend the window. /duty/hours caps days at 30 and is anchored on today, but a month view needs an arbitrary month, so add ?month=YYYY-MM or from/to.
- order-tracking (the new attendance/scheduling domain, recommended here because it owns duty evidence). Migration V15__shift_schedules_and_attendance.sql:
-   - shift_templates: id, carrier_id, name, zone_label, start_time, end_time, days_of_week bitmask, late_grace_minutes, active.
-   - rider_shift_assignments: rider_id, template_id, effective_from, effective_to.
-   - attendance_overrides: id, rider_id, carrier_id, work_date, status [PRESENT_MANUAL, ABSENT_EXCUSED, SICK, LEAVE, LATE_EXCUSED], clock_in, clock_out, note ≤ 500, created_by, created_at; unique per (rider_id, work_date).
-   - Service: AttendanceService derives each day's status from assignment ∩ sessions ∪ override: scheduled with no session = ABSENT; first session start > shift start + grace = LATE; seconds beyond the scheduled length = overtime; unscheduled day = OFF, or EXTRA if worked.
-   - Endpoints: GET /api/tracking/riders/{riderId}/attendance?month=YYYY-MM (BACKOFFICE, CARRIER) → {zone, days:[{date, scheduled:{name, start, end}|null, clockIn, clockOut, secondsOnline, status, note, source}], totals:{daysWorked, absences, lates, overtimeSeconds}}.
-   - POST/PUT/DELETE /api/tracking/riders/{riderId}/attendance/entries (CARRIER own fleet, audited, never edits duty_sessions).
-   - CRUD /api/tracking/carrier/shift-templates and PUT /api/tracking/riders/{riderId}/shift-assignment (CARRIER; carrier id from CarrierScopeResolver, never the request).
- Membership linkage (VERIFY): the carrier scope for riderHours relies on rider_presence.carrier_id. V12/V14 show carrier linkage learned from ORDER_EVENT inference and a DIRECTORY lookup (written for office staff). A freshly hired rider who has declared duty but never carried an order for the company may have a null carrier_id, so every carrier attendance read returns 404 for them. Needs a hire-time membership write (order-manager → order-tracking event on assignRider/hire), or a DIRECTORY-style lookup against /api/delivery-providers/my-company/riders.

**Design-system pieces to reuse**

- ConsolePage/ConsoleTopbar, ConsoleCard, ConsoleTable/ConsoleColumn/ConsoleTableRow, ConsoleStatusPill (On-Time positive, Late caution, Absent critical), ConsoleLegendSwatch, ConsoleAvatar, ConsolePrimaryButton, ConsoleSelect for the status in the manual log dialog, and an AlertDialog pattern like _StandingDialog.
- The zero-fill and zone-footnote logic from _RiderDetailState._hoursBlock.
- Tokens: DeliveryAccent.positive/caution/critical with their soft backgrounds (match the design's #ECFDF5/#FEF3C7/#FEF2F2), DeliveryColors.borderFaint (#F1F5F9) for off days, faint for weekday headers, and DeliveryRadius.sm (8) for day cells.

**Strings**

- attendanceTitle 'Rider Attendance & Shift Logs' / attendanceSubtitle 'Track daily check-ins, lates, absences, and shift overrides'
- attendanceForMonth 'Attendance & clock logs for {month}'
- attendanceManualLog 'Manual Attendance Log'
- attendancePresent 'Present' / attendanceLate 'Late' / attendanceAbsent 'Absent' / attendanceOff 'Day off' / attendanceExcused 'Excused' / attendanceSick 'Sick leave' / attendanceLeave 'Leave'
- weekday short names MON..SUN (use intl DateFormat, not hard-coded)
- attendanceAggregatesTitle 'Attendance Aggregates' / attendanceDaysWorked 'Days worked' / attendanceAbsences 'Absences' / attendanceTimesLate 'Times late' / attendanceOvertime 'Overtime accumulated' / daysCount '{n} days' / hoursCount '{n} hours'
- attendanceLogsTitle 'Recent Clock-In / Clock-Out Logs' / colDate 'Date' / colScheduledShift 'Scheduled shift' / colClockIn 'Clock in' / colClockOut 'Clock out' / colHours 'Hours' / colStatus 'Status' / colNotes 'Notes'
- attendanceOnTime 'On time' / attendanceLateCheckIn 'Late check-in' / attendanceOnShiftNow 'On shift now' / attendanceAutoClosed 'Auto-closed: signal lost'
- attendanceNoSchedule 'No shift schedule is set for this rider, so only time on duty is shown.'
- attendanceEmptyMonth 'No duty recorded for this month. History starts when duty tracking began; nothing is backfilled.'
- manualLogTitle 'Log attendance for {name}' / manualLogDate 'Date' / manualLogStatus 'Status' / manualLogClockIn 'Clock in' / manualLogClockOut 'Clock out' / manualLogNote 'Note (optional)' / manualLogSave 'Save entry'
- attendanceZoneNote 'Days are split in the {zone} time zone.'

**Tests that should prove it**

- Widget test (test/carrier/rider_attendance_screen_test.dart): the calendar colours days from a stubbed attendance month (present/late/absent/off) and shows a today marker; prev/next month re-fetches with the right month param.
- Widget test v1 (no schedules): with only duty sessions, the calendar shows present days and nothing else, Late/Absent legend items are hidden, and the explanatory note is shown.
- Widget test: the logs table renders session rows in 24h format, an open session shows 'On shift now', and an EXPIRED session shows the auto-closed note; the Scheduled column is hidden when no schedule exists.
- Widget test: aggregates sum from secondsOnline (not from rounded hours); empty month copy.
- Widget test: the Manual Attendance Log dialog requires a date and status, POSTs the entry, and refreshes the day to its override status; a note longer than 500 is refused.
- Widget test: 404 → 'not on your fleet' copy; 403 → no-company copy.
- Java (order-tracking) DutySessionServiceTest additions: the sessions endpoint for a carrier returns only own-fleet riders (a foreign rider gets 404 identical to unknown); a session spanning midnight appears on both days under Asia/Beirut; window > 31 days → 400.
- Java AttendanceServiceTest: scheduled + no session = ABSENT; first start after start+grace = LATE; overtime = worked − scheduled when positive; an override beats derived status; an unscheduled day with work = EXTRA/present; an EXPIRED session counts only to last sighting.
- Java migration test: V15 applies on top of V14; unique (rider_id, work_date) on overrides.
- Java controller auth tests: DELIVERY cannot read another rider; CARRIER cannot write for a foreign rider; BACKOFFICE can read any rider.
- API scenario on dev: a rider toggles on/off duty via POST /api/tracking/riders/me/duty, then the carrier GETs /duty/sessions and sees the session with endReason RIDER.

**Questions**

- Are this company's riders employees on fixed shifts (schedules, lateness, absence) or freelancers who choose when to go on duty (today's model)? Lateness and absence imply employment control, which is a legal/labour question in Lebanon, not only a UI one.
- If schedules are wanted, who defines them: the carrier (templates per zone/day) or the platform? Can a rider see their schedule in the rider app (a mobile change)?
- One clock-in per day (first on, last off) or one row per duty session?
- Should 'On Break' (from the directory) pause a shift without ending it? It affects hours and overtime.
- Overtime basis: beyond the scheduled length per day, or beyond N hours per week? Is overtime paid (accounting), or informational?
- Manual entries: may a carrier mark a rider present for a day with no duty evidence? How are they audited and shown to the rider?
- Can we switch the platform day zone to Asia/Beirut now? It also shifts the existing hours-online tiles for riders and Backoffice.
- How far back must attendance go? History starts at V13 (no backfill), and duty data is under a retention sweep (TrackingPartitionMaintenance), so check the retention period against payroll needs.

**Build order for this cluster**

- 1. (S, client-only) Wire the four withheld clients into the existing CompanyScreen in D:/workspace/delivery/clients/apps/delivery_portal/lib/src/portal_shell.dart (onboardingApi: a.onboarding, managementApi: a.partnerManagement, trackingApi: a.tracking, performanceApi: a.riderPerformance). Add a shell wiring test. This alone revives status, region, join date, Add Rider, suspend/reinstate and the rider drawer in production.
- 2. (S) Show real ratings: fan out OrderApi.riderRating in the fleet loader, render 'New' when unrated, and delete the stale 'Rating is not recorded on this platform' copy and comments in company_screen.dart and its test.
- 3. (S) Extract _Fleet/_load, _StandingDialog, _WaitingList, _Unknown, _shortRef and _date from company_screen.dart into shared carrier files (fleet_roster.dart, rider_standing_dialog.dart) with no behaviour change; existing tests stay green.
- 4. (M) Riders HR directory (112:413): card grid, four stat cards, search, vehicle filter (details['vehicleType']) and free-text region filter over the shared loader. Rename the rail entry to 'Riders' via a new l10n key without changing indices. Decide where the score card and pause switch move (Dashboard or Settings) before removing them. Presence shows On duty / Signal lost / Off duty; 'On Break' waits for a product decision.
- 5. (M) Rider profile page (112:740) from existing endpoints only: identity (application), documents (companyApplicantDocuments + a shared checklist row from applicants_screen), rating with the '% happy' histogram, 30-day performance with completion rate in place of on-time, suspend/reinstate, start date. Unknown employment fields show 'Not recorded'. Add a back affordance and an 'Attendance' entry.
- 6. (S, order-manager) Per-rider daily delivered series (GET /api/orders/riders/{id}/performance/daily?days=30) and avgSecondsToDeliver in RiderPerformanceView, plus delivery_core methods; then the profile's output chart (ConsoleBarChart) and avg-delivery-time card.
- 7. (M, order-manager) Carrier-scoped terminate/release endpoint (DELETE /api/delivery-providers/my-company/riders/{riderRef}, with a reason, audit, and an in-flight-job guard), plus the membership event to order-tracking. Then the Terminate Contract dialog.
- 8. (M, order-manager) Fleet rider employment record (fleet_rider_profiles migration, and GET/PUT /my-company/riders/{riderRef}/profile: badge code, contract type, base rate display, coverage-zone assignment, emergency contact). Then the Edit Profile dialog, a real zone on cards and a real zone filter. Confirm first with product and accounting that the base rate is informational.
- 9. (S, config) Switch order-tracking delivery.tracking.duty-session.day-zone from UTC to Asia/Beirut. Fix the rider → carrier linkage in order-tracking so freshly hired riders resolve to their fleet (a hire/assign event or a directory lookup), and verify with a carrier reading a new rider's /duty/hours.
- 10. (M, order-tracking + client) Attendance v1 'duty log': GET /api/tracking/riders/{id}/duty/sessions?from&to (carrier-scoped, ≤ 31 days) and a month parameter for hours. Then RiderAttendanceScreen with the month calendar (present / no duty), duty aggregates and the sessions table (auto-closed and open-session handling), clearly stating that no schedule exists.
- 11. (L, order-tracking + client) Only after the product decides riders work scheduled shifts: V15 migration (shift_templates, rider_shift_assignments, attendance_overrides), AttendanceService deriving late/absent/overtime, the attendance and manual-entry endpoints, and shift-template management UI. Then light up the Late/Absent colours, the full aggregates, the Scheduled/Status/Notes columns and the Manual Attendance Log.
- 12. (Optional, M) Performance: a joined /my-company/riders/directory endpoint (or bulk ratings plus a bulk onboarding standing read) to replace the ~3N-request fan-out; and an ON_BREAK duty state in order-tracking plus the rider-app toggle, if 'On Break' is confirmed.

**Cross-cutting**

- The design's carrier sidebar does not match the shipped rail. Design: 'Carrier Backoffice' wordmark, carrier pill with name/hub/ID, and Dashboard, Orders, Fleet, Reconciliation, Riders HR, Earnings, Coverage, Settings, with a job title 'Operations Manager'. Code: 'Carrier Hub' wordmark, no pill, and Dashboard, Jobs, Earnings, Statement, Company, Applicants, Settings, with the role line t.carrierPartner (the code refuses to print job titles because the token has none). The shell/chrome cluster should settle this; this cluster only needs a 'Riders' entry.
- The existing carrier Riders page (CompanyScreen) is built and tested but shipped half-dead because portal_shell.dart withholds its optional clients. Fixing that is a one-line win that predates all new work.
- Rider identity is thin. Order-manager knows riders only as Keycloak subject strings (myRiders() returns List<String>). Names, phone, email, region and vehicle come only from the rider's onboarding application (details is a free-form JSON map, keys like vehicleType/plateNumber/vehicleModel/workRegion written by mobile_app partner_application_screen.dart). Riders attached directly by Backoffice have none of it.
- There is no rider→zone link in any service (backoffice riders_screen.dart says so). Coverage zones belong to the company. Every 'zone' element in these frames needs either the free-text application region or a new assignment model.
- Presence vocabulary: the backend has ON_DUTY / STALE (signal lost) / OFF_DUTY plus suspension. The design uses Active / On Break / Offline / Suspended. 'On Break' has no source, and STALE must never be shown as a break.
- The rating exists (order-manager RiderRatingController; GET /api/riders/{id}/rating is open to any authenticated caller), contrary to comments in company_screen.dart and its test, which should be corrected.
- The N+1 request fan-out grows with fleet size: suspension per rider (onboarding-service), rating per rider (order-manager), and on the profile, documents, performance, hours and rating. Acceptable for tens of riders; a joined directory endpoint is the real fix.
- Time zones: order-tracking splits duty days in UTC (application.yml day-zone: UTC). Any per-day attendance or hours figure for Lebanon is shifted 2-3 hours until it becomes Asia/Beirut, and order-manager's per-day series must use the same zone.
- L10n: the portal console screens so far use inline English ('English-only in this wave'). New screens should add keys to clients/packages/delivery_l10n/lib/l10n/app_en.arb and app_ar.arb and test RTL. The design shows only English.
- Money: 'Fresh USD' amounts (base rate) must go through the existing money formatting and be clearly non-payroll unless accounting-service consumes them.
- Privacy: emergency contacts, phone numbers and attendance are personal data about named individuals. Keep them carrier-scoped (company resolved from the token, never the request) with identical 404s for foreign riders, as every existing carrier route does, and never log them.
- Screenshots saved for implementers in D:/dev-cache/temp/claude/D--workspace-azkar/709fbe40-df14-4950-b9b5-9dbd338df9ab/scratchpad/figma/ (112-413_web-carrier-riders-directory.png, 112-740_web-carrier-rider-profile.png, 112-945_web-carrier-rider-attendance.png).

## Customer: multi-merchant cart and offline mode

### `121:358` multi-merchant-cart — XL

*Who:* Customer, mobile_app customer shell, Basket tab (nav index 2; the design highlights Basket).

*What:* A 'Smart Basket' that holds items from several shops (in the design, a restaurant, a dekkane and a pharmacy) and checks them all out in one go. It charges one 'Unified Delivery Fee' ($3.00) in place of the sum of the per-shop fees ($9.00), and shows the saving. Today the app and the server both refuse this, deliberately: one basket means one store means one order.

*Reached from:* CustomerShell -> CustomerNavBar Basket tab (CustomerNavBar.basketIndex, index 2) -> CartScreen, which becomes the Smart Basket when the cart holds more than one store. Also reached from any StorePageScreen's StickyBasketBar ('View basket' -> CustomerShell._openBasket), and from OrderDetailsScreen Reorder. The CTA pushes CheckoutScreen; on success onOrderPlaced switches to the Orders tab. The design's back chevron is not applicable on a tab root. Drop it or show it only when CartScreen is pushed.

**Every element, and where its data comes from**

- Header bar (white, bottom border DeliveryColors.border): back chevron in a round #f8fafc chip. This contradicts today's CartScreen, which is a tab with no onBack (surface-checklist: 'YdScreenHeader with NO onBack (it is a tab)'). Title 'Smart Basket' (Rubik Bold 18, ink). Subtitle 'Single checkout deliverable' (12, muted). Data: static strings.
- '3 Merchants' pill (brandSoft bg, brand text, 11 bold, radius 8). Data: count of distinct stores in Cart. Distinct stores, not merchants: Cart and the server key on storeId, and one merchant can own several stores.
- Merchant group section, repeated per store: an uppercase label 'FROM {STORE NAME} ({n} ITEMS)' (13 bold, muted), then a white bordered radius-16 card listing that store's lines. Data: Cart lines grouped by product.storeId; store name from the StoreCard captured at add time (Cart._store today holds only one).
- Line row inside the group card: '{qty}x {product name} ({options summary})' (14 regular, ink) with the line total on the right (14 bold). Data: CartLine.qty, product.name, optionsSummary, lineTotal (unitPrice already includes option deltas). The design has NO stepper, thumbnail, LBP price or delete, all of which today's _basketRow + QuantityStepper provide. Decide whether the stepper stays; the recommendation is to keep it.
- Summary section (white, top border): 'Individual Deliveries Combined' with the struck-through sum of each store's own fee ($9.00, 13, muted, line-through). Data: sum over groups of the zone-aware store fee. Must come from a server quote, not StoreCard.deliveryFee: the real fee is zone-priced via product-service GET /api/delivery-zones/terms/{storeId}?zoneId, and cart.dart warns that a locally computed total 'is how checkout came to quote 18.25 and then bill 15.00'.
- 'Unified Delivery Fee' row: $3.00 in brand red, 14 bold. Data: a new server-side bundle-fee policy. Nothing like it exists; see missingBackend.
- Savings badge '💰 You save $6.00!' (DeliveryAccent.positive green text on a grey rgba(209,214,224,.42) box, radius 8). Data: combined minus unified, from the quote. Hide it when the saving is 0, e.g. a single store.
- Primary CTA 'Checkout — $34.50' (brand, radius 12, 16 bold white, full width). BUG IN DESIGN: $34.50 is the goods alone (9.00+2.50+1.60+1.40+15.00+5.00). The unified $3.00 is left out, so the CTA would under-quote the bill by $3.00. It must show the server quote's grand total (goods + unified fee + express surcharge − waivers − promo). Tap pushes CheckoutScreen (CartScreen._checkout).
- States the design omits but the code already has and must keep, per group: store below its minimum (today t.minimumExplanationFull plus a disabled CTA; with several stores it has to say WHICH store); store closed (applyStoreTerms: '{store} is closed and is not taking orders right now'); store does not deliver to the chosen zone ('{store} does not deliver to that area'); delivery radius failed (checkout haversine check, t.custOutsideDeliveryArea). Also: free-delivery waiver line with the offer title (Cart.waiver / OfferApi.preview is per store), promo code row (_promoSection), Solo/Split toggle (_modeToggle / split plan), express tier surcharge row, empty basket YdEmptyState t.basketEmpty, and quote loading/failed states.
- Bottom nav (Home, Butler, Basket, Orders, Account): already CustomerNavBar/YdBottomNav with basketCount = cart.itemCount. No change.
- Removed interaction: the 'Start a new basket?' dialog in store_page_screen.dart (conflictsWith at ~248/290, switchTo at ~342) and the 'Replace your basket?' dialog in order_details_screen.dart (_confirmReplaceBasket ~247) stop appearing when a second store is added. Replace them with a max-stores cap dialog if product caps the number of shops.

**Existing code that already covers part of it**

- clients/apps/mobile_app/lib/src/cart.dart — Cart ChangeNotifier. Single _storeId/_store, conflictsWith() and a StateError on a second store, subtotal/deliveryFee/deliveryFeeCharged/total, amountBelowMinimum against one store, refreshWaiver(OfferApi) per one storeId, toOrderLines(), giftNote, splitPlanId, switchTo(). Its doc comment explicitly argues AGAINST mixing a pharmacy and a pizzeria in one basket.
- clients/apps/mobile_app/lib/src/cart_screen.dart (1232 lines) — the Basket tab. _storeStrip (725, one store name + ETA), _basketRow (760, thumbnail + QuantityStepper), _promoSection (863, 450ms debounced PromoApi.quote), _modeToggle/_splitSummary (split order), _summary (1035: Subtotal, Delivery/Free, Discounts + offer title, promo line, Total Amount with LBP, minimum explanation, YdPillButton 'Proceed to Checkout' / 'Minimum not reached').
- clients/apps/mobile_app/lib/src/checkout_screen.dart — _place() (219-356): address required, radius haversine against cart.store, one OrderApi.place, then TransferApi.initiate(orderId) and SplitApi.attachOrder(planId, orderId), cart.clear(), pop(order). Maps DioException 422/402/400 to messages.
- clients/apps/mobile_app/lib/src/customer_shell.dart — owns the single Cart, _requoteDelivery listener (a per-store waiver quote with a _quotedFor signature), IndexedStack tabs, CustomerNavBar(basketCount).
- clients/apps/mobile_app/lib/src/store_page_screen.dart (~248, 290, 342) and order_details_screen.dart (~209-247) — the second-shop conflict dialogs, plus Reorder that rebuilds the basket from one order.
- clients/packages/delivery_core/lib/src/api/order_api.dart — OrderApi.place() posts ONE order to POST /api/orders (items, deliveryAddress, deliveryZoneId, paymentMethod, deliveryTier, promoCode, paymentInstrumentToken, lat/lng).
- clients/packages/delivery_core/lib/src/api/offer_api.dart — OfferApi.preview(storeId, subtotal, deliveryFee) -> GET /api/offers/preview, per store. promo_api.dart — PromoApi.quote -> POST /api/promotions/validate.
- clients/packages/delivery_core/lib/src/models/store_models.dart — StoreCard: deliveryFee, minOrder, etaMin/MaxMinutes, availability, vertical (RESTAURANT/GROCERY/CONVENIENCE/PHARMACY/...), latitude/longitude, deliveryRadiusMetres.
- services/order-manager/.../service/OrderService.java place() (122-248) — refuses mixed merchants ('All items in an order must come from the same merchant') and mixed stores ('...same shop') with a 422. Then applyStoreTerms (acceptsOrders, zone served, per-store minimum, per-store zone fee via StoreClient.termsFor), chooseTier (express surcharge per order), FeeWaiverService.decideAtPlacement(subtotal, fee, storeId, merchantId), PromotionService.quote/redeem (maxPerCustomer counted per ORDER), payments.authorize (per order), outbox ORDER_PLACED.
- services/order-manager/.../api/dto/OrderDtos.java PlaceOrderRequest — one basket, no group/checkout id.
- services/order-manager/.../domain/Order.java — one merchantId/storeId/storeName per order; deliveryFee (what the carrier is owed), deliveryFeeWaived/merchantFeeWaived/carrierFeeWaived booleans, discountAmount, expressSurcharge, totalAmount. Waivers are all-or-nothing: there is no partial fee discount.
- services/order-manager/.../service/DispatchService.java chooseFor(merchantId) — carrier chosen per order at READY, honouring each merchant's pinned carrier/fallback policy. Order.assignRider claims one order at a time. No batching/multi-stop concept exists in order-manager or order-tracking (grep for batch/stacked/multi-stop is empty).
- services/accounting-service/.../event/OrderEventListener.java + service/SettlementService.java — settles each order on its own: merchant paid on subtotal, carrier owed OrderSnapshot.deliveryFee, waivers and discount applied, points awarded.
- services/notifications-manager/.../event/OrderEventListener.java — 'order.placed' sends one customer receipt and one merchant work item PER ORDER, so a 3-shop basket means 3 receipts.
- services/product-service/.../api/DeliveryZoneController.java GET /api/delivery-zones/terms/{storeId}?zoneId -> {served, deliveryFee, minOrder, etaMin, etaMax} — the per-store zone pricing a quote would reuse.
- clients/packages/delivery_design_system/lib/src/storefront.dart StickyBasketBar (940) — the shop-page basket bar, which today names the one store's shortfall.

**Missing in the clients**

- Cart refactor to multi-store: replace _storeId/_store with an ordered Map<storeId, BasketGroup{StoreCard store, lines, waiver}>. Per-group subtotal / amountBelowMinimum / meetsMinimum. The basket-wide meetsMinimum = every group meets its own. itemCount and qtyOf stay global. Removing the last line of a group drops the group. Replace conflictsWith with a max-stores check (e.g. canAdd(product) false when a new store would exceed the cap). New toOrderGroups() for the batch payload. Rewrite the class doc comment that currently forbids mixing.
- A server-quote holder on Cart (or a new BasketQuote ChangeNotifier) that replaces refreshWaiver: calls the new quote endpoint on each basket change, debounced, with a signature like customer_shell._quotedFor. It holds per-group fee/waiver/minimum/served plus combinedFees, unifiedFee, saving, grandTotal. Failure keeps the last quote, as refreshWaiver does now.
- CartScreen: a grouped layout. A 'Smart Basket' header + merchant-count pill (YdBadge) when groups > 1. Per group: an uppercase section label (YdSectionHeader or a Text style), a YdCard.bordered holding the existing _basketRow (keep QuantityStepper; the design's read-only rows are too thin for a basket), and a per-group warning row for below-minimum/closed/not-served with a 'Remove {store}' action. The summary gets the 'Individual Deliveries Combined' struck row, the 'Unified Delivery Fee' row and the savings badge. The CTA label becomes 'Checkout — {grandTotal}' from the quote. With a single store, keep today's layout unchanged (_storeStrip etc.).
- CheckoutScreen._place: branch to a new OrderApi.placeCheckout(groups...) when groups > 1. The radius check runs per group's store. TransferApi.initiate per returned order, or one checkout-level intent (open question). SplitApi.attachOrder currently takes one orderId, so split mode must be disabled for multi-store or changed to take a checkoutId. On success pop a list/checkout instead of a single DeliveryOrder; CartScreen.onOrderPlaced then jumps to Orders. Map a 422 naming a store to that group.
- delivery_core: OrderApi.quote(...) and OrderApi.placeCheckout(...) methods. New models BasketQuote/GroupQuote and Checkout{id, orders, unifiedFee, saving, total}. DeliveryOrder gains checkoutId (nullable).
- Remove or gate the start-new-basket dialog in store_page_screen.dart and the replace-basket dialog in order_details_screen.dart (Reorder adds a group instead of replacing). Add a cap dialog. StickyBasketBar shortfall text becomes per-store ('Add {amount} at {store}').
- MyOrdersScreen / OrderDetailsScreen: show that an order is part of a multi-shop checkout (a 'Part of a 3-shop order' chip), and link the siblings via checkoutId. Cancel semantics per order need copy explaining the unified fee impact.

**Missing in the backend**

- order-manager — product decision first: allow multi-store baskets at all. OrderService.place keeps its one-store rule for single orders; a NEW CheckoutService places N single-store orders in ONE @Transactional call. Each order goes through the exact same pricing (applyStoreTerms, tier, waivers, promo, payments.authorize), and any refusal rolls back all of them. Reuse place()'s internals by extracting a priceOrder(customerId, lines, request) step.
- order-manager — new endpoint POST /api/orders/checkout (or /api/checkouts), CUSTOMER role. Body {groups:[{items:[{productId,qty,optionIds}]}], deliveryAddress, deliveryZoneId, lat/lng, contactPhone, notes, paymentMethod, deliveryTier, promoCode, paymentInstrumentToken}. Returns {checkoutId, orders:[OrderResponse], combinedDeliveryFees, unifiedDeliveryFee, saving, totalAmount}. The server derives the groups itself from product.storeId, and never trusts client grouping for pricing.
- order-manager — new endpoint POST /api/orders/quote: a dry run of the same pricing path with no save, no authorization and no redemption. Returns per-store {storeId, storeName, served, acceptsOrders, subtotal, minOrder, shortfall, deliveryFee, deliveryFeeWaived, offerTitle} plus combined/unified/saving/grandTotal and the promo outcome. This also replaces the client's local total arithmetic for single-store baskets.
- order-manager — entity + migration V31__checkouts.sql (db/migration/orders; the latest is V30__carrier_order_indexes.sql). Table checkouts(id uuid pk, customer_id, unified_delivery_fee, combined_delivery_fees, created_at). orders gets checkout_id uuid null FK + index, and bundle_discount numeric(12,2) not null default 0 (the share of the saving allocated to this order, so totalAmount = subtotal + deliveryFee + express − bundle_discount − waivers − discount).
- order-manager — BundleFeePolicy (config like DeliveryTierPolicy: e.g. delivery.bundle.fee=3.00, max-stores=3, max-distance-between-pickups). Allocation rule: split the unified fee across the orders to the cent, with the remainder going to the largest order. The customer-facing charge drops, but Order.deliveryFee (what the carrier is owed) must NOT drop unless one carrier really does the whole route. Otherwise the platform funds the saving, and it should count against the FeeWaiverService budget.
- order-manager — Order.applyBundleDiscount(amount) + recalc, and OrderSnapshot.checkoutId/bundleDiscount on the outbox events.
- order-manager — promo on a multi-store checkout: PromotionService counts maxPerCustomer by redemption rows, i.e. per order. A code applied to 3 orders would either burn 3 redemptions or fail CUSTOMER_LIMIT_REACHED on the 2nd. It needs a checkout-level redemption (apply the discount once, allocated across orders).
- order-manager — dispatch: DispatchService.chooseFor is per merchant and runs at each order's READY. A real unified fee implies ONE carrier doing a multi-pickup run: a group dispatch that waits for (or batches) the READY siblings, picks a carrier allowed by EVERY merchant's policy, and assigns all siblings to one rider. Conflicting pinned carriers make this impossible, so fall back to separate dispatch with the platform absorbing the saving.
- order-tracking — multi-stop route/ETA for a rider carrying sibling orders (pickup A, B, C then one dropoff). Nothing exists.
- accounting-service — OrderEventListener/SettlementService must read bundleDiscount. The merchant is still paid on subtotal and the carrier on deliveryFee; the platform books the bundle discount as a cost, like a delivery-fee waiver. SettlementServiceTest cases are needed.
- notifications-manager — optional: a single customer receipt for 'checkout.placed' instead of N 'order.placed' receipts (merchant copies stay per order).

**Design-system pieces to reuse**

- YdScreenHeader (title/subtitle; no onBack on the tab)
- YdBadge (the '3 Merchants' pill: color DeliveryColors.brand, background DeliveryColors.brandSoft, uppercase false)
- YdCard.bordered (group card, radius DeliveryRadius.lg = 16, borderColor DeliveryColors.border)
- YdSectionHeader or the existing uppercase label style for 'FROM {store}'
- YdPillButton (CTA, busy while the quote/checkout is in flight)
- YdEmptyState (empty basket)
- QuantityStepper + CartScreen._basketRow / _summaryRow / _promoSection (reuse inside each group)
- StickyBasketBar (storefront.dart) with a per-store shortfall
- Tokens: #e11d48 DeliveryColors.brand, #fff1f2 brandSoft, #0f172a ink, #475569 muted, #94a3b8 faint, #e2e8f0 border, #f8fafc background, #10b981 DeliveryAccent.positive.color. Spacing: 16 = DeliverySpacing.md, 12 = md-4 (as cart_screen does). Radii 16/12/8 = DeliveryRadius.lg/md/sm. The savings box's rgba(209,214,224,.42) has no token; use DeliveryColors.borderFaint or a positive-tinted soft fill.
- MarketRates.instance.lbpParen for LBP under the totals, as today

**Strings**

- smartBasketTitle: 'Smart Basket' (ar needed)
- smartBasketSubtitle: 'Single checkout deliverable' (suggest rewording to 'One checkout, every shop')
- basketStoreCount: '{count, plural, =1{1 shop} other{{count} shops}}' (the design says 'Merchants'; stores are what we count)
- basketFromStoreItems: 'From {store} ({count, plural, =1{1 item} other{{count} items}})'
- individualDeliveriesCombined: 'Individual Deliveries Combined'
- unifiedDeliveryFee: 'Unified Delivery Fee'
- youSaveAmount: 'You save {amount}!'
- checkoutWithAmount: 'Checkout — {amount}'
- storeBelowMinimum: '{store}: add {amount} to reach the minimum'
- storeClosedRemoveItems: '{store} is closed right now. Remove its items to continue.'
- storeNotServingArea: '{store} does not deliver to this address'
- removeStoreFromBasket: 'Remove {store}'
- basketStoreLimit: 'You can order from up to {max} shops at once'
- partOfMultiShopOrder: 'Part of a {count}-shop order'
- Existing, to reuse: custMyBasket, subtotal, delivery, free, custDiscounts, custTotalAmount, custProceedToCheckout, minimumNotReached, minimumExplanationFull, addToReachMinimumShort, basketEmpty, navBasket. To retire or reword: startNewBasket, basketFromAnotherShopSingle ('We can only deliver from one shop at a time.'), basketFromShopReplace, replaceYourBasket.

**Tests that should prove it**

- Dart unit (mobile_app/test/cart_test.dart, new): adding products from 2 stores creates 2 groups and throws no StateError; per-group amountBelowMinimum; removing the last line of a group removes the group and keeps the other; the max-stores cap refuses a 4th store; toOrderGroups groups by storeId and keeps the option-keyed lines separate.
- Widget test (cart_screen grouped): 3 stores render 3 'FROM X (n ITEMS)' labels, the '3 Merchants' pill, the struck combined fee, the unified fee and 'You save' — from a FAKE quote, asserting no locally computed totals. The CTA shows the quote's grandTotal INCLUDING the unified fee (guards the design's $34.50 bug). A single store renders today's layout with no savings badge. One group below its minimum disables the CTA and names that store.
- Widget test (view_basket_test.dart update): opening shop B with a basket from shop A and tapping Add no longer shows 'Start a new basket?'; the badge count sums both stores; the cap dialog appears at the limit.
- Widget test (checkout_test.dart): a multi-store basket calls OrderApi.placeCheckout once (not N places); a 422 naming a store surfaces that store; split mode is hidden/disabled for multi-store; the radius check is applied per store.
- Java (order-manager CheckoutServiceTest): 3 stores -> 3 orders sharing a checkoutId, each priced by its own StoreClient terms; one store closed / not served / below its minimum -> 422 and ZERO orders saved (rollback); a payment decline on the 2nd authorization rolls back the 1st; bundle allocation sums exactly to the unified fee; carrier-owed deliveryFee is unchanged; promo redeemed once per checkout; mixed-merchant lines inside ONE group are still refused.
- Java (OrderServiceTest regression): POST /api/orders with two stores still returns 422 'same shop'.
- Java (accounting SettlementServiceTest): an order with bundleDiscount pays the merchant on subtotal and the carrier on deliveryFee, and books the discount as a platform cost; an older event without the field settles as before.
- API scenario (dev): quote with 3 stores returns combined 9.00 / unified 3.00 / saving 6.00; POST checkout returns 201 with 3 orders; GET /api/orders/mine shows checkoutId on all 3; the merchant of each store sees only its own order; cancelling one order while PLACED leaves the others valid (define the fee re-allocation).

**Questions**

- Product: do we reverse the deliberate one-store rule (cart.dart and OrderService.place both argue that a pharmacy and a pizzeria in one basket is 'one delivery nobody can make')? Which verticals may mix, is there a max number of shops, and is there a max distance between pickups?
- Is the unified fee a real operational saving (ONE rider, multi-pickup) or a marketing subsidy (N riders, platform pays the difference)? That decides whether group dispatch + multi-stop tracking (XL) is needed or only pricing + settlement (L).
- The CTA in the design ($34.50) excludes the $3.00 unified fee. Confirm the button must show the full payable total ($37.50).
- How is the unified fee computed: a flat amount, max(store fees), or zone-based? Does express tier apply per checkout or per order? How does it interact with a store's own free-delivery waiver (FeeWaiverService per store)?
- Cancelling one order of a checkout: does the customer pay the remaining shops' full individual fees, keep the unified fee, or is partial cancel forbidden?
- Card payments: one authorization per order (N holds on the customer's card), or one checkout-level hold that needs a provider change?
- Split-a-bill (SplitApi.attachOrder takes one orderId) and the diaspora gift note: disabled for multi-store, or moved to checkout level?
- Design items the backend cannot honour: 'Gas Cylinder Refill (Scheduled)' — there is no scheduled delivery in order-manager. 'Almaza Beer' — there is no age-restriction flag on products. A pharmacy product in a mixed basket — prescriptions are not modelled. Are these just sample data?
- Should the design keep read-only lines (no stepper/delete/thumbnail) as drawn? That would regress editing compared with today's CartScreen.

### `121:279` offline-mode — L

*Who:* Customer, mobile_app customer shell. The design's nav highlights the Orders tab, and the header has a back chevron, i.e. a pushed screen. Aimed at Lebanon's patchy connectivity and power cuts.

*What:* Lets a customer keep shopping when there is no connection. It shows an offline indicator and banner, a 'Cached Catalog' of their last purchases from a local dekkane with 'Quick Add', and a 'Sync Outbox Queue' of orders placed while offline that 'will send instantly when internet resumes'. Today the app has NO connectivity detection, NO cache and NO outbox, and the basket is deliberately not persisted.

*Reached from:* The offline banner and pill live in CustomerShell (every tab). Cached Catalog: when ConnectivityService is offline, the Home tab (StoreHomeScreen, which cannot load) shows an entry card / is replaced by CachedCatalogScreen, pushed with the back chevron as in the design. Sync Outbox Queue: a section at the top of MyOrdersScreen (Orders tab, CustomerNavBar.ordersIndex), which matches the design's active Orders tab. Checkout's 'Place when back online' adds to the outbox and jumps to Orders like a normal placement (CartScreen.onOrderPlaced).

**Every element, and where its data comes from**

- In-app 'OFFLINE' pill (amber #d97706 bg, white 9 bold, radius 4). The design puts it inside the iOS status bar mock, which the app cannot draw into; implement it as an app-level indicator instead. Data: a new ConnectivityService.isOnline.
- Offline alert banner (full width, #fef3c7 bg, #d97706 13 bold): '📡 You're offline — orders will sync automatically once connected.' Data: ConnectivityService. It should sit at shell level (above every tab's body), not per screen. Needs a 'Back online' transient state and hides on reconnect.
- Header: back chevron chip, title 'Cached Catalog' (18 bold), subtitle 'Local Dekkane' (12 muted) — the name of the store whose catalog is cached (StoreCard.name / vertical CONVENIENCE). Badge 'Offline Mode' (brandSoft/brand pill, 11 bold).
- Section 'Your Last Cached Purchases' (14 bold ink): a horizontal, clipped/scrolling track of 160px cached-cards. Each card: 70px image radius 8 (ProductImage from the cached thumb; ProductImage already falls back when offline), name (12 bold, ellipsis), price (11 semibold brand), and a 'Quick Add' button (brandSoft bg, brand 10 bold, radius 6). Data: a new local cache built while online from OrderApi.mine() line productIds + StoreApi.products(storeId, ids:) — the same derivation as StorePageScreen._loadBuyAgain (store_page_screen.dart 167-205) — persisted with the price and the time it was saved.
- Quick Add: Cart.add(product, from: cachedStoreCard) with the cached price. Only safe for optionless products: options are priced by a live catalog call (ProductOptionsSheet/ConfiguredProduct), so configured products either need their last configuration cached (optionIds + unitPrice, marked 'price confirmed on send') or are disabled offline. Show a 'Prices saved {ago}; may change' caveat.
- Section 'Sync Outbox Queue' (14 bold): queued-order cards with a #d97706 border, radius 16, 16px padding. Contents: a refresh-cw icon in a #fef3c7 radius-12 chip; title 'Order #4521 — Queued' (14 bold); '{store} • {amount}' (12 muted, e.g. 'Dekkane Abou Selim • $12.40'); 'Will send instantly when internet resumes' (11 semibold amber). Data: a new persisted PendingOrder outbox. NOTE: a queued order has no server id yet. '#4521' must be a client-side reference, and server orders only have DeliveryOrder.shortId (the first 8 characters of the UUID), so there is no '#4521'-style number anywhere.
- States implied by the design but not drawn, all required: sending (spinner); sent (card disappears and the real order appears in My Orders); price changed / item unavailable / shop closed / below minimum on send (needs review, with Review/Discard); failed (reason + Retry/Discard); empty outbox (section hidden); no cached purchases (empty state); back online (banner turns green briefly, then disappears).
- Bottom nav with Orders active: CustomerNavBar unchanged. Implies the outbox lives on (or is reached from) the Orders tab.

**Existing code that already covers part of it**

- NONE for connectivity: grep for connectivity/offline across mobile_app/lib and delivery_core/lib finds only comments. mobile_app/pubspec.yaml and delivery_core/pubspec.yaml have no connectivity_plus, path_provider, shared_preferences, sqflite, hive or drift.
- clients/packages/delivery_core/lib/src/network/api_client.dart — Dio with 20s connect/receive/send timeouts, a correlation-id interceptor and an auth interceptor (refresh on 401). No retry, no offline interceptor, no Idempotency-Key header.
- clients/packages/delivery_core/lib/src/network/user_queue_socket.dart:65 — `ValueNotifier<bool> connected` with 2s..60s jittered reconnect backoff (the STOMP socket for notifications/tracking). Usable as ONE reachability signal but not sufficient alone: it is false before sign-in and while no subscription is open.
- clients/apps/mobile_app/lib/src/rider_chat_screen.dart:81-95 — the existing pattern of listening to socket.connected (_onConnectivity).
- clients/apps/mobile_app/lib/src/cart.dart — the basket is in memory only, BY DESIGN (doc comment: prices are re-read at placement, so a restored basket could show a stale total). Offline mode directly contradicts this.
- clients/apps/mobile_app/lib/src/checkout_screen.dart _place() — on DioException it maps 422/402/400 and anything else (including connection errors) to t.couldNotPlaceOrder in a SnackBar. The basket is kept, nothing is queued.
- clients/apps/mobile_app/lib/src/my_orders_screen.dart — 'Active'/'Past' tabs, a Timer.periodic poll (_refresh(silent: true)), and a YdEmptyState t.couldNotLoadOrders on first-load failure. Where the outbox section would sit.
- clients/apps/mobile_app/lib/src/store_page_screen.dart _loadBuyAgain (167-205) — 'Buy Again' derived from OrderApi.mine(size: 20) product ids, intersected with StoreApi.products(storeId, ids:). The source for 'Last Cached Purchases'.
- clients/apps/mobile_app/lib/src/delivery_address.dart — DeliveryAddressStore persists addresses (with zoneId, lat/lng) in FlutterSecureStorage, scoped to ownerId. The only customer data available offline today, and enough to build a queued order's address.
- clients/packages/delivery_design_system/lib/src/product_image.dart:86 — already falls back gracefully for an offline client / expired presigned URL. It does not cache bytes to disk.
- clients/apps/mobile_app/lib/src/hyperlocal_screen.dart — 'Neighborhood Dekkane' browse. Per the surface-checklist it is UNREACHABLE today; related to the 'Local Dekkane' subtitle.
- services/order-manager/.../service/OrderService.java place() — prices, the store's availability, zone fee, minimum, waivers, promo and payment authorization are ALL decided at placement time from live data. Nothing is accepted from the client, so a queued order is really a re-submitted basket, priced when it arrives.
- services/order-manager/.../api/OrderController.java POST /api/orders — no Idempotency-Key handling (grep finds idempotency only in accounting/notifications/onboarding/pos spec). A replayed request after a timeout places a DUPLICATE order.

**Missing in the clients**

- ConnectivityService in delivery_core (a ChangeNotifier/ValueListenable<bool>). Combine an OS network signal (add connectivity_plus) with real reachability: a cheap gateway ping, plus marking offline on DioExceptionType.connectionError/connectionTimeout and online on any successful response through a new Dio interceptor in ApiClient.create. Optionally OR it with UserQueueSocket.connected.
- OfflineBanner widget (design system or mobile_app) mounted once in CustomerShell above the IndexedStack body, plus the 'OFFLINE' pill. Listens to ConnectivityService.
- Local cache store for the offline catalog (new; add path_provider + JSON files, or drift/sqflite). NOT FlutterSecureStorage: that is for secrets and small values, and the catalog plus thumbnails is bulk data. Cache: last N purchased products (id, name, price, thumb URL, storeId, hasOptions), their StoreCards (fee, minOrder, availability, zone data), the time each was saved, scoped to session.subject like DeliveryAddressStore. Refreshed opportunistically whenever online (e.g. after My Orders loads). Optional image byte cache for the 70px thumbs.
- CachedCatalogScreen ('Cached Catalog' / store subtitle / 'Offline Mode' badge / 'Your Last Cached Purchases' track with Quick Add), reachable when offline. Quick Add is limited to optionless products unless a last configuration is cached.
- Cart persistence while offline (reverses the in-memory-only decision): persist the basket only while offline or while an outbox item references it, and show 'prices may change' on restore.
- OrderOutbox (ChangeNotifier, persisted) with a PendingOrder model: clientRequestId (UUID v4), clientRef (a short display ref like '#4521'), storeId/storeName, lines (productId, qty, optionIds, the unit price seen), address line/zoneId/lat/lng, contactPhone, notes, paymentMethod (CASH only), deliveryTier, expectedTotal, createdAt, status {queued, sending, needsReview, failed}, lastError. It drains FIFO when ConnectivityService goes online, with backoff, sending the SAME Idempotency-Key on every retry. On 409/422 it moves to needsReview and never retries silently. On success it removes the item and refreshes MyOrders.
- CheckoutScreen._place: when offline, or on a connection-class DioException, offer 'Place when back online' (queue) instead of only the SnackBar. Refuse to queue card/wallet payments (authorization needs the provider) and promo codes (re-evaluated server-side; the outcome is unknown). Clear the cart only after queueing succeeds.
- OutboxSection in MyOrdersScreen (above Active): the queued-card UI, with Review/Retry/Discard.
- delivery_core OrderApi.place(): an optional idempotencyKey parameter -> 'Idempotency-Key' header, and an optional expectedTotal field.

**Missing in the backend**

- order-manager — Idempotency-Key on POST /api/orders (and on the new checkout endpoint). Migration V31__order_client_request_id.sql in db/migration/orders (latest is V30): orders.client_request_id varchar(64) null, with a UNIQUE(customer_id, client_request_id) index. OrderService.place: if a row exists for (customerId, key), return it with 200 instead of placing again; the same key with a different body gets 409 (the same rule as the pos-service spec in docs/MERCHANT_SUITE_SPEC.md ~438).
- order-manager — an optional expectedTotal on PlaceOrderRequest: after pricing, if expectedTotal != order.totalAmount, throw a new 409 PRICE_CHANGED carrying the new total and lines, so a queued order is NEVER charged at a price the customer did not see. (Consistent with the existing philosophy: the server prices; the client only asserts what it agreed to.)
- order-manager — optional clientCreatedAt on PlaceOrderRequest (audit only; placedAt stays server time, and SLA/ETA must not run from the offline time).
- No backend is needed for the cached catalog itself: OrderApi.mine + StoreApi.products(ids:) already exist (product-service).

**Design-system pieces to reuse**

- YdScreenHeader (title 'Cached Catalog', subtitle, back button YdBackButton)
- YdBadge ('Offline Mode' pill brand/brandSoft; the 'OFFLINE' pill needs an amber background)
- YdCard.bordered (cached-card radius DeliveryRadius.md = 12; queued-card with borderColor amber, radius 16)
- ProductImage / NetImage (thumbs, already offline-tolerant)
- YdPillButton.secondary / YdChip for 'Quick Add'
- YdSectionHeader ('Your Last Cached Purchases', 'Sync Outbox Queue')
- YdEmptyState (no cached purchases)
- DeliveryAddressStore (address for queued orders), StorePageScreen._loadBuyAgain logic (move it into a shared BuyAgainRepository so the store page and the offline cache share it)
- UserQueueSocket.connected as an extra reachability hint
- Tokens: #fef3c7 and #d97706 are NOT tokens (the nearest is DeliveryAccent.caution F59E0B / B45309). Add DeliveryColors.cautionSoft (#FEF3C7) and use DeliveryAccent.caution.strong (#B45309, better contrast) or add #D97706 as a token. Also brand/brandSoft/ink/muted/border/background as in the frame, and DeliveryStatusColor.offline (#9E9E9E) exists but is the neutral grey, not this amber.

**Strings**

- offlinePill: 'OFFLINE'
- offlineBanner: 'You're offline — orders will sync automatically once connected.' (consider 'will be sent when you're back online')
- backOnline: 'Back online'
- offlineModeBadge: 'Offline Mode'
- cachedCatalogTitle: 'Cached Catalog'
- lastCachedPurchases: 'Your Last Cached Purchases'
- quickAdd: 'Quick Add'
- cachedPricesCaveat: 'Prices saved {ago} and may change'
- needsConnectionForOptions: 'Connect to choose options'
- noCachedPurchases: 'Nothing saved for offline yet'
- syncOutboxQueue: 'Sync Outbox Queue' (consider 'Waiting to send')
- queuedOrderTitle: 'Order {ref} — Queued'
- queuedOrderStoreAmount: '{store} • {amount}'
- willSendWhenOnline: 'Will send instantly when internet resumes'
- queueOrderAction: 'Place when back online'
- queuedCashOnly: 'Only cash orders can be queued offline'
- queuedSending: 'Sending…'
- queuedPriceChanged: 'Prices changed — review before sending'
- queuedFailed: 'Could not place: {reason}'
- queuedReview / queuedRetry / queuedDiscard: 'Review' / 'Retry' / 'Discard'
- Existing, to reuse: couldNotReachTheServer, tryAgain, couldNotPlaceOrder, couldNotLoadOrders, navOrders

**Tests that should prove it**

- Dart unit (delivery_core): ConnectivityService goes offline on a DioExceptionType.connectionError from a fake adapter and online on the next 2xx; a 401/422 does NOT flip it offline.
- Dart unit (mobile_app): OrderOutbox persists a PendingOrder across a simulated restart (fake storage, mocked flutter_secure_storage/path_provider channel as view_basket_test does); drains in FIFO on reconnect; reuses the same Idempotency-Key on retry; a 409 PRICE_CHANGED moves the item to needsReview and stops auto-send; card payment cannot be queued.
- Widget test: CustomerShell shows the offline banner when the fake ConnectivityService is offline and hides it on reconnect; the banner does not cover the nav bar; Arabic RTL mirrors (extend arabic_rtl_test.dart).
- Widget test: CachedCatalogScreen renders the cached cards with the saved-at caveat; Quick Add adds an optionless product to the Cart with the cached price; a product with options shows disabled / needs-online; no cached items shows the empty state.
- Widget test (checkout_test.dart): a connection error from the fake OrderApi offers 'Place when back online'; choosing it queues the order, clears the cart and lands on Orders with the queued card; a 422 still shows the server detail and does not queue.
- Widget test (MyOrdersScreen): outbox section states queued/sending/needsReview/failed; Discard removes it; the real order appears after a successful drain.
- Java (order-manager OrderServiceTest/OrderControllerTest): the same Idempotency-Key twice returns the first order and creates one row, with one promo redemption, one payment authorization and one ORDER_PLACED outbox event; the same key with a different body returns 409; expectedTotal mismatch returns 409 with the new total and saves nothing; no key behaves exactly as today.
- Integration (device): airplane mode -> banner; queue a cash order; airplane off -> exactly one order in GET /api/orders/mine and the merchant sees it once.

**Questions**

- Should a queued order auto-send when back online if the total changed, or always require re-confirmation? The recommendation is to auto-send only when the server total equals the queued expectedTotal, else needsReview. The copy 'Will send instantly' over-promises and needs a softer wording.
- How long may an order sit in the outbox (e.g. expire after 2 hours; a dekkane may have closed, and a food order placed 5 hours late is wrong)? Should customers be warned the shop may be closed by then?
- Is offline limited to cash on delivery? Card/wallet authorization and promo codes cannot be decided offline.
- Is 'Cached Catalog' one store (the design says 'Local Dekkane') or last purchases across all stores? It interacts with the one-store Cart rule unless the multi-merchant cart ships first.
- Order reference: the design shows '#4521'. The server has only UUIDs (DeliveryOrder.shortId = 8 hex chars). Do we introduce a human order number server-side (new sequence column), or show a client ref for queued items only?
- Reversing the deliberate 'basket is never persisted' decision in cart.dart: acceptable if restored baskets are always re-quoted before placement?
- Should offline also cover the rider app (a rider in a dead zone marking Delivered)? It is not in this frame, but it is where offline hurts most.
- The 'OFFLINE' pill is drawn inside the OS status bar, which Flutter cannot draw into. Is the in-app banner enough?

**Build order for this cluster**

- 1. order-manager: Idempotency-Key on POST /api/orders (migration V31 orders.client_request_id + UNIQUE(customer_id, client_request_id); same key returns the first order, a different body returns 409) plus OrderServiceTest. Small, safe, and a prerequisite for any offline replay or batch retry; it also fixes duplicate orders after today's 20s timeouts.
- 2. order-manager: POST /api/orders/quote (a dry run of place(): store terms, zone fee, tier, waiver, promo; no save/authorize/redeem) for ONE store. Switch CartScreen to show the server quote instead of the local cart arithmetic. Behaviour is otherwise unchanged.
- 3. Client: a ConnectivityService (delivery_core, Dio interceptor + connectivity_plus) and an OfflineBanner in CustomerShell; map connection-class DioExceptions to 'you're offline' instead of 'could not place order'. Read-only awareness only.
- 4. Client: an offline cache of last purchases (extract StorePageScreen._loadBuyAgain into a shared repository; persist to app files, not secure storage) and CachedCatalogScreen with Quick Add for optionless products.
- 5. order-manager: an optional expectedTotal guard (409 PRICE_CHANGED). Client: a persisted OrderOutbox (cash only, no promo) drained on reconnect with a stable Idempotency-Key, and an outbox section in MyOrdersScreen, plus checkout's 'Place when back online'.
- 6. Product decision gate for multi-merchant: which verticals may mix, max shops, whether the unified fee is operational (one rider) or subsidised, and the fixed CTA total.
- 7. order-manager: a checkouts table (V32) + orders.checkout_id/bundle_discount, CheckoutService placing N single-store orders atomically (any refusal rolls everything back), a multi-store quote, and checkout-level promo redemption. With the unified fee disabled at first, every order is priced as today.
- 8. Client: Cart refactor to store groups, grouped CartScreen (Smart Basket header, per-store sections, per-store minimum/closed/not-served warnings), CheckoutScreen batch placement, removal of the start-new-basket / replace-basket dialogs (a cap dialog instead), and checkout siblings in My Orders.
- 9. order-manager + accounting-service: BundleFeePolicy and allocation (bundle_discount per order, carrier-owed deliveryFee untouched, platform-funded and counted against the waiver budget), OrderSnapshot fields, SettlementService handling, savings line in the UI.
- 10. (Only if the unified fee is operational) group dispatch to one carrier respecting every merchant's DispatchService policy, multi-pickup route/ETA in order-tracking, and rider-app grouping of sibling orders.

**Cross-cutting**

- Both frames push against deliberate design decisions written into the code: cart.dart says the basket is one store and never persisted, and OrderService.place says one store per order and never trust client prices. Record any reversal as a product decision, and update the class doc comments so the next reader is not misled.
- Server-priced-everything rule: any number the UI shows as a fee, saving or total (unified fee, savings, a queued order's $12.40) must come from a server quote or be re-validated at placement (expectedTotal). cart.dart already records an incident where a local total quoted 18.25 and billed 15.00.
- Idempotency is missing on POST /api/orders today. Both an offline outbox and a multi-order checkout retry would create duplicate orders, duplicate promo redemptions and duplicate payment holds without it. Build it first.
- Per-order side effects fan out N times for a multi-store checkout: payment authorization, TransferApi.initiate, promo redemption, fee-waiver budget records, order.placed notifications (a customer receipt each) and settlement. Each needs a checkout-level decision.
- Design colours outside the token set: amber #d97706 / #fef3c7 (offline) and the savings box grey rgba(209,214,224,.42). Add tokens (e.g. DeliveryColors.cautionSoft) rather than hard-coding hex. Note that DeliveryStatusColor.offline is a neutral grey meant for rider/order status, not this banner.
- Both frames draw an iOS status bar with a back chevron on tab roots. The status bar is a mock (do not implement), and tab roots (CartScreen) have no back button in the current shell.
- l10n: every new string needs en + ar in clients/packages/delivery_l10n/lib/l10n/app_en.arb / app_ar.arb (generated class DeliveryStrings, output lib/generated), with ICU plurals for the item/shop counts, and an RTL check in arabic_rtl_test.dart.
- Figma PNGs saved for implementers: D:/dev-cache/temp/claude/D--workspace-azkar/709fbe40-df14-4950-b9b5-9dbd338df9ab/scratchpad/figma/121-358_multi-merchant-cart.png and .../121-279_offline-mode.png

## Souk landing page (web)

### `119:4` souk-landing-page — M

*Who:* Anonymous visitors to the public site: prospective sellers (home cooks, artisans, tutors, freelancers), local shoppers, and Lebanese abroad. None of them has an account. Existing partners use the Log In link.

*What:* A public marketing page (1440x6144) for a DIFFERENT brand: 'Souk', with an Arabic letter-seen mark. It pitches a Lebanese micro-entrepreneur marketplace (home cooks, mouneh, crafts, tutoring, creative freelancers) with diaspora gifting and payments. Its jobs are to recruit sellers and to send shoppers to a marketplace. It is NOT a redesign of the current YouDrop landing page (clients/website/index.html, rebuilt from Figma frame 14:4): the name, palette, typefaces, audiences and proposition all differ, and riders, carriers and Butler are absent. DECISION: EXTEND, do not replace. Ship it as a separate static page at /souk (souk.html + souk.css + souk.js in clients/website) and leave index.html alone until product says whether Souk is a rebrand of the whole platform. A rebrand would also mean re-skinning register.html, the portal and the app, which is outside this frame.

*Reached from:* Public website, served by nginx at https://www.youdrop.shop/souk (new exact-match location). It is not linked from index.html until product decides whether to cross-link it (for example a footer link, or making /souk the front door). If Souk gets its own domain, add a host rule in deploy/k3s/cluster/website.yaml. Outbound: Become a Seller, Launch Your Store and Start Your Free Shop -> /register?kind=MERCHANT. Shop Local Goods, Explore the Souk Marketplace and Explore Diaspora Portal -> /app (APK) with the Android APK tag, until a web storefront exists. Log In -> the portal URL from config.js. Nav and footer links are in-page anchors only.

**Every element, and where its data comes from**

- PAGE TOKENS (from get_design_context; not in site.css or tokens.dart): cream bg #FAF7F2, white #FFFFFF, terracotta brand #C55A37 (pill tint rgba(197,90,55,0.1)), olive #4E5E41 (stats band, tools card, final CTA, secondary buttons), sage pill bg #F1F4F0, ink #1A1E18 (text and footer bg), body grey #5C6257, hairline #E8E2D5, peach #E6A28A (footer headings; icon tiles at 15% opacity), footer link #F2EDE4. Display font: Cormorant Garamond (Medium/SemiBold/Bold; 64/48/44/40/32/24/22/20). UI and body font: DM Sans (Regular/Medium/SemiBold/Italic; 18/16/15/14/13/12/11). Radii: button 4, card 8, tools card 12, pill 100, logo tile 6. Sections use 80px side padding and 112px top/bottom; content measure 1280.
- 1 NAV HEADER (119:5), 88px tall, cream, bottom hairline. Logo: a 36px terracotta tile with the Arabic letter seen in cream (Cormorant Bold 22), then 'Souk' (Cormorant Bold 28). Links to /souk. Nav (DM Sans Medium 14, gap 40): 'How it Works' -> #how, 'Explore Categories' -> #categories, 'Our Impact' -> #impact (the stats band), 'Diaspora Support' -> #diaspora, 'Success Stories' -> #stories. Actions: 'Log In' is a text link (olive, SemiBold 14) that should go to the portal; today index.html hard-codes https://portal-dev.youdrop.shop, so read it from config.js instead. 'Become a Seller' is a terracotta button (padding 20x10, radius 4) -> /register?kind=MERCHANT. NOT IN THE DESIGN BUT REQUIRED: the EN/AR language toggle that every site page has (site.js mechanism), and a collapsed nav below 900px, which the existing site handles by hiding the nav. Data: static.
- 2 HERO (119:20), 680px tall, cream, two columns of 624. Left: a sage pill 'LEBANESE MICRO-ENTREPRENEURSHIP PLATFORM' (olive, SemiBold 12, uppercase); H1 'Empowering the home cooks, artisans, and makers of Lebanon.' (Cormorant Medium 64, line-height 1.1); lede (DM Sans 18/1.6, #5C6257). CTA row, gap 16: 'Launch Your Store' (terracotta filled, 28x16 padding) -> /register?kind=MERCHANT, and 'Shop Local Goods' (1.5px olive outline). There is no customer web storefront, so the only honest target is /app (the Android APK) with the existing 'Android APK' tag chip (.cta-soon pattern). Feature row, gap 24: three 16px check icons with labels 'No upfront fees', 'Lebanon-wide logistics' and 'Diaspora orders enabled'. The third is FALSE today: DiasporaScreen is unreachable and there is no foreign-card rail. Right: a 4-photo gallery in 2 columns of 304, gap 16; column 1 is 304h + 200h, column 2 is offset 40px down with 200h + 264h; radius 8, object-fit cover. Photos are decorative (alt empty or brief).
- 3 STATS BAND (119:52), 'Our Impact', olive, padding 48/80, four 240-wide centred columns: '4,200+' Active Home Businesses, '24+' Lebanese Villages Represented, '$1.8M+' Earned by Local Creators, '45k+' Global Orders Delivered (Cormorant SemiBold 44 cream; labels DM Sans Medium 14 #F1F4F0). ALL FOUR FIGURES ARE INVENTED. Nothing produces them: /api/orders/stats in order-manager is BACKOFFICE-only, there is no 'village' concept (DeliveryZone is a named area), and there are no international orders. Follow the rule index.html already applies to its counters band: keep the labels, show a '-' figure with a 'Coming soon' chip, and hold the designed numbers in an HTML comment. Optional live data needs a new public endpoint (see missingBackend).
- 4 HOW IT WORKS (119:65), id=how, white. Centred header: a terracotta-tint pill 'GROUNDED EMPOWERMENT' and H2 'Everything you need to turn your craft into a sustainable living.' (Cormorant Medium 48, 720 wide). Three equal cards, gap 32: cream bg, 1px #E8E2D5 border, radius 8, padding 32; number '01/02/03' (Cormorant SemiBold 40 terracotta), title (Cormorant SemiBold 24), body (DM Sans 15/1.6). Card 01 'Set up in minutes': storefront on the phone, products, custom preparation or crafting times, own prices. The merchant app has products and store hours, but no preparation-time field exists in product-service. Card 02 'We handle the logistics': pickup from home, delivery across Lebanon and 'to our custom international diaspora hubs'. The international part is FALSE. Card 03 'Get paid instantly': weekly payments in fresh USD or bank transfers, 'Keep 92%'. This CONTRADICTS the backend: commission-percentage is 12.5 (accounting-service application.yml:106; FeeWaiverService default 12.5), so sellers keep 87.5%. Settlement happens at delivery with cash on delivery, and merchants are paid in points; there is no bank rail (SettlementService doc). The title also says 'instantly' while the body says 'weekly'. Copy must change before shipping.
- 5 CATEGORIES (119:86), id=categories, cream. Header row: a sage pill 'EXPLORE SOUKS', H2 'A rich ecosystem of Lebanese talent' (Cormorant 44), and on the right an outline terracotta button 'View All Marketplace Categories'. The design gives no target, and no web category page exists, so point it at /app or drop it. 2x2 grid of 624-wide cards, gap 24: white, border #E8E2D5, radius 8, a 260px photo on top, body padding 28 with gap 16. Each card has a title (Cormorant SemiBold 24), a sage pill tag, a description (DM Sans 15) and 'Explore category sellers' with a 14px arrow-right (terracotta SemiBold 14). Cards and tags: 'Mouneh and Home Cooking' / FRESH AND ARTISANAL; 'Artisanal Crafts' / HERITAGE CRAFT; 'Tutoring and Knowledge' / LOCAL KNOWLEDGE; 'Creative Services' / DIGITAL TALENT. CONTRADICTS THE BACKEND: Store.Vertical (product-service domain/Store.java:53, check constraint in V11__stores.sql) is RESTAURANT, COFFEE, GROCERY, CONVENIENCE, PHARMACY, ELECTRONICS, FLOWERS_GIFTS. There is no crafts, home-food, tutoring or services vertical. OrderKind (order-manager) is CATALOG / BUTLER_BUY / BUTLER_SEND, so a tutoring or freelance service cannot be ordered at all. GET /api/categories and /api/stores need a token, because product-service uses only the default permit-all list. Ship the cards as static content, link them to /app, and ask product whether the Tutoring and Creative Services cards stay.
- 6 BUILT-IN TOOLS (119:143), white, left column 515 and right card 733. Left: a terracotta-tint pill 'ALL-IN-ONE PLATFORM', H2 'Empowered with world-class tools.' (44), and a lede (16). Three feature rows, gap 24; each has a 40px tile (peach #E6A28A at 15% opacity, radius 6) with a 20px icon, a title (Cormorant SemiBold 20) and a body (DM Sans 14/1.5). Rows: 'Souk Delivery Network' (truck icon); 'Global USD Payments' (credit-card icon), whose card acceptance and FX claims are FALSE today because there is no card processor and the platform runs on cash on delivery plus points; 'Instant Storefront Builder' (layout icon), where the merchant has a store profile in the app but no storefront builder. Right: the tools-visual, an olive card (radius 12, padding 40, height 500) with 'Your Local Store, Elevated.' (Cormorant 32 cream) and a subline (14). Inside it, a white mock card (radius 8, padding 24, shadow 0 16 16 rgba(0,0,0,.06)): a 36px round avatar photo, 'Hala's Mountain Olive Soap' / 'Koura, Lebanon', a sage pill 'STORE LIVE', a hairline, then two cream KPI tiles: 'THIS WEEK'S REVENUE $412.50 USD' (Cormorant Bold 22 terracotta) and 'PENDING DELIVERIES 12 Orders' (olive). This is a product mock-up; index.html accepts sample data in a product picture (its Control Tower card), but make the sample shop name clearly generic. Data: static.
- 7 DIASPORA (119:196), id=diaspora, cream. A 624x480 photo (radius 8) on the left, text column 624 on the right. A sage pill 'DIASPORA CONNECTION', H2 'A bridge across boundaries. Support Lebanon from anywhere.' (44), and a lede about a 'Diaspora Portal' for expats in the US, Europe and Gulf: order goods, send gift baskets, 'direct funds straight to home-based freelancers'. Two rows with 20px gift icons: 'International Payments, Local Impact' (pay in USD/EUR/GBP, routed to bank accounts or cash pickup) and 'Direct Home Gifting'. CTA: 'Explore Diaspora Portal' (olive filled). REALITY: DiasporaScreen (mobile_app/lib/src/diaspora_screen.dart, Figma 80:133) exists but has zero call sites, and its own doc says the foreign-card rail does not exist. transfer-service (/api/transfers) moves money through cash plus a Whish/OMT simulator only. Sending funds to individuals is remittance and likely needs a licence. There is no portal page, so the CTA can only go to /app, or it needs an honest 'Coming soon' chip.
- 8 SUCCESS STORIES (119:219), id=stories, white. Centred terracotta-tint pill 'PROUD STORIES OF RESILIENCE' and H2 'Beloved stories from our local sellers' (44, 720 wide). Two cards, gap 32: cream, border, radius 8; a 220x332 portrait on the left; content padding 32 with a 24px text-quote icon, an italic quote (DM Sans Italic 15/1.6), a name (Cormorant Bold 20) and a role line (olive SemiBold 12 uppercase). The designed quotes come from 'Teta Mariam, Bsharre' and 'Rami Khoury, Byblos'. These are INVENTED testimonials with portraits of people who may not exist. index.html rejects exactly this for its own testimonials (see its 'CONTENT STILL PENDING SIGN-OFF' comment). Ship the card geometry with 'Awaiting a seller' placeholders and a 'Coming soon' chip, like the existing .quote.pending cards. No backend: StoreReview is customer-to-store feedback, not a seller testimonial.
- 9 FINAL CTA (119:243), olive, centred. H2 'Let's build Lebanon's independent future, together.' (Cormorant Medium 64/1.1, cream, 800 wide), lede (DM Sans 18, 600 wide). Buttons, gap 16: 'Start Your Free Shop' (terracotta, padding 36x18) -> /register?kind=MERCHANT; 'Explore the Souk Marketplace' (1.5px cream outline) -> /app with the Android APK tag.
- 10 FOOTER (119:252), bg #1A1E18, padding 80/80/40. Brand column (320): a 32px logo and a mission paragraph (14/1.6 #E8E2D5). Three 180-wide link columns with peach headings (Cormorant SemiBold 18 uppercase) and links (DM Sans 14 #F2EDE4, gap 10). Sellers: How It Works -> #how; Storefront Builder -> #tools; Shipping and Logistics -> #tools; Success Stories -> #stories; USD Wallet Payouts has no page. Marketplace: Explore Mouneh, Artisanal Crafts, Tutoring Services and Professional Freelancers -> #categories; Gift Card Portal has no page (gift cards do not exist; PromoCode is not a gift card). Diaspora Support: Expat Shipping Hub, Direct Gifting Solutions, Support Village Artisans and NGO Alliances have no pages. Then a hairline. Bottom row (13px): '(c) 2026 Souk Lebanon Technologies Ltd. Handcrafted with pride in Beirut.' This legal entity differs from 'YouDrop Logistics Technologies' in index.html. Social text links Instagram, Twitter and Facebook: no accounts exist, so render them inert with a Coming soon chip, as index.html does. Follow the house rule 'a link into a 404 is worse than no link': do not render links without destinations. MISSING FROM THE DESIGN but needed before going public: Terms, Privacy, and the footer language toggle.
- STATES: static page, no network calls, so no loading or error states. It must work with JS off: English in the markup, and the language button does nothing. Arabic: html lang=ar dir=rtl through the site.js-style dictionary. Neither Cormorant Garamond nor DM Sans has Arabic glyphs, so Arabic needs its own stack (for example Noto Naskh Arabic or Amiri for display; self-hosted, OFL). Responsive: the design exists only at 1440; add breakpoints at 900 and 560, as site.css does (stack the hero, gallery, categories grid, tools and diaspora into one column; stats go 2x2). Honour prefers-reduced-motion. Anchors need scroll-padding-top for a sticky header.

**Existing code that already covers part of it**

- D:/workspace/delivery/clients/website/index.html - the current YouDrop landing page (Figma 14:4). Reusable patterns: section bands, .cta-soon plus the 'Android APK' tag, the .soon chip, .quote.pending placeholders, inert social spans, and the honesty comments covering invented stats, testimonials and dead links.
- D:/workspace/delivery/clients/website/site.js - EN/AR switch: data-t nodes, inline AR dictionary, English read from the DOM, localStorage key 'youdrop-lang', aria-pressed on every data-lang-toggle. Its dictionary is page-specific, so souk.js needs its own AR map (or site.js needs refactoring to load a per-page map).
- D:/workspace/delivery/clients/website/site.css - shared primitives (--gutter clamp(20px,5.56vw,80px), --measure 1280, scroll-padding, Rubik self-hosted, the Arabic font stack, breakpoints). Its colours are the YouDrop rose tokens copied from tokens.dart, which do not match Souk.
- D:/workspace/delivery/clients/website/nginx.conf - the catch-all 'location / { try_files $uri $uri/ /index.html; }' means /souk currently answers 200 with the YouDrop page. Exact-match blocks for /register and /admin show the pattern to copy. /app serves the APK.
- D:/workspace/delivery/clients/website/register.html + register.js - the seller sign-up target (/register?kind=MERCHANT; kinds MERCHANT/CARRIER; the onboarding Kind enum also has RIDER). It is YouDrop-branded.
- D:/workspace/delivery/clients/website/config.js - DELIVERY_API_BASE and DELIVERY_IAM_BASE; the right place for a portal URL for 'Log In'.
- D:/workspace/delivery/infra/deploy-website.sh - copies the whole clients/website directory and the nginx configmap; new files ship with no change to the script.
- D:/workspace/delivery/deploy/k3s/cluster/website.yaml - an IngressRoute for www.youdrop.shop only; a separate Souk domain would need a new host rule, DNS and a certificate.
- D:/workspace/delivery/infra/smoke-test-website.js - the website smoke test. It is ALREADY STALE: it asserts 'Your city, delivered', class=backdrop and ports 5010/5012/5013, none of which appear in the current index.html or site.css.
- D:/workspace/delivery/clients/apps/mobile_app/lib/src/diaspora_screen.dart - 'Send to Lebanon' flow (recipient = saved address, gift note). Unreachable; the checklist also flags a '0026' string bug in the custStartOrder ARB entry.
- D:/workspace/delivery/services/product-service/src/main/java/com/delivery/product/domain/Store.java - the Vertical enum, which has no crafts, home-food, tutoring or services value.
- D:/workspace/delivery/services/product-service/src/main/java/com/delivery/product/api/MarketController.java - GET /api/market/config (lbpPerUsd). All prices are stored in USD.
- D:/workspace/delivery/services/order-manager/src/main/java/com/delivery/order/api/OrderController.java - GET /api/orders/stats (BACKOFFICE-only counts by status); the only existing aggregate.
- D:/workspace/delivery/services/accounting-service/src/main/java/com/delivery/accounting/service/SettlementService.java - settlement at delivery, cash on delivery, points instead of bank transfer, 12.5% commission.
- D:/workspace/delivery/services/transfer-service - /api/transfers: cash plus a Whish/OMT simulator; the nearest thing to the design's 'cash pickup' claim.
- D:/workspace/delivery/platform/platform-security/.../PlatformSecurityProperties.java - the default permit-all list is actuator and docs only. Each service opens its own public paths in application.yml (onboarding opens /api/onboarding/applications; order-manager opens /api/delivery-providers/hiring).

**Missing in the clients**

- clients/website/souk.html - new page: 10 sections with ids how, categories, impact, diaspora, stories, tools; every text node carries a data-t key; honest placeholders for stats and testimonials; no links to non-existent pages.
- clients/website/souk.css - its own :root tokens (Souk palette, radii, type scale), the section layouts, and 900/560 breakpoints. Reuse the site.css ideas (gutter, measure, pill, chip, reduced-motion) by copying the pattern, not the rose colours. A shared base file is optional.
- clients/website/souk.js - the language switch (copy the site.js mechanism, or refactor site.js to take a per-page dictionary) plus an AR dictionary of about 110 keys. Remember-choice key: reuse 'youdrop-lang' so the choice carries across pages, or pick a Souk key; product decides.
- Self-hosted fonts in clients/website/fonts: Cormorant Garamond (variable or 500-700) and DM Sans (variable 400-600 plus italic 400), both SIL OFL, woff2 with OFL.txt. The site deliberately avoids third-party font hosts. Also an Arabic companion face.
- Assets in clients/website/img/souk: 4 hero photos, 4 category photos, 1 diaspora photo and 1 avatar, downloaded from the Figma asset URLs (they expire after 7 days), converted to WebP/JPG around 1600px or smaller, with width and height set and loading=lazy below the fold. The 2 testimonial portraits must NOT ship. Icons in clients/website/icons/souk: check, arrow-right, truck, credit-card, layout, gift, text-quote, exported as SVG. The existing check.svg and truck.svg are YouDrop-styled, so reuse them only if the glyphs match.
- nginx.conf: 'location = /souk { try_files /souk.html =404; }' and the same for '/souk/'. Without these the catch-all serves the YouDrop page.
- config.js: add window.DELIVERY_PORTAL_URL for 'Log In' so it follows the deployment (index.html and register.html hard-code portal-dev today).
- Optional mobile work if 'Diaspora Support' is to be real: wire DiasporaScreen from the customer shell and fix the custStartOrder ARB string.

**Missing in the backend**

- NONE required for an honest static page. Everything below exists only to make the design's claims true.
- product-service (optional, live counters): GET /api/public/stats returning {activeStores, deliveredOrders} as coarse cached counts. Add it to product-service delivery.security.permit-all by exact path, rate-limited, with no PII. Delivered-order counts live in order-manager, so either expose a public count there or have product-service read its delivered_order_lines. 'Villages represented' and 'Earned by local creators' have no data source; the earnings figure would come from accounting-service merchant legs.
- product-service: new Store.Vertical values (for example HOME_FOOD, CRAFTS) and a Flyway migration that extends the stores.vertical and categories.vertical check constraints (V11, V17), plus StoreVertical in delivery_core, verticalX ARB labels, and category art in infra/category-art.
- order-manager: a service or booking order kind for tutoring and freelance work. OrderKind today is CATALOG/BUTLER only. This is a new product line (XL), not landing-page work.
- A public, anonymous browse API (categories, stores by vertical) plus a customer web storefront for 'Shop Local Goods' and 'Explore category sellers'. There is none today (the portal is backoffice, merchant and carrier only). XL.
- Card acceptance and FX (USD/EUR/GBP), international shipping, a diaspora remittance portal, weekly bank payouts, gift cards: none exist. Settlement is cash on delivery plus points, and transfer-service connectors are simulated. Each is XL and has regulatory dependencies.

**Design-system pieces to reuse**

- No Yd* Flutter widgets and no tokens.dart. This is a static HTML/CSS/JS page with no build step, and the Souk palette and typefaces deliberately differ from DeliveryColors (brand #E11D48).
- site.js language-switch mechanism (data-t, AR map, DOM-read English, localStorage in try/catch, dir=rtl, aria-pressed sync).
- index.html honesty patterns: .soon chip, .cta-soon plus .tag 'Android APK', .quote.pending placeholder cards, inert social spans, and the HTML-comment record of designed but unsourced numbers.
- site.css layout ideas: --gutter clamp, --measure 1280, scroll-padding-top for the sticky header, the Arabic system font stack with letter-spacing reset, reduced-motion handling.
- nginx exact-match location pattern used for /register and /admin; deploy-website.sh unchanged.
- /register?kind=MERCHANT as the only seller sign-up path; /app as the only shopper path.

**Strings**

- Every visible string is English in the markup and Arabic in the souk.js dictionary (the website does not use delivery_l10n ARB files). Keys by section:
- nav: nav-how 'How it Works', nav-categories 'Explore Categories', nav-impact 'Our Impact', nav-diaspora 'Diaspora Support', nav-stories 'Success Stories', nav-login 'Log In', cta-seller 'Become a Seller'
- hero: hero-pill 'Lebanese Micro-Entrepreneurship Platform', hero-title, hero-lede, cta-launch 'Launch Your Store', cta-shop 'Shop Local Goods', tag-android 'Android APK', hero-f1 'No upfront fees', hero-f2 'Lebanon-wide logistics', hero-f3 (change 'Diaspora orders enabled' to something true, or drop it)
- stats: stat1 'Active Home Businesses', stat2 'Lebanese Villages Represented', stat3 'Earned by Local Creators', stat4 'Global Orders Delivered' (reword; there are no global orders), soon 'Coming soon'
- how: how-pill 'Grounded Empowerment', how-title, step1-title/body, step2-title/body, step3-title/body (rewrite 'Keep 92%' and 'weekly fresh USD' to match the 12.5% commission and the cash/points settlement)
- categories: cat-pill 'Explore Souks', cat-title, cat-all 'View All Marketplace Categories', cat1..cat4 title/tag/body, cat-explore 'Explore category sellers'
- tools: tools-pill, tools-title, tools-lede, tool1..tool3 title/body, visual-title 'Your Local Store, Elevated.', visual-sub, visual-live 'Store Live', visual-rev 'This Week's Revenue', visual-pending 'Pending Deliveries', visual-orders '12 Orders'
- diaspora: dia-pill, dia-title, dia-lede, dia1-title/body, dia2-title/body, cta-diaspora 'Explore Diaspora Portal'
- stories: stories-pill 'Proud Stories of Resilience', stories-title, quote-pending-name/role/body for 2 cards
- final: final-title, final-lede, cta-free-shop 'Start Your Free Shop', cta-marketplace 'Explore the Souk Marketplace'
- footer: footer-mission, footer-sellers, footer-marketplace, footer-diaspora, link labels that have destinations, footer-legal, lang label 'English (US)' / Arabic; the page title and meta description in both languages

**Tests that should prove it**

- Fix infra/smoke-test-website.js first. Its landing assertions ('Your city, delivered', .backdrop, ports 5010/5012/5013) already fail against the current index.html.
- Smoke: GET /souk and /souk/ return 200, include the Souk H1 text, and are NOT the index.html fallback (assert the YouDrop H1 is absent). souk.css, souk.js and every img/icon referenced in souk.html return 200.
- Smoke: every href on souk.html is either an in-page anchor whose id exists, /register?kind=MERCHANT, /app, or the configured portal. No link points at a page that does not exist.
- Smoke (honesty): the designed invented figures ('4,200+', '$1.8M+', '45k+', '92%') and the names 'Teta Mariam' and 'Rami Khoury' do not appear in the served HTML. The Backoffice address is absent, as the existing check asserts for index.html.
- Node check: every data-t key in souk.html has an entry in the souk.js AR map, and there are no orphan AR keys.
- Browser check (Browser pane, JS on and off): EN to AR toggle flips lang, dir and title and persists across reload; JS off shows the complete English page; screenshots at 1440, 900 and 375 are compared with scratchpad/figma/119-4_souk-landing-page.png; no horizontal scroll at 375; every image has alt or is decorative.
- Accessibility: one h1; section headings in order; pills are not headings; colour contrast checked for cream on olive, #5C6257 on #FAF7F2 and peach #E6A28A on #1A1E18 (likely borderline at 14px).
- Only if the optional public stats endpoint is built: a product-service WebMvc test that anonymous GET /api/public/stats returns 200 with counts only, that neighbouring paths are still 401 without a token, and a gateway scenario with no Authorization header through api-dev and platform-cors from the www.youdrop.shop origin.

**Questions**

- Is 'Souk' a rebrand of YouDrop, a sub-brand or vertical of it, or a separate product? This decides /souk versus replacing index.html (and register.html, the portal and the app), the domain, and the copyright entity ('Souk Lebanon Technologies Ltd.' versus 'YouDrop Logistics Technologies').
- Do the Tutoring and Creative Services categories stay? The platform cannot sell a service: there is no vertical and no OrderKind for it.
- Seller economics copy: the design says 'keep 92%', 'weekly payments in fresh USD or bank transfer' and 'get paid instantly'. The backend charges 12.5% commission, settles at delivery with cash on delivery, and pays merchants in points. Which is the truth to print?
- Diaspora: are foreign-card payments, international shipping and remittance to freelancers actually planned? Remittance likely needs a licence. Until then, should the section carry a 'Coming soon' chip or be cut?
- Where should 'Shop Local Goods' and 'Explore the Souk Marketplace' go when there is no customer web storefront? /app (Android only, no iOS) is the only working target.
- Photo provenance and licences for the 10 raster images. Are the hero and category photos real Lebanese sellers, stock, or generated? The testimonial portraits look generated and are excluded under the site's existing rule.
- Are real counters wanted (a backend endpoint), or static figures signed off by someone who can source them?
- Arabic typography: which Arabic display face pairs with Cormorant Garamond?
- Should seller sign-up at /register be re-skinned for Souk, or should Souk sellers land on the YouDrop-branded wizard?

**Build order for this cluster**

- 0. Get product answers on brand scope (extend at /souk or replace), the seller-economics copy, the diaspora and services claims, and photo licences. Nothing below should print a claim the backend contradicts.
- 1. Repair infra/smoke-test-website.js so it passes against today's index.html. This gives a green baseline before a second page is added.
- 2. Add the nginx exact-match locations for /souk and /souk/ plus an empty souk.html skeleton, and extend the smoke test to prove /souk is not the index fallback. Deploy with infra/deploy-website.sh.
- 3. Self-host Cormorant Garamond and DM Sans (plus an Arabic face) and write the souk.css tokens and primitives: pill, primary, outline and olive buttons, card, section band, chip.
- 4. Build the sections in order: header, hero, how-it-works, categories, tools, diaspora, final CTA, footer. Use the corrected copy, static data and the /register and /app targets. Stats and testimonials use the honest placeholder pattern from index.html.
- 5. Export and optimise the Figma photos and icons into img/souk and icons/souk (the asset URLs expire in 7 days, so do this early), and exclude the testimonial portraits.
- 6. Write souk.js: the EN/AR dictionary and toggle (shared localStorage key), plus DELIVERY_PORTAL_URL in config.js for Log In.
- 7. Responsive pass at 900 and 560, RTL pass, reduced-motion and contrast checks, then Browser-pane screenshots against the Figma PNG and the full smoke test.
- 8. Only if product commits: the public stats endpoint (product-service permit-all plus tests), then separately scoped epics for new verticals, service orders, a web storefront, card/FX payments and the diaspora portal. Each is XL and outside this frame.

**Cross-cutting**

- Honesty rule already in the codebase: index.html refuses invented counters, invented testimonials with generated portraits, and links to pages that do not exist. This design contains all three (4 stats, 2 testimonials, and about 12 footer links with no destination) and must follow the same rule.
- Brand divergence: site.css and tokens.dart share the YouDrop rose palette and Rubik so that a site visitor recognises the portal 30 seconds later. Souk breaks that continuity (terracotta and olive, serif display). If Souk is only a campaign page, sellers who click through land on the YouDrop-branded /register and portal.
- Several design claims contradict backend rules: 92% kept versus 12.5% commission; weekly USD bank payouts versus cash on delivery plus points; international shipping and diaspora hubs versus Lebanon-only named DeliveryZones; card payments in USD/EUR/GBP versus no card processor; tutoring and freelance services versus Store.Vertical and OrderKind; 'Diaspora orders enabled' versus an unreachable DiasporaScreen; preparation or crafting times versus no such field.
- No public API exists for anything the page could show live. product-service opens no anonymous paths, and /api/orders/stats is BACKOFFICE-only. Keep the page network-free, as index.html is, unless an endpoint is deliberately opened.
- The design is desktop-only (1440) and English-only. Mobile layouts and Arabic RTL (including an Arabic typeface, since Cormorant and DM Sans lack Arabic) must be designed by the implementer or requested from design.
- Stale test: infra/smoke-test-website.js already fails against the current landing page, so website regressions are not being caught today.

## Older frames that no code cites

Audited against the code to see whether they are built without citing their id.

| Frame | Name | Status | Evidence |
|---|---|---|---|
| `38:12` | wassel-feed | missing | Nothing in clients/, services/ or the ARB files mentions Wassel, community carry, a traveller feed or a posted route (word-boundary grep for wassel/tol3a/community carry returns nothing). The frame's bottom nav (Home/Wassel/Tol3a/Amen/Account) contradicts the shipped customer bar Home/Butler/Basket/Orders/Account in clients/apps/mobile_app/lib/src/customer_nav_bar.dart (tabCount 5, fixed indices). No peer-carrier, route or price-range entity exists in order-manager. The closest capability is the Butler 'Send Anything' errand (clients/apps/mobile_app/lib/src/butler_screen.dart), which a platform rider carries, not a traveller. |
| `38:119` | wassel-post-delivery | missing | There is no 'Request Community Carry' form: no pickup/dropoff city pickers, package-size chips (Envelope/Small/Medium/Large), customer-offered price or 'suggested community range'. The nearest thing is ButlerScreen SEND mode (clients/apps/mobile_app/lib/src/butler_screen.dart: what/pickup/receiver fields). Its fee is fixed by the server (ButlerTerms), never offered by the customer, and there is no backend for matching travellers. |
| `38:190` | tolaa-group-order | missing | There is no 'Create Group Cart', no 'Join Active Orders Nearby' discovery, and no delivery fee that falls per person as people join. What exists is a host-led payment split: the Split Order toggle in clients/apps/mobile_app/lib/src/cart_screen.dart, backed by services/transfer-service/.../domain/SplitPlan.java (EVEN/ITEMIZED, 15-minute window). That shares one person's basket cost among invited friends; it does not let strangers or neighbours join an open order. |
| `38:254` | tolaa-shared-cart | partly | The per-person breakdown partly exists. In CartScreen's split mode (cart_screen.dart, Figma 83:*) the host assigns each line to a participant ('Assigned: {name}', custItemsCountLine), and SplitStatusScreen (split_status_screen.dart) shows each share, Remind and Cover the Rest; SplitPlan in transfer-service backs it. Missing: members adding their own items (only the host's basket exists), a discounted 'Shared Delivery Fee' ($2.40 struck through to $0.80), a named group cart ('Office Lunch'), the group chat button, and 'Place Group Order' from a collaborative cart. |
| `38:328` | butler-voice-order | missing | ButlerScreen is free text only: no mic, record, audio or speech code in clients/apps/mobile_app/lib/src/butler_screen.dart. The order-manager ButlerRequest domain (ButlerRequest/ButlerMode/ButlerStatus.java) has no audio attachment or transcription field. The Arabic/English/French chips conflict with the app, which only supports EN/AR. 'Recent Voice Commands' corresponds loosely to ButlerRequestsList 'Recent tasks', which is text errands. |
| `38:393` | amen-request | missing | Nothing for secure delivery of valuables exists: no declared value, valuables category, insurance tier or tamper-code concept anywhere. Grep for insured/insurance/valuables finds only the carrier FLEET_INSURANCE document kind in services/onboarding-service/.../DocumentKind.java. There is no order type or surcharge for it in order-manager; DeliveryTier is STANDARD/EXPRESS only. |
| `38:461` | amen-tracking | missing | There is no 'Tamper Seal Intact / Code' banner, 'Verified Background' or 'Elite Rider' badge, transit checkpoints, or Report Issue. The generic live tracking in clients/apps/mobile_app/lib/src/order_tracking_panel.dart (OSM map, progress steps, rider chat) would be the base. It deliberately has no Call button, and the wire carries a rider ref, not a phone number. |
| `38:519` | sahra-night-mode | missing | The app has no dark theme: no ThemeMode or darkTheme anywhere, and main.dart forces dark status-bar icons. There is no 10PM-4AM night window, night surcharge or rider night bonus (order-manager DeliveryTier is STANDARD/EXPRESS; no night pricing rule). There is no 'Night Owls' marketplace or late-night category (Late Night/Munchies/Pharmacy 24/7/Hookah), and no 'open now' filter strings in app_en.arb. |
| `38:589` | rider-fuel-rewards | missing | It exists only as marketing copy: riderPerk3Title 'Rider Fuel Rewards' / riderPerk3Body in clients/packages/delivery_l10n/lib/l10n/app_en.arb:1567-1568, shown on the rider partner intro. There is no fuel balance, weekly stipend, delivery missions, voucher redemption or partner-station screen, and no rider-rewards backend. The rider shell has only Earnings/Statement (rider_earnings_screen.dart, rider_statement_screen.dart). The points system (RewardsScreen, pointsApi) is customer-only. |
| `40:4472` | rider-onboard-personal | implemented | This is step 1 of the rider wizard in clients/apps/mobile_app/lib/src/partner_application_screen.dart (_riderPersonal ~l.1497; title t.authPersonalInformation). It has full name, email, phone, date of birth and national ID (t.authFullName, authEmailAddress, authPhoneNumber, authDateOfBirth, authNationalId). It implements the older 22:* frames (the code cites 22:336/22:503), so this 40:* version differs: 'STEP 1 OF 5' against the code's 4 steps, a Nationality dropdown the code lacks (no ARB key), and no National ID field in the design. |
| `40:4539` | rider-onboard-vehicle | partly | _riderVehicle in partner_application_screen.dart has a vehicle-type grid (enum _Vehicle: MOTORCYCLE, CAR, BICYCLE, VAN; Figma 22:503), make/model (authVehicleModel), plate (authPlateNumber) and year (authVehicleYear). Against the frame: 'On Foot' is missing (the code has Van instead), and the required 'Vehicle Photo' upload ('Take or Upload Photo') does not exist. Onboarding DocumentKind has no vehicle-photo kind. |
| `40:4614` | rider-onboard-documents | implemented | _documentsStep (partner_application_screen.dart ~l.2034) plus clients/apps/mobile_app/lib/src/application_documents_step.dart (Figma 86:241) provide per-document upload rows with progress and done states. The server-side rider set matches the frame's three rows exactly: services/onboarding-service/.../domain/DocumentKind.java RIDER_DOCUMENTS = NATIONAL_ID, DRIVING_LICENCE, VEHICLE_REGISTRATION (ARB docNationalId/docDrivingLicence/docVehicleRegistration). Only the step number differs (3 of 4 against 3 of 5). |
| `40:4684` | rider-onboard-zones | partly | _riderZone (partner_application_screen.dart l.1638+) has a map with a pin the applicant places (OSM, Figma 22:624), a preferred-area text field and a 'who will you ride for' company picker. The frame's multi-select zone checklist with 'orders/day' badges is deliberately empty (YdEmptyState authZonesNoneToPickTitle), for two documented reasons. First, GET /api/delivery-zones requires a signed-in user, which an applicant is not. Second, no rider record carries zones. There is also no per-zone order-volume data. |
| `40:4751` | rider-onboard-bank | partly | The rider wizard has no bank step: only the merchant and carrier flows run PayoutDetailsStep (partner_application_screen.dart:361-365), and the rider's step 4 is zones. Account holder and IBAN can be entered later on PendingApplicationScreen through payout_details_step.dart while the application is undecided. After approval RiderPayoutSheet is read-only (canEdit hard-coded false; surface-checklist: UNREACHABLE). Missing from the frame: Bank Transfer vs Cash Payout choice, a Bank Name dropdown and a 'WhatsApp for Notifications' number. |
| `40:4822` | rider-onboard-submitted | implemented | This is the rider flavour of PendingApplicationScreen (clients/apps/mobile_app/lib/src/pending_application_screen.dart, 'rider-pending-approval' 22:651): a confirmation, a 'what to expect next' timeline and a white button back out. Strings: authApplicationSubmitted, authApplicationUnderReview, authWhatToExpectNext, authExpectVerification, authExpectBackgroundCheck, authExpectTrainingInvite. The frame's copy differs (steps 'WhatsApp Invitation' and 'Collect Kit & Start', 'Under Review (24-48 hours)', 'Return to Home'), and the code shows live document and bank state from the application. |
| `58:12` | customer-home | partly | StoreHomeScreen (clients/apps/mobile_app/lib/src/store_home_screen.dart, cites Figma 3:12) has the greeting and address header, search, category tiles (CategoryStrip), a favourites rail, promo banners and the shop grid under t.custActiveStoresNearby. Missing: the two feature-entry cards (112:1658). 'Send a Gift to Lebanon' should open DiasporaScreen (diaspora_screen.dart, 80:133) and 'Neighborhood Shops' should open HyperlocalScreen (hyperlocal_screen.dart). Both screens exist but have zero call sites (surface-checklist: UNREACHABLE), and the home screen draws no such cards. |
| `58:309` | customer-product | implemented | ProductDetailScreen (clients/apps/mobile_app/lib/src/product_detail_screen.dart) has the title, description, USD price with '/ LBP' from MarketRates (l.369-414), a USD currency chip, option groups (e.g. size, _toggle), a quantity stepper and Add to Basket. The 'DUAL PRICE MODE' toggle pill is not a real toggle: the USD chip only names the settlement currency. The code cites the older frames 3:65/3:98. |
| `58:371` | customer-basket | implemented | CartScreen, the Basket tab (clients/apps/mobile_app/lib/src/cart_screen.dart, cites 3:389), has lines with options, USD+LBP prices and a stepper, a promo code field with Apply (PromoApi quote), and a summary (Subtotal, Delivery, Discounts, Total with LBP) above 'Proceed to Checkout'. The frame's 'Service Fee' line has no counterpart; there is no service-fee concept in order-manager. The code adds a Solo/Split toggle and a minimum-order gate. |
| `58:461` | customer-tracking | implemented | OrderTrackingPanel (clients/apps/mobile_app/lib/src/order_tracking_panel.dart), embedded in OrderDetailsScreen for any in-flight order, has a live OSM map with the rider marker (STOMP plus polling), progress steps custTrackConfirmed/Preparing/OnTheWay/Delivered, ETA, and 'Message the rider' opening CustomerChatScreen. Differences: it is not a standalone 'Tracking Order #' route, there is deliberately no Call button, and there is no rider vehicle or rating line. |
| `58:525` | customer-orders | implemented | MyOrdersScreen, the Orders tab (clients/apps/mobile_app/lib/src/my_orders_screen.dart), has 'Your Orders' (custYourOrders) with Active Orders ({n}) and Past Orders tabs. Cards show store, time stamp, a status pill, item count and total with LBP, plus Reorder and Cancel, refreshed by a 5-second poll. All elements in the frame are present. |
| `58:604` | customer-butler | partly | ButlerScreen, the Butler tab (clients/apps/mobile_app/lib/src/butler_screen.dart, cites 20:4), plus butler_requests_list.dart have the banner (custButlerBanner 'We buy or deliver anything!'), Buy/Send modes, a 'What do you need?' text area, the fee from the server (errandFeeBuy) and 'Request a Butler'. Missing: 'Upload photo / bill' (no photo or attachment in the client or the order-manager ButlerRequest), and the fare as a range with LBP. The frame's photo of the store bill implies a receipt-photo flow that doesn't exist. |
| `58:657` | customer-account | implemented | RewardsScreen, the Account tab (clients/apps/mobile_app/lib/src/rewards_screen.dart), has 'Rewards & Points', total points, '+{n} pts this month', next-tier progress, a current-tier card, reward categories (Free Delivery vouchers, Cashback, Referral Bonus) and recent activity. Free Delivery vouchers and Referral Bonus are hard-coded 0 / $0.00 because no voucher or referral engine exists, and there is no 'See all'. The old AccountScreen is dead code. |
| `80:8` | checkout-payment | implemented | CheckoutScreen (clients/apps/mobile_app/lib/src/checkout_screen.dart; it cites 3:471 but draws this content) has the locked-rate banner (custPlatformRate/custRateLocked), a Lebanese Split Payment card (custPayInUsd/custPayInLbp, % USD/LBP bar), the rider-change note (custRiderChange), Local Payment Methods (Cash USD/LBP, Whish, OMT via transferApi.methods()) and 'Place Order ({amount})'. Deltas: no itemised order-summary card with 'Fresh' suffixes, and the code adds address, delivery speed and notes. |
| `80:240` | shop-power-status | partly | The power chip is live. StorePowerChip (clients/apps/mobile_app/lib/src/store_power_chip.dart, cites `shop-power-status`; mains/generator/dark) appears on StorePageScreen and ShopsListingScreen, and merchants set it in StoreScreen (delivery_merchant/lib/src/store_screen.dart:416) through POST /api/stores/{id}/power. The full list screen with district chips is HyperlocalScreen (hyperlocal_screen.dart, cites both this frame and neighborhood-browse), which has zero call sites (UNREACHABLE). Missing: 'Notify Me' on dark shops, per-shop status blurbs, and 'auto-updated' grid checks (status is merchant-declared). |
| `80:355` | medicine-finder | missing | There is no medicine-finder screen and no prescription upload. Nothing shows per-pharmacy stock, distance or availability ('In Stock / 2 Packs Left / Out of Stock'), and there is no arabizi drug search. Backend pieces that exist: GET /api/products?search= (services/product-service/.../api/ProductController.java:79-82) and the Pharmacy vertical (verticalPharmacy). Butler free-text errands cover the 'can't find' fallback. |
| `80:461` | neighborhood-browse | partly | HyperlocalScreen (clients/apps/mobile_app/lib/src/hyperlocal_screen.dart) implements district chips from StoreApi.neighborhoods() (GET /api/stores/neighborhoods, StoreController.java:149), dekkane rows with VerifiedLocalBadge and the power chip, and an arabizi search hint. It has zero call sites (surface-checklist: UNREACHABLE, dead code with a live backend). Missing: district 'vibe' cards with images ('Artsy & Lively') and the 'Trending in {district}' product rail. |
| `83:457` | split-setup | partly | This lives inline in CartScreen's split mode (clients/apps/mobile_app/lib/src/cart_screen.dart; l.551 cites `split-setup` by name), not as a separate 'Split with Group' screen. It has even split with host-absorbs-remainder (custEvenBreakdown, custHostAbsorbs), an add-friend-by-username sheet (split_add_friend_sheet.dart, 83:161) and 'Send Payment Requests'. It is backed by SplitPlan (transfer-service), whose 15-minute window matches the frame. Missing or different: a 'How many people?' stepper (the count comes from the friends added), an 'Each pays' USD/LBP line, and 'Send Invites via WhatsApp'; invites go through the in-app/notification path. |
| `87:9` | carrier-dashboard | implemented | This is the CarrierShell Dashboard tab (clients/apps/mobile_app/lib/src/carrier_shell.dart, header 'Figma 87:*'). It has four stat tiles (carrActiveDeliveries LIVE, carrPendingOrders WAITING, carrRidersOnline FLEET, carrTodayRevenue USD), Recent activity, and the Dashboard/Orders/Fleet/Earnings/Settings nav. Deltas: 'Live Fleet Map' is replaced by a Coverage Zones card opening CarrierZonesScreen, because rider pins are deliberately not drawn. Activity rows are order cards rather than rider events, since the wire carries rider refs, not names. |
| `87:553` | carrier-settings | partly | The CarrierShell Settings tab (carrier_shell.dart; surface-checklist 'CarrierShell · Settings tab') has the company card, Coverage Zones, Pause/Resume company, a static payment-terms card, the EN/AR language toggle and Log Out. Missing on mobile: operating hours, delivery capabilities, vehicle management, rider onboarding link, auto-assign toggle (no such backend concept), payout method, view invoices, notifications and help rows. The portal CarrierSettingsScreen (delivery_portal/lib/src/carrier/settings_screen.dart) has hours, regions and payout, but its profileApi and keysApi are not wired (UNREACHABLE). |
| `88:4` | coverage-map | missing | This is a 1440px public-website section: 'Coverage Areas / Where We Deliver', a 1280x600 map, and stats (6 Cities, 8,500+ Merchants, 120+ Carrier Partners, Growing Weekly). clients/website/index.html has no such section. surface-checklist notes the FAQ5 answer refers to a 'map widget' that does not exist on the page. Carrier CoverageZone data exists (order-manager CoverageZone.java, Figma 88:107 in carrier_zones_screen.dart), but there is no anonymous public endpoint for a website map. |
| `94:715` | merchant-pos-terminal (mobile) | partly | PosTerminalScreen (clients/packages/delivery_merchant/lib/src/pos/pos_terminal_screen.dart, cites 94:4345/94:5092) is the MerchantShell POS tab. It has category chips, a product grid, a scan path (the search field doubles as a barcode wedge, Icons.qr_code_scanner), a basket bar with USD+LBP and Charge. The client is complete, but pos-service does not exist anywhere in the repo: services/ has no pos-service, no /api/pos controller and no deploy manifest. Every write fails (surface-checklist: UNREACHABLE). There is no camera barcode FAB (spec open decision d). |
| `94:788` | merchant-pos-checkout (mobile) | partly | PosCheckoutScreen (pos/pos_checkout_screen.dart, cites 94:4462) opens as a 92%-height sheet on phone. It has the order items, a tax line, tenders (PosTenderMethod cashUsd/cashLbp/card/wallet in delivery_core pos_models.dart, plus split), cash received and a change preview with LBP, and Complete. Missing: the 'Print Receipt on Complete' toggle, and PosReceiptScreen is never navigated to. There is no pos-service backend, so Complete fails. |
| `94:929` | merchant-sales-report | missing | No screen exists (surface-checklist 'Reports — NO SCREEN EXISTS'). ReportsApi (clients/packages/delivery_core/lib/src/api/reports_api.dart) is passed into MerchantShell but never read, and there is no reporting service in services/. The nearest analytics are MerchantAnalyticsScreen (14-day series) and the dashboard's fortnight chart. The frame's hourly chart, Walk-in vs YouDrop channel split and Cash/Card/Whish breakdown have no data source. |
| `94:1108` | merchant-settings | partly | MerchantSettingsScreen (delivery_merchant/lib/src/merchant_settings_screen.dart, cites 3:2194) is the Settings tab hub (profile band, language, rows, log out). 'Store Acceptance (Open)' corresponds to the publish/busy controls in StoreScreen and the dashboard. 'Backup Generator Active' corresponds to StoreScreen's power-status picker (store_screen.dart:416). Missing: POS Tax Rate (11% TVA), since no VAT exists anywhere (spec open decision a); 'Print Receipts automatically'; an 'Accept YouDrop Orders' toggle; and 'Avg Delivery Prep Time'. |
| `94:1215` | merchant-pos-terminal (web) | partly | The same PosTerminalScreen, in its wide layout at 1000dp and above, is mounted as the portal merchant rail entry 'POS' (clients/apps/delivery_portal/lib/src/portal_shell.dart, onCheckout opens PosCheckoutScreen.show). It has the search/scan field, category tabs, a grid with LBP, a basket with steppers and Charge. Missing: Add Customer, Add Discount, Add Note, the cashier and register header (onOpenShift is reserved, shifts not wired) and the Whish tender. The portal rail also lacks the frame's Reports and Settings entries. pos-service is absent. |
| `94:1387` | merchant-pos-checkout (web) | partly | PosCheckoutScreen shows as a 420x720 dialog on the portal. It has the total with LBP, the locked rate, tenders cash/card/wallet/split, and a change preview in integer cents with LBP rounding. Missing: quick-cash buttons ($10/$15/$20/$50/Exact), a 'Whish / OMT' tab (not in PosTenderMethod), and receipt options Print/WhatsApp/Email (the spec says ship them disabled until a notifications consumer exists). The pos-service backend is absent. |
| `94:1452` | merchant-orders-web | partly | OrdersScreen (delivery_merchant/lib/src/orders_screen.dart, cites 3:1822 'Order Flow') is the portal rail entry 'Orders'. It has status buckets and accept/reject/mark-ready via OrderApi.act, and MerchantOrderDetailScreen is pushed on tap. Missing: the YouDrop Orders / Walk-in Sales toggle (no walk-in or posApi code in orders_screen.dart; POS is absent), kanban columns with counts, the right-hand detail panel with customer and rider, Status/Date filters and the 'Synced' indicator. |
| `94:1775` | merchant-staff | implemented | StaffScreen (delivery_merchant/lib/src/staff_screen.dart, cites 94:4770/94:5948) is on the portal rail entry 'Staff' and in the mobile Settings under Staff. Its backend is live: product-service StoreStaffController and StaffMembershipController with migrations V27__store_staff.sql and V28__revoke_staff_invites.sql. It has an owner card, a role-defaults permission band (StorePermission), a presence poll, and invite by code instead of 'Add Employee' accounts. Clock-in times and 'Sales Today' read t.staffNoPosSalesYet because POS is absent. |
| `94:1911` | merchant-settings-web | partly | The portal merchant rail has no Settings entry. portal_shell.dart's merchant area lists Dashboard, Products, Orders, WhatsApp, Delivery, Delivery areas, My Shop, Inventory, POS, Categories and Staff. Store profile name, phone and address are editable in StoreScreen ('My Shop'). Missing: an Auto-Accept Delivery Orders toggle (no autoAccept anywhere in clients or services), a Dual-Currency Display toggle, and a POS receipt template preview (only a receiptFooter field in delivery_core pos_api.dart/pos_models.dart, whose backend is absent). |
| `94:2246` | web-merchant-dashboard | partly | MerchantDashboardScreen (delivery_merchant/lib/src/dashboard_screen.dart, cites 3:1742) is portal rail item 1. It has pending/incoming orders with actions, today's figures, the fortnight chart and best sellers. Missing: the Items Sold and Low Stock stat cards, Walk-In Sales Analytics, the 'POS Mode Active / Launch POS Terminal' banner, and Quick Actions (Add New Product, Record Quick Sale, Initiate Stock Audit). None of the onSwitchToPos/onNewSale/onStockCount/ReportsApi hooks planned in MERCHANT_SUITE_SPEC exist in dashboard_screen.dart. |
| `94:2395` | web-merchant-inventory | partly | InventoryScreen (delivery_merchant/lib/src/inventory_screen.dart, cites 94:106/94:3166) is the portal rail entry 'Inventory'. It has server-side filters, stock quantity and status, and 'Not tracked' handling. inventory-service does not exist in the repo (no /api/inventory controller), so it loads into its error state. The portal passes no onOpenAlerts or onOpenItem (portal_shell.dart), so alerts and per-item adjustment are unreachable there. '+ Add Product' lives on the Products page (ProductListScreen) instead. |
| `94:2527` | web-merchant-add-product | partly | ProductFormScreen (delivery_merchant/lib/src/product_form_screen.dart, cites 3:1964) opens from the portal Products page FAB or a row (product_list_screen.dart:99-102). It has the image dropzone, gallery, title, price, category and variants/options. Missing: the SKU Code field (the backend already has Product.sku/barcode, product-service migration V25__sku_barcode_in_stock.sql, but the form has no sku or barcode input), Cost of Production, and the Basic Info / Pricing model / Inventory triggers tabs. Low-stock thresholds and initial stock need the absent inventory-service. |
| `94:2634` | web-merchant-stock-alerts | partly | StockAlertsScreen (delivery_merchant/lib/src/stock_alerts_screen.dart, cites 94:272/94:3530) groups OUT/CRITICAL/LOW with Restock, which records a RECEIVED adjustment. Only MerchantShell constructs it (clients/apps/mobile_app/lib/src/merchant_shell.dart:306); the portal never does. Missing: the master-detail console with sales velocity and time to depletion, 'One-Click Reorder', and supplier replenishment automation (no supplier or purchase-order model; spec decision e). The inventory backend is absent. |
| `94:2726` | web-merchant-categories | partly | MerchantCategoriesScreen (delivery_merchant/lib/src/merchant_categories_screen.dart, cites 94:351/94:3710) is the portal rail entry 'Categories', with a live backend: product-service StoreCategoryController (/api/stores/{storeId}/categories GET/POST/PUT/PUT order/DELETE) and V26__store_categories.sql. It supports add, rename and drag-to-reorder of sections. Missing: the per-section product-card grid with 'Drag cards to change display order'; products have no position within a section. |
| `94:2807` | web-merchant-stock-count | partly | StockCountScreen (delivery_merchant/lib/src/stock_count_screen.dart, cites 94:425/94:3856) has a setup face and a session face: system quantity against counted, a variance per row, N of M counted, and submit or cancel. Only MerchantShell opens it (merchant_shell.dart:316, Settings > Stock count); the portal rail has no route to it. inventory-service does not exist, so Start fails. The 'Enable USB Scanner' control is missing. |
