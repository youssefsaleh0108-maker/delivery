import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// The first thing anyone sees: a full-bleed red field with the wordmark.
///
/// Doubles as the loading state and the sign-in state, on purpose. Sign-in is automatic — there is
/// no button to press — so a separate "please sign in" screen would be a dead end the user is
/// pushed through rather than a decision they make. Holding one branded screen across bootstrap and
/// redirect means the app never flashes an empty scaffold on the way to Keycloak.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.error, this.onRetry, this.onApply});

  /// How long the brand screen is held before the app redirects to sign-in.
  ///
  /// Without a floor the screen is a flash: bootstrap resolves in well under a second, and the
  /// only thing the customer sees is a red flicker on the way to Keycloak. Long enough to read
  /// the name, short enough not to be a toll gate.
  static const Duration hold = Duration(milliseconds: 1900);

  /// Set when automatic sign-in failed. Turns the screen into something actionable rather than an
  /// indefinite spinner.
  final Object? error;
  final VoidCallback? onRetry;

  /// Opens the rider application. Shown only once signing in has failed — see the note below.
  final VoidCallback? onApply;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  /// One controller driving a staggered entrance — mark, then name, then tagline. Staggering is
  /// what makes it read as an intro rather than as three things that happened to fade in at once.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  late final Animation<double> _markFade = _curve(0.00, 0.45, Curves.easeOut);
  late final Animation<double> _markScale = Tween<double>(begin: 0.82, end: 1)
      .animate(_curve(0.00, 0.55, Curves.easeOutBack));
  late final Animation<double> _nameFade = _curve(0.30, 0.75, Curves.easeOut);
  late final Animation<double> _nameRise = Tween<double>(begin: 14, end: 0)
      .animate(_curve(0.30, 0.75, Curves.easeOutCubic));
  late final Animation<double> _tailFade = _curve(0.55, 1.00, Curves.easeOut);

  Animation<double> _curve(double begin, double end, Curve curve) =>
      CurvedAnimation(parent: _controller, curve: Interval(begin, end, curve: curve));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool failed = widget.error != null;

    return Scaffold(
      backgroundColor: DeliveryColors.brand,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(DeliverySpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // The mark, the way a launcher icon reads: white tile, rose mark. Inverted from
                // the app bar's white-on-rose, because here the field behind it is already rose.
                FadeTransition(
                  opacity: _markFade,
                  child: ScaleTransition(
                    scale: _markScale,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const DeliveryLogo(
                        size: 96,
                        background: DeliveryColors.white,
                        foreground: DeliveryColors.brand,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: DeliverySpacing.lg),

                // The wordmark. Heavy, tight tracking, white on red — the shape a delivery brand
                // takes. Translated, so the Arabic build shows the Arabic name rather than a
                // transliteration.
                FadeTransition(
                  opacity: _nameFade,
                  child: AnimatedBuilder(
                    animation: _nameRise,
                    builder: (BuildContext context, Widget? child) => Transform.translate(
                      offset: Offset(0, _nameRise.value),
                      child: child,
                    ),
                    child: Text(
                      DeliveryStrings.of(context).appTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: DeliverySpacing.sm),
                FadeTransition(
                  opacity: _tailFade,
                  child: Text(
                    DeliveryStrings.of(context).splashTagline,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14.5,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: DeliverySpacing.xxl),

                if (!failed)
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                else ...<Widget>[
                  Text(
                    DeliveryStrings.of(context).signInFailed,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95), fontSize: 14),
                  ),
                  const SizedBox(height: DeliverySpacing.md),
                  FilledButton(
                    onPressed: widget.onRetry,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: DeliveryColors.brand,
                      minimumSize: const Size(180, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(DeliveryRadius.md)),
                    ),
                    child: Text(DeliveryStrings.of(context).tryAgain,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  // The way in for somebody who has no account and cannot get one by trying again.
                  //
                  // It belongs on this state and not the loading one: a would-be rider opens the
                  // app, is sent to sign in, has nothing to sign in with, and lands back here.
                  // That is the moment they need this — offering it during the intro would put it
                  // on screen for a second and a half, mostly in front of customers who are being
                  // signed in anyway.
                  if (widget.onApply != null) ...<Widget>[
                    const SizedBox(height: DeliverySpacing.lg),
                    TextButton(
                      onPressed: widget.onApply,
                      child: Text(
                        DeliveryStrings.of(context).wantToRideForACompany,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.95),
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
