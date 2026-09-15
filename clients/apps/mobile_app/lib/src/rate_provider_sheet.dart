import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'utf16_length_limit.dart';

/// Rating the shop behind a completed service order: five stars and an optional sentence.
///
/// The rider sheet's shape (rate_rider_sheet.dart) for the other half of the work — the provider who
/// printed, tailored or repaired it, not the rider who carried it. Returns the review as the server
/// stored it, or null when the customer backed out.
///
/// A failure is said for what it is. product-service answers 404 for an order it does not have on
/// record as completed, and for an order this customer really did complete that means the moment
/// before `order.delivered` reached it — so the sheet says to try again shortly instead of "could not
/// send". The comment is held to the server's 2,000 UTF-16 units as it is typed.
Future<StoreReview?> showRateProviderSheet(
  BuildContext context, {
  required StoreApi api,
  required String storeId,
  required String orderId,
  required String shopName,
}) {
  return showModalBottomSheet<StoreReview>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DeliveryColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(DeliveryRadius.sheet)),
    ),
    builder: (BuildContext context) =>
        _RateProviderSheet(api: api, storeId: storeId, orderId: orderId, shopName: shopName),
  );
}

class _RateProviderSheet extends StatefulWidget {
  const _RateProviderSheet({
    required this.api,
    required this.storeId,
    required this.orderId,
    required this.shopName,
  });

  final StoreApi api;
  final String storeId;
  final String orderId;
  final String shopName;

  @override
  State<_RateProviderSheet> createState() => _RateProviderSheetState();
}

class _RateProviderSheetState extends State<_RateProviderSheet> {
  /// product-service's `@Size(max = 2000)` on a review's comment.
  static const int _commentLimit = 2000;

  final TextEditingController _comment = TextEditingController();

  /// 0 until a star is tapped; the button stays disabled, since a rating of nothing is not a rating.
  int _stars = 0;

  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars < 1 || _sending) return;
    final DeliveryStrings t = DeliveryStrings.of(context);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final StoreReview review = await widget.api.submitReview(
        widget.storeId,
        orderId: widget.orderId,
        rating: _stars,
        comment: _comment.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(review);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.response?.statusCode == 404 ? t.svcReviewNotYet : t.custCouldNotSendRating;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = t.custCouldNotSendRating;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Padding(
      // Lifts the sheet clear of the keyboard while the comment is being typed.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
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
              Text(
                t.svcRateProvider(widget.shopName),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: DeliveryColors.ink, height: 1.25),
              ),
              const SizedBox(height: DeliverySpacing.xs),
              Text(
                t.svcRateProviderPrompt,
                style: const TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.35),
              ),
              const SizedBox(height: DeliverySpacing.lg),
              _starRow(t),
              const SizedBox(height: DeliverySpacing.lg),
              TextField(
                controller: _comment,
                minLines: 2,
                maxLines: 4,
                inputFormatters: const <TextInputFormatter>[Utf16LengthLimit(_commentLimit)],
                style: const TextStyle(fontSize: 13, color: DeliveryColors.ink, height: 1.4),
                decoration: _boxDecoration(t.custAddCommentOptional),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: DeliverySpacing.sm),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 12, color: DeliveryAccent.critical.color, height: 1.35),
                ),
              ],
              const SizedBox(height: DeliverySpacing.lg),
              YdPillButton(
                label: t.submitReview,
                busy: _sending,
                onPressed: _stars < 1 || _sending ? null : _submit,
              ),
              const SizedBox(height: DeliverySpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  /// Five 36px stars, each with a 48dp square to tap.
  Widget _starRow(DeliveryStrings t) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int star = 1; star <= 5; star++)
          Semantics(
            button: true,
            selected: star <= _stars,
            label: t.ratingStars(star),
            child: InkWell(
              borderRadius: BorderRadius.circular(DeliveryRadius.pill),
              onTap: _sending ? null : () => setState(() => _stars = star),
              child: Padding(
                padding: const EdgeInsetsDirectional.all(6),
                child: Icon(
                  star <= _stars ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 36,
                  color: star <= _stars ? DeliveryAccent.caution.color : DeliveryColors.border,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// The design's plain input box, as the rider sheet and checkout draw it.
  InputDecoration _boxDecoration(String hint) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: DeliveryColors.white,
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: DeliveryColors.faint, height: 1.4),
      contentPadding: const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
      border: border(DeliveryColors.border, 1),
      enabledBorder: border(DeliveryColors.border, 1),
      focusedBorder: border(DeliveryColors.brand, 1.5),
    );
  }
}
