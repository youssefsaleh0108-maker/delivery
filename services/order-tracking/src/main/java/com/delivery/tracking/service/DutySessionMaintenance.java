package com.delivery.tracking.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

/**
 * Runs the duty-session expiry sweep on a clock.
 *
 * <p>A separate bean rather than a {@code @Scheduled} method on {@link DutySessionService} for one
 * concrete reason: the sweep must run inside the service's transaction, and a scheduled method
 * calling a sibling method on its own bean bypasses the transactional proxy. Calling across a bean
 * boundary is what makes {@code @Transactional} on {@code expireAbandoned} real.
 *
 * <p>Safe on every instance simultaneously, like {@link TrackingPartitionMaintenance}: the closes
 * are idempotent (a session already closed no longer matches the abandoned query) and the OFF_DUTY
 * declaration of an already-off rider is a no-op, so two instances racing waste a query and corrupt
 * nothing — a better trade than a distributed lock for a sweep this small.
 */
@Service
public class DutySessionMaintenance {

    private static final Logger log = LoggerFactory.getLogger(DutySessionMaintenance.class);

    private final DutySessionService dutySessions;

    public DutySessionMaintenance(DutySessionService dutySessions) {
        this.dutySessions = dutySessions;
    }

    /**
     * Every few minutes rather than nightly: the sweep bounds how long an abandoned rider stays
     * declared ON_DUTY past the expire-after threshold, and a nightly run would add up to a day to
     * that bound. The interval only sets how promptly expiry is noticed — the closed session's end
     * is the rider's last sighting regardless of when this happens to fire.
     */
    @Scheduled(fixedDelayString = "${delivery.tracking.duty-session.sweep-interval:PT15M}")
    public void onSchedule() {
        try {
            int closed = dutySessions.expireAbandoned();
            if (closed > 0) {
                log.info("Duty session expiry: closed {} abandoned shift(s) at last sighting", closed);
            }
        } catch (Exception e) {
            // Never propagate out of a scheduled method — same rule as TrackingPartitionMaintenance:
            // one bad run must not cancel every future one and leave shifts open forever.
            log.error("Duty session expiry failed; will retry on the next run", e);
        }
    }
}
