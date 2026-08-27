package com.delivery.tracking.route;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Picks the routing provider named in configuration, and complains loudly if it cannot.
 *
 * <p>The runtime switch, in the same spirit as the SMS connector's: every provider is built and
 * deployed, and which one is live is a property rather than a release. It is a startup property
 * here rather than a Backoffice setting because, unlike a messaging vendor, changing routing engine
 * mid-shift would make every customer's ETA jump — the switch is a deployment decision.
 *
 * <p>Falling back to the dev provider when the configured one is unusable is a considered choice
 * and a narrow one. It happens only when the named provider is <em>not configured at all</em> —
 * a missing key or base URL — and it is logged at WARN naming both providers. It does not happen
 * when a configured provider fails a request, because that is a transient fault and quietly
 * swapping a routed ETA for a straight-line one mid-delivery would make the number jump for a
 * reason no one could see. Either way the answer carries the name of whoever actually computed it.
 */
@Component
public class RouteProviderRegistry {

    private static final Logger log = LoggerFactory.getLogger(RouteProviderRegistry.class);

    private final Map<String, RouteProvider> byName = new LinkedHashMap<>();
    private final RouteProvider active;

    public RouteProviderRegistry(
            List<RouteProvider> providers,
            @Value("${delivery.tracking.routing.provider:HAVERSINE_DEV}") String configuredName) {

        for (RouteProvider provider : providers) {
            byName.put(provider.name(), provider);
        }

        RouteProvider requested = byName.get(configuredName);
        RouteProvider dev = byName.get(HaversineRouteProvider.NAME);

        if (requested == null) {
            log.error("Unknown routing provider '{}' configured; known providers are {}. "
                            + "Falling back to {}.",
                    configuredName, byName.keySet(), HaversineRouteProvider.NAME);
            this.active = dev;
        } else if (!requested.isConfigured()) {
            log.warn("Routing provider {} is selected but not configured (no key or base URL); "
                            + "falling back to {}. Every ETA will be a straight-line estimate and "
                            + "will say so.",
                    configuredName, HaversineRouteProvider.NAME);
            this.active = dev;
        } else {
            log.info("Routing provider: {}", configuredName);
            this.active = requested;
        }
    }

    /** The provider every ETA goes through. Never null — the dev provider always exists. */
    public RouteProvider active() {
        return active;
    }

    /** Every provider on the classpath and whether it could serve traffic, for the health page. */
    public Map<String, Boolean> configurationStatus() {
        Map<String, Boolean> status = new LinkedHashMap<>();
        byName.forEach((name, provider) -> status.put(name, provider.isConfigured()));
        return status;
    }
}
