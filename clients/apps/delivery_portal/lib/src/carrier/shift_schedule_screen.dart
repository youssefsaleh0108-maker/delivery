import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../shell/console_controls.dart';
import '../shell/shell.dart';
import 'rider_attendance_screen.dart';

/// Shift schedules — the part of Riders HR the attendance frame (112:945) implies but does not
/// draw: somewhere to say which shift a rider works, so "late" and "absent" mean something.
///
/// Two blocks. The company's shifts, which can be added and retired but never re-timed (a shift
/// whose hours changed would silently re-judge every day already worked against it — the server
/// refuses, and the dialog says why before anybody tries). Retired shifts stay listed, folded away:
/// they are never offered again, but past days are still judged against them. Then the riders, each with the shift
/// they are on today and any change already set to start, and two actions: change the shift, or
/// open the rider's monthly attendance, which replaces this page in place so the rail stays.
///
/// The rider list is the tracking roster — exactly the riders the attendance endpoints will answer
/// for. A rider the company employs but that tracking has not yet linked to the fleet (they have
/// not carried an order for it) cannot be scheduled or read, and a sentence says how many, rather
/// than listing rows whose every action would come back "not found".
///
/// A rider with no shift is a freelancer: never late, never absent. That is the default, and
/// taking a rider off their schedule returns them to it.
class ShiftScheduleScreen extends StatefulWidget {
  const ShiftScheduleScreen({
    super.key,
    required this.api,
    required this.providerApi,
    this.onboardingApi,
  });

  /// Shifts, assignments, the roster, and each rider's attendance.
  final TrackingApi api;

  /// The company, and its rider list — to count riders tracking cannot see yet.
  final DeliveryProviderApi providerApi;

  /// The riders' own applications, for their names. Without it riders show by reference.
  final OnboardingApi? onboardingApi;

  @override
  State<ShiftScheduleScreen> createState() => _ShiftScheduleScreenState();
}

class _ShiftScheduleScreenState extends State<ShiftScheduleScreen> {
  late Future<_Schedule> _data = _load();
  bool _busy = false;

  /// The rider whose attendance is open in place of this page, or null.
  String? _openRider;

  /// Whether the retired shifts are unfolded.
  bool _retiredOpen = false;

  /// The page's read, marked handled the moment it is made: after an action it is made outside a
  /// frame, and a failure landing before the FutureBuilder subscribes would otherwise be reported as
  /// uncaught although the page shows it. [Future.ignore] does not stop the builder receiving it.
  Future<_Schedule> _load() => _fetch()..ignore();

  Future<_Schedule> _fetch() async {
    // These three are the page; if any fails, the page says so.
    final List<Object> core = await Future.wait(<Future<Object>>[
      widget.api.shifts(),
      widget.api.shiftAssignments(),
      widget.api.roster(onDutyOnly: false),
    ]);

    // Everything below only names and counts riders; a failure leaves references and no count.
    final DeliveryProviderInfo? company = await _tryLoad(widget.providerApi.myCompany);
    final List<String>? employed = await _tryLoad(widget.providerApi.myRiders);
    final OnboardingApi? onboarding = widget.onboardingApi;
    final List<OnboardingApplication>? applications = onboarding == null || company == null
        ? null
        : await _tryLoad(() => onboarding.forCompany(company.id, all: true));

    final List<String> roster = (core[2] as List<RiderPresence>)
        .map((RiderPresence p) => p.riderId)
        .toSet()
        .toList();
    final List<ShiftTemplate> shifts = core[0] as List<ShiftTemplate>;
    return _Schedule(
      shifts: shifts.where((ShiftTemplate s) => !s.archived).toList(),
      retired: shifts.where((ShiftTemplate s) => s.archived).toList(),
      assignments: core[1] as List<ShiftAssignment>,
      riders: roster,
      names: <String, String>{
        if (applications != null)
          for (final OnboardingApplication a in applications)
            if (a.kind == OnboardingKind.rider && a.provisionedUserRef != null)
              a.provisionedUserRef!: a.contactName,
      },
      unlinked: employed == null
          ? 0
          : employed.where((String r) => !roster.contains(r)).length,
    );
  }

  static Future<T?> _tryLoad<T>(Future<T> Function() load) async {
    try {
      return await load();
    } catch (_) {
      return null;
    }
  }

  // A block, not an arrow: `() => _data = _load()` would hand setState the Future the assignment
  // evaluates to, which Flutter refuses.
  void _reload() {
    setState(() {
      _data = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return FutureBuilder<_Schedule>(
      future: _data,
      builder: (BuildContext context, AsyncSnapshot<_Schedule> snapshot) {
        final _Schedule? data = snapshot.data;
        final String? open = _openRider;
        if (open != null && data != null) {
          return RiderAttendanceScreen(
            api: widget.api,
            riderId: open,
            riderName: data.nameOf(open),
            onBack: () => setState(() => _openRider = null),
          );
        }

        return ConsolePage(
          header: ConsoleTopbar(
            title: t.attendanceShiftsTitle,
            subtitle: t.attendanceShiftsSubtitle,
            titleStyle: ConsoleText.pageTitleSmall,
            actions: <Widget>[
              ConsolePrimaryButton(
                label: t.attendanceAddShift,
                icon: Icons.add,
                busy: _busy,
                onPressed: data == null ? null : _addShift,
              ),
            ],
          ),
          children: <Widget>[
            if (snapshot.connectionState != ConnectionState.done)
              const Padding(
                padding: EdgeInsets.all(DeliverySpacing.xl),
                child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
              )
            else if (snapshot.hasError)
              _failure(t, snapshot.error!)
            else ...<Widget>[
              _shiftsCard(t, data!),
              _ridersBlock(t, data),
            ],
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------------------------ shifts

  Widget _shiftsCard(DeliveryStrings t, _Schedule data) {
    return ConsoleCard(
      title: t.attendanceShiftsCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (data.shifts.isEmpty)
            Text(t.attendanceNoShifts, style: ConsoleText.pageSubtitle)
          else
            for (int i = 0; i < data.shifts.length; i++) ...<Widget>[
              if (i > 0) const Divider(height: DeliverySpacing.lg, color: DeliveryColors.border),
              _shiftRow(t, data.shifts[i]),
            ],
          if (data.retired.isNotEmpty) _retiredBlock(t, data.retired),
        ],
      ),
    );
  }

  /// Retired shifts, folded under their own heading. They are history rather than choices — never
  /// offered for a schedule again — but every past day worked on one is still judged against it,
  /// so the office can still find what "Old (06:00 - 12:00)" was.
  Widget _retiredBlock(DeliveryStrings t, List<ShiftTemplate> retired) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Divider(height: DeliverySpacing.lg, color: DeliveryColors.border),
        InkWell(
          onTap: () => setState(() => _retiredOpen = !_retiredOpen),
          borderRadius: BorderRadius.circular(DeliveryRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.xs),
            child: Row(
              children: <Widget>[
                Icon(
                  _retiredOpen ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: DeliveryColors.muted,
                ),
                const SizedBox(width: DeliverySpacing.xs),
                Text(t.attendanceRetiredShifts(retired.length), style: ConsoleText.cellMuted),
              ],
            ),
          ),
        ),
        if (_retiredOpen)
          for (final ShiftTemplate shift in retired)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: DeliverySpacing.lg,
                top: DeliverySpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(t.attendanceShiftLabel(shift.name, shift.startTime, shift.endTime),
                      style: ConsoleText.cellMuted),
                  const SizedBox(height: 2),
                  Text(_days(t, shift.weekdays), style: ConsoleText.meta),
                ],
              ),
            ),
      ],
    );
  }

  Widget _shiftRow(DeliveryStrings t, ShiftTemplate shift) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(t.attendanceShiftLabel(shift.name, shift.startTime, shift.endTime),
                  style: ConsoleText.cellStrong),
              const SizedBox(height: DeliverySpacing.xs),
              Wrap(
                spacing: DeliverySpacing.sm,
                runSpacing: DeliverySpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(_days(t, shift.weekdays), style: ConsoleText.cellMuted),
                  ConsoleQuietChip(label: t.attendanceShiftGrace(shift.lateGraceMinutes)),
                  if (shift.overnight) ConsoleQuietChip(label: t.attendanceShiftOvernight),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: DeliverySpacing.md),
        ConsoleCountChip(t.attendanceShiftRiders(shift.riders)),
        const SizedBox(width: DeliverySpacing.md),
        // A shift somebody is on, or is about to start, cannot be retired — the server answers
        // 409 — so the action is drawn off and its tooltip says what to do first, rather than
        // inviting a confirmation that ends in a refusal.
        ConsoleRowAction(
          icon: Icons.archive_outlined,
          tooltip: shift.riders > 0 ? t.attendanceRetireBlocked : t.attendanceRetireShift,
          destructive: true,
          onPressed: _busy || shift.riders > 0 ? null : () => _retire(shift),
        ),
      ],
    );
  }

  static String _days(DeliveryStrings t, List<int> weekdays) {
    final List<String> names = _weekdayNames(t);
    return weekdays.map((int d) => names[d - 1]).join(' · ');
  }

  static List<String> _weekdayNames(DeliveryStrings t) => <String>[
        t.attendanceWeekMon, t.attendanceWeekTue, t.attendanceWeekWed, t.attendanceWeekThu,
        t.attendanceWeekFri, t.attendanceWeekSat, t.attendanceWeekSun,
      ];

  // ------------------------------------------------------------------------------ riders

  Widget _ridersBlock(DeliveryStrings t, _Schedule data) {
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    final List<String> riders = List<String>.of(data.riders)
      ..sort((String a, String b) =>
          data.nameOf(a).toLowerCase().compareTo(data.nameOf(b).toLowerCase()));
    final MaterialLocalizations dates = MaterialLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(t.attendanceRidersCard, style: ConsoleText.cardTitle),
        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        ConsoleTable(
          minWidth: 760,
          columns: <ConsoleColumn>[
            ConsoleColumn(label: t.attendanceColRider, flex: 1),
            ConsoleColumn(label: t.attendanceColCurrentShift, width: 320),
            ConsoleColumn(label: t.attendanceColActions, width: 110, alignRight: true),
          ],
          empty: Text(t.attendanceNoRiders, style: ConsoleText.pageSubtitle),
          rows: <ConsoleTableRow>[
            for (final String rider in riders)
              ConsoleTableRow(
                onTap: () => setState(() => _openRider = rider),
                cells: <Widget>[
                  ConsoleNameCell(
                    name: data.nameOf(rider),
                    leading: ConsoleAvatar(name: data.nameOf(rider), radius: DeliveryRadius.sm),
                  ),
                  _shiftCell(t, data, rider, today, dates),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      ConsoleRowAction(
                        icon: Icons.schedule,
                        tooltip: t.attendanceChangeShift,
                        onPressed: _busy ? null : () => _assign(data, rider),
                      ),
                      const SizedBox(width: DeliverySpacing.sm),
                      ConsoleRowAction(
                        icon: Icons.calendar_month_outlined,
                        tooltip: t.attendanceOpenAttendance,
                        onPressed: () => setState(() => _openRider = rider),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
        if (data.unlinked > 0) ...<Widget>[
          const SizedBox(height: DeliverySpacing.sm),
          Text(t.attendanceUnlinkedRiders(data.unlinked), style: ConsoleText.meta),
        ],
      ],
    );
  }

  Widget _shiftCell(DeliveryStrings t, _Schedule data, String rider, DateTime today,
      MaterialLocalizations dates) {
    final List<ShiftAssignment> mine =
        data.assignments.where((ShiftAssignment a) => a.riderId == rider).toList();
    ShiftAssignment? current;
    ShiftAssignment? next;
    for (final ShiftAssignment a in mine) {
      if (a.covers(today)) {
        current = a;
      } else if (a.effectiveFrom.isAfter(today) &&
          (next == null || a.effectiveFrom.isBefore(next.effectiveFrom))) {
        next = a;
      }
    }
    final ShiftTemplate? shift = current == null ? null : data.shift(current.shiftId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          shift != null
              ? t.attendanceShiftLabel(shift.name, shift.startTime, shift.endTime)
              : current?.shiftName ?? t.attendanceFreelancer,
          overflow: TextOverflow.ellipsis,
          style: current == null ? ConsoleText.cellMuted : ConsoleText.cell,
        ),
        if (next != null)
          Text(
            t.attendanceUpcomingShift(
                next.shiftName ?? '—', dates.formatMediumDate(next.effectiveFrom)),
            overflow: TextOverflow.ellipsis,
            style: ConsoleText.meta,
          ),
      ],
    );
  }

  // ----------------------------------------------------------------------------- actions

  Future<void> _addShift() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final _NewShift? shift = await showDialog<_NewShift>(
      context: context,
      builder: (BuildContext _) => const _ShiftDialog(),
    );
    if (shift == null || !mounted) return;
    await _run(
      () => widget.api.createShift(
        name: shift.name,
        startTime: shift.start,
        endTime: shift.end,
        weekdays: shift.weekdays,
        lateGraceMinutes: shift.grace,
      ),
      t.attendanceShiftCreated,
    );
  }

  Future<void> _retire(ShiftTemplate shift) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: DeliveryColors.white,
        surfaceTintColor: DeliveryColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
        title: Text(t.attendanceRetireShift, style: ConsoleText.cardTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              t.attendanceShiftLabel(shift.name, shift.startTime, shift.endTime),
              style: ConsoleText.pageSubtitle,
            ),
            const SizedBox(height: DeliverySpacing.sm),
            // What retiring does not do, said where it is decided: the days already worked on
            // this shift keep being judged against it.
            Text(
              t.attendanceRetireKeepsHistory,
              style: ConsoleText.body.copyWith(color: DeliveryColors.muted),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel, style: const TextStyle(color: DeliveryColors.muted)),
          ),
          ConsoleSoftButton(
            label: t.attendanceRetireShift,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() => widget.api.retireShift(shift.id), t.attendanceShiftRetired);
  }

  Future<void> _assign(_Schedule data, String rider) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final _Assignment? choice = await showDialog<_Assignment>(
      context: context,
      builder: (BuildContext _) => _AssignDialog(
        riderName: data.nameOf(rider),
        shifts: data.shifts,
        current: data.assignments
            .where((ShiftAssignment a) =>
                a.riderId == rider && a.covers(DateUtils.dateOnly(DateTime.now())))
            .map((ShiftAssignment a) => a.shiftId)
            .firstOrNull,
      ),
    );
    if (choice == null || !mounted) return;
    await _run(
      () => widget.api.assignShift(
        rider,
        shiftId: choice.shiftId,
        // "Today" is sent as no date at all, so the server applies its own today in Beirut. The
        // browser's date can be a day behind it (a manager in Paris just before midnight), and
        // the server refuses any schedule that starts before its today.
        effectiveFrom: DateUtils.isSameDay(choice.from, DateTime.now()) ? null : choice.from,
      ),
      t.attendanceAssignSaved,
    );
  }

  Future<void> _run(Future<Object?> Function() action, String done) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    setState(() => _busy = true);
    try {
      await action();
      _tell(done);
      _reload();
    } on DioException catch (e) {
      // The one refusal worth its own sentence: a shift still in use cannot be retired.
      _tell(e.response?.statusCode == 409 && e.response?.data is Map &&
              (e.response!.data as Map)['riders'] is num &&
              ((e.response!.data as Map)['riders'] as num) > 0
          ? t.attendanceRetireBlocked
          : _messageFor(e, t), bad: true);
    } catch (e) {
      _tell(_messageFor(e, t), bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _tell(String message, {bool bad = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: bad ? DeliveryAccent.critical.color : null,
    ));
  }

  static String _messageFor(Object error, DeliveryStrings t) {
    if (error is DioException) {
      final dynamic body = error.response?.data;
      if (body is Map && body['detail'] is String) return body['detail'] as String;
    }
    return t.thatDidNotWork;
  }

  Widget _failure(DeliveryStrings t, Object error) {
    final bool noCompany = error is DioException && error.response?.statusCode == 403;
    return Padding(
      padding: const EdgeInsets.all(DeliverySpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.help_outline, size: 32, color: DeliveryColors.faint),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          Text(noCompany ? t.noCompanyYet : t.attendanceLoadFailed,
              textAlign: TextAlign.center, style: ConsoleText.cardTitle),
          const SizedBox(height: DeliverySpacing.sm),
          if (noCompany)
            Text(t.askThePlatformToAttachYou,
                textAlign: TextAlign.center, style: ConsoleText.pageSubtitle)
          else
            ConsoleSoftButton(
              label: t.tryAgain,
              icon: Icons.refresh,
              accent: DeliveryAccent.info,
              onPressed: _reload,
            ),
        ],
      ),
    );
  }
}

/// What the page loaded.
class _Schedule {
  const _Schedule({
    required this.shifts,
    required this.retired,
    required this.assignments,
    required this.riders,
    required this.names,
    required this.unlinked,
  });

  /// Current shifts only; retired ones are history and are not offered.
  final List<ShiftTemplate> shifts;

  /// Retired shifts: listed, folded away, for the past days still judged against them.
  final List<ShiftTemplate> retired;
  final List<ShiftAssignment> assignments;

  /// The tracking roster: the riders the attendance endpoints answer for.
  final List<String> riders;
  final Map<String, String> names;

  /// Riders the company employs that tracking has not linked to the fleet yet.
  final int unlinked;

  /// The rider's own name from their application, or their reference when there is none.
  String nameOf(String rider) =>
      names[rider] ?? (rider.length > 8 ? rider.substring(0, 8) : rider);

  ShiftTemplate? shift(String id) {
    for (final ShiftTemplate s in shifts) {
      if (s.id == id) return s;
    }
    return null;
  }
}

class _NewShift {
  const _NewShift({
    required this.name,
    required this.start,
    required this.end,
    required this.weekdays,
    required this.grace,
  });

  final String name;
  final String start;
  final String end;
  final List<int> weekdays;
  final int grace;
}

/// A new shift. The hours are fixed once created, and the dialog says so up front.
class _ShiftDialog extends StatefulWidget {
  const _ShiftDialog();

  @override
  State<_ShiftDialog> createState() => _ShiftDialogState();
}

class _ShiftDialogState extends State<_ShiftDialog> {
  static final RegExp _time = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

  final TextEditingController _name = TextEditingController();
  final TextEditingController _start = TextEditingController(text: '08:00');
  final TextEditingController _end = TextEditingController(text: '18:00');
  final TextEditingController _grace = TextEditingController(text: '10');

  /// Monday to Friday to begin with — the design's schedule, and the commonest one.
  final Set<int> _days = <int>{1, 2, 3, 4, 5};
  bool _tried = false;

  @override
  void dispose() {
    _name.dispose();
    _start.dispose();
    _end.dispose();
    _grace.dispose();
    super.dispose();
  }

  String? _problem(DeliveryStrings t) {
    if (_name.text.trim().isEmpty) return t.attendanceShiftNeedsName;
    final String start = _start.text.trim();
    final String end = _end.text.trim();
    if (!_time.hasMatch(start) || !_time.hasMatch(end)) return t.attendanceTimeInvalid;
    if (start == end) return t.attendanceShiftSameTimes;
    if (_days.isEmpty) return t.attendanceShiftNeedsDays;
    final int? grace = int.tryParse(_grace.text.trim());
    if (grace == null || grace < 0 || grace > 120) return t.attendanceGraceInvalid;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String? problem = _problem(t);
    final List<String> names = _ShiftScheduleScreenState._weekdayNames(t);

    return AlertDialog(
      backgroundColor: DeliveryColors.white,
      surfaceTintColor: DeliveryColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
      title: Text(t.attendanceNewShiftTitle, style: ConsoleText.cardTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _field(_name, t.attendanceShiftName, maxLength: 80),
              const SizedBox(height: DeliverySpacing.sm),
              Row(
                children: <Widget>[
                  Expanded(child: _field(_start, t.attendanceShiftStart)),
                  const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
                  Expanded(child: _field(_end, t.attendanceShiftEnd)),
                ],
              ),
              const SizedBox(height: DeliverySpacing.md),
              Text(t.attendanceShiftDays, style: ConsoleText.fieldLabel),
              const SizedBox(height: DeliverySpacing.sm),
              Wrap(
                spacing: DeliverySpacing.sm,
                runSpacing: DeliverySpacing.sm,
                children: <Widget>[
                  for (int d = 1; d <= 7; d++)
                    _DayToggle(
                      label: names[d - 1],
                      selected: _days.contains(d),
                      onTap: () => setState(() => _days.contains(d) ? _days.remove(d) : _days.add(d)),
                    ),
                ],
              ),
              const SizedBox(height: DeliverySpacing.md),
              _field(_grace, t.attendanceShiftGraceField),
              const SizedBox(height: DeliverySpacing.sm),
              Text(t.attendanceShiftImmutable, style: ConsoleText.meta),
              if (_tried && problem != null) ...<Widget>[
                const SizedBox(height: DeliverySpacing.sm),
                Text(problem,
                    style: TextStyle(fontSize: 12, color: DeliveryAccent.critical.onTint)),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel, style: const TextStyle(color: DeliveryColors.muted)),
        ),
        ConsolePrimaryButton(
          label: t.attendanceCreateShift,
          onPressed: () {
            if (problem != null) {
              setState(() => _tried = true);
              return;
            }
            Navigator.pop(
              context,
              _NewShift(
                name: _name.text.trim(),
                start: _start.text.trim(),
                end: _end.text.trim(),
                weekdays: _days.toList()..sort(),
                grace: int.parse(_grace.text.trim()),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label, {int? maxLength}) {
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      borderSide: const BorderSide(color: DeliveryColors.border),
    );
    return TextField(
      controller: controller,
      maxLength: maxLength,
      style: ConsoleText.cell,
      cursorColor: DeliveryColors.brand,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: DeliveryColors.background,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(borderSide: const BorderSide(color: DeliveryColors.brand)),
      ),
      onChanged: (_) => setState(() {}),
    );
  }
}

/// One weekday in the shift dialog: crimson when chosen, the page's slate when not — the same
/// pairing as [ConsoleSegmented], but several may be on at once.
class _DayToggle extends StatelessWidget {
  const _DayToggle({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? DeliveryColors.brand : DeliveryColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        side: BorderSide(color: selected ? DeliveryColors.brand : DeliveryColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DeliverySpacing.md - DeliverySpacing.xs,
            vertical: 6,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? DeliveryColors.white : DeliveryColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _Assignment {
  const _Assignment({required this.shiftId, required this.from});

  /// Null takes the rider off their schedule.
  final String? shiftId;
  final DateTime from;
}

/// Which shift a rider works, from which day. Today or later only — past days keep the schedule
/// they were worked against, and the dialog cannot pick a past date.
class _AssignDialog extends StatefulWidget {
  const _AssignDialog({required this.riderName, required this.shifts, this.current});

  final String riderName;
  final List<ShiftTemplate> shifts;
  final String? current;

  @override
  State<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<_AssignDialog> {
  late String? _shift = widget.current;
  DateTime _from = DateUtils.dateOnly(DateTime.now());

  String _label(DeliveryStrings t, String? id) {
    if (id == null) return t.attendanceFreelancer;
    for (final ShiftTemplate s in widget.shifts) {
      if (s.id == id) return t.attendanceShiftLabel(s.name, s.startTime, s.endTime);
    }
    return t.attendanceFreelancer;
  }

  Future<void> _pickDate() async {
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: today,
      // The server's own limit on how far ahead a schedule may be set up.
      lastDate: today.add(const Duration(days: 90)),
    );
    if (picked != null) setState(() => _from = picked);
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return AlertDialog(
      backgroundColor: DeliveryColors.white,
      surfaceTintColor: DeliveryColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
      title: Text(t.attendanceAssignTitle(widget.riderName), style: ConsoleText.cardTitle),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(t.attendanceColCurrentShift, style: ConsoleText.fieldLabel),
            const SizedBox(height: 6),
            ConsoleSelect(
              label: _label(t, _shift),
              icon: Icons.schedule,
              options: <ConsoleOption>[
                ConsoleOption(label: t.attendanceFreelancer, value: null),
                for (final ShiftTemplate s in widget.shifts)
                  ConsoleOption(
                    label: t.attendanceShiftLabel(s.name, s.startTime, s.endTime),
                    value: s.id,
                  ),
              ],
              onSelected: (String? id) => setState(() => _shift = id),
            ),
            const SizedBox(height: DeliverySpacing.md),
            Text(t.attendanceAssignFrom, style: ConsoleText.fieldLabel),
            const SizedBox(height: 6),
            ConsoleFilterButton(
              label: MaterialLocalizations.of(context).formatFullDate(_from),
              icon: Icons.event_outlined,
              onPressed: _pickDate,
            ),
            const SizedBox(height: DeliverySpacing.sm),
            Text(t.attendanceAssignNote, style: ConsoleText.meta),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel, style: const TextStyle(color: DeliveryColors.muted)),
        ),
        ConsolePrimaryButton(
          label: t.attendanceAssignSave,
          onPressed: () => Navigator.pop(context, _Assignment(shiftId: _shift, from: _from)),
        ),
      ],
    );
  }
}
