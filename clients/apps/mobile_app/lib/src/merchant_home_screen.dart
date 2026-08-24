import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'settings_screen.dart';

/// The shop owner's surface, on a phone.
///
/// <p>A merchant signing into the mobile app used to land in the customer storefront — the role
/// branch knew about riders and treated everything else as a shopper, so the person running the
/// shop got a basket and a browse tab and no way to see their own orders.
///
/// <p><strong>Deliberately narrow.</strong> This is not the merchant portal shrunk down. Editing a
/// catalog, uploading images and managing delivery areas are desk work and stay on the web; what a
/// merchant needs on a phone is the queue — what came in, and moving each one along. Everything
/// here is a decision that has to be made within minutes of an order arriving.
class MerchantHomeScreen extends StatefulWidget {
  const MerchantHomeScreen({
    super.key,
    required this.orderApi,
    required this.session,
    required this.locale,
    this.pendingApproval = false,
    required this.onSignOut,
  });

  final OrderApi orderApi;
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
  State<MerchantHomeScreen> createState() => _MerchantHomeScreenState();
}

class _MerchantHomeScreenState extends State<MerchantHomeScreen> {
  late Future<Paged<DeliveryOrder>> _orders = widget.orderApi.forMerchant();
  bool _acting = false;

  Future<void> _refresh() async {
    setState(() => _orders = widget.orderApi.forMerchant());
    await _orders;
  }

  /// Moves one order along and reloads.
  ///
  /// <p>Reloads rather than patching the row in place: the status a merchant sees has to be the one
  /// the server holds. An optimistic update would show PREPARING for an order the server refused,
  /// and the next action would then fail for a reason the screen had hidden.
  Future<void> _advance(DeliveryOrder order, OrderAction action) async {
    setState(() => _acting = true);
    try {
      await widget.orderApi.act(order.id, action);
      await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DeliveryStrings.of(context).orderAlreadyMovedOn)),
        );
        // Reloaded anyway: a refused action almost always means somebody else moved the order, so
        // the useful next thing is the state it is actually in.
        await _refresh();
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.merchantHome),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: t.refresh,
            onPressed: _acting ? null : _refresh,
          ),
          // Settings, on every surface rather than only the customer one. Fingerprint unlock lives
          // there, and before this a merchant or a rider had no route to it at all — the setting
          // existed and could not be reached, which reads exactly like a setting that is broken.
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: t.settings,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => SettingsScreen(
                  locale: widget.locale, userId: widget.session.subject),
            )),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: t.signOut,
            onPressed: () => widget.onSignOut(),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (widget.pendingApproval)
            Padding(
              padding: const EdgeInsets.all(DeliverySpacing.md),
              child: SoftNote(
                  icon: Icons.hourglass_top_rounded,
                  text: t.pendingBannerMerchant),
            ),
          Expanded(
            child: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<Paged<DeliveryOrder>>(
          future: _orders,
          builder: (BuildContext context, AsyncSnapshot<Paged<DeliveryOrder>> snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _Centered(
                icon: Icons.cloud_off,
                message: t.couldNotLoadOrders,
                action: TextButton(onPressed: _refresh, child: Text(t.tryAgain)),
              );
            }

            final List<DeliveryOrder> orders =
                snapshot.data?.content ?? const <DeliveryOrder>[];
            if (orders.isEmpty) {
              return _Centered(
                icon: Icons.receipt_long_outlined,
                message: t.noOrdersYetMerchant,
              );
            }

            return ListView.separated(
              // AlwaysScrollable so pull-to-refresh still works on a list too short to scroll.
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(DeliverySpacing.md),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: DeliverySpacing.sm),
              itemBuilder: (BuildContext context, int i) => _OrderCard(
                order: orders[i],
                busy: _acting,
                onAdvance: _advance,
              ),
            );
          },
        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.busy,
    required this.onAdvance,
  });

  final DeliveryOrder order;
  final bool busy;
  final Future<void> Function(DeliveryOrder, OrderAction) onAdvance;

  @override
  Widget build(BuildContext context) {
    // Exactly one action per status, and none once the order has left the shop. A merchant cannot
    // mark an order delivered — that is the rider's to say, and offering it here would let a shop
    // close an order still in a bag on a bike.
    final OrderAction? next = switch (order.status) {
      OrderStatus.placed => OrderAction.accept,
      OrderStatus.accepted => OrderAction.prepare,
      OrderStatus.preparing => OrderAction.ready,
      _ => null,
    };

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: DeliveryColors.brandSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  order.status.name.toUpperCase(),
                  style: const TextStyle(
                    color: DeliveryColors.brandDark,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              Text(order.totalAmount.toStringAsFixed(2),
                  style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: DeliverySpacing.sm),
          Text(
            order.items
                .map((OrderLine line) => '${line.qty} × ${line.productName}')
                .join(', '),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (order.deliveryAddress.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(order.deliveryAddress, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (next != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: busy ? null : () => onAdvance(order, next),
                // The action's own label, so the button and the API call cannot describe different
                // things.
                child: Text(next.label),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: <Widget>[
        const SizedBox(height: 120),
        Icon(icon, size: 48, color: DeliveryColors.muted),
        const SizedBox(height: DeliverySpacing.md),
        Text(message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium),
        if (action != null) ...<Widget>[
          const SizedBox(height: DeliverySpacing.sm),
          Center(child: action!),
        ],
      ],
    );
  }
}
