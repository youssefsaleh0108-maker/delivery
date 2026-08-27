import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The auth surface's shared parts: the code entry, and the field/button/step furniture every
/// signed-out screen in the 2026-08 Figma redesign is built from.
///
/// <p>This file started as the one-time code alone — there were two of those, the shopper's
/// sign-up drawing a large centred field and the partner application an ordinary labelled
/// TextField with a character counter, for the same six digits against the same server. Sharing it
/// is what stopped them drifting.
///
/// <p>The redesign gave the same problem to every other control on these screens: eight frames
/// draw the identical labelled input, the identical radius-16 button and the identical wizard step
/// header. They live here for the same reason the code field does.
///
/// <p>Everything here takes strings the caller has already localised, and lays out with
/// directional insets so the whole surface mirrors in Arabic.

// ---------------------------------------------------------------------------- the code

/// How a six-digit code is entered, everywhere it is entered.
///
/// <p>Figma `customer-otp` (22:165) draws four cells, for an SMS code. This platform sends a
/// six-digit code to an *email address* — the endpoint pair behind every flow here — so six cells
/// are rendered in the design's exact cell style. That deviation is forced by the backend, not
/// chosen: rendering four would mean refusing two digits of a code the server actually sent.
class OneTimeCodeField extends StatelessWidget {
  const OneTimeCodeField({
    super.key,
    required this.controller,
    required this.onCompleted,
    this.enabled = true,
    this.autofocus = false,
    this.hasError = false,
  });

  static const int length = 6;

  final TextEditingController controller;

  /// Called on the last digit. Asking somebody to type six digits and then reach for a button is a
  /// step with no purpose, so the button below is a fallback rather than the way through.
  final VoidCallback onCompleted;

  final bool enabled;
  final bool autofocus;

  /// Paints every cell in the critical accent — for a code the server refused.
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return YdOtpCells(
      length: length,
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      hasError: hasError,
      semanticLabel: DeliveryStrings.of(context).enterTheCode,
      onCompleted: (String _) {
        if (enabled) onCompleted();
      },
    );
  }
}

/// Says what was actually sent, to whom, and for how long it lasts.
///
/// The partner application used to reveal a code box and say nothing at all, which leaves somebody
/// staring at an empty field wondering whether anything was sent, to which address, and whether
/// tapping the button again would help.
class OneTimeCodeSentNote extends StatelessWidget {
  const OneTimeCodeSentNote({super.key, required this.destination});

  /// As the server normalised it, not as it was typed — that is the address the message went to.
  final String destination;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return SoftNote(
      icon: Icons.mark_email_read_outlined,
      text: t.codeSentTo(destination),
    );
  }
}

// ---------------------------------------------------------------------------- fields

/// The redesign's labelled input (Figma `input-field`, e.g. 22:443, 22:66, 22:902).
///
/// Measured: a SemiBold 13 label, then a white box with a 1px hairline, radius
/// [DeliveryRadius.md], 14px padding, an optional 18px leading glyph in [DeliveryColors.faint],
/// 14px [DeliveryColors.ink] text and a [DeliveryColors.faint] placeholder.
///
/// The frames disagree about two details and the disagreement is carried as parameters rather than
/// averaged away: the customer screens draw the hairline in [DeliveryColors.borderFaint] and the
/// partner wizards in [DeliveryColors.border]; the rider wizard uppercases its labels and nothing
/// else does. The label colour is [DeliveryColors.ink] by default — the customer frames draw
/// slate-700, which the token layer does not carry and which sits within a shade of ink at this
/// weight and size.
class AuthField extends StatefulWidget {
  const AuthField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.icon,
    this.keyboardType,
    this.textInputAction,
    this.obscure = false,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.autofocus = false,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.trailing,
    this.borderColor = DeliveryColors.borderFaint,
    this.labelColor = DeliveryColors.ink,
    this.uppercaseLabel = false,
    this.verified = false,
  });

  /// Already localised by the caller.
  final String label;

  final TextEditingController controller;

  /// Placeholder, already localised.
  final String? hint;

  /// 18px leading glyph. The customer frames draw none; the partner wizards draw one per field.
  final IconData? icon;

  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  /// Starts hidden behind the design's eye toggle. The toggle is drawn only when this is true.
  final bool obscure;

  final bool enabled;
  final bool readOnly;
  final int maxLines;
  final bool autofocus;
  final List<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// End-slot widget, replacing the eye toggle — a chevron for a picker, a chip for a control that
  /// does not work yet.
  final Widget? trailing;

  final Color borderColor;
  final Color labelColor;
  final bool uppercaseLabel;

  /// Shows the design's confirmation tick — for an address the server has already proved.
  final bool verified;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  late bool _hidden = widget.obscure;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    Widget? suffix = widget.trailing;
    if (suffix == null && widget.verified) {
      suffix = Icon(Icons.check_circle,
          size: 18, color: DeliveryAccent.positive.color);
    }
    if (suffix == null && widget.obscure) {
      suffix = Semantics(
        button: true,
        label: _hidden ? t.authShowPassword : t.authHidePassword,
        child: InkResponse(
          onTap: () => setState(() => _hidden = !_hidden),
          radius: 20,
          child: Icon(
            _hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 20,
            color: DeliveryColors.faint,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AuthFieldLabel(
          label: widget.label,
          color: widget.labelColor,
          uppercase: widget.uppercaseLabel,
        ),
        const SizedBox(height: 6),
        TextField(
          controller: widget.controller,
          enabled: widget.enabled,
          readOnly: widget.readOnly,
          autofocus: widget.autofocus,
          obscureText: _hidden,
          maxLines: widget.obscure ? 1 : widget.maxLines,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          autofillHints: widget.autofillHints,
          textCapitalization: widget.textCapitalization,
          inputFormatters: widget.inputFormatters,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          style: const TextStyle(
            fontSize: 14,
            color: DeliveryColors.ink,
            height: 1.3,
          ),
          decoration: InputDecoration(
            hintText: widget.hint,
            isDense: true,
            // The design's own 14px box padding, tighter than the theme's default.
            contentPadding: const EdgeInsetsDirectional.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            prefixIcon: widget.icon == null
                ? null
                : Padding(
                    padding: const EdgeInsetsDirectional.only(
                        start: 14, end: 10),
                    child: Icon(widget.icon,
                        size: 18, color: DeliveryColors.faint),
                  ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
            suffixIcon: suffix == null
                ? null
                : Padding(
                    padding: const EdgeInsetsDirectional.only(end: 14),
                    child: suffix,
                  ),
            suffixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
              borderSide: BorderSide(color: widget.borderColor),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
              borderSide: BorderSide(color: widget.borderColor),
            ),
          ),
        ),
      ],
    );
  }
}

/// The SemiBold 13 label that sits above every input, and above the design's non-input groups
/// (`VEHICLE TYPE`, `AVAILABLE ZONES`) too.
class AuthFieldLabel extends StatelessWidget {
  const AuthFieldLabel({
    super.key,
    required this.label,
    this.color = DeliveryColors.ink,
    this.uppercase = false,
  });

  /// Already localised by the caller.
  final String label;
  final Color color;
  final bool uppercase;

  @override
  Widget build(BuildContext context) {
    return Text(
      uppercase ? label.toUpperCase() : label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: color,
        height: 1.2,
      ),
    );
  }
}

/// A field-shaped control that opens a picker instead of a keyboard — the design's Business Type
/// box (22:912), drawn as an input with a chevron.
class AuthPickerField extends StatelessWidget {
  const AuthPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.hint,
    required this.options,
    required this.onSelected,
    this.enabled = true,
    this.borderColor = DeliveryColors.border,
    this.labelColor = DeliveryColors.ink,
    this.uppercaseLabel = false,
  });

  /// Already localised by the caller.
  final String label;

  /// The chosen option's localised label, or null for the placeholder.
  final String? value;

  /// Placeholder, already localised.
  final String hint;

  /// Localised option labels, in the order they should be offered.
  final List<String> options;

  final ValueChanged<int> onSelected;
  final bool enabled;
  final Color borderColor;
  final Color labelColor;
  final bool uppercaseLabel;

  Future<void> _open(BuildContext context) async {
    final int? picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: DeliveryColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DeliveryRadius.sheet),
        ),
      ),
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: DeliveryColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: DeliverySpacing.sm),
            for (int i = 0; i < options.length; i++)
              ListTile(
                title: Text(options[i],
                    style: const TextStyle(
                        fontSize: 15, color: DeliveryColors.ink)),
                trailing: options[i] == value
                    ? const Icon(Icons.check, color: DeliveryColors.brand)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(i),
              ),
            const SizedBox(height: DeliverySpacing.sm),
          ],
        ),
      ),
    );
    if (picked != null) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AuthFieldLabel(
            label: label, color: labelColor, uppercase: uppercaseLabel),
        const SizedBox(height: 6),
        Semantics(
          button: true,
          label: label,
          value: value,
          child: Material(
            color: DeliveryColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
              side: BorderSide(color: borderColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? () => _open(context) : null,
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 14, vertical: 14),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        value ?? hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: value == null
                              ? DeliveryColors.faint
                              : DeliveryColors.ink,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: DeliverySpacing.sm),
                    const Icon(Icons.keyboard_arrow_down,
                        size: 20, color: DeliveryColors.faint),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------- buttons

/// The auth surface's call to action (Figma `primary-button`, e.g. 22:79, 22:157, 24:83).
///
/// A rectangle at [DeliveryRadius.lg], not the customer app's pill: every signed-out frame draws
/// the 16-radius button, and the shared [ElevatedButton] theme shapes its own to
/// [DeliveryRadius.pill]. Rather than fight the theme on nine screens, the shape lives here.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.height = 52,
    this.trailingIcon,
    this.onWhite = false,
  });

  /// Already localised by the caller.
  final String label;

  /// `null` disables it, which is also how the design draws an inactive CTA.
  final VoidCallback? onPressed;

  final bool busy;

  /// 52 on the form screens, 56 on the two intro screens. Both are the design's own.
  final double height;

  /// The design's trailing arrow on the merchant wizard's "Next Step".
  final IconData? trailingIcon;

  /// The inverted dialect the rider's pending screen draws on the brand background: white fill,
  /// brand label.
  final bool onWhite;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !busy;
    final Color background = onWhite
        ? DeliveryColors.white
        : enabled
            ? DeliveryColors.brand
            : DeliveryColors.brandLine;
    final Color foreground =
        onWhite ? DeliveryColors.brand : DeliveryColors.white;
    final BorderRadius corners = BorderRadius.circular(DeliveryRadius.lg);

    return SizedBox(
      width: double.infinity,
      height: height,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(borderRadius: corners),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: Center(
            child: busy
                ? SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(foreground),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: foreground,
                            height: 1.2,
                          ),
                        ),
                      ),
                      if (trailingIcon != null) ...<Widget>[
                        const SizedBox(width: DeliverySpacing.sm + 2),
                        Icon(trailingIcon, size: 20, color: foreground),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// The footer sentence every auth frame ends on: a muted question and a brand answer that is the
/// tap target (Figma 22:94, 22:159, 24:22).
///
/// Two [Text]s in a wrapping row rather than one rich string, so the brand half stays a real
/// button for a screen reader and the pair reflows instead of clipping in Arabic.
class AuthFooterLink extends StatelessWidget {
  const AuthFooterLink({
    super.key,
    required this.question,
    required this.action,
    required this.onTap,
    this.questionColor = DeliveryColors.muted,
    this.actionColor = DeliveryColors.brand,
  });

  /// Already localised by the caller.
  final String question;

  /// Already localised by the caller.
  final String action;

  final VoidCallback? onTap;
  final Color questionColor;
  final Color actionColor;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: DeliverySpacing.xs,
      children: <Widget>[
        Text(
          question,
          style: TextStyle(fontSize: 14, color: questionColor, height: 1.3),
        ),
        Semantics(
          button: true,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(DeliveryRadius.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
              child: Text(
                action,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: actionColor,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------- wizard furniture

/// The 36px circular back button the signup wizards draw (Figma 22:434): white, a 1px
/// [DeliveryColors.border] hairline, fully rounded, with a chevron that mirrors in Arabic.
///
/// Distinct from the design system's [YdBackButton], which is the 32px background-filled one the
/// signed-in screen headers use.
class AuthBackButton extends StatelessWidget {
  const AuthBackButton({
    super.key,
    required this.onPressed,
    this.semanticLabel,
    this.color = DeliveryColors.white,
    this.borderColor = DeliveryColors.border,
    this.iconColor = DeliveryColors.ink,
  });

  final VoidCallback? onPressed;

  /// Localised accessibility label supplied by the caller.
  final String? semanticLabel;

  final Color color;
  final Color borderColor;
  final Color iconColor;

  static const double dimension = 36;

  @override
  Widget build(BuildContext context) {
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: color,
        shape: CircleBorder(side: BorderSide(color: borderColor)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: dimension,
            child: Icon(
              rtl ? Icons.chevron_right : Icons.chevron_left,
              size: 16,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// The head of every wizard step (Figma 22:432, 22:491, 22:614, 22:889).
///
/// A row holding the back button and the brand step counter, the shared [YdStepper] track beneath
/// it, then the step's Bold 22 title and its 13 muted line. The merchant frames put the counter and
/// a completion percentage above a segmented track; the rider frames put the counter opposite the
/// back button above a continuous one. Both shapes are here because both are drawn.
class AuthStepHeader extends StatelessWidget {
  const AuthStepHeader({
    super.key,
    required this.step,
    required this.totalSteps,
    required this.stepLabel,
    required this.title,
    required this.subtitle,
    this.onBack,
    this.backSemanticLabel,
    this.progressLabel,
    this.segmented = false,
  });

  /// 1-based.
  final int step;
  final int totalSteps;

  /// "Step 2 of 4", already localised and formatted by the caller.
  final String stepLabel;

  /// Already localised by the caller.
  final String title;

  /// Already localised by the caller.
  final String subtitle;

  final VoidCallback? onBack;
  final String? backSemanticLabel;

  /// "50% Complete", already localised — the merchant frames draw it, the rider frames do not.
  final String? progressLabel;

  final bool segmented;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (onBack != null) ...<Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              AuthBackButton(
                onPressed: onBack,
                semanticLabel: backSemanticLabel,
              ),
              if (progressLabel == null)
                Text(
                  stepLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.brand,
                    height: 1.2,
                  ),
                ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        ],
        YdStepper(
          step: step,
          totalSteps: totalSteps,
          // Without a back button the counter has nowhere else to go, so the stepper carries it.
          stepLabel: (onBack == null || progressLabel != null) ? stepLabel : null,
          progressLabel: progressLabel,
          segmented: segmented,
          trackHeight: segmented ? 6 : 4,
        ),
        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
            height: 1.25,
          ),
        ),
        const SizedBox(height: DeliverySpacing.xs),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 13,
            color: DeliveryColors.muted,
            height: 18 / 13,
          ),
        ),
      ],
    );
  }
}

/// The design's error surface for these screens: the brand-tinted note with a critical glyph.
///
/// A shared widget because all five auth screens grew their own copy of it, and they had already
/// drifted apart on padding and radius before the redesign gave them one shape.
class AuthErrorNote extends StatelessWidget {
  const AuthErrorNote({super.key, required this.message});

  /// Already localised, or the server's own words — those are written to be acted on.
  final String message;

  @override
  Widget build(BuildContext context) {
    return SoftNote(
      text: message,
      icon: Icons.error_outline,
      accent: DeliveryAccent.critical,
    );
  }
}

/// The map slot the region step draws (Figma `map-canvas-container` 22:624), painted as the styled
/// placeholder it is.
///
/// There is no map in this wave — no tile source, no zone geometry, nothing to plot. The design's
/// 180px, radius-[DeliveryRadius.lg], hairlined box is reproduced exactly and filled with a faint
/// grid and a pin, so the layout below it sits where it was drawn to sit and nobody mistakes it for
/// a map that failed to load.
class AuthMapPlaceholder extends StatelessWidget {
  const AuthMapPlaceholder({super.key, required this.label, this.height = 180});

  /// Already localised by the caller.
  final String label;

  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: label,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: DeliveryColors.background,
          borderRadius: BorderRadius.circular(DeliveryRadius.lg),
          border: Border.all(color: DeliveryColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            CustomPaint(painter: _MapGridPainter()),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.place_outlined,
                      size: 28, color: DeliveryColors.brand),
                  const SizedBox(height: DeliverySpacing.sm),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: DeliveryColors.muted,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  static const double _cell = 28;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = DeliveryColors.border
      ..strokeWidth = 1;
    for (double x = _cell; x < size.width; x += _cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = _cell; y < size.height; y += _cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MapGridPainter oldDelegate) => false;
}
