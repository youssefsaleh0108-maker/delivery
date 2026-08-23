import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

/// Who is asking to join, and the decision.
///
/// The API for this existed for a while with no screen in front of it, which meant applications
/// arrived, sat in a queue nobody could see, and could only be approved by somebody willing to
/// craft an HTTP request. A person applying is told "we read every application"; this is the page
/// that makes that true.
///
/// Two decisions, deliberately asymmetric. Approving is one click, because approving is the
/// expected outcome and the process does the rest. Declining takes a sentence, because a refusal
/// with no reason produces the phone call, the reapplication, and the same review done twice — and
/// because the applicant is told the reason verbatim.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.api});

  final OnboardingApi api;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  /// Applications arrive from a public form at any hour, so the queue refreshes itself.
  static const Duration _pollInterval = Duration(seconds: 30);

  Timer? _poll;
  List<OnboardingApplication> _applications = <OnboardingApplication>[];
  bool _showDecided = false;
  bool _loading = true;
  Object? _error;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(_pollInterval, (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final List<OnboardingApplication> loaded =
          _showDecided ? await widget.api.all() : await widget.api.queue();
      if (!mounted) return;
      setState(() {
        _applications = loaded;
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
    final int waiting = _applications.where((OnboardingApplication a) => !a.status.isDecided).length;

    return Padding(
      padding: const EdgeInsets.all(DeliverySpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('Onboarding', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(width: DeliverySpacing.md),
              if (_loading)
                const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const Spacer(),
              // A record of what was decided, not just what is outstanding. Somebody asking "why
              // was this shop turned down" needs the answer to survive the decision.
              FilterChip(
                label: Text(_showDecided ? 'All applications' : 'Waiting only'),
                selected: _showDecided,
                selectedColor: DeliveryColors.brandSoft,
                onSelected: (bool on) {
                  setState(() => _showDecided = on);
                  _refresh();
                },
              ),
              const SizedBox(width: DeliverySpacing.sm),
              IconButton(
                onPressed: () => _refresh(),
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
            ],
          ),
          Text(
            _showDecided
                ? 'Everything ever applied for, newest first.'
                : '$waiting waiting · oldest first, so nothing is left behind',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: DeliverySpacing.md),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(child: Text('Could not load applications.\n$_error', textAlign: TextAlign.center));
    }
    if (_loading && _applications.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
    }
    if (_applications.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.inbox_outlined, size: 40, color: DeliveryColors.muted),
            const SizedBox(height: DeliverySpacing.sm),
            Text(_showDecided ? 'Nobody has applied yet.' : 'Nothing waiting to be read.',
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _applications.length,
      separatorBuilder: (_, __) => const SizedBox(height: DeliverySpacing.sm),
      itemBuilder: (BuildContext context, int i) => _card(_applications[i]),
    );
  }

  Widget _card(OnboardingApplication a) {
    final bool busy = _busyId == a.id;

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(a.businessName,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('${a.kind.label} · applied ${_when(a.createdAt)}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              StatePill(label: a.status.label, accent: _accentOf(a.status)),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md),

          Wrap(
            spacing: DeliverySpacing.lg,
            runSpacing: DeliverySpacing.sm,
            children: <Widget>[
              _fact('Contact', a.contactName),
              // The verification marks are the point of showing these at all. Approving an
              // application whose address was never proved sends an account to whoever actually
              // owns that inbox — so the reviewer sees which details were checked before deciding.
              _fact('Email', a.contactEmail, verified: a.emailVerified),
              _fact('Phone', a.contactPhone ?? 'Not given',
                  verified: a.phoneVerified, absent: a.contactPhone == null),
            ],
          ),

          if ((a.notes ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(DeliverySpacing.sm + 2),
              decoration: BoxDecoration(
                color: DeliveryColors.background,
                borderRadius: BorderRadius.circular(DeliveryRadius.sm),
              ),
              child: Text(a.notes!, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],

          // What happened after the decision, for the ones already decided.
          if (a.status.isDecided) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            Text(_outcomeOf(a), style: Theme.of(context).textTheme.bodySmall),
          ],

          if (!a.status.isDecided) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            // The one warning worth interrupting a reviewer with. Applications taken before
            // verification existed carry no proof, and approving one means the account goes to an
            // address nobody confirmed.
            if (!a.emailVerified)
              const Padding(
                padding: EdgeInsets.only(bottom: DeliverySpacing.sm),
                child: SoftNote(
                  text: 'This email address was never verified. Anything sent to it — including '
                      'how to sign in — may reach somebody else.',
                  accent: DeliveryAccent.caution,
                  icon: Icons.warning_amber_rounded,
                ),
              ),
            Row(
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _decline(a),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Decline'),
                ),
                const SizedBox(width: DeliverySpacing.sm),
                ElevatedButton.icon(
                  onPressed: busy ? null : () => _approve(a),
                  icon: busy
                      ? const SizedBox(
                          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check, size: 18),
                  label: Text(a.kind == OnboardingKind.carrier
                      ? 'Approve and set up the company'
                      : 'Approve'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _fact(String label, String value, {bool verified = false, bool absent = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700,
                letterSpacing: 0.6, color: DeliveryColors.muted)),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: absent ? DeliveryColors.muted : DeliveryColors.ink)),
            if (!absent) ...<Widget>[
              const SizedBox(width: 5),
              Icon(verified ? Icons.verified_rounded : Icons.error_outline_rounded,
                  size: 15,
                  color: verified ? DeliveryAccent.positive.color : DeliveryAccent.caution.color),
            ],
          ],
        ),
      ],
    );
  }

  String _outcomeOf(OnboardingApplication a) {
    final String who = a.decidedBy == null ? '' : ' by ${_short(a.decidedBy!)}';
    return switch (a.status) {
      OnboardingStatus.rejected =>
        'Declined$who ${_when(a.decidedAt)} — ${a.rejectionReason ?? "no reason recorded"}',
      OnboardingStatus.provisioned =>
        'Approved$who ${_when(a.decidedAt)}. Account created; they can set a password and sign in.',
      OnboardingStatus.approved =>
        'Approved$who ${_when(a.decidedAt)}. Setting the account up now.',
      // Its own state because it needs different work: an approved application is waiting on a
      // machine, a failed one is waiting on a person.
      OnboardingStatus.failed =>
        'Approved$who, but setting the account up did not finish. Somebody has to look at this.',
      _ => '',
    };
  }

  Future<void> _approve(OnboardingApplication a) async {
    setState(() => _busyId = a.id);
    try {
      await widget.api.approve(a.id);
      _tell('${a.businessName} approved. We have emailed them.');
      await _refresh(silent: true);
    } catch (e) {
      _tell(_messageFrom(e), bad: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _decline(OnboardingApplication a) async {
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _DeclineDialog(businessName: a.businessName),
    );
    if (reason == null || reason.isBlank) return;

    setState(() => _busyId = a.id);
    try {
      await widget.api.reject(a.id, reason);
      _tell('${a.businessName} declined. They have been told why.');
      await _refresh(silent: true);
    } catch (e) {
      _tell(_messageFrom(e), bad: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// The server's own words where it has any. "This application was already rejected" is something
  /// a reviewer can act on; "DioException [bad response]" is not.
  String _messageFrom(Object e) {
    if (e is DioException) {
      final Object? body = e.response?.data;
      if (body is Map && body['message'] is String) return body['message'] as String;
    }
    return 'That did not go through. Try again.';
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

  static String _short(String id) => id.length <= 8 ? id : '${id.substring(0, 8)}…';

  static String _when(DateTime? at) {
    if (at == null) return 'at an unknown time';
    final Duration ago = DateTime.now().difference(at);
    if (ago.inMinutes < 1) return 'just now';
    if (ago.inMinutes < 60) return '${ago.inMinutes}m ago';
    if (ago.inHours < 24) return '${ago.inHours}h ago';
    if (ago.inDays < 30) return '${ago.inDays}d ago';
    return '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
  }
}

/// Declining, with the reason typed out.
///
/// A dialog rather than an inline field because the text is sent to the applicant verbatim, and
/// something read by the person being turned down deserves a moment's deliberate attention rather
/// than a box that can be tabbed past.
class _DeclineDialog extends StatefulWidget {
  const _DeclineDialog({required this.businessName});

  final String businessName;

  @override
  State<_DeclineDialog> createState() => _DeclineDialogState();
}

class _DeclineDialogState extends State<_DeclineDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Decline ${widget.businessName}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('They are sent this word for word. Say what would have to change.'),
            const SizedBox(height: DeliverySpacing.md),
            TextField(
              controller: _reason,
              maxLines: 3,
              maxLength: 500,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'The address given is outside the area we cover',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          // Disabled rather than validated on submit: the server refuses an empty reason, and
          // finding that out after pressing the button teaches nothing the button could have said.
          onPressed: _reason.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _reason.text.trim()),
          child: const Text('Decline'),
        ),
      ],
    );
  }
}

extension on String {
  bool get isBlank => trim().isEmpty;
}
