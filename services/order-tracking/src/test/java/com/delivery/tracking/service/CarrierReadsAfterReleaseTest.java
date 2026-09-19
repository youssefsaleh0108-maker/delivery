package com.delivery.tracking.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.catchThrowable;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

import com.delivery.tracking.client.CarrierDirectoryClient;
import com.delivery.tracking.client.CarrierDirectoryClient.DirectoryUnavailableException;
import com.delivery.tracking.domain.CarrierMembership;
import com.delivery.tracking.domain.CarrierMembershipPeriod;
import com.delivery.tracking.domain.CarrierMembershipPeriodRepository;
import com.delivery.tracking.domain.CarrierMembershipRepository;
import com.delivery.tracking.domain.DutySession;
import com.delivery.tracking.domain.DutySessionRepository;
import com.delivery.tracking.domain.DutyState;
import com.delivery.tracking.domain.OrderParticipantsRepository;
import com.delivery.tracking.domain.RiderDutyEventRepository;
import com.delivery.tracking.domain.RiderPresence;
import com.delivery.tracking.domain.RiderPresenceRepository;
import com.delivery.tracking.service.DutySessionService.HoursOnline;
import com.delivery.tracking.service.PresenceService.RiderPresenceView;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;

/**
 * A delivery company's sight of a rider ends when the rider leaves it — not when the rider next
 * carries somebody else's order — and never reaches into the rider's time with anybody else.
 *
 * <p>The linkage these reads start from ({@code carrier_membership},
 * {@code rider_presence.carrier_id}) is learned from order events. Every case here leaves that
 * linkage in place — what a late or lost membership event would leave behind — and lets the real
 * {@link FleetMembershipGuard} decide: Order Manager, through a stubbed directory, says who is on the
 * fleet now, and the membership periods say for when.
 */
@DisplayName("a company's sight of a rider it let go")
class CarrierReadsAfterReleaseTest {

    private static final String DISPATCHER = "dispatcher-sub";
    private static final String TOKEN = "dispatcher-token";
    private static final String KEPT = "rider-kept";
    private static final String RELEASED = "rider-released";
    private static final UUID CARRIER = UUID.randomUUID();
    private static final Duration WINDOW = Duration.ofMinutes(2);

    private CarrierDirectoryClient directory;
    private CarrierMembershipPeriodRepository periods;
    private DutySessionRepository sessions;
    private OrderParticipantsRepository participants;
    private PresenceService presence;
    private DutySessionService dutySessions;

    @BeforeEach
    @SuppressWarnings("unchecked")
    void setUp() {
        RiderPresenceRepository presenceRows = mock(RiderPresenceRepository.class);
        CarrierMembershipRepository memberships = mock(CarrierMembershipRepository.class);
        CarrierScopeResolver carrierScope = mock(CarrierScopeResolver.class);
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        ValueOperations<String, String> values = mock(ValueOperations.class);
        sessions = mock(DutySessionRepository.class);
        periods = mock(CarrierMembershipPeriodRepository.class);
        directory = mock(CarrierDirectoryClient.class);
        participants = mock(OrderParticipantsRepository.class);

        when(redis.opsForValue()).thenReturn(values);
        when(sessions.findOverlapping(anyString(), any(), any())).thenReturn(List.of());
        when(memberships.findById(anyString())).thenReturn(Optional.empty());
        when(presenceRows.findById(anyString())).thenReturn(Optional.empty());

        // The linkage a late membership event leaves behind: both riders still read as this company's.
        Instant anHourAgo = Instant.now().minus(Duration.ofHours(1));
        List<RiderPresence> rows = new ArrayList<>();
        for (String rider : List.of(KEPT, RELEASED)) {
            RiderPresence row = RiderPresence.firstSeen(rider, anHourAgo);
            row.attachCarrier(CARRIER, anHourAgo);
            row.declare(DutyState.ON_DUTY, anHourAgo);
            row.sighted(33.89, 35.50, 5.0f, Instant.now().minusSeconds(5));
            when(presenceRows.findById(rider)).thenReturn(Optional.of(row));
            when(memberships.findById(rider)).thenReturn(Optional.of(new CarrierMembership(
                    rider, CARRIER, CarrierMembership.Kind.RIDER,
                    CarrierMembership.Source.ORDER_EVENT)));
            rows.add(row);
        }
        when(presenceRows.findByCarrierIdOrderByLastSeenAtDesc(CARRIER)).thenReturn(rows);
        when(carrierScope.scopeFor(DISPATCHER)).thenReturn(Optional.of(CARRIER));
        when(carrierScope.requireScopeFor(DISPATCHER)).thenReturn(CARRIER);

        FleetMembershipGuard guard =
                new FleetMembershipGuard(directory, periods, Duration.ofSeconds(30));
        presence = new PresenceService(presenceRows, mock(RiderDutyEventRepository.class), sessions,
                memberships, carrierScope, participants, redis,
                new ObjectMapper().registerModule(new JavaTimeModule()),
                WINDOW, Duration.ofSeconds(30), guard, FixPolicy.defaults());
        dutySessions = new DutySessionService(sessions, presenceRows, carrierScope, presence,
                "UTC", WINDOW, Duration.ofHours(4), guard);

        // The company's dispatcher, whose own token is what Order Manager is asked with.
        Jwt jwt = Jwt.withTokenValue(TOKEN).header("alg", "none").subject(DISPATCHER).build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(
                jwt, List.of(new SimpleGrantedAuthority("ROLE_CARRIER"))));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private void orderManagerSaysTheFleetIs(String... riders) {
        when(directory.ridersFor(TOKEN)).thenReturn(Set.of(riders));
    }

    private static long totalSeconds(HoursOnline hours) {
        return hours.days().stream().mapToLong(DutySessionService.DayOnline::secondsOnline).sum();
    }

    @Test
    @DisplayName("a released rider disappears from the company's roster, and the rest stay")
    void the_roster_leaves_out_a_released_rider() {
        orderManagerSaysTheFleetIs(KEPT);

        assertThat(presence.roster(DISPATCHER, false, null, false))
                .extracting(RiderPresenceView::riderId)
                .containsExactly(KEPT);
    }

    @Test
    @DisplayName("a released rider's live position is refused exactly as an unknown rider's is")
    void the_position_of_a_released_rider_is_not_found() {
        orderManagerSaysTheFleetIs(KEPT);

        assertThat(presence.locationOf(KEPT, DISPATCHER, false).lat()).isNotNull();

        Throwable released = catchThrowable(() -> presence.locationOf(RELEASED, DISPATCHER, false));
        Throwable unknown = catchThrowable(() -> presence.locationOf("nobody", DISPATCHER, false));
        assertThat(released)
                .isInstanceOf(PresenceService.PresenceNotFoundException.class)
                .hasMessage(unknown.getMessage());
    }

    @Test
    @DisplayName("a released rider's hours are refused exactly as an unknown rider's are")
    void the_hours_of_a_released_rider_are_not_found() {
        orderManagerSaysTheFleetIs(KEPT);

        assertThat(dutySessions.riderHours(KEPT, DISPATCHER, false, 7).riderId()).isEqualTo(KEPT);

        Throwable released = catchThrowable(() -> dutySessions.riderHours(RELEASED, DISPATCHER, false, 7));
        Throwable unknown = catchThrowable(() -> dutySessions.riderHours("nobody", DISPATCHER, false, 7));
        assertThat(released)
                .isInstanceOf(PresenceService.PresenceNotFoundException.class)
                .hasMessage(unknown.getMessage());
    }

    @Test
    @DisplayName("with Order Manager out of reach, roster, position and hours are refused, not guessed")
    void an_outage_refuses_all_three() {
        when(directory.ridersFor(TOKEN)).thenThrow(new DirectoryUnavailableException("down", null));

        assertThatThrownBy(() -> presence.roster(DISPATCHER, false, null, false))
                .isInstanceOf(DirectoryUnavailableException.class);
        assertThatThrownBy(() -> presence.locationOf(KEPT, DISPATCHER, false))
                .isInstanceOf(DirectoryUnavailableException.class);
        assertThatThrownBy(() -> dutySessions.riderHours(KEPT, DISPATCHER, false, 7))
                .isInstanceOf(DirectoryUnavailableException.class);
    }

    @Test
    @DisplayName("a rider's hours count only from the moment they became the company's rider")
    void the_hours_start_where_the_rider_joined() {
        orderManagerSaysTheFleetIs(KEPT);
        Instant shiftStart = Instant.now().minus(Duration.ofDays(1)).truncatedTo(ChronoUnit.SECONDS);
        DutySession shift = DutySession.open(KEPT, shiftStart);
        shift.close(shiftStart.plus(Duration.ofHours(2)), DutySession.EndReason.RIDER);
        when(sessions.findOverlapping(eq(KEPT), any(), any())).thenReturn(List.of(shift));
        // Hired an hour into that shift: the first hour was worked for somebody else.
        when(periods.overlappingForRider(eq(CARRIER), eq(KEPT), any(), any())).thenReturn(List.of(
                CarrierMembershipPeriod.open(KEPT, CARRIER, shiftStart.plus(Duration.ofHours(1)))));

        assertThat(totalSeconds(dutySessions.riderHours(KEPT, DISPATCHER, false, 7))).isEqualTo(3600);
    }

    @Test
    @DisplayName("a rider the record never put on the company's fleet shows the company no hours")
    void no_period_no_hours() {
        orderManagerSaysTheFleetIs(KEPT);
        Instant shiftStart = Instant.now().minus(Duration.ofDays(1)).truncatedTo(ChronoUnit.SECONDS);
        DutySession shift = DutySession.open(KEPT, shiftStart);
        shift.close(shiftStart.plus(Duration.ofHours(2)), DutySession.EndReason.RIDER);
        when(sessions.findOverlapping(eq(KEPT), any(), any())).thenReturn(List.of(shift));

        assertThat(dutySessions.riderHours(KEPT, DISPATCHER, false, 7).days()).isEmpty();
    }
}
