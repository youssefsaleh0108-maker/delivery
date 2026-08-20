package com.delivery.platform.notifications;

import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.zip.CRC32;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Sends a slice of traffic to a second provider, so a vendor cutover can be a ramp rather than a
 * switch.
 *
 * <p>Phase 6 asks to "monitor delivery rates before fully retiring the test-inbox fallback", which
 * only means anything if both providers can be live at once. An all-or-nothing flip gives you one
 * data point — everything worked, or everything is broken and customers noticed first.
 *
 * <p>Configured through the two keys below on the connector's non-secret config, so it is the same
 * Backoffice screen and the same audit trail as any other provider change:
 *
 * <pre>
 *   canaryProvider   = TWILIO
 *   canaryPercentage = 5
 * </pre>
 *
 * <p><strong>The routing is deterministic on the idempotency key, and that is not a detail.</strong>
 * A retried send must reach the same vendor as the original attempt. Route it randomly and a retry
 * can land on the other provider, which has never seen that idempotency key — so it accepts the
 * message as new and the customer gets two texts, both billed. Hashing the notification id means a
 * given message belongs to one provider for its whole life, however many times it is retried.
 *
 * <p>CRC32 rather than a cryptographic hash: this is bucketing, not security, and it needs to be
 * cheap on every send and stable across restarts and across connector instances. Two instances must
 * make the same choice for the same message, which rules out anything seeded per process.
 */
public final class CanaryRouter {

    private static final Logger log = LoggerFactory.getLogger(CanaryRouter.class);

    public static final String CANARY_PROVIDER = "canaryProvider";
    public static final String CANARY_PERCENTAGE = "canaryPercentage";

    private CanaryRouter() {
    }

    /**
     * Picks the provider for one message.
     *
     * @param primary the connector's active provider
     * @param config  the connector's non-secret config, which may name a canary
     * @param key     the idempotency key — the same message must always resolve the same way
     */
    public static String route(String primary, Map<String, String> config, String key) {
        if (config == null || key == null) {
            return primary;
        }

        String canary = config.get(CANARY_PROVIDER);
        if (canary == null || canary.isBlank() || canary.equals(primary)) {
            return primary;
        }

        int percentage = percentage(config);
        if (percentage <= 0) {
            return primary;
        }
        if (percentage >= 100) {
            // A 100% canary is just a provider switch, and expressing it this way rather than
            // refusing it lets a ramp finish without a separate final step.
            return canary;
        }

        return bucketOf(key) < percentage ? canary : primary;
    }

    /** 0-99, stable for a given key. */
    public static int bucketOf(String key) {
        CRC32 crc = new CRC32();
        crc.update(key.getBytes(StandardCharsets.UTF_8));
        return (int) (crc.getValue() % 100);
    }

    private static int percentage(Map<String, String> config) {
        String raw = config.get(CANARY_PERCENTAGE);
        if (raw == null || raw.isBlank()) {
            return 0;
        }
        try {
            return Math.max(0, Math.min(100, Integer.parseInt(raw.trim())));
        } catch (NumberFormatException e) {
            // Fail closed onto the primary. A typo in a percentage must not silently send every
            // message through an unproven vendor.
            log.warn("Ignoring unreadable {} '{}'; staying on the primary provider",
                    CANARY_PERCENTAGE, raw);
            return 0;
        }
    }
}
