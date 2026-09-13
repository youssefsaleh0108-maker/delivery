package com.delivery.accounting.service;

import java.net.ConnectException;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withException;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withResourceNotFound;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import com.delivery.accounting.service.RiderDeliveriesSource.DeliveriesRead;

/**
 * Counting a company's deliveries for a pay run — every order its riders delivered, fee or none — and,
 * above all, that nothing Order Manager can do wrong escapes as an exception or is paid on as if it
 * were right.
 */
@DisplayName("counting deliveries for a pay run")
class OrderManagerDeliveriesClientTest {

    private static final String ORDERS = "http://order-manager";
    private static final String URL = ORDERS
            + "/api/orders/riders/delivered?from=2026-10-01&to=2026-10-15";
    private static final ZoneId BEIRUT = ZoneId.of("Asia/Beirut");
    private static final LocalDate FROM = LocalDate.parse("2026-10-01");
    private static final LocalDate TO = LocalDate.parse("2026-10-15");

    private RestClient.Builder builder;
    private MockRestServiceServer server;

    @BeforeEach
    void setUp() {
        builder = RestClient.builder();
        server = MockRestServiceServer.bindTo(builder).build();
    }

    private DeliveriesRead read() {
        return new OrderManagerDeliveriesClient(builder, ORDERS)
                .fleet("caller-token", "provider-77", BEIRUT, FROM, TO);
    }

    private static String body(String carrier, String zone, String from, String riders) {
        return """
                {"carrierId":"%s","zone":"%s","from":"%s","to":"2026-10-15",
                 "asOf":"2026-10-20T09:00:00Z","riders":%s}
                """.formatted(carrier, zone, from, riders);
    }

    private void answers(String json) {
        server.expect(requestTo(URL)).andRespond(withSuccess(json, MediaType.APPLICATION_JSON));
    }

    @Test
    @DisplayName("reads each rider's delivered orders for the period, with the carrier's own token")
    void readsTheCounts() {
        server.expect(requestTo(URL))
                .andExpect(header(HttpHeaders.AUTHORIZATION, "Bearer caller-token"))
                .andRespond(withSuccess(body("provider-77", "Asia/Beirut", "2026-10-01",
                                "[{\"riderId\":\"kc-youssef\",\"delivered\":17},"
                                        + "{\"riderId\":\"kc-rania\",\"delivered\":0}]"),
                        MediaType.APPLICATION_JSON));

        DeliveriesRead read = read();

        assertThat(read.available()).isTrue();
        assertThat(read.riders()).containsEntry("kc-youssef", 17).containsEntry("kc-rania", 0);
        server.verify();
    }

    @Test
    @DisplayName("no such route where this runs is 'not deployed', never zero deliveries")
    void notDeployed() {
        server.expect(requestTo(URL)).andRespond(withResourceNotFound());

        assertThat(read()).isEqualTo(DeliveriesRead.unavailable("NOT_DEPLOYED"));
    }

    @Test
    @DisplayName("an outage, a refused connection, a refused token and a refused period say which")
    void failures() {
        server.expect(requestTo(URL)).andRespond(withStatus(HttpStatus.SERVICE_UNAVAILABLE));
        assertThat(read().reason()).isEqualTo("UNREACHABLE");

        server.reset();
        server.expect(requestTo(URL)).andRespond(withException(new ConnectException("refused")));
        assertThat(read().reason()).isEqualTo("UNREACHABLE");

        server.reset();
        server.expect(requestTo(URL)).andRespond(withStatus(HttpStatus.FORBIDDEN));
        assertThat(read().reason()).isEqualTo("REFUSED");

        server.reset();
        server.expect(requestTo(URL)).andRespond(withStatus(HttpStatus.BAD_REQUEST));
        assertThat(read().reason()).isEqualTo("PERIOD_REFUSED");
    }

    @Test
    @DisplayName("an answer about another company, zone or period is not paid on")
    void mismatches() {
        String riders = "[{\"riderId\":\"kc-youssef\",\"delivered\":3}]";
        answers(body("provider-rival", "Asia/Beirut", "2026-10-01", riders));
        assertThat(read().reason()).isEqualTo("MISMATCH");

        server.reset();
        answers(body("provider-77", "UTC", "2026-10-01", riders));
        assertThat(read().reason()).isEqualTo("MISMATCH");

        server.reset();
        answers(body("provider-77", "Asia/Beirut", "2026-09-30", riders));
        assertThat(read().reason()).isEqualTo("MISMATCH");
    }

    @Test
    @DisplayName("a count that is fractional, negative, missing or given twice makes the whole read unreadable")
    void unreadable() {
        for (String riders : List.of(
                "[{\"riderId\":\"kc-youssef\",\"delivered\":2.5}]",
                "[{\"riderId\":\"kc-youssef\",\"delivered\":-1}]",
                "[{\"riderId\":\"kc-youssef\",\"delivered\":\"3\"}]",
                "[{\"riderId\":\"kc-youssef\"}]",
                "[{\"riderId\":\" \",\"delivered\":1}]",
                "[{\"riderId\":\"kc-youssef\",\"delivered\":1},"
                        + "{\"riderId\":\"kc-youssef\",\"delivered\":2}]")) {
            server.reset();
            answers(body("provider-77", "Asia/Beirut", "2026-10-01", riders));
            assertThat(read().reason()).as(riders).isEqualTo("UNREADABLE");
        }

        server.reset();
        answers("{\"carrierId\":\"provider-77\"}");
        assertThat(read().reason()).isEqualTo("UNREADABLE");
    }
}
