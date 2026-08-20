import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// App settings — how the app behaves, as distinct from who you are.
///
/// Split from the Account tab deliberately. An account page answers "who am I and where do I live";
/// settings answer "how should this thing work". Language sits here because it is a property of the
/// app, not of the person — the same account on two devices can reasonably read in two languages.
///
/// Reached from the gear in the home app bar rather than from a tab: it is a place you visit
/// rarely and leave, which is what a pushed route means and what a tab does not.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.locale});

  final LocaleController locale;

  @override
  Widget build(BuildContext context) {

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
