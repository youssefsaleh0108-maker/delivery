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
/// Quoted requests are pulled to the top for that reason — everything else here is history, and
/// only these are waiting on the person reading the screen.
class ButlerRequestsList extends StatefulWidget {
  const ButlerRequestsList({
    super.key,
    required this.api,
    required this.orderApi,
    required this.storeApi,
    required this.cart,
    this.version = 0,
  });

  final ButlerApi api;
  final OrderApi orderApi;
  final StoreApi storeApi;
  final Cart cart;

  /// Bumped by the form above when it submits, to reload without a manual pull.
  final int version;

  @override
  State<ButlerRequestsList> createState() => _ButlerRequestsListState();
}

class _ButlerRequestsListState extends State<ButlerRequestsList> {
  late Future<Paged<ButlerRequest>> _page = widget.api.mine();
  String? _busyId;

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

  @override
  Widget build(BuildContext context) {
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
            child: Text(DeliveryStrings.of(context).couldNotLoadErrands,
                style: const TextStyle(color: DeliveryColors.muted)),
          );
        }

        final List<ButlerRequest> all = snapshot.data!.content;
        if (all.isEmpty) return const SizedBox.shrink();

        // Anything waiting on an answer first; the rest in the order it came back.
        final List<ButlerRequest> sorted = <ButlerRequest>[
          ...all.where((ButlerRequest r) => r.awaitingApproval),
          ...all.where((ButlerRequest r) => !r.awaitingApproval),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: DeliverySpacing.lg),
            Text(DeliveryStrings.of(context).yourErrands,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: DeliverySpacing.sm),
            for (final ButlerRequest request in sorted) _card(request),
          ],
        );
      },
    );
  }

  Widget _card(ButlerRequest r) {
    final bool busy = _busyId == r.id;
    final bool decide = r.awaitingApproval;

    return Container(
      margin: const EdgeInsets.only(bottom: DeliverySpacing.sm),
      padding: const EdgeInsets.all(DeliverySpacing.md),
      decoration: BoxDecoration(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        // A request waiting on the customer is ringed, because it is the only one that needs them.
        border: Border.all(
          color: decide ? DeliveryColors.brand : DeliveryColors.border,
          width: decide ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                  r.mode == ButlerMode.buy
                      ? Icons.shopping_basket_outlined
                      : Icons.local_shipping_outlined,
                  size: 18,
                  color: DeliveryColors.brand),
              const SizedBox(width: DeliverySpacing.xs + 2),
              Expanded(
                child: Text(r.what,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              _statusChip(r),
            ],
          ),
          const SizedBox(height: DeliverySpacing.xs),
          Text(_lineFor(r),
              style: const TextStyle(fontSize: 12.5, color: DeliveryColors.muted, height: 1.3)),
          if (decide) ...<Widget>[
            if (r.overBudget) ...<Widget>[
              const SizedBox(height: DeliverySpacing.xs),
              Text(
                DeliveryStrings.of(context).aboveYourCap(r.budgetCap!.toStringAsFixed(2)),
                style: const TextStyle(
                    fontSize: 12.5, color: DeliveryColors.brand, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: DeliverySpacing.sm),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => _run(r.id, () => widget.api.decline(r.id), DeliveryStrings.of(context).declined),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DeliveryColors.brand,
                      side: const BorderSide(color: DeliveryColors.brandLine),
                    ),
                    child: Text(DeliveryStrings.of(context).noThanks),
                  ),
                ),
                const SizedBox(width: DeliverySpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: busy
                        ? null
                        : () => _run(r.id, () => widget.api.approve(r.id),
                            DeliveryStrings.of(context).approvedOnItsWay),
                    style: FilledButton.styleFrom(backgroundColor: DeliveryColors.brand),
                    child: Text(DeliveryStrings.of(context).payAmount(r.payableTotal.toStringAsFixed(2))),
                  ),
                ),
              ],
            ),
          ] else if (r.status == ButlerStatus.requested ||
              r.status == ButlerStatus.claimed) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: busy ? null : () => _run(r.id, () => widget.api.cancel(r.id), DeliveryStrings.of(context).cancelled),
                child: Text(DeliveryStrings.of(context).cancel),
              ),
            ),
          ] else if (r.orderId != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              // Once approved it is an ordinary order, and the ordinary order screen is where it
              // belongs — tracking, status and receipt all already work there.
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => OrderDetailsScreen(
                    orderId: r.orderId!,
                    orderApi: widget.orderApi,
                    storeApi: widget.storeApi,
                    cart: widget.cart,
                  ),
                )),
                child: Text(DeliveryStrings.of(context).trackIt),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _lineFor(ButlerRequest r) {
    return switch (r.status) {
      ButlerStatus.requested => DeliveryStrings.of(context).waitingForShopper(_money(r.deliveryFee)),
      ButlerStatus.claimed => r.mode == ButlerMode.buy
          ? DeliveryStrings.of(context).shopperIsOnIt
          : DeliveryStrings.of(context).riderOnTheWayToCollect(_money(r.payableTotal)),
      ButlerStatus.quoted =>
        DeliveryStrings.of(context).goodsPlusFee(_money(r.goodsCost ?? 0), _money(r.deliveryFee), _money(r.payableTotal)),
      ButlerStatus.approved => DeliveryStrings.of(context).agreedAt(_money(r.payableTotal)),
      ButlerStatus.declined => DeliveryStrings.of(context).youDeclinedThisPrice,
      ButlerStatus.cancelled => DeliveryStrings.of(context).cancelled,
      ButlerStatus.expired => DeliveryStrings.of(context).nobodyPickedThisUp,
    };
  }

  static String _money(double value) => value.toStringAsFixed(2);

  Widget _statusChip(ButlerRequest r) {
    final (String label, Color colour) = switch (r.status) {
      ButlerStatus.requested => (DeliveryStrings.of(context).butlerStatusOpen, DeliveryColors.muted),
      ButlerStatus.claimed => (DeliveryStrings.of(context).butlerStatusClaimed, DeliveryStoreState.busy.color),
      ButlerStatus.quoted => (DeliveryStrings.of(context).butlerStatusYourCall, DeliveryColors.brand),
      ButlerStatus.approved => (DeliveryStrings.of(context).butlerStatusAgreed, DeliveryStoreState.open.color),
      ButlerStatus.declined => (DeliveryStrings.of(context).declined, DeliveryColors.muted),
      ButlerStatus.cancelled => (DeliveryStrings.of(context).cancelled, DeliveryColors.muted),
      ButlerStatus.expired => (DeliveryStrings.of(context).butlerStatusExpired, DeliveryColors.muted),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: colour)),
    );
  }
}
