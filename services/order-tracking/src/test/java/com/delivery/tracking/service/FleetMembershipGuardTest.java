package com.delivery.tracking.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.catchThrowable;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

import com.delivery.tracking.client.CarrierDirectoryClient;
import com.delivery.tracking.client.CarrierDirectoryClient.DirectoryUnavailableException;
import com.delivery.tracking.domain.CarrierMembershipPeriod;
import com.delivery.tracking.domain.CarrierMembershipPeriodRepository;
import com.delivery.tracking.domain.MembershipWindow;

/**
 * Which riders a company may see, and for when — the check that ends a company's sight of a rider
 * it let go, and keeps it out of their time with anybody else.
 *
 * <p>Now: the answer is Order Manager's, asked with the caller's own token; it is held for a short
 * window and then asked for again, so a departure lands within that window; and an Order Manager
 * that cannot be asked refuses, rather than letting an older answer stand in for it. When: the
 * windows are the membership periods cut to the range asked, so a history read clipped to them
 * holds none of the rider's time before they joined, after they left, or away in between.
 */
@DisplayName("which riders a company may see, and for when")
class FleetMembershipGuardTest {

    private static final String STAFF = "carrier-office-sub";
    private static final String TOKEN = "carrier-token";
    private static final String KEPT = "rider-kept";
    private static final String RELEASED = "rider-released";
    private static final UUID CARRIER = UUID.fromString("5857ac51-0000-4000-8000-000000000001");
    private static final Duration WINDOW = Duration.ofSeconds(30);

    private static final Instant FROM = Instant.parse("2026-09-01T00:00:00Z");
    private static final Instant TO = Instant.parse("2026-09-30T00:00:00Z");

    private CarrierDirectoryClient directory;
    private CarrierMembershipPeriodRepository periods;
    private MovableClock clock;
    private FleetMembershipGuard guard;

    @BeforeEach
    void setUp() {
        directory = mock(CarrierDirectoryClient.class);
        periods = mock(CarrierMembershipPeriodRepository.class);
        clock = new MovableClock(Instant.parse("2026-09-13T08:00:00Z"));
        guard = new FleetMembershipGuard(directory, periods, WINDOW, clock);
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private static void signedInAs(String subject, String tokenValue, String role) {
        Jwt jwt = Jwt.withTokenValue(tokenValue).header("alg", "none").subject(subject).build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(
                jwt, List.of(new SimpleGrantedAuthority("ROLE_" + role))));
    }

    private static CarrierMembershipPeriod period(String rider, Instant joined, Instant left) {
        CarrierMembershipPeriod period = CarrierMembershipPeriod.open(rider, CARRIER, joined);
        if (left != null) {
            period.endAt(left);
        }
        return period;
    }

    // ---------------------------------------------------------------- now

    @Test
    @DisplayName("asks Order Manager with the caller's own token, and answers from its list")
    void asks_with_the_callers_own_token() {
        signedInAs(STAFF, TOKEN, "CARRIER");
        when(directory.ridersFor(TOKEN)).thenReturn(Set.of(KEPT));

        assertThat(guard.isOnCallersFleet(STAFF, KEPT)).isTrue();
        assertThat(guard.isOnCallersFleet(STAFF, RELEASED)).isFalse();
        verify(directory).ridersFor(TOKEN);
    }

    @Test
    @DisplayName("a rider the company let go drops out once the window has passed, and not before")
    void a_departure_lands_within_the_window() {
        signedInAs(STAFF, TOKEN, "CARRIER");
        when(directory.ridersFor(TOKEN))
                .thenReturn(Set.of(KEPT, RELEASED))
                .thenReturn(Set.of(KEPT));

        assertThat(guard.isOnCallersFleet(STAFF, RELEASED)).isTrue();

        // Inside the window: the answer already held, and no second call from a console's poll.
        clock.advance(Duration.ofSeconds(29));
        assertThat(guard.isOnCallersFleet(STAFF, RELEASED)).isTrue();
        verify(directory, times(1)).ridersFor(TOKEN);

        // Past it: asked again, and the release shows.
        clock.advance(Duration.ofSeconds(2));
        assertThat(guard.isOnCallersFleet(STAFF, RELEASED)).isFalse();
        assertThat(guard.isOnCallersFleet(STAFF, KEPT)).isTrue();
        verify(directory, times(2)).ridersFor(TOKEN);
    }

    @Test
    @DisplayName("an Order Manager that cannot be asked refuses the read, and the refusal is not kept")
    void an_outage_denies_and_is_not_remembered() {
        signedInAs(STAFF, TOKEN, "CARRIER");
        when(directory.ridersFor(TOKEN))
                .thenThrow(new DirectoryUnavailableException("down", null))
                .thenThrow(new DirectoryUnavailableException("down", null))
                .thenReturn(Set.of(KEPT));

        assertThatThrownBy(() -> guard.isOnCallersFleet(STAFF, KEPT))
                .isInstanceOf(DirectoryUnavailableException.class);
        assertThatThrownBy(() -> guard.ridersOnCallersFleet(STAFF))
                .as("a failure is not an empty fleet")
                .isInstanceOf(DirectoryUnavailableException.class);

        // Back up: asked again at once, not after a window of remembered failure.
        assertThat(guard.isOnCallersFleet(STAFF, KEPT)).isTrue();
    }

    @Test
    @DisplayName("an expired answer is never served through an outage")
    void an_expired_answer_is_not_served_through_an_outage() {
        signedInAs(STAFF, TOKEN, "CARRIER");
        when(directory.ridersFor(TOKEN))
                .thenReturn(Set.of(KEPT))
                .thenThrow(new DirectoryUnavailableException("down", null));
        assertThat(guard.isOnCallersFleet(STAFF, KEPT)).isTrue();

        clock.advance(WINDOW.plusSeconds(1));

        assertThatThrownBy(() -> guard.isOnCallersFleet(STAFF, KEPT))
                .isInstanceOf(DirectoryUnavailableException.class);
    }

    @Test
    @DisplayName("a caller without the carrier role has no fleet, and costs Order Manager nothing")
    void callers_who_are_not_carrier_staff_are_never_looked_up() {
        signedInAs("customer-sub", "customer-token", "CUSTOMER");

        assertThat(guard.ridersOnCallersFleet("customer-sub")).isEmpty();
        assertThat(guard.isOnCallersFleet("customer-sub", KEPT)).isFalse();
        verifyNoInteractions(directory);
    }

    @Test
    @DisplayName("a token is only ever used to ask about its own holder")
    void another_holders_token_is_never_used() {
        signedInAs("somebody-else-sub", TOKEN, "CARRIER");

        assertThat(guard.isOnCallersFleet(STAFF, KEPT)).isFalse();
        verifyNoInteractions(directory);
    }

    @Test
    @DisplayName("a rider off the fleet is refused with the unknown rider's own not-found")
    void the_refusal_is_the_unknown_riders_not_found() {
        signedInAs(STAFF, TOKEN, "CARRIER");
        when(directory.ridersFor(TOKEN)).thenReturn(Set.of(KEPT));

        Throwable released = catchThrowable(() -> guard.requireOnCallersFleet(STAFF, RELEASED));
        Throwable unknown = catchThrowable(() -> guard.requireOnCallersFleet(STAFF, "nobody"));

        assertThat(released).isInstanceOf(PresenceService.PresenceNotFoundException.class);
        assertThat(released).hasMessage(unknown.getMessage());
        // A rider still on the fleet passes without a word.
        guard.requireOnCallersFleet(STAFF, KEPT);
    }

    @Test
    @DisplayName("a listing keeps only the rows whose rider is on the fleet, in their order")
    void a_listing_keeps_the_current_members() {
        signedInAs(STAFF, TOKEN, "CARRIER");
        when(directory.ridersFor(TOKEN)).thenReturn(Set.of(KEPT, "rider-third"));

        assertThat(guard.retainCallersFleet(STAFF, List.of("rider-third", RELEASED, KEPT), row -> row))
                .containsExactly("rider-third", KEPT);
        // Nothing to filter: nothing to ask.
        assertThat(guard.retainCallersFleet(STAFF, List.<String>of(), row -> row)).isEmpty();
        verify(directory, times(1)).ridersFor(TOKEN);
    }

    @Test
    @DisplayName("each dispatcher's answer is their own")
    void answers_are_held_per_caller() {
        signedInAs(STAFF, TOKEN, "CARRIER");
        when(directory.ridersFor(TOKEN)).thenReturn(Set.of(KEPT));
        when(directory.ridersFor("rival-token")).thenReturn(Set.of(RELEASED));
        assertThat(guard.isOnCallersFleet(STAFF, KEPT)).isTrue();

        signedInAs("rival-sub", "rival-token", "CARRIER");
        assertThat(guard.isOnCallersFleet("rival-sub", KEPT)).isFalse();
        assertThat(guard.isOnCallersFleet("rival-sub", RELEASED)).isTrue();
    }

    // ---------------------------------------------------------------- when

    @Test
    @DisplayName("a rider's windows are their periods on the company's fleet, cut to the range asked")
    void windows_are_the_periods_cut_to_the_range() {
        Instant left = Instant.parse("2026-09-05T00:00:00Z");
        Instant back = Instant.parse("2026-09-12T08:00:00Z");
        when(periods.overlappingForRider(CARRIER, KEPT, FROM, TO)).thenReturn(List.of(
                period(KEPT, Instant.parse("2026-08-20T00:00:00Z"), left),
                period(KEPT, back, null)));

        // Not the days before the range, and not the week away between the two spells.
        assertThat(guard.membershipWindows(CARRIER, KEPT, FROM, TO)).containsExactly(
                new MembershipWindow(FROM, left),
                new MembershipWindow(back, TO));
    }

    @Test
    @DisplayName("leaving and coming back at the same instant is one unbroken window")
    void touching_periods_merge() {
        Instant boundary = Instant.parse("2026-09-10T00:00:00Z");
        when(periods.overlappingForRider(CARRIER, KEPT, FROM, TO)).thenReturn(List.of(
                period(KEPT, Instant.parse("2026-09-02T00:00:00Z"), boundary),
                period(KEPT, boundary, null)));

        assertThat(guard.membershipWindows(CARRIER, KEPT, FROM, TO)).containsExactly(
                new MembershipWindow(Instant.parse("2026-09-02T00:00:00Z"), TO));
    }

    @Test
    @DisplayName("no period, a zero-length one, or an empty range: no window, and nothing to show")
    void nothing_to_clip_to_means_nothing() {
        Instant at = Instant.parse("2026-09-03T00:00:00Z");
        when(periods.overlappingForRider(CARRIER, RELEASED, FROM, TO)).thenReturn(List.of(
                CarrierMembershipPeriod.leftWithoutJoin(RELEASED, CARRIER, at)));

        assertThat(guard.membershipWindows(CARRIER, "never-hired", FROM, TO)).isEmpty();
        assertThat(guard.membershipWindows(CARRIER, RELEASED, FROM, TO)).isEmpty();
        assertThat(guard.membershipWindows(CARRIER, KEPT, TO, FROM)).isEmpty();
    }

    @Test
    @DisplayName("a whole fleet's windows come from one query, rider by rider")
    void windows_for_a_whole_fleet() {
        Instant left = Instant.parse("2026-09-08T00:00:00Z");
        when(periods.overlappingForCarrier(CARRIER, FROM, TO)).thenReturn(List.of(
                period(KEPT, Instant.parse("2026-08-01T00:00:00Z"), null),
                period(RELEASED, Instant.parse("2026-08-01T00:00:00Z"), left)));

        Map<String, List<MembershipWindow>> byRider = guard.membershipWindowsByRider(CARRIER, FROM, TO);

        assertThat(byRider).containsOnlyKeys(KEPT, RELEASED);
        assertThat(byRider.get(KEPT)).containsExactly(new MembershipWindow(FROM, TO));
        // Left during the range: their part of it, and not a day past it.
        assertThat(byRider.get(RELEASED)).containsExactly(new MembershipWindow(FROM, left));
    }

    @Test
    @DisplayName("the record says whether a rider is on a company's fleet now, for a caller with no token")
    void is_current_member_reads_the_record() {
        when(periods.findByRiderIdAndLeftAtIsNull(KEPT))
                .thenReturn(Optional.of(period(KEPT, FROM, null)));
        when(periods.findByRiderIdAndLeftAtIsNull(RELEASED)).thenReturn(Optional.empty());

        assertThat(guard.isCurrentMember(CARRIER, KEPT)).isTrue();
        assertThat(guard.isCurrentMember(UUID.randomUUID(), KEPT)).isFalse();
        assertThat(guard.isCurrentMember(CARRIER, RELEASED)).isFalse();
        verifyNoInteractions(directory);
    }

    /** A clock the test moves by hand, short of or past the window. */
    private static final class MovableClock extends Clock {

        private Instant now;

        MovableClock(Instant now) {
            this.now = now;
        }

        void advance(Duration by) {
            now = now.plus(by);
        }

        @Override
        public ZoneId getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return now;
        }
    }
}
