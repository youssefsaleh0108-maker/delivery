# Rider attendance contract (order-tracking)

What a payroll module — the accounting-service pay run is the first consumer — and the carrier
console can rely on when they read attendance: shift schedules, the Manual Attendance Log, and
each rider's days judged against them. The code is
`services/order-tracking/.../api/AttendanceController.java` and `service/AttendanceService.java`;
the tables are `V15__shift_schedules_and_attendance.sql`.

Errors are RFC-7807 ProblemDetail (`title`, `detail`, `status`, `correlationId`), as everywhere in
order-tracking.

## The rules that shape every figure

- **One zone.** Every date, every `HH:mm` and every `...Local` string is in the platform day zone,
  `delivery.tracking.duty-session.day-zone` = `Asia/Beirut` (a region id, so the summer UTC+3 and
  winter UTC+2 clocks are both right). It is echoed as `zone` on every read. Instants (`...At`,
  `clockIn`, `clockOut`) are ISO-8601 UTC; print the `...Local` strings, never the browser's
  conversion of an instant.
- **Evidence and claims are kept apart.** `workedSeconds` is duty-session time the rider app
  recorded, credited only up to the rider's last sighting. `manualSeconds` is what the office typed
  in the Manual Attendance Log, and only on a day with no evidence. They are never summed by this
  service: whether manual hours are paid is payroll's rule.
- **No schedule, no verdict.** A rider with no shift assignment covering a day is a freelancer on
  that day: `WORKED` or `NO_DUTY`, never late, never absent, never overtime.
- **Seconds are exact, hours are display.** Every `...Hours` field is the seconds over 3600 at two
  decimals, HALF_UP. Do arithmetic on seconds.
- **Nothing is backfilled.** Duty history starts at V13 and is deleted after
  `delivery.tracking.duty-event-retention-days` (400). A period starting before that is refused
  (400) rather than judged, because every scheduled day in it would read as an absence.

## Who may call

| Endpoint | BACKOFFICE | CARRIER | anyone else |
|---|---|---|---|
| every `GET` below | any rider / any named fleet | only riders whose `rider_presence.carrier_id` is the caller's own fleet | 403 (401 unsigned) |
| every write | 403 | own fleet only | 403 (401 unsigned) |

- A carrier's fleet always comes from its token (the membership row, or Order Manager's directory
  when this service has not learned it yet), never from the request. A `carrierId` a carrier
  passes is ignored.
- A rider on another fleet and a rider that does not exist are the **identical 404**
  (`"title": "Rider not found"`). A shift id from another fleet is `404 "Shift not found"`.
- A CARRIER account attached to no company: 403 `"No delivery company"`. Order Manager unreachable
  with no cached answer: 503 `"Fleet unavailable"`.
- Service-to-service: forward the signed-in user's token (the way order-tracking's
  `CarrierDirectoryClient` does), so the carrier's own scoping applies to the pay run. There is no
  service role on these endpoints.

## Periods

Every read takes **exactly one** of `month=YYYY-MM` or `from=YYYY-MM-DD&to=YYYY-MM-DD` (inclusive
dates in the zone). At most 31 days; both or neither, a malformed value, `to` before `from`, or a
longer window is 400 before anything is read. Ask for a quarter as three calls.

## GET /api/tracking/carrier/attendance — the pay run's read

Query: the period, plus `carrierId` (UUID) — required for BACKOFFICE, ignored for CARRIER.

```json
{ "carrierId": "uuid", "zone": "Asia/Beirut", "from": "2026-10-01", "to": "2026-10-31",
  "asOf": "2026-11-03T07:00:00Z",
  "riders": [ { "riderId": "kc-sub", "hasSchedule": true, "totals": { …AttendanceTotals… } } ] }
```

`riders` is every rider **currently** linked to the fleet (`rider_presence.carrier_id`), sorted by
id, each computed exactly as the per-rider read below — the two always agree. `asOf` is the one
instant every rider's figures were computed at; the figures are not final, so keep it with what you
pay (see *When a period's figures are final*).

### AttendanceTotals

| Field | Type | Meaning |
|---|---|---|
| `scheduledDays` | int | days in the period with a shift, including days still to come |
| `daysWorked` | int | days up to today with credited duty time or a manual `PRESENT` entry |
| `absences` | int | unexcused absences only (`ABSENT` days) |
| `lates` | int | unexcused lates only (`LATE` days) |
| `excusedLates` | int | `LATE_EXCUSED` days |
| `excusedAbsences` | int | `EXCUSED` days |
| `sickDays` | int | `SICK` days (planned future ones included) |
| `leaveDays` | int | `LEAVE` days (planned future ones included) |
| `workedSeconds` | long | evidence: credited duty-session time of every session attributed to the period |
| `manualSeconds` | long | claims: hours typed on manual `PRESENT` entries for days with no evidence |
| `scheduledSeconds` | long | the real length of every scheduled shift in the period (an hour more or less on the nights the clocks change) |
| `overtimeSeconds` | long | evidence only: per scheduled day, credited time beyond that day's shift length — or all of it when no credited session touched the shift; all credited time on a scheduled day off; never anything for a freelancer day |
| `workedHours`, `overtimeHours` | decimal | display only |

## GET /api/tracking/riders/{riderId}/attendance

Query: the period. `riderId` is the rider's Keycloak subject. BACKOFFICE reads the rider against
their current fleet's schedule (a rider on no fleet has none).

```json
{ "riderId": "kc-sub", "carrierId": "uuid|null", "zone": "Asia/Beirut",
  "from": "2026-10-01", "to": "2026-10-31", "today": "2026-10-12",
  "asOf": "2026-10-12T17:00:00Z", "hasSchedule": true,
  "days": [ …one AttendanceDay per date, in order… ], "totals": { …AttendanceTotals… } }
```

`hasSchedule` false means no assignment touches the period: a client shows time on duty only, with
no late or absent legend.

### AttendanceDay

| Field | Meaning |
|---|---|
| `date` | the day |
| `status` | the verdict after any manual entry (table below) |
| `derivedStatus` | what the evidence and the schedule alone say — what an entry corrected |
| `scheduled` | `{shiftId, name, startTime, endTime ("HH:mm"), overnight, startsAt, endsAt, scheduledSeconds, lateGraceMinutes}`, or null on a day off / with no schedule |
| `clockIn`, `clockInLocal` | first credited session's start (instant, and `yyyy-MM-ddTHH:mm` in the zone); null when none |
| `clockOut`, `clockOutLocal` | last credited session's close; null when none or still open. The local date is the next day after a night shift |
| `clockOutReason` | `RIDER`, `BACKOFFICE`, or `EXPIRED` — closed by the platform at the rider's last sighting, not by a tap |
| `onShiftNow` | a session attributed to the day is still open |
| `worked` | counts toward `daysWorked` |
| `workedSeconds`, `workedHours` | evidence for the day |
| `manualSeconds` | typed hours, only on a day with no evidence |
| `lateBySeconds` | seconds from shift start to arrival, in whole minutes, 0 when early; null when unscheduled or no credited session touched the shift |
| `overtimeSeconds` | as in the totals |
| `sessions` | the duty sessions attributed to the day (the `SessionView` shape below), including zero-credit ones |
| `entry` | the live manual entry `{id, date, status, clockIn, clockOut, manualSeconds, note, recordedBy, recordedAt}`, or null |

### Status

| Status | When |
|---|---|
| `PRESENT` | scheduled; a credited session touches the shift window, and the first one began no more than `lateGraceMinutes` after the shift start (exactly at the grace is on time) |
| `LATE` | scheduled; the first credited session touching the shift window began later than start + grace |
| `ABSENT` | scheduled; no credited session touches the shift window; the shift is over |
| `PENDING` | scheduled; no credited session has touched the shift window yet; the shift is not over — not an absence |
| `DAY_OFF` | an assigned rider's non-shift day, not worked |
| `EXTRA` | an assigned rider's non-shift day, worked (all of it is overtime) |
| `WORKED` / `NO_DUTY` | no schedule that day (a freelancer): worked / did not |
| `UPCOMING` | after `today` |
| `LATE_EXCUSED` | a `LATE` day with a `LATE_EXCUSED` entry |
| `EXCUSED`, `SICK`, `LEAVE` | an `ABSENT_EXCUSED`, `SICK` or `LEAVE` entry (they win whatever the evidence says; the evidence stays in `workedSeconds`) |

**Arrival.** Only a credited session that overlaps the shift window is an arrival, and it is
judged to the minute: arrival is truncated to the minute before it is compared (shifts are stored in
whole minutes, and the log prints minutes), so 08:10:40 against ten minutes' grace is on time and
`lateBySeconds` is always whole minutes. Duty that never touches the window — two hours at dawn
before an 08:00 start, going on duty at 19:00 after an 18:00 end, a day's work before a 23:00 night
shift — is not an arrival: the day is `PENDING` until the window ends and `ABSENT` after, all of
that time is `overtimeSeconds`, and the day still has `worked` true because it has credited time
(so such a day counts in both `daysWorked` and `absences`).

A manual `PRESENT` entry turns `ABSENT`/`PENDING` into `PRESENT`, `DAY_OFF` into `EXTRA` and
`NO_DUTY` into `WORKED`; it does not excuse a `LATE`. Treat an unknown status as neutral.

**Which day a session belongs to.** A session is attributed whole to one day, so a period's total
never counts an hour twice: the earliest of the day before, the day of and the day after its start
whose scheduled shift window it overlaps, otherwise the date it started on. A 22:00–06:00 shift is
the day it starts on, and arriving at 00:10 is late for it. This deliberately differs from
`/duty/hours`, which splits sessions at every midnight.

## GET /api/tracking/riders/{riderId}/duty/sessions

Query: the period. The clock-in/clock-out rows, whole (a session crossing an edge of the period is
listed once, not clipped).

```json
{ "riderId": "kc-sub", "zone": "Asia/Beirut", "from": "2026-10-01", "to": "2026-10-31",
  "sessions": [ { "id": "uuid", "startedAt": "instant", "endedAt": "instant|null",
                  "endReason": "RIDER|BACKOFFICE|EXPIRED|null", "open": false,
                  "countedUntil": "instant", "countedSeconds": 36000, "countedHours": 10.00,
                  "startedAtLocal": "2026-10-05T08:05", "countedUntilLocal": "2026-10-05T18:05" } ] }
```

`countedUntil` is the close for a closed session, now for an open one whose rider is still pinging,
and the last sighting for one whose rider went quiet — the same rule as `/duty/hours`.

## Shifts and schedules (CARRIER writes; BACKOFFICE may read with `carrierId`)

- `GET /api/tracking/carrier/shifts` → `[ShiftView]`:
  `{id, name, startTime, endTime, overnight, days: ["MONDAY",…], lateGraceMinutes, archived, riders}`
  where `riders` is how many are on it today or starting later. Archived shifts are included and
  marked.
- `POST /api/tracking/carrier/shifts` `{name ≤80, startTime "HH:mm", endTime "HH:mm", days:
  ["MONDAY",…] (≥1), lateGraceMinutes 0..120 (default 10)}` → **201** `ShiftView`. An end at or
  before the start ends the next morning; equal times are refused. **The hours can never be
  edited**: re-timing would re-judge days already paid. Add a new shift and move riders onto it.
- `DELETE /api/tracking/carrier/shifts/{shiftId}` → `ShiftView` (archived). **409** with
  `"riders": n` while anybody is on it or about to start it.
- `GET /api/tracking/carrier/shift-assignments` → `[{riderId, shiftId, shiftName, effectiveFrom,
  effectiveTo}]` running today or starting later (`effectiveTo` inclusive, null = open-ended).
- `PUT /api/tracking/riders/{riderId}/shift-assignment` `{shiftId: uuid|null, effectiveFrom:
  "YYYY-MM-DD"|omitted}` → the rider's assignments from today. Omitted date = today in the zone;
  never before today (400), at most 90 days ahead. **A change asked for today starts tomorrow once
  today is under way** — once the window of the rider's shift today, or of the shift they are
  moving to, has begun — so assigning an 08:00–18:00 shift at 19:00 does not make today an absence,
  and moving or freeing a rider does not rewrite or erase a late or an absence today already
  earned. The answer's rows show the date the change took. The running assignment is closed the
  day before the change; one that had not started yet is replaced; a row that covered a window that
  has begun is always ended, never deleted. `shiftId: null` makes the rider a freelancer from that
  date. Assigning the shift a rider is already on is a no-op. A retired shift is 409.

A past day — and today, once under way — is always judged against the assignment that covered it.

## Manual Attendance Log (CARRIER, own fleet)

- `PUT /api/tracking/riders/{riderId}/attendance/entries/{YYYY-MM-DD}` `{status: PRESENT |
  LATE_EXCUSED | ABSENT_EXCUSED | SICK | LEAVE, clockIn?: "HH:mm", clockOut?: "HH:mm", note?: ≤500}`
  → the entry. Times only on `PRESENT`, both or neither, not equal (an out at or before the in is
  the next morning). A future day may only be `ABSENT_EXCUSED`, `SICK` or `LEAVE`, at most 180 days
  ahead; a day older than the retention is refused. Replacing an entry revokes the old row.
- `DELETE` the same path → 204; the day goes back to what the evidence says. 404 when there is no
  live entry.

Entries are append-only (`revoked_at`/`revoked_by`), so who changed a day, and from what, stays
answerable. Duty sessions are never edited by anything here.

## When a period's figures are final

Never, on their own. Every read is computed from the duty evidence and the Manual Attendance Log as
they stand at that moment, echoed as `asOf` (an ISO-8601 instant) on the fleet read and the rider
read, and a period's figures can still change after the period is over:

- **A night shift runs past the period's end.** A rider who arrives at 00:10 on 1 November for a
  31 October 22:00 shift is attributed to 31 October, so October's `workedSeconds`, `lates` and
  `absences` move after October ends (until that window closes, 31 October reads `PENDING`).
- **Open sessions keep counting** until the rider closes them or the platform expires them, so a
  day's `workedSeconds` and `overtimeSeconds` can grow after the period ends.
- **The Manual Attendance Log reaches back.** Entries can be recorded, replaced or withdrawn for any
  day inside the duty history (`duty-event-retention-days`, 400 days), which changes that day's
  `status`, `daysWorked`, `manualSeconds`, and the late, absence, excused, sick and leave counts.

Schedules are the one input that cannot move a past day (see the shift-assignment rules). So a pay
run must **snapshot** what it pays: store the totals it used together with the read's `asOf`, never
recompute a period it has already paid, and settle a later difference as an adjustment in a later
run — re-reading the paid period and comparing it with the snapshot is how that difference is found.

## Known limits a pay run must allow for

- **Fleet linkage.** A carrier reads a rider only once `rider_presence.carrier_id` names its fleet,
  which today happens when the rider carries an order for it. A newly hired rider who has not is a
  404 on every read and is missing from the fleet read.
- **Duty sessions carry no fleet.** A rider who moved companies inside the period brings the
  sessions they worked before the move into the new fleet's `workedSeconds` (on days with no
  assignment there, as `WORKED`). The fleet read lists only riders linked to the fleet now, so a
  rider who left mid-period is absent from the old fleet's read. Settle a leaver's final period
  before the move, or read by range up to their last day.
- **Open sessions** are credited to the last sighting; the figure only ever grows or stays.
