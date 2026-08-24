import 'dart:async';
import 'dart:math';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'settings_screen.dart';

import 'rider_butler_board.dart';
import 'rider_job_card.dart';

/// The Delivery Rider surface (Phase 2): the job board, and the rider's own deliveries.
///
/// While an order is PICKED_UP this screen reports the rider's position on a timer, which is what
/// feeds the customer's tracking card.
///
/// The layout is deliberately warmer than a list of rows. A rider reads this on a phone, outdoors,
/// usually with one hand and often with a helmet on — so the address is the largest thing on each
/// card, the action is a full-width button rather than one of several equal ones, and anything that
/// changes what happens at the door (cash to collect, above all) is a chip rather than a sentence.
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

  /// Passed through to Settings, which is reachable from here now.
  final LocaleController locale;

  /// True while the application behind this account is still being decided.
  ///
  /// The screen works either way — the server is what refuses the committing act — but saying so
  /// up front beats letting somebody build a shop and discover the refusal at the last step.
  final bool pendingApproval;
  final Future<void> Function() onSignOut;

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  static const Duration _refreshInterval = Duration(seconds: 5);

  /// Matches `delivery.tracking.rider-ping-interval-seconds` in config-repo. Every reduction here
  /// multiplies write volume on tracking_events across every active rider (Section 10).
  static const Duration _pingInterval = Duration(seconds: 10);

  Timer? _refreshTimer;
  Timer? _pingTimer;
  final Random _random = Random();

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

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: DeliveryColors.background,
        body: Column(
          children: <Widget>[
            _header(context, t),
            if (widget.pendingApproval)
              Padding(
                padding: const EdgeInsets.all(DeliverySpacing.md),
                child: SoftNote(
                    icon: Icons.hourglass_top_rounded,
                    text: t.pendingBannerRider),
              ),
            Expanded(
              child: _loading && _available.isEmpty && _assigned.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      children: <Widget>[
                        _list(
                          _available,
                          icon: Icons.inbox_rounded,
                          title: t.nothingWaitingForPickup,
                          subtitle: t.newJobsAppearHere,
                        ),
                        _list(
                          _assigned,
                          icon: Icons.delivery_dining_rounded,
                          title: t.noActiveDeliveries,
                          subtitle: t.claimOneToSeeItHere,
                        ),
                        // An approved errand becomes an ordinary order and shows up in Mine, so
                        // this board covers only the part that is not a delivery yet: claiming, and
                        // agreeing what the goods cost.
                        RiderButlerBoard(api: widget.butlerApi),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// The greeting, the day's shape, and the tabs — one brand-coloured block.
  ///
  /// It replaces a plain AppBar because the first thing a rider opening the app wants to know is
  /// whether there is work, and a title reading "Deliveries" answers a question nobody asked.
  Widget _header(BuildContext context, DeliveryStrings t) {
    final int onTheWay = _assigned
        .where((DeliveryOrder o) => o.status == OrderStatus.pickedUp)
        .length;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[DeliveryColors.brand, DeliveryColors.brandDark],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(DeliveryRadius.lg + 6)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              DeliverySpacing.md, DeliverySpacing.sm, DeliverySpacing.md, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          t.riderGreeting(widget.session.displayName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: DeliveryColors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t.riderHeaderLine,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: DeliveryColors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => SettingsScreen(
                          locale: widget.locale, userId: widget.session.subject),
                    )),
                    icon: const Icon(Icons.settings_outlined, color: DeliveryColors.white),
                    tooltip: t.settings,
                  ),
                  IconButton(
                    onPressed: widget.onSignOut,
                    icon: const Icon(Icons.logout_rounded, color: DeliveryColors.white),
                    tooltip: t.signOut,
                  ),
                ],
              ),
              const SizedBox(height: DeliverySpacing.sm + 4),
              Row(
                children: <Widget>[
                  _statPill(Icons.hourglass_bottom_rounded, t.riderWaitingCount(_available.length)),
                  const SizedBox(width: DeliverySpacing.sm),
                  _statPill(Icons.two_wheeler_rounded, t.riderOnTheWayCount(onTheWay)),
                ],
              ),
              const SizedBox(height: DeliverySpacing.sm),
              TabBar(
                indicatorColor: DeliveryColors.white,
                indicatorWeight: 3,
                labelColor: DeliveryColors.white,
                unselectedLabelColor: DeliveryColors.brandSoft,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                tabs: <Widget>[
                  Tab(text: t.availableWithCount(_available.length)),
                  Tab(text: t.mineWithCount(_assigned.length)),
                  // No count: errands load on their own timer, and a number that lags the list it
                  // labels is worse than no number.
                  Tab(text: t.errands),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A count with its meaning attached, on the header's own colour.
  Widget _statPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: DeliverySpacing.sm + 2, vertical: DeliverySpacing.xs + 2),
      decoration: BoxDecoration(
        color: DeliveryColors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: DeliveryColors.white),
          const SizedBox(width: DeliverySpacing.xs + 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: DeliveryColors.white)),
        ],
      ),
    );
  }

  Widget _list(
    List<DeliveryOrder> orders, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    if (orders.isEmpty) {
      // Still scrollable, so pull-to-refresh works on an empty board — which is exactly the board a
      // rider is most likely to pull on.
      return RefreshIndicator(
        onRefresh: () => _refresh(),
        child: ListView(
          padding: const EdgeInsets.all(DeliverySpacing.lg),
          children: <Widget>[
            const SizedBox(height: DeliverySpacing.xxl),
            // Centred explicitly: a ListView stretches its children to the full width, which would
            // turn the circle into a stadium.
            Center(
              child: Container(
                width: 84,
                height: 84,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                    color: DeliveryColors.brandSoft, shape: BoxShape.circle),
                child: Icon(icon, size: 38, color: DeliveryColors.brand),
              ),
            ),
            const SizedBox(height: DeliverySpacing.md),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: DeliveryColors.ink)),
            const SizedBox(height: DeliverySpacing.xs),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.4)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _refresh(),
      child: ListView.separated(
        padding: const EdgeInsets.all(DeliverySpacing.md),
        itemCount: orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: DeliverySpacing.sm + 4),
        itemBuilder: (BuildContext context, int i) => RiderJobCard(
          order: orders[i],
          busy: _busyId == orders[i].id,
          onAction: (OrderAction a) => _act(orders[i], a),
        ),
      ),
    );
  }
}
