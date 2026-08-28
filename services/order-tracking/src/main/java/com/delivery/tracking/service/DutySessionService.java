package com.delivery.tracking.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.SortedMap;
import java.util.TreeMap;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.tracking.domain.CarrierMembership;
import com.delivery.tracking.domain.CarrierMembershipRepository;
import com.delivery.tracking.domain.DutySession;
import com.delivery.tracking.domain.DutySessionRepository;
import com.delivery.tracking.domain.DutyState;
import com.delivery.tracking.domain.RiderDutyEvent;
import com.delivery.tracking.domain.RiderPresence;
import com.delivery.tracking.domain.RiderPresenceRepository;
import com.delivery.tracking.service.PresenceService.NoCarrierException;
import com.delivery.tracking.service.PresenceService.PresenceNotFoundException;

/**
 * Hours online, computed from duty sessions — the number behind the rider stat tile and the
 * console's hours column.
 *
 * <p>{@link PresenceService} answers "is this rider working now"; this class answers "how long have
 * they worked", summed from {@code duty_sessions} rows that the duty transition path writes. Two
 * rules keep the number honest:
 *
 * <ul>
 *   <li><strong>Only evidence is counted.</strong> A closed session contributes exactly its
 *       interval. An open session contributes up to now only while the rider is still effectively
 *       present; a rider who went quiet contributes up to their last sighting, which is the same
 *       instant the expiry sweep will eventually close the session at — so the live tile and the
 *       eventual record agree instead of the number shrinking overnight.</li>
 *   <li><strong>Nothing is invented.</strong> History starts when the table did. A rider with no
 *       sessions gets an empty list, and a day with no on-duty time simply does not appear —
 *       zeros the client can render are the client's to draw, not this service's to assert.</li>
 * </ul>
 *
 * <h2>Day boundaries</h2>
 *
 * <p>A session is split at midnight in a single configured zone
 * ({@code delivery.tracking.duty-session.day-zone}), so a 23:00–01:00 shift is one hour on each
 * day rather than two hours on whichever day the query ran. One zone for the whole platform rather
 * than per-caller, because payroll and the consoles must agree on what "Tuesday" means; the zone is
 * echoed on every response so no client has to guess.
 */
@Service
public class DutySessionService {

    private final DutySessionRepository sessions;
    private final RiderPresenceRepository presenceRows;
    private final CarrierMembershipRepository memberships;
    private final PresenceService presence;
    private final ZoneId dayZone;
    private final Duration presenceWindow;
    private final Duration expireAfter;

    public DutySessionService(DutySessionRepository sessions,
                              RiderPresenceRepository presenceRows,
                              CarrierMembershipRepository memberships,
                              PresenceService presence,
                              @Value("${delivery.tracking.duty-session.day-zone:UTC}") String dayZone,
                              @Value("${delivery.tracking.presence.ttl:120s}") Duration presenceWindow,
                              @Value("${delivery.tracking.duty-session.expire-after:4h}") Duration expireAfter) {
        this.sessions = sessions;
        this.presenceRows = presenceRows;
        this.memberships = memberships;
        this.presence = presence;
        this.dayZone = ZoneId.of(dayZone);
        this.presenceWindow = presenceWindow;
        this.expireAfter = expireAfter;
    }

    // -----------------------------------------------------------------------------------------
    // Reading
    // -----------------------------------------------------------------------------------------

    /** A rider's own hours. No authorisation question: the id comes from their token. */
    @Transactional(readOnly = true)
    public HoursOnline ownHours(String riderId, int days) {
        return aggregate(riderId, days, Instant.now());
    }

    /**
     * One rider's hours, for a console.
     *
     * <p>Scoped exactly as the roster is: a carrier's fleet comes from their own membership row and
     * never from the request, and the rider must belong to that fleet by the same linkage the
     * roster filters on — {@code rider_presence.carrier_id}. A carrier asking about anybody else's
     * rider, or about an id that does not exist, gets the same not-found, so this endpoint cannot
     * be used to enumerate riders any more than the location one can.
     *
     * <p>Backoffice may ask about any rider, but an id nobody has ever heard of is still a 404
     * rather than an empty history — "no such rider" and "a rider who has not worked yet" are
     * different answers and conflating them would make every typo look like a lazy new hire.
     */
    @Transactional(readOnly = true)
    public HoursOnline riderHours(String riderId, String callerId, boolean isBackoffice, int days) {
        if (isBackoffice) {
            if (!presenceRows.existsById(riderId)) {
                throw new PresenceNotFoundException(riderId);
            }
        } else {
            UUID scope = memberships.findById(callerId)
                    .map(CarrierMembership::getCarrierId)
                    .orElseThrow(() -> new NoCarrierException(
                            "You are not a member of any delivery company"));
            boolean owned = presenceRows.findById(riderId)
                    .map(row -> scope.equals(row.getCarrierId()))
                    .orElse(false);
            if (!owned) {
                throw new PresenceNotFoundException(riderId);
            }
        }
        return aggregate(riderId, days, Instant.now());
    }

    /**
     * The sum. Package-private overload with an explicit clock instant so tests can put a session
     * either side of a midnight they control.
     */
    HoursOnline aggregate(String riderId, int days, Instant now) {
        LocalDate today = LocalDate.ofInstant(now, dayZone);
        LocalDate from = today.minusDays(days - 1L);
        Instant windowStart = from.atStartOfDay(dayZone).toInstant();

        List<DutySession> overlapping = sessions.findOverlapping(riderId, windowStart, now);
        if (overlapping.isEmpty()) {
            // Nothing has happened. An empty list, not a row of zeros — zeros are a statement.
            return new HoursOnline(riderId, dayZone.getId(), from, today, List.of());
        }

        Instant lastSeen = presenceRows.findById(riderId)
                .map(RiderPresence::getLastSeenAt)
                .orElse(null);

        // date -> [secondsOnline, sessionsTouchingTheDay]
        SortedMap<LocalDate, long[]> perDay = new TreeMap<>();
        for (DutySession session : overlapping) {
            Instant start = max(session.getStartedAt(), windowStart);
            Instant end = min(effectiveEnd(session, lastSeen, now), now);

            // Walk the session across midnights, crediting each slice to its own day. A 23:00–01:00
            // shift is one hour today and one tomorrow, never two on either.
            Instant cursor = start;
            while (cursor.isBefore(end)) {
                LocalDate day = LocalDate.ofInstant(cursor, dayZone);
                Instant dayEnd = day.plusDays(1).atStartOfDay(dayZone).toInstant();
                Instant sliceEnd = min(end, dayEnd);

                long[] agg = perDay.computeIfAbsent(day, d -> new long[2]);
                agg[0] += Duration.between(cursor, sliceEnd).getSeconds();
                agg[1] += 1;
                cursor = sliceEnd;
            }
        }

        List<DayOnline> daysOnline = perDay.entrySet().stream()
                .filter(e -> e.getValue()[0] > 0)
                .map(e -> DayOnline.of(e.getKey(), e.getValue()[0], (int) e.getValue()[1]))
                .toList();
        return new HoursOnline(riderId, dayZone.getId(), from, today, daysOnline);
    }

    /**
     * Where an open session's counting stops.
     *
     * <p>To now while the rider is still effectively present, because the shift is genuinely
     * running. Once they have gone quiet, to their last sighting — the exact instant
     * {@link #expireAbandoned} will close the session at if they never return, so the live number
     * never exceeds what the record will eventually say.
     */
    private Instant effectiveEnd(DutySession session, Instant lastSeen, Instant now) {
        if (!session.isOpen()) {
            return session.getEndedAt();
        }
        boolean present = lastSeen != null && !lastSeen.isBefore(now.minus(presenceWindow));
        if (present) {
            return now;
        }
        // Quiet. Count only what there is evidence for; a sighting from before the shift, or no
        // sighting at all, is evidence for nothing.
        return lastSeen == null ? session.getStartedAt() : max(lastSeen, session.getStartedAt());
    }

    // -----------------------------------------------------------------------------------------
    // Expiry
    // -----------------------------------------------------------------------------------------

    /**
     * Closes the shifts of riders the platform has given up hearing from.
     *
     * <p>A rider whose phone died, or who walked away without tapping "go offline", leaves a
     * session open forever and stays declared ON_DUTY. After
     * {@code delivery.tracking.duty-session.expire-after} of silence this gives up on their behalf:
     * the session is closed <em>at their last sighting</em>, not at the moment the sweep noticed —
     * the hours in between are hours nobody can show the rider was working, and crediting them
     * would turn a forgotten tap into paid time. A session with no sighting at all closes at its
     * own start, length zero, which is what a shift with no evidence behind it is worth.
     *
     * <p>The rider is then declared OFF_DUTY through the ordinary declare path with the SYSTEM
     * source, which writes the audit event and refreshes the cache exactly as a human declaration
     * would. The event carries the sweep's own time, deliberately different from the session's end:
     * the audit log records when the platform acted, the session records how long the rider worked,
     * and pretending the platform acted earlier than it did would falsify the one to flatter the
     * other. Declaring OFF_DUTY is also what re-arms the rider's next ON_DUTY tap to open a fresh
     * session and to read as a real transition.
     *
     * <p>The threshold is hours where the presence window is seconds, on purpose. STALE riders
     * staying visible on the roster is a feature — a dispatcher wants to see the rider who went
     * quiet — so expiry only fires long after anyone watching has had every chance to notice.
     *
     * @return how many shifts were closed
     */
    @Transactional
    public int expireAbandoned() {
        return expireAbandoned(Instant.now());
    }

    int expireAbandoned(Instant now) {
        Instant cutoff = now.minus(expireAfter);
        List<DutySession> abandoned = sessions.findAbandonedBefore(cutoff);
        for (DutySession session : abandoned) {
            Instant lastSeen = presenceRows.findById(session.getRiderId())
                    .map(RiderPresence::getLastSeenAt)
                    .orElse(null);
            session.close(lastSeen == null ? session.getStartedAt() : lastSeen,
                    DutySession.EndReason.EXPIRED);
            sessions.save(session);
            presence.declare(session.getRiderId(), DutyState.OFF_DUTY,
                    RiderDutyEvent.Source.SYSTEM);
        }
        return abandoned.size();
    }

    private static Instant min(Instant a, Instant b) {
        return a.isBefore(b) ? a : b;
    }

    private static Instant max(Instant a, Instant b) {
        return a.isAfter(b) ? a : b;
    }

    // -----------------------------------------------------------------------------------------
    // Types
    // -----------------------------------------------------------------------------------------

    /**
     * Hours online per day over the requested window.
     *
     * @param zone the zone whose midnights split the days — echoed so no client has to guess
     * @param from first day of the window (inclusive)
     * @param to   last day of the window, i.e. today in {@code zone} (inclusive)
     * @param days only the days with on-duty time; empty when there is none, never fabricated zeros
     */
    public record HoursOnline(
            String riderId,
            String zone,
            LocalDate from,
            LocalDate to,
            List<DayOnline> days) {
    }

    /**
     * One day's total.
     *
     * @param secondsOnline the exact figure, what anything doing arithmetic should use
     * @param hoursOnline   the same figure over 3600 at two decimals, what a tile displays —
     *                      derived here so every screen rounds the same way
     * @param sessions      how many distinct shifts touched this day
     */
    public record DayOnline(
            LocalDate date,
            long secondsOnline,
            BigDecimal hoursOnline,
            int sessions) {

        static DayOnline of(LocalDate date, long secondsOnline, int sessions) {
            return new DayOnline(date, secondsOnline,
                    BigDecimal.valueOf(secondsOnline)
                            .divide(BigDecimal.valueOf(3600), 2, RoundingMode.HALF_UP),
                    sessions);
        }
    }
}
