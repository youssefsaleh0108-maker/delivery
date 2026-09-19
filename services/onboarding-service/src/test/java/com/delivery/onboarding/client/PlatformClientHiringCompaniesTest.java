package com.delivery.onboarding.client;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import com.sun.net.httpserver.HttpServer;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.web.client.RestClient;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Order Manager's list of who is hiring, as the application path reads it.
 *
 * <p>Over real HTTP, from a stand-in Order Manager on a local port, because what matters is how the
 * wire is read: each company with its region, trimmed of anything that is not a name; the list asked
 * for with no token, as the app asks for it, so no Keycloak secret is needed to judge an application;
 * and every way of not getting a usable answer — a refusal, a 5xx, something that is not a list, an
 * Order Manager older than the {@code regions} field, nobody listening — turned into the one coded
 * "try again", never into a company with no region.
 */
@DisplayName("reading who is hiring from Order Manager")
class PlatformClientHiringCompaniesTest {

    private static final String SWIFT = "8a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d";
    private static final String FRESH = "1f2e3d4c-5b6a-4978-8695-a4b3c2d1e0f9";

    private HttpServer orderManager;
    private final AtomicReference<String> answer = new AtomicReference<>("[]");
    private final AtomicInteger status = new AtomicInteger(200);
    private final AtomicReference<String> authorization = new AtomicReference<>();

    @BeforeEach
    void start() throws IOException {
        orderManager = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        orderManager.createContext("/api/delivery-providers/hiring", exchange -> {
            authorization.set(exchange.getRequestHeaders().getFirst("Authorization"));
            byte[] body = answer.get().getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("Content-Type", "application/json");
            exchange.sendResponseHeaders(status.get(), body.length);
            try (OutputStream out = exchange.getResponseBody()) {
                out.write(body);
            }
        });
        orderManager.start();
    }

    @AfterEach
    void stop() {
        orderManager.stop(0);
    }

    /**
     * The client with no Keycloak client secret, so a read that tried to fetch a service token would
     * fail instead of quietly succeeding.
     */
    private static PlatformClient clientOf(String orderManagerUrl) {
        return new PlatformClient(RestClient.builder(), orderManagerUrl, "http://127.0.0.1:9",
                "http://127.0.0.1:9", "http://127.0.0.1:9", "delivery-platform",
                "onboarding-service", "");
    }

    private PlatformClient client() {
        return clientOf("http://127.0.0.1:" + orderManager.getAddress().getPort());
    }

    @Test
    @DisplayName("each company comes with its region, names only and trimmed, asked for with no token")
    void companies_with_their_regions() {
        answer.set("[{\"id\":\"" + SWIFT + "\",\"name\":\"Swift Couriers\","
                + "\"regions\":[\"Achrafieh\",\" Hamra \",\"\",\"   \",7,null]},"
                + "{\"id\":\"" + FRESH + "\",\"name\":\"Fresh Fleet\",\"regions\":[]}]");

        assertThat(client().hiringCompanies()).containsExactly(
                new PlatformClient.HiringCompany(UUID.fromString(SWIFT), "Swift Couriers",
                        List.of("Achrafieh", "Hamra")),
                new PlatformClient.HiringCompany(UUID.fromString(FRESH), "Fresh Fleet", List.of()));
        assertThat(authorization.get()).isNull();
    }

    @Test
    @DisplayName("a company whose id is not an id is skipped, and the rest are still read")
    void an_unreadable_id_is_skipped() {
        answer.set("[{\"id\":\"not-an-id\",\"name\":\"Nobody\",\"regions\":[\"Dora\"]},"
                + "{\"id\":\"" + FRESH + "\",\"name\":\"Fresh Fleet\",\"regions\":[]}]");

        assertThat(client().hiringCompanies()).extracting(PlatformClient.HiringCompany::name)
                .containsExactly("Fresh Fleet");
    }

    @Test
    @DisplayName("companies listed without their regions come from an older Order Manager: try again, not an empty region")
    void no_regions_field_is_no_answer() {
        answer.set("[{\"id\":\"" + SWIFT + "\",\"name\":\"Swift Couriers\"}]");

        assertThatThrownBy(() -> client().hiringCompanies())
                .isInstanceOf(PlatformClient.CompaniesUnavailableException.class);
    }

    @Test
    @DisplayName("a 5xx, or an answer that is not a list, is the coded try-again")
    void a_failure_or_nonsense_is_no_answer() {
        status.set(500);
        answer.set("{\"message\":\"boom\"}");
        assertThatThrownBy(() -> client().hiringCompanies())
                .isInstanceOf(PlatformClient.CompaniesUnavailableException.class);

        status.set(200);
        answer.set("{\"companies\":[]}");
        assertThatThrownBy(() -> client().hiringCompanies())
                .isInstanceOf(PlatformClient.CompaniesUnavailableException.class);

        assertThat(PlatformClient.CompaniesUnavailableException.CODE)
                .isEqualTo("hiring-companies-unavailable");
    }

    @Test
    @DisplayName("an Order Manager nobody is listening for is the same try-again")
    void nobody_listening_is_no_answer() throws IOException {
        int closed;
        try (ServerSocket socket = new ServerSocket(0)) {
            closed = socket.getLocalPort();
        }

        assertThatThrownBy(() -> clientOf("http://127.0.0.1:" + closed).hiringCompanies())
                .isInstanceOf(PlatformClient.CompaniesUnavailableException.class);
    }
}
