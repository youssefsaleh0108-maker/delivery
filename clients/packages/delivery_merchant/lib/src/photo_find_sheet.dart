/// "Do I already have this?": a merchant photographs a pack and sees it in their own catalogue.
///
/// One flow for both hosts — the phone's Inventory tab and the portal's Inventory and Products pages
/// — so a shopkeeper meets the same three steps wherever they are: pick a photo (and read where it
/// goes), wait while it is read, then open the product they already have or start a new one from what
/// the reader read.
library;

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'product_form_screen.dart' show PickedImageBytes, ProductPrefill;
import 'photo_pick_sheet.dart';
import 'photo_source.dart';

/// What the merchant chose on the sheet: a product they already have, or a new one to add.
class PhotoFindChoice {
  const PhotoFindChoice.open(Product this.product) : prefill = null;

  const PhotoFindChoice.add(ProductPrefill this.prefill) : product = null;

  /// The product to open in the form, when they picked one they already have.
  final Product? product;

  /// What a new product starts from, when they chose to add one.
  final ProductPrefill? prefill;
}

/// Picks a photo, asks the server what it is, and shows the answer. Null when the merchant backed
/// out anywhere along the way.
///
/// [storeId] narrows the search to one of the caller's shops; without it every goods shop they own is
/// searched.
Future<PhotoFindChoice?> findProductByPhoto(
  BuildContext context, {
  required CatalogApi api,
  required ShelfPhotoSource source,
  String? storeId,
}) async {
  final DeliveryStrings t = DeliveryStrings.of(context);
  final PickedShelfPhoto? photo = await pickPhotoToRead(
    context,
    source: source,
    title: t.pfindSheetTitle,
    message: t.pfindSheetBody,
  );
  if (photo == null || !context.mounted) return null;

  return showModalBottomSheet<PhotoFindChoice>(
    context: context,
    backgroundColor: DeliveryColors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(DeliveryRadius.sheet)),
    ),
    builder: (BuildContext _) => PhotoFindSheet(
      photo: photo,
      // Started inside the sheet, so nothing can fail before there is anything to show it.
      run: () => api.findByPhoto(
          bytes: photo.bytes, contentType: photo.contentType, storeId: storeId),
    ),
  );
}

/// The answer: what the photo was read as, the merchant's own matching products, and a way to add it
/// when they have none.
class PhotoFindSheet extends StatefulWidget {
  const PhotoFindSheet({super.key, required this.run, required this.photo});

  /// Asks the server. Called once, when the sheet opens.
  final Future<PhotoFindResult> Function() run;

  /// The photo itself, which becomes a new product's first image.
  final PickedShelfPhoto photo;

  @override
  State<PhotoFindSheet> createState() => _PhotoFindSheetState();
}

class _PhotoFindSheetState extends State<PhotoFindSheet> {
  late Future<PhotoFindResult> _pending = widget.run();

  void _again() {
    setState(() => _pending = widget.run());
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: DeliveryColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: DeliverySpacing.md),
            FutureBuilder<PhotoFindResult>(
              future: _pending,
              builder: (BuildContext context, AsyncSnapshot<PhotoFindResult> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _looking(t);
                }
                if (snapshot.hasError) {
                  return _failed(t, snapshot.error!);
                }
                return _answer(t, snapshot.data!);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _looking(DeliveryStrings t) => Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: DeliverySpacing.lg),
        child: Column(
          children: <Widget>[
            const CircularProgressIndicator(color: DeliveryColors.brand),
            const SizedBox(height: DeliverySpacing.md),
            Text(
              t.psrchLooking,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: DeliveryColors.muted, height: 1.35),
            ),
          ],
        ),
      );

  /// A refusal in the words of the code the server answered with; anything else is a plain failure.
  Widget _failed(DeliveryStrings t, Object error) {
    final String words;
    bool canRetry = true;
    if (error is PhotoSearchFailure) {
      canRetry = error.code == PhotoSearchFailure.busy || error.code == PhotoSearchFailure.failed;
      words = switch (error.code) {
        PhotoSearchFailure.findLimit || PhotoSearchFailure.searchLimit =>
          error.scope == PhotoSearchFailure.scopeMinute
              ? t.psrchLimitMinute
              : t.pfindLimitDay(error.limit ?? 0),
        PhotoSearchFailure.busy => t.psrchBusy,
        PhotoSearchFailure.unavailable => t.psrchUnavailable,
        PhotoSearchFailure.tooLarge => t.psrchTooLarge,
        PhotoSearchFailure.wrongType => t.psrchWrongType,
        PhotoSearchFailure.unreadable => t.psrchUnreadable,
        PhotoSearchFailure.refused => t.psrchRefused,
        _ => t.psrchFailed,
      };
    } else {
      // A catalogue rule — a service shop, or a merchant with no shop open yet — arrives as the
      // server's own sentence, which is written for the merchant to read and act on.
      words = _detailOf(error) ?? t.psrchFailed;
      canRetry = _detailOf(error) == null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          words,
          style: const TextStyle(fontSize: 14, color: DeliveryColors.ink, height: 1.4),
        ),
        if (canRetry) ...<Widget>[
          const SizedBox(height: DeliverySpacing.md),
          YdPillButton.secondary(label: t.tryAgain, onPressed: _again),
        ],
      ],
    );
  }

  Widget _answer(DeliveryStrings t, PhotoFindResult result) {
    final String? read = result.understood.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // The reader is not switched on: these are Blitz's example lines, said in Blitz's words.
        if (result.sample) ...<Widget>[
          _SampleBanner(title: t.blitzSampleTitle, body: t.blitzSampleBody),
          const SizedBox(height: DeliverySpacing.md),
        ],
        if (!result.understood.isProduct)
          Text(
            t.psrchNotAProduct,
            style: const TextStyle(fontSize: 14, color: DeliveryColors.ink, height: 1.4),
          )
        else ...<Widget>[
          if (read != null)
            Text(
              t.psrchLooksLike(read),
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: DeliveryColors.ink, height: 1.3),
            ),
          const SizedBox(height: DeliverySpacing.md),
          if (result.matches.isEmpty)
            Text(
              t.pfindNoMatch,
              style: const TextStyle(fontSize: 14, color: DeliveryColors.muted, height: 1.4),
            )
          else ...<Widget>[
            Text(
              t.pfindInCatalogue,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: DeliveryColors.ink),
            ),
            const SizedBox(height: DeliverySpacing.sm),
            for (final PhotoFindMatch match in result.matches)
              _MatchRow(
                match: match,
                onTap: () => Navigator.of(context).pop(PhotoFindChoice.open(match.product)),
              ),
          ],
          const SizedBox(height: DeliverySpacing.md),
          // A sample reading is a fixed example of a product nobody photographed — the reader is not
          // switched on. Carrying its name, barcode and section into the form would turn an example
          // into a real product on a real shelf, with a barcode the till would scan, and a merchant
          // who tapped past the banner would never see where it came from. So a sample offers a blank
          // form instead, and says so. Their own photo still comes along: that part is not an example.
          if (result.sample) ...<Widget>[
            YdPillButton(
              label: t.pfindAddBlank,
              icon: Icons.add,
              onPressed: () => Navigator.of(context).pop(PhotoFindChoice.add(ProductPrefill(
                photo: PickedImageBytes(widget.photo.bytes, widget.photo.contentType),
              ))),
            ),
            const SizedBox(height: DeliverySpacing.sm),
            Text(
              t.pfindSampleNoPrefill,
              style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.4),
            ),
          ] else
            YdPillButton(
              label: t.pfindAddNew,
              icon: Icons.add,
              onPressed: () => Navigator.of(context).pop(PhotoFindChoice.add(ProductPrefill(
                name: result.suggestion?.name ?? read,
                barcode: result.suggestion?.barcode,
                categoryId: result.suggestion?.categoryId,
                photo: PickedImageBytes(widget.photo.bytes, widget.photo.contentType),
              ))),
            ),
        ],
        const SizedBox(height: DeliverySpacing.md),
        PhotoConsentLine(text: t.psrchConsent),
      ],
    );
  }
}

/// One of the merchant's own products: its photo, name, price and status, and how it matched.
class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match, required this.onTap});

  final PhotoFindMatch match;
  final VoidCallback onTap;

  static const double _thumb = 48;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final Product product = match.product;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DeliveryRadius.md),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: DeliverySpacing.xs),
        child: Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
              child: product.listImageUrl == null
                  ? Container(
                      width: _thumb,
                      height: _thumb,
                      color: DeliveryColors.background,
                      child: const Icon(Icons.inventory_2_outlined,
                          size: 20, color: DeliveryColors.faint),
                    )
                  : Image.network(product.listImageUrl!,
                      width: _thumb,
                      height: _thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                            width: _thumb,
                            height: _thumb,
                            color: DeliveryColors.background,
                          )),
            ),
            const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: DeliveryColors.ink),
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: DeliverySpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text(
                        '\$${product.price.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700, color: DeliveryColors.brand),
                      ),
                      Text(
                        _statusLabel(t, product.status),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: product.status == ProductStatus.active
                              ? DeliveryAccent.positive.color
                              : DeliveryColors.faint,
                        ),
                      ),
                      if (match.isBarcodeMatch)
                        Text(
                          t.pfindMatchedByBarcode,
                          style: const TextStyle(fontSize: 11, color: DeliveryColors.muted),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: DeliveryColors.faint),
          ],
        ),
      ),
    );
  }
}

/// The sentence a refusal carries, when it carries one a merchant can act on: 4xx problem details
/// are written for the person reading them. A 5xx says nothing useful, and gets the app's own words.
String? _detailOf(Object error) {
  if (error is DioException && (error.response?.statusCode ?? 500) < 500) {
    final Object? body = error.response?.data;
    if (body is Map<String, dynamic> && body['detail'] is String) {
      return body['detail'] as String;
    }
  }
  return null;
}

/// The same words the portal's product list gives a status, so one product reads the same in both.
///
/// A draft keeps its own word rather than being collapsed into "off shelf": it has never been
/// published, usually because it has no photo yet, and that is the one thing to fix.
String _statusLabel(DeliveryStrings t, ProductStatus status) => switch (status) {
      ProductStatus.active => t.merchbAvailable,
      ProductStatus.draft => t.draft,
      ProductStatus.paused => t.merchbOffShelf,
      ProductStatus.archived => t.merchbOffShelf,
    };

/// Blitz's own sample banner, said here for the same reason: these lines are examples, not a reading
/// of this shelf.
class _SampleBanner extends StatelessWidget {
  const _SampleBanner({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
      decoration: BoxDecoration(
        color: DeliveryAccent.caution.tint,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        border: Border.all(color: DeliveryAccent.caution.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: DeliveryColors.ink),
          ),
          const SizedBox(height: 2),
          Text(
            body,
            style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.35),
          ),
        ],
      ),
    );
  }
}
