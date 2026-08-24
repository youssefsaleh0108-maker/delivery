import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'biometric_lock.dart';

/// App settings — how the app behaves, as distinct from who you are.
///
/// Split from the Account tab deliberately. An account page answers "who am I and where do I live";
/// settings answer "how should this thing work". Language sits here because it is a property of the
/// app, not of the person — the same account on two devices can reasonably read in two languages.
///
/// Reached from the gear in the home app bar rather than from a tab: it is a place you visit
/// rarely and leave, which is what a pushed route means and what a tab does not.
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
    final LocaleController locale = widget.locale;

    return AnimatedBuilder(
      animation: locale,
      builder: (BuildContext context, _) => Scaffold(
        backgroundColor: DeliveryColors.background,
        appBar: AppBar(
          backgroundColor: DeliveryColors.brand,
          foregroundColor: DeliveryColors.white,
          elevation: 0,
          title: Text(DeliveryStrings.of(context).settings, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: ListView(
          padding: const EdgeInsets.all(DeliverySpacing.md),
          children: <Widget>[
            _card(DeliveryStrings.of(context).language, <Widget>[
              // Radios, not a toggle. A toggle is fine when a control has an obvious on-state;
              // a language does not — both options have to be readable by someone who cannot read
              // the other one, which is why each row is written in its own script.
              RadioGroup<String>(
                groupValue: locale.isArabic ? 'ar' : 'en',
                onChanged: (String? code) {
                  if (code != null) locale.setLanguage(code);
                },
                child: Column(
                  children: <Widget>[
                    for (final ({String code, String label}) option
                        in const <({String code, String label})>[
                      (code: 'en', label: 'English'),
                      (code: 'ar', label: 'العربية'),
                    ])
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: option.code,
                        activeColor: DeliveryColors.brand,
                        title: Text(option.label,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                      ),
                  ],
                ),
              ),
            ]),
            // Here rather than on the Account tab, which is where it was and which only exists on
            // the customer surface — so a merchant, a rider or an applicant could never reach it.
            if (widget.userId != null && _available && _enabled != null) ...<Widget>[
              const SizedBox(height: DeliverySpacing.md),
              _card(DeliveryStrings.of(context).biometricUnlock, <Widget>[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _enabled!,
                  onChanged: _working ? null : _set,
                  secondary: _working
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.fingerprint, color: DeliveryColors.brand),
                  title: Text(DeliveryStrings.of(context).useFingerprintNextTime,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                  subtitle: Text(
                      DeliveryStrings.of(context).fingerprintKeepsYourAccountClosed,
                      style: const TextStyle(fontSize: 12.5)),
                ),
              ]),
            ],
            const SizedBox(height: DeliverySpacing.md),
            // Nothing else is claimed here on purpose. A settings page padded with switches that
            // are not wired to anything is worse than a short one.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.xs),
              child: Text(
                DeliveryStrings.of(context).appTitle,
                style: const TextStyle(
                    fontSize: 12, color: DeliveryColors.muted, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.md),
      decoration: BoxDecoration(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
        boxShadow: DeliveryShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(title,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.muted)),
          const SizedBox(height: DeliverySpacing.xs),
          ...children,
        ],
      ),
    );
  }
}
