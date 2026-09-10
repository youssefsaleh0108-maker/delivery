# Every screen and control, by surface

Derived from the source, not from clicking around — so a screen missing here is a screen
that does not exist, and a screen listed here with no tick is one nobody has driven.
**180 screens, 1091 controls.** 45 unreachable or dead. 55 reachable with no test that drives them.


## CARRIER — mobile CarrierShell (mobile_app/lib/src/carrier_*

25 screens, 137 controls.

### CarrierShell (chrome: header, bottom nav, load/error/refresh)
*The frame every carrier tab is drawn inside: company monogram + 'YouDrop Carrier' wordmark, a paused chip, five bottom tabs, and one shared refresh that fans out six concurrent calls (myCompany, myScore, carrierEarnings, carrierSummary, myRiders, forCarrier).*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/carrier_shell.dart`
- reached by: Sign in as carrier/500005 on the mobile app — main.dart lands straight here; there is no intermediate screen.
- covered by: integration_test/carrier_test.dart — drives the real cold start, the sign-in form, arrival, and asserts the error state is absent. No widget test exists for this shell anywhere in mobile_app/test.
- states: Loading: full-screen CircularProgressIndicator while _company is null. · Error: YdEmptyState icon cloud_off, title t.somethingWentWrong 'Something went wrong', message t.couldNotReachTheServer 'We could not reach the server. Check your connection and try again.' — reachable ONLY by breaking /api/delivery-providers/my-company. · Silent partial failure: score, earnings, summary, riders and orders each swallow their error — a 403 on riders renders identically to an empty fleet. No visible indication. · Header chip t.carrCompanyPaused 'Company paused — no new work is offered' when company.canTakeWork is false.

  - [ ] t.carrDashboard — 'Dashboard' — setState(_tab = 0). Shows the dashboard body.  `YdBottomNav → _YdBottomNavTab (InkWell, no Key)`
  - [ ] t.carrOrdersTab — 'Orders' — setState(_tab = 1).  `YdBottomNav → _YdBottomNavTab`
  - [ ] t.carrFleetTab — 'Fleet' — setState(_tab = 2).  `YdBottomNav → _YdBottomNavTab`
  - [ ] t.carrEarningsTab — 'Earnings' — setState(_tab = 3).  `YdBottomNav → _YdBottomNavTab`
  - [ ] t.carrSettingsTab — 'Settings' — setState(_tab = 4).  `YdBottomNav → _YdBottomNavTab`
  - [ ] (no label) pull down on any tab — Re-runs _load(): all six endpoints again. Works on all five tabs since every body is a ListView.  `RefreshIndicator (brand colour) wrapping the tab switch`
  - [ ] t.tryAgain — 'Try again' — Re-runs _load(). Only rendered when _error != null AND _company == null — i.e. only myCompany() failing; the other five calls are individually .catchError'd and fail silently.  `YdPillButton.secondary, compact, inside YdEmptyState`

### CarrierShell · Dashboard tab (_dashboard)  — no driving test
*The day at a glance: four stat tiles (t.carrActiveDeliveries 'Active deliveries' + LIVE badge, t.carrPendingOrders 'Pending orders' + WAITING, t.carrRidersOnline 'Riders on fleet' + FLEET, t.carrTodayRevenue "Today's revenue" + USD), an optional score card, and the five most recent orders.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/carrier_shell.dart`
- reached by: Sign in as carrier → lands here (tab 0). Or tap 'Dashboard' in the bottom nav.
- states: Empty orders: YdCard.bordered with t.noOrdersYet 'No orders yet' under t.carrRecentActivity 'Recent activity'. · Score card (t.carrScore 'Carrier score', t.carrCompletionRate 'Completion rate', t.carrOrdersDelivered 'Orders delivered') is omitted entirely when myScore() failed or 404s — no placeholder, the card just is not there. · Today's revenue reads $0.00 when carrierSummary() failed (caught to null) — indistinguishable from a genuinely empty day. · 'Riders on fleet' reads 0 when myRiders() 403s.

  - [ ] t.carrCoverageZones — 'Coverage Zones' / subtitle t.carrCoverageMapBlurb — 'The circles your riders work. Tap to edit.' — Navigator.push → CarrierZonesScreen(api: providerApi). This is where the frame draws a live fleet map; rider pins are deliberately absent.  `YdCard.bordered with onTap (whole card is the target; the chevron is decorative)`
  - [ ] '#{shortId}' order card ×5 (t.carrWaitingDispatch — 'Waiting for dispatch' on the unassigned ones) — Navigator.push → CarrierOrderDetailsScreen(order, cutPercentage: earnings?.cutPercentage ?? 15).  `Material + InkWell (custom _orderRow; crimson 1.5px border when unassigned)`
  - [ ] (no label) pull-to-refresh — Re-runs _load().  `RefreshIndicator`

### CarrierShell · Orders tab (_ordersTab)  — no driving test
*The dispatch board, bucketed three ways off the one loaded page of 30 orders. Defaults to the Active bucket (_ordersSegment = 1), NOT Incoming.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/carrier_shell.dart`
- reached by: Sign in as carrier → bottom nav 'Orders' (2nd tab).
- states: Empty bucket: YdCard.bordered with t.noOrdersYet 'No orders yet'. Note the chip counts still show (0) beside it. · Only 30 orders are ever loaded (forCarrier(size: 30)) — the Completed bucket is a slice of that, not history. No pagination control exists. · Rider identity on a row is the raw Keycloak ref, uppercased and cut to 10 chars — no name.

  - [ ] t.carrIncoming — 'Incoming', rendered as 'Incoming (n)' — setState(_ordersSegment = 0). Filters to !isTerminal && riderId == null. Client-side only — no refetch.  `InkWell inside Expanded + 2px underline (custom _ordersSegmentChip, no Key)`
  - [ ] t.riderTabActive — 'Active', rendered as 'Active (n)' — setState(_ordersSegment = 1). Filters to !isTerminal && riderId != null. This is the default tab.  `InkWell + underline (_ordersSegmentChip)`
  - [ ] t.carrCompleted — 'Completed', rendered as 'Completed (n)' — setState(_ordersSegment = 2). Filters to isTerminal, capped at .take(30).  `InkWell + underline (_ordersSegmentChip)`
  - [ ] '#{shortId}' order card (all rows in the shown bucket) — Navigator.push → CarrierOrderDetailsScreen.  `Material + InkWell (_orderRow)`
  - [ ] (no label) pull-to-refresh — Re-runs _load().  `RefreshIndicator`

### CarrierShell · Fleet tab (_fleetTab)
*t.carrFleetManagement 'Fleet Management' — the roster, one card per rider ref, showing what that ref is carrying now and how many drops it made in the window.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/carrier_shell.dart`
- reached by: Sign in as carrier → bottom nav 'Fleet' (3rd tab).
- covered by: integration_test/carrier_test.dart — taps the Fleet tab, asserts carrFleetManagement is on screen, and compares the rendered count and the first rider card against a live out-of-band GET /api/delivery-providers/my-company/riders. This is the only mobile carrier tab checked against the server.
- states: Count line t.carrShowingRiders '{count} riders on the fleet'. · Empty: t.carrNoRiders 'No riders on the fleet yet — the platform assigns riders after onboarding.' — NOTE this same sentence renders for a 403 and a 500, because _load() wraps myRiders() in .catchError((_) => <String>[]). · Per rider: t.carrDelivering 'Delivering #{id}' (blue) or t.carrAvailable 'Available' (green); t.carrDeliveriesToday '{count} deliveries in window' only when drops > 0. · Rider refs longer than 12 chars are uppercased and truncated with a real ellipsis (U+2026).

  - [ ] (none) — NOTHING IS TAPPABLE ON THIS TAB. Rider cards have no onTap, no Call, no Assign, no reassign — the class doc says per-rider Call/Assign and reassignment all wait on backend work. Only pull-to-refresh operates here.  `YdCard.bordered (no onTap) per rider`
  - [ ] (no label) pull-to-refresh — Re-runs _load().  `RefreshIndicator`

### CarrierShell · Earnings tab (_earningsTab)
*The crimson revenue hero, a weekly bar chart, the deliveries breakdown (gross / commission / net) and the standing payout schedule.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/carrier_shell.dart`
- reached by: Sign in as carrier → bottom nav 'Earnings' (4th tab).
- covered by: integration_test/carrier_test.dart — taps the Earnings icon (by Icons.attach_money_rounded, because the label is ambiguous with the nav item), drags up to the breakdown, and asserts the three rendered strings against a live /api/orders/carrier/earnings payload bracketed by two reads. The period pill and the bar chart are NOT driven.
- states: Hero always renders; falls back summary.window.money → earnings.earned → 0. · Weekly bar card (t.carrWeeklySummary 'Weekly summary') omitted when summary is null or has no days. Bars are labelled by 'MTWTFSS'[weekday-1]. · Breakdown card (t.carrDeliveriesBreakdown 'Deliveries breakdown') omitted entirely when carrierEarnings() failed — the screen still looks healthy. Rows: t.navOrders 'Orders', t.carrTotalRevenue 'Total revenue', t.carrCommissionPct 'Commission paid to YouDrop ({rate}%)' shown as -$x.xx, and the green band t.carrNetEarnings 'Net earnings'. · t.carrNextPayout 'Next payout scheduled' / t.carrEveryMonday 'Every Monday' is a hard-coded standing schedule, not a computed date.

  - [ ] t.carrWindowEarned — 'Earned ({days}d)', i.e. 'Earned (7d)' / 'Earned (30d)', with a keyboard_arrow_down glyph — Flips _windowDays between 7 and 30 and calls _load() — refetches ALL six endpoints, not just the summary. There is no menu: the chevron is a lie about the affordance.  `InkWell + pill Container (looks like a dropdown, is actually a toggle)`
  - [ ] (no label) pull-to-refresh — Re-runs _load(). Careful: dragging DOWN here re-fetches and discards the snapshot under test.  `RefreshIndicator`

### CarrierShell · Settings tab (_settingsTab)
*Company card, operations (zones + pause), the standing payment terms, language and the way out.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/carrier_shell.dart`
- reached by: Sign in as carrier → bottom nav 'Settings' (5th tab). The log-out button is below the fold on a phone — scroll the ListView up.
- covered by: integration_test/carrier_test.dart — reaches this tab by Icons.settings_outlined, scrolls, ensureVisible, and taps Log Out Account as its teardown. Pause/Resume, Coverage Zones and the language toggle are NOT driven.
- states: Company card omitted when _company is null (only possible transiently). · Pause/Resume row omitted entirely when _company is null. · Payments card is static text: t.carrCommissionRate 'Commission rate' → t.carrFlatFee '{rate}% flat fee' (defaults to 15 when earnings did not load), and t.carrPayoutSchedule 'Payout schedule' → t.carrEveryMonday 'Every Monday'. · Footer t.carrVersionCaption 'YouDrop Carrier v{version}' with a hard-coded '1.0' — not the real build number.

  - [ ] t.carrCoverageZones — 'Coverage Zones' / t.carrCoverageMapBlurb — 'The circles your riders work. Tap to edit.' — Navigator.push → CarrierZonesScreen. Second entry point to the same screen as the dashboard card.  `YdListRow (icon map_outlined) with onTap`
  - [ ] **[destructive]** t.carrPauseCompany — 'Pause company' / t.carrResumeCompany — 'Resume company' — POST /api/delivery-providers/my-company/pause or /resume. PAUSING STOPS THE WHOLE COMPANY BEING OFFERED ANY NEW WORK, platform-wide, immediately. Subtitle shows t.carrCompanyPaused when already paused. Failure raises a SnackBar with t.somethingWentWrong.  `YdListRow with onTap (icon pause_circle_outline / play_circle_outline; trailing swaps to a 20px CircularProgressIndicator while _pausing)`
  - [ ] t.custAppLanguage — 'App Language', with segments 'EN' and 'AR' (hard-coded) — LocaleController.setLanguage('en'|'ar'). Persists to secure storage under delivery.locale and flips the whole app to RTL. A run left in Arabic breaks every English finder in the integration test.  `AppLanguageRow (imported from settings_screen.dart) — two Semantics(button: true) segments inside a pill`
  - [ ] **[destructive]** t.custLogOutAccount — 'Log Out Account' — Calls onSignOut() → clears the session from FlutterSecureStorage and returns to the sign-in screen.  `YdPillButton.secondary with icon logout_rounded`

### CarrierOrderDetailsScreen  — no driving test
*One order as the dispatch desk reads it: a five-step stepper, pickup/drop-off, the rider ref, and the money card. Entirely built from the order object already in memory — it makes no second fetch, so it cannot go stale or fail.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/carrier_order_details_screen.dart`
- reached by: Sign in as carrier → Dashboard, tap any of the five 'Recent activity' cards; OR bottom nav 'Orders' → tap any order card in any of the three buckets.
- states: Stepper: t.carrStepReceived 'Received', t.carrStepAssigned 'Assigned', t.carrStepPickingUp 'Picking up', t.carrStepEnRoute 'En route', t.carrStepDelivered 'Delivered'. ACCEPTED with no rider still shows stage 0, not 1. · CANCELLED order: stage is -1 and the WHOLE STEPPER CARD IS OMITTED — only the CustomerStatusPill in the header says so. Worth a look on a cancelled job. · Rider card is absent entirely while riderId is null — no placeholder. · Money card: t.carrDeliveryFee 'Delivery total (Fresh USD)', t.carrPlatformFee 'YouDrop platform fee ({rate}%)' as a negative, t.total 'Total'. The cut is DERIVED here (fee × cutPercentage / 100), unlike the earnings tab which uses the server's figures. · t.carrLbpRate 'LBP conversion rate ({rate})' row renders only when MarketRates.instance.lbpPerUsd > 0 — i.e. only after GET /api/market/config succeeded. Verify both with and without it.

  - [ ] t.back — 'Back' (semantic label; the control is a chevron) — Returns to the tab you came from.  `YdScreenHeader onBack → Navigator.pop`
  - [ ] (none) — THERE ARE NO OTHER CONTROLS. The Figma frame's 'Reassign Rider' button and the rider's Call are deliberately absent — dispatch has no reassignment endpoint and the wire carries a ref, not a phone. Nothing on this screen writes.  `—`

### CarrierZonesScreen  — no driving test
*t.carrCoverageZones 'Coverage Zones' — every zone as a translucent circle on an OSM map plus a card each with a switch, an edit pencil and a delete. Every change is written straight to the server and the reply replaces the row; nothing is optimistic.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/carrier_zones_screen.dart`
- reached by: Two paths — Dashboard → tap the 'Coverage Zones' card; OR Settings → tap the 'Coverage Zones' row.
- states: Loading: full-screen CircularProgressIndicator (only while _zones is empty). · Error: YdEmptyState with t.somethingWentWrong / t.couldNotReachTheServer / t.tryAgain — gated on _error != null && _zones.isEmpty, so a failure after a successful load shows nothing. · Empty: no map card at all, plus YdCard.bordered with t.carrNoZones 'No zones yet. Draw the first circle your riders work.' · Radius line t.carrZoneRadiusKm 'Radius: {km} km', formatted with 0 decimals on an exact-km zone and 1 otherwise. · OSM tiles need network — on an offline device the map renders as empty grey tiles with the circles still drawn.

  - [ ] t.back — 'Back' — Pops to the dashboard or settings tab.  `YdScreenHeader onBack`
  - [ ] t.carrAddZone — 'Add zone' — Pushes _ZoneEditor with no zone, centred on the first zone or on Beirut (33.8938, 35.5018). Disabled while _busy.  `YdPillButton (compact, expand:false) in the header trailing slot`
  - [ ] (no label) the map itself — Pan and pinch only. Circles are crimson when active, faint grey when paused, each with a dark label chip at its centre. Camera is fit to the bounds of all zones with maxZoom 14.  `FlutterMap with InteractionOptions(pinchZoom | drag) — rotation and double-tap zoom are OFF`
  - [ ] **[destructive]** (no label) per-zone active switch — pill reads t.carrZoneActive 'ACTIVE' or t.carrZonePaused 'PAUSED' — PUT /api/delivery-providers/my-company/zones/{id} with active flipped. TURNING IT OFF STOPS WORK BEING OFFERED IN THAT CIRCLE, live. Failure raises a SnackBar with t.somethingWentWrong and the switch snaps back.  `Material Switch (activeTrackColor brand), disabled while _busy`
  - [ ] t.carrEditZone — 'Edit zone' (tooltip; the control is a pencil glyph) — Pushes _ZoneEditor seeded with this zone.  `IconButton (Icons.edit_outlined), disabled while _busy`
  - [ ] **[destructive]** t.remove — 'Remove' (tooltip; the control is a crimson bin glyph) — Opens an AlertDialog asking t.carrDeleteZoneAsk 'Remove {name}? Riders keep working the other zones.' with t.cancel 'Cancel' and t.remove 'Remove'. Confirming DELETEs the zone permanently — there is no undo.  `IconButton (Icons.delete_outline), disabled while _busy`
  - [ ] t.cancel — 'Cancel' (delete dialog) — pop(false) — no request is sent.  `TextButton`
  - [ ] **[destructive]** t.remove — 'Remove' (delete dialog, brand-coloured) — pop(true) → DELETE /api/delivery-providers/my-company/zones/{id}, then drops the row locally.  `TextButton with brand foreground`
  - [ ] (no label) pull-to-refresh — Re-runs myZones().  `RefreshIndicator`

### _ZoneEditor (add / edit a coverage zone)  — no driving test
*Title is t.carrNewZone 'New zone' or t.carrEditZone 'Edit zone'. A full-screen map over a form: tap places the pin, the slider sizes the circle, the field names it. One Save POSTs or PUTs and pops the server's answer back to the list.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/carrier_zones_screen.dart`
- reached by: Sign in as carrier → Dashboard or Settings → 'Coverage Zones' → 'Add zone' (header) for a new one, or the pencil on a zone card to edit one.
- states: Validation: an empty/whitespace name sets the inline error to t.requiredField 'Required' in crimson above Save, and nothing is sent. · Save failure: inline error t.somethingWentWrong, the form keeps what was typed, _saving clears. · While saving: back, map tap, the name field and the slider are all disabled; Save shows its spinner. · New-zone defaults: radius 3000 m (3.0 km), pin at the first existing zone's centre or Beirut.

  - [ ] t.back — 'Back' — Pops without saving. Note there is no confirm-discard: unsaved edits are lost silently.  `YdScreenHeader onBack — set to null (disabled) while _saving`
  - [ ] (no label) tap anywhere on the map — Moves the pin (Icons.place, 32px crimson) and the preview circle to that LatLng. Initial zoom 12.  `FlutterMap MapOptions.onTap (null while saving)`
  - [ ] t.carrZoneName — 'Zone name' (label) / t.carrZoneNameHint — 'e.g. Central Beirut' (hint) — Names the zone. Empty-on-save is refused client-side.  `TextField, isDense, textCapitalization.words, disabled while saving`
  - [ ] t.carrZoneRadiusKm — 'Radius: {km} km' (live readout beside the control) — Resizes the preview circle live. Submitted as (km × 1000).round() metres.  `Material Slider, min 0.5, max 30, divisions 59 (i.e. 0.5 km steps), brand active colour`
  - [ ] **[destructive]** t.save — 'Save' — New zone → POST .../my-company/zones. Edit → PUT .../zones/{id} with name, lat, lng, radius and the existing active flag. On success pops the saved CoverageZone back into the list. EDITING A ZONE MOVES LIVE COVERAGE.  `YdPillButton with busy flag`

### Portal chrome — Carrier Hub sidebar and account menu
*The fixed-width left rail: brand tile (Icons.local_shipping), wordmark 'Carrier Hub' (hard-coded English), seven destinations, and a footer user card whose menu carries language and sign-out.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/portal_shell.dart`
- reached by: Sign in at https://portal-dev.youdrop.shop as carrier/500005. PortalArea.forSession puts the carrier area up; with only the CARRIER role there is exactly one area and the wordmark is not a menu.
- covered by: test/shell/console_shell_test.dart covers the shell generically, not the carrier destinations.
- states: User card shows session.displayName over t.carrierPartner 'Carrier partner'. · Area switcher (onAreaSelected) is null unless the account holds more than one of MERCHANT/CARRIER/BACKOFFICE — the demo carrier will not see it. · There is no responsive collapse: the rail is a fixed ConsoleMetrics.sidebarWidth Row child, so a narrow window squeezes the content column rather than hiding the rail.

  - [ ] t.navDashboard — 'Dashboard' — index 0 → CarrierDashboardScreen(api: order, providerApi: provider, onShowJobs: jump(1)). No aggregatesApi, no performanceApi.  `ConsoleSidebar → _NavItem (InkWell + 4px _ActiveBar)`
  - [ ] t.navJobs — 'Jobs' — index 1 → JobsScreen(api: order).  `_NavItem`
  - [ ] t.navEarnings — 'Earnings' — index 2 → EarningsScreen(api: order).  `_NavItem`
  - [ ] 'Statement' (hard-coded English, no l10n key) — index 3 → CarrierStatementScreen(api: statements).  `_NavItem`
  - [ ] t.navCompany — 'Company' (the page inside is titled 'Riders Management') — index 4 → CompanyScreen(api: provider, orderApi: order) — the four optional clients are NOT passed.  `_NavItem`
  - [ ] t.navApplicants — 'Applicants' — index 5 → ApplicantsScreen(api: onboarding, providerApi: provider, documentsApi: documents) — fully wired.  `_NavItem`
  - [ ] t.navSettings — 'Settings' — index 6 → CarrierSettingsScreen(api: provider, locale, documentsApi) — profileApi and keysApi are NOT passed.  `_NavItem`
  - [ ] t.english — 'English' / t.arabic — 'العربية' — LocaleController.setLanguage. Note the console screens are English-only in this wave — only the l10n-keyed strings flip.  `CheckedPopupMenuItem inside the user card's PopupMenuButton`
  - [ ] **[destructive]** t.signOut — 'Sign out' — Ends the session.  `PopupMenuItem with Icons.logout`

### CarrierDashboardScreen — 'Carrier Control Tower'  — UNREACHABLE
*Four KPI cards over a split of an hourly tier-split chart and a live activity feed. Subtitle is 'Operational health dashboard for {company}'. Polls itself every 60 s (silently — a failed poll leaves the last good numbers up).*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/dashboard_screen.dart`
- reached by: Sign in to the portal as carrier → lands on 'Dashboard' (rail item 1).
- **unreachable:** The week-over-week footnote line ('This week: 54 delivered, +12.5% on the week before') can NEVER render in the deployed portal: it needs aggregatesApi/CarrierSummary.days of length ≥ 14, and portal_shell.dart passes no aggregatesApi. Likewise the fleet footnote can only ever read 'Fleet size is not recorded day by day' — the '{n} of {m} delivered something today' variant needs performanceApi, which is not passed.
- covered by: test/carrier/dashboard_screen_test.dart — DRIVES it: types into the header search and asserts the feed narrows, taps 'Deliveries Today' and asserts the jump callback fires, and has an explicit wired:false case ('works, and says less, when the new clients are not passed').
- states: Loading: CircularProgressIndicator on the background colour, until carrierSummary resolves. · No company: Icons.help_outline + t.noCompanyYet 'No company attached to this account yet' + t.askThePlatformToAttachYou — this is the ONLY error branch; anything that makes carrierSummary throw lands here. · KPI dashes: 'Total Assigned Riders' and 'Active Right Now' show '—' when riders/jobs did not load. · Chart empty: 'No jobs placed today yet'. Work outside 08:00–20:00 is dropped, not folded into the end columns — a quiet chart on a busy night is correct behaviour. · Feed empty: 'Nothing has happened on the job board yet.' / 'No recent job matches that.' / 'Could not read the job board just now.' · Trend fallbacks: 'Nothing delivered yesterday to compare with' and 'Nothing taken yesterday to compare with' when yesterday was zero; 'Level' when equal. · Below 1100px the chart and the 380px feed stack instead of sitting side by side.

  - [ ] 'Search recent jobs...' (hard-coded hint) — Live-filters the Live Active Feed only — matches shortId, storeName, status label or delivery address. The KPI cards and the chart are NOT filtered.  `ConsoleSearchField.global (TextField, no Key)`
  - [ ] t.refresh — 'Refresh' (tooltip; the control is a refresh glyph) — Calls _refresh() — carrierSummary, then myCompany, myRiders, forCarrier(size:100) each individually caught.  `ConsoleIconAction (Tooltip + InkWell)`
  - [ ] 'Notifications' (tooltip; a bell glyph) — NOTHING. Rendered permanently in the faint tier. A FINISH-WAVE NOTE in the source says ConsoleBell is not exported from shell/shell.dart yet. Same inert bell sits on all six other carrier pages.  `ConsoleIconAction with NO onPressed`
  - [ ] 'Deliveries Today' KPI card — onShowJobs → jump(1), moving the rail to the Jobs board. The only tappable KPI on the page.  `ConsoleKpiCard with onTap (InkWell wrapper)`
  - [ ] (no label) hover a chart column pair — Shows '{total} placed between 08:00 and 10:00 — {n} standard, {n} express'. Hover-only; no touch equivalent.  `Tooltip around the Standard/Express bar pair`
  - [ ] (no label) horizontal scroll on the chart — Seven two-hour columns 08:00–20:00 scroll sideways in a narrow window.  `SingleChildScrollView(Axis.horizontal) inside _TierBarChart`

### JobsScreen — t.jobsTitle 'Your jobs'
*t.jobsBlurb 'Everything your riders are carrying, and everything they have delivered.' — a six-column console table over one page of 50 jobs, showing the carrier's own fee rather than the order total.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/jobs_screen.dart`
- reached by: Portal sidebar → 'Jobs' (rail item 2). Also reached by tapping the 'Deliveries Today' KPI on the carrier dashboard.
- covered by: test/carrier/jobs_and_earnings_test.dart — DRIVES the filter pill ('filters down to one state without losing the count') and asserts the fee/waived/no-company cases. Search and refresh are not driven.
- states: Loading: full-panel CircularProgressIndicator. · Error (404 = no company): Icons.local_shipping_outlined + t.noCompanyYet + t.askThePlatformToAttachYou. · Empty: t.noJobsBlurb 'Orders assigned to your company will appear here.' when there are no jobs at all; 'No job matches that.' when the filter or search emptied it. · Waived cut: a second crimson line t.savedByOffers 'Saved by offers' under the fee, only when job.carrierFeeWaived. · Footer 'Showing {n} of {m} recent jobs.' — 50 is the hard cap; there is no paging control. · Placed date renders '—' when placedAt is null.

  - [ ] 'All' (hard-coded) — _filter = 0, no status filter.  `ConsoleFilterPills → _Pill (InkWell)`
  - [ ] 'On the road' (hard-coded) — _filter = 1 → PICKED_UP or READY only.  `ConsoleFilterPills → _Pill`
  - [ ] 'Delivered' (hard-coded) — _filter = 2 → DELIVERED only.  `ConsoleFilterPills → _Pill`
  - [ ] 'Cancelled' (hard-coded) — _filter = 3 → CANCELLED only. Note PLACED/ACCEPTED/PREPARING jobs are visible under All but under no other pill.  `ConsoleFilterPills → _Pill`
  - [ ] 'Search jobs...' (hard-coded hint) — Live-filters on shortId, delivery address and store name. Composes with the pill.  `ConsoleSearchField.global`
  - [ ] t.refresh — 'Refresh' — _reload() — replaces the Future with a fresh forCarrier(size: 50), which flashes the full-screen spinner again.  `ConsoleIconAction`
  - [ ] 'Notifications' — Inert. See the dashboard entry.  `ConsoleIconAction with no onPressed`
  - [ ] (none) table rows — ROWS ARE NOT CLICKABLE. There is no job detail view anywhere in the portal carrier console — the mobile shell has one, this does not.  `ConsoleTableRow WITHOUT onTap`
  - [ ] (no label) horizontal scroll of the table — Scrolls sideways below 1040px of content column.  `ConsoleTable minWidth 1040`

### EarningsScreen — t.earningsTitle 'Earnings'
*Four KPI cards keeping earned and expected deliberately apart, plus a conditional offers card. Subtitle is t.earningsWindowNote "Over the last {days} days, after the platform's {cut}% share of each delivery fee."*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/earnings_screen.dart`
- reached by: Portal sidebar → 'Earnings' (rail item 3).
- covered by: test/carrier/jobs_and_earnings_test.dart mounts it and asserts earned/expected stay apart and the offers card appears/absents correctly. Nothing on the page is tapped, because there is nothing tappable except refresh.
- states: Loading: full-panel spinner. · Error (404 = no company): Icons.help_outline + t.noCompanyYet + t.askThePlatformToAttachYou. · Earned footnote: "After the platform's {cut}% cut" (hard-coded English around the server's rate). · Expected footnote: t.expectedNote 'What the work in flight is worth if it all completes. Not yet owed.' · t.savedByOffers 'Saved by offers' card with t.savedByOffersNote appears ONLY when savedByOffers > 0 — a zero is deliberately not drawn.

  - [ ] t.refresh — 'Refresh' — _reload() — new carrierEarnings() future, spinner returns.  `ConsoleIconAction`
  - [ ] 'Notifications' — Inert.  `ConsoleIconAction with no onPressed`
  - [ ] (none) — THE PAGE HAS NO OTHER CONTROLS. Four read-only KPI cards: t.earned 'Earned', t.expected 'Expected', t.jobsDelivered 'Delivered', t.jobsInFlight 'In flight'. No period picker, no export, no drill-down.  `—`

### CarrierStatementScreen — 'Statement'
*The ledger's own arithmetic for a closed period, via /statements/mine — the route names nobody, so a carrier cannot ask for someone else's. Defaults to the 1st of the current month → today. Read-only by design.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/statement_screen.dart`
- reached by: Portal sidebar → 'Statement' (rail item 4).
- covered by: test/carrier/statement_screen_test.dart — mounts and asserts the /mine call names nobody, the KPI shapes, the itemised table, the empty period and the 403 copy. THE DATE-RANGE PICKER AND THE max-range SNACKBAR ARE NOT DRIVEN BY ANY TEST.
- states: Range guard: picking more than StatementsApi.maxRangeDays raises a critical-red SnackBar 'A statement covers at most {n} days and that period is {d}. The period is unchanged.' and leaves the period alone. WORTH TESTING — drag the picker across a year. · Loading: a ConsoleCard holding a 160px-tall spinner (first load only). · Empty period: card 'Nothing in this period' with 'No jobs of yours settled between {from} and {to}. That is an answer, not a failure — widen the period to look further back.' · 403: 'This account has no statement of its own…'; 404: 'You are not attached to a delivery company yet…'; anything else prints the raw error under 'No statement to show'. · KPI 'Itemised below' is a count of returned rows, NOT a job count — the server trims the list and the card says so ('of the jobs in this period'). · When the ledger sends no debit line the "Platform's cut" card shows '—' plus 'not itemised for this period' — deliberately never a zero. · Net card footnote uses NetDirection.selfLabel ('Owed to you'), colour-coded positive/caution/info/neutral.

  - [ ] '{yyyy-MM-dd} → {yyyy-MM-dd}' (the live period, e.g. '2026-09-01 → 2026-09-10'), Icons.date_range_outlined — Opens Material showDateRangePicker with helpText 'Statement period', saveText 'Use period', firstDate = three years back, lastDate = today. On accept it re-fetches. THE ONLY REAL INPUT ON THE PAGE.  `ConsoleFilterButton (InkWell), disabled while _loading`
  - [ ] 'Refresh' (tooltip, hard-coded — not t.refresh here) — Re-fetches the same period.  `ConsoleIconAction, disabled while _loading`
  - [ ] 'Notifications' — Inert. The source note says wiring it needs a NotificationApi threaded to the carrier area, which no carrier page has.  `ConsoleIconAction with no onPressed`
  - [ ] (none) entries table — Order / Settled / Gross / Commission / Net / Paid by — all read-only. Order ids are shortened to 8 uppercase chars.  `ConsoleTableRow without onTap, minWidth 900`

### CompanyScreen — 'Riders Management'  — UNREACHABLE
*Subtitle 'Manage your delivery team, dispatch regions, and rider status'. A seven-column fleet table over the score card and the availability switch. This is where a carrier pauses itself — deliberately NOT on Settings.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/company_screen.dart`
- reached by: Portal sidebar → 'Company' (rail item 5). Note the rail label ('Company') and the page title ('Riders Management') disagree.
- **unreachable:** In the deployed portal: 'Add New Rider' is permanently disabled, both row suspend/reinstate actions are permanently disabled, the Region and Join Date columns are always '—' (they come from onboarding applications), the Status column can never show a real presence label, and the rider drawer's performance and hours blocks always read 'not wired up in this build'. All of these ARE driven by the tests, which pass the clients the shell withholds.
- covered by: test/carrier/company_screen_test.dart — the most thoroughly driven carrier screen: taps Add New Rider and Approve, the eye, Suspend (including picking 'Policy violation' from the ConsoleSelect and confirming), Reinstate, and t.pauseNewOrders; plus wired:false and Arabic-direction cases.
- states: Loading: full-panel spinner. Error (404): Icons.help_outline + t.noCompanyYet + t.askThePlatformToAttachYou. · Empty fleet: t.noRidersBlurb 'You have no riders. Your company looks available and can collect nothing…'. Filtered-empty: 'No rider matches that.' · Every Rating cell is a permanent '—' (_Unknown) — nothing on the platform rates a rider, stated in the table footer. · Status cell precedence: 'Suspended' (critical) → presence label → 'On a job' (info) → '—'. · Score card t.howYouAreDoing 'How you are doing' with t.deliveryScore, t.ordersDelivered, t.timeToClaim, t.timeOnTheRoad; a provisional score gets the t.tooEarlyToTell 'too early to tell' pill and t.scoreProvisionalBlurb instead of t.scoreBlurb. · A platform-suspended company gets t.suspendedByPlatform and NO button at all — deliberately, because resuming would fail. · Server error text is preferred over t.thatDidNotWork 'That did not work' when the response body carries message/detail. · Below 900px the score and availability cards stack.

  - [ ] 'All Delivery Riders' with a live count (hard-coded) — _tab = 0, shows the whole roster.  `ConsoleFilterTabs → _Tab (InkWell), inside a horizontal SingleChildScrollView`
  - [ ] 'Working now' with a live count (hard-coded) — _tab = 1. 'Working now' means PresenceState.onDuty where tracking loaded, and 'holding an unfinished job' where it did not — in the shipped build always the latter.  `ConsoleFilterTabs → _Tab`
  - [ ] 'Search riders...' (hard-coded hint) — Filters on the rider's name, the 8-char short ref and the region.  `ConsoleSearchField.global`
  - [ ] t.refresh — 'Refresh' — _reload() — re-runs myCompany + myScore + myRiders (Future.wait) then the enrichment calls.  `ConsoleIconAction`
  - [ ] 'Notifications' — Inert.  `ConsoleIconAction with no onPressed`
  - [ ] 'Add New Rider' (hard-coded), Icons.add — Opens the 'Add a rider' drawer of waiting applicants. DISABLED IN THE SHIPPED BUILD — onPressed is null unless applicationsLoaded, and applications need onboardingApi, which the portal shell does not pass. The tooltip then reads 'Riders join by applying — approve them on the Onboarding page'.  `ConsolePrimaryButton wrapped in a Tooltip`
  - [ ] (no label) a table row — Opens the rider detail drawer. Same target as the eye.  `ConsoleTableRow with onTap (InkWell)`
  - [ ] 'Rider detail' (tooltip; an eye glyph) — showConsoleDrawer → _RiderDetail.  `ConsoleRowAction (Icons.visibility_outlined)`
  - [ ] **[destructive]** 'Suspend this rider' / 'Reinstate this rider' (tooltip; a block or open-padlock glyph) — Opens _StandingDialog, then POSTs suspendRider / unsuspendRider against the rider's application id. SUSPENDING STOPS THAT RIDER BEING OFFERED WORK. DISABLED IN THE SHIPPED BUILD (managementApi and the application are both null) — the tooltip degrades to 'No application on file for this rider — the platform attached them directly'.  `ConsoleRowAction with destructive: true (red tint)`
  - [ ] **[destructive]** t.pauseNewOrders — 'Pause new orders' / t.startTakingOrders — 'Start taking orders' — POST pauseMyCompany / resumeMyCompany, SnackBars t.pausedNoNewOrders 'Paused. No new orders will be sent to you.' or t.resumedTakingOrders 'You are taking orders again.', then reloads. PAUSING STOPS THE WHOLE COMPANY BEING SENT WORK. This is the portal twin of the mobile Settings row — same endpoints.  `ConsolePrimaryButton with busy flag, inside the t.takingOrders 'Taking orders' card`

### _RiderDetail drawer  — UNREACHABLE
*Everything the platform knows about one rider, in a 460px right-hand slide-over: Presence, Today, Performance (30 days, this company's scope only), Hours online (7 days), and their Application. Loads its own two endpoints so the table does not fire two requests per row.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/company_screen.dart`
- reached by: Portal sidebar → 'Company' → click any table row, or its eye action.
- **unreachable:** In the shipped portal the Performance block always reads 'Rider performance is not wired up in this build.' and the Hours block always reads 'Hours online are not wired up in this build.', because performanceApi and trackingApi are not passed to CompanyScreen.
- covered by: test/carrier/company_screen_test.dart — 'the eye opens everything the platform knows about one rider' and 'a rider with no claimed work shows a dash, never 0% or 100%'. Both run wired:true.
- states: Header badge: 'Suspended' (critical) or the presence pill, or nothing. · Presence: 'Presence could not be read just now.' when the roster failed; 'This rider has never declared duty, so the platform has no presence for them.' when absent from it; a stale rider adds 'Declared on duty, but the last fix is too old to dispatch on.' · Today: 'Delivered today' and 'Delivered in the last 100 jobs' — each 'Could not be read' when their source is null. · Performance: an inline 16px spinner, then either the four lines or 'Could not read this rider's performance just now.' Completion is '—' rather than 0%/100% when nothing was claimed. · Hours online: zero-filled across the whole window so a quiet day shows '0.00 h'; failure reads 'No presence history for this rider. Nothing is backfilled before the feature existed.' · Application section is omitted entirely when there is no application on file.

  - [ ] 'Close' (tooltip; an X) — Closes the drawer.  `ConsoleRowAction in the _DrawerPanel header → Navigator.pop`
  - [ ] (no label) click the scrim — Also closes it. Esc works too, via the route.  `showGeneralDialog barrierDismissible: true, barrier at 32% ink`
  - [ ] (none) — THE DRAWER IS ENTIRELY READ-ONLY. No actions on the rider from inside it — suspension lives on the table row behind.  `—`

### _WaitingList drawer — 'Add a rider'  — UNREACHABLE
*The undecided rider applications addressed to this company, approved in place. Subtitle is 'Nobody is waiting to ride for you' or '{n} waiting to ride for you'.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/company_screen.dart`
- reached by: Portal sidebar → 'Company' → 'Add New Rider'.
- **unreachable:** UNREACHABLE IN THE DEPLOYED PORTAL. The only door to this drawer is the 'Add New Rider' button, which is disabled because CompanyScreen is built without onboardingApi. The same hire() call is reachable from the Applicants page, which IS wired.
- covered by: test/carrier/company_screen_test.dart — 'Add New Rider approves somebody who is actually waiting' taps the button and then Approve.
- states: Empty: 'Nobody has applied to ride for you. Riders reach a fleet by applying — there is no way to create one directly.' · Failure: the server's own message (or t.thatDidNotWork) in critical red above the list; the row stays approvable. · Only one hire is in flight at a time — every other Approve is disabled while _busyId is set.

  - [ ] **[destructive]** 'Approve' (hard-coded) — onboardingApi.hire(companyId, applicationId) — CREATES THE RIDER'S KEYCLOAK ACCOUNT, EMAILS THEM, AND PUTS THEM ON THE FLEET SO THEY CAN BE SENT WORK. Irreversible from here. The row then swaps to a 'On your fleet' badge. Blurb above says so: t.hiringAlsoCreatesTheirAccount.  `ConsoleButton, tone tinted, with a per-row busy flag`
  - [ ] 'Done' (hard-coded) — pop(_hired.isNotEmpty) → the page reloads only if somebody was actually approved.  `ConsoleButton, tone outlined`
  - [ ] 'Close' / scrim — Closes without the reload signal.  `ConsoleRowAction + barrierDismissible`

### _StandingDialog — suspend / reinstate a rider  — UNREACHABLE
*Title 'Suspend {name}' or 'Reinstate {name}'. The reason is a typed enum because the server searches suspension records by it; the note is the free half and optional on both.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/company_screen.dart`
- reached by: Portal sidebar → 'Company' → the block or padlock action on a rider row.
- **unreachable:** Unreachable in the deployed portal — its only entry point (the row's block action) is disabled without managementApi.
- covered by: test/carrier/company_screen_test.dart — drives the whole dialog including opening the ConsoleSelect and choosing 'Policy violation', and separately drives reinstatement.
- states: Body copy differs by direction: 'They keep their sign-in and their history, and stop being offered work. You can reinstate them here at any time.' vs 'They can be offered work again from the moment this is saved.' · Both endpoints are idempotent server-side and double-gated on actually running this company. · Server refusal surfaces as a critical-red SnackBar carrying the server's own sentence.

  - [ ] 'Choose a reason' (placeholder) → the picked SuspensionReason.label, Icons.flag_outlined — Sets _reason. REQUIRED — the Suspend button stays disabled until one is chosen. Only rendered when suspending.  `ConsoleSelect (a button that opens a PopupMenu of every SuspensionReason)`
  - [ ] 'A note for the record (optional)' (hint) — Optional free-text note on both suspend and reinstate.  `TextField, maxLines 3, maxLength 500 (counter visible)`
  - [ ] t.cancel — 'Cancel' — pop(null) — nothing is sent.  `TextButton`
  - [ ] **[destructive]** 'Suspend rider' (hard-coded) — POST suspendRider(companyId, applicationId, reason, note). THE RIDER KEEPS THEIR SIGN-IN AND HISTORY BUT STOPS BEING OFFERED WORK. SnackBar '{name} is suspended and will not be offered work.'  `ConsoleSoftButton (critical tint), disabled until a reason is picked`
  - [ ] **[destructive]** 'Reinstate rider' (hard-coded) — POST unsuspendRider(companyId, applicationId, note). Effective immediately. SnackBar '{name} can take work again.'  `ConsolePrimaryButton in DeliveryAccent.positive green`

### ApplicantsScreen — 'Rider Onboarding Portal'
*Subtitle 'Review incoming fleet registration applications and safety documents'. A wrapping grid of applicant cards (1–3 across, min 340px), each with a verification checklist, the uploaded papers reviewable in place, and the hire/reject pair. Polls every 45 s. THIS IS THE FULLY-WIRED CARRIER PAGE — every optional client it needs is passed by the shell.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/applicants_screen.dart`
- reached by: Portal sidebar → 'Applicants' (rail item 6).
- covered by: test/carrier/applicants_screen_test.dart — DRIVES approve-document, refuse-document (including typing the reason and confirming), Approve Rider, and Reject Application (including the reason dialog). Also has layout cases at several widths.
- states: Loading: a spinner in place of the grid, only while _applicants is empty. · Error: Icons.help_outline + t.noCompanyYet + t.askThePlatformToAttachYou (a failed silent poll does NOT replace the page). · Empty: 'Nobody matches that' + 'Try a different name or email address.' when searching; otherwise t.nobodyWaiting 'Nobody is waiting on you.' or t.nobodyHasApplied 'Nobody has applied yet.' · Checklist rows 1–2 are always 'Email address verified' and 'Phone number verified' with badges 'Approved' / 'Pending Verification' / 'Not given'. · Uploaded-document rows carry one of: 'Waiting' (caution), 'Approved' (positive), 'Refused' (critical), 'Replaced' (neutral). Special rows: 'Loading uploaded documents…' with a 12px spinner, 'Uploaded documents could not be loaded' with the retry action, and 'Identity, vehicle and background documents' / 'Not uploaded' when the list came back genuinely empty. · A decided applicant shows a status pill plus t.turnedDownBecause 'Turned down: {reason}' or t.onYourFleetNow 'On your fleet. They can be sent work.' — and NO buttons. · Registration line has three shapes: 'Registered today at HH:mm', 'Registered yesterday at HH:mm', 'Registered Oct 14, 2025', or 'Registration date not recorded'. · Grid reflows 3 → 2 → 1 across as the content column narrows past ~340px per card.

  - [ ] 'Search applicants...' (hard-coded hint) — Filters the grid on contact name and contact email.  `ConsoleSearchField.global`
  - [ ] t.refresh — 'Refresh' — _load() — re-resolves the company id if needed, re-reads the applications and every card's documents.  `ConsoleIconAction`
  - [ ] 'Notifications' — Inert.  `ConsoleIconAction with no onPressed`
  - [ ] t.waitingOnly — 'Waiting only' — _showAll = false then _load() — a REFETCH with all:false, not a client filter. Also makes the rose count chip ('{n} Applications Left' / '1 Application Left') reappear.  `ConsoleFilterTabs → _Tab`
  - [ ] t.everyone — 'Everyone' — _showAll = true then _load() with all:true — includes decided applications. Hides the count chip.  `ConsoleFilterTabs → _Tab`
  - [ ] 'Copy {phone}' / 'No phone number on this application' (tooltip; a phone glyph) — Clipboard.setData(phone) then a SnackBar '{phone} copied'. Disabled and faint when contactPhone is null — there is no dialler on a web console, so it does the useful half.  `_CallButton (Material + InkWell, 16px Icons.phone_outlined)`
  - [ ] 'Open the document' (tooltip; open_in_new) — openExternalLink(doc.viewUrl) — a new browser tab. The action is ABSENT when storage could not sign a URL.  `ConsoleRowAction on a checklist row`
  - [ ] **[destructive]** 'Approve this document' (tooltip; a tick) — POST approveCompanyApplicantDocument then re-reads that card's documents. Only rendered while the application is undecided, the doc is not superseded, and its status is pending.  `ConsoleRowAction, per-document busy flag`
  - [ ] **[destructive]** 'Refuse this document' (tooltip; an X) — Opens _DocumentReasonDialog; on confirm POSTs rejectCompanyApplicantDocument with the reason THE APPLICANT IS SHOWN VERBATIM.  `ConsoleRowAction with destructive: true`
  - [ ] 'Try again' (tooltip; a refresh glyph on the checklist row) — Re-reads just that applicant's documents after a failure.  `ConsoleRowAction`
  - [ ] **[destructive]** 'Reject Application' (hard-coded) — Opens _ReasonDialog; on confirm POSTs turnDown(companyId, applicationId, reason). THE APPLICANT IS SENT THE REASON WORD FOR WORD. SnackBar t.applicantTurnedDown '{name} has been told.'  `ConsoleSoftButton (critical tint) in an Expanded, 50/50 with Approve`
  - [ ] **[destructive]** 'Approve Rider' (hard-coded), emerald — POST hire(companyId, applicationId). CREATES THE RIDER'S ACCOUNT AND PUTS THEM ON THE FLEET IN ONE IRREVERSIBLE STEP. SnackBar t.riderAdded '{name} is on your fleet. We have emailed them how to sign in.' The warning above the pair is t.hiringAlsoCreatesTheirAccount.  `ConsolePrimaryButton with color DeliveryAccent.positive and a busy flag`

### _ReasonDialog — turning an applicant down
*t.turnDownName 'Turn down {name}' — the refusal cannot happen without a reason, because the applicant is sent it verbatim.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/applicants_screen.dart`
- reached by: Portal sidebar → 'Applicants' → 'Reject Application' on any undecided card.
- covered by: test/carrier/applicants_screen_test.dart — 'turning somebody down cannot happen without a reason' asserts the disabled state, types, and confirms.
- states: The button is genuinely disabled, not merely no-op: onPressed is null until _reason.text.trim() is non-empty, and onChanged rebuilds to re-evaluate. · A whitespace-only reason is also refused by the caller after the pop.

  - [ ] (no hint) the reason box — Types the reason. Body above reads t.theyAreSentThisWordForWord 'They are sent this word for word. Say what would have to change.'  `TextField, autofocus, maxLines 3, maxLength 500, brand cursor`
  - [ ] t.cancel — 'Cancel' — pop(null) — nothing is sent.  `TextButton`
  - [ ] **[destructive]** t.turnDown — 'Turn down' — pop(reason) → turnDown() on the application. The person is emailed the text.  `ConsoleSoftButton, disabled while the trimmed text is empty`

### _DocumentReasonDialog — refusing one uploaded paper
*Title 'Refuse {document kind}'. The reason is the only way the applicant learns what to upload instead.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/applicants_screen.dart`
- reached by: Portal sidebar → 'Applicants' → the X ('Refuse this document') on any pending, non-superseded document row of an undecided application.
- covered by: test/carrier/applicants_screen_test.dart — 'refusing a paper cannot happen without the reason the applicant reads'.
- states: Document label falls back to the server's raw kindWire when this build does not know the typed kind.

  - [ ] 'The photo is too blurred to read the expiry date' (hint) — Types the refusal reason. Body: 'The applicant is shown this word for word. Say what is wrong with the document and what to upload instead.'  `TextField, autofocus, maxLines 3, maxLength 500`
  - [ ] t.cancel — 'Cancel' — pop(null).  `TextButton`
  - [ ] **[destructive]** 'Refuse document' (hard-coded) — pop(reason) → rejectCompanyApplicantDocument. The document flips to the 'Refused' badge.  `ConsoleSoftButton, disabled while empty`

### CarrierSettingsScreen — 'Company Preferences'  — UNREACHABLE
*Subtitle 'Configure payment, service domains, languages, and system preferences'. Four cards in two columns: Carrier Identity, Payout Details (left); Configuration Preferences, API Integration Endpoint (right). The company's availability switch is deliberately NOT here — it lives on the Riders page.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/settings_screen.dart`
- reached by: Portal sidebar → 'Settings' (rail item 7, last).
- **unreachable:** IN THE DEPLOYED PORTAL profileApi and keysApi are not passed, so: 'Upload Logo' is permanently disabled; the whole regions editor is replaced by a single ConsoleTagChip reading 'Dispatch regions are not wired up in this build'; the hours editor is replaced by 'Operating hours are not wired up in this build.'; 'Save Settings Configuration' is permanently disabled; the 'Create key' button is absent; and the API card reads 'Partner API keys are not wired up in this build.' Only the payout dialog and the language segment are actually operable on this page today.
- covered by: test/carrier/settings_screen_test.dart — the most exhaustively driven file: payout dialog PUT, language toggle, the three-step logo upload, the over-limit file guard, region add and remove, both hours validation failures, ticking a closed day, key creation with the secret dialog and copy, revocation with its confirm, and the header search. All with wired:true, plus one wired:false case.
- states: Loading: full-panel spinner. Error (404): Icons.help_outline + t.noCompanyYet + t.askThePlatformToAttachYou. · Identity card: 'Registered Legal Name', 'Primary Contact', 'Contact Phone' — read-only, 'Nothing on file' in the faint tier when absent, footer 'The registered name and contact are set by the platform. Ask support to change them.' · Payout card header pill is company.payoutState.label; 'Corporate Bank Partner' is a permanent stated absence: 'Not recorded — the platform stores the account, not the bank'. · IBAN field cycles 'Loading…' → 'Could not load the payout account' → 'Not set yet' → the masked form 'SA44 •••••••••••••••• 1234'. The full IBAN is never rendered. · payoutState.needsAttention adds t.payoutNeedsAttentionBlurb. · Regions empty: 'No regions yet. A company with none is not narrowed to any area.' · Hours validation errors render above Save, in critical red: '{Day}: times are 24-hour HH:mm, like 09:00.' and '{Day}: opening has to be before closing.' A server refusal replaces them with the server's own sentence and the form KEEPS what was typed. · 'Nothing has changed since the last save.' under a disabled Save when the form is clean. · API card: 'No API key has been issued' when there are none; a revoked key stays listed with a 'Revoked' badge and no bin; each key line reads 'Created {date} · never used|last used {date} · revoked {date}'. · Search miss: a single card reading 'Nothing on this page matches "{query}".' · Below 980px the two columns become one, left column first.

  - [ ] 'Search settings...' (hard-coded hint) — Narrows the GRID to the cards whose keyword list contains the query — left: carrier identity/legal name/logo/contact/phone, payout/bank/iban/account; right: configuration/dispatch/region/hours/language, api/key/integration/endpoint/save. NOTE the match is term.contains(query), so a query longer than any keyword hides everything.  `ConsoleSearchField.global`
  - [ ] t.refresh — 'Refresh' — _reload() — disposes the seven day-form controller pairs, clears dirty state, re-loads the company, profile, keys and payout. UNSAVED HOURS/REGION EDITS ARE DISCARDED WITHOUT WARNING.  `ConsoleIconAction`
  - [ ] 'Notifications' — Inert.  `ConsoleIconAction with no onPressed`
  - [ ] 'Upload Logo' / 'Replace Logo' / 'Uploading…' (hard-coded) — Picks a file (file_selector, jpg/jpeg/png/webp), presigns, PUTs to storage with a BARE Dio (no Authorization header, which presigned storage rejects), then confirms. DISABLED in the shipped build (profileApi is null) with caption 'Logo upload is not wired up in this build'.  `ConsoleTintButton`
  - [ ] **[destructive]** 'Add bank account' / 'Update bank account' (hard-coded) — Opens _PayoutDialog. LIVE in the shipped build — documentsApi is a required parameter and is passed.  `ConsoleTintButton`
  - [ ] **[destructive]** 'Remove {region}' (tooltip; an X on each region tag) — Drops the region from the local list and marks the form dirty. Nothing leaves the browser until Save.  `ConsoleRowAction destructive: true inside _RemovableTag`
  - [ ] 'Add a region — Beirut, Jounieh…' (hint), key ValueKey('region-field') — Types a region. Case-insensitive duplicate check on add.  `ConsoleSearchField (one of the few keyed controls in this codebase)`
  - [ ] 'Add region' (hard-coded), Icons.add — Appends the trimmed region and clears the field.  `ConsoleButton tone tinted, disabled while the field is empty`
  - [ ] per-day open checkbox, key ValueKey('hours-{DAY}-open?') — row label 'Monday'…'Sunday' — Ticks the day open (revealing its two time fields) or closed (the row then reads 'Closed'). A DAY LEFT UNTICKED IS CLOSED in the PUT — absence is meaningful in the contract.  `Material Checkbox, compact`
  - [ ] opening time, key ValueKey('hours-{DAY}-from'), hint 'HH:mm', Semantics '{Day} opening time' — 24-hour opening time, validated client-side before any request.  `_TimeField → TextField, maxLength 5, 64px wide`
  - [ ] closing time, key ValueKey('hours-{DAY}-to'), hint 'HH:mm', Semantics '{Day} closing time' — Closing time. Must be strictly after opening.  `_TimeField → TextField, maxLength 5`
  - [ ] 'English' / 'العربية' (both hard-coded, each named in its own script) — LocaleController.setLanguage('en'|'ar') — THE ONE CONTROL ON THIS PAGE THAT TAKES EFFECT THE MOMENT IT IS TOUCHED, with no Save.  `ConsoleSegmented (two InkWells in a trough)`
  - [ ] 'Create key' (hard-coded) — Opens _KeyLabelDialog, mints the key, then shows the secret exactly once. THE WHOLE TRAILING SLOT IS null (the button is absent, not disabled) when keysApi is null — which is the shipped build.  `ConsoleTintButton in the API card's trailing slot`
  - [ ] 'Copy the key prefix' (tooltip; a copy glyph) — Clipboard + SnackBar '{prefix} copied'. Only when a live key exists.  `ConsoleRowAction inside the ConsoleReadOnlyField trailing slot`
  - [ ] **[destructive]** 'Revoke this key' (tooltip; a bin glyph) — Opens _RevokeDialog then keysApi.revoke(id). ANYTHING AUTHENTICATING WITH THAT KEY STOPS WORKING IMMEDIATELY AND IT CANNOT BE BROUGHT BACK.  `ConsoleRowAction destructive: true, per non-revoked key row`
  - [ ] **[destructive]** 'Save Settings Configuration' / 'Saving…' (hard-coded) — PUT of dispatchRegions + operatingHours as ONE form with PUT semantics — what is on screen replaces what the company had. Disabled unless profileApi != null AND _dirty AND !_saving.  `ConsolePrimaryButton wide: true, busy flag`

### _PayoutDialog — add / update the bank account
*Both fields are PUT together or not at all — half-edited bank details sitting in an editable card would look saved without being saved.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/settings_screen.dart`
- reached by: Portal sidebar → 'Settings' → 'Add bank account' or 'Update bank account' in the Payout Details card.
- covered by: test/carrier/settings_screen_test.dart — 'the dialog PUTs holder and IBAN together and re-reads the record' drives both fields and Save.
- states: Body: 'Both fields are saved together and replace what is on record. Payouts go to this account.' · Failure surfaces the server's own message (body.message or body.detail) in a critical-red SnackBar, else 'That did not go through. Try again.' · After a successful save a second badge appears beside the button carrying PayoutVerificationState.label (the bank check's own verdict, distinct from the card-header pill).

  - [ ] 'Account holder, exactly as the bank has it' (hint) — Pre-filled from the current record when one exists.  `TextField, autofocus, maxLength 200`
  - [ ] 'IBAN — spaces are fine' (hint) — DELIBERATELY LEFT BLANK even when an account exists, so the mask outside can never be submitted as the account. The server normalises and mod-97 checks it.  `TextField, maxLength 42`
  - [ ] 'Cancel' (hard-coded, not t.cancel here) — pop(null).  `TextButton`
  - [ ] **[destructive]** 'Save bank account' (hard-coded) — setMyPayout(holder, iban) → SnackBar 'Payout account updated' and the payout future is re-read. THIS CHANGES WHERE THE COMPANY'S MONEY IS SENT.  `ConsolePrimaryButton, disabled until BOTH fields are non-empty`

### _KeyLabelDialog + _SecretDialog — minting a partner API key  — UNREACHABLE
*Name the key, then see its secret exactly once — the server stores only a hash.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/settings_screen.dart`
- reached by: Portal sidebar → 'Settings' → 'Create key' in the API Integration Endpoint card header.
- **unreachable:** Unreachable in the deployed portal — the 'Create key' button is not rendered at all, because CarrierSettingsScreen is built without keysApi.
- covered by: test/carrier/settings_screen_test.dart — 'creating a key shows the secret once, with the warning and a copy' drives label, create, copy and confirm.
- states: _SecretDialog is barrierDismissible: false and has NO cancel — the only way out is the confirm button, deliberately. · Warning copy: 'This is the only time {prefix} can be shown. It is stored hashed, so nobody — not you, not support — can read it again. Lose it and you revoke the key and create another.'

  - [ ] 'dispatch box (optional)' (hint) — Optional label. Body: 'The secret is shown once, on the next screen, and cannot be shown again. Name the key after the machine that will hold it.'  `TextField, autofocus, maxLength 80`
  - [ ] 'Cancel' (hard-coded) — pop(null) — no key is minted.  `TextButton`
  - [ ] **[destructive]** 'Create key' (hard-coded) — keysApi.create(label) then immediately opens the secret dialog BEFORE refreshing the listing, so nothing can navigate away from it.  `ConsolePrimaryButton — enabled even with an empty label`
  - [ ] (the secret itself) — Selectable so it can be copied by hand as well.  `SelectableText in a bordered box`
  - [ ] 'Copy the key' (hard-coded), Icons.copy_outlined — Clipboard.setData(secret) + SnackBar 'Key copied'.  `ConsoleButton tone tinted`
  - [ ] 'I have copied it' (hard-coded) — pop() then the settings page reloads. THE SECRET IS GONE FOR GOOD AFTER THIS.  `ConsolePrimaryButton`

### _RevokeDialog — revoking an API key  — UNREACHABLE
*Title 'Revoke {prefix}'. One confirm in front of an immediate, irreversible cut-off.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/carrier/settings_screen.dart`
- reached by: Portal sidebar → 'Settings' → the bin glyph on any non-revoked key row.
- **unreachable:** Unreachable in the deployed portal — key rows only render when keysApi returns keys, and keysApi is not passed.
- covered by: test/carrier/settings_screen_test.dart — 'revoking asks first, then revokes' and 'a revoked key stays in the listing, flagged and unrevokable'.
- states: Body: 'Anything still authenticating with this key stops working the moment it is revoked. A revoked key cannot be brought back — create a new one instead.' · The revoked key remains in the listing afterwards with a neutral 'Revoked' badge and no bin action.

  - [ ] 'Cancel' (hard-coded) — pop(false).  `TextButton`
  - [ ] **[destructive]** 'Revoke key' (hard-coded) — pop(true) → keysApi.revoke(id) → SnackBar '{prefix} revoked' and a reload. ANYTHING STILL AUTHENTICATING WITH THAT KEY STOPS WORKING THE MOMENT IT IS REVOKED, AND IT CANNOT BE BROUGHT BACK.  `ConsoleSoftButton (critical tint)`

## Back office console in delivery_portal (lib/src/backoffice/ + lib/src/shell/ + portal_shell

48 screens, 189 controls.

### _SignInScreen (+ _BrandPanel, _SignInPanel, _LanguageToggle)  — no driving test
*Start the Keycloak OIDC redirect and pick the console language before signing in.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/main.dart`
- reached by: Open https://portal-dev.youdrop.shop with no session (or after Sign out). This is the pre-auth screen; everything else is behind it.
- states: Bootstrap: full-screen CircularProgressIndicator while _authService.restore() runs · Error: _MessageScreen 'Sign-in failed: <error>' with a 'Try again' OutlinedButton · Busy: button disabled, label 'Sign in…' · SnackBar 'Sign-in failed' if signIn() throws · Responsive: below 1040px logical width the 480px crimson brand panel is dropped and the 416px card centres (constant _splitPanelBreakpoint, main.dart:266)

  - [ ] t.signIn — "Sign in" (renders as "Sign in…" while busy) — AuthService.signIn() → navigates the browser away to Keycloak; the session comes back via AuthService.restore() on the next load. Type backoffice / 400004 on Keycloak's own page.  `ElevatedButton (full width, brand fill; disabled while busy)`
  - [ ] t.language tooltip — "Language"; items t.english "English" / t.arabic "العربية"; button face is the literal "AR / EN" — LocaleController.setLanguage; persisted to flutter_secure_storage key 'delivery.locale' and survives reload. Console screens themselves are English-only, so only the rail and shared widgets re-label.  `PopupMenuButton<String> wrapped in a bordered Container (position: under)`

### _MessageScreen (no-role / sign-in-failed screen)  — UNREACHABLE, no driving test
*Tell a signed-in person they have no console, and let them sign out and try another account.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/main.dart`
- reached by: Sign in with an account whose token carries none of MERCHANT / CARRIER / BACKOFFICE (PortalArea.forSession returns empty) — or when the bootstrap future throws.
- **unreachable:** Not reachable with any of the five demo logins — all five carry a portal or app role. Needs a fresh Keycloak user with only default-roles-delivery-platform.
- states: Message 'This account has no Merchant, Carrier or Backoffice access.' with lock_outline glyph · Message 'Sign-in failed: <error>' with error_outline glyph

  - [ ] no l10n getter — "Sign in as someone else" (error variant: "Try again") — No-role variant calls _signOut() (AuthService.signOut, clears the session); error variant re-runs _signIn().  `OutlinedButton`

### PortalShell + ConsoleSidebar (the rail, the console switcher, the account menu)  — UNREACHABLE
*Move between the 14 back office destinations, and change language or sign out.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/portal_shell.dart + lib/src/shell/console_sidebar.dart`
- reached by: Immediately after sign-in. Present on every back office screen; it is the only navigation the app has.
- **unreachable:** The console switcher is unreachable with backoffice/400004 — that user holds only the BACKOFFICE realm role, so areas.length == 1 and onAreaSelected is null (portal_shell.dart:667). To exercise it a Keycloak user needs two of MERCHANT/CARRIER/BACKOFFICE.
- covered by: test/shell/console_shell_test.dart — DRIVES the sidebar: renders it at several widths and taps 'CARRIER HUB' → 'Backoffice' to prove the switcher swaps areas. Also mounts ConsolePage with header/KPIs/table.
- states: Single-area account: wordmark is plain Text, no switcher · Multi-area account: wordmark becomes the popup · Long display name / long rail label: ellipsised · Rail scrolls when the window is shorter than 14 rows

  - [ ] 14 rail rows: t.navDashboard "Dashboard", t.navOrders "Orders", t.navCategories "Categories", t.navCatalog "Catalog", t.navBanners "Banners", t.navOnboarding "Onboarding", t.navCarriers "Carriers", inline "Riders", t.navAreas "Areas", t.navFinance "Finance", inline "Statements", t.navOffers "Offers", inline "Promo Codes", t.navSettings "Settings" — setState(_index = i). The whole content pane is rebuilt from scratch, so every screen's state (filters, search text, loaded page) is discarded on each rail move. The rail scrolls: on a short window the last rows (Promo Codes, Settings) need scrolling.  `_NavItem — Material+InkWell rows inside a SingleChildScrollView (NOT NavigationRail, no Keys); selected row gets shellRaised ground plus a 4x20 crimson _ActiveBar`
  - [ ] Wordmark "BACKOFFICE" (PortalArea.wordmark, upper-cased by _Logo) with tooltip "Switch console" — Switches PortalArea and resets _index to 0.  `PopupMenuButton<int> around the wordmark + expand_more chevron`
  - [ ] Account menu (tooltip t.language "Language"); items t.english "English", t.arabic "العربية" (both CheckedPopupMenuItem), divider, t.signOut "Sign out" — Language items call LocaleController.setLanguage; 'Sign out' calls AuthService.signOut and returns to _SignInScreen.  `PopupMenuButton<String> boxed to 24x24 with an Icons.unfold_more glyph, in the footer _UserCard`
  - [ ] Footer user card — "Bailey Backoffice" over t.backofficeOperator "Backoffice operator", avatar initials "BB" — Displays session.displayName and the area's accountRole. _UserCard.initialsOf is the only logic here.  `_UserCard (static, not tappable except the trailing menu)`

### ConsoleBell (header notification bell + its panel)
*Read the operator's own in-app inbox (GET /api/notifications, scoped server-side to the caller's token) without leaving the page.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/shell/console_bell.dart`
- reached by: Top-right of the header on rail items 0 Dashboard, 1 Orders, 5 Onboarding, 6 Carriers, 7 Riders, 10 Statements, 12 Promo Codes. NOT present on Categories, Catalog, Banners, Areas, Finance, Offers, Settings — those screens predate the console chrome.
- covered by: test/backoffice/promotions_screen_test.dart 'Notification bell' group — DRIVES it: taps the bell, asserts the unread count, the listed inbox, that exactly the shown messages are marked read, the error state, and the greyed no-client state.
- states: Loading: 20px spinner inside the panel · Empty: 'Nothing has come in yet.' · List error: 'Could not load notifications.' + the error text + Try again · Partial mark-read failure: footer notice 'Some messages could not be marked read.' · markAllRead failure: 'That did not go through. Try again.' · No api (null NotificationApi): box greyed, tooltip 'Notifications unavailable', tap does nothing · Badge suppressed entirely when the count endpoint fails (never a stale number)

  - [ ] Bell, tooltip "Notifications" / "N unread notifications" / "Notifications unavailable" — Opens/closes the 360px panel; opening triggers _load() which fetches inbox(limit:20) and then POSTs /{id}/read for exactly the messages shown. Badge polls unreadCount every 45s.  `MenuAnchor builder → InkWell over a 36px ConsoleSurface.control box with Icons.notifications_none and a _CountBadge (capped '99+')`
  - [ ] no l10n getter — "Mark all as read" (only drawn when _countKnown && _unread > 0) — POST markAllRead; zeroes the badge and clears every dot in the loaded list.  `_PanelAction (InkWell + crimson 12px text)`
  - [ ] no l10n getter — "Try again" (error state only) — Re-runs _load().  `_PanelAction`

### OverviewScreen ("Operations Dashboard")
*Read the platform's four headline numbers, the week's order shape, and what just happened.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/overview_screen.dart`
- reached by: Sign in → rail item 0 "Dashboard" (the landing screen).
- covered by: test/backoffice/overview_screen_test.dart — mounts only. It exercises many data states (movements, falling movement, no baseline, derived feed, unreadable store count) and three window widths, but taps nothing: Refresh, the bell and the Total Orders → Orders jump are undriven.
- states: Loading: KPI values render as '—' · Page error: _ErrorBanner 'Could not load the overview. <error>' + Retry · Storefront count unreadable: that card alone shows '—' / 'Unavailable' · Series absent: no % movement at all (never a percentage of zero); caption becomes 'Counted from the N most recent orders.' · Empty week: 'No orders in the last seven days.' · Feed absent: activity rows derived from loaded orders + the sentence 'The activity feed did not answer…' · Feed empty: 'Nothing has happened yet.' · Below 780px content width the chart and the 380px activity card stack

  - [ ] no l10n getter — KPI card "Total Orders" — Clicking jumps the rail to item 1, Orders Ledger. This is an invisible affordance — the card looks exactly like the other three, which do nothing when clicked.  `ConsoleKpiCard wrapped in InkWell (onTap: widget.onShowOrders) and a Tooltip 'Last 7 days: N orders · the 7 days before: M'`
  - [ ] no l10n getter — KPI cards "Active Merchants", "Active Riders", "Today's Revenue" — Read-only. Merchants = storeApi.browse(size:1).totalElements; Riders = distinct riderId over the loaded 100-order window; Revenue = the server's delivered value for today, or a client sum over the window when the series is down.  `ConsoleKpiCard (no onTap)`
  - [ ] no l10n getter — tooltip "Refresh" — _refresh() — re-reads stats, 100 orders, store count, 14-day series and the 20-entry activity feed. The page also polls every 30s.  `ConsoleIconAction (Icons.refresh)`
  - [ ] ConsoleBell — See the ConsoleBell entry.  `ConsoleBell`
  - [ ] no l10n getter — "Retry" on the error banner — _refresh().  `TextButton inside _ErrorBanner`
  - [ ] Chart columns (hover only) — tooltip "<Day> · N placed · M delivered" — Hover reveals the day's two counts; the band scrolls sideways.  `_Column/_Bar inside a horizontally scrolling _BarBand`

### DashboardScreen ("Orders Ledger") — the cross-merchant order table
*Monitor every order on the platform and open the one support is being phoned about.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/dashboard_screen.dart`
- reached by: Sign in → rail item 1 "Orders" (or click the Total Orders KPI on rail item 0).
- covered by: test/backoffice/orders_ledger_test.dart — DRIVES: taps the 'Delivered' pill and asserts the request, types in the search box, opens two rows, and walks the whole cancel flow. Plus test/live/order_ripple_test.dart, which renders this screen from bytes a real api-dev deployment returned.
- states: Loading: centred spinner (only while _orders is empty) · Error: _ErrorCard 'Could not load orders. <error>' with a Retry _DialogButton · Empty: 'No orders match this filter.' · Footer: 'Showing N of the M most recent orders.' · Rider unassigned cell reads 'Unassigned'; no placedAt renders '—'

  - [ ] no l10n getter — search box, hint "Search Order ID, Customer..." — Client-side filter over the loaded 50-row page only — matches id, customerId, merchantId, storeName, riderId. There is no search parameter on /api/orders.  `ConsoleSearchField (width 272) wrapping a borderless TextField`
  - [ ] no l10n getter — "Today", tooltip "Show only orders placed today" / "Showing orders placed today" — Two-state client filter on placedAt >= midnight local.  `_TodayButton (bespoke Material+InkWell, tints brandSoft when on)`
  - [ ] State pills: "All", "Preparing", "Picked up", "Delivered", "Placed", "Accepted", "Ready", "Cancelled" (labels from OrderStatus.label) — Sets _filter and re-requests /api/orders?status=… size=50 server-side. Eight pills, not the four the design draws.  `ConsoleFilterPills → _Pill (Material+InkWell, radius 20)`
  - [ ] Row (whole row clickable; the id cell is painted crimson to imply it) — Opens _OrderDetailDialog for that order.  `ConsoleTableRow onTap → InkWell`
  - [ ] no l10n getter — tooltip "Refresh · updates every 10s" — _refresh(); the table also polls every 10 seconds.  `ConsoleIconAction`
  - [ ] ConsoleBell — See the ConsoleBell entry.  `ConsoleBell`
  - [ ] Horizontal scroll of the table — Below 980px the card scrolls sideways rather than squeezing columns.  `ConsoleTable(minWidth: 980) → SingleChildScrollView(horizontal)`

### _OrderDetailDialog (order detail + support cancellation)
*Read one order in full, and cancel it for support reasons — the only write the back office has over an order.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/dashboard_screen.dart:320`
- reached by: Rail item 1 Orders → click any table row.
- covered by: test/backoffice/orders_ledger_test.dart — DRIVES: 'offers no cancellation on an order the server did not offer it on' and 'will not cancel without a reason, and asks twice' (types the reason, presses Cancel order, then Yes, cancel it).
- states: Rows: Merchant, Customer, Rider, Items ('N in M lines'), Total, Payment, Address, Placed, and 'Cancelled because' when a reason exists · No cancel section at all when availableActions lacks cancel · Failure: 'Could not cancel this order. <error>' in critical red, buttons re-enabled · Success: dialog pops true and the ledger refreshes

  - [ ] no l10n getter — "Reason for cancelling" (hint) — Types the reason. Empty reason keeps both cancel buttons disabled — the server would accept an empty one, this screen refuses.  `TextField (maxLines 2) under the heading "Support cancellation"`
  - [ ] **[destructive]** no l10n getter — "Cancel order" — First press only arms the confirmation (_confirming = true); it does not call the API.  `_DialogButton(destructive: true)`
  - [ ] **[destructive]** no l10n getter — "Yes, cancel it" (becomes "Cancelling…") — DESTRUCTIVE — POSTs OrderAction.cancel with the typed reason. The customer AND the shop are both notified, the reason is stored on the order, and there is no undo. Only drawn when the server listed `cancel` in the order's availableActions.  `_DialogButton(destructive: true), replaces the button above once armed`
  - [ ] no l10n getter — "Close" — Pops with false; disabled while a cancel is in flight.  `_DialogButton`

### CategoriesScreen (the platform taxonomy)  — no driving test
*See the whole category tree merchants pick from, and add to it. BACKOFFICE-only server-side (@PreAuthorize on Product Service).*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/categories_screen.dart`
- reached by: Sign in → rail item 2 "Categories".
- states: Loading: centred CircularProgressIndicator · Error: 'Could not load categories: <error>' (no retry control — the only way back is to leave the rail item and return) · Subtitle counts the flattened tree: 'N categories. Merchants choose from this list.' · Depth is drawn by indentation (folder_outlined at depth 0, subdirectory_arrow_right below)

  - [ ] no l10n getter — "New category" — Opens _AddCategoryDialog with the current roots.  `FloatingActionButton.extended (brand fill, Icons.add), bottom-right`
  - [ ] Category rows — Read-only. There is no rename, no re-parent and no delete on this screen at all — creation is the only write.  `ListTile inside a SoftCard — NOT tappable`

### _AddCategoryDialog  — no driving test
*Create one category, optionally under a parent.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/categories_screen.dart:127`
- reached by: Rail item 2 Categories → "New category" FAB.
- states: 409 from the service → SnackBar 'A category with that name already exists here' (uniqueness is on (name, parent)) · Any other DioException → 'Could not create the category' · Empty name → button does nothing at all, with no message

  - [ ] no l10n getter — "Name" (labelText) — The category name. Empty name makes Create a silent no-op (the button neither errors nor closes).  `TextField (autofocus)`
  - [ ] no l10n getter — "Parent" (labelText); items "Top level" plus every existing category, indented — Sets parentId; null = root.  `DropdownButtonFormField<String>`
  - [ ] no l10n getter — "Create" / "Cancel" — Create POSTs createCategory(name, parentId) and reloads.  `ElevatedButton / TextButton`

### CatalogScreen ("Live catalog")
*Look at exactly what a customer would see — the public browse endpoint, ACTIVE products only across every merchant.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/catalog_screen.dart`
- reached by: Sign in → rail item 3 "Catalog".
- covered by: test/backoffice/catalog_screen_test.dart — mounts only (6 tests: card rendering, image preview presence, layout at narrow/wide widths, fills its width, empty state). The search field and Search button are undriven.
- states: Loading: centred spinner · Error: 'Could not load: <error>' · Empty: 'No live products yet. Publish one from the Merchant Portal.' · Every card carries a fixed 'Live' DeliveryStatusBadge — the endpoint returns ACTIVE only · Grid is SliverGridDelegateWithMaxCrossAxisExtent(340) so column count changes with window width · Deliberately no edit/delete anywhere: the back office looks at the catalog, it does not change it

  - [ ] no l10n getter — "Search products" (labelText, prefix search icon) — Pressing Enter re-requests browse(search: …) server-side.  `TextField with onSubmitted`
  - [ ] no l10n getter — "Search" — Same as Enter — re-requests with the current text.  `ElevatedButton`
  - [ ] Product photo — Opens showProductImagePreview (full-size gallery) — only when the product actually has images.  `DeliveryProductImage with onTap (openLabel "Open full-size photo", emptyLabel "No photo", unavailableLabel "Image unavailable")`

### Product image preview overlay (showProductImagePreview)
*View a merchant's full-size photos.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/catalog_screen.dart:127 (words) — widget lives in delivery_design_system`
- reached by: Rail item 3 Catalog → click a product photo that has at least one image.
- covered by: test/backoffice/catalog_screen_test.dart asserts every card offers the preview, but never opens it.
- states: Single image: paging controls have nothing to move to · Broken/expired URL: 'Image unavailable'

  - [ ] _previewWords: untitled "Photo", unavailable "Image unavailable", close "Close", previous "Previous", next "Next", position "N of M" — Close dismisses; Previous/Next page through product.imageUrls; the position line counts them.  `Design-system preview overlay (buttons supplied by ProductPreviewWords)`

### BannersScreen (two-tab home-screen editorial)  — no driving test
*Host the two editorial jobs — the customer home banner rail, and the artwork on the category strip.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/banners_screen.dart:14`
- reached by: Sign in → rail item 4 "Banners".
- states: The TabBar is the only chrome — this screen has no ConsoleTopbar and no bell

  - [ ] no l10n getter — tabs "Banners" and "Category pictures" — Switches between _BannerList and _CategoryImages. Both tabs keep their own state while the screen is mounted.  `TabBar/TabBarView inside DefaultTabController (crimson label + indicator)`

### _BannerList (Banners tab)  — no driving test
*Create, edit, illustrate, withdraw and restore the campaign banners on the customer home rail.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/banners_screen.dart:50`
- reached by: Rail item 4 Banners → "Banners" tab (the default).
- states: Loading: centred spinner · Error: 'Could not load banners: <error>' · Empty: 'No banners yet. The home rail is hidden until there is one.' · Per-banner status chip 'Live' / 'Withdrawn' · No artwork: brandSoft placeholder tile; expired presigned URL: broken_image_outlined box · Destination line: 'Position N · Informational, not tappable' / '· Opens store X' / '· Opens category X' / '· Opens <url>' · Errors: 422/400 → the server's message or 'That destination does not exist'; 403 → 'Your account cannot edit banners'; non-HTTP → 'Something went wrong: <e>'; picker failure → 'Could not open the file picker: <e>' · All buttons disable together while _busy

  - [ ] no l10n getter — "New banner" — Opens _BannerDialog with no existing banner.  `FloatingActionButton.extended (Icons.add)`
  - [ ] no l10n getter — "Edit" — Opens _BannerDialog seeded with this banner; saving PUTs the whole record.  `TextButton.icon (Icons.edit_outlined)`
  - [ ] no l10n getter — "Add artwork" / "Replace artwork" — Opens the OS file picker via file_selector (jpg/jpeg/png/webp), reads the bytes and POSTs uploadBannerImage. Replacing overwrites the live artwork immediately.  `TextButton.icon (Icons.image_outlined)`
  - [ ] **[destructive]** no l10n getter — "Withdraw" / "Put back" — DESTRUCTIVE (customer-visible, no confirmation): 'Withdraw' calls the dedicated withdraw endpoint and the banner disappears from every customer's home screen at once. 'Put back' is an ordinary update(active: true). Neither asks first.  `TextButton.icon (visibility_off_outlined / visibility_outlined)`
  - [ ] no l10n getter — "Previous" / "Next" with "Page N of M" — Pages the 20-per-page listing.  `TextButton.icon pair (_pager), hidden when totalPages <= 1`

### _BannerDialog (new / edit banner)  — no driving test
*Compose one banner: its words, where tapping it goes, its place in the rail, and whether it is live.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/banners_screen.dart:405`
- reached by: Rail item 4 Banners → "New banner" FAB, or "Edit" on a banner card.
- states: Inline _error text in brand crimson for each of the three validation failures · On edit, a note: 'Artwork is uploaded from the list, not here — it needs the banner to exist first.'

  - [ ] no l10n getter — "Title" (maxLength 160, autofocus) — Required — empty shows 'A banner needs a title'.  `TextField`
  - [ ] no l10n getter — "Subtitle", helper "Optional — the smaller line under the title" (maxLength 240) — Optional second line.  `TextField`
  - [ ] no l10n getter — "Tapping it opens"; options "No destination", "Store", "Category", "Web link" — Chooses the link kind; anything but 'No destination' reveals the target field.  `DropdownButtonFormField<BannerLinkKind>`
  - [ ] no l10n getter — target field, label "Store id or slug" / "Category id" / "https://…", helper "Checked when you save — a destination that does not exist is refused" — The destination. STORE/CATEGORY are validated server-side (422 if they do not exist).  `TextField (conditional)`
  - [ ] no l10n getter — "Position", helper "Lowest first on the home rail" — Must parse to 0..999, otherwise 'Position must be a number from 0 to 999'.  `TextField (number keyboard)`
  - [ ] **[destructive]** no l10n getter — "Live", subtitle "Off keeps it here but off the customer home screen" — Sets active on create/update — a customer-visible flag with no confirmation.  `SwitchListTile (brand thumb)`
  - [ ] no l10n getter — "Create" / "Save" and "Cancel" — Validates locally, then pops a _BannerDraft the list POSTs or PUTs.  `ElevatedButton / TextButton`

### _CategoryImages (Category pictures tab)  — no driving test
*Decide which top-level categories appear in the customer home strip, and give each one its picture.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/banners_screen.dart:578`
- reached by: Rail item 4 Banners → "Category pictures" tab.
- states: Loading / 'Could not load categories: <error>' · Header counts: 'N of M top-level categories appear in the customer home strip.' · Row subtitle: 'Not in the home strip' or 'Filters the storefront by <vertical>' · 409 → 'Another category already stands for that vertical' (the vertical is uniquely indexed) · Other errors → 'Could not save the category' · Only root categories are listed — a leaf can never be given a picture here · Avatar falls back to a category glyph, or broken_image_outlined on a dead URL

  - [ ] **[destructive]** no l10n getter — "Vertical" dropdown; options "None" plus every StoreVertical not already taken — Immediately PUTs setVertical — no confirmation. Choosing a vertical puts the category into the customer home strip; choosing 'None' removes it from the strip.  `DropdownButtonFormField<StoreVertical?> (keyed on the server's last confirmed value so a refused change snaps back)`
  - [ ] no l10n getter — "Add picture" / "Replace" — File picker → uploadCategoryImage. Replacing overwrites what customers see.  `TextButton.icon (Icons.image_outlined)`

### OnboardingScreen ("Merchants Directory" — the partner review queue)
*Decide who joins the platform (shops, delivery companies, riders), and manage partners who are already live.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/onboarding_screen.dart`
- reached by: Sign in → rail item 5 "Onboarding".
- covered by: test/backoffice/onboarding_screen_test.dart — DRIVES heavily: tab switch, row Approve, Decline (empty-reason refusal and verbatim send), category filter via the popup, search, Edit partner (only-changed-fields PATCH), Suspend, Reinstate, and the inert columns.
- states: Loading: spinner inside a ConsoleCard · Error: cloud_off + 'Could not load applications.' + the error + a 'Try again' ConsoleButton · Empty: 'Nobody has applied yet.' (All) / 'Nothing waiting to be read.' (Pending) / 'No partner matches that search.' · Auto-approval line above the table (read-only): 'Every application is read by a person…' or '<kinds> are approved automatically…', always ending 'Changed in Settings › Approvals'. Drawn only when the AutoApproval read succeeded · Suspended partners show a critical 'Suspended' pill in the Status column, with the real application status on hover · Products and Orders columns are permanently ConsoleNoValue dashes; footer ConsoleInertNote 'Not aggregated — Product and order counts per partner are not aggregated by any endpoint yet.' · Write failures surface the server's own message via SnackBar ('That did not go through. Try again.' as fallback)

  - [ ] no l10n getter — tabs "All Partners" and "Pending Approval (N)" — Switches endpoint: queue() for pending (oldest-first) vs all(). The bracketed count is suppressed while loading rather than shown as 0.  `ConsoleFilterTabs (opens on Pending)`
  - [ ] no l10n getter — search, hint "Search merchants..." — Client filter over business name, contact name, contact email and reference.  `ConsoleSearchField (232px)`
  - [ ] no l10n getter — "Category" filter (tooltip "Filter by category"); options "All categories" plus the categories actually present — Client filter on details['businessType'] ?? details['vehicleType'] ?? kind.label.  `ConsoleSelect → ConsoleFilterButton + showMenu (PopupMenuItem<int>)`
  - [ ] **[destructive]** no l10n getter — row action tooltip "Approve" (pending rows) — MONEY/IDENTITY consequence — one click, no confirmation: POST approve. The applicant is emailed and an account is provisioned with the MERCHANT/CARRIER/DELIVERY realm role. Not reversible from this screen (only Suspend afterwards).  `ConsoleRowAction (Icons.check)`
  - [ ] **[destructive]** no l10n getter — row action tooltip "Decline" (pending rows) — Opens _DeclineDialog; the typed reason is sent to the applicant verbatim.  `ConsoleRowAction (Icons.close, destructive tint)`
  - [ ] no l10n getter — row action tooltip "Edit partner" (decided rows) — Opens _EditPartnerDialog; PATCHes only changed fields and writes an audit row.  `ConsoleRowAction (Icons.edit_outlined)`
  - [ ] **[destructive]** no l10n getter — row action tooltip "Suspend partner" / "A declined application has no standing to withdraw" / "Suspension is not available in this build" — Opens _SuspendDialog. Disabled for SUBMITTED/IN_REVIEW/REJECTED rows (server answers 422).  `ConsoleRowAction (Icons.block, destructive tint)`
  - [ ] no l10n getter — row action tooltip "Reinstate partner" (suspended rows) — Opens _UnsuspendDialog; gives the realm role back.  `ConsoleRowAction (Icons.lock_open)`
  - [ ] Row body (whole row) — Opens the _ApplicationDetail drawer.  `ConsoleTableRow onTap`
  - [ ] no l10n getter — tooltip "Refresh" — Re-reads the current tab; the queue also polls every 30s. Disabled while loading.  `ConsoleIconAction`
  - [ ] ConsoleBell — See the ConsoleBell entry.  `ConsoleBell`

### _ApplicationDetail (partner drawer)
*Everything a decision rests on: contacts and their verification marks, the wizard's answers, the uploaded papers, the outcome, and the record's history.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/onboarding_screen.dart:759`
- reached by: Rail item 5 Onboarding → click a table row (opens showConsoleDrawer, 460px, right edge).
- covered by: test/backoffice/onboarding_screen_test.dart — DRIVES: opens the drawer by row name, asserts the wizard block presence/absence, approves a document, refuses one with a typed reason, asserts the unverified-email warning, and reads the merged history.
- states: Unverified email on an undecided application: an amber _Note 'This email address was never verified…' · 'From their application' section absent when details is empty · Documents: spinner; 'Could not load the documents.'; 'No documents uploaded. Applications taken before the document step existed carry none.'; per-row badges Waiting / Approved / Refused / Replaced; refusal reason under the name · Decided application: document verdict buttons disappear (readOnly), Outcome section appears ('Declined by X …', 'Approved …. Account created…', 'Approved…, but setting the account up did not finish. Somebody has to look at this.') · History: merged corrections + standing changes newest-first; 'Nothing has been changed on this record.'; partial failure 'Could not read the corrections or the standing changes. This list is incomplete.' · History section absent entirely when the build has no PartnerManagementApi · Approve/Decline footer absent on decided applications

  - [ ] no l10n getter — "Edit details" — Pops the drawer and opens _EditPartnerDialog.  `ConsoleButton(tone: outlined, Icons.edit_outlined) in the Applicant section header`
  - [ ] no l10n getter — document row tooltip "Open the document" — openExternalLink(doc.viewUrl) — opens the short-lived presigned GET in a new browser tab. Absent when storage could not sign a URL.  `ConsoleRowAction (Icons.open_in_new)`
  - [ ] no l10n getter — document row tooltip "Approve this document" — POST approveDocument. Only on pending, non-superseded documents of an undecided application.  `ConsoleRowAction (Icons.check)`
  - [ ] **[destructive]** no l10n getter — document row tooltip "Refuse this document" — Opens _DocumentReasonDialog; the reason is shown to the applicant verbatim.  `ConsoleRowAction (Icons.close, destructive)`
  - [ ] **[destructive]** no l10n getter — "Approve" / "Approve and set up the company" (carriers) — IDENTITY consequence, one click: pops the drawer and approves the application (account provisioned, email sent).  `ConsoleButton(tone: solid, Icons.check), Expanded`
  - [ ] **[destructive]** no l10n getter — "Decline" — Pops the drawer and opens _DeclineDialog.  `ConsoleButton(tone: outlined, Icons.close)`
  - [ ] no l10n getter — "Try again" (documents section, and History section) — Re-runs the documents load / the audit+standing load.  `ConsoleButton(tone: outlined)`
  - [ ] no l10n getter — tooltip "Close" — Navigator.pop.  `ConsoleIconAction (Icons.close) in the drawer header; barrier tap also dismisses`

### _DeclineDialog
*Refuse an application with a reason the applicant reads word for word.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/onboarding_screen.dart:1295`
- reached by: Rail item 5 Onboarding → row 'Decline' action, or the drawer's Decline button.
- covered by: test/backoffice/onboarding_screen_test.dart — DRIVES both the empty-reason refusal and the verbatim send.
- states: Copy above the field: 'They are sent this word for word. Say what would have to change.' · Decline stays disabled until non-whitespace text exists

  - [ ] no l10n getter — reason field, hint "The address given is outside the area we cover" (maxLines 3, maxLength 500, autofocus) — The verbatim refusal text.  `TextField`
  - [ ] **[destructive]** no l10n getter — "Decline" — DESTRUCTIVE — POST reject(id, reason). The applicant is told; the application cannot be un-declined from this console.  `ConsoleButton(tone: solid); disabled while the reason is blank`
  - [ ] no l10n getter — "Cancel" — Pops with null; nothing is sent.  `ConsoleButton(tone: outlined)`

### _DocumentReasonDialog
*Refuse one uploaded paper with the reason the applicant is shown.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/onboarding_screen.dart:1174`
- reached by: Rail item 5 Onboarding → row → drawer → Documents → 'Refuse this document'.
- covered by: test/backoffice/onboarding_screen_test.dart 'refusing a paper requires the reason the applicant will read' — DRIVES.
- states: Title 'Refuse <document kind>' — the typed kind's label, or the server's own wire spelling for a kind this build does not know · Failure → critical SnackBar with the server's message/detail

  - [ ] no l10n getter — reason field, hint "The photo is too blurred to read the expiry date" (maxLines 3, maxLength 500, autofocus) — The verbatim reason.  `TextField`
  - [ ] **[destructive]** no l10n getter — "Refuse document" — DESTRUCTIVE — POST rejectDocument(applicationId, documentId, reason); the applicant must re-upload.  `ConsoleButton(tone: solid); disabled while blank`
  - [ ] no l10n getter — "Cancel" — Sends nothing.  `ConsoleButton(tone: outlined)`

### _EditPartnerDialog (correct a partner's record)
*Correct the four audited fields; every change writes an audit row.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/onboarding_screen.dart:1627`
- reached by: Rail item 5 Onboarding → row 'Edit partner' action, or the drawer's 'Edit details'.
- covered by: test/backoffice/onboarding_screen_test.dart 'sends only the fields that actually changed' — DRIVES.
- states: Standing note: 'A field cannot be emptied — clearing one leaves it as it was…' · Phone changing: amber _Note 'Changing the phone number marks it unverified…' · Bad email: 'That does not look like an email address.' in critical red · On success the SnackBar appends ' The new phone number is now unverified.' when the server confirms it

  - [ ] no l10n getter — "Business name" — Sent only if it differs from the original.  `TextField`
  - [ ] no l10n getter — "Contact name" — Sent only if changed.  `TextField`
  - [ ] no l10n getter — "Contact email" (emailAddress keyboard) — Sent only if changed; a light shape check blocks Save on an obvious typo. Does NOT change how they sign in.  `TextField`
  - [ ] **[destructive]** no l10n getter — "Contact phone" (phone keyboard) — Sent only if changed — and changing it marks the number UNVERIFIED server-side.  `TextField`
  - [ ] no l10n getter — "Save changes" — PATCH with only the changed fields.  `ConsoleButton(tone: solid); dead until something differs and the email looks valid`
  - [ ] no l10n getter — "Cancel" — Discards.  `ConsoleButton(tone: outlined)`

### _SuspendDialog
*Withdraw a live partner's standing, with a reason and a note kept on the record.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/onboarding_screen.dart:1787`
- reached by: Rail item 5 Onboarding → 'Suspend partner' on an approved/provisioned/failed row.
- covered by: test/backoffice/onboarding_screen_test.dart — DRIVES (opens it, fills it, asserts the POST).
- states: A critical _Note states exactly what suspension does, naming the realm role that changes · Note field carries the caption 'Kept on the record and shown to whoever asks later…' · Endpoint is idempotent, so pressing it on an already-suspended partner is safe

  - [ ] no l10n getter — "Reason"; button reads "Choose a reason" then the chosen SuspensionReason.label — Picks the server enum. Required.  `ConsoleSelect (ConsoleFilterButton + showMenu) over SuspensionReason.values`
  - [ ] no l10n getter — "What happened", hint "Three chargebacks in a week, all disputed by the cardholder" (maxLines 3, maxLength 500) — The human note. Required.  `TextField`
  - [ ] **[destructive]** no l10n getter — "Suspend partner" — DESTRUCTIVE — POST suspend. Revokes the MERCHANT / CARRIER / DELIVERY realm role platform-wide: the partner can still sign in and read history, but every committing action (taking an order, claiming a job, changing a menu) is refused until reinstated.  `ConsoleButton(tone: destructive); dead until reason AND note exist`
  - [ ] no l10n getter — "Cancel" — Sends nothing.  `ConsoleButton(tone: outlined)`

### _UnsuspendDialog
*Give a partner's realm role back.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/onboarding_screen.dart:1889`
- reached by: Rail item 5 Onboarding → 'Reinstate partner' on a suspended row.
- covered by: test/backoffice/onboarding_screen_test.dart 'a suspended partner says so in the directory and offers reinstatement' — DRIVES.
- states: Copy names the exact role being restored

  - [ ] no l10n getter — "Note (optional)", hint "Chargebacks resolved with the bank" (maxLines 2, maxLength 500) — Optional note recorded with the standing change.  `TextField`
  - [ ] no l10n getter — "Reinstate" — POST unsuspend; re-grants the role, so the partner can take work again at their next sign-in.  `ConsoleButton(tone: solid) — always enabled, no note required`
  - [ ] no l10n getter — "Cancel" — Sends nothing.  `ConsoleButton(tone: outlined)`

### ProvidersScreen ("Fleet Carriers")
*The delivery-marketplace register: onboard a company, read its score and payout state, staff it, and stop it.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/providers_screen.dart`
- reached by: Sign in → rail item 6 "Carriers".
- covered by: test/backoffice/providers_screen_test.dart — DRIVES: search, suspend from a card, the bank re-check (both outcomes), the drawer, and 'Give someone access'.
- states: Loading: spinner in a ConsoleCard · Error: 'Could not load providers: <error>' (no retry button) · Empty: 'No delivery providers yet.' / 'No carrier matches that search.' · Cards sorted platform fleet → external companies → merchant fleets, 260px each in a Wrap · Score cell: '—' when unranked, '<n>?' greyed when provisional, crimson when measured · Riders cell: 'All' for the in-house fleet, '…' while loading, amber zero for a carrier with none · Payout warnings on the card: 'No payout account — every payment to this carrier will fail.' (critical) or 'The bank has not confirmed this account.' (caution) · Scores failing to load leaves the register rendered without scores · Write failures: the server's `detail`, or 'That handle is already taken' on 409, or 'That did not work: <e>'

  - [ ] no l10n getter — search, hint "Search carriers..." (in the topbar) — Client filter on name and slug over the loaded 50.  `ConsoleSearchField`
  - [ ] no l10n getter — "Onboard a company" — Opens _OnboardDialog. This is the only way a carrier enters the register.  `ConsoleButton(tone: solid, Icons.add) in the topbar`
  - [ ] no l10n getter — "Manage" (per card) — Opens the carrier drawer (score / payout / logins / riders).  `ConsoleButton(tone: tinted), Expanded`
  - [ ] **[destructive]** no l10n getter — "Suspend" / "Reinstate" (per card) — DESTRUCTIVE — one click calls suspend()/reinstate() straight away. A suspended carrier cannot resume itself. Disabled for the in-house platform fleet unless it is already suspended (stopping it would stop every order with no other carrier).  `ConsoleButton(tone: outlined), Expanded — NO confirmation dialog`
  - [ ] ConsoleBell — See the ConsoleBell entry (this screen was the last to get a live bell).  `ConsoleBell`

### Carrier drawer (score / payout / logins / riders)
*Everything about one carrier that does not fit on the card: its score parts, its bank account, who can sign in for it, and its roster.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/providers_screen.dart:501`
- reached by: Rail item 6 Carriers → "Manage" on a carrier card.
- covered by: test/backoffice/providers_screen_test.dart — DRIVES the drawer, the bank re-check and 'Give access'; the chip crosses (release rider / remove staff) are NOT driven by any test.
- states: Score: 'No score yet — this carrier has not been ranked.'; provisional shows a 'Provisional' ConsoleQuietChip and 'Only N orders so far, so this is mostly an assumption.'; measured shows completion %, claim time and time on road · Payout: 'Not paid through this register.' for non-external; critical note for a missing account; caution note quoting payoutDetail for an unconfirmed one · Logins: 'Loading logins…'; caution note 'Nobody can sign in for this carrier yet…' when empty; section absent entirely for platform/merchant fleets · Riders: 'Loading riders…'; 'No riders yet — this carrier cannot take work until it has some'; 'Every rider not assigned to another fleet' for the in-house fleet

  - [ ] no l10n getter — "Check with the bank" (unconfirmed) / "Re-check account" (confirmed) — Pops the drawer, then POSTs verifyPayout and reports what actually came back.  `ConsoleButton in the Payout section header; absent when there is no account on file`
  - [ ] no l10n getter — "Give someone access" (external companies only) — Pops the drawer and opens _AddStaffDialog.  `ConsoleButton in the Logins section header`
  - [ ] no l10n getter — "Add a rider" (not shown for the in-house fleet) — Pops the drawer and opens _AddRiderDialog.  `ConsoleButton in the Riders section header`
  - [ ] **[destructive]** Rider chip cross (tooltip = the full Keycloak subject) — DESTRUCTIVE — releaseRider(ref) with no confirmation: the rider is moved out of this fleet back to the in-house fleet.  `_RefChip with an InkWell Icons.close`
  - [ ] **[destructive]** Login chip cross (tooltip = the full subject) — DESTRUCTIVE — removeStaff(userRef) with no confirmation: that account can no longer administer the carrier.  `_RefChip with an InkWell Icons.close`
  - [ ] no l10n getter — tooltip "Close" — Navigator.pop.  `ConsoleIconAction in the drawer header (barrier tap also closes)`

### _OnboardDialog (onboard a delivery company)  — no driving test
*Register a new delivery company in the carrier register.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/providers_screen.dart:958`
- reached by: Rail item 6 Carriers → "Onboard a company".
- states: Inline error 'A carrier needs a name and a handle' or 'A handle is lower-case letters, digits and hyphens' · 409 from the server → 'That handle is already taken'

  - [ ] no l10n getter — "Name" (autofocus) — Required. Typing here auto-derives the handle until the handle is edited by hand.  `_ConsoleField (TextField)`
  - [ ] no l10n getter — "Handle", helper "Appears in config and URLs. Lower-case, no spaces." — Required, must match ^[a-z0-9][a-z0-9-]*$.  `_ConsoleField`
  - [ ] no l10n getter — "Payout account", helper "Must already exist at the bank, or every payment to them fails" — Optional at this step but a missing/incorrect account makes every later payment to the carrier fail silently until an order is delivered.  `_ConsoleField`
  - [ ] no l10n getter — "Contact (optional)" and "Phone (optional)" — Optional metadata.  `_ConsoleField x2`
  - [ ] no l10n getter — "Onboard" / "Cancel" — Onboard POSTs register(...) and reloads the register.  `ConsoleButton(solid) / ConsoleButton(outlined)`

### _AddStaffDialog ("Give someone access")
*Attach a Keycloak account that may administer one carrier.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/providers_screen.dart:1069`
- reached by: Rail item 6 Carriers → Manage → Logins → "Give someone access".
- covered by: test/backoffice/providers_screen_test.dart 'and one can be given access' — DRIVES (types a subject, presses Give access, asserts the POST).
- states: Explanatory copy above the field spells out what the grant allows and that it is limited to this carrier

  - [ ] no l10n getter — "Account id", helper "The user's Keycloak subject (sub)" (autofocus, submits on Enter) — The subject to grant. No validation and no lookup — a typo is accepted by the dialog and refused (or worse, accepted) by the server.  `_ConsoleField`
  - [ ] **[destructive]** no l10n getter — "Give access" — ACCESS GRANT — POST addStaff. That account can then see the carrier's score and riders and take it out of rotation.  `ConsoleButton(tone: solid) — enabled even when the field is empty`
  - [ ] no l10n getter — "Cancel" — Sends nothing.  `ConsoleButton(tone: outlined)`

### _AddRiderDialog ("Move a rider to this fleet")  — no driving test
*Move a rider from whichever fleet they are in now into this one.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/providers_screen.dart:1126`
- reached by: Rail item 6 Carriers → Manage → Riders → "Add a rider".
- states: Success SnackBar 'Rider moved to <carrier>'

  - [ ] no l10n getter — "Rider id", helper "Their Keycloak subject. They leave whichever fleet they are in now." (autofocus) — The rider's subject.  `_ConsoleField`
  - [ ] **[destructive]** no l10n getter — "Move" — A rider works for one fleet at a time, so this REMOVES them from their current carrier as a side effect.  `ConsoleButton(tone: solid) — enabled with an empty field`
  - [ ] no l10n getter — "Cancel" — Sends nothing.  `ConsoleButton(tone: outlined)`

### RidersScreen ("Riders Control Panel")  — UNREACHABLE
*Every rider assigned to a carrier, with presence, today's drops, seven-day duty hours and customer rating.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/riders_screen.dart`
- reached by: Sign in → rail item 7 "Riders".
- **unreachable:** The Region column is permanently empty and the design's second 'All regions' selector is deliberately NOT drawn: no rider record on this platform carries a work region, and there is no plan in the data model for one (riders_screen.dart:386-394). That is a finding, not a gap.
- covered by: test/backoffice/riders_screen_test.dart — DRIVES the carrier filter (opens the popup and picks a carrier) and asserts every degraded state; search and Refresh are undriven.
- states: Loading: spinner in a ConsoleCard · Error: 'Could not load the roster.' + error + 'Try again' ConsoleButton · Empty: 'No rider is assigned to a carrier yet.' / 'No rider matches that filter.' plus 'Riders who have never been moved to a company ride for the in-house fleet, and that roster is not enumerable.' · Status pill: On duty / Signal lost / Off duty / Unknown ('The tracking service did not answer' vs 'This rider has never gone on duty'), with 'seen Nm ago' underneath · Deliveries Today: a true 0 when the endpoint answered; a dash when it could not be read · Hours Online (7d): '0.0h' only when the service knows the rider and reports no shifts; dash when the lookup failed · Rating: '★ 4.8' with the rating count on hover; 'New' when nobody has rated; dash when the lookup failed — never a zero · Table scrolls horizontally below 1120px · Footer ConsoleInertNote about the empty Region column and the unlistable in-house fleet

  - [ ] no l10n getter — carrier selector, reads "All Carriers" or the chosen carrier's name (tooltip "Filter by carrier") — Client filter; only carriers that actually have riders on this page are offered.  `ConsoleSelect → ConsoleFilterButton + showMenu`
  - [ ] no l10n getter — search, hint "Search riders..." — Client filter on the rider's subject and the carrier name.  `ConsoleSearchField`
  - [ ] no l10n getter — tooltip "Refresh" — _reload() — rebuilds the whole N+1 join (register, then one roster per carrier) and clears ratings/duty hours. Presence + delivered counts also poll every 30s.  `ConsoleIconAction`
  - [ ] ConsoleBell — See the ConsoleBell entry.  `ConsoleBell`
  - [ ] Rows and cells (hover only) — This table is entirely read-only — there is no rider detail screen, no suspend, no message. Everything is hover text.  `ConsoleTableRow with NO onTap; tooltips on the name cell (full subject), status, deliveries, hours and rating`

### ZonesScreen ("Delivery areas") — back office copy  — no driving test
*Own the single list of delivery areas customers pick from and shops price against.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/zones_screen.dart`
- reached by: Sign in → rail item 8 "Areas". (Imported prefixed in portal_shell.dart:25 because delivery_merchant exports a different ZonesScreen with the same name.)
- states: Loading: centred spinner · Error: 'Could not load areas: <error>' (no retry) · Empty: SoftCard 'No areas yet' explaining that every shop then charges one flat fee · StatRow: 'In the picker' (amber with footnote 'flat fees everywhere' when zero) and 'Retired' · Retired rows carry a 'Retired' StatePill and a neutral accent · Standing SoftNote about what retiring actually does · All controls disable together while _busy

  - [ ] no l10n getter — "New area" — Opens _ZoneDialog empty.  `FloatingActionButton.extended (Icons.add_location_alt_outlined)`
  - [ ] no l10n getter — "Edit" (per area row) — Opens _ZoneDialog seeded; saving calls rename(name, region, sortOrder).  `TextButton`
  - [ ] **[destructive]** no l10n getter — "Retire" / "Reinstate" (per area row) — CUSTOMER-VISIBLE: 'Retire' removes the area from the address picker immediately (existing addresses and shop prices keep working); 'Reinstate' puts it back. One click each.  `TextButton — NO confirmation`

### _ZoneDialog (new / edit area)  — no driving test
*Name an area, group it, and place it in the picker.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/zones_screen.dart:227`
- reached by: Rail item 8 Areas → "New area" FAB or "Edit" on a row.
- states: Field-level validation messages 'Required' and 'A number' · Failure → SnackBar with the server's `detail` or 'That did not work: <e>'

  - [ ] no l10n getter — "Area name", helper "What a customer would call it — \"Hamra\", not \"District 4\"" (autofocus) — The picker label.  `TextFormField with validator 'Required'`
  - [ ] no l10n getter — "Region (optional)", helper "Groups areas in the picker — \"Beirut\", \"Mount Lebanon\"" — Optional grouping; blank is sent as null.  `TextFormField`
  - [ ] no l10n getter — "Order in the list", helper "Lower comes first; ties fall back to the name" — Sort order; defaults to 100 for a new area.  `TextFormField (number keyboard) with validator 'A number'`
  - [ ] no l10n getter — "Save" / "Cancel" — Validates the Form, then create() or rename().  `FilledButton (brand) / TextButton`

### ReconciliationScreen ("Reconciliation" — rail label "Finance")
*Answer 'what has not settled' — the money at risk, the cash riders are still carrying, and every settlement leg the bank was asked about.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/reconciliation_screen.dart`
- reached by: Sign in → rail item 9 "Finance".
- covered by: test/backoffice/reconciliation_screen_test.dart — DRIVES: taps the 'Posted' chip and asserts the request, opens the sync log, and walks the whole Banked → confirm / cancel flow. Also mounted against real settlement bytes in test/live/order_ripple_test.dart.
- states: Loading: centred spinner; Error: 'Could not load reconciliation: <error>' (no retry control) · Six StatTiles: At risk (green/critical), Cash on hand (info, caution once cash is older than 24h), Settled, In flight, Reversed, Abandoned · Cash on hand block hidden entirely when nobody is holding; SoftNote 'Cash has been out longer than a day…' when the oldest exceeds 24h; per-row 'Overdue' StatePill; the list is capped at 220px and sorted oldest-first · Empty table: 'Nothing here — every settlement in this view has completed.' · Bank reference cell shows '—' for a leg the bank never accepted · The transaction table scrolls both ways (DataTable inside two SingleChildScrollViews)

  - [ ] no l10n getter — tooltip "Refresh" — Re-reads summary, the filtered rows and the cash float.  `IconButton (Icons.refresh)`
  - [ ] no l10n getter — filter chips "Needs attention" (default), "Posted", "Failed", "Pending", "Compensated", "Abandoned" (labels from SettlementStatus.label) — 'Needs attention' calls unsettled(); each status calls byStatus(status). There is deliberately no 'everything' view.  `ChoiceChip row`
  - [ ] **[destructive]** no l10n getter — "Banked" (per cash holder) — MONEY, IRREVERSIBLE — opens the hand-over confirmation; confirming discharges that holder's ENTIRE cash balance. The ledger can discharge but not un-discharge.  `OutlinedButton.icon (Icons.account_balance_outlined)`
  - [ ] no l10n getter — tooltip "What the bank was told" (per transaction row) — Opens _SyncLogDialog for that leg.  `IconButton (Icons.receipt_long_outlined)`
  - [ ] Status badge (hover) — Hover reveals why a leg failed.  `DeliveryStatusBadge inside a Tooltip carrying failureReason`

### Hand-over confirmation ("Record a hand-over")
*Confirm, in money and order count, that a rider or company physically handed the cash over.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/reconciliation_screen.dart:45`
- reached by: Rail item 9 Finance → "Banked" on a cash holder row.
- covered by: test/backoffice/reconciliation_screen_test.dart 'asks before recording a hand-over' / 'cancelling records nothing' / 'confirming records it against that holder' — DRIVES all three.
- states: Body names the holder, the amount and the order count, and states 'This clears their whole balance and cannot be undone.' · Empty receipt → SnackBar 'Nothing was outstanding — somebody may have recorded this already.' · Success → 'Recorded <amount> from <holder>.'; failure → 'Could not record it: <e>'

  - [ ] **[destructive]** no l10n getter — "Yes, they banked it" — MONEY, IRREVERSIBLE — POST remit(holderRef); clears that holder's whole balance. No undo exists anywhere in the product.  `FilledButton`
  - [ ] no l10n getter — "Cancel" — Records nothing.  `TextButton`

### _SyncLogDialog ("what the bank was told")
*Read the exact request and response exchanged with core banking for one settlement leg.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/reconciliation_screen.dart:511`
- reached by: Rail item 9 Finance → the receipt icon at the end of any transaction row.
- covered by: test/backoffice/reconciliation_screen_test.dart 'the sync log shows what was sent and what came back' — DRIVES.
- states: Loading: 120px spinner · Error: 'Could not load the sync log: <error>' · Empty: 'The bank has not been asked about this yet.' · Missing payload renders as 'nothing recorded'

  - [ ] Payload bodies under "Sent" and "Received" — Selectable so the payload can be pasted into an email to the bank.  `SelectableText (monospace) inside a bordered box`
  - [ ] no l10n getter — "Close" — Dismisses.  `TextButton`

### StatementsScreen ("Statements")
*What the platform owes each shop, rider and delivery company over a period — and whether anybody outside the building has actually been told.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/statements_screen.dart`
- reached by: Sign in → rail item 10 "Statements".
- covered by: test/backoffice/statements_screen_test.dart — DRIVES: opens the drawer by row, opens Send, cancels it, confirms it, asserts the two 409 messages, and types a recipient for a counterparty with no address. The period picker and Refresh are undriven.
- states: Loading: 160px spinner in a ConsoleCard · Error: ConsoleCard 'The statements could not be loaded' + the error (no retry button; use Refresh) · Empty: 'Nobody traded in this period. That is an answer, not a failure — widen the dates.' · Unattributed block above the table: caution card 'Not attributed to anybody' with the amount, order count and the server's note; a single green line when genuinely clean; a plain warning sentence when the server sent no block at all · Direction pill: We owe (info) / They owe (caution) / Settled (positive) / Unknown (neutral) · 'Last sent' column reads 'Never' until something is sent, then a yyyy-MM-dd HH:mm stamp (the later of the server's and this session's) · Missing figures render '—', never 0.00 · Footer explains the dash rule; table scrolls horizontally below 1080px

  - [ ] no l10n getter — period button, reads "YYYY-MM-DD → YYYY-MM-DD" (opens on the current month to date) — Sets the range and reloads. A range over StatementsApi.maxRangeDays (366) is refused client-side with the old period left standing.  `ConsoleFilterButton (Icons.date_range_outlined) → showDateRangePicker (helpText "Statement period", saveText "Use period")`
  - [ ] no l10n getter — tooltip "Refresh" — Re-reads the counterparty listing. Disabled while loading.  `ConsoleIconAction`
  - [ ] ConsoleBell — See the ConsoleBell entry.  `ConsoleBell`
  - [ ] **[destructive]** no l10n getter — "Send" (per counterparty row) — Opens _SendDialog — the only control in the portal that puts a figure in front of a business the platform does not employ.  `ConsoleButton(icon: Icons.send_outlined) with a busy spinner; every Send in the table disables while one is in flight`
  - [ ] Row (whole row) — Opens the _StatementDetail drawer (560px) for that counterparty and period.  `ConsoleTableRow onTap`

### _StatementDetail (statement drawer)
*One counterparty's full statement for the chosen period: the summary lines, the net, and the itemised orders.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/statements_screen.dart:530`
- reached by: Rail item 10 Statements → click a counterparty row.
- covered by: test/backoffice/statements_screen_test.dart 'renders the summary lines, the bottom line and the orders behind them' — DRIVES (opens it by row).
- states: Loading: 200px spinner · Error: 'The statement could not be loaded: <error>' · Empty: 'No activity in this period. A shop that sold nothing has an empty statement; that is not a fault.' · Sections: Summary (lines + Net row with direction pill), Note (server's caveat, only when present), Itemised (count in a ConsoleQuietChip; 'The totals above are not itemised for this period.' when the server trimmed the list) · Debit lines render in the critical colour; signed amounts come from the model, never concatenated here

  - [ ] no l10n getter — tooltip "Close" — Navigator.pop. There is no Send inside the drawer — sending is only from the table row.  `ConsoleIconAction in the drawer header; barrier tap also closes`

### _SendDialog ("Send <name> their statement?")
*Name the address before a counterparty's figures leave the building.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/statements_screen.dart:753`
- reached by: Rail item 10 Statements → "Send" on a row.
- covered by: test/backoffice/statements_screen_test.dart — DRIVES: names the address before sending, cancels, confirms, handles a failed send, tells the two 409s apart, and types an address for a counterparty with none.
- states: Body restates the period, the net figure, the order count and the direction · Counterparty with no address on file starts in the typed state with the caution line 'No address is on file for them, so one has to be typed in…' — carriers are always in this state today · 409 NO_RECIPIENT → 'Nothing was sent: no address is on file for them. Press Send again and type one in.' · 409 ALREADY_SENT → 'Nothing was sent: this period already went out to X on <stamp>.' · Other failures → 'Not sent: <server message>' / 'Not sent — the server answered <status>.' / 'Not sent. Nothing has gone to them; try again.' (8-second SnackBar)

  - [ ] no l10n getter — "Sends to" (read-only, resolved address) — Shows the server-resolved recipient; deliberately not an editable pre-filled box.  `ConsoleReadOnlyField`
  - [ ] no l10n getter — "Use a different address" — Switches to the typed-address state.  `TextButton`
  - [ ] no l10n getter — "Send to" (labelText), hint "name@example.com" (autofocus, emailAddress keyboard) — An operator-typed recipient. Nothing on this screen can verify it.  `TextField`
  - [ ] no l10n getter — "Use <resolved address> instead" — Returns to the resolved address.  `TextButton (only when an address is on file)`
  - [ ] **[destructive]** no l10n getter — "Send statement" — DESTRUCTIVE / EXTERNAL — POSTs the statement to that address. Cannot be recalled; a mistyped address sends one business's figures to another. The server records the dispatch and answers 409 ALREADY_SENT on a repeat for the same period.  `ConsoleButton(tone: solid, Icons.send_outlined); disabled while the typed address is blank`
  - [ ] no l10n getter — "Cancel" — Sends nothing.  `ConsoleButton(tone: outlined)`

### OffersScreen ("Fee waivers")
*Fees the platform absorbs to grow the marketplace, with the budget printed above the button that spends it.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/offers_screen.dart`
- reached by: Sign in → rail item 11 "Offers".
- covered by: test/backoffice/offers_screen_test.dart — mounts only, and only two tests, both about money formatting ('every amount on the budget panel is written to the cent', 'the budget bar agrees with the tiles above it'). New offer and Withdraw are completely undriven.
- states: Loading: brand CircularProgressIndicator; Error: 'That did not work: <error>' (no retry) · Budget card: four StatTiles (Revenue earned, Given away, Left to give, Kept — critical when negative), a UsageBar 'Budget used' formatted to the cent, the window/cap sentence, and a per-audience breakdown line once anything has been given · Exhausted budget: SoftNote 'The budget is spent. No further waivers will be granted until revenue catches up.' · Empty: SoftCard 'No offers yet' · Per-offer state pill: Live / Scheduled / Ended / Withdrawn, plus the spelled-out effect line for the audience · All buttons disable together while _busy; failures show the server's message/detail

  - [ ] no l10n getter — "New offer" — Opens _NewOfferDialog.  `FilledButton.icon (Icons.add) in the page header`
  - [ ] **[destructive]** no l10n getter — "Withdraw" (per active offer card) — Opens the withdraw confirmation.  `TextButton`

### _NewOfferDialog ("New offer")  — no driving test
*Commit the platform to absorbing a fee for one audience.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/offers_screen.dart:390`
- reached by: Rail item 11 Offers → "New offer".
- states: The effect note re-renders as the audience changes · Server refusals ('An offer cannot end before it starts') surface verbatim in a SnackBar

  - [ ] no l10n getter — audience segments "Customers", "Merchants", "Delivery" — Chooses who stops paying; the SoftNote below restates the exact effect (free delivery / no commission / no platform cut).  `SegmentedButton<OfferAudience>`
  - [ ] no l10n getter — "Title" (labelText) — Required — Create stays disabled while it is blank.  `TextField`
  - [ ] no l10n getter — "Subtitle" (labelText) — Optional.  `TextField`
  - [ ] no l10n getter — "Minimum basket" (labelText, decimal keyboard, defaults to 0) — Unparseable text silently becomes 0.  `TextField`
  - [ ] no l10n getter — "Pick an end date" with the line "Runs until withdrawn/<date>" — Sets endsAt; leaving it unset means the offer runs until it is withdrawn.  `TextButton → showDatePicker (today .. +365, initial +30)`
  - [ ] **[destructive]** no l10n getter — "Create" — MONEY — creates a live fee waiver that the platform pays for on every qualifying order.  `FilledButton; disabled while the title is blank`
  - [ ] no l10n getter — "Cancel" — Creates nothing.  `TextButton`

### Withdraw-offer confirmation  — no driving test
*Stop a fee waiver applying to new orders.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/offers_screen.dart:81`
- reached by: Rail item 11 Offers → "Withdraw" on an active offer.
- states: Body: 'It stops applying to new orders. Orders already placed keep what they were promised.'

  - [ ] **[destructive]** no l10n getter — "Withdraw" — DESTRUCTIVE — POST withdraw(offer.id). Not retroactive; orders already placed keep what they were promised. No reactivate exists.  `FilledButton`
  - [ ] no l10n getter — "Cancel" — Nothing is sent.  `TextButton`

### PromotionsScreen ("Promo Codes")
*Mint and withdraw discount codes, and see what each one has actually cost the platform.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/promotions_screen.dart`
- reached by: Sign in → rail item 12 "Promo Codes".
- covered by: test/backoffice/promotions_screen_test.dart — DRIVES: withdraw (confirm and cancel), the create dialog (dead button until the code matches the server's shape, then a full mint), search, and the notification bell group.
- states: Loading: spinner in a ConsoleCard · Error: cloud_off + 'Could not load the promo codes.' + error + 'Try again' · Empty: 'No promo code has been minted yet.' / 'No code matches that filter.' · Status pill: Live / Scheduled / Ended / Fully redeemed / Withdrawn / Not live (the server's verdict is never argued with) · A withdrawn row's action cell is a ConsoleNoValue dash, tooltip 'Withdrawn. What it gave away stays on the record.' — there is deliberately no delete and no reactivate · Table scrolls horizontally below 1000px

  - [ ] no l10n getter — tabs "All Codes", "Live Now (N)", "Withdrawn" — Client-side slices of the loaded register; the Live count is suppressed while loading.  `ConsoleFilterTabs`
  - [ ] no l10n getter — search, hint "Search codes..." — Client filter on the code string.  `ConsoleSearchField (232px)`
  - [ ] no l10n getter — "New Code" — Opens _NewCodeDialog.  `ConsolePrimaryButton (Icons.add); disabled while loading`
  - [ ] no l10n getter — tooltip "Refresh" — Re-reads codes() and re-sorts newest-first. This screen does NOT poll.  `ConsoleIconAction; disabled while loading`
  - [ ] ConsoleBell — See the ConsoleBell entry.  `ConsoleBell`
  - [ ] **[destructive]** no l10n getter — row action tooltip "Withdraw this code" (active codes only) — Opens the withdraw confirmation.  `ConsoleRowAction (Icons.block, destructive tint)`
  - [ ] Row (whole row) — Opens the _CodeDetail drawer.  `ConsoleTableRow onTap`

### _CodeDetail (promo code drawer)
*Everything the register knows about one code, including what it has cost.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/promotions_screen.dart:445`
- reached by: Rail item 12 Promo Codes → click a row.
- covered by: test/backoffice/promotions_screen_test.dart mounts the table and the withdraw path; the drawer itself is opened by no test.
- states: Four fact sections: What it does, When it applies, What it has cost (Redeemed / Given away), Record (Created, Created by) · Absent values render faint: 'None', 'Unlimited', 'Not recorded'

  - [ ] **[destructive]** no l10n getter — "Withdraw this code" — Pops the drawer and opens the withdraw confirmation.  `ConsoleButton(tone: destructive, Icons.block); absent once withdrawn`
  - [ ] no l10n getter — tooltip "Close" — Navigator.pop.  `ConsoleIconAction in the drawer header`

### _NewCodeDialog ("New promo code")
*Mint a discount code customers type at checkout.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/promotions_screen.dart:586`
- reached by: Rail item 12 Promo Codes → "New Code".
- covered by: test/backoffice/promotions_screen_test.dart 'is dead until the code has the server's own shape' and 'sends what was typed and reloads the register' — DRIVES.
- states: Inverted window: 'The window ends before it starts.' in critical red and the mint button dead · Standing copy: 'Customers type this at checkout. Every redemption is the platform's money.' · Server refusals surface verbatim ('a promo code is 3-32 letters…') · Success SnackBar '<CODE> is minted' / '<CODE> is minted and live.'

  - [ ] no l10n getter — "Code", hint "WELCOME10" (autofocus) — Must match the server's own pattern ^[A-Za-z0-9][A-Za-z0-9._-]{2,31}$ or the mint button stays dead.  `TextField`
  - [ ] no l10n getter — kind switch under "WHAT IT DOES": PromoKind labels (percent off / amount off / free delivery) — Free delivery hides the value field; percent off caps the value at 100.  `ConsoleSegmented inside a FittedBox`
  - [ ] no l10n getter — "Percent off the goods (1–100)" or "Amount off the bill", hint "10" / "5.00" — Required for the two valued kinds; must be > 0.  `TextField (decimal keyboard)`
  - [ ] no l10n getter — "Minimum basket — blank for none", hint "20.00" — Optional floor.  `TextField (decimal)`
  - [ ] no l10n getter — "Starts now" / "From <date>" and "Until withdrawn" / "To <date>" under "WINDOW" — Sets startsAt / endsAt; the end date is stored as 23:59:59 of the chosen day.  `ConsoleButton(outlined, Icons.event_outlined) x2 → showDatePicker (yesterday .. +2 years)`
  - [ ] no l10n getter — "Total uses" and "Per customer" under "CAPS — BLANK IS UNLIMITED", hints "100" / "1" — Optional caps; blank means unlimited, matching the server's nulls.  `TextField x2 (decimal keyboards)`
  - [ ] **[destructive]** no l10n getter — "Mint the code" — MONEY — creates a live discount every customer who types it can redeem.  `ConsoleButton(tone: solid); dead until _ready`
  - [ ] no l10n getter — "Cancel" — Mints nothing.  `ConsoleButton(tone: outlined)`

### Withdraw-code confirmation ("Withdraw <CODE>?")
*Stop a code applying, permanently.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/promotions_screen.dart:322`
- reached by: Rail item 12 Promo Codes → the block row action, or the drawer's 'Withdraw this code'.
- covered by: test/backoffice/promotions_screen_test.dart — DRIVES both the confirm and the cancel path.
- states: Body: 'It stops applying to new orders immediately and cannot be switched back on. Discounts already given stay given.'

  - [ ] **[destructive]** no l10n getter — "Withdraw" — DESTRUCTIVE and ONE-WAY — POST deactivate(id). The server has no reactivate; discounts already given stay given.  `ConsoleButton(tone: destructive)`
  - [ ] no l10n getter — "Cancel" — Posts nothing.  `ConsoleButton(tone: outlined)`

### SettingsScreen (Approvals + Connectors)
*The platform's runtime controls: who is read by a person before going live, and which provider each integration uses right now.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/settings_screen.dart`
- reached by: Sign in → rail item 13 "Settings" (last in the rail, deliberately — the most consequential page).
- covered by: test/backoffice/settings_screen_test.dart (connectors) and test/backoffice/auto_approval_test.dart (approvals) — both DRIVE.
- states: Connector list: spinner, then 'Could not load connector settings: <error>' on failure — the approval switches above stay usable either way · SectionLabel 'Integrations' with an 'N connectors' count · Two standing sentences state that both kinds of change take effect immediately with no deploy and no restart

  - [ ] **[destructive]** Approvals section — hosts AutoApprovalPanel (see its own entry) — Three approval gates. Loaded independently of the connector list so one failing endpoint cannot take the other down.  `AutoApprovalPanel`
  - [ ] **[destructive]** Connectors section — one _ConnectorCard per connector (see its own entry) — Provider switch, canary ramp, delivery rates and change history for SMS / EMAIL / PUSH / CORE_BANKING.  `_ConnectorCard, keyed by connectorType`

### AutoApprovalPanel ("Automatic approval")
*Decide, per applicant kind, whether an application is read by a person or waved through.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/auto_approval_panel.dart`
- reached by: Sign in → rail item 13 Settings → the first card on the page.
- covered by: test/backoffice/auto_approval_test.dart — DRIVES thoroughly (17 tests): taps each switch by Key, asserts all three values are sent, that the thumb waits for the server, that a refusal leaves the switch alone and does not disturb the other two, and that a failed read draws no gates. It also covers the read-only line this panel feeds on the Onboarding screen.
- states: Loading: card with a 20px spinner and no switches at all (three switches drawn off would be a false claim) · Read failure: 'Could not read whether applications are being approved automatically.' + Try again · Saving: the touched row's thumb is replaced by a spinner and ALL THREE switches disable (the PUT carries all three) · Save failure: the switch stays where the server last said it was, plus a critical SnackBar and a persistent inline error line — server messages surface verbatim, 403 becomes 'Your account is not allowed to change this.' · Per-kind source chip (ConsoleQuietChip) distinguishes a value somebody chose from the deployment default · Footer: 'Last changed by X <ago>.' or 'Never changed from the portal. What is running is this environment's own default.'

  - [ ] **[destructive]** no l10n getter — "Riders" switch (Key 'auto-approval-RIDER') — DESTRUCTIVE / IDENTITY — turning it on means a rider is on the road as soon as they apply, with nobody checking the driving licence. PUT sends all three values; the thumb does not move until the server answers.  `Switch (brand thumb) — the only keyed control in the whole console`
  - [ ] **[destructive]** no l10n getter — "Shops" switch (Key 'auto-approval-MERCHANT') — DESTRUCTIVE — a shop can take orders as soon as it applies, with nobody checking the commercial registration.  `Switch`
  - [ ] **[destructive]** no l10n getter — "Delivery companies" switch (Key 'auto-approval-CARRIER') — DESTRUCTIVE — the heaviest of the three: a company signs for a fleet and for the account the platform pays.  `Switch`
  - [ ] no l10n getter — "Try again" (failed-read state only) — Re-runs the GET.  `ConsoleButton(tone: outlined)`

### _ConnectorCard (one integration: SMS / EMAIL / PUSH / CORE_BANKING)
*Change where real messages and real money actually go, at runtime.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/settings_screen.dart:147`
- reached by: Sign in → rail item 13 Settings → scroll to "Connectors".
- covered by: test/backoffice/settings_screen_test.dart — DRIVES: opens the provider dropdown, asserts only server-sent providers are offered, that a fixed-provider connector cannot be changed, and walks switch → confirm / cancel / go-live. The canary buttons, Stop ramp, the History dialog and the 1h/24h/7d window tabs are NOT driven by any test.
- states: Header badge 'Live provider' (inTransit) vs 'Dev provider' (offline) — the single most important thing on the page · Busy: the dropdown is replaced by a LinearProgressIndicator · Credential block shows the masked secret, the Vault path and 'rotated <ago>' / 'never rotated', or 'Not configured' — never the secret itself · Delivery rates: LinearProgressIndicator while loading; 'Delivery rates unavailable: <error>'; 'Nothing sent on this channel in the last N hours.'; per-provider acceptance % over a bar with the denominator, plus a second delivery line reading 'not measured — no carrier receipts…' when the carrier sends no receipts · Config chips rendered from connector.config; 'Last changed by X <ago>' when known · Rate panel and canary control are hidden entirely for a fixed-provider connector (SMTP-only email) · 422 on save → the server's `detail`; anything else → 'Could not change the provider' / 'Could not change the ramp'

  - [ ] **[destructive]** no l10n getter — "Active provider" dropdown; options are the server's availableProviders rendered as "Dev test inbox", "Dev log only", "MontyMobile", "Twilio", "SMTP relay", "Firebase (FCM)", "Simulator", "Live bank" — DESTRUCTIVE — picking a different provider opens _ConfirmSwitchDialog; confirming redirects real SMS/email/push traffic, or in CORE_BANKING's case real money ('REAL — Posts to the live Core Banking system. Real money moves.'). Disabled (not hidden) when the connector is fixed-provider.  `DropdownButtonFormField<String> (isExpanded), helperText = the effect of the current choice`
  - [ ] no l10n getter — "History" — Opens _HistoryDialog for this connector.  `TextButton.icon (Icons.history)`
  - [ ] **[destructive]** no l10n getter — canary start buttons "<Provider> 5%" (one per candidate provider) — Starts a canary ramp at 5% through the same audited update call.  `OutlinedButton inside a Wrap`
  - [ ] **[destructive]** no l10n getter — ramp steps "5%", "25%", "50%", "100% (complete)" after "Move to" — DESTRUCTIVE — moves the traffic share; 100% completes the cutover so every message goes to the canary.  `OutlinedButton row; the current step is disabled`
  - [ ] no l10n getter — "Stop ramp" — Clears canaryProvider/canaryPercentage — the rollback. One click on purpose: the only reason to press it is that something is already going wrong.  `TextButton.icon (Icons.stop_circle_outlined), brand foreground — deliberately NO confirmation`
  - [ ] no l10n getter — delivery-rate window tabs "1h", "24h", "7d" (DeliveryRatePanel) — Re-requests forChannel(channel, windowHours) — 1 / 24 / 168.  `ConsoleFilterTabs`

### _ConfirmSwitchDialog ("Switch <CONNECTOR> provider?")
*Slow down the one change that starts (or stops) touching the outside world.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/settings_screen.dart:584`
- reached by: Rail item 13 Settings → a connector's Active provider dropdown → pick a different provider.
- covered by: test/backoffice/settings_screen_test.dart 'switching to a live vendor asks first and warns about credentials', 'cancelling the confirmation changes nothing', 'confirming sends the switch' — DRIVES.
- states: Going live: a brand-tinted panel warning that credentials must already be in Vault or every message fails · Going back to dev: 'This stops sending through the live provider… real recipients will receive nothing.' · Always: 'The change is recorded against your account.'

  - [ ] **[destructive]** no l10n getter — "Go live" (when moving dev → real) or "Switch" — DESTRUCTIVE — commits the provider change. Going live starts sending to real recipients through a paid provider (and for CORE_BANKING, moves real money). The change is recorded against the operator's account.  `FilledButton`
  - [ ] no l10n getter — "Cancel" — Changes nothing; the dropdown snaps back on the next reload.  `TextButton`

### _HistoryDialog ("<CONNECTOR> change history")  — no driving test
*Show the previous value, so a mistaken switch can be reversed.*

- file: `D:/workspace/delivery/clients/apps/delivery_portal/lib/src/backoffice/settings_screen.dart:649`
- reached by: Rail item 13 Settings → "History" on a connector card.
- states: Loading: 120px spinner · Error: 'Could not load the history: <error>' · Empty: 'This connector has never been changed.' · Rows read '<old label>  →  <new label>' with '<changedBy> · <ago>'

  - [ ] no l10n getter — "Close" — Dismisses. The list itself is read-only — there is no one-click revert.  `TextButton`

## RIDER SHELL of the mobile app (Flutter, D:\workspace\delivery\clients\apps\mobile_app)

22 screens, 110 controls.

### BiometricLockScreen  — no driving test
*Proves it is still the same person holding the phone before any rider screen is drawn.*

- file: `D:\workspace\delivery\clients\apps\mobile_app\lib\src\biometric_lock_screen.dart`
- reached by: Sign in as rider/300003 → Settings tab → App language row (or Notification preferences row) → shared Settings → turn ON Fingerprint unlock → kill and cold-start the app. main.dart:676-683 draws this before the rider shell on every restored session.
- states: busy: spinner inside the circle, both controls disabled · error line under the glyph: couldNotVerifyYou "We could not verify you..." or fingerprintNotSetUp "No fingerprint or face is set up on this phone yet..." · enrolment removed since the setting was turned on: BiometricResult.unavailable lets the rider in rather than locking them out

  - [ ] t.unlockWithFingerprint — "Unlock with fingerprint" — Raises the OS biometric prompt; 45s timeout is treated as a refusal (main.dart:276-277). Shows a CircularProgressIndicator in place of the fingerprint glyph while busy.  `InkWell (112px circle, customBorder CircleBorder, Semantics button) — no Button subclass`
  - [ ] **[destructive]** t.signInWithPasscodeInstead — "Use my passcode instead" — Despite the label this does NOT open a passcode pad — main.dart:682 wires onUsePasscode to _signOut, so it ends the session and drops back to the sign-in gate.  `TextButton`

### RiderHomeScreen (shell chrome / bottom nav)
*One four-tab app; the tabs share one 5s order poll and one 10s position ping.*

- file: `D:\workspace\delivery\clients\apps\mobile_app\lib\src\rider_home_screen.dart`
- reached by: Sign in screen → username field (hint authEmailOrPhoneHint) "rider" → passcode field (hint authPasscodeHint) "300003" → authLogIn "Log In". Lands on _tab = 0 (Available).
- covered by: integration_test/rider_earnings_test.dart (asserts the Available/Active/Earnings trio is the rider nav, then taps Earnings); integration_test/order_lifecycle_test.dart via integration_test/support/journey.dart:282 signOutRider (taps the Settings tab)
- states: Timer.periodic 5s refresh of available+assigned runs on every tab, silently; a failed poll leaves the last list and says nothing · Timer.periodic 10s ping runs whenever an order is PICKED_UP or the rider declared duty; position is SIMULATED (rider_home_screen.dart:154-155, walked ±0.002° per tick from 51.5074/-0.1278) — there is no location plugin and no runtime permission prompt anywhere in this shell · No notification bell / inbox anywhere in the rider shell (the customer shell has one); push taps do not deep-link into any rider screen

  - [ ] t.riderTabAvailable — "Available" — setState(_tab = 0) — the offers/errands board. Icons home_outlined → home_rounded when active.  `YdBottomNavItem inside YdBottomNav (each tab is an InkWell in the private _YdBottomNavTab)`
  - [ ] t.riderTabActive — "Active" — setState(_tab = 1) — the claimed-jobs list. Also selected automatically by _claimAndFollow after a successful claim.  `YdBottomNavItem / InkWell`
  - [ ] t.riderTabEarnings — "Earnings" — setState(_tab = 2) — builds a fresh RiderEarningsScreen, so all three ledger GETs plus the three stat calls re-run on EVERY visit to this tab.  `YdBottomNavItem / InkWell`
  - [ ] t.settings — "Settings" — setState(_tab = 3) — the rider's Driver settings body.  `YdBottomNavItem / InkWell`

### Available tab (deliveries board)
*Decide which unclaimed READY job to take.*

- file: `D:\workspace\delivery\clients\apps\mobile_app\lib\src\rider_home_screen.dart (_availableTab :408, _regionBar :462, _mapSlot :540, _offers :680)`
- reached by: Default tab on sign-in, or bottom nav → Available.
- covered by: integration_test/order_lifecycle_test.dart — scrolls the board, finds the RiderJobCard by its delivery address and presses Accept delivery
- states: loading: bare CircularProgressIndicator (no RefreshIndicator) while _loading && _available.isEmpty · empty: YdEmptyState nothingWaitingForPickup "Nothing waiting for pickup right now." + newJobsAppearHere "New jobs land here as soon as a shop marks an order ready." · map, no fix yet: riderMapNoFixYet "Waiting for your first GPS fix" over the ruled placeholder — this is what an off-duty rider who has never pinged sees · map, dead tiles: riderMapUnavailable "Map unavailable" after 6 refused tiles (_tileFailureLimit); the map is then torn down permanently for the life of the tab · SCOPING TRAP: /api/orders/available only returns orders whose deliveryProviderId is null or this rider's own fleet. A demo rider left in a carrier's fleet sees an empty board indistinguishable from 'no work' — order_lifecycle_test.dart:114 calls putRiderBackInHouse for exactly this reason · a failed 5s poll is swallowed entirely — no snackbar, no error state

  - [ ] t.riderRegionZone "Region zone" / t.riderRegionAllAreas "Every area" — Nothing. Read-only statement that every approved rider sees every ready order everywhere.  `Container + Row (NOT tappable — the design's chevron/zone picker was deliberately dropped)`
  - [ ] the 160px mini-map (no label; marker Semantics t.riderMapYouAreHere — "You") — Pan by drag and zoom by double-tap. Rotation and pinch are deliberately off. Camera is anchored once at the first platform fix and never re-centres. Marker shows the last fix the PLATFORM holds, not this screen's simulated lat/lng.  `FlutterMap over a CustomPaint grid placeholder, InteractionOptions = drag | doubleTapZoom only`
  - [ ] t.riderDeliveriesNearby(n) — "N deliveries nearby" / "No deliveries nearby" — Read-only count of _available.length.  `Container pill (shellDeep)`
  - [ ] t.riderSegmentDeliveries — "Deliveries" — setState(_board = deliveries) — shows the offers list.  `YdChip (selected = brand fill)`
  - [ ] t.errands — "Errands" — setState(_board = errands) — swaps the list body for RiderButlerBoard. This chip is the ONLY route to the errands board.  `YdChip`
  - [ ] pull-to-refresh (no label) — _refresh() — re-reads available AND assigned. Absent while the first load is still running.  `RefreshIndicator over the offers ListView`
  - [ ] t.riderOffersNearYou — "Offers near you" — Read-only.  `Text heading`
  - [ ] t.pendingBannerRider — "Your application is being reviewed. Look around the board — you can take deliveries once you are approved." — Read-only; drawn only when the session still carries APPLICANT alongside DELIVERY.  `SoftNote`

### RiderJobCard (offer card, Figma offer-card 3:1188)
*Sell one job: payout first, route second, one button that takes it.*

- file: `D:\workspace\delivery\clients\apps\mobile_app\lib\src\rider_job_card.dart (:411-544)`
- reached by: Available tab → Deliveries chip → one card per unclaimed order.
- covered by: test/rider_job_card_test.dart — 7 driving cases: taps the action and captures it, asserts the step-forward is the ONLY tappable thing on the card, asserts a busy card refuses further taps, and re-runs it in Arabic RTL. Also driven end-to-end by integration_test/order_lifecycle_test.dart
- states: busy: the label is replaced by a spinner inside the button and further taps are refused · 422 on claim → snackbar anotherRiderClaimedIt "Another rider claimed that one first." · 422 on anything else → orderAlreadyMovedOn "That order has already moved on." · any other failure → actionFailed "Could not {action}." · cash job: RiderTag collectCash "Collect {amount} cash" in caution colours; prepaid job: RiderTag itemCountWithDot "N items" in the same slot · EXPRESS order: RiderTag riderTierExpress "EXPRESS" (brand tint); STANDARD wears nothing · no storeName: the pickUpFrom "Pick up from" row is omitted and the card starts at the door · notes present: a muted 2-line box under the route

  - [ ] t.riderAcceptDelivery — "Accept delivery" (for OrderAction.claim); any other server-offered action renders action.labelIn(t), e.g. actionPickedUp "Picked up", actionDelivered "Delivered" — POSTs the action, refreshes the board, snackbars actionOnOrder "{action} · #{ref}", and on a claim switches the shell to the Active tab. One button per availableActions entry; OrderAction.cancel is filtered out of this card by design so a rider cannot cancel by brushing a scrolling list.  `RiderButton (filled, 12px radius rectangle — NOT YdPillButton, NOT a FilledButton), full width`

### RiderButlerBoard (errands board)
*Claim customer errands and agree what the goods cost; once approved the errand becomes an ordinary order and moves to the Active tab.*

- file: `D:\workspace\delivery\clients\apps\mobile_app\lib\src\rider_butler_board.dart`
- reached by: Available tab → t.errands "Errands" chip. There is no other entry — the redesign has no home for errands, this chip is it.
- covered by: test/butler_live_refresh_test.dart — DRIVES the 5-second poll (an errand posted after load appears on its own; no spinner flicker; a failed poll keeps the last good board) but never presses Claim or Report what it cost
- states: first load: CircularProgressIndicator; later polls never blink back to a spinner (initialData keeps the last board) · both lists empty: YdEmptyState noErrandsWaiting "No errands waiting." · open empty but Yours populated: nothingToClaim "Nothing waiting to be claimed." · load error: YdEmptyState couldNotLoadErrands "Could not load your errands" · 409 → somebodyElseClaimed "Somebody else claimed that one"; otherwise the server's own body.detail string; last resort thatDidNotWork "That did not work" · the 5s silent poll is skipped entirely while a claim or quote is in flight, so a card cannot move out from under a finger · terminal (declined/cancelled) errands are dropped from Yours client-side · buy mode shows RiderTag buyAndBring "Buy and bring", pickup mode collectAndDrop "Collect and drop"; rows from "From", riderErrandTry "Try", riderErrandTo "To", riderErrandCap "Cap"

  - [ ] t.claim — "Claim" — ButlerApi.claim → snackbar butlerStatusClaimed "Claimed" and the card moves from the Open group to the Yours group.  `RiderButton (filled), full width, one per open errand`
  - [ ] t.reportWhatItCost — "Report what it cost" — Opens the price dialog (see next row). This is the button that unblocks the whole errand.  `RiderButton (filled), only on a CLAIMED buy-mode errand`
  - [ ] pull-to-refresh (no label) — _reload() — refetches available + claimed.  `RefreshIndicator over the board ListView (also present on the fully-empty state)`
  - [ ] t.headingWithCount(t.yours, n) — "Yours (N)" / t.headingWithCount(t.butlerStatusOpen, n) — "Open (N)" — Read-only group headers.  `Text headings`
  - [ ] t.collectAndDropInstruction / t.waitingOnApprovalOf(total) / t.approvedDeliverIt — Read-only standing instruction; there is deliberately no button in these states.  `private _Note (brandSoft box) — replaces the button in those states`

### Butler price dialog (_askPrice)  — no driving test
*Type the receipt total the customer will be asked to approve and be charged for.*

- file: `D:\workspace\delivery\clients\apps\mobile_app\lib\src\rider_butler_board.dart (:141-208)`
- reached by: Available tab → Errands chip → a claimed BUY errand → Report what it cost.
- states: invalid or zero amount: the button silently does nothing — no validation message is shown, so it reads as a dead button · success: snackbar sentForApproval "Sent. They will approve the price before you deliver." and the card flips to the waitingOnApprovalOf note · the dialog is an async gap: the board's poll is paused while it is open

  - [ ] t.whatDidItCost — "What did it cost?" — Read-only; the errand's `what` text and, when set, cappedAtBudget "They capped it at {amount}" sit under it.  `AlertDialog title`
  - [ ] t.goodsTotal — "Goods total" (helper t.whatYouPaidBeforeFee — "What you paid, before the errand fee") — The number the customer is asked to approve.  `TextField, autofocus, TextInputType.numberWithOptions(decimal: true)`
  - [ ] t.receiptNumberOptional — "Receipt number (optional)" — Optional receipt reference sent with the quote.  `TextField`
  - [ ] t.cancel — "Cancel" — Pops with null; nothing is sent.  `TextButton`
  - [ ] **[destructive]** t.sendForApproval — "Send for approval" — Parses the amount, refuses null or <= 0, then ButlerApi.quote(goodsCost, receiptRef). MONEY: this is the figure the customer is charged once they approve.  `ElevatedButton (the only Material button on the whole rider surface)`

### Active tab
*The jobs this rider has taken and has not finished.*

- file: `D:\workspace\delivery\clients\apps\mobile_app\lib\src\rider_home_screen.dart (_activeTab :724)`
- reached by: Bottom nav → Active, or automatically after a successful claim (_claimAndFollow sets _tab = 1).
- covered by: integration_test/order_lifecycle_test.dart — waits for the tab after a claim, then finds the task card and presses View details twice
- states: loading: CircularProgressIndicator while _loading && _assigned.isEmpty · empty: YdEmptyState noActiveDeliveries "You have no active deliveries." + claimOneToSeeItHere "Claim one from Available and it will show up here." · the request asks only for PLACED/ACCEPTED/PREPARING/READY/PICKED_UP, and terminal rows are filtered again client-side

  - [ ] t.riderMyActiveTasks "My active tasks" + t.riderActiveCount(n) "N active" / "None active" — Read-only.  `private _screenHeader Container (title start, brand-coloured count end)`
  - [ ] pull-to-refresh (no label) — _refresh().  `RefreshIndicator over the ListView`
  - [ ] one RiderTaskCard per job — Navigate / View details.  `RiderTaskCard (see next row)`

### RiderTaskCard (task card, Figma task-card 3:1269)
*Track a job already taken; deliberately carries NO step-forward action.*

- file: `D:\workspace\delivery\clients\apps\mobile_app\lib\src\rider_job_card.dart (:551-669)`
- reached by: Active tab → one card per claimed job.
- covered by: integration_test/order_lifecycle_test.dart drives View details. Navigate is undriven (it leaves the app).
- states: riderNavigateFailed "No map app could be opened." snackbar when nothing on the device handles the URL (and when the platform throws rather than returning false) · EXPRESS tag beside the status pill on express orders

  - [ ] t.riderNavigate — "Navigate" — riderNavigateTo() → launchUrl(externalApplication) to https://www.google.com/maps/search/?api=1&query=<deliveryAddress verbatim>. LEAVES THE APP. Disabled (onPressed null) only when the address is blank.  `RiderButton (soft style, 13px, 10px padding)`
  - [ ] t.riderViewDetails — "View details" — Pushes RiderOrderDetailScreen — the only route to it.  `RiderButton (filled, 13px)`
  - [ ] status pill (order.status.labelIn: stepPlaced/stepAccepted/stepPreparing/statusReadyForPickup "Ready for pickup"/stepOnTheWay) — Read-only.  `YdStatusPill, colour read back out of OrderStatusBadge.colorFor`
  - [ ] t.riderMinutesAgo(n) "N min ago" / t.riderHoursAgo(n) "N hrs ago" — Read-only job age (there is no SLA countdown anywhere in the data model).  `Text, tinted with the status colour`
  - [ ] t.riderOrderRef(ref) "Order #{ref}", fee, t.pickUpFrom "Pick up from", t.dropOffAt "Drop off at" — Read-only.  `RiderRouteRow.labelled + Text`

### RiderOrderDetailScreen (Figma rider-order-detail 3:1344)
*The whole job on one screen, and the one place the committing acts happen.*

- file: `D:\workspace\delivery\clients\apps\mobile_app\lib\src\rider_order_detail_screen.dart`
- reached by: Active tab → task card → View details. NOTE: an offer on the Available tab cannot open this screen — the detail view exists only for jobs already claimed.
- covered by: integration_test/order_lifecycle_test.dart — drives Picked up and Delivered end-to-end against the live backend and verifies the order status server-side after each. The Cancel path, the chat button, the ETA panel and the split checklist are undriven.
- states: busy: every forward CTA spins and all taps are refused; the screen pops itself when the action lands · ETA unavailable renders the server's reason, never a spinner or an invented number: etaWaitingFirstFix / etaPositionOutOfDate / etaNoMapPoint / etaRouteServiceDown / etaNothingOnItsWay / etaUnavailable · no items: riderNoItemsListed "This order has no itemised list." · no conversation: no chat button in the header at all · a chat frame arriving while this screen is up bumps the unread badge live over the socket

  - [ ] t.back — "Back" (semanticLabel) — maybePop() back to the Active tab.  `YdBackButton`
  - [ ] t.riderChatTitle — "Customer chat" (Semantics label; the button itself is an icon) — Pushes RiderChatScreen, then re-reads the conversation so the badge matches the server. DRAWN ONLY when ChatApi.conversationForOrder answered — the server opens a conversation when a rider is assigned, so a 404 leaves the header with no button at all.  `InkWell circle (44px, brandSoft, chat_bubble_outline_rounded) with an unread-count badge`
  - [ ] OrderAction.pickUp.labelIn → t.actionPickedUp — "Picked up" — Runs the board's own action wiring, then pops this screen because the page is stale by definition.  `RiderButton (filled, 15px/w700, 14px padding), full width`
  - [ ] **[destructive]** OrderAction.deliver.labelIn → t.actionDelivered — "Delivered" — Closes the job. IRREVERSIBLE, and on a cash order it asserts the money was collected — this is what puts the basket total onto the rider's cash float and into the Reconciliation screen.  `RiderButton (filled), full width`
  - [ ] t.riderStartNavigation — "Start navigation" — Maps the SHOP NAME before pick-up and the delivery address after it (_navigationTarget). Leaves the app. Disabled when both are blank.  `RiderButton (outlined)`
  - [ ] **[destructive]** OrderAction.cancel.labelIn → t.actionCancel — "Cancel" — Opens the confirmation dialog. Not in the Figma — kept deliberately because the server offers CANCEL on some orders. Only drawn when availableActions contains CANCEL.  `TextButton (critical colour, zero padding, below the CTAs)`
  - [ ] t.riderYourPayout "YOUR PAYOUT" + fee; t.collectCash(total) "Collect {amount} cash" or t.alreadyPaid "Already paid" — Read-only. The design's circular call button is absent — there is no telephony integration.  `YdCard + RiderTag`
  - [ ] t.riderRouteTimeline "ROUTE TIMELINE", t.riderPickupAddress "PICKUP ADDRESS", t.riderDeliveryAddress "DELIVERY ADDRESS" — Read-only; the door row also shows contactPhone.  `YdCard + private _routeNode`
  - [ ] t.riderEtaCaption "LIVE ETA" panel — riderEtaAway "{distance} away", riderEtaArrivingAt "arriving about {time}", riderEtaComputedBy "Estimated by {provider}", etaStraightLineNote — Read-only; refreshed on a 30s timer, and only while the order is not terminal.  `Text column at the foot of the route card`
  - [ ] t.riderItemsToCollect "ITEMS TO COLLECT" + riderItemLine "{qty}x {name}"; t.riderDeliveryInstructions "DELIVERY INSTRUCTIONS" — Read-only manifest to check against the bag.  `YdCard`
  - [ ] t.riderCashChecklist "Cash Collection Checklist" + riderSplitOrderTag "SPLIT ORDER", riderAlreadyPaid "ALREADY PAID DIGITALLY", riderTotalCashCollect "Total Cash to Collect" — Read-only. Only on a split order (SplitApi.forOrder 404 = ordinary order, nothing drawn). Sums the CASH_AT_DOOR shares.  `YdCard.bordered`

### Cancel-order confirmation dialog  — no driving test
*The one guard between a rider's thumb and a cancelled customer order.*

- file: `D:\workspace\delivery\clients\apps\mobile_app\lib\src\rider_order_detail_screen.dart (_confirmCancel :338-360)`
- reached by: Active tab → View details → Cancel (only when the server offers CANCEL in availableActions).
- states: dismissing via the barrier returns null and is treated as no

  - [ ] t.cancelThisOrder — "Cancel this order?" — Read-only.  `AlertDialog title (no body text)`
  - [ ] t.cancel — "Cancel" — Dismisses, nothing sent. NOTE the collision: the dismissing button and the destructive button both start with the word Cancel.  `TextButton`
  - [ ] **[destructive]** t.cancelOrder — "Cancel order" — Fires OrderAction.cancel on a live customer order, then pops the detail screen.  `TextButton (foreground DeliveryAccent.critical)`

### RiderChatScreen  — no driving test
*The rider's only live channel to a customer. There is no support desk anywhere in the platform.*

- file: `D:\workspace\delivery\clients\apps\mobile_app\lib\src\rider_chat_screen.dart`
- reached by: Two routes: (a) Active tab → View details → chat button in the header; (b) Settings tab → Help & live chat support → a row under "Your conversations".
- states: loading: CircularProgressIndicator · load failed: YdEmptyState riderChatCouldNotLoad "Could not load the conversation" + Try again · empty thread: riderChatEmpty "No messages yet." · socket down: caution strip riderChatReconnecting "Reconnecting…" — messages still send over REST, only the other party's replies stop arriving live; on reconnect the screen refetches from its sequence cursor · 409 on send: the composer is replaced permanently by riderChatClosed "This conversation has closed." · any other send failure: snackbar riderChatSendFailed "The message was not sent." · own bubbles carry a tick: done_rounded when sent, done_all_rounded when delivered, full-strength white when read · read receipts are posted on open and on every live frame

  - [ ] t.back — "Back" — maybePop; the caller re-reads the conversation so the unread badge matches the server.  `YdBackButton`
  - [ ] t.riderChatHint — "Type a message…" — Composes a message; disabled while a send is in flight.  `TextField (minLines 1, maxLines 4, TextInputAction.send, onSubmitted → _send), filled with the page background`
  - [ ] t.riderChatSend — "Send" (Semantics label; the control is an icon) — ChatApi.send over REST with a client-generated idempotency key (the socket is receive-only).  `InkWell in a brand Material CircleBorder (40px, send_rounded, mirrored under RTL)`
  - [ ] t.tryAgain — "Try again" — _loadInitial() again.  `RiderButton (outlined) — only in the load-failure state`

### RiderEarningsScreen — Earnings tab (ledger flavour)
*What the rider earned, and the one place a cash-out is asked for.*

- file: `D:\workspace\delivery\clients\apps\mobile_app\lib\src\rider_earnings_screen.dart`
- reached by: Bottom nav → Earnings. Rebuilt from scratch on every visit.
- covered by: integration_test/rider_earnings_test.dart — DRIVES it against the live dev backend: taps into the tab, waits for riderBalanceLine, opens the cash-out sheet, dismisses it via the scrim, switches to Weekly, scrolls the whole ledger list and sweeps every RichText and EditableText for negative money
- states: loading: full-body CircularProgressIndicator under the header; the header's cash-out slot is EMPTY while loading and after a failure · error: YdEmptyState riderCouldNotLoadEarnings "Could not load your earnings" if any of the three ledger calls fails · empty period: riderNothingDeliveredYet "Nothing delivered in this period yet." · stat with no answer: "—" (em dash) for hours, completion and rating — never 0% or 100% · unrated rider: ratingNewRider "New" · open cash-out: caution line riderCashOutOpenLine "{amount} requested — waiting on the payout"; last one refused: critical line riderCashOutLastRefused "Your last cash-out was refused."

  - [ ] t.riderCashOutTitle — "Cash out" (header trailing slot); becomes t.cashOutRequested — "Requested" tag while a request is open — Awaits the ledger future then opens the cash-out sheet. The Requested tag is the SAME InkWell and still opens the sheet.  `InkWell wrapping either a Text or a RiderTag (no button widget)`
  - [ ] t.riderPeriodToday — "Today" — setState(_period) — a local filter over already-fetched data; nothing is refetched. The selected segment has onTap null.  `Material + InkWell segment in a border-filled track (Semantics button/selected)`
  - [ ] t.riderPeriodWeekly — "Weekly" — Same, 7-day window; flips the list heading to riderThisWeeksDeliveries "This week's deliveries".  `Material + InkWell segment`
  - [ ] t.riderStatementTitle — "Reconciliation" (subtitle t.riderStatementRowSubtitle — "Cash you are holding, against what you have earned") — Pushes RiderStatementScreen — the only route to it.  `RiderSettingRow with a direction-aware chevron`
  - [ ] pull-to-refresh (no label) — _reloadLedger() — all three ledger GETs plus the three independent stat calls.  `RefreshIndicator over the ledger ListView`
  - [ ] t.riderTotalEarnings "TOTAL EARNINGS"; t.riderHoursOnline "HOURS ONLINE" + riderHoursValue "{hours} h"; t.riderEarningsBreakdown "{earnings} delivery pay · {tips} tips"; t.riderBalanceLine "Balance {balance} · available for cash-out {available}" — Read-only. The balance line renders balance.withdrawable (clamped at zero), never the signed balance.available.  `YdCard + Text`
  - [ ] t.deliveries "Deliveries" / t.riderCompletionRate "Completed" / t.riderRating "Rating" stats; t.riderPerformanceLine "{delivered} of {claimed} claimed jobs delivered in {days} days" (+ riderPerformanceDropped) — Read-only; each stat is loaded independently so one dead service costs one figure.  `private _stat columns`
  - [ ] t.riderWeeklyOverview — "WEEKLY OVERVIEW" 7-bar chart — Read-only; today's bar is green and bold. Amounts exist only as semantics values, never as drawn text.  `Container bars inside Semantics(label: weekday, value: amount) — NOT tappable`
  - [ ] per-job rows: t.riderOrderRef, t.riderTipLine "+{tip} tip", t.riderReimbursedLine "+{amount} reimbursed", riderPayerLabel (paidByPlatform / paidByYourCompany "Paid by your company" / paidElsewhere) — Read-only.  `Container rows (not tappable)`

### Cash-out sheet (_CashOutSheet)
*Ask the platform to hand over money.*

- file: `D:\workspace\delivery\clients\apps\mobile_app\lib\src\rider_earnings_screen.dart (:1347-1580)`
- reached by: Earnings tab → "Cash out" (or the "Requested" tag) in the header.
- covered by: integration_test/rider_earnings_test.dart opens the sheet and asserts the clamped figure, the held note and that nothing in it (including the seeded text field) shows negative money — but it never presses Request cash-out
- states: a request already open: the amount field and the button are replaced entirely by a SoftNote riderCashOutOpenLine · 409: snackbar riderCashOutAlreadyOpen "A cash-out request is already on its way." and the sheet still pops true (treated as success) · any other failure: snackbar riderCashOutFailed "The cash-out could not be requested." · amount null or <= 0: the button silently does nothing · keyboard-aware: padded by MediaQuery viewInsets so the field stays visible

  - [ ] t.riderCashOutAmountLabel — "Amount" — How much to request; disabled while busy.  `TextField with an OutlineInputBorder, decimal keyboard, PREFILLED with balance.withdrawable`
  - [ ] **[destructive]** t.riderCashOutRequest — "Request cash-out" — MONEY: RiderMoneyApi.requestCashOut(amount). Pops true and the screen behind refetches. One open request at a time — the server answers 409 to a second.  `RiderButton (filled, 15px/w700)`
  - [ ] scrim / drag-down (no label) — Dismisses with null; nothing is refetched.  `showModalBottomSheet barrier`
  - [ ] t.riderCashOutAvailable "Available to cash out"; t.riderCashOutHeldNote "{amount} of it is cash you are still carrying — hand it in to free it up"; t.riderCashOutMinimum "Minimum {amount}"; t.riderCashOutManualNote "Payouts are handed over by the platform team — nothing transfers automatically." — Read-only. The held note only appears when cashFloatHeld > 0 and is the explanation beside a clamped zero.  `Text rows`
  - [ ] t.riderCashOutHistory — "RECENT REQUESTS" with RiderTags cashOutRequested "Requested" / cashOutPaid "Paid" / cashOutRefused "Refused" — Read-only, newest first, max 10.  `Rows of Text + RiderTag`

### RiderStatementScreen (Reconciliation)
*Where the rider stands with the platform once door-collected cash is counted — normally a debt, and deliberately worded rather than signed.*

- file: `D:\workspace\delivery\clients\apps\mobile_app\lib\src\rider_statement_screen.dart`
- reached by: Earnings tab → Reconciliation row.
- covered by: test/rider_statement_test.dart — 7 scenarios against a fake Dio adapter (real contract parsing exercised), but it only MOUNTS each state: no tap on the period segments, no pull-to-refresh. One test does assert the client can only ever call /mine.
- states: loading: the period selector stays visible above a CircularProgressIndicator · error: YdEmptyState riderStatementCouldNotLoad "Could not load your statement" and NOTHING else — no zeroes, never "settled" · empty period: YdEmptyState riderStatementNothingYet "No money moved in this period." · any figure the server omitted renders "—", never 0.00 · statement.note is rendered in a SoftNote when present

  - [ ] t.back — "Back" — maybePop back to Earnings.  `YdBackButton`
  - [ ] t.riderStatementPeriodThisMonth — "This month" — REFETCHES /api/accounting/statements/mine for month-start → today.  `Material + InkWell segment (same track as the Earnings period selector)`
  - [ ] t.riderStatementPeriodLastMonth — "Last month" — Refetches for the whole previous calendar month.  `Material + InkWell segment`
  - [ ] pull-to-refresh (no label) — Reloads the current period.  `RefreshIndicator over the body ListView`
  - [ ] t.riderStatementSummary "HOW IT ADDS UP" — one row per server line, with the server's own label, note and SIGNED amount — Read-only; credit rows green, debit rows ink, unknown muted. Nothing is recomputed on this screen.  `YdCard + Row`
  - [ ] the net card: t.riderStatementYouOwe "You owe the platform" / t.riderStatementOwedToYou "The platform owes you" / t.riderStatementSettled "Nothing outstanding either way" / t.riderStatementDirectionUnclear "This balance could not be read", with riderStatementDebtNote / CreditNote / SettledNote / UnclearNote — Read-only. Debt is caution-coloured, never critical; only an unreadable direction earns the alarm colour.  `YdCard + Text (figure drawn UNSIGNED at 32px)`
  - [ ] t.riderStatementOrders "Orders in this period" + per-order rows with t.riderStatementCollectedLine "You collected {amount} at the door" — Read-only.  `Container rows (not tappable)`
  - [ ] t.riderStatementRangeLine "{from} – {to}" and t.riderStatementGeneratedAt "Worked out {when}" — Read-only — taken from the server's answer, not from the range the screen asked for.  `Text captions`

### Settings tab (Driver settings)
*Who the rider is, whether they are on duty, and every door out of the shell.*

- file: `D:\workspace\delivery\clients\apps\mobile_app\lib\src\rider_home_screen.dart (_settingsTab :773) + D:\workspace\delivery\clients\apps\mobile_app\lib\src\rider_settings_widgets.dart`
- reached by: Bottom nav → Settings.
- covered by: integration_test/support/journey.dart:282 signOutRider, used by integration_test/order_lifecycle_test.dart — taps the Settings tab, drags the list until the log-out button is found and presses it. The duty toggle, the language row, all four preference rows and the profile card are undriven.
- states: duty change refused: snackbar riderDutyChangeFailed "Could not update your duty state." and the toggle is re-read from the server · rating service down: the rating line on the profile card is simply absent, not zero · the Documents and Bank details rows are omitted entirely when documentsApi is null — never in the shipped build (main.dart:739) · the whole body is wrapped in an AnimatedBuilder on the LocaleController, so switching to Arabic re-renders it in place

  - [ ] t.riderDriverSettings — "Driver settings" — Read-only header.  `private _screenHeader Container`
  - [ ] profile card — session.displayName, initials avatar, t.ratingWithCount "{average} · {ratings} ratings" or t.ratingNewRider "New" — Read-only. No vehicle/plate line is drawn: the applications endpoint returns a receipt shape with no details in it.  `RiderProfileCard (YdCard) — not tappable`
  - [ ] t.riderActiveDuty — "Active duty (online)" — POSTs duty ON/OFF to the tracking service and renders the SERVER's answer, not the tap. Going on duty starts the between-jobs position ping; going off stops it and takes the rider off the roster. Disabled while a change is in flight.  `Switch.adaptive inside RiderDutyToggleCard/RiderSettingRow, with a RiderTag beside it`
  - [ ] duty subtitle t.riderLastSeen "Last seen {when}" / t.riderDutyNotYetDeclared "You have not gone on duty yet."; tag t.dutyOnDuty "On duty" / t.dutyOffDuty "Off duty" / t.presenceSignalLost "Signal lost" — Read-only. "Signal lost" is PresenceState.stale — declared on duty but the phone has gone quiet.  `RiderSettingRow subtitle + RiderTag`
  - [ ] t.riderAppLanguage — "App language" (trailing value "English" / "العربية") — Pushes the shared SettingsScreen — language is not changed here, only shown.  `RiderSettingRow (InkWell)`
  - [ ] t.riderDocuments — "Documents & licences" — showRiderSheet(RiderDocumentsSheet).  `RiderPreference row inside RiderPreferencesGroup (InkWell + chevron)`
  - [ ] t.riderBankDetails — "Bank account details" — showRiderSheet(RiderPayoutSheet).  `RiderPreference row`
  - [ ] t.riderNotificationPreferences — "Notification preferences" — Pushes the shared SettingsScreen — NOT the notification grid. A second tap on that screen's own notifPreferences row is needed to reach the switches.  `RiderPreference row`
  - [ ] t.riderHelpAndSupport — "Help & live chat support" — showRiderSheet(RiderHelpSheet).  `RiderPreference row`
  - [ ] **[destructive]** t.signOut — "Sign out" — Ends the session and returns to the sign-in gate; the whole shell is torn down.  `RiderLogOutButton → RiderButton (outlined, brand, full width) — the file itself calls it the destructive button`

### RiderDocumentsSheet (Documents & licences)  — UNREACHABLE, no driving test
*Read back the rider's KYC file and the reviewer's verdict on each paper.*

- file: `D:\workspace\delivery\clients\apps\mobile_app\lib\src\rider_settings_widgets.dart (:667-729) → ApplicantDocumentsCard in D:\workspace\delivery\clients\apps\mobile_app\lib\src\application_documents_step.dart (:216-399)`
- reached by: Settings tab → Documents & licences (bottom sheet).
- **unreachable:** Every upload control here is gated off: canUpload is hard-coded false at rider_settings_widgets.dart:720 because the onboarding endpoints refuse changes to a decided application, and a rider signed into this app is approved by definition. Consequence for a sweep: a rider whose licence is refused AFTER approval has no way to replace it anywhere in the app — the Add/Replace chip, the picker and the wizDocUploading/wizDocTooLarge/wizDocUploadFailed states in ApplicantDocumentsCard are all unreachable from the rider shell (they are live only on PendingApplicationScreen, which an approved rider never sees).
- states: loading: CircularProgressIndicator · error: riderDocumentsCouldNotLoad "Could not load your documents" · a document kind the server knows and this build does not is still listed, named by its wire string, with no action · the wizDocsPendingBlurb "A refused document can be replaced..." line is suppressed because canUpload is false

  - [ ] t.riderDocumentsTitle — "Documents & licences" / card title t.wizDocsPendingTitle — "Your documents" — Read-only.  `private _RiderSheet + YdCard.bordered`
  - [ ] three rows: t.docNationalId "National ID", t.docDrivingLicence "Driving licence", t.docVehicleRegistration "Vehicle registration" — NOTHING IS PRESSABLE ON THIS SHEET. Each row shows a kind, its status badge and (when refused) the reviewer's reason as a red subtitle.  `private _DocumentRow (Material + InkWell) with onTap NULL, so the t.wizDocAdd "Add" / t.wizDocReplace "Replace" YdBadge.brand chip is never drawn`
  - [ ] status badges: t.wizDocNotAddedYet "Not added yet", t.docWaitingReview "Waiting for review", t.docApproved "Approved", t.docRefused "Refused" — Read-only.  `YdBadge / YdBadge.accent`
  - [ ] scrim / drag-down (no label) — Dismisses the sheet.  `showModalBottomSheet barrier`

### RiderPayoutSheet (Bank account details)  — UNREACHABLE, no driving test
*Show where the rider's money is meant to go.*

- file: `D:\workspace\delivery\clients\apps\mobile_app\lib\src\rider_settings_widgets.dart (:742-794) → PayoutDetailsCard in D:\workspace\delivery\clients\apps\mobile_app\lib\src\payout_details_step.dart (:192-426)`
- reached by: Settings tab → Bank account details (bottom sheet).
- **unreachable:** canEdit is hard-coded false at rider_settings_widgets.dart:786. Combined with the rider onboarding wizard having no bank step (payout_details_step.dart:188-191 says this card is 'the rider's only place to enter details at all'), an approved rider who never filled payout details while their application was undecided can NEVER enter them anywhere in the app: this sheet is the only offer of it and it is read-only, and for that rider it renders as an empty card. The whole AuthField form (wizPayoutAccountHolder "Account holder", wizPayoutIban "IBAN", wizPayoutSave "Save bank details") and the Change chip are unreachable from the rider shell.
- states: loading: CircularProgressIndicator · error: riderPayoutCouldNotLoad "Could not load your bank details" · NO RECORD SAVED: the card renders the title and a wizDocNotAddedYet "Not added yet" badge and then NOTHING — payout_details_step.dart:299-312 draws the form only when (formShowing && canEdit) and the saved block only when saved != null, so both branches are skipped

  - [ ] t.riderBankDetails — "Bank account details" (sheet title) / t.authBankDetails — "Bank details" (card title) — Read-only.  `private _RiderSheet + YdCard.bordered`
  - [ ] saved record: account holder + IBAN masked by maskIban(), plus a verification-state YdBadge.accent — Read-only. The t.wizPayoutChange "Change" chip (InkWell + YdBadge.brand) is NOT drawn because canEdit is false.  `Row inside the card — not tappable`
  - [ ] scrim / drag-down (no label) — Dismisses the sheet.  `showModalBottomSheet barrier`

### RiderHelpSheet (Help & support)  — no driving test
*The written answers to what this surface actually does, plus the rider's live conversations.*

- file: `D:\workspace\delivery\clients\apps\mobile_app\lib\src\rider_settings_widgets.dart (:516-655)`
- reached by: Settings tab → Help & live chat support (bottom sheet).
- states: loading: CircularProgressIndicator · error: riderHelpCouldNotLoad "Could not load your conversations" · empty: riderHelpNoConversations "A chat opens with the customer on every job you are assigned." · the conversations half is omitted entirely when chatApi is null (never in the shipped build) · There is deliberately NO support phone number, email, ticket form or 'call support' button — the platform's configuration carries none

  - [ ] t.riderHelpTitle "Help & support" and t.riderHelpHowItWorks "HOW THIS WORKS" with four lines: riderHelpDuty, riderHelpClaim, riderHelpCashOut, riderHelpExpress — Read-only guidance.  `private _RiderSheet + Text`
  - [ ] t.riderHelpConversations — "YOUR CONVERSATIONS" caption — Read-only.  `Text caption`
  - [ ] t.riderHelpOrderThread(ref) — "Order {ref}" (subtitle t.riderHelpThreadClosed "Closed" on a closed thread; trailing unread count as a brand RiderTag) — Pushes RiderChatScreen for that order; on return the thread list is refetched so the badge matches the server. This is the only way to reach a conversation without first finding its order.  `RiderSettingRow (InkWell)`
  - [ ] scrim / drag-down (no label) — Dismisses the sheet.  `showModalBottomSheet barrier`

### SettingsScreen (shared app settings)  — no driving test
*App-level questions that are not rider-specific: language, fingerprint unlock, notification prefs, and a statement of the payment methods that exist.*

- file: `D:\workspace\delivery\clients\apps\mobile_app\lib\src\settings_screen.dart`
- reached by: Settings tab → App language row, OR Settings tab → Notification preferences row. Both push this same screen.
- states: the fingerprint row is not drawn at all while the availability check is still running, when the device has no enrolment, or when userId is null — so its absence is three different things · working: the switch is replaced by a small CircularProgressIndicator while the OS prompt is out · refused: snackbar fingerprintNotSetUp "No fingerprint or face is set up on this phone yet..." (6s) or couldNotVerifyYou · the notification row is omitted when prefsApi is null (never in the shipped rider build)

  - [ ] t.back — "Back" (backSemanticLabel) — maybePop back to the rider Settings tab.  `YdScreenHeader back control`
  - [ ] t.custAppLanguage — "App Language", with EN / AR segments — locale.setLanguage('en'|'ar') — flips the whole app, including the rider shell behind this route, to RTL immediately.  `AppLanguageRow — Material + InkWell segments in a pill track (Semantics button/selected); the active one has onTap null`
  - [ ] t.biometricUnlock — "Fingerprint unlock" (subtitle t.fingerprintKeepsYourAccountClosed) — Turning ON raises the OS biometric prompt FIRST and only stores the setting if it succeeds; turning OFF just clears it. This is what makes BiometricLockScreen appear on the next cold start.  `Switch inside YdListRow`
  - [ ] t.notifPreferences — "Notification preferences" (subtitle t.notifPrefsBlurb) — Pushes NotificationPrefsScreen.  `YdListRow (tappable)`
  - [ ] t.cashOnDelivery — "Cash on delivery" — Nothing. A statement of fact under t.custPaymentMethods "Payment Methods".  `YdListRow with an empty trailing — NOT tappable`
  - [ ] t.card — "Card" (subtitle t.paymentTestModeNote, badge t.custTestPayment "Test payment") — Nothing.  `YdListRow with a YdBadge.brand — NOT tappable`
  - [ ] t.appTitle — "YouDrop" — Read-only.  `Text footer`

### NotificationPrefsScreen  — no driving test
*Per-category, per-channel control of what the platform sends this rider.*

- file: `D:\workspace\delivery\clients\apps\mobile_app\lib\src\notifications_screen.dart (:216-425)`
- reached by: Settings tab → App language row (or Notification preferences row) → shared Settings → Notification preferences row. Two taps deep from the rider Settings tab either way.
- states: loading: CircularProgressIndicator · load failed: YdEmptyState couldNotLoadPreferences "Could not load your preferences" + Try again · saving one cell: that cell's switch is replaced by a 16px spinner; other cells stay live · save failed: snackbar couldNotSaveThatChange "Could not save that change" and the switch stays where it was · unknown categories/channels are rendered last, by wire string, never dropped

  - [ ] t.back — "Back" — maybePop.  `YdScreenHeader back control`
  - [ ] t.notifPrefsBlurb — "Choose how we reach you, topic by topic" — Read-only intro.  `Text`
  - [ ] one switch per category × channel cell (labels come from custNotifCategoryLabel / custNotifChannelLabel, and fall back to the server's wire string for anything this build does not know) — PUTs that single cell's change and re-renders the grid the server answers with; the switch never moves optimistically.  `Switch inside a YdCard per category`
  - [ ] locked cells — t.notifAlwaysOn "Always on — account and security messages cannot be switched off" — Nothing; the note is drawn when every cell in a category is locked.  `Switch with onChanged null (disabled)`
  - [ ] t.tryAgain — "Try again" — _load() again.  `YdPillButton (compact) inside the empty state`

### RiderEarningsScreen — derived (pre-ledger) flavour  — UNREACHABLE, no driving test
*The fallback that adds a rider's own delivered-order fees up client-side and labels the total as derived.*

- file: `D:\workspace\delivery\clients\apps\mobile_app\lib\src\rider_earnings_screen.dart (_buildDerived :1015, _derivedStatsCard :1099, _derivedWeeklyCard :1210, _transaction :1265, and the empty header slot at :677-680)`
- reached by: Nothing. Requires RiderEarningsScreen.moneyApi == null.
- **unreachable:** main.dart:733 always passes _riderMoneyApi, so this branch is never taken in the shipped app. integration_test/rider_earnings_test.dart even asserts the ledger ListView is the only one mounted, calling the fallback list 'the no-moneyApi branch, which the real app never takes'. Treat any sighting of riderEarningsDerived on a real device as a wiring regression.
- states: header has NO cash-out control at all in this flavour (trailing is left null on purpose)

  - [ ] t.riderPeriodToday "Today" / t.riderPeriodWeekly "Weekly" — Same local period filter as the ledger flavour.  `Material + InkWell segments`
  - [ ] t.riderStatementTitle — "Reconciliation" row — Still drawn in this flavour (statementsApi is independent of moneyApi).  `RiderSettingRow`
  - [ ] t.riderEarningsDerived — "Added up from the delivery fees on your own completed deliveries." — Read-only — copy no shipped rider can see.  `Text caption`
  - [ ] pull-to-refresh — _reloadDerived() — refetches DELIVERED orders only.  `RefreshIndicator`

### _RateRiderSheet (rate the rider)  — UNREACHABLE, no driving test
*The customer's post-delivery rating of the rider. Listed here only because it sits in the rider file group; the rider sees its output as the Rating stat on Earnings and the ratingWithCount line on the Settings profile card.*

- file: `D:\workspace\delivery\clients\apps\mobile_app\lib\src\rate_rider_sheet.dart`
- reached by: Not reachable by the rider role at all. It is opened from the CUSTOMER's order details (order_details_screen.dart:159, showRateRiderSheet).
- **unreachable:** Customer-surface screen. A rider account has no path to it — /api/riders/{id}/rating/comments is BACKOFFICE-only, and the rider's own view is limited to GET /api/riders/me/rating.


## PUBLIC WEBSITE — D:/workspace/delivery/clients/website (static HTML/CSS/JS, no framework, no build step)

13 screens, 111 controls.

### Landing page (index.html)  — no driving test
*The public front door: pitches the platform to four audiences and routes two of them to /register and two of them to the Android APK at /app.*

- file: `D:/workspace/delivery/clients/website/index.html`
- reached by: Open https://www.youdrop.shop/ (locally http://127.0.0.1:5014/). Also reached by typing ANY unknown path — nginx `location / { try_files $uri $uri/ /index.html; }` serves this page at that URL with a 200.
- states: API UNREACHABLE: no effect whatsoever. This page makes zero network requests beyond its own static assets — the QR is drawn locally by lib/qr.js precisely so no third-party image service is called. The platform can be entirely down and this page is fully functional; only the outbound destinations (/app, portal-dev.youdrop.shop) would fail once followed. · JS OFF or site.js fails to load: complete English page (the English lives in the markup, never fetched). Both language buttons do nothing. #qr-code shows its shipped sentence 'Scanning needs JavaScript. Use the link below.' (deliberately English-only). All six FAQ <details> still toggle. Every link still works. · localStorage throws (private window, blocked site data, embedded webview): readStored/store are try/caught — page opens in English and forgets the choice; no error surfaces. · Arabic: html lang=ar dir=rtl, title -> TITLE_AR, letter-spacing reset (html[lang="ar"] *), aria-pressed=true on both toggles, footer label 'العربية'. The QR image itself does not change — only its aria-label. · PERMANENT EMPTY STATE (by design, not a bug): the counters band ships four em-dash figures (.figure.pending) under 'Active Merchants / Deliveries Daily / Verified Riders / Satisfaction Rate' plus a data-t="soon" 'Coming soon' chip; the three testimonial cards ship 'Awaiting a merchant/rider/customer' placeholders plus their own chip. Three 'Coming soon' chips total (counters, testimonials, store badges) plus one in the footer social row. · <=1024px: hero and all .split bands become one column; control tower card unstacks above the phone. <=900px: masthead nav vanishes; steps/quotes/FAQ go single-column; stats go 2-up. <=560px: wordmark text hidden, lang and CTA shrink, Butler cards stack. · prefers-reduced-motion: reduce (site.css:1622): scroll-behavior auto and all animation/transition durations forced to .001ms. · 404 states: /app 404s when no APK has been deployed. Any other unknown path does NOT 404 — it silently serves this page at the typed URL.

  - [ ] aria-label="YouDrop" (no data-t) — wordmark — Reloads the landing page. Below 560px .wordmark-text is display:none, so only the square mark remains — the aria-label is the only thing announcing it.  `<a class="wordmark" href="/"> with <span class="mark"> + <span class="wordmark-text">`
  - [ ] data-t="nav-merchants" / AR 'للتجّار' — "For Merchants" — Smooth-scrolls to the #merchants band. HIDDEN below 900px (site.css `.masthead nav { display: none; }`) — on a phone this link only exists in the footer.  `<a href="#merchants"> inside <nav aria-label="Sections">`
  - [ ] data-t="nav-carriers" / AR 'لشركات الشحن' — "For Carriers" — Scrolls to the #carriers band. Hidden below 900px.  `<a href="#carriers">`
  - [ ] data-t="nav-riders" / AR 'للمندوبين' — "For Riders" — Scrolls to the #riders band. Hidden below 900px. Note there is NO "For Customers" link in the masthead — that anchor exists only in the footer.  `<a href="#riders">`
  - [ ] literal "EN / AR" (deliberately untranslated) + icons/globe.svg — site.js: flips documentElement.lang/dir between en/ltr and ar/rtl, rewrites every [data-t] node from the inline AR dictionary (missing key falls back to the English read out of the DOM at load), swaps document.title to TITLE_AR, re-labels the QR via QR_LABEL, sets aria-pressed on BOTH toggles, and writes 'youdrop-lang' to localStorage inside try/catch. Inert with JS off.  `<button class="lang" type="button" data-lang-toggle aria-pressed="false">`
  - [ ] data-t="cta-get-started" / AR 'ابدأ الآن' — "Get Started" — Leaves for the wizard with no kind in the query, so it opens defaulted to MERCHANT.  `<a class="primary" href="/register">`
  - [ ] data-t="cta-merchant" / AR 'ابدأ كتاجر' — "Start as Merchant" — Opens the wizard with the shop radio pre-checked.  `<a class="primary" href="/register?kind=MERCHANT"> in .hero-actions`
  - [ ] data-t="cta-rider" / AR 'انضم كمندوب' — "Become a Rider" (hero) — Downloads app/youdrop.apk as an attachment. Returns 404 when the APK has not been pushed (the -[path-to-apk] argument of infra/deploy-website.sh is optional) — verify before ticking.  `<a class="secondary" href="/app"> wrapped in <span class="cta-soon"> beside a <span class="tag" data-t="tag-android">Android APK</span> chip`
  - [ ] data-t="cta-shop" / AR 'افتح متجرك الآن' — "Open Your Shop Now" — Same destination as Start as Merchant.  `<a class="primary" href="/register?kind=MERCHANT"> at the foot of the #merchants band`
  - [ ] data-t="cta-partner" / AR 'كن شريكاً لنا' — "Partner With Us" — The ONLY link on the whole site that pre-selects the carrier path.  `<a class="secondary" href="/register?kind=CARRIER"> at the foot of the #carriers band`
  - [ ] data-t="cta-rider" — "Become a Rider" (#riders band) — Second instance of the same key and destination as the hero button.  `<a class="primary" href="/app"> in <span class="cta-soon"> + Android APK chip`
  - [ ] data-t="cta-download" / AR 'حمّل تطبيق العملاء' — "Download Customer App" — Third route to the same APK.  `<a class="primary" href="/app"> in <span class="cta-soon"> + Android APK chip`
  - [ ] aria-label from QR_LABEL.en — "QR code for youdrop.shop/app, where the Android app downloads" (AR variant on switch) — Scan it: encodes the literal https://www.youdrop.shop/app (QR_TARGET in site.js), version 3 level M. Not clickable. If lib/qr.js is absent or throws, the div keeps its shipped sentence "Scanning needs JavaScript. Use the link below." and the dashed .qr-slot box.  `<div class="qr-code qr-slot" id="qr-code"> replaced at load with inline SVG by lib/qr.js (YouDropQR.svg, quiet:2, dark #0F172A)`
  - [ ] "App Store" and "Google Play" (no data-t, no href) — NOTHING — they are spans, not links, by design (the comment says both listings are owner accounts nobody can create). Tick as 'inert, correct'; a tester will try to click them.  `<span class="store"> x2 with icons/apple.svg and icons/app-window.svg, under a data-t="soon" chip`
  - [ ] data-t="cta-apk" / AR 'حمّل ملف APK مباشرةً' — "Download the APK directly" — Fourth and last route to /app.  `<a class="apk-link" href="/app">`
  - [ ] data-t="faq1-q" — "How do I sign up as a Merchant?" — Collapses/expands. Open by default; chevron rotates 180deg via .faq-item[open] summary img. Pure CSS+HTML — works with JS off.  `<details class="faq-item" open><summary> with icons/chevron-down.svg`
  - [ ] data-t="faq2-q" — "What is the YouDrop Butler service?" — Collapses/expands.  `<details class="faq-item" open><summary>`
  - [ ] data-t="faq3-q" — "Are delivery fleets managed directly?" — Collapses/expands.  `<details class="faq-item" open><summary>`
  - [ ] data-t="faq4-q" — "How fast are rider earnings paid out?" — Collapses/expands.  `<details class="faq-item" open><summary>`
  - [ ] data-t="faq5-q" — "Which regions does YouDrop operate in?" — Collapses/expands. Its answer refers to a "map widget" that does not exist on this page — content bug.  `<details class="faq-item" open><summary>`
  - [ ] data-t="faq6-q" — "What are the platform onboarding fees?" — Collapses/expands.  `<details class="faq-item" open><summary>`
  - [ ] aria-label Facebook / Instagram / X / LinkedIn (no data-t, no href) — NOTHING — deliberately hrefless spans (there are no accounts). Inert by design; a tester will try all four.  `<li><span role="img"><img icons/*.svg></span> x4 in <ul class="social">, followed by a data-t="soon" chip`
  - [ ] data-t="nav-merchants" — "For Merchants" (footer Platform column) — Scrolls to #merchants. Below 900px this is the ONLY way to reach the section anchors.  `<a href="#merchants"> in <nav class="footer-col" aria-label="Platform">`
  - [ ] data-t="nav-carriers" — "For Carriers" (footer) — Scrolls to #carriers.  `<a href="#carriers">`
  - [ ] data-t="nav-riders" — "For Riders" (footer) — Scrolls to #riders.  `<a href="#riders">`
  - [ ] data-t="nav-customers" / AR 'للعملاء' — "For Customers" (footer only) — Scrolls to the Butler band. This anchor has no masthead equivalent at any width.  `<a href="#customers">`
  - [ ] data-t="footer-partner" / AR 'كن شريكاً لنا' — "Partner with us" — Wizard, defaulted to MERCHANT.  `<a href="/register"> in <nav class="footer-col" aria-label="Company">`
  - [ ] data-t="footer-signin" / AR 'تسجيل الدخول' — "Sign in" — Leaves the site for the one portal that serves back office, carrier console and merchants alike. Hard-coded absolute URL in the markup — not read from config.js, so it does not follow a deployment.  `<a href="https://portal-dev.youdrop.shop">`
  - [ ] data-t="faq-eyebrow" (key reused) — "Help Center" — Scrolls to the FAQ. Shares a data-t key with the FAQ eyebrow, so both nodes always read the same.  `<a href="#faq"> in <nav class="footer-col" aria-label="Support">`
  - [ ] data-lang-label — "English (US)" / AR 'العربية' (SWITCH_LABEL) — Second language toggle: same handler as the masthead one, but its own label REPORTS the current language rather than naming the pair. Check both toggles stay in sync (aria-pressed is set on all [data-lang-toggle]).  `<button class="footer-lang" type="button" data-lang-toggle aria-pressed="false"> with icons/globe-muted.svg`

### Register wizard — shared frame (.wizard, brand panel + form chrome)  — no driving test
*The two-panel frame every wizard step is drawn inside: brand panel on the inline-start, progress and form on the other side. Present on all six steps; replaced wholesale by the receipt after submit.*

- file: `D:/workspace/delivery/clients/website/register.html`
- reached by: Any of the five /register links on the landing page (Get Started, Start as Merchant, Open Your Shop Now, Partner With Us, footer Partner with us), or type /register, /register/ or /register.html.
- states: NO SCRIPT: a <p class="form-error w-noscript"> is the one thing visible before JS runs — 'This form needs JavaScript…'. It is deliberately untranslated. Only the business step renders (every other .wstep carries the `hidden` attribute in the markup); no button does anything; the receipt div stays hidden. The page is unusable and says so. · RELOAD = TOTAL LOSS. Nothing is persisted (no localStorage, no sessionStorage, no cookie — see the note at register.js:1298). A refresh on any step, including the receipt, returns to step 1 with the reference and the session gone. · ?kind=CARRIER or ?kind=MERCHANT pre-checks the radio and re-words everything; any other value (or none) silently defaults to MERCHANT. · Below 1100px the brand panel shrinks; below 880px it becomes a band across the top and drops its paragraph and footer; below 560px .w-row and .w-verify stack and .w-actions reverses to column-reverse (so Continue sits ABOVE Back on a phone). · RTL specifics worth an eyeball: the brand panel deliberately MIRRORS to the right; the Continue arrow is scaleX(-1); email/tel/number/password inputs and the code boxes and the reference are forced direction:ltr with text-align right/center.

  - [ ] no data-t — logo, <b>YouDrop</b> + #brand-eyebrow (WORDING[kind].hub — "Merchant Hub" / AR 'مركز التجّار', or "Carrier Hub" / AR 'مركز شركات التوصيل') — The only navigation off this page — back to the landing page. Abandons everything typed (nothing is stored).  `<a class="w-logo" href="/">`
  - [ ] data-t="signin-note" / AR 'مسجّل لدينا من قبل؟' — "Already registered?" + data-t="signin-link" / AR 'تسجيل الدخول' — "Sign in" — Leaves for the portal. Hard-coded absolute URL, not from config.js.  `<p class="w-top-note"> with <a href="https://portal-dev.youdrop.shop">`
  - [ ] data-t-aria="lang-aria" aria-label "Language" / AR 'اللغة'; visible text literal "AR / EN" — register.js apply(): flips lang/dir, rewrites [data-t] textContent, [data-t-placeholder] placeholders and [data-t-aria] aria-labels, then calls applyWording() + paint() and replays every remembered run-time write from the `rewrites` and `rewriteLabels` maps (so a countdown, an error box, an upload pill and a summary row all re-translate in place) WITHOUT scrolling. Shares the 'youdrop-lang' key with the landing page, so a reader who chose Arabic there arrives here in Arabic. Text somebody else wrote (business name, reviewer's rejection reason, server messages, the reference) is never re-translated.  `<button class="w-lang" type="button" data-lang-toggle aria-pressed="false" data-t-aria="lang-aria">`
  - [ ] #step-of — SAY['step-of'] "Step {n} of {total}" / AR 'الخطوة {n} من {total}'; #step-percent — SAY.percent "{percent}% Complete" — Read-only. Totals differ by kind: MERCHANT 4 steps (25/50/75/100%), CARRIER 6 (17/33/50/67/83/100%). Verify the total changes the instant the kind radio is flipped.  `<div class="w-bar" role="progressbar" aria-labelledby="step-of"> with <span id="bar-fill">`
  - [ ] #step-title / #step-lede / #brand-headline / #brand-lede — from COPY[step][kind] and BRAND_LEDE[kind] — Read-only, rewritten on every step change AND on every language flip. The business step is the only one with per-kind title/lede; the rest are shared. Static markup ships the CARRIER wording ('Carrier Hub', 'Company Profile', 'Step 1 of 4') and JS overwrites it at first paint — a JS failure leaves a page that says Carrier and 4 steps.  `<h2 id="step-title">, <p id="step-lede">, <h1 id="brand-headline">, <p id="brand-lede">`
  - [ ] #brand-company — the typed business name, else WORDING[kind].fallbackCompany ("Merchant Partner Application" / "Carrier Partner Application") — Echoes #businessName on every keystroke (writeRaw — never translated). HIDDEN below 880px along with #brand-lede.  `<span id="brand-company"> in .w-brand-foot`

### Step 1 of 4|6 — Business / Company Profile (section[data-step="business"])  — no driving test
*Choose which kind of partner is applying, and give the names the reviewer reads. Nothing here goes over the network.*

- file: `D:/workspace/delivery/clients/website/register.html`
- reached by: Landing on /register. Also re-entered from anywhere by changing the kind radio (register.js calls go('business')), and by Back from the email step.
- states: API UNREACHABLE: this step is entirely client-side and behaves identically. The applicant only discovers the platform is down on step 2. · Empty-name and empty-CR errors are the only two failures here. · No <form> element and no submit handler — Enter in a text field does nothing. Worth a tick: keyboard users cannot advance with Enter anywhere in this wizard. · Below 560px the name/phone .w-row stacks.

  - [ ] data-t="kinds-legend" / AR 'بأي صفة تتقدّم بالطلب؟' — "What are you applying as?" — Groups the two radios.  `<fieldset class="w-kinds"><legend>`
  - [ ] data-t="kind-shop" — "A shop" + data-t="kind-shop-note" — "Put your menu in front of the city and let us find the rider" — Sets state.kind=MERCHANT, re-words the three dynamic labels, the eyebrow, the brand lede and document.title (TITLE.MERCHANT — 'Apply as a shop — YouDrop'), HIDES every [data-kind="CARRIER"] field, shortens the flow to 4 steps and JUMPS BACK TO THIS STEP.  `<label class="w-kind"><input type="radio" name="kind" value="MERCHANT" checked> (card styled via :has(input:checked))`
  - [ ] data-t="kind-carrier" — "A delivery company" + data-t="kind-carrier-note" — "Bring your fleet onto the platform and get work routed to you" — Sets state.kind=CARRIER, reveals the CR number and Company Type fields, extends the flow to 6 steps (adds documents + fleet), retitles the tab. Test flipping this AFTER verifying an email — the verification survives, the flow length changes under it.  `<label class="w-kind"><input type="radio" name="kind" value="CARRIER">`
  - [ ] #business-label — WORDING[kind].business: MERCHANT "Shop name" / AR 'اسم المتجر'; CARRIER "Company / Business Name" / AR 'اسم الشركة أو النشاط التجاري'. Placeholder data-t-placeholder="business-hint" — "e.g. FastFlow Logistics" — Required (JS-validated, not by the browser — there is no <form>). Mirrors into #brand-company on every keystroke.  `<input id="businessName" type="text" required maxlength="200" autocomplete="organization">`
  - [ ] data-t="cr-label" / AR 'رقم السجل التجاري' — "Commercial Registration Number" (required *). Placeholder data-t-placeholder="cr-hint" — "e.g. CR-894211A" — CARRIER ONLY. Carries no `required` attribute — enforced only by validateBusiness(). Rides to the server inside details.commercialRegistrationNumber.  `<input id="registrationNumber" type="text" maxlength="64"> in a <div class="w-field" data-kind="CARRIER" hidden>`
  - [ ] data-t="company-type" / AR 'نوع الشركة' — "Company Type" (required *) — CARRIER ONLY. Always has a value, so its * is cosmetic. Value goes to details.companyType; the review row re-translates it through COMPANY_TYPES.  `<select id="companyType"> with 5 <option>: ct-logistics "Logistics Company", ct-courier "Courier Service", ct-freight "Freight & Trucking", ct-sole "Individual / Sole Proprietor", ct-other "Other"`
  - [ ] #contact-label — WORDING[kind].contact: MERCHANT "Your name" / AR 'اسمك'; CARRIER "Owner Full Name" / AR 'الاسم الكامل لصاحب الشركة'. Placeholder data-t-placeholder="contact-hint" — "John Doe" / AR 'مثال: أحمد خليل' — Required (JS-validated).  `<input id="contactName" type="text" required maxlength="160" autocomplete="name">`
  - [ ] data-t="contact-phone" / AR 'هاتف للتواصل' — "Contact Phone" + data-t="optional" — "optional" — NEVER SUBMITTED. seedPhone() copies it into #contactPhone when the phone step opens, but only while that field is empty and unverified. Type a number here, verify a DIFFERENT one on step 3, come back and forward — the verified one must survive.  `<input id="phoneSeed" type="tel" maxlength="32" autocomplete="tel" placeholder="+961 …">`
  - [ ] #notes-label — WORDING[kind].notes: MERCHANT "What do you sell, and where are you?"; CARRIER "How many riders, and which areas do you cover?" — Optional free text; submitted as `notes` (null when blank) and shown on the review as an untranslated row.  `<textarea id="notes" rows="3" maxlength="2000">`
  - [ ] NEXT_LABEL.email — "Continue to Email" / AR 'متابعة إلى البريد الإلكتروني' (markup fallback data-t="continue" — "Continue") — validateBusiness() then advance. Label is rewritten by paint() at the moment the step opens, so it always names its destination.  `<button class="primary" data-nav="next"> with <span class="w-next-label"> and an inline arrow <svg class="w-arrow">`
  - [ ] #page-error — SAY['need-name'] "Please give the business name and your own name." / SAY['need-cr'] "Please give your commercial registration number." — Blocking validation only; re-hidden on the next successful attempt. Re-translates live on a language flip (it was written through write(), not writeRaw).  `<p class="form-error" id="page-error" hidden>`

### Step 2 — Your email address (section[data-step="email"])  — no driving test
*Prove the applicant can open the address every later message goes to. The one unskippable network step — the wizard cannot be finished without it.*

- file: `D:/workspace/delivery/clients/website/register.html`
- reached by: Step 1 -> "Continue to Email". Back from step 3.
- states: API UNREACHABLE — HARD STOP. 'Send code' rejects with a TypeError, the error box reads 'We could not reach the server. Check your connection and try again.', the button re-enables and restores its label, the code box never opens and Continue stays disabled. There is no way past this step, and no offline or alternative path (the page publishes no contact address on purpose). · UN-VERIFY PATH: editing the address after verifying hides the tick, un-hides Send code, clears readOnly and nulls state.email/state.emailToken — but the code box STAYS HIDDEN, so the applicant must press Send code again (and a second real email goes out). Worth an explicit tick. · Server-side refusals arrive as the service's own sentence, in whatever language the service speaks — deliberately not translated. · Below 560px .w-verify stacks and Send code goes full width.

  - [ ] data-t="email-note" — "We send a six-digit code to check the address reaches you…" — Static copy.  `<p class="w-note">`
  - [ ] data-t="email-label" / AR 'البريد الإلكتروني' — "Email" (required *) — After a successful Verify the server's NORMALISED spelling is written back into this field and it goes readOnly. Editing it afterwards un-verifies (see below).  `<input id="contactEmail" type="email" required maxlength="200" autocomplete="email" placeholder="you@company.com">`
  - [ ] **[destructive]** data-t="send-code" / AR 'أرسل الرمز' — "Send code" (becomes SAY.sending "Sending…" / AR 'جارٍ الإرسال…' while in flight) — DESTRUCTIVE IN DEV — POST /api/onboarding/verifications {channel:'EMAIL',destination} actually sends mail through the Gmail relay to whatever address was typed. On success reveals #email-code-box, focuses the code field and starts the 10-minute countdown. Hidden entirely once verified.  `<button class="secondary w-send" id="email-send">`
  - [ ] data-t="code-label" / AR 'الرمز الذي أرسلناه' — "The code we sent" — Six digits. autocomplete=one-time-code so iOS/Android offer to fill it. Letter-spaced .35em, forced LTR in Arabic.  `<input id="email-code" inputmode="numeric" autocomplete="one-time-code" maxlength="6" placeholder="000000"> in <div class="w-code" id="email-code-box" hidden>`
  - [ ] data-t="verify" / AR 'تحقّق' — "Verify" (becomes SAY.checking "Checking…" / AR 'جارٍ التحقّق…') — POST /api/onboarding/verifications/confirm. On 200: writes body.destination back into the field, stores body.token in state.emailToken, hides the code box, shows the tick, makes the field readOnly, hides Send code, clears the countdown interval, and ENABLES #email-continue.  `<button class="primary w-confirm" id="email-confirm">`
  - [ ] #email-expiry — SAY['code-expires'] "Expires in {clock}. " / AR 'تنتهي صلاحيته خلال {clock}. ' then SAY['code-expired'] "That code has expired. " — 1-second setInterval countdown off the server's expiresAt. Both strings keep a trailing space because the resend button sits on the same line. Re-translates mid-countdown on a language flip.  `<span id="email-expiry"> in <p class="w-code-foot">`
  - [ ] **[destructive]** data-t="send-another" / AR 'أرسل رمزاً آخر' — "Send another" — DESTRUCTIVE IN DEV — a second real email. Stays disabled while (expiresAt - now) > 9m01s, i.e. for the first ~59 seconds of the server's 10-minute TTL (ContactVerification.LIFETIME), then enables. Verify by waiting a minute rather than assuming.  `<button class="linkish" id="email-resend" disabled>`
  - [ ] data-t="verified" / AR 'تمّ التحقّق' — "Verified" (with a tick svg) — Read-only success mark.  `<p class="w-verified" id="email-verified" hidden>`
  - [ ] #email-error — SAY['need-email'] "Enter your email address.", SAY['need-code'] "Enter the code we sent you.", SAY['code-send-failed'] "We could not send a code just now.", SAY['code-refused'] "That code was not accepted.", SAY['network-failed'] "We could not reach the server. Check your connection and try again.", or the onboarding service's own {"message"} verbatim — showError() distinguishes our strings (re-translated on a language flip) from the server's (left exactly as sent). A fetch TypeError — no network, service down, blocked origin — is always rewritten to 'network-failed'.  `<p class="form-error" id="email-error" hidden>`
  - [ ] data-t="back" / AR 'رجوع' — "Back" — To step 1. No confirmation and nothing is lost.  `<button class="secondary" data-nav="back">`
  - [ ] NEXT_LABEL.phone — "Continue to Phone" / AR 'متابعة إلى رقم الهاتف' — Ships disabled in the markup; enabled ONLY by a successful Verify and disabled again the moment the address is edited.  `<button class="primary" data-nav="next" id="email-continue" disabled>`

### Step 3 — A phone number, optional (section[data-step="phone"])  — no driving test
*An optional second verified channel. The only step in the wizard with three buttons and the only one that can be walked past unanswered.*

- file: `D:/workspace/delivery/clients/website/register.html`
- reached by: Step 2 -> "Continue to Phone". Back from step 4 (CARRIER) or the review step (MERCHANT).
- states: API UNREACHABLE: Send code shows 'network-failed', but this step is NOT a stop — Skip this still works and the application can be completed without a phone (the server accepts a null phone; that path is the one the old smoke test exercised). · Three states to tick: never touched -> Skip; verified -> Continue; verified then edited -> un-verified, Continue disabled, code box hidden, Send code back.

  - [ ] data-t="phone-note" — "Useful when something about an order needs sorting out quickly. If you would rather not, skip this…" — Static copy.  `<p class="w-note">`
  - [ ] data-t="phone-label" / AR 'رقم الهاتف' — "Phone" + data-t="optional" — "optional" — NOT marked required (the stale smoke test guards exactly this). Seeded from #phoneSeed by seedPhone() only while empty and unverified. Goes readOnly after verification; the server's normalised form (punctuation stripped) replaces what was typed.  `<input id="contactPhone" type="tel" maxlength="32" autocomplete="tel" placeholder="+961 …">`
  - [ ] **[destructive]** data-t="send-code" — "Send code" — DESTRUCTIVE IN DEV — POST /api/onboarding/verifications {channel:'PHONE'}. In dev every simulated SMS becomes a real email to SMS_TEST_INBOX (youssef.saleh0108@gmail.com per the dev kustomization).  `<button class="secondary w-send" id="phone-send">`
  - [ ] data-t="code-label" — "The code we sent" — Same shape as the email code box.  `<input id="phone-code" inputmode="numeric" autocomplete="one-time-code" maxlength="6"> in #phone-code-box`
  - [ ] data-t="verify" — "Verify" — POST /verifications/confirm; on success sets state.phone/state.phoneToken, CLEARS state.skippedPhone, and enables #phone-continue.  `<button class="primary w-confirm" id="phone-confirm">`
  - [ ] **[destructive]** #phone-expiry countdown + data-t="send-another" — "Send another" — Identical 10-minute / ~59-second cooldown behaviour to the email step. Resend sends a second real message.  `<span id="phone-expiry"> and <button class="linkish" id="phone-resend" disabled>`
  - [ ] data-t="verified" — "Verified"; #phone-error (same SAY keys as the email step, with SAY['need-phone'] "Enter a phone number.") — Read-only marks.  `<p class="w-verified" id="phone-verified" hidden> / <p class="form-error" id="phone-error" hidden>`
  - [ ] data-t="back" — "Back" — To the email step.  `<button class="secondary" data-nav="back">`
  - [ ] data-t="skip-this" / AR 'تجاوز هذه الخطوة' — "Skip this" — Deliberately a full-weight button beside the others, not a small link. CLEARS the field, state.phone and state.phoneToken, sets skippedPhone and jumps to the step after phone (documents for CARRIER, review for MERCHANT). Test: verify a phone, then press Skip — the proof must be discarded, not merely bypassed.  `<button class="secondary" id="phone-skip">`
  - [ ] NEXT_LABEL.documents — "Continue to Documents" (CARRIER) / NEXT_LABEL.review — "Review and Send" (MERCHANT) — Disabled until a phone is verified. The label differs by kind because the destination does — check both.  `<button class="primary" data-nav="next" id="phone-continue" disabled>`

### Step 4 — Regulatory Documents PREVIEW (section[data-step="documents"]) — CARRIER ONLY  — UNREACHABLE, no driving test
*A read-only preview of the papers that will be asked for after submission. Deliberately has nothing to press.*

- file: `D:/workspace/delivery/clients/website/register.html`
- reached by: Choose "A delivery company" on step 1 (or arrive via /register?kind=CARRIER or the landing page's "Partner With Us"), then Continue through email and phone.
- **unreachable:** A MERCHANT never sees this step at all — FLOW.MERCHANT is ['business','email','phone','review'] — yet DOCUMENTS.MERCHANT is populated, so a shop's first sight of the upload rows is the receipt, with no preview and no mention of documents on its review summary.
- states: API UNREACHABLE: no effect. Nothing here touches the network. · Rows are rebuilt from the same PAPERS/DOCUMENTS tables the receipt's live panel uses, so the preview and the real thing cannot drift — which is why the wrong CARRIER kind shows up in both. · The design's Tax & VAT Certificate and Active Fleet Insurance rows were dropped on the grounds that no document kind existed for them; TRADE_LICENCE, FLEET_INSURANCE and FLEET_REGISTRATION now DO exist in the enum, so three carrier papers have no row anywhere on this site.

  - [ ] data-t="documents-note" — "You will attach these on the next screen, once your application is in and you have chosen a passcode. Nothing is uploaded from this step." — Static copy.  `<p class="w-note">`
  - [ ] PAPERS.COMMERCIAL_REGISTRATION — "Commercial Registration (CR)" / AR 'السجل التجاري'; detail SAY['doc-photo-or-pdf'] — "A photo or a PDF"; action SAY['doc-after-submit'] — "After you submit" / AR 'بعد إرسال الطلب' — NO CONTROL BY DESIGN — a deliberately absent affordance rather than a disabled button. Confirm nothing here is clickable or focusable.  `<div class="w-upload"> built by documentRow() into #documents-preview, with a plain <span class="w-later"> where the design drew a Choose File button`
  - [ ] PAPERS.NATIONAL_ID — "Authorized Signatory Owner ID" / AR 'هوية المفوّض بالتوقيع'; same detail and 'After you submit' label — NO CONTROL. AND THE PROMISE IS FALSE: the service refuses NATIONAL_ID for a CARRIER application (DocumentKind.java:51), so this row previews a paper that can never be attached — see the receipt's documents panel.  `<div class="w-upload"> (second row of #documents-preview)`
  - [ ] data-t="back" — "Back" — To the phone step.  `<button class="secondary" data-nav="back">`
  - [ ] NEXT_LABEL.fleet — "Next: Fleet Setup" / AR 'التالي: بيانات الأسطول' — No validation — this step always passes.  `<button class="primary" data-nav="next">`

### Step 5 — Fleet & Service Scope (section[data-step="fleet"]) — CARRIER ONLY  — no driving test
*Capacity and coverage. Everything here rides to the server inside the free-form `details` object.*

- file: `D:/workspace/delivery/clients/website/register.html`
- reached by: CARRIER path only: step 1 (delivery company) -> email -> phone -> documents -> "Next: Fleet Setup".
- states: API UNREACHABLE: no effect — fully client-side. · Zero vehicle types selected is a valid, silent empty state: no summary row and no details.vehicleTypes key.

  - [ ] data-t="fleet-size" / AR 'العدد التقديري للمندوبين أو السائقين العاملين' — "Estimated Number of Active Riders/Drivers" (required *) — validateFleet() demands a finite number >= 1. min/max are advisory only — there is no <form>, so the browser never enforces them; try 0, -5, 1e9 and 'abc'. Goes to details.fleetSize.  `<input id="fleetSize" type="number" min="1" max="100000" step="1" placeholder="48">`
  - [ ] data-t="vehicles-label" / AR 'أنواع المركبات المتوفّرة' — "Vehicle Types Available" (NOT required) — Groups the four chips.  `<div class="w-chips" role="group" aria-labelledby="vehicles-label">`
  - [ ] data-t="veh-motorcycle" / AR 'درّاجات نارية' — "Motorcycles" — Custom checkbox — the real input is clipped, the glyph swap is pure CSS :has(), and focus shows via .w-chip:focus-within. Test with the keyboard: :has() support and the focus ring are the two things that break here. Selected values go to details.vehicleTypes.  `<label class="w-chip"><input type="checkbox" name="vehicleType" value="MOTORCYCLE"> with paired .on (tick) and .off (empty box) inline SVGs swapped by :has(input:checked)`
  - [ ] data-t="veh-car" / AR 'سيارات' — "Cars" — Same. Zero selected is allowed — the row is simply omitted from the summary and from details.  `<label class="w-chip"><input type="checkbox" name="vehicleType" value="CAR">`
  - [ ] data-t="veh-van" / AR 'فانات' — "Vans" — Same.  `<label class="w-chip"><input type="checkbox" name="vehicleType" value="VAN">`
  - [ ] data-t="veh-truck" / AR 'شاحنات' — "Trucks" — Same.  `<label class="w-chip"><input type="checkbox" name="vehicleType" value="TRUCK">`
  - [ ] data-t="regions-label" / AR 'المناطق المفضّلة للعمل' — "Preferred Operating Regions" (required *). Placeholder data-t-placeholder="regions-hint" — "e.g. Beirut, Mount Lebanon" — Free text, deliberately NOT a select (there is no zones catalogue behind this page). validateFleet() requires it non-blank. Goes to details.operatingRegions.  `<input id="operatingRegions" type="text" maxlength="240">`
  - [ ] data-t="hours-label" / AR 'أوقات العمل المفضّلة' — "Preferred Operating Hours" (required *) — Always has a value, so the * is cosmetic and it is never validated. The review row copies the chosen option's own textContent, so switching language before reviewing must change the summary row too.  `<select id="operatingHours"> with 5 <option>: hours-24 "24 Hours (Full Service)", hours-day "Daytime (08:00 – 20:00)", hours-evening "Evenings and nights (16:00 – 02:00)", hours-weekend "Weekends only", hours-other "Other — described in the notes"`
  - [ ] #fleet-error — SAY['need-fleet-size'] "Please give roughly how many riders or drivers you have active." / SAY['need-region'] "Please name at least one area you would like to work." — Blocking validation, checked in that order.  `<p class="form-error" id="fleet-error" hidden>`
  - [ ] data-t="back" — "Back" / NEXT_LABEL.review — "Review and Send" / AR 'المراجعة والإرسال' — Back to the documents preview; forward to review after validateFleet() passes.  `<button class="secondary" data-nav="back"> and <button class="primary" data-nav="next">`

### Step 4|6 — Check and send (section[data-step="review"])  — no driving test
*The last look, and the one button on this surface that creates a record a human has to deal with.*

- file: `D:/workspace/delivery/clients/website/register.html`
- reached by: MERCHANT: phone step -> "Review and Send". CARRIER: fleet step -> "Review and Send".
- states: API UNREACHABLE: 'Send application' shows 'We could not reach the server…', the button re-enables and restores its label, and everything typed is still on screen — the one failure on this page that is genuinely recoverable by retrying. · Double-submit guard is the disabled attribute only; a slow network plus a second click is worth testing for duplicate applications. · Summary is rebuilt on every entry to the step and re-translated in place on a language flip.

  - [ ] #summary rows — SAY['sum-applying-as'] "Applying as" (value SAY['sum-shop'] "A shop" / SAY['sum-carrier'] "A delivery company"), WORDING[kind].business, WORDING[kind].contact, SAY['sum-email'] "Email", SAY['sum-phone'] "Phone" (SAY['sum-verified'] "{value} ✓ verified" or SAY['sum-not-given'] "Not given"), and for CARRIER also SAY['sum-registration'] "Registration no.", SAY['sum-company-type'] "Company type", SAY['sum-documents'] "Documents" = SAY['sum-documents-later'] "Attached on the next screen", SAY['sum-riders'] "Riders / drivers", SAY['sum-vehicles'] "Vehicles", SAY['sum-regions'] "Regions", SAY['sum-hours'] "Hours"; plus SAY['sum-notes'] "Notes" for either kind — Read-only. Deliberately XSS-safe: values are set as text, never interpolated into markup (a business name of `<script>` must render as literal text — worth actually trying). Terms and chosen options are translated (write); business name, contact name, CR number, region text and notes are NOT (writeRaw). NOTE: a MERCHANT's summary has no Documents row at all, yet the receipt will show a merchant two upload rows.  `<dl class="w-summary" id="summary"> — empty <dt>/<dd> pairs built with innerHTML then filled with textContent only`
  - [ ] data-t="back" — "Back" — To the previous step in this kind's flow (phone for MERCHANT, fleet for CARRIER).  `<button class="secondary" data-nav="back">`
  - [ ] **[destructive]** SAY['send-application'] / data-t="send-application" / AR 'أرسل الطلب' — "Send application" (becomes SAY.sending "Sending…") — DESTRUCTIVE — POST /api/onboarding/applications creates a real record in the BACKOFFICE reviewer queue that a person must approve or reject to clear (the old smoke test cleaned up after itself for exactly this reason). Spends both verification tokens. On a 400 WITH details it silently retries once WITHOUT the details object (forward-compat with an older service) — so a carrier's fleet answers can be dropped and the applicant is never told. On success: writes body.reference, hides #wizard, shows #receipt, scrolls to top. There is no way back to the wizard afterwards.  `<button class="primary" id="submit">`
  - [ ] #submit-error — SAY['submit-failed'] "Something went wrong sending that. Please try again.", SAY['network-failed'], or the service's own {"message"} verbatim (e.g. the 422 for an unproved address) — Second-attempt failures are what get reported, not the first.  `<p class="form-error" id="submit-error" hidden>`
  - [ ] data-t="review-note" / AR 'نقرأ كل طلب يصلنا، وسنردّ عليك في الحالتين.' — "We read every application. You will hear from us either way." — Static copy below the buttons.  `<p class="w-note">`

### Receipt — Application Submitted Successfully (#receipt.w-receipt.wizard-done)  — no driving test
*Hands over the reference, sells a passcode (which creates the applicant's real account), and unlocks the document uploads.*

- file: `D:/workspace/delivery/clients/website/register.html`
- reached by: Only by pressing "Send application" on the review step in the SAME page load. It is a sibling div toggled from hidden — it has no URL, survives no reload, and cannot be reached any other way.
- states: API UNREACHABLE: 'Set it' -> 'We could not reach the server…' and the documents panel never appears. 'Check its status' -> the same sentence in #status. The reference is still on screen and still valid — that is the only thing the applicant keeps. · IAM UNREACHABLE or its origin not allowed: the account POST may SUCCEED and the sign-in still fail, leaving an account created that this page cannot use. The message shown is the generic network one. · SESSION EXPIRED mid-upload: sessionLost() nulls the tokens, hides 'Signed in', re-shows the note and the passcode row, and writes 'Your sign-in has run out. Type your passcode again to carry on.' Reachable by waiting out the token (authFetch refreshes ahead of expiry and once more on a 401 first). Tokens live in a plain JS variable only — never storage — so this is by design. · SAY['lost-track'] ("We have lost track of your application on this page…") is UNREACHABLE from the UI: it needs an empty reference or a null state.email on a screen that only exists once both are set. · Reload here loses everything; there is no /register?ref= or any way back to a receipt.

  - [ ] no data-t — logo + #receipt-eyebrow (WORDING[kind].hub — "Merchant Hub" / "Carrier Hub") — Back to the landing page — and the reference and session are gone for good.  `<a class="w-receipt-logo" href="/">`
  - [ ] data-t="receipt-title" / AR 'تمّ إرسال طلبك بنجاح' — "Application Submitted Successfully"; data-t="receipt-lede" — Static copy.  `<h1> and <p> under a <span class="w-badge"> tick`
  - [ ] data-t="your-reference" / AR 'رقمك المرجعي' — "Your reference" — Written with writeRaw (never translated). >= 20 chars, 160 bits. The ONLY key to the application until the platform writes back; also emailed to the verified address. One click selects the whole thing — verify that, and verify it does not reflow in RTL.  `<p class="reference" id="reference"> — monospace, dashed border, user-select:all, forced direction:ltr in Arabic`
  - [ ] data-t="set-passcode" / AR 'اختر رمز الدخول' — "Set your passcode" + data-t="account-note" — "Six digits. It signs you in right here so you can attach your papers…" — Static copy; #account-note is hidden once signed in and re-shown by sessionLost().  `<p class="w-block-title"> and <p class="w-note" id="account-note"> in <div class="w-block" id="account-block">`
  - [ ] data-t="passcode-label" / AR 'رمز الدخول' — "Passcode" (required *) — EXACTLY six digits, enforced by /^\d{6}$/ in JS (the service itself would take 6-128 chars; six is chosen because the mobile keypad refuses anything else). type=password because this page is written for a shared shop computer. Forced direction:ltr in Arabic.  `<input id="passcode" type="password" inputmode="numeric" autocomplete="new-password" minlength="6" maxlength="6" pattern="[0-9]{6}" placeholder="••••••">`
  - [ ] **[destructive]** data-t="set-it" / AR 'اعتمده' — "Set it" (becomes SAY.setting "Setting…" / AR 'جارٍ الحفظ…') — DESTRUCTIVE — two calls. (1) POST /api/onboarding/applications/{reference}/account creates a REAL Keycloak user carrying the APPLICANT role, keyed on the verified email; this cannot be undone from this page. (2) A direct password grant against ${IAM}/realms/delivery-platform/protocol/openid-connect/token with client_id 'mobile-app'. Creation failure is SWALLOWED if sign-in then succeeds (so 'you already did this' self-heals on a second attempt with the same passcode). On success: clears the field, hides the note and the input row, shows 'Signed in', and calls openDocuments().  `<button class="primary w-send" id="account-save">`
  - [ ] data-t="signed-in" / AR 'تمّ تسجيل الدخول' — "Signed in" (with tick) — Read-only success mark; hidden again by sessionLost().  `<p class="w-verified" id="account-done" hidden>`
  - [ ] #account-error — SAY['passcode-six'] "Please choose six digits.", SAY['passcode-refused'] "That passcode was not accepted." (Keycloak invalid_grant), SAY['passcode-failed'], SAY['signin-not-allowed'] "This page is not allowed to sign you in yet. Your application is still in — we will ask for your documents by email." (invalid_client / unauthorized_client), SAY['session-lost-note'] "Your sign-in has run out. Type your passcode again to carry on.", SAY['lost-track'], SAY['network-failed'], or Keycloak's own error_description verbatim — Note the mapping gap: a CORS refusal from Keycloak (the likely real-world failure — see the Web Origins finding) is a fetch TypeError and therefore reports 'We could not reach the server', NOT the far more helpful 'not allowed to sign you in yet'.  `<p class="form-error" id="account-error" hidden>`
  - [ ] data-t="whats-next" — "What happens next?" with next1-title "Documents Auditing" (marked .is-now), next2-title "Verification Call", next3-title "Hub Activation" + next3-body "Approval opens your dashboard. The passcode you set above is the one that gets you in." — Static. Row 1 is always highlighted regardless of the real status.  `three <div class="w-next-row"> with numbered <span class="w-next-num">`
  - [ ] data-t="info-line" — "Verification typically takes 1 – 5 business days. You'll receive email alerts at every step." — Static copy.  `<div class="w-info"> with an info svg`
  - [ ] data-t="check-status" / AR 'تحقّق من حالة الطلب' — "Check its status" — Unauthenticated GET /api/onboarding/applications/by-reference/{reference}. Writes into #status one of six mapped sentences: SUBMITTED "Received — waiting for someone to read it.", IN_REVIEW "Someone is reading it now.", APPROVED "Approved. We are setting your account up.", PROVISIONED "Approved and ready — check your email to set a password.", REJECTED "Not this time: {reason}" (the reviewer's own words, untranslated), FAILED "Approved, but setting your account up did not finish. We are on it."; SAY['status-unknown'] "We could not find that reference." on any non-200. CONTENT BUG: the PROVISIONED line tells the applicant to check their email for a password, contradicting next3-body two blocks above which says the passcode they just set is the one that works. All six service statuses are mapped, so STATUS.UNKNOWN is dead code.  `<button class="primary" id="check">`
  - [ ] data-t="back-to-site" / AR 'العودة إلى الموقع' — "Back to the site" — Leaves. Reference and session are unrecoverable afterwards.  `<a class="secondary" href="/">`
  - [ ] #status — SAY.checking "Checking…" then the status sentence or an error — Re-translates live if the language is flipped while it is showing.  `<p class="status-line" id="status" hidden>`

### Receipt — Your documents panel (#documents-block, gated)  — UNREACHABLE, no driving test
*The only working upload on this surface — the three-step presign / PUT-to-storage / confirm dance, as the mobile app does it.*

- file: `D:/workspace/delivery/clients/website/register.html`
- reached by: On the receipt, type six digits and press "Set it" successfully. #documents-rule and #documents-block are hidden until openDocuments() runs; there is no other way to reveal them.
- **unreachable:** For a CARRIER application the second row (NATIONAL_ID) can NEVER succeed: the service's CARRIER document set is {TRADE_LICENCE, COMMERCIAL_REGISTRATION, FLEET_INSURANCE, FLEET_REGISTRATION} (DocumentKind.java:51), so presign throws DocumentRuleException -> 422 and the row shows the server's sentence 'A carrier application does not ask for a national_id'. Conversely the three carrier papers the service DOES expect have no row on this page at all. A MERCHANT's two rows both work (MERCHANT_DOCUMENTS = {NATIONAL_ID, COMMERCIAL_REGISTRATION}).
- states: API UNREACHABLE: presign rejects -> 'We could not reach the server…' in #documents-error and the row reverts to whatever it honestly was (an accepted document goes back to saying Accepted, an empty row goes back to 'A photo or a PDF'). · STORAGE UNREACHABLE but API up: the PUT fails -> 'That upload did not finish. Please try again.' (a non-2xx) or 'network-failed' (a rejection). The document is never confirmed. · SILENT EMPTY STATE — the load of already-filed documents (GET /api/onboarding/applications/mine/documents) is wrapped in a catch that says NOTHING. If that call fails, both rows render empty and invite a re-upload of papers that are already on file. Test by killing the API between 'Set it' succeeding and the panel painting. · DECIDED APPLICATION: requireOpenForUpload throws 422 'This application has already been decided, so its documents cannot change' — surfaced verbatim. · Below 560px .w-upload wraps. · On a language flip the pill, the detail line and the button's aria-label all re-translate in place (both halves of 'Choose a file for {title}'), while a reviewer's rejection reason stays as written.

  - [ ] data-t="your-documents" / AR 'مستنداتك' — "Your documents" + data-t="documents-note-2" — "A photo or a PDF of each. Upload a better copy any time before a decision — the newest one is the one a reviewer reads." — Static copy.  `<p class="w-block-title"> and <p class="w-note">`
  - [ ] **[destructive]** PAPERS.COMMERCIAL_REGISTRATION — "Commercial Registration (CR)" / AR 'السجل التجاري'; button SAY['doc-choose'] "Choose File" / AR 'اختر ملفاً', aria-label SAY['doc-choose-for'] "Choose a file for {title}" / AR 'اختر ملفاً لمستند {title}' — DESTRUCTIVE — writes to the KYC bucket and puts a document in front of a reviewer. Sequence: POST /api/onboarding/applications/mine/documents/presign {kind,contentType} (Bearer token) -> size checked against ticket.maxSizeBytes BEFORE any bytes move -> PUT straight to storage with NO Authorization header (the URL carries its own signature) -> POST /api/onboarding/applications/mine/documents/{fileId}/confirm. Re-choosing the same file fires again (picker.value is cleared). Uploading over a live document supersedes rather than replaces it, so an earlier verdict stays on the record.  `<div class="w-upload"> with a display:none <input type="file" class="w-file" accept="image/jpeg,image/png,image/webp,application/pdf,.jpg,.jpeg,.png,.webp,.pdf"> driven by a real <button class="w-choose"> (one tab stop, keyboard-operable, individually named)`
  - [ ] **[destructive]** PAPERS.NATIONAL_ID — "Authorized Signatory Owner ID" / AR 'هوية المفوّض بالتوقيع'; same Choose File button and per-row aria-label — DESTRUCTIVE for a MERCHANT (works). For a CARRIER it always fails at presign with a 422 — see unreachable above.  `second <div class="w-upload"> in #documents-list`
  - [ ] button becomes SAY['doc-replace'] "Replace" / AR 'استبدل' once a document exists — Same three-step upload; the row keeps its old state if the replacement fails.  `same <button class="w-choose">, relabelled by show()`
  - [ ] row pills — SAY['doc-uploading'] "Uploading…" (is-wait), SAY['doc-accepted'] "Accepted" / AR 'مقبول' (is-ok, row .is-done), SAY['doc-refused'] "Needs a new copy" / AR 'يحتاج نسخة جديدة' (is-bad, row .is-bad), SAY['doc-waiting'] "Awaiting review" / AR 'بانتظار المراجعة' (is-wait) — Read-only status. Detail line under the title becomes doc-accepted-note / doc-waiting-note / the REVIEWER'S OWN rejectionReason verbatim (never translated) or doc-refused-note when there is none.  `<span class="w-pill"> appended to each row`
  - [ ] #documents-error — SAY['doc-types'] "We take JPEG, PNG, WebP or PDF files.", SAY['doc-too-big'] "That file is {size} and the limit is {limit}." (both sizes via SAY.megabytes "{n} MB"), SAY['doc-presign-failed'], SAY['doc-put-failed'] "That upload did not finish. Please try again.", SAY['doc-confirm-failed'], SAY['passcode-first'] "Set your passcode first.", SAY['session-lost'], SAY['network-failed'], or the service's 422 message verbatim — typeOf() falls back to the file EXTENSION when the browser reports an empty MIME type — worth testing a .pdf with no type, and a .txt renamed to .pdf.  `<p class="form-error" id="documents-error" hidden>`

### Platform administration (admin.html)  — no driving test
*A one-card signpost to the Backoffice. Not a security control — the portal enforces the BACKOFFICE realm role on every request; this page only keeps the door out of the public shopfront.*

- file: `D:/workspace/delivery/clients/website/admin.html`
- reached by: TYPE /admin or /admin/ in the address bar. Nothing on the site links here, robots.txt deliberately does not name it, and the smoke test asserts the word 'admin' appears nowhere in any file a stranger can read. nginx serves it via `location = /admin { try_files /admin.html =404; }` so the address in the bar stays /admin.
- states: API UNREACHABLE: no effect. This page loads no JS at all (not even config.js or site.js — only site.css plus a <style> block) and makes no network calls. · No language switch and no Arabic — the whole page is English-only, unlike every other page on this surface. · <meta name="robots" content="noindex, nofollow"> is the only thing keeping it out of search results; robots.txt stays silent on purpose so crawlers still fetch the page and see the tag. · Copy states 'Staff only. You will be asked to sign in.' — this page itself asks for nothing.

  - [ ] no l10n on this page at all — "Open the Backoffice" — Leaves for the portal, which will demand a sign-in (backoffice/400004). Hard-coded absolute URL in the markup, not read from config.js — this link previously pointed at a dead 127.0.0.1:5011 and would rot the same way again.  `<a class="primary wide" href="https://portal-dev.youdrop.shop">`
  - [ ] "Back to the site" — Returns to the landing page.  `<a class="back" href="/">`

### /app — the Android APK download route  — UNREACHABLE, no driving test
*The single stable address every download route and the QR code encode. It is a file, not a page.*

- file: `D:/workspace/delivery/clients/website/nginx.conf`
- reached by: Four links on the landing page (hero "Become a Rider", riders band "Become a Rider", Butler band "Download Customer App", "Download the APK directly"), plus scanning the QR code, plus typing /app. Anything under /app/ — including the raw /app/youdrop.apk — 301s here.
- **unreachable:** Serves 404 whenever the Android build has not been pushed — infra/deploy-website.sh takes the APK as an OPTIONAL second argument, and the deploy explicitly preserves the existing app/ directory (`! -name app`) rather than shipping one. Confirm the current state of https://www.youdrop.shop/app before ticking the four buttons and the QR code that all point at it.
- states: 404 when no APK is deployed — deliberately NOT falling back to index.html, so a QR scan cannot silently loop back to the page it was scanned from. · Under k3s the pod is memory-limited to 128Mi specifically so a ~70MB APK can stream to several phones at once — worth a concurrent-download check. · absolute_redirect is off, so the /app/ 301 emits a path-only Location and a phone that scanned the QR over HTTPS is not bounced through cleartext.

  - [ ] n/a — a route, not a control — Hands over the file as a download rather than rendering it. Verify the three response headers, and verify that /app/anything 301s to /app without looping (the =404 branch fires add_header only on success, so a 404 does not claim to be a file).  `nginx `location = /app` with default_type application/vnd.android.package-archive, Content-Disposition: attachment; filename="youdrop.apk", X-Content-Type-Options: nosniff, try_files /app/youdrop.apk =404`

### /robots.txt  — no driving test
*Invites crawlers onto the shopfront and — deliberately — says nothing about /admin.*

- file: `D:/workspace/delivery/clients/website/nginx.conf`
- reached by: Type /robots.txt.
- states: Static, no API involvement.

  - [ ] n/a — a route — Tick that the body is exactly 'User-agent: *' / 'Allow: /' and that the word 'admin' does not appear. A Disallow line here would publish the staff door in the one file every scanner reads first, and would stop crawlers ever fetching the page whose noindex tag does the real work.  `nginx `location = /robots.txt { add_header Content-Type text/plain; return 200 "User-agent: *\nAllow: /\n"; }``

## CustomerShell — mobile_app (Flutter), demo login customer / 100001

33 screens, 281 controls.

### CustomerShell (frame: Scaffold + IndexedStack + drawer)
*The five-tab frame: owns the one Cart, the DeliveryAddressStore (scoped to session.subject), the NotificationInbox poll, and the ProfileDrawer that slides over every tab.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/customer_shell.dart`
- reached by: Sign in as customer/100001 -> SplashScreen -> main.dart role branch (_customerShell, main.dart:437) -> lands on Home (index 0).
- covered by: test/customer_nav_bar_test.dart — DRIVES all five destinations (taps each, asserts the reported index), the basket count, a 3-figure count, a small phone, and Arabic mirroring. integration_test/order_lifecycle_test.dart taps navBasket and navOrders for real.
- states: Cart badge 0 (no badge) / 1..99 / 3-figure · IndexedStack keeps each tab's scroll position and in-flight requests — switching away and back must NOT refetch the catalog · Sign-out then sign-in as a different account: shell is keyed by session.subject, so basket/address/inbox must be empty for the new account

  - [ ] t.navHome = "Home" — IndexedStack index 0 -> StoreHomeScreen. All five tabs are built eagerly, so their timers run whichever tab shows.  `YdBottomNavItem inside YdBottomNav (custom, not BottomNavigationBar)`
  - [ ] t.navButler = "Butler" — index 1 -> ButlerScreen.  `YdBottomNavItem`
  - [ ] t.navBasket = "Basket" — index 2 -> CartScreen. Badge shows cart.itemCount; zero draws no badge at all — check it appears on first add and disappears on last remove.  `YdBottomNavItem with badgeCount`
  - [ ] t.navOrders = "Orders" — index 3 -> MyOrdersScreen.  `YdBottomNavItem`
  - [ ] t.navAccount = "Account" — index 4 -> RewardsScreen (NOT AccountScreen — see the AccountScreen row).  `YdBottomNavItem`
  - [ ] (no label) drawer edge-drag — Opens ProfileDrawer from ANY tab by swiping from the start edge — an entry path the design does not draw and no test exercises.  `Scaffold.drawer default drawerEnableOpenDragGesture`

### StoreHomeScreen (Home tab)
*The storefront: greeting header with address + bell, pinned search, category tiles, promo banners, favourites rail, then the paged shop grid.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/store_home_screen.dart`
- reached by: Sign in -> Home tab (default landing).
- covered by: integration_test/customer_test.dart — DRIVES it live (waits for custHiName, asserts noShopsMatch absent, taps up to 3 shop cards until a stocked one is found). integration_test/order_lifecycle_test.dart waits on custActiveStoresNearby then taps into a shop. test/category_strip_test.dart drives only the strip's height at 1x and at raised text scale.
- states: Loading: full-screen CircularProgressIndicator while isLoadingFirstPage || _loadingRails · Error: Icons.cloud_off_rounded + t.couldNotLoadStorefront = "Could not load the storefront" + the raw exception text + Try again · Empty: YdEmptyState t.noShopsMatch = "No shops match", message t.tryClearingAFilter = "Try clearing a filter or two." when filters active, else t.nothingDeliveringHere = "Nothing is delivering here just yet." · No banners / no favourites / no chips: those sections are simply absent, not empty-stated · Shop closed: meta line shows t.statusClosed = "Closed" instead of the ETA and drops the fee · Section subtitle t.shopsDelivering(n) is ICU-plural and uses the SERVER total, except under the Offers chip where it counts what is on screen

  - [ ] Avatar, Semantics label t.custAccountSettings = "Account Settings" — Scaffold.of(context).openDrawer() -> ProfileDrawer. This is the ONLY drawn entrance to the drawer and therefore to sign-out.  `InkWell(customBorder: CircleBorder) wrapping StoreMonogram or ClipOval Image`
  - [ ] t.custHiName(firstName) = "Hi, {name}" — Read-only. First word of session.displayName.  `Text`
  - [ ] Address row — addresses.headerLabelOr(t.setDeliveryAddress = "Set delivery address") — showAddressSheet(zoneApi:) — no geocodingApi passed here, so the place-search block is NOT drawn on this entry (it IS on checkout's). Worth diffing.  `InkWell + Icons.location_on_outlined + Icons.keyboard_arrow_down`
  - [ ] Bell, Semantics label t.alerts = "Alerts" — Pushes NotificationsScreen. Badge = inbox.unread, polled every 15s.  `Material+InkWell 32px disc with brand count badge`
  - [ ] t.searchShops = "Search shops and cuisines" (hint cycles t.custSearchInCategory = "Search in {name}" every 2.8s) — 350ms-debounced server search re-running the grid only. The animated hint freezes the moment you type — check it does.  `YdSearchField (custom)`
  - [ ] Filter glyph Icons.tune, Semantics label t.custFilters = "Filters" — Toggles the refine chip row in/out below the strip.  `YdSearchField.onFilterTap`
  - [ ] t.filterOffers = "Offers" — CLIENT-side filter (topOffer != null). Does not re-query; instead _onStoresChanged keeps calling loadMore until something is visible. Test with a shop set where offers are sparse.  `YdChip`
  - [ ] t.filterUnder30 = "Under 30 min" — maxEtaMinutes=30, re-queries. Tap again to clear.  `YdChip`
  - [ ] t.filterFreeDelivery = "Free delivery" — maxDeliveryFee=0, re-queries. Tap again to clear.  `YdChip`
  - [ ] t.filterHighlyRated = "4.5+" — minRating=4.5, re-queries. Tap again to clear.  `YdChip`
  - [ ] t.clear = "Clear" — filters.cleared() + re-query.  `YdChip (only rendered when _filters.isActive)`
  - [ ] Category tiles (curated CategoryChip.name, else vertical.labelIn) — Pushes ShopsListingScreen for that vertical. Does NOT filter the home grid.  `CategoryCard inside CategoryStrip (category_strip.dart)`
  - [ ] Pinned labels-only category row (same names) — Appears only once the tile strip scrolls under the pinned search bar; same _openListing. IgnorePointer when hidden — scroll down far enough to make it live, then tap.  `InkWell pills in a PositionedDirectional/AnimatedOpacity overlay`
  - [ ] Promo banner card (banner.title / banner.subtitle) — BannerLinkKind.store -> StorePageScreen; .category -> filters the home grid to that vertical; .url and .none -> TAP DOES NOTHING. A url banner still reports isTappable==true (store_models.dart:837) so it gets a live InkWell that silently no-ops.  `PageView.builder card, Material+InkWell, auto-advances every 4s`
  - [ ] Banner page dots — Indicator only — not tappable. Swipe the pager instead; the 4s timer resumes from wherever you left it.  `AnimatedContainer row`
  - [ ] t.yourFavourites = "Your favourites" — Section heading; the rail only renders when the account has starred shops.  `YdSectionHeader title`
  - [ ] t.custSeeAll = "See All" — QUIRK: does not open a favourites list — it animates the scroll controller to maxScrollExtent (the bottom of the shop grid). Confirm that is intended.  `YdSectionHeader.onAction (text action)`
  - [ ] Favourite shop card (store.name + rating/ETA/fee meta) — _openStore -> StorePageScreen with preview + onFavoriteChanged callback.  `CoverCard (product_detail_screen.dart) 260px`
  - [ ] Grid shop card (store.name + compact meta) — _openStore -> StorePageScreen.  `YdCard, two-up SliverGrid`
  - [ ] Heart, Semantics label t.addToFavourites = "Add to favourites" / t.removeFromFavourites = "Remove from favourites" — Optimistic star/unstar; patches both the grid and the favourites rail. On failure rolls back and shows t.couldNotUpdateFavourites = "Could not update your favourites." Both endpoints idempotent — double-tap is a valid test.  `GestureDetector over a white 85%-alpha circle (NOT an IconButton)`
  - [ ] t.custSplitRequestBanner(hostName) = "{name} invited you to split an order" / t.custPayYourShare = "Pay your share" — Pushes FriendSplitScreen for splitRequests.first, then reloads the request list on return. Only drawn when splitApi.requests() came back non-empty.  `Material+InkWell brandSoft banner`
  - [ ] t.couldNotLoadMore = "Could not load more — try again" — Retries the failed next page while keeping the pages already loaded.  `TextButton.icon in the grid footer`
  - [ ] t.tryAgain = "Try again" — Re-runs _load (grid + favourites + banners + chips in one Future.wait).  `YdPillButton (compact) in the error state`
  - [ ] Pull-to-refresh — Reloads grid, favourites, banners and category chips together.  `RefreshIndicator(onRefresh: _load)`
  - [ ] Infinite scroll — loadMore at 20/page. The depth guard exists because horizontal rails were satisfying the near-the-end check at position zero — regression-test by swiping the category strip and the banner rail sideways and confirming NO extra page loads.  `NotificationListener<ScrollNotification> guarded to notification.depth == 0`

### ShopsListingScreen  — no driving test
*One vertical's shops as tall photo cards, with the same refine chips behind a Sort/Filter link.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/shops_listing_screen.dart`
- reached by: Home -> tap a category tile in the CategoryStrip, OR scroll until the pinned labels-only row appears and tap a label there.
- states: Loading first page: SliverFillRemaining spinner · Empty: YdEmptyState Icons.storefront_outlined, t.noShopsMatch + t.tryClearingAFilter · Loading more: 22px footer spinner · Dark shop: whole card at 55% opacity but still tappable

  - [ ] Back chevron, Semantics t.back = "Back" — maybePop.  `YdBackButton inside YdScreenHeader`
  - [ ] t.allStores = "All stores" — Clears the vertical filter and refreshes.  `YdChip`
  - [ ] Vertical chips (vertical.labelIn) — Switches vertical, resets to page 0.  `YdChip row`
  - [ ] t.custShowingShops(count) = "Showing {count} shops" — Read-only; uses server totalElements when known.  `Text`
  - [ ] t.custSortFilter = "Sort / Filter" + Icons.tune — Toggles the refine chip row. NOTE: it says Sort but there is NO sort control behind it — only the three filter chips.  `InkWell + Semantics(button: true)`
  - [ ] t.filterUnder30 = "Under 30 min" — maxEtaMinutes toggle + refresh.  `YdChip`
  - [ ] t.filterFreeDelivery = "Free delivery" — maxDeliveryFee toggle + refresh.  `YdChip`
  - [ ] t.filterHighlyRated = "4.5+" — minRating toggle + refresh. The Offers chip from Home is deliberately NOT offered here.  `YdChip`
  - [ ] Shop card (name, power chip, rating, tagline, ETA, t.custMinOrderLine = "Min. Order: {amount}") — Pushes StorePageScreen with preview. No onFavoriteChanged is passed here, so a heart toggled on the shop page will NOT patch this list.  `YdCard(padding: zero); wrapped in Opacity(0.55) when powerStatus == dark`
  - [ ] Power chip t.custPowerMains = "Mains Power" / t.custPowerGenerator = "Generator" / t.custPowerDark = "Currently Dark" — Read-only badge; drawn nowhere for StorePowerStatus.unknown.  `StorePowerChip(compact: true)`
  - [ ] Pull-to-refresh — Page 0 again.  `RefreshIndicator(onRefresh: _stores.refresh)`
  - [ ] t.tryAgain = "Try again" — Retries a failed next page.  `YdPillButton.secondary in the footer`

### StorePageScreen
*A shop's landing page — hero, power banner, three stats, four tabs (Shop / Aisles / Offers / Buy Again) and the sticky basket bar.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/store_page_screen.dart`
- reached by: Home -> favourites rail card OR grid card OR a store-linked banner; ShopsListingScreen -> shop card; Orders -> Past Orders -> t.custReorder; OrderDetailsScreen -> the shop card's chevron circle.
- covered by: integration_test/customer_test.dart — DRIVES it (opens up to 3 shops looking for a stocked one, reads a product name off a rendered card, taps into detail). integration_test/order_lifecycle_test.dart drives the add-to-basket path through it.
- states: Loading with no preview: bare spinner Scaffold · Load failed with no store: YdScreenHeader t.couldNotLoadShop = "Could not load this shop" + YdEmptyState + t.tryAgain · Shop tab empty: t.nothingOnShelves = "Nothing on the shelves yet" · Aisle/search empty: t.nothingInAisle = "Nothing in this aisle" · Aisles empty: t.noAislesYet = "This shop has no aisles yet" · Offers empty: t.noOffersHere = "No offers running here right now" · Buy Again with no orderApi: t.signInPrompt = "Sign in to see what you ordered before" (unreachable in the shipped build — orderApi is always passed) · Buy Again with no matching history: t.noHistoryHere = "Nothing from this shop in your history yet" · Shop closed/paused: every AddButton disabled

  - [ ] Back glass disc, Semantics t.back = "Back" — maybePop. Mirrors chevron direction in RTL.  `GlassCircleButton (custom 36px, product_detail_screen.dart) in SliverAppBar.title`
  - [ ] Search glass disc, Semantics t.custSearchInShop = "Search this shop" — Opens an in-shop YdSearchField sliver AND animates to tab 0. Closing it clears the query and refreshes the shelf — verify both directions.  `GlassCircleButton, glyph flips to Icons.close when open`
  - [ ] Heart glass disc, Semantics t.addToFavourites / t.removeFromFavourites — Optimistic star/unstar; calls onFavoriteChanged so the Home grid + rail update live. Rolls back silently (no snackbar here, unlike Home).  `GlassCircleButton`
  - [ ] t.custShopSearchHint = "Search the menu" — 350ms debounce; queries the WHOLE shop catalogue server-side, not the loaded pages.  `YdSearchField(autofocus: true)`
  - [ ] Stat: rating / t.custRatingsCount(n) = "{n} Ratings" ("No ratings" at 0) — Read-only. Falls back to t.ratingNew = "New".  `Text column, hairline-separated`
  - [ ] Stat: etaLabel / t.custDeliveryTime = "Delivery Time" — Read-only.  `Text column`
  - [ ] Stat: minOrder or t.free = "Free" / t.custMinOrderStat = "Min. Order" — Read-only.  `Text column`
  - [ ] Store state pill (availability.labelIn) — Drawn only when the shop is not OPEN.  `StoreStatePill`
  - [ ] t.custGeneratorBanner = "Generator hours — delivery may take longer" / t.custDarkBanner = "This shop is dark right now — orders may wait for power" — Read-only. Nothing at all for mains or undeclared.  `amber / grey Container strip`
  - [ ] t.tabShop = "Shop" — TabController index 0 — the paged shelf.  `Hand-built InkWell tab with a 24x3 bar (NOT a TabBar)`
  - [ ] t.tabAislesCount(n) = "Aisles ({n})" — index 1.  `InkWell tab`
  - [ ] t.tabOffersCount(n) = "Offers ({n})" — index 2.  `InkWell tab`
  - [ ] t.tabBuyAgain = "Buy Again" — index 3 — a SEPARATE PagedList reconstructed from order history intersected with the live catalogue.  `InkWell tab`
  - [ ] t.everything = "Everything" + aisle chips — Re-queries the shelf by categoryId (not an in-memory filter).  `YdChip row on the Shop tab`
  - [ ] Product row (name, description, $price + LBP) — _openProduct -> fetches options (cached per product) -> pushes ProductDetailScreen. Tapping the ROW and tapping Add reach the same place for an optioned product.  `YdCard with onTap`
  - [ ] Add, Semantics label t.add = "Add" — No options -> straight into the cart. Has options -> ProductDetailScreen. DISABLED (opacity 0.4, null onPressed) when the shop does not accept orders.  `AddButton (28px brand circle, custom)`
  - [ ] Remove, Semantics label t.remove = "Remove" — cart.removeProduct — removes ALL configurations of that product id at once, not one line.  `InkResponse with Icons.remove_circle_outline; only rendered when qtyOf(product) > 0`
  - [ ] In-basket count — Read-only; sums every configuration of that product.  `Text beside the stepper glyphs`
  - [ ] Aisle tile (aisle.name + t.itemCount = "{n} items") — Selects that aisle and animates back to tab 0.  `YdCard.bordered in a GridView`
  - [ ] Offer row (title, subtitle, t.appliesEverywhere = "Applies everywhere", badgeLabel) — Purely informational. An offer cannot be tapped or applied from here.  `YdCard — NO onTap`
  - [ ] t.viewBasket = "View basket" (or blocked: t.addToReachMinimumShort = "Add {amount} to reach the minimum") — Pops back to the shell. Blocked state is grey and onTap is null. REGRESSION AREA: the empty check must stay INSIDE the AnimatedBuilder — outside it, the bar never appeared on the first add.  `StickyBasketBar (design system) as bottomNavigationBar`
  - [ ] t.couldNotLoadMore = "Could not load more — try again" — Retries the failed page.  `TextButton.icon list footer`

### Start-a-new-basket dialog  — no driving test
*Enforces the one-store rule at the moment of the tap rather than as a 422 at checkout.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/store_page_screen.dart (_askToSwitchStore, ~line 275)`
- reached by: Put something in the basket at shop A -> open shop B -> tap Add or a product row.
- states: Only ever shown when cart.conflictsWith(product) is true

  - [ ] t.startNewBasket = "Start a new basket?" — Body is t.basketFromShopReplace(shop) + t.basketFromAnotherShopSingle = "We can only deliver from one shop at a time."  `AlertDialog title`
  - [ ] t.keepIt = "Keep it" — Pops false — nothing added, basket untouched.  `TextButton`
  - [ ] **[destructive]** t.startHere = "Start here" — cart.switchTo(newShop) then adds. DESTRUCTIVE — silently discards the entire basket from the other shop, with no undo.  `FilledButton (brand)`

### ProductDetailScreen
*Photo gallery, dual-price card, option groups re-priced against the catalogue on every change, quantity, and the cross-sell rail.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/product_detail_screen.dart`
- reached by: StorePageScreen (any tab that lists products: Shop, Buy Again) -> tap a product row, or tap Add on a product that has option groups.
- covered by: integration_test/customer_test.dart — DRIVES it (asserts custProductDetails and custDualPriceMode after tapping a product). integration_test/order_lifecycle_test.dart taps custAddToBasket on it for real.
- states: Pricing in flight: the CTA shows a white spinner · Pricing failed: t.couldNotPriceCombination = "Could not price that combination." in brand text above the CTA, CTA disabled · Suggestion options failed: SnackBar t.couldNotReachTheServer · No suggestions / endpoint silent: the whole rail is absent (never an empty rail) · No options at all: no groups, no pricing round trip, unit price = product price · Single or zero photos: static CustomerPhoto, no dots

  - [ ] Back, Semantics t.back = "Back"; title t.custProductDetails = "Product Details" — maybePop, returning null (nothing added).  `YdScreenHeader + YdBackButton`
  - [ ] Photo gallery — Swipe between images; white pill dots below (indicator only, not tappable).  `PageView.builder, only when imageUrls.length > 1`
  - [ ] t.custDualPriceMode = "Dual price mode" card (+ USD chip) — Read-only. Shows the LIVE unit price — it must change as options are ticked. LBP half is absent until MarketRates loads.  `brandSoft Container`
  - [ ] Option group header: group.name + t.required = "Required" / t.optional = "Optional" — Read-only rule marker.  `Text row`
  - [ ] Option pill: option.name (+ deltaLabel) / t.optionSoldOut(name) = "{name} — sold out" — Radio behaviour for singleChoice (re-tapping a REQUIRED group's selection keeps it; an optional group's clears it); checkbox behaviour otherwise. Every toggle fires a real priceSelection round trip. Sold-out pills are at 45% opacity with null onTap.  `VariantPill (custom, product_detail_screen.dart)`
  - [ ] Over the max: t.chooseUpTo(n, group) = "Choose up to {n} under {group}" — The tap is refused rather than silently ignored — worth pressing a 4th extra on a max-3 group.  `SnackBar (2s)`
  - [ ] t.custDecreaseQuantity = "Decrease quantity" / t.custIncreaseQuantity = "Increase quantity" — 1..99. Both sides disable at their bound (opacity 0.4, null onPressed).  `QuantityStepper (custom, product_detail_screen.dart)`
  - [ ] t.custAddToBasket = "Add to Basket" · live line total (or t.selectRequiredOptions = "Select required options") — Pops a ConfiguredProduct to the shop page, which adds it. Disabled while pricing, while a required group is unanswered, or after a pricing failure.  `Material+InkWell 48px pill with Semantics(enabled:)`
  - [ ] Cross-sell rail heading: t.crossSellBoughtTogether = "Often bought together" / t.crossSellSameShelf = "From the same shelf" / t.crossSellYouMightAlsoLike = "You might also like" — Title is chosen from the suggestions' basis — verify the wording matches what the server actually counted.  `YdSectionHeader`
  - [ ] Suggestion card (name, price, t.crossSellTogetherCount(n) = "{n}× together") — Fetches THAT product's options then pushes a nested ProductDetailScreen; a configured result is popped straight through two levels to the shop page. Re-entrancy guarded by _openingSuggestion — double-tap it.  `Material+InkWell 200px card`

### Product options bottom sheet (_OptionsSheet)  — UNREACHABLE, no driving test
*The pre-redesign lighter surface for the same job as ProductDetailScreen: DraggableScrollableSheet with radio/checkbox option rows, QuantityStepper and t.addWithTotal = "Add · {total}".*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/product_options_sheet.dart`
- reached by: Nothing. showProductOptionsSheet has ZERO call sites in lib/, test/ or integration_test/ — store_page_screen.dart:258 calls showProductDetail instead.
- **unreachable:** Dead code. No caller anywhere in the repo. It also duplicates ProductDetailScreen's toggle/reprice logic, so the two can drift silently. Either delete it or give it a call site; do not spend sweep time pressing it.
- states: N/A — never mounted

  - [ ] t.addWithTotal(total) = "Add · {total}" / t.selectRequiredOptions = "Select required options" — Would pop a ConfiguredProduct. Unreachable.  `YdPillButton in the sheet footer`
  - [ ] Option rows (Icons.radio_button_checked / Icons.check_box) — Same _toggle + reprice logic, duplicated. Unreachable.  `InkWell rows — a DIFFERENT presentation from ProductDetailScreen's VariantPill`

### CartScreen (Basket tab)
*The basket lines with steppers, the Solo/Split toggle and the whole group-split setup, the promo code row, and the itemised money plinth.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/cart_screen.dart`
- reached by: Basket tab (nav index 2), or the sticky basket bar on StorePageScreen (which pops back to the shell), or automatically after placing an order the shell jumps to Orders.
- covered by: integration_test/order_lifecycle_test.dart — DRIVES it (reaches it via navBasket and taps through to checkout). No test drives the split mode, the promo row, or the delete-at-1 stepper.
- states: Empty: YdEmptyState Icons.shopping_bag_outlined, t.basketEmpty = "Your basket is empty" — and NOTHING else renders (no promo row, no split toggle) · Promo checking: 12px spinner + t.custPromoChecking = "Checking the code…" · Promo refused by the server: custPromoReasonLabel(reason) in critical red · Promo unreachable: t.promoCouldNotCheck = "Could not check the code" — a DIFFERENT sentence from a refusal; both must be tested · Below minimum: info row + disabled CTA · Free delivery waived: Discounts line + the offer's own title under it

  - [ ] t.custMyBasket = "My Basket" — Title only.  `YdScreenHeader with NO onBack (it is a tab)`
  - [ ] Store strip (store.name + etaLabel) — Read-only; makes the one-store lock visible.  `brandSoft Container`
  - [ ] t.custSoloOrder = "Solo Order" / t.custSplitOrder = "Split Order" — Toggles split mode, which reveals the participants row, the per-line Assigned chips and the split summary. Drawn only when splitApi + profileApi + session are all present — all three ARE in the shipped build.  `GestureDetector halves inside a pill track, Semantics(selected:)`
  - [ ] t.custOrderParticipants = "Order Participants" — Host (t.you = "You", green check) then each added friend.  `Text heading over a horizontal ListView of StoreMonogram avatars`
  - [ ] t.custAddFriend = "Add Friend" — Mines recent co-splitters from splitApi.mine(), then opens showAddFriendSheet. Duplicate usernames are silently ignored on return.  `InkWell dashed brand circle with Semantics(label:)`
  - [ ] t.custAssignedTo(name) = "Assigned: {name}" — CYCLES through participants on each tap (no menu). With 3 people you must tap twice to reach the third — easy to mis-test.  `InkWell pill under each basket line`
  - [ ] t.custEvenBreakdown = "Even split breakdown" — Switches from itemized to even. Even mode floors each friend's share to the cent and the HOST absorbs the remainder — t.custHostAbsorbs(amount) = "Host absorbs {amount} remainder". Test with a total that does not divide evenly.  `YdChip (selected toggle)`
  - [ ] Per-person rows: name + t.custItemsCountLine(n) = "{n} items" + amount — Read-only. Under EVEN mode item counts are all zero by construction — check that reads acceptably.  `Text rows`
  - [ ] t.custTotalOrderAmount = "Total Order Amount" — Read-only.  `Text row`
  - [ ] **[destructive]** t.custSendPaymentRequests = "Send Payment Requests" — splitApi.create(mode EVEN|ITEMIZED) then pushes SplitStatusScreen. FINANCIAL — creates real payment obligations against other accounts. Failure shows t.somethingWentWrong.  `YdPillButton, disabled while _friends is empty`
  - [ ] Basket line (thumbnail, name, optionsSummary, unit $ + LBP) — Read-only body; the stepper is the control.  `white radius-16 Container row`
  - [ ] **[destructive]** QuantityStepper decrease — glyph is Icons.remove above 1 and Icons.delete_outline AT 1 — cart.remove(line.key). At quantity 1 this DELETES the line — the only way to empty the basket. Flag on a sweep: at 1 there is no confirmation.  `QuantityStepper(decreaseIcon:)`
  - [ ] QuantityStepper increase — cart.addConfigured of the same configuration — merges into the same line.  `QuantityStepper`
  - [ ] t.custPromoCode = "Promo Code" — 450ms-debounced quote against PromoApi; also re-quotes when the basket subtotal changes. Answers for a stale code are dropped.  `TextField (textCapitalization: characters) inside a bordered white row with Icons.sell_outlined`
  - [ ] t.custApply = "Apply" — Cancels the debounce and quotes immediately. Also the retry after a network failure.  `InkWell tinted box with Semantics(button:)`
  - [ ] Applied chip: "{code} · -{discount}" — Read-only confirmation.  `Row with Icons.check_circle_rounded`
  - [ ] t.custPromoRemove = "Remove the code" — Clears field, quote and signature.  `InkWell + Icons.close_rounded with Semantics(label:)`
  - [ ] Summary rows: t.subtotal = "Subtotal", t.delivery = "Delivery" (or t.free = "Free"), t.custDiscounts = "Discounts", the promo line, t.custTotalAmount = "Total Amount" — Read-only. Delivery shows what will be CHARGED (deliveryFeeCharged), not the shop's listed fee — check a waived-fee basket.  `Text.rich rows with the LBP conversion in faint`
  - [ ] t.custProceedToCheckout = "Proceed to Checkout" / t.minimumNotReached = "Minimum not reached" — Pushes CheckoutScreen carrying only a VALID promo quote. Disabled (not hidden) below the shop minimum, with t.minimumExplanationFull above it.  `YdPillButton`
  - [ ] Order-placed toast — t.orderPlacedToastShort = "Order #{ref} placed · {total}" plus t.deliveryTierExpressSurcharge = "Express +{amount}" when the server charged one; clears the promo and jumps to the Orders tab.  `SnackBar after checkout pops an order`

### Add-friend sheet (_AddFriendSheet)  — no driving test
*Find a real account by username, quick-add someone you split with before, or add a cash-at-the-door guest by name.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/split_add_friend_sheet.dart`
- reached by: Basket tab -> Split Order -> the dashed "Add Friend" circle.
- states: Searching: 20px centred spinner · <2 characters: results cleared, no guest row · Search failed: indistinguishable from 'no results' — the guest row appears either way · t.custRecentlySplitWith = "Recently split with" section absent when there is no history

  - [ ] t.custAddToOrder = "Add to Order" — Heading.  `Text title`
  - [ ] Close — Pops null.  `IconButton(Icons.close_rounded)`
  - [ ] t.custSearchByUsername = "Search by username..." — 350ms debounce; queries profileApi.search only at 2+ characters. A failed search silently shows nothing.  `TextField with Icons.search prefix`
  - [ ] t.add = "Add" (on a search result row) — Pops a SplitParticipant with the real username.  `YdPillButton (compact)`
  - [ ] t.custQuickAdd = "Quick Add" (on a recent row) — Same, from the recent-co-splitter list (max 4), mined from past plans.  `YdPillButton (compact)`
  - [ ] t.custAddAsGuest(typed) = "Add {name} as guest — pays cash at the door" — Pops a username-less participant. Only offered when 2+ chars are typed AND the search returned nothing AND it is not still searching — an easy state to miss.  `YdPillButton.secondary`

### SplitStatusScreen  — no driving test
*The host's collection screen: countdown, payment progress, per-share rows with Remind, Cover the Rest, and the way to checkout.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/split_status_screen.dart`
- reached by: Basket -> Split Order -> add at least one friend -> "Send Payment Requests".
- states: COLLECTING vs READY change which buttons appear · Any action failing: SnackBar t.somethingWentWrong · Poll failure is silent — the last good plan stays on screen

  - [ ] Back, t.custSplitOrder = "Split Order" — maybePop — leaves the plan open on the server.  `YdScreenHeader + YdBackButton`
  - [ ] t.custWaitingGroupPayments = "Waiting for group payments" / t.custReadyToPlace = "All shares are in — place the order" — Status line, amber vs green.  `Text`
  - [ ] t.custTimeRemaining = "Time remaining" + m:ss countdown — Read-only. Shows '--:--' with no expiresAt and '0:00' once expired — check what happens after it hits zero.  `dark Container, repainted by a 1s Timer`
  - [ ] t.custPaymentProgress = "Payment progress" / t.custNPaid = "{paid} / {total} Paid" / t.custCollectedOf = "{collected} of {total} collected" — Read-only, refreshed by a 5s poll.  `progress bar + Text`
  - [ ] Share row + status chip: t.custPaidChip = "Paid" / t.custPendingChip = "Pending" / t.custDeclinedChip = "Declined" / t.custCoveredChip = "Covered"; t.custPaidVia(method) = "Paid via {method}" — Read-only per participant.  `Row with a tinted chip`
  - [ ] t.custRemindBtn = "Remind" — splitApi.remind — sends a real notification to that person. Disabled while any action is in flight.  `TextButton on a share row`
  - [ ] **[destructive]** t.custCoverRest(amount) = "Cover the Rest ({amount})" — splitApi.cover — the host takes on every PENDING and DECLINED share. FINANCIAL: it moves other people's obligations onto the host with no confirmation dialog.  `YdPillButton.secondary`
  - [ ] t.custContinueToCheckout = "Continue to Checkout" — Pops this screen and invokes onReady, which is CartScreen._checkout — pushing CheckoutScreen with cart.splitPlanId set.  `YdPillButton`
  - [ ] **[destructive]** t.custCancelSplit = "Cancel Split Order" — splitApi.cancel — kills the plan for everyone, including shares already paid. No confirmation dialog.  `TextButton`

### CheckoutScreen
*Rate-lock banner, saved-address radio cards, delivery tier, Lebanese payment methods with the USD/LBP cash split, notes and phone, and the sticky Place Order bar.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/checkout_screen.dart`
- reached by: Basket tab -> "Proceed to Checkout"; or Basket -> Split Order -> Send Payment Requests -> SplitStatusScreen -> "Continue to Checkout".
- covered by: test/checkout_test.dart — DRIVES it hard with a fake Dio (address picked not typed, cash pre-selected, the all-USD split default, the placement payload carrying address+zone+CASH, the door-notes-follow-the-address rule, and the nothing-saved state). integration_test/order_lifecycle_test.dart places a real order through it. NOT covered: the tier cards, the wallet rows, the split card's typed half, the rate banner, the radius refusal.
- states: No address chosen: SnackBar t.addressRequired = "We need somewhere to deliver to" · Outside the shop's circle: SnackBar t.custOutsideDeliveryArea(store, km) — needs pins on BOTH the shop and the address, so test with a map-pinned address · 422: the server's own detail, else t.itemNoLongerAvailable · 402: the provider's detail, else t.custPaymentDeclined = "The payment was declined and your order was not placed." · 400: t.checkDeliveryDetails; anything else: t.couldNotPlaceOrder · transferApi silent: cash-only, no wallet rows, display rate — a state the shipped build should NOT reach · Split plan attached: SplitCompleteScreen is pushed before the pop

  - [ ] Back, t.checkout = "Checkout", Semantics t.back — maybePop, returning null.  `YdScreenHeader + YdBackButton`
  - [ ] t.custPlatformRate(rate) = "Platform Rate: $1 = {rate} LBP" / t.custRateLocked = "Locked rate — the lira total you approve is the lira total collected." — Read-only. Uses transferApi's LOCKED rate when it answered, else MarketRates' display rate. Absent entirely when the rate is <= 0.  `amber lock Container`
  - [ ] t.deliveryAddress = "Delivery address" — Heading.  `YdSectionHeader`
  - [ ] t.addANewAddress = "Add a new address" (+ Icons.add_rounded) — showAddressSheet WITH geocodingApi and zoneApi — so the place search and map ARE drawn on this entry (unlike Home's).  `InkWell text link with Semantics(button:) in the header's trailing slot`
  - [ ] Saved address radio card (label or line, then line · zoneName · notes) — Selects the address AND re-seeds the notes field from THAT address's door notes — anything typed is overwritten. Test: type a note, switch address, switch back.  `YdCard with a hand-drawn 20px radio ring + Semantics(selected:)`
  - [ ] t.chooseAnAddress = "Choose an address" — Opens the address sheet.  `YdCard with Icons.add_location_alt_outlined — only when nothing is saved`
  - [ ] t.custDeliverySpeed = "Delivery speed" — Heading.  `Text heading`
  - [ ] t.deliveryTierStandard = "Standard" — tier = STANDARD (the default, always sent explicitly).  `_payCard (Material+InkWell, Semantics(selected:))`
  - [ ] t.deliveryTierExpress = "Express" + caption t.custExpressSurchargeApplies = "Surcharge applies" — tier = EXPRESS. NO amount is shown here by design — no endpoint publishes it before the order exists. Selecting it adds the note t.custExpressNote below; the figure only appears on the order-placed toast and the receipt.  `_payCard`
  - [ ] t.custLocalPaymentMethods = "Local Payment Methods" — Heading.  `Text heading`
  - [ ] t.custCashUsdLbp = "Cash on Delivery (USD/LBP)" — payment = CASH, clears walletChoice, and REVEALS the split card. Selected by default.  `_methodRow (Material+InkWell + Icons.radio_button_checked, Semantics(selected:))`
  - [ ] t.custWhishTransfer = "Whish Money Transfer" — payment = WALLET with walletChoice WHISH. Runs against the DEV provider.  `_methodRow — only when transferApi.methods() contained 'WHISH'`
  - [ ] t.custOmtTransfer = "OMT (Online Money Transfer)" — payment = WALLET with walletChoice OMT.  `_methodRow — only when methods() contained 'OMT'`
  - [ ] t.custSplitPayment = "Lebanese Split Payment" / t.custSplitBlurb — Container for the two halves below.  `YdCard.bordered, cash only`
  - [ ] t.custPayInUsd = "Pay in Fresh USD" — Typed USD half, clamped to [0, total]. BLANK MEANS ALL USD — verify the default placement sends the whole total in USD.  `TextField (numberWithOptions decimal), prefix "$ ", hint = the full total`
  - [ ] t.custPayInLbp = "Pay in LBP (Lira)" — Computed at the locked rate and rounded to the nearest 1000 LBP. Two editable halves were deliberately avoided.  `READ-ONLY Container, not a field`
  - [ ] t.custPctUsd = "{pct}% USD" / t.custPctLbp = "{pct}% LBP" + progress bar — Read-only mirror of the split.  `Text + LinearProgressIndicator`
  - [ ] t.custRiderChange(amount) = "Rider carries change for up to {amount} LBP and cash USD." — Read-only.  `brandSoft note, only when rate.riderChangeLimitLbp > 0`
  - [ ] t.paymentTestModeNote = "Test payment — no real money moves in this build" — Read-only honesty note for the wallet rails.  `Row with Icons.science_outlined, only when payment.needsProvider`
  - [ ] t.custOrderNotes = "Order Notes" / hint t.custOrderNotesHint — Travels with the order. A diaspora gift note (cart.giftNote) would be prefixed with a gift emoji — but nothing in the shipped build can set giftNote (see DiasporaScreen).  `TextFormField minLines 2, maxLines 3`
  - [ ] t.contactPhoneOptional = "Contact phone (optional)" — Sent as contactPhone. Not drawn in the design; no validator.  `TextFormField(keyboardType: phone) inside the Form`
  - [ ] t.custTotalPrice = "Total Price" + amount — Advisory total (cached prices minus the promo quote). The server recomputes; the toast shows the SERVER's total.  `Text column in the sticky bar`
  - [ ] **[destructive]** t.custPlaceOrderAmount(amount) = "Place Order ({amount})" — FINANCIAL. Validates the form, checks the shop's delivery radius by haversine, places the order, records the transfer intent, closes any split plan, clears the basket and pops the order. Disabled while placing or when the basket is empty.  `YdPillButton(busy: _placing)`

### SplitCompleteScreen  — UNREACHABLE, no driving test
*The all-shares-paid ceremony: how each share travelled and the rider-collects note for the cash ones.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/split_complete_screen.dart`
- reached by: Checkout -> Place Order, when cart.splitPlanId is set and splitApi.attachOrder succeeds. Pushed OVER checkout just before it pops.
- **unreachable:** Reachable only through the full group-split flow (add a friend, send requests, have every share settle or be covered). Needs a second demo account to test end to end.
- states: Only reachable on a split basket; attachOrder failure skips it silently and the order still stands

  - [ ] t.custAllSharesPaid = "All Shares Paid!" — Read-only.  `Text over a green Icons.check circle`
  - [ ] t.custGroupSplitSummary = "Group Split Summary" + one row per share (name, t.custPaidVia(method), amount) — Read-only.  `Rows with Icons.check_rounded`
  - [ ] t.custRiderCollectNote(amount, name) = "Rider will collect {amount} from {name} at delivery" — Read-only.  `note row, cash shares only`
  - [ ] t.trackIt = "Track it" — Pops this screen; checkout then pops the order and the shell jumps to Orders.  `YdPillButton`

### Address sheet (_AddressSheet)
*Pick a saved address or make a new one: place search, an OSM map with a draggable pin, the typed line, the area dropdown, Home/Work/Other label chips and rider notes.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/address_sheet.dart`
- reached by: Home header address row (NO place search — geocodingApi is not passed); Checkout -> "Add a new address" or the empty card (WITH place search); Butler -> the Deliver to / Drop off at row; ProfileDrawer -> "My Addresses".
- covered by: test/arabic_rtl_test.dart — DRIVES it (opens the sheet, asserts RTL direction and that whereShouldWeBring / address / deliverHere are Arabic with no English left). integration_test/order_lifecycle_test.dart fills it in for real. test/delivery_address_test.dart drives the STORE (per-account scoping), not the sheet.
- states: Nothing saved: no Recent block, the address field autofocuses · No zones configured: no area dropdown and no area validator · Tiles dead: t.custMapUnavailable = "The map could not load. The address you type is what we will use." and the Set here / My location pills are WITHHELD · Reverse geocoding in flight: t.custNamingThisPlace = "Looking up this place…" · Search failed: t.couldNotSearchPlaces = "Could not search just now"; empty: t.noPlacesFound = "No places found" (only ever said about a query the server answered) · Keyboard open: the sheet lifts via viewInsets

  - [ ] t.whereShouldWeBring = "Where should we bring your order?" — Heading.  `Text title under a grab handle`
  - [ ] t.recent = "Recent" + saved rows — Tapping selects that address (which reorders the list) and closes.  `InkWell rows, max 5 (DeliveryAddressStore._maxRecents)`
  - [ ] **[destructive]** t.forgetThisAddress = "Forget this address" — store.forget — deletes the saved address from this device with no confirmation.  `IconButton(Icons.close_rounded) with tooltip`
  - [ ] t.searchForAPlace = "Search for a place…" — 400ms-debounced forward geocode; picking a candidate moves the camera and drops the pin.  `TextFormField, only when geocodingApi was passed`
  - [ ] Candidate row (place name, near-match presented as a guess) — _pickCandidate — moves the map, sets lat/lng, may fill an empty address line.  `InkWell`
  - [ ] t.custPinYourDoor = "Pin your door" + the crosshair — Drag / pinch / double-tap / scroll-wheel zoom to aim. The pin does not move; the map does.  `OsmBasemap (custom, defined in this file) with a fixed IgnorePointer Icons.place at the camera centre`
  - [ ] t.custSetHere = "Set here" — Commits the camera centre as lat/lng and reverse-geocodes it for a locality caption. Only drawn when tiles actually loaded.  `YdPillButton (compact) with Icons.place`
  - [ ] t.locMyLocation = "My location" — Device fix -> moves the camera. Failure paths are separate sentences worth testing individually: t.locServicesOff + action t.locTurnOn; t.locPermissionNeeded + action t.locOpenSettings; t.locNoFix.  `YdPillButton.secondary with Icons.my_location_rounded, busy while locating`
  - [ ] t.addressPinnedOnMap = "Pinned on the map" (· locality) — The X clears the pin. The pin is deliberately KEPT when the line is edited.  `chip with a close affordance`
  - [ ] t.address = "Address" / hint t.addressHint = "12 Test Street, Flat 4" — Validator: t.addressTooShort = "A bit more detail so the rider can find you" under 5 chars.  `TextFormField, autofocus when nothing is saved`
  - [ ] t.area = "Area" — Sets zoneId. Validator t.pickYourArea = "Pick your area so we know who can reach you" — REQUIRED once any zone exists. Zone name shows as "name · region".  `DropdownButtonFormField<String>, only when zones loaded`
  - [ ] t.custLabelAddressAs = "Label Address As:" / t.custLabelHome = "Home" / t.custLabelWork = "Work" / t.custLabelOther = "Other" — Home/Work write that word into the label. Only "Other" reveals the free-text label field (hint t.labelHint = "Home, Work").  `three YdChip-style chips`
  - [ ] t.riderNotesOptional = "Notes for the rider (optional)" / hint t.riderNotesHint = "Buzzer 4, second floor" — Stored on the address; checkout seeds its Order Notes from it.  `TextFormField`
  - [ ] t.deliverHere = "Deliver here" — Validates and store.select — saves, selects, promotes to the top of recents and notifies every listener (checkout follows it automatically).  `ElevatedButton, 52px`

### MyOrdersScreen (Orders tab)
*Active and past orders as cards, polled every 5 seconds, with cancel and reorder on the cards themselves.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/my_orders_screen.dart`
- reached by: Orders tab (nav index 3); ProfileDrawer -> "My Orders"; automatically after placing an order.
- covered by: integration_test/live_order_tracking_test.dart — DRIVES the poll specifically (each wait starts from the previous label still showing; nothing re-enters the tab or pulls to refresh). integration_test/cancel_order_test.dart drives both tabs and the cancel affordance appearing/disappearing. integration_test/order_lifecycle_test.dart uses it end to end.
- states: Loading with no orders yet: centred spinner · Error: YdEmptyState t.couldNotLoadOrders = "Could not load your orders." + t.pullDownToTryAgain + Try again · Empty tab: YdEmptyState t.noOrdersYet = "No orders yet" + t.browseAndPlaceFirst · 5s silent poll: a status change made by a merchant or rider must appear WITHOUT any interaction

  - [ ] t.custYourOrders = "Your Orders" — Title.  `YdScreenHeader (no back)`
  - [ ] t.custActiveOrdersTab(n) = "Active Orders ({n})" — Shows non-terminal orders.  `InkWell tab with a 2px brand underline, Semantics(selected:)`
  - [ ] t.custPastOrdersTab = "Past Orders" — Shows terminal orders (delivered / cancelled).  `InkWell tab`
  - [ ] Order card (storeName, time stamp, status pill, t.custItemsCountLine, total + LBP) — Pushes OrderDetailsScreen with the row as preview, then refreshes on return. Time stamp is "8:45 PM" today, t.custYesterdayAt = "Yesterday, {time}", then short dates.  `YdCard with onTap`
  - [ ] Status pill (order.status.labelIn) — Read-only. This is the label the 5s poll must update without you touching the screen.  `CustomerStatusPill (order_details_screen.dart) — colour from the shared OrderStatusBadge.colorFor`
  - [ ] t.custReorder = "Reorder" — Pushes StorePageScreen for that shop — it does NOT rebuild the basket. (The basket-rebuilding Reorder lives on OrderDetailsScreen; two different behaviours behind the same word.)  `YdPillButton (compact), past-order cards only`
  - [ ] **[destructive]** t.cancel = "Cancel" — Opens the cancel dialog. DESTRUCTIVE — cancels a real order.  `YdPillButton.secondary (compact), only when availableActions contains cancel`
  - [ ] t.riderAtShort(lat, lng) = "Rider at {lat}, {lng}" — Read-only; only fetched for orders in PICKED_UP.  `brandSoft strip with Icons.two_wheeler`
  - [ ] Pull-to-refresh — Refetches 30 orders.  `RefreshIndicator(onRefresh: _refresh)`
  - [ ] t.tryAgain = "Try again" — Re-runs _refresh.  `YdPillButton in the error state`

### Cancel-this-order dialog
*Confirms a cancellation that cannot be undone.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/my_orders_screen.dart (_cancel, ~line 119)`
- reached by: Orders -> Active -> a card whose order is still PLACED -> "Cancel".
- covered by: integration_test/cancel_order_test.dart — DRIVES both sides of the window: cancels one order through the dialog and confirms against the ledger, then has a merchant accept a second order and asserts the app STOPS offering the button.
- states: 422 (merchant already accepted): SnackBar t.tooLateToCancel = "Too late — the merchant has already started this order." then a silent refresh · Any other failure: t.couldNotCancelOrder

  - [ ] t.cancelThisOrder = "Cancel this order?" / t.cancelBeforeAccepted = "You can only cancel before the merchant accepts it. This cannot be undone." — States the window.  `AlertDialog title + content`
  - [ ] t.keepIt = "Keep it" — Pops false.  `TextButton`
  - [ ] **[destructive]** t.cancelOrder = "Cancel order" — orderApi.act(cancel, reason: 'Cancelled by customer' — deliberately untranslated, it is an audit string). DESTRUCTIVE and irreversible.  `ElevatedButton`

### OrderDetailsScreen
*One order in full: status stepper, live tracking panel, rating card, items, shop card, receipt and Reorder.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/order_details_screen.dart`
- reached by: Orders tab -> tap any order card; OR Butler tab -> Recent tasks -> tap a task that has an orderId (i.e. an approved errand).
- covered by: integration_test/order_lifecycle_test.dart reaches it through the list. No test drives Reorder, the rating card, or the delivery-charge tooltip.
- states: Loading with no preview: centred spinner · Load failed: YdEmptyState t.couldNotLoadOrder = "Could not load this order" + Try again · Cancelled order: no stepper, no tracking panel · Reorder with nothing still sold: SnackBar t.nothingStillAvailable · Reorder success: t.addedToBasket(n) or t.addedSomeMissing(added, missing) · Reorder failure: t.couldNotReorder · Rating state unknown (server silent): NO rating card is drawn at all

  - [ ] Back, t.custOrderStatus = "Order Status" — maybePop; the orders list refreshes on return.  `YdScreenHeader + YdBackButton`
  - [ ] "{t.custOrderRef} #{shortId}" = "Order #XXXXXXXX" + storeName + status pill — Read-only.  `Text + CustomerStatusPill`
  - [ ] Five-step stepper: t.stepPlaced "Placed", t.stepAccepted "Accepted", t.stepPreparing "Preparing", t.stepOnTheWay "On the way", t.stepDelivered "Delivered" — Read-only. The wire's READY state has NO node — it folds into Preparing shown as DONE. Not drawn at all for a cancelled order.  `hand-built circles + labels`
  - [ ] t.custRateYourRider = "Rate your rider" / t.custHowWasDelivery = "How was your delivery?" — Opens showRateRiderSheet. Drawn ONLY after the server answered whether a rating exists, and only for DELIVERED orders with a riderId.  `YdCard with onTap`
  - [ ] t.custAlreadyRatedDelivery = "You rated this delivery" + 5 stars — Read-only replacement once rated.  `YdCard with Semantics label t.ratingStars(score)`
  - [ ] t.custItemsOrdered = "Items Ordered" + rows t.lineQuantity(qty, name) = "{qty} × {name}" — Read-only. Thumbnails come from re-reading the live catalogue; delisted items render with a StoreMonogram.  `white radius-12 rows with a catalogue thumbnail`
  - [ ] Shop card (name, address) + circle chevron, Semantics t.openStore(name) = "Open {store}" — Pushes StorePageScreen. There is deliberately NO call-the-merchant control.  `YdCard + a 36px brandSoft Material/InkWell circle`
  - [ ] Receipt: timestamp line (t.deliveredOn / t.placedOn), t.subtotal, t.deliveryCharge = "Delivery Charge", promo line, t.total = "Total" — Read-only.  `YdCard with money rows`
  - [ ] Delivery-charge info glyph — TAP, not hover — shows t.deliveryWasFree(amount) = "Normally {amount} — we covered it" or t.setByStoreCharged(store). Easy to miss on a sweep.  `Tooltip(triggerMode: TooltipTriggerMode.TAP) on Icons.info_outline_rounded`
  - [ ] Payment row: method label (+ " · " + t.custTestPayment = "Test payment" for non-cash) and paymentStatus.labelIn — Read-only.  `Row with Icons.payments_outlined`
  - [ ] t.reorder = "Reorder" — Re-reads every line from the LIVE catalogue and refills the basket. Disabled while working or when the order has no storeId. Different from the Orders-list Reorder, which only opens the shop.  `YdPillButton(icon: Icons.refresh_rounded, busy: _reordering)`
  - [ ] Pull-to-refresh — Re-reads the order, shop, thumbnails and rating.  `RefreshIndicator(onRefresh: _load)`
  - [ ] t.tryAgain = "Try again" — Re-runs _load.  `YdPillButton in the error state`

### Replace-your-basket dialog  — no driving test
*Guards the one-store rule on the reorder path.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/order_details_screen.dart (_confirmReplaceBasket, ~line 231)`
- reached by: Order details -> "Reorder" while the basket already holds items from a DIFFERENT shop.
- states: Not shown when the basket is empty or already belongs to the same shop

  - [ ] t.replaceYourBasket = "Replace your basket?" / t.basketFromShopReplace(shop) + t.reorderWillReplace = "Reordering will start a new one." — States what is about to be lost.  `AlertDialog`
  - [ ] t.keepIt = "Keep it" — Pops false, reorder abandoned.  `TextButton`
  - [ ] **[destructive]** t.replace = "Replace" — Discards the whole existing basket and rebuilds it from the order. DESTRUCTIVE.  `FilledButton (brand)`

### OrderTrackingPanel (embedded, not a route)
*A real OpenStreetMap canvas with the rider's trail, live pushed positions over STOMP, ETA, and the road into the rider chat.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/order_tracking_panel.dart`
- reached by: OrderDetailsScreen for any order that is not DELIVERED or CANCELLED — it sits between the status card and the items.
- covered by: integration_test/live_order_tracking_test.dart references its terminal-state behaviour but drives MyOrdersScreen, not this panel. Nothing drives the map, the chat entry, or the pushed-fix glide.
- states: Terminal order: build() returns SizedBox.shrink() — the whole panel vanishes · Socket connected: 30s safety poll; socket down: 5s poll — the panel must keep working either way · No fixes yet: the styled surface + t.waitingForRider (after pickup) or t.locationAfterPickup (before) · Tiles dead: the palette-neutral styled surface instead of a grey lattice · ETA endpoint unreachable: the previous answer stays on screen

  - [ ] Map canvas (520px) — drag / pinchZoom / pinchMove / doubleTapZoom / scrollWheelZoom. Once you pan or zoom, the camera is YOURS — the 5s refit must stop. That is the specific thing to test.  `OsmBasemap (imported from address_sheet.dart) + MapController`
  - [ ] Rider marker, Semantics t.custTheRider = "The rider" — Glides 800ms between fixes rather than teleporting.  `Icons.two_wheeler in a brand disc`
  - [ ] Destination marker, Semantics t.custYourAddress = "Your address" — Drawn ONLY when the order's address line matches a saved address in THIS device's book that carries a pin. No match = no pin, by design.  `Icons.place 30px`
  - [ ] t.custLiveMap = "Live map" — Read-only badge.  `IgnorePointer chip, top-start`
  - [ ] Distance/ETA chip: t.distanceKm = "{km} km" / t.distanceM = "{m} m" · "{n} {t.etaMinShort}" — Read-only; from the tracking service, never invented.  `IgnorePointer white chip`
  - [ ] Progress steps: t.custTrackConfirmed "Confirmed", t.custTrackPreparing "Preparing", t.custTrackOnTheWay "On the Way", t.custTrackDelivered "Delivered" — Read-only.  `Row`
  - [ ] Sheet headline + t.etaArriving = "Expected arrival" + time, and t.etaStraightLineNote = "Rough estimate — measured in a straight line, not by road" — Read-only. Falls back to the status label, then to a reason sentence, then to t.waitingForRider / t.locationAfterPickup.  `Text block under a grab handle`
  - [ ] Stats: t.fixes = "Fixes", t.travelled = "Travelled", t.lastSeen = "Last seen" — Read-only.  `Text columns`
  - [ ] t.custChatWithRider = "Message the rider" — Pushes CustomerChatScreen. Drawn ONLY when chatApi is present AND order.riderId is non-null — before a rider is assigned there is no button at all (not a disabled one). There is deliberately NO call button.  `InkWell row with a 40px brandSoft chat disc, Semantics(button:)`

### CustomerChatScreen  — no driving test
*The customer's side of the order conversation, polled every 4s with an afterSequence cursor.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/customer_chat_screen.dart`
- reached by: Orders -> an in-flight order -> OrderDetailsScreen -> tracking panel -> "Message the rider". Requires a rider to already be assigned.
- states: Loading: spinner · No conversation / 404 / network failure: YdEmptyState t.couldNotLoadChat = "Could not load the conversation" + t.tryAgain (the poll keeps re-attempting the load on its own) · Empty thread: YdEmptyState t.chatNoMessagesYet = "No messages yet" · 409 on send: SnackBar t.chatClosed = "This conversation is closed" · Other send failure: SnackBar t.chatCouldNotSend · Closed conversation: a locked bar (Icons.lock_outline_rounded + t.chatClosed) replaces the composer

  - [ ] Back, t.custChatWithRider = "Message the rider" — maybePop.  `YdScreenHeader + YdBackButton`
  - [ ] Message bubbles with a delivery tick (Icons.done_rounded / Icons.done_all_rounded) — Read-only; read receipts are sent fire-and-forget as messages arrive.  `bubble Containers`
  - [ ] t.chatTypeMessage = "Type a message…" — Composes. Empty text is refused.  `TextField in the composer bar`
  - [ ] Send, Semantics label t.chatSend = "Send" — Posts with a per-attempt idempotency key that is REUSED on retry — a retry of the same text must not double-post. Test by killing the network mid-send and retrying.  `InkWell + Icons.send_rounded (spinner while sending)`

### Rate-rider sheet (_RateRiderSheet)  — no driving test
*Five stars plus an optional sentence, once per order.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/rate_rider_sheet.dart`
- reached by: Orders -> Past Orders -> a DELIVERED order that had a rider -> OrderDetailsScreen -> the "Rate your rider" card. One time only.
- states: Stars == 0: submit disabled · 409 (already rated from another device): shows t.custAlreadyRatedDelivery in the sheet as a statement, not an error · Other failure: t.custCouldNotSendRating = "Could not send your rating" · Keyboard: the sheet lifts via viewInsets

  - [ ] Stars 1-5, each Semantics label t.ratingStars(n) = "{n} stars", Semantics(selected:) — Sets the score. Starts at 0 with the submit button disabled — a rating of nothing is not a rating.  `InkWell + Icons.star_rounded / star_outline_rounded, 36px`
  - [ ] t.custAddCommentOptional = "Add a comment (optional)" — Optional free text; blank is sent as null.  `TextField minLines 2 maxLines 4`
  - [ ] t.custSubmitRating = "Submit rating" — orderApi.rateRider then pops the entry; the details screen shows t.custThanksForRating = "Thanks for rating your rider".  `YdPillButton(busy: _sending)`

### ButlerScreen (Butler tab)
*Request an errand — Buy Anything or Send Anything — over a free-text form, with the errand history and quote approvals below it.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/butler_screen.dart`
- reached by: Butler tab (nav index 1).
- covered by: test/arabic_rtl_test.dart — DRIVES it (mounts ButlerScreen in Arabic, asserts the buy-mode labels, TAPS the Send Anything card, then asserts the send-mode labels; also asserts no English is left). Nothing drives an actual submission.
- states: No address set: SnackBar t.setAddressFirst = "Set a delivery address first" · 403: t.cannotRequestErrands = "This account cannot request errands" · Server detail wins over any client sentence on failure; fallback t.couldNotSendRequest · Success: fields cleared, list version bumped, SnackBar t.sentBuyConfirmation or t.sentMoveConfirmation · Terms endpoint down: the fee reads "—" and the button still works

  - [ ] t.custButlerTitle = "YouDrop Butler" — Title.  `centred Text (the frame's back chip slot is deliberately empty — it is a root tab)`
  - [ ] t.custSearchTasksHint = "Search your errands" — Filters the history list BELOW in memory — there is no task-search endpoint. Matches what / sourceHint / pickupAddress.  `YdSearchField`
  - [ ] t.custButlerBanner = "We buy or deliver anything!" + t.custButlerBannerBlurb — Read-only.  `brandSoft Container`
  - [ ] t.custBuyAnything = "Buy Anything" / t.custBuyAnythingBlurb = "We buy & deliver from anywhere" — mode = buy. Switching modes RESETS the Form's validation state — check that errors from the other mode do not persist.  `Material+InkWell card, Semantics(selected:)`
  - [ ] t.custSendAnything = "Send Anything" / t.custSendAnythingBlurb = "Courier, pick up, or send items" — mode = send — a different set of fields entirely.  `Material+InkWell card`
  - [ ] BUY: t.whatDoYouNeed = "What do you need?", hint t.buyHint — Validator t.buyValidator under 8 chars.  `TextFormField, maxLines 3, prefix Icons.edit_note_outlined`
  - [ ] BUY: t.whereFromOptional = "Where from? (optional)", hint t.whereFromHint — sourceHint. No validator.  `TextFormField`
  - [ ] BUY: t.budgetCapOptional = "Budget cap (optional)", hint "30.00" — Validator t.budgetValidator = "A number, or leave it blank" when non-empty and unparseable.  `TextFormField(numberWithOptions decimal)`
  - [ ] SEND: t.whatAreWeMoving = "What are we moving?", hint t.moveHint — Validator t.moveValidator under 8 chars.  `TextFormField, maxLines 3`
  - [ ] SEND: t.pickUpFrom = "Pick up from", hint t.pickUpHint — REQUIRED — validator t.pickUpValidator under 6 chars. (Contrast with buy's optional 'where from'.)  `TextFormField, maxLines 2`
  - [ ] SEND: t.whoReceivesItOptional = "Who receives it? (optional)", hint t.receiverHint — recipient.  `TextFormField`
  - [ ] t.deliverTo = "Deliver to" (buy) / t.dropOffAt = "Drop off at" (send) + addresses.headerLabelOr(t.setDeliveryAddress) — showAddressSheet(zoneApi:) — no place search on this entry either.  `Material+InkWell row with Icons.location_on_outlined`
  - [ ] **[destructive]** t.requestAButler = "Request a Butler" / t.requestAPickup = "Request a pickup" — Validates, requires an address, then requestPurchase or requestPickup. Creates a real, chargeable errand.  `YdPillButton(busy: _submitting)`
  - [ ] t.errandFeeBuy(fee) / t.errandFeeMove(fee) — Read-only — the fee is fetched from the server, never assumed.  `FutureBuilder<ButlerTerms> Text, shows "—" until terms land`

### ButlerRequestsList (embedded in the Butler tab)
*The only place a shopper's quote can be approved or declined, plus the recent-tasks history. Polls every 5s.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/butler_requests_list.dart`
- reached by: Butler tab — it renders under the form. Requires the account to have at least one errand.
- covered by: test/butler_live_refresh_test.dart drives the same poll/no-blink/keep-last-good-page behaviour but on RiderButlerBoard, the RIDER's equivalent — the customer's list has no test of its own.
- states: Status words: t.custStatusPending "Pending", t.butlerStatusClaimed "Claimed", t.butlerStatusYourCall "Your call", t.butlerStatusAgreed "Agreed", t.declined, t.cancelled, t.butlerStatusExpired "Expired" · No errands and no query: renders NOTHING (the form above is the whole answer) · Search matched nothing: t.custNoTasksMatch = "No errands match that search" · Load error: t.couldNotLoadErrands · 5s poll must NOT blink the list back to a spinner (initialData keeps the last page) and must NOT fire while an approve/decline is in flight · Failure message prefers the server's own `detail`, else t.thatDidNotWork

  - [ ] t.custWaitingOnYou = "Waiting on you" quote card (what, price line, t.aboveYourCap when over budget) — Lifted out of history into its own card — a quote buried in a list is a quote nobody answers.  `brandSoft Container with a brand hairline`
  - [ ] **[destructive]** t.noThanks = "No thanks" — butlerApi.decline. DESTRUCTIVE — refuses goods a shopper has already bought with their own money. Confirmation is SnackBar t.declined = "Declined".  `YdPillButton.secondary (compact)`
  - [ ] **[destructive]** t.payAmount(total) = "Pay {amount}" — butlerApi.approve — FINANCIAL, commits the customer to the goods price plus the errand fee, with no confirmation dialog. SnackBar t.approvedOnItsWay.  `YdPillButton (compact)`
  - [ ] t.custRecentTasks = "Recent tasks" — History card, capped at 4 rows.  `YdCard.bordered with YdSectionHeader`
  - [ ] t.custSeeAll = "See All" / t.custShowLess = "Show Less" — Expands/collapses in place — there is no separate task screen to route to.  `YdSectionHeader.onAction`
  - [ ] Task row (what + status line + status word) — Opens OrderDetailsScreen — but ONLY when r.orderId is non-null (i.e. the errand was approved). Rows without an order are silently un-tappable.  `InkWell`
  - [ ] **[destructive]** t.cancel = "Cancel" (small brand text under the status word) — butlerApi.cancel. Only offered while status is requested or claimed. DESTRUCTIVE. SnackBar t.cancelled.  `InkWell`

### RewardsScreen (Account tab)  — no driving test
*Points balance, tier ladder, reward categories and recent points activity. Read-only end to end.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/rewards_screen.dart`
- reached by: Account tab (nav index 4). This is what the Account tab renders in the shipped build, because main.dart always passes pointsApi.
- states: Loading: centred spinner · Error with no balance: YdEmptyState t.somethingWentWrong + t.couldNotReachTheServer + Try again · Empty history: YdCard with t.custNoActivityYet = "No points yet — they arrive with your first delivered order." · No loyalty standing: the tier card collapses to SizedBox.shrink() · There is NO sign-out and NO account management on this tab — that lives only in the drawer

  - [ ] t.custRewardsTitle = "Rewards & Points" — Title.  `YdScreenHeader (no back)`
  - [ ] t.custTotalPoints = "Total points" + balance; t.custPtsThisMonth(n) = "+{n} pts this month" — Read-only. The month chip is computed client-side from the history window (20 entries) — a heavy month could under-count.  `brand-gradient Container`
  - [ ] t.custNextTierLabel(tier) = "Next tier: {tier}" / t.custPtsToGo(n) = "{n} pts to go" + progress bar — Read-only.  `LinearProgressIndicator`
  - [ ] t.custCurrentTierHeading = "Current tier" / t.custCurrentTierLine(tier) = "Current Tier: {tier}" / t.custTierEarnedLine(points, orders) — Read-only. Tier names: t.tierBronze/Silver/Gold/Platinum.  `YdCard.bordered + YdBadge.brand`
  - [ ] t.custNextTierLine(tier) = "Next Tier: {tier}" / t.custNextTierBlurb(points) / t.custTopTier = "You are at the top tier." — Read-only.  `row in the tier card`
  - [ ] t.custFreeDelivery = "Free Delivery" / t.custVouchersAvailable = "Vouchers available" — value hard-coded "0" — NOT WIRED. There is no voucher engine; the zero is deliberate rather than a bug, but it is also permanently zero.  `YdCard.bordered row`
  - [ ] t.custCashback = "Cashback" / t.custEarnedLabel = "Earned" (currency) — Read-only. This is what the spendable balance is WORTH at today's rate — it is not money that can be paid out.  `YdCard.bordered row`
  - [ ] t.custReferralBonus = "Referral Bonus" — value hard-coded "$0.00" — NOT WIRED. No referral engine exists.  `YdCard.bordered row`
  - [ ] t.custRecentActivity = "Recent activity" + rows t.custPointsOrderEntry(pts, shortId) = "{pts} pts · Order #{id}" or t.custPointsEntry(pts) — Read-only.  `YdCard.bordered, max 8 rows shown of 20 fetched`
  - [ ] Pull-to-refresh — Re-reads balance + history.  `RefreshIndicator(onRefresh: _load)`
  - [ ] t.tryAgain = "Try again" — Re-runs _load.  `YdPillButton.secondary in the error state`

### ProfileDrawer
*The customer's entire account and settings surface, absorbed from the old Account tab. This is the ONLY way out of the app.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/profile_drawer.dart`
- reached by: Home tab -> tap the header avatar (Semantics "Account Settings"). It lives on the SHELL scaffold, so an edge-drag from any tab also opens it. Note the avatar only works from the Home tab — a tap on an unpainted IndexedStack child is silently swallowed.
- covered by: integration_test/support/journey.dart signOutCustomer() — DRIVES it (taps the Home tab, taps the avatar by its Semantics label, waits for ProfileDrawer, taps the Log Out YdPillButton, asserts the app returns to the gate with no 'Continue as' card). Used by order_lifecycle_test.dart. Nothing drives the avatar upload, the language toggle here, or the biometric switch.
- states: Biometric prompt refused: SnackBar t.couldNotVerifyYou; no enrolment: t.fingerprintNotSetUp · Avatar upload success: SnackBar t.pictureUpdated = "Picture updated"; failure: t.somethingWentWrong; picker throws: t.couldNotOpenPicker(reason) · Avatar fetch failure: the monogram stands, silently · profileApi null would hide the camera badge and the Edit link — not reachable in the shipped build

  - [ ] Avatar + camera badge — Decoration; the edit affordance below is the control.  `Stack over StoreMonogram / ClipOval Image`
  - [ ] t.custEditProfile = "Edit Profile" — Opens the OS file picker (file_selector) and uploads the picked jpg/jpeg/png/webp as the account avatar. NO crop, NO size limit, NO preview — worth pressing with a very large image.  `InkWell text link with Icons.edit_outlined, Semantics(button:)`
  - [ ] t.custMyAccount = "My account" — Heading.  `section label`
  - [ ] t.custMyOrders = "My Orders" — Closes the drawer and jumps to the Orders tab.  `YdListRow`
  - [ ] t.custMyAddresses = "My Addresses" — Closes the drawer then opens the address sheet against the NavigatorState captured before the pop.  `YdListRow`
  - [ ] t.custPaymentMethods = "Payment Methods", value "Cash · Card · Wallet", subtitle t.paymentTestModeNote — INFORMATIONAL ONLY — no onTap. There is no payment-method management screen anywhere in the app.  `YdListRow with trailing: SizedBox.shrink()`
  - [ ] t.custVouchersPromos = "Vouchers & Promos" wrapped in t.authComingSoon = "Soon" — Deliberately inert. Flag: this is a drawn-but-dead row by design.  `YdComingSoon.wrap(YdListRow) with trailing: SizedBox.shrink()`
  - [ ] t.custPreferences = "Preferences" — Heading.  `section label`
  - [ ] t.custAppLanguage = "App Language" with EN / AR segments — locale.setLanguage — rebuilds the WHOLE app in the other direction. The active segment's onTap is null. This is one of only two places in the mobile app that can change the language.  `AppLanguageRow (settings_screen.dart) — a segmented toggle, each segment a Material+InkWell with Semantics(selected:)`
  - [ ] t.notifications = "Notifications" (value = unread count when > 0) — Closes the drawer and pushes NotificationsScreen (the inbox). NOT the preferences grid — see the finding on NotificationPrefsScreen.  `YdListRow`
  - [ ] t.biometricUnlock = "Fingerprint unlock" / t.useFingerprintNextTime — Turning ON prompts the system biometric FIRST and only enables on success. Turning OFF means the next sign-out revokes the refresh token rather than stashing it — it changes what sign-out does. Row is absent entirely on hardware with no biometrics.  `Switch inside a YdListRow (spinner while working)`
  - [ ] t.custSupport = "Support" — Heading.  `section label`
  - [ ] t.custHelpSupport = "Help & Support" — Closes the drawer and pushes HelpSupportScreen.  `YdListRow`
  - [ ] **[destructive]** t.custLogOutAccount = "Log Out Account" — Pops the drawer then signs out immediately — NO CONFIRMATION DIALOG on the customer surface (the merchant surface does ask). The only way out of the app.  `YdPillButton(icon: Icons.logout_rounded) pinned under the list`

### NotificationsScreen (in-app inbox)
*The IN_APP channel of the notification log, with per-message and mark-all read.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/notifications_screen.dart`
- reached by: Home header bell; OR ProfileDrawer -> "Notifications".
- covered by: test/notification_inbox_test.dart — DRIVES the NotificationInbox model thoroughly (refresh, derived unread count, optimistic markRead, rollback on failure, no double-decrement, markAllRead, silent poll failure). The SCREEN itself has no test.
- states: Loading with no messages: centred spinner · Error with no messages: YdEmptyState t.couldNotLoadNotifications + t.pullDownToTryAgain · Empty: YdEmptyState t.nothingYet = "Nothing yet" + t.orderUpdatesHere · Unread row: brandSoft tile, bold title, an 8px brand dot · Time labels: t.justNow / t.minutesAgo / t.hoursAgo / t.daysAgo · Badge on the Home bell is polled every 15s independently of this screen

  - [ ] Back, t.notifications = "Notifications" — maybePop.  `YdScreenHeader + YdBackButton`
  - [ ] t.markAllRead = "Mark all read" — inbox.markAllRead. Failure is silent and reconciled on the next refresh.  `Tooltip + Material/InkWell circle with Icons.done_all_rounded, Semantics(label:) — rendered ONLY when unread > 0`
  - [ ] Message row (icon tile from eventType, title, body, relative time, unread dot) — markRead — OPTIMISTIC: the badge drops before the server answers and rolls back on failure. Tapping does NOT navigate anywhere, even for order events.  `YdCard with onTap`
  - [ ] Pull-to-refresh — Full reload. Works over the empty and error states too — that is what the _scrollable wrapper is for.  `RefreshIndicator(onRefresh: inbox.refresh) with AlwaysScrollableScrollPhysics`

### HelpSupportScreen  — no driving test
*Support channels plus a 14-question FAQ that describes what this build actually does.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/help_support_screen.dart`
- reached by: ProfileDrawer -> "Help & Support".
- states: Neither channel configured: SoftNote t.custHelpNoChannelsYet = "No support channel is set up in this build yet..." and no 'Talk to us' rows · Nothing on the phone can open the link: SnackBar t.custCouldNotOpenThat = "Nothing on this phone could open that." — test on an emulator with no WhatsApp and no mail client

  - [ ] Back, t.custHelpSupport = "Help & Support" — maybePop.  `YdScreenHeader + YdBackButton`
  - [ ] t.custChatOnWhatsApp = "Chat on WhatsApp" — launchUrl to wa.me. Drawn only when the SUPPORT_WHATSAPP dart-define is set at build time — with the default empty define this row DOES NOT EXIST. Check your build's defines before reporting it missing.  `YdListRow`
  - [ ] t.custEmailSupport = "Email support" — launchUrl mailto:. Same rule with SUPPORT_EMAIL.  `YdListRow`
  - [ ] 14 FAQ rows across t.custHelpOrdering / Delivery / Payments / Account / Applying — Each expands in place to reveal its answer. Independent — several can be open at once.  `_Faq — a YdCard with onTap and Semantics(expanded:), hand-built rather than ExpansionTile`

### FriendSplitScreen (pay your share)  — UNREACHABLE, no driving test
*The guest side of a group split: see the host's invitation, your share in USD and LBP, pick a method, pay or decline.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/friend_split_screen.dart`
- reached by: Home tab -> the split-invitation banner under the search bar. That banner appears only when splitApi.requests() returns something addressed to this account.
- **unreachable:** Not reachable at all without a SECOND account creating a split plan that names this one. There is no self-serve entry: the banner is the only door and it is data-driven.
- states: No PENDING share for this username: YdEmptyState t.custAllSharesPaid · No wallet methods returned: only Cash at Door is offered

  - [ ] Back, t.custPayYourShare = "Pay your share" — maybePop.  `YdScreenHeader + YdBackButton`
  - [ ] t.custInvitedYouToSplit(host) = "{name} invited you to split" + storeName — Read-only.  `Text block`
  - [ ] t.custYourShareToPay = "Your share to pay" + amount + LBP at plan.rateUsed; t.custPlatformRate(rate) — Read-only.  `Text block`
  - [ ] t.custSelectPaymentMethod = "Select Payment Method" — Heading.  `Text heading`
  - [ ] t.custWhishShort = "Whish Money" (+ t.custRecommendedChip = "Recommended") — method = WHISH.  `_methodRow, Material+InkWell with a radio glyph, Semantics(selected:) — only when transferApi.methods() contained WHISH`
  - [ ] t.custOmtShort = "OMT" — method = OMT.  `_methodRow — only when methods() contained OMT`
  - [ ] t.custBobShort = "BOB Finance" — method = BOB. NOTE: BOB is offered HERE but not on CheckoutScreen, which only draws WHISH and OMT — an inconsistency worth confirming.  `_methodRow — only when methods() contained BOB`
  - [ ] t.custCashAtDoor = "Cash at Door" / t.custRiderCollectsFromYou = "Rider will collect from you" — method = CASH_AT_DOOR.  `_methodRow — always drawn`
  - [ ] **[destructive]** t.custPayMyShare(amount) = "Pay My Share ({amount})" — splitApi.answer(accept). FINANCIAL — commits this person to the amount.  `YdPillButton(busy:)`
  - [ ] **[destructive]** t.custDeclineInvitation = "Decline invitation" — splitApi.answer(decline). Pushes the amount back onto the host's Cover-the-Rest. No confirmation.  `TextButton`

### AccountScreen  — UNREACHABLE, no driving test
*The pre-redesign merged account page: profile block with an Edit sheet, language row, addresses, payment methods, order history, notifications inbox, the notification-preferences row, biometrics, help, and a tinted Log Out. Superseded by RewardsScreen + ProfileDrawer.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/account_screen.dart`
- reached by: Nothing in the shipped build. customer_shell.dart:209-211 renders RewardsScreen whenever pointsApi != null, and main.dart:455 always passes it.
- **unreachable:** Dead in the shipped build (pointsApi is always non-null). Two real capabilities die with it: CHANGE PASSCODE (there is no other in-app entry for a signed-in customer) and NOTIFICATION PREFERENCES. Report both as functionality gaps, not as untested screens.
- states: N/A — never mounted; integration_test/support/journey.dart:210 documents this explicitly ('a scenario that goes looking for a Log Out button on the Account tab is looking for a widget the real app never builds')

  - [ ] t.edit = "Edit" — The sheet offers t.authChangeYourPasscode with the account email locked, pushing ForgotPasswordScreen(emailFixed: true, signedIn: true) — the ONLY in-app passcode change. Unreachable.  `InkWell + YdBadge.brand -> a modal bottom sheet`
  - [ ] t.notifPreferences = "Notification preferences" — Pushes NotificationPrefsScreen. This is the only customer-side road to the preference grid, and it is unreachable.  `YdListRow with Icons.tune`
  - [ ] **[destructive]** t.signOut = "Sign out" — The only customer sign-out with a confirmation dialog behind it. Unreachable.  `critical-tinted Material+InkWell`

### NotificationPrefsScreen  — UNREACHABLE, no driving test
*The per-category / per-channel notification matrix, saved cell by cell.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/notifications_screen.dart (line 216)`
- reached by: For a customer: nothing. Its only customer-side caller is AccountScreen:543, which is itself unreachable. The merchant shell (merchant_shell.dart:292) and SettingsScreen:146 reach it, so it is live for merchant and rider — just not for customers.
- **unreachable:** Unreachable from the CustomerShell. The customer's only notification control is the inbox; the prefsApi IS threaded all the way through CustomerShell -> StoreHomeScreen and then goes nowhere, because the redesign moved settings into ProfileDrawer and the drawer has no preferences row. This is a wiring gap, not a missing screen.
- states: Loading: spinner · Load failed: YdEmptyState t.couldNotLoadPreferences + Try again · All cells locked in a category: t.notifAlwaysOn note under the title · Save failed: SnackBar t.couldNotSaveThatChange, switch never moves

  - [ ] Per-channel Switch (custNotifChannelLabel) — Saves only itself and re-renders from the grid the server sends back. Locked (account-critical) cells render DISABLED rather than snapping back.  `Switch inside a YdCard per category, replaced by a 16px spinner while that one cell saves`
  - [ ] t.tryAgain = "Try again" — Reloads the grid.  `YdPillButton in the error state`

### SettingsScreen  — UNREACHABLE
*The rider/merchant equivalent of the customer's drawer: language row, biometric switch, the notification-preferences row, and the informational payment rows.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/settings_screen.dart`
- reached by: For a customer: nothing. Only merchant_shell.dart:282 and rider_home_screen.dart:802/850 push it.
- **unreachable:** Not part of the customer surface. Listed only so a sweep does not go hunting for a gear icon on a customer screen — there isn't one. Its AppLanguageRow IS reachable, embedded in ProfileDrawer.
- covered by: test/merchant_shell_wiring_test.dart drives it from the merchant side only.
- states: N/A for the customer surface

  - [ ] AppLanguageRow EN / AR — Shared; the customer reaches this widget through the drawer, not through this screen.  `segmented toggle — the SAME widget the customer drawer embeds`

### CategoriesScreen  — UNREACHABLE, no driving test
*A 2-up grid of every vertical with a live shop count per vertical (one size-1 request each, read for totalElements), popping the chosen StoreVertical to its caller.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/categories_screen.dart`
- reached by: Nothing. Zero call sites — grep for `CategoriesScreen` returns only its own declaration (the merchant's `MerchantCategoriesScreen` is a different class). store_home_screen.dart carries a comment saying the See-All directory chip 'left with the pill strip' and 'the separate directory screen has no seat on this header any more'.
- **unreachable:** Dead code. Deleted from the navigation graph by the redesign but left in lib/. Do not sweep it; report it for deletion. It still costs one HTTP request per vertical if anything ever mounts it.
- states: _CountShimmer placeholder while each count is in flight — never seen

  - [ ] Back, t.custAllCategories = "All Categories" — Unreachable.  `YdScreenHeader + YdBackButton`
  - [ ] Category card (chip name or vertical label + t.custShopsInCategory(n) = "{n} Shops") — Would pop the vertical to the caller. Unreachable.  `CoverCard`

### HyperlocalScreen (Neighborhood Dekkane)  — UNREACHABLE, no driving test
*District chips over the shops of that district, each row carrying its power chip, with an arabizi search hint. Backed by real endpoints (storeApi.neighborhoods(), StoreFilters.neighborhood).*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/hyperlocal_screen.dart`
- reached by: Nothing. Zero call sites anywhere in lib/, test/ or integration_test/.
- **unreachable:** Dead code with a live backend behind it. Flag as a shipped-but-unwired feature: the neighborhood filter and the district endpoint have no user-facing entry point at all.
- states: Never mounted

  - [ ] t.custHyperlocalTitle = "Neighborhood Dekkane" / t.custHyperlocalSub = "The local shops of your streets" — Unreachable.  `YdScreenHeader + Text`
  - [ ] t.custSearchArabiziHint = "Search: 2ahwe, man'oushe, knefe..." — 350ms-debounced search. Unreachable.  `YdSearchField`
  - [ ] t.custDistricts = "Districts" chips — Filters by neighborhood. Unreachable — and this is the ONLY consumer of the neighborhoods endpoint and of StoreFilters.neighborhood in the whole client.  `chip row driven by storeApi.neighborhoods()`
  - [ ] Shop rows with StorePowerChip; dark shops dimmed — Unreachable.  `cards -> StorePageScreen`

### DiasporaScreen (Send to Lebanon)  — UNREACHABLE, no driving test
*Pick a recipient (a saved address labelled with their name), attach a gift note, and start shopping with THEIR address active.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/diaspora_screen.dart`
- reached by: Nothing. Zero call sites. Its onStartOrder callback has no caller to supply it.
- **unreachable:** Dead code, and it takes a checkout code path with it (the gift-note prefix). Also carries a visible string bug that would ship the moment anyone wires it up.
- states: Never mounted

  - [ ] t.custDiasporaTitle = "Send to Lebanon" / t.custDiasporaBanner = "Remittance made real" — Unreachable.  `YdScreenHeader + banner`
  - [ ] t.edit = "Edit" on the t.custFamilyRecipient = "Family recipient" card — Opens the address sheet to choose the recipient. Unreachable.  `InkWell`
  - [ ] t.custPersonalNote = "Attach a personal note (delivered with the order)" — Sets cart.giftNote. Unreachable — which means cart.giftNote is ALWAYS null, so checkout's gift-note prefix branch (checkout_screen.dart ~line 250) is unreachable code too.  `TextField`
  - [ ] t.custStartOrder — Selects the recipient's address, stores the note, pops and calls onStartOrder. Unreachable. SEPARATE BUG: the English string is "Select Items 0026 Start Order" — an unescaped ampersand survived as the literal digits 0026 in app_en.arb:1865.  `YdPillButton`

## MERCHANT — mobile_app MerchantShell + the delivery_merchant package (dashboard, POS terminal/checkout/receipt, inventory, product form, categories, stock alerts, stock count, orders + order detail, staff, settings, payout, statement, analytics, shop profile, WhatsApp draft panel, reports)

39 screens, 263 controls.

### MerchantShell (five-tab chrome)
*Decides who is standing at the phone (owner vs employee) and which of the five tabs they may see; carries the unaccepted-order badge.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/merchant_shell.dart`
- reached by: Sign in as merchant/200002 → main.dart role branch (carrier and delivery are checked FIRST, merchant lands here) → MerchantShell opens on the Dashboard tab.
- covered by: integration_test/merchant_shell_test.dart 'a merchant signs in and reaches all five shop tabs' — DRIVES: real sign-in, taps all five nav items, asserts IndexedStack actually swapped. test/merchant_shell_wiring_test.dart taps the Settings tab and asserts the statement row appears/hides.
- states: Owner (MERCHANT role): all 5 tabs · Employee (MERCHANT_STAFF): only POS/Inventory they are permitted + Settings; if current tab becomes invisible after the staff lookup it snaps to _visibleTabs().first · Badge absent until merchantSummary() answers; a failed badge poll is deliberately silent (line 186) · _storeId null (store lookup and myMembership both failed) ⇒ POS/Inventory/StockCount degrade · 30s badge poll; owner only

  - [ ] t.navDashboard — "Dashboard" — _open(MerchantTab.dashboard); builds MerchantDashboardScreen on first visit only (_visited set, line 215)  `YdBottomNavItem inside YdBottomNav (custom, no Key)`
  - [ ] t.navPos — "POS" — Opens PosTerminalScreen. Employee sees it only with StorePermission.posSales  `YdBottomNavItem`
  - [ ] t.navInventory — "Inventory" — Opens InventoryScreen. Employee needs MODIFY_INVENTORY_PRICING  `YdBottomNavItem`
  - [ ] t.navOrders — "Orders" (+ numeric badge = summary.awaitingYou) — Opens OrdersScreen AND re-calls orderApi.merchantSummary() immediately. OWNER-ONLY — order-manager refuses employee tokens (class doc, lines 22-26)  `YdBottomNavItem with badgeCount`
  - [ ] t.navSettings — "Settings" — Opens MerchantSettingsScreen; always visible, even to a permission-less employee  `YdBottomNavItem`

### MerchantDashboardScreen
*How today is going, whether the shop is live, and what is waiting to be accepted.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/dashboard_screen.dart`
- reached by: Sign in → lands here (tab 1 of 5, the shell's default).
- covered by: packages/delivery_merchant/test/dashboard_phone_test.dart 'the chart keeps its numbers somewhere a thumb can reach' DRIVES the Day-by-day tap; the other 6 cases mount only (layout/overflow/48dp/RTL). dashboard_deltas_test.dart (10 cases) and portal dashboard_screen_test.dart (14 cases) are mount-and-assert — the publish switch is NEVER tapped by any test.
- states: First load: CircularProgressIndicator · Hard fail: YdEmptyState t.couldNotLoadOrdersShort "Could not load orders." + server 'detail' + Try again · Silent 60s poll failure keeps the last good numbers on screen · pendingApproval=true ⇒ amber banner t.pendingBannerMerchant AND the publish switch is disabled · No store ⇒ header title falls back to "Dashboard", switch disabled · Recent-orders section disappears entirely if that call fails · Period comparison lines vanish (never zero) if aggregates fail or are unwired · t.nothingSoldYet "Nothing has sold in this period yet." for empty best sellers · Queue section hidden entirely when preparing+ready+onTheWay are all 0 · savedByOffers tile only drawn when > 0

  - [ ] t.refresh — "Refresh" (tooltip; icon-only) — _refresh(): summary + recent orders + store + 28-day series, all four in parallel  `IconButton(Icons.refresh), hit box forced to 48x48`
  - [ ] **[destructive]** t.merchPublishShop — "Publish your shop" (Semantics label); visible text t.merchActive "Active" / t.merchInactive "Inactive" — ON = storeApi.publish(storeId) → snackbar t.yourShopIsLive "Your shop is live". OFF = storeApi.suspend(storeId) → snackbar t.merchShopHidden "Your shop is hidden from the market." Optimistic thumb + _storeSeq generation guard  `Material Switch inside FittedBox inside GestureDetector (48x26 drawn, 48dp hit box)`
  - [ ] t.merchPendingOrders "Pending Orders" / t.merchNewOrders "New Orders" / t.allCaughtUp "Nothing waiting on you." with a t.merchView "View" chip — Jumps to the Orders tab via onShowOrders  `YdCard.bordered(onTap:)`
  - [ ] t.preparingNow "Preparing" — Jumps to Orders tab  `MerchantMetricCard.accent(onTap:)`
  - [ ] t.readyForPickup "Ready for pickup" — Jumps to Orders tab  `MerchantMetricCard.accent(onTap:)`
  - [ ] t.outForDelivery "Out for delivery" — Jumps to Orders tab  `MerchantMetricCard.accent(onTap:)`
  - [ ] t.merchViewAll — "View All" (Recent Orders section action) — Jumps to Orders tab  `YdSectionHeader actionLabel/onAction`
  - [ ] Recent order row "#<shortId>" + "N items • 12.34" — Pushes MerchantOrderDetailScreen; onChanged silently re-refreshes the dashboard  `YdCard.bordered(onTap:) — 5 rows max`
  - [ ] t.dayByDay — "Day by day" — Opens the _DayByDaySheet modal bottom sheet (null/absent when s.days is empty)  `YdSectionHeader action on the chart card`
  - [ ] pull-to-refresh — Same _refresh()  `RefreshIndicator over the whole ListView (AlwaysScrollableScrollPhysics)`
  - [ ] t.tryAgain — "Try again" — Only on the hard-failure screen (summary null AND error)  `YdPillButton.secondary inside YdEmptyState`
  - [ ] horizontal drag on the 14-day chart — Scrolls the bars when 14 × 22dp exceeds the card; must NOT move the page sideways  `SingleChildScrollView inside the chart card`

### _DayByDaySheet
*The chart's numbers as rows, for a thumb that cannot hover a 5px bar.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/dashboard_screen.dart:1213`
- reached by: Dashboard → chart card → tap "Day by day".
- covered by: dashboard_phone_test.dart 'the chart keeps its numbers somewhere a thumb can reach' (opens it and asserts the rows)
- states: Flexible list: a fortnight scrolls, a slow week leaves the sheet short

  - [ ] drag handle — Dismisses the sheet  `showModalBottomSheet(showDragHandle: true, useSafeArea, maxWidth 560)`
  - [ ] column headings t.ordersInWindow "Orders" / t.deliveredInWindow "Delivered" / t.salesInWindow "Sales" — Read-only; rows are newest-first, reversed against the chart  `Text rows (not sortable)`

### PosTerminalScreen  — UNREACHABLE, no driving test
*The till: a grid of the shop's products over a basket, and one button that takes money.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/pos/pos_terminal_screen.dart`
- reached by: Sign in → bottom nav "POS" (tab 2).
- **unreachable:** pos-service is not deployed (main.dart:141-142). Every write — openSale, addLine, setQty, voidSale, checkout — will fail; expect the snackbar t.posCouldNotLoadSale "Could not load this sale" or the server's own detail on the first tile tap. The "Open shift" chip is unreachable in BOTH hosts because neither passes onOpenShift.
- states: Wide ≥1000dp: permanent 380px basket column; narrow: sticky bar + sheet — one file, two layouts · t.posTerminalUnavailable "The register is not available yet." amber band — ONLY when posApi is null or storeId is null. On dev BOTH are non-null, so the band is NOT shown and taps fail on the wire instead · Catalogue loading spinner / t.posCouldNotLoadCatalogue "Could not load the catalogue" + Try again / t.posNoProducts "No products to sell yet" · t.merchbNoMatchingItems "No matching items" when search+category match nothing · Out-of-stock tile shows a red t.invStatusOut "Out of stock" badge; a tile already in the basket shows a brand quantity badge instead · LBP second line only when MarketRates has a rate

  - [ ] t.back — "Back" (YdScreenHeader back arrow) — onExit → returns to Dashboard (owner) or Settings (employee)  `YdScreenHeader onBack`
  - [ ] t.posOpenShift — "Open shift" — NOT WIRED — onOpenShift is null in both hosts, so the chip never draws  `YdChip in the header trailing slot`
  - [ ] t.posShiftActive — "Shift open · N sales" — Read-only; only when currentShift() returns an open shift  `YdBadge.accent`
  - [ ] t.posSearchProducts — "Search products, SKU or barcode" — onChanged filters the loaded page in memory; ENTER (onSubmitted) is the scanner path — matches a local SKU/barcode and adds it, else posts addLine(barcode:)  `YdSearchField(controller, textInputAction.search)`
  - [ ] t.posScanBarcode — "Scan barcode" (filter slot semantic label) — Same _submitSearch as ENTER. Disabled when !_live  `YdSearchField filterIcon Icons.qr_code_scanner, onFilterTap`
  - [ ] t.all — "All" + one chip per root category — setState(_category) — client-side filter; strip hidden when categories() returns empty  `YdChip(selected, elevated) in a horizontal ListView`
  - [ ] Product tile (photo, name, price, LBP hint) — _add(product) → openSale (first tap only) then addLine. Serialised behind _queue; spinner overlay while busy. Archived products are filtered out of the grid  `_ProductTile → YdCard.bordered(onTap:) wrapped in MergeSemantics + Tooltip(name · SKU)`
  - [ ] t.clear — "Clear" — Clears the search box AND the category chip  `TextButton inside the no-matches YdEmptyState`
  - [ ] t.tryAgain — "Try again" — _reload() the catalogue after a load failure  `YdPillButton.secondary`
  - [ ] pull-to-refresh (narrow only) — Re-fetches myProducts(size:200)  `RefreshIndicator over the grid`
  - [ ] sticky bar t.posLinesCount "N items" + total, chevron up — _openBasketSheet() — inert when the basket is empty  `InkWell across the left half of the bar`
  - [ ] t.posCharge — "Charge  $12.34" — _charge() → PosCheckoutScreen.show. Disabled when empty, !_live, or onCheckout is null  `YdPillButton (compact, maxWidth 220) in the sticky bar`

### POS basket (wide column, or the phone's modal sheet)  — no driving test
*What is rung up, at what quantities, and what it comes to.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/pos/pos_terminal_screen.dart:745`
- reached by: POS tab → tap the sticky bar (phone) — or it is simply the right-hand column at ≥1000dp.
- states: Empty: YdEmptyState t.posCartEmpty "Nothing rung up yet" + t.posCartEmptyHint "Tap a product to start the sale." · Totals block draws only the rows the server sent: t.posSubtotal, t.posDiscount (negative), t.posTax "VAT", t.posOutstanding · Per-line spinner replaces the quantity while a write is in flight · Sheet height is 72% of the window so the grid stays visible behind it

  - [ ] **[destructive]** t.posClearSale — "Clear sale" — Confirm dialog (title t.posClearSale, body t.posLinesCount) → api.voidSale(saleId, reason). ABANDONS the customer's whole basket  `TextButton in the basket header`
  - [ ] t.back — "Back" (close, sheet only) — Pops the basket sheet  `IconButton(Icons.close)`
  - [ ] **[destructive]** t.posQuantity — "Quantity" (increase); decrease is t.posQuantity or t.posRemoveLine "Remove" at qty 1 — setQty(line, qty±1). Decrementing from 1 sends 0, which is how the line is DELETED — there is no separate delete button  `_StepperButton — 32dp Semantics(button) InkWell, minus/plus, delete_outline glyph at qty 1`
  - [ ] t.posCharge — "Charge  $12.34" — In the sheet: pops the sheet FIRST, then _charge()  `YdPillButton (full width) at the foot of the basket`

### PosCheckoutScreen (a.k.a. PosCheckoutSheet)  — UNREACHABLE, no driving test
*The tender step — how the customer is paying, what they handed over, what comes back. Nothing is written until Complete.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/pos/pos_checkout_screen.dart`
- reached by: POS tab → add at least one line → "Charge" (bottom sheet at 92% height under 1000px window width; a 420x720 non-dismissible Dialog at or above it).
- **unreachable:** pos-service not deployed — Complete will fail. Note the receipt screen is NOT opened from here in either host: checkout ends on its own settled state.
- states: Preview block (t.posChangePreview "Preview — the till confirms the final figure."): t.posCashLbp face value, t.posRoundingLbp "Rounded to the nearest note", t.posChangeDue "Change due" · Bottom bar shows t.posRemainingAmount "Remaining $x" + t.posTendersShort "The payments do not cover the total yet." while short · Inline notices (never snackbars): t.posTerminalUnavailable when api is null; t.posCouldNotLoadSale when the total is unreadable; the server's 422 detail after a failed checkout · Settled: YdEmptyState t.posSaleCompleted "Sale completed" + the basket card again · Two-pane at ≥900dp of its OWN width: basket left, tender pad right · Empty basket: YdEmptyState t.posCartEmpty

  - [ ] t.back — "Back" — _close() — pops with the settled sale or nothing. Suppressed entirely while _busy (PopScope canPop:false too)  `MerchantScreenHeader onBack`
  - [ ] t.posCashUsd "Cash (USD)" / t.posCashLbp "Cash (LBP)" / t.posCard "Card" / t.posWallet "YouDrop wallet" — _pickMethod(). WALLET IS PERMANENTLY INERT — carries a YdComingSoon t.posWalletComingSoon "Coming soon". CASH_LBP is inert when the sale carries no locked rate  `YdChip inside Wrap, each in Semantics(button, selected), Opacity 0.5 when inert`
  - [ ] t.posAmountTendered — "Amount given" — Prefilled with what is outstanding; ENTER completes the sale when it exactly settles the total  `TextField, numeric keyboard, FilteringTextInputFormatter + _TwoDecimalFormatter, $ prefix (suffix in RTL)`
  - [ ] t.posChangeIn — "Change in" USD / LBP — Switches which currency the change preview is quoted in; LBP disabled without a rate  `two YdChip in a Wrap; cash-USD only`
  - [ ] t.posCardReference — "Reference (optional)" — Rides on the tender  `TextField(maxLength 64); card method only`
  - [ ] t.posAddTender — "Add another payment" — Stages the drafted tender for a split payment. Only drawn when the draft would leave a shortfall > 0  `MerchantActionButton(outlined)`
  - [ ] t.posRemoveLine — "Remove" (tooltip on a staged tender) — _removeTender(index) and re-prefills the amount box  `IconButton(Icons.close_rounded, compact)`
  - [ ] **[destructive]** t.posCompleteSale — "Complete sale" — api.checkout(saleId, tenders, idempotencyKey). TAKES THE MONEY. The key is generated ONCE in initState and reused on every retry. Disabled unless shortfall == 0 exactly  `YdPillButton with busy state, at the bottom bar`
  - [ ] t.done — "Done" — _close(); only drawn when there is somewhere to pop to  `YdPillButton.secondary in the settled YdEmptyState`

### PosReceiptScreen  — UNREACHABLE, no driving test
*The settled sale as a printable artifact — store block, receipt number, lines, totals, payments, footer.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/pos/pos_receipt_screen.dart`
- reached by: NOTHING NAVIGATES HERE.
- **unreachable:** UNREACHABLE IN BOTH SHIPPED HOSTS. Exported from delivery_merchant.dart and never constructed: MerchantShell hands checkout to PosCheckoutScreen.show and the portal does the same (portal_shell.dart:272-273); neither opens a receipt. grep for 'PosReceiptScreen' finds only its own declaration.
- states: No receipt and no way to fetch one: YdEmptyState t.posReceipt + t.posTerminalUnavailable · Error: t.posCouldNotLoadSale + Try again (only when re-fetchable) · Actions stack vertically below 420dp, share as a row above it

  - [ ] t.posPrintReceipt — "Print receipt" — onPrint(url) or, with no handler, copies the server HTML URL to the clipboard. Hidden when there is no URL to open  `YdPillButton.secondary(Icons.print_outlined)`
  - [ ] t.posShareReceipt — "Share receipt" — onShare(plain text) or copies the rendered text — the WhatsApp path  `YdPillButton.secondary(Icons.ios_share)`
  - [ ] t.posNewSale — "New sale" — onNewSale, falling back to Navigator.maybePop  `YdPillButton (primary)`
  - [ ] t.refresh — "Refresh" — Re-fetches the receipt (the reprint path)  `IconButton in the header; only when api+saleId are both present`
  - [ ] t.back — back arrow — Pops, when there is anything to pop  `MerchantScreenHeader onBack`

### InventoryScreen  — UNREACHABLE, no driving test
*How many are left on each shelf — a different question, and a different service, from the catalogue.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/inventory_screen.dart`
- reached by: Sign in → bottom nav "Inventory" (tab 3).
- **unreachable:** inventory-service is not deployed, so on dev this screen loads into its error state. Consequence: the summary never arrives ⇒ the alerts pill never draws ⇒ StockAlertsScreen has NO route in the shipped build. Separately, the per-item adjust sheet and movement history behind onOpenItem are unreachable in both hosts — neither MerchantShell nor portal_shell passes onOpenItem, so a row tap opens the product form instead.
- states: Header counts t.invProducts "Products" / t.invCategories "Sections" print an em dash (never 0) when unknown; they fall back to the list total and the catalogue's category count only when the summary FAILED · t.invSyncing "Bringing your catalogue in…" chip: a one-time InventoryApi.sync() fires when the unfiltered list is empty but myProducts is not, then a snackbar t.invSynced "N products added" · First load / syncing: spinner · t.invCouldNotLoad "Could not load inventory" + server detail + Try again · t.invEmpty "Nothing in inventory yet" (+ t.invEmptyHint unfiltered, or a Clear button when filtered) · Stock cell prints an em dash + t.invNotTracked "Not tracked" — NEVER a zero — for an untracked product; otherwise the count coloured by StockSeverity with t.invStatusWarning "Low" / t.invStatusCritical "Critical" / t.invStatusOut "Out of stock" · Hidden/draft rows carry t.invFilterHidden "Hidden" or t.draft "Draft" · api null ⇒ inert unavailable state with no retry (does not occur on dev)

  - [ ] t.refresh — "Refresh" (wide only, ≥600dp) — _refresh(): reloads the paged list and the summary  `IconButton in MerchantScreenHeader trailing`
  - [ ] t.invAlertsCount — "N items need restocking" (tooltip/semantics); face text "N Alerts" — THE ONLY ROUTE to StockAlertsScreen. Drawn ONLY when summary != null AND alerts > 0  `_AlertsPill — amber InkWell pill with a chevron`
  - [ ] t.invSearch — "Search by name, SKU or barcode" — SERVER-SIDE search, 350ms debounced; onSubmitted cancels the debounce and refetches at once  `YdSearchField`
  - [ ] t.invFilterAll "All" / t.invFilterLowStock "Low stock" / t.invFilterOutOfStock "Out of stock" / t.invFilterActive "Active" / t.invFilterHidden "Hidden" — _selectFilter → rebuilds the whole PagedList closure (a chip tap is a refetch, not a local filter). Inert when api is null  `YdChip in a Wrap`
  - [ ] Inventory row (thumb, name, SKU/barcode/price, stock cell) — _openItem: onOpenItem is NULL in both hosts, so it falls back to catalogApi.read(productId) then pushes ProductFormScreen  `_InventoryRow → YdCard.bordered(onTap:)`
  - [ ] t.merchbAddProduct — "Add Product" — Pushes ProductFormScreen with no existing product; refreshes on a true result  `_AddButton — custom 44dp brand pill as floatingActionButton (NOT a FloatingActionButton.extended)`
  - [ ] t.clear — "Clear" — _clearFilters(): resets query and chip to All  `TextButton in the filtered-empty YdEmptyState`
  - [ ] t.tryAgain — "Try again" — _refresh() after a failed first page  `YdPillButton.secondary`
  - [ ] t.couldNotLoadMore — "Could not load more — try again" — list.loadMore() after a mid-scroll page failure  `TextButton.icon in the grid footer`
  - [ ] pull-to-refresh (narrow only) — Same _refresh()  `RefreshIndicator`
  - [ ] infinite scroll — Auto-loads the next page  `NotificationListener<ScrollNotification> + shouldLoadMore`

### ProductFormScreen
*Create or edit one product and manage its photos.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/product_form_screen.dart`
- reached by: Inventory tab → "Add Product" FAB (new) or tap any inventory row (edit). Portal: Products page → row tap or FAB.
- covered by: packages/delivery_merchant/test/product_image_picker_test.dart — DRIVES the dropzone tap for two paths: 'a picker that throws is reported, not swallowed' and 'cancelling the dialog is silent'. Nothing drives Save, the price validator, the category dropdown or image removal.
- states: New product: hint t.merchbAddPhotosNow "Add photos now — they upload when you save." → t.merchbPhotosAddedOnSave once something is queued · Existing product with no photos: t.needsAPhotoToPublish "A product needs at least one photo before it can be published." · Options card: 2px LinearProgressIndicator while loading, a Try again InkWell on failure (NOT the empty state — a failed load must not read as 'your variants are gone'), t.merchbNoOptionsYet "No options on this item yet" when genuinely empty · Save failure: snackbar t.couldNotSaveProduct "Could not save this product" · Picker failure: snackbar t.couldNotOpenPicker "Could not open the file picker: {reason}"; cancel is silent

  - [ ] t.back — "Back" — Pops with _dirty, so the list behind refreshes only if something was saved  `YdScreenHeader onBack; PopScope(canPop:false) intercepts the system back too`
  - [ ] t.merchbUploadImageCta — "Upload a product photo" (+ hint t.merchbUploadHint "PNG, JPG up to 5MB") — file_selector openFile (jpg/jpeg/png/webp). On an EXISTING product it uploads immediately; on a NEW one the bytes are held in _pendingImages and uploaded after the first save  `_Dropzone — 130px dashed CustomPaint over an InkWell, Semantics(button)`
  - [ ] **[destructive]** t.remove — "Remove" (tooltip) — catalogApi.removeImage(objectKey) then re-reads the product  `IconButton(Icons.close) on each _ImageTile`
  - [ ] t.remove — "Remove" (tooltip) on a pending tile — Drops the queued bytes locally; disabled while saving  `IconButton on _PendingImageTile (badged t.merchbPending "Pending")`
  - [ ] t.nameLabel — "Name" — Validator t.nameRequired "Name is required"  `TextFormField(maxLength 200, counter hidden)`
  - [ ] t.descriptionLabel — "Description" — Optional  `TextFormField(maxLines 3, maxLength 4000)`
  - [ ] t.priceLabel — "Price" — Validators t.enterANumber "Enter a number" and t.priceMustBePositive "Price must be greater than zero" (mirrors the server's @DecimalMin 0.01)  `TextFormField, decimal keyboard`
  - [ ] t.categoryLabel — "Category" — Sets _categoryId  `DropdownButtonFormField<String>, indented tree, first item t.uncategorised "Uncategorised"`
  - [ ] t.tryAgain — "Try again" (inside the category box) — _reloadCategories(). The form stays saveable — a category outage must not block adding a product  `InkWell replacing the dropdown when categories() failed`
  - [ ] t.merchbAddOption — "+ Add option" — Reads the current option groups, then opens ProductOptionsEditor. INERT (muted) until the product has an id — footnote t.merchbOptionsNeedSave "Save the item first, then add its options."  `InkWell text button on the Variants & Options card`
  - [ ] t.merchbSaveMenuItem "Save Product" (new) / t.saveChanges "Save changes" (edit) — create() or update(), then uploads any pending photos, then re-reads. Snackbar t.saved "Saved" or t.uploadFailedBecause "Upload failed: {reason}"  `ElevatedButton, full width, 52dp, spinner while saving`

### ProductOptionsEditor (modal sheet)  — no driving test
*Every option group on a product and what each asks the customer. Edits a COPY; the endpoint is a whole-structure REPLACE.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/product_options_editor.dart`
- reached by: Product form (SAVED product only) → "+ Add option" on the Variants & Options card.
- states: Client-mirrored refusals shown above Save in brand crimson: t.merchbGroupNeedsName, t.merchbGroupNeedsOption, t.merchbOptionNeedsName, t.merchbMinAboveMax, t.merchbMinAboveCount, t.merchbGroupOutOfRange (0–50) · Empty: t.merchbNoOptionsYet · Caller-side failures: t.merchbOptionsLoadFailed (refuses to open rather than risk replacing groups with nothing) and t.merchbOptionsSaveFailed

  - [ ] t.merchbAddGroup — "+ Add group" — Appends an empty OptionGroupDraft with one blank option  `TextButton in the sheet header`
  - [ ] t.merchbGroupName — "Group name" — Mutates the draft; blank ⇒ Save disabled with t.merchbGroupNeedsName  `TextFormField per group card`
  - [ ] **[destructive]** t.merchbRemoveGroup — "Remove group" (tooltip) — Removes the whole group from the draft. On Save this DELETES it server-side, because the PUT replaces everything  `IconButton(Icons.delete_outline)`
  - [ ] t.merchbMinSelect "Choose at least" / t.merchbMaxSelect "Choose at most" — The server derives 'required' from min and 'single choice' from max; the hint line switches between t.merchbRuleRequired and t.merchbRuleOptional  `_CountField — TextFormField(number); empty falls back to 0 / 1`
  - [ ] t.merchbOptionName — "Option" — Blank ⇒ Save disabled with t.merchbOptionNeedsName  `TextFormField per choice row`
  - [ ] t.merchbPriceDelta — "Extra" — Signed on purpose — 'Small' may cost less than base  `TextFormField, signed decimal keyboard`
  - [ ] **[destructive]** t.merchbRemoveOption — "Remove option" (tooltip) — Drops one choice  `IconButton(Icons.close)`
  - [ ] **[destructive]** t.save — "Save" — Pops the drafts → caller PUTs the whole structure. DISABLED while _firstProblem is non-null  `YdPillButton at the foot`
  - [ ] drag / dismiss — Cancel — the caller writes nothing  `DraggableScrollableSheet 0.5–0.95, initial 0.85`

### MerchantCategoriesScreen  — UNREACHABLE, no driving test
*The shop's OWN sections and the order customers see them in — not the platform taxonomy.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/merchant_categories_screen.dart`
- reached by: Settings tab → "Categories" row (shown only with MODIFY_INVENTORY_PRICING; an owner always has it). Portal: Merchant Hub rail → Categories.
- **unreachable:** Depends on product-service release B store-category endpoints; if they are not up, expect the Could-not-load state.
- states: storeId null: YdEmptyState t.catCouldNotLoad + t.staffNoShopYet · Loading spinner / t.catCouldNotLoad "Could not load sections" + detail + Try again · Empty: t.catEmpty "No sections yet" + t.catEmptyHint + an Add button · Reorder hint banner drawn only with 2+ sections; a spinner sits in the section header while the order is in flight · Row subtitle t.catProductsCount "N products" / "No products"

  - [ ] t.back — "Back" — Pops  `MerchantScreenHeader onBack (passed by the shell, absent in the portal)`
  - [ ] t.refresh — "Refresh" (wide only) — _load(); disabled while loading  `IconButton`
  - [ ] drag handle (t.catDragToReorder as tooltip + semantic label) — Optimistic move, then PUT …/categories/order with the WHOLE id list. A failure reverts to _confirmed and says t.catOrderFailed "The order could not be saved"; success says t.catOrderSaved "Order saved". Handle greyed while saving and for a one-row list  `ReorderableDragStartListener wrapping a 32dp Icons.drag_indicator inside a SliverReorderableList`
  - [ ] t.catRename — "Rename" (tooltip) — Opens _SectionEditorDialog pre-filled  `IconButton(Icons.edit_outlined, compact)`
  - [ ] **[destructive]** t.catDelete — "Delete section" (tooltip) — REFUSES BEFORE ASKING when productCount > 0 (snackbar t.catCannotDeleteNonEmpty); otherwise a confirm dialog t.catDeleteConfirm then deleteStoreCategory. A 409 falls back to the same sentence  `IconButton(Icons.delete_outline, compact)`
  - [ ] t.catAdd — "Add a section" — Opens _SectionEditorDialog empty. Not drawn at all when storeId is null  `YdPillButton(compact) as floatingActionButton`
  - [ ] t.tryAgain — "Try again" — _load()  `YdPillButton.secondary`
  - [ ] pull-to-refresh (narrow, storeId non-null) — _load()  `RefreshIndicator`
  - [ ] platform category chips — Deliberately inert — read-only reference  `YdChip with NO onTap under t.catPlatformCategories "YouDrop categories"`

### _SectionEditorDialog  — no driving test
*Name a section and file it under a platform category.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/merchant_categories_screen.dart:816`
- reached by: Categories → "Add a section" FAB, or the pencil on any row.
- states: Title is t.catAdd "Add a section" or t.catRename "Rename" · Parent dropdown hidden entirely when the taxonomy failed to load

  - [ ] t.catName — "Section name" (hint t.catNameHint "Drinks") — ENTER submits; a blank name silently refuses to submit  `TextField(autofocus, textInputAction.done)`
  - [ ] t.catParent — "Sits under" — A section may hang under a PLATFORM row, never under another section. A retired parent is dropped rather than crashing the dropdown  `DropdownButtonFormField<String?>, first item t.catNoParent "Top level"`
  - [ ] t.cancel — "Cancel" — Pops with null  `TextButton`
  - [ ] t.save — "Save" — createStoreCategory or updateStoreCategory, then a full reload  `ElevatedButton`

### StockAlertsScreen  — UNREACHABLE, no driving test
*Everything running out, worst first, with the one thing a merchant does about it.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/stock_alerts_screen.dart`
- reached by: Inventory tab → the amber "N Alerts" pill in the header band. There is no other route.
- **unreachable:** NO ROUTE IN THE SHIPPED BUILD. Its only entry point is the Inventory alerts pill, which is drawn only when the inventory summary call SUCCEEDS and returns alerts > 0 (inventory_screen.dart:420-427) — and inventory-service is not deployed. MerchantShell wires _openStockAlerts correctly; the door is what is missing.
- states: Tally band: three MerchantMetricCards — t.invStatusOut "Out of stock", t.invStatusCritical "Critical", t.invStatusWarning "Low" (2 per row on a phone, 3 when wide) · Groups stacked worst-first with a count badge per group · Row meta: t.invVelocity "Sells about N a day" or t.invNoVelocityYet "Not enough sales yet to say" (never a zero), t.invHoursOfCover, t.invLastSold · api null: t.invAlertsCouldNotLoad + t.invAlertsEmptyHint, deliberately WITHOUT a retry · Error: t.invAlertsCouldNotLoad "Could not load stock alerts" + detail + Try again · Empty: t.invAlertsEmpty "Every shelf is stocked" + t.invAlertsEmptyHint

  - [ ] t.back — "Back" — Pops  `MerchantScreenHeader onBack (falls back to maybePop)`
  - [ ] t.refresh — "Refresh" (wide only) — _reload()  `IconButton`
  - [ ] t.invRestock — "Restock" — Opens the _RestockSheet for that product  `MerchantActionButton(primary) — full width on a phone, right-aligned when wide`
  - [ ] t.tryAgain — "Try again" — _reload()  `YdPillButton.secondary`
  - [ ] pull-to-refresh (narrow) — _refresh()  `RefreshIndicator`

### _RestockSheet  — UNREACHABLE, no driving test
*Record a stock RECEIPT — 'the goods arrived', not 'order more from the wholesaler'.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/stock_alerts_screen.dart:702`
- reached by: Stock alerts → "Restock" on a row.
- **unreachable:** Reachable only through Stock alerts, which is itself unreachable today.
- states: Sheet lifts on MediaQuery.viewInsetsOf for the keyboard · Errors render INLINE under the fields (a snackbar over a sheet is covered by the keyboard) · Parent shows snackbar t.invAdjusted "Stock updated" and reloads on success

  - [ ] t.invAdjustQuantity — "How many?" — Must parse > 0 or the field errors with the same string  `TextField(autofocus, digitsOnly formatter, numeric keyboard)`
  - [ ] t.invAdjustReason — "Why?" — Fixed and stated: this sheet only ever records a receipt  `YdBadge showing t.invReasonReceived "Received" — NOT a picker`
  - [ ] t.invAdjustNote — "Note (optional)" — Rides on the movement  `TextField(maxLines 2)`
  - [ ] t.cancel — "Cancel" — Pops with null  `YdPillButton.secondary`
  - [ ] **[destructive]** t.invAdjustSave — "Save adjustment" — inventoryApi.adjust(productId, delta, RECEIVED, idempotencyKey) — WRITES STOCK. The key is generated once in the state and reused on retry, so a double-submit cannot receive the delivery twice  `YdPillButton with busy state`

### StockCountScreen — setup face (no open count)  — UNREACHABLE, no driving test
*Name and scope a new counting session, and read the ones that came before.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/stock_count_screen.dart`
- reached by: Settings tab → "Stock count" row (needs MODIFY_INVENTORY_PRICING AND a resolved _storeId — the row is absent otherwise).
- **unreachable:** inventory-service is not deployed: on dev this lands on the error state and Start will 404.
- states: api null: YdEmptyState t.invCountTitle + t.invCouldNotLoad, no retry · Loading spinner / error state t.invCouldNotLoad + detail + Try again · No history: YdEmptyState t.invCountEmpty "No counts yet"

  - [ ] t.back — "Back" — Pops freely while no count is open  `MerchantScreenHeader onBack (when poppable)`
  - [ ] t.refresh — "Refresh" — _load()  `IconButton in the header trailing (replaced by a spinner while a write is in flight)`
  - [ ] t.invCountName — "Name this count" (hint t.invCountNameHint "Friday shelf check") — onChanged rebuilds so Start enables; ENTER starts the count  `TextField(textInputAction.done)`
  - [ ] t.invCountScope — "What are you counting?" — Scopes the count to one category. Not drawn when catalogApi is null or categories() failed  `DropdownButtonFormField<String>, first item t.invCountAllProducts "Everything"`
  - [ ] t.invCountStart — "Start counting" — startCount(name, categoryId, storeId). Disabled until the name is non-blank. A 409 becomes t.invCountOpenExists "A count is already open. Finish it first." and re-loads  `YdPillButton(Icons.play_arrow_rounded), busy state`
  - [ ] history row — Read-only: name, t.invCountProgress, relative time, and a status badge t.invCountStatusSubmitted "Submitted" / "Cancelled" / t.invCountStatusOpen "In progress"  `_HistoryRow — YdCard.bordered, NOT tappable`
  - [ ] pull-to-refresh — _load(silent:true)  `RefreshIndicator over the setup ListView`

### StockCountScreen — session face (a count is open)  — UNREACHABLE, no driving test
*Type what is on the shelf beside what the system believes, then apply or abandon it.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/stock_count_screen.dart:790`
- reached by: Settings → Stock count → Start counting (or re-open the screen while a count is already open — the screen adopts it automatically).
- **unreachable:** inventory-service is not deployed.
- states: Progress band: t.invCountProgress "N of M counted", a clamped LinearProgressIndicator, and a caution badge with the count status · Variance column is the SERVER's, printed signed (+3 / -3) and coloured — missing red, surplus amber, match green; an uncounted row shows an em dash · System column shows an em dash for an untracked product · Empty results: t.invCountNoDiscrepancies + an "All" button, or t.invEmpty + Clear when searching, or t.invEmpty + the count name for an empty scope · Row stacks below 720dp of its own width · Header spinner replaces Refresh while a batch is in flight

  - [ ] t.invSearch — "Search by name, SKU or barcode" — Client-side filter of the already-loaded lines  `YdSearchField in the progress band`
  - [ ] t.all — "All" / t.invCountDiscrepancies — "Differences found (N)" — Toggles _differencesOnly  `two YdChip in a Wrap`
  - [ ] t.invCountCounted — "You counted" — 400ms debounced, BATCHED write (recordLines for 2+, recordLine for one). Clearing the box sends NULL = uncounted, which submit skips — it does NOT mean zero. onEditingComplete flushes immediately  `96dp TextField per row, digitsOnly + 6-char limit, centred`
  - [ ] **[destructive]** t.invCountCancelCount — "Cancel count" — Confirm dialog (t.invCountKeepCounting "Keep counting" vs t.invCountCancelCount) → cancelCount(id) → snackbar t.invCountCancelled. THROWS THE SESSION AWAY  `YdPillButton.secondary in the pinned action bar`
  - [ ] **[destructive]** t.invCountSubmit — "Submit count" — Flushes pending edits, shows the discrepancy review dialog, then submitCount(id) — WRITES ONE STOCK MOVEMENT PER NON-ZERO VARIANCE. Snackbar t.invCountSubmitted "Count applied to stock"  `YdPillButton in the pinned action bar, busy state`
  - [ ] **[destructive]** review dialog: t.cancel "Cancel" / t.invCountSubmit "Submit count" — Confirms the write. Shows t.invCountNoDiscrepancies "Everything matches" when there are none  `AlertDialog listing every counted line whose variance ≠ 0, signed and coloured`
  - [ ] leave dialog: t.invCountKeepCounting "Keep counting" / t.invCountDiscard "Leave" — Flushes first, then leaves. Body t.invCountLeaveWarningBody "What you have counted is saved, and the count stays open."  `AlertDialog raised by PopScope(canPop:false) on back`

### OrdersScreen ("Order Flow")
*The incoming queue: accept, prepare, mark ready, or reject.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/orders_screen.dart`
- reached by: Sign in → bottom nav "Orders" (tab 4) — owner only. Also from the dashboard's pending card / queue tiles / View All. Portal: Merchant Hub rail → Orders.
- covered by: apps/delivery_portal/test/merchant/orders_phone_test.dart — DRIVES the 'Completed' tab tap and a pull-to-refresh drag on the empty state; 6 other cases are layout/overflow/48dp/RTL mounts. NO test presses Accept, Start preparing, Mark ready or Reject.
- states: 5-second poll; a failed BACKGROUND poll never wipes the list · 422 on an action ⇒ snackbar t.orderAlreadyMovedRefreshing "That order has already moved on. Refreshing."; anything else ⇒ t.actionFailed "Could not {action}." · All buttons on a card disable together while that order id is busy (spinner in place of the label) · Empty bucket: t.noOrdersNeedingAttention "No orders needing attention." (or t.noOrdersYetMerchant on Completed) + t.merchNothingInThisList · Error: t.couldNotLoadOrdersShort + raw error + Try again · Waiver line on the card: t.noCommissionOnThisOrder or t.deliveryPaidByPlatform · Wide (≥640x560): pinned header; narrow: header and tabs scroll away

  - [ ] t.merchTabNew "New (N)" / t.stepPreparing "Preparing" / t.stepReady "Ready" / t.merchTabCompleted "Completed" — setState(_bucket). Counts come from the ONE loaded page (50 orders), never four separate requests. The selected pill's onTap is null  `Custom Material+InkWell pills in a Wrap, Semantics(button, selected) — not a TabBar`
  - [ ] t.refresh — "Refresh" (tooltip) — _refresh() — scrolls away with the header on a phone (<640dp wide or <560dp tall)  `IconButton in MerchantScreenHeader trailing`
  - [ ] Order card body — Pushes MerchantOrderDetailScreen; onChanged reloads the queue  `YdCard.bordered(onTap:), brand-ringed while status == PLACED`
  - [ ] t.actionAccept — "Accept" — orderApi.act(id, ACCEPT). Only rendered when the SERVER lists it in availableActions  `MerchantActionButton(primary), 48dp floor, in an Expanded row`
  - [ ] t.actionPrepare — "Start preparing" — act(id, PREPARE)  `MerchantActionButton(primary)`
  - [ ] t.actionMarkReady — "Mark ready" — act(id, READY)  `MerchantActionButton(primary)`
  - [ ] **[destructive]** t.merchReject — "Reject" (the CANCEL action, renamed for merchants) — act(id, CANCEL, reason:'Cancelled by merchant'). NO CONFIRMATION DIALOG — one tap kills a customer's order  `MerchantActionButton(primary:false — the recessed dialect)`
  - [ ] pull-to-refresh — _refresh()  `RefreshIndicator (both layouts, AlwaysScrollableScrollPhysics so it works on the empty state)`
  - [ ] t.tryAgain — "Try again" — _refresh()  `YdPillButton.secondary in the error YdEmptyState`

### MerchantOrderDetailScreen  — no driving test
*One order in full: flow position, customer, receipt breakdown, and whatever transitions the state machine allows.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/order_detail_screen.dart:506`
- reached by: Orders tab → tap any order card. OR Dashboard → tap a Recent Orders row. (Not exported for direct mounting — the card is the only way in.)
- states: Flow card t.merchFlowStatus "Flow Status": four bars — t.stepAccepted, t.stepPreparing, t.stepReady, t.merchStepPickedUp "Picked Up". PLACED and CANCELLED leave every bar grey; DELIVERED fills all four · Customer card t.merchCustomerDetails: the payload carries a customer id and no name, so the ADDRESS leads ('Deliver to: …') · Receipt card t.merchItemsBreakdown, optional t.merchSpecialInstructions block, t.subtotal, t.deliveryFeeLabelMerchant, t.merchGrandTotal · Waiver line t.noCommissionOnThisOrder / t.deliveryPaidByPlatform · Action row absent entirely when availableActions is empty · 422 ⇒ t.orderAlreadyMovedRefreshing; other failures ⇒ t.actionFailed

  - [ ] back arrow (MaterialLocalizations backButtonTooltip) — maybePop  `MerchantScreenHeader with YdBackButton`
  - [ ] t.actionAccept "Accept" / t.actionPrepare "Start preparing" / t.actionMarkReady "Mark ready" — act(id, action) then updates in place and notifies the queue behind  `MerchantActionButton(primary, outlined dialect, radius md, 14sp)`
  - [ ] **[destructive]** t.merchReject — "Reject" — act(id, CANCEL, reason:'Cancelled by merchant'). NO CONFIRMATION  `MerchantActionButton(primary:false, outlined)`
  - [ ] pull-to-refresh — _reload() — a failed reload keeps the list's copy on screen rather than blanking  `RefreshIndicator over the card ListView`
  - [ ] phone chip — Displays contactPhone only; there is no dial action  `a tinted Container with Icons.phone — NOT tappable`

### StaffScreen  — no driving test
*Who works here, whether they are on the floor, and what each of them may do. THE ONE SUITE SCREEN WHOSE BACKEND IS LIVE — every refusal here is a real 403.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/staff_screen.dart`
- reached by: Settings tab → "Staff" row (drawn only with MANAGE_STAFF — an owner always has it). Portal: Merchant Hub rail → Staff.
- states: 30s presence poll; a silent poll failure never wipes the roster · Badges: t.staffOnShift "On shift" (green, dot), t.staffOffShift "Off shift", or t.staffStatusInactive "Suspended" (red, overrides both) · Every member row says '{t.staffSalesToday}: {t.staffNoPosSalesYet}' — 'Sales appear here once the register is live.' rather than a column of $0.00 · Empty roster: t.staffEmpty "You work alone so far" + t.staffEmptyHint · No pending invites: t.staffNoPendingInvites "No codes outstanding"; expired codes render dimmed with a red expiry · Not attached to a shop: t.staffNoShopYet + a Join button; api null: t.staffCouldNotLoad with no retry · Without MANAGE_STAFF: rows are not tappable, no FAB, switches read-only, and a caution line t.staffNoPermission "You cannot change this" · A 403 names the missing capability: '{t.staffNoPermission} · {permission label}' · Wide ≥980dp: the permissions panel moves into its own 400px column

  - [ ] t.refresh — "Refresh" (wide only, ≥600dp) — _load(); disabled while loading  `IconButton in MerchantScreenHeader`
  - [ ] t.staffInvite — "Invite someone" — Opens _InviteDialog, then _InviteCodeDialog. Drawn only when canManage AND a roster loaded AND wired  `FloatingActionButton.extended(Icons.person_add_alt_1)`
  - [ ] owner card — Inert by design — ownership is stores.merchant_id, not a roster row. Says t.staffCannotEditOwner "The owner always has every permission."  `YdCard.bordered, deliberately NOT tappable`
  - [ ] member card — Opens _MemberPanel (bottom sheet <980dp of own width, 460x640 Dialog above it)  `YdCard.bordered(onTap:) with a chevron — only when canManage`
  - [ ] t.staffInviteShare — "Share code" (tooltip) — Clipboard copy → snackbar t.staffInviteCopied "Code copied"  `IconButton(Icons.copy_rounded) on each pending invite row`
  - [ ] t.staffRoleOwner "Owner" / t.staffRoleManager "Manager" / t.staffRoleCashier "Cashier" / t.staffRoleStockkeeper "Stockkeeper" — Switches which role band the seven switches below show. The Owner column is a statement of fact and is read-only  `YdChip row in the permissions panel`
  - [ ] **[destructive]** 7 role-band switches: t.staffPermPosSales "Sell at the register", t.staffPermPosRefundsVoids "Refunds and voids", t.staffPermModifyInventoryPricing "Products and stock", t.staffPermManageOrders "Delivery orders", t.staffPermViewReports "Reports", t.staffPermAccessSettings "Store settings", t.staffPermManageStaff "Staff" — setRolePermission(store, role, permission, granted). RE-RESOLVES EVERY ACTIVE MEMBER ON THAT ROLE — this is a bulk privilege change, not a single edit  `_PermissionRow — an InkWell row carrying a Material Switch (the whole row toggles), spinner in the thumb's place while in flight`
  - [ ] t.staffAcceptJoin — "Join" — Opens _AcceptInviteDialog — the only route in for somebody holding a code  `YdPillButton inside the no-shop YdEmptyState`
  - [ ] pull-to-refresh (narrow) — _refresh(); a failure over an existing list keeps it and says t.staffCouldNotLoad  `RefreshIndicator`
  - [ ] t.tryAgain — "Try again" — _load()  `YdPillButton.secondary`

### _MemberPanel (one employee)  — no driving test
*Everything that can be done to one person: their role, their permissions, their shift and their standing.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/staff_screen.dart:1123`
- reached by: Staff → tap a member card (requires MANAGE_STAFF).
- states: Without MANAGE_STAFF: a caution line t.staffNoPermission at the top and every control read-only · Every write re-reads the roster because the API answers with an empty body · Bottom sheet capped at 90% height on a phone; a 460x640 Dialog when wide

  - [ ] t.cancel — "Cancel" (close tooltip) — Pops with whether anything changed  `IconButton(Icons.close) in the panel header`
  - [ ] **[destructive]** t.staffChangeRole — "Change role": Manager / Cashier / Stockkeeper — changeRole(store, member, role) then re-reads the roster — a role change re-resolves the whole permission set  `YdChip row`
  - [ ] **[destructive]** 7 per-member permission switches (same labels as the role band, plus t.staffCustomised "Changed for this person" badge) — setPermission(store, member, permission, granted:) — a per-member OVERRIDE of the role band  `_PermissionRow with a Switch`
  - [ ] t.staffResetToRole — "Back to the role default" — setPermission(..., granted: null) — clears the override  `InkWell text under an overridden row`
  - [ ] **[destructive]** t.staffClockOut — "Clock out" — clockOut(store, member) → snackbar t.staffClockedOut "Shift ended". Only when the member is on shift  `YdPillButton.secondary(Icons.logout), busy state`
  - [ ] **[destructive]** t.staffDeactivate "Suspend" / t.staffActivate "Reinstate" — setStatus(INACTIVE/ACTIVE). Suspending also closes their shift server-side. NOT DRAWN on your own row — the server refuses it  `YdPillButton.secondary(pause_circle_outline / play_circle_outline)`
  - [ ] **[destructive]** t.staffRemove — "Remove from shop" — Confirm dialog t.staffRemoveConfirm "Remove this person? Their past shifts and sales stay on the record." → remove(store, member) → closes the panel with snackbar t.staffRemoved. NOT DRAWN on your own row  `TextButton.icon in critical red`

### _InviteDialog  — no driving test
*Mints a CODE, not an account — the platform never creates an identity on a merchant's say-so.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/staff_screen.dart:1415`
- reached by: Staff → "Invite someone" FAB.
- states: Hint t.staffInviteCodeHint "They sign in to YouDrop and enter this code. You never set their password." · Failures render inline in critical red under the fields

  - [ ] t.staffInviteRole — "Their role": Manager / Cashier / Stockkeeper — Sets the role the code will grant  `YdChip row (default Cashier)`
  - [ ] t.staffInviteName — "Their name" — A label for the merchant's own benefit; sent with the invite  `TextField(textInputAction.next)`
  - [ ] t.staffInviteEmail — "Email (optional)" — Label only — nothing is emailed  `TextField(emailAddress keyboard)`
  - [ ] t.staffInvitePhone — "Phone (optional)" — Label only  `TextField(phone keyboard)`
  - [ ] t.cancel — "Cancel" — Pops  `TextButton`
  - [ ] **[destructive]** t.staffInviteCreate — "Create invite code" — api.invite(...) — MINTS A REAL CODE that grants shop access when redeemed  `ElevatedButton with spinner`

### _InviteCodeDialog  — no driving test
*The code itself — this dialog IS the delivery mechanism; nothing was sent anywhere.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/staff_screen.dart:1574`
- reached by: Staff → Invite someone → Create invite code.
- states: t.staffInviteExpires "Expires {when}" — today collapses to the time alone

  - [ ] the code — Selectable for reading out or copying by hand  `_CodeText — SelectableText, monospace, 26sp, 4pt tracking, forced LTR`
  - [ ] t.staffInviteShare — "Share code" — Clipboard copy → snackbar t.staffInviteCopied  `ElevatedButton.icon(Icons.copy_rounded)`
  - [ ] t.done — "Done" — Pops  `TextButton`

### _AcceptInviteDialog  — UNREACHABLE, no driving test
*The employee's end of the code.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/staff_screen.dart:1658`
- reached by: Staff screen, ONLY from the 'You are not on a shop's team yet' empty state → "Join".
- **unreachable:** Only reachable by an account with NO shop — i.e. a MERCHANT_STAFF login. None of the five demo logins is a staff member, so this dialog cannot be exercised with the supplied credentials.
- states: Failure inline in red: t.staffAcceptFailed "That code did not work" or the server's own refusal

  - [ ] t.staffAcceptCode — "Enter your invite code" — ENTER submits  `TextField(autofocus, TextCapitalization.characters)`
  - [ ] t.cancel — "Cancel" — Pops  `TextButton`
  - [ ] **[destructive]** t.staffAcceptJoin — "Join" — api.acceptInvite(code) — JOINS THE SHOP. Snackbar t.staffJoined "You now work at {store}"; the host must re-resolve the membership before the roster loads  `ElevatedButton with spinner`

### MerchantSettingsScreen ("Account Settings")
*The hub: who is signed in, the language, and the doors to the six management pages plus sign-out.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/merchant_settings_screen.dart`
- reached by: Sign in → bottom nav "Settings" (tab 5). Always visible, to every role.
- covered by: apps/mobile_app/test/merchant_shell_wiring_test.dart DRIVES the Settings tab and asserts the Reconciliation row appears/hides. merchant_payout_test.dart, analytics_screen_test.dart and merchant_statement_test.dart each tap their own row and assert the pushed screen. Categories / Stock count / Staff / Notification Settings / Shop Profile / Log Out are NOT driven by any test.
- states: Profile band: a StoreMonogram avatar (no merchant avatar exists in the model) over the display name and '{t.merchbRoleOwner} • email-or-username' · Every optional row is ABSENT rather than disabled when its permission is missing; the three rows the Figma frame draws keep a Soon chip instead · Makes NO network call at all — the most deterministic screen in the suite

  - [ ] t.edit — "Edit" — Pushes SettingsScreen (account preferences)  `_EditChip — brand-tinted Material+InkWell, Semantics(button)`
  - [ ] t.merchbLangShortEn "EN" / t.merchbLangShortAr "AR" (semantic labels t.english / t.arabic) — locale.setLanguage('en'|'ar'). Takes effect under the finger — the whole screen is wrapped in AnimatedBuilder(locale)  `_LanguageToggle — a two-segment custom control, each segment Semantics(button, selected)`
  - [ ] t.merchbShopProfile — "Shop Profile" — Pushes StoreScreen. Owner-only (onShopProfile is null for employees)  `_MenuRow → YdCard.bordered + YdListRow`
  - [ ] t.navCategories — "Categories" — Pushes MerchantCategoriesScreen. Row is ABSENT without MODIFY_INVENTORY_PRICING  `_MenuRow`
  - [ ] t.invCountTitle — "Stock count" — Pushes StockCountScreen. ABSENT without MODIFY_INVENTORY_PRICING or a resolved storeId  `_MenuRow`
  - [ ] t.navStaff — "Staff" — Pushes StaffScreen. ABSENT without MANAGE_STAFF  `_MenuRow`
  - [ ] t.merchbPaymentBankDetails — "Payment & Bank details" — Pushes MerchantPayoutScreen. Owner-only; falls back to an inert YdComingSoon t.merchbSoon "Soon" chip when documents is null  `_MenuRow`
  - [ ] "Reconciliation" (MerchantStatementWords.en.title — hardcoded in the screen, NOT in the ARB) — Pushes MerchantStatementScreen. Owner-only; the row HIDES (does not say Soon) when statements is unwired  `_MenuRow`
  - [ ] t.merchbNotificationSettings — "Notification Settings" — Pushes NotificationPrefsScreen; inert with a Soon chip when prefsApi is null  `_MenuRow`
  - [ ] t.merchbShopAnalytics — "Shop Analytics" — Pushes MerchantAnalyticsScreen. Owner-only; Soon chip when aggregates is null  `_MenuRow`
  - [ ] **[destructive]** t.merchbLogOutAccount — "Log Out Account" — Confirm dialog t.signOut "Sign out" / t.signOutConfirm "You will need to sign in again to order." → onSignOut()  `_LogOutButton — brand-tinted soft destructive Material+InkWell (not an ElevatedButton)`

### MerchantPayoutScreen ("Payment & Bank details")
*Which bank account the platform holds for this shop. READ-ONLY BY DESIGN — onboarding refuses a change once an application is decided.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/merchant_payout_screen.dart`
- reached by: Settings tab → "Payment & Bank details".
- covered by: packages/delivery_merchant/test/merchant_payout_test.dart — 6 cases; DRIVES the settings-row tap ('is a live route once the host wires the client'), then mounts and asserts masking, the empty record and the never-read-a-failure-as-empty rule. The Try again button is not driven.
- states: Loading spinner · Failure: t.riderPayoutCouldNotLoad "Could not load your bank details" + Try again — deliberately NOT 'not added yet' · No record: YdEmptyState t.wizDocNotAddedYet "Not added yet" + t.merchbBankNoneFiled · Record: account holder + a MASKED IBAN ('LB •••• 1234'), a verification badge — t.payoutFormatChecked "Format checked" / t.payoutVerified "Verified" / t.payoutFailedVerification "Failed verification" — and the note t.merchbBankReadOnly · There is NO editor and no Save anywhere on this screen

  - [ ] t.back — "Back" — Pops  `YdScreenHeader onBack`
  - [ ] t.tryAgain — "Try again" — Re-issues documentsApi.myPayout()  `YdPillButton inside the problem card`

### MerchantStatementScreen ("Reconciliation")
*What the ledger says the shop is owed over a range it picks, and the orders behind it.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/merchant_statement_screen.dart`
- reached by: Settings tab → "Reconciliation". (Shipped DEAD for a while — MerchantShell did not pass StatementsApi and the row hides itself when unwired; main.dart:764 now does.)
- covered by: packages/delivery_merchant/test/merchant_statement_test.dart — 14 cases; DRIVES preset chips (Last 7 days, Last month) and asserts a new request each time, plus the settings-row tap. The date-range picker and Try again are not driven.
- states: THE LOAD-BEARING SENTENCE: _NotAPaymentNotice, an info-tinted block directly under the headline figure — 'This is what the platform's ledger records for these dates. It is not a payment. There is no payout yet…'. It must read on the FIRST PAINT of a 360dp phone · Headline is UNSIGNED with the direction spelled out in words: 'Owed to you' / 'You owe the platform' / 'Settled' / 'Unclear' · A figure the server did not send renders as an em dash, never a zero · A failed load renders NO number at all — the previous range's money is dropped, not left under the new heading · Empty range: 'No orders in these dates' + the explicit note that this is not a zero balance · Server note rendered when present; 'How it adds up' summary; 'Order by order' table (Order / Customer paid / Commission / Yours) with the settlement-date caveat · Arabic strings live IN THIS FILE (MerchantStatementWords.ar), not in delivery_l10n — the line labels themselves are the server's and arrive in English regardless

  - [ ] t.back — "Back" — Pops  `YdScreenHeader onBack`
  - [ ] "This month" / "Last month" / "Last 7 days" / "Last 30 days" (MerchantStatementWords — NOT ARB keys) — Each is a NEW REQUEST, not a client-side filter. 'Last month' ends on the last day of last month, not today  `YdChip in a horizontal SingleChildScrollView`
  - [ ] "Pick dates" (Icons.date_range_outlined) — Opens the Material range picker, floored at 365 days ago and capped at today so it cannot produce a range the server would refuse  `YdChip → showDateRangePicker`
  - [ ] t.tryAgain — "Try again" — _load()  `YdPillButton.secondary`

### MerchantAnalyticsScreen ("Shop Analytics")
*The shop's own 14-day series and the Standard/Express split the dashboard cannot show.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/merchant_analytics_screen.dart`
- reached by: Settings tab → "Shop Analytics" (owner only; aggregates must be wired or the row keeps its Soon chip).
- covered by: packages/delivery_merchant/test/analytics_screen_test.dart — 10 cases; DRIVES the settings-row tap in both directions ('the settings row that used to say Soon now leads here' / 'and keeps its chip for a host that wired no series'). Body cases are mount-and-assert.
- states: Loading spinner / error t.couldNotLoadOrdersShort + server detail + Try again / empty t.quietSoFar + t.merchAnalyticsBlurb · Three tiles: t.ordersInWindow, t.deliveredInWindow, t.merchOrderValue "Order value" with the footnote t.merchOrderValueNote — the money here is the whole customer bill, NOT a payout, and the screen says so twice · t.merchTierSplit "By delivery speed": Standard vs Express rows · A single-day series shows no comparison at all rather than an arrow pointing at nothing · Header subtitle is the window the SERVER returned (server clamps 1..30), not the 14 asked for

  - [ ] t.back — "Back" — Pops  `YdScreenHeader onBack`
  - [ ] pull-to-refresh — _load()  `RefreshIndicator over the ListView`
  - [ ] t.tryAgain — "Try again" — _load()  `YdPillButton.secondary`
  - [ ] horizontal drag on the chart — Scrolls the bars; must not take the page sideways  `SingleChildScrollView inside the card`

### StoreScreen ("Shop Configuration")
*Everything needed to get a shop listed and keep it accurate — the screen that rescues an auto-provisioned DRAFT store.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/store_screen.dart`
- reached by: Settings tab → "Shop Profile" (owner only). Portal: Merchant Hub rail → My Shop (no back arrow there).
- covered by: packages/delivery_merchant/test/store_pin_test.dart — 12 cases, 10 driving actions; DRIVES the map slot, the picker, tapping a point, Save and Remove against the pin endpoints. apps/delivery_portal/test/merchant/arabic_test.dart mounts it for RTL only. Publish/Hide, Busy, power chips, hours editing and Save Shop Settings are NOT driven by any test.
- states: Loading spinner / t.couldNotLoadYourShop + Try again / t.noShopYet "No shop yet" + t.shopCreatedAutomatically (a merchant with no products has no store yet) · A store with no hours is seeded with a default 09:00–22:00 week so Publish is one tap away · Status line reads the LISTING STATUS (t.listedOnStorefront / t.notListedYet), never availability — the two were conflated and a suspended shop read as Listed · Server refusals surface their own 'detail' on a brandDark snackbar

  - [ ] t.back — "Back" — Pops  `YdScreenHeader onBack (null in the portal)`
  - [ ] t.busy30m — "Busy 30m" — storeApi.setBusy(30) → snackbar t.markedBusy30. Self-clearing  `_ActionButton`
  - [ ] t.notBusy — "Not busy" — clearBusy() → t.noLongerBusy  `_ActionButton`
  - [ ] **[destructive]** t.publish — "Publish" — storeApi.publish(id) → t.yourShopIsLive. Refused without opening hours — the server's own detail is surfaced  `_ActionButton(primary, Icons.rocket_launch_rounded)`
  - [ ] **[destructive]** t.merchbHideShop — "Hide shop" — storeApi.suspend(id) → t.merchShopHidden. DELISTS THE SHOP  `_ActionButton(Icons.visibility_off_outlined)`
  - [ ] t.custPowerMains "Mains Power" / t.custPowerGenerator "Generator" / t.custPowerDark "Currently Dark" — declarePower(status) — one tap, shows on the customer storefront card  `YdChip row`
  - [ ] t.merchbChangeCover "Change Cover" / t.upload "Upload" — file_selector pick → uploadImage(slot:'cover')  `InkWell over the 120px cover with a scrim badge`
  - [ ] **[destructive]** t.remove — "Remove" (cover) — removeImage(slot:'cover') → snackbar t.labelRemoved  `IconButton(Icons.close) in a white circle`
  - [ ] t.merchbChangeLogo "Change Logo" / t.upload — uploadImage(slot:'logo')  `_ChipButton`
  - [ ] **[destructive]** t.remove — "Remove" (logo) — removeImage(slot:'logo')  `IconButton(Icons.close)`
  - [ ] t.shopName "Shop name" (required), t.tagline "Tagline", t.categoryLabel "Category" (StoreVertical dropdown), t.tags "Tags" (comma separated), t.descriptionLabel "Description" — Feed updateProfile on Save; name validator t.requiredField  `TextFormField ×4 + DropdownButtonFormField<StoreVertical>`
  - [ ] t.addressLabel — "Address" — Feeds updateProfile; also seeds the pin picker's search box  `borderless TextFormField inside a bordered row with a place pin`
  - [ ] map thumbnail (t.merchPinShopLocation semantics + t.addressPinnedOnMap / t.merchPinNoneYet) — Opens the pin picker sheet  `StorePinPreview — a real 100px OSM FlutterMap under an InkWell`
  - [ ] t.openingHours — "Opening hours" summary row — Expands seven editable rows. Summary reads t.merchbHoursDaily "Daily: 09:00 - 22:00", t.merchbHoursCustom or t.merchbHoursNone  `Material+InkWell, Semantics(button, label t.merchbEditHours)`
  - [ ] t.merchbDay "Day" / t.opens "Opens" / t.closes "Closes" — Edits one opening window; typed rather than a picker because seven days is fourteen dialogs  `DropdownButtonFormField<int> + two TextFormFields validated against ^([01]\\d|2[0-3]):[0-5]\\d$ (hint t.merchbTimeHint "HH:mm")`
  - [ ] **[destructive]** t.removeThisWindow — "Remove this window" (tooltip) — Drops that window from the local list (written on Save)  `IconButton(Icons.close_rounded)`
  - [ ] t.addASecondWindow — "Add a second window" — Appends a 14:00–19:00 Monday window to edit  `TextButton.icon`
  - [ ] t.minimumOrder "Minimum order", t.deliveryFeeLabelMerchant "Delivery fee", t.etaFromMin "ETA from (min)", t.etaToMin "ETA to (min)" — Feed updateCommercials on Save  `four numeric TextFormFields, validators t.aNumber "A number" / t.cannotBeNegative`
  - [ ] **[destructive]** t.merchbSaveShopSettings — "Save Shop Settings" — THREE sequential writes: updateProfile, updateCommercials, setHours → snackbar t.shopSaved "Shop saved", then a full reload  `ElevatedButton, full width 52dp, spinner`

### Store pin picker (_StorePinPicker sheet)
*Place the shop's pin and, optionally, draw the circle it delivers inside.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/store_pin_map.dart:487`
- reached by: Shop Profile → tap the map thumbnail under the address.
- covered by: packages/delivery_merchant/test/store_pin_test.dart — DRIVES opening from the slot, Save-is-inert-until-a-point, tapping a point and saving through the pin endpoint, removing a pin, and RTL. The radius switch/slider and the geocoding search are NOT driven.
- states: Tiles that will not load fall back to MapSlotPlaceholder with t.merchMapUnavailable rather than a grey grid · Hint switches between t.merchPinDropHint and t.merchPinWhyItMatters · t.noPlacesFound / t.couldNotSearchPlaces for the search box · Required OpenStreetMap attribution is drawn on the map itself

  - [ ] t.searchForAPlace — "Search for a place…" — Geocoding search; results are a tappable list that moves the camera and drops the pin  `TextField pre-filled from the address box; drawn only when a GeocodingApi was passed`
  - [ ] tap anywhere on the map — setState(_picked) — moves the pin  `FlutterMap onTap (drag / pinch / double-tap / scroll-wheel zoom enabled; ROTATION deliberately off)`
  - [ ] t.locMyLocation — "My location" — Device fix → drops the pin at the phone. Handles t.locServicesOff (+ t.locTurnOn action), t.locPermissionNeeded (+ t.locOpenSettings) and t.locNoFix  `circular Material+InkWell floated bottom-start`
  - [ ] t.merchbDeliverWithin "Deliver within N km" / t.merchbDeliveryAreaOff "No delivery limit — zones alone decide" — Turns the delivery circle on (defaults to 3.0 km) or off. Only drawn once a point exists  `Material Switch`
  - [ ] radius slider — Sizes the circle, drawn in real metres on the map  `Slider(0.5–15 km, 29 divisions)`
  - [ ] **[destructive]** t.remove — "Remove" — Pops StorePinRemoved → caller clears the radius THEN the pin → snackbar t.merchPinCleared  `_SheetButton; only when the shop already had a pin`
  - [ ] **[destructive]** t.save — "Save" — Pops StorePinPlaced → caller sets the pin THEN the radius (order is not negotiable — the server refuses a radius with no pin) → t.merchPinSaved  `_SheetButton; inert until a point is picked`

### SettingsScreen (account preferences)  — no driving test
*The signed-in person's own device preferences — shared with the customer shell, not merchant-specific.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/settings_screen.dart`
- reached by: Settings tab → the "Edit" chip on the profile band.
- states: Payment section is a pair of facts under the heading t.custPaymentMethods; the page ends with t.appTitle "YouDrop" and claims nothing else

  - [ ] t.back — "Back" — maybePop  `YdScreenHeader onBack`
  - [ ] t.custAppLanguage — "App Language" EN/AR — locale.setLanguage — the same setting as the one on the Settings tab  `AppLanguageRow — a second copy of the segmented toggle`
  - [ ] t.biometricUnlock — "Fingerprint unlock" (subtitle t.fingerprintKeepsYourAccountClosed) — Turning ON prompts a real biometric check (t.unlockWithFingerprint) before persisting. Failure paths: t.fingerprintNotSetUp / t.couldNotVerifyYou. Row hidden entirely when no biometrics are available  `YdListRow trailing a Material Switch (spinner while working)`
  - [ ] t.notifPreferences — "Notification preferences" — Pushes NotificationPrefsScreen (only when prefsApi is wired)  `YdListRow(onTap:)`
  - [ ] t.cashOnDelivery — "Cash on delivery" — Deliberately inert — a statement of fact, not a wallet  `YdListRow with an EMPTY trailing`
  - [ ] t.card — "Card" (subtitle t.paymentTestModeNote) — Inert  `YdListRow with a YdBadge t.custTestPayment "Test payment"`

### NotificationPrefsScreen  — no driving test
*Which channel reaches you for which topic.*

- file: `D:/workspace/delivery/clients/apps/mobile_app/lib/src/notifications_screen.dart:216`
- reached by: Settings tab → "Notification Settings" (direct), OR Settings tab → Edit → "Notification preferences" (two routes to the same screen).
- states: Loading spinner / t.couldNotLoadPreferences "Could not load your preferences" + Try again · A fully locked category shows t.notifAlwaysOn "Always on — account and security messages cannot be switched off" · Blurb t.notifPrefsBlurb "Choose how we reach you, topic by topic" · Channels sorted by the enum's declared order; unknown channels still shown, last

  - [ ] t.back — "Back" — maybePop  `YdScreenHeader onBack`
  - [ ] one Switch per category × channel cell — prefsApi.update([change]). LOCKED cells render disabled — the server refuses to switch account-critical messages off  `Material Switch inside a Row; the cell shows a spinner in the switch's place while saving`
  - [ ] t.tryAgain — "Try again" — _load()  `YdPillButton in the failure YdEmptyState`

### ProductListScreen ("Menu Items")  — UNREACHABLE
*The shop's own catalogue in every status, with the availability switch a merchant flips twenty times a day.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/product_list_screen.dart`
- reached by: Portal only: portal-dev.youdrop.shop → sign in backoffice-style as a merchant → Merchant Hub rail → "Products" (2nd item).
- **unreachable:** NOT REACHABLE FROM THE MOBILE MERCHANT SHELL AT ALL. MerchantShell has no Products tab (class doc lines 12-17: 'Inventory is where Products went'), so on the phone the availability switch — the one-tap publish/archive control — does not exist; a merchant must edit the product form instead.
- covered by: apps/delivery_portal/test/merchant/widget_test.dart — 10 cases; DRIVES the availability switch twice (publishing a draft, and the archive confirmation on a live product). arabic_test.dart mounts it for RTL. apps/mobile_app never mounts this screen — Inventory replaced it there.
- states: State label under the switch: t.merchbAvailable "Available" / t.draft "Draft" / t.merchbOffShelf "Off-shelf" — DRAFT keeps its own word because that is the state the merchant has to fix · Photo-count badge only when a product has more than one image · No photo: a glyph with t.noPhoto as tooltip and semantic label · Empty catalogue: t.noProductsYet + t.createYourFirstProduct · Reflows to more columns above 600dp of its own width

  - [ ] t.refresh — "Refresh" (wide only) — _reload()  `IconButton in YdScreenHeader`
  - [ ] t.merchbSearchMenuItems — "Search products..." — CLIENT-SIDE name filter of the loaded page  `YdSearchField`
  - [ ] t.all — "All" + one chip per root category — Client-side category filter  `YdChip(elevated) in a horizontal ListView`
  - [ ] product row — Pushes ProductFormScreen for that product  `YdCard.bordered(onTap:) — the whole row is the target`
  - [ ] row photo — Opens the full-size preview gallery — a SEPARATE tap target from the row  `DeliveryProductImage with its own onTap (t.openFullSizePhoto)`
  - [ ] **[destructive]** t.merchbAvailability — "Availability" (semantic label) — ON = catalogApi.publish (422 without a photo, and the reason is surfaced). OFF = catalogApi.archive behind a confirm dialog t.archiveThisProduct "Archive this product?" / t.archiveConfirm → t.archive "Archive". Reversible  `_AvailabilitySwitch — a hand-drawn 48x26 AnimatedContainer, NOT a Material Switch, Semantics(toggled:)`
  - [ ] t.merchbAddProduct — "Add Product" — Pushes an empty ProductFormScreen  `_AddProductButton — custom 44dp brand pill as the FAB`
  - [ ] t.clear — "Clear" — Clears the query and the category  `TextButton in the no-matches empty state`
  - [ ] t.tryAgain — "Try again" — _reload()  `YdPillButton.secondary`
  - [ ] pull-to-refresh (narrow) — _refresh()  `RefreshIndicator`

### WhatsAppScreen (three-column inbox)  — UNREACHABLE
*Who is waiting, what they said, and the order you are building from it — all three at once.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/whatsapp_screen.dart`
- reached by: Portal only: Merchant Hub rail → "WhatsApp" (4th item).
- **unreachable:** No route from the mobile merchant shell — WhatsAppScreen is mounted only by portal_shell.dart:227.
- covered by: apps/delivery_portal/test/merchant/whatsapp_test.dart — 13 cases; DRIVES one conversation selection (tap 'Rana'). Reply, Send, Archive and the archived toggle are NOT driven.
- states: No selection: t.selectAConversation "Pick a conversation" + blurb · Empty inbox: t.noConversations "No messages yet" + t.noConversationsBlurb · Non-text messages are NAMED rather than left blank: t.voiceNote, t.photo, t.document, t.locationPin, t.unsupportedMessage · Fixed widths: 300px list, flexible thread, 400px draft panel — no phone layout exists

  - [ ] t.refresh — "Refresh" (tooltip, list column) — Re-fetches the inbox  `IconButton`
  - [ ] t.connectedNumbers — "Connected numbers" (tooltip) — Opens _NumbersDialog  `IconButton(Icons.phone_iphone)`
  - [ ] t.showArchived "Show archived" / t.showActive "Show active" — Flips the inbox filter and CLEARS the selection  `TextButton.icon`
  - [ ] conversation row — _select(): shows the thread and marks it read (fire-and-forget)  `ListTile(selected, selectedTileColor) with an unread Badge`
  - [ ] t.typeAReply — "Write a reply" — Composes the outbound message  `TextField(minLines 1, maxLines 4), ENTER sends`
  - [ ] **[destructive]** t.sendReply — "Send" — api.reply(). Recorded either way; if !result.sent the merchant is told plainly (t.replyNotSent "Saved, but it could not be sent" or the server's failure detail)  `FilledButton`
  - [ ] **[destructive]** t.archive — "Archive" (tooltip) — api.archive(conversation) and clears the selection  `IconButton(Icons.archive_outlined) in the thread header`
  - [ ] t.refresh (thread) — Re-fetches the messages  `IconButton`

### WhatsAppDraftPanel  — UNREACHABLE
*Turning what the customer said into an order. The gap between a request and a commitment IS the feature — nothing is parsed automatically.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/whatsapp_draft_panel.dart`
- reached by: Portal → WhatsApp → select a conversation (it is the right-hand 400px column).
- **unreachable:** No route from the mobile merchant shell.
- covered by: apps/delivery_portal/test/merchant/whatsapp_test.dart 'Draft panel' group — 6 mount-and-assert cases including 'confirming stays disabled until there is an address' and 'and becomes available once the draft is placeable' (asserts onPressed nullity, does NOT tap). Nothing drives Confirm order, Discard, Add item or Save.
- states: No open draft: the blurb t.whatsappInboxBlurb + Start an order + a history list of PLACED/discarded drafts · Empty draft: t.nothingToOrderYet "Nothing added yet" + t.nothingToOrderYetBlurb · t.estimate "Estimate" is explicitly captioned t.estimateNote — 'the final total is calculated when you confirm' · Delivery fields are filled from the draft ONCE per draft id, so a half-typed address survives repaints · Failures surface the server's own words: t.thatDidNotWorkWith "That did not work: {error}"

  - [ ] t.startAnOrder — "Start an order" — api.openDraft(conversationId) — the merchant's explicit decision  `FilledButton.icon(Icons.add_shopping_cart), full width`
  - [ ] t.addItem — "Add item" — Opens _AddItemDialog  `TextButton.icon in the Products header row`
  - [ ] **[destructive]** remove line — api.removeLine(draft, line)  `IconButton(Icons.close, 18) on each draft line ListTile`
  - [ ] t.addressRequired — "We need somewhere to deliver to" (used as the address field's label) — Feeds setDelivery  `TextField(minLines 1, maxLines 3)`
  - [ ] t.phoneLabel — "Phone number" — Feeds setDelivery  `TextField, pre-filled from the customer's WhatsApp id`
  - [ ] t.orderNotes — "Notes" — Feeds setDelivery  `TextField`
  - [ ] t.save — "Save" — api.setDelivery(address, phone, notes) → snackbar t.saved  `TextButton, end-aligned`
  - [ ] **[destructive]** t.confirmOrder — "Confirm order" — Confirm dialog t.confirmOrderWarning "This places a real order and books a rider." → api.place(draft) → snackbar t.orderPlaced. DISABLED until draft.placeable — the server owns the shop-open / minimum / coverage rules  `FilledButton.icon(Icons.check), full width`
  - [ ] **[destructive]** t.discardRequest — "Discard" — api.discard(draft) → snackbar t.draftDiscarded "Discarded"  `TextButton, full width`

### _AddItemDialog (WhatsApp)  — UNREACHABLE, no driving test
*Pick a product and configure its options the same way the customer app would have asked.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/whatsapp_draft_panel.dart:432`
- reached by: Portal → WhatsApp → conversation → draft panel → "Add item".
- **unreachable:** No route from the mobile merchant shell.
- states: Empty catalogue: t.noProductsYet · Each group prints its own rule line (group.rule) under the heading

  - [ ] product row — _choose(product) — swaps to the configure step and memoises optionsFor(product)  `ListTile(title name, subtitle price) in a 460x460 list`
  - [ ] t.quantity — "Quantity" − / + — Sets qty  `two IconButtons around a count (1..99)`
  - [ ] option choices — Applies the customer app's own rules: single-choice groups swap, required groups cannot be un-answered, multi-select stops at maxSelect. Sold-out choices show t.optionSoldOut "{name} — sold out" and refuse the tap  `_ChoiceRow — radio/checkbox ICONS (not Radio/Checkbox widgets), dimmed at 0.45 when unavailable`
  - [ ] t.cancel — "Cancel" — Backs out of the configure step to the picker, or closes the dialog from the picker  `TextButton`
  - [ ] t.addToOrder — "Add to order" — Pops the choice → api.addLine(draft, productId, qty, optionIds)  `FilledButton`

### _NumbersDialog (connected WhatsApp numbers)  — UNREACHABLE, no driving test
*Which WhatsApp Business numbers route into this inbox.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/whatsapp_screen.dart:467`
- reached by: Portal → WhatsApp → the phone icon in the conversation-list header.
- **unreachable:** No route from the mobile merchant shell.
- states: Empty: t.noNumbersBlurb "Connect the WhatsApp number your customers already write to."

  - [ ] **[destructive]** t.disconnect — "Disconnect" — api.disconnectNumber(id). New messages stop arriving; existing conversations are kept (t.disconnectNumberWarning says so)  `TextButton on each number's ListTile`
  - [ ] t.numberId "WhatsApp number ID" / t.numberLabel "Label" / t.displayNumber "Phone number" — Feed connectNumber; only the id is required  `three TextFields`
  - [ ] t.cancel — "Cancel" — Closes  `TextButton`
  - [ ] **[destructive]** t.connect — "Connect" — api.connectNumber(...) then reloads the list  `FilledButton`

### DeliveryScreen ("Delivery" — who carries your orders)  — UNREACHABLE
*Choose whether the platform picks a carrier, you name one, or your own drivers carry.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/delivery_screen.dart`
- reached by: Portal only: Merchant Hub rail → "Delivery" (5th item).
- **unreachable:** No route from the mobile merchant shell — mounted only by portal_shell.dart:233.
- covered by: packages/delivery_merchant/test/delivery_screen_test.dart — 9 cases, 3 driving: 'the tapped carrier says it is working, and the others go quiet' (taps a carrier), the failure retry, and pull-to-refresh. The fallback switch and Set up my own drivers are not driven.
- states: Only ONE control is in flight at a time (_pending names the row); every other card goes inert · Failure: t.couldNotLoadCarriers "Could not load carriers: {error}" with the server detail, plus Try again — a 404 becomes t.carrierNotAvailableToYou · No fleet yet: a SoftCard with t.ownDriversBlurb and the set-up button

  - [ ] **[destructive]** t.letThePlatformChoose — "Let the platform choose" (subtitle t.whoeverIsAvailable) — api.choose(preferredProviderId: null) → snackbar t.thePlatformWillChoose  `SoftCard(onTap:, selected) with a check glyph`
  - [ ] **[destructive]** one row per carrier — the carrier's own name — api.choose(preferredProviderId: id, allowFallback:) → t.carrierWillCarry "{name} will carry your orders". A carrier that cannot take work now is still choosable and says t.notTakingWorkNow  `SoftCard(onTap:, selected)`
  - [ ] **[destructive]** t.setUpMyOwnDrivers — "Set up my own drivers" — api.myFleet() — CREATES a merchant-kind provider → t.yourFleetIsSetUp  `OutlinedButton.icon, full width on a phone`
  - [ ] **[destructive]** t.letSomeoneElseStepIn — "Let someone else step in" — choose(..., allowFallback: value) → t.anotherCarrierMayStepIn / t.onlyYourChosenCarrier. DISABLED while the platform is deciding (nothing to fall back from) — the subtitle then reads t.onlyAppliesOnceChosen  `ListTile(onTap: the whole row) carrying a Material Switch, spinner while in flight`
  - [ ] pull-to-refresh — Re-fetches available() + policy()  `RefreshIndicator (AlwaysScrollableScrollPhysics so a short page still overscrolls)`
  - [ ] t.tryAgain — "Try again" — _reload()  `OutlinedButton in the failure state`

### ZonesScreen ("Delivery areas")  — UNREACHABLE
*Where the shop delivers and what it charges to get there.*

- file: `D:/workspace/delivery/clients/packages/delivery_merchant/lib/src/zones_screen.dart`
- reached by: Portal only: Merchant Hub rail → "Delivery areas" (6th item). NOTE: a second, different ZonesScreen exists at apps/delivery_portal/lib/src/backoffice/zones_screen.dart for the Backoffice rail — same name, different page.
- **unreachable:** No route from the mobile merchant shell — mounted only by portal_shell.dart:239.
- covered by: packages/delivery_merchant/test/zones_screen_test.dart — 9 cases, 4 driving: 'the destructive action says what it does instead of hiding in a tooltip' and 'terms are edited in a sheet on a phone, not a dialog under the keyboard' both open the relevant control.
- states: No areas: banner t.noAreasBlurb + card t.flatFeeEverywhere "You charge one fee everywhere" + t.flatFeeExplanation · With areas: caution banner t.onlyTheseAreas — 'Orders from anywhere else are refused' · No shop: t.noShopYet + t.shopCreatedAutomatically, still pull-to-refreshable

  - [ ] t.addAnArea "Add an area" / t.edit "Edit" — Opens the terms form — a modal SHEET on a phone, a Dialog when wide  `_ChipButton (wide) or _WideButton (phone)`
  - [ ] **[destructive]** t.stopDelivering — "Stop delivering here" — api.dropCoverage(store, zone) → snackbar t.saved. REMOVES the area — orders from it are then refused  `_WideButton in critical red (phone) or an IconButton with the same tooltip (wide)`
  - [ ] t.feeToHere "Fee", t.minimumHere "Minimum" (hint t.usesShopMinimum), t.extraMinutes "Extra minutes" — Compose the coverage terms  `three TextFormFields in _TermsForm, validators t.aNumber / t.cannotBeNegative`
  - [ ] **[destructive]** t.save — "Save" — Writes the zone's coverage terms  `YdPillButton in the sheet/dialog`
  - [ ] t.cancel — "Cancel" — Closes without writing  `TextButton`

### Reports — NO SCREEN EXISTS  — UNREACHABLE, no driving test
*reporting-service would answer dashboard stats, a sales report, a receipts ledger, a CSV export and a backfill — no Flutter screen consumes any of it.*

- file: `D:/workspace/delivery/clients/packages/delivery_core/lib/src/api/reports_api.dart`
- reached by: Nowhere. There is no tap path from anywhere in either host.
- **unreachable:** FINDING: MerchantShell declares `final ReportsApi? reportsApi` (merchant_shell.dart:83) and main.dart:768 passes `_reportsApi` — and `_tabAt()` never reads it. No screen file in the repo references ReportsApi. The client and the wiring shipped; the UI did not. The service is also not deployed (main.dart:141).
- states: ReportsApi exposes dashboard(), sales(), ledger(), ledgerEntry(), exportCsv() and backfill(); nothing in clients/ calls any of them · The permission StorePermission.viewReports (t.staffPermViewReports "Reports" / "See sales figures and the dashboard money.") is togglable on the Staff screen and grants access to a surface that has not been built

