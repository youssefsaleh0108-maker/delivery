package com.delivery.platform.notifications;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Holds which provider a connector is currently using, and refreshes it when Connector Settings
 * says it changed (Section 8).
 *
 * <p>Two mechanisms on purpose. The {@code connector.settings_changed} event makes a switch take
 * effect within a second; the TTL below is the safety net for a connector that was restarting when
 * the event went out, or that missed it because the bus hiccuped. Without the TTL a missed event
 * would leave a connector on a stale provider indefinitely, which for SMS means silently sending
 * through a vendor the business thought it had turned off.
 *
 * <p>The short in-memory cache is also what Section 8 requires so a Connector Settings outage
 * cannot take a connector down: the last known-good value keeps being used.
 */
public class ActiveProviderRegistry {

    private static final Logger log = LoggerFactory.getLogger(ActiveProviderRegistry.class);

    private final String connectorType;
    private final Duration ttl;
    private final AtomicReference<Snapshot> current = new AtomicReference<>();

    public ActiveProviderRegistry(String connectorType, String defaultProvider, Duration ttl) {
        this.connectorType = connectorType;
        this.ttl = ttl;
        // Starts on the safe default rather than null, so a connector is usable before it has ever
        // heard from Connector Settings. Timestamped at the epoch, i.e. already stale: the default
        // is a fallback we have never confirmed, so the first refresh must actually run rather than
        // sit out a whole TTL. Otherwise a connector that booted while a switch was in flight would
        // keep sending through the old vendor for minutes.
        this.current.set(new Snapshot(defaultProvider, Map.of(), Instant.EPOCH));
    }

    public String activeProvider() {
        return current.get().provider();
    }

    public Map<String, String> config() {
        return current.get().config();
    }

    public boolean isStale() {
        return Instant.now().isAfter(current.get().loadedAt().plus(ttl));
    }

    /** Called from the bus listener when Connector Settings announces a change. */
    public void apply(String provider, Map<String, String> config) {
        Snapshot previous = current.getAndSet(new Snapshot(provider, config, Instant.now()));
        if (!previous.provider().equals(provider)) {
            // Worth an INFO: this line is the audit trail's counterpart on the connector side, and
            // the first thing to look for when "why did that go through Twilio" comes up.
            log.info("{} connector switched provider {} -> {}",
                    connectorType, previous.provider(), provider);
        }
    }

    private record Snapshot(String provider, Map<String, String> config, Instant loadedAt) {
    }
}
