import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../shell/console_controls.dart';
import '../shell/shell.dart';

/// Rider Attendance & Shift Logs — Figma `web-carrier-rider-attendance` (112:945), inside the
/// carrier's Riders HR.
///
/// One rider, one calendar month: a calendar coloured by what each day came to, the month's
/// totals, and the clock-in/clock-out log — all from order-tracking's attendance read, which
/// judges the duty sessions the rider app records against the shift the company scheduled.
///
/// Three rules decide what is drawn:
///
/// * **A freelancer is never late or absent.** A rider with no schedule for the month gets the
///   duty log only: the Late/Absent legend, the scheduled-shift and status columns and the
///   absence, lateness and overtime figures are not drawn at all, and a sentence says why. Zeros in
///   those places would be claims about somebody who was never expected.
/// * **The app's evidence and the office's typed hours stay apart.** Hours logged by hand are
///   shown as such, beside — never inside — what the app recorded.
/// * **Beirut's clock, not the browser's.** Times arrive as wall-clock strings in the server's
///   day zone, so a manager reading from abroad still sees the rider's 07:56.
///
/// The design's month has no navigation drawn but says "for October 2026"; the chevrons beside the
/// month are that implied control. The header's live badge is the fleet's on-duty count from the
/// tracking roster, and is not drawn at all when the roster cannot be read. The design's sample figures (22 days worked by the 21st with
/// weekends off) are impossible and are not reproduced — every figure here is the server's.
class RiderAttendanceScreen extends StatefulWidget {
  const RiderAttendanceScreen({
    super.key,
    required this.api,
    required this.riderId,
    required this.riderName,
    this.initialMonth,
    this.onBack,
    this.backTooltip,
  });

  final TrackingApi api;

  /// The rider's Keycloak subject. A carrier can only open riders on its own fleet; anybody else
  /// is the server's 404, rendered as "not on your fleet".
  final String riderId;
  final String riderName;

  /// Any day in the month to open on. Today's month when null.
  final DateTime? initialMonth;

  /// Back to the page this was opened from. Null draws no back control.
  final VoidCallback? onBack;

  /// What the back control says it returns to. "Back to riders" when null — the Shifts page's
  /// rider list, where this page was first opened from; a rider's profile passes its own.
  final String? backTooltip;

  @override
  State<RiderAttendanceScreen> createState() => _RiderAttendanceScreenState();
}

class _RiderAttendanceScreenState extends State<RiderAttendanceScreen> {
  late DateTime _month;
  late Future<RiderAttendance> _data;
  bool _busy = false;

  /// Riders on duty right now, for the header's live badge. Null until the roster answers — and for
  /// good if it cannot, in which case no badge is drawn rather than a guessed count.
  int? _onDuty;

  @override
  void initState() {
    super.initState();
    final DateTime start = widget.initialMonth ?? DateTime.now();
    _month = DateTime(start.year, start.month);
    _data = _load();
    _countOnDuty();
  }

  /// The live badge's figure: riders who declared duty and are still being sighted. The roster's
  /// on-duty filter keeps a rider whose phone went quiet (marked stale) on purpose, for dispatch;
  /// live they are not, so they are not counted.
  Future<void> _countOnDuty() async {
    try {
      final List<RiderPresence> declared = await widget.api.roster(onDutyOnly: true);
      if (!mounted) return;
      setState(() {
        _onDuty = declared.where((RiderPresence p) => p.state == PresenceState.onDuty).length;
      });
    } catch (_) {
      // No figure beats a wrong one: the badge stays undrawn.
    }
  }

  /// The month's read, marked handled the moment it is made. A chevron or a retry makes it outside a
  /// frame, and the FutureBuilder only subscribes on the next build: a refusal landing before then
  /// would otherwise be reported as an uncaught error even though the page shows it. [Future.ignore]
  /// does not stop the builder receiving the error.
  Future<RiderAttendance> _load() =>
      widget.api.riderAttendance(widget.riderId, month: _month)..ignore();

  void _step(int months) {
    setState(() {
      _month = DateTime(_month.year, _month.month + months);
      _data = _load();
    });
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
    final String monthLabel = MaterialLocalizations.of(context).formatMonthYear(_month);

    return ConsolePage(
      header: ConsoleTopbar(
        title: t.attendanceTitle,
        subtitle: t.attendanceSubtitle,
        titleStyle: ConsoleText.pageTitleSmall,
        actions: <Widget>[
          if (_onDuty != null) _LiveBadge(label: t.attendanceLiveOnDuty(_onDuty!)),
          // The console bell's slot, drawn off as on the other carrier pages: wiring it needs a
          // NotificationApi threaded to the carrier area, which no carrier page has yet, and a
          // greyed control is a truer picture than an empty corner.
          ConsoleIconAction(icon: Icons.notifications_none, tooltip: t.notifications),
        ],
      ),
      children: <Widget>[
        FutureBuilder<RiderAttendance>(
          future: _data,
          builder: (BuildContext context, AsyncSnapshot<RiderAttendance> snapshot) {
            final RiderAttendance? month =
                snapshot.connectionState == ConnectionState.done ? snapshot.data : null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _headerRow(t, monthLabel, month),
                const SizedBox(height: ConsoleMetrics.pageGap),
                if (month != null)
                  _body(t, month, monthLabel)
                else ...<Widget>[
                  // The month's own controls stay while it loads and after it failed, so a month
                  // that cannot be read is never a dead end: the reader can step back out of it.
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _monthNav(t, monthLabel),
                  ),
                  if (snapshot.connectionState != ConnectionState.done)
                    const Padding(
                      padding: EdgeInsets.all(DeliverySpacing.xl),
                      child: Center(
                        child: CircularProgressIndicator(color: DeliveryColors.brand),
                      ),
                    )
                  else
                    _failure(t, snapshot.error ?? StateError('no attendance')),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  // ------------------------------------------------------------------------------ header

  Widget _headerRow(DeliveryStrings t, String monthLabel, RiderAttendance? month) {
    return Row(
      children: <Widget>[
        if (widget.onBack != null) ...<Widget>[
          ConsoleIconAction(
            icon: Icons.arrow_back,
            tooltip: widget.backTooltip ?? t.attendanceBackToRiders,
            onPressed: widget.onBack,
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
        ],
        ConsoleAvatar(name: widget.riderName, size: 36),
        const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                widget.riderName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                t.attendanceForMonth(monthLabel),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: DeliveryColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: DeliverySpacing.md),
        ConsolePrimaryButton(
          label: t.attendanceManualLog,
          icon: Icons.add,
          busy: _busy,
          // Needs the loaded month: the dialog's "today" is the server's, in its zone.
          onPressed: month == null ? null : () => _openLog(month, null),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------------- body

  Widget _body(DeliveryStrings t, RiderAttendance month, String monthLabel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final Widget calendar = _calendarCard(t, month, monthLabel);
            final Widget totals = _totalsCard(t, month);
            // The design's split: calendar flexing, a 380px figures panel beside it. Stacked
            // when the content column is too narrow to give the calendar its seven cells.
            if (box.maxWidth >= 1000) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: calendar),
                  const SizedBox(width: ConsoleMetrics.pageGap),
                  SizedBox(width: 380, child: totals),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                calendar,
                const SizedBox(height: ConsoleMetrics.pageGap),
                totals,
              ],
            );
          },
        ),
        const SizedBox(height: ConsoleMetrics.pageGap),
        _logs(t, month),
      ],
    );
  }

  // ---------------------------------------------------------------------------- calendar

  static const TextStyle _heading = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: DeliveryColors.ink,
  );

  /// The month's name with the chevrons that step it — the navigation the design implies with "for
  /// October 2026" but does not draw.
  Widget _monthNav(DeliveryStrings t, String monthLabel) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(monthLabel, style: _heading),
        const SizedBox(width: DeliverySpacing.sm),
        ConsoleIconAction(
          icon: Icons.chevron_left,
          tooltip: t.attendancePrevMonth,
          onPressed: () => _step(-1),
        ),
        const SizedBox(width: DeliverySpacing.xs),
        ConsoleIconAction(
          icon: Icons.chevron_right,
          tooltip: t.attendanceNextMonth,
          onPressed: () => _step(1),
        ),
      ],
    );
  }

  Widget _calendarCard(DeliveryStrings t, RiderAttendance month, String monthLabel) {
    final Map<String, AttendanceDay> byDate = <String, AttendanceDay>{
      for (final AttendanceDay d in month.days) _key(d.date): d,
    };
    final DateTime first = DateTime(_month.year, _month.month);
    final int length = DateTime(_month.year, _month.month + 1, 0).day;
    // Monday first, as drawn — the Lebanese working week, and what the schedule's weekdays mean.
    final int lead = first.weekday - DateTime.monday;

    final List<Widget> cells = <Widget>[
      for (int i = 0; i < lead; i++) const SizedBox(width: 40, height: 40),
      for (int d = 1; d <= length; d++)
        _dayCell(t, DateTime(_month.year, _month.month, d),
            byDate[_key(DateTime(_month.year, _month.month, d))], month),
    ];
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox(width: 40, height: 40));
    }

    final bool excusedShown = month.days.any((AttendanceDay d) =>
        d.status == AttendanceStatus.excused ||
        d.status == AttendanceStatus.sick ||
        d.status == AttendanceStatus.leave);
    final List<String> weekdays = <String>[
      t.attendanceWeekMon, t.attendanceWeekTue, t.attendanceWeekWed, t.attendanceWeekThu,
      t.attendanceWeekFri, t.attendanceWeekSat, t.attendanceWeekSun,
    ];

    return Container(
      padding: const EdgeInsets.all(ConsoleMetrics.cardPadding),
      decoration: ConsoleSurface.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Wrap(
            spacing: DeliverySpacing.md,
            runSpacing: DeliverySpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: <Widget>[
              _monthNav(t, monthLabel),
              Wrap(
                spacing: DeliverySpacing.md,
                runSpacing: DeliverySpacing.xs,
                children: month.hasSchedule
                    ? <Widget>[
                        ConsoleLegendSwatch(
                            label: t.attendanceLegendPresent,
                            color: DeliveryAccent.positive.color),
                        ConsoleLegendSwatch(
                            label: t.attendanceLegendLate, color: DeliveryAccent.caution.color),
                        ConsoleLegendSwatch(
                            label: t.attendanceLegendAbsent,
                            color: DeliveryAccent.critical.color),
                        ConsoleLegendSwatch(
                            label: t.attendanceLegendOff, color: DeliveryColors.border),
                        if (excusedShown)
                          ConsoleLegendSwatch(
                              label: t.attendanceExcusedDays, color: DeliveryAccent.info.color),
                      ]
                    // A freelancer has one state worth a colour: on duty.
                    : <Widget>[
                        ConsoleLegendSwatch(
                            label: t.attendanceLegendOnDuty,
                            color: DeliveryAccent.positive.color),
                      ],
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              for (final String w in weekdays)
                SizedBox(
                  width: 40,
                  child: Text(
                    w,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: DeliveryColors.faint,
                    ),
                  ),
                ),
            ],
          ),
          for (int row = 0; row < cells.length ~/ 7; row++) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: cells.sublist(row * 7, row * 7 + 7),
            ),
          ],
          if (!month.hasSchedule) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            Text(
              t.attendanceNoSchedule,
              style: ConsoleText.body.copyWith(color: DeliveryColors.muted),
            ),
          ],
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          Text(t.attendanceZoneNote(month.zone), style: ConsoleText.meta),
        ],
      ),
    );
  }

  Widget _dayCell(
      DeliveryStrings t, DateTime date, AttendanceDay? day, RiderAttendance month) {
    final _CellLook look = _CellLook.of(day?.status);
    final bool today = _key(date) == _key(month.today);
    // A day opens the Manual Attendance Log only if the server would take an entry for it: inside
    // the duty history it keeps, and no further ahead than leave may be planned.
    final bool loggable = _withinLogWindow(date, month.today);

    final Widget cell = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _busy || !loggable ? null : () => _openLog(month, date),
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: look.fill,
            borderRadius: BorderRadius.circular(DeliveryRadius.sm),
            // Today is marked whatever it came to, so the reader can find their place.
            border: today ? Border.all(color: DeliveryColors.brand, width: 2) : null,
          ),
          child: Text(
            '${date.day}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: look.strong ? FontWeight.w600 : FontWeight.w400,
              color: look.ink,
            ),
          ),
        ),
      ),
    );
    // A verdict gets a tooltip; a day with nothing to say (no duty, not yet, unknown) gets none
    // rather than a lone dash.
    if (day == null || !_hasVerdict(day.status)) return cell;
    return Tooltip(message: _statusLabel(t, day.status), child: cell);
  }

  /// How far back the server keeps duty history (`delivery.tracking.duty-event-retention-days`)
  /// and how far ahead it lets leave be planned — its bounds on a Manual Attendance Log entry,
  /// restated so a day outside them offers no log at all rather than one that is refused.
  static const int _historyDays = 400;
  static const int _leaveAheadDays = 180;

  /// Calendar arithmetic rather than a [Duration]: across a clock change a day is not 24 hours.
  static DateTime _addDays(DateTime day, int days) => DateTime(day.year, day.month, day.day + days);

  static bool _withinLogWindow(DateTime date, DateTime today) =>
      !date.isBefore(_addDays(today, -_historyDays)) &&
      !date.isAfter(_addDays(today, _leaveAheadDays));

  static bool _hasVerdict(AttendanceStatus status) =>
      status != AttendanceStatus.noDuty &&
      status != AttendanceStatus.upcoming &&
      status != AttendanceStatus.unknown;

  // ------------------------------------------------------------------------------ totals

  Widget _totalsCard(DeliveryStrings t, RiderAttendance month) {
    final AttendanceTotals x = month.totals;
    final int excused = x.excusedAbsences + x.sickDays + x.leaveDays + x.excusedLates;

    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.lg - DeliverySpacing.xs),
      decoration: ConsoleSurface.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            t.attendanceAggregatesTitle,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
            ),
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          _figure(t.attendanceDaysWorked, t.attendanceDaysCount(x.daysWorked),
              DeliveryAccent.positive.color),
          // Absence, lateness and overtime only exist against a schedule. For a freelancer they
          // are not zero — they are not questions — so they are not drawn.
          if (month.hasSchedule) ...<Widget>[
            _figure(t.attendanceAbsences, t.attendanceDaysCount(x.absences),
                DeliveryAccent.critical.color),
            _figure(t.attendanceTimesLate, t.attendanceDaysCount(x.lates),
                DeliveryAccent.caution.color),
            _figure(t.attendanceOvertime, t.attendanceHoursValue(_hours(x.overtimeSeconds)),
                DeliveryColors.ink),
            if (excused > 0)
              _figure(t.attendanceExcusedDays, t.attendanceDaysCount(excused),
                  DeliveryAccent.info.color),
          ] else
            _figure(t.attendanceHoursOnDuty, t.attendanceHoursValue(_hours(x.workedSeconds)),
                DeliveryColors.ink),
          if (x.manualSeconds > 0)
            _figure(t.attendanceManualHours, t.attendanceHoursValue(_hours(x.manualSeconds)),
                DeliveryColors.muted),
        ],
      ),
    );
  }

  static Widget _figure(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13, color: DeliveryColors.muted)),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  /// Hours at one decimal, from the exact seconds — never a sum of rounded figures.
  static String _hours(int seconds) => (seconds / 3600).toStringAsFixed(1);

  // -------------------------------------------------------------------------------- logs

  Widget _logs(DeliveryStrings t, RiderAttendance month) {
    final bool scheduled = month.hasSchedule;
    // Newest first, and only days with something to say: a freelancer's idle day and a day off
    // are not log lines, but a scheduled day nobody came for is.
    final List<AttendanceDay> days = month.days.where(_loggable).toList().reversed.toList();
    final MaterialLocalizations dates = MaterialLocalizations.of(context);

    return ConsoleTable(
      // Inside the card, as 112:945 draws it.
      title: Text(t.attendanceLogsTitle, style: _heading),
      minWidth: 900,
      columns: <ConsoleColumn>[
        ConsoleColumn(label: t.attendanceColDate, width: 150),
        if (scheduled) ConsoleColumn(label: t.attendanceColShift, width: 200),
        ConsoleColumn(label: t.attendanceColClockIn, width: 110),
        ConsoleColumn(label: t.attendanceColClockOut, width: 130),
        ConsoleColumn(label: t.attendanceColHours, width: 100),
        if (scheduled) ConsoleColumn(label: t.attendanceColStatus, width: 150),
        ConsoleColumn(label: t.attendanceColNotes, flex: 1),
      ],
      empty: Text(t.attendanceEmptyMonth, style: ConsoleText.pageSubtitle),
      rows: <ConsoleTableRow>[
        for (final AttendanceDay d in days)
          ConsoleTableRow(
            cells: <Widget>[
              // "Oct 24, 2026", as drawn: a line of a pay record carries its year.
              Text(dates.formatShortDate(d.date), style: ConsoleText.cellStrong),
              if (scheduled)
                Text(
                  d.scheduled == null
                      ? '—'
                      : t.attendanceShiftLabel(
                          d.scheduled!.name, d.scheduled!.startTime, d.scheduled!.endTime),
                  style: ConsoleText.body,
                ),
              _clockInCell(t, d),
              _clockOutCell(t, d),
              _hoursCell(t, d),
              if (scheduled) _statusPill(t, d.status),
              Text(
                _notes(t, d),
                style: const TextStyle(fontSize: 12, color: DeliveryColors.muted),
              ),
            ],
            onTap: _busy ? null : () => _openLog(month, d.date),
          ),
      ],
    );
  }

  static bool _loggable(AttendanceDay d) {
    if (d.status == AttendanceStatus.upcoming) return false;
    if (d.sessions.isNotEmpty || d.entry != null) return true;
    return d.status != AttendanceStatus.noDuty &&
        d.status != AttendanceStatus.dayOff &&
        d.status != AttendanceStatus.unknown;
  }

  /// 24-hour wall-clock time, with a "+1" when it fell on the next day (the end of a night shift).
  static String _clock(DateTime local, DateTime day) {
    final String hhmm =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    final bool nextDay = local.year != day.year || local.month != day.month || local.day != day.day;
    return nextDay ? '$hhmm (+1)' : hhmm;
  }

  /// A time on the log, laid out left to right in either language. In a right-to-left row the bidi
  /// algorithm would otherwise paint "06:30 (+1)" as "(1+) 06:30".
  static Widget _time(String text, {TextStyle style = ConsoleText.body}) =>
      Text(text, textDirection: TextDirection.ltr, style: style);

  /// How a figure the office typed is printed: muted and italic, never in the app's own ink.
  static const TextStyle _typedStyle =
      TextStyle(fontSize: 13, color: DeliveryColors.muted, fontStyle: FontStyle.italic);

  static Widget _clockInCell(DeliveryStrings t, AttendanceDay d) {
    if (d.clockInLocal != null) return _time(_clock(d.clockInLocal!, d.date));
    final ManualAttendanceEntry? typed = _typed(d);
    if (typed != null) return _typedTime(t, typed.clockIn!, nextDay: false);
    return const Text('—', style: ConsoleText.body);
  }

  static Widget _clockOutCell(DeliveryStrings t, AttendanceDay d) {
    if (d.onShiftNow) {
      return Text(
        t.attendanceOnShiftNow,
        style: ConsoleText.body.copyWith(
          color: DeliveryAccent.positive.onTint,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    if (d.clockOutLocal != null) return _time(_clock(d.clockOutLocal!, d.date));
    final ManualAttendanceEntry? typed = _typed(d);
    if (typed != null) {
      // A typed clock-out at or before the clock-in is the next morning, as the server counts it.
      return _typedTime(t, typed.clockOut!,
          nextDay: typed.clockOut!.compareTo(typed.clockIn!) <= 0);
    }
    return const Text('—', style: ConsoleText.body);
  }

  /// The office's typed times, on the one kind of day they are what the day has: a manual
  /// "present" with times and nothing from the app (the server reports manual seconds only then).
  /// On a day the app shows, typed times count for nothing, so none are printed.
  static ManualAttendanceEntry? _typed(AttendanceDay d) {
    final ManualAttendanceEntry? entry = d.entry;
    if (d.manualSeconds <= 0 || entry?.clockIn == null || entry?.clockOut == null) return null;
    return entry;
  }

  /// A typed time, beside the app's and never dressed as it: muted, pencil-marked, and saying on
  /// hover where it came from.
  static Widget _typedTime(DeliveryStrings t, String hhmm, {required bool nextDay}) {
    return Tooltip(
      message: t.attendanceTypedByHand,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _time(nextDay ? '$hhmm (+1)' : hhmm, style: _typedStyle),
          const SizedBox(width: DeliverySpacing.xs),
          const Icon(Icons.edit_outlined, size: 12, color: DeliveryColors.faint),
        ],
      ),
    );
  }

  /// The app's hours — or, on a day it has none, the office's typed hours under a Manual tag.
  /// Never one printed as though it were the other.
  static Widget _hoursCell(DeliveryStrings t, AttendanceDay d) {
    if (d.workedSeconds == 0 && d.manualSeconds > 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(t.attendanceHoursShort(_hours(d.manualSeconds)), style: _typedStyle),
          const SizedBox(height: 2),
          ConsoleQuietChip(label: t.attendanceManualTag),
        ],
      );
    }
    return Text(
      t.attendanceHoursShort(_hours(d.workedSeconds)),
      style: ConsoleText.body.copyWith(fontWeight: FontWeight.w500),
    );
  }

  String _notes(DeliveryStrings t, AttendanceDay d) {
    final List<String> parts = <String>[
      if (d.entry?.note != null) d.entry!.note!,
      if (!d.onShiftNow && d.clockOutReason == DutyEndReason.expired) t.attendanceAutoClosed,
      if (d.status == AttendanceStatus.late && d.lateBySeconds != null)
        t.attendanceLateBy(d.lateBySeconds! ~/ 60),
      if (d.overtimeSeconds >= 60) t.attendanceOvertimeNote(d.overtimeSeconds ~/ 60),
      if (d.entry != null) t.attendanceLoggedByHand,
    ];
    return parts.isEmpty ? '' : parts.join(' · ');
  }

  static Widget _statusPill(DeliveryStrings t, AttendanceStatus status) {
    final String label = _statusLabel(t, status);
    final DeliveryAccent? accent = switch (status) {
      AttendanceStatus.present || AttendanceStatus.worked || AttendanceStatus.extra =>
        DeliveryAccent.positive,
      AttendanceStatus.late || AttendanceStatus.lateExcused => DeliveryAccent.caution,
      AttendanceStatus.absent => DeliveryAccent.critical,
      AttendanceStatus.pending ||
      AttendanceStatus.excused ||
      AttendanceStatus.sick ||
      AttendanceStatus.leave =>
        DeliveryAccent.info,
      _ => null,
    };
    return accent == null
        ? ConsoleQuietChip(label: label)
        : ConsoleStatusPill(label: label, accent: accent);
  }

  static String _statusLabel(DeliveryStrings t, AttendanceStatus status) => switch (status) {
        AttendanceStatus.present => t.attendanceStatusOnTime,
        AttendanceStatus.late => t.attendanceStatusLate,
        AttendanceStatus.absent => t.attendanceStatusAbsent,
        AttendanceStatus.pending => t.attendanceStatusPending,
        AttendanceStatus.dayOff => t.attendanceStatusDayOff,
        AttendanceStatus.extra => t.attendanceStatusExtra,
        AttendanceStatus.worked => t.attendanceStatusWorked,
        AttendanceStatus.lateExcused => t.attendanceStatusLateExcused,
        AttendanceStatus.excused => t.attendanceStatusExcused,
        AttendanceStatus.sick => t.attendanceStatusSick,
        AttendanceStatus.leave => t.attendanceStatusLeave,
        AttendanceStatus.noDuty ||
        AttendanceStatus.upcoming ||
        AttendanceStatus.unknown =>
          '—',
      };

  // ----------------------------------------------------------------------------- failure

  Widget _failure(DeliveryStrings t, Object error) {
    final int? status = error is DioException ? error.response?.statusCode : null;
    if (status == 404) {
      // A foreign rider and an unknown one answer the identical 404 by design; the likeliest
      // reason on this page is the tracking linkage, which is what the sentence says.
      return _note(Icons.person_off_outlined, t.attendanceNotOnFleet, null);
    }
    if (status == 403) {
      return _note(Icons.help_outline, t.noCompanyYet, t.askThePlatformToAttachYou);
    }
    if (status == 400) {
      // The one 400 this page can cause: a month older than the duty history the server keeps,
      // reached with the chevrons. Asking again can never work, so no retry is offered; the
      // month controls above stay, and lead back out.
      return _note(Icons.history_toggle_off, t.attendanceHistoryLimit, null);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _note(Icons.cloud_off_outlined, t.attendanceLoadFailed, null),
        const SizedBox(height: DeliverySpacing.md),
        ConsoleSoftButton(
          label: t.tryAgain,
          icon: Icons.refresh,
          accent: DeliveryAccent.info,
          onPressed: _reload,
        ),
      ],
    );
  }

  static Widget _note(IconData icon, String title, String? detail) {
    return Padding(
      padding: const EdgeInsets.all(DeliverySpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 32, color: DeliveryColors.faint),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          Text(title, textAlign: TextAlign.center, style: ConsoleText.cardTitle),
          if (detail != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            Text(detail, textAlign: TextAlign.center, style: ConsoleText.pageSubtitle),
          ],
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------- manual log

  Future<void> _openLog(RiderAttendance month, DateTime? date) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    // The month on screen when it contains today, otherwise its last day — whichever the office
    // is most likely correcting.
    DateTime initial = date ??
        (month.today.isBefore(month.from) || month.today.isAfter(month.to)
            ? month.to
            : month.today);
    // Kept inside the days the server takes an entry for, which is also the date picker's range: a
    // month far ahead would otherwise open the log on a day nobody may record.
    final DateTime earliest = _addDays(month.today, -_historyDays);
    final DateTime latest = _addDays(month.today, _leaveAheadDays);
    if (initial.isBefore(earliest)) initial = earliest;
    if (initial.isAfter(latest)) initial = latest;

    final _LogAnswer? answer = await showDialog<_LogAnswer>(
      context: context,
      builder: (BuildContext _) => _ManualLogDialog(
        riderName: widget.riderName,
        today: month.today,
        initialDate: initial,
        month: month,
        loadEntry: _entryOn,
      ),
    );
    if (answer == null || !mounted) return;

    setState(() => _busy = true);
    try {
      if (answer.withdraw) {
        await widget.api.withdrawAttendanceEntry(widget.riderId, answer.date);
        _tell(t.attendanceLogRemoved);
      } else {
        await widget.api.recordAttendanceEntry(
          widget.riderId,
          date: answer.date,
          status: answer.kind!,
          clockIn: answer.clockIn,
          clockOut: answer.clockOut,
          note: answer.note,
        );
        _tell(t.attendanceLogSaved);
      }
      if (!mounted) return;
      // Show the month the entry was for, so the change is on screen.
      setState(() {
        _month = DateTime(answer.date.year, answer.date.month);
        _data = _load();
      });
    } catch (e) {
      _tell(_messageFor(e, t), bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The live entry of one day outside the month on screen, read on its own. A save replaces
  /// whatever entry a day has, so the log must know that entry before it offers to save.
  Future<ManualAttendanceEntry?> _entryOn(DateTime day) async {
    final RiderAttendance read =
        await widget.api.riderAttendanceBetween(widget.riderId, from: day, to: day);
    return read.days
        .where((AttendanceDay d) => DateUtils.isSameDay(d.date, day))
        .firstOrNull
        ?.entry;
  }

  void _tell(String message, {bool bad = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: bad ? DeliveryAccent.critical.color : null,
    ));
  }

  /// The server's own sentence where it has one: it is the side that knows why a day was refused.
  static String _messageFor(Object error, DeliveryStrings t) {
    if (error is DioException) {
      final dynamic body = error.response?.data;
      if (body is Map && body['detail'] is String) return body['detail'] as String;
    }
    return t.thatDidNotWork;
  }

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// How a calendar cell is painted for a status: the design's soft fills, derived from the accent
/// tokens rather than restated as hex.
class _CellLook {
  const _CellLook(this.fill, this.ink, {this.strong = true});

  final Color fill;
  final Color ink;
  final bool strong;

  static _CellLook of(AttendanceStatus? status) => switch (status) {
        AttendanceStatus.present ||
        AttendanceStatus.worked ||
        AttendanceStatus.extra ||
        AttendanceStatus.lateExcused =>
          _CellLook(DeliveryAccent.positive.tint, DeliveryAccent.positive.onTint),
        AttendanceStatus.late =>
          _CellLook(DeliveryAccent.caution.tint, DeliveryAccent.caution.onTint),
        AttendanceStatus.absent =>
          _CellLook(DeliveryAccent.critical.tint, DeliveryAccent.critical.onTint),
        AttendanceStatus.excused || AttendanceStatus.sick || AttendanceStatus.leave =>
          _CellLook(DeliveryAccent.info.tint, DeliveryAccent.info.onTint),
        AttendanceStatus.dayOff =>
          const _CellLook(DeliveryColors.borderFaint, DeliveryColors.muted, strong: false),
        // Future days are left unstyled, as the spec asks; so are a freelancer's idle days and a
        // scheduled day not over yet.
        AttendanceStatus.upcoming =>
          const _CellLook(Colors.transparent, DeliveryColors.faint, strong: false),
        _ => const _CellLook(Colors.transparent, DeliveryColors.ink, strong: false),
      };
}

/// The header's live badge — the design's "Beirut Live (34 Riders)" pill: a dot and the count of
/// riders the platform can see on duty now, on the positive accent's wash.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    const DeliveryAccent accent = DeliveryAccent.positive;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DeliverySpacing.md - DeliverySpacing.xs,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: accent.tint,
        border: Border.all(color: accent.color),
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: accent.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent.onTint),
          ),
        ],
      ),
    );
  }
}

/// What the Manual Attendance Log dialog decided.
class _LogAnswer {
  const _LogAnswer({
    required this.date,
    this.kind,
    this.clockIn,
    this.clockOut,
    this.note,
    this.withdraw = false,
  });

  final DateTime date;
  final AttendanceEntryKind? kind;
  final String? clockIn;
  final String? clockOut;
  final String? note;
  final bool withdraw;
}

/// The Manual Attendance Log: what the office says about one day.
///
/// Checks here what the server would refuse, so the reader is told in their own language before
/// anything is sent: a status is required, clock times only on a present day and in pairs, and a
/// day that has not happened can only be leave, sickness or an excused absence. The note is capped
/// at the server's 500 characters by the field itself.
///
/// A day outside the month on screen is read on its own first. Until that read answers nothing is
/// prefilled or offered for removal, and if it fails nothing can be saved: a save replaces the day's
/// entry, and must never replace one nobody has seen.
class _ManualLogDialog extends StatefulWidget {
  const _ManualLogDialog({
    required this.riderName,
    required this.today,
    required this.initialDate,
    required this.month,
    required this.loadEntry,
  });

  final String riderName;

  /// Today in the server's zone.
  final DateTime today;
  final DateTime initialDate;

  /// The month on screen, whose days' entries are already known.
  final RiderAttendance month;

  /// Reads the live entry of a day outside [month].
  final Future<ManualAttendanceEntry?> Function(DateTime day) loadEntry;

  @override
  State<_ManualLogDialog> createState() => _ManualLogDialogState();
}

class _ManualLogDialogState extends State<_ManualLogDialog> {
  static final RegExp _time = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

  late DateTime _date;
  AttendanceEntryKind? _kind;
  ManualAttendanceEntry? _existing;

  /// The chosen day lies outside the month on screen and is being read for its entry.
  bool _checking = false;

  /// That read failed, so the day's entry is unknown and nothing may be saved over it.
  bool _checkFailed = false;

  /// Counts the dates chosen, so a read for an earlier choice that answers late is ignored.
  int _lookup = 0;

  final TextEditingController _clockIn = TextEditingController();
  final TextEditingController _clockOut = TextEditingController();
  final TextEditingController _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _prefill(widget.initialDate);
  }

  @override
  void dispose() {
    _clockIn.dispose();
    _clockOut.dispose();
    _note.dispose();
    super.dispose();
  }

  void _prefill(DateTime day) {
    _date = DateTime(day.year, day.month, day.day);
    final int lookup = ++_lookup;
    _checkFailed = false;
    final RiderAttendance month = widget.month;
    if (!_date.isBefore(month.from) && !_date.isAfter(month.to)) {
      _checking = false;
      _fill(month.days
          .where((AttendanceDay d) => DateUtils.isSameDay(d.date, _date))
          .firstOrNull
          ?.entry);
      return;
    }
    _checking = true;
    _fill(null);
    widget.loadEntry(_date).then((ManualAttendanceEntry? entry) {
      if (!mounted || lookup != _lookup) return;
      setState(() {
        _checking = false;
        // With no entry there is nothing to prefill, and whatever was chosen meanwhile stays.
        if (entry != null) _fill(entry);
      });
    }, onError: (Object _) {
      if (!mounted || lookup != _lookup) return;
      setState(() {
        _checking = false;
        _checkFailed = true;
      });
    });
  }

  void _fill(ManualAttendanceEntry? entry) {
    _existing = entry;
    _kind = entry?.status;
    _clockIn.text = entry?.clockIn ?? '';
    _clockOut.text = entry?.clockOut ?? '';
    _note.text = entry?.note ?? '';
  }

  String? _problem(DeliveryStrings t) {
    final AttendanceEntryKind? kind = _kind;
    if (kind == null) return null;
    if (_date.isAfter(widget.today) &&
        (kind == AttendanceEntryKind.present || kind == AttendanceEntryKind.lateExcused)) {
      return t.attendanceLogFutureRule;
    }
    if (kind == AttendanceEntryKind.present) {
      final String a = _clockIn.text.trim();
      final String b = _clockOut.text.trim();
      if (a.isEmpty != b.isEmpty) return t.attendanceLogTimesRule;
      if (a.isNotEmpty && (!_time.hasMatch(a) || !_time.hasMatch(b) || a == b)) {
        return t.attendanceTimeInvalid;
      }
    }
    return null;
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      // The server's own bounds on an entry — see _RiderAttendanceScreenState._historyDays.
      firstDate: _RiderAttendanceScreenState._addDays(
          widget.today, -_RiderAttendanceScreenState._historyDays),
      lastDate: _RiderAttendanceScreenState._addDays(
          widget.today, _RiderAttendanceScreenState._leaveAheadDays),
    );
    if (picked != null) setState(() => _prefill(picked));
  }

  static String _kindLabel(DeliveryStrings t, AttendanceEntryKind kind) => switch (kind) {
        AttendanceEntryKind.present => t.attendanceKindPresent,
        AttendanceEntryKind.lateExcused => t.attendanceKindLateExcused,
        AttendanceEntryKind.absentExcused => t.attendanceKindAbsentExcused,
        AttendanceEntryKind.sick => t.attendanceKindSick,
        AttendanceEntryKind.leave => t.attendanceKindLeave,
      };

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String? problem = _problem(t);
    // Never a save while the day's own entry is unknown: it would replace an entry nobody saw.
    final bool ready = _kind != null && problem == null && !_checking && !_checkFailed;
    final bool present = _kind == AttendanceEntryKind.present;

    return AlertDialog(
      backgroundColor: DeliveryColors.white,
      surfaceTintColor: DeliveryColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
      title: Text(t.attendanceLogTitle(widget.riderName), style: ConsoleText.cardTitle),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(t.attendanceColDate, style: ConsoleText.fieldLabel),
              const SizedBox(height: 6),
              ConsoleFilterButton(
                label: MaterialLocalizations.of(context).formatFullDate(_date),
                icon: Icons.event_outlined,
                onPressed: _pickDate,
              ),
              if (_checking) ...<Widget>[
                const SizedBox(height: DeliverySpacing.sm),
                Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: DeliveryColors.brand,
                      ),
                    ),
                    const SizedBox(width: DeliverySpacing.sm),
                    Expanded(child: Text(t.attendanceLogChecking, style: ConsoleText.meta)),
                  ],
                ),
              ],
              if (_checkFailed) ...<Widget>[
                const SizedBox(height: DeliverySpacing.sm),
                Text(
                  t.attendanceLogCheckFailed,
                  style: TextStyle(fontSize: 12, color: DeliveryAccent.critical.onTint),
                ),
              ],
              const SizedBox(height: DeliverySpacing.md),
              Text(t.attendanceLogStatus, style: ConsoleText.fieldLabel),
              const SizedBox(height: 6),
              ConsoleSelect(
                label: _kind == null ? t.attendanceLogChooseStatus : _kindLabel(t, _kind!),
                icon: Icons.flag_outlined,
                options: <ConsoleOption>[
                  for (final AttendanceEntryKind k in AttendanceEntryKind.values)
                    ConsoleOption(label: _kindLabel(t, k), value: k.wire),
                ],
                onSelected: (String? wire) =>
                    setState(() => _kind = AttendanceEntryKind.fromWire(wire)),
              ),
              if (present) ...<Widget>[
                const SizedBox(height: DeliverySpacing.md),
                Row(
                  children: <Widget>[
                    Expanded(child: _field(_clockIn, t.attendanceLogClockIn, hint: 'HH:mm')),
                    const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
                    Expanded(child: _field(_clockOut, t.attendanceLogClockOut, hint: 'HH:mm')),
                  ],
                ),
                const SizedBox(height: DeliverySpacing.sm),
                // The two rules the server applies to a "present" entry, said before it is saved:
                // typed hours give way to the app's, and being present does not excuse a late.
                Text(t.attendanceLogManualNote, style: ConsoleText.meta),
                const SizedBox(height: DeliverySpacing.xs),
                Text(t.attendanceLogPresentKeepsLate, style: ConsoleText.meta),
              ],
              const SizedBox(height: DeliverySpacing.md),
              _field(_note, t.attendanceLogNote, maxLength: 500, maxLines: 3),
              if (problem != null) ...<Widget>[
                const SizedBox(height: DeliverySpacing.sm),
                Text(
                  problem,
                  style: TextStyle(fontSize: 12, color: DeliveryAccent.critical.onTint),
                ),
              ],
            ],
          ),
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
        if (_existing != null)
          ConsoleSoftButton(
            label: t.attendanceLogWithdraw,
            onPressed: () =>
                Navigator.pop(context, _LogAnswer(date: _date, withdraw: true)),
          ),
        ConsolePrimaryButton(
          label: t.attendanceLogSave,
          onPressed: ready ? _save : null,
        ),
      ],
    );
  }

  void _save() {
    final bool present = _kind == AttendanceEntryKind.present;
    final String clockIn = _clockIn.text.trim();
    final String clockOut = _clockOut.text.trim();
    final String note = _note.text.trim();
    Navigator.pop(
      context,
      _LogAnswer(
        date: _date,
        kind: _kind,
        clockIn: present && clockIn.isNotEmpty ? clockIn : null,
        clockOut: present && clockOut.isNotEmpty ? clockOut : null,
        note: note.isEmpty ? null : note,
      ),
    );
  }

  Widget _field(TextEditingController controller, String label,
      {String? hint, int? maxLength, int maxLines = 1}) {
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      borderSide: const BorderSide(color: DeliveryColors.border),
    );
    return TextField(
      controller: controller,
      maxLength: maxLength,
      maxLines: maxLines,
      style: ConsoleText.cell,
      cursorColor: DeliveryColors.brand,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: DeliveryColors.faint),
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
