package com.delivery.tracking.service;

import java.time.Duration;
import java.time.Instant;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.delivery.tracking.route.GeoPoint;
import com.delivery.tracking.route.HaversineRouteProvider;

/**
 * Whether a rider's position report is believable enough to record, and at what time.
 *
 * <p>Everything downstream of a ping trusts it completely: the customer's map draws the rider
 * there, the ETA measures from there, dispatch's roster places the rider there, and the breadcrumb
 * trail a dispute is settled from keeps it forever. Until this class existed the only questions
 * asked of a ping were who sent it and whether the order was still running, so a fix that was
 * two kilometres wide, ten minutes old, or on another continent was recorded exactly like a good
 * one — which is how a simulated rider in London came to be "on the way" to a door in Beirut.
 *
 * <p>Three questions, in this order, each answered with a refusal rather than a repair:
 *
 * <ol>
 *   <li><b>Is it precise enough?</b> A fix whose own reported radius is wider than
 *       {@code max-accuracy-m} cannot place a rider on a street; it is what an "approximate
 *       location" permission or a cell-tower fix produces. Drawing it would move the rider's pin
 *       by blocks. A report with no accuracy at all is accepted, as it always was — older app
 *       builds never sent one, and refusing them would be a contract change rather than a
 *       validation.</li>
 *   <li><b>Is it from now?</b> The fix time is the phone's own clock, so a little skew is allowed
 *       ({@code max-clock-skew}) and a fix inside it is clamped to the moment it arrived, so that
 *       nothing is ever recorded in the future. Beyond it the report is refused: a future time
 *       would keep a rider "present" after their phone died. A fix older than
 *       {@code max-fix-age} is refused too — a queued report drained after a tunnel, or a cached
 *       last-known position, says where the rider was, not where they are. A report without a
 *       time is stamped on arrival, which is what every report was before the field existed.</li>
 *   <li><b>Could the rider have got there?</b> Against the last fix accepted for this rider, the
 *       distance may not exceed {@code max-speed-kmh} for the time between them, plus both fixes'
 *       own radii and a fixed slack. That catches the classic GPS glitch — a multipath jump of
 *       kilometres for one reading — and a stale or spoofed origin. A fix older than the last one
 *       accepted is refused outright: it would walk the rider backwards on every map.</li>
 * </ol>
 *
 * <p><b>Why the jump check forgets.</b> The previous fix only counts while it is younger than
 * {@code jump-window}. Without that, one bad fix that got through — or the last point of the old
 * simulator, in London — would become an anchor no honest fix could ever get far enough away from
 * in time, and the rider would be refused for hours. With it, the worst case is a rider refused
 * for the length of the window, after which the next fix is taken as a fresh start. Refused
 * reports never move the anchor, so a run of refusals ages it out rather than extending it.
 *
 * <p>Nothing here is a security boundary — a phone that lies consistently passes every check,
 * and who may report at all is decided before this class is asked. It is data hygiene for honest
 * handsets, which is where nearly all bad positions come from.
 */
@Component
public class FixPolicy {

    /**
     * Tolerance on top of both fixes' own radii. The fused provider is occasionally over-confident
     * about its accuracy for a reading or two, and a refusal costs a customer their live dot for
     * the next ten seconds; fifty metres is well below anything a customer's map could mistake for
     * a different street, and far below the kilometre-scale jumps this check exists for.
     */
    static final double JUMP_SLACK_M = 50;

    private final float maxAccuracyM;
    private final Duration maxFixAge;
    private final Duration maxClockSkew;
    private final double maxSpeedMps;
    private final Duration jumpWindow;

    public FixPolicy(@Value("${delivery.tracking.ping.max-accuracy-m:100}") float maxAccuracyM,
                     @Value("${delivery.tracking.ping.max-fix-age:60s}") Duration maxFixAge,
                     @Value("${delivery.tracking.ping.max-clock-skew:30s}") Duration maxClockSkew,
                     @Value("${delivery.tracking.ping.max-speed-kmh:150}") double maxSpeedKmh,
                     @Value("${delivery.tracking.ping.jump-window:5m}") Duration jumpWindow) {
        this.maxAccuracyM = maxAccuracyM;
        this.maxFixAge = maxFixAge;
        this.maxClockSkew = maxClockSkew;
        this.maxSpeedMps = maxSpeedKmh / 3.6;
        this.jumpWindow = jumpWindow;
    }

    /** The shipped values, for tests and anything built outside Spring. */
    public static FixPolicy defaults() {
        return new FixPolicy(100f, Duration.ofSeconds(60), Duration.ofSeconds(30), 150,
                Duration.ofMinutes(5));
    }

    /**
     * Decides whether {@code fix} may be recorded, and when it was.
     *
     * @param previous the last fix accepted for this rider, or null when there is none to compare
     * @param now      the moment the report arrived
     * @return the instant to record the fix at — the phone's fix time, never later than {@code now}
     * @throws FixRejectedException naming which question the fix failed
     */
    public Instant admit(Fix fix, Previous previous, Instant now) {
        if (fix.accuracyM() != null && fix.accuracyM() > maxAccuracyM) {
            throw new FixRejectedException(Reason.ACCURACY_TOO_LOW);
        }

        Instant at = timeOf(fix, now);

        if (previous != null) {
            if (at.isBefore(previous.at())) {
                throw new FixRejectedException(Reason.FIX_OUT_OF_ORDER);
            }
            Duration gap = Duration.between(previous.at(), at);
            if (gap.compareTo(jumpWindow) <= 0) {
                double metres = HaversineRouteProvider.distanceMetres(
                        new GeoPoint(previous.lat(), previous.lng()),
                        new GeoPoint(fix.lat(), fix.lng()));
                double reachable = maxSpeedMps * (gap.toMillis() / 1000.0)
                        + radius(previous.accuracyM()) + radius(fix.accuracyM()) + JUMP_SLACK_M;
                if (metres > reachable) {
                    throw new FixRejectedException(Reason.IMPLAUSIBLE_JUMP);
                }
            }
        }
        return at;
    }

    private Instant timeOf(Fix fix, Instant now) {
        Instant takenAt = fix.takenAt();
        if (takenAt == null) {
            return now;
        }
        if (takenAt.isAfter(now.plus(maxClockSkew))) {
            throw new FixRejectedException(Reason.FIX_IN_FUTURE);
        }
        if (takenAt.isBefore(now.minus(maxFixAge))) {
            throw new FixRejectedException(Reason.FIX_TOO_OLD);
        }
        // Inside the skew allowance but still ahead of us: the phone's clock is a little fast.
        // Recorded as "now" so that no stored time is ever in the future.
        return takenAt.isAfter(now) ? now : takenAt;
    }

    /**
     * A fix that did not say how precise it was is given the widest radius that would have been
     * accepted. The generous reading: an older app build must not be refused for movement that is
     * only implausible if its fixes were sharper than anybody claimed.
     */
    private double radius(Float accuracyM) {
        return accuracyM == null ? maxAccuracyM : accuracyM;
    }

    /**
     * The last fix accepted for a rider — what a new one is compared with.
     *
     * @param at when it was taken, as recorded
     */
    public record Previous(double lat, double lng, Float accuracyM, Instant at) {

        /** Empty (null) unless there is a whole fix to compare with: both axes and a time. */
        public static Previous of(Double lat, Double lng, Float accuracyM, Instant at) {
            if (lat == null || lng == null || at == null) {
                return null;
            }
            return new Previous(lat, lng, accuracyM, at);
        }
    }

    /**
     * Why a report was refused, sent to the handset as {@code reason} on a 422.
     *
     * <p>The app acts on two of them: {@link #FIX_IN_FUTURE} and {@link #FIX_TOO_OLD} arriving
     * again and again mean the phone's clock is wrong, which only the rider can fix, so the app
     * tells them. The rest are one-off readings the next fix replaces.
     */
    public enum Reason {
        ACCURACY_TOO_LOW("This location is too imprecise to place the rider on a street, so it "
                + "was not recorded."),
        FIX_IN_FUTURE("This location is dated in the future. Check that the phone's date and time "
                + "are set automatically."),
        FIX_TOO_OLD("This location is too old to say where the rider is now, so it was not "
                + "recorded."),
        FIX_OUT_OF_ORDER("A newer location from this rider has already been recorded."),
        IMPLAUSIBLE_JUMP("This location is further from the last one than the rider could have "
                + "travelled in the time between them, so it was not recorded.");

        private final String explanation;

        Reason(String explanation) {
            this.explanation = explanation;
        }

        public String explanation() {
            return explanation;
        }
    }

    /**
     * A report that failed one of the questions above.
     *
     * <p>The message is fixed text per reason. Nothing from the request is echoed into it: it is
     * rendered by clients, and a coordinate or a time the caller made up is untrusted text.
     */
    public static class FixRejectedException extends RuntimeException {

        private final Reason reason;

        public FixRejectedException(Reason reason) {
            super(reason.explanation());
            this.reason = reason;
        }

        public Reason reason() {
            return reason;
        }
    }
}
