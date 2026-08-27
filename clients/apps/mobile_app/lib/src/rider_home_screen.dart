import 'dart:async';
import 'dart:math';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'rider_butler_board.dart';
import 'rider_earnings_screen.dart';
import 'rider_job_card.dart';
import 'rider_order_detail_screen.dart';
import 'rider_settings_widgets.dart';
import 'settings_screen.dart';

/// The Delivery Rider surface — the four-tab shell of the 2026-08 Figma redesign.
///
/// Frames 3:1163 (Available), 3:1255 (Active), 3:1486 (Earnings) and 3:1591 (Settings) are one
/// app with one bottom bar, so they are one widget here: the tabs share the poll that keeps the
/// board fresh, and a job claimed on Available appears on Active without a second round trip.
///
/// While an order is PICKED_UP this screen reports the rider's position on a timer, which is what
/// feeds the customer's tracking card. That, the 5-second refresh and the action wiring are older
/// than the redesign and are carried through it unchanged — the restyle happens around them.
///
/// The design has no home for the errands board, which is a live feature: a customer can raise a
/// Butler request right now and a rider has to be able to claim it. So Available carries a
/// two-chip segmented toggle, in the design's own chip language, and Errands lives behind it
/// rather than being dropped.
class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({
    super.key,
    required this.api,
    required this.butlerApi,
    required this.session,
    required this.locale,
    this.pendingApproval = false,
    required this.onSignOut,
  });

  final OrderApi api;
  final ButlerApi butlerApi;
  final AuthSession session;

  /// Passed through to Settings, which is a tab of its own now.
  final LocaleController locale;

  /// True while the application behind this account is still being decided.
  ///
  /// The screen works either way — the server is what refuses the committing act — but saying so
  /// up front beats letting somebody read the board and discover the refusal at the last step.
  final bool pendingApproval;
  final Future<void> Function() onSignOut;

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

/// What the Available tab is showing. Deliveries and errands are two boards, not two filters.
enum _Board { deliveries, errands }

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  static const Duration _refreshInterval = Duration(seconds: 5);

  /// Matches `delivery.tracking.rider-ping-interval-seconds` in config-repo. Every reduction here
  /// multiplies write volume on tracking_events across every active rider (Section 10).
  static const Duration _pingInterval = Duration(seconds: 10);

  Timer? _refreshTimer;
  Timer? _pingTimer;
  final Random _random = Random();

  int _tab = 0;
  _Board _board = _Board.deliveries;

  List<DeliveryOrder> _available = <DeliveryOrder>[];
  List<DeliveryOrder> _assigned = <DeliveryOrder>[];
  bool _loading = true;
  String? _busyId;

  /// Simulated position, walked slightly on each ping.
  ///
  /// Real GPS needs a location plugin and a runtime permission prompt, which is a Phase 5 concern.
  /// What matters now is that the tracking pipeline carries real, changing coordinates end to end.
  double _lat = 51.5074;
  double _lng = -0.1278;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _refresh(silent: true));
    _pingTimer = Timer.periodic(_pingInterval, (_) => _pingActiveDeliveries());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _pingTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final List<Paged<DeliveryOrder>> results = await Future.wait(<Future<Paged<DeliveryOrder>>>[
        widget.api.available(size: 30),
        widget.api.assigned(size: 30),
      ]);
      if (!mounted) return;
      setState(() {
        _available = results[0].content;
        _assigned = results[1].content
            .where((DeliveryOrder o) => !o.status.isTerminal)
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _pingActiveDeliveries() async {
    final List<DeliveryOrder> inTransit =
        _assigned.where((DeliveryOrder o) => o.status == OrderStatus.pickedUp).toList();
    if (inTransit.isEmpty) return;

    // Drift by roughly a street's width so the customer's view visibly changes.
    _lat += (_random.nextDouble() - 0.5) * 0.002;
    _lng += (_random.nextDouble() - 0.5) * 0.002;

    for (final DeliveryOrder order in inTransit) {
      try {
        await widget.api.ping(order.id, _lat, _lng, accuracyM: 8);
      } catch (_) {
        // A dropped ping is replaced by the next one; never surface it to the rider.
      }
    }
  }

  Future<void> _act(DeliveryOrder order, OrderAction action) async {
    setState(() => _busyId = order.id);
    try {
      await widget.api.act(order.id, action);
      await _refresh(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DeliveryStrings.of(context).actionOnOrder(action.labelIn(DeliveryStrings.of(context)), order.shortId))),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      // 422 on a claim is the expected race: another rider got there first.
      final String message = switch (e.response?.statusCode) {
        422 when action == OrderAction.claim => DeliveryStrings.of(context).anotherRiderClaimedIt,
        422 => DeliveryStrings.of(context).orderAlreadyMovedOn,
        _ => DeliveryStrings.of(context).actionFailed(action.labelIn(DeliveryStrings.of(context)).toLowerCase()),
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      await _refresh(silent: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// A claim taken from Available belongs on Active, so the tab follows the job.
  Future<void> _claimAndFollow(DeliveryOrder order, OrderAction action) async {
    await _act(order, action);
    if (!mounted || action != OrderAction.claim) return;
    setState(() => _tab = 1);
  }

  void _openDetail(DeliveryOrder order) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RiderOrderDetailScreen(
        order: order,
        onAction: (OrderAction action) => _act(order, action),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: SafeArea(
        bottom: false,
        child: switch (_tab) {
          0 => _availableTab(t),
          1 => _activeTab(t),
          2 => RiderEarningsScreen(api: widget.api),
          _ => _settingsTab(t),
        },
      ),
      bottomNavigationBar: YdBottomNav(
        currentIndex: _tab,
        onTap: (int i) => setState(() => _tab = i),
        items: <YdBottomNavItem>[
          YdBottomNavItem(
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded,
            label: t.riderTabAvailable,
          ),
          YdBottomNavItem(
            icon: Icons.assignment_outlined,
            activeIcon: Icons.assignment_rounded,
            label: t.riderTabActive,
          ),
          YdBottomNavItem(
            icon: Icons.trending_up_rounded,
            label: t.riderTabEarnings,
          ),
          YdBottomNavItem(
            icon: Icons.settings_outlined,
            activeIcon: Icons.settings_rounded,
            label: t.settings,
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ available

  Widget _availableTab(DeliveryStrings t) {
    return Column(
      children: <Widget>[
        _regionBar(t),
        _mapSlot(t),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Row(
            children: <Widget>[
              YdChip(
                label: t.riderSegmentDeliveries,
                selected: _board == _Board.deliveries,
                onTap: () => setState(() => _board = _Board.deliveries),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              YdChip(
                label: t.errands,
                selected: _board == _Board.errands,
                onTap: () => setState(() => _board = _Board.errands),
              ),
            ],
          ),
        ),
        if (widget.pendingApproval)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, DeliverySpacing.md, 20, 0),
            child: SoftNote(
                icon: Icons.hourglass_top_rounded, text: t.pendingBannerRider),
          ),
        Expanded(
          child: _board == _Board.errands
              // An approved errand becomes an ordinary order and shows up in Active, so this board
              // covers only the part that is not a delivery yet: claiming, and agreeing what the
              // goods cost.
              ? RiderButlerBoard(api: widget.butlerApi)
              : _offers(t),
        ),
      ],
    );
  }

  /// The white `region-selector` bar.
  ///
  /// The design's chevron opens a zone picker. A rider's account carries no zone preference and the
  /// board is not filtered by one — every approved rider sees every ready order — so there is
  /// nothing here to choose between yet. The row is drawn as designed and says so, rather than
  /// offering a menu that would change nothing.
  Widget _regionBar(DeliveryStrings t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: DeliverySpacing.lg,
        vertical: DeliverySpacing.md - DeliverySpacing.xs,
      ),
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.place_outlined, size: 20, color: DeliveryColors.brand),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  t.riderRegionZone,
                  style: const TextStyle(
                    fontSize: 11,
                    color: DeliveryColors.faint,
                    height: 1.3,
                  ),
                ),
                Text(
                  t.appTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          YdComingSoon(label: t.riderComingSoon),
        ],
      ),
    );
  }

  /// The 160px `regional-mini-map`, painted as a placeholder surface.
  ///
  /// No entity on this platform carries coordinates — the rider's own position is a random walk
  /// from a hard-coded origin — so there is nothing to draw a map from. It keeps its exact designed
  /// height and its dark overlay pill, and the pill carries a real number: how many orders are
  /// waiting on the board right now.
  Widget _mapSlot(DeliveryStrings t) {
    return SizedBox(
      height: 160,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned.fill(
            child: CustomPaint(
              painter: _MapGridPainter(),
              child: const SizedBox.expand(),
            ),
          ),
          for (final Alignment where in const <Alignment>[
            Alignment(-0.62, -0.45),
            Alignment(0.48, -0.6),
            Alignment(-0.3, 0.55),
            Alignment(0.66, 0.4),
          ])
            Align(
              alignment: where,
              child: Icon(
                Icons.place,
                size: 16,
                color: DeliveryColors.brand.withValues(alpha: 0.35),
              ),
            ),
          Container(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: DeliverySpacing.md - DeliverySpacing.xs,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: DeliveryColors.shellDeep,
              borderRadius: BorderRadius.circular(DeliveryRadius.pill),
            ),
            child: Text(
              t.riderDeliveriesNearby(_available.length),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.white,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _offers(DeliveryStrings t) {
    if (_loading && _available.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
    }

    return RefreshIndicator(
      onRefresh: () => _refresh(),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            t.riderOffersNearYou,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
              height: 1.3,
            ),
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          if (_available.isEmpty)
            YdEmptyState(
              icon: Icons.inbox_rounded,
              title: t.nothingWaitingForPickup,
              message: t.newJobsAppearHere,
            )
          else
            for (final DeliveryOrder order in _available)
              Padding(
                padding: const EdgeInsets.only(
                    bottom: DeliverySpacing.md - DeliverySpacing.xs),
                child: RiderJobCard(
                  order: order,
                  busy: _busyId == order.id,
                  onAction: (OrderAction a) => _claimAndFollow(order, a),
                ),
              ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------- active

  Widget _activeTab(DeliveryStrings t) {
    return Column(
      children: <Widget>[
        _screenHeader(
          title: t.riderMyActiveTasks,
          trailing: Text(
            t.riderActiveCount(_assigned.length),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.brand,
            ),
          ),
        ),
        Expanded(
          child: _loading && _assigned.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(color: DeliveryColors.brand))
              : RefreshIndicator(
                  onRefresh: () => _refresh(),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: <Widget>[
                      if (_assigned.isEmpty)
                        YdEmptyState(
                          icon: Icons.two_wheeler_rounded,
                          title: t.noActiveDeliveries,
                          message: t.claimOneToSeeItHere,
                        )
                      else
                        for (final DeliveryOrder order in _assigned)
                          Padding(
                            padding: const EdgeInsets.only(
                                bottom: DeliverySpacing.md),
                            child: RiderTaskCard(
                              order: order,
                              onOpen: () => _openDetail(order),
                            ),
                          ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------- settings

  Widget _settingsTab(DeliveryStrings t) {
    return AnimatedBuilder(
      animation: widget.locale,
      builder: (BuildContext context, _) => Column(
        children: <Widget>[
          _screenHeader(title: t.riderDriverSettings),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                RiderProfileCard(name: widget.session.displayName),
                const SizedBox(height: DeliverySpacing.md),
                const RiderDutyToggleCard(),
                const SizedBox(height: DeliverySpacing.md),
                // The language itself is set on the shared settings screen, which is also where
                // fingerprint unlock lives. Two places to change one setting is one too many, so
                // this row shows the answer and opens the page that owns the question.
                RiderLanguageRow(
                  value: widget.locale.isArabic ? 'العربية' : 'English',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => SettingsScreen(
                      locale: widget.locale,
                      userId: widget.session.subject,
                    ),
                  )),
                ),
                const SizedBox(height: DeliverySpacing.md),
                RiderPreferencesGroup(
                  rows: <RiderPreference>[
                    // Document upload, payout details, per-rider notification preferences and live
                    // chat are all new capabilities with no backend behind them yet.
                    RiderPreference(
                      icon: Icons.folder_outlined,
                      label: t.riderDocuments,
                      inert: true,
                    ),
                    RiderPreference(
                      icon: Icons.credit_card_outlined,
                      label: t.riderBankDetails,
                      inert: true,
                    ),
                    RiderPreference(
                      icon: Icons.notifications_outlined,
                      label: t.riderNotificationPreferences,
                      inert: true,
                    ),
                    RiderPreference(
                      icon: Icons.help_outline_rounded,
                      label: t.riderHelpAndSupport,
                      inert: true,
                    ),
                  ],
                ),
                const SizedBox(height: DeliverySpacing.md),
                RiderLogOutButton(onPressed: widget.onSignOut),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------- parts

  /// The redesign's 56px white screen header: title hard against the start edge, an optional
  /// accent-coloured fact against the end edge.
  ///
  /// Deliberately not [YdScreenHeader], which centres its title as soon as it is given a trailing
  /// widget. These rider frames keep the title left and the count right.
  Widget _screenHeader({required String title, Widget? trailing}) {
    return Container(
      height: 56,
      width: double.infinity,
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: DeliverySpacing.lg),
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: DeliveryColors.ink,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}

/// The map placeholder's ruled backdrop.
///
/// Not a decorative flourish: it is what stops a flat grey rectangle reading as a failed image
/// load. Drawn in the border token at a low contrast so it stays behind the pill overlay.
class _MapGridPainter extends CustomPainter {
  static const double _cell = 28;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = DeliveryColors.background,
    );

    final Paint line = Paint()
      ..color = DeliveryColors.border
      ..strokeWidth = 1;

    for (double x = _cell; x < size.width; x += _cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (double y = _cell; y < size.height; y += _cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(_MapGridPainter oldDelegate) => false;
}
