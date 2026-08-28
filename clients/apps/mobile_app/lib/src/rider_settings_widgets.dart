import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'application_documents_step.dart';
import 'payout_details_step.dart';
import 'rider_chat_screen.dart';
import 'rider_job_card.dart';

/// The rider-specific sections of Figma `rider-settings` (3:1591), as parts rather than a screen.
///
/// They live here, separately, because the design draws one Driver Settings page but the app has a
/// shared settings screen that every role reaches — language and fingerprint unlock are the same
/// two questions whoever is asking. So these are the rider's *extra* blocks, consumable from the
/// rider shell's Settings tab and from `settings_screen.dart` alike, and neither owns the other.
///
/// Most of these are wired now: the duty toggle to the presence service, the rating to the rating
/// service, documents to the applicant-documents endpoints, and support to the order chat. What is
/// still missing is named where it is missing, with the reason, rather than chipped.

/// `profile-card`: who the rider is, at the top of their own settings.
///
/// The design shows a photographed avatar, a vehicle-and-plate line and a lifetime rating. The
/// avatar is drawn from initials — no account carries a photograph.
///
/// The rating is real: [standing] is the rider's own aggregate, and an unrated rider reads "new"
/// rather than zero, because a zero shown as a score is a lie about somebody's livelihood.
///
/// The **vehicle line is not drawn at all**, and that is deliberate rather than an omission. The
/// vehicle a rider declared lives in their onboarding application's free-form `details`, and the
/// only endpoint that resolves an application from a rider's own token
/// (`GET /api/onboarding/applications/mine`) answers with the *receipt* shape — reference, status,
/// business name, kind, submitted-at, rejection reason — which carries no details at all. So there
/// is nothing to read, and a row saying so, or a chip promising one, would both be furniture.
class RiderProfileCard extends StatelessWidget {
  const RiderProfileCard({
    super.key,
    required this.name,
    this.subtitle,
    this.standing,
  });

  final String name;

  /// A real second line if the caller has one (an email, a reference). Takes precedence over the
  /// rating when both are given.
  final String? subtitle;

  /// The rider's own standing. Null while the rating service has not answered — the line is then
  /// simply absent, which is the honest rendering of a fact nobody has yet.
  final RiderStanding? standing;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return YdCard(
      child: Row(
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: DeliveryColors.brandSoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              _initials(name),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: DeliveryColors.brand,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: DeliverySpacing.xs),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DeliveryColors.muted,
                      height: 1.3,
                    ),
                  ),
                ] else if (standing != null) ...<Widget>[
                  const SizedBox(height: DeliverySpacing.xs),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.star_rounded,
                          size: 14, color: DeliveryAccent.caution.color),
                      const SizedBox(width: DeliverySpacing.xs),
                      Text(
                        standing!.isRated
                            ? t.ratingWithCount(
                                standing!.average!.toStringAsFixed(1),
                                standing!.ratings,
                              )
                            : t.ratingNewRider,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: DeliveryColors.muted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}

/// The compact radius-12 row the design uses for the duty toggle and the language row.
///
/// Not [YdListRow]: that one is a radius-16 card with a chevron, and this is the shorter shell the
/// rider settings body puts its two switch-ish rows in.
class RiderSettingRow extends StatelessWidget {
  const RiderSettingRow({
    super.key,
    required this.icon,
    required this.label,
    required this.trailing,
    this.subtitle,
    this.tint = DeliveryColors.background,
    this.iconColour = DeliveryColors.ink,
    this.onTap,
  });

  final IconData icon;
  final String label;

  /// A muted 11px second line under the label — the duty row's "last seen" fact. Null draws the
  /// single-line row every other caller has always had.
  final String? subtitle;

  final Widget trailing;
  final Color tint;
  final Color iconColour;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget row = Padding(
      padding: const EdgeInsets.all(DeliverySpacing.md),
      child: Row(
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: iconColour),
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: DeliveryColors.muted,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          trailing,
        ],
      ),
    );

    return Semantics(
      button: onTap != null,
      child: Material(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? row : InkWell(onTap: onTap, child: row),
      ),
    );
  }
}

/// `availability-card`: the online/offline switch, wired to the presence API.
///
/// A view, not a caller: the screen that owns the timers and the GPS fix
/// (`rider_home_screen.dart`) owns the presence too, and hands this card the server's last answer.
/// The switch renders what the rider *declared* and the tag beside it what the platform *believes*
/// — a rider who declared duty and then went quiet is [PresenceState.stale], and the card says
/// "signal lost" instead of showing them as available for work they will not receive.
///
/// A shell that was handed no presence API passes no [onChanged], which disables the switch. That
/// is the whole of the unwired rendering now: the previous "coming soon" chip described duty as
/// unbuilt, and it is built.
class RiderDutyToggleCard extends StatelessWidget {
  const RiderDutyToggleCard({
    super.key,
    this.presence,
    this.busy = false,
    this.onChanged,
  });

  /// The server's last answer. Null while it has not answered yet — also the answer a rider who
  /// has never declared duty gets (a 204, not an invented OFF_DUTY).
  final RiderPresence? presence;

  /// True while a declaration is in flight; the switch refuses input rather than lying about
  /// where it will land.
  final bool busy;

  /// Called with the state the rider asked for. The card never assumes the tap worked — the
  /// owner re-renders it with whatever the server said.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    final bool declaredOn = presence?.dutyState == DutyState.onDuty;
    final bool stale = presence?.state == PresenceState.stale;

    return RiderSettingRow(
      icon: Icons.power_settings_new_rounded,
      tint: DeliveryColors.brandSoft,
      iconColour: DeliveryColors.brand,
      label: t.riderActiveDuty,
      subtitle: _subtitle(context, t),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (stale)
            RiderTag(
              label: t.presenceSignalLost,
              color: DeliveryAccent.caution.color,
              background: DeliveryAccent.caution.tint,
            )
          else if (presence != null)
            RiderTag(
              label: declaredOn ? t.dutyOnDuty : t.dutyOffDuty,
              color: declaredOn
                  ? DeliveryAccent.positive.color
                  : DeliveryColors.muted,
              background: declaredOn
                  ? DeliveryAccent.positive.tint
                  : DeliveryColors.background,
            ),
          const SizedBox(width: DeliverySpacing.sm),
          Switch.adaptive(
            value: declaredOn,
            onChanged:
                busy || onChanged == null ? null : (bool on) => onChanged!(on),
            activeThumbColor: DeliveryColors.white,
            activeTrackColor: DeliveryColors.brand,
          ),
        ],
      ),
    );
  }

  /// The last-seen line: when the platform last heard from this device, or the honest sentence
  /// for a rider it has never heard from at all.
  String? _subtitle(BuildContext context, DeliveryStrings t) {
    if (presence == null) return t.riderDutyNotYetDeclared;
    final DateTime? seen = presence!.lastSeenAt;
    if (seen == null) return null;
    final String? age = riderAgeLabel(t, seen);
    return age == null ? null : t.riderLastSeen(age);
  }
}

/// `lang-card`: the language row, showing what is set and opening the place it is changed.
class RiderLanguageRow extends StatelessWidget {
  const RiderLanguageRow({
    super.key,
    required this.value,
    required this.onTap,
  });

  /// The current language, written in its own script.
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RiderSettingRow(
      icon: Icons.language_rounded,
      label: DeliveryStrings.of(context).riderAppLanguage,
      onTap: onTap,
      trailing: Text(
        value,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: DeliveryColors.brand,
          height: 1.2,
        ),
      ),
    );
  }
}

/// One row inside [RiderPreferencesGroup].
///
/// The row carried an `inert` flag that drew a "coming soon" chip where the chevron goes. Every
/// row in this group now leads somewhere — documents, bank details, notifications, help — so the
/// flag has no caller and is gone rather than left as a facility for chipping a row again.
class RiderPreference {
  const RiderPreference({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
}

/// `preferences`: one clipped white group, rows divided by hairlines.
///
/// The design lists Documents & Licenses, Bank Account Details, Notification Preferences and
/// Help & Live Chat Support. Only the shape of the group is load-bearing here — the caller decides
/// which rows go in it and which of them lead anywhere.
class RiderPreferencesGroup extends StatelessWidget {
  const RiderPreferencesGroup({super.key, required this.rows});

  final List<RiderPreference> rows;

  @override
  Widget build(BuildContext context) {
    final bool rtl = Directionality.of(context) == TextDirection.rtl;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < rows.length; i++) ...<Widget>[
            if (i > 0) const RiderHairline(),
            Semantics(
              button: rows[i].onTap != null,
              child: InkWell(
                onTap: rows[i].onTap,
                child: Padding(
                  padding: const EdgeInsets.all(DeliverySpacing.md),
                  child: Row(
                    children: <Widget>[
                      Icon(rows[i].icon,
                          size: 18, color: DeliveryColors.ink),
                      const SizedBox(
                          width: DeliverySpacing.md - DeliverySpacing.xs),
                      Expanded(
                        child: Text(
                          rows[i].label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: DeliveryColors.ink,
                            height: 1.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: DeliverySpacing.sm),
                      Icon(
                        rtl ? Icons.chevron_left : Icons.chevron_right,
                        size: 16,
                        color: DeliveryColors.faint,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The shell every rider settings sheet is presented in: white, rounded at the top, keyboard-aware
/// and scrollable, with a 18px title.
///
/// One helper rather than two copies, because two sheets opened from the same group that do not
/// look like each other read as two different apps.
class _RiderSheet extends StatelessWidget {
  const _RiderSheet({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.ink,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: DeliverySpacing.md),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens one of the rider sheets, in the design's own bottom-sheet shape.
Future<void> showRiderSheet(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DeliveryColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(DeliveryRadius.lg)),
    ),
    builder: builder,
  );
}

/// `preferences` → Help & Live Chat Support, made of what the platform actually has.
///
/// Two halves, and neither of them invents a contact route:
///
/// * **How this works** — the answers to the questions this surface actually raises, written from
///   the behaviour that shipped: duty gates the work, a claim is a race, cash-out is manual, and
///   the Express premium is not the rider's money.
/// * **Your conversations** — the *live* half. The order chat is the only live channel a rider has
///   on this platform, and it is real: the server opens a conversation when a rider is assigned,
///   and this lists them, badge and all, so the rider can reach a customer without first finding
///   the order. There is no support desk, no support number and no support address anywhere in the
///   platform's configuration, so none is drawn — a dead "call support" button costs a rider a
///   phone call at the worst possible moment.
class RiderHelpSheet extends StatefulWidget {
  const RiderHelpSheet({super.key, this.chatApi, this.socket});

  /// The order chat. Null draws the guidance half only.
  final ChatApi? chatApi;
  final UserQueueSocket? socket;

  @override
  State<RiderHelpSheet> createState() => _RiderHelpSheetState();
}

class _RiderHelpSheetState extends State<RiderHelpSheet> {
  Future<List<ChatConversation>>? _threads;

  @override
  void initState() {
    super.initState();
    _threads = widget.chatApi?.conversations();
  }

  Future<void> _open(ChatConversation conversation) async {
    final ChatApi? chat = widget.chatApi;
    if (chat == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RiderChatScreen(
        api: chat,
        socket: widget.socket,
        conversation: conversation,
        orderShortId: conversation.orderId.length <= 8
            ? conversation.orderId
            : conversation.orderId.substring(0, 8),
      ),
    ));
    // The badge moved while that screen was up; re-ask rather than assume.
    if (mounted) setState(() => _threads = chat.conversations());
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return _RiderSheet(
      title: t.riderHelpTitle,
      children: <Widget>[
        _caption(t.riderHelpHowItWorks),
        const SizedBox(height: DeliverySpacing.sm),
        for (final String line in <String>[
          t.riderHelpDuty,
          t.riderHelpClaim,
          t.riderHelpCashOut,
          t.riderHelpExpress,
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
            child: Text(
              line,
              style: const TextStyle(
                fontSize: 13,
                color: DeliveryColors.muted,
                height: 1.5,
              ),
            ),
          ),
        if (widget.chatApi != null) ...<Widget>[
          const SizedBox(height: DeliverySpacing.md),
          const RiderHairline(),
          const SizedBox(height: DeliverySpacing.md),
          _caption(t.riderHelpConversations),
          const SizedBox(height: DeliverySpacing.sm),
          FutureBuilder<List<ChatConversation>>(
            future: _threads,
            builder: (BuildContext context,
                AsyncSnapshot<List<ChatConversation>> snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(DeliverySpacing.md),
                  child: Center(
                      child: CircularProgressIndicator(
                          color: DeliveryColors.brand)),
                );
              }
              if (snapshot.hasError) {
                return _note(t.riderHelpCouldNotLoad);
              }
              final List<ChatConversation> threads = snapshot.data!;
              if (threads.isEmpty) return _note(t.riderHelpNoConversations);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final ChatConversation thread in threads)
                    RiderSettingRow(
                      icon: Icons.chat_bubble_outline_rounded,
                      tint: DeliveryColors.brandSoft,
                      iconColour: DeliveryColors.brand,
                      label: t.riderHelpOrderThread(
                        thread.orderId.length <= 8
                            ? thread.orderId
                            : thread.orderId.substring(0, 8),
                      ),
                      subtitle: thread.open ? null : t.riderHelpThreadClosed,
                      onTap: () => _open(thread),
                      trailing: thread.unread > 0
                          ? RiderTag(
                              label: '${thread.unread}',
                              color: DeliveryColors.white,
                              background: DeliveryColors.brand,
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  static Widget _caption(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: DeliveryColors.faint,
          height: 1.3,
        ),
      );

  static Widget _note(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.sm),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            color: DeliveryColors.muted,
            height: 1.4,
          ),
        ),
      );
}

/// `preferences` → Documents & Licenses, against the applicant-documents endpoints.
///
/// The rider's own file: what the platform holds, and what a reviewer made of each one. It reuses
/// [ApplicantDocumentsCard] rather than restating those rows — the pending screen and this sheet
/// must not disagree about whether a licence was accepted.
///
/// [ApplicantDocumentsCard.canUpload] is false here on purpose. These endpoints resolve the
/// application from the token, and the server refuses changes to a decided one; a rider signed in
/// to the app has been approved by definition, so an upload control here would be a button that
/// always fails. The file stays readable, which is the question a rider is actually asking.
class RiderDocumentsSheet extends StatefulWidget {
  const RiderDocumentsSheet({super.key, required this.api});

  final DocumentsApi api;

  @override
  State<RiderDocumentsSheet> createState() => _RiderDocumentsSheetState();
}

class _RiderDocumentsSheetState extends State<RiderDocumentsSheet> {
  late Future<List<ApplicantDocument>> _documents = widget.api.myDocuments();

  /// What a rider is asked for. The commercial registration is a business's document and is not
  /// among them.
  static const List<ApplicantDocumentKind> _riderKinds = <ApplicantDocumentKind>[
    ApplicantDocumentKind.nationalId,
    ApplicantDocumentKind.drivingLicence,
    ApplicantDocumentKind.vehicleRegistration,
  ];

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return _RiderSheet(
      title: t.riderDocumentsTitle,
      children: <Widget>[
        FutureBuilder<List<ApplicantDocument>>(
          future: _documents,
          builder: (BuildContext context,
              AsyncSnapshot<List<ApplicantDocument>> snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(DeliverySpacing.md),
                child: Center(
                    child:
                        CircularProgressIndicator(color: DeliveryColors.brand)),
              );
            }
            if (snapshot.hasError) {
              return Text(
                t.riderDocumentsCouldNotLoad,
                style: const TextStyle(
                  fontSize: 13,
                  color: DeliveryColors.muted,
                  height: 1.4,
                ),
              );
            }
            return ApplicantDocumentsCard(
              api: widget.api,
              documents: snapshot.data!,
              kinds: _riderKinds,
              canUpload: false,
              onChanged: () =>
                  setState(() => _documents = widget.api.myDocuments()),
            );
          },
        ),
      ],
    );
  }
}

/// `preferences` → Bank Account Details, against the applicant-payout endpoints.
///
/// Read-only, and that is the server's rule rather than a shortcut: the onboarding payout endpoint
/// refuses a change once the application is decided, on the grounds that after approval the
/// account is what the platform is about to pay and redirecting it through the applicant-facing
/// route would bypass whatever the payments side requires. A rider signed in to this app has been
/// approved, so [PayoutDetailsCard.canEdit] is false and the card shows the record rather than an
/// editor that would always be refused.
///
/// The number is shown to its owner in full — masking a number somebody is being asked to check
/// defeats the point of showing it.
class RiderPayoutSheet extends StatefulWidget {
  const RiderPayoutSheet({super.key, required this.api});

  final DocumentsApi api;

  @override
  State<RiderPayoutSheet> createState() => _RiderPayoutSheetState();
}

class _RiderPayoutSheetState extends State<RiderPayoutSheet> {
  late Future<PayoutDetails?> _payout = widget.api.myPayout();

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return _RiderSheet(
      title: t.riderBankDetails,
      children: <Widget>[
        FutureBuilder<PayoutDetails?>(
          future: _payout,
          builder:
              (BuildContext context, AsyncSnapshot<PayoutDetails?> snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(DeliverySpacing.md),
                child: Center(
                    child:
                        CircularProgressIndicator(color: DeliveryColors.brand)),
              );
            }
            if (snapshot.hasError) {
              return Text(
                t.riderPayoutCouldNotLoad,
                style: const TextStyle(
                  fontSize: 13,
                  color: DeliveryColors.muted,
                  height: 1.4,
                ),
              );
            }
            return PayoutDetailsCard(
              api: widget.api,
              payout: snapshot.data,
              canEdit: false,
              onChanged: () => setState(() => _payout = widget.api.myPayout()),
            );
          },
        ),
      ],
    );
  }
}

/// `logout-btn`: the outlined destructive button that ends the session.
class RiderLogOutButton extends StatelessWidget {
  const RiderLogOutButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: RiderButton(
        label: DeliveryStrings.of(context).signOut,
        style: RiderButtonStyle.outlined,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        verticalPadding: 14,
        onPressed: onPressed,
      ),
    );
  }
}
