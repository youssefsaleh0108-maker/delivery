import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// The neighbourhood chat moderation queue.
///
/// Reported messages, oldest wait first — the order the server returns, so the wait at the top of
/// the page is the longest one and a brigade of reports on one harmless message cannot bury a
/// harmful one. For each: the room, the author as the room shows them (a first name and an initial;
/// staff never see an account), the words even when already removed, why neighbours reported it and
/// how many did, and whether the author is muted.
///
/// Every decision asks for a reason before it is sent: the server writes the reason and the
/// moderator's identity into its audit trail in the same transaction as the action, and refuses an
/// action without one. Staff act through the reported message — hide it, dismiss its reports, mute
/// its author in that room for a day, a week or a month, or lift a mute — and never type an id.
class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key, required this.api});

  final ChatModerationApi api;

  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

enum _Decision { hide, dismiss, mute, unmute }

class _ModerationScreenState extends State<ModerationScreen> {
  /// The mutes on offer, in hours. Bounded on purpose: a permanent silence is a ban, and a ban is a
  /// decision about an account with an appeal, not a click in a queue.
  static const List<int> _muteHours = <int>[24, 24 * 7, 24 * 30];

  List<ReportedRoomMessage>? _queue;
  bool _failed = false;
  String? _busyMessageId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final List<ReportedRoomMessage> queue = await widget.api.queue();
      if (!mounted) return;
      setState(() {
        _queue = queue;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _decide(ReportedRoomMessage line, _Decision decision) async {
    final DeliveryStrings t = DeliveryStrings.of(context);

    int? hours;
    if (decision == _Decision.mute) {
      hours = await showDialog<int>(
        context: context,
        builder: (BuildContext dialog) => SimpleDialog(
          title: Text(t.chatModerationMute),
          children: <Widget>[
            for (final int option in _muteHours)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialog).pop(option),
                child: Text(_muteLabel(t, option)),
              ),
          ],
        ),
      );
      if (hours == null || !mounted) return;
    }

    final String? reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(title: _decisionLabel(t, decision)),
    );
    if (reason == null || !mounted) return;

    setState(() => _busyMessageId = line.messageId);
    try {
      switch (decision) {
        case _Decision.hide:
          await widget.api.hide(line.messageId, reason: reason);
        case _Decision.dismiss:
          await widget.api.dismiss(line.messageId, reason: reason);
        case _Decision.mute:
          await widget.api.muteAuthor(line.messageId, hours: hours!, reason: reason);
        case _Decision.unmute:
          await widget.api.unmuteAuthor(line.messageId, reason: reason);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.chatModerationDone)));
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.chatActionFailed)));
    } finally {
      if (mounted) setState(() => _busyMessageId = null);
    }
  }

  static String _decisionLabel(DeliveryStrings t, _Decision decision) => switch (decision) {
        _Decision.hide => t.chatModerationHide,
        _Decision.dismiss => t.chatModerationDismiss,
        _Decision.mute => t.chatModerationMute,
        _Decision.unmute => t.chatModerationUnmute,
      };

  static String _muteLabel(DeliveryStrings t, int hours) => switch (hours) {
        24 => t.chatModerationMute24h,
        168 => t.chatModerationMute7d,
        _ => t.chatModerationMute30d,
      };

  static String _reasonLabel(DeliveryStrings t, RoomReportReason reason) => switch (reason) {
        RoomReportReason.spam => t.chatRoomReasonSpam,
        RoomReportReason.abuse => t.chatRoomReasonAbuse,
        RoomReportReason.personalInfo => t.chatRoomReasonPersonalInfo,
        RoomReportReason.other => t.chatRoomReasonOther,
      };

  String _moment(DateTime at) {
    final MaterialLocalizations words = MaterialLocalizations.of(context);
    return '${words.formatMediumDate(at)} '
        '${words.formatTimeOfDay(TimeOfDay.fromDateTime(at), alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat)}';
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<ReportedRoomMessage>? queue = _queue;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.all(DeliverySpacing.lg),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(t.chatModerationTitle, style: Theme.of(context).textTheme.headlineMedium),
              ),
              TextButton.icon(
                onPressed: () => unawaited(_load()),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(t.chatModerationRefresh),
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.xs),
          Text(t.chatModerationSub, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: DeliverySpacing.md),
          if (queue == null && !_failed)
            const Padding(
              padding: EdgeInsets.all(DeliverySpacing.xl),
              child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
            )
          else if (queue == null)
            YdEmptyState(
              icon: Icons.cloud_off_outlined,
              title: t.chatModerationCouldNotLoad,
              action: TextButton(onPressed: () => unawaited(_load()), child: Text(t.tryAgain)),
            )
          else if (queue.isEmpty)
            YdEmptyState(icon: Icons.verified_user_outlined, title: t.chatModerationEmpty)
          else
            for (final ReportedRoomMessage line in queue)
              Padding(
                padding: const EdgeInsets.only(bottom: DeliverySpacing.md),
                child: _card(t, line),
              ),
        ],
      ),
    );
  }

  Widget _card(DeliveryStrings t, ReportedRoomMessage line) {
    final bool busy = _busyMessageId == line.messageId;
    final DateTime? first = line.firstReportedAt;
    final DateTime? sent = line.sentAt;
    final DateTime? mutedUntil = line.authorMutedUntil;
    const TextStyle meta = TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.4);

    return YdCard(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: DeliverySpacing.sm,
            runSpacing: DeliverySpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              if (line.roomName != null)
                Text(
                  t.chatRoomTitle(line.roomName!),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: DeliveryColors.ink),
                ),
              YdBadge(
                label: t.chatModerationReports(line.reportCount),
                color: DeliveryAccent.caution.color,
                background: DeliveryAccent.caution.tint,
                uppercase: false,
              ),
              if (line.hidden)
                YdBadge(
                  label: t.chatModerationRemoved,
                  color: DeliveryColors.muted,
                  background: DeliveryColors.background,
                  uppercase: false,
                ),
              if (mutedUntil != null)
                YdBadge(
                  label: t.chatModerationMutedUntil(_moment(mutedUntil)),
                  color: DeliveryColors.brand,
                  background: DeliveryColors.brandSoft,
                  uppercase: false,
                ),
              if (first != null) Text(_moment(first), style: meta),
            ],
          ),
          const SizedBox(height: DeliverySpacing.sm),
          Text(
            [line.authorName ?? t.chatRoomNeighbour, if (sent != null) _moment(sent)].join(' · '),
            style: meta,
          ),
          const SizedBox(height: DeliverySpacing.xs),
          Text(
            line.text,
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: line.hidden ? DeliveryColors.muted : DeliveryColors.ink,
              decoration: line.hidden ? TextDecoration.lineThrough : null,
            ),
          ),
          if (line.reasons.isNotEmpty) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Wrap(
              spacing: DeliverySpacing.xs,
              runSpacing: DeliverySpacing.xs,
              children: <Widget>[
                for (final RoomReportReason reason in line.reasons)
                  YdBadge(
                    label: _reasonLabel(t, reason),
                    color: DeliveryColors.ink,
                    background: DeliveryColors.background,
                    uppercase: false,
                  ),
              ],
            ),
          ],
          const SizedBox(height: DeliverySpacing.md),
          if (busy)
            const LinearProgressIndicator(color: DeliveryColors.brand)
          else
            Wrap(
              spacing: DeliverySpacing.sm,
              runSpacing: DeliverySpacing.sm,
              children: <Widget>[
                if (!line.hidden)
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: DeliveryColors.brand),
                    onPressed: () => unawaited(_decide(line, _Decision.hide)),
                    child: Text(t.chatModerationHide),
                  ),
                if (mutedUntil == null)
                  OutlinedButton(
                    onPressed: () => unawaited(_decide(line, _Decision.mute)),
                    child: Text(t.chatModerationMute),
                  )
                else
                  OutlinedButton(
                    onPressed: () => unawaited(_decide(line, _Decision.unmute)),
                    child: Text(t.chatModerationUnmute),
                  ),
                TextButton(
                  onPressed: () => unawaited(_decide(line, _Decision.dismiss)),
                  child: Text(t.chatModerationDismiss),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Asks for the reason the audit trail will keep. Three characters at least, as the server requires,
/// so a moderator is told here rather than by a failed request.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title});

  final String title;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final TextEditingController _reason = TextEditingController();
  bool _tooShort = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _confirm() {
    final String reason = _reason.text.trim();
    if (reason.length < 3) {
      setState(() => _tooShort = true);
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _reason,
        autofocus: true,
        maxLength: 200,
        decoration: InputDecoration(
          labelText: t.chatModerationReasonLabel,
          errorText: _tooShort ? t.chatModerationReasonTooShort : null,
        ),
        onSubmitted: (_) => _confirm(),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.cancel)),
        FilledButton(onPressed: _confirm, child: Text(t.chatModerationConfirm)),
      ],
    );
  }
}
