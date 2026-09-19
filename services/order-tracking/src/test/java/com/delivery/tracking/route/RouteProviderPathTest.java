package com.delivery.tracking.route;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import java.time.Duration;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

/**
 * The path each provider draws through a list of stops.
 *
 * <p>The rule under test is the map's honesty: a straight-line provider says it has no geometry, a
 * routing provider answers with the road or not at all, and nothing ever degrades a missing road
 * into a line nobody returned.
 */
@DisplayName("a provider's path through several stops")
class RouteProviderPathTest {

    // Beirut: a shop in Hamra, a second shop in Achrafieh, and a door in Mar Mikhael.
    private static final GeoPoint SHOP_A = new GeoPoint(33.8938, 35.5018);
    private static final GeoPoint SHOP_B = new GeoPoint(33.8869, 35.5131);
    private static final GeoPoint DOOR = new GeoPoint(33.8981, 35.5214);

    private static final String OSRM_OK = """
            {"code":"Ok","routes":[{"distance":4210.4,"duration":611.6,
             "geometry":"_c`|~AyzuoeAoAbCsEhK"}],"waypoints":[]}
            """;

    @Nested
    @DisplayName("the dev straight-line provider")
    class Haversine {

        private final HaversineRouteProvider provider = new HaversineRouteProvider(60);

        /** The path's numbers and an ETA over the same stops must be the same numbers. */
        @Test
        @DisplayName("sums its straight legs exactly as its estimates do, and draws no geometry")
        void sums_the_legs_without_geometry() {
            RoutePath path = provider.path(List.of(SHOP_A, SHOP_B, DOOR)).orElseThrow();

            RouteEstimate first = provider.estimate(SHOP_A, SHOP_B).orElseThrow();
            RouteEstimate second = provider.estimate(SHOP_B, DOOR).orElseThrow();
            assertThat(path.distanceMetres())
                    .isCloseTo(first.distanceMetres() + second.distanceMetres(), within(0.001));
            assertThat(path.travelTime()).isEqualTo(first.travelTime().plus(second.travelTime()));
            assertThat(path.polyline6()).isNull();
            assertThat(path.geometry()).isEqualTo(PathGeometry.STRAIGHT);
            assertThat(path.provider()).isEqualTo(HaversineRouteProvider.NAME);
            assertThat(provider.pathGeometry()).isEqualTo(PathGeometry.STRAIGHT);
            assertThat(provider.mayCachePaths()).isFalse();
        }

        @Test
        @DisplayName("has no path through a single point")
        void one_point_is_not_a_path() {
            assertThat(provider.path(List.of(DOOR))).isEmpty();
        }
    }

    @Nested
    @DisplayName("OSRM")
    class Osrm {

        private final RestClient.Builder builder = RestClient.builder();
        private final MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();

        private OsrmRouteProvider provider() {
            return new OsrmRouteProvider(builder, "http://osrm.test", "driving");
        }

        /**
         * lng,lat per stop, in visiting order, separators intact, and the geometry parameters that
         * make the answer drawable.
         */
        @Test
        @DisplayName("asks for lng,lat stops in order, simplified polyline6 geometry")
        void asks_for_the_route_in_osrm_order() {
            server.expect(requestTo("http://osrm.test/route/v1/driving/"
                            + "35.501800,33.893800;35.513100,33.886900;35.521400,33.898100"
                            + "?overview=simplified&geometries=polyline6"))
                    .andExpect(method(HttpMethod.GET))
                    .andRespond(withSuccess(OSRM_OK, MediaType.APPLICATION_JSON));

            RoutePath path = provider().path(List.of(SHOP_A, SHOP_B, DOOR)).orElseThrow();

            server.verify();
            assertThat(path.distanceMetres()).isEqualTo(4210.4);
            assertThat(path.travelTime()).isEqualTo(Duration.ofSeconds(612));
            assertThat(path.polyline6()).isEqualTo("_c`|~AyzuoeAoAbCsEhK");
            assertThat(path.geometry()).isEqualTo(PathGeometry.ROAD);
            assertThat(path.provider()).isEqualTo(OsrmRouteProvider.NAME);
        }

        /** Never a road the provider did not return. */
        @Test
        @DisplayName("a route without geometry is no path, not a straight line")
        void no_geometry_no_path() {
            server.expect(requestTo(org.hamcrest.Matchers.startsWith("http://osrm.test/route/v1/")))
                    .andRespond(withSuccess("{\"code\":\"Ok\",\"routes\":[{\"distance\":10,"
                            + "\"duration\":2}]}", MediaType.APPLICATION_JSON));

            assertThat(provider().path(List.of(SHOP_A, DOOR))).isEmpty();
        }

        @Test
        @DisplayName("an error or a refusal from the server is an empty path, never an exception")
        void failures_are_empty() {
            server.expect(requestTo(org.hamcrest.Matchers.startsWith("http://osrm.test/")))
                    .andRespond(withServerError());
            server.expect(requestTo(org.hamcrest.Matchers.startsWith("http://osrm.test/")))
                    .andRespond(withSuccess("{\"code\":\"NoRoute\",\"routes\":[]}",
                            MediaType.APPLICATION_JSON));

            OsrmRouteProvider osrm = provider();
            assertThat(osrm.path(List.of(SHOP_A, DOOR))).isEmpty();
            assertThat(osrm.path(List.of(SHOP_A, DOOR))).isEmpty();
            server.verify();
        }

        @Test
        @DisplayName("with no base URL it declines without calling anybody")
        void unconfigured_declines() {
            OsrmRouteProvider unconfigured = new OsrmRouteProvider(RestClient.builder(), "", "driving");

            assertThat(unconfigured.path(List.of(SHOP_A, DOOR))).isEmpty();
            assertThat(unconfigured.pathGeometry()).isEqualTo(PathGeometry.ROAD);
        }

        @Test
        @DisplayName("is the one provider whose paths may be kept")
        void may_be_cached() {
            assertThat(provider().mayCachePaths()).isTrue();
        }
    }

    @Nested
    @DisplayName("Mapbox")
    class Mapbox {

        private final RestClient.Builder builder = RestClient.builder();
        private final MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();

        @Test
        @DisplayName("asks for the same shape of route, and its paths are never kept")
        void same_shape_never_cached() {
            server.expect(requestTo("https://mapbox.test/directions/v5/mapbox/driving-traffic/"
                            + "35.501800,33.893800;35.521400,33.898100"
                            + "?overview=simplified&geometries=polyline6&access_token=pk.test"))
                    .andRespond(withSuccess(OSRM_OK, MediaType.APPLICATION_JSON));

            MapboxRouteProvider mapbox = new MapboxRouteProvider(builder, "https://mapbox.test",
                    "pk.test", "mapbox/driving-traffic");
            Optional<RoutePath> path = mapbox.path(List.of(SHOP_A, DOOR));

            server.verify();
            assertThat(path).isPresent();
            assertThat(path.get().provider()).isEqualTo(MapboxRouteProvider.NAME);
            assertThat(path.get().geometry()).isEqualTo(PathGeometry.ROAD);
            // Its terms forbid storing Navigation API results.
            assertThat(mapbox.mayCachePaths()).isFalse();
        }
    }

    /** A provider that has not decided what its paths are draws none, rather than guessing. */
    @Test
    @DisplayName("a provider that does not implement paths draws nothing")
    void the_default_is_no_path() {
        RouteProvider silent = new RouteProvider() {
            @Override
            public String name() {
                return "SILENT";
            }

            @Override
            public boolean isConfigured() {
                return true;
            }

            @Override
            public Optional<RouteEstimate> estimate(GeoPoint from, GeoPoint to) {
                return Optional.of(new RouteEstimate(1, Duration.ofSeconds(1), "SILENT"));
            }
        };

        assertThat(silent.path(List.of(SHOP_A, DOOR))).isEmpty();
        assertThat(silent.pathGeometry()).isEqualTo(PathGeometry.STRAIGHT);
        assertThat(silent.mayCachePaths()).isFalse();
    }
}
