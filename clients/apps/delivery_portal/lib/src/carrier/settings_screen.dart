import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import '../shell/console_controls.dart';
import '../shell/shell.dart';

/// The carrier's own preferences page — Figma `carrier-settings` (3:3878), "Company Preferences".
///
/// New in this wave: the design draws a settings console the carrier portal never had, and this is
/// it, laid out exactly as drawn — two columns, four cards, 24px gutters.
///
/// It is also the most speculative frame in the set, and the page is honest about that. Of the
/// eight things it offers, three are real:
///
/// * the company's registered name and contact details, read from `my-company`;
/// * the state of its payout account, which the platform does track;
/// * the portal language, which is wired to the same [LocaleController] the rest of the app uses.
///
/// The rest — logo upload, the bank's name, the IBAN itself, dispatch regions, a production API
/// key, and the Save button that would persist any of it — have no endpoint behind them. Each is
/// drawn at the design's exact geometry, greyed, and carries a Coming-soon chip. Rendering an
/// editable field that silently discards what is typed into it would be worse than rendering none.
///
/// The company's own *availability* switch is not here despite looking like a setting: pausing a
/// fleet is an operational decision taken while looking at that fleet, so it stays on the Riders
/// page beside the riders it stops sending work to.
class CarrierSettingsScreen extends StatefulWidget {
  const CarrierSettingsScreen({super.key, required this.api, required this.locale});

  final DeliveryProviderApi api;
  final LocaleController locale;

  @override
  State<CarrierSettingsScreen> createState() => _CarrierSettingsScreenState();
}

class _CarrierSettingsScreenState extends State<CarrierSettingsScreen> {
  late Future<DeliveryProviderInfo> _company = widget.api.myCompany();

  void _reload() => setState(() => _company = widget.api.myCompany());

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return FutureBuilder<DeliveryProviderInfo>(
      future: _company,
      builder: (BuildContext context, AsyncSnapshot<DeliveryProviderInfo> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            color: DeliveryColors.background,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(color: DeliveryColors.brand),
          );
        }
        // Not attached to a company yet — a 404, and an expected state for a freshly created
        // carrier account rather than a failure worth showing a stack trace for.
        if (snapshot.hasError) {
          return Container(
            color: DeliveryColors.background,
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.all(DeliverySpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.help_outline, size: 40, color: DeliveryColors.faint),
                  const SizedBox(height: DeliverySpacing.md),
                  Text(t.noCompanyYet, style: ConsoleText.cardTitle),
                  const SizedBox(height: DeliverySpacing.xs),
                  Text(t.askThePlatformToAttachYou,
                      textAlign: TextAlign.center, style: ConsoleText.pageSubtitle),
                ],
              ),
            ),
          );
        }

        return _page(snapshot.data!, t);
      },
    );
  }

  Widget _page(DeliveryProviderInfo company, DeliveryStrings t) {
    return ConsolePage(
      header: ConsoleTopbar(
        title: 'Company Preferences',
        subtitle: 'Configure payment, service domains, languages, and system preferences',
        actions: <Widget>[
          const ConsoleSearchField.global(
            hintText: 'Search console...',
            enabled: false,
          ),
          const ConsoleComingSoonChip(),
          ConsoleIconAction(
            icon: Icons.refresh,
            tooltip: t.refresh,
            onPressed: _reload,
          ),
          const ConsoleIconAction(
            icon: Icons.notifications_none,
            tooltip: 'Notifications — coming soon',
          ),
        ],
      ),
      children: <Widget>[_grid(company, t)],
    );
  }

  /// Figma `settings-grid` (3:3921): two equal columns 24 apart, each stacking its cards 24 apart.
  /// Below 980 the two columns become one, in the design's own reading order.
  Widget _grid(DeliveryProviderInfo company, DeliveryStrings t) {
    final List<Widget> left = <Widget>[
      _identityCard(company),
      _payoutCard(company, t),
    ];
    final List<Widget> right = <Widget>[
      _preferencesCard(),
      _apiCard(),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 980) {
          return _column(<Widget>[...left, ...right]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: _column(left)),
            const SizedBox(width: ConsoleMetrics.pageGap),
            Expanded(child: _column(right)),
          ],
        );
      },
    );
  }

  static Widget _column(List<Widget> cards) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < cards.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: ConsoleMetrics.pageGap),
          cards[i],
        ],
      ],
    );
  }

  Widget _identityCard(DeliveryProviderInfo company) {
    return ConsoleCard(
      title: 'Carrier Identity',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              // 64px at radius 12, per the design. No company logo is stored anywhere on this
              // platform, so the tile carries the company's initial rather than a grey box.
              ConsoleAvatar(name: company.name, size: 64, radius: DeliveryRadius.md),
              const SizedBox(width: DeliverySpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        // Drawn and greyed: there is no upload endpoint and nowhere to put the
                        // file if there were.
                        const ConsoleTintButton(label: 'Upload Logo'),
                        const SizedBox(width: DeliverySpacing.sm),
                        const ConsoleComingSoonChip(),
                      ],
                    ),
                    const SizedBox(height: DeliverySpacing.xs),
                    const Text(
                      'PNG, JPG up to 5MB',
                      style: TextStyle(fontSize: 11, color: DeliveryColors.faint),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: ConsoleMetrics.kpiGap),
          ConsoleReadOnlyField(
            label: 'Registered Legal Name',
            value: company.name,
          ),
          const SizedBox(height: ConsoleMetrics.kpiGap),
          // Not in the design, and kept because it is real and belongs to this card: these are the
          // details the Backoffice registered the company with, and a carrier who cannot see them
          // cannot tell anyone they are wrong.
          ConsoleReadOnlyField(
            label: 'Primary Contact',
            value: company.contactName ?? 'Nothing on file',
            placeholder: company.contactName == null,
          ),
          const SizedBox(height: ConsoleMetrics.kpiGap),
          ConsoleReadOnlyField(
            label: 'Contact Phone',
            value: company.contactPhone ?? 'Nothing on file',
            placeholder: company.contactPhone == null,
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          const Text(
            'The registered name and contact are set by the platform. Ask support to change them.',
            style: ConsoleText.meta,
          ),
        ],
      ),
    );
  }

  Widget _payoutCard(DeliveryProviderInfo company, DeliveryStrings t) {
    final bool verified = company.payoutState == PayoutState.verified;

    return ConsoleCard(
      title: 'Payout Details',
      // The one genuinely live fact on this card, and the one that matters: a carrier whose
      // account cannot be paid into finds out here rather than after a week of deliveries.
      trailing: ConsoleStatusPill(
        label: company.payoutState.label,
        accent: verified
            ? DeliveryAccent.positive
            : (company.payoutState == PayoutState.unconfirmed
                ? DeliveryAccent.caution
                : DeliveryAccent.neutral),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: ConsoleReadOnlyField(
                  label: 'Corporate Bank Partner',
                  // The platform stores an account reference, never the bank behind it.
                  value: 'Not recorded',
                  placeholder: true,
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              const Padding(
                padding: EdgeInsets.only(top: DeliverySpacing.lg),
                child: ConsoleComingSoonChip(),
              ),
            ],
          ),
          const SizedBox(height: ConsoleMetrics.kpiGap),
          ConsoleReadOnlyField(
            label: 'International Bank Account Number (IBAN)',
            // Withheld from every audience but the Backoffice on purpose — it is a fact about a
            // carrier's banking, not about their service — so it arrives null here by design.
            value: company.accountRef ?? 'Held by the platform, not shown here',
            placeholder: company.accountRef == null,
          ),
          if (company.payoutDetail != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Text(company.payoutDetail!, style: ConsoleText.meta),
          ],
          if (company.payoutState.needsAttention) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            Text(
              t.payoutNeedsAttentionBlurb,
              style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _preferencesCard() {
    return ConsoleCard(
      title: 'Configuration Preferences',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'Assigned Dispatch Regions',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.muted,
            ),
          ),
          const SizedBox(height: 6),
          // The design's wrapping tag row, with nothing to put in it: delivery zones belong to
          // merchants and to the Backoffice on this platform, and no endpoint assigns a region to
          // a carrier. One greyed exemplar keeps the row's height and shape.
          const Row(
            children: <Widget>[
              ConsoleTagChip('No regions assigned'),
              SizedBox(width: DeliverySpacing.sm),
              ConsoleComingSoonChip(),
            ],
          ),
          const SizedBox(height: ConsoleMetrics.kpiGap),
          // Live, and the only control on this page that changes anything.
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Portal Primary Language',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.muted,
                  ),
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              ConsoleSegmented(
                // Each language named in its own script, which is what makes the switch readable
                // to somebody who cannot read the language currently on screen.
                labels: const <String>['English', 'العربية'],
                selectedIndex: widget.locale.isArabic ? 1 : 0,
                onSelected: (int i) => widget.locale.setLanguage(i == 1 ? 'ar' : 'en'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _apiCard() {
    return ConsoleCard(
      title: 'API Integration Endpoint',
      trailing: const ConsoleComingSoonChip(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const ConsoleReadOnlyField(
            label: 'Carrier Authentication Key (Production)',
            // No key, and deliberately not a masked placeholder that looks like one: a carrier who
            // believed they had a key would go looking for the API it opens.
            value: 'No API key has been issued',
            placeholder: true,
            trailing: Icon(Icons.copy_outlined, size: 16, color: DeliveryColors.faint),
          ),
          const SizedBox(height: DeliverySpacing.sm),
          const Text(
            'Carriers integrate through the rider app today; there is no partner API to key.',
            style: ConsoleText.meta,
          ),
          const SizedBox(height: ConsoleMetrics.kpiGap),
          // The design's full-width save. Everything above it is either read-only or saves itself
          // the moment it is touched, so this has nothing to submit and says so.
          const ConsolePrimaryButton(
            label: 'Save Settings Configuration',
            wide: true,
          ),
        ],
      ),
    );
  }
}
