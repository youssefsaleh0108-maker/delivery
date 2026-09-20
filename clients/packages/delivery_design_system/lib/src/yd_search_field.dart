import 'package:flutter/material.dart';

import 'tokens.dart';

/// The redesign's search input (Figma `search-bar`, reused verbatim on `customer-home` 3:27 and
/// the butler page 20:21, and again on the merchant and rider lists).
///
/// Measured: [DeliveryColors.background] fill on a white header, radius [DeliveryRadius.md],
/// 12px padding all round, 10px gap, an 18px leading search glyph, a flexed 14px placeholder in
/// [DeliveryColors.faint], and an optional 18px trailing filter glyph.
///
/// Set [readOnly] with [onTap] for the frames where the "search bar" is really a button that
/// opens a search screen — the field then still looks identical but never raises a keyboard.
///
/// With [onCameraTap] and [cameraSemanticLabel] both set, a camera sits at the trailing end, after the
/// filter glyph: search by photo. It is a full 48 dp touch target, so the field is 48 dp tall while it
/// shows (the design's 12 px padding runs into the target rather than adding to it); without it the
/// field is exactly as drawn. A caller sets it only when a photo search can actually run — never a
/// camera that cannot work.
class YdSearchField extends StatelessWidget {
  const YdSearchField({
    super.key,
    required this.hintText,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.readOnly = false,
    this.autofocus = false,
    this.textInputAction = TextInputAction.search,
    this.onFilterTap,
    this.filterIcon = Icons.tune,
    this.filterSemanticLabel,
    this.searchSemanticLabel,
    this.animatedHint,
    this.onCameraTap,
    this.cameraSemanticLabel,
  });

  /// The touch target of the camera action: Material's minimum.
  static const double cameraTarget = 48;

  /// Placeholder text, already localised by the caller.
  final String hintText;

  /// An optional live placeholder — e.g. an [AnimatedSwitcher] cycling suggestions — painted in
  /// the hint's spot while the field is empty. It replaces [hintText] whenever it is non-null
  /// and needs a [controller] to know when the field has text.
  final Widget? animatedHint;

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Tapping the field. With [readOnly] this turns the whole thing into a navigation affordance.
  final VoidCallback? onTap;

  final bool readOnly;
  final bool autofocus;
  final TextInputAction textInputAction;

  /// Shows the design's trailing filter glyph when non-null.
  final VoidCallback? onFilterTap;

  final IconData filterIcon;

  /// Accessibility labels, localised by the caller.
  final String? filterSemanticLabel;
  final String? searchSemanticLabel;

  /// Search by photo. Drawn only when this and [cameraSemanticLabel] are both set.
  final VoidCallback? onCameraTap;

  /// What a screen reader says for the camera, localised by the caller.
  final String? cameraSemanticLabel;

  bool get _hasCamera => onCameraTap != null && cameraSemanticLabel != null;

  /// Stand-in listenable when [animatedHint] is used without a [controller]; the field then has
  /// no way to gain text we could observe, so a permanently-empty value is the truth.
  static final TextEditingController _emptyController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DeliveryColors.background,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      // With the camera, its 48 dp target stands in for the padding at the trailing end and sets the
      // height, and the rest of the row centres on it.
      padding: _hasCamera
          ? const EdgeInsetsDirectional.only(start: DeliverySpacing.md - DeliverySpacing.xs)
          : const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.search,
            size: 18,
            color: DeliveryColors.faint,
            semanticLabel: searchSemanticLabel,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Stack(
              alignment: AlignmentDirectional.centerStart,
              children: <Widget>[
                if (animatedHint != null)
                  Positioned.fill(
                    child: ExcludeSemantics(
                      child: IgnorePointer(
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable:
                              controller ?? _emptyController,
                          builder: (BuildContext context,
                              TextEditingValue value, Widget? hint) {
                            return Visibility(
                              visible: value.text.isEmpty,
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: hint,
                              ),
                            );
                          },
                          child: animatedHint,
                        ),
                      ),
                    ),
                  ),
                TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  onTap: onTap,
                  readOnly: readOnly,
                  autofocus: autofocus,
                  textInputAction: textInputAction,
                  style: const TextStyle(
                    fontSize: 14,
                    color: DeliveryColors.ink,
                    height: 1.2,
                  ),
                  cursorColor: DeliveryColors.brand,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: animatedHint == null ? hintText : null,
                    hintStyle: const TextStyle(
                      fontSize: 14,
                      color: DeliveryColors.faint,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (onFilterTap != null) ...<Widget>[
            const SizedBox(width: 10),
            Semantics(
              button: true,
              label: filterSemanticLabel,
              child: InkResponse(
                onTap: onFilterTap,
                radius: 18,
                child: Icon(filterIcon, size: 18, color: DeliveryColors.brand),
              ),
            ),
          ],
          if (_hasCamera)
            Semantics(
              button: true,
              label: cameraSemanticLabel,
              excludeSemantics: true,
              child: InkResponse(
                onTap: onCameraTap,
                radius: cameraTarget / 2,
                child: const SizedBox.square(
                  dimension: cameraTarget,
                  child: Center(
                    child: Icon(Icons.photo_camera_outlined, size: 20, color: DeliveryColors.brand),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
