import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// Turning what the customer said into an order.
///
/// The whole design of this feature is the gap this panel represents. The message on the left is a
/// request; this is the merchant's reading of it; only "Confirm order" makes it a commitment. Every
/// step here is one a merchant can get wrong and fix, which is why none of it happens automatically:
/// a mis-parsed quantity is money, and the person who pays for it is the customer.
class WhatsAppDraftPanel extends StatefulWidget {
  const WhatsAppDraftPanel({
    super.key,
    required this.api,
    required this.catalogApi,
    required this.conversation,
    required this.onPlaced,
  });

  final WhatsAppApi api;
  final CatalogApi catalogApi;
  final WhatsAppConversation conversation;
  final VoidCallback onPlaced;

  @override
  State<WhatsAppDraftPanel> createState() => _WhatsAppDraftPanelState();
}

class _WhatsAppDraftPanelState extends State<WhatsAppDraftPanel> {
  late Future<List<DraftOrder>> _drafts = widget.api.draftsFor(widget.conversation.id);
  final TextEditingController _address = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  bool _busy = false;

  /// Which draft the delivery fields currently hold, so they are filled once rather than on every
  /// rebuild — otherwise a merchant's half-typed address is wiped by the next repaint.
  String? _fieldsFor;

  @override
  void dispose() {
    _address.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
        _drafts = widget.api.draftsFor(widget.conversation.id);
      });

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final DeliveryStrings t = DeliveryStrings.of(context);
    try {
      await action();
      _reload();
      if (!mounted || success == null) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.thatDidNotWorkWith(_reason(e)))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The server's own words, not a stack trace.
  ///
  /// The refusals that reach here are the ones a merchant can act on — "Choose Size" needs a
  /// selection, the shop is closed, the basket is under its minimum. Showing a Dio exception
  /// instead would leave them with nothing to change while a customer waits.
  String _reason(Object error) {
    if (error is DioException) {
      final Object? data = error.response?.data;
      if (data is Map && data['message'] is String) return data['message'] as String;
      if (data is Map && data['detail'] is String) return data['detail'] as String;
    }
    return '$error';
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return FutureBuilder<List<DraftOrder>>(
      future: _drafts,
      builder: (BuildContext context, AsyncSnapshot<List<DraftOrder>> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
        }
        final List<DraftOrder> drafts = snapshot.data ?? const <DraftOrder>[];
        final DraftOrder? open = drafts.where((DraftOrder d) => d.isOpen).firstOrNull;

        if (open == null) {
          return _StartPanel(
            history: drafts,
            busy: _busy,
            onStart: () => _run(() => widget.api
                .openDraft(widget.conversation.id)
                .then((_) {})),
          );
        }

        // Fill the delivery fields from the draft the first time this particular draft is shown.
        if (_fieldsFor != open.id) {
          _fieldsFor = open.id;
          _address.text = open.deliveryAddress ?? '';
          _phone.text = open.contactPhone ?? widget.conversation.customerWaId;
          _notes.text = open.notes ?? '';
        }

        return _DraftEditor(
          draft: open,
          busy: _busy,
          address: _address,
          phone: _phone,
          notes: _notes,
          onAddItem: () => _addItem(open),
          onRemoveLine: (DraftLine line) =>
              _run(() => widget.api.removeLine(open.id, line.id).then((_) {})),
          onSaveDelivery: () => _run(
            () => widget.api
                .setDelivery(open.id,
                    deliveryAddress: _address.text.trim(),
                    contactPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
                    notes: _notes.text.trim().isEmpty ? null : _notes.text.trim())
                .then((_) {}),
            success: t.saved,
          ),
          onPlace: () => _confirm(open),
          onDiscard: () => _run(
            () => widget.api.discard(open.id).then((_) {}),
            success: t.draftDiscarded,
          ),
        );
      },
    );
  }

  Future<void> _confirm(DraftOrder draft) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    // The one step that costs money, so it asks. Everything before this is reversible.
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(t.confirmOrder),
        content: Text(t.confirmOrderWarning),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.confirmOrder),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    await _run(() => widget.api.place(draft.id).then((_) {}), success: t.orderPlaced);
    widget.onPlaced();
  }

  Future<void> _addItem(DraftOrder draft) async {
    final _Chosen? chosen = await showDialog<_Chosen>(
      context: context,
      builder: (BuildContext context) =>
          _AddItemDialog(api: widget.api, catalogApi: widget.catalogApi),
    );
    if (chosen == null || !mounted) return;

    await _run(() => widget.api
        .addLine(draft.id,
            productId: chosen.productId, qty: chosen.qty, optionIds: chosen.optionIds)
        .then((_) {}));
  }
}

// ---------------------------------------------------------------------------- no draft yet

class _StartPanel extends StatelessWidget {
  const _StartPanel({required this.history, required this.busy, required this.onStart});

  final List<DraftOrder> history;
  final bool busy;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return ListView(
      padding: const EdgeInsets.all(DeliverySpacing.md),
      children: <Widget>[
        SoftNote(
          // Stated here rather than assumed: a merchant coming from a competitor's product may
          // expect the platform to have read the message and built the order already.
          text: t.whatsappInboxBlurb,
        ),
        const SizedBox(height: DeliverySpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: busy ? null : onStart,
            icon: const Icon(Icons.add_shopping_cart),
            label: Text(t.startAnOrder),
          ),
        ),
        if (history.isNotEmpty) ...<Widget>[
          const SizedBox(height: DeliverySpacing.lg),
          SectionLabel(t.navOrders),
          ...history.map((DraftOrder d) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  d.status == 'PLACED' ? Icons.check_circle_outline : Icons.cancel_outlined,
                  color: d.status == 'PLACED' ? DeliveryColors.brand : DeliveryColors.muted,
                ),
                title: Text(d.status == 'PLACED' ? t.orderPlaced : t.draftDiscarded),
                subtitle: Text(
                  d.lines.map((DraftLine l) => '${l.qty}× ${l.productName}').join(', '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              )),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------- building the order

class _DraftEditor extends StatelessWidget {
  const _DraftEditor({
    required this.draft,
    required this.busy,
    required this.address,
    required this.phone,
    required this.notes,
    required this.onAddItem,
    required this.onRemoveLine,
    required this.onSaveDelivery,
    required this.onPlace,
    required this.onDiscard,
  });

  final DraftOrder draft;
  final bool busy;
  final TextEditingController address;
  final TextEditingController phone;
  final TextEditingController notes;
  final VoidCallback onAddItem;
  final ValueChanged<DraftLine> onRemoveLine;
  final VoidCallback onSaveDelivery;
  final VoidCallback onPlace;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return ListView(
      padding: const EdgeInsets.all(DeliverySpacing.md),
      children: <Widget>[
        if (draft.requestText != null && draft.requestText!.trim().isNotEmpty) ...<Widget>[
          SectionLabel(t.theRequest),
          SoftCard(child: Text(draft.requestText!)),
          const SizedBox(height: DeliverySpacing.md),
        ],
        Row(
          children: <Widget>[
            Expanded(child: SectionLabel(t.navProducts)),
            TextButton.icon(
              onPressed: busy ? null : onAddItem,
              icon: const Icon(Icons.add, size: 18),
              label: Text(t.addItem),
            ),
          ],
        ),
        if (draft.lines.isEmpty)
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(t.nothingToOrderYet, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: DeliverySpacing.xs),
                Text(t.nothingToOrderYetBlurb, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          )
        else
          ...draft.lines.map((DraftLine line) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${line.qty}× ${line.productName}'),
                subtitle: line.optionsSummary.isEmpty ? null : Text(line.optionsSummary),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(line.lineTotal.toStringAsFixed(2)),
                    IconButton(
                      onPressed: busy ? null : () => onRemoveLine(line),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              )),
        const SizedBox(height: DeliverySpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(t.estimate, style: Theme.of(context).textTheme.titleSmall),
            Text(draft.estimatedSubtotal.toStringAsFixed(2),
                style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
        // Said plainly, because a merchant reading a number back to a customer needs to know it is
        // not a promise. The catalog prices the real order at the moment it is confirmed.
        Text(t.estimateNote, style: Theme.of(context).textTheme.bodySmall),

        const SizedBox(height: DeliverySpacing.lg),
        SectionLabel(t.deliveryDetails),
        TextField(
          controller: address,
          decoration: InputDecoration(labelText: t.addressRequired),
          minLines: 1,
          maxLines: 3,
        ),
        const SizedBox(height: DeliverySpacing.sm),
        TextField(
          controller: phone,
          decoration: InputDecoration(labelText: t.phoneLabel),
        ),
        const SizedBox(height: DeliverySpacing.sm),
        TextField(
          controller: notes,
          decoration: InputDecoration(labelText: t.orderNotes),
        ),
        const SizedBox(height: DeliverySpacing.sm),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(onPressed: busy ? null : onSaveDelivery, child: Text(t.save)),
        ),

        const SizedBox(height: DeliverySpacing.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            // Disabled until there is something to send and somewhere to send it. Everything else —
            // the shop being open, the basket clearing its minimum, the area being served — is
            // checked by Order Manager, and duplicating those rules here would mean two places to
            // keep in step and one of them quietly wrong.
            onPressed: busy || !draft.placeable ? null : onPlace,
            icon: const Icon(Icons.check),
            label: Text(t.confirmOrder),
          ),
        ),
        const SizedBox(height: DeliverySpacing.sm),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: busy ? null : onDiscard,
            child: Text(t.discardRequest),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------- picking an item

class _Chosen {
  const _Chosen({required this.productId, required this.qty, required this.optionIds});

  final String productId;
  final int qty;
  final List<String> optionIds;
}

/// One option, shown the way the customer app shows it.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.choice,
    required this.group,
    required this.selected,
    required this.onTap,
  });

  final ProductOptionChoice choice;
  final OptionGroup group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final IconData icon = group.singleChoice
        ? (selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded)
        : (selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded);

    return Opacity(
      opacity: choice.available ? 1 : 0.45,
      child: InkWell(
        onTap: choice.available ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.xs),
          child: Row(
            children: <Widget>[
              Icon(icon,
                  size: 20, color: selected ? DeliveryColors.brand : DeliveryColors.muted),
              const SizedBox(width: DeliverySpacing.sm),
              Expanded(
                child: Text(
                  choice.available
                      ? choice.name
                      : DeliveryStrings.of(context).optionSoldOut(choice.name),
                ),
              ),
              if (choice.deltaLabel.isNotEmpty)
                Text(choice.deltaLabel, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddItemDialog extends StatefulWidget {
  const _AddItemDialog({required this.api, required this.catalogApi});

  final WhatsAppApi api;
  final CatalogApi catalogApi;

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  late final Future<Paged<Product>> _products = widget.catalogApi.myProducts(size: 100);
  Product? _product;
  Future<List<OptionGroup>>? _options;
  final Map<String, Set<String>> _picked = <String, Set<String>>{};
  int _qty = 1;

  void _choose(Product product) {
    setState(() {
      _product = product;
      _picked.clear();
      _qty = 1;
      // Memoised against the chosen product, not built inside build(): a Future created during a
      // rebuild fires a fresh request on every repaint.
      _options = widget.api.optionsFor(product.id);
    });
  }

  List<String> get _optionIds =>
      _picked.values.expand((Set<String> ids) => ids).toList(growable: false);

  /// The same selection rules the customer app applies, so a merchant taking the order by hand
  /// cannot build a combination the app would have refused.
  void _toggle(OptionGroup group, ProductOptionChoice choice) {
    setState(() {
      final Set<String> ids = _picked.putIfAbsent(group.id, () => <String>{});
      if (group.singleChoice) {
        // Re-tapping the chosen option in a *required* group keeps it — otherwise the merchant can
        // leave a mandatory question unanswered by mistake and only find out at placement.
        if (ids.contains(choice.id) && !group.required) {
          ids.clear();
        } else {
          ids
            ..clear()
            ..add(choice.id);
        }
      } else if (ids.contains(choice.id)) {
        ids.remove(choice.id);
      } else if (ids.length < group.maxSelect) {
        ids.add(choice.id);
      }
      // At the limit, the tap does nothing. The rule is already stated under the group heading.
    });
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return AlertDialog(
      title: Text(_product == null ? t.addItem : _product!.name),
      content: SizedBox(
        width: 460,
        height: 460,
        child: _product == null ? _picker(t) : _configure(t),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => _product == null
              ? Navigator.of(context).pop()
              : setState(() => _product = null),
          child: Text(t.cancel),
        ),
        if (_product != null)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_Chosen(
              productId: _product!.id,
              qty: _qty,
              optionIds: _optionIds,
            )),
            child: Text(t.addToOrder),
          ),
      ],
    );
  }

  Widget _picker(DeliveryStrings t) {
    return FutureBuilder<Paged<Product>>(
      future: _products,
      builder: (BuildContext context, AsyncSnapshot<Paged<Product>> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
        }
        final List<Product> products = snapshot.data?.content ?? const <Product>[];
        if (products.isEmpty) {
          return Center(child: Text(t.noProductsYet));
        }
        return ListView.builder(
          itemCount: products.length,
          itemBuilder: (BuildContext context, int i) => ListTile(
            title: Text(products[i].name),
            subtitle: Text(products[i].price.toStringAsFixed(2)),
            onTap: () => _choose(products[i]),
          ),
        );
      },
    );
  }

  Widget _configure(DeliveryStrings t) {
    return FutureBuilder<List<OptionGroup>>(
      future: _options,
      builder: (BuildContext context, AsyncSnapshot<List<OptionGroup>> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
        }
        final List<OptionGroup> groups = snapshot.data ?? const <OptionGroup>[];
        return ListView(
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(t.quantity)),
                IconButton(
                  onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                  icon: const Icon(Icons.remove),
                ),
                Text('$_qty'),
                IconButton(
                  onPressed: _qty < 99 ? () => setState(() => _qty++) : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            for (final OptionGroup group in groups) ...<Widget>[
              const Divider(),
              SectionLabel(group.name),
              // The rule the customer app shows too, so the merchant answers the same question the
              // customer would have been asked.
              Text(group.rule, style: Theme.of(context).textTheme.bodySmall),
              // Icons rather than Radio/Checkbox widgets, matching the customer app's option sheet:
              // Material's Radio API is mid-migration to RadioGroup, which this SDK does not have
              // yet, and the icon form renders identically without depending on either.
              for (final ProductOptionChoice choice in group.options)
                _ChoiceRow(
                  choice: choice,
                  group: group,
                  selected: _picked[group.id]?.contains(choice.id) ?? false,
                  onTap: () => _toggle(group, choice),
                ),
            ],
          ],
        );
      },
    );
  }
}
