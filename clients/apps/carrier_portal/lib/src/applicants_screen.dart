import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// People asking to ride for this company.
///
/// The decision belongs here and not in the Backoffice, which is the whole point of the screen.
/// The platform does not know who turned up for a trial, who has a licence, or who was let go last
/// month — a company does. Having the platform hire on its behalf would mean choosing somebody
/// else's staff and leaving them with the consequences.
///
/// Approving does two things at once, and the screen says so before it is pressed: it creates the
/// rider's account and puts them on this company's fleet, so they can be offered work immediately.
class ApplicantsScreen extends StatefulWidget {
  const ApplicantsScreen({super.key, required this.api, required this.providerApi});

  final OnboardingApi api;
  final DeliveryProviderApi providerApi;

  @override
  State<ApplicantsScreen> createState() => _ApplicantsScreenState();
}

class _ApplicantsScreenState extends State<ApplicantsScreen> {
  static const Duration _pollInterval = Duration(seconds: 45);

  Timer? _poll;
  String? _providerId;
  List<OnboardingApplication> _applicants = <OnboardingApplication>[];
  bool _showAll = false;
  bool _loading = true;
  Object? _error;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(_pollInterval, (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      // The company is resolved from the caller's own account, never typed in. The id then travels
      // in the path and the server checks it again — this is convenience, not the access control.
      _providerId ??= (await widget.providerApi.myCompany()).id;
      final List<OnboardingApplication> loaded =
          await widget.api.forCompany(_providerId!, all: _showAll);
      if (!mounted) return;
      setState(() {
        _applicants = loaded;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final int waiting =
        _applicants.where((OnboardingApplication a) => !a.status.isDecided).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.navApplicants),
        actions: <Widget>[
          IconButton(
            onPressed: () => _load(),
            icon: const Icon(Icons.refresh),
            tooltip: t.refresh,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(DeliverySpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _showAll ? t.everyoneWhoApplied : t.waitingOnYou(waiting),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                FilterChip(
                  label: Text(_showAll ? t.everyone : t.waitingOnly),
                  selected: _showAll,
                  selectedColor: DeliveryColors.brandSoft,
                  onSelected: (bool on) {
                    setState(() => _showAll = on);
                    _load();
                  },
                ),
              ],
            ),
            const SizedBox(height: DeliverySpacing.md),
            Expanded(child: _body(t)),
          ],
        ),
      ),
    );
  }

  Widget _body(DeliveryStrings t) {
    if (_error != null) {
      // Belonging to no company is a provisioning gap, not a failure — the same expected state the
      // earnings and dashboard screens handle, worded the same way so it does not read as a bug.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DeliverySpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.help_outline, size: 40, color: DeliveryColors.muted),
              const SizedBox(height: DeliverySpacing.md),
              Text(t.noCompanyYet, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: DeliverySpacing.xs),
              Text(t.askThePlatformToAttachYou,
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
    }
    if (_loading && _applicants.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
    }
    if (_applicants.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.person_search_outlined, size: 40, color: DeliveryColors.muted),
            const SizedBox(height: DeliverySpacing.sm),
            Text(_showAll ? t.nobodyHasApplied : t.nobodyWaiting,
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _applicants.length,
      separatorBuilder: (_, __) => const SizedBox(height: DeliverySpacing.sm),
      itemBuilder: (BuildContext context, int i) => _card(_applicants[i], t),
    );
  }

  Widget _card(OnboardingApplication a, DeliveryStrings t) {
    final bool busy = _busyId == a.id;

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // The rider's own name leads. On the platform's queue the business name is the
                    // headline; here the business is this company, and the person is the news.
                    Text(a.contactName,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(a.contactEmail, style: Theme.of(context).textTheme.bodySmall),
                    if (a.contactPhone != null)
                      Text(a.contactPhone!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              StatePill(label: a.status.label, accent: _accentOf(a.status)),
            ],
          ),

          if ((a.notes ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Text(a.notes!, style: Theme.of(context).textTheme.bodySmall),
          ],

          if (a.status.isDecided) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Text(
              a.status == OnboardingStatus.rejected
                  ? t.turnedDownBecause(a.rejectionReason ?? '—')
                  : t.onYourFleetNow,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            // Said before the button is pressed, because approving is two irreversible things at
            // once: an account exists afterwards, and this person can be sent work.
            Text(t.hiringAlsoCreatesTheirAccount,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: DeliverySpacing.sm),
            Row(
              children: <Widget>[
                OutlinedButton(
                  onPressed: busy ? null : () => _turnDown(a, t),
                  child: Text(t.turnDown),
                ),
                const SizedBox(width: DeliverySpacing.sm),
                ElevatedButton.icon(
                  onPressed: busy ? null : () => _hire(a, t),
                  icon: busy
                      ? const SizedBox(
                          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.person_add_alt_1, size: 18),
                  label: Text(t.addToMyFleet),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _hire(OnboardingApplication a, DeliveryStrings t) async {
    setState(() => _busyId = a.id);
    try {
      await widget.api.hire(_providerId!, a.id);
      _tell(t.riderAdded(a.contactName));
      await _load(silent: true);
    } catch (e) {
      _tell(_messageFrom(e, t), bad: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _turnDown(OnboardingApplication a, DeliveryStrings t) async {
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _ReasonDialog(name: a.contactName),
    );
    if (reason == null || reason.trim().isEmpty) return;

    setState(() => _busyId = a.id);
    try {
      await widget.api.turnDown(_providerId!, a.id, reason.trim());
      _tell(t.applicantTurnedDown(a.contactName));
      await _load(silent: true);
    } catch (e) {
      _tell(_messageFrom(e, t), bad: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  String _messageFrom(Object e, DeliveryStrings t) {
    if (e is DioException) {
      final Object? body = e.response?.data;
      if (body is Map && body['message'] is String) return body['message'] as String;
    }
    return t.thatDidNotGoThrough;
  }

  void _tell(String message, {bool bad = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: bad ? DeliveryAccent.critical.color : null,
    ));
  }

  static DeliveryAccent _accentOf(OnboardingStatus status) => switch (status) {
        OnboardingStatus.submitted => DeliveryAccent.caution,
        OnboardingStatus.inReview => DeliveryAccent.info,
        OnboardingStatus.approved => DeliveryAccent.info,
        OnboardingStatus.provisioned => DeliveryAccent.positive,
        OnboardingStatus.rejected => DeliveryAccent.neutral,
        OnboardingStatus.failed => DeliveryAccent.critical,
      };
}

/// Turning somebody down, with the reason typed out — they are sent it word for word.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.name});

  final String name;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return AlertDialog(
      title: Text(t.turnDownName(widget.name)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(t.theyAreSentThisWordForWord),
            const SizedBox(height: DeliverySpacing.md),
            TextField(
              controller: _reason,
              maxLines: 3,
              maxLength: 500,
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        ElevatedButton(
          onPressed: _reason.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _reason.text.trim()),
          child: Text(t.turnDown),
        ),
      ],
    );
  }
}
