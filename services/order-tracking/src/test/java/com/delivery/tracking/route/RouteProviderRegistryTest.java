package com.delivery.tracking.route;

import java.time.Duration;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Which provider ends up computing ETAs, and what happens when the configured one cannot.
 *
 * <p>The guarantee being protected is that the platform never goes quiet because a routing account
 * was not bought, and never pretends a straight line came from a routing engine. Falling back is
 * allowed; falling back silently is not, which is why the provider name is asserted rather than
 * just the fact that something answered.
 */
class RouteProviderRegistryTest {

    private final HaversineRouteProvider dev = new HaversineRouteProvider(20);

    /** Stands in for a real vendor: named, and configured only when it has been given credentials. */
    private static RouteProvider vendor(String name, boolean configured) {
        return new RouteProvider() {
            @Override
            public String name() {
                return name;
            }

            @Override
            public boolean isConfigured() {
                return configured;
            }

            @Override
            public Optional<RouteEstimate> estimate(GeoPoint from, GeoPoint to) {
                return Optional.of(new RouteEstimate(1234, Duration.ofMinutes(5), name));
            }
        };
    }

    @Test
    @DisplayName("the configured provider is used when it has what it needs")
    void uses_the_configured_provider() {
        RouteProviderRegistry registry = new RouteProviderRegistry(
                List.of(dev, vendor("OSRM", true)), "OSRM");

        assertThat(registry.active().name()).isEqualTo("OSRM");
    }

    /**
     * The case the owner is actually in: a real provider named in config with no key behind it.
     * Answering nothing would take every ETA off every screen; answering with the dev estimator and
     * saying so keeps the feature working and keeps it honest.
     */
    @Test
    @DisplayName("a provider named but never given a key falls back to the dev estimator")
    void falls_back_when_the_configured_provider_has_no_credentials() {
        RouteProviderRegistry registry = new RouteProviderRegistry(
                List.of(dev, vendor("MAPBOX", false)), "MAPBOX");

        assertThat(registry.active().name()).isEqualTo(HaversineRouteProvider.NAME);
    }

    @Test
    @DisplayName("a typo in the provider name does not leave the service with no provider at all")
    void falls_back_when_the_configured_name_is_unknown() {
        RouteProviderRegistry registry = new RouteProviderRegistry(List.of(dev), "GOOGLE_MAPS");

        assertThat(registry.active().name()).isEqualTo(HaversineRouteProvider.NAME);
    }

    /**
     * Whatever answered, the estimate carries that provider's name — so a caller can always tell a
     * routed number from a straight-line one without having to ask what the config says.
     */
    @Test
    @DisplayName("an estimate is always labelled with whoever actually computed it")
    void labels_estimates_with_the_provider_that_produced_them() {
        RouteProviderRegistry fellBack = new RouteProviderRegistry(
                List.of(dev, vendor("OSRM", false)), "OSRM");

        assertThat(fellBack.active().estimate(new GeoPoint(0, 0), new GeoPoint(0, 1)))
                .hasValueSatisfying(route ->
                        assertThat(route.provider()).isEqualTo(HaversineRouteProvider.NAME));
    }

    @Test
    @DisplayName("every provider on the classpath reports whether it could serve traffic")
    void reports_which_providers_are_configured() {
        RouteProviderRegistry registry = new RouteProviderRegistry(
                List.of(dev, vendor("OSRM", false), vendor("MAPBOX", true)), "MAPBOX");

        assertThat(registry.configurationStatus())
                .containsEntry(HaversineRouteProvider.NAME, true)
                .containsEntry("OSRM", false)
                .containsEntry("MAPBOX", true);
    }
}
