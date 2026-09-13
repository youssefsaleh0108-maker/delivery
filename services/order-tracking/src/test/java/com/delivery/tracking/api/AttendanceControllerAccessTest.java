package com.delivery.tracking.api;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.tracking.service.AttendancePeriod;
import com.delivery.tracking.service.AttendanceService;
import com.delivery.tracking.service.AttendanceService.AttendanceTotals;
import com.delivery.tracking.service.AttendanceService.RiderAttendance;
import com.delivery.tracking.service.DutySessionService.DutySessions;
import com.delivery.tracking.service.PresenceService;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Who may read and write attendance.
 *
 * <p>Attendance is personal data about named workers that decides their pay. Two properties are
 * pinned here: a carrier sees only its own riders, with a foreign rider indistinguishable from one
 * that does not exist; and every write is the carrier's alone, in the carrier's own name — there is
 * no field in any body through which a fleet could be named.
 *
 * <p>Standalone MockMvc, so method security is NOT wired: every refusal below holds because the
 * controller checks the role itself as well, which is the point.
 */
@DisplayName("who may read and write attendance")
class AttendanceControllerAccessTest {

    private static final String DISPATCHER = "dispatcher-sub";
    private static final UUID CARRIER = UUID.fromString("5857ac51-0000-4000-8000-000000000001");
    private static final UUID RIVAL = UUID.fromString("5857ac51-0000-4000-8000-000000000002");
    private static final AttendancePeriod OCTOBER =
            new AttendancePeriod(LocalDate.of(2026, 10, 1), LocalDate.of(2026, 10, 31));

    private AttendanceService attendance;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        attendance = mock(AttendanceService.class);
        mvc = MockMvcBuilders.standaloneSetup(new AttendanceController(attendance)).build();

        when(attendance.riderAttendance(anyString(), anyString(), anyBoolean(), any()))
                .thenReturn(emptyMonth());
        when(attendance.riderSessions(anyString(), anyString(), anyBoolean(), any()))
                .thenReturn(new DutySessions("r1", "Asia/Beirut", OCTOBER.from(), OCTOBER.to(),
                        List.of()));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private static void signedInAs(String subject, String... roles) {
        Jwt jwt = Jwt.withTokenValue("token").header("alg", "none").subject(subject).build();
        List<GrantedAuthority> authorities = Arrays.stream(roles)
                .<GrantedAuthority>map(role -> new SimpleGrantedAuthority("ROLE_" + role))
                .toList();
        SecurityContextHolder.getContext().setAuthentication(
                new JwtAuthenticationToken(jwt, authorities));
    }

    private static RiderAttendance emptyMonth() {
        return new RiderAttendance("r1", CARRIER, "Asia/Beirut", OCTOBER.from(), OCTOBER.to(),
                LocalDate.of(2026, 10, 12), Instant.parse("2026-10-12T17:00:00Z"), false, List.of(),
                new AttendanceTotals(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, BigDecimal.ZERO,
                        BigDecimal.ZERO));
    }

    @Nested
    @DisplayName("reading one rider")
    class Reading {

        @Test
        void anonymous_callers_are_refused() throws Exception {
            mvc.perform(get("/api/tracking/riders/r1/attendance").param("month", "2026-10"))
                    .andExpect(status().isUnauthorized());
            verifyNoInteractions(attendance);
        }

        @Test
        void a_rider_cannot_read_attendance_here_not_even_their_own() throws Exception {
            signedInAs("r1", "DELIVERY");

            mvc.perform(get("/api/tracking/riders/r1/attendance").param("month", "2026-10"))
                    .andExpect(status().isForbidden());
            mvc.perform(get("/api/tracking/riders/r1/duty/sessions").param("month", "2026-10"))
                    .andExpect(status().isForbidden());
            verifyNoInteractions(attendance);
        }

        @Test
        void a_customer_or_a_merchant_is_refused() throws Exception {
            signedInAs("c1", "CUSTOMER", "MERCHANT");

            mvc.perform(get("/api/tracking/riders/r1/attendance").param("month", "2026-10"))
                    .andExpect(status().isForbidden());
            verifyNoInteractions(attendance);
        }

        @Test
        void a_carrier_reads_in_its_own_name_never_as_backoffice() throws Exception {
            signedInAs(DISPATCHER, "CARRIER");

            mvc.perform(get("/api/tracking/riders/r1/attendance").param("month", "2026-10"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.zone").value("Asia/Beirut"))
                    // When the figures were computed, which a pay run stores beside them. Present
                    // only: standalone MockMvc lacks Spring Boot's Jackson defaults, so it prints
                    // instants as numbers where the running service writes ISO-8601.
                    .andExpect(jsonPath("$.asOf").exists());

            verify(attendance).riderAttendance("r1", DISPATCHER, false, OCTOBER);
        }

        @Test
        void backoffice_reads_as_backoffice() throws Exception {
            signedInAs("op-1", "BACKOFFICE");

            mvc.perform(get("/api/tracking/riders/r1/duty/sessions")
                            .param("from", "2026-10-01").param("to", "2026-10-31"))
                    .andExpect(status().isOk());

            verify(attendance).riderSessions("r1", "op-1", true, OCTOBER);
        }

        /** The same body the hours endpoint returns, so the two cannot be told apart. */
        @Test
        void another_fleets_rider_is_the_same_404_as_an_unknown_one() throws Exception {
            signedInAs(DISPATCHER, "CARRIER");
            when(attendance.riderAttendance(eq("theirs"), anyString(), anyBoolean(), any()))
                    .thenThrow(new PresenceService.PresenceNotFoundException("theirs"));

            mvc.perform(get("/api/tracking/riders/theirs/attendance").param("month", "2026-10"))
                    .andExpect(status().isNotFound())
                    .andExpect(jsonPath("$.title").value("Rider not found"))
                    .andExpect(jsonPath("$.detail").value("No presence information for that rider"));
        }

        @Test
        void a_carrier_account_in_no_company_is_told_so() throws Exception {
            signedInAs(DISPATCHER, "CARRIER");
            when(attendance.riderAttendance(anyString(), anyString(), anyBoolean(), any()))
                    .thenThrow(new PresenceService.NoCarrierException(
                            "You are not a member of any delivery company"));

            mvc.perform(get("/api/tracking/riders/r1/attendance").param("month", "2026-10"))
                    .andExpect(status().isForbidden())
                    .andExpect(jsonPath("$.title").value("No delivery company"));
        }

        @Test
        void a_window_longer_than_thirty_one_days_is_refused_before_anything_is_read()
                throws Exception {
            signedInAs(DISPATCHER, "CARRIER");

            mvc.perform(get("/api/tracking/riders/r1/duty/sessions")
                            .param("from", "2026-10-01").param("to", "2026-11-15"))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.title").value("Invalid request"));
            mvc.perform(get("/api/tracking/riders/r1/attendance").param("month", "2026-10")
                            .param("from", "2026-10-01").param("to", "2026-10-02"))
                    .andExpect(status().isBadRequest());
            verifyNoInteractions(attendance);
        }
    }

    @Nested
    @DisplayName("writing")
    class Writing {

        /** Support looks; it does not rearrange a company's rota or rewrite its register. */
        @Test
        void backoffice_cannot_write_anything() throws Exception {
            signedInAs("op-1", "BACKOFFICE");

            mvc.perform(put("/api/tracking/riders/r1/shift-assignment")
                            .contentType(MediaType.APPLICATION_JSON).content("{}"))
                    .andExpect(status().isForbidden());
            mvc.perform(post("/api/tracking/carrier/shifts")
                            .contentType(MediaType.APPLICATION_JSON).content("{}"))
                    .andExpect(status().isForbidden());
            mvc.perform(put("/api/tracking/riders/r1/attendance/entries/2026-10-06")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"status\":\"SICK\"}"))
                    .andExpect(status().isForbidden());
            mvc.perform(delete("/api/tracking/carrier/shifts/" + UUID.randomUUID()))
                    .andExpect(status().isForbidden());
            verifyNoInteractions(attendance);
        }

        @Test
        void a_rider_cannot_schedule_or_excuse_themselves() throws Exception {
            signedInAs("r1", "DELIVERY");

            mvc.perform(put("/api/tracking/riders/r1/shift-assignment")
                            .contentType(MediaType.APPLICATION_JSON).content("{}"))
                    .andExpect(status().isForbidden());
            mvc.perform(put("/api/tracking/riders/r1/attendance/entries/2026-10-06")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"status\":\"PRESENT\"}"))
                    .andExpect(status().isForbidden());
            verifyNoInteractions(attendance);
        }

        @Test
        void a_carrier_writing_for_another_fleets_rider_gets_the_same_404() throws Exception {
            signedInAs(DISPATCHER, "CARRIER");
            when(attendance.recordEntry(eq("theirs"), anyString(), anyString(), any(), any(), any(),
                    any())).thenThrow(new PresenceService.PresenceNotFoundException("theirs"));

            mvc.perform(put("/api/tracking/riders/theirs/attendance/entries/2026-10-06")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"status\":\"SICK\"}"))
                    .andExpect(status().isNotFound())
                    .andExpect(jsonPath("$.title").value("Rider not found"));
        }

        /** There is no fleet field to reach for: a named company in the body changes nothing. */
        @Test
        void the_fleet_written_to_never_comes_from_the_request() throws Exception {
            signedInAs(DISPATCHER, "CARRIER");

            mvc.perform(post("/api/tracking/carrier/shifts")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"name\":\"Night\",\"startTime\":\"22:00\","
                                    + "\"endTime\":\"06:00\",\"days\":[\"MONDAY\"],"
                                    + "\"carrierId\":\"" + RIVAL + "\"}"))
                    .andExpect(status().isCreated());

            verify(attendance).createShift(eq(DISPATCHER), eq("Night"), eq("22:00"), eq("06:00"),
                    eq(List.of("MONDAY")), isNull());
        }

        @Test
        void the_entry_is_recorded_by_the_caller_for_the_day_in_the_path() throws Exception {
            signedInAs(DISPATCHER, "CARRIER");

            mvc.perform(put("/api/tracking/riders/r1/attendance/entries/2026-10-06")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"status\":\"PRESENT\",\"clockIn\":\"08:00\","
                                    + "\"clockOut\":\"18:00\",\"note\":\"Phone died\","
                                    + "\"recordedBy\":\"someone-else\"}"))
                    .andExpect(status().isOk());

            verify(attendance).recordEntry("r1", DISPATCHER, "2026-10-06", "PRESENT", "08:00",
                    "18:00", "Phone died");
        }

        @Test
        void withdrawing_an_entry_answers_no_content() throws Exception {
            signedInAs(DISPATCHER, "CARRIER");

            mvc.perform(delete("/api/tracking/riders/r1/attendance/entries/2026-10-06"))
                    .andExpect(status().isNoContent());

            verify(attendance).withdrawEntry("r1", DISPATCHER, "2026-10-06");
        }

        @Test
        void archiving_a_shift_in_use_is_a_conflict_that_says_how_many() throws Exception {
            signedInAs(DISPATCHER, "CARRIER");
            UUID shift = UUID.randomUUID();
            when(attendance.archiveShift(DISPATCHER, shift)).thenThrow(
                    new AttendanceService.ConflictException("Move the riders first.", 3));

            mvc.perform(delete("/api/tracking/carrier/shifts/" + shift))
                    .andExpect(status().isConflict())
                    .andExpect(jsonPath("$.riders").value(3));
        }
    }

    @Nested
    @DisplayName("the fleet reads")
    class FleetReads {

        @Test
        void a_carrier_asks_in_its_own_name_and_the_service_ignores_any_fleet_it_names()
                throws Exception {
            signedInAs(DISPATCHER, "CARRIER");

            mvc.perform(get("/api/tracking/carrier/attendance")
                            .param("month", "2026-10").param("carrierId", RIVAL.toString()))
                    .andExpect(status().isOk());

            // isBackoffice=false is what makes the service resolve the fleet from the token; the
            // service's own test pins that the named fleet is then never read.
            verify(attendance).fleetAttendance(DISPATCHER, false, RIVAL, OCTOBER);
        }

        @Test
        void a_rider_cannot_read_a_fleets_schedule_or_pay_figures() throws Exception {
            signedInAs("r1", "DELIVERY");

            mvc.perform(get("/api/tracking/carrier/attendance").param("month", "2026-10"))
                    .andExpect(status().isForbidden());
            mvc.perform(get("/api/tracking/carrier/shifts"))
                    .andExpect(status().isForbidden());
            mvc.perform(get("/api/tracking/carrier/shift-assignments"))
                    .andExpect(status().isForbidden());
            verifyNoInteractions(attendance);
        }
    }
}
