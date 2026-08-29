import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../shell/shell.dart';

/// Whether an application is read by a person, or waved through — one switch per applicant kind.
///
/// This existed as an environment variable and a container restart, which meant the only way to open
/// or close the gate was a deployment, and the only record of who decided was a merge commit. An
/// operator asking "why did a shop go live without anyone reading it" had nowhere to look. So the
/// three switches are the point, and so is the line under them naming whoever last moved one.
///
/// Two decisions worth stating, because both look like omissions:
///
///  * **The switch does not move until the server has answered.** Every save sends all three values
///    and re-renders from the response, so what is drawn is what is running. Moving the thumb first
///    and putting it back on failure would show, for as long as the request takes, a gate in a state
///    nobody has agreed to — and this is the one control on the page where that state means live
///    riders on the road.
///  * **Nothing here is painted red.** Opening a gate is a deliberate operating choice, not an
///    accident being intercepted; the fact belongs next to the switch, and a warning colour would
///    only teach an operator to click past it. The source chip carries the one distinction that
///    actually changes what the value means — whether a person chose it or a deployment did.
class AutoApprovalPanel extends StatefulWidget {
  const AutoApprovalPanel({super.key, required this.api});

  final AutoApprovalApi api;

  @override
  State<AutoApprovalPanel> createState() => _AutoApprovalPanelState();
}

class _AutoApprovalPanelState extends State<AutoApprovalPanel> {
  /// The server's view, and the only thing the switches are drawn from.
  ///
  /// Null means "not known", which is why the panel draws no switches at all until it is loaded:
  /// three switches drawn off is a claim that every application is being read by a person, and a
  /// request that has not answered is not evidence for it.
  AutoApprovalSettings? _settings;

  bool _loading = true;

  /// Which kind is mid-save, or null. Also what disables the other two — the PUT carries all three,
  /// so a second change started before the first lands would send a value from a stale record.
  OnboardingKind? _saving;

  /// Why the last save did not go through. Shown in the card as well as in the snackbar, because a
  /// snackbar is gone in four seconds and the switch it refers to is still on screen.
  String? _saveError;

  /// The order the kinds are listed in, cheapest decision first: a rider is one person, a delivery
  /// company is a fleet.
  static const List<OnboardingKind> _kinds = <OnboardingKind>[
    OnboardingKind.rider,
    OnboardingKind.merchant,
    OnboardingKind.carrier,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _saveError = null;
    });
    try {
      final AutoApprovalSettings loaded = await widget.api.get();
      if (!mounted) return;
      setState(() {
        _settings = loaded;
        _loading = false;
      });
    } catch (_) {
      // Left as it was — null on the first read, and the last known good record on a retry that
      // failed. Neither case invents a value for a switch.
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// Sends all three values with [kind] set to [value].
  ///
  /// The other two come from the loaded record rather than from the widgets, so a switch that is
  /// drawn from a response is also what is sent back — there is no second copy of this state to
  /// drift out of step with the server's.
  Future<void> _set(OnboardingKind kind, bool value) async {
    final AutoApprovalSettings current = _settings!;
    setState(() {
      _saving = kind;
      _saveError = null;
    });
    try {
      final AutoApprovalSettings saved = await widget.api.update(
        rider: kind == OnboardingKind.rider ? value : current.rider.automatic,
        merchant: kind == OnboardingKind.merchant ? value : current.merchant.automatic,
        carrier: kind == OnboardingKind.carrier ? value : current.carrier.automatic,
      );
      if (!mounted) return;
      // The response, not the value that was sent: it carries the new source and the audit line,
      // and it is the server's account of what is now running.
      setState(() => _settings = saved);
    } catch (e) {
      if (!mounted) return;
      // _settings is deliberately untouched, so the switch stays where the server last said it was.
      final String message = _messageFrom(e);
      setState(() => _saveError = message);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: DeliveryAccent.critical.color,
      ));
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  /// The server's own words where it has any — "carrier auto-approval is disabled in this
  /// environment" is something an operator can act on; "DioException [bad response]" is not.
  static String _messageFrom(Object e) {
    if (e is DioException) {
      final Object? body = e.response?.data;
      if (body is Map) {
        if (body['message'] is String) return body['message'] as String;
        if (body['detail'] is String) return body['detail'] as String;
      }
      if (e.response?.statusCode == 403) {
        return 'Your account is not allowed to change this.';
      }
    }
    return 'That did not save. The switches still show what is running.';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _settings == null) {
      return const ConsoleCard(
        title: 'Automatic approval',
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: DeliverySpacing.md),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.brand),
            ),
          ),
        ),
      );
    }

    final AutoApprovalSettings? settings = _settings;
    if (settings == null) {
      return ConsoleCard(
        title: 'Automatic approval',
        child: Row(
          children: <Widget>[
            const Expanded(
              // Not "nothing is automatic": a read that failed and a gate that is shut are
              // different facts, and only one of them is safe to believe.
              child: Text(
                'Could not read whether applications are being approved automatically.',
                style: ConsoleText.meta,
              ),
            ),
            ConsoleButton(
              label: 'Try again',
              tone: ConsoleButtonTone.outlined,
              onPressed: _load,
            ),
          ],
        ),
      );
    }

    return ConsoleCard(
      title: 'Automatic approval',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // The whole consequence, in the two sentences an operator needs before touching a switch.
          const Text(
            'Turning a kind on means somebody who has verified an email address becomes a live '
            'rider, shop or delivery company without anyone reading their licence or their '
            'commercial registration. The papers are still collected and still sit on the '
            'application for a reviewer to open — they simply stop being a gate.',
            style: TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.5),
          ),
          const SizedBox(height: DeliverySpacing.md),
          for (int i = 0; i < _kinds.length; i++)
            _KindRow(
              kind: _kinds[i],
              decision: settings.forKind(_kinds[i]),
              // Everything is out of service while any one of them is saving: the PUT sends all
              // three, so a change started against a record that is about to be replaced would
              // write back a value the operator never saw.
              busy: _saving == _kinds[i],
              enabled: _saving == null,
              onChanged: (bool value) => _set(_kinds[i], value),
              last: i == _kinds.length - 1,
            ),
          const SizedBox(height: DeliverySpacing.sm),
          const Divider(height: 1, color: DeliveryColors.border),
          const SizedBox(height: DeliverySpacing.sm),
          Text(_lastChanged(settings), style: ConsoleText.meta),
          if (_saveError != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Row(
              children: <Widget>[
                Icon(Icons.error_outline, size: 14, color: DeliveryAccent.critical.color),
                const SizedBox(width: DeliverySpacing.sm),
                Expanded(
                  child: Text(
                    _saveError!,
                    style: TextStyle(fontSize: 12, color: DeliveryAccent.critical.color),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Who last saved from the portal, and when.
  ///
  /// "Nobody has" is said in words rather than left blank — a blank line reads as a failed lookup,
  /// and the difference matters: it is the same fact as every source below reading CONFIG.
  static String _lastChanged(AutoApprovalSettings settings) {
    final String? who = settings.lastChangedBy;
    if (who == null) {
      return 'Never changed from the portal. What is running is this environment’s own default.';
    }
    return 'Last changed by $who ${_ago(settings.lastChangedAt)}.';
  }

  /// Relative time, because "3 minutes ago" answers "did somebody just do that" and a timestamp
  /// does not. Same ladder as the connector cards above.
  static String _ago(DateTime? time) {
    if (time == null) return 'at an unknown time';
    final Duration d = DateTime.now().difference(time);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

/// The plural, commercial name for an applicant kind — an operator hires riders and signs up shops,
/// and neither of them is a `RIDER`.
///
/// Lives here rather than beside [OnboardingKind] because it is this control's own wording, and it
/// is shared with the review queue's read-only line so the two surfaces cannot drift into calling
/// the same gate two different things.
String autoApprovalKindLabel(OnboardingKind kind) => switch (kind) {
      OnboardingKind.rider => 'Riders',
      OnboardingKind.merchant => 'Shops',
      OnboardingKind.carrier => 'Delivery companies',
    };

/// One kind: what it is, where its current value came from, and the switch.
class _KindRow extends StatelessWidget {
  const _KindRow({
    required this.kind,
    required this.decision,
    required this.busy,
    required this.enabled,
    required this.onChanged,
    required this.last,
  });

  final OnboardingKind kind;
  final AutoApprovalDecision decision;
  final bool busy;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final bool last;

  /// What is actually skipped for that kind. The carrier line carries the extra word it has earned:
  /// a carrier signs for a fleet and for the account the platform pays.
  static String _blurb(OnboardingKind kind) => switch (kind) {
        OnboardingKind.rider =>
          'A rider is on the road as soon as they apply. Nobody checks the driving licence first.',
        OnboardingKind.merchant =>
          'A shop can take orders as soon as it applies. Nobody checks the commercial registration '
              'first.',
        OnboardingKind.carrier =>
          'A delivery company signs for a fleet of riders and for the account the platform pays, so '
              'this is the one with the most standing behind it.',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.sm + 2),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(autoApprovalKindLabel(kind), style: ConsoleText.cellStrong),
                    const SizedBox(width: DeliverySpacing.sm),
                    // Which of the two facts this value is: somebody's decision, or the
                    // deployment's default still standing because nobody has made one.
                    ConsoleQuietChip(label: decision.sourceLabel),
                  ],
                ),
                const SizedBox(height: 2),
                Text(_blurb(kind), style: ConsoleText.meta),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.md),
          // A spinner where the thumb is, rather than a moved thumb: the switch is the server's
          // answer, and until there is one there is nothing true to draw.
          if (busy)
            const SizedBox(
              width: 40,
              height: 24,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.brand),
                ),
              ),
            )
          else
            Switch(
              // Keyed by the wire name so a test — and a screenshot diff — can name the switch it
              // means rather than counting them off in layout order.
              key: ValueKey<String>('auto-approval-${kind.wire}'),
              value: decision.automatic,
              onChanged: enabled ? onChanged : null,
              activeThumbColor: DeliveryColors.brand,
            ),
        ],
      ),
    );
  }
}
