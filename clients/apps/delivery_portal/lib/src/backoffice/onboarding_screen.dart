import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../shell/console_controls.dart';
import '../shell/shell.dart';

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
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.api, required this.documentsApi});

  final OnboardingApi api;
  final DocumentsApi documentsApi;

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

  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// The Category filter's chosen value, or null for all of them.
  String? _category;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(_pollInterval, (_) => _refresh(silent: true));
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _error = e;
        _loading = false;
      });
    }
  }

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
          // Drawn on every console frame and answered by nothing: there is no cross-entity search
          // endpoint. Rendered rather than removed, greyed rather than pretending.
          const ConsoleSearchField.global(
            hintText: 'Search backoffice...',
            enabled: false,
          ),
          const ConsoleIconAction(
            icon: Icons.notifications_none,
            tooltip: 'Notifications — no feed yet',
          ),
          const ConsoleComingSoonChip(),
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
        _table(),
      ],
    );
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
        text: 'Product and order counts per partner are not aggregated by any endpoint yet, and '
            'a partner cannot be edited or suspended from here.',
      ),
    );
  }

  ConsoleTableRow _row(OnboardingApplication a) {
    final bool busy = _busyId == a.id;
    final bool pending = !a.status.isDecided;

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
              // Drawn by the design against every partner; there is no endpoint behind either for a
              // partner who is already live.
              const ConsoleRowAction(
                icon: Icons.edit_outlined,
                tooltip: 'Edit partner — coming soon',
              ),
              const SizedBox(width: DeliverySpacing.sm),
              const ConsoleRowAction(
                icon: Icons.block,
                tooltip: 'Suspend partner — coming soon',
                destructive: true,
              ),
            ],
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------------- the drawer

  Future<void> _open(OnboardingApplication a) async {
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
    required this.onApprove,
    required this.onDecline,
  });

  final OnboardingApplication application;
  final _ReviewerDocuments documents;
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

extension on String {
  bool get isBlank => trim().isEmpty;
}
