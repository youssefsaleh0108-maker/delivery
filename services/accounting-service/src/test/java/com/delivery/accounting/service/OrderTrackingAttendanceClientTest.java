package com.delivery.accounting.service;

import java.net.ConnectException;
import java.time.LocalDate;
import java.time.ZoneId;

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

/**
 * Reading a fleet's hours for a pay run — and, above all, that nothing order-tracking can do wrong
 * escapes as an exception or is paid on as if it were right.
 */
@DisplayName("reading attendance for a pay run")
class OrderTrackingAttendanceClientTest {

    private static final String TRACKING = "http://order-tracking";
    private static final String URL = TRACKING
            + "/api/tracking/carrier/attendance?from=2026-10-01&to=2026-10-15";
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

    private RiderAttendanceSource.AttendanceRead read() {
        return new OrderTrackingAttendanceClient(builder, TRACKING)
                .fleet("caller-token", "provider-77", BEIRUT, FROM, TO);
    }

    private static String body(String carrier, String zone, String totals) {
        return """
                {"carrierId":"%s","zone":"%s","from":"2026-10-01","to":"2026-10-15",
                 "riders":[{"riderId":"kc-youssef","hasSchedule":true,"totals":%s}]}
                """.formatted(carrier, zone, totals);
    }

    private static final String TOTALS = """
            {"scheduledDays":11,"daysWorked":10,"absences":1,"lates":2,"excusedLates":1,
             "excusedAbsences":0,"sickDays":0,"leaveDays":0,"workedSeconds":288000,
             "manualSeconds":5400,"scheduledSeconds":316800,"overtimeSeconds":3600,
             "workedHours":80.00,"overtimeHours":1.00}
            """;

    @Test
    @DisplayName("reads each rider's exact seconds, for the period, with the carrier's own token")
    void readsTheFleet() {
        server.expect(requestTo(URL))
                .andExpect(header(HttpHeaders.AUTHORIZATION, "Bearer caller-token"))
                .andRespond(withSuccess(body("provider-77", "Asia/Beirut", TOTALS),
                        MediaType.APPLICATION_JSON));

        RiderAttendanceSource.AttendanceRead read = read();

        assertThat(read.available()).isTrue();
        assertThat(read.riders()).containsEntry("kc-youssef",
                new PayslipCalculator.RiderHours(288_000, 5_400, 3_600, 2, 1));
        server.verify();
    }

    @Test
    @DisplayName("no attendance route where this runs is 'not deployed', not zero hours")
    void notDeployed() {
        server.expect(requestTo(URL)).andRespond(withResourceNotFound());

        assertThat(read()).isEqualTo(RiderAttendanceSource.AttendanceRead.unavailable("NOT_DEPLOYED"));
    }

    @Test
    @DisplayName("an outage or a refused connection is unreachable, and never an exception")
    void outage() {
        server.expect(requestTo(URL)).andRespond(withStatus(HttpStatus.SERVICE_UNAVAILABLE));
        assertThat(read().reason()).isEqualTo("UNREACHABLE");

        server.reset();
        server.expect(requestTo(URL)).andRespond(withException(new ConnectException("refused")));
        assertThat(read().reason()).isEqualTo("UNREACHABLE");
    }

    @Test
    @DisplayName("a refused token and a refused period say which")
    void refusals() {
        server.expect(requestTo(URL)).andRespond(withStatus(HttpStatus.FORBIDDEN));
        assertThat(read().reason()).isEqualTo("REFUSED");

        server.reset();
        server.expect(requestTo(URL)).andRespond(withStatus(HttpStatus.BAD_REQUEST));
        assertThat(read().reason()).isEqualTo("PERIOD_REFUSED");
    }

    @Test
    @DisplayName("an answer about another fleet or judged in another zone is not paid on")
    void mismatches() {
        server.expect(requestTo(URL)).andRespond(withSuccess(
                body("provider-rival", "Asia/Beirut", TOTALS), MediaType.APPLICATION_JSON));
        assertThat(read().reason()).isEqualTo("MISMATCH");

        server.reset();
        server.expect(requestTo(URL)).andRespond(withSuccess(
                body("provider-77", "UTC", TOTALS), MediaType.APPLICATION_JSON));
        assertThat(read().reason()).isEqualTo("MISMATCH");
    }

    @Test
    @DisplayName("totals that are missing, fractional or negative make the whole read unreadable")
    void unreadable() {
        server.expect(requestTo(URL)).andRespond(withSuccess(
                body("provider-77", "Asia/Beirut", "{\"workedSeconds\":12.5,\"manualSeconds\":0,"
                        + "\"overtimeSeconds\":0,\"lates\":0,\"absences\":0}"),
                MediaType.APPLICATION_JSON));
        assertThat(read().reason()).isEqualTo("UNREADABLE");

        server.reset();
        server.expect(requestTo(URL)).andRespond(withSuccess(
                body("provider-77", "Asia/Beirut", "{\"workedSeconds\":-1,\"manualSeconds\":0,"
                        + "\"overtimeSeconds\":0,\"lates\":0,\"absences\":0}"),
                MediaType.APPLICATION_JSON));
        assertThat(read().reason()).isEqualTo("UNREADABLE");

        server.reset();
        server.expect(requestTo(URL)).andRespond(withSuccess("{\"carrierId\":\"provider-77\"}",
                MediaType.APPLICATION_JSON));
        assertThat(read().reason()).isEqualTo("UNREADABLE");
    }
}
