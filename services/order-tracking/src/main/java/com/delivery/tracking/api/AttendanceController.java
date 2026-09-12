package com.delivery.tracking.api;

import java.util.List;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.security.CurrentUser;
import com.delivery.tracking.client.CarrierDirectoryClient;
import com.delivery.tracking.service.AttendancePeriod;
import com.delivery.tracking.service.AttendanceService;
import com.delivery.tracking.service.AttendanceService.AssignmentView;
import com.delivery.tracking.service.AttendanceService.ConflictException;
import com.delivery.tracking.service.AttendanceService.EntryNotFoundException;
import com.delivery.tracking.service.AttendanceService.FleetAttendance;
import com.delivery.tracking.service.AttendanceService.InvalidRequestException;
import com.delivery.tracking.service.AttendanceService.ManualEntry;
import com.delivery.tracking.service.AttendanceService.RiderAttendance;
import com.delivery.tracking.service.AttendanceService.ShiftNotFoundException;
import com.delivery.tracking.service.AttendanceService.ShiftView;
import com.delivery.tracking.service.DutySessionService.DutySessions;
import com.delivery.tracking.service.PresenceService.NoCarrierException;
import com.delivery.tracking.service.PresenceService.PresenceNotFoundException;

/**
 * Shifts, schedules, and attendance — the carrier's Riders HR, and the figures a pay run reads.
 *
 * <p>Separate from {@link RiderPresenceController} because the subject is a company's arrangement
 * with its riders rather than the riders' own duty. The read rules are nevertheless the same ones:
 * every per-rider read here is scoped exactly as {@code /duty/hours} is, through one shared check,
 * so a carrier sees its own riders and nobody else's and a foreign rider is the same 404 as an
 * unknown one.
 *
 * <p>Every write is CARRIER only, and the fleet it writes to comes from the caller's token, never
 * from the request. Backoffice may read — support needs to see what a company sees — but a
 * company's schedule and its corrections are the company's to make.
 *
 * <p>Roles are checked twice: by {@code @PreAuthorize} and again in each handler. Method security
 * is a proxy, and a refusal that holds only when the proxy is present cannot be tested standalone
 * and will one day stop holding (the same rule the accounting controllers follow).
 */
@RestController
@RequestMapping("/api/tracking")
public class AttendanceController {

    private final AttendanceService attendance;

    public AttendanceController(AttendanceService attendance) {
        this.attendance = attendance;
    }

    // ------------------------------------------------------------------------------ reading

    /**
     * One rider's duty sessions over a period — the clock-in/clock-out log. Up to 31 days, by
     * {@code month=YYYY-MM} or {@code from}/{@code to}.
     */
    @GetMapping("/riders/{riderId}/duty/sessions")
    @PreAuthorize("hasAnyRole('BACKOFFICE','CARRIER')")
    public DutySessions sessions(@PathVariable String riderId,
                                 @RequestParam(required = false) String month,
                                 @RequestParam(required = false) String from,
                                 @RequestParam(required = false) String to) {
        String caller = caller("BACKOFFICE", "CARRIER");
        return attendance.riderSessions(riderId, caller, CurrentUser.hasRole("BACKOFFICE"),
                AttendancePeriod.parse(month, from, to));
    }

    /** One rider's attendance: every day of the period judged, and the totals. */
    @GetMapping("/riders/{riderId}/attendance")
    @PreAuthorize("hasAnyRole('BACKOFFICE','CARRIER')")
    public RiderAttendance riderAttendance(@PathVariable String riderId,
                                           @RequestParam(required = false) String month,
                                           @RequestParam(required = false) String from,
                                           @RequestParam(required = false) String to) {
        String caller = caller("BACKOFFICE", "CARRIER");
        return attendance.riderAttendance(riderId, caller, CurrentUser.hasRole("BACKOFFICE"),
                AttendancePeriod.parse(month, from, to));
    }

    /**
     * A fleet's totals for a period — the pay run's one call. A carrier reads its own fleet and
     * {@code carrierId} is ignored for them; Backoffice must name one.
     */
    @GetMapping("/carrier/attendance")
    @PreAuthorize("hasAnyRole('BACKOFFICE','CARRIER')")
    public FleetAttendance fleetAttendance(@RequestParam(required = false) UUID carrierId,
                                           @RequestParam(required = false) String month,
                                           @RequestParam(required = false) String from,
                                           @RequestParam(required = false) String to) {
        String caller = caller("BACKOFFICE", "CARRIER");
        return attendance.fleetAttendance(caller, CurrentUser.hasRole("BACKOFFICE"), carrierId,
                AttendancePeriod.parse(month, from, to));
    }

    // ------------------------------------------------------------------------------- shifts

    @GetMapping("/carrier/shifts")
    @PreAuthorize("hasAnyRole('BACKOFFICE','CARRIER')")
    public List<ShiftView> shifts(@RequestParam(required = false) UUID carrierId) {
        String caller = caller("BACKOFFICE", "CARRIER");
        return attendance.shifts(caller, CurrentUser.hasRole("BACKOFFICE"), carrierId);
    }

    @PostMapping("/carrier/shifts")
    @PreAuthorize("hasRole('CARRIER')")
    public ResponseEntity<ShiftView> createShift(@RequestBody ShiftRequest request) {
        String caller = caller("CARRIER");
        ShiftRequest body = request == null ? ShiftRequest.EMPTY : request;
        return ResponseEntity.status(HttpStatus.CREATED).body(attendance.createShift(caller,
                body.name(), body.startTime(), body.endTime(), body.days(),
                body.lateGraceMinutes()));
    }

    /** Retires a shift. 409 while riders are still on it. */
    @DeleteMapping("/carrier/shifts/{shiftId}")
    @PreAuthorize("hasRole('CARRIER')")
    public ShiftView archiveShift(@PathVariable UUID shiftId) {
        return attendance.archiveShift(caller("CARRIER"), shiftId);
    }

    @GetMapping("/carrier/shift-assignments")
    @PreAuthorize("hasAnyRole('BACKOFFICE','CARRIER')")
    public List<AssignmentView> assignments(@RequestParam(required = false) UUID carrierId) {
        String caller = caller("BACKOFFICE", "CARRIER");
        return attendance.fleetAssignments(caller, CurrentUser.hasRole("BACKOFFICE"), carrierId);
    }

    /**
     * Puts one of the caller's riders on a shift from a date (today when omitted), or takes them
     * off their schedule with {@code shiftId: null}. Answers with the rider's schedule from today.
     */
    @PutMapping("/riders/{riderId}/shift-assignment")
    @PreAuthorize("hasRole('CARRIER')")
    public List<AssignmentView> assign(@PathVariable String riderId,
                                       @RequestBody(required = false) AssignmentRequest request) {
        String caller = caller("CARRIER");
        AssignmentRequest body = request == null ? new AssignmentRequest(null, null) : request;
        return attendance.assign(riderId, caller, body.shiftId(), body.effectiveFrom());
    }

    // --------------------------------------------------------------------- manual attendance

    /** Records or replaces the office's entry for one day. */
    @PutMapping("/riders/{riderId}/attendance/entries/{date}")
    @PreAuthorize("hasRole('CARRIER')")
    public ManualEntry recordEntry(@PathVariable String riderId, @PathVariable String date,
                                   @RequestBody(required = false) EntryRequest request) {
        String caller = caller("CARRIER");
        EntryRequest body = request == null ? new EntryRequest(null, null, null, null) : request;
        return attendance.recordEntry(riderId, caller, date, body.status(), body.clockIn(),
                body.clockOut(), body.note());
    }

    /** Withdraws the office's entry for one day; the day goes back to what the evidence says. */
    @DeleteMapping("/riders/{riderId}/attendance/entries/{date}")
    @PreAuthorize("hasRole('CARRIER')")
    public ResponseEntity<Void> withdrawEntry(@PathVariable String riderId,
                                              @PathVariable String date) {
        attendance.withdrawEntry(riderId, caller("CARRIER"), date);
        return ResponseEntity.noContent().build();
    }

    // ------------------------------------------------------------------------------ plumbing

    /** The caller's subject, provided they hold one of {@code roles}. */
    private static String caller(String... roles) {
        String id = CurrentUser.id().orElseThrow(NotSignedInException::new);
        for (String role : roles) {
            if (CurrentUser.hasRole(role)) {
                return id;
            }
        }
        throw new RoleRefusedException();
    }

    static final class NotSignedInException extends RuntimeException {
    }

    static final class RoleRefusedException extends RuntimeException {
    }

    @ExceptionHandler(NotSignedInException.class)
    public ProblemDetail onNotSignedIn(NotSignedInException e) {
        return TrackingProblems.of(HttpStatus.UNAUTHORIZED, "Not signed in",
                "Sign in to see attendance.");
    }

    @ExceptionHandler(RoleRefusedException.class)
    public ProblemDetail onRoleRefused(RoleRefusedException e) {
        return TrackingProblems.of(HttpStatus.FORBIDDEN, "Not allowed",
                "Your account cannot do that.");
    }

    /** Identical to the hours endpoint's body, so the two cannot be told apart by an enumerator. */
    @ExceptionHandler(PresenceNotFoundException.class)
    public ProblemDetail onNotFound(PresenceNotFoundException e) {
        return TrackingProblems.of(HttpStatus.NOT_FOUND, "Rider not found", e.getMessage());
    }

    @ExceptionHandler(NoCarrierException.class)
    public ProblemDetail onNoCarrier(NoCarrierException e) {
        return TrackingProblems.of(HttpStatus.FORBIDDEN, "No delivery company", e.getMessage());
    }

    @ExceptionHandler(CarrierDirectoryClient.DirectoryUnavailableException.class)
    public ProblemDetail onDirectoryUnavailable(
            CarrierDirectoryClient.DirectoryUnavailableException e) {
        return TrackingProblems.of(HttpStatus.SERVICE_UNAVAILABLE, "Fleet unavailable",
                "Your delivery company could not be confirmed just now. Please try again.");
    }

    @ExceptionHandler(InvalidRequestException.class)
    public ProblemDetail onInvalid(InvalidRequestException e) {
        return TrackingProblems.of(HttpStatus.BAD_REQUEST, "Invalid request", e.getMessage());
    }

    @ExceptionHandler(ShiftNotFoundException.class)
    public ProblemDetail onShiftNotFound(ShiftNotFoundException e) {
        return TrackingProblems.of(HttpStatus.NOT_FOUND, "Shift not found", e.getMessage());
    }

    @ExceptionHandler(EntryNotFoundException.class)
    public ProblemDetail onEntryNotFound(EntryNotFoundException e) {
        return TrackingProblems.of(HttpStatus.NOT_FOUND, "No entry", e.getMessage());
    }

    /** 409, with how many riders stand in the way when that is the reason. */
    @ExceptionHandler(ConflictException.class)
    public ProblemDetail onConflict(ConflictException e) {
        ProblemDetail problem = TrackingProblems.of(HttpStatus.CONFLICT, "Conflict", e.getMessage());
        problem.setProperty("riders", e.riders());
        return problem;
    }

    // ------------------------------------------------------------------------------- bodies

    /**
     * @param startTime        HH:mm in the platform day zone
     * @param endTime          HH:mm; at or before startTime means the shift ends next morning
     * @param days             weekday names, MONDAY..SUNDAY
     * @param lateGraceMinutes 0..120, default 10
     */
    public record ShiftRequest(String name, String startTime, String endTime, List<String> days,
                               Integer lateGraceMinutes) {
        static final ShiftRequest EMPTY = new ShiftRequest(null, null, null, null, null);
    }

    /**
     * @param shiftId       the shift, or null to take the rider off their schedule
     * @param effectiveFrom YYYY-MM-DD, today or later; today when omitted
     */
    public record AssignmentRequest(UUID shiftId, String effectiveFrom) {
    }

    /**
     * @param status   PRESENT, LATE_EXCUSED, ABSENT_EXCUSED, SICK or LEAVE
     * @param clockIn  HH:mm, only with PRESENT, and only together with clockOut
     * @param clockOut HH:mm; at or before clockIn means the next morning
     * @param note     up to 500 characters
     */
    public record EntryRequest(String status, String clockIn, String clockOut, String note) {
    }
}
