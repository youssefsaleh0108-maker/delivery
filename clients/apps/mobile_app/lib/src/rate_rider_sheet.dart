import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';


/// The post-delivery rating sheet: five stars and an optional sentence, once per order.
///
/// Returns the stored [RiderRatingEntry] when a rating was submitted, or null when the customer
/// backed out. A 409 — somebody rated from another device between the button and the sheet — is
/// shown as the already-rated sentence rather than an error, because it is not one.
Future<RiderRatingEntry?> showRateRiderSheet(
  BuildContext context, {
  required OrderApi api,
  required String orderId,
}) {
  return showModalBottomSheet<RiderRatingEntry>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DeliveryColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(DeliveryRadius.sheet)),
    ),
    builder: (BuildContext context) => _RateRiderSheet(api: api, orderId: orderId),
  );
}

class _RateRiderSheet extends StatefulWidget {
  const _RateRiderSheet({required this.api, required this.orderId});

  final OrderApi api;
  final String orderId;

  @override
  State<_RateRiderSheet> createState() => _RateRiderSheetState();
}

class _RateRiderSheetState extends State<_RateRiderSheet> {
  final TextEditingController _comment = TextEditingController();

  /// 0 until the customer taps a star; the button stays disabled — a rating of nothing is not a
  /// rating.
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
      final String text = _comment.text.trim();
      final RiderRatingEntry entry = await widget.api
          .rateRider(widget.orderId, _stars, text: text.isEmpty ? null : text);
      if (!mounted) return;
      Navigator.of(context).pop(entry);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        // 409: already rated, likely from another device. Not an error — say what happened.
        _error = e.response?.statusCode == 409
            ? t.custAlreadyRatedDelivery
            : t.custCouldNotSendRating;
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
                t.custRateYourRider,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.ink,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: DeliverySpacing.xs),
              Text(
                t.custHowWasDelivery,
                style: const TextStyle(
                  fontSize: 13,
                  color: DeliveryColors.muted,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: DeliverySpacing.lg),
              _starRow(t),
              const SizedBox(height: DeliverySpacing.lg),
              TextField(
                controller: _comment,
                minLines: 2,
                maxLines: 4,
                style: const TextStyle(
                    fontSize: 13, color: DeliveryColors.ink, height: 1.4),
                decoration: _boxDecoration(t.custAddCommentOptional),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: DeliverySpacing.sm),
                Text(
                  _error!,
                  style: TextStyle(
                    fontSize: 12,
                    color: DeliveryAccent.critical.color,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: DeliverySpacing.lg),
              YdPillButton(
                label: t.custSubmitRating,
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
              onTap: () => setState(() => _stars = star),
              child: Padding(
                padding: const EdgeInsetsDirectional.all(DeliverySpacing.xs),
                child: Icon(
                  star <= _stars ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 36,
                  color: star <= _stars
                      ? DeliveryAccent.caution.color
                      : DeliveryColors.border,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// The design's plain input box, as checkout draws it.
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
