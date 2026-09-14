import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shell/shell.dart';
import 'services_admin_parts.dart';

/// The longest reason the server keeps: product-service `Product.MAX_TAKEDOWN_REASON_LENGTH`, checked
/// with `@Size` and Java's `String.length()`, which count UTF-16 code units, not the characters a
/// person sees: an emoji is one character and two units. The reason field counts and stops in those
/// units ([_Utf16LengthLimit]), so a reason is never refused for its length after it was typed.
const int _maxReason = 500;

/// Back office's Service offers page: every service shop's offers, in every status, and the one thing
/// back office does to an offer — take it down, or restore it — with a reason, and the trail of both.
///
/// The list is the server's, filtered and paged by the server: status (taken down included), category,
/// shop and text. A row opens the offer beside the list — its shop, terms, price, photos and status —
/// with Take down or Restore, and its moderation history.
///
/// Every act asks for a reason first and cannot be sent without one: the server records the reason with
/// the staff member in the same transaction as the act, and a take-down's reason is what the provider
/// reads on their offer. A refusal is said as what it is — already down, changed under the act, gone —
/// and the list is read again, so what stays on screen is the server's.
class ServiceOffersScreen extends StatefulWidget {
  const ServiceOffersScreen({super.key, required this.api, this.notificationApi});

  final BackofficeCatalogApi api;

  /// The operator's own inbox, behind the header's bell. Optional, as on the orders ledger.
  final NotificationApi? notificationApi;

  @override
  State<ServiceOffersScreen> createState() => _ServiceOffersScreenState();
}

class _ServiceOffersScreenState extends State<ServiceOffersScreen> {
  static const int _pageSize = 20;

  /// How long typing pauses before the search is sent: one request per word, not per letter.
  static const Duration _typingPause = Duration(milliseconds: 400);

  /// The status pills: every status the server filters by, taken down last because it is the one
  /// back office put there.
  static const List<ServiceOfferStatusFilter?> _statuses = <ServiceOfferStatusFilter?>[
    null,
    ServiceOfferStatusFilter.active,
    ServiceOfferStatusFilter.paused,
    ServiceOfferStatusFilter.draft,
    ServiceOfferStatusFilter.archived,
    ServiceOfferStatusFilter.takenDown,
  ];

  final TextEditingController _search = TextEditingController();
  Timer? _typing;

  ServiceOfferStatusFilter? _status;
  ServiceCategory? _category;
  String? _storeId;
  int _page = 0;

  Paged<BackofficeServiceOffer>? _result;
  Object? _error;
  bool _loading = true;

  /// Bumped by every read, so an answer to an older one (a slow page 1 after page 2 was asked for) is
  /// dropped rather than drawn over the newer.
  int _asked = 0;

  /// The shops the results have named so far, for the shop filter: the list takes a shop's id, and back
  /// office has no other list of service shops to pick one from. Kept across filters, so narrowing to
  /// one shop does not empty the menu that widens it again.
  final Map<String, String> _shops = <String, String>{};

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

  /// Reads the page the filters describe. Answers it too, for a drawer that wants its offer as the
  /// server now has it; null when the read failed or was overtaken.
  Future<Paged<BackofficeServiceOffer>?> _load() async {
    final int asked = ++_asked;
    if (!_loading) setState(() => _loading = true);
    final String text = _search.text.trim();
    try {
      final Paged<BackofficeServiceOffer> page = await widget.api.serviceOffers(
        status: _status,
        serviceCategory: _category,
        storeId: _storeId,
        search: text.isEmpty ? null : text,
        page: _page,
        size: _pageSize,
      );
      if (!mounted || asked != _asked) return null;
      setState(() {
        _result = page;
        _error = null;
        _loading = false;
        for (final BackofficeServiceOffer row in page.content) {
          if (row.storeId.isNotEmpty) {
            _shops[row.storeId] = row.storeName ?? _short(row.storeId);
          }
        }
      });
      return page;
    } catch (e) {
      if (!mounted || asked != _asked) return null;
      setState(() {
        _error = e;
        _loading = false;
      });
      return null;
    }
  }

  void _refilter(VoidCallback change) {
    setState(() {
      change();
      _page = 0;
    });
    unawaited(_load());
  }

  void _typed(String _) {
    _typing?.cancel();
    _typing = Timer(_typingPause, () => _refilter(() {}));
  }

  void _goTo(int page) {
    setState(() => _page = page);
    unawaited(_load());
  }

  Future<BackofficeServiceOffer?> _reloadOne(String productId) async {
    final Paged<BackofficeServiceOffer>? page = await _load();
    return page?.content.where((BackofficeServiceOffer r) => r.offer.id == productId).firstOrNull;
  }

  Future<void> _open(BackofficeServiceOffer row) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    await showConsoleDrawer<void>(
      context: context,
      title: row.offer.name,
      subtitle: <String>[
        row.storeName ?? '—',
        if (row.serviceCategory != null) row.serviceCategory!.labelIn(t),
      ].join(' · '),
      width: 520,
      builder: (BuildContext _) => _OfferDetail(
        row: row,
        api: widget.api,
        onChanged: () => unawaited(_load()),
        reload: _reloadOne,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return ConsolePage(
      header: ConsoleTopbar(
        title: t.svcBoOffersTitle,
        subtitle: t.svcBoOffersSubtitle,
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
        _filters(t),
        _body(t),
      ],
    );
  }

  Widget _filters(DeliveryStrings t) {
    final String? shop = _storeId;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: ConsoleMetrics.pageGap,
      runSpacing: DeliverySpacing.md - DeliverySpacing.xs,
      children: <Widget>[
        Wrap(
          spacing: DeliverySpacing.md - DeliverySpacing.xs,
          runSpacing: DeliverySpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            ConsoleSearchField(
              hintText: t.svcBoOffersSearchHint,
              controller: _search,
              width: 272,
              onChanged: _typed,
            ),
            // The whole taxonomy, closed categories included: back office moderates the offers no
            // customer can see as much as the ones they can.
            ConsoleSelect(
              label: _category?.labelIn(t) ?? t.svcBoAllCategories,
              icon: Icons.category_outlined,
              options: <ConsoleOption>[
                ConsoleOption(label: t.svcBoAllCategories, value: null),
                for (final ServiceCategory c in ServiceCategory.values)
                  ConsoleOption(label: c.labelIn(t), value: c.wireValue),
              ],
              onSelected: (String? wire) =>
                  _refilter(() => _category = ServiceCategory.maybeFromWire(wire)),
            ),
            ConsoleSelect(
              label: shop == null ? t.svcBoAllShops : (_shops[shop] ?? _short(shop)),
              icon: Icons.storefront_outlined,
              tooltip: t.svcBoShopFilterTooltip,
              options: <ConsoleOption>[
                ConsoleOption(label: t.svcBoAllShops, value: null),
                for (final MapEntry<String, String> s in _shops.entries)
                  ConsoleOption(label: s.value, value: s.key),
              ],
              onSelected: (String? id) => _refilter(() => _storeId = id),
            ),
          ],
        ),
        ConsoleFilterPills(
          labels: <String>[
            for (final ServiceOfferStatusFilter? s in _statuses) _filterLabel(t, s),
          ],
          selectedIndex: _statuses.indexOf(_status),
          onSelected: (int i) => _refilter(() => _status = _statuses[i]),
        ),
      ],
    );
  }

  Widget _body(DeliveryStrings t) {
    final Object? error = _error;
    if (error != null) {
      // A 403 is this account, and pressing Try again would not change it.
      if (refusalStatus(error) == 403) {
        return ServicesStateCard(icon: Icons.lock_outline, text: t.svcBoOffersRefused);
      }
      return ServicesStateCard(
        icon: Icons.error_outline,
        text: t.svcBoOffersLoadFailed,
        action: ConsoleButton(
          label: t.tryAgain,
          tone: ConsoleButtonTone.outlined,
          onPressed: () => unawaited(_load()),
        ),
      );
    }
    final Paged<BackofficeServiceOffer>? result = _result;
    if (result == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: DeliverySpacing.xxl),
        child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
      );
    }

    return ConsoleTable(
      minWidth: 900,
      columns: <ConsoleColumn>[
        ConsoleColumn(label: t.svcBoColOffer, flex: 2),
        ConsoleColumn(label: t.svcBoColShop, flex: 1),
        ConsoleColumn(label: t.svcBoColCategory, width: 160),
        ConsoleColumn(label: t.svcBoColPrice, width: 190),
        ConsoleColumn(label: t.svcBoColStatus, width: 140),
      ],
      empty: Text(t.svcBoOffersEmpty, style: ConsoleText.cellMuted),
      footer: result.content.isEmpty ? null : _pager(t, result),
      rows: <ConsoleTableRow>[
        for (final BackofficeServiceOffer row in result.content)
          ConsoleTableRow(
            onTap: () => _open(row),
            cells: <Widget>[
              ConsoleNameCell(
                name: row.offer.name,
                leading: ConsoleInitialTile(label: row.offer.name),
              ),
              Text(row.storeName ?? '—', overflow: TextOverflow.ellipsis, style: ConsoleText.cell),
              Text(
                row.serviceCategory?.labelIn(t) ?? '—',
                overflow: TextOverflow.ellipsis,
                style: ConsoleText.cellMuted,
              ),
              Text(offerPrice(t, row.offer),
                  overflow: TextOverflow.ellipsis, style: ConsoleText.cellStrong),
              ConsoleStatusPill(label: offerStatusLabel(t, row), accent: offerStatusAccent(row)),
            ],
          ),
      ],
    );
  }

  Widget _pager(DeliveryStrings t, Paged<BackofficeServiceOffer> result) {
    final int pages = result.totalPages < 1 ? 1 : result.totalPages;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            '${t.svcBoOffersCount(result.totalElements)} · ${t.svcBoPageOf(result.page + 1, pages)}',
            style: ConsoleText.meta,
          ),
        ),
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

  static String _filterLabel(DeliveryStrings t, ServiceOfferStatusFilter? status) =>
      switch (status) {
        null => t.svcBoFilterAll,
        ServiceOfferStatusFilter.active => t.svcBoOfferActive,
        ServiceOfferStatusFilter.paused => t.svcBoOfferPaused,
        ServiceOfferStatusFilter.draft => t.svcBoOfferDraft,
        ServiceOfferStatusFilter.archived => t.svcBoOfferArchived,
        ServiceOfferStatusFilter.takenDown => t.svcBoOfferTakenDown,
      };
}

/// An offer's status as back office reads it: held off sale first, whatever status the hold left.
@visibleForTesting
String offerStatusLabel(DeliveryStrings t, BackofficeServiceOffer row) => row.offer.isTakenDown
    ? t.svcBoOfferTakenDown
    : switch (row.offer.status) {
        ProductStatus.draft => t.svcBoOfferDraft,
        ProductStatus.active => t.svcBoOfferActive,
        ProductStatus.paused => t.svcBoOfferPaused,
        ProductStatus.archived => t.svcBoOfferArchived,
      };

@visibleForTesting
DeliveryAccent offerStatusAccent(BackofficeServiceOffer row) => row.offer.isTakenDown
    ? DeliveryAccent.critical
    : switch (row.offer.status) {
        ProductStatus.active => DeliveryAccent.positive,
        ProductStatus.paused => DeliveryAccent.caution,
        ProductStatus.draft || ProductStatus.archived => DeliveryAccent.neutral,
      };

/// The price as the offer is sold: "$15.00 per 500 cards", "$8.00 per sqm", "From $15.00". A term this
/// build does not know shows the bare price rather than a guess at what it is per.
@visibleForTesting
String offerPrice(DeliveryStrings t, Product offer) {
  final ServiceTerms? terms = offer.service;
  final String amount = usd(offer.price);
  if (terms == null) return amount;
  final String? unit = terms.unitLabel;
  return switch (terms.pricingType) {
    ServicePricingType.from => t.svcBoPriceFrom(usd(offer.fromPrice ?? offer.price)),
    ServicePricingType.perUnit => unit == null ? amount : t.svcBoPricePer(amount, unit),
    ServicePricingType.fixed =>
      unit == null ? amount : t.svcBoPricePerPack(amount, terms.unitSize, unit),
    ServicePricingType.unknown => amount,
  };
}

String _short(String id) => id.length <= 8 ? id : id.substring(0, 8);

/// One offer beside the list: what it is, whose it is, what it promises, and the act on it.
class _OfferDetail extends StatefulWidget {
  const _OfferDetail({
    required this.row,
    required this.api,
    required this.onChanged,
    required this.reload,
  });

  final BackofficeServiceOffer row;
  final BackofficeCatalogApi api;

  /// The act went through: the list behind should be read again.
  final VoidCallback onChanged;

  /// Reads the list again and answers this offer as it now stands, or null when it is not on the page.
  final Future<BackofficeServiceOffer?> Function(String productId) reload;

  @override
  State<_OfferDetail> createState() => _OfferDetailState();
}

class _OfferDetailState extends State<_OfferDetail> {
  late BackofficeServiceOffer _row = widget.row;
  late Future<List<OfferModerationAction>> _history =
      widget.api.moderationHistory(widget.row.offer.id);
  bool _busy = false;

  /// The server said the offer does not exist: nothing is left to act on.
  bool _gone = false;

  /// What the last act came to, said inside the drawer, where the reader is looking.
  ({String text, bool good})? _outcome;

  Future<void> _act({required bool takeDown}) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String name = _row.offer.name;
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext _) => _ReasonDialog(
        title: takeDown ? t.svcBoTakeDownTitle(name) : t.svcBoRestoreTitle(name),
        body: takeDown ? t.svcBoTakeDownBody : t.svcBoRestoreBody,
        confirmLabel: takeDown ? t.svcBoTakeDown : t.svcBoRestore,
        destructive: takeDown,
      ),
    );
    if (reason == null || !mounted) return;

    setState(() {
      _busy = true;
      _outcome = null;
    });
    try {
      final BackofficeServiceOffer updated = takeDown
          ? await widget.api.takeDown(_row.offer.id, reason: reason)
          : await widget.api.restore(_row.offer.id, reason: reason);
      if (!mounted) return;
      setState(() {
        _row = updated;
        _busy = false;
        _outcome = (
          text: takeDown ? t.svcBoTakenDownDone(name) : t.svcBoRestoredDone(name),
          good: true,
        );
        _history = widget.api.moderationHistory(updated.offer.id);
      });
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      final int? status = refusalStatus(e);
      setState(() {
        _busy = false;
        _outcome = (
          text: switch (status) {
            // The server's own no to this act: already down (or not a service offer), or not down.
            422 => takeDown ? t.svcBoTakeDownRefused : t.svcBoRestoreRefused,
            // PRODUCT_CHANGED: the offer moved under the act, which was refused whole.
            409 => t.svcBoOfferChanged,
            404 => t.svcBoOfferGone,
            403 => t.svcBoModerateRefused,
            400 => t.svcBoReasonRejected(_maxReason),
            _ => t.svcBoActionFailed,
          },
          good: false,
        );
        _gone = status == 404;
      });
      // Each of these says the list behind is out of date; read it again, and this offer with it.
      if (status == 422 || status == 409 || status == 404) {
        final BackofficeServiceOffer? fresh = await widget.reload(_row.offer.id);
        if (!mounted) return;
        setState(() {
          if (fresh != null) _row = fresh;
          if (!_gone) _history = widget.api.moderationHistory(_row.offer.id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final Product offer = _row.offer;
    final ServiceTerms? terms = offer.service;
    final ProductModeration? hold = _row.offer.moderation;
    final ({String text, bool good})? outcome = _outcome;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ConsoleDrawerSection(
          title: t.svcBoSectionOffer,
          first: true,
          trailing: _gone
              ? null
              : hold == null
                  ? ConsoleButton(
                      label: t.svcBoTakeDown,
                      icon: Icons.block,
                      tone: ConsoleButtonTone.destructive,
                      busy: _busy,
                      onPressed: () => unawaited(_act(takeDown: true)),
                    )
                  : ConsoleButton(
                      label: t.svcBoRestore,
                      icon: Icons.undo,
                      tone: ConsoleButtonTone.solid,
                      busy: _busy,
                      onPressed: () => unawaited(_act(takeDown: false)),
                    ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (outcome != null) ...<Widget>[
                ServicesNote(
                  text: outcome.text,
                  icon: outcome.good ? Icons.check_circle_outline : Icons.error_outline,
                  accent: outcome.good ? DeliveryAccent.positive : DeliveryAccent.critical,
                ),
                const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
              ],
              ConsoleFactGrid(
                facts: <ConsoleFact>[
                  ConsoleFact(t.svcBoColStatus, offerStatusLabel(t, _row)),
                  ConsoleFact(t.svcBoColPrice, offerPrice(t, offer)),
                  ConsoleFact(
                    t.svcBoColCategory,
                    _row.serviceCategory?.labelIn(t) ?? '—',
                    absent: _row.serviceCategory == null,
                  ),
                ],
              ),
              if ((offer.description ?? '').trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                Text(t.svcBoFactDescription, style: ConsoleText.fieldLabel),
                const SizedBox(height: DeliverySpacing.xs),
                Text(offer.description!.trim(), style: ConsoleText.body),
              ],
            ],
          ),
        ),
        if (hold != null)
          ConsoleDrawerSection(
            title: t.svcBoSectionHold,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(t.svcBoHoldReason, style: ConsoleText.fieldLabel),
                const SizedBox(height: DeliverySpacing.xs),
                Text(hold.reason ?? '—', style: ConsoleText.body),
                if (hold.takenDownAt != null) ...<Widget>[
                  const SizedBox(height: DeliverySpacing.sm),
                  Text('${t.svcBoHoldSince} ${localMoment(context, hold.takenDownAt!)}',
                      style: ConsoleText.meta),
                ],
              ],
            ),
          ),
        ConsoleDrawerSection(
          title: t.svcBoSectionShop,
          child: ConsoleFactGrid(
            facts: <ConsoleFact>[
              ConsoleFact(t.svcBoFactName, _row.storeName ?? '—', absent: _row.storeName == null),
              ConsoleFact(t.svcBoFactListing, _listing(t, _row.storeStatus)),
            ],
          ),
        ),
        if (terms != null)
          ConsoleDrawerSection(
            title: t.svcBoSectionTerms,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ConsoleFactGrid(
                  facts: <ConsoleFact>[
                    ConsoleFact(t.svcBoTermPricing, _pricing(t, terms.pricingType)),
                    ConsoleFact(t.svcBoTermPack, _pack(t, terms)),
                    ConsoleFact(t.svcBoTermTurnaround, _turnaround(t, terms) ?? '—',
                        absent: _turnaround(t, terms) == null),
                    ConsoleFact(t.svcBoTermFulfilment, _fulfilment(t, terms.fulfilmentModes)),
                    ConsoleFact(t.svcBoTermFiles, _files(t, terms.attachmentPolicy)),
                  ],
                ),
                if (terms.instructionsPrompt != null) ...<Widget>[
                  const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                  Text(t.svcBoTermPrompt, style: ConsoleText.fieldLabel),
                  const SizedBox(height: DeliverySpacing.xs),
                  Text(terms.instructionsPrompt!, style: ConsoleText.body),
                ],
              ],
            ),
          ),
        ConsoleDrawerSection(
          title: t.svcBoSectionPhotos,
          child: _photos(t, offer),
        ),
        ConsoleDrawerSection(
          title: t.svcBoSectionModerationHistory,
          child: _gone
              ? Text(t.svcBoOfferGone, style: ConsoleText.cellMuted)
              : FutureBuilder<List<OfferModerationAction>>(
                  future: _history,
                  builder: (BuildContext context,
                      AsyncSnapshot<List<OfferModerationAction>> snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const LinearProgressIndicator(color: DeliveryColors.brand);
                    }
                    if (snapshot.hasError) {
                      return Text(t.svcBoHistoryLoadFailed, style: ConsoleText.cellMuted);
                    }
                    final List<OfferModerationAction> acts = snapshot.data!;
                    if (acts.isEmpty) {
                      return Text(t.svcBoHistoryNever, style: ConsoleText.cellMuted);
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        for (final OfferModerationAction act in acts) _HistoryEntry(act: act),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _photos(DeliveryStrings t, Product offer) {
    if (offer.imageUrls.isEmpty) {
      return Text(t.svcBoNoPhotos, style: ConsoleText.cellMuted);
    }
    // The 320px derivatives when the server made one per photo; the originals otherwise. The tap
    // opens the full-size gallery either way.
    final List<String> shown = offer.imageThumbUrls.length == offer.imageUrls.length
        ? offer.imageThumbUrls
        : offer.imageUrls;
    final ProductPreviewWords words = ProductPreviewWords(
      untitled: t.svcBoPhoto,
      unavailable: t.svcBoPhotoUnavailable,
      close: t.close,
      previous: t.previous,
      next: t.next,
      position: t.svcBoPhotoPosition,
    );
    return Wrap(
      spacing: DeliverySpacing.sm,
      runSpacing: DeliverySpacing.sm,
      children: <Widget>[
        for (int i = 0; i < shown.length; i++)
          DeliveryProductImage(
            url: shown[i],
            width: 96,
            height: 96,
            borderRadius: BorderRadius.circular(DeliveryRadius.sm),
            unavailableLabel: t.svcBoPhotoUnavailable,
            openLabel: t.svcBoOpenPhoto,
            onTap: () => showProductImagePreview(
              context,
              urls: offer.imageUrls,
              title: offer.name,
              initialIndex: i,
              words: words,
            ),
          ),
      ],
    );
  }

  static String _listing(DeliveryStrings t, StoreListingStatus status) => switch (status) {
        StoreListingStatus.active => t.svcBoShopListed,
        StoreListingStatus.draft => t.svcBoShopDraft,
        StoreListingStatus.suspended => t.svcBoShopSuspended,
      };

  static String _pricing(DeliveryStrings t, ServicePricingType type) => switch (type) {
        ServicePricingType.fixed => t.svcBoPricingFixed,
        ServicePricingType.perUnit => t.svcBoPricingPerUnit,
        ServicePricingType.from => t.svcBoPricingFrom,
        ServicePricingType.unknown => t.svcBoTermUnknown,
      };

  static String _pack(DeliveryStrings t, ServiceTerms terms) => terms.unitLabel == null
      ? t.svcBoPackUnits(terms.unitSize)
      : t.svcBoPackOf(terms.unitSize, terms.unitLabel!);

  /// Null when the offer promises no turnaround, so the fact shows a dash.
  static String? _turnaround(DeliveryStrings t, ServiceTerms terms) {
    final int? max = terms.turnaroundMaxHours;
    final int? min = terms.turnaroundMinHours;
    if (max == null) return null;
    if (min == null || min >= max) return t.svcBoTurnaroundUpTo(max);
    return t.svcBoTurnaroundRange(min, max);
  }

  static String _fulfilment(DeliveryStrings t, ServiceFulfilment modes) => switch (modes) {
        ServiceFulfilment.pickup => t.svcBoFulfilPickup,
        ServiceFulfilment.delivery => t.svcBoFulfilDelivery,
        ServiceFulfilment.both => t.svcBoFulfilBoth,
        ServiceFulfilment.unknown => t.svcBoTermUnknown,
      };

  static String _files(DeliveryStrings t, ServiceAttachmentPolicy policy) => switch (policy) {
        ServiceAttachmentPolicy.none => t.svcBoFilesPolicyNone,
        ServiceAttachmentPolicy.optional => t.svcBoFilesPolicyOptional,
        ServiceAttachmentPolicy.required => t.svcBoFilesPolicyRequired,
        ServiceAttachmentPolicy.unknown => t.svcBoTermUnknown,
      };
}

class _HistoryEntry extends StatelessWidget {
  const _HistoryEntry({required this.act});

  final OfferModerationAction act;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final (String label, IconData icon, DeliveryAccent accent) = switch (act.action) {
      OfferModerationActionKind.takeDown => (t.svcBoActTakeDown, Icons.block, DeliveryAccent.critical),
      OfferModerationActionKind.restore => (t.svcBoActRestore, Icons.undo, DeliveryAccent.positive),
      OfferModerationActionKind.unknown =>
        (t.svcBoActUnknown, Icons.help_outline, DeliveryAccent.neutral),
    };
    final String actor = act.actorName ?? _short(act.actorId);
    final DateTime? at = act.createdAt;

    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.md - DeliverySpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: accent.color),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(label, style: ConsoleText.cellStrong),
                if (act.reason.isNotEmpty) Text(act.reason, style: ConsoleText.body),
                Text(
                  <String>[t.svcBoActBy(actor), if (at != null) localMoment(context, at)].join(' · '),
                  style: ConsoleText.meta,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks for the reason the trail keeps, and will not answer without one. The field counts and stops in
/// the units the server counts (see [_maxReason]), so a typed reason is never refused for its length.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.destructive,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final bool destructive;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final TextEditingController _reason = TextEditingController();
  bool _missing = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _confirm() {
    final String reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _missing = true);
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    // In UTF-16 units, as the server counts. Every edit rebuilds the dialog, so this stays current.
    final int used = _reason.text.length;
    return AlertDialog(
      backgroundColor: DeliveryColors.white,
      title: Text(widget.title, style: ConsoleText.cardTitle),
      content: SizedBox(
        width: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(widget.body, style: ConsoleText.body),
            const SizedBox(height: DeliverySpacing.md),
            TextField(
              controller: _reason,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              // Not `maxLength`, which counts characters (see [_maxReason]).
              inputFormatters: const <TextInputFormatter>[_Utf16LengthLimit(_maxReason)],
              style: ConsoleText.control,
              cursorColor: DeliveryColors.brand,
              decoration: InputDecoration(
                labelText: t.svcBoReasonLabel,
                errorText: _missing ? t.svcBoReasonRequired : null,
                counterText: t.svcBoReasonLength(used, _maxReason),
              ),
              // Redraws the counter, and clears a "reason required" the edit answers.
              onChanged: (_) => setState(() => _missing = false),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        ConsoleButton(
          label: t.cancel,
          tone: ConsoleButtonTone.outlined,
          onPressed: () => Navigator.of(context).pop(),
        ),
        ConsoleButton(
          label: widget.confirmLabel,
          tone: widget.destructive ? ConsoleButtonTone.destructive : ConsoleButtonTone.solid,
          onPressed: _confirm,
        ),
      ],
    );
  }
}

/// Holds a field to [max] UTF-16 code units, which is what Java's `String.length()` and `@Size` count,
/// and cuts only between whole characters. The customer app holds a gift card's text the same way.
///
/// Not Flutter's `maxLength`, which counts characters as a person sees them: an emoji is one there and
/// two here, so a reason that field let through could come back from the server as a 400.
class _Utf16LengthLimit extends TextInputFormatter {
  const _Utf16LengthLimit(this.max);

  final int max;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length <= max) return newValue;
    // Already full and typed at a caret: the keystroke is refused, not the end of the reason trimmed.
    if (oldValue.text.length == max && oldValue.selection.isCollapsed) return oldValue;
    final StringBuffer kept = StringBuffer();
    for (final String character in newValue.text.characters) {
      if (kept.length + character.length > max) break;
      kept.write(character);
    }
    final String text = kept.toString();
    int within(int offset) => offset > text.length ? text.length : offset;
    return TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: within(newValue.selection.baseOffset),
        extentOffset: within(newValue.selection.extentOffset),
      ),
    );
  }
}
