import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// The rider's side of Butler: errands to claim, and the ones they are running.
///
/// Open and claimed sit on one screen rather than two tabs, because the list a rider is working
/// from is short and the two states are one job at different points. Claiming moves a card from the
/// top group to the bottom one, which is the whole story.
///
/// The flow stops here on purpose. Once a customer approves the price the errand becomes an
/// ordinary order, and it appears in the rider's Deliveries tab with pick-up and deliver like
/// anything else — there is no second, parallel delivery flow to learn.
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
    return FutureBuilder<List<List<ButlerRequest>>>(
      future: _board,
      builder: (BuildContext context, AsyncSnapshot<List<List<ButlerRequest>>> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(DeliverySpacing.lg),
              child: Text(DeliveryStrings.of(context).couldNotLoadErrands,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: DeliveryColors.muted)),
            ),
          );
        }

        final List<ButlerRequest> open = snapshot.data![0];
        final List<ButlerRequest> mine = snapshot.data![1];

        if (open.isEmpty && mine.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              children: <Widget>[
                SizedBox(height: MediaQuery.sizeOf(context).height * 0.3),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(DeliverySpacing.lg),
                    child: Text(DeliveryStrings.of(context).noErrandsWaiting,
                        style: const TextStyle(color: DeliveryColors.muted)),
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(DeliverySpacing.md),
            children: <Widget>[
              if (mine.isNotEmpty) ...<Widget>[
                _heading(DeliveryStrings.of(context).yours, mine.length),
                for (final ButlerRequest r in mine) _card(r, claimed: true),
                const SizedBox(height: DeliverySpacing.md),
              ],
              _heading(DeliveryStrings.of(context).butlerStatusOpen, open.length),
              if (open.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.md),
                  child: Text(DeliveryStrings.of(context).nothingToClaim,
                      style: const TextStyle(color: DeliveryColors.muted, fontSize: 13)),
                )
              else
                for (final ButlerRequest r in open) _card(r, claimed: false),
            ],
          ),
        );
      },
    );
  }

  Widget _heading(String text, int count) => Padding(
        padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
        child: Text(DeliveryStrings.of(context).headingWithCount(text, count),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      );

  Widget _card(ButlerRequest r, {required bool claimed}) {
    final bool busy = _busyId == r.id;
    final bool buying = r.mode == ButlerMode.buy;

    return Container(
      margin: const EdgeInsets.only(bottom: DeliverySpacing.sm),
      padding: const EdgeInsets.all(DeliverySpacing.md),
      decoration: BoxDecoration(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        boxShadow: DeliveryShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(buying ? Icons.shopping_basket_outlined : Icons.local_shipping_outlined,
                  size: 18, color: DeliveryColors.brand),
              const SizedBox(width: DeliverySpacing.xs + 2),
              Expanded(
                child: Text(buying ? DeliveryStrings.of(context).buyAndBring : DeliveryStrings.of(context).collectAndDrop,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              ),
              Text('+${r.deliveryFee.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14, color: DeliveryColors.brand)),
            ],
          ),
          const SizedBox(height: DeliverySpacing.xs),
          Text(r.what, style: const TextStyle(fontSize: 14, height: 1.3)),
          const SizedBox(height: DeliverySpacing.xs),
          // Both places, because the distance between them is the job.
          if (r.pickupAddress != null)
            _place(Icons.my_location_rounded, DeliveryStrings.of(context).from, r.pickupAddress!),
          if (buying && r.sourceHint != null)
            _place(Icons.storefront_outlined, 'Try', r.sourceHint!),
          _place(Icons.place_outlined, 'To', r.dropoffAddress),
          if (buying && r.budgetCap != null)
            _place(Icons.account_balance_wallet_outlined, 'Cap',
                r.budgetCap!.toStringAsFixed(2)),
          const SizedBox(height: DeliverySpacing.sm),
          _action(r, claimed: claimed, busy: busy, buying: buying),
        ],
      ),
    );
  }

  Widget _action(ButlerRequest r,
      {required bool claimed, required bool busy, required bool buying}) {
    if (!claimed) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: busy ? null : () => _run(r.id, () => widget.api.claim(r.id), DeliveryStrings.of(context).butlerStatusClaimed),
          style: FilledButton.styleFrom(backgroundColor: DeliveryColors.brand),
          child: Text(DeliveryStrings.of(context).claim),
        ),
      );
    }

    return switch (r.status) {
      // A purchase needs its price before anyone can be charged. This is the button that unblocks
      // the whole errand, so it is the loud one.
      ButlerStatus.claimed when buying => SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: busy ? null : () => _askPrice(r),
            style: FilledButton.styleFrom(backgroundColor: DeliveryColors.brand),
            child: Text(DeliveryStrings.of(context).reportWhatItCost),
          ),
        ),
      // A pickup has no goods price to agree, so it is already approved and waiting to be run.
      ButlerStatus.claimed => _Note(
          icon: Icons.directions_bike_rounded,
          text: DeliveryStrings.of(context).collectAndDropInstruction,
        ),
      ButlerStatus.quoted => _Note(
          icon: Icons.hourglass_bottom_rounded,
          text: DeliveryStrings.of(context).waitingOnApprovalOf(r.payableTotal.toStringAsFixed(2)),
        ),
      ButlerStatus.approved => _Note(
          icon: Icons.check_circle_outline_rounded,
          text: DeliveryStrings.of(context).approvedDeliverIt,
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
          Icon(icon, size: 14, color: DeliveryColors.muted),
          const SizedBox(width: DeliverySpacing.xs + 2),
          Text('$label ',
              style: const TextStyle(
                  fontSize: 12, color: DeliveryColors.muted, fontWeight: FontWeight.w600)),
          Expanded(
            child: Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, height: 1.3)),
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
      padding: const EdgeInsets.all(DeliverySpacing.sm + 2),
      decoration: BoxDecoration(
        color: DeliveryColors.brandSoft,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: DeliveryColors.brand),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12.5, height: 1.3, color: DeliveryColors.ink)),
          ),
        ],
      ),
    );
  }
}
