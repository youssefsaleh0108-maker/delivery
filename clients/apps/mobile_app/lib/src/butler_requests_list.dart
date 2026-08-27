import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'cart.dart';
import 'order_details_screen.dart';

/// The customer's errands, and the one place a quote gets answered.
///
/// This exists because Butler has a step no catalog order has: a shopper is standing in a shop
/// having spent their own money, and the customer has to say yes or no to a number. Without a
/// surface for that answer the request simply stalls, and the shopper is left holding goods nobody
/// has agreed to pay for.
///
/// The redesign's butler page (Figma 20:4) draws only a `recent-tasks` card — a history list with
/// no decision in it. It is drawn here as designed, with the requests waiting on an answer lifted
/// out of it and into their own cards above, in the same card language. That is not decoration:
/// a quote buried three rows down a history list is a quote nobody answers.
class ButlerRequestsList extends StatefulWidget {
  const ButlerRequestsList({
    super.key,
    required this.api,
    required this.orderApi,
    required this.storeApi,
    required this.cart,
    this.version = 0,
    this.query = '',
  });

  final ButlerApi api;
  final OrderApi orderApi;
  final StoreApi storeApi;
  final Cart cart;

  /// Bumped by the form above when it submits, to reload without a manual pull.
  final int version;

  /// The butler header's search box. Filters the history in place — there is no task-search
  /// endpoint, and the list it searches is already in memory.
  final String query;

  @override
  State<ButlerRequestsList> createState() => _ButlerRequestsListState();
}

class _ButlerRequestsListState extends State<ButlerRequestsList> {
  late Future<Paged<ButlerRequest>> _page = widget.api.mine();
  String? _busyId;

  /// The history card shows a handful; "See All" opens the rest. The design draws the link and
  /// this is the only place it can lead — there is no separate task screen to route to.
  bool _expanded = false;

  static const int _collapsedCount = 4;

  @override
  void didUpdateWidget(ButlerRequestsList old) {
    super.didUpdateWidget(old);
    if (old.version != widget.version) _reload();
  }

  void _reload() {
    setState(() {
      _page = widget.api.mine();
    });
  }

  Future<void> _run(String id, Future<ButlerRequest> Function() action, String success) async {
    setState(() => _busyId = id);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_messageFor(e, DeliveryStrings.of(context)))));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// The server's sentence where there is one. It is the side that knows why a request cannot be
  /// cancelled once a shopper has paid for the goods, and says so.
  ///
  /// Takes the strings as an argument: this is static, so there is no context to read them from.
  static String _messageFor(Object error, DeliveryStrings t) {
    if (error is DioException) {
      final dynamic body = error.response?.data;
      if (body is Map && body['detail'] is String) return body['detail'] as String;
    }
    return t.thatDidNotWork;
  }

  bool _matches(ButlerRequest r) {
    final String q = widget.query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return r.what.toLowerCase().contains(q) ||
        (r.sourceHint ?? '').toLowerCase().contains(q) ||
        (r.pickupAddress ?? '').toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return FutureBuilder<Paged<ButlerRequest>>(
      future: _page,
      builder: (BuildContext context, AsyncSnapshot<Paged<ButlerRequest>> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(DeliverySpacing.lg),
            child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(DeliverySpacing.md),
            child: Text(t.couldNotLoadErrands,
                style: const TextStyle(color: DeliveryColors.muted, fontSize: 13)),
          );
        }

        final List<ButlerRequest> all =
            snapshot.data!.content.where(_matches).toList(growable: false);

        // Anything waiting on an answer first, in its own card; the rest is history.
        final List<ButlerRequest> waiting =
            all.where((ButlerRequest r) => r.awaitingApproval).toList();
        final List<ButlerRequest> history =
            all.where((ButlerRequest r) => !r.awaitingApproval).toList();

        if (all.isEmpty) {
          // A search that matched nothing is worth saying; an account with no errands at all is
          // not — the form above it is the whole answer.
          return widget.query.trim().isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.all(DeliverySpacing.md),
                  child: Text(t.custNoTasksMatch,
                      style: const TextStyle(color: DeliveryColors.muted, fontSize: 13)),
                );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final ButlerRequest r in waiting) ...<Widget>[
              _quoteCard(r),
              const SizedBox(height: DeliverySpacing.md),
            ],
            if (history.isNotEmpty) _historyCard(history),
          ],
        );
      },
    );
  }

  /// A request waiting on the customer, in the design's selected-card treatment — the brand tint
  /// with a brand hairline, which is exactly how the frame marks the thing you are being asked to
  /// choose.
  Widget _quoteCard(ButlerRequest r) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool busy = _busyId == r.id;

    return Container(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
      decoration: BoxDecoration(
        color: DeliveryColors.brandSoft,
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
        border: Border.all(color: DeliveryColors.brand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _iconChip(r, background: DeliveryColors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  r.what,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              YdBadge.brand(label: t.custWaitingOnYou, uppercase: false, fontSize: 11),
            ],
          ),
          const SizedBox(height: DeliverySpacing.sm),
          Text(
            _lineFor(r),
            style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.35),
          ),
          if (r.overBudget) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            Text(
              t.aboveYourCap(r.budgetCap!.toStringAsFixed(2)),
              style: const TextStyle(
                  fontSize: 12, color: DeliveryColors.brand, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: DeliverySpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: YdPillButton.secondary(
                  label: t.noThanks,
                  size: YdPillButtonSize.compact,
                  busy: busy,
                  onPressed: busy
                      ? null
                      : () => _run(r.id, () => widget.api.decline(r.id), t.declined),
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              Expanded(
                child: YdPillButton(
                  label: t.payAmount(r.payableTotal.toStringAsFixed(2)),
                  size: YdPillButtonSize.compact,
                  busy: busy,
                  onPressed: busy
                      ? null
                      : () => _run(
                          r.id, () => widget.api.approve(r.id), t.approvedOnItsWay),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// `recent-tasks`: a bordered white card, a heading with a text action, and the rows.
  Widget _historyCard(List<ButlerRequest> history) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool truncated = history.length > _collapsedCount;
    final List<ButlerRequest> shown =
        _expanded || !truncated ? history : history.take(_collapsedCount).toList();

    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          YdSectionHeader(
            title: t.custRecentTasks,
            actionLabel: truncated ? (_expanded ? t.custShowLess : t.custSeeAll) : null,
            onAction: truncated ? () => setState(() => _expanded = !_expanded) : null,
          ),
          const SizedBox(height: DeliverySpacing.md - 4),
          for (int i = 0; i < shown.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: 10),
            _taskRow(shown[i]),
          ],
        ],
      ),
    );
  }

  /// `task-item`: the round icon chip, the title over its detail line, and the status word.
  Widget _taskRow(ButlerRequest r) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool busy = _busyId == r.id;
    final bool cancellable =
        r.status == ButlerStatus.requested || r.status == ButlerStatus.claimed;
    final (String label, Color colour) = _statusOf(r);

    return InkWell(
      // Once approved it is an ordinary order, and the ordinary order screen is where it belongs —
      // tracking, status and receipt all already work there.
      onTap: r.orderId == null
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => OrderDetailsScreen(
                  orderId: r.orderId!,
                  orderApi: widget.orderApi,
                  storeApi: widget.storeApi,
                  cart: widget.cart,
                ),
              )),
      borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _iconChip(r, background: DeliveryColors.background),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  r.what,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                // The frame puts a timestamp here. The status sentence carries the money as well
                // as the moment, and on a list of four rows that is the more useful of the two.
                Text(
                  _lineFor(r),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: DeliveryColors.faint, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: colour),
              ),
              if (cancellable)
                InkWell(
                  onTap: busy
                      ? null
                      : () => _run(r.id, () => widget.api.cancel(r.id), t.cancelled),
                  borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(top: 2),
                    child: Text(
                      t.cancel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: DeliveryColors.brand,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconChip(ButlerRequest r, {required Color background}) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(
        r.mode == ButlerMode.buy ? Icons.shopping_cart_outlined : Icons.inventory_2_outlined,
        size: 18,
        color: DeliveryColors.brand,
      ),
    );
  }

  String _lineFor(ButlerRequest r) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return switch (r.status) {
      ButlerStatus.requested => t.waitingForShopper(_money(r.deliveryFee)),
      ButlerStatus.claimed => r.mode == ButlerMode.buy
          ? t.shopperIsOnIt
          : t.riderOnTheWayToCollect(_money(r.payableTotal)),
      ButlerStatus.quoted => t.goodsPlusFee(
          _money(r.goodsCost ?? 0), _money(r.deliveryFee), _money(r.payableTotal)),
      ButlerStatus.approved => t.agreedAt(_money(r.payableTotal)),
      ButlerStatus.declined => t.youDeclinedThisPrice,
      ButlerStatus.cancelled => t.cancelled,
      ButlerStatus.expired => t.nobodyPickedThisUp,
    };
  }

  static String _money(double value) => value.toStringAsFixed(2);

  /// The design colour-codes the status word green for finished and rose for outstanding; the
  /// states that are neither take the faint neutral rather than borrowing one of those meanings.
  (String, Color) _statusOf(ButlerRequest r) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return switch (r.status) {
      ButlerStatus.requested => (t.custStatusPending, DeliveryAccent.caution.color),
      ButlerStatus.claimed => (t.butlerStatusClaimed, DeliveryAccent.caution.color),
      ButlerStatus.quoted => (t.butlerStatusYourCall, DeliveryColors.brand),
      ButlerStatus.approved => (t.butlerStatusAgreed, DeliveryAccent.positive.color),
      ButlerStatus.declined => (t.declined, DeliveryColors.faint),
      ButlerStatus.cancelled => (t.cancelled, DeliveryColors.faint),
      ButlerStatus.expired => (t.butlerStatusExpired, DeliveryColors.faint),
    };
  }
}
