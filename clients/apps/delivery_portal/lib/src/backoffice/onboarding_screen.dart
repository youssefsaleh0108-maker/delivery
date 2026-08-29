import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../shell/console_controls.dart';
import '../shell/shell.dart';
import 'auto_approval_panel.dart';

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
///
/// Drawn as `backoffice-merchants` (Figma 3:2666): a directory of partners across two tabs, with
/// the decision itself moved off the row and into a drawer. A row is scanned; a decision that is
/// sent to a person verbatim is read. Keeping both on the same surface made the table either too
/// tall to scan or too terse to decide from.
///
/// The drawer now also carries the applicant's uploaded papers, reviewed one by one: the document
/// pipeline exists, and each document is approved with a click or refused with a typed reason the
/// applicant is shown verbatim — the same asymmetry as the application decision itself, for the
/// same cause: a refusal nobody can see the reason for produces the same photograph uploaded again
/// unchanged.
/// A partner who is already live is managed rather than decided: their record can be corrected,
/// their standing can be withdrawn and given back, and every one of those changes is written down.
/// That is [PartnerManagementApi], and it is why the two row actions on a decided partner — the
/// pencil and the block — are no longer drawn dead.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.api,
    required this.documentsApi,
    this.managementApi,
    this.notificationApi,
    this.autoApprovalApi,
  });

  final OnboardingApi api;
  final DocumentsApi documentsApi;

  /// Read-only here, and only so the queue can say which kinds are approving themselves.
  ///
  /// A reviewer opening an empty queue has two explanations available — nobody applied, or nobody
  /// has to be read any more — and guessing wrong either way is expensive. The switches themselves
  /// stay on Settings: this screen is where applications are decided, and a control that changes
  /// whether they arrive at all does not belong beside the decision.
  ///
  /// Optional so the screen still renders standalone; null simply draws no line rather than
  /// claiming everything waits for a person.
  final AutoApprovalApi? autoApprovalApi;

  /// Corrections, the audit trail and the suspension switch. Optional so the screen still renders
  /// standalone; null leaves the two decided-row actions drawn and disabled, as they were.
  final PartnerManagementApi? managementApi;

  /// The operator's own in-app inbox, behind the header's bell.
  final NotificationApi? notificationApi;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

/// Which population the directory is showing.
///
/// Not a status filter: "All Partners" and "Pending Approval" are answered by two different
/// endpoints, because the queue endpoint is the one that guarantees oldest-first.
enum _Tab { all, pending }

class _OnboardingScreenState extends State<OnboardingScreen> {
  /// Applications arrive from a public form at any hour, so the queue refreshes itself.
  static const Duration _pollInterval = Duration(seconds: 30);

  Timer? _poll;
  List<OnboardingApplication> _applications = <OnboardingApplication>[];
  _Tab _tab = _Tab.pending;
  bool _loading = true;
  Object? _error;
  String? _busyId;

  /// Where each already-decided partner stands, keyed by application id.
  ///
  /// Loaded alongside the list, one request per decided row, because the standing is not on the
  /// application record — suspension lives in its own table with its own history. A row missing
  /// from this map is one whose standing could not be read, and its block action falls back to
  /// "Suspend": the endpoint is idempotent, so an operator can never do harm by pressing it on a
  /// partner who is already suspended.
  Map<String, PartnerStanding> _standings = <String, PartnerStanding>{};

  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// The Category filter's chosen value, or null for all of them.
  String? _category;

  /// Which kinds are being waved through, or null while unknown — including after a failed read.
  ///
  /// Deliberately not retried and not surfaced as an error: this is context on somebody else's
  /// page. A queue that loaded is still workable without it, and a red box about a settings
  /// endpoint would take attention from the applications this screen is for.
  AutoApprovalSettings? _autoApproval;

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadAutoApproval();
    _poll = Timer.periodic(_pollInterval, (_) => _refresh(silent: true));
  }

  Future<void> _loadAutoApproval() async {
    final AutoApprovalApi? api = widget.autoApprovalApi;
    if (api == null) return;
    try {
      final AutoApprovalSettings loaded = await api.get();
      if (!mounted) return;
      setState(() => _autoApproval = loaded);
    } catch (_) {
      // Left null. See the field comment: silence is the right failure here.
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final List<OnboardingApplication> loaded =
          _tab == _Tab.all ? await widget.api.all() : await widget.api.queue();
      if (!mounted) return;
      setState(() {
        _applications = loaded;
        _error = null;
        _loading = false;
      });
      unawaited(_loadStandings(loaded));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _error = e;
        _loading = false;
      });
    }
  }

  /// One standing lookup per decided partner, concurrently. There is no batch endpoint, and the
  /// standing is not carried on the application record.
  ///
  /// A failed lookup leaves the row out of the map rather than assuming "active" — the block action
  /// then reads "Suspend", which is safe on an already-suspended partner (the endpoint is
  /// idempotent and records nothing the second time).
  Future<void> _loadStandings(List<OnboardingApplication> applications) async {
    final PartnerManagementApi? api = widget.managementApi;
    if (api == null) return;

    final List<OnboardingApplication> live =
        applications.where(_suspendable).toList();
    final List<MapEntry<String, PartnerStanding>?> found =
        await Future.wait<MapEntry<String, PartnerStanding>?>(
      live.map((OnboardingApplication a) async {
        try {
          final PartnerSuspensionRecord record = await api.suspension(a.id);
          return MapEntry<String, PartnerStanding>(
            a.id,
            PartnerStanding(suspended: record.suspended, lastChange: record.lastChange),
          );
        } catch (_) {
          return null;
        }
      }),
    );
    if (!mounted) return;
    setState(() {
      _standings = <String, PartnerStanding>{
        for (final MapEntry<String, PartnerStanding>? e in found)
          if (e != null) e.key: e.value,
      };
    });
  }

  /// Whether the suspension switch applies at all.
  ///
  /// The server refuses (422) an application that is still undecided or was declined — there is no
  /// role to revoke and no sign-in account behind it — so the action is drawn disabled there rather
  /// than offered and then refused.
  static bool _suspendable(OnboardingApplication a) =>
      a.status == OnboardingStatus.approved ||
      a.status == OnboardingStatus.provisioned ||
      a.status == OnboardingStatus.failed;

  // -------------------------------------------------------------------- corrections

  /// Corrects the record. Only the fields the operator actually changed are sent: an unchanged
  /// field is absent from the PATCH, and a PATCH that changes nothing writes no audit row.
  Future<void> _edit(OnboardingApplication a) async {
    final PartnerManagementApi? api = widget.managementApi;
    if (api == null) return;

    final _PartnerEdit? edit = await showDialog<_PartnerEdit>(
      context: context,
      builder: (BuildContext context) => _EditPartnerDialog(application: a),
    );
    if (edit == null || edit.isEmpty || !mounted) return;

    setState(() => _busyId = a.id);
    try {
      final PartnerRecordView updated = await api.edit(
        a.id,
        businessName: edit.businessName,
        contactName: edit.contactName,
        contactEmail: edit.contactEmail,
        contactPhone: edit.contactPhone,
      );
      // The server's own asymmetry, said out loud: a new number is a number nobody has confirmed.
      final String note = edit.contactPhone != null && updated.phoneVerifiedAt == null
          ? ' The new phone number is now unverified.'
          : '';
      _tell('${updated.businessName} updated.$note');
      await _refresh(silent: true);
    } catch (e) {
      _tell(_messageFrom(e), bad: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  // -------------------------------------------------------------------- the standing

  Future<void> _suspend(OnboardingApplication a) async {
    final PartnerManagementApi? api = widget.managementApi;
    if (api == null) return;

    final _Suspension? decision = await showDialog<_Suspension>(
      context: context,
      builder: (BuildContext context) => _SuspendDialog(application: a),
    );
    if (decision == null || !mounted) return;

    setState(() => _busyId = a.id);
    try {
      final PartnerStanding standing =
          await api.suspend(a.id, decision.reason, note: decision.note);
      if (!mounted) return;
      setState(() => _standings = <String, PartnerStanding>{..._standings, a.id: standing});
      _tell('${a.businessName} suspended. Their ${_roleOf(a.kind)} role has been revoked.');
    } catch (e) {
      _tell(_messageFrom(e), bad: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _unsuspend(OnboardingApplication a) async {
    final PartnerManagementApi? api = widget.managementApi;
    if (api == null) return;

    final String? note = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _UnsuspendDialog(application: a),
    );
    if (note == null || !mounted) return;

    setState(() => _busyId = a.id);
    try {
      final PartnerStanding standing =
          await api.unsuspend(a.id, note: note.isEmpty ? null : note);
      if (!mounted) return;
      setState(() => _standings = <String, PartnerStanding>{..._standings, a.id: standing});
      _tell('${a.businessName} reinstated. Their ${_roleOf(a.kind)} role is back.');
    } catch (e) {
      _tell(_messageFrom(e), bad: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// The realm role a suspension actually takes away. A rider's is `DELIVERY`, not `RIDER` — the
  /// commercial word and the Keycloak word differ, and the confirm dialog names the one that
  /// changes.
  static String _roleOf(OnboardingKind kind) => switch (kind) {
        OnboardingKind.merchant => 'MERCHANT',
        OnboardingKind.carrier => 'CARRIER',
        OnboardingKind.rider => 'DELIVERY',
      };

  // -------------------------------------------------------------------- reading the list

  /// What the Category column shows, and what the Category filter filters on.
  ///
  /// The applicant's own answer where the signup wizard asked for one, and what they applied to be
  /// otherwise. Never a guess: a shop that did not say what it sells is "Shop", not "Restaurant".
  static String _categoryOf(OnboardingApplication a) =>
      a.details['businessType'] ?? a.details['vehicleType'] ?? a.kind.label;

  /// The categories actually present in what is loaded, so the filter can only offer real answers.
  List<String> get _categories {
    final Set<String> found =
        _applications.map(_categoryOf).where((String c) => c.isNotEmpty).toSet();
    return found.toList()..sort();
  }

  List<OnboardingApplication> get _visible {
    final String q = _query.trim().toLowerCase();
    return _applications.where((OnboardingApplication a) {
      if (_category != null && _categoryOf(a) != _category) return false;
      if (q.isEmpty) return true;
      return a.businessName.toLowerCase().contains(q) ||
          a.contactName.toLowerCase().contains(q) ||
          a.contactEmail.toLowerCase().contains(q) ||
          a.reference.toLowerCase().contains(q);
    }).toList();
  }

  int get _waiting =>
      _applications.where((OnboardingApplication a) => !a.status.isDecided).length;

  @override
  Widget build(BuildContext context) {
    return ConsolePage(
      header: ConsoleTopbar(
        title: 'Merchants Directory',
        subtitle: 'Review, approve, and suspend merchant partners',
        actions: <Widget>[
          ConsoleBell(api: widget.notificationApi),
          // Not in the design, and kept: the queue polls itself every 30s, and an operator who has
          // just told somebody "you're approved" wants to see it now rather than in 29 seconds.
          ConsoleIconAction(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _refresh(),
          ),
        ],
      ),
      children: <Widget>[
        _controls(),
        if (_autoApproval != null) _autoApprovalLine(_autoApproval!),
        _table(),
      ],
    );
  }

  /// One quiet line above the table: which kinds never reach it, and where that is changed.
  ///
  /// Said in both directions. "Nothing is automatic" is the more useful of the two sentences to a
  /// reviewer staring at an empty queue, because it rules out the explanation that would otherwise
  /// be the first guess — and it is only true when it has actually been read from the server.
  Widget _autoApprovalLine(AutoApprovalSettings settings) {
    final List<OnboardingKind> automatic = settings.automaticKinds;
    // "Never appear here" would be wrong, and wrong in the place a reviewer can see: auto-approved
    // applications are persisted like any other and the All Partners tab lists them, already
    // approved and stamped system:auto-approval. Only the pending queue excludes them, because
    // that query asks for SUBMITTED and IN_REVIEW. The honest sentence is about waiting, not about
    // appearing — and it has to survive being read on either tab.
    final String text = automatic.isEmpty
        ? 'Every application is read by a person. Nothing is approved automatically.'
        : '${_and(automatic.map(autoApprovalKindLabel).toList())} are approved automatically — '
            'those applications are never waiting for a decision. Their documents are still '
            'collected and still open from the row.';

    return Row(
      children: <Widget>[
        Icon(
          automatic.isEmpty ? Icons.how_to_reg_outlined : Icons.bolt_outlined,
          size: 14,
          color: DeliveryColors.faint,
        ),
        const SizedBox(width: DeliverySpacing.sm),
        Expanded(child: Text(text, style: ConsoleText.meta)),
        // Read-only, and it says so by pointing at the page that is not: the control belongs with
        // the other settings, and a reviewer who wants it should not have to hunt for it twice.
        const Text('Changed in Settings › Approvals', style: ConsoleText.meta),
      ],
    );
  }

  /// "Riders", "Riders and Shops", "Riders, Shops and Delivery companies".
  static String _and(List<String> parts) {
    if (parts.length == 1) return parts.single;
    return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }

  /// Figma `controls-row` (3:2720): the tabs against the left edge, the filters against the right.
  ///
  /// A [Wrap] rather than a Row with a Spacer. At 1440 the two groups sit exactly where the design
  /// draws them; the difference shows up at 1024, where a Row overflowed by two pixels because the
  /// two groups happened to add up to slightly more than the content width. A breakpoint would only
  /// have moved the guess — this drops the filters onto a second line whenever they genuinely do
  /// not fit, at whatever width that turns out to be.
  Widget _controls() {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: DeliverySpacing.md,
      runSpacing: DeliverySpacing.md,
      children: <Widget>[
        ConsoleFilterTabs(
          tabs: <ConsoleFilterTab>[
            const ConsoleFilterTab(label: 'All Partners'),
            // The design's bracketed count, and real on either tab: the queue endpoint returns
            // only what is waiting, and the full list carries the same applications with their
            // status on them, so counting the undecided ones is correct in both cases. Suppressed
            // while loading rather than shown as zero — no applications and none loaded yet are
            // different things, and only one of them is good news.
            ConsoleFilterTab(
              label: 'Pending Approval',
              count: _loading ? null : _waiting,
            ),
          ],
          selectedIndex: _tab == _Tab.all ? 0 : 1,
          onSelected: (int i) {
            setState(() => _tab = i == 0 ? _Tab.all : _Tab.pending);
            _refresh();
          },
        ),
        Wrap(
          spacing: DeliverySpacing.md - DeliverySpacing.xs,
          runSpacing: DeliverySpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            ConsoleSearchField(
              hintText: 'Search merchants...',
              controller: _search,
              width: 232,
              onChanged: (String v) => setState(() => _query = v),
            ),
            _categoryFilter(),
          ],
        ),
      ],
    );
  }

  /// Figma `filter-btn` (3:2731), wired: the values come from the applications on screen, so it can
  /// only ever offer a category something actually is.
  Widget _categoryFilter() {
    return ConsoleSelect(
      label: _category ?? 'Category',
      icon: Icons.tune,
      tooltip: 'Filter by category',
      options: <ConsoleOption>[
        const ConsoleOption(label: 'All categories', value: null),
        for (final String category in _categories)
          ConsoleOption(label: category, value: category),
      ],
      onSelected: (String? value) => setState(() => _category = value),
    );
  }

  // -------------------------------------------------------------------- the table

  Widget _table() {
    if (_error != null) {
      return ConsoleCard(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.cloud_off, size: 28, color: DeliveryAccent.critical.color),
                const SizedBox(height: DeliverySpacing.sm),
                const Text('Could not load applications.', style: ConsoleText.cardTitle),
                const SizedBox(height: DeliverySpacing.xs),
                Text('$_error', style: ConsoleText.meta, textAlign: TextAlign.center),
                const SizedBox(height: DeliverySpacing.md),
                ConsoleButton(label: 'Try again', onPressed: () => _refresh()),
              ],
            ),
          ),
        ),
      );
    }

    if (_loading && _applications.isEmpty) {
      return const ConsoleCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: DeliverySpacing.xl),
            child: CircularProgressIndicator(color: DeliveryColors.brand),
          ),
        ),
      );
    }

    final List<OnboardingApplication> rows = _visible;

    return ConsoleTable(
      minWidth: 980,
      columns: const <ConsoleColumn>[
        ConsoleColumn(label: 'Merchant Name', flex: 1),
        ConsoleColumn(label: 'Category', width: 150),
        ConsoleColumn(label: 'Status', width: 120),
        ConsoleColumn(label: 'Products', width: 100),
        ConsoleColumn(label: 'Orders', width: 100),
        ConsoleColumn(label: 'Join Date', width: 140),
        ConsoleColumn(label: 'Actions', width: 120, alignRight: true),
      ],
      rows: <ConsoleTableRow>[
        for (final OnboardingApplication a in rows) _row(a),
      ],
      empty: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.inbox_outlined, size: 28, color: DeliveryColors.faint),
            const SizedBox(height: DeliverySpacing.sm),
            Text(
              _applications.isEmpty
                  ? (_tab == _Tab.all
                      ? 'Nobody has applied yet.'
                      : 'Nothing waiting to be read.')
                  : 'No partner matches that search.',
              style: ConsoleText.cellStrong,
            ),
          ],
        ),
      ),
      // Two of the design's columns have no source. Said once, under the table, rather than
      // stamped into forty cells.
      footer: const ConsoleInertNote(
        chipLabel: 'Not aggregated',
        text: 'Product and order counts per partner are not aggregated by any endpoint yet.',
      ),
    );
  }

  ConsoleTableRow _row(OnboardingApplication a) {
    final bool busy = _busyId == a.id;
    final bool pending = !a.status.isDecided;
    final bool manageable = widget.managementApi != null;
    final bool suspended = _standings[a.id]?.suspended ?? false;

    return ConsoleTableRow(
      onTap: () => _open(a),
      cells: <Widget>[
        ConsoleNameCell(
          name: a.businessName,
          secondary: a.contactName.isEmpty ? a.reference : a.contactName,
          leading: ConsoleInitialTile(label: a.businessName),
        ),
        Text(
          _categoryOf(a),
          overflow: TextOverflow.ellipsis,
          style: ConsoleText.cellMuted,
        ),
        // A suspended partner must be visible from the directory, not only from their drawer —
        // somebody scanning for "why is this shop not taking orders" reads this column first.
        if (suspended)
          Tooltip(
            message: 'Application status: ${a.status.label}',
            child: ConsoleStatusPill(
              label: 'Suspended',
              accent: DeliveryAccent.critical,
            ),
          )
        else
          ConsoleStatusPill(label: a.status.label, accent: _accentOf(a.status)),
        const ConsoleNoValue(tooltip: 'No per-partner product count yet'),
        const ConsoleNoValue(tooltip: 'No per-partner order count yet'),
        Text(_date(a.createdAt), style: ConsoleText.cellMuted),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (pending) ...<Widget>[
              // The live decision, in the design's row-action geometry. Approve is one tap;
              // Decline goes through the reason dialog, as it always has.
              ConsoleRowAction(
                icon: Icons.check,
                tooltip: 'Approve',
                onPressed: busy ? null : () => _approve(a),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              ConsoleRowAction(
                icon: Icons.close,
                tooltip: 'Decline',
                destructive: true,
                onPressed: busy ? null : () => _decline(a),
              ),
            ] else ...<Widget>[
              // The design's two actions against a live partner, both wired: the pencil corrects
              // the record, the block withdraws their standing.
              ConsoleRowAction(
                icon: Icons.edit_outlined,
                tooltip: manageable ? 'Edit partner' : 'Editing is not available in this build',
                onPressed: busy || !manageable ? null : () => _edit(a),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              if (suspended)
                ConsoleRowAction(
                  icon: Icons.lock_open,
                  tooltip: 'Reinstate partner',
                  onPressed: busy ? null : () => _unsuspend(a),
                )
              else
                ConsoleRowAction(
                  icon: Icons.block,
                  tooltip: !manageable
                      ? 'Suspension is not available in this build'
                      : _suspendable(a)
                          ? 'Suspend partner'
                          // The server refuses this one, and says so first rather than after.
                          : 'A declined application has no standing to withdraw',
                  destructive: true,
                  onPressed:
                      busy || !manageable || !_suspendable(a) ? null : () => _suspend(a),
                ),
            ],
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------------- the drawer

  Future<void> _open(OnboardingApplication a) async {
    final PartnerManagementApi? management = widget.managementApi;

    await showConsoleDrawer<void>(
      context: context,
      title: a.businessName,
      subtitle: '${a.kind.label} · applied ${_when(a.createdAt)}',
      badge: ConsoleStatusPill(label: a.status.label, accent: _accentOf(a.status)),
      builder: (BuildContext drawerContext) => _ApplicationDetail(
        application: a,
        documents: _ReviewerDocuments(
          load: () => widget.documentsApi.applicationDocuments(a.id),
          approve: (String documentId) =>
              widget.documentsApi.approveDocument(a.id, documentId),
          reject: (String documentId, String reason) =>
              widget.documentsApi.rejectDocument(a.id, documentId, reason: reason),
        ),
        // Null when the portal was built without the management client — the section then does not
        // draw at all, rather than drawing an empty history that reads as "never touched".
        history: management == null
            ? null
            : _PartnerHistory(
                audit: () => management.audit(a.id),
                suspension: () => management.suspension(a.id),
              ),
        onEdit: management == null
            ? null
            : () {
                Navigator.of(drawerContext).pop();
                _edit(a);
              },
        onApprove: () {
          Navigator.of(drawerContext).pop();
          _approve(a);
        },
        onDecline: () {
          Navigator.of(drawerContext).pop();
          _decline(a);
        },
      ),
    );
  }

  // -------------------------------------------------------------------- the decisions

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

  /// The design's join-date spelling — "Oct 12, 2025".
  static String _date(DateTime? at) {
    if (at == null) return '—';
    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[at.month - 1]} ${at.day.toString().padLeft(2, '0')}, ${at.year}';
  }

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

/// Everything a decision is made on, in the drawer the row opens.
///
/// The contact details and their verification marks, the applicant's own words, whatever the signup
/// wizard collected, and — for one already decided — what happened afterwards.
class _ApplicationDetail extends StatelessWidget {
  const _ApplicationDetail({
    required this.application,
    required this.documents,
    required this.history,
    required this.onEdit,
    required this.onApprove,
    required this.onDecline,
  });

  final OnboardingApplication application;
  final _ReviewerDocuments documents;

  /// The record's own history — corrections and standing changes. Null when this build has no
  /// management client to read it with.
  final _PartnerHistory? history;

  final VoidCallback? onEdit;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final OnboardingApplication a = application;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // The one warning worth interrupting a reviewer with. Applications taken before
        // verification existed carry no proof, and approving one means the account goes to an
        // address nobody confirmed.
        if (!a.status.isDecided && !a.emailVerified) ...<Widget>[
          _Note(
            text: 'This email address was never verified. Anything sent to it — including how to '
                'sign in — may reach somebody else.',
            accent: DeliveryAccent.caution,
            icon: Icons.warning_amber_rounded,
          ),
          const SizedBox(height: ConsoleMetrics.pageGap),
        ],

        ConsoleDrawerSection(
          title: 'Applicant',
          first: true,
          // The correction lives beside the details it corrects. Available at every status: an
          // application waiting to be read is exactly where a mistyped address gets caught.
          trailing: onEdit == null
              ? null
              : ConsoleButton(
                  label: 'Edit details',
                  icon: Icons.edit_outlined,
                  tone: ConsoleButtonTone.outlined,
                  onPressed: onEdit,
                ),
          child: ConsoleFactGrid(
            facts: <ConsoleFact>[
              ConsoleFact('Contact', a.contactName.isEmpty ? 'Not given' : a.contactName,
                  absent: a.contactName.isEmpty),
              // The verification marks are the point of showing these at all. Approving an
              // application whose address was never proved sends an account to whoever actually
              // owns that inbox — so the reviewer sees which details were checked before deciding.
              ConsoleFact(
                'Email',
                a.contactEmail,
                mark: a.emailVerified
                    ? const ConsoleFactMark.verified()
                    : const ConsoleFactMark.unverified(),
              ),
              ConsoleFact(
                'Phone',
                a.contactPhone ?? 'Not given',
                absent: a.contactPhone == null,
                mark: a.contactPhone == null
                    ? null
                    : (a.phoneVerified
                        ? const ConsoleFactMark.verified()
                        : const ConsoleFactMark.unverified()),
              ),
              ConsoleFact('Reference', a.reference.isEmpty ? '—' : a.reference,
                  absent: a.reference.isEmpty),
            ],
          ),
        ),

        // The signup wizard's own answers — vehicle, work region, business type. Present on
        // applications taken through the newer flow and absent on everything older, which is why
        // the whole section disappears rather than showing a row of dashes.
        if (a.details.isNotEmpty)
          ConsoleDrawerSection(
            title: 'From their application',
            child: ConsoleFactGrid(
              facts: <ConsoleFact>[
                for (final MapEntry<String, String> e in a.details.entries)
                  ConsoleFact(_humanise(e.key), e.value),
              ],
            ),
          ),

        // The applicant's uploaded papers, decided one by one. Live for every application — a
        // reviewer reading a decided record still needs to see what the decision rested on.
        ConsoleDrawerSection(
          title: 'Documents',
          child: _DocumentReviewList(
            documents: documents,
            readOnly: a.status.isDecided,
          ),
        ),

        if ((a.notes ?? '').isNotEmpty)
          ConsoleDrawerSection(
            title: 'What they wrote',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(DeliverySpacing.md - 2),
              decoration: BoxDecoration(
                color: DeliveryColors.background,
                borderRadius: BorderRadius.circular(DeliveryRadius.sm),
              ),
              child: Text(a.notes!, style: ConsoleText.body),
            ),
          ),

        if (a.status.isDecided)
          ConsoleDrawerSection(
            title: 'Outcome',
            child: Text(_outcomeOf(a), style: ConsoleText.body),
          ),

        // Who changed what, and when. Two sources — field corrections and standing changes — read
        // as one story, because that is how somebody asking "what happened to this partner"
        // needs it.
        if (history != null)
          ConsoleDrawerSection(
            title: 'History',
            child: _HistoryList(history: history!),
          ),

        if (!a.status.isDecided) ...<Widget>[
          const SizedBox(height: ConsoleMetrics.pageGap),
          const Divider(height: 1, color: DeliveryColors.border),
          const SizedBox(height: ConsoleMetrics.pageGap),
          Row(
            children: <Widget>[
              Expanded(
                child: ConsoleButton(
                  label: a.kind == OnboardingKind.carrier
                      ? 'Approve and set up the company'
                      : 'Approve',
                  icon: Icons.check,
                  tone: ConsoleButtonTone.solid,
                  onPressed: onApprove,
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              ConsoleButton(
                label: 'Decline',
                icon: Icons.close,
                tone: ConsoleButtonTone.outlined,
                onPressed: onDecline,
              ),
            ],
          ),
        ],
      ],
    );
  }

  static String _outcomeOf(OnboardingApplication a) {
    final String who = a.decidedBy == null ? '' : ' by ${_short(a.decidedBy!)}';
    final String at = _OnboardingScreenState._when(a.decidedAt);
    return switch (a.status) {
      OnboardingStatus.rejected =>
        'Declined$who $at — ${a.rejectionReason ?? "no reason recorded"}',
      OnboardingStatus.provisioned =>
        'Approved$who $at. Account created; they can set a password and sign in.',
      OnboardingStatus.approved => 'Approved$who $at. Setting the account up now.',
      // Its own state because it needs different work: an approved application is waiting on a
      // machine, a failed one is waiting on a person.
      OnboardingStatus.failed =>
        'Approved$who, but setting the account up did not finish. Somebody has to look at this.',
      _ => '',
    };
  }

  static String _short(String id) => id.length <= 8 ? id : '${id.substring(0, 8)}…';

  /// `businessType` → `Business type`. The wizard's keys are camelCase and are shown to a person.
  static String _humanise(String key) {
    final String spaced = key
        .replaceAllMapped(RegExp(r'(?<=[a-z0-9])([A-Z])'), (Match m) => ' ${m[1]!.toLowerCase()}')
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .trim();
    if (spaced.isEmpty) return key;
    return spaced[0].toUpperCase() + spaced.substring(1);
  }
}

/// The document endpoints for one application, bundled so the list widget stays ignorant of ids.
class _ReviewerDocuments {
  const _ReviewerDocuments({
    required this.load,
    required this.approve,
    required this.reject,
  });

  final Future<List<ReviewedDocument>> Function() load;
  final Future<ReviewedDocument> Function(String documentId) approve;
  final Future<ReviewedDocument> Function(String documentId, String reason) reject;
}

/// The papers on one application, each with its own verdict.
///
/// Loads itself when the drawer opens rather than making the row click wait on a second request —
/// a reviewer reads the applicant block first anyway. Each decision refreshes only this list; the
/// application row outside carries no document state to go stale.
class _DocumentReviewList extends StatefulWidget {
  const _DocumentReviewList({required this.documents, required this.readOnly});

  final _ReviewerDocuments documents;

  /// True on a decided application: the record stays readable, the verdict buttons go — deciding
  /// a document under an application that is already answered would change nothing for anybody.
  final bool readOnly;

  @override
  State<_DocumentReviewList> createState() => _DocumentReviewListState();
}

class _DocumentReviewListState extends State<_DocumentReviewList> {
  late Future<List<ReviewedDocument>> _docs = widget.documents.load();
  String? _busyId;

  void _reload() => setState(() => _docs = widget.documents.load());

  Future<void> _approve(ReviewedDocument doc) async {
    setState(() => _busyId = doc.id);
    try {
      await widget.documents.approve(doc.id);
      _reload();
    } catch (e) {
      _tell(_documentError(e));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _reject(ReviewedDocument doc) async {
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext context) =>
          _DocumentReasonDialog(documentLabel: _labelOf(doc)),
    );
    if (reason == null || reason.trim().isEmpty || !mounted) return;

    setState(() => _busyId = doc.id);
    try {
      await widget.documents.reject(doc.id, reason.trim());
      _reload();
    } catch (e) {
      _tell(_documentError(e));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _tell(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: DeliveryAccent.critical.color,
    ));
  }

  static String _documentError(Object e) {
    if (e is DioException) {
      final Object? body = e.response?.data;
      if (body is Map) {
        if (body['message'] is String) return body['message'] as String;
        if (body['detail'] is String) return body['detail'] as String;
      }
    }
    return 'That did not go through. Try again.';
  }

  /// The typed kind's label, or the server's own spelling for a kind this build does not know —
  /// never a guess.
  static String _labelOf(ReviewedDocument doc) => doc.kind?.label ?? doc.kindWire;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ReviewedDocument>>(
      future: _docs,
      builder: (BuildContext context, AsyncSnapshot<List<ReviewedDocument>> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: DeliverySpacing.md),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: DeliveryColors.brand),
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return Row(
            children: <Widget>[
              const Expanded(
                child: Text('Could not load the documents.', style: ConsoleText.meta),
              ),
              ConsoleButton(
                label: 'Try again',
                tone: ConsoleButtonTone.outlined,
                onPressed: _reload,
              ),
            ],
          );
        }

        final List<ReviewedDocument> docs = snapshot.data ?? const <ReviewedDocument>[];
        if (docs.isEmpty) {
          // Nothing was uploaded, and that is a fact worth a sentence: older applications
          // predate the document step entirely.
          return const Text(
            'No documents uploaded. Applications taken before the document step existed '
            'carry none.',
            style: ConsoleText.meta,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < docs.length; i++) _row(docs[i], last: i == docs.length - 1),
          ],
        );
      },
    );
  }

  Widget _row(ReviewedDocument doc, {required bool last}) {
    final bool busy = _busyId == doc.id;
    final bool decidable =
        !widget.readOnly && !doc.superseded && doc.status == ApplicantDocumentStatus.pending;

    final (String badge, DeliveryAccent accent) = doc.superseded
        ? ('Replaced', DeliveryAccent.neutral)
        : switch (doc.status) {
            ApplicantDocumentStatus.pending => ('Waiting', DeliveryAccent.caution),
            ApplicantDocumentStatus.approved => ('Approved', DeliveryAccent.positive),
            ApplicantDocumentStatus.rejected => ('Refused', DeliveryAccent.critical),
          };

    return Container(
      padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.sm),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(_labelOf(doc),
                    overflow: TextOverflow.ellipsis, style: ConsoleText.cell),
                if (doc.status == ApplicantDocumentStatus.rejected &&
                    (doc.rejectionReason ?? '').isNotEmpty)
                  Text(doc.rejectionReason!,
                      overflow: TextOverflow.ellipsis, style: ConsoleText.meta),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          ConsoleSmallBadge(label: badge, accent: accent),
          const SizedBox(width: DeliverySpacing.sm),
          // The paper itself, in a new tab. Absent when storage could not sign a URL — a dead
          // button would promise a file this drawer cannot show.
          if (doc.viewUrl != null) ...<Widget>[
            ConsoleRowAction(
              icon: Icons.open_in_new,
              tooltip: 'Open the document',
              onPressed: () => openExternalLink(doc.viewUrl!),
            ),
            const SizedBox(width: DeliverySpacing.xs),
          ],
          if (decidable) ...<Widget>[
            ConsoleRowAction(
              icon: Icons.check,
              tooltip: 'Approve this document',
              onPressed: busy ? null : () => _approve(doc),
            ),
            const SizedBox(width: DeliverySpacing.xs),
            ConsoleRowAction(
              icon: Icons.close,
              tooltip: 'Refuse this document',
              destructive: true,
              onPressed: busy ? null : () => _reject(doc),
            ),
          ],
        ],
      ),
    );
  }
}

/// Refusing one document, with the reason typed out — the applicant is shown it verbatim, and it
/// is the only way they learn what to upload instead.
class _DocumentReasonDialog extends StatefulWidget {
  const _DocumentReasonDialog({required this.documentLabel});

  final String documentLabel;

  @override
  State<_DocumentReasonDialog> createState() => _DocumentReasonDialogState();
}

class _DocumentReasonDialogState extends State<_DocumentReasonDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: DeliveryColors.white,
      surfaceTintColor: DeliveryColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
      title: Text('Refuse ${widget.documentLabel}', style: ConsoleText.cardTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'The applicant is shown this word for word. Say what is wrong with the document '
              'and what to upload instead.',
              style: ConsoleText.pageSubtitle,
            ),
            const SizedBox(height: DeliverySpacing.md),
            TextField(
              controller: _reason,
              maxLines: 3,
              maxLength: 500,
              autofocus: true,
              style: ConsoleText.cell,
              cursorColor: DeliveryColors.brand,
              decoration: InputDecoration(
                hintText: 'The photo is too blurred to read the expiry date',
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
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        ConsoleButton(
          label: 'Cancel',
          tone: ConsoleButtonTone.outlined,
          onPressed: () => Navigator.pop(context),
        ),
        ConsoleButton(
          label: 'Refuse document',
          tone: ConsoleButtonTone.solid,
          onPressed: _reason.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _reason.text.trim()),
        ),
      ],
    );
  }
}

/// The console's inline note: a tinted panel with a glyph, for the one thing a reviewer must read.
class _Note extends StatelessWidget {
  const _Note({required this.text, required this.accent, required this.icon});

  final String text;
  final DeliveryAccent accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.md - 2),
      decoration: BoxDecoration(
        color: accent.tint,
        border: Border.all(color: accent.line),
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: accent.color),
          const SizedBox(width: DeliverySpacing.sm + 2),
          Expanded(
            child: Text(text, style: ConsoleText.body.copyWith(height: 1.4)),
          ),
        ],
      ),
    );
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
      backgroundColor: DeliveryColors.white,
      surfaceTintColor: DeliveryColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
      title: Text('Decline ${widget.businessName}', style: ConsoleText.cardTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'They are sent this word for word. Say what would have to change.',
              style: ConsoleText.pageSubtitle,
            ),
            const SizedBox(height: DeliverySpacing.md),
            TextField(
              controller: _reason,
              maxLines: 3,
              maxLength: 500,
              autofocus: true,
              style: ConsoleText.cell,
              cursorColor: DeliveryColors.brand,
              decoration: InputDecoration(
                hintText: 'The address given is outside the area we cover',
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
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        ConsoleButton(
          label: 'Cancel',
          tone: ConsoleButtonTone.outlined,
          onPressed: () => Navigator.pop(context),
        ),
        ConsoleButton(
          label: 'Decline',
          tone: ConsoleButtonTone.solid,
          // Disabled rather than validated on submit: the server refuses an empty reason, and
          // finding that out after pressing the button teaches nothing the button could have said.
          onPressed: _reason.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _reason.text.trim()),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------- the record's history

/// The two management reads for one application, bundled so the list widget stays ignorant of ids —
/// the same shape as [_ReviewerDocuments], for the same reason.
class _PartnerHistory {
  const _PartnerHistory({required this.audit, required this.suspension});

  final Future<List<PartnerAuditEntry>> Function() audit;
  final Future<PartnerSuspensionRecord> Function() suspension;
}

/// One line of the record's history, whichever of the two sources it came from.
class _HistoryEntry {
  const _HistoryEntry({
    required this.at,
    required this.text,
    required this.actor,
    required this.icon,
    required this.accent,
  });

  final DateTime? at;
  final String text;
  final String actor;
  final IconData icon;
  final DeliveryAccent accent;
}

/// Corrections and standing changes, merged and newest first.
///
/// Two requests, both allowed to fail on their own: an audit trail that loaded and a standing that
/// did not is still worth showing, and saying which half is missing is better than showing neither.
class _HistoryList extends StatefulWidget {
  const _HistoryList({required this.history});

  final _PartnerHistory history;

  @override
  State<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<_HistoryList> {
  late Future<List<_HistoryEntry>> _entries = _load();

  /// Which halves came back. A failure is named rather than rendered as an empty history — "never
  /// edited" and "could not read the edits" are different facts about a partner.
  bool _auditFailed = false;
  bool _standingFailed = false;

  Future<List<_HistoryEntry>> _load() async {
    _auditFailed = false;
    _standingFailed = false;

    final Future<List<PartnerAuditEntry>?> audit = widget.history
        .audit()
        .then<List<PartnerAuditEntry>?>((List<PartnerAuditEntry> a) => a)
        .catchError((Object _) => null);
    final Future<PartnerSuspensionRecord?> standing = widget.history
        .suspension()
        .then<PartnerSuspensionRecord?>((PartnerSuspensionRecord r) => r)
        .catchError((Object _) => null);

    final List<PartnerAuditEntry>? edits = await audit;
    final PartnerSuspensionRecord? record = await standing;
    _auditFailed = edits == null;
    _standingFailed = record == null;

    final List<_HistoryEntry> entries = <_HistoryEntry>[
      for (final PartnerAuditEntry e in edits ?? const <PartnerAuditEntry>[])
        _HistoryEntry(
          at: e.at,
          text: _correction(e),
          actor: e.actor,
          icon: Icons.edit_outlined,
          accent: DeliveryAccent.info,
        ),
      for (final StandingChange c in record?.history ?? const <StandingChange>[])
        _HistoryEntry(
          at: c.at,
          text: _standingLine(c),
          actor: c.actor,
          icon: c.suspended ? Icons.block : Icons.lock_open,
          accent: c.suspended ? DeliveryAccent.critical : DeliveryAccent.positive,
        ),
    ];

    // Newest first. An entry the server sent with no timestamp sorts last rather than being
    // dropped or given a time it does not have.
    entries.sort((_HistoryEntry a, _HistoryEntry b) {
      if (a.at == null && b.at == null) return 0;
      if (a.at == null) return 1;
      if (b.at == null) return -1;
      return b.at!.compareTo(a.at!);
    });
    return entries;
  }

  static String _correction(PartnerAuditEntry e) {
    final String field = _ApplicationDetail._humanise(e.field);
    final String? from = e.oldValue;
    final String? to = e.newValue;
    if (from == null || from.isEmpty) return '$field set to "${to ?? ''}"';
    if (to == null || to.isEmpty) return '$field cleared';
    return '$field changed from "$from" to "$to"';
  }

  static String _standingLine(StandingChange c) {
    if (!c.suspended) {
      return c.reasonNote == null || c.reasonNote!.isEmpty
          ? 'Reinstated'
          : 'Reinstated — ${c.reasonNote}';
    }
    // A reason this build does not know keeps the server's own spelling rather than being guessed
    // at or dropped.
    final String reason = c.reason?.label ?? c.reasonWire ?? 'no reason recorded';
    return c.reasonNote == null || c.reasonNote!.isEmpty
        ? 'Suspended — $reason'
        : 'Suspended — $reason · ${c.reasonNote}';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_HistoryEntry>>(
      future: _entries,
      builder: (BuildContext context, AsyncSnapshot<List<_HistoryEntry>> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: DeliverySpacing.md),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.brand),
              ),
            ),
          );
        }

        final List<_HistoryEntry> entries = snapshot.data ?? const <_HistoryEntry>[];
        final List<String> missing = <String>[
          if (_auditFailed) 'the corrections',
          if (_standingFailed) 'the standing changes',
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (entries.isEmpty && missing.isEmpty)
              const Text(
                'Nothing has been changed on this record.',
                style: ConsoleText.meta,
              )
            else
              for (int i = 0; i < entries.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: DeliverySpacing.sm + 2),
                _HistoryRow(entry: entries[i]),
              ],
            if (missing.isNotEmpty) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Could not read ${missing.join(' or ')}. This list is incomplete.',
                      style: ConsoleText.meta,
                    ),
                  ),
                  ConsoleButton(
                    label: 'Try again',
                    tone: ConsoleButtonTone.outlined,
                    onPressed: () => setState(() => _entries = _load()),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final _HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(entry.icon, size: 14, color: entry.accent.color),
        ),
        const SizedBox(width: DeliverySpacing.sm + 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(entry.text, style: ConsoleText.body),
              const SizedBox(height: 2),
              Text(
                '${_ApplicationDetail._short(entry.actor)} · '
                '${_OnboardingScreenState._when(entry.at)}',
                style: ConsoleText.meta,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------- correcting the record

/// The fields an operator actually changed. Anything left alone is null and is not sent, because a
/// PATCH that changes nothing writes no audit row — and a field sent unchanged would write one.
class _PartnerEdit {
  const _PartnerEdit({
    this.businessName,
    this.contactName,
    this.contactEmail,
    this.contactPhone,
  });

  final String? businessName;
  final String? contactName;
  final String? contactEmail;
  final String? contactPhone;

  bool get isEmpty =>
      businessName == null &&
      contactName == null &&
      contactEmail == null &&
      contactPhone == null;
}

/// The four audited fields, and only those.
///
/// Everything else on an application — the wizard's answers, the documents, the decision — is not
/// correctable by this endpoint and is not offered here.
class _EditPartnerDialog extends StatefulWidget {
  const _EditPartnerDialog({required this.application});

  final OnboardingApplication application;

  @override
  State<_EditPartnerDialog> createState() => _EditPartnerDialogState();
}

class _EditPartnerDialogState extends State<_EditPartnerDialog> {
  late final TextEditingController _business =
      TextEditingController(text: widget.application.businessName);
  late final TextEditingController _contact =
      TextEditingController(text: widget.application.contactName);
  late final TextEditingController _email =
      TextEditingController(text: widget.application.contactEmail);
  late final TextEditingController _phone =
      TextEditingController(text: widget.application.contactPhone ?? '');

  @override
  void dispose() {
    _business.dispose();
    _contact.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  /// What to send for one field: the trimmed value when it actually differs, and null otherwise.
  ///
  /// A field emptied on screen returns null rather than an empty string — the server refuses a
  /// whitespace-only value with a 422, and there is deliberately no way to blank a field, so
  /// clearing one leaves it as it was. The dialog says so under the form.
  static String? _changed(String? original, TextEditingController field) {
    final String value = field.text.trim();
    if (value.isEmpty) return null;
    if (value == (original ?? '').trim()) return null;
    return value;
  }

  _PartnerEdit get _edit => _PartnerEdit(
        businessName: _changed(widget.application.businessName, _business),
        contactName: _changed(widget.application.contactName, _contact),
        contactEmail: _changed(widget.application.contactEmail, _email),
        contactPhone: _changed(widget.application.contactPhone, _phone),
      );

  /// A light shape check only. The server is the authority on what an address is; this exists so an
  /// obvious typo is caught before a round trip, not to reimplement validation here.
  bool get _emailLooksWrong {
    final String? email = _edit.contactEmail;
    return email != null && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  @override
  Widget build(BuildContext context) {
    final _PartnerEdit edit = _edit;
    final bool phoneChanging = edit.contactPhone != null;

    return AlertDialog(
      backgroundColor: DeliveryColors.white,
      surfaceTintColor: DeliveryColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
      title: Text('Edit ${widget.application.businessName}', style: ConsoleText.cardTitle),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _field('Business name', _business),
              _field('Contact name', _contact),
              _field('Contact email', _email, keyboard: TextInputType.emailAddress),
              _field('Contact phone', _phone, keyboard: TextInputType.phone),
              const SizedBox(height: DeliverySpacing.sm),
              const Text(
                'A field cannot be emptied — clearing one leaves it as it was. Changing the email '
                'does not change how they sign in, and keeps the address already verified.',
                style: ConsoleText.meta,
              ),
              if (phoneChanging) ...<Widget>[
                const SizedBox(height: DeliverySpacing.sm),
                _Note(
                  text: 'Changing the phone number marks it unverified: nobody has confirmed the '
                      'new one reaches them.',
                  accent: DeliveryAccent.caution,
                  icon: Icons.warning_amber_rounded,
                ),
              ],
              if (_emailLooksWrong) ...<Widget>[
                const SizedBox(height: DeliverySpacing.sm),
                Text(
                  'That does not look like an email address.',
                  style: ConsoleText.meta.copyWith(color: DeliveryAccent.critical.color),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        ConsoleButton(
          label: 'Cancel',
          tone: ConsoleButtonTone.outlined,
          onPressed: () => Navigator.pop(context),
        ),
        ConsoleButton(
          label: 'Save changes',
          tone: ConsoleButtonTone.solid,
          // Dead until something actually differs: a PATCH that changes nothing is a request that
          // teaches nobody anything, and the server writes no audit row for it either.
          onPressed: edit.isEmpty || _emailLooksWrong
              ? null
              : () => Navigator.pop(context, edit),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController controller,
      {TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.md - DeliverySpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: ConsoleText.fieldLabel),
          const SizedBox(height: DeliverySpacing.xs + 2),
          TextField(
            controller: controller,
            keyboardType: keyboard,
            style: ConsoleText.cell,
            cursorColor: DeliveryColors.brand,
            decoration: _inputDecoration(),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- withdrawing the standing

/// A suspension as the operator composed it: the server's enum, and the sentence beside it.
class _Suspension {
  const _Suspension({required this.reason, required this.note});

  final SuspensionReason reason;
  final String note;
}

/// Suspending a live partner.
///
/// Two things it insists on, for the same reason the decline dialog insists on a sentence: a
/// reason the platform can act on later, and a note a human can read. And one thing it states
/// plainly before the button — what suspension actually does — because "suspended" means something
/// specific here and guessing at it is how a partner gets switched off by mistake.
class _SuspendDialog extends StatefulWidget {
  const _SuspendDialog({required this.application});

  final OnboardingApplication application;

  @override
  State<_SuspendDialog> createState() => _SuspendDialogState();
}

class _SuspendDialogState extends State<_SuspendDialog> {
  final TextEditingController _note = TextEditingController();
  SuspensionReason? _reason;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String role = _OnboardingScreenState._roleOf(widget.application.kind);

    return AlertDialog(
      backgroundColor: DeliveryColors.white,
      surfaceTintColor: DeliveryColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
      title: Text('Suspend ${widget.application.businessName}', style: ConsoleText.cardTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Note(
                text: 'This revokes their $role role. They can still sign in and read their own '
                    'history, but every action that commits something — taking an order, claiming '
                    'a job, changing a menu — is refused across the platform until they are '
                    'reinstated.',
                accent: DeliveryAccent.critical,
                icon: Icons.block,
              ),
              const SizedBox(height: DeliverySpacing.md),
              const Text('Reason', style: ConsoleText.fieldLabel),
              const SizedBox(height: DeliverySpacing.xs + 2),
              ConsoleSelect(
                label: _reason?.label ?? 'Choose a reason',
                icon: Icons.flag_outlined,
                options: <ConsoleOption>[
                  for (final SuspensionReason r in SuspensionReason.values)
                    ConsoleOption(label: r.label, value: r.wire),
                ],
                onSelected: (String? wire) =>
                    setState(() => _reason = SuspensionReason.fromWire(wire)),
              ),
              const SizedBox(height: DeliverySpacing.md),
              const Text('What happened', style: ConsoleText.fieldLabel),
              const SizedBox(height: DeliverySpacing.xs + 2),
              TextField(
                controller: _note,
                maxLines: 3,
                maxLength: 500,
                style: ConsoleText.cell,
                cursorColor: DeliveryColors.brand,
                decoration: _inputDecoration(
                  hint: 'Three chargebacks in a week, all disputed by the cardholder',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const Text(
                'Kept on the record and shown to whoever asks later why this partner was switched '
                'off.',
                style: ConsoleText.meta,
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        ConsoleButton(
          label: 'Cancel',
          tone: ConsoleButtonTone.outlined,
          onPressed: () => Navigator.pop(context),
        ),
        ConsoleButton(
          label: 'Suspend partner',
          tone: ConsoleButtonTone.destructive,
          onPressed: _reason == null || _note.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    _Suspension(reason: _reason!, note: _note.text.trim()),
                  ),
        ),
      ],
    );
  }
}

/// Giving the standing back. The note is optional here — the server asks for no reason to
/// reinstate, and requiring one would be this screen inventing a rule the platform does not have.
class _UnsuspendDialog extends StatefulWidget {
  const _UnsuspendDialog({required this.application});

  final OnboardingApplication application;

  @override
  State<_UnsuspendDialog> createState() => _UnsuspendDialogState();
}

class _UnsuspendDialogState extends State<_UnsuspendDialog> {
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String role = _OnboardingScreenState._roleOf(widget.application.kind);

    return AlertDialog(
      backgroundColor: DeliveryColors.white,
      surfaceTintColor: DeliveryColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
      title: Text('Reinstate ${widget.application.businessName}', style: ConsoleText.cardTitle),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'This gives their $role role back. They can take work again as soon as they sign in '
              'next.',
              style: ConsoleText.pageSubtitle,
            ),
            const SizedBox(height: DeliverySpacing.md),
            const Text('Note (optional)', style: ConsoleText.fieldLabel),
            const SizedBox(height: DeliverySpacing.xs + 2),
            TextField(
              controller: _note,
              maxLines: 2,
              maxLength: 500,
              style: ConsoleText.cell,
              cursorColor: DeliveryColors.brand,
              decoration: _inputDecoration(hint: 'Chargebacks resolved with the bank'),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        ConsoleButton(
          label: 'Cancel',
          tone: ConsoleButtonTone.outlined,
          onPressed: () => Navigator.pop(context),
        ),
        ConsoleButton(
          label: 'Reinstate',
          tone: ConsoleButtonTone.solid,
          onPressed: () => Navigator.pop(context, _note.text.trim()),
        ),
      ],
    );
  }
}

/// The console's field box, shared by the three management dialogs so they cannot drift apart.
InputDecoration _inputDecoration({String? hint}) => InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 14, color: DeliveryColors.faint),
      filled: true,
      fillColor: DeliveryColors.background,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: DeliverySpacing.md - 2,
        vertical: DeliverySpacing.sm + 2,
      ),
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

extension on String {
  bool get isBlank => trim().isEmpty;
}
