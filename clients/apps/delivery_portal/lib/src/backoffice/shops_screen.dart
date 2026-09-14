import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import '../shell/shell.dart';
import 'services_admin_parts.dart';

/// Back office's Shops page: the shops listed on the storefront, goods or services, and the one thing
/// back office decides about a shop here — whether it carries the Verified Local badge.
///
/// A page of its own because nothing else in back office can reach a shop. The badge is set with
/// `PUT /api/stores/{id}/verified-local`, which needs a store's id, and no back-office page had one: the
/// Merchants Directory lists applications, and a merchant's application never names a store —
/// product-service opens the shop with the merchant's first product, so onboarding provisions nothing
/// for a merchant to point at. The storefront's own browse is the one list of shops back office can
/// read, and it carries each shop's badge.
///
/// So the page lists listed shops only, and says so. A draft or suspended shop is left out because the
/// server shows it to nobody but its owner, and a badge on it would show nobody anything until it
/// publishes.
///
/// Every change asks first. The badge is YouDrop's own claim to a shop's neighbours, and for a service
/// provider it is the "verified" mark on their page (owner default 17), so a mis-click is not cheap.
/// What the switch shows after a change is what the server stored, not what was asked for.
class ShopsScreen extends StatefulWidget {
  const ShopsScreen({super.key, required this.api, this.notificationApi});

  final StoreApi api;

  /// The operator's own inbox, behind the header's bell. Optional, as on the orders ledger.
  final NotificationApi? notificationApi;

  @override
  State<ShopsScreen> createState() => _ShopsScreenState();
}

class _ShopsScreenState extends State<ShopsScreen> {
  static const int _pageSize = 20;

  /// How long typing pauses before the search is sent: one request per word, not per letter.
  static const Duration _typingPause = Duration(milliseconds: 400);

  final TextEditingController _search = TextEditingController();
  Timer? _typing;

  /// False lists every goods shop — what the storefront lists when no vertical is named. True lists
  /// service shops, in the categories the server has open.
  bool _services = false;
  int _page = 0;

  Paged<StoreCard>? _result;
  Object? _error;
  bool _loading = true;

  /// Bumped by every read, so an older answer is dropped rather than drawn over a newer one.
  int _asked = 0;

  /// The badge as the server stored it on this page, by shop — until the next read says otherwise.
  final Map<String, bool> _stored = <String, bool>{};

  String? _busyId;

  /// What the last change came to.
  ({String text, bool good})? _outcome;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _typing?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final int asked = ++_asked;
    if (!_loading) setState(() => _loading = true);
    final String text = _search.text.trim();
    try {
      final Paged<StoreCard> page = await widget.api.browse(
        vertical: _services ? StoreVertical.services : null,
        search: text.isEmpty ? null : text,
        page: _page,
        size: _pageSize,
      );
      if (!mounted || asked != _asked) return;
      setState(() {
        _result = page;
        _error = null;
        _loading = false;
        // A fresh read is the server's word on every badge it lists.
        for (final StoreCard shop in page.content) {
          _stored.remove(shop.id);
        }
      });
    } catch (e) {
      if (!mounted || asked != _asked) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _typed(String _) {
    _typing?.cancel();
    _typing = Timer(_typingPause, () {
      setState(() => _page = 0);
      unawaited(_load());
    });
  }

  void _goTo(int page) {
    setState(() => _page = page);
    unawaited(_load());
  }

  Future<void> _change(StoreCard shop, bool verified) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext dialog) => AlertDialog(
            backgroundColor: DeliveryColors.white,
            title: Text(
              verified ? t.svcBoVerifyGrantTitle(shop.name) : t.svcBoVerifyRevokeTitle(shop.name),
              style: ConsoleText.cardTitle,
            ),
            content: SizedBox(
              width: 440,
              child: Text(
                verified ? t.svcBoVerifyGrantBody : t.svcBoVerifyRevokeBody,
                style: ConsoleText.body,
              ),
            ),
            actions: <Widget>[
              ConsoleButton(
                label: t.cancel,
                tone: ConsoleButtonTone.outlined,
                onPressed: () => Navigator.of(dialog).pop(false),
              ),
              ConsoleButton(
                label: verified ? t.svcBoVerifyGrant : t.svcBoVerifyRevoke,
                tone: verified ? ConsoleButtonTone.solid : ConsoleButtonTone.destructive,
                onPressed: () => Navigator.of(dialog).pop(true),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() {
      _busyId = shop.id;
      _outcome = null;
    });
    try {
      final Store stored = await widget.api.setVerifiedLocal(shop.id, verified: verified);
      if (!mounted) return;
      setState(() {
        _stored[shop.id] = stored.verifiedLocal;
        _busyId = null;
        _outcome = (
          text: stored.verifiedLocal
              ? t.svcBoVerifyGranted(shop.name)
              : t.svcBoVerifyRevoked(shop.name),
          good: true,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busyId = null;
        _outcome = (
          text: switch (refusalStatus(e)) {
            403 => t.svcBoVerifyRefused,
            404 => t.svcBoVerifyGone,
            _ => t.svcBoVerifyFailed,
          },
          good: false,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final ({String text, bool good})? outcome = _outcome;

    return ConsolePage(
      header: ConsoleTopbar(
        title: t.svcBoShopsTitle,
        subtitle: t.svcBoShopsSubtitle,
        actions: <Widget>[
          ConsoleBell(api: widget.notificationApi),
          ConsoleIconAction(
            icon: Icons.refresh,
            tooltip: t.refresh,
            onPressed: () => unawaited(_load()),
          ),
        ],
      ),
      children: <Widget>[
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: ConsoleMetrics.pageGap,
          runSpacing: DeliverySpacing.md - DeliverySpacing.xs,
          children: <Widget>[
            ConsoleFilterTabs(
              tabs: <ConsoleFilterTab>[
                ConsoleFilterTab(label: t.svcBoShopsGoods),
                ConsoleFilterTab(label: t.svcBoShopsServices),
              ],
              selectedIndex: _services ? 1 : 0,
              onSelected: (int i) {
                setState(() {
                  _services = i == 1;
                  _page = 0;
                });
                unawaited(_load());
              },
            ),
            ConsoleSearchField(
              hintText: t.svcBoShopsSearchHint,
              controller: _search,
              width: 272,
              onChanged: _typed,
            ),
          ],
        ),
        if (outcome != null)
          ServicesNote(
            text: outcome.text,
            icon: outcome.good ? Icons.check_circle_outline : Icons.error_outline,
            accent: outcome.good ? DeliveryAccent.positive : DeliveryAccent.critical,
          ),
        _body(t),
      ],
    );
  }

  Widget _body(DeliveryStrings t) {
    if (_error != null) {
      return ServicesStateCard(
        icon: Icons.error_outline,
        text: t.svcBoShopsLoadFailed,
        action: ConsoleButton(
          label: t.tryAgain,
          tone: ConsoleButtonTone.outlined,
          onPressed: () => unawaited(_load()),
        ),
      );
    }
    final Paged<StoreCard>? result = _result;
    if (result == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: DeliverySpacing.xxl),
        child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
      );
    }

    return ConsoleTable(
      minWidth: 760,
      title: Text(t.svcBoShopsListedOnly, style: ConsoleText.meta),
      columns: <ConsoleColumn>[
        ConsoleColumn(label: t.svcBoColShop, flex: 2),
        ConsoleColumn(label: t.svcBoDetailKind, width: 240),
        ConsoleColumn(label: t.custVerifiedLocal, width: 160),
      ],
      empty: Text(t.svcBoShopsEmpty, style: ConsoleText.cellMuted),
      footer: result.content.isEmpty ? null : _pager(t, result),
      rows: <ConsoleTableRow>[
        for (final StoreCard shop in result.content)
          ConsoleTableRow(
            cells: <Widget>[
              ConsoleNameCell(
                name: shop.name,
                secondary: shop.tagline,
                leading: ConsoleInitialTile(label: shop.name),
              ),
              Text(_kindOf(t, shop), overflow: TextOverflow.ellipsis, style: ConsoleText.cellMuted),
              _badge(t, shop),
            ],
          ),
      ],
    );
  }

  Widget _badge(DeliveryStrings t, StoreCard shop) {
    if (_busyId == shop.id) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.brand),
      );
    }
    return Tooltip(
      message: t.svcBoVerifiedToggle(shop.name),
      child: Switch(
        value: _stored[shop.id] ?? shop.verifiedLocal,
        // One change at a time: a second confirmation over a change still in flight could be read
        // against a badge that is about to move.
        onChanged: _busyId != null ? null : (bool verified) => unawaited(_change(shop, verified)),
      ),
    );
  }

  Widget _pager(DeliveryStrings t, Paged<StoreCard> result) {
    final int pages = result.totalPages < 1 ? 1 : result.totalPages;
    return Row(
      children: <Widget>[
        Expanded(child: Text(t.svcBoPageOf(result.page + 1, pages), style: ConsoleText.meta)),
        ConsoleButton(
          label: t.previous,
          tone: ConsoleButtonTone.outlined,
          onPressed: result.page > 0 && !_loading ? () => _goTo(result.page - 1) : null,
        ),
        const SizedBox(width: DeliverySpacing.sm),
        ConsoleButton(
          label: t.next,
          tone: ConsoleButtonTone.outlined,
          onPressed: result.page + 1 < pages && !_loading ? () => _goTo(result.page + 1) : null,
        ),
      ],
    );
  }

  static String _kindOf(DeliveryStrings t, StoreCard shop) {
    if (shop.vertical != StoreVertical.services) return shop.vertical.labelIn(t);
    final ServiceCategory? category = shop.serviceCategory;
    return category == null ? t.svcBoServiceTag : t.svcBoKindServiceIn(category.labelIn(t));
  }
}
