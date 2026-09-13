package com.delivery.accounting.service;

import java.net.ConnectException;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.entry;
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

    private static String twoRiders(String youssef, String rania) {
        return """
                {"carrierId":"provider-77","zone":"Asia/Beirut","from":"2026-10-01","to":"2026-10-15",
                 "riders":[{"riderId":"kc-youssef","hasSchedule":true,"totals":%s},
                           {"riderId":"kc-rania","hasSchedule":false,"totals":%s}]}
                """.formatted(youssef, rania);
    }

    /**
     * The read is one call for the fleet, but a figure that cannot be believed is one rider's: their
     * hours are unknown, and everyone else's are still read and paid.
     */
    @Test
    @DisplayName("one rider's totals that are missing, fractional or negative make that rider's hours unknown, and nobody else's")
    void oneUnreadableRider() {
        for (String bad : List.of(
                "{\"workedSeconds\":12.5,\"manualSeconds\":0,\"overtimeSeconds\":0,\"lates\":0,"
                        + "\"absences\":0}",
                "{\"workedSeconds\":-1,\"manualSeconds\":0,\"overtimeSeconds\":0,\"lates\":0,"
                        + "\"absences\":0}",
                "{\"manualSeconds\":0,\"overtimeSeconds\":0,\"lates\":0,\"absences\":0}",
                "null")) {
            server.reset();
            server.expect(requestTo(URL)).andRespond(withSuccess(twoRiders(bad, TOTALS),
                    MediaType.APPLICATION_JSON));

            RiderAttendanceSource.AttendanceRead read = read();

            assertThat(read.available()).as(bad).isTrue();
            assertThat(read.unreadable()).as(bad).containsExactly(entry("kc-youssef", "UNREADABLE"));
            assertThat(read.riders()).as(bad).containsOnlyKeys("kc-rania");
        }

        // Listed twice: neither set of figures is believed.
        server.reset();
        server.expect(requestTo(URL)).andRespond(withSuccess(twoRiders(TOTALS, TOTALS)
                .replace("kc-rania", "kc-youssef"), MediaType.APPLICATION_JSON));
        RiderAttendanceSource.AttendanceRead twice = read();
        assertThat(twice.riders()).isEmpty();
        assertThat(twice.unreadable()).containsOnlyKeys("kc-youssef");
    }

    @Test
    @DisplayName("an answer with no list of riders is unreadable as a whole")
    void unreadable() {
        server.expect(requestTo(URL)).andRespond(withSuccess("{\"carrierId\":\"provider-77\"}",
                MediaType.APPLICATION_JSON));
        assertThat(read().reason()).isEqualTo("UNREADABLE");
    }
}
