import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'rider_job_card.dart';

/// The rider's side of Butler: errands to claim, and the ones they are running.
///
/// Open and claimed sit on one screen rather than two tabs, because the list a rider is working
/// from is short and the two states are one job at different points. Claiming moves a card from the
/// top group to the bottom one, which is the whole story.
///
/// The flow stops here on purpose. Once a customer approves the price the errand becomes an
/// ordinary order, and it appears in the rider's Active tab with pick-up and deliver like anything
/// else — there is no second, parallel delivery flow to learn.
///
/// Restyled with the 2026-08 redesign to match the offer cards it now sits beside: an errand
/// reached through the Errands chip on Available should not look like it came from another app.
class RiderButlerBoard extends StatefulWidget {
  const RiderButlerBoard({super.key, required this.api});

  final ButlerApi api;

  @override
  State<RiderButlerBoard> createState() => _RiderButlerBoardState();
}

class _RiderButlerBoardState extends State<RiderButlerBoard> {
  late Future<List<List<ButlerRequest>>> _board = _load();
  String? _busyId;

  Future<List<List<ButlerRequest>>> _load() async {
    final List<Paged<ButlerRequest>> pages = await Future.wait(<Future<Paged<ButlerRequest>>>[
      widget.api.available(size: 30),
      widget.api.claimed(size: 30),
    ]);
    return <List<ButlerRequest>>[
      pages[0].content,
      // Terminal ones are dropped: a declined or cancelled errand is not work, and leaving it here
      // makes the rider's list grow forever with things they can do nothing about.
      pages[1].content.where((ButlerRequest r) => !r.status.isTerminal).toList(),
    ];
  }

  void _reload() {
    setState(() {
      _board = _load();
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

  /// The server's sentence where it has one. It is the side that knows another rider got there
  /// first, and says so precisely.
  ///
  /// Takes the strings as an argument: this is static, so there is no context to read them from.
  static String _messageFor(Object error, DeliveryStrings t) {
    if (error is DioException) {
      final dynamic body = error.response?.data;
      if (body is Map && body['detail'] is String) return body['detail'] as String;
      if (error.response?.statusCode == 409) return t.somebodyElseClaimed;
    }
    return t.thatDidNotWork;
  }

  /// Asks what the goods actually cost.
  ///
  /// A number the rider types from a receipt they are holding, so it is checked here as well as on
  /// the server: a typo becomes a price the customer is asked to approve.
  Future<void> _askPrice(ButlerRequest r) async {
    final TextEditingController cost = TextEditingController();
    final TextEditingController receipt = TextEditingController();

    final double? amount = await showDialog<double>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(DeliveryStrings.of(context).whatDidItCost),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(r.what, style: const TextStyle(fontSize: 13, color: DeliveryColors.muted)),
            if (r.budgetCap != null) ...<Widget>[
              const SizedBox(height: DeliverySpacing.xs),
              Text(DeliveryStrings.of(context).cappedAtBudget(r.budgetCap!.toStringAsFixed(2)),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: DeliverySpacing.md),
            TextField(
              controller: cost,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: DeliveryStrings.of(context).goodsTotal,
                helperText: DeliveryStrings.of(context).whatYouPaidBeforeFee,
              ),
            ),
            const SizedBox(height: DeliverySpacing.sm),
            TextField(
              controller: receipt,
              decoration: InputDecoration(labelText: DeliveryStrings.of(context).receiptNumberOptional),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(DeliveryStrings.of(context).cancel),
          ),
          ElevatedButton(
            onPressed: () {
              final double? parsed = double.tryParse(cost.text.trim());
              // Zero is refused as well as nonsense: an errand that cost nothing is a mistake, and
              // sending it would ask the customer to approve paying for goods nobody bought.
              if (parsed == null || parsed <= 0) return;
              Navigator.of(context).pop(parsed);
            },
            child: Text(DeliveryStrings.of(context).sendForApproval),
          ),
        ],
      ),
    );

    final String receiptRef = receipt.text.trim();
    cost.dispose();
    receipt.dispose();
    // The dialog is an async gap: this State can be disposed while it is open, and reading strings
    // off a dead context afterwards is the usual way that crashes.
    if (amount == null || !mounted) return;

    await _run(
      r.id,
      () => widget.api.quote(r.id,
          goodsCost: amount, receiptRef: receiptRef.isEmpty ? null : receiptRef),
      DeliveryStrings.of(context).sentForApproval,
    );
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return FutureBuilder<List<List<ButlerRequest>>>(
      future: _board,
      builder: (BuildContext context, AsyncSnapshot<List<List<ButlerRequest>>> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
        }
        if (snapshot.hasError) {
          return YdEmptyState(
            icon: Icons.shopping_basket_outlined,
            title: t.couldNotLoadErrands,
          );
        }

        final List<ButlerRequest> open = snapshot.data![0];
        final List<ButlerRequest> mine = snapshot.data![1];

        if (open.isEmpty && mine.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                const SizedBox(height: DeliverySpacing.xxl),
                YdEmptyState(
                  icon: Icons.shopping_basket_outlined,
                  title: t.noErrandsWaiting,
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              if (mine.isNotEmpty) ...<Widget>[
                _heading(t, t.yours, mine.length),
                for (final ButlerRequest r in mine) _card(t, r, claimed: true),
                const SizedBox(height: DeliverySpacing.md),
              ],
              _heading(t, t.butlerStatusOpen, open.length),
              if (open.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.md),
                  child: Text(t.nothingToClaim,
                      style: const TextStyle(color: DeliveryColors.muted, fontSize: 13)),
                )
              else
                for (final ButlerRequest r in open) _card(t, r, claimed: false),
            ],
          ),
        );
      },
    );
  }

  Widget _heading(DeliveryStrings t, String text, int count) => Padding(
        padding: const EdgeInsets.only(bottom: DeliverySpacing.md - DeliverySpacing.xs),
        child: Text(
          t.headingWithCount(text, count),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
            height: 1.3,
          ),
        ),
      );

  Widget _card(DeliveryStrings t, ButlerRequest r, {required bool claimed}) {
    final bool busy = _busyId == r.id;
    final bool buying = r.mode == ButlerMode.buy;

    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.md - DeliverySpacing.xs),
      child: YdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // The payout first, as on an offer card — an errand is a job and it is judged the
            // same way.
            Row(
              children: <Widget>[
                Text(
                  r.deliveryFee.toStringAsFixed(2),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: DeliveryAccent.positive.color,
                    height: 1.2,
                  ),
                ),
                const Spacer(),
                RiderTag(
                  label: buying ? t.buyAndBring : t.collectAndDrop,
                  color: DeliveryColors.brand,
                  background: DeliveryColors.brandSoft,
                ),
              ],
            ),
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            const RiderHairline(),
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            Text(
              r.what,
              style: const TextStyle(
                fontSize: 14,
                color: DeliveryColors.ink,
                height: 1.4,
              ),
            ),
            const SizedBox(height: DeliverySpacing.sm),
            // Both places, because the distance between them is the job.
            if (r.pickupAddress != null)
              _place(Icons.my_location_rounded, t.from, r.pickupAddress!),
            if (buying && r.sourceHint != null)
              _place(Icons.storefront_outlined, t.riderErrandTry, r.sourceHint!),
            _place(Icons.place_outlined, t.riderErrandTo, r.dropoffAddress),
            if (buying && r.budgetCap != null)
              _place(Icons.account_balance_wallet_outlined, t.riderErrandCap,
                  r.budgetCap!.toStringAsFixed(2)),
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            _action(t, r, claimed: claimed, busy: busy, buying: buying),
          ],
        ),
      ),
    );
  }

  Widget _action(DeliveryStrings t, ButlerRequest r,
      {required bool claimed, required bool busy, required bool buying}) {
    if (!claimed) {
      return SizedBox(
        width: double.infinity,
        child: RiderButton(
          label: t.claim,
          busy: busy,
          onPressed: busy
              ? null
              : () => _run(r.id, () => widget.api.claim(r.id), t.butlerStatusClaimed),
        ),
      );
    }

    return switch (r.status) {
      // A purchase needs its price before anyone can be charged. This is the button that unblocks
      // the whole errand, so it is the loud one.
      ButlerStatus.claimed when buying => SizedBox(
          width: double.infinity,
          child: RiderButton(
            label: t.reportWhatItCost,
            busy: busy,
            onPressed: busy ? null : () => _askPrice(r),
          ),
        ),
      // A pickup has no goods price to agree, so it is already approved and waiting to be run.
      ButlerStatus.claimed => _Note(
          icon: Icons.directions_bike_rounded,
          text: t.collectAndDropInstruction,
        ),
      ButlerStatus.quoted => _Note(
          icon: Icons.hourglass_bottom_rounded,
          text: t.waitingOnApprovalOf(r.payableTotal.toStringAsFixed(2)),
        ),
      ButlerStatus.approved => _Note(
          icon: Icons.check_circle_outline_rounded,
          text: t.approvedDeliverIt,
        ),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _place(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 14, color: DeliveryColors.faint),
          const SizedBox(width: DeliverySpacing.sm),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: DeliveryColors.faint,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(width: DeliverySpacing.xs),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                color: DeliveryColors.muted,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A line of standing instruction, for a state where the rider's next move is not a button here.
class _Note extends StatelessWidget {
  // Still const even though the call sites can no longer be: the text they pass is looked up at
  // runtime, which is the caller's constraint rather than this widget's.
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
      decoration: BoxDecoration(
        color: DeliveryColors.brandSoft,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: DeliveryColors.brand),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: DeliveryColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
