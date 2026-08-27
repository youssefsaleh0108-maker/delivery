import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'biometric_lock.dart';

/// App settings — how the app behaves, as distinct from who you are.
///
/// The redesign merges these two questions on the customer surface, and that merged page is the
/// customer's Account tab (`customer-settings`, node 3:686). This screen is what the *other*
/// surfaces reach: a rider or a merchant has no account tab to merge it into, and both open it from
/// the gear in their own header. It is drawn in the same visual language as the merged page — the
/// white 56px header, the bordered language row with its EN/AR segmented toggle, and the radius-16
/// menu rows — so the two are the same page in two places rather than two designs.
///
/// Language sits here because it is a property of the app, not of the person — the same account on
/// two devices can reasonably read in two languages.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.locale, this.userId});

  final LocaleController locale;

  /// Whose fingerprint setting this is. Null on a surface with no session, in which case the
  /// unlock section is not offered at all — there would be nothing to lock.
  final String? userId;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final BiometricLock _biometrics = BiometricLock();

  /// Null until the checks answer. The row is not drawn while it is null rather than drawn off — a
  /// switch that flicks itself on a moment after the screen opens looks like the app changing a
  /// security setting by itself.
  bool? _enabled;
  bool _available = false;

  /// True while the system prompt is out, so the row can say something is happening.
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bool available = await _biometrics.isAvailable;
    final bool enabled = await _biometrics.isEnabledFor(widget.userId);
    if (!mounted) return;
    setState(() {
      _available = available;
      _enabled = enabled;
    });
  }

  Future<void> _set(bool on) async {
    final DeliveryStrings t = DeliveryStrings.of(context);

    // Busy while the platform call is out. Without it the switch sits there doing nothing visible
    // and the whole thing reads as hung — which is exactly what it looked like on a phone with no
    // finger enrolled, where the prompt never appears because there is nothing to match against.
    setState(() => _working = true);
    try {
      if (on) {
        // Proved before it is turned on, never after. Enabling on the strength of the sensor merely
        // existing is how somebody locks themselves out with a finger the phone does not recognise.
        final BiometricResult result = await _biometrics.authenticate(t.unlockWithFingerprint);
        if (result != BiometricResult.ok) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 6),
            content: Text(result == BiometricResult.unavailable
                ? t.fingerprintNotSetUp
                : t.couldNotVerifyYou),
          ));
          return;
        }
      }

      await _biometrics.setEnabledFor(widget.userId, on);
      if (!mounted) return;
      setState(() => _enabled = on);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return AnimatedBuilder(
      animation: widget.locale,
      builder: (BuildContext context, _) => Scaffold(
        backgroundColor: DeliveryColors.background,
        appBar: YdScreenHeader(
          title: t.settings,
          onBack: () => Navigator.of(context).maybePop(),
          backSemanticLabel: t.back,
        ),
        body: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            AppLanguageRow(locale: widget.locale, label: t.custAppLanguage),
            Padding(
              padding: const EdgeInsets.all(DeliverySpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (widget.userId != null && _available && _enabled != null) ...<Widget>[
                    YdListRow(
                      icon: Icons.fingerprint,
                      title: t.biometricUnlock,
                      subtitle: t.fingerprintKeepsYourAccountClosed,
                      trailing: _working
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Switch(
                              value: _enabled!,
                              activeThumbColor: DeliveryColors.white,
                              activeTrackColor: DeliveryColors.brand,
                              onChanged: _set,
                            ),
                    ),
                    const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                  ],
                  // Nothing else is claimed here on purpose. A settings page padded with switches
                  // that are not wired to anything is worse than a short one.
                  Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: DeliverySpacing.xs),
                    child: Text(
                      t.appTitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: DeliveryColors.faint,
                        height: 1.35,
                      ),
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

/// The redesign's `language-selector` (node 3:703): a full-width white row with a 1px border all
/// round, 20px padding, a 20px globe and a SemiBold 14 label on the start side, and a segmented
/// EN/AR toggle on the end.
///
/// The toggle's track is the page background at radius 20 with 2px of padding; the chosen segment
/// is a white radius-18 pill with the card shadow and a Bold 12 brand label, the other transparent
/// with a SemiBold 12 muted one.
///
/// Each segment keeps its own script's abbreviation rather than being translated, so the option you
/// cannot currently read is still the one you can point at. [label] arrives already localised.
class AppLanguageRow extends StatelessWidget {
  const AppLanguageRow({super.key, required this.locale, required this.label});

  final LocaleController locale;

  /// "App Language", already localised.
  final String label;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: locale,
      builder: (BuildContext context, _) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: DeliveryColors.white,
          border: Border.fromBorderSide(BorderSide(color: DeliveryColors.border)),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.language, size: 20, color: DeliveryColors.brand),
            const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: DeliveryColors.ink,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(width: DeliverySpacing.sm),
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: DeliveryColors.background,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _segment(context, 'en', 'EN', !locale.isArabic),
                  const SizedBox(width: DeliverySpacing.xs),
                  _segment(context, 'ar', 'AR', locale.isArabic),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment(BuildContext context, String code, String text, bool active) {
    return Semantics(
      button: true,
      selected: active,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: active ? YdCard.softShadow : null,
        ),
        child: Material(
          color: active ? DeliveryColors.white : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: active ? null : () => locale.setLanguage(code),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: DeliverySpacing.md,
                vertical: DeliverySpacing.sm - 2,
              ),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? DeliveryColors.brand : DeliveryColors.muted,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
