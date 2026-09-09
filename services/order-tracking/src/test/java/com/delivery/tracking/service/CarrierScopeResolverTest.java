package com.delivery.tracking.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

import com.delivery.tracking.client.CarrierDirectoryClient;
import com.delivery.tracking.client.CarrierDirectoryClient.DirectoryUnavailableException;
import com.delivery.tracking.domain.CarrierMembership;
import com.delivery.tracking.domain.CarrierMembershipRepository;

/**
 * How this service learns whose fleet a caller may see.
 *
 * <p>Before this resolver, the answer came from {@code carrier_membership} alone, whose only
 * writer infers a rider's fleet from an order that named both. A delivery company's office staff
 * carry no orders, so no order ever named them, so they never had a row — and the roster, a
 * rider's live position and the hours columns were 403 for <em>every carrier account on the
 * platform</em>, permanently, from the day it was provisioned. The console could not see the fleet
 * it exists to run.
 *
 * <p>The tests below are about the two halves of the fix that are easy to get wrong: a cached
 * answer must not outlive the job it was read for, and an outage must not be mistaken for either
 * a departure or a permission.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("resolving whose fleet a caller may see")
class CarrierScopeResolverTest {

    private static final String STAFF = "carrier-office-sub";
    private static final String TOKEN = "carrier-token";
    private static final UUID COMPANY = UUID.fromString("5857ac51-0000-4000-8000-000000000001");
    private static final UUID OTHER_COMPANY = UUID.fromString("5857ac51-0000-4000-8000-000000000002");

    @Mock
    private CarrierMembershipRepository memberships;
    @Mock
    private CarrierDirectoryClient directory;

    private CarrierScopeResolver resolver;

    @BeforeEach
    void setUp() {
        resolver = new CarrierScopeResolver(memberships, directory, Duration.ofMinutes(15));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private static void signedInAs(String subject, String tokenValue) {
        signedInAs(subject, tokenValue, "CARRIER");
    }

    private static void signedInAs(String subject, String tokenValue, String role) {
        Jwt jwt = Jwt.withTokenValue(tokenValue)
                .header("alg", "none")
                .subject(subject)
                .claim("realm_access", Map.of("roles", List.of(role)))
                .build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(
                jwt, List.of(new SimpleGrantedAuthority("ROLE_" + role))));
    }

    private static CarrierMembership row(UUID company, CarrierMembership.Kind kind,
                                         CarrierMembership.Source source, Instant updatedAt) {
        CarrierMembership m = new CarrierMembership(STAFF, company, kind, source);
        if (updatedAt != null) {
            // The row's own clock is set on construction; wind it back to age it.
            try {
                java.lang.reflect.Field f = CarrierMembership.class.getDeclaredField("updatedAt");
                f.setAccessible(true);
                f.set(m, updatedAt);
            } catch (ReflectiveOperationException e) {
                throw new AssertionError(e);
            }
        }
        return m;
    }

    @Nested
    @DisplayName("an account this service has never heard of")
    class FirstSight {

        @Test
        void is_looked_up_in_the_directory_and_remembered() {
            signedInAs(STAFF, TOKEN);
            when(memberships.findById(STAFF)).thenReturn(Optional.empty());
            when(directory.companyFor(TOKEN)).thenReturn(Optional.of(COMPANY));

            assertThat(resolver.scopeFor(STAFF)).contains(COMPANY);

            ArgumentCaptor<CarrierMembership> saved =
                    ArgumentCaptor.forClass(CarrierMembership.class);
            verify(memberships).save(saved.capture());
            // STAFF, not RIDER: office staff may read their fleet and must never appear on it.
            assertThat(saved.getValue().getMemberKind()).isEqualTo(CarrierMembership.Kind.STAFF);
            assertThat(saved.getValue().getSource()).isEqualTo(CarrierMembership.Source.DIRECTORY);
            assertThat(saved.getValue().getCarrierId()).isEqualTo(COMPANY);
        }

        @Test
        void that_belongs_to_no_company_is_empty_and_writes_nothing() {
            signedInAs(STAFF, TOKEN);
            when(memberships.findById(STAFF)).thenReturn(Optional.empty());
            when(directory.companyFor(TOKEN)).thenReturn(Optional.empty());

            assertThat(resolver.scopeFor(STAFF)).isEmpty();
            verify(memberships, never()).save(any());
        }

        @Test
        void is_refused_by_requireScopeFor_with_something_true() {
            signedInAs(STAFF, TOKEN);
            when(memberships.findById(STAFF)).thenReturn(Optional.empty());
            when(directory.companyFor(TOKEN)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> resolver.requireScopeFor(STAFF))
                    .isInstanceOf(PresenceService.NoCarrierException.class)
                    .hasMessageContaining("not a member of any delivery company");
        }

        /** No token, no question: the directory only ever answers about the holder of one. */
        @Test
        void is_not_looked_up_when_the_caller_is_somebody_else() {
            signedInAs("a-different-person", TOKEN);
            when(memberships.findById(STAFF)).thenReturn(Optional.empty());

            assertThat(resolver.scopeFor(STAFF)).isEmpty();
            verifyNoInteractions(directory);
        }

        /**
         * The customer watching their own delivery.
         *
         * <p>locationOf asks whose fleet the CALLER belongs to for every caller, so without this
         * gate a customer refreshing a tracking screen sent a lookup to Order Manager every few
         * seconds — which its own role gate answers 403 to, which arrived back as a 503 on the
         * customer's map. Found on the live environment, not here, which is why it is here now.
         */
        @Test
        void is_not_looked_up_at_all_for_a_caller_who_is_not_carrier_staff() {
            signedInAs(STAFF, TOKEN, "CUSTOMER");
            when(memberships.findById(STAFF)).thenReturn(Optional.empty());

            assertThat(resolver.scopeFor(STAFF)).isEmpty();
            verifyNoInteractions(directory);
        }
    }

    @Nested
    @DisplayName("an account we already hold a row for")
    class Cached {

        @Test
        void is_answered_without_asking_the_directory_again() {
            signedInAs(STAFF, TOKEN);
            when(memberships.findById(STAFF)).thenReturn(Optional.of(row(
                    COMPANY, CarrierMembership.Kind.STAFF, CarrierMembership.Source.DIRECTORY,
                    Instant.now())));

            assertThat(resolver.scopeFor(STAFF)).contains(COMPANY);
            verifyNoInteractions(directory);
        }

        /** A rider's row is an order-event inference and asking about somebody else cannot improve it. */
        @Test
        void from_an_order_event_is_never_re_checked() {
            signedInAs(STAFF, TOKEN);
            when(memberships.findById(STAFF)).thenReturn(Optional.of(row(
                    COMPANY, CarrierMembership.Kind.RIDER, CarrierMembership.Source.ORDER_EVENT,
                    Instant.now().minus(Duration.ofDays(30)))));

            assertThat(resolver.scopeFor(STAFF)).contains(COMPANY);
            verifyNoInteractions(directory);
        }

        @Test
        void is_re_checked_once_it_ages_past_the_window() {
            signedInAs(STAFF, TOKEN);
            when(memberships.findById(STAFF)).thenReturn(Optional.of(row(
                    COMPANY, CarrierMembership.Kind.STAFF, CarrierMembership.Source.DIRECTORY,
                    Instant.now().minus(Duration.ofHours(1)))));
            when(directory.companyFor(TOKEN)).thenReturn(Optional.of(OTHER_COMPANY));

            // Somebody moved companies. The console must follow them, not their old fleet.
            assertThat(resolver.scopeFor(STAFF)).contains(OTHER_COMPANY);
        }

        @Test
        void is_deleted_when_the_directory_no_longer_places_them_in_a_company() {
            signedInAs(STAFF, TOKEN);
            CarrierMembership existing = row(COMPANY, CarrierMembership.Kind.STAFF,
                    CarrierMembership.Source.DIRECTORY, Instant.now().minus(Duration.ofHours(1)));
            when(memberships.findById(STAFF)).thenReturn(Optional.of(existing));
            when(directory.companyFor(TOKEN)).thenReturn(Optional.empty());

            assertThat(resolver.scopeFor(STAFF)).isEmpty();
            // The row is the only thing granting sight of that fleet. A departure has to remove it,
            // or a former dispatcher keeps watching riders they no longer work with.
            verify(memberships).delete(existing);
        }
    }

    @Nested
    @DisplayName("when Order Manager cannot be reached")
    class Outage {

        @Test
        void a_known_caller_keeps_the_fleet_they_already_had() {
            signedInAs(STAFF, TOKEN);
            CarrierMembership existing = row(COMPANY, CarrierMembership.Kind.STAFF,
                    CarrierMembership.Source.DIRECTORY, Instant.now().minus(Duration.ofHours(1)));
            when(memberships.findById(STAFF)).thenReturn(Optional.of(existing));
            when(directory.companyFor(anyString()))
                    .thenThrow(new DirectoryUnavailableException("down", null));

            // An outage is not a departure: the console keeps working on the last known answer
            // rather than emptying, which would read as every rider having gone offline at once.
            assertThat(resolver.scopeFor(STAFF)).contains(COMPANY);
            verify(memberships, never()).delete(any());
        }

        @Test
        void an_unknown_caller_gets_the_outage_and_not_a_refusal() {
            signedInAs(STAFF, TOKEN);
            when(memberships.findById(STAFF)).thenReturn(Optional.empty());
            when(directory.companyFor(anyString()))
                    .thenThrow(new DirectoryUnavailableException("down", null));

            // Unknown is not permission — and it is not "you belong to no company" either, which
            // would send a dispatcher looking for a provisioning fix that does not exist.
            assertThatThrownBy(() -> resolver.scopeFor(STAFF))
                    .isInstanceOf(DirectoryUnavailableException.class);
        }
    }
}
