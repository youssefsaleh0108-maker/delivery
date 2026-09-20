package com.delivery.tracking.route;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.time.Duration;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Which paths are kept, for how long, and which never are.
 *
 * <p>A counting provider stands in for the routing host, so "served from the cache" is proved by
 * the host not being asked again rather than by the answer merely looking the same.
 */
@DisplayName("keeping route paths")
class RoutePathsTest {

    private static final GeoPoint SHOP = new GeoPoint(33.8938, 35.5018);
    private static final GeoPoint DOOR = new GeoPoint(33.8981, 35.5214);
    private static final GeoPoint RIDER = new GeoPoint(33.8900, 35.4950);

    /** A routing host that answers every question and counts them. */
    static final class CountingProvider implements RouteProvider {
        final String name;
        final boolean cacheable;
        final List<List<GeoPoint>> asked = new ArrayList<>();
        boolean answers = true;

        CountingProvider(String name, boolean cacheable) {
            this.name = name;
            this.cacheable = cacheable;
        }

        @Override
        public String name() {
            return name;
        }

        @Override
        public boolean isConfigured() {
            return true;
        }

        @Override
        public Optional<RouteEstimate> estimate(GeoPoint from, GeoPoint to) {
            return Optional.of(new RouteEstimate(100, Duration.ofSeconds(10), name));
        }

        @Override
        public Optional<RoutePath> path(List<GeoPoint> stops) {
            asked.add(stops);
            return answers
                    ? Optional.of(new RoutePath(1000d * asked.size(), Duration.ofSeconds(60), name,
                            "road-" + asked.size()))
                    : Optional.empty();
        }

        @Override
        public PathGeometry pathGeometry() {
            return PathGeometry.ROAD;
        }

        @Override
        public boolean mayCachePaths() {
            return cacheable;
        }
    }

    private final Map<String, String> store = new HashMap<>();
    private final Map<String, Duration> ttls = new HashMap<>();
    private StringRedisTemplate redis;

    @BeforeEach
    @SuppressWarnings("unchecked")
    void setUp() {
        redis = mock(StringRedisTemplate.class);
        ValueOperations<String, String> values = mock(ValueOperations.class);
        when(redis.opsForValue()).thenReturn(values);
        when(values.get(anyString())).thenAnswer(call -> store.get(call.<String>getArgument(0)));
        Mockito.doAnswer(call -> {
            store.put(call.getArgument(0), call.getArgument(1));
            ttls.put(call.getArgument(0), call.getArgument(2));
            return null;
        }).when(values).set(anyString(), anyString(), any(Duration.class));
    }

    private RoutePaths pathsWith(RouteProvider provider) {
        RouteProviderRegistry registry = new RouteProviderRegistry(
                List.of(new HaversineRouteProvider(18), provider), provider.name());
        return new RoutePaths(registry, redis, new ObjectMapper(), Duration.ofHours(24), 150,
                Duration.ofSeconds(60));
    }

    @Test
    @DisplayName("a planned path is routed once and then served for a day")
    void a_planned_path_is_a_cache_hit_the_second_time() {
        CountingProvider osrm = new CountingProvider("OSRM", true);
        RoutePaths paths = pathsWith(osrm);

        RoutePath first = paths.planned(List.of(SHOP, DOOR)).orElseThrow();
        RoutePath second = paths.planned(List.of(SHOP, DOOR)).orElseThrow();

        assertThat(osrm.asked).hasSize(1);
        assertThat(second).isEqualTo(first);
        assertThat(ttls.values()).containsExactly(Duration.ofHours(24));
        // Keyed by provider and by the stops at five decimal places.
        assertThat(store.keySet()).containsExactly(
                RoutePaths.PLANNED_PREFIX + "OSRM:33.89380,35.50180;33.89810,35.52140");
    }

    /**
     * A routing host that cannot answer — down, timed out, no route — leaves a line to draw all
     * the same: straight segments between the same stops, named by the provider that produced
     * them so the answer says what it is. Nothing of it is kept, so the host is asked again on the
     * next refresh rather than a day later.
     */
    @Test
    @DisplayName("falls back to straight segments, and keeps neither the silence nor the fallback")
    void no_answer_falls_back_to_straight_lines() {
        CountingProvider osrm = new CountingProvider("OSRM", true);
        osrm.answers = false;
        RoutePaths paths = pathsWith(osrm);

        RoutePath fallback = paths.planned(List.of(SHOP, DOOR)).orElseThrow();

        assertThat(fallback.polyline6()).as("a road nobody returned is never drawn").isNull();
        assertThat(fallback.geometry()).isEqualTo(PathGeometry.STRAIGHT);
        assertThat(fallback.provider()).isEqualTo(HaversineRouteProvider.NAME);
        assertThat(fallback.distanceMetres())
                .isEqualTo(HaversineRouteProvider.distanceMetres(SHOP, DOOR));
        assertThat(store).isEmpty();

        osrm.answers = true;
        assertThat(paths.planned(List.of(SHOP, DOOR)).orElseThrow().polyline6()).isNotNull();
        assertThat(osrm.asked).hasSize(2);
    }

    @Test
    @DisplayName("a rider's leg falls back the same way, and is not kept either")
    void a_rider_leg_falls_back_to_straight_lines() {
        CountingProvider osrm = new CountingProvider("OSRM", true);
        osrm.answers = false;
        RoutePaths paths = pathsWith(osrm);

        RoutePath fallback = paths.riderLeg(RIDER, List.of(SHOP, DOOR)).orElseThrow();

        assertThat(fallback.polyline6()).isNull();
        assertThat(fallback.provider()).isEqualTo(HaversineRouteProvider.NAME);
        assertThat(store).isEmpty();
    }

    /** The dev provider is already straight lines: there is nothing to fall back to. */
    @Test
    @DisplayName("the straight-line provider answering nothing draws nothing")
    void the_dev_provider_has_no_fallback() {
        RoutePaths paths = pathsWith(new HaversineRouteProvider(18));

        assertThat(paths.planned(List.of(SHOP))).isEmpty();
    }

    @Test
    @DisplayName("a rider's leg is reused while they stay within 150 m, and re-routed beyond")
    void a_rider_leg_is_rerouted_only_after_the_rider_moves() {
        CountingProvider osrm = new CountingProvider("OSRM", true);
        RoutePaths paths = pathsWith(osrm);

        RoutePath first = paths.riderLeg(RIDER, List.of(SHOP, DOOR)).orElseThrow();
        // About 55 m north: the same road for the customer's purposes.
        RoutePath nearby = paths.riderLeg(new GeoPoint(33.8905, 35.4950), List.of(SHOP, DOOR))
                .orElseThrow();
        assertThat(nearby).isEqualTo(first);
        assertThat(osrm.asked).hasSize(1);
        assertThat(osrm.asked.get(0)).containsExactly(RIDER, SHOP, DOOR);
        // The time half of the rule is the entry's own expiry.
        assertThat(ttls.values()).containsExactly(Duration.ofSeconds(60));

        // About 330 m on: routed again, from where the rider now is.
        GeoPoint moved = new GeoPoint(33.8930, 35.4950);
        RoutePath rerouted = paths.riderLeg(moved, List.of(SHOP, DOOR)).orElseThrow();
        assertThat(osrm.asked).hasSize(2);
        assertThat(osrm.asked.get(1)).containsExactly(moved, SHOP, DOOR);
        assertThat(rerouted).isNotEqualTo(first);
    }

    /** Mapbox's terms forbid storing its results: every drawing is its own request. */
    @Test
    @DisplayName("Mapbox is never kept, planned or not")
    void mapbox_is_never_cached() {
        CountingProvider mapbox = new CountingProvider("MAPBOX", false);
        RoutePaths paths = pathsWith(mapbox);

        paths.planned(List.of(SHOP, DOOR));
        paths.planned(List.of(SHOP, DOOR));
        paths.riderLeg(RIDER, List.of(SHOP, DOOR));
        paths.riderLeg(RIDER, List.of(SHOP, DOOR));

        assertThat(mapbox.asked).hasSize(4);
        verifyNoInteractions(redis);
    }

    @Test
    @DisplayName("the dev provider is asked directly: arithmetic costs less than a round trip")
    void the_dev_provider_is_not_cached() {
        RouteProviderRegistry registry = new RouteProviderRegistry(
                List.of(new HaversineRouteProvider(18)), HaversineRouteProvider.NAME);
        RoutePaths paths = new RoutePaths(registry, redis, new ObjectMapper(), Duration.ofHours(24),
                150, Duration.ofSeconds(60));

        RoutePath path = paths.planned(List.of(SHOP, DOOR)).orElseThrow();

        assertThat(path.geometry()).isEqualTo(PathGeometry.STRAIGHT);
        assertThat(paths.geometry()).isEqualTo(PathGeometry.STRAIGHT);
        assertThat(paths.providerName()).isEqualTo(HaversineRouteProvider.NAME);
        verifyNoInteractions(redis);
    }

    /** A path routed by one provider is never served while another is live. */
    @Test
    @DisplayName("an entry that names another provider is not served")
    void providers_are_never_mixed() throws Exception {
        CountingProvider osrm = new CountingProvider("OSRM", true);
        RoutePaths paths = pathsWith(osrm);
        String key = RoutePaths.PLANNED_PREFIX + "OSRM:" + RoutePaths.keyOf(List.of(SHOP, DOOR));
        store.put(key, new ObjectMapper().writeValueAsString(
                new RoutePaths.Stored(5, 1, "MAPBOX", "somebody-elses-road", null, null)));

        RoutePath path = paths.planned(List.of(SHOP, DOOR)).orElseThrow();

        assertThat(path.provider()).isEqualTo("OSRM");
        assertThat(osrm.asked).hasSize(1);
    }

    /** Redis is an optimisation here, never a dependency. */
    @Test
    @DisplayName("with Redis unreachable the provider is simply asked")
    void redis_down_routes_directly() {
        when(redis.opsForValue()).thenThrow(new IllegalStateException("redis down"));
        CountingProvider osrm = new CountingProvider("OSRM", true);
        RoutePaths paths = pathsWith(osrm);

        assertThat(paths.planned(List.of(SHOP, DOOR))).isPresent();
        assertThat(paths.riderLeg(RIDER, List.of(DOOR))).isPresent();
        assertThat(osrm.asked).hasSize(2);
    }
}
