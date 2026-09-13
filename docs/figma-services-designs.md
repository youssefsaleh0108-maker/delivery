# The services marketplace designs, mapped to the code

Figma file `4lIJm9HXkQtTQHqhBIpNfB` ("YouDrop"), page 0:1. The frames below have the node-id prefix 126, and nothing in the code cited them when this was written. Each was read with Figma's design context and mapped against the real code on `main` (monorepo `21ba6de`, order-manager `b4e28ec`) and against the feature worktrees in flight on 2026-09-12. The file paths, endpoints and gaps below are checked, not guessed. Sizes are honest estimates. **Questions** are product decisions the code cannot make; each has the default the build will use unless the owner overrides it.

**8 frames in 1 cluster.** Every one of them draws (or implies) the six-destination customer bar: Home, Butler, Basket, Services, Orders, Account.

| Frame | Name | Size | Audience |
|---|---|---|---|
| `126:11` | service-provider-signup | M | Service provider (merchant shell / portal) |
| `126:51` | service-provider-dashboard | L | Service provider (merchant shell / portal) |
| `126:133` | service-add-offer | L | Service provider (merchant shell / portal) |
| `126:200` | service-provider-orders | XL | Service provider (merchant shell / portal) |
| `126:285` | customer-services-browse | L | Customer (mobile_app) |
| `126:371` | customer-service-provider-page | M | Customer (mobile_app) |
| `126:437` | customer-service-order | XL | Customer (mobile_app) |
| `126:507` | customer-service-tracking | L | Customer (mobile_app) |

## Decision in brief

Build the services marketplace inside the services that already own its pieces, with no new microservice, no new realm role and no new ingress prefix.

- product-service: a service provider is a MERCHANT that owns a Store with the new vertical SERVICES and a service category. Each offer is a Product plus a one-to-one service_terms row (pricing type, unit, turnaround, fulfilment modes, file policy), reusing images, option groups and server pricing.
- order-manager: a service order is an Order of kind SERVICE with a fulfilment of DELIVERY or PICKUP. It runs on the existing status machine, with labels chosen by kind and two narrow additions: accepting moves straight into production, and a merchant 'collected' step takes a pickup order from READY to DELIVERED.
- onboarding-service: providers apply as MERCHANT with businessType SERVICES in the details map.
- accounting-service: settles service orders on order.delivered like any shop order. It learns that a merchant can hold pickup cash.
- notifications-manager: gains service wording.
- app-notification: reuses shop chat once that ships.

The rejected alternative is a dedicated services microservice. The single k3s node is already booked past its RAM on memory limits; a new service adds two JVMs and about a dozen deploy edits; and nothing downstream (settlement, reviews, notifications, dispatch) would see its orders. Details are in [Architecture](#architecture-where-the-marketplace-lives).

## Decisions in force

This is slice 0, the decision gate. The owner has not yet answered the [questions](#questions-only-the-owner-can-answer), so the build runs on the defaults below. Each one is kept easy to change. When the owner answers, replace the matching line here before building the slice that depends on it. Where this section and the rest of the document disagree, this section wins.

### Owner defaults

1. **Launch categories:** Printing, Tailoring & alterations, Repairs and Photography prints. Cleaning, Beauty and Tutoring exist in the taxonomy but are disabled by server configuration (`delivery.product.services.enabled-categories`), because appointments at the customer's place are not modelled. A disabled category is never offered to providers and never shown to customers.
2. **Items for a tailor or repairer:** the customer drops them off. There is no courier leg to the provider.
3. **Payment:** cash only, to the provider at pickup or to the rider on delivery. No deposit. The provider may decline.
4. **Commission:** the same 12.5% as goods.
5. **Signup:** MERCHANT with businessType SERVICES, sharing merchant auto-approval and documents.
6. **Where providers work:** MerchantShell "services mode" with a role switch, not inside the customer Account tab as drawn.
7. **Accept:** moves straight to In production. Estimated completion = accept time + the offer's maximum turnaround.
8. **Decline:** a picklist of reasons, stored as cancel reason "PROVIDER_DECLINED: …" and shown to the customer.
9. **Quantity:** packs of the offer's unit size, 1–99 packs.
10. **Pricing:** USD only, with a read-only LBP preview at the platform rate (MarketRates, rounded to 1,000). Pricing types FIXED, PER_UNIT and FROM.
11. **Customer files:**
    - PDF, JPEG or PNG; up to 10 MB each and 3 files per order.
    - Visible to the provider from placement.
    - Deleted 90 days after completion.
12. **Pickup:** free, with no verification code. The provider may cancel an uncollected READY order after 72 hours.
13. **Delivery:**
    - Zone fee as for shops, STANDARD tier only, and promo codes are allowed.
    - Never in the multi-shop basket, never queued offline, never giftable.
14. **Navigation:** six customer tabs as drawn (Home, Butler, Basket, Services, Orders, Account). Butler's glyph becomes a truck. Service shops never appear on Home.
15. **Order numbers:** the existing 8-character shortId.
16. **"This Week" and "Popular":** "This Week" = orders placed in the last 7 days. "Popular" appears only when delivered-order counts back it; otherwise the rail reads "Services near you".
17. **Verified badge:** the existing back-office Verified Local flag.
18. **Chat with the provider:** hidden until shop chat is merged. The chat branch is final and merges soon; slice 12 wires it.
19. **Refunds and disputes:** none in v1. Back office can cancel before completion.
20. **Ordering while the provider is closed:** refused, as for shops.

### Migration numbers

Parallel builds took some of the numbers printed further down, so these supersede them:

| Service | Services migrations | Why it differs from the plan below |
|---|---|---|
| product-service | V33 services vertical, V34 service terms, V35 product paused, V36 offer moderation | Unchanged |
| order-manager | **V36** service orders, **V37** order attachments (the plan prints V35 and V36) | V33 multi-shop checkout, V34 demand density and V35 carrier release audit are taken |
| accounting-service | V52 merchant cash holder | Unchanged; V49_1 gift wrap leg, V50 carrier cash custody and V51 payroll sit below it |
| notifications-manager | V19 service templates | Unchanged |
| app-notification | **V26 or later**, only if an order link is wanted (the plan prints V24) | Shop and neighbourhood chat use V22–V25 |
| onboarding-service | V46, only if the owner chooses a new Kind (default: no) | Unchanged |

New strings use the key prefix `svc` and are appended at the end of both ARB files.

## Services marketplace: provider signup, dashboard, offers and orders; customer browse, provider page, order and tracking (Figma 126:*)

### `126:11` service-provider-signup — M

*Who:* A would-be service provider (print shop, tailor, repair shop) in the mobile app. No bottom nav and no back button are drawn, so the frame reads as a standalone signup step; implemented as a pushed route it needs a back button.

*What:* A one-screen application to sell services: business name, service category, phone, location/area and 'Create Service Account', under a 'Lebanese Merchant Services' banner. Today the only seller path is the four-step merchant wizard (PartnerApplicationScreen: business type RESTAURANT/GROCERY/PHARMACY/BAKERY/RETAIL/OTHER, National ID + commercial registration, IBAN), and a signed-in customer has no in-app way to apply at all.

*Reached from:* Entry: ProfileDrawer 'Offer your services', or PartnerChoiceScreen / Google role question 'Services', pushes ServiceProviderSignupScreen (open path adds email, code and passcode). Submit leads to the application status: MERCHANT + APPLICANT sends homeFor to MerchantShell with the pending banner (merchant_shell pendingApproval); APPLICANT alone goes to PendingApplicationScreen. After approval: MerchantShell in services mode (126:51). The frame draws neither a nav bar nor a back button; as a pushed route it gets YdBackButton.

**Every element, and where its data comes from**

- Status bar mock (9:41, signal, wifi, battery) and home indicator: OS chrome, not implemented.
- Title 'Grow Your Business on YouDrop' (Rubik Bold 24/30, #0f172a ink) and subtitle 'Reach thousands of customers in your neighborhood.' (Regular 14/20, #475569 muted). Static copy. 'Thousands' is a number nothing on the platform backs; soften it (see strings).
- Banner (brandSoft #fff1f2, radius 16, padding 16): 'Lebanese Merchant Services' (14 bold, brand #e11d48), body 'Tailoring, printing, repairs, photography, and more delivered same-day to neighborhood doors.' (11/16 muted), and a 64px illustration (radius 12). The illustration is a Figma image asset: download it before the MCP URL expires (about 7 days). 'Same-day' is a promise the data cannot keep, because turnaround is per offer ('1-2 Days' on 126:133); reword it.
- BUSINESS NAME label (11 SemiBold ink, uppercase) and text field (white, 1px #e2e8f0 border, radius 8, padding 12, placeholder 'e.g. Al Fakhry Press' in #94a3b8). Data: OnboardingApplication.businessName (varchar 200, NOT NULL). Required, 200 characters at most.
- SERVICE CATEGORY select showing 'Printing' with a 16px chevron. Data: nothing today. Add a ServiceCategory enum (PRINTING, TAILORING, PHOTOGRAPHY, REPAIRS, CLEANING, BEAUTY, TUTORING, OTHER, matching the 126:285 grid) and send it as details.serviceCategory beside details.businessType = 'SERVICES'. The merchant wizard already sends businessType in the details map (partner_application_screen.dart:592-594).
- PHONE NUMBER field '+961 71 234 567'. Data: OnboardingApplication.contactPhone (varchar 32). It is optional, and verified when given: phone_verified_at is set together with it. The frame has no one-time-code step. The open path verifies through POST /api/onboarding/verifications and /verifications/confirm; the signed-in path (POST /api/onboarding/applications/mine) relies on the account's verified email.
- LOCATION / AREA field 'Mar Mikhael, Beirut' (free text in the design). Data: merchant applications have no area today; the wizard asks none. Store it as details.area {zoneId, label}, picked from the curated delivery zones (GET /api/delivery-zones, DeliveryZoneController.java:58), not free text. stores.neighborhood is free text (VARCHAR 80), and the previous batch already flagged these as two incompatible vocabularies. The pick later seeds the store's neighbourhood.
- Primary CTA 'Create Service Account' (brand fill, radius 12, padding 14, 14 bold white). Action: submit the application. Signed-in path: POST /api/onboarding/applications/mine, kind MERCHANT. Open path: POST /api/onboarding/applications, then a passcode. 'Create account' is misleading: the account holds APPLICANT until a reviewer or auto-approval lets it sell (ProvisionAccount revokes APPLICANT), so the copy should say 'Apply'.
- States the frame omits but the flow needs:
  - The open path needs an email and a passcode, because an application cannot exist without a verified email (email_verified_at NOT NULL).
  - Submitting spinner.
  - 409 when the account already has an application: show its status.
  - 422 field errors.
  - Success: PendingApplicationScreen with the reference.
  - Auto-approved: the role only takes effect after signing out and in again (main.dart:849 pattern).
  - The documents step: merchants upload National ID and commercial registration today (application_documents_step.dart:49-52).

**Existing code that already covers part of it**

- clients/apps/mobile_app/lib/src/partner_application_screen.dart
  - PartnerApplicationScreen (104); PartnerKind {merchant, rider, carrier} (43-54).
  - Merchant step 0 (1922-1993): business name, owner name, businessType (73-84), email, optional phone, passcode.
  - Details sent at 592-594; always four steps (211).
- clients/apps/mobile_app/lib/src/partner_choice_screen.dart (Merchant/Rider/Carrier cards, 54-73), welcome_screen.dart (38-40), google_sign_in.dart (Customer/Rider/Seller question, 54-61), home_route.dart homeFor (34-71).
- clients/packages/delivery_core/lib/src/api/onboarding_api.dart
  - Open path: POST /api/onboarding/applications (76-163), then /applications/{reference}/account (169-177).
  - Signed-in path: POST /api/onboarding/applications/mine (211-233).
  - Status: GET /applications/mine (183-191).
  - Kinds: models/onboarding_models.dart OnboardingKind MERCHANT/CARRIER/RIDER (5-13).
- services/onboarding-service/src/main/java/com/delivery/onboarding/domain/OnboardingApplication.java
  - Kind {MERCHANT, CARRIER, RIDER}; liveRole() maps MERCHANT to the MERCHANT realm role (40-61).
  - details is jsonb ('business type ... different questions for different kinds of applicant'), validated for size only.
  - contactPhone is optional and verified when given.
- services/onboarding-service/.../api/AccountOnboardingController.java: POST /api/onboarding/applications/mine (88) and POST /api/onboarding/me/customer (106).
  services/onboarding-service/.../service/AccountApplicationService.java: grants APPLICANT, then the live role (323-337); auto-approval can run straight away (348).
- services/onboarding-service/.../service/AutoApprovalPolicy.java: one switch per kind, isAutomatic(kind). delivery.onboarding.auto-approve.merchant defaults to false. V43__auto_approval_settings.sql pins the kinds with CHECK (kind IN ('MERCHANT','CARRIER','RIDER')).
- services/onboarding-service/.../process/ProvisionAccount.java grants MERCHANT and revokes APPLICANT on an existing account (59-81). CreatePartnerRecord.java deliberately creates nothing for a merchant: 'their shop appears with their first product'.
- services/product-service/.../service/StoreService.java requireStoreFor (466-480) auto-creates 'My Store' as a RESTAURANT, open all day and already published, on the merchant's first product. A provider's first offer would create a restaurant today.
- Back office:
  - clients/apps/delivery_portal/lib/src/backoffice/onboarding_screen.dart: approve (581-585), decline with a reason (587-592), Category column (503-511).
  - auto_approval_panel.dart: Riders / Shops / Delivery companies switches.

**Missing in the clients**

- ServiceProviderSignupScreen (mobile_app/lib/src/service_signup_screen.dart): the four fields and the CTA.
  - Reuses the merchant wizard's submission code rather than a second copy.
  - The signed-in path is the default. It sends kind MERCHANT with details {businessType: 'SERVICES', serviceCategory, area: {zoneId, label}}.
  - The open-path variant adds the existing wizard's email, one-time code and passcode fields.
- Entry points:
  - An 'Offer your services' row in ProfileDrawer (profile_drawer.dart). No become-a-partner entry exists today.
  - A Services choice in PartnerChoiceScreen, and after 'Seller' in the Google role question.
  - A footer link on the Services tab (126:285; not drawn).
- delivery_core: a ServiceCategory enum with wire values, localised labels (localised_labels.dart) and icons. A zone picker for the area, reusing the zone list the address sheet already loads.
- Role switch: homeFor ranks MERCHANT above customer (home_route.dart:66), so a customer who applies lands in MerchantShell from then on. Add 'Switch to shopping' / 'Open your services shop' rows using the preferred-role rule homeFor already honours (48-59).
- First run after approval: create the SERVICES store from the application details (see missingBackend) before the offers screens can be used.

**Missing in the backend**

- onboarding-service, default: no schema change. Kind stays MERCHANT, with details.businessType = 'SERVICES' plus details.serviceCategory and details.area. Validate in ApplicationIntake when businessType is SERVICES: serviceCategory must be a known value, and area.zoneId a UUID. The portal can then trust the values. No migration, because details is jsonb.
- onboarding-service, only if the owner wants a separate approval switch or queue: a new Kind SERVICE_PROVIDER whose liveRole is still MERCHANT. It needs:
  - V46__service_provider_kind.sql, widening chk_application_kind (V32) and both auto-approval CHECKs (V43).
  - An AutoApprovalPolicy default.
  - New arms in ProvisionAccount and CreatePartnerRecord.
  - Client OnboardingKind and portal filters.

  Not the default.
- product-service: the provider app must create its store explicitly, with POST /api/stores (MERCHANT; exists) and StoreRequest {vertical: SERVICES, serviceCategory} prefilled from GET /api/onboarding/applications/mine, before its first offer. requireStoreFor then finds that store instead of auto-creating a restaurant. Slice 1 adds serviceCategory to StoreRequest.
- Portal: show businessType and serviceCategory from details in the application row. The Category column already exists (onboarding_screen.dart:503-511).

**Design-system pieces to reuse**

- PartnerApplicationScreen submission code and PendingApplicationScreen
- OnboardingApi: the applications/mine and open-path methods
- YdScreenHeader / YdBackButton (yd_screen_header.dart)
- YdPillButton (CTA, busy while submitting)
- YdCard (banner, with DeliveryColors.brandSoft background)
- Tokens: DeliveryColors.brand #e11d48, brandSoft #fff1f2, ink #0f172a, muted #475569, faint #94a3b8, border #e2e8f0, background #f8fafc. Radii: DeliveryRadius.sm 8 (fields), md 12 (CTA), lg 16 (banner).

**Strings** (prefix `svc`; each needs en and ar)

- svcSignupTitle: 'Grow your business on YouDrop'
- svcSignupSubtitle: 'Reach customers in your neighbourhood.' (the design's 'thousands' dropped)
- svcSignupBannerTitle: 'Lebanese services'; svcSignupBannerBody: 'Printing, tailoring, repairs, photography and more — picked up at your shop or delivered by YouDrop.' (the design's 'same-day' dropped)
- svcBusinessName: 'Business name'; svcBusinessNameHint: 'e.g. Al Fakhry Press'
- svcServiceCategory: 'Service category'
- svcArea: 'Location / area'; svcAreaHint: 'Choose your area'
- svcApplyCta: 'Apply to sell services' (design: 'Create Service Account')
- svcCategoryPrinting / svcCategoryTailoring / svcCategoryPhotography / svcCategoryRepairs / svcCategoryCleaning / svcCategoryBeauty / svcCategoryTutoring / svcCategoryOther
- svcOfferYourServices: 'Offer your services' (drawer row); svcSwitchToShopping: 'Switch to shopping'
- Reuse the wizard's existing phone, email, one-time code and pending-application strings. Every new key needs en and ar.

**Tests that should prove it**

- Widget (mobile_app):
  - Name, category and area are required.
  - Submitting calls the applications/mine method with kind MERCHANT and details {businessType: SERVICES, serviceCategory: PRINTING, area: {zoneId, label}} (fake OnboardingApi).
  - 409 shows the existing application's status; success pushes the pending state.
  - RTL layout (arabic_rtl_test.dart).
- Java (onboarding AccountApplicationServiceTest / ApplicationIntake):
  - businessType SERVICES with an unknown serviceCategory is refused.
  - A SERVICES application is auto-approved exactly when merchant auto-approval is on, and not otherwise.
  - ProvisionAccount grants MERCHANT and revokes APPLICANT as for any merchant.
- Java (product-service StoreServiceTest): a merchant who already created a SERVICES store gets that store from requireStoreFor. No RESTAURANT store is auto-created.
- Portal widget: the onboarding row reads 'Services · Printing' for such an application.

**Questions**

- A new onboarding kind, or MERCHANT with businessType SERVICES? (Default: MERCHANT + businessType. It shares the merchant auto-approval switch and documents.)
- Must informal providers (many tailors and repairers) upload National ID and commercial registration? (Default: the same documents as merchants. A reviewer can approve past missing ones with acknowledgeDocumentIssues.)
- Is the phone verified by one-time code? (Default: yes, when it is not already the account's verified contact.)
- Which categories are offered at signup? (Default: the item-based ones only; see the architecture questions.)

*Screenshot:* `D:/dev-cache/temp/claude/D--workspace-azkar/11fcc69a-fe2e-40db-a8fa-f1a5dd6e94d8/scratchpad/figma126/126-11_service-provider-signup.png`

### `126:51` service-provider-dashboard — L

*Who:* An approved service provider (MERCHANT role, store vertical SERVICES) on the phone; the same screen on merchant web. The frame draws the customer six-tab bar with Account active, as if the provider area lived inside the customer app's Account tab.

*What:* The provider's home, showing:

- Identity: logo, name, verified badge, area.
- A notifications bell.
- Three stats: Active Offers 3, This Week 12, Rating ★ 4.8.
- Quick actions: Add Offer, View Orders.
- The Current Offers list: title, unit ('500 cards', 'Per sqm', '1000 pcs'), price, ACTIVE/PAUSED chip.

*Reached from:* After sign-in, homeFor sends the provider to MerchantShell; in services mode the Dashboard tab (index 0) is their home.

- Add Offer pushes the offer form.
- View Orders switches to the Orders tab.
- An offer row pushes the form in edit mode.
- The bell pushes NotificationsScreen.

The design's customer bar with Account active is not implemented. If the owner wants the provider area inside the customer app instead, this dashboard becomes a ProfileDrawer entry and its orders and offers screens become pushed routes.

**Every element, and where its data comes from**

- Header row:
  - 40px round logo: Store.logoRef via StoreResponse.logoThumbUrl, StoreAvatar monogram fallback.
  - Name 'Al Fakhry Press' (14 bold ink) with a 14px verified glyph (brand).
  - Subtitle 'Beirut, Lebanon' (11 muted).

  Data: GET /api/stores/mine (StoreController.java:226-233). 'Beirut, Lebanon' is not a stored pair; use store.neighborhood (e.g. 'Mar Mikhael') or the address.
  Verified glyph = Store.verifiedLocal (Store.java:191-193, 'Backoffice-set, never merchant-writable'). main has no setter; PUT /api/stores/{id}/verified-local exists only in the uncommitted wt-dekkane worktree. Hide the glyph when false.
- Bell (36px brandSoft circle, 20px brand bell): opens NotificationsScreen with the unread badge from /api/notifications/unread-count. The inbox is owned by CustomerShell today (customer_shell.dart:104-106); MerchantShell has no bell.
- Stat card 'Active Offers' (label 11 SemiBold muted, value '3' 18 bold brand; white, border, radius 12, padding 12). Data: count of ACTIVE products in the service store. GET /api/products/mine (ProductController.java:96-104) has no status filter and no count. Add ?status=ACTIVE and read PageResponse.totalElements with size=1.
- Stat card 'This Week' (value '12', 18 bold ink). Undefined in the design: placed orders, completed orders, or revenue? Recommend orders placed in the rolling last 7 days: window.orders of GET /api/orders/merchant/summary?days=7 (OrderController.java:121; TradingSummaryService Totals(orders, delivered, money, waived) at 223, MerchantSummary at 248-253). OrderApi.merchantSummary(days) exists (order_api.dart:99-103); the goods dashboard uses days=14.
- Stat card 'Rating' (value '★ 4.8', 18 bold #10b981, DeliveryAccent.positive). Data: Store.rating and ratingCount (store_models.dart:372-373); null renders 'New', the storefront's own rule (StoreService.bestFirst: no rating is not a good rating). Reviews are accepted only for delivered orders (ReviewService.requireDeliveredOrder, via reviewable_orders built from order.delivered). Pickup orders must end in DELIVERED, or a pickup-only provider can never be rated.
- 'QUICK ACTIONS' label (11 SemiBold muted), then two buttons:
  - '+ Add Offer' (brand fill, radius 8, 11 SemiBold white, plus glyph): pushes the offer form (126:133).
  - 'View Orders' (brandSoft fill, brand text, clipboard-list glyph): switches to the Orders tab (126:200).
- 'Current Offers' (14 bold) and offer rows (white, border, radius 12, padding 12):
  - Title (14 bold ink).
  - Unit line (11 muted: '500 cards', 'Per sqm', '1000 pcs').
  - Price (14 bold brand: '$15.00').
  - Status chip: ACTIVE (#dcfce7 bg, #10b981 10 bold) or PAUSED (#e2e8f0 bg, #475569).

  Data: GET /api/products/mine plus the new service block (unit label and size, pricing type). PAUSED has no source: Product.Status is DRAFT/ACTIVE/ARCHIVED (Product.java:26-36; chk_product_status in V10__catalog.sql:36). The rows show no LBP figure, unlike every other price in this batch.
- States the frame omits:
  - No store yet: first run creates it from the application.
  - Pending approval: MerchantShell's pendingApproval banner; publishing is refused while APPLICANT (ProductController.java:159-163).
  - No offers: empty state with Add Offer.
  - Load error.
  - DRAFT (never published) shown apart from PAUSED.
  - Rating null.
- Bottom nav: the customer six-tab bar (Home, Butler, Basket, Services, Orders, Account) with Account active. This conflicts with routing: a MERCHANT account lands in MerchantShell (home_route.dart:66; main.dart:896-916), whose bar is Dashboard/POS/Inventory/Orders/Settings (merchant_shell.dart:101, items 347-381).

**Existing code that already covers part of it**

- clients/packages/delivery_merchant/lib/src/dashboard_screen.dart, MerchantDashboardScreen (26).
  - Loads: merchantSummary days=14 (161), forMerchant(size: 5) (177), storeApi.mine(size: 1) (203), aggregates.merchantDaily (148); refreshes every 60s (70).
  - Shows: header with the Active switch (411-460), Today's Summary (497-531), Pending Orders card (634-718), 'Needs you now' (728-772).
  - No rating, no week figure, no offers count.
- clients/packages/delivery_merchant/lib/src/order_detail_screen.dart: MerchantMetricCard (122), MerchantTileGrid (267), MerchantScreenHeader (309), MerchantStatusTag (99), merchantMoney (38; two decimals, no currency).
- clients/apps/mobile_app/lib/src/merchant_shell.dart: MerchantTab {dashboard, pos, inventory, orders, settings} (101); owner = hasRole(merchant) (117-119); Orders badge polls every 30s (130-135); YdBottomNav (402).
- clients/apps/mobile_app/lib/src/home_route.dart homeFor (34-71): CARRIER, then DELIVERY, then MERCHANT, then customer. A preferred role from the Google question wins if the account holds it (48-59).
- services/order-manager/.../service/TradingSummaryService.java: MerchantSummary(windowDays, days, today, yesterday, window, platformFees, savedByOffers, commissionPercentage, awaitingYou, preparing, readyForPickup, onTheWay, topProducts) (248-253); commission-percentage default 12.5 (61).
- services/product-service/.../domain/Store.java: rating and ratingCount (122-127, 'Null until the store has been rated at all'), verifiedLocal (191-193), neighborhood (187-189). ReviewService.recomputeRating writes them.
- services/product-service/.../api/ProductController.java: GET /mine (96-104), POST /{id}/publish refusing APPLICANT (159-163), DELETE /{id} archives (169-176).
- clients/packages/delivery_merchant/lib/src/product_list_screen.dart: availability switch, where on = publish and off = archive (120-168); status labels Available/Draft/Off-shelf (591-595).

**Missing in the clients**

- ServiceDashboardScreen in delivery_merchant, shared by phone and portal merchant web:
  - Header: logo, name, verified glyph, area.
  - Bell with unread badge.
  - Three MerchantMetricCards: Active offers, This week, Rating ('New' when null).
  - Two quick actions.
  - Current offers list with ACTIVE/PAUSED/DRAFT chips and a Pause/Resume action per row.
  - Secondary LBP line via MarketRates.instance.lbp (the design omits it; every other price in the batch has one).
- MerchantShell services mode:
  - Trigger: the owner's store (StoreApi.mine) has vertical SERVICES.
  - Bar: Dashboard / Orders / Offers / Settings. POS and Inventory are hidden (in this model a print shop has no till or stock ledger).
  - Dashboard mounts ServiceDashboardScreen.
  - Portal merchant rail gets the same substitution: hide POS, Inventory and Categories; Products becomes Offers. Keep the existing destination order so jump(2) still means Orders (portal_shell.dart:192).
- Role switch rows (see 126:11) in MerchantShell Settings and ProfileDrawer.
- delivery_core additions:
  - StoreVertical.services, excluded from every picker.
  - ServiceCategory.
  - Product.service (ServiceTerms: pricingType, unitLabel, unitSize, turnaroundMinHours, turnaroundMaxHours, fulfilmentModes, attachmentPolicy).
  - ProductStatus.paused, parsed tolerantly.
  - CatalogApi.myProducts(status:), pause, resume.
  - StoreApi.reviews (no client method exists today).
- The notification inbox and bell, mounted for the merchant shell.

**Missing in the backend**

- product-service V35__product_paused.sql: widen chk_product_status to include 'PAUSED'.
  - Product.pause() (ACTIVE to PAUSED) and resume() (PAUSED to ACTIVE, re-running publish's image rule).
  - POST /api/products/{id}/pause and /resume (MERCHANT, owner only), emitting PRODUCT_UPDATED.
  - GET /api/products/mine?status=.

  Every storefront query already filters status = ACTIVE (ProductRepository.findActiveInStore / findActiveCatalog), so a paused offer drops out with no other change.
- order-manager: nothing new if 'This Week' means orders placed in the last 7 days (summary?days=7). The same payload has delivered and money if the owner picks another meaning.
- Rating: no change, provided pickup completion emits order.delivered (126:200 and 126:507). Otherwise pickup-only providers stay 'New' forever.
- Verified glyph: depends on the dekkane work's PUT /api/stores/{id}/verified-local (BACKOFFICE) landing.

**Design-system pieces to reuse**

- MerchantMetricCard, MerchantTileGrid, MerchantScreenHeader, MerchantStatusTag, merchantMoney (order_detail_screen.dart)
- StoreAvatar (storefront.dart) as the logo fallback
- VerifiedLocalBadge (mobile_app store_power_chip.dart) or its glyph, moved to the design system so delivery_merchant can use it
- YdBottomNav (services-mode items), YdEmptyState, YdBadge
- NotificationsScreen and the shell-owned notification inbox
- MarketRates.instance.lbp for the secondary LBP line
- Tokens: brand, brandSoft, ink, muted, border, background. DeliveryAccent.positive for the rating and the ACTIVE chip. The ACTIVE green tint #dcfce7 has no token; use the positive accent's soft fill.

**Strings** (prefix `svc`; each needs en and ar)

- svcDashboardActiveOffers: 'Active offers'
- svcDashboardThisWeek: 'This week'; svcDashboardThisWeekCaption: 'Orders, last 7 days'
- svcDashboardRating: 'Rating'; svcRatingNew: 'New'
- svcQuickActions: 'Quick actions'; svcAddOffer: 'Add offer'; svcViewOrders: 'View orders'
- svcCurrentOffers: 'Current offers'
- svcOfferActive: 'ACTIVE'; svcOfferPaused: 'PAUSED'; svcOfferDraft: 'DRAFT'
- svcPauseOffer: 'Pause offer'; svcResumeOffer: 'Resume offer'
- svcNoOffersYet: 'No offers yet — add your first service'
- svcUnitPack: '{count} {unit}'; svcUnitPer: 'Per {unit}'
- svcOpenServicesShop: 'Open your services shop'
- Reuse navOrders, navSettings and the existing notification strings.

**Tests that should prove it**

- Widget (delivery_merchant):
  - Stats from fakes: Active offers = totalElements of myProducts(status: ACTIVE); This week = summary(days: 7).window.orders; Rating = store.rating, 'New' when null.
  - Chips: PAUSED for a paused product, ACTIVE for an active one.
  - Empty state offers Add Offer.
  - The verified glyph is hidden when verifiedLocal is false.
- Widget (mobile_app merchant shell): a SERVICES store shows Dashboard/Orders/Offers/Settings and no POS or Inventory. A goods store renders exactly as today (regression).
- Java (product-service CatalogServiceTest):
  - Pausing an ACTIVE product sets PAUSED, emits product.updated, and removes it from GET /api/stores/{id}/products.
  - Resume without images is refused (422).
  - A non-owner gets 404.
  - GET /mine?status=ACTIVE counts only active products.
- Migration: V35 applies on a database holding existing DRAFT/ACTIVE/ARCHIVED rows.
- Portal: the merchant rail for a SERVICES store hides POS and Inventory, and index 2 is still Orders.

**Questions**

- What is 'This Week': orders placed in the rolling last 7 days (default), completed orders, or revenue?
- Does the provider work in a merchant-shell 'services mode' (default), or inside the customer app's Account tab as drawn?
- Can one store sell both goods and services (a stationer that also prints)? (Default: no. One store has one vertical, and a merchant may open a second store.)
- Is the verified badge the existing Verified Local flag (default), or a separate 'verified provider' status?

*Screenshot:* `D:/dev-cache/temp/claude/D--workspace-azkar/11fcc69a-fe2e-40db-a8fa-f1a5dd6e94d8/scratchpad/figma126/126-51_service-provider-dashboard.png`

### `126:133` service-add-offer — L

*Who:* A service provider (MERCHANT, SERVICES store) on the phone; the same form on merchant web.

*What:* Create or edit a service offer: title, description, category, price with a dual-tariff display (USD with LBP), pricing type, photos, estimated turnaround, delivery method, and Publish.

*Reached from:* ServiceDashboardScreen 'Add Offer' pushes ServiceOfferFormScreen in create mode; an Offers tab row pushes it in edit mode. Publish success pops to the list with a snackbar. Portal: the merchant web 'Offers' destination opens the same screen, as product_list_screen does for ProductFormScreen (FAB and row tap).

**Every element, and where its data comes from**

- Header bar (white, bottom border): back chip (16px chevron in a #f8fafc disc), title 'New Service Offer' (18 bold), and an overflow '…' with no defined actions. In edit mode, use the overflow for Save draft, Pause and Archive.
- OFFER TITLE field ('Corporate Brochure Printing'). Data: Product.name (@NotBlank, @Size(max = 200) on ProductRequest).
- DESCRIPTION, multi-line. Data: Product.description (@Size(max = 4000)).
- CATEGORY select ('Printing'). Data: the new ServiceCategory on the offer, defaulting to the store's. Not Product.categoryId: platform categories are the goods tree, and store categories are shelf sections (V26).
- PRICE & DUAL TARIFF: a label, a 'USD' toggle pill (brand, 56x24, white knob), and two boxes: '$20.00' (white) and '1,800,000 LBP' (brandSoft fill, brand border, bold brand).
  Data: Product.price, numeric(12,2) USD (@DecimalMin 0.01, @Digits(10,2)).
  The LBP box must be a read-only conversion at the platform rate: MarketController delivery.market.lbp-per-usd, default 90000; $20 × 90,000 = 1,800,000, consistent. The server has no LBP price and must not get one (MarketController: 'a CONVERSION at one platform-wide rate, not a second price anybody set').
  The toggle's meaning is undefined. Letting a provider type LBP and converting to USD would store non-round USD prices at a rate that moves. Drop the toggle (default), or make it swap only which figure is shown first.
- PRICING TYPE select ('Fixed Price'). No such concept exists. Proposed values:
  - FIXED: one price per offer, or per pack of the offer's unit.
  - PER_UNIT: price × a unit count such as sqm or pages.
  - FROM: base price, with options adding to it.

  'Quote on request' cannot go through a server-priced order and is excluded.
- UPLOAD PHOTOS: a camera tile and two 64px placeholder tiles, one selected in brand.
  Data: the product image flow: POST /api/products/{id}/images/presign, PUT to storage, POST /api/products/{id}/images/{fileId}/confirm (ProductImageController.java:33-74).
  Limits: at most 8 images (delivery.catalog.max-images-per-product); image types only (Thumbnailer.requireRenderable). Publishing needs at least one image (Product.publish, 179-185).
  On a new product, picked photos are held and uploaded after the first save (product_form_screen.dart:177-223).
- ESTIMATED DELIVERY TIME select ('1-2 Days'). Data: none. Store.etaMinMinutes and etaMaxMinutes are the whole shop's delivery minutes (CHECK eta_min_minutes > 0), not turnaround. Needs a per-offer turnaround (min/max hours) chosen from presets: Same day, 1–2 days, 3–5 days, About a week. The label should say 'Turnaround', because delivery time comes on top.
- DELIVERY METHOD select ('Both (Pickup & YouDrop Delivery)'). Data: none. There is no pickup fulfilment anywhere; the merchant store screen has no pickup option, and OrderService.place always prices a delivery. Needs per-offer fulfilment modes PICKUP / DELIVERY / BOTH. DELIVERY requires the store to have delivery areas or a pin with a radius (zones_screen.dart, store_pin_map.dart).
- Primary CTA 'Publish Offer'. Sequence:
  1. POST /api/products with the service block.
  2. Upload photos.
  3. PUT /api/products/{id}/options, if any.
  4. POST /api/products/{id}/publish: 422 without an image, 403 while APPLICANT.
- Fields the frame omits that the other frames depend on:
  - Unit label and pack size (the dashboard shows '500 cards', 'Per sqm', '1000 pcs'; the order screen steps its quantity in 500s).
  - Option groups (the order frame's 'Paper type: Matte Finish (Premium)'), via the existing ProductOptionsEditor.
  - Customer file policy (the order frame's 'Upload design file'): none, optional or required.
  - An optional instructions prompt.
  - Save draft, validation errors, 'publishing is available after approval', and edit mode with Pause/Resume/Archive.

**Existing code that already covers part of it**

- clients/packages/delivery_merchant/lib/src/product_form_screen.dart, ProductFormScreen (26).
  - Fields: name (456-467), description (469-479), price ≥ 0.01 (485-501), category dropdown (511-593).
  - Images: upload held until first save (177-223), remove (303-311).
  - Options section, available after the first save (603-713).
  - Save: POST or PUT, then re-read (127-150).
- clients/packages/delivery_merchant/lib/src/product_options_editor.dart, ProductOptionsEditor (15): group name (195-202), min/max selections (216-242), option name and signed price delta (258-284), validation (41-62).
- clients/packages/delivery_core/lib/src/api/catalog_api.dart: create (53), update (59), publish (66), setProductOptions (80-91), archive (94), uploadImage (190-242), removeImage (244).
- services/product-service/.../api/dto/CatalogDtos.java: ProductRequest (29-48) has name, description, price, categoryId, storeId, sku and barcode. No service fields.
- services/product-service/.../domain/Product.java: DRAFT/ACTIVE/ARCHIVED; publish needs an image (179-185); removing the last image demotes to DRAFT (197-204).
- services/product-service/.../domain/ProductOptionGroup.java: selection is a min/max range, validateSelection, and minimumDelta ('used to show a product's "from" price'). ProductOption.java has a signed priceDelta, isDefault and available. Tables in V15__product_options.sql.
- services/product-service/.../service/ProductImageService.java: presign (max 8 images, Thumbnailer.requireRenderable) and confirmImage (creates the thumbnail).
- services/product-service/.../api/MarketController.java: lbpPerUsd, default 90000. clients/packages/delivery_core/lib/src/util/market_rates.dart: MarketRates.lbp rounds to the nearest 1,000 (44-48).

**Missing in the clients**

- ServiceOfferFormScreen (delivery_merchant/lib/src/service_offer_form_screen.dart), built on ProductFormScreen's image and options plumbing rather than a copy. Fields:
  - Title, description, ServiceCategory.
  - USD price with a read-only LBP preview (MarketRates.instance.lbp).
  - Pricing type, unit label and pack size (e.g. 'cards' × 500, or 'sqm' × 1).
  - Photos (at least one to publish), turnaround preset, fulfilment modes, customer file policy, instructions prompt.
  - Option groups via ProductOptionsEditor.
  - Save draft and Publish; in edit mode Pause/Resume/Archive in the overflow.
- Offers list screen for the 'Offers' tab in services mode: the dashboard's Current Offers as a full list, reusing product_list_screen's row-and-switch pattern with PAUSED added.
- delivery_core: ServiceTerms model (toJson/fromJson) on Product.service, ProductStatus.paused, CatalogApi.pause and resume.

**Missing in the backend**

- product-service V34__service_terms.sql: table service_terms.
  - product_id uuid PRIMARY KEY, REFERENCES products ON DELETE CASCADE.
  - service_category varchar(24) NOT NULL, CHECK list.
  - pricing_type varchar(16) NOT NULL, CHECK IN ('FIXED','PER_UNIT','FROM').
  - unit_label varchar(40) NULL.
  - unit_size integer NOT NULL DEFAULT 1, CHECK 1..100000.
  - turnaround_min_hours and turnaround_max_hours integer NOT NULL, CHECK (turnaround_min_hours >= 0 AND turnaround_max_hours >= turnaround_min_hours).
  - fulfilment_modes varchar(16) NOT NULL, CHECK IN ('PICKUP','DELIVERY','BOTH').
  - attachment_policy varchar(16) NOT NULL DEFAULT 'NONE', CHECK IN ('NONE','OPTIONAL','REQUIRED').
  - instructions_prompt varchar(160) NULL.

  Entity ServiceTerms (@Id productId) with a top-level repository; RepositoriesAreTopLevelTest guards nested repositories, which crashed a deploy before.
- ProductRequest and ProductResponse gain an optional nested 'service' block; ProductResponse also gains fromPrice (price plus each required group's minimumDelta) for 'From $15.00'. CatalogService.create and update: a product in a SERVICES store MUST carry a service block, and a product in any other store MUST NOT (422). CatalogEvents.ProductSnapshot carries the block.
- Publish rule for a DELIVERY or BOTH offer: the store must have delivery zones or a pin with a radius. Otherwise every delivery order is refused at placement with 'does not deliver to that area' (OrderService.applyStoreTerms 329-335).
- PAUSED status: V35, see 126:51.
- Keep prices USD-only; no LBP column (platform rule).

**Design-system pieces to reuse**

- ProductFormScreen image picker and three-step upload
- ProductOptionsEditor
- MerchantScreenHeader, YdPillButton, the product form's field styles
- MarketRates.instance.lbp
- CatalogApi create / update / publish / uploadImage / setProductOptions

**Strings** (prefix `svc`; each needs en and ar)

- svcNewOffer: 'New service offer'; svcEditOffer: 'Edit offer'
- svcOfferTitle: 'Offer title'; svcDescription: 'Description'; svcCategory: 'Category'
- svcPriceUsd: 'Price (USD)'; svcLbpPreview: '≈ {amount} at today’s rate'
- svcPricingType: 'Pricing type'; svcPricingFixed: 'Fixed price'; svcPricingPerUnit: 'Price per unit'; svcPricingFrom: 'Starting price (options add to it)'
- svcUnitLabel: 'Unit (e.g. cards, sqm)'; svcPackSize: 'Units per step'
- svcPhotos: 'Photos'; svcPhotoRequired: 'Add at least one photo to publish'
- svcTurnaround: 'Turnaround'; svcTurnaroundSameDay: 'Same day'; svcTurnaround1to2: '1–2 days'; svcTurnaround3to5: '3–5 days'; svcTurnaroundWeek: 'About a week'
- svcFulfilment: 'How customers get it'; svcFulfilmentPickup: 'Pickup at your shop'; svcFulfilmentDelivery: 'YouDrop delivery'; svcFulfilmentBoth: 'Both'
- svcCustomerFile: 'Customer file'; svcCustomerFileNone: 'Not needed'; svcCustomerFileOptional: 'Optional'; svcCustomerFileRequired: 'Required'
- svcInstructionsPrompt: 'What should customers tell you?'
- svcPublishOffer: 'Publish offer'; svcSaveDraft: 'Save draft'
- svcDeliveryNeedsAreas: 'Set your delivery areas before offering YouDrop delivery'

**Tests that should prove it**

- Widget:
  - The LBP preview equals MarketRates.lbp(price) and cannot be edited.
  - A price of 0, or with 3 decimals, is refused.
  - Publishing without a photo shows the server's 422 message.
  - Turnaround and fulfilment are required.
  - The pack preview renders '500 cards'.
  - Option groups round-trip through ProductOptionsEditor.
- Java (CatalogServiceTest / ServiceTermsTest):
  - A product in a SERVICES store without a service block: 422.
  - A product with a service block in a RESTAURANT store: 422.
  - turnaround_max below turnaround_min: 422.
  - fromPrice = price + the cheapest available delta of each required group.
  - product.created carries the service block.
- Java: publishing a DELIVERY offer in a store with no zones and no pin returns 422 with an actionable message.
- Migration: V34 applies to a database with existing products (no service_terms rows needed).

**Questions**

- Is the price always entered in USD with LBP shown (default), or may a provider type an LBP price?
- Which pricing types launch? (Default: FIXED, PER_UNIT and FROM. No quote-on-request.)
- Turnaround as presets mapped to hour ranges (default), or free hours?
- Is the delivery method chosen per offer (default, checked against the store's delivery areas) or per store?

*Screenshot:* `D:/dev-cache/temp/claude/D--workspace-azkar/11fcc69a-fe2e-40db-a8fa-f1a5dd6e94d8/scratchpad/figma126/126-133_service-add-offer.png`

### `126:200` service-provider-orders — XL

*Who:* A service provider on the phone (MerchantShell services mode, Orders tab); the same queue on merchant web.

*What:* The provider's queue, in tabs New (3) / In Progress (2) / Completed.

- A New card shows the customer's avatar, name and time ago, a NEW chip, '500 Business Cards — Matte Finish', '$15.00 / 1,350,000 LBP', and Decline / Accept Order.
- An In Progress card shows Mark Ready.

This frame carries the service lifecycle: accept, decline, ready, and collected for pickup.

*Reached from:* MerchantShell services mode, Orders tab (with the awaitingYou badge), shows ServiceOrdersScreen; a card pushes the service order detail. The dashboard's View Orders switches to this tab, and a new-order push opens it. Portal merchant web: the Orders destination, which must stay at index 2 (portal_shell.dart:192 jump(2)).

**Every element, and where its data comes from**

- Header bar: back chip, 'Incoming Orders' (18 bold), overflow. As a tab root in services mode there is no back button. The overflow is undefined; use it for search or filter.
- Tabs (white; active tab 14 bold brand with a 3px brand underline, inactive 14 SemiBold muted):
  - 'New (3)': count of PLACED.
  - 'In Progress (2)': ACCEPTED and PREPARING.
  - 'Completed'.

  The design has no home for READY orders (waiting for pickup or a rider). Put READY in In Progress with a 'Waiting for pickup' or 'Waiting for a rider' line (recommended), or add a fourth Ready tab as OrdersScreen has.
- Card header (card: white, border, radius 16, padding 16, gap 12):
  - 32px customer avatar, name 'Jean-Pierre' (14 bold), '10 mins ago' (11 faint).
  - Chip: NEW (#ffedd5 bg, #f97316 text, 10 bold) or IN PROGRESS (brandSoft bg, brand text).

  Data: the order carries no customer name or avatar, only customerId (Keycloak sub) and contactPhone (orders_screen.dart:487-490 notes the gap). Needs a customer display-name snapshot on the order: first name plus last initial, taken from the token at placement. That is a privacy decision. The avatar would need a profile lookup and is not recommended. Time ago comes from placedAt.
- Divider (1px border colour).
- Line summary '500 Business Cards — Matte Finish' (14 muted): {qty × unitSize} {offer name} — {selected options}. Data: OrderItem qty, productName and selectedOptions (V12 jsonb). Unit size and label must be snapshotted onto the line, because a pack of 500 is qty 1.
- Price '$15.00' (14 bold brand) and '/ 1,350,000 LBP' (11 faint).
  Data: show OrderResponse.subtotal, the goods the provider earns before commission; totalAmount includes a delivery fee the provider does not receive. LBP via MarketRates.lbp.
  DESIGN BUG: the second card reads '$16.00 / 1,350,000 LBP', but $16 × 90,000 = 1,440,000. LBP must always be computed, never typed.
- New card actions:
  - 'Decline' (#e2e8f0 bg, muted text, radius 8): POST /api/orders/{id}/cancel with a reason. A merchant may cancel from PLACED (OrderService.cancel 499-540).
  - 'Accept Order' (#10b981 fill, white): POST /api/orders/{id}/accept. By default a service order then goes straight into production.
- In Progress card action: 'Mark Ready' (brand fill): POST /api/orders/{id}/ready, legal only from PREPARING (OrderStatus.allowedNext). For a YouDrop-delivery order this dispatches a carrier (OrderService.applyTransition 654-673). For a pickup order it must not.
- What the frame omits:
  - An order detail with the customer's design files (download), special instructions, delivery method and address, and estimated completion.
  - 'Customer collected' for a READY pickup order (READY to DELIVERED).
  - A decline-reason picker.
  - Empty tabs, refresh and polling.
  - Cancelling after acceptance.
  - Chat with the customer (shop chat).
- Bottom nav: the customer six-tab bar with Orders active, which conflicts with the provider living in MerchantShell.

**Existing code that already covers part of it**

- clients/packages/delivery_merchant/lib/src/orders_screen.dart, OrdersScreen (22).
  - forMerchant(size: 50), polled every 5s (61, 104).
  - Tabs (40-58, counts 274-277): New = PLACED, Preparing = ACCEPTED+PREPARING, Ready = READY+PICKED_UP, Completed = DELIVERED+CANCELLED.
  - Buttons come only from availableActions (576-598), sent via OrderApi.act as POST /api/orders/{id}/{action} (order_api.dart:169-177).
  - Cancel is relabelled Reject and sends the reason 'Cancelled by merchant' (127-128; merchantActionLabel in order_detail_screen.dart:493-494).
  - A 422 means someone else already moved the order (132-135).
- clients/packages/delivery_merchant/lib/src/order_detail_screen.dart, MerchantOrderDetailScreen (506): GET /api/orders/{id} (550); progress bar ACCEPTED/PREPARING/READY/PICKED_UP (532-537); address, phone and totals; actions (986-1008).
- services/order-manager/.../api/OrderController.java: POST /{id}/accept (142-147), /prepare (149-154), /ready (156-161), /cancel (329); GET /merchant (106).
- services/order-manager/.../service/OrderService.java:
  - merchantTransition (434-440).
  - cancel (499-540): a customer may cancel only while PLACED.
  - actionsFor (587-621): PLACED gives ACCEPT, ACCEPTED gives PREPARE, PREPARING gives READY, CANCEL until terminal or picked up.
  - applyTransition (623-687): payment gate, capture on DELIVERED, dispatch at READY, outbox events.
- services/order-manager/.../domain/OrderStatus.java: PLACED → ACCEPTED → PREPARING → READY → PICKED_UP → DELIVERED, plus CANCELLED (38-49). OrderKind.java: CATALOG, BUTLER_BUY, BUTLER_SEND; hasMerchant() true only for CATALOG (77-79). chk_order_kind in V15__butler_orders.sql:9.
- services/order-manager/.../domain/OrderRepository.java: findAvailableForRiders (127-133) and findAvailableFor(providerId) (141-150) list every READY order with no rider. A READY pickup order would appear on every rider and fleet board.
- clients/packages/delivery_core/lib/src/models/order_models.dart: OrderStatus labels ('Ready for pickup' means a rider pickup; fromWire maps unknown values to placed), OrderAction accept/prepare/ready/claim/pickUp/deliver/cancel, DeliveryOrder (kind not parsed).

**Missing in the clients**

- ServiceOrdersScreen (delivery_merchant): OrdersScreen's polling and availableActions model with service tabs: New (PLACED) / In progress (ACCEPTED, PREPARING, READY) / Completed (DELIVERED, CANCELLED).
  - Service card: customer display name, time ago, units × offer — options, subtotal and LBP, a fulfilment chip ('Pickup' / 'Delivery').
  - Actions: Decline sheet with reasons, Accept, Mark ready, Customer collected.
  - Detail screen: instructions, attachments (download via short-lived link), estimated completion, pickup or delivery block.
- OrderAction.collected (wire COLLECTED, POST /api/orders/{id}/collected).
  DeliveryOrder gains kind, fulfilment, customerDisplayName, estimatedReadyAt, attachments, and serviceLine (unitLabel, unitSize), all parsed tolerantly.
- MerchantShell services-mode Orders tab with the existing awaitingYou badge.

**Missing in the backend**

- order-manager V35__service_orders.sql (after V31 idempotency and whatever V32–V34 the gift, checkout and heatmap work claims):
  - chk_order_kind (V15) adds 'SERVICE'.
  - orders.fulfilment varchar(16) NOT NULL DEFAULT 'DELIVERY', CHECK IN ('DELIVERY','PICKUP').
  - orders.delivery_address DROP NOT NULL, with CHECK (fulfilment = 'PICKUP' OR delivery_address IS NOT NULL).
  - orders.customer_display_name varchar(80) NULL.
  - orders.estimated_ready_at timestamptz NULL.
  - order_items.service jsonb NULL: snapshot of unitLabel, unitSize, pricingType, turnaroundMinHours, turnaroundMaxHours.
  - Replace idx_orders_unassigned with a partial index WHERE rider_id IS NULL AND status = 'READY' AND fulfilment = 'DELIVERY'.
- Domain:
  - OrderKind.SERVICE: hasMerchant() true, isButler() false.
  - Order.fulfilment.
  - Order.transitionTo allows READY → DELIVERED only when fulfilment is PICKUP (OrderStatus has no order context, so the rule lives on Order); PICKED_UP stays unreachable for PICKUP.
- OrderService:
  - accept on a SERVICE order records ACCEPTED then PREPARING in one call (default) and stamps estimated_ready_at = acceptedAt + turnaroundMaxHours.
  - New POST /api/orders/{id}/collected (MERCHANT): READY → DELIVERED for PICKUP, running payments.captureOnDelivery and emitting order.delivered.
  - applyTransition skips dispatch for PICKUP.
  - actionsFor gives the merchant COLLECTED on PICKUP+READY and never offers CLAIM there.
  - findAvailableForRiders, findAvailableFor and the partner jobs API exclude PICKUP.
- Decline = merchant cancel from PLACED with reason 'PROVIDER_DECLINED: {reason}'. releaseOnCancel runs as usual, and order.cancelled already carries cancelReason, which notifications render.
- OrderSnapshot and OrderResponse gain fulfilment, estimatedReadyAt and customerDisplayName; kind is already there. Consumers must tolerate the new fields and kind: accounting, notifications-manager, product-service, order-tracking, app-notification, whatsapp-service.
- GET /api/orders/merchant?kind=SERVICE (optional filter, for a merchant with both a goods store and a services store).
- Attachments: GET /api/orders/{id}/attachments, visible to the order's merchant, its customer and BACKOFFICE (see 126:437).

**Design-system pieces to reuse**

- OrdersScreen polling, tab strip and availableActions buttons
- MerchantActionButton, MerchantStatusTag, merchantActionLabel, MerchantOrderDetailScreen layout
- YdEmptyState, MarketRates.instance.lbp
- Tokens: DeliveryAccent.positive (#10b981 Accept), brand (Mark Ready), border / muted (Decline). The NEW chip colours #ffedd5 / #f97316 are not tokens; use DeliveryAccent.caution's soft fill.

**Strings** (prefix `svc`; each needs en and ar)

- svcIncomingOrders: 'Incoming orders'
- svcTabNew: 'New ({count})'; svcTabInProgress: 'In progress ({count})'; svcTabCompleted: 'Completed'
- svcChipNew: 'NEW'; svcChipInProgress: 'IN PROGRESS'; svcChipReady: 'READY'
- svcLineSummary: '{units} {offer} — {options}'
- svcAcceptOrder: 'Accept order'; svcDecline: 'Decline'
- svcDeclineTitle: 'Why are you declining?'; svcDeclineBusy: 'Too busy right now'; svcDeclineCannotDo: 'We can’t do this job'; svcDeclineFileProblem: 'Problem with the file'; svcDeclineOther: 'Other'
- svcMarkReady: 'Mark ready'; svcMarkCollected: 'Customer collected'
- svcWaitingForPickup: 'Waiting for the customer'; svcWaitingForRider: 'Waiting for a rider'
- svcChipPickup: 'Pickup'; svcChipDelivery: 'Delivery'
- svcMinutesAgo: ICU plural '{count, plural, one{1 min ago} other{{count} mins ago}}' (Arabic plural forms required)
- svcNoNewOrders: 'No new orders'; svcDownloadFile: 'Download file'; svcInstructions: 'Special instructions'

**Tests that should prove it**

- Widget:
  - Tab counts from a fake list: PLACED; ACCEPTED+PREPARING+READY; DELIVERED+CANCELLED.
  - Buttons strictly from availableActions: a card whose actions lack COLLECTED shows no Collected button.
  - Decline requires a reason and calls cancel with 'PROVIDER_DECLINED: …'.
  - The LBP line equals MarketRates.lbp(subtotal), guarding the design's 1,350,000-for-$16 bug.
  - A 422 refreshes with the 'already moved' message.
- Java (OrderServiceTest):
  - Accepting a SERVICE order leaves it PREPARING with two history rows, and estimated_ready_at = acceptedAt + turnaroundMaxHours.
  - A READY pickup order is absent from findAvailableForRiders and findAvailableFor, and DispatchService.chooseFor is not called.
  - POST collected on a READY pickup order gives DELIVERED, payment COLLECTED for CASH, and exactly one order.delivered event.
  - collected on a DELIVERY order: 422. A rider trying to deliver a PICKUP order: 404-shaped.
  - CATALOG behaviour is unchanged (the existing suite stays green).
- Migration: V35 on a database with existing orders. Every row gets fulfilment DELIVERY, addresses stay populated, and the new partial index serves findAvailableForRiders.

**Questions**

- May the provider see the customer's name? (Default: first name plus last initial, snapshotted at placement. No avatar.)
- Does Accept go straight to 'In production' (default), or does the provider start production separately?
- Where do READY orders live? (Default: the In progress tab, with 'Waiting for the customer' or 'Waiting for a rider'.)
- Decline reasons: a picklist (default). Does a decline count against the provider?
- How long may a READY pickup wait before the provider can cancel it as not collected? (Default: 72 hours, with a reason.)

*Screenshot:* `D:/dev-cache/temp/claude/D--workspace-azkar/11fcc69a-fe2e-40db-a8fa-f1a5dd6e94d8/scratchpad/figma126/126-200_service-provider-orders.png`

### `126:285` customer-services-browse — L

*Who:* A customer in mobile_app, on the new Services tab (the sixth destination). The frame highlights Home, not Services; that is a design bug, and the Services item is drawn inactive.

*What:* The services home:

- Greeting with avatar and a YOUDROP SERVICES pill.
- A service search.
- A 4×2 category grid: Printing, Tailoring, Photography, Repairs, Cleaning, Beauty, Tutoring, More.
- 'Popular Services Near You' cards: cover, provider, rating, category • distance • area.

*Reached from:* CustomerShell: the CustomerNavBar Services item (new index 3) shows ServicesHomeScreen as a tab root, with no back button.

- A category tile pushes ServiceCategoryResultsScreen.
- Submitting a search pushes ServiceSearchResultsScreen.
- A provider card pushes ServiceProviderScreen (126:371).

The frame's Home-active state is a design bug.

**Every element, and where its data comes from**

- Header (white):
  - 32px avatar (the profile avatar from onboarding GET /api/profile/me) and 'Hi, Jean-Pierre' (14 bold; first name from the token or profile).
  - 'YOUDROP SERVICES' pill (brandSoft, brand 11 SemiBold, radius 8), static.
- Search field (#f8fafc fill, border, radius 12, 18px search glyph, placeholder 'Search for a service...'). Two sources:
  - Providers by name: GET /api/stores?vertical=SERVICES&search=. This matches store names only, with a plain LOWER LIKE (StoreRepository.findStorefrontWithStatus 37-46).
  - Offers by title: nothing restricted to services exists. GET /api/products?search= covers every ACTIVE product of every store (ProductRepository.findActiveCatalog). Needs a new GET /api/products/services?search=&serviceCategory= returning each offer with a store summary.
- 'Service Categories' (14 bold) and a 4×2 grid of tiles (white, border, radius 12, padding 12; 36px brandSoft icon box with a 16px brand glyph; 11 SemiBold label).
  Glyphs: printer, circle-x (Tailoring), camera, wrench, brush-cleaning, sparkles, book-open, more-vertical ('More'). 'circle-x' reads as close or error, not tailoring; use scissors.
  Data: the ServiceCategory enum with localised labels. A tile opens that category's results; 'More' opens the full list.
  Cleaning, Beauty and Tutoring are appointments at the customer's place, which this order flow (make, then pickup or delivery) does not model.
- 'Popular Services Near You' (14 bold) and a card (white, border, radius 16, padding 12):
  - 130px cover, radius 12 (StoreCard.coverThumbUrl).
  - Name 'Al Fakhry Press' (14 bold).
  - Rating chip '★ 4.8' (brandSoft bg, brand 11 SemiBold). The provider page and dashboard draw rating in green #10b981, and the storefront's RatingChip has its own colour; choose one.
  - Subtitle 'Printing • 0.5 km away • Mar Mikhael': category label • distance (GET /api/stores/nearby distanceMetres) • store.neighborhood.

  'Popular' has no metric: nearby sorts by distance, and rating comes from reviews. A real signal exists in product-service's delivered_order_lines (order_id, product_id, store_id, qty, delivered_at; V22): count distinct orders per store over the last 30 days.
- States the frame omits:
  - No address pin: nearby needs coordinates, so fall back to GET /api/stores?vertical=SERVICES (rating first, nulls last) with no distance.
  - No providers in range, search with no results, empty category.
  - Loading skeleton, and error with retry.
- Bottom nav, six destinations: Home, Butler (truck glyph), Basket (cart), Services (briefcase), Orders (clipboard-list), Account (user). The shipped CustomerNavBar has five and draws Butler as a briefcase (customer_nav_bar.dart:61-67); the new frames move the briefcase to Services and give Butler a truck.

**Existing code that already covers part of it**

- clients/apps/mobile_app/lib/src/customer_nav_bar.dart: five destinations; homeIndex 0, butlerIndex 1, basketIndex 2, ordersIndex 3, accountIndex 4, tabCount 5 (31-38). The Butler briefcase glyph is at 61-67.
- clients/apps/mobile_app/lib/src/customer_shell.dart: IndexedStack over tabCount (281-286). _tabAt (172-252) has a default branch that renders an empty box (247-251), so a missing sixth case renders blank instead of failing. Account is RewardsScreen when pointsApi is set, which it is live (233-235).
- clients/packages/delivery_design_system/lib/src/yd_bottom_nav.dart, YdBottomNav (31): any number of items in equal slots, 20px side padding, 11px one-line label with ellipsis. Six items get about 53dp each on a 360dp phone.
- services/product-service/.../api/StoreController.java: GET /api/stores browse (128-147: vertical, search, maxDeliveryFee, maxEtaMinutes, minRating, neighborhood); GET /nearby (177-211; no vertical filter on main); GET /neighborhoods (149). BannerController.java:69 serves GET /api/categories/chips.
- services/product-service/.../domain/StoreRepository.java findStorefrontWithStatus (37-54): '(:vertical IS NULL OR s.vertical = :vertical)'. With no vertical, every vertical is listed, so a SERVICES store would appear on the food and grocery Home.
- clients/packages/delivery_core/lib/src/models/store_models.dart StoreVertical.fromWire (19-21): an unknown value becomes restaurant. An already-installed app would render a print shop as a restaurant.
- Every vertical picker iterates StoreVertical.values: store_home_screen.dart:300, shops_listing_screen.dart:98, categories_screen.dart:43, delivery_merchant store_screen.dart:640, delivery_portal backoffice banners_screen.dart:767.
- services/product-service/.../domain/DeliveredOrderLine.java (V22): order_id, product_id, store_id, qty, delivered_at. The evidence base for 'popular'. CrossSellService states the platform's rule that numbers on a rail must be real.
- In flight (wt-dekkane, uncommitted): StoreController nearby gains openNow, powerStatus, neighborhood, newSinceDays and verifiedLocal through StoreService.NearbyFilters (StoreService.java:269-283 in that worktree). A services filter must extend that record, not fork the endpoint.

**Missing in the clients**

- CustomerNavBar with six destinations: homeIndex 0, butlerIndex 1, basketIndex 2, servicesIndex 3, ordersIndex 4, accountIndex 5, tabCount 6.
  - Butler glyph becomes a truck (Icons.local_shipping); Services takes the briefcase.
  - Fix the class doc comment ('five flat destinations').
  - Add the Services case to CustomerShell._tabAt; its default branch hides a missing case.
  - Every jump already uses the index constants, so value changes propagate. Grep for literal indices before merging.
- ServicesHomeScreen (mobile_app/lib/src/services_home_screen.dart):
  - Greeting and pill.
  - Debounced search whose results page has Providers and Offers sections.
  - Category grid of 8 tiles with a More sheet.
  - A 'near you' list: StoreApi.nearby(vertical: services) when the active address has a pin, else browse(vertical: services).
- ServiceCategoryResultsScreen and ServiceSearchResultsScreen.
- delivery_core:
  - StoreVertical.services plus a pickerVerticals list that excludes it, used in place of StoreVertical.values in the five pickers.
  - StoreFilters.serviceCategory; StoreApi.nearby(vertical, serviceCategory); StoreCard.serviceCategory.
  - ServiceOfferCard model and CatalogApi.searchServices(search, category).

**Missing in the backend**

- product-service V33__services_vertical.sql:
  - chk_store_vertical (V11:66) and chk_category_vertical (V17:64) add 'SERVICES'.
  - stores.service_category varchar(24) NULL, with a CHECK list and CHECK ((vertical = 'SERVICES') = (service_category IS NOT NULL)).
  - An index on (vertical, service_category) WHERE status = 'ACTIVE'.

  Code: Store.Vertical.SERVICES and a Store.ServiceCategory enum; StoreRequest.serviceCategory; StoreService.create and update refuse moving a store into or out of SERVICES (422). That also stops an old merchant app, which reads SERVICES as RESTAURANT, from rewriting the store on a profile save.
- Isolation. This must ship BEFORE the first SERVICES store exists:
  - findStorefront with no vertical excludes SERVICES.
  - nearby excludes SERVICES unless vertical=SERVICES (a NearbyFilters field once dekkane lands).
  - distinctNeighborhoods excludes them.
  - findActiveCatalog (GET /api/products) excludes products of SERVICES stores unless asked.
  - Category chips exclude them.
  - Favourites keep them, because the customer starred them.
- New filters and search: GET /api/stores?vertical=SERVICES&serviceCategory=PRINTING; GET /api/stores/nearby?vertical=SERVICES&serviceCategory=; GET /api/products/services?search=&serviceCategory=&page= returns ACTIVE offers in ACTIVE SERVICES stores, each with a store summary (id, name, logo, rating, neighbourhood).
- Optional 'popular': GET /api/stores/services/popular?latitude&longitude ranks stores by distinct delivered orders in the last 30 days from delivered_order_lines, breaking ties by rating. Nothing invented.
- No ingress change: /api/stores and /api/products already route to product-service (deploy/k3s/overlays/ingress.template.yaml:102-103).

**Design-system pieces to reuse**

- YdBottomNav, CustomerNavBar
- YdSearchField (yd_search_field.dart)
- StoreCard / StoreCardResponse with coverThumbUrl
- RatingChip, StoreAvatar, StoreStatePill (storefront.dart)
- YdSectionHeader, YdEmptyState, YdChip
- DeliveryAddressStore (the active address pin), StoreApi.nearby and browse, ProfileApi avatar
- Tokens: brand, brandSoft, ink, muted, faint, border, background

**Strings** (prefix `svc`; each needs en and ar)

- navServices: 'Services'
- svcHiName: 'Hi, {name}'; svcBrandPill: 'YOUDROP SERVICES'
- svcSearchHint: 'Search for a service…'
- svcCategoriesTitle: 'Service categories'; svcCategoryMore: 'More'
- svcNearYou: 'Services near you' (the design's 'Popular Services Near You' only once a real popularity count backs it); svcPopularNearYou: 'Popular near you'
- svcCardSubtitle: '{category} • {distance} away • {area}'
- svcNoServicesNearby: 'No services near you yet'
- svcSearchProviders: 'Providers'; svcSearchOffers: 'Offers'; svcNoResults: 'Nothing found for “{query}”'
- Reuse tryAgain and the existing could-not-load patterns.

**Tests that should prove it**

- Widget (nav bar and shell):
  - Six items in order, with Services at index 3.
  - Tapping Orders selects index 4 and the shell shows MyOrdersScreen, which guards against jump-by-literal regressions.
  - Butler draws the truck.
  - Every index renders a non-empty body.
  - At 320dp and in Arabic, labels ellipsize without overflow (arabic_rtl_test.dart).
- Widget (ServicesHomeScreen):
  - With a pinned address it calls nearby(vertical: SERVICES) and renders 'Printing • 0.5 km • Mar Mikhael'.
  - Without a pin it calls browse(vertical: SERVICES) and shows no distance.
  - Empty and error states render.
  - A category tile pushes results with serviceCategory set.
- Dart unit: pickerVerticals excludes services; StoreVertical.fromWire('SERVICES') == services.
- Java (StoreRepository / StoreServiceTest):
  - A SERVICES store is absent from GET /api/stores with no vertical, from nearby without vertical, from GET /api/products, from category chips and from neighborhoods.
  - It appears with vertical=SERVICES and the serviceCategory filter.
  - Changing a store into or out of SERVICES: 422.
- API scenario (dev): create a services store and an offer, and confirm the Home storefront responses for goods stores are unchanged.

**Questions**

- Six tabs as drawn (default), or Services reached from Home?
- What does 'Popular' mean? (Default: a distance-sorted 'near you' list until the delivered-orders count endpoint exists.)
- Which categories launch? (Default: Printing, Tailoring, Photography, Repairs. Cleaning, Beauty and Tutoring hidden until appointments exist.)
- Should service stores ever appear on Home or in its search? (Default: no.)

*Screenshot:* `D:/dev-cache/temp/claude/D--workspace-azkar/11fcc69a-fe2e-40db-a8fa-f1a5dd6e94d8/scratchpad/figma126/126-285_customer-services-browse.png`

### `126:371` customer-service-provider-page — M

*Who:* A customer, pushed from the Services tab, search or a category. No nav bar is drawn.

*What:* The provider's storefront:

- Cover, name with verified badge, subtitle, share button.
- '★ 4.8 (56 reviews) • 0.5 km • Open until 6:00 PM'.
- Tabs Offers / Reviews / About.
- Offer cards: photo, title, description, 'From $15.00', Order.

*Reached from:* ServicesHomeScreen, search results or category results push ServiceProviderScreen(storeId). 'Order' pushes ServiceOrderScreen(productId, storeId). Back pops. A later deep link can use the slug (GET /api/stores/{idOrSlug} accepts slugs).

**Every element, and where its data comes from**

- 150px full-bleed cover: StoreResponse.coverUrl, the full-size hero (StoreDtos.java:61-65). No back button over the cover; a pushed route needs one.
- Name 'Al Fakhry Press' (24 bold) with an 18px verified glyph (verifiedLocal). Subtitle 'Printing & Copywriting Services' (14 muted) = Store.tagline (varchar 240).
- Share button (40px #f8fafc circle, share glyph): the app has no share capability (no share_plus; url_launcher only) and a store has no public web page, although slugs exist (GET /api/stores/{idOrSlug}). Default: omit in v1.
- Meta row (11px), items separated by '•':
  - '★ 4.8 (56 reviews)' (SemiBold #10b981): rating and ratingCount.
  - '0.5 km': client haversine from the active address pin to the store's latitude/longitude; checkout_screen.dart and order_tracking_panel.dart already compute haversine.
  - 'Open until 6:00 PM' (SemiBold brand): StoreResponse.closesAt with availability. The CLOSING_SOON, BUSY and CLOSED variants already exist as StoreStatePill states.
- Tabs Offers / Reviews / About: active tab brand 14 bold with a 3px underline; inactive faint.
- Offer card (white, border, radius 16, padding 12):
  - 80px photo, radius 8 (ProductResponse.imageThumbUrls[0]).
  - Title (14 bold) and description (11 muted, one line, ellipsis).
  - 'From $15.00' (14 bold brand): price plus required option minimums (ProductOptionGroup.minimumDelta). Say 'From' only for FROM pricing, or when required options change the price.
  - 'Order' button (brand, radius 8, 11 SemiBold white): pushes the order screen.

  The card has no LBP line and no unit; 'pack of 500' is buried in the description.
- Reviews tab (not drawn): GET /api/stores/{id}/reviews (StoreController.java:434-445). No client method exists.
- About tab (not drawn): description, address, hours (GET /api/stores/{id}/hours), map pin, neighbourhood, and how customers get the work (pickup at the shop, delivery areas).
- States: closed (the order button follows the existing rule: StoreClient.acceptsOrders refuses CLOSED stores); no offers (paused offers are not listed); load error.

**Existing code that already covers part of it**

- clients/apps/mobile_app/lib/src/store_page_screen.dart: the goods storefront (hero, StoreStatePill, aisles, add-to-basket, option sheet). Its basket-add path must not be used for a services store.
- services/product-service/.../api/StoreController.java: GET /api/stores/{idOrSlug} (243-248), /{id}/products (251-270), /{id}/hours (287-295), /{id}/reviews (434-445).
- services/product-service/.../api/dto/StoreDtos.java, StoreResponse (42 onward): description, rating, ratingCount, availability, closesAt (57-58), logoUrl, coverUrl, address, latitude/longitude. It exposes no merchantId.
- services/product-service/.../service/ReviewService.java: forStore page (49); rate requires a reviewable_orders row (77-104).
- clients/packages/delivery_core/lib/src/api/store_api.dart: read (104), products (110), hours (311). No reviews method.
- clients/apps/mobile_app/lib/src/product_options_sheet.dart (option selection UI) and product_detail_screen.dart (QuantityStepper).
- storefront.dart: StoreStatePill, RatingChip, StoreAvatar. store_power_chip.dart: VerifiedLocalBadge.

**Missing in the clients**

- ServiceProviderScreen (mobile_app):
  - Hero with a back button; name, verified glyph, tagline.
  - Meta row: rating; distance only when the address has a pin; open-until from closesAt.
  - Offers tab: ServiceOfferCard list (photo, title, description, unit line, fixed or 'From' price with LBP, Order).
  - Reviews tab: paged list via the new StoreApi.reviews.
  - About tab: description, address, hours table, map preview.
- ServiceOfferCard widget, shared with search results. A haversine helper extracted from checkout_screen.dart.
- StoreApi.reviews(storeId, page) and a Review model.

**Missing in the backend**

- ProductResponse.service block and fromPrice (126:133).
- Nothing else: rating, reviews, hours, closesAt, cover, tagline and pin all exist. GET /api/stores/{id}/products already returns only ACTIVE products.

**Design-system pieces to reuse**

- StoreStatePill, RatingChip, StoreAvatar (storefront.dart); VerifiedLocalBadge
- StorePinPreview (delivery_merchant store_pin_map.dart) for the About map
- YdEmptyState, YdCard, YdPillButton (Order)
- MarketRates.instance.lbp
- The haversine already in checkout_screen.dart / order_tracking_panel.dart, extracted

**Strings** (prefix `svc`; each needs en and ar)

- svcReviewsCount: '{count, plural, one{1 review} other{{count} reviews}}'
- svcOpenUntil: 'Open until {time}'
- svcTabOffers: 'Offers'; svcTabReviews: 'Reviews'; svcTabAbout: 'About'
- svcFromPrice: 'From {price}'; svcOrderCta: 'Order'
- svcNoOffers: 'This provider has no offers right now'
- svcAboutHours: 'Opening hours'; svcAboutAddress: 'Address'; svcAboutGetIt: 'Pickup at the shop or YouDrop delivery'
- svcDistanceKm: '{km} km'

**Tests that should prove it**

- Widget:
  - The meta row renders 'Open until 6:00 PM' from closesAt 18:00 in the device locale, plus the CLOSED and closing-soon variants.
  - Distance appears only with an address pin.
  - 'From $15.00' appears only for FROM offers.
  - The Reviews tab pages GET /api/stores/{id}/reviews.
  - No share button.
  - RTL.
- Java: ProductResponse.fromPrice = price + the cheapest available delta of each required group; an optional group adds 0 (ProductOptionGroup.minimumDelta).

**Questions**

- Can a customer order while the provider is closed, given acceptance happens later anyway? (Default: no. Keep the shops' rule, where CLOSED refuses orders.)
- Share in v1? (Default: no. There is no public store page.)

*Screenshot:* `D:/dev-cache/temp/claude/D--workspace-azkar/11fcc69a-fe2e-40db-a8fa-f1a5dd6e94d8/scratchpad/figma126/126-371_customer-service-provider-page.png`

### `126:437` customer-service-order — XL

*Who:* A customer, pushed from the provider page's Order button.

*What:* Configure and place a service order:

- The offer and its provider.
- Quantity stepper (500) and an option select (Paper type).
- Upload design file and special instructions.
- Delivery method: Pickup at store FREE / YouDrop Delivery +$2.00.
- Subtotal, delivery fee, total, and 'Place Order — $17.00'.

*Reached from:* ServiceProviderScreen 'Order' pushes ServiceOrderScreen(productId, storeId). Place does a pushReplacement to ServiceOrderTrackingScreen(orderId) and refreshes the Orders tab (CustomerNavBar.ordersIndex). The address row opens showAddressSheet. Back pops, with a discard confirm once a file is uploaded.

**Every element, and where its data comes from**

- Header: back chip, 'Order Service' (18 bold), overflow (undefined; drop it).
- Offer title 'Business Card Printing' (18 bold) and 'Provider: Al Fakhry Press' (14 muted): ProductResponse.name and StoreResponse.name.
- Quantity card: 'Quantity' (14 bold), minus (#e2e8f0 tile), '500' (14 bold), plus (brandSoft tile, brand glyph).
  500 means 1 pack of unitSize 500, so OrderLineRequest.qty = 1. The stepper moves in steps of unitSize.
  qty is capped at @Min(1) @Max(99) (OrderDtos.java:42), so at most 99 packs (49,500 cards). PER_UNIT offers such as sqm step by 1.
  A price per card cannot be stored: $25 / 1,000 = $0.025 does not fit unit_price numeric(12,2).
- PAPER TYPE select 'Matte Finish (Premium)': a required single-choice option group (min 1, max 1) from GET /api/products/{id}/options. The running price comes from POST /api/products/{id}/price, the same endpoint order-manager calls at placement. '(Premium)' suggests a surcharge, yet the subtotal stays $15.00: either sample data or a zero delta.
- UPLOAD DESIGN FILE (dashed-border box, radius 12, 24px upload glyph, 'Tap to choose PDF/Artwork file'). No customer upload exists anywhere.
  - platform-storage accepts images only, through one global allow-list (StorageService.presignUpload:58, StorageProperties).
  - onboarding-service overrides the list to add application/pdf for applicant documents (application.yml:238, ApplicantDocumentService.java:74). That is the pattern to copy.
  - order-manager does not depend on platform-storage; its pom has platform-security, platform-outbox and platform-observability only.

  Needs: a picker, presign, PUT, confirm, then the fileIds sent at placement. Required or optional per the offer's file policy. Size cap: StorageProperties.maxUploadSizeBytes is 10 MB.
- SPECIAL INSTRUCTIONS field ('e.g. Please leave white border around card edges...'). PlaceOrderRequest.notes (@Size(max = 500)) is the door or courier note that riders and receipts show. Keep service instructions in their own field, so the rider never sees artwork notes and the provider never misses them.
- DELIVERY METHOD: two radio rows.
  - 'Pickup at store' with 'FREE' (#10b981 11 SemiBold).
  - 'YouDrop Delivery', selected (brandSoft bg, brand border, filled brand radio), with '+$2.00' (14 bold brand).

  Data: the offer's fulfilmentModes. The fee comes from the store's zone terms for the customer's address: GET /api/delivery-zones/terms/{storeId}?zoneId returns served, deliveryFee, minOrder and eta (StoreClient.termsFor 139-147). $2.00 is not a constant.
  Missing: the delivery address row (the DeliveryAddressStore picker checkout uses), a not-served state (served = false), the radius check (checkout's haversine), and a pickup address and hours line.
- Summary: 'Subtotal $15.00', 'Delivery Fee $2.00', divider, 'Total Price $17.00' (18 bold brand). These must be the server's figures: the quote endpoint planned for the multi-shop basket (POST /api/orders/quote; not built), or placement's own response. cart.dart records a local total that quoted 18.25 and then billed 15.00.
  Also missing: an LBP line (checkout shows one), a payment row (only CASH is accepted: delivery.ordering.payment-methods, OrderService.java:76), and a promo row.
- CTA 'Place Order — $17.00' (brand, radius 12, 14 bold white). Sent through OrderApi.place(OrderSubmission) with an Idempotency-Key, which is in flight on feat/order-idempotency and wt-offline. Fulfilment, attachments and instructions must be added to OrderSubmission.toBody and to the server's PlaceOrderRequest.fingerprint(), so a retry that changes the file or the method is refused with 409.
- States the frame omits:
  - Upload: in progress, failed, too large, wrong type; a required file missing.
  - Area not served; store closed (422 '… is closed and is not taking orders right now').
  - 409 PRICE_CHANGED (from the idempotency work).
  - Payment note ('Pay cash when you collect' or 'Pay cash on delivery').
  - Placing spinner, and success leading to tracking.

**Existing code that already covers part of it**

- services/order-manager/.../service/OrderService.java place() (121-248):
  - One store per order (145-154); catalog-priced lines (157-167).
  - applyStoreTerms (312-350): acceptsOrders, zone terms (served, minimum, fee), store pin through routeVia.
  - Then tier (186), waivers (191-193), promo (202-214), payments.authorize (222), outbox ORDER_PLACED (239-240).
- services/order-manager/.../api/dto/OrderDtos.java:
  - OrderLineRequest: qty @Min(1) @Max(99) (40-54).
  - PlaceOrderRequest (56 onward): deliveryAddress @NotBlank, deliveryZoneId, contactPhone, notes (500 max), paymentMethod (defaults to CASH), promoCode, paymentInstrumentToken, deliveryLatitude/Longitude, deliveryTier.
- services/order-manager/src/main/resources/db/migration/orders: V10__orders.sql (delivery_address NOT NULL at 18; chk_item_price_positive), V12__order_line_options.sql (selected_options jsonb, base_unit_price), V15__butler_orders.sql (chk_order_kind).
- services/order-manager/.../client/StoreClient.java: fetch /api/stores/{id} (37-45), termsFor /api/delivery-zones/terms/{id} (139-147), acceptsOrders (106), hasLocation (120).
- services/product-service/.../api/ProductController.java: GET /{id}/options (178), POST /{id}/price (191-203; 'Order Manager calls the same endpoint at checkout'). DeliveryZoneController.java:174 serves GET /api/delivery-zones/terms/{storeId}.
- platform/platform-storage/src/main/java/com/delivery/platform/storage:
  - StorageService.java: presignUpload checks the image allow-list (58); confirmUpload enforces the size after upload.
  - FilePurpose.java: PRODUCT_IMAGE, DELIVERY_PROOF, MERCHANT_KYC, USER_AVATAR, RECEIPT.
  - StorageProperties: presignTtl 10 min, maxUploadSizeBytes 10 MB.
- clients/apps/mobile_app/lib/src/checkout_screen.dart (address, radius check, _place, LBP rate banner 682-700, payment strip), product_options_sheet.dart, delivery_address.dart (DeliveryAddressStore), cart.dart (the local-total incident comment).
- In flight:
  - D:/workspace/wt-offline/clients/packages/delivery_core/lib/src/models/order_submission.dart: OrderSubmission and its Idempotency-Key; its comment tells successors to produce one OrderSubmission per order.
  - wt-offline order_api.dart:43: place(OrderSubmission, {expectedTotal}).
  - D:/workspace/wt-om-offline: OrderDtos.java expectedTotal (155) and fingerprint() (239-262); V31__order_client_request_id.sql.

**Missing in the clients**

- ServiceOrderScreen (mobile_app):
  - Header; offer and provider.
  - QuantityStepper stepping by unitSize: shows units, sends packs.
  - Option selects from productOptions: a dropdown for single choice, the options sheet for multi.
  - Attachment picker: PDF, JPEG or PNG; size checked before upload; progress; remove. Uses the new OrderAttachmentApi (presign, PUT, confirm).
  - Instructions field (1000 characters max).
  - Fulfilment radios limited to the offer's modes; for delivery, the address row and zone (DeliveryAddressStore, showAddressSheet) and a not-served state.
  - Server-quoted subtotal, fee and total with a secondary LBP line; the payment line 'Cash on pickup' or 'Cash on delivery'.
  - CTA with the quoted total, sending an OrderSubmission with fulfilment, attachmentFileIds and serviceInstructions.
  - A 409 PRICE_CHANGED re-confirms; success opens ServiceOrderTrackingScreen and refreshes Orders.
- OrderSubmission (once offline lands) gains fulfilment, attachmentFileIds and serviceInstructions in toBody and toJson. The offline outbox must refuse to queue a service order, which needs uploaded files and a provider's acceptance.
- delivery_core: OrderAttachmentApi, a Fulfilment enum, DeliveryOrder.attachments.

**Missing in the backend**

- order-manager placement (needs V35):
  - PlaceOrderRequest gains fulfilment (default DELIVERY), attachmentFileIds (3 at most) and serviceInstructions (1000 max); fingerprint() includes all three.
  - StoreClient.StoreTerms reads the store's vertical from GET /api/stores/{id}.

  When the vertical is SERVICES:

  - Exactly one line (422 'Order one service at a time').
  - The line's service terms come from ProductCatalogClient (ProductResponse.service) and are snapshotted onto the line.
  - The fulfilment must be one the offer allows.
  - DELIVERY runs applyStoreTerms unchanged.
  - PICKUP skips the served check, charges no fee, needs no address, and keeps acceptsOrders and the minimum.
  - deliveryTier must be STANDARD.
  - The file policy is enforced: REQUIRED needs at least one confirmed file owned by the customer.
  - kind is SERVICE; customer_display_name comes from the token.

  For any other store: PICKUP or attachments return 422 (no shop pickup in v1).
- order-manager V36__order_attachments.sql: table order_attachments (id, order_id NULL until placement, file_id uuid UNIQUE, owner_id varchar(64), object_key, content_type, size_bytes, created_at, attached_at).
  Endpoints:

  - POST /api/orders/attachments/presign (CUSTOMER; body contentType and sizeBytes).
  - POST /api/orders/attachments/{fileId}/confirm.
  - GET /api/orders/{id}/attachments (the order's merchant, its customer, BACKOFFICE), returning short-lived presigned GETs.

  Unattached files older than 24 hours are swept by a scheduled job; order-manager has no @Scheduled code today.
- platform-storage release: FilePurpose.ORDER_ATTACHMENT (bucket 'order-attachments', private) and allowed content types per purpose; today there is one global image list. order-manager is a separate repo that consumes the platform jars from GitHub Packages.
- Deploy, by hand in both namespaces: create the MinIO bucket, and give order-manager MinIO credentials (a Vault bootstrap.sh line plus config rows). order-manager pulls a mutable docker.io tag (services.yaml:98-101).
- Quote: reuse the multi-shop basket's POST /api/orders/quote once it exists (plan only today). Until then, price the line with POST /api/products/{id}/price and the fee with GET /api/delivery-zones/terms/{storeId}?zoneId, and send expectedTotal so the server refuses any other total (409 PRICE_CHANGED, from the idempotency branch).
- Multi-shop basket guard: the planned CheckoutService must refuse products of SERVICES stores (422).

**Design-system pieces to reuse**

- QuantityStepper (product_detail_screen.dart), ProductOptionsSheet and StoreApi.priceSelection
- DeliveryAddressStore, showAddressSheet, checkout's radius check
- OrderApi.place(OrderSubmission), in flight
- MarketRates.instance.lbpParen
- YdPillButton (busy), YdCard, the checkout payment strip's radio row style
- The onboarding documents upload flow (ApplicantDocumentService presign/confirm; application_documents_step.dart picker)

**Strings** (prefix `svc`; each needs en and ar)

- svcOrderServiceTitle: 'Order service'; svcProviderLine: 'Provider: {name}'
- svcQuantity: 'Quantity'
- svcUploadDesign: 'Upload design file'; svcUploadHint: 'Tap to choose a PDF or image'; svcUploading: 'Uploading…'; svcRemoveFile: 'Remove'
- svcUploadTooLarge: 'Files must be under {size} MB'; svcUploadWrongType: 'Only PDF, JPG or PNG files'; svcFileRequired: 'This provider needs your file to start'
- svcSpecialInstructions: 'Special instructions'; svcInstructionsHint: 'e.g. Leave a white border around the card edges'
- svcDeliveryMethod: 'Delivery method'; svcPickupAtStore: 'Pickup at the shop'; svcYouDropDelivery: 'YouDrop delivery'; svcDeliveryFeePlus: '+{amount}'
- svcPlaceOrderTotal: 'Place order — {amount}'
- svcPayCashPickup: 'Pay cash when you collect'; svcPayCashDelivery: 'Pay cash on delivery'
- svcOneServiceAtATime: 'Order one service at a time'
- Reuse: subtotal, delivery, free, custTotalAmount, custOutsideDeliveryArea, tryAgain.

**Tests that should prove it**

- Widget:
  - The stepper shows 500 and 1000 while sending qty 1 and 2, and stops at 99 packs.
  - A required option must be chosen.
  - A REQUIRED attachment keeps the CTA disabled until an upload confirms.
  - A file over 10 MB, or an .ai file, is refused before upload.
  - Pickup hides the address row and shows FREE.
  - Delivery shows the fee from the fake zone terms (not a hard-coded $2.00), and 'does not deliver to this address' when served is false.
  - The CTA shows the quoted total with LBP.
  - Exactly one OrderApi.place call, carrying fulfilment, attachmentFileIds, serviceInstructions and an Idempotency-Key.
  - 409 PRICE_CHANGED shows the new total and asks again; a 422 closed-store message is shown.
- Java (OrderServiceTest, service placement):
  - A SERVICES store with two lines: 422.
  - PICKUP: deliveryFee 0, no served check, null delivery_address accepted, total = subtotal.
  - DELIVERY: fee from the zone terms.
  - EXPRESS: 422. Missing REQUIRED attachment: 422. Another customer's fileId: refused.
  - A non-services store with PICKUP: 422.
  - The snapshot carries fulfilment and the service line.
  - The same Idempotency-Key with a different fulfilment: 409.
- Java (attachments):
  - presign refuses application/zip and oversize files; confirm enforces the size.
  - GET attachments from another merchant: 404.
  - Unattached files are swept after 24 hours.
- Java (platform-storage): PRODUCT_IMAGE still refuses PDF; ORDER_ATTACHMENT accepts it.
- API scenario (dev): upload a PDF; place a pickup order; the provider downloads the PDF, accepts, marks ready and marks collected; order.delivered arrives once and a review is then accepted.

**Questions**

- File types, size, count and retention? (Default: PDF, JPEG or PNG; 10 MB each; up to 3; deleted 90 days after completion.)
- Is cash on collection acceptable for custom work, with no deposit? (Default: yes. The provider can decline.)
- Does delivery follow the provider's delivery zones like shops (default: yes), and is Express offered (default: no)?
- Are promo codes accepted on service orders? (Default: yes, on the subtotal. Free-delivery codes only for delivery.)
- Instructions separate from the courier note? (Default: separate.)

*Screenshot:* `D:/dev-cache/temp/claude/D--workspace-azkar/11fcc69a-fe2e-40db-a8fa-f1a5dd6e94d8/scratchpad/figma126/126-437_customer-service-order.png`

### `126:507` customer-service-tracking — L

*Who:* A customer, straight after placing, or from the Orders tab.

*What:* Track a service order:

- 'Order #8842', provider • category, and an IN PROGRESS status pill.
- 'Estimated completion: Tomorrow, 2:00 PM'.
- A five-step timeline: Order Placed → Provider Accepted → In Production → Ready for Delivery → Completed.
- A provider contact card with a chat button.

*Reached from:* Opened from ServiceOrderScreen on success (pushReplacement), from MyOrdersScreen for kind SERVICE (Orders tab, CustomerNavBar.ordersIndex), and from a push notification per status. The chat button opens the generalised customer chat screen on the store thread once shop chat ships. Back returns to Orders.

**Every element, and where its data comes from**

- Header: back, 'Track Service Order' (18 bold), overflow (undefined; use it for 'Cancel order' while PLACED, and Help).
- 'Order #8842' (18 bold). No human order number exists: server ids are UUIDs, and the client shows shortId, the first 8 characters (order_models.dart:284). '#8842' cannot be produced; offline mode's '#4521' raises the same open question.
- 'Al Fakhry Press • Printing' (11 muted): storeName plus the store's service category, snapshotted on the order.
- Status pill 'IN PROGRESS' (brandSoft bg, brand 11 SemiBold). Labels depend on the order's kind:
  - PLACED: 'Waiting for provider'.
  - ACCEPTED / PREPARING: 'In progress'.
  - READY: 'Ready for pickup' or 'Ready for delivery'.
  - PICKED_UP: 'On the way'.
  - DELIVERED: 'Completed'.
  - CANCELLED: 'Declined' or 'Cancelled'.
- Estimated completion card (white, border, radius 16, padding 16; 24px brand clock; 'ESTIMATED COMPLETION' 11 SemiBold muted; 'Tomorrow, 2:00 PM' 14 bold).
  Data: the new orders.estimated_ready_at, formatted relatively ('Today, 5:00 PM', 'Tomorrow, 2:00 PM', 'Thu 14 Sep').
  Before acceptance, show the offer's turnaround range with 'confirmed once the provider accepts'.
  For delivery orders this is when the work is ready, not when it arrives. Label it 'Ready by'; once PICKED_UP, the existing tracking ETA (GET /api/tracking/orders/{id}/eta) takes over.
- 'ORDER STATUS' and the timeline card. Each row has a 16px dot (done: filled #10b981; current: brand ring; pending: grey outline) and a 14 SemiBold label (pending rows in faint).
  Rows: Order Placed, Provider Accepted, In Production, Ready for Delivery, Completed.
  Data: GET /api/orders/{id}/history (OrderStatusHistory status, changed_by, changed_at, note; OrderController.java:321), mapped PLACED, ACCEPTED, PREPARING, READY, DELIVERED.
  Gaps in the design:

  - Delivery orders need a PICKED_UP 'Out for delivery' row.
  - Pickup orders must read 'Ready for pickup'.
  - A declined order needs a terminal row with its cancelReason.
- Provider card (white, border, radius 16, padding 12): 40px round logo, 'Al Fakhry Press' (14 bold), 'Support Representative' (11 muted), and a chat button (38px brandSoft circle, brand message-square glyph).
  'Support Representative' is wrong: this is the provider's shop, not YouDrop support.
  The button should open a customer↔shop thread, and shop chat does not exist yet. app-notification's chat is order-scoped and customer↔rider only: ChatConversation ('The merchant is deliberately not in it'), ChatParticipantRole CUSTOMER/RIDER, opened only by order.rider_assigned.
  The shop chat plan (V22__store_chat.sql, GET /api/chat/stores/{storeId}/conversation; docs/figma-added-designs.md:1066-1069) has no code in any branch or worktree as of 2026-09-12. The only trace is a ShopChatActionBuilder placeholder at wt-dekkane store_page_screen.dart:16.
- What the frame omits:
  - The customer's uploaded files and instructions.
  - Fulfilment details: pickup address and hours, or delivery address.
  - Price summary and payment.
  - Cancel while PLACED.
  - The rider map after pickup (OrderTrackingPanel).
  - Rating the provider after completion (POST /api/stores/{id}/reviews).

**Existing code that already covers part of it**

- clients/apps/mobile_app/lib/src/order_details_screen.dart, OrderDetailsScreen (26).
  - GET /api/orders/{id} (96).
  - Stepper PLACED/ACCEPTED/PREPARING/PICKED_UP/DELIVERED, with READY folded into Preparing (353-381).
  - Tracking panel (299-305), rider rating (149-176), items (620-704), shop card (708-778), receipt (806-921), Reorder (183-245).
- clients/apps/mobile_app/lib/src/order_tracking_panel.dart, OrderTrackingPanel (39).
  - Hidden once DELIVERED or CANCELLED (120-121).
  - Map, and GET /api/tracking/orders/{id}/history (233).
  - Live position on topic /topic/orders/{id}/position (147).
  - ETA from GET /api/tracking/orders/{id}/eta, whose reasons include NO_DESTINATION (tracking_models.dart:32-47).
  - 'Message the rider' appears only once a rider is assigned (795-818).
- clients/apps/mobile_app/lib/src/my_orders_screen.dart opens OrderDetailsScreen (115). customer_chat_screen.dart: CustomerChatScreen(api, orderId), via GET /api/chat/orders/{orderId}/conversation.
- services/order-manager/.../api/OrderController.java: GET /{id} (316), GET /{id}/history (321), POST /{id}/cancel (329). OrderService.historyOf (414).
- services/app-notification/.../domain/ChatConversation.java: order_id, customer_id and rider_id NOT NULL; isParticipant checks customer or rider (79-81).
  service/ChatService.java: openForRider (84).
  event/OrderChatLifecycleListener.java: opens a thread on order.rider_assigned, closes it 2 hours after delivered, and at once on cancelled.
  Migrations: V21__order_chat.sql.
- clients/packages/delivery_core/lib/src/api/chat_api.dart: conversationForOrder (49); no store method. models/chat_models.dart: ChatRole customer/rider/unknown.
- services/product-service/.../api/StoreController.java: POST /{id}/reviews (453-462), accepted only for delivered orders.

**Missing in the clients**

- ServiceOrderTrackingScreen (mobile_app):
  - Header with the shortId until a human number exists; store • category.
  - Status pill by kind; estimated completion card.
  - Timeline built from history, with a Declined terminal row and PICKED_UP for delivery.
  - Provider card with chat, hidden until shop chat ships; stores expose no phone to call.
  - Files and instructions section.
  - Fulfilment block: for pickup, address, hours and 'Show this order number when you collect'; for delivery, the address plus OrderTrackingPanel from READY.
  - Summary and payment; Cancel while PLACED (from availableActions); Rate provider after completion.
- MyOrdersScreen opens ServiceOrderTrackingScreen for kind SERVICE; list rows show a 'Service' chip and the service status label.
- OrderApi.statusHistory(orderId) for GET /api/orders/{id}/history (no client method exists; order_api.dart only reads tracking history), plus a StatusHistoryEntry model.
- ChatApi.conversationForStore(storeId), once shop chat lands.

**Missing in the backend**

- order-manager: OrderResponse gains fulfilment, estimatedReadyAt, a serviceCategory snapshot and an attachments summary. kind and the history endpoint already exist.
- app-notification, after shop chat: the store thread opens from the tracking screen with the order reference in the first message. No schema change by default. If the owner wants a hard link from a STORE thread to the order, that migration is the first free number after shop chat's V22 and neighbourhood chat's V23, i.e. V24.
- notifications-manager: service wording per status (see the architecture section).
- product-service: nothing; reviews come from order.delivered.

**Design-system pieces to reuse**

- OrderDetailsScreen sections (items, shop card, receipt)
- OrderTrackingPanel
- The shared order status palette; StoreAvatar
- CustomerChatScreen, generalised for store threads when shop chat ships
- YdCard, YdBadge (status pill)
- DeliveryAccent.positive for done dots, brand for the current dot

**Strings** (prefix `svc`; each needs en and ar)

- svcTrackTitle: 'Track service order'; svcOrderNumber: 'Order #{ref}'
- svcStatusWaiting: 'Waiting for provider'; svcStatusInProgress: 'In progress'; svcStatusReadyPickup: 'Ready for pickup'; svcStatusReadyDelivery: 'Ready for delivery'; svcStatusOnTheWay: 'On the way'; svcStatusCompleted: 'Completed'; svcStatusDeclined: 'Declined'
- svcEstimatedCompletion: 'Estimated completion'; svcReadyBy: 'Ready by'; svcEstimateAfterAccept: '{range}, confirmed once the provider accepts'
- svcTodayAt: 'Today, {time}'; svcTomorrowAt: 'Tomorrow, {time}'
- svcTimelinePlaced: 'Order placed'; svcTimelineAccepted: 'Provider accepted'; svcTimelineInProduction: 'In production'; svcTimelineReadyPickup: 'Ready for pickup'; svcTimelineReadyDelivery: 'Ready for delivery'; svcTimelineOutForDelivery: 'Out for delivery'; svcTimelineCompleted: 'Completed'
- svcDeclinedReason: 'Declined by the provider: {reason}'
- svcProviderRole: 'Service provider' (design: 'Support Representative')
- svcChatWithProvider: 'Chat with {name}'; svcYourFiles: 'Your files'
- svcShowNumberAtPickup: 'Show this order number when you collect'; svcRateProvider: 'Rate {name}'

**Tests that should prove it**

- Widget:
  - History [PLACED, ACCEPTED, PREPARING] renders Placed and Accepted done, In production current, Ready and Completed pending.
  - A pickup order says 'Ready for pickup'.
  - A delivery order adds 'Out for delivery' after PICKED_UP and mounts OrderTrackingPanel.
  - CANCELLED with PROVIDER_DECLINED renders 'Declined by the provider: {reason}' and no estimate card.
  - The estimate formats today, tomorrow and later dates in the device locale.
  - The chat button is hidden without a store-chat API; Cancel shows only while PLACED.
  - RTL.
- Widget: MyOrdersScreen opens ServiceOrderTrackingScreen for kind SERVICE and OrderDetailsScreen otherwise.
- Java: OrderResponse for a SERVICE order carries fulfilment and estimatedReadyAt; after a service accept, history lists both ACCEPTED and PREPARING.
- API scenario: take an order through to Completed; a review for it is accepted.

**Questions**

- Human-readable order numbers ('#8842')? (Default: the existing shortId. Decide together with offline mode.)
- Is the estimated completion computed (default: accept time + the offer's maximum turnaround) or entered by the provider at accept?
- Before shop chat exists: hide the chat button (default) or offer something else?
- How is a pickup verified? (Default: the customer shows the order number; no code in v1.)

*Screenshot:* `D:/dev-cache/temp/claude/D--workspace-azkar/11fcc69a-fe2e-40db-a8fa-f1a5dd6e94d8/scratchpad/figma126/126-507_customer-service-tracking.png`

## Architecture: where the marketplace lives

### Decision

Build the services marketplace inside the services that already own its pieces, with no new microservice, no new realm role and no new ingress prefix.

- product-service: a service provider is a MERCHANT that owns a Store with the new vertical SERVICES and a service category. Each offer is a Product plus a one-to-one service_terms row (pricing type, unit, turnaround, fulfilment modes, file policy), reusing images, option groups and server pricing.
- order-manager: a service order is an Order of kind SERVICE with a fulfilment of DELIVERY or PICKUP. It runs on the existing status machine, with labels chosen by kind and two narrow additions: accepting moves straight into production, and a merchant 'collected' step takes a pickup order from READY to DELIVERED.
- onboarding-service: providers apply as MERCHANT with businessType SERVICES in the details map.
- accounting-service: settles service orders on order.delivered like any shop order. It learns that a merchant can hold pickup cash.
- notifications-manager: gains service wording.
- app-notification: reuses shop chat once that ships.

### Why

- Memory.
  - The node is documented as 8 cores / 24 GB (deploy/k3s/README.md:3-6). The manifests' memory limits already add up to about 24.7 GiB across both namespaces and the cluster add-ons.
  - Each namespace runs 13 Spring services at 512Mi limits, plus config-server, Keycloak and the data layer, under deliberately cramped JAVA_OPTS (configmap-common.yaml:35: MaxRAMPercentage=70, SerialGC, C1 only).
  - Commit cfc7009 put those flags back after switching to G1 took the node down within hours: 'the box could not carry twenty-two G1 heaps'. Nothing alerts on memory.
  - A new service is two more JVMs (dev and qa) and another 1 GiB of limits.
- Cost per service.
  - About 11–14 edits: module, root pom, CI caller with its permissions block, services.yaml block, overlay images on develop/qa, ingress template plus render-overlays.sh, infra/traefik routes.yml, compose stacks.
  - Postgres init 01/02/03, plus the same SQL run by hand in both namespaces and a busrefresh.
  - A Vault bootstrap.sh line and configmap URLs.
  - Precedent: staff-service was rejected on exactly this cost (docs/MERCHANT_SUITE_SPEC.md:34-41). The three services that spec did accept (inventory, pos, reporting) have still not been created (no directories, no git history). The platform has not absorbed the services it already approved.
- The domain already lives there.
  - A service shop needs everything a Store has: name, logo and cover, tagline, description, hours with closesAt, pin, delivery radius and zone terms, rating from reviews, verified flag, favourites, publish/suspend.
  - An offer needs everything a Product has: a USD price, presigned images with thumbnails, the publish rule, and option groups with signed deltas priced by POST /api/products/{id}/price.
  - A service order needs everything OrderService.place and applyTransition already do: catalog-priced lines, zone fee, promo, the payment gate, merchant accept/cancel, dispatch at READY, the rider board, settlement on order.delivered, reviews through reviewable_orders, cross-sell lines, notifications and the chat lifecycle.
  - All of that downstream work is keyed on order.* events from order-manager.
  - A separate service would have to duplicate it, or emit events nobody consumes. The POS analysis turned 'emits no order.* event' into a reason to isolate pos-service (MERCHANT_SUITE_SPEC.md:20-23). Services want the opposite.
- The differences are small and additive:
  - A pickup fulfilment.
  - Customer file attachments.
  - Service terms on the offer.
  - An accept that moves into production.
  - A 'collected' step for pickup.

  None needs an aggregate outside Order or Store.

### Rejected options

**(b) A new services-service microservice owning provider profiles, offers, service orders and attachments.** Rejected on the memory and deploy evidence above, and on duplication:

- YouDrop Delivery would still need order-manager, because dispatch and the rider board read orders.
- It would need its own copy of store data (name, pin, zones), exactly the store cache that sank staff-service.
- Its orders would not settle (accounting-service settles only order.delivered), would not be reviewable (product-service's projection reads order.delivered), and would not be notified.
- The one argument for it, that order-manager is a separate repository and so a two-repo release, applies equally here: delivery still goes through order-manager.

**(a′) Service orders as their own table in product-service, next to the offers.** Rejected. product-service cannot see payments, dispatch or settlement. It would re-implement OrderService.place and bypass the payment gate that OrderService.applyTransition enforces (623-636).

**(a″) New OrderStatus values: IN_PRODUCTION, COMPLETED, DECLINED.** Rejected.

- chk_order_status (V10__orders.sql:31-32) and the rider board's partial index both key on the existing values.
- Installed apps parse an unknown status as PLACED (order_models.dart OrderStatus.fromWire), so a completed order would read 'Placed'.
- accounting-service, product-service and app-notification listen specifically for order.delivered and order.cancelled.

Mapping labels by kind gives the design's words without these risks.

**(a‴) A new onboarding Kind SERVICE_PROVIDER, or a new realm role.** Not the default. Kind maps to the realm role every product and store endpoint checks (OnboardingApplication.Kind.liveRole), so a new kind would still map to MERCHANT. It costs:

- V46 CHECK changes (chk_application_kind in V32; both auto-approval CHECKs in V43).
- An AutoApprovalPolicy default and new ProvisionAccount / CreatePartnerRecord arms.
- Client OnboardingKind and portal filters.

Its only benefit is a separate auto-approval switch and review queue. That is an owner question.

**(a⁗) Service offers in the multi-shop basket.** Rejected.

- Each service order carries its own file and instructions, waits on a provider's accept or decline and a multi-day turnaround, and may be a pickup.
- A unified delivery for items ready hours or days apart is not a real saving.

Service orders get their own one-line checkout, and the planned CheckoutService must refuse SERVICES products.

### The service order on the existing state machine

| Design label | Order status | Who / endpoint | Notes |
|---|---|---|---|
| New | PLACED | customer: POST /api/orders (Idempotency-Key) | Provider sees NEW. The customer may cancel while PLACED. |
| Declined | CANCELLED, reason PROVIDER_DECLINED: {reason} | merchant: POST /api/orders/{id}/cancel | payments.releaseOnCancel. order.cancelled carries cancelReason. |
| Provider accepted | ACCEPTED | merchant: POST /api/orders/{id}/accept | For kind SERVICE the same call continues to PREPARING (two history rows) and stamps estimated_ready_at = acceptedAt + turnaroundMaxHours. |
| In production | PREPARING | automatic after accept (POST /prepare stays valid) | Push suppressed for SERVICE (it follows accept instantly). |
| Ready for pickup / Ready for delivery | READY | merchant: POST /api/orders/{id}/ready | DELIVERY: DispatchService.chooseFor as today. PICKUP: no dispatch, excluded from rider/fleet boards and partner jobs. |
| Out for delivery (not drawn) | PICKED_UP | rider: POST /pick-up | DELIVERY only. |
| Completed | DELIVERED | rider: POST /deliver (DELIVERY); merchant: new POST /api/orders/{id}/collected (PICKUP, READY → DELIVERED) | captureOnDelivery marks CASH COLLECTED. order.delivered feeds settlement, reviewable_orders and delivered_order_lines. |

A pickup order goes PLACED → ACCEPTED → PREPARING → READY → DELIVERED. A delivery order adds PICKED_UP between READY and DELIVERED, exactly as a shop order does today. No new status exists, so installed apps, CHECK constraints and every `order.*` listener keep working.

### Topic by topic

#### Provider signup and approval

- Kind stays MERCHANT, with details.businessType = 'SERVICES' plus serviceCategory and area. The merchant wizard already sends businessType (partner_application_screen.dart:592-594, values at 73-84), and details is free-form jsonb, 'the client's to evolve'.
- Realm roles: MERCHANT, plus APPLICANT while pending. No new role. Publishing a product is already refused while APPLICANT (ProductController.java:163). Store publish does not check APPLICANT (StoreController.java:406-407); that is harmless, because nothing in the store can be published.
- Auto-approval follows the MERCHANT switch (AutoApprovalPolicy, per kind; default off). A separate switch would need a new Kind (V46).
- Entry points: the signed-in path (POST /api/onboarding/applications/mine, AccountOnboardingController.java:88) from a new ProfileDrawer row. No become-a-partner entry exists for a signed-in customer today. The open path through PartnerChoiceScreen or the Google 'Seller' answer stays available.
- Store creation: nothing is created at approval; CreatePartnerRecord deliberately creates no store for merchants. The provider app creates the SERVICES store with POST /api/stores from the application details, before the first offer. Otherwise requireStoreFor auto-creates a published RESTAURANT called 'My Store' (StoreService.java:466-480).
- Documents: the same kinds as merchants (National ID, commercial registration). Reviewers can approve past missing ones with acknowledgeDocumentIssues (OnboardingService.java:292-317).
- Routing: homeFor puts MERCHANT above customer (home_route.dart:64-70), so a customer who becomes a provider needs a role switch. The preferred-role rule homeFor already honours (48-59) supports one.

#### The provider app experience

- MerchantShell 'services mode', decided by the owner's store vertical: Dashboard (126:51) / Orders (126:200) / Offers (list plus 126:133) / Settings. POS and Inventory are hidden; merchant_shell.dart already computes visible tabs per access (195-202). The portal merchant rail gets the same substitution without reordering, so jump(2) still means Orders.
- 'This Week' = orders placed in the rolling last 7 days: GET /api/orders/merchant/summary?days=7, window.orders (TradingSummaryService Totals 223).
- 'Rating' = Store.rating / ratingCount, 'New' when null. It only moves once completed orders are reviewed, which is why pickup completion must emit order.delivered.
- 'Active Offers' = ACTIVE products, counted through a new ?status filter on GET /api/products/mine.
- The customer six-tab bar drawn on the provider frames is not implemented. Role-switch rows replace it.

#### The customer Services tab and service search

- CustomerNavBar goes to six destinations: servicesIndex 3, ordersIndex 4, accountIndex 5, tabCount 6. YdBottomNav accepts any count, about 53dp per item on a 360dp phone. CustomerShell._tabAt's default branch renders an empty box, so a missing case fails silently; add a test for it.
- Search:
  - Providers: GET /api/stores?vertical=SERVICES&search=.
  - Offers: GET /api/products/services?search=&serviceCategory=, a new literal path under the already-routed /api/products.
- Isolation ships first:
  - StoreRepository.findStorefrontWithStatus lists every vertical when none is given.
  - Installed apps map an unknown vertical to restaurant (StoreVertical.fromWire).
  - Five pickers iterate StoreVertical.values.

#### The provider page

- StoreResponse already carries cover, logo, tagline, description, rating, ratingCount, availability, closesAt, address and pin. Reviews (GET /api/stores/{id}/reviews) and hours exist; reviews have no client method yet.
- Distance is a client haversine from the address pin. Verified = verifiedLocal, whose setter exists only in the dekkane worktree. Share is omitted in v1.

#### Order placement

- A separate one-line checkout, not the basket (see rejected option a⁗). The client builds it on the in-flight OrderSubmission, whose own comment tells successors to produce one OrderSubmission per order and send it through OrderApi.place.
- Quantity is a number of packs. The stepper shows qty × unitSize ('500 cards'), and OrderLineRequest's @Max(99) caps the packs. PER_UNIT offers such as sqm use unitSize 1. A per-card price like $0.025 does not fit numeric(12,2).
- Options: the existing groups ('Paper type' is a required single choice), priced by POST /api/products/{id}/price and snapshotted into order_items.selected_options (V12).
- File upload lives in order-manager, because the order decides who may read the file: its merchant, its customer, and back office.
  - The customer presigns before placement and confirms; placement then references the fileIds.
  - order-manager adopts platform-storage (today only product-service and onboarding-service use it).
  - New FilePurpose ORDER_ATTACHMENT (private), and content types per purpose; StorageService.presignUpload knows a single image list today, and onboarding overrides it to add PDF.
  - Default limits: 10 MB (StorageProperties), PDF/JPEG/PNG, three files. Unattached files are swept after 24 hours.
- Instructions get their own field, serviceInstructions (up to 1000 characters). PlaceOrderRequest.notes (up to 500) remains the door and courier note.
- Delivery fee:
  - DELIVERY: applyStoreTerms unchanged (served, minimum and fee from the store's zone terms; the store pin becomes the pickup point).
  - PICKUP: no fee, no delivery address (V35 relaxes delivery_address NOT NULL behind a CHECK), no zone check; acceptsOrders and the minimum still apply.
  - Express is refused for SERVICE. Fee waivers apply to DELIVERY only. Promo codes work as for shops.
- Idempotency: fulfilment, attachmentFileIds and serviceInstructions join PlaceOrderRequest.fingerprint(), which lists its fields explicitly (OrderDtos.java:249-251 on feat/order-idempotency).
- Estimated completion: turnaround is snapshotted onto the line at placement; at accept, estimated_ready_at = acceptedAt + turnaroundMaxHours.

#### Payment methods and cash rules

- Only CASH completes today: delivery.ordering.payment-methods is CASH, and only a DEV card provider exists. Delivery orders: the rider collects, as today.
- Pickup orders: the provider collects at the counter, and order-manager marks the payment COLLECTED at DELIVERED (Order.transitionTo). accounting-service's OrderEventListener, however, only knows a RIDER cash holder. With no rider it records 'the collection against the customer, which overstates their account' (OrderEventListener.java:136-149). cash_float only allows RIDER and PROVIDER holders (V42:73).
- So accounting V52 adds a MERCHANT holder kind. Pickup cash is then attributed to the provider, whose statement nets the cash they hold against their share: they owe the platform its commission.
- No deposits or prepayment (there is no live card provider); the provider can decline. The gift rule refusing CASH does not apply, because services are not giftable in v1.

#### Settlement and commission

- order.delivered for kind SERVICE settles exactly like CATALOG:
  - The payee is merchantId; the listener special-cases only kinds starting with BUTLER (OrderEventListener.java:88-95).
  - Merchant commission = goods × delivery.ordering.commission-percentage (12.5; one global value, no per-vertical or per-merchant rate; SettlementService.java:86-87, 361-366).
  - Carrier or rider legs exist only for DELIVERY. A PICKUP order's deliveryFee is 0, so no leg is written; the in-house-fleet test already settles a null carrier.
  - Delivery points are skipped with no carrier or rider (PointsService.java:109-116).
- A different services commission would need kind on the settlement path and a rate map. That is code only, but TradingSummaryService reads the same key for the dashboard's commission %, so both must change together.

#### Dispatch

- DELIVERY service orders dispatch at READY through DispatchService.chooseFor(merchantId), honouring the merchant's pinned carrier and fallback policy. They appear on /api/orders/available and go claim → pick-up → deliver.
- There is no timeout or re-offer for an unclaimed READY order (order-manager has no @Scheduled code). The provider's card should say 'Waiting for a rider since…'.
- PICKUP orders are never dispatched. They are excluded from findAvailableForRiders and findAvailableFor (both read READY with no rider), from the partner jobs API, and from the customer map. order-tracking still projects them but has no dropoff (EtaService answers NO_DESTINATION), so the tracking panel must not be shown for pickup.

#### Notifications per status

- Today: notifications-manager's OrderEventListener sends customer and merchant templates for placed, status_changed, rider_assigned, delivered and cancelled (V10/V11/V17/V18). Everything is English (default locale en; no Arabic templates). statusMessage is hard-coded restaurant wording (OrderEventListener.java:194-202: 'The restaurant has accepted your order.').
- Needed: read kind and fulfilment from the snapshot and choose service wording:
  - placed, to the merchant: 'New service order: {offer}'.
  - ACCEPTED: '{store} accepted your order — ready by {time}'.
  - PREPARING: no push for SERVICE.
  - READY, pickup: 'Ready to collect at {store}'. READY, delivery: 'Ready — a rider is being assigned'.
  - delivered, pickup: 'Collected — rate {store}'.
  - cancelled by the provider: 'Declined by {store}: {reason}'.

  New template rows go in notifications-manager V19 (next free on main; no branch claims it).

#### Chat with the provider

- The tracking frame's button means a customer↔shop thread. Order chat cannot serve it: it is customer↔rider only and opens on order.rider_assigned (OrderChatLifecycleListener).
- As of 2026-09-12 no shop-chat code exists in any branch or worktree; the plan is app-notification V22__store_chat.sql plus /api/chat/stores/{storeId}/conversation. Services add nothing to it: open the store thread from the order with the order reference in the composer, and the planned merchant inbox serves providers. Until it ships, the button is hidden.
- StoreResponse exposes no merchantId, so shop chat's ownership lookup must be internal, as its plan already notes.

#### Back office

- Approving providers: the existing OnboardingScreen, with businessType and serviceCategory shown in the Category column, plus approve/decline/suspend. Suspension revokes MERCHANT, which also takes down a goods store on the same account.
- Verified badge: PUT /api/stores/{id}/verified-local from the dekkane work, plus a portal toggle (none exists).
- Offer moderation does not exist; CatalogScreen is read-only. Add a BACKOFFICE archive with a recorded reason (product-service V36__offer_moderation.sql audit table).
- Service orders: the Orders Ledger (DashboardScreen) gains kind and fulfilment filters (GET /api/orders?kind=), and support cancel exists. Opening a customer's file from back office should leave an audit row; chat's TranscriptAccess is the precedent.
- Disputes and refunds do not exist anywhere (Payment REFUNDED is never set; OrderService calls refunds 'a separate flow that does not exist yet'). They are out of scope and listed as an owner question.

### What existing endpoints and screens would show or break once a service store exists

| Surface | What happens today | What the build does |
|---|---|---|
| GET /api/stores with no vertical (Home, ShopsListingScreen, HyperlocalScreen, CategoriesScreen count) | Would list print shops among restaurants | Exclude SERVICES by default (V33 slice) |
| GET /api/stores/nearby | No vertical filter at all | Exclude by default; vertical/serviceCategory via NearbyFilters (dekkane) |
| GET /api/stores/neighborhoods | A provider's neighbourhood becomes a dekkane chip | Exclude SERVICES |
| GET /api/products (catalog-wide, back-office CatalogScreen) | Lists offers as products | Exclude by default; /api/products/services for offers |
| GET /api/categories/chips | A SERVICES row would add a Home chip | Leave SERVICES out |
| Installed apps: StoreVertical.fromWire | SERVICES parsed as restaurant; an old merchant app would save it back as RESTAURANT | Server exclusion + vertical immutability (422) |
| GET /api/orders/merchant and /merchant/summary | Include service orders (correct: same merchant) | Optional kind filter for mixed accounts |
| GET /api/orders/available, findAvailableFor, partner jobs | Would offer READY pickup orders to riders | Exclude PICKUP (V35 index + query) |
| order-tracking OrderEventListener | Projects every snapshot with a merchantId; pickup has no dropoff | Harmless; client hides the map for pickup |
| notifications-manager | Restaurant wording for print jobs | Kind-aware wording (V19) |
| accounting-service | Pickup cash with no rider misattributed to the customer | MERCHANT cash holder (V52) |
| product-service OrderEventListener | Reviews and cross-sell only on order.delivered | Pickup completion emits order.delivered |
| MerchantDashboardScreen / POS / Inventory | Goods concepts (stock, till, "ready for pickup" by rider) | Services mode swaps in ServiceDashboardScreen and hides POS/Inventory |
| whatsapp-service | Messages only WhatsApp-origin orders | Unaffected |

### Collisions with the work in flight

Where each feature lives, as read on 2026-09-12:

- Most of the work is uncommitted changes in `D:/workspace/wt-*` worktrees.
- Order-manager has two branches: `feat/order-idempotency` (V31) and `feat/rider-performance-daily`.
- Shop chat, neighbourhood chat, gift hub/checkout, multi-shop basket, demand heatmap and payroll have no code in any branch or worktree. They exist only as plans in `docs/figma-added-designs.md`.

| In-flight feature | What it changes | What services must do |
|---|---|---|
| Offline mode + Idempotency-Key (wt-offline; order-manager feat/order-idempotency, V31) | OrderApi.place(OrderSubmission) replaces named parameters; fingerprint() lists fields explicitly | Build service orders as OrderSubmission; add fulfilment/attachments/instructions to toBody and fingerprint; the outbox never queues service orders |
| Multi-shop basket (plan only; checkouts table and POST /api/orders/quote proposed) | One Cart, one order per shop | CheckoutService refuses SERVICES products; reuse the quote endpoint for the service order screen when it exists |
| Gift hub / gift checkout (plan only; gift fields on orders, CASH refused for gifts) | Gift fields on PlaceOrderRequest | No gifting of services in v1; placement rejects gift fields on SERVICE |
| Neighbourhood dekkane (wt-dekkane, uncommitted) | NearbyFilters record; PUT /api/stores/{id}/verified-local; the profile save still nulls neighborhood | Add vertical/serviceCategory to NearbyFilters; reuse verified-local; fix the neighborhood wipe before using it as the provider area |
| Shop chat (plan only, app-notification V22) | Customer↔shop threads, merchant inbox | Tracking and provider screens call it when it lands; no services migration by default (V24 if an order link is wanted) |
| Neighbourhood chat (plan only, app-notification V23) | Community rooms | None |
| Merchant Blitz (wt-blitz, product-service V29) | Catalog scans | None; services use V33–V36 |
| Carrier cash custody (wt-carrier-cash, accounting V50) | cash_float gains carrier_ref | V52 MERCHANT holder builds on V50's shape |
| Carrier riders directory / attendance / payroll | Carrier portal, order-tracking V15 | None |
| Merchant demand heatmap (plan only) | Proposed order-manager V31 (collides with idempotency, not with us) | None |
| l10n ARB files (changed in 5 worktrees) | Merge hotspot | Prefix svc*, one commit per slice, regenerate after rebasing |

## Build plan

Slices in dependency order. Migration numbers are inside the pre-assigned ranges (product-service V33+, order-manager V35+, onboarding-service V46+, accounting-service V52+); app-notification only after shop chat's.

| # | Slice | Size | Services / packages | Migrations | l10n | Depends on | Parallel with |
|---|---|---|---|---|---|---|---|
| 0 | Decision gate | S | docs only | none | none | nothing | can run beside slice 1 |
| 1 | SERVICES vertical and storefront isolation | M | product-service; delivery_core; mobile_app / delivery_merchant / delivery_portal pickers | product-service V33__services_vertical.sql | svcCategory* | dekkane nearby filters merged, or coordinated | nothing; everything else waits on it |
| 2 | Service offers in product-service | L | product-service; delivery_core (contract only) | product-service V34__service_terms.sql, V35__product_paused.sql | none (server) | 1 | slice 3 |
| 3 | Provider onboarding and store bootstrap | M | onboarding-service; mobile_app; delivery_core; delivery_portal | none by default (onboarding V46 only if the owner picks a new Kind) | svcSignup*, svcOfferYourServices, svcSwitchTo* | 1 | slice 2 |
| 4 | Service orders in order-manager | XL | order-manager (own repo, docker.io tag) | order-manager V35__service_orders.sql | none (server) | 2 (ProductResponse.service contract); feat/order-idempotency V31 merged | slice 5 |
| 5 | Order attachments | L | platform-storage (library release); order-manager; deploy (MinIO bucket, Vault, config rows in dev and qa) | order-manager V36__order_attachments.sql | none (server) | platform-storage release; slice 4 schema for the order link | slice 4 |
| 6 | Pickup cash in settlement | M | accounting-service | accounting V52__merchant_cash_holder.sql | none | 4 (fulfilment on the snapshot); carrier cash custody V50 merged | slices 7 and 8 |
| 7 | Service notifications | M | notifications-manager | notifications-manager V19__service_order_templates.sql | server templates (English only today; Arabic templates are an existing platform gap) | 4 | slices 6 and 8 |
| 8 | delivery_core contracts | M | delivery_core | none | none | agreed DTOs of 2, 4, 5 (can be written against them); wt-offline OrderSubmission merged | slices 6 and 7 |
| 9 | Provider screens | XL | delivery_merchant; mobile_app merchant_shell; delivery_portal portal_shell | none | svcDashboard*, svcOffer*, svcPricing*, svcTurnaround*, svcFulfilment*, svcOrders*/svcTab*/svcDecline* | 8 | slices 10 and 11 |
| 10 | Customer screens | XL | mobile_app | none | navServices, svcHi*/svcSearch*/svcNearYou, svcTab*/svcFromPrice, svcOrderService*/svcUpload*, svcTrack*/svcStatus*/svcTimeline* | 8 | slices 9 and 11 |
| 11 | Back office | M | delivery_portal; product-service; order-manager | product-service V36__offer_moderation.sql | portal svcAdmin* | 2, 4, 5; dekkane verified-local | slices 9 and 10 |
| 12 | Shop chat hookup | S | mobile_app; delivery_merchant | none by default (app-notification V24 only if an order link is wanted) | svcChatWithProvider | shop chat shipped (plan: app-notification V22) | any time after it lands |
| 13 | End-to-end proof | M | dev and qa; mobile_app integration_test; docs/surface-checklist.md | none | Arabic review | 1–11 | nothing |

Order of work: 0 and 1, then 2 and 3 in parallel, then 4 and 5 in parallel (8 can start against the agreed DTOs), then 6, 7 and 8, then 9, 10 and 11 in parallel, then 13. Slice 12 waits for shop chat.

### Slice 0: Decision gate (S)

Record the owner's answers, or these defaults, in docs/. Download the Figma image assets (banner illustration, covers, offer photos, avatars) before the MCP URLs expire around 2026-09-19; they are placeholders.

*Tests:* None.

### Slice 1: SERVICES vertical and storefront isolation (M)

Server:

- Store.Vertical.SERVICES and Store.ServiceCategory; stores.service_category with its CHECKs; StoreRequest.serviceCategory.
- A store cannot move into or out of SERVICES (422).
- SERVICES excluded by default from findStorefront, nearby, distinctNeighborhoods, findActiveCatalog and category chips.
- New filters: GET /api/stores?vertical=SERVICES&serviceCategory= and nearby with vertical.

Client:

- StoreVertical.services and pickerVerticals, used in store_home_screen.dart:300, shops_listing_screen.dart:98, categories_screen.dart:43, store_screen.dart:640 and banners_screen.dart:767.
- ServiceCategory with labels and icons.

Must be deployed to dev and qa before any SERVICES store is created: installed apps map an unknown vertical to restaurant.

*Tests:*

- StoreServiceTest / repository tests: every exclusion; vertical immutability; the serviceCategory filter.
- V33 applies on the live seeded data.
- Dart: pickerVerticals; fromWire('SERVICES').
- Widget regression: the Home storefront is unchanged.

### Slice 2: Service offers in product-service (L)

- ServiceTerms entity with a top-level repository.
- ProductRequest/ProductResponse 'service' block and fromPrice.
- CatalogService rule: a SERVICES store requires a service block, and other stores refuse one.
- pause/resume endpoints; GET /api/products/mine?status=.
- GET /api/products/services search (plus an optional popular endpoint over delivered_order_lines).
- ProductSnapshot carries the service block.
- A DELIVERY offer needs store zones or a pin before it can be published.

*Tests:*

- CatalogServiceTest / ServiceTermsTest: the block rules, turnaround validation, fromPrice, pause/resume, the ?status count, search scoping.
- RepositoriesAreTopLevelTest stays green.
- V34 and V35 apply on data with existing products.
- The product-service suite loads no Spring context (merchant-suite deploy lesson), so verify the new beans on a dev deploy.

### Slice 3: Provider onboarding and store bootstrap (M)

- ApplicationIntake validates businessType SERVICES.
- ServiceProviderSignupScreen (126:11) on the signed-in path, plus the open-path variant.
- Entry points: the ProfileDrawer row and the PartnerChoice / Google 'Services' choice.
- On first entry, create the SERVICES store with POST /api/stores from the application details.
- Role-switch rows using homeFor's preferred-role rule.
- Portal onboarding row shows 'Services · {category}'.

*Tests:*

- Widget: validation; the submission body; pending state.
- AccountApplicationServiceTest: SERVICES auto-approval follows the merchant switch.
- StoreServiceTest: requireStoreFor returns the existing SERVICES store and never creates a restaurant.
- Portal row widget.

### Slice 4: Service orders in order-manager (XL)

- Schema and domain: OrderKind.SERVICE; fulfilment; nullable delivery_address behind a CHECK; customer_display_name; estimated_ready_at; order_items.service snapshot; the rider-board partial index.
- Clients: StoreClient reads the store's vertical; ProductCatalogClient reads the service block.
- Placement rules: one line; fulfilment allowed by the offer; PICKUP with no fee or address; STANDARD tier only; file policy; kind SERVICE.
- Lifecycle: accept moves into PREPARING and stamps the estimate; POST /api/orders/{id}/collected; READY → DELIVERED only for PICKUP; no dispatch for PICKUP; PICKUP excluded from all boards; actionsFor with COLLECTED.
- Contracts: OrderSnapshot/OrderResponse fields; the fingerprint extension; kind filters on /merchant and the back-office list.

*Tests:*

- OrderServiceTest cases listed under 126:200 and 126:437.
- The CATALOG regression suite stays green.
- V35 migration safety on existing orders.
- An API scenario against dev.

### Slice 5: Order attachments (L)

- FilePurpose.ORDER_ATTACHMENT (private) and allowed content types per purpose.
- order-manager adopts platform-storage.
- Endpoints: presign, confirm, list with short-lived GETs.
- A scheduled sweep of unattached files after 24 hours.
- Audited back-office reads.
- By hand in both namespaces: create the bucket and add credentials (Vault bootstrap.sh line).

*Tests:*

- Storage: per-purpose types (PRODUCT_IMAGE still refuses PDF).
- Attachments: presign/confirm size and type; visibility (the order's merchant, its customer, BACKOFFICE); the sweep.
- Placement: a REQUIRED file is enforced.

### Slice 6: Pickup cash in settlement (M)

- chk_float_holder gains MERCHANT.
- A CASH order with no rider and fulfilment PICKUP gets holder MERCHANT (merchantId), with the CASH_COLLECTED obligation attributed to the merchant.
- Statements show the cash the merchant holds.
- SERVICE kind settles like CATALOG.

*Tests:* SettlementServiceTest:

- A pickup service order writes no carrier or rider legs, merchant commission 12.5%, and CASH_COLLECTED attributed to the merchant.
- A delivery service order settles identically to CATALOG.
- An older event without fulfilment settles exactly as before.

### Slice 7: Service notifications (M)

- OrderEventListener reads kind and fulfilment.
- Service wording: placed (merchant), accepted with the ready-by time, READY for pickup or delivery, collected with a rate prompt, declined with the reason.
- No PREPARING push for SERVICE.

*Tests:* OrderEventListenerTest: per-status recipients and wording for SERVICE+PICKUP and SERVICE+DELIVERY; CATALOG wording unchanged; dedupe keys unchanged.

### Slice 8: delivery_core contracts (M)

Models:

- ServiceTerms, ServiceCategory, ProductStatus.paused, StoreCard.serviceCategory.
- DeliveryOrder.kind / fulfilment / estimatedReadyAt / customerDisplayName / attachments / serviceLine.
- OrderAction.collected, Fulfilment.

APIs:

- CatalogApi pause, resume, myProducts(status), searchServices.
- StoreApi.reviews and nearby(vertical).
- OrderApi.statusHistory; OrderAttachmentApi.
- OrderSubmission gains the service fields.

Export everything from delivery_core.dart.

*Tests:* Model and API tests with a fake Dio adapter; tolerant parsing of unknown kind, status and fulfilment.

### Slice 9: Provider screens (XL)

- ServiceDashboardScreen (126:51).
- ServiceOfferFormScreen and the offers list (126:133).
- ServiceOrdersScreen and the order detail with files (126:200).
- MerchantShell services mode with a bell; portal merchant rail substitution, append-only.

*Tests:*

- Widget tests per frame.
- merchant_shell wiring test for services mode.
- Portal rail test: Orders still at index 2.
- Arabic no-Latin test for every new screen.

### Slice 10: Customer screens (XL)

- Six-tab CustomerNavBar, with the Butler truck glyph.
- ServicesHomeScreen (126:285) with category and search results.
- ServiceProviderScreen (126:371).
- ServiceOrderScreen with uploads (126:437).
- ServiceOrderTrackingScreen (126:507).
- MyOrdersScreen routes by kind; rate provider.

*Tests:*

- Widget tests per frame.
- Nav bar / shell index tests.
- 320dp and Arabic truncation.
- checkout-style placement tests (one place call, Idempotency-Key, 409 PRICE_CHANGED).

### Slice 11: Back office (M)

- Verified toggle.
- Offer moderation: BACKOFFICE archive with a reason and audit row.
- Orders Ledger kind and fulfilment filters (GET /api/orders?kind=).
- Attachment viewer with audited access.
- Application row chip, if not already done in slice 3.

*Tests:*

- Endpoint role tests (BACKOFFICE only).
- Audit rows written.
- Portal widget tests for the filters and the moderation dialog.

### Slice 12: Shop chat hookup (S)

- The chat button on ServiceOrderTrackingScreen and the provider's order detail opens the store thread with the order reference.
- The merchant inbox lists the SERVICES store's threads.

*Tests:*

- Widget: the button appears only with a store-chat API and opens the store conversation.
- The merchant inbox shows the thread.

### Slice 13: End-to-end proof (M)

- Deploy order: product-service (1, 2), then order-manager (4, 5), then accounting (6), then notifications (7), then clients.
- Scenario: apply, approve, bootstrap the store, publish an offer, place a pickup order with a PDF, accept, ready, collected; confirm settlement rows and a review. Then a delivery order: dispatch, rider claim, deliver.
- Run it on a real phone, as affec00 did for goods.
- Add surface-checklist entries.

*Tests:*

- API scenario scripts.
- Integration test on a device.
- RTL sweep.
- Screenshots of all eight frames against Figma.

## Questions only the owner can answer

The build proceeds on these defaults unless the owner overrides them.

| # | Question | Default | Why this default |
|---|---|---|---|
| 1 | Which service categories launch? | Item-based only: Printing, Tailoring & alterations, Repairs, Photography prints. Cleaning, Beauty and Tutoring are hidden: they are appointments at the customer's place, and no scheduling exists. | The order flow the frames draw is make, then pickup or delivery. |
| 2 | How does a customer's garment or broken phone reach a tailor or repairer? | The customer drops it off at the shop. There is no courier leg to the provider in v1 (Butler 'Send Anything' remains an option). | No inbound delivery exists in order-manager. |
| 3 | Payment for custom work? | Cash only: paid to the provider at collection, or to the rider on delivery. No deposit. The provider can decline. | CASH is the only method that completes today (delivery.ordering.payment-methods). |
| 4 | Commission on services? | The same 12.5% as goods. | One global rate exists; a separate rate is a code change in two services. |
| 5 | Onboarding: a new kind, or MERCHANT with businessType SERVICES? | MERCHANT + businessType SERVICES. It shares merchant auto-approval and documents. | A new kind still maps to the MERCHANT role and costs V46 plus client and portal work. |
| 6 | Where does the provider work? | In MerchantShell 'services mode', plus a role switch. Not inside the customer Account tab as drawn. | homeFor already routes MERCHANT accounts there, and the merchant package holds the queue and forms to reuse. |
| 7 | Accept flow and estimated completion? | Accept moves straight into 'In production'. Estimated completion = accept time + the offer's maximum turnaround, not editable in v1. | The design has no separate start button. |
| 8 | Decline? | A picklist of reasons, stored as cancel reason 'PROVIDER_DECLINED: …' and shown to the customer. | Reuses merchant cancel from PLACED. |
| 9 | Quantity semantics? | Packs of the offer's unit size, 1–99 packs. | qty @Max(99) and numeric(12,2) unit prices. |
| 10 | Pricing entry? | USD only, with a read-only LBP preview at the platform rate. Types FIXED / PER_UNIT / FROM. No quote-on-request. | The platform stores USD and converts at one rate. |
| 11 | Customer files? | PDF, JPEG or PNG, 10 MB each, up to 3. Visible to the provider from placement; deleted 90 days after completion. | The platform-storage default cap is 10 MB. |
| 12 | Pickup rules? | No fee, no verification code (the customer shows the order number). The provider may cancel an uncollected READY order after 72 hours. | Nothing collects cash for an order nobody picks up. |
| 13 | Delivery rules for services? | Zone fee as for shops. STANDARD tier only. Promo codes allowed. Not in the multi-shop basket, never queued offline, not giftable. | Keeps service orders off every in-flight flow they do not fit. |
| 14 | Navigation? | Six tabs as drawn; Butler's glyph becomes a truck. Service stores never appear on Home. | YdBottomNav fits six at about 53dp each; truncation is tested. |
| 15 | Order numbers like '#8842'? | The existing 8-character shortId. | Shared open question with offline mode. |
| 16 | 'This Week' and 'Popular'? | This Week = orders placed in the last 7 days. 'Popular' is shown only when backed by delivered-order counts; otherwise 'Services near you'. | The platform's rule that numbers must be real (CrossSellService). |
| 17 | Verified badge? | The existing back-office-set Verified Local flag. | Every live provider is approved, so a badge they all have means nothing. |
| 18 | Chat before shop chat ships? | The button is hidden. | Order chat is customer↔rider only. |
| 19 | Misprint disputes and refunds? | Back-office cancel before completion only. No refunds in v1. | No refund or dispute flow exists anywhere. |
| 20 | Ordering while the provider is closed? | Refused, as for shops. | One availability rule platform-wide. |

## Cross-cutting

- Naming collisions:
  - In code, 'provider' already means a delivery company: DeliveryProvider, ProviderProfile, and the providerKind* l10n keys.
  - 'Offer' already means a promotion (StoreOffer) or a fee waiver (FeeWaiverController at /api/offers).

  Code vocabulary: a service shop is a Store with vertical SERVICES, ServiceTerms, OrderKind.SERVICE, and the svc l10n prefix. The UI may still say 'Provider' and 'Offer'.
- Design bugs to correct, not copy:
  - 126:285 highlights Home instead of Services.
  - 126:200 prints 1,350,000 LBP for $16.00 (should be 1,440,000).
  - 126:507 says 'Support Representative' and 'Order #8842'.
  - The Tailoring tile uses a circle-x glyph.
  - 'Same-day' and 'thousands' copy.
  - 126:437 has no address row and no payment line, and its total must be server-quoted.
  - The provider frames draw the customer tab bar.
  - Share has no backing.
  - Rating is drawn green on some frames and brand on others.
- Money: prices are USD only. LBP is always MarketRates' conversion, rounded to 1,000. Every total a screen shows comes from the server, or is guarded with expectedTotal (409 PRICE_CHANGED).
- Old app versions in the field:
  - An unknown store vertical parses as restaurant.
  - An unknown order status parses as placed.
  - The order model ignores kind.

  Server defaults (exclusion, no new statuses, vertical immutability) protect them.
- Migrations used, all within the pre-assigned ranges: product-service V33–V36; order-manager V35–V36; accounting V52; notifications-manager V19 (next free on main); onboarding V46 and app-notification V24 only if the owner chooses those options.
- Deploy: no new service, schema, role or ingress prefix. What it does need:
  - A platform-storage library release.
  - A cross-repo order-manager release (mutable docker.io tag).
  - A MinIO bucket and credentials, added by hand in both namespaces.
  - Argo deploys develop and qa, so validate on those branches.
- l10n: every key needs en and ar in clients/packages/delivery_l10n/lib/l10n/app_en.arb / app_ar.arb; regenerate the committed generated files. ICU plurals need Arabic forms. notifications-manager has no Arabic templates at all today.
- Figma: node ids 126:11–126:507 in file 4lIJm9HXkQtTQHqhBIpNfB; the six-item bar is node 130:* inside each frame. Image assets are placeholders served from expiring MCP URLs. Screenshots: D:/dev-cache/temp/claude/D--workspace-azkar/11fcc69a-fe2e-40db-a8fa-f1a5dd6e94d8/scratchpad/figma126/.
