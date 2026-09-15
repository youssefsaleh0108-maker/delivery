package com.delivery.accounting.service;

import java.time.LocalDate;
import java.time.ZoneId;
import java.util.Map;

/**
 * Where a pay run reads its riders' hours: order-tracking's attendance contract
 * ({@code docs/rider-attendance-contract.md}).
 *
 * <p><strong>Built to be absent.</strong> Attendance ships separately from payroll and can be down, not
 * yet deployed, or answering for somebody else. None of those may stop a company paying its riders
 * for their deliveries, and none may be mistaken for "nobody worked any hours". So this never
 * throws: every failure is an {@link AttendanceRead} that says it is unavailable and why, the run
 * computes without hours, and it says so on the page and at approval.
 *
 * <p><strong>Per rider, not per fleet.</strong> The read is one call for the whole fleet, but one
 * rider's figures that cannot be believed make that rider's hours unknown and nobody else's: the rider
 * is named at approval and everyone else is paid their hours.
 *
 * <p><strong>Moves between companies are order-tracking's to clip.</strong> Every figure it gives a
 * company is cut to the rider's time on that company's fleet (the contract's "Whose time a company
 * sees"): a rider who joined or left mid-period is listed with their own part only. So payroll pays
 * exactly the figures it is given and adds no adjustment of its own for a move.
 */
public interface RiderAttendanceSource {

    /**
     * Every rider of the caller's fleet, judged over a period of at most 31 days.
     *
     * @param bearerToken the signed-in carrier's own token: order-tracking scopes the read to their
     *                    fleet itself, and there is no service role on the endpoint
     * @param carrierRef  the company the pay run is for. An answer about any other fleet is refused
     * @param zone        the calendar the period's dates are in. An answer judged in another zone
     *                    bucketed its days differently from the deliveries, and is refused
     */
    AttendanceRead fleet(String bearerToken, String carrierRef, ZoneId zone, LocalDate from,
                         LocalDate to);

    /**
     * What came back.
     *
     * @param reason     why the whole read is unavailable, as a code the page words:
     *                   {@code NOT_DEPLOYED}, {@code REFUSED}, {@code PERIOD_REFUSED},
     *                   {@code UNREACHABLE}, {@code MISMATCH} or {@code UNREADABLE}; null when
     *                   available
     * @param riders     rider to totals when available; empty otherwise
     * @param unreadable riders the read listed whose own figures could not be believed, with why
     *                   ({@code UNREADABLE}); never in {@code riders}
     */
    record AttendanceRead(boolean available, String reason,
                          Map<String, PayslipCalculator.RiderHours> riders,
                          Map<String, String> unreadable) {

        public static AttendanceRead of(Map<String, PayslipCalculator.RiderHours> riders) {
            return of(riders, Map.of());
        }

        public static AttendanceRead of(Map<String, PayslipCalculator.RiderHours> riders,
                                        Map<String, String> unreadable) {
            return new AttendanceRead(true, null, Map.copyOf(riders), Map.copyOf(unreadable));
        }

        public static AttendanceRead unavailable(String reason) {
            return new AttendanceRead(false, reason, Map.of(), Map.of());
        }
    }
}
