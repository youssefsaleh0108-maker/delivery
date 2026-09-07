/// A counting session: what the system believes is on the shelf, beside what somebody just counted.
///
/// Figma `merchant-stock-count` (94:425 phone / 94:3856 web). One screen with two faces, because a
/// count is a state a shop is either in or not:
///
///  * **No open count** — a card to name and scope a new one, and the sessions that came before it.
///  * **An open count** — the lines, a running "N of M counted", the difference on each row, and
///    the two ways out: submit it, or cancel it.
///
/// The backend allows exactly one open count per store (409 on a second `startCount`), so the
/// screen never asks which count to resume — it looks for the open one and adopts it. That also
/// means a merchant who backgrounds the app mid-count comes back to the same session with every
/// line they had already entered still on it.
///
/// Two rules the service imposes and this screen obeys:
///  * `variance` and `systemQty` are the SERVER's. Nothing here computes `counted - system`; the
///    shelf may have moved since the count opened and the server re-snapshots on every write.
///  * an uncounted line is null, never zero. Clearing a box sends null, which is "nobody has
///    looked" — submitting SKIPS those, where a zero would empty the shelf.
///
/// Writes are debounced 400ms and batched: a scanner run typing forty boxes in a row goes out as
/// one `recordLines` call rather than forty, which is what keeps it under the shared Traefik
/// `platform-rate-limit` (average 20 / burst 40) with the tail of the count intact.
///
/// inventory-service is not deployed yet, so [InventoryApi] is nullable here and every failure
/// lands on a calm state rather than an exception — a merchant opening this before the service
/// ships should see "not loaded", not a red screen.
library;

import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'order_detail_screen.dart';

/// The stock-count session screen. Pushed from the inventory tab and from the dashboard's quick
/// actions; mounted by the phone shell and by the portal, so it lays out from its own constraints
/// rather than from the window.
class StockCountScreen extends StatefulWidget {
  const StockCountScreen({
    super.key,
    required this.api,
    required this.storeId,
    this.catalogApi,
  });

  /// Nullable because inventory-service is not deployed yet. Null draws the unavailable state
  /// instead of a list — a host can mount the screen before the service exists.
  final InventoryApi? api;

  /// Whose shelves are being counted. Sent on `startCount`; every other call is addressed by count
  /// id, which is already scoped server-side.
  final String storeId;

  /// Only used to offer "count one section" when starting. Optional: without it the scope picker
  /// is not drawn and a count covers everything, which is the common case anyway.
  final CatalogApi? catalogApi;

  @override
  State<StockCountScreen> createState() => _StockCountScreenState();
}

class _StockCountScreenState extends State<StockCountScreen> {
  /// Below this the row stacks: the product on its own line, the three numbers under it.
  ///
  /// Measured off this widget's constraints, not the window — the portal hands the screen the space
  /// beside its rail, so a half-width browser is as narrow as a phone here.
  static const double _narrowWidth = 720;

  /// How long a box waits after the last keystroke before it is sent.
  ///
  /// 400ms is long enough that typing "12" is one write rather than two, and short enough that a
  /// counter moving down a shelf never wonders whether their number stuck.
  static const Duration _debounceDelay = Duration(milliseconds: 400);

  static const int _historySize = 20;

  /// The counted box. Wide enough for four digits at 200% text scale.
  static const double _fieldWidth = 96;

  /// The width one number column gets on a wide row.
  static const double _statWidth = 104;

  bool _loading = true;
  Object? _error;

  /// The open session, or null when there is none. Only ever holds an OPEN count — a submitted one
  /// belongs in [_history].
  StockCount? _count;

  List<StockCountSummary> _history = const <StockCountSummary>[];
  List<Category> _categories = const <Category>[];

  final TextEditingController _name = TextEditingController();
  final TextEditingController _search = TextEditingController();
  String _query = '';
  bool _differencesOnly = false;
  String? _scopeCategoryId;

  bool _starting = false;
  bool _submitting = false;

  /// A write is in flight — drawn in the header so a counter can see their numbers landing.
  bool _saving = false;

  /// One controller per line, created once and never rewritten from the server.
  ///
  /// Rewriting it would move the caret out from under somebody mid-count, and the box is the one
  /// piece of state the merchant owns rather than the server.
  final Map<String, TextEditingController> _fields = <String, TextEditingController>{};

  /// Edits typed but not yet sent. Null value means "clear this line back to uncounted".
  final Map<String, int?> _pending = <String, int?>{};

  Timer? _debounce;
  bool _flushing = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadCategories();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _search.dispose();
    for (final TextEditingController controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------------ loading

  /// Finds the open count, if there is one, and the sessions behind it.
  ///
  /// Block body rather than an arrow, and every `setState` guarded by `mounted`: this is awaited
  /// from a snackbar path and from a pull gesture as well as from `initState`.
  Future<void> _load({bool silent = false}) async {
    final InventoryApi? api = widget.api;
    if (api == null) {
      // Nothing to ask. The unavailable state is not an error — the service simply is not there.
      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }
      return;
    }
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final Paged<StockCountSummary> open =
          await api.counts(status: StockCountStatus.open, size: 1);
      StockCount? active;
      if (open.content.isNotEmpty) {
        active = await api.count(open.content.first.id);
      }
      final Paged<StockCountSummary> recent = await api.counts(size: _historySize);
      if (!mounted) return;
      setState(() {
        _adopt(active);
        _history = recent.content
            .where((StockCountSummary s) => s.id != active?.id)
            .toList(growable: false);
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // A failed silent reload must not wipe a session somebody is standing in front of a shelf
        // counting into.
        if (!silent) _error = e;
        _loading = false;
      });
    }
  }

  /// Best effort, and deliberately not awaited by [_load]: the scope picker is a convenience, and a
  /// catalogue that will not load must not stop a merchant counting everything.
  Future<void> _loadCategories() async {
    final CatalogApi? api = widget.catalogApi;
    if (api == null) return;
    try {
      final List<Category> categories = await api.categories();
      if (!mounted) return;
      setState(() => _categories = categories);
    } catch (_) {
      // Swallowed on purpose. No picker is a better outcome than an error over a start button.
    }
  }

  /// Takes on a count as the session, throwing away the boxes belonging to the previous one.
  ///
  /// Must be called inside a `setState`.
  void _adopt(StockCount? next) {
    if (next?.id != _count?.id) {
      for (final TextEditingController controller in _fields.values) {
        controller.dispose();
      }
      _fields.clear();
      _pending.clear();
      _debounce?.cancel();
      _query = '';
      _search.clear();
      _differencesOnly = false;
    }
    _count = (next != null && next.isOpen) ? next : null;
  }

  TextEditingController _fieldFor(StockCountLine line) => _fields.putIfAbsent(
        line.productId,
        () => TextEditingController(text: line.countedQty?.toString() ?? ''),
      );

  // ------------------------------------------------------------------ writing

  /// A box changed. Records the intent and restarts the debounce; nothing goes out yet.
  void _onCounted(StockCountLine line, String raw) {
    final String text = raw.trim();
    if (text.isEmpty) {
      // Empty is not zero. Null clears the line back to uncounted, and submit will skip it.
      _pending[line.productId] = null;
    } else {
      final int? value = int.tryParse(text);
      // The formatter already blocks everything else; a paste of something odd is simply ignored
      // rather than sent as a guess.
      if (value == null || value < 0) return;
      _pending[line.productId] = value;
    }
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () => unawaited(_flush()));
  }

  /// Sends everything pending now, and waits for it. Used before submitting and before leaving.
  Future<void> _flushNow() {
    _debounce?.cancel();
    return _flush();
  }

  /// Sends the pending edits, as one batch wherever there is more than one.
  ///
  /// Forty single-line writes from a scanner run trips the shared gateway limit and the tail of the
  /// count is silently lost, so anything over a single line goes through `recordLines`. Clears
  /// cannot ride in that batch — the batch endpoint takes ints — so they go one at a time, which is
  /// fine because clearing a line is a thing a person does, not a scanner.
  Future<void> _flush() async {
    final InventoryApi? api = widget.api;
    final StockCount? current = _count;
    if (api == null || current == null || _pending.isEmpty) return;
    if (_flushing) return; // the finally below picks up whatever arrived meanwhile

    final Map<String, int?> batch = Map<String, int?>.of(_pending);
    _pending.clear();
    _flushing = true;
    if (mounted) setState(() => _saving = true);

    try {
      final Map<String, int> counted = <String, int>{
        for (final MapEntry<String, int?> e in batch.entries)
          if (e.value != null) e.key: e.value!,
      };
      final List<String> cleared = <String>[
        for (final MapEntry<String, int?> e in batch.entries)
          if (e.value == null) e.key,
      ];

      if (counted.length > 1) {
        final StockCount updated = await api.recordLines(current.id, counted);
        if (!mounted) return;
        setState(() => _adoptSameCount(updated));
      } else if (counted.length == 1) {
        final StockCountLine line =
            await api.recordLine(current.id, counted.keys.first, counted.values.first);
        if (!mounted) return;
        setState(() => _merge(line));
      }

      for (final String productId in cleared) {
        final StockCountLine line = await api.recordLine(current.id, productId, null);
        if (!mounted) return;
        setState(() => _merge(line));
      }
    } catch (e) {
      if (!mounted) return;
      final DeliveryStrings t = DeliveryStrings.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageFor(e, fallback: t.somethingWentWrong))),
      );
    } finally {
      _flushing = false;
      if (mounted) setState(() => _saving = false);
      if (_pending.isNotEmpty) unawaited(_flush());
    }
  }

  /// Replaces the session with the server's version of the same count, keeping the boxes.
  ///
  /// Must be called inside a `setState`. Not [_adopt], which would throw the controllers away and
  /// take the caret with them.
  void _adoptSameCount(StockCount updated) {
    if (updated.id != _count?.id) return;
    _count = updated.isOpen ? updated : _count;
  }

  /// Folds one server-recorded line back into the session.
  ///
  /// `itemsCounted` is recounted from the lines rather than taken from the last full response,
  /// which would be one line stale — the same arithmetic the server does, over the same rows.
  void _merge(StockCountLine updated) {
    final StockCount? current = _count;
    if (current == null) return;
    final List<StockCountLine> lines = <StockCountLine>[
      for (final StockCountLine line in current.lines)
        if (line.productId == updated.productId) updated else line,
    ];
    _count = StockCount(
      id: current.id,
      name: current.name,
      status: current.status,
      categoryId: current.categoryId,
      startedAt: current.startedAt,
      submittedAt: current.submittedAt,
      itemsTotal: current.itemsTotal == 0 ? lines.length : current.itemsTotal,
      itemsCounted: lines.where((StockCountLine l) => l.isCounted).length,
      lines: lines,
    );
  }

  // ------------------------------------------------------------------ actions

  Future<void> _start() async {
    final InventoryApi? api = widget.api;
    final String name = _name.text.trim();
    if (api == null || name.isEmpty || _starting) return;
    final DeliveryStrings t = DeliveryStrings.of(context);

    setState(() => _starting = true);
    try {
      final StockCount started = await api.startCount(
        name: name,
        categoryId: _scopeCategoryId,
        storeId: widget.storeId,
      );
      if (!mounted) return;
      setState(() {
        _adopt(started);
        _name.clear();
        _scopeCategoryId = null;
      });
    } catch (e) {
      if (!mounted) return;
      // 409 is the one refusal with a better sentence than the server's: somebody else in the shop
      // already has a count open, and the fix is to finish that one.
      final bool conflict = e is DioException && e.response?.statusCode == 409;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          conflict ? t.invCountOpenExists : _messageFor(e, fallback: t.somethingWentWrong),
        ),
      ));
      if (conflict) await _load(silent: true);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _submit() async {
    final InventoryApi? api = widget.api;
    if (api == null || _submitting) return;

    // Everything typed goes out before the review, or the dialog would list yesterday's variances.
    await _flushNow();
    if (!mounted) return;
    final StockCount? current = _count;
    if (current == null) return;

    final bool confirmed = await _confirmSubmit(current) ?? false;
    if (!confirmed || !mounted) return;

    final DeliveryStrings t = DeliveryStrings.of(context);
    setState(() => _submitting = true);
    try {
      await api.submitCount(current.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.invCountSubmitted)));
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageFor(e, fallback: t.somethingWentWrong))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _cancelCount() async {
    final InventoryApi? api = widget.api;
    final StockCount? current = _count;
    if (api == null || current == null || _submitting) return;
    final DeliveryStrings t = DeliveryStrings.of(context);

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(t.invCountCancelCount),
        content: Text(current.name),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.invCountKeepCounting),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: DeliveryAccent.critical.color),
            child: Text(t.invCountCancelCount),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;

    setState(() => _submitting = true);
    try {
      await api.cancelCount(current.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.invCountCancelled)));
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageFor(e, fallback: t.somethingWentWrong))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// The review before the shelf is rewritten: every counted line that disagrees with the system.
  ///
  /// Submitting writes one movement per non-zero variance, which is the most destructive thing this
  /// screen does, so it is the one place the differences are read back before it happens.
  Future<bool?> _confirmSubmit(StockCount count) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<StockCountLine> differences = count.discrepancies;

    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(t.invCountSubmit),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  t.invCountProgress(count.itemsCounted, count.itemsTotal),
                  style: const TextStyle(fontSize: 13, color: DeliveryColors.muted),
                ),
                const SizedBox(height: DeliverySpacing.md),
                if (differences.isEmpty)
                  Row(
                    children: <Widget>[
                      Icon(Icons.check_circle_outline,
                          size: 18, color: DeliveryAccent.positive.color),
                      const SizedBox(width: DeliverySpacing.sm),
                      Expanded(
                        child: Text(
                          t.invCountNoDiscrepancies,
                          style: const TextStyle(fontSize: 14, color: DeliveryColors.ink),
                        ),
                      ),
                    ],
                  )
                else ...<Widget>[
                  Text(
                    '${t.invCountDiscrepancies} (${differences.length})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: DeliveryColors.ink,
                    ),
                  ),
                  const SizedBox(height: DeliverySpacing.sm),
                  for (final StockCountLine line in differences)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(bottom: DeliverySpacing.sm),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              line.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, color: DeliveryColors.muted),
                            ),
                          ),
                          const SizedBox(width: DeliverySpacing.sm),
                          Text(
                            _signed(line.variance ?? 0),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _varianceColor(line.variance ?? 0),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.invCountSubmit),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmLeave() {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(t.invCountLeaveWarning),
        content: Text(t.invCountLeaveWarningBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.invCountKeepCounting),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.invCountDiscard),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final StockCount? count = _count;
    final bool canBack = Navigator.of(context).canPop();

    return PopScope(
      // A half-finished count must not vanish on a back-swipe. Everything typed is already saved,
      // but the merchant has no way of knowing that unless they are told — so they are.
      canPop: count == null,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final NavigatorState navigator = Navigator.of(context);
        await _flushNow();
        if (!mounted) return;
        final bool leave = await _confirmLeave() ?? false;
        if (leave) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: DeliveryColors.background,
        // No AppBar: the host owns the framing, per this package's contract.
        body: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool narrow = constraints.maxWidth < _narrowWidth;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                MerchantScreenHeader(
                  title: t.invCountTitle,
                  subtitle: count?.name,
                  onBack: canBack ? () => Navigator.maybePop(context) : null,
                  backSemanticLabel: t.back,
                  trailing: _headerTrailing(t),
                ),
                Expanded(child: _body(t, narrow: narrow)),
                if (count != null) _actionBar(t),
              ],
            );
          },
        ),
      ),
    );
  }

  /// A spinner while a write is in flight, and otherwise the reload the portal has no gesture for.
  Widget _headerTrailing(DeliveryStrings t) {
    if (_saving) {
      return const Padding(
        padding: EdgeInsetsDirectional.all(DeliverySpacing.sm),
        child: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.brand),
        ),
      );
    }
    return IconButton(
      onPressed: _loading ? null : () => _load(),
      icon: const Icon(Icons.refresh, size: 20),
      color: DeliveryColors.muted,
      tooltip: t.refresh,
    );
  }

  Widget _body(DeliveryStrings t, {required bool narrow}) {
    if (widget.api == null) {
      // Calm, not alarming: the service is simply not there yet.
      return _capped(
        YdEmptyState(
          icon: Icons.inventory_2_outlined,
          title: t.invCountTitle,
          message: t.invCouldNotLoad,
        ),
      );
    }
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(DeliverySpacing.xl),
          child: CircularProgressIndicator(color: DeliveryColors.brand),
        ),
      );
    }
    if (_error != null) {
      return _capped(
        YdEmptyState(
          icon: Icons.cloud_off_rounded,
          title: t.invCouldNotLoad,
          message: _messageFor(_error!, fallback: t.somethingWentWrong),
          action: YdPillButton.secondary(
            label: t.tryAgain,
            onPressed: () => _load(),
            size: YdPillButtonSize.compact,
            expand: false,
          ),
        ),
      );
    }
    final StockCount? count = _count;
    if (count == null) {
      return _capped(_setup(t));
    }
    return _capped(_session(t, count, narrow: narrow));
  }

  /// Holds the phone design at its own measure and centres it, so the same widget reads the same
  /// way in 380dp of handset and in a 1400px portal pane.
  Widget _capped(Widget child) => Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: merchantMaxContentWidth),
          child: child,
        ),
      );

  // -------------------------------------------------------------------- setup

  /// No count is open: name one, scope it, start it — and read the ones that came before.
  Widget _setup(DeliveryStrings t) {
    final List<({Category category, int depth})> categories =
        _categories.isEmpty ? const <({Category category, int depth})>[] : Category.flatten(_categories);
    final bool canStart = _name.text.trim().isNotEmpty && !_starting;

    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      color: DeliveryColors.brand,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          DeliverySpacing.lg,
          DeliverySpacing.lg,
          DeliverySpacing.lg,
          DeliverySpacing.lg + MediaQuery.paddingOf(context).bottom,
        ),
        children: <Widget>[
          YdCard.bordered(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  t.invCountNew,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                  ),
                ),
                const SizedBox(height: DeliverySpacing.md),
                _labelled(
                  t.invCountName,
                  TextField(
                    controller: _name,
                    textInputAction: TextInputAction.done,
                    cursorColor: DeliveryColors.brand,
                    style: _valueStyle,
                    decoration: _boxDecoration(hintText: t.invCountNameHint),
                    // Rebuilds so the start button enables the moment there is a name.
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _start(),
                  ),
                ),
                if (categories.isNotEmpty) ...<Widget>[
                  const SizedBox(height: DeliverySpacing.md),
                  _labelled(
                    t.invCountScope,
                    DropdownButtonFormField<String>(
                      initialValue: _scopeCategoryId,
                      isExpanded: true,
                      style: _valueStyle,
                      icon: const Icon(Icons.expand_more, size: 16, color: DeliveryColors.ink),
                      decoration: _boxDecoration(),
                      items: <DropdownMenuItem<String>>[
                        DropdownMenuItem<String>(
                          value: null,
                          child: Text(t.invCountAllProducts),
                        ),
                        for (final ({Category category, int depth}) entry in categories)
                          DropdownMenuItem<String>(
                            value: entry.category.id,
                            child: Text(
                              '${'    ' * entry.depth}${entry.category.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (String? value) => setState(() => _scopeCategoryId = value),
                    ),
                  ),
                ],
                const SizedBox(height: DeliverySpacing.lg),
                YdPillButton(
                  label: t.invCountStart,
                  busy: _starting,
                  onPressed: canStart ? _start : null,
                  icon: Icons.play_arrow_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(height: DeliverySpacing.lg),
          if (_history.isEmpty)
            YdEmptyState(
              icon: Icons.fact_check_outlined,
              title: t.invCountEmpty,
              padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.lg),
            )
          else
            for (final StockCountSummary summary in _history)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: DeliverySpacing.sm + DeliverySpacing.xs),
                child: _HistoryRow(summary: summary),
              ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ session

  Widget _session(DeliveryStrings t, StockCount count, {required bool narrow}) {
    final List<StockCountLine> visible = _visibleLines(count);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _progressBand(t, count),
        Expanded(
          child: visible.isEmpty
              ? _noLines(t, count)
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    DeliverySpacing.lg,
                    DeliverySpacing.md,
                    DeliverySpacing.lg,
                    DeliverySpacing.lg,
                  ),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: DeliverySpacing.sm + DeliverySpacing.xs),
                  itemBuilder: (BuildContext context, int index) {
                    final StockCountLine line = visible[index];
                    return _CountLineRow(
                      line: line,
                      controller: _fieldFor(line),
                      narrow: narrow,
                      onChanged: (String value) => _onCounted(line, value),
                      onEditingComplete: () => unawaited(_flushNow()),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// The lines the filters leave standing. Client-side, because the whole count is already in hand
  /// — the server sends every line with the session, and refetching to hide rows would be slower
  /// and could disagree with the boxes somebody is typing into.
  List<StockCountLine> _visibleLines(StockCount count) {
    return count.lines.where((StockCountLine line) {
      if (_differencesOnly && !(line.isCounted && (line.variance ?? 0) != 0)) {
        return false;
      }
      if (_query.isEmpty) return true;
      return line.name.toLowerCase().contains(_query) ||
          (line.sku?.toLowerCase().contains(_query) ?? false);
    }).toList(growable: false);
  }

  Widget _noLines(DeliveryStrings t, StockCount count) {
    if (_differencesOnly) {
      return YdEmptyState(
        icon: Icons.verified_outlined,
        title: t.invCountNoDiscrepancies,
        action: YdPillButton.secondary(
          label: t.all,
          onPressed: () => setState(() => _differencesOnly = false),
          size: YdPillButtonSize.compact,
          expand: false,
        ),
      );
    }
    if (_query.isNotEmpty) {
      return YdEmptyState(
        icon: Icons.search_off,
        title: t.invEmpty,
        action: YdPillButton.secondary(
          label: t.clear,
          onPressed: () => setState(() {
            _search.clear();
            _query = '';
          }),
          size: YdPillButtonSize.compact,
          expand: false,
        ),
      );
    }
    // A count opened over a scope that holds nothing. Cancelling it is the only sensible way out,
    // and the action bar below already offers that.
    return YdEmptyState(
      icon: Icons.inventory_2_outlined,
      title: t.invEmpty,
      message: count.name,
    );
  }

  /// The white band that says how far along the count is, and narrows what is listed.
  Widget _progressBand(DeliveryStrings t, StockCount count) {
    final int differences = count.discrepancies.length;

    return Container(
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(
        DeliverySpacing.lg,
        DeliverySpacing.md - DeliverySpacing.xs,
        DeliverySpacing.lg,
        DeliverySpacing.md - DeliverySpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  t.invCountProgress(count.itemsCounted, count.itemsTotal),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              YdBadge.accent(
                label: count.status.labelIn(t),
                accent: DeliveryAccent.caution,
                uppercase: false,
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(DeliveryRadius.pill),
            child: LinearProgressIndicator(
              // Clamped: itemsTotal is the server's and a line list longer than it would otherwise
              // paint a bar past its own end.
              value: count.progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: DeliveryColors.borderFaint,
              valueColor: const AlwaysStoppedAnimation<Color>(DeliveryColors.brand),
            ),
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          YdSearchField(
            controller: _search,
            hintText: t.invSearch,
            onChanged: (String value) => setState(() => _query = value.trim().toLowerCase()),
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          // Wrap rather than a horizontal scroller: two translated labels carrying a count are
          // wider than the narrowest phone, and a chip hidden off the edge filters nothing.
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              YdChip(
                label: t.all,
                selected: !_differencesOnly,
                onTap: () => setState(() => _differencesOnly = false),
              ),
              YdChip(
                label: '${t.invCountDiscrepancies} ($differences)',
                selected: _differencesOnly,
                onTap: () => setState(() => _differencesOnly = true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The two ways out of a count, pinned under the list where a thumb can reach them.
  Widget _actionBar(DeliveryStrings t) {
    return Container(
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(top: BorderSide(color: DeliveryColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(
        DeliverySpacing.lg,
        DeliverySpacing.md - DeliverySpacing.xs,
        DeliverySpacing.lg,
        // `paddingOf`, not `viewPaddingOf`: a host that already wrapped this in a SafeArea has
        // spent the inset, and this must not spend it twice.
        DeliverySpacing.md - DeliverySpacing.xs + MediaQuery.paddingOf(context).bottom,
      ),
      child: Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: merchantMaxContentWidth),
          child: Row(
            children: <Widget>[
              Expanded(
                child: YdPillButton.secondary(
                  label: t.invCountCancelCount,
                  onPressed: _submitting ? null : _cancelCount,
                  size: YdPillButtonSize.compact,
                ),
              ),
              const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
              Expanded(
                child: YdPillButton(
                  label: t.invCountSubmit,
                  busy: _submitting,
                  onPressed: _submitting ? null : _submit,
                  size: YdPillButtonSize.compact,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _labelled(String label, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.muted,
            ),
          ),
          const SizedBox(height: DeliverySpacing.sm - 2),
          child,
        ],
      );
}

/// One product on the count: what the system believes, what was counted, and the gap.
///
/// The counted box is the only editable thing on the screen, so it is the widest target on the row
/// and keeps its own label at every width.
class _CountLineRow extends StatelessWidget {
  const _CountLineRow({
    required this.line,
    required this.controller,
    required this.narrow,
    required this.onChanged,
    required this.onEditingComplete,
  });

  final StockCountLine line;
  final TextEditingController controller;
  final bool narrow;
  final ValueChanged<String> onChanged;
  final VoidCallback onEditingComplete;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    final Widget name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          line.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
            height: 1.25,
          ),
        ),
        if (line.sku != null && line.sku!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            t.invSku(line.sku!),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: DeliveryColors.faint, height: 1.25),
          ),
        ],
      ],
    );

    final Widget system = _stat(
      label: t.invCountSystem,
      // An untracked product has no system figure, and a dash says so where a zero would lie.
      value: line.systemQty?.toString() ?? '—',
      color: DeliveryColors.ink,
    );

    final Widget variance = _stat(
      label: t.invCountVariance,
      value: line.isCounted ? _signed(line.variance ?? 0) : '—',
      color: line.isCounted
          ? _varianceColor(line.variance ?? 0)
          : DeliveryColors.faint,
    );

    final Widget field = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          t.invCountCounted,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: DeliveryColors.faint, height: 1.2),
        ),
        const SizedBox(height: DeliverySpacing.xs),
        SizedBox(
          width: _StockCountScreenState._fieldWidth,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            textAlign: TextAlign.center,
            textInputAction: TextInputAction.next,
            cursorColor: DeliveryColors.brand,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
            ),
            decoration: _boxDecoration(hintText: '—'),
            onChanged: onChanged,
            // Leaving the box sends it immediately rather than waiting out the debounce, which is
            // what a counter tabbing down a shelf expects.
            onEditingComplete: onEditingComplete,
          ),
        ),
      ],
    );

    return YdCard.bordered(
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                name,
                const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(child: system),
                    Expanded(child: variance),
                    field,
                  ],
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(child: name),
                const SizedBox(width: DeliverySpacing.md),
                SizedBox(width: _StockCountScreenState._statWidth, child: system),
                SizedBox(width: _StockCountScreenState._statWidth, child: variance),
                const SizedBox(width: DeliverySpacing.sm),
                field,
              ],
            ),
    );
  }

  Widget _stat({required String label, required String value, required Color color}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: DeliveryColors.faint, height: 1.2),
          ),
          const SizedBox(height: DeliverySpacing.xs),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
              height: 1.2,
            ),
          ),
        ],
      );
}

/// A finished count, as the list under the start card draws it.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.summary});

  final StockCountSummary summary;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final DateTime? at = summary.submittedAt ?? summary.startedAt;

    return YdCard.bordered(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  summary.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t.invCountProgress(summary.itemsCounted, summary.itemsTotal),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: DeliveryColors.faint, height: 1.25),
                ),
                if (at != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    merchantTimeAgo(at, t),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 11, color: DeliveryColors.faint, height: 1.25),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          YdBadge.accent(
            label: summary.status.labelIn(t),
            accent: switch (summary.status) {
              StockCountStatus.submitted => DeliveryAccent.positive,
              StockCountStatus.cancelled => DeliveryAccent.critical,
              StockCountStatus.open => DeliveryAccent.caution,
            },
            uppercase: false,
          ),
        ],
      ),
    );
  }
}

/// A difference with its sign kept: `+3` reads as three more on the shelf than the system thought,
/// `-3` as three missing. An unsigned 3 would be two different facts in one glyph.
String _signed(int variance) => variance > 0 ? '+$variance' : '$variance';

/// Missing stock is critical, surplus is only worth a look, and a match is quietly positive.
Color _varianceColor(int variance) {
  if (variance == 0) return DeliveryAccent.positive.color;
  return variance < 0 ? DeliveryAccent.critical.color : DeliveryAccent.caution.color;
}

const TextStyle _valueStyle = TextStyle(fontSize: 14, color: DeliveryColors.ink);

/// The bordered field the merchant forms use, copied rather than shared because the one in
/// `product_form_screen.dart` is private to that library.
InputDecoration _boxDecoration({String? hintText}) {
  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: DeliveryColors.white,
    counterText: '',
    hintText: hintText,
    contentPadding:
        const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
    border: border(DeliveryColors.border),
    enabledBorder: border(DeliveryColors.border),
    focusedBorder: border(DeliveryColors.brand, 1.5),
    errorBorder: border(DeliveryAccent.critical.color),
    focusedErrorBorder: border(DeliveryAccent.critical.color, 1.5),
    hintStyle: const TextStyle(fontSize: 14, color: DeliveryColors.faint),
    errorStyle: TextStyle(fontSize: 11, color: DeliveryAccent.critical.color),
  );
}

/// Pulls the human-readable half out of an RFC 9457 problem response.
///
/// The same extractor `product_list_screen.dart` carries; the spec promotes it into the package's
/// shared-vocabulary file, and this copy should collapse into that one when it lands.
String _messageFor(Object error, {required String fallback}) {
  if (error is DioException) {
    final Object? body = error.response?.data;
    if (body is Map<String, dynamic>) {
      final String? detail = body['detail'] as String?;
      final String? correlationId = body['correlationId'] as String?;
      if (detail != null) {
        return correlationId == null ? detail : '$detail (ref: $correlationId)';
      }
    }
  }
  return fallback;
}
