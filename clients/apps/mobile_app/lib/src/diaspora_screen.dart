import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'address_sheet.dart';
import 'cart.dart';
import 'delivery_address.dart';

/// Send to Lebanon (Figma `diaspora-gift-order` 80:133): pick who receives it, attach a note,
/// and start shopping with THEIR address active.
///
/// What this v1 honestly is: a flow over machinery the platform already trusts. The recipient is
/// a saved address (the label is their name), the personal note rides the order's notes to the
/// door, and "recent deliveries" are this account's orders to that address. Paying with a foreign
/// card is the part that does not exist yet — checkout still offers the platform's methods — so
/// this screen promises the delivery, not a card rail it does not have.
class DiasporaScreen extends StatefulWidget {
  const DiasporaScreen({
    super.key,
    required this.addresses,
    required this.orderApi,
    required this.cart,
    required this.zoneApi,
    required this.onStartOrder,
  });

  final DeliveryAddressStore addresses;
  final OrderApi orderApi;
  final Cart cart;
  final DeliveryZoneApi zoneApi;

  /// Called after the recipient is active and the note is stored — the shell lands the customer
  /// on the home tab to pick the goods.
  final VoidCallback onStartOrder;

  @override
  State<DiasporaScreen> createState() => _DiasporaScreenState();
}

class _DiasporaScreenState extends State<DiasporaScreen> {
  final TextEditingController _note = TextEditingController();

  DeliveryAddress? _recipient;
  List<DeliveryOrder> _recent = const <DeliveryOrder>[];

  @override
  void initState() {
    super.initState();
    _recipient = widget.addresses.selected;
    _note.text = widget.cart.giftNote ?? '';
    _loadRecent();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final Paged<DeliveryOrder> page = await widget.orderApi.mine(size: 30);
      if (!mounted) return;
      setState(() => _recent = page.content);
    } catch (_) {
      // The section stays empty.
    }
  }

  List<DeliveryOrder> get _recentToRecipient {
    final DeliveryAddress? recipient = _recipient;
    if (recipient == null) return const <DeliveryOrder>[];
    return _recent
        .where((DeliveryOrder o) => o.deliveryAddress == recipient.line)
        .take(3)
        .toList();
  }

  Future<void> _pickRecipient() async {
    await showAddressSheet(context, widget.addresses, zoneApi: widget.zoneApi);
    if (!mounted) return;
    setState(() => _recipient = widget.addresses.selected);
  }

  Future<void> _start() async {
    final DeliveryAddress? recipient = _recipient;
    if (recipient == null) {
      await _pickRecipient();
      if (_recipient == null) return;
    }
    // Their address becomes the active one — the whole storefront now shops for their door.
    await widget.addresses.select(_recipient!);
    widget.cart.giftNote = _note.text.trim().isEmpty ? null : _note.text.trim();
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onStartOrder();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final DeliveryAddress? recipient = _recipient;

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(
        title: t.custDiasporaTitle,
        onBack: () => Navigator.of(context).maybePop(),
        backSemanticLabel: t.back,
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(DeliverySpacing.md),
              children: <Widget>[
                // The promise banner.
                Container(
                  padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
                  decoration: BoxDecoration(
                    color: DeliveryColors.white,
                    borderRadius: BorderRadius.circular(DeliveryRadius.md),
                    border: Border.all(color: DeliveryColors.borderFaint),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(Icons.favorite_rounded,
                          size: 22, color: DeliveryColors.brand),
                      const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              t.custDiasporaBanner,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: DeliveryColors.ink,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              t.custDiasporaBlurb,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: DeliveryColors.muted,
                                  height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: DeliverySpacing.lg),
                // The recipient card.
                YdCard.bordered(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              t.custFamilyRecipient.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: DeliveryColors.faint,
                                letterSpacing: 0.6,
                                height: 1.2,
                              ),
                            ),
                          ),
                          Semantics(
                            button: true,
                            child: InkWell(
                              onTap: _pickRecipient,
                              borderRadius:
                                  BorderRadius.circular(DeliveryRadius.sm),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  const Icon(Icons.edit_outlined,
                                      size: 13, color: DeliveryColors.brand),
                                  const SizedBox(width: 4),
                                  Text(
                                    t.edit,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: DeliveryColors.brand,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: DeliverySpacing.md),
                      if (recipient == null)
                        Text(
                          t.custNoRecipientYet,
                          style: const TextStyle(
                              fontSize: 13,
                              color: DeliveryColors.muted,
                              height: 1.45),
                        )
                      else
                        Row(
                          children: <Widget>[
                            StoreMonogram(
                                name: recipient.label ?? recipient.line,
                                size: 44,
                                radius: 22),
                            const SizedBox(
                                width: DeliverySpacing.md - DeliverySpacing.xs),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    recipient.label ?? recipient.line,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: DeliveryColors.ink,
                                      height: 1.25,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    recipient.line,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        color: DeliveryColors.muted,
                                        height: 1.35),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: DeliverySpacing.md),
                      const Divider(height: 1, color: DeliveryColors.borderFaint),
                      const SizedBox(height: DeliverySpacing.md),
                      Text(
                        t.custPersonalNote,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: DeliveryColors.muted,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: DeliverySpacing.sm),
                      TextField(
                        controller: _note,
                        maxLines: 3,
                        maxLength: 240,
                        decoration: InputDecoration(
                          hintText: '"${t.custPersonalNoteHint}"',
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.custGiftNoteRides,
                        style: const TextStyle(
                            fontSize: 11,
                            color: DeliveryColors.faint,
                            height: 1.3),
                      ),
                    ],
                  ),
                ),
                if (_recentToRecipient.isNotEmpty) ...<Widget>[
                  const SizedBox(height: DeliverySpacing.lg),
                  Text(
                    t.custRecentDeliveriesTo(
                        recipient!.label ?? recipient.line),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: DeliveryColors.ink,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: DeliverySpacing.sm),
                  for (final DeliveryOrder order in _recentToRecipient)
                    Padding(
                      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
                      child: YdCard.bordered(
                        child: Row(
                          children: <Widget>[
                            Icon(Icons.check_circle_rounded,
                                size: 20,
                                color: DeliveryAccent.positive.color),
                            const SizedBox(
                                width: DeliverySpacing.md - DeliverySpacing.xs),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    order.storeName ?? t.tabShop,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: DeliveryColors.ink,
                                      height: 1.25,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${order.status.labelIn(t)} · \$${order.totalAmount.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: DeliveryColors.muted,
                                        height: 1.3),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          // The CTA, pinned the way the frame pins it.
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(DeliverySpacing.md),
              child: YdPillButton(
                label: t.custStartOrder,
                onPressed: _start,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
