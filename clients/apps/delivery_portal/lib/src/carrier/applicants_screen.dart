import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shell/console_controls.dart';
import '../shell/shell.dart';

/// People asking to ride for this company — Figma `carrier-onboarding` (3:3724), "Rider Onboarding
/// Portal".
///
/// The decision belongs here and not in the Backoffice, which is the whole point of the screen.
/// The platform does not know who turned up for a trial, who has a licence, or who was let go last
/// month — a company does. Having the platform hire on its behalf would mean choosing somebody
/// else's staff and leaving them with the consequences.
///
/// Approving does two things at once, and the screen says so before it is pressed: it creates the
/// rider's account and puts them on this company's fleet, so they can be offered work immediately.
///
/// The design draws a three-row document checklist per applicant — national ID, vehicle papers,
/// background check — with Approved / Uploaded / Pending states. There is no document pipeline on
/// this platform. Two of the three rows are replaced by verifications that genuinely exist and are
/// carried on the application (the email address and the phone number were proved to reach the
/// applicant, or were not), and the third is drawn with a Coming-soon chip where its badge goes.
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
  final TextEditingController _search = TextEditingController();
  String _query = '';
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
    _search.dispose();
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

    return ConsolePage(
      header: ConsoleTopbar(
        title: 'Rider Onboarding Portal',
        subtitle: 'Review incoming fleet registration applications and safety documents',
        actions: <Widget>[
          ConsoleSearchField.global(
            hintText: 'Search applicants...',
            controller: _search,
            onChanged: (String value) => setState(() => _query = value.trim()),
          ),
          ConsoleIconAction(
            icon: Icons.refresh,
            tooltip: t.refresh,
            onPressed: () => _load(),
          ),
          const ConsoleIconAction(
            icon: Icons.notifications_none,
            tooltip: 'Notifications — coming soon',
          ),
        ],
      ),
      children: <Widget>[
        _queueHeading(waiting, t),
        _body(t),
      ],
    );
  }

  /// The design's queue row (3:3767): a SemiBold 16 heading with a rose count chip beside it.
  ///
  /// The chip's number is the real count of applications nobody has answered. The population switch
  /// on the right is this screen's own — the design draws only the pending queue, and the ability to
  /// look back at who was turned down predates it and is not worth losing.
  Widget _queueHeading(int waiting, DeliveryStrings t) {
    // A Wrap rather than a Row with a Spacer: the two halves sit apart on one line at the design's
    // width and stack once the content column is narrow enough that they would collide, which a
    // Spacer cannot do — it overflows instead.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: DeliverySpacing.md,
      runSpacing: DeliverySpacing.md - DeliverySpacing.xs,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'Pending Verification Queue',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.ink,
              ),
            ),
            if (!_showAll) ...<Widget>[
              const SizedBox(width: DeliverySpacing.sm),
              ConsoleCountChip(
                waiting == 1 ? '1 Application Left' : '$waiting Applications Left',
              ),
            ],
          ],
        ),
        ConsoleFilterTabs(
          tabs: <ConsoleFilterTab>[
            ConsoleFilterTab(label: t.waitingOnly),
            ConsoleFilterTab(label: t.everyone),
          ],
          selectedIndex: _showAll ? 1 : 0,
          onSelected: (int i) {
            setState(() => _showAll = i == 1);
            _load();
          },
        ),
      ],
    );
  }

  Widget _body(DeliveryStrings t) {
    if (_error != null) {
      // Belonging to no company is a provisioning gap, not a failure — the same expected state the
      // earnings and dashboard screens handle, worded the same way so it does not read as a bug.
      return _empty(
        Icons.help_outline,
        t.noCompanyYet,
        t.askThePlatformToAttachYou,
      );
    }
    if (_loading && _applicants.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(DeliverySpacing.xxl),
        child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
      );
    }

    final List<OnboardingApplication> shown = _applicants
        .where((OnboardingApplication a) =>
            _query.isEmpty ||
            a.contactName.toLowerCase().contains(_query.toLowerCase()) ||
            a.contactEmail.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    if (shown.isEmpty) {
      return _empty(
        Icons.person_search_outlined,
        _query.isNotEmpty
            ? 'Nobody matches that'
            : (_showAll ? t.nobodyHasApplied : t.nobodyWaiting),
        _query.isNotEmpty ? 'Try a different name or email address.' : '',
      );
    }

    // The design's `applications-grid` (3:3771): three equal columns, 20px gutters. Wraps to two
    // and then to one rather than compressing — a card narrower than about 340 puts "Pending
    // Verification" on two lines and the checklist stops scanning.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double gap = ConsoleMetrics.kpiGap;
        const double minCard = 340;
        final int fit = ((constraints.maxWidth + gap) / (minCard + gap)).floor();
        final int perRow = fit.clamp(1, 3);
        final double width = (constraints.maxWidth - gap * (perRow - 1)) / perRow;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final OnboardingApplication a in shown)
              SizedBox(width: width, child: _card(a, t)),
          ],
        );
      },
    );
  }

  Widget _empty(IconData icon, String title, String message) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.xxl),
      decoration: ConsoleSurface.card(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 40, color: DeliveryColors.faint),
          const SizedBox(height: DeliverySpacing.md),
          Text(title, style: ConsoleText.cardTitle),
          if (message.isNotEmpty) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            Text(message, textAlign: TextAlign.center, style: ConsoleText.pageSubtitle),
          ],
        ],
      ),
    );
  }

  /// Figma `onboarding-card` (3:3772): 24px padding, 20px between blocks, radius 16.
  Widget _card(OnboardingApplication a, DeliveryStrings t) {
    final bool busy = _busyId == a.id;

    return Container(
      padding: const EdgeInsets.all(ConsoleMetrics.cardPadding),
      decoration: ConsoleSurface.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _cardTop(a),
          const SizedBox(height: ConsoleMetrics.kpiGap),
          _documents(a),
          if ((a.notes ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: ConsoleMetrics.kpiGap),
            Text(a.notes!, style: ConsoleText.body.copyWith(color: DeliveryColors.muted)),
          ],
          const SizedBox(height: ConsoleMetrics.kpiGap),
          if (a.status.isDecided) _decided(a, t) else _actions(a, busy, t),
        ],
      ),
    );
  }

  Widget _cardTop(OnboardingApplication a) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        // 48px circle, per the design. The photograph it holds there has no source on this
        // platform — an application carries a name, an address and a phone number — so the same
        // geometry carries the applicant's initial instead.
        ConsoleAvatar(name: a.contactName, size: 48),
        const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // The rider's own name leads. On the platform's queue the business name is the
              // headline; here the business is this company, and the person is the news.
              Text(
                a.contactName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: DeliveryColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _registered(a.createdAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: DeliveryColors.faint),
              ),
            ],
          ),
        ),
        const SizedBox(width: DeliverySpacing.sm),
        // The design's call button. There is no dialler to hand a web console, so it does the
        // useful half: puts the number on the clipboard and says so.
        _CallButton(
          phone: a.contactPhone,
          onCopied: () => _tell('${a.contactPhone} copied'),
        ),
      ],
    );
  }

  /// The design's `docs-list` (3:3782), with the two checks this platform actually performs.
  Widget _documents(OnboardingApplication a) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const ConsoleSectionLabel('Onboarding documentation check'),
        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        _DocRow(
          label: 'Email address verified',
          // Null on applications taken before verification existed, and "not checked" is exactly
          // right for those: the account and the decision are both sent to an address nobody
          // confirmed.
          done: a.emailVerified,
          badge: a.emailVerified
              ? const ConsoleSmallBadge(label: 'Approved')
              : const ConsoleSmallBadge(
                  label: 'Pending Verification', accent: DeliveryAccent.caution),
        ),
        _DocRow(
          label: 'Phone number verified',
          done: a.phoneVerified,
          badge: a.contactPhone == null
              ? const ConsoleSmallBadge(label: 'Not given', accent: DeliveryAccent.neutral)
              : a.phoneVerified
                  ? const ConsoleSmallBadge(label: 'Approved')
                  : const ConsoleSmallBadge(
                      label: 'Pending Verification', accent: DeliveryAccent.caution),
        ),
        const _DocRow(
          label: 'Identity, vehicle and background documents',
          done: false,
          badge: ConsoleComingSoonChip(),
          last: true,
        ),
      ],
    );
  }

  Widget _decided(OnboardingApplication a, DeliveryStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ConsoleStatusPill(label: a.status.label, accent: _accentOf(a.status)),
        const SizedBox(height: DeliverySpacing.sm),
        Text(
          a.status == OnboardingStatus.rejected
              ? t.turnedDownBecause(a.rejectionReason ?? '—')
              : t.onYourFleetNow,
          style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.4),
        ),
      ],
    );
  }

  Widget _actions(OnboardingApplication a, bool busy, DeliveryStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Said before the button is pressed, because approving is two irreversible things at once:
        // an account exists afterwards, and this person can be sent work.
        Text(
          t.hiringAlsoCreatesTheirAccount,
          style: ConsoleText.meta.copyWith(height: 1.4),
        ),
        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        Row(
          children: <Widget>[
            Expanded(
              child: ConsoleSoftButton(
                label: 'Reject Application',
                onPressed: busy ? null : () => _turnDown(a, t),
              ),
            ),
            const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
            Expanded(
              child: ConsolePrimaryButton(
                label: 'Approve Rider',
                // Emerald, per the design — the one filled button on these frames that is not
                // crimson, because it is the safe half of a pair with a destructive twin.
                color: DeliveryAccent.positive.color,
                busy: busy,
                onPressed: busy ? null : () => _hire(a, t),
              ),
            ),
          ],
        ),
      ],
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

  /// "Registered today at 09:30", "Registered yesterday at 14:15", "Registered Oct 14, 2025" — the
  /// design's own three shapes.
  static String _registered(DateTime? at) {
    if (at == null) return 'Registration date not recorded';

    final DateTime now = DateTime.now();
    final DateTime day = DateTime(at.year, at.month, at.day);
    final DateTime today = DateTime(now.year, now.month, now.day);
    final String clock =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

    if (day == today) return 'Registered today at $clock';
    if (day == today.subtract(const Duration(days: 1))) {
      return 'Registered yesterday at $clock';
    }
    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return 'Registered ${months[at.month - 1]} '
        '${at.day.toString().padLeft(2, '0')}, ${at.year}';
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

/// One line of the checklist: a 16px state glyph, the label, and the badge.
///
/// Figma `doc-row` (3:3784): 8px vertically, a hairline underneath, Regular 13 slate.
class _DocRow extends StatelessWidget {
  const _DocRow({
    required this.label,
    required this.done,
    required this.badge,
    this.last = false,
  });

  final String label;
  final bool done;
  final Widget badge;

  /// The design draws a rule under every row including the last. Kept, because the block below it
  /// is a button pair rather than more list, and the rule is what separates them.
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.sm),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            done ? Icons.check : Icons.schedule,
            size: 16,
            color: done ? DeliveryAccent.positive.color : DeliveryAccent.caution.color,
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: DeliveryColors.muted),
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          badge,
        ],
      ),
    );
  }
}

/// The design's phone button (3:3780): slate-50, 1px border, radius 8, 8px around a 16px glyph.
class _CallButton extends StatelessWidget {
  const _CallButton({required this.phone, required this.onCopied});

  final String? phone;
  final VoidCallback onCopied;

  @override
  Widget build(BuildContext context) {
    final bool on = phone != null;

    return Tooltip(
      message: on ? 'Copy $phone' : 'No phone number on this application',
      child: Material(
        color: DeliveryColors.background,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        child: InkWell(
          onTap: on
              ? () async {
                  await Clipboard.setData(ClipboardData(text: phone!));
                  onCopied();
                }
              : null,
          borderRadius: BorderRadius.circular(DeliveryRadius.sm),
          child: Container(
            padding: const EdgeInsets.all(DeliverySpacing.sm),
            decoration: BoxDecoration(
              border: Border.all(color: DeliveryColors.border),
              borderRadius: BorderRadius.circular(DeliveryRadius.sm),
            ),
            child: Icon(
              Icons.phone_outlined,
              size: 16,
              color: on ? DeliveryColors.muted : DeliveryColors.faint,
            ),
          ),
        ),
      ),
    );
  }
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
    final bool ready = _reason.text.trim().isNotEmpty;

    return AlertDialog(
      backgroundColor: DeliveryColors.white,
      surfaceTintColor: DeliveryColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
      ),
      title: Text(t.turnDownName(widget.name), style: ConsoleText.cardTitle),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(t.theyAreSentThisWordForWord, style: ConsoleText.pageSubtitle),
            const SizedBox(height: DeliverySpacing.md),
            TextField(
              controller: _reason,
              maxLines: 3,
              maxLength: 500,
              autofocus: true,
              style: ConsoleText.cell,
              cursorColor: DeliveryColors.brand,
              decoration: InputDecoration(
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
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            t.cancel,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.muted,
            ),
          ),
        ),
        ConsoleSoftButton(
          label: t.turnDown,
          onPressed:
              ready ? () => Navigator.pop(context, _reason.text.trim()) : null,
        ),
      ],
    );
  }
}
