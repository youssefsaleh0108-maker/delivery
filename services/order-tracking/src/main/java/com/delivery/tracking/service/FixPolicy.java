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
 * trail a dispute is settled from keeps it for the retention window. Until this class existed the
 * only questions asked of a ping were who sent it and whether the order was still running, so a fix
 * that was two kilometres wide, ten minutes old, or on another continent was recorded exactly like a
 * good one — which is how a simulated rider in London came to be "on the way" to a door in Beirut.
 *
 * <p>The questions, in this order. Each is answered with a refusal rather than a repair, except
 * the fifth, which only decides that there is nothing new to record:
 *
 * <ol>
 *   <li><b>Does it say when it was taken?</b> The fix time is required. Without it a report cannot
 *       be judged for age at all — which is how a drained queue, or the old simulator's London
 *       walk, would get in stamped as "now".</li>
 *   <li><b>Is it precise enough?</b> A fix whose own reported radius is wider than
 *       {@code max-accuracy-m} cannot place a rider on a street; it is what an "approximate
 *       location" permission or a cell-tower fix produces. A report with no accuracy at all is
 *       accepted, as it always was.</li>
 *   <li><b>Is it from now?</b> The fix time is the phone's own clock, so a little skew is allowed
 *       ({@code max-clock-skew}) and a fix inside it is clamped to the moment it arrived, so that
 *       nothing is ever recorded in the future. Beyond it the report is refused: a future time
 *       would keep a rider "present" after their phone died. A fix older than
 *       {@code max-fix-age} is refused too — a queued report drained after a tunnel, or a cached
 *       last-known position, says where the rider was, not where they are.</li>
 *   <li><b>Is it where the platform works?</b> With {@code service-area.enabled}, a fix outside the
 *       configured box (Lebanon and a margin) is refused. Nothing a rider does honestly happens
 *       there, and what does report from there is a fake: the old simulator's London, an
 *       emulator's Mountain View, a spoofing app's default. Off in dev only, where emulators are
 *       the riders.</li>
 *   <li><b>Is it new?</b> Against the last fix accepted for this rider: one dated at or before it
 *       is ignored — the same fix sent twice, or one overtaken by a later one, would walk the rider
 *       backwards — and so is one under {@code min-interval} after it. The app never sends that
 *       often; a client that does is not given a write per report on the busiest table in the
 *       platform, nor a push per report to every watcher.</li>
 *   <li><b>Could the rider have got there?</b> The distance from the last fix may not exceed
 *       {@code max-speed-kmh} for the time between them, plus both fixes' own radii and a fixed
 *       slack. That catches the classic GPS glitch — a multipath jump of kilometres for one
 *       reading — and a stale or spoofed origin.</li>
 * </ol>
 *
 * <p>An ignored fix is not a refusal: the report was fine and simply adds nothing, so the handset
 * is answered as if it had been recorded and is never told to change anything.
 *
 * <p><b>Which last fix counts.</b> Only one inside the service area, and — for the jump check — only
 * while it is younger than {@code jump-window}. A last fix outside the box is not a position this
 * platform could have recorded honestly: it is what an old app build's London walk, or a dev
 * emulator, left behind. Compared against it, a rider's first real fix after an upgrade was refused
 * as a jump for five minutes. The window does the same for a bad fix inside the box that got
 * through: the worst case is a rider refused for the length of the window, after which the next fix
 * starts fresh. Refused reports never move the anchor, so a run of refusals ages it out rather than
 * extending it.
 *
 * <p>Nothing here is a security boundary — a phone that lies consistently, inside Lebanon, passes
 * every check, and who may report at all is decided before this class is asked. It is data hygiene
 * for honest handsets, which is where nearly all bad positions come from, plus the cheapest spoofs.
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

    /**
     * Lebanon's extent (33.05–34.69 N, 35.10–36.63 E) with about fifteen kilometres of margin on
     * every side, rounded outwards: 0.135° of latitude, and 0.164° of longitude at the northern
     * edge, where a degree of longitude is shortest.
     */
    public static final ServiceArea LEBANON = new ServiceArea(32.91, 34.83, 34.93, 36.80);

    private final float maxAccuracyM;
    private final Duration maxFixAge;
    private final Duration maxClockSkew;
    private final double maxSpeedMps;
    private final Duration jumpWindow;
    private final Duration minInterval;
    private final ServiceArea serviceArea;
    private final boolean serviceAreaEnforced;

    public FixPolicy(@Value("${delivery.tracking.ping.max-accuracy-m:100}") float maxAccuracyM,
                     @Value("${delivery.tracking.ping.max-fix-age:60s}") Duration maxFixAge,
                     @Value("${delivery.tracking.ping.max-clock-skew:30s}") Duration maxClockSkew,
                     @Value("${delivery.tracking.ping.max-speed-kmh:150}") double maxSpeedKmh,
                     @Value("${delivery.tracking.ping.jump-window:5m}") Duration jumpWindow,
                     @Value("${delivery.tracking.ping.min-interval:5s}") Duration minInterval,
                     @Value("${delivery.tracking.ping.service-area.enabled:true}")
                     boolean serviceAreaEnforced,
                     @Value("${delivery.tracking.ping.service-area.min-lat:32.91}") double minLat,
                     @Value("${delivery.tracking.ping.service-area.max-lat:34.83}") double maxLat,
                     @Value("${delivery.tracking.ping.service-area.min-lng:34.93}") double minLng,
                     @Value("${delivery.tracking.ping.service-area.max-lng:36.80}") double maxLng) {
        this.maxAccuracyM = maxAccuracyM;
        this.maxFixAge = maxFixAge;
        this.maxClockSkew = maxClockSkew;
        this.maxSpeedMps = maxSpeedKmh / 3.6;
        this.jumpWindow = jumpWindow;
        this.minInterval = minInterval;
        this.serviceAreaEnforced = serviceAreaEnforced;
        this.serviceArea = new ServiceArea(minLat, maxLat, minLng, maxLng);
    }

    /** The shipped values, service area enforced, for tests and anything built outside Spring. */
    public static FixPolicy defaults() {
        return defaults(true);
    }

    /** The shipped values, with the service area enforced or not — dev's one difference. */
    public static FixPolicy defaults(boolean serviceAreaEnforced) {
        return new FixPolicy(100f, Duration.ofSeconds(60), Duration.ofSeconds(30), 150,
                Duration.ofMinutes(5), Duration.ofSeconds(5), serviceAreaEnforced,
                LEBANON.minLat(), LEBANON.maxLat(), LEBANON.minLng(), LEBANON.maxLng());
    }

    /**
     * Decides whether {@code fix} may be recorded, and when it was.
     *
     * @param previous the last fix accepted for this rider, or null when there is none to compare
     * @param now      the moment the report arrived
     * @return the instant the fix is recorded at — the phone's fix time, never later than
     *         {@code now} — or why there is nothing new to record
     * @throws FixRejectedException naming which question the fix failed
     */
    public Admission admit(Fix fix, Previous previous, Instant now) {
        if (fix.takenAt() == null) {
            throw new FixRejectedException(Reason.FIX_TIME_MISSING);
        }
        if (fix.accuracyM() != null && fix.accuracyM() > maxAccuracyM) {
            throw new FixRejectedException(Reason.ACCURACY_TOO_LOW);
        }

        Instant at = timeOf(fix.takenAt(), now);

        if (serviceAreaEnforced && !serviceArea.contains(fix.lat(), fix.lng())) {
            throw new FixRejectedException(Reason.OUTSIDE_SERVICE_AREA);
        }

        Previous anchor = previous != null && serviceArea.contains(previous.lat(), previous.lng())
                ? previous
                : null;
        if (anchor == null) {
            return Admission.recordAt(at);
        }

        if (!at.isAfter(anchor.at())) {
            return Admission.skip(at, Skip.NOT_NEWER);
        }
        Duration gap = Duration.between(anchor.at(), at);
        if (gap.compareTo(minInterval) < 0) {
            return Admission.skip(at, Skip.TOO_SOON);
        }
        if (gap.compareTo(jumpWindow) <= 0) {
            double metres = HaversineRouteProvider.distanceMetres(
                    new GeoPoint(anchor.lat(), anchor.lng()),
                    new GeoPoint(fix.lat(), fix.lng()));
            double reachable = maxSpeedMps * (gap.toMillis() / 1000.0)
                    + radius(anchor.accuracyM()) + radius(fix.accuracyM()) + JUMP_SLACK_M;
            if (metres > reachable) {
                throw new FixRejectedException(Reason.IMPLAUSIBLE_JUMP);
            }
        }
        return Admission.recordAt(at);
    }

    /** Whether a point lies inside the configured service area, enforced or not. */
    public boolean inServiceArea(double lat, double lng) {
        return serviceArea.contains(lat, lng);
    }

    private Instant timeOf(Instant takenAt, Instant now) {
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
     * accepted. The generous reading: a handset must not be refused for movement that is only
     * implausible if its fixes were sharper than anybody claimed.
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

    /** A latitude/longitude box, edges included. */
    public record ServiceArea(double minLat, double maxLat, double minLng, double maxLng) {

        public boolean contains(double lat, double lng) {
            return lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng;
        }
    }

    /**
     * What becomes of a fix that was not refused.
     *
     * @param at   when it was taken, as it would be recorded
     * @param skip why it is not recorded after all, or null when it is
     */
    public record Admission(Instant at, Skip skip) {

        static Admission recordAt(Instant at) {
            return new Admission(at, null);
        }

        static Admission skip(Instant at, Skip why) {
            return new Admission(at, why);
        }

        /** True when the fix is to be recorded; false when it adds nothing new. */
        public boolean recorded() {
            return skip == null;
        }
    }

    /** Why a believable fix is still not recorded. Never sent to the handset: it answers 2xx. */
    public enum Skip {
        /** Dated at or before the last fix accepted for this rider. */
        NOT_NEWER,
        /** Less than the minimum interval after the last fix accepted for this rider. */
        TOO_SOON
    }

    /**
     * Why a report was refused, sent to the handset as {@code reason} on a 422.
     *
     * <p>The app acts on two of them: {@link #FIX_IN_FUTURE} and {@link #FIX_TOO_OLD} arriving
     * again and again mean the phone's clock is wrong, which only the rider can fix, so the app
     * tells them. Any other reason arriving again and again is shown as no usable fix.
     */
    public enum Reason {
        FIX_TIME_MISSING("This location does not say when it was taken, so it cannot be judged and "
                + "was not recorded. Update the app."),
        ACCURACY_TOO_LOW("This location is too imprecise to place the rider on a street, so it "
                + "was not recorded."),
        FIX_IN_FUTURE("This location is dated in the future. Check that the phone's date and time "
                + "are set automatically."),
        FIX_TOO_OLD("This location is too old to say where the rider is now, so it was not "
                + "recorded."),
        OUTSIDE_SERVICE_AREA("This location is outside the area YouDrop delivers in, so it was not "
                + "recorded."),
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
