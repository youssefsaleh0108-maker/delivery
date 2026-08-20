package com.delivery.notifications.api;

import java.time.Duration;
import java.time.Instant;
import java.util.List;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.notifications.domain.DeliveryRateProjection;
import com.delivery.notifications.domain.NotificationLogRepository;

/**
 * Delivery rates per channel and provider — the gate on a vendor cutover (Phase 6).
 *
 * <p>The roadmap's Phase 6 says to "monitor delivery rates before fully retiring the test-inbox
 * fallback". That sentence assumes a number that did not exist until this endpoint: the notification
 * log had every fact needed to compute it, and nothing computed it.
 *
 * <p>Grouped by provider, not just channel, because a canary ramp puts two vendors on one channel
 * at the same time and comparing them is the entire point. A channel-level success rate during a
 * ramp is an average across a vendor that works and one that might not, which is the one shape of
 * number that can hide the problem it is meant to reveal.
 */
@RestController
@RequestMapping("/api/notification-rates")
@PreAuthorize("hasRole('BACKOFFICE')")
public class DeliveryRateController {

    /** Long enough to be statistically useful, short enough to reflect a change made this morning. */
    private static final Duration DEFAULT_WINDOW = Duration.ofHours(24);
    private static final Duration MAX_WINDOW = Duration.ofDays(30);

    private final NotificationLogRepository logs;

    public DeliveryRateController(NotificationLogRepository logs) {
        this.logs = logs;
    }

    @GetMapping
    public List<ProviderRate> rates(@RequestParam(required = false) Integer windowHours) {
        Duration window = windowHours == null
                ? DEFAULT_WINDOW
                : clamp(Duration.ofHours(windowHours));

        return logs.deliveryRatesSince(Instant.now().minus(window)).stream()
                .map(row -> ProviderRate.from(row, window))
                .toList();
    }

    private static Duration clamp(Duration requested) {
        if (requested.isNegative() || requested.isZero()) {
            return DEFAULT_WINDOW;
        }
        return requested.compareTo(MAX_WINDOW) > 0 ? MAX_WINDOW : requested;
    }

    /**
     * Two different rates, kept apart on purpose.
     *
     * <p>{@code successRate} is ACCEPTANCE: what share of messages a provider took off our hands.
     * {@code deliveryRate} is ARRIVAL: what share of those a carrier confirmed reached the handset.
     * Before carrier receipts existed, only the first was measurable and the README said so; showing
     * it under the word "delivery" is the overstatement this record now avoids. A vendor can accept
     * everything and deliver very little, and that gap is the entire reason to run a pilot.
     *
     * @param successRate     0-100, or null when nothing has completed yet — deliberately null
     *                        rather than 0, because "no data" and "everything failed" must not look
     *                        alike on a screen someone is using to decide whether to keep a vendor
     * @param inFlight        still PENDING, excluded from the rate for the same reason
     * @param awaitingReceipt accepted, but no carrier receipt yet. Excluded from {@code deliveryRate}
     *                        rather than counted as a failure — most SMS traffic never produces a
     *                        receipt at all, and treating silence as non-delivery would invent a
     *                        catastrophe out of a vendor that simply is not configured to report.
     * @param deliveryRate    0-100 over CONFIRMED outcomes only, or null when no receipt has ever
     *                        arrived for this provider
     */
    public record ProviderRate(
            String channel,
            String provider,
            long total,
            long sent,
            long failed,
            long inFlight,
            Double successRate,
            Double avgSecondsToSend,
            long delivered,
            long undelivered,
            long awaitingReceipt,
            Double deliveryRate,
            Double avgSecondsToDeliver,
            int windowHours) {

        static ProviderRate from(DeliveryRateProjection row, Duration window) {
            long completed = row.getSent() + row.getFailed();
            Double rate = completed == 0
                    ? null
                    : Math.round((row.getSent() * 10000.0) / completed) / 100.0;

            long confirmed = row.getDelivered() + row.getUndelivered();
            Double delivery = confirmed == 0
                    ? null
                    : Math.round((row.getDelivered() * 10000.0) / confirmed) / 100.0;

            return new ProviderRate(
                    row.getChannel(),
                    // Null means the message never reached a provider at all. Named rather than
                    // hidden, because a pile of these is its own kind of problem.
                    row.getProvider() == null ? "(never dispatched)" : row.getProvider(),
                    row.getTotal(),
                    row.getSent(),
                    row.getFailed(),
                    row.getPending(),
                    rate,
                    round(row.getAvgSecondsToSend()),
                    row.getDelivered(),
                    row.getUndelivered(),
                    row.getAwaitingReceipt(),
                    delivery,
                    round(row.getAvgSecondsToDeliver()),
                    (int) window.toHours());
        }

        private static Double round(Double value) {
            return value == null ? null : Math.round(value * 100.0) / 100.0;
        }
    }
}
