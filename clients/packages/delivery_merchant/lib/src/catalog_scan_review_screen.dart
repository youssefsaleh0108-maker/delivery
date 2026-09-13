/// The review Merchant Blitz leads to: every line the photo reader found, to keep or to skip.
///
/// Figma draws no frame for this page — the 121:198 analyst spec flags it as needing a design — so it
/// takes its shape from the single-product form it feeds: the same name and price fields, a section
/// picker offering the shop's own sections before the platform's, and the price rule the server
/// enforces on every product (more than zero, at most two decimals), checked here so a whole review
/// is never refused over one box.
///
/// Three things it will not do:
///  * put the reader's price guess in the price box. The guess sits beside the box, labelled, with a
///    button to use it. A merchant who sells at a different price must never find the guess saved
///    because they scrolled past it.
///  * publish. "Save N drafts" is the whole promise, and the result says drafts stay hidden.
///  * save half a review. One request carries every keep and every skip, and the server applies all
///    of it or none of it, so a failure leaves every line exactly as it was and the merchant simply
///    saves again.
library;

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'order_detail_screen.dart';

class CatalogScanReviewScreen extends StatefulWidget {
  const CatalogScanReviewScreen({
    super.key,
    required this.api,
    required this.catalogApi,
    required this.scan,
    this.storeId,
  });

  final CatalogScanApi api;

  /// The section lists: the shop's own and the platform's.
  final CatalogApi catalogApi;

  /// The scan as last read. Only its PENDING lines are offered: a line already kept or skipped was
  /// decided on an earlier visit and is a product, or nothing, now.
  final CatalogScan scan;

  /// Whose own sections are offered first. Null offers the platform's only.
  final String? storeId;

  @override
  State<CatalogScanReviewScreen> createState() => _CatalogScanReviewScreenState();
}

/// One line under review, with the merchant's edits.
class _Draft {
  _Draft(this.line)
      : name = TextEditingController(text: line.name),
        // The merchant's own earlier price if one was saved — never the guess.
        price = TextEditingController(text: line.price == null ? '' : merchantMoney(line.price!)),
        categoryId = line.categoryId;

  final ScanLine line;
  final TextEditingController name;
  final TextEditingController price;
  String? categoryId;
  bool keep = true;

  void dispose() {
    name.dispose();
    price.dispose();
  }
}

class _CatalogScanReviewScreenState extends State<CatalogScanReviewScreen> {
  static final RegExp _money = RegExp(r'^\d{1,10}(\.\d{1,2})?$');
  static final RegExp _tooPrecise = RegExp(r'^\d{1,10}\.\d{3,}$');

  /// Doubtful lines first: they are the ones that need the merchant's eye, and at the top they are
  /// seen before a long list wears that attention out. Otherwise the reader's own order.
  late final List<_Draft> _drafts = <ScanLine>[
    ...widget.scan.pendingLines.where((ScanLine l) => l.isDoubtful),
    ...widget.scan.pendingLines.where((ScanLine l) => !l.isDoubtful),
  ].map(_Draft.new).toList();

  List<Category>? _sections;
  bool _sectionsFailed = false;

  /// Errors appear once the merchant has tried to save, not while the first digit is being typed.
  bool _showErrors = false;

  bool _saving = false;

  /// What the server answered to the save. Non-null swaps the list for the result.
  CatalogScan? _saved;

  @override
  void initState() {
    super.initState();
    _loadSections();
  }

  @override
  void dispose() {
    for (final _Draft draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSections() async {
    try {
      final String? storeId = widget.storeId;
      final List<Category> own =
          storeId == null ? const <Category>[] : await widget.catalogApi.storeCategories(storeId);
      final List<Category> platform = await widget.catalogApi.categories();
      if (!mounted) return;
      final Set<String> ids = <String>{};
      final List<Category> all = <Category>[
        for (final Category c in <Category>[...own, ...platform])
          if (ids.add(c.id)) c,
      ];
      setState(() {
        _sections = all;
        // A suggestion this list does not hold would be drawn as "No section" and still be sent:
        // the picker would be lying about what gets saved. The reader only suggests from these same
        // lists, so this is rare, and it resolves the honest way — to no section.
        for (final _Draft draft in _drafts) {
          if (draft.categoryId != null && !ids.contains(draft.categoryId)) {
            draft.categoryId = null;
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      // Each line keeps the section the server suggested, and the page says so.
      setState(() => _sectionsFailed = true);
    }
  }

  /// Arabic-Indic digits and the Arabic decimal separator, the way a phone keyboard set to Arabic
  /// types a price.
  static String _normalise(String raw) {
    final StringBuffer out = StringBuffer();
    for (final int rune in raw.trim().runes) {
      if (rune >= 0x0660 && rune <= 0x0669) {
        out.writeCharCode(0x30 + rune - 0x0660);
      } else if (rune >= 0x06F0 && rune <= 0x06F9) {
        out.writeCharCode(0x30 + rune - 0x06F0);
      } else if (rune == 0x066B || rune == 0x2C) {
        out.write('.');
      } else {
        out.writeCharCode(rune);
      }
    }
    return out.toString();
  }

  String? _nameError(DeliveryStrings t, _Draft draft) =>
      draft.name.text.trim().isEmpty ? t.blitzNeedName : null;

  /// The server's rule for every product price: at least 0.01, at most two decimals.
  String? _priceError(DeliveryStrings t, _Draft draft) {
    final String text = _normalise(draft.price.text);
    if (_tooPrecise.hasMatch(text)) return t.blitzPriceDecimals;
    if (!_money.hasMatch(text) || double.parse(text) < 0.01) return t.blitzNeedPrice;
    return null;
  }

  bool _valid(DeliveryStrings t, _Draft draft) =>
      _nameError(t, draft) == null && _priceError(t, draft) == null;

  Future<void> _save() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<_Draft> kept = _drafts.where((_Draft d) => d.keep).toList();
    if (kept.any((_Draft d) => !_valid(t, d))) {
      setState(() => _showErrors = true);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.blitzFixItems)));
      return;
    }

    setState(() => _saving = true);
    try {
      final CatalogScan saved = await widget.api.commit(
        scanId: widget.scan.id,
        accept: <ScanLineDecision>[
          for (final _Draft d in kept)
            ScanLineDecision(
              lineId: d.line.id,
              name: d.name.text.trim(),
              price: double.parse(_normalise(d.price.text)),
              categoryId: d.categoryId,
            ),
        ],
        reject: <String>[
          for (final _Draft d in _drafts)
            if (!d.keep) d.line.id,
        ],
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = saved;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(_messageFor(e, fallback: t.somethingWentWrong))),
      );
    }
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final CatalogScan? saved = _saved;

    return PopScope<CatalogScan>(
      // Held while a save is on the wire: it can land after the merchant has left, and the Blitz
      // screen would then offer to review lines that are already products. Once saved, leaving
      // carries the result back however the merchant leaves — the header's back, the system back,
      // or Done — so the Blitz screen never shows lines that are already products.
      canPop: saved == null && !_saving,
      onPopInvokedWithResult: (bool didPop, CatalogScan? result) {
        if (!didPop && saved != null) Navigator.of(context).pop(saved);
      },
      child: Scaffold(
        backgroundColor: DeliveryColors.background,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              MerchantScreenHeader(
                title: t.blitzReviewTitle,
                subtitle: t.blitzReviewSubtitle,
                onBack: () => Navigator.of(context).maybePop(),
                backSemanticLabel: t.back,
              ),
              Expanded(child: _capped(saved == null ? _list(t) : _result(t, saved))),
              if (saved == null) _bottomBar(t),
            ],
          ),
        ),
      ),
    );
  }

  Widget _capped(Widget child) => Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: merchantMaxContentWidth),
          child: child,
        ),
      );

  Widget _list(DeliveryStrings t) {
    return ListView(
      padding: const EdgeInsets.all(DeliverySpacing.md),
      children: <Widget>[
        if (widget.scan.sample) ...<Widget>[
          _SampleNote(title: t.blitzSampleTitle, body: t.blitzSampleBody),
          const SizedBox(height: DeliverySpacing.md),
        ],
        if (_sectionsFailed) ...<Widget>[
          Text(
            t.blitzSectionsUnavailable,
            style: const TextStyle(fontSize: 12, color: DeliveryColors.muted),
          ),
          const SizedBox(height: DeliverySpacing.sm),
        ],
        for (final _Draft draft in _drafts) ...<Widget>[
          _card(t, draft),
          const SizedBox(height: DeliverySpacing.sm + DeliverySpacing.xs),
        ],
      ],
    );
  }

  Widget _card(DeliveryStrings t, _Draft draft) {
    final ScanLine line = draft.line;
    final bool invalid = _showErrors && draft.keep && !_valid(t, draft);
    final String details = <String?>[line.brand, line.size]
        .whereType<String>()
        .where((String s) => s.trim().isNotEmpty)
        .join(' · ');
    final double? guess = line.priceGuess;
    final String shownName = draft.name.text.trim().isEmpty ? line.name : draft.name.text.trim();

    return YdCard.bordered(
      borderColor: invalid ? DeliveryAccent.critical.color : DeliveryColors.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      shownName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: draft.keep ? DeliveryColors.ink : DeliveryColors.faint,
                      ),
                    ),
                    if (details.isNotEmpty)
                      Text(
                        details,
                        style: const TextStyle(fontSize: 12, color: DeliveryColors.muted),
                      ),
                  ],
                ),
              ),
              Semantics(
                label: t.blitzKeepItem(shownName),
                child: Switch(
                  value: draft.keep,
                  onChanged: _saving ? null : (bool value) => setState(() => draft.keep = value),
                ),
              ),
            ],
          ),
          if (line.isDoubtful) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            // A sentence, so it is allowed to wrap. It started as a YdBadge, whose single line ran
            // off the card on a 320-wide phone in Arabic.
            Container(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 4),
              decoration: BoxDecoration(
                color: DeliveryAccent.caution.tint,
                borderRadius: BorderRadius.circular(DeliveryRadius.sm),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.help_outline_rounded,
                      size: 14, color: DeliveryAccent.caution.onTint),
                  const SizedBox(width: DeliverySpacing.xs),
                  Expanded(
                    child: Text(
                      t.blitzCheckThis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DeliveryAccent.caution.onTint,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (draft.keep) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            TextField(
              controller: draft.name,
              enabled: !_saving,
              maxLength: 200,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: t.blitzName,
                counterText: '',
                errorText: _showErrors ? _nameError(t, draft) : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: DeliverySpacing.sm + DeliverySpacing.xs),
            TextField(
              controller: draft.price,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: t.blitzPriceUsd,
                prefixText: r'$ ',
                errorText: _showErrors ? _priceError(t, draft) : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (guess != null)
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: DeliverySpacing.sm,
                children: <Widget>[
                  Text(
                    t.blitzGuess('\$${merchantMoney(guess)}'),
                    style: const TextStyle(fontSize: 12, color: DeliveryColors.muted),
                  ),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() => draft.price.text = merchantMoney(guess)),
                    child: Text(t.blitzUseGuess),
                  ),
                ],
              ),
            const SizedBox(height: DeliverySpacing.sm),
            _sectionField(t, draft),
          ],
        ],
      ),
    );
  }

  Widget _sectionField(DeliveryStrings t, _Draft draft) {
    final List<Category>? sections = _sections;
    if (sections == null) return const SizedBox.shrink();
    return DropdownButtonFormField<String?>(
      initialValue: draft.categoryId,
      isExpanded: true,
      decoration: InputDecoration(labelText: t.blitzSection),
      items: <DropdownMenuItem<String?>>[
        DropdownMenuItem<String?>(value: null, child: Text(t.blitzNoSection)),
        for (final Category section in sections)
          DropdownMenuItem<String?>(
            value: section.id,
            child: Text(section.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _saving ? null : (String? value) => setState(() => draft.categoryId = value),
    );
  }

  Widget _bottomBar(DeliveryStrings t) {
    final int keeping = _drafts.where((_Draft d) => d.keep).length;
    return Container(
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(top: BorderSide(color: DeliveryColors.border)),
      ),
      padding: EdgeInsetsDirectional.fromSTEB(
        DeliverySpacing.md,
        DeliverySpacing.sm + DeliverySpacing.xs,
        DeliverySpacing.md,
        DeliverySpacing.sm + DeliverySpacing.xs + MediaQuery.paddingOf(context).bottom,
      ),
      child: _capped(
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving || _drafts.isEmpty ? null : _save,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                  horizontal: DeliverySpacing.md, vertical: DeliverySpacing.sm + 6),
            ),
            child: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(keeping == 0 ? t.blitzSkipAll : t.blitzSaveDrafts(keeping)),
          ),
        ),
      ),
    );
  }

  Widget _result(DeliveryStrings t, CatalogScan saved) {
    final Set<String> kept = <String>{
      for (final _Draft d in _drafts)
        if (d.keep) d.line.id,
    };
    final int accepted = saved.lines
        .where((ScanLine l) => kept.contains(l.id) && l.status == ScanLineStatus.accepted)
        .length;

    return ListView(
      padding: const EdgeInsets.all(DeliverySpacing.lg),
      children: <Widget>[
        Icon(Icons.check_circle_rounded, size: 56, color: DeliveryAccent.positive.color),
        const SizedBox(height: DeliverySpacing.md),
        Text(
          t.blitzSavedTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700, color: DeliveryColors.ink),
        ),
        const SizedBox(height: DeliverySpacing.sm),
        Text(
          t.blitzSavedCount(accepted),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: DeliveryColors.ink),
        ),
        if (accepted > 0) ...<Widget>[
          const SizedBox(height: DeliverySpacing.sm),
          Text(
            t.blitzSavedHint,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, height: 1.4, color: DeliveryColors.muted),
          ),
        ],
        const SizedBox(height: DeliverySpacing.lg),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(saved),
            child: Text(t.blitzDone),
          ),
        ),
      ],
    );
  }
}

/// The sample warning, repeated here because this is the page where a merchant could otherwise
/// save an example item as though the reader had found it on their shelf.
class _SampleNote extends StatelessWidget {
  const _SampleNote({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    const DeliveryAccent accent = DeliveryAccent.caution;
    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.md),
      decoration: BoxDecoration(
        color: accent.tint,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.science_outlined, size: 18, color: accent.onTint),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: accent.onTint)),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(fontSize: 13, color: DeliveryColors.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The server's own sentence for a refusal when it sent one, else [fallback].
String _messageFor(Object error, {required String fallback}) {
  if (error is DioException) {
    final Object? body = error.response?.data;
    if (body is Map<String, dynamic>) {
      final String? detail = body['detail'] as String?;
      final String? correlationId = body['correlationId'] as String?;
      if (detail != null) {
        return correlationId == null ? detail : '$detail (ref: $correlationId)';
      }
    }
  }
  return fallback;
}
