import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shell/console_controls.dart';
import '../shell/shell.dart';

/// The carrier's own preferences page — Figma `carrier-settings` (3:3878), "Company Preferences".
///
/// Laid out exactly as drawn — two columns, four cards, 24px gutters — and, since the provider
/// profile and partner-key endpoints exist, nearly all of it is live:
///
/// * the company's registered name and contact details, read from `my-company`;
/// * the state of its payout account, and the account itself — holder and IBAN, read masked and
///   corrected in place through the onboarding payout endpoints;
/// * the company logo, uploaded through the same three-step presign / PUT / confirm dance product
///   photos use, and drawn in the design's own 64px tile once it exists;
/// * the dispatch regions and the operating hours, edited here and saved as one form — PUT
///   semantics, so what is on screen when Save is pressed is what the company has afterwards;
/// * the partner API keys their dispatch software authenticates with: minted (the secret shown
///   once, because the server hashes it and cannot show it again), listed by prefix, and revoked;
/// * the portal language, wired to the same [LocaleController] the rest of the app uses.
///
/// One field on this frame still has no backend and says so in place of a value: the bank behind
/// the payout account. The platform stores an IBAN and a holder, never the institution.
///
/// The company's own *availability* switch is not here despite looking like a setting: pausing a
/// fleet is an operational decision taken while looking at that fleet, so it stays on the Riders
/// page beside the riders it stops sending work to.
class CarrierSettingsScreen extends StatefulWidget {
  const CarrierSettingsScreen({
    super.key,
    required this.api,
    required this.locale,
    required this.documentsApi,
    this.profileApi,
    this.keysApi,
    this.pickLogo,
    this.putBytes,
  });

  final DeliveryProviderApi api;
  final LocaleController locale;

  /// The payout-details endpoints — the company's own bank account, read and corrected through
  /// the same token-scoped pair the onboarding wizard uses, because that is where the account was
  /// first typed in.
  final DocumentsApi documentsApi;

  /// Logo, dispatch regions and operating hours. Optional only because the portal shell has not
  /// been rewired to pass it yet; without it those controls say so rather than pretending.
  final ProviderProfileApi? profileApi;

  /// The company's machine credentials.
  final PartnerApiKeysApi? keysApi;

  /// Opens the file picker. Injectable so a test can supply bytes without a file dialog.
  final Future<PickedLogo?> Function(BuildContext context)? pickLogo;

  /// PUTs the bytes to the presigned URL. Injectable for the same reason; the default is a bare
  /// Dio, because presigned storage refuses a request that also carries an Authorization header.
  final Future<void> Function(String url, Uint8List bytes, String contentType)? putBytes;

  @override
  State<CarrierSettingsScreen> createState() => _CarrierSettingsScreenState();
}

/// A logo the user chose, before it is uploaded.
class PickedLogo {
  const PickedLogo({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;
}

class _CarrierSettingsScreenState extends State<CarrierSettingsScreen> {
  late Future<_Settings> _data = _load();

  /// Null when the bank step has never been done; a failed load is its own state and never
  /// pretends to be "not set".
  late Future<PayoutDetails?> _payout = widget.documentsApi.myPayout();

  /// The editable form, seeded from the profile the first time it arrives. Held here rather than
  /// re-read from the future so typing survives a rebuild.
  List<String> _regions = <String>[];
  final Map<String, _DayForm> _hours = <String, _DayForm>{};
  bool _seeded = false;
  bool _dirty = false;
  bool _saving = false;
  String? _formError;

  final TextEditingController _search = TextEditingController();
  String _query = '';

  bool _uploading = false;
  String? _logoUrl;

  @override
  void dispose() {
    _search.dispose();
    for (final _DayForm day in _hours.values) {
      day.dispose();
    }
    super.dispose();
  }

  Future<_Settings> _load() async {
    final DeliveryProviderInfo company = await widget.api.myCompany();

    final ProviderProfileApi? profiles = widget.profileApi;
    final ProviderProfile? profile =
        profiles == null ? null : await _tryLoad(() => profiles.profile(company.id));

    final PartnerApiKeysApi? keysApi = widget.keysApi;
    final List<PartnerApiKey>? keys = keysApi == null ? null : await _tryLoad(keysApi.list);

    if (profile != null && !_seeded) _seed(profile);
    if (profile != null) _logoUrl = profile.logoUrl;

    return _Settings(
      company: company,
      profile: profile,
      profileReadable: profiles == null || profile != null,
      keys: keys,
      keysReadable: keysApi == null || keys != null,
    );
  }

  static Future<T?> _tryLoad<T>(Future<T> Function() load) async {
    try {
      return await load();
    } catch (_) {
      return null;
    }
  }

  /// The stored profile into the form. A day absent from the map is closed that day — absence is
  /// meaningful in this contract, so it seeds an unticked row rather than a blank one.
  void _seed(ProviderProfile profile) {
    _seeded = true;
    _regions = List<String>.from(profile.dispatchRegions);
    for (final String day in ProviderProfile.weekDays) {
      final DayHours? stored = profile.operatingHours[day];
      _hours[day] = _DayForm(
        open: stored?.open ?? '09:00',
        close: stored?.close ?? '18:00',
        enabled: stored != null,
        onChanged: () => setState(() {
          _dirty = true;
          _formError = null;
        }),
      );
    }
  }

  void _reload() => setState(() {
        _seeded = false;
        for (final _DayForm day in _hours.values) {
          day.dispose();
        }
        _hours.clear();
        _dirty = false;
        _formError = null;
        _data = _load();
        _payout = widget.documentsApi.myPayout();
      });

  void _tell(String message, {bool bad = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: bad ? DeliveryAccent.critical.color : null,
    ));
  }

  // ------------------------------------------------------------------ payout

  Future<void> _editPayout(PayoutDetails? current) async {
    final ({String holder, String iban})? entered =
        await showDialog<({String holder, String iban})>(
      context: context,
      builder: (BuildContext context) => _PayoutDialog(current: current),
    );
    if (entered == null || !mounted) return;

    try {
      await widget.documentsApi
          .setMyPayout(accountHolder: entered.holder, iban: entered.iban);
      if (!mounted) return;
      _tell('Payout account updated');
      setState(() {
        _payout = widget.documentsApi.myPayout();
      });
    } catch (e) {
      if (!mounted) return;
      _tell(_serverError(e), bad: true);
    }
  }

  /// The server's own sentence where it gave one — it names what is wrong with the IBAN, the
  /// region list or the hours — and a generic one where it did not.
  static String _serverError(Object e) {
    if (e is DioException) {
      final Object? body = e.response?.data;
      if (body is Map) {
        if (body['message'] is String) return body['message'] as String;
        if (body['detail'] is String) return body['detail'] as String;
      }
    }
    return 'That did not go through. Try again.';
  }

  /// `SA44 •••••••••••••••• 1234` — enough to recognise the account, never enough to copy it.
  static String _maskedIban(String iban) {
    final String compact = iban.replaceAll(' ', '');
    if (compact.length <= 8) return compact;
    return '${compact.substring(0, 4)} '
        '${'•' * (compact.length - 8)} '
        '${compact.substring(compact.length - 4)}';
  }

  // ------------------------------------------------------------------- logo

  Future<void> _uploadLogo(String providerId) async {
    final ProviderProfileApi? profiles = widget.profileApi;
    if (profiles == null) return;

    // The picker is called straight from the handler: on the web the file dialog may only open
    // while the browser still considers the click to be in progress.
    final PickedLogo? picked = await (widget.pickLogo ?? _pickLogoFile)(context);
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final DocumentUploadTicket ticket =
          await profiles.presignLogo(providerId, picked.contentType);
      if (ticket.maxSizeBytes > 0 && picked.bytes.length > ticket.maxSizeBytes) {
        // Checked before the bytes go anywhere: the confirm would refuse it afterwards anyway,
        // and a failed upload of a large file is a slow way to be told so.
        _tell('That file is larger than the ${_megabytes(ticket.maxSizeBytes)} limit.', bad: true);
        return;
      }

      await (widget.putBytes ?? _putBytes)(
          ticket.uploadUrl, picked.bytes, ticket.contentType);
      final ProviderProfile profile = await profiles.confirmLogo(providerId, ticket.fileId);
      if (!mounted) return;
      setState(() => _logoUrl = profile.logoUrl);
      _tell('Logo updated');
    } catch (e) {
      if (mounted) _tell(_serverError(e), bad: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  static String _megabytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(bytes % (1024 * 1024) == 0 ? 0 : 1)}MB';

  // ------------------------------------------------------- regions and hours

  /// The same rules the server applies, applied here first so the commonest mistakes are answered
  /// beside the field rather than by a round trip: `HH:mm`, and open strictly before close.
  ///
  /// Everything the server alone knows — the region cap, the day names it accepts — is left to it,
  /// and its refusal is shown word for word.
  String? _validate() {
    for (final String day in ProviderProfile.weekDays) {
      final _DayForm? form = _hours[day];
      if (form == null || !form.enabled) continue;

      final int? open = _minutes(form.openText);
      final int? close = _minutes(form.closeText);
      if (open == null || close == null) {
        return '${_dayLabel(day)}: times are 24-hour HH:mm, like 09:00.';
      }
      if (open >= close) {
        return '${_dayLabel(day)}: opening has to be before closing.';
      }
    }
    return null;
  }

  static int? _minutes(String value) {
    final RegExp shape = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');
    final RegExpMatch? match = shape.firstMatch(value.trim());
    if (match == null) return null;
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }

  static String _dayLabel(String day) =>
      day[0] + day.substring(1).toLowerCase();

  Future<void> _save(String providerId) async {
    final ProviderProfileApi? profiles = widget.profileApi;
    if (profiles == null) return;

    final String? problem = _validate();
    if (problem != null) {
      setState(() => _formError = problem);
      return;
    }

    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      final ProviderProfile saved = await profiles.save(
        providerId,
        dispatchRegions: _regions,
        operatingHours: <String, DayHours>{
          for (final String day in ProviderProfile.weekDays)
            if (_hours[day]?.enabled == true)
              day: DayHours(
                open: _hours[day]!.openText.trim(),
                close: _hours[day]!.closeText.trim(),
              ),
        },
      );
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _logoUrl = saved.logoUrl;
      });
      _tell('Settings saved');
    } catch (e) {
      if (!mounted) return;
      // PUT semantics: nothing was stored, so the form keeps what the carrier typed and shows the
      // server's own refusal above the Save button.
      setState(() => _formError = _serverError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // -------------------------------------------------------------- api keys

  Future<void> _createKey() async {
    final PartnerApiKeysApi? keysApi = widget.keysApi;
    if (keysApi == null) return;

    final String? label = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const _KeyLabelDialog(),
    );
    if (label == null || !mounted) return;

    try {
      final PartnerApiKeyCreated created =
          await keysApi.create(label: label.isEmpty ? null : label);
      if (!mounted) return;
      // The one and only sight of the secret. Shown before the listing refreshes, so nothing can
      // navigate away from it by accident.
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => _SecretDialog(created: created),
      );
      if (!mounted) return;
      setState(() => _data = _load());
    } catch (e) {
      if (mounted) _tell(_serverError(e), bad: true);
    }
  }

  Future<void> _revokeKey(PartnerApiKey key) async {
    final PartnerApiKeysApi? keysApi = widget.keysApi;
    if (keysApi == null) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => _RevokeDialog(keyPrefix: key.keyPrefix),
    );
    if (confirmed != true || !mounted) return;

    try {
      await keysApi.revoke(key.id);
      if (!mounted) return;
      _tell('${key.keyPrefix} revoked');
      setState(() => _data = _load());
    } catch (e) {
      if (mounted) _tell(_serverError(e), bad: true);
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return FutureBuilder<_Settings>(
      future: _data,
      builder: (BuildContext context, AsyncSnapshot<_Settings> snapshot) {
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

  Widget _page(_Settings settings, DeliveryStrings t) {
    return ConsolePage(
      header: ConsoleTopbar(
        title: 'Company Preferences',
        subtitle: 'Configure payment, service domains, languages, and system preferences',
        actions: <Widget>[
          // Live, over this page: it narrows the grid to the cards that mention what was typed,
          // which on a four-card settings page is what a search here can honestly be.
          ConsoleSearchField.global(
            hintText: 'Search settings...',
            controller: _search,
            onChanged: (String value) => setState(() => _query = value.trim().toLowerCase()),
          ),
          ConsoleIconAction(
            icon: Icons.refresh,
            tooltip: t.refresh,
            onPressed: _reload,
          ),
          // FINISH-WAVE NOTE: the console bell's slot. `ConsoleBell` is not exported from
          // `shell/shell.dart` yet, so this keeps the drawn control and compiles against the
          // barrel as it stands.
          const ConsoleIconAction(
            icon: Icons.notifications_none,
            tooltip: 'Notifications',
          ),
        ],
      ),
      children: <Widget>[_grid(settings, t)],
    );
  }

  /// Figma `settings-grid` (3:3921): two equal columns 24 apart, each stacking its cards 24 apart.
  /// Below 980 the two columns become one, in the design's own reading order.
  Widget _grid(_Settings settings, DeliveryStrings t) {
    final List<Widget> left = <Widget>[
      if (_shows(<String>['carrier identity', 'legal name', 'logo', 'contact', 'phone']))
        _identityCard(settings.company),
      if (_shows(<String>['payout', 'bank', 'iban', 'account']))
        _payoutCard(settings.company, t),
    ];
    final List<Widget> right = <Widget>[
      if (_shows(<String>['configuration', 'dispatch', 'region', 'hours', 'language']))
        _preferencesCard(settings),
      if (_shows(<String>['api', 'key', 'integration', 'endpoint', 'save']))
        _apiCard(settings),
    ];

    if (left.isEmpty && right.isEmpty) {
      return ConsoleCard(
        child: Text('Nothing on this page matches "$_query".', style: ConsoleText.pageSubtitle),
      );
    }

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

  bool _shows(List<String> terms) =>
      _query.isEmpty || terms.any((String term) => term.contains(_query));

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
              // 64px at radius 12, per the design: the uploaded logo where there is one, and the
              // company's initial where there is not.
              _logoTile(company),
              const SizedBox(width: DeliverySpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        ConsoleTintButton(
                          label: _uploading
                              ? 'Uploading…'
                              : (_logoUrl == null ? 'Upload Logo' : 'Replace Logo'),
                          onPressed: widget.profileApi == null || _uploading
                              ? null
                              : () => _uploadLogo(company.id),
                        ),
                      ],
                    ),
                    const SizedBox(height: DeliverySpacing.xs),
                    Text(
                      widget.profileApi == null
                          ? 'Logo upload is not wired up in this build'
                          : 'PNG, JPG or WebP. The service refuses anything over its own limit.',
                      style: const TextStyle(fontSize: 11, color: DeliveryColors.faint),
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

  Widget _logoTile(DeliveryProviderInfo company) {
    final String? url = _logoUrl;
    if (url == null) {
      return ConsoleAvatar(name: company.name, size: 64, radius: DeliveryRadius.md);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(DeliveryRadius.md),
      child: Image.network(
        url,
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        // A logo that will not load is not a reason to draw a broken frame where the company's
        // identity goes.
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
            ConsoleAvatar(name: company.name, size: 64, radius: DeliveryRadius.md),
      ),
    );
  }

  Widget _payoutCard(DeliveryProviderInfo company, DeliveryStrings t) {
    final bool verified = company.payoutState == PayoutState.verified;

    return ConsoleCard(
      title: 'Payout Details',
      // The one genuinely live fact on this card's header, and the one that matters: a carrier
      // whose account cannot be paid into finds out here rather than after a week of deliveries.
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
          // The one field on this frame with nothing behind it anywhere on the platform: an
          // account is an IBAN and a holder, and no endpoint records the institution. Left as a
          // stated absence rather than a box that would silently discard a bank's name.
          const ConsoleReadOnlyField(
            label: 'Corporate Bank Partner',
            value: 'Not recorded — the platform stores the account, not the bank',
            placeholder: true,
          ),
          const SizedBox(height: ConsoleMetrics.kpiGap),
          // The company's own bank account, from the onboarding payout record. Masked on screen:
          // it is displayed to be recognised, not to be copied off a shared monitor.
          FutureBuilder<PayoutDetails?>(
            future: _payout,
            builder:
                (BuildContext context, AsyncSnapshot<PayoutDetails?> snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const ConsoleReadOnlyField(
                  label: 'International Bank Account Number (IBAN)',
                  value: 'Loading…',
                  placeholder: true,
                );
              }
              if (snapshot.hasError) {
                return const ConsoleReadOnlyField(
                  label: 'International Bank Account Number (IBAN)',
                  value: 'Could not load the payout account',
                  placeholder: true,
                );
              }

              final PayoutDetails? payout = snapshot.data;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ConsoleReadOnlyField(
                    label: 'Account Holder',
                    value: payout?.accountHolder ?? 'Not set yet',
                    placeholder: payout == null,
                  ),
                  const SizedBox(height: ConsoleMetrics.kpiGap),
                  ConsoleReadOnlyField(
                    label: 'International Bank Account Number (IBAN)',
                    value: payout == null
                        ? 'Not set yet'
                        : _maskedIban(payout.iban),
                    placeholder: payout == null,
                  ),
                  const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                  Row(
                    children: <Widget>[
                      ConsoleTintButton(
                        label: payout == null
                            ? 'Add bank account'
                            : 'Update bank account',
                        onPressed: () => _editPayout(payout),
                      ),
                      if (payout != null) ...<Widget>[
                        const SizedBox(width: DeliverySpacing.sm),
                        // The bank check's own verdict on this account, distinct from the
                        // platform-level pill in the card header.
                        ConsoleSmallBadge(
                          label: payout.verificationState.label,
                          accent: switch (payout.verificationState) {
                            PayoutVerificationState.verified =>
                              DeliveryAccent.positive,
                            PayoutVerificationState.failed =>
                              DeliveryAccent.critical,
                            _ => DeliveryAccent.caution,
                          },
                        ),
                      ],
                    ],
                  ),
                ],
              );
            },
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

  Widget _preferencesCard(_Settings settings) {
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
          _regionsEditor(settings),
          const SizedBox(height: ConsoleMetrics.kpiGap),
          const Text(
            'Operating Hours',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.muted,
            ),
          ),
          const SizedBox(height: 6),
          _hoursEditor(settings),
          const SizedBox(height: ConsoleMetrics.kpiGap),
          // Live, and the one control on this page that takes effect the moment it is touched.
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

  /// The design's wrapping tag row, now with real tags: each region is removable and there is a
  /// field to add one. Nothing is saved until the form is.
  Widget _regionsEditor(_Settings settings) {
    if (!settings.profileReadable) {
      return const Text('The company profile could not be read just now.',
          style: ConsoleText.body);
    }
    if (widget.profileApi == null) {
      // Wrapped, not a Row: the sentence is longer than the tag row is wide in one column.
      return const Wrap(
        children: <Widget>[
          ConsoleTagChip('Dispatch regions are not wired up in this build'),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (_regions.isEmpty)
          const Text(
            'No regions yet. A company with none is not narrowed to any area.',
            style: ConsoleText.meta,
          )
        else
          Wrap(
            spacing: DeliverySpacing.sm,
            runSpacing: DeliverySpacing.sm,
            children: <Widget>[
              for (final String region in _regions)
                _RemovableTag(
                  label: region,
                  onRemove: () => setState(() {
                    _regions.remove(region);
                    _dirty = true;
                    _formError = null;
                  }),
                ),
            ],
          ),
        const SizedBox(height: DeliverySpacing.sm),
        _RegionField(
          onAdd: (String region) {
            final String trimmed = region.trim();
            if (trimmed.isEmpty) return;
            // Case-insensitive, because "Beirut" and "beirut" are one region to a dispatcher and
            // two rows to a server.
            if (_regions.any((String r) => r.toLowerCase() == trimmed.toLowerCase())) return;
            setState(() {
              _regions.add(trimmed);
              _dirty = true;
              _formError = null;
            });
          },
        ),
      ],
    );
  }

  /// Seven rows, one per day, because a day left out of the form is CLOSED that day rather than
  /// unspecified — the contract is explicit, and a form that hid closed days would make closing a
  /// day impossible to express.
  Widget _hoursEditor(_Settings settings) {
    if (!settings.profileReadable) {
      return const Text('The company profile could not be read just now.',
          style: ConsoleText.body);
    }
    if (widget.profileApi == null) {
      return const Text('Operating hours are not wired up in this build.',
          style: ConsoleText.body);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final String day in ProviderProfile.weekDays)
          if (_hours[day] != null)
            _DayRow(
              day: day,
              label: _dayLabel(day),
              form: _hours[day]!,
              onToggled: (bool open) => setState(() {
                _hours[day]!.enabled = open;
                _dirty = true;
                _formError = null;
              }),
            ),
        const SizedBox(height: DeliverySpacing.xs),
        const Text(
          'A day left unticked is closed. Times are 24-hour HH:mm and open before close.',
          style: ConsoleText.meta,
        ),
      ],
    );
  }

  Widget _apiCard(_Settings settings) {
    final List<PartnerApiKey> keys = settings.keys ?? const <PartnerApiKey>[];
    final PartnerApiKey? live = keys.where((PartnerApiKey k) => !k.revoked).firstOrNull;

    return ConsoleCard(
      title: 'API Integration Endpoint',
      trailing: widget.keysApi == null
          ? null
          : ConsoleTintButton(label: 'Create key', onPressed: _createKey),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ConsoleReadOnlyField(
            label: 'Carrier Authentication Key (Production)',
            // The prefix, which is all any listing ever carries — the secret is hashed server-side
            // and shown exactly once, at minting. A masked placeholder that looked like a key
            // would send a carrier looking for an API it cannot open.
            value: !settings.keysReadable
                ? 'Could not read this company\'s keys just now'
                : live == null
                    ? 'No API key has been issued'
                    : '${live.keyPrefix}…',
            placeholder: live == null,
            trailing: live == null
                ? null
                : ConsoleRowAction(
                    icon: Icons.copy_outlined,
                    tooltip: 'Copy the key prefix',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: live.keyPrefix));
                      _tell('${live.keyPrefix} copied');
                    },
                  ),
          ),
          const SizedBox(height: DeliverySpacing.sm),
          Text(
            widget.keysApi == null
                ? 'Partner API keys are not wired up in this build.'
                : 'Your dispatch software sends this on X-API-Key to read the job board. The '
                    'secret is shown once, when the key is created.',
            style: ConsoleText.meta,
          ),
          if (keys.isNotEmpty) ...<Widget>[
            const SizedBox(height: ConsoleMetrics.kpiGap),
            for (final PartnerApiKey key in keys) _keyRow(key),
          ],
          const SizedBox(height: ConsoleMetrics.kpiGap),
          if (_formError != null) ...<Widget>[
            Text(
              _formError!,
              style: ConsoleText.body.copyWith(color: DeliveryAccent.critical.color),
            ),
            const SizedBox(height: DeliverySpacing.sm),
          ],
          // The design's full-width save. It now submits the regions and the hours as one form —
          // PUT semantics, so what is on screen is what the company has afterwards.
          ConsolePrimaryButton(
            label: _saving ? 'Saving…' : 'Save Settings Configuration',
            wide: true,
            busy: _saving,
            onPressed: widget.profileApi == null || !_dirty || _saving
                ? null
                : () => _save(settings.company.id),
          ),
          if (widget.profileApi != null && !_dirty && !_saving) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            const Text('Nothing has changed since the last save.', style: ConsoleText.meta),
          ],
        ],
      ),
    );
  }

  Widget _keyRow(PartnerApiKey key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        key.label == null
                            ? key.keyPrefix
                            : '${key.keyPrefix} · ${key.label}',
                        overflow: TextOverflow.ellipsis,
                        style: ConsoleText.cellStrong,
                      ),
                    ),
                    if (key.revoked) ...<Widget>[
                      const SizedBox(width: DeliverySpacing.sm),
                      const ConsoleSmallBadge(
                          label: 'Revoked', accent: DeliveryAccent.neutral),
                    ],
                  ],
                ),
                Text(
                  <String>[
                    key.createdAt == null ? 'Created —' : 'Created ${_stamp(key.createdAt!)}',
                    // Never used is the honest answer for a key minted and forgotten, and the one
                    // that makes it safe to revoke.
                    key.lastUsedAt == null
                        ? 'never used'
                        : 'last used ${_stamp(key.lastUsedAt!)}',
                    if (key.revokedAt != null) 'revoked ${_stamp(key.revokedAt!)}',
                  ].join(' · '),
                  style: ConsoleText.meta,
                ),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          if (!key.revoked)
            ConsoleRowAction(
              icon: Icons.delete_outline,
              tooltip: 'Revoke this key',
              destructive: true,
              onPressed: () => _revokeKey(key),
            ),
        ],
      ),
    );
  }

  static String _stamp(DateTime at) {
    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[at.month - 1]} ${at.day.toString().padLeft(2, '0')}, ${at.year}';
  }
}

/// Everything the page loads in one shape, so a card can tell "not readable" from "empty".
class _Settings {
  const _Settings({
    required this.company,
    required this.profile,
    required this.profileReadable,
    required this.keys,
    required this.keysReadable,
  });

  final DeliveryProviderInfo company;

  /// Null when the endpoint is not wired up here or could not be read. A company that never saved
  /// settings gets the empty shape from the server, never a 404.
  final ProviderProfile? profile;
  final bool profileReadable;

  final List<PartnerApiKey>? keys;
  final bool keysReadable;
}

/// One day's editable state. Controllers live here so the seven rows keep their cursors.
class _DayForm {
  _DayForm({
    required String open,
    required String close,
    required this.enabled,
    required this.onChanged,
  })  : openController = TextEditingController(text: open),
        closeController = TextEditingController(text: close) {
    openController.addListener(onChanged);
    closeController.addListener(onChanged);
  }

  final TextEditingController openController;
  final TextEditingController closeController;
  final VoidCallback onChanged;
  bool enabled;

  String get openText => openController.text;
  String get closeText => closeController.text;

  void dispose() {
    openController.dispose();
    closeController.dispose();
  }
}

/// One row of the hours editor: the day, whether it is open, and the two times.
class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.label,
    required this.form,
    required this.onToggled,
  });

  /// The server's own key for this day — also the stable handle each of the row's controls is
  /// keyed by, so a rebuild cannot swap one day's fields for another's.
  final String day;

  final String label;
  final _DayForm form;
  final ValueChanged<bool> onToggled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.xs),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 24,
            child: Checkbox(
              key: ValueKey<String>('hours-$day-open?'),
              value: form.enabled,
              activeColor: DeliveryColors.brand,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (bool? value) => onToggled(value ?? false),
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          SizedBox(
            width: 92,
            child: Text(label, style: ConsoleText.body),
          ),
          if (form.enabled) ...<Widget>[
            _TimeField(
              key: ValueKey<String>('hours-$day-from'),
              controller: form.openController,
              semantic: '$label opening time',
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: DeliverySpacing.xs),
              child: Text('–', style: ConsoleText.body),
            ),
            _TimeField(
              key: ValueKey<String>('hours-$day-to'),
              controller: form.closeController,
              semantic: '$label closing time',
            ),
          ] else
            const Text('Closed', style: ConsoleText.meta),
        ],
      ),
    );
  }
}

/// A five-character `HH:mm` box at the console's control proportions.
class _TimeField extends StatelessWidget {
  const _TimeField({super.key, required this.controller, required this.semantic});

  final TextEditingController controller;
  final String semantic;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: Semantics(
        label: semantic,
        child: TextField(
          controller: controller,
          maxLength: 5,
          style: ConsoleText.control,
          cursorColor: DeliveryColors.brand,
          decoration: InputDecoration(
            counterText: '',
            isDense: true,
            hintText: 'HH:mm',
            hintStyle: const TextStyle(fontSize: 13, color: DeliveryColors.faint),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: DeliverySpacing.sm,
              vertical: DeliverySpacing.sm,
            ),
            filled: true,
            fillColor: DeliveryColors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DeliveryRadius.sm),
              borderSide: const BorderSide(color: DeliveryColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DeliveryRadius.sm),
              borderSide: const BorderSide(color: DeliveryColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DeliveryRadius.sm),
              borderSide: const BorderSide(color: DeliveryColors.brand),
            ),
          ),
        ),
      ),
    );
  }
}

/// A region tag with the cross the design's tags do not draw, because these are editable.
class _RemovableTag extends StatelessWidget {
  const _RemovableTag({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.only(
        start: DeliverySpacing.md - DeliverySpacing.xs,
        end: DeliverySpacing.xs,
        top: 2,
        bottom: 2,
      ),
      decoration: BoxDecoration(
        color: DeliveryColors.background,
        border: Border.all(color: DeliveryColors.border),
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: const TextStyle(fontSize: 13, color: DeliveryColors.muted)),
          const SizedBox(width: DeliverySpacing.xs),
          ConsoleRowAction(
            icon: Icons.close,
            tooltip: 'Remove $label',
            destructive: true,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// The add-a-region field: type it, press enter or the button.
class _RegionField extends StatefulWidget {
  const _RegionField({required this.onAdd});

  final ValueChanged<String> onAdd;

  @override
  State<_RegionField> createState() => _RegionFieldState();
}

class _RegionFieldState extends State<_RegionField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    if (_controller.text.trim().isEmpty) return;
    widget.onAdd(_controller.text);
    _controller.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: ConsoleSearchField(
            key: const ValueKey<String>('region-field'),
            hintText: 'Add a region — Beirut, Jounieh…',
            controller: _controller,
            onChanged: (_) => setState(() {}),
            width: double.infinity,
          ),
        ),
        const SizedBox(width: DeliverySpacing.sm),
        ConsoleButton(
          label: 'Add region',
          icon: Icons.add,
          tone: ConsoleButtonTone.tinted,
          onPressed: _controller.text.trim().isEmpty ? null : _add,
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ dialogs

/// Naming a new key. The label is optional server-side and optional here.
class _KeyLabelDialog extends StatefulWidget {
  const _KeyLabelDialog();

  @override
  State<_KeyLabelDialog> createState() => _KeyLabelDialogState();
}

class _KeyLabelDialogState extends State<_KeyLabelDialog> {
  final TextEditingController _label = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: DeliveryColors.white,
      surfaceTintColor: DeliveryColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
      title: const Text('Create an API key', style: ConsoleText.cardTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'The secret is shown once, on the next screen, and cannot be shown again. Name the '
              'key after the machine that will hold it.',
              style: ConsoleText.pageSubtitle,
            ),
            const SizedBox(height: DeliverySpacing.md),
            TextField(
              controller: _label,
              maxLength: 80,
              autofocus: true,
              style: ConsoleText.cell,
              cursorColor: DeliveryColors.brand,
              decoration: InputDecoration(
                hintText: 'dispatch box (optional)',
                hintStyle: const TextStyle(fontSize: 14, color: DeliveryColors.faint),
                filled: true,
                fillColor: DeliveryColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                  borderSide: const BorderSide(color: DeliveryColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                  borderSide: const BorderSide(color: DeliveryColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                  borderSide: const BorderSide(color: DeliveryColors.brand),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.muted,
            ),
          ),
        ),
        ConsolePrimaryButton(
          label: 'Create key',
          onPressed: () => Navigator.pop(context, _label.text.trim()),
        ),
      ],
    );
  }
}

/// The secret, once.
///
/// Not dismissible by tapping outside, and the copy control is the first thing under it: this
/// response is the only place the credential ever exists, and a carrier who closes this dialog
/// without it has to revoke the key and mint another.
class _SecretDialog extends StatelessWidget {
  const _SecretDialog({required this.created});

  final PartnerApiKeyCreated created;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: DeliveryColors.white,
      surfaceTintColor: DeliveryColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
      title: const Text('Copy this key now', style: ConsoleText.cardTitle),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'This is the only time ${created.keyPrefix} can be shown. It is stored hashed, so '
              'nobody — not you, not support — can read it again. Lose it and you revoke the key '
              'and create another.',
              style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.4),
            ),
            const SizedBox(height: DeliverySpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
              decoration: BoxDecoration(
                color: DeliveryColors.background,
                border: Border.all(color: DeliveryColors.border),
                borderRadius: BorderRadius.circular(DeliveryRadius.sm),
              ),
              child: SelectableText(
                created.secret,
                style: const TextStyle(fontSize: 14, color: DeliveryColors.ink),
              ),
            ),
            const SizedBox(height: DeliverySpacing.md),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ConsoleButton(
                label: 'Copy the key',
                icon: Icons.copy_outlined,
                tone: ConsoleButtonTone.tinted,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: created.secret));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Key copied')),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        ConsolePrimaryButton(
          label: 'I have copied it',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

/// Revoking, which takes effect immediately and cannot be undone.
class _RevokeDialog extends StatelessWidget {
  const _RevokeDialog({required this.keyPrefix});

  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: DeliveryColors.white,
      surfaceTintColor: DeliveryColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
      title: Text('Revoke $keyPrefix', style: ConsoleText.cardTitle),
      content: const SizedBox(
        width: 420,
        child: Text(
          'Anything still authenticating with this key stops working the moment it is revoked. '
          'A revoked key cannot be brought back — create a new one instead.',
          style: ConsoleText.pageSubtitle,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text(
            'Cancel',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.muted,
            ),
          ),
        ),
        ConsoleSoftButton(
          label: 'Revoke key',
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}

/// The bank step, corrected in place: account holder and IBAN, PUT as one pair.
///
/// A dialog rather than inline fields because the pair is submitted together or not at all —
/// half-edited bank details left sitting in an editable card would look saved without being saved.
/// The server normalises the IBAN and mod-97 checks it; what it refuses comes back as its own
/// sentence, so the dialog does not second-guess formats here.
class _PayoutDialog extends StatefulWidget {
  const _PayoutDialog({required this.current});

  final PayoutDetails? current;

  @override
  State<_PayoutDialog> createState() => _PayoutDialogState();
}

class _PayoutDialogState extends State<_PayoutDialog> {
  late final TextEditingController _holder =
      TextEditingController(text: widget.current?.accountHolder ?? '');
  // Deliberately empty even when details exist: the stored IBAN is shown masked outside, and
  // pre-filling a masked number would submit the mask as the account.
  final TextEditingController _iban = TextEditingController();

  @override
  void dispose() {
    _holder.dispose();
    _iban.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: DeliveryColors.faint),
        filled: true,
        fillColor: DeliveryColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.sm),
          borderSide: const BorderSide(color: DeliveryColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.sm),
          borderSide: const BorderSide(color: DeliveryColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.sm),
          borderSide: const BorderSide(color: DeliveryColors.brand),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final bool ready = _holder.text.trim().isNotEmpty && _iban.text.trim().isNotEmpty;

    return AlertDialog(
      backgroundColor: DeliveryColors.white,
      surfaceTintColor: DeliveryColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
      ),
      title: Text(
        widget.current == null ? 'Add bank account' : 'Update bank account',
        style: ConsoleText.cardTitle,
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Both fields are saved together and replace what is on record. Payouts go to '
              'this account.',
              style: ConsoleText.pageSubtitle,
            ),
            const SizedBox(height: DeliverySpacing.md),
            TextField(
              controller: _holder,
              maxLength: 200,
              autofocus: true,
              style: ConsoleText.cell,
              cursorColor: DeliveryColors.brand,
              decoration: _decoration('Account holder, exactly as the bank has it'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: DeliverySpacing.sm),
            TextField(
              controller: _iban,
              maxLength: 42,
              style: ConsoleText.cell,
              cursorColor: DeliveryColors.brand,
              decoration: _decoration('IBAN — spaces are fine'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.muted,
            ),
          ),
        ),
        ConsolePrimaryButton(
          label: 'Save bank account',
          onPressed: ready
              ? () => Navigator.pop(
                    context,
                    (holder: _holder.text.trim(), iban: _iban.text.trim()),
                  )
              : null,
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ picking

/// Opens the file picker and reads the bytes.
///
/// `file_selector` rather than `image_picker`, matching the rest of this portal — it is the one
/// that works cleanly on Flutter Web, which is the only place this app runs.
Future<PickedLogo?> _pickLogoFile(BuildContext context) async {
  const XTypeGroup images = XTypeGroup(
    label: 'Images',
    extensions: <String>['jpg', 'jpeg', 'png', 'webp'],
    mimeTypes: <String>['image/jpeg', 'image/png', 'image/webp'],
  );

  try {
    final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[images]);
    if (file == null) return null;
    return PickedLogo(bytes: await file.readAsBytes(), contentType: _contentTypeFor(file));
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not open the file picker: $e')));
    }
    return null;
  }
}

/// `XFile.mimeType` is null on several platforms, so fall back to the extension.
String _contentTypeFor(XFile file) {
  final String? declared = file.mimeType;
  if (declared != null && declared.startsWith('image/')) return declared;
  final String name = file.name.toLowerCase();
  if (name.endsWith('.png')) return 'image/png';
  if (name.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

/// The presigned PUT.
///
/// A bare Dio on purpose: S3-compatible storage rejects a presigned request that also carries an
/// Authorization header, because that is two conflicting auth mechanisms on one request.
Future<void> _putBytes(String url, Uint8List bytes, String contentType) async {
  final Dio bare = Dio();
  await bare.put<void>(
    url,
    data: Stream<List<int>>.fromIterable(<List<int>>[bytes]),
    options: Options(headers: <String, dynamic>{
      'Content-Type': contentType,
      Headers.contentLengthHeader: bytes.length,
    }),
  );
}
