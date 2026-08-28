package com.delivery.tracking.service;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

import com.delivery.tracking.domain.CarrierMembership;
import com.delivery.tracking.domain.CarrierMembershipRepository;
import com.delivery.tracking.domain.DutySession;
import com.delivery.tracking.domain.DutySessionRepository;
import com.delivery.tracking.domain.DutyState;
import com.delivery.tracking.domain.OrderParticipantsRepository;
import com.delivery.tracking.domain.PresenceState;
import com.delivery.tracking.domain.RiderDutyEvent;
import com.delivery.tracking.domain.RiderDutyEventRepository;
import com.delivery.tracking.domain.RiderPresence;
import com.delivery.tracking.domain.RiderPresenceRepository;
import com.delivery.tracking.service.PresenceService.RiderPresenceView;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyFloat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Whether a rider is working, and who is allowed to know where they are.
 *
 * <p>Two rules carry the weight. A declaration of duty is not evidence of presence — the platform
 * only believes a rider is out there while their phone keeps saying so, because a handset that dies
 * cannot send a message announcing it. And a rider's live position is personal data about a worker,
 * so the set of people who may read it is short, specific, and closes again when the delivery ends.
 */
class PresenceServiceTest {

    private static final String RIDER = "rider-sub";
    private static final String CUSTOMER = "customer-sub";
    private static final String DISPATCHER = "dispatcher-sub";
    private static final UUID CARRIER = UUID.randomUUID();
    private static final UUID OTHER_CARRIER = UUID.randomUUID();
    private static final Duration PRESENCE_WINDOW = Duration.ofMinutes(2);
    private static final String CACHE_KEY = "delivery:tracking:presence:" + RIDER;

    private RiderPresenceRepository presenceRepo;
    private RiderDutyEventRepository dutyEvents;
    private DutySessionRepository dutySessions;
    private CarrierMembershipRepository memberships;
    private OrderParticipantsRepository participants;
    private StringRedisTemplate redis;
    private ValueOperations<String, String> values;
    private PresenceService presence;

    @BeforeEach
    void setUp() {
        presenceRepo = mock(RiderPresenceRepository.class);
        dutyEvents = mock(RiderDutyEventRepository.class);
        dutySessions = mock(DutySessionRepository.class);
        memberships = mock(CarrierMembershipRepository.class);
        participants = mock(OrderParticipantsRepository.class);
        redis = mock(StringRedisTemplate.class);
        values = mock(ValueOperations.class);

        when(redis.opsForValue()).thenReturn(values);
        when(presenceRepo.save(any(RiderPresence.class))).thenAnswer(c -> c.getArgument(0));
        when(presenceRepo.findById(anyString())).thenReturn(Optional.empty());
        when(memberships.findById(anyString())).thenReturn(Optional.empty());
        when(dutySessions.findByRiderIdAndEndedAtIsNull(anyString())).thenReturn(Optional.empty());

        presence = new PresenceService(presenceRepo, dutyEvents, dutySessions, memberships,
                participants, redis, new ObjectMapper().registerModule(new JavaTimeModule()),
                PRESENCE_WINDOW, Duration.ofSeconds(30));
    }

    /** A rider row in the given state whose last fix arrived {@code fixAge} ago. */
    private RiderPresence rider(DutyState state, Duration fixAge) {
        Instant now = Instant.now();
        RiderPresence row = RiderPresence.firstSeen(RIDER, now.minus(Duration.ofHours(1)));
        row.declare(state, now.minus(Duration.ofHours(1)));
        if (fixAge != null) {
            row.sighted(33.89, 35.50, 5.0f, now.minus(fixAge));
        }
        when(presenceRepo.findById(RIDER)).thenReturn(Optional.of(row));
        return row;
    }

    private void employs(String userId, UUID carrierId, CarrierMembership.Kind kind) {
        when(memberships.findById(userId)).thenReturn(Optional.of(new CarrierMembership(
                userId, carrierId, kind, CarrierMembership.Source.ORDER_EVENT)));
    }

    @Nested
    @DisplayName("a rider is only on duty while their phone keeps saying so")
    class Freshness {

        @Test
        void a_rider_who_declared_duty_and_is_still_pinging_is_on_duty() {
            rider(DutyState.ON_DUTY, Duration.ofSeconds(5));

            assertThat(presence.ownPresence(RIDER))
                    .hasValueSatisfying(view ->
                            assertThat(view.state()).isEqualTo(PresenceState.ON_DUTY));
        }

        /**
         * The guarantee this whole class exists for. A rider whose battery died is still ON_DUTY by
         * declaration and must not be dispatchable, or the platform hands jobs to a dark phone.
         */
        @Test
        void a_rider_who_has_gone_quiet_reads_as_stale_rather_than_on_duty() {
            rider(DutyState.ON_DUTY, Duration.ofMinutes(30));

            assertThat(presence.ownPresence(RIDER)).hasValueSatisfying(view -> {
                assertThat(view.state()).isEqualTo(PresenceState.STALE);
                assertThat(view.state()).isNotEqualTo(PresenceState.ON_DUTY);
                // The declaration is untouched: this is a judgement about evidence, not a state
                // change made on the rider's behalf.
                assertThat(view.dutyState()).isEqualTo(DutyState.ON_DUTY);
            });
        }

        /** Going online before the GPS has a fix is not the same as being out there. */
        @Test
        void a_rider_who_has_declared_duty_but_never_pinged_is_not_yet_on_duty() {
            rider(DutyState.ON_DUTY, null);

            assertThat(presence.ownPresence(RIDER))
                    .hasValueSatisfying(view ->
                            assertThat(view.state()).isEqualTo(PresenceState.STALE));
        }

        /** A location is evidence a phone is alive, never consent to be given work. */
        @Test
        void a_rider_who_is_pinging_but_has_not_gone_on_duty_stays_off_duty() {
            rider(DutyState.OFF_DUTY, Duration.ofSeconds(2));

            assertThat(presence.ownPresence(RIDER))
                    .hasValueSatisfying(view ->
                            assertThat(view.state()).isEqualTo(PresenceState.OFF_DUTY));
        }

        /** Nothing has happened for this rider — which is not the same as them being off duty. */
        @Test
        void a_rider_nobody_has_ever_heard_from_has_no_presence_at_all() {
            assertThat(presence.ownPresence("unknown-rider")).isEmpty();
        }
    }

    @Nested
    @DisplayName("declaring duty")
    class Declaring {

        @Test
        void records_the_state_and_returns_what_the_platform_now_believes() {
            RiderPresenceView view = presence.declare(RIDER, DutyState.ON_DUTY,
                    RiderDutyEvent.Source.RIDER);

            assertThat(view.dutyState()).isEqualTo(DutyState.ON_DUTY);
            // No fix yet, so the honest answer is STALE rather than ON_DUTY — and the app can tell
            // the rider that instead of showing them as available for work they will not receive.
            assertThat(view.state()).isEqualTo(PresenceState.STALE);
            verify(presenceRepo).save(any(RiderPresence.class));
        }

        /** The shift log is what payroll and a late dispute read; it needs the transitions in it. */
        @Test
        void appends_a_shift_log_entry_for_a_real_transition() {
            presence.declare(RIDER, DutyState.ON_DUTY, RiderDutyEvent.Source.RIDER);

            verify(dutyEvents).save(any(RiderDutyEvent.class));
        }

        /**
         * An app that re-asserts duty every time it comes to the foreground would otherwise write a
         * row a minute and bury the real transitions in noise.
         */
        @Test
        void does_not_log_anything_when_the_state_has_not_actually_changed() {
            rider(DutyState.ON_DUTY, Duration.ofSeconds(5));

            presence.declare(RIDER, DutyState.ON_DUTY, RiderDutyEvent.Source.RIDER);

            verify(dutyEvents, never()).save(any(RiderDutyEvent.class));
        }

        /** Going off duty is a transition like any other and belongs in the log. */
        @Test
        void logs_a_rider_going_off_duty() {
            rider(DutyState.ON_DUTY, Duration.ofSeconds(5));

            presence.declare(RIDER, DutyState.OFF_DUTY, RiderDutyEvent.Source.RIDER);

            verify(dutyEvents).save(any(RiderDutyEvent.class));
        }
    }

    @Nested
    @DisplayName("duty sessions: the intervals hours-online is summed from")
    class Sessions {

        @Test
        void going_on_duty_opens_a_session() {
            presence.declare(RIDER, DutyState.ON_DUTY, RiderDutyEvent.Source.RIDER);

            ArgumentCaptor<DutySession> saved = ArgumentCaptor.forClass(DutySession.class);
            verify(dutySessions).save(saved.capture());
            assertThat(saved.getValue().isOpen()).isTrue();
            assertThat(saved.getValue().getRiderId()).isEqualTo(RIDER);
        }

        /**
         * The idempotency guarantee. An app that re-asserts ON_DUTY on every foreground must not
         * open a second shift — the reconciliation is against what is actually open, not against
         * whether this particular call happened to be a transition.
         */
        @Test
        void a_repeated_on_duty_declaration_does_not_open_a_second_session() {
            rider(DutyState.ON_DUTY, Duration.ofSeconds(5));
            when(dutySessions.findByRiderIdAndEndedAtIsNull(RIDER))
                    .thenReturn(Optional.of(DutySession.open(RIDER, Instant.now())));

            presence.declare(RIDER, DutyState.ON_DUTY, RiderDutyEvent.Source.RIDER);

            verify(dutySessions, never()).save(any(DutySession.class));
        }

        @Test
        void going_off_duty_closes_the_open_session_and_records_who_ended_it() {
            rider(DutyState.ON_DUTY, Duration.ofSeconds(5));
            DutySession open = DutySession.open(RIDER, Instant.now().minus(Duration.ofHours(3)));
            when(dutySessions.findByRiderIdAndEndedAtIsNull(RIDER)).thenReturn(Optional.of(open));

            presence.declare(RIDER, DutyState.OFF_DUTY, RiderDutyEvent.Source.RIDER);

            assertThat(open.isOpen()).isFalse();
            assertThat(open.getEndReason()).isEqualTo(DutySession.EndReason.RIDER);
            verify(dutySessions).save(open);
        }

        /**
         * History starts at the migration. A rider who was already on duty before duty_sessions
         * existed has no open session, and going off duty must close nothing rather than invent a
         * shift backwards.
         */
        @Test
        void going_off_duty_with_no_open_session_closes_nothing() {
            rider(DutyState.ON_DUTY, Duration.ofSeconds(5));

            presence.declare(RIDER, DutyState.OFF_DUTY, RiderDutyEvent.Source.RIDER);

            verify(dutySessions, never()).save(any(DutySession.class));
        }

        /**
         * The self-healing half of open-if-none: a rider whose previous session was expired starts
         * a fresh one on their next ON_DUTY declaration even if the presence row somehow still says
         * ON_DUTY — hours must start counting again the moment there is a declaration to count from.
         */
        @Test
        void an_on_duty_declaration_with_no_open_session_opens_one_even_without_a_transition() {
            rider(DutyState.ON_DUTY, Duration.ofSeconds(5));

            presence.declare(RIDER, DutyState.ON_DUTY, RiderDutyEvent.Source.RIDER);

            verify(dutySessions).save(any(DutySession.class));
            // But the transition log stays quiet: nothing actually changed state.
            verify(dutyEvents, never()).save(any(RiderDutyEvent.class));
        }
    }

    @Nested
    @DisplayName("recording a fix")
    class Fixes {

        /** A rider we have never seen gets a durable row, off duty until they say otherwise. */
        @Test
        void creates_the_durable_row_the_first_time_a_rider_is_seen() {
            presence.recordFix(RIDER, 33.89, 35.50, 5.0f);

            verify(presenceRepo).save(any(RiderPresence.class));
        }

        /**
         * The throttle. With a warm cache the durable row is only moved when it is due, which is
         * what stops presence doubling the cost of the busiest write path in the platform.
         */
        @Test
        void only_moves_the_durable_row_when_the_write_throttle_is_due() throws Exception {
            warmCacheFor(DutyState.ON_DUTY);

            presence.recordFix(RIDER, 33.89, 35.50, 5.0f);

            verify(presenceRepo).touchIfDue(eq(RIDER), anyDouble(), anyDouble(), anyFloat(),
                    any(Instant.class), any(Instant.class));
            verify(presenceRepo, never()).save(any(RiderPresence.class));
        }

        /**
         * Redis being unavailable degrades presence to a durable write per ping. Slower and
         * correct, which is the right way round — the alternative is losing sight of the fleet.
         */
        @Test
        void falls_back_to_writing_the_record_when_the_cache_is_unavailable() {
            doThrow(new IllegalStateException("redis down")).when(values).get(anyString());

            presence.recordFix(RIDER, 33.89, 35.50, 5.0f);

            verify(presenceRepo).save(any(RiderPresence.class));
        }

        /** A fix must never fail because the cache could not be written. */
        @Test
        void still_succeeds_when_the_cache_cannot_be_written() {
            doThrow(new IllegalStateException("redis down"))
                    .when(values).set(anyString(), anyString(), any(Duration.class));

            presence.recordFix(RIDER, 33.89, 35.50, 5.0f);

            verify(presenceRepo).save(any(RiderPresence.class));
        }

        /**
         * A cached snapshot must not be able to claim freshness just by still being in the cache.
         * Freshness is judged against the clock on every read, in one place, whichever store
         * answered.
         */
        @Test
        void a_cached_snapshot_still_goes_stale_on_the_clock() throws Exception {
            cache(new PresenceService.PresenceSnapshot(RIDER, CARRIER, DutyState.ON_DUTY,
                    Instant.now().minus(Duration.ofHours(2)),
                    Instant.now().minus(Duration.ofHours(1)),
                    33.89, 35.50, 5.0f));

            assertThat(presence.ownPresence(RIDER))
                    .hasValueSatisfying(view ->
                            assertThat(view.state()).isEqualTo(PresenceState.STALE));
        }

        private void warmCacheFor(DutyState state) throws Exception {
            cache(new PresenceService.PresenceSnapshot(RIDER, CARRIER, state,
                    Instant.now().minus(Duration.ofMinutes(10)), Instant.now(),
                    33.89, 35.50, 5.0f));
        }

        private void cache(PresenceService.PresenceSnapshot snapshot) throws Exception {
            String json = new ObjectMapper().registerModule(new JavaTimeModule())
                    .writeValueAsString(snapshot);
            when(values.get(CACHE_KEY)).thenReturn(json);
        }
    }

    @Nested
    @DisplayName("reading where a rider is")
    class Reading {

        /**
         * Live rider location is personal data about a worker. Somebody with no connection to this
         * rider must not be able to follow them around — and must not learn they exist either,
         * which is why this is a not-found rather than a forbidden.
         */
        @Test
        void a_stranger_is_refused_and_told_nothing() {
            rider(DutyState.ON_DUTY, Duration.ofSeconds(5));
            when(participants.customerHasLiveOrderWith(anyString(), anyString())).thenReturn(false);

            assertThatThrownBy(() -> presence.locationOf(RIDER, "stranger-sub", false))
                    .isInstanceOf(PresenceService.PresenceNotFoundException.class);
        }

        @Test
        void the_rider_may_read_their_own_position() {
            rider(DutyState.ON_DUTY, Duration.ofSeconds(5));

            assertThat(presence.locationOf(RIDER, RIDER, false).riderId()).isEqualTo(RIDER);
        }

        @Test
        void backoffice_may_read_any_riders_position() {
            rider(DutyState.ON_DUTY, Duration.ofSeconds(5));

            assertThat(presence.locationOf(RIDER, "backoffice-sub", true).riderId())
                    .isEqualTo(RIDER);
        }

        /** A dispatcher watching their own fleet is the whole point of the roster screen. */
        @Test
        void the_fleet_that_employs_the_rider_may_read_it() {
            rider(DutyState.ON_DUTY, Duration.ofSeconds(5));
            employs(RIDER, CARRIER, CarrierMembership.Kind.RIDER);
            employs(DISPATCHER, CARRIER, CarrierMembership.Kind.STAFF);

            assertThat(presence.locationOf(RIDER, DISPATCHER, false).riderId()).isEqualTo(RIDER);
        }

        /** A competitor's dispatcher is a stranger, whatever role they hold. */
        @Test
        void a_different_fleet_may_not() {
            rider(DutyState.ON_DUTY, Duration.ofSeconds(5));
            employs(RIDER, CARRIER, CarrierMembership.Kind.RIDER);
            employs(DISPATCHER, OTHER_CARRIER, CarrierMembership.Kind.STAFF);
            when(participants.customerHasLiveOrderWith(anyString(), anyString())).thenReturn(false);

            assertThatThrownBy(() -> presence.locationOf(RIDER, DISPATCHER, false))
                    .isInstanceOf(PresenceService.PresenceNotFoundException.class);
        }

        /**
         * Two riders employed by nobody — platform riders — must not be able to see each other
         * merely because they both have no carrier. An absent membership matching another absent
         * membership would grant exactly that.
         */
        @Test
        void two_riders_who_belong_to_no_fleet_are_still_strangers_to_each_other() {
            rider(DutyState.ON_DUTY, Duration.ofSeconds(5));
            when(participants.customerHasLiveOrderWith(anyString(), anyString())).thenReturn(false);

            assertThatThrownBy(() -> presence.locationOf(RIDER, "another-rider-sub", false))
                    .isInstanceOf(PresenceService.PresenceNotFoundException.class);
        }

        /** The customer waiting on this rider, while they are waiting and not afterwards. */
        @Test
        void a_customer_with_a_live_order_in_that_riders_hands_may_read_it() {
            rider(DutyState.ON_DUTY, Duration.ofSeconds(5));
            when(participants.customerHasLiveOrderWith(CUSTOMER, RIDER)).thenReturn(true);

            assertThat(presence.locationOf(RIDER, CUSTOMER, false).riderId()).isEqualTo(RIDER);
        }

        /** Once the delivery is over the customer's window closes with it. */
        @Test
        void a_customer_whose_order_has_finished_may_not() {
            rider(DutyState.ON_DUTY, Duration.ofSeconds(5));
            when(participants.customerHasLiveOrderWith(CUSTOMER, RIDER)).thenReturn(false);

            assertThatThrownBy(() -> presence.locationOf(RIDER, CUSTOMER, false))
                    .isInstanceOf(PresenceService.PresenceNotFoundException.class);
        }

        /** Nothing about a rider id is echoed back into a body something might render. */
        @Test
        void the_refusal_does_not_reflect_the_requested_id_back_to_the_caller() {
            when(participants.customerHasLiveOrderWith(anyString(), anyString())).thenReturn(false);

            assertThatThrownBy(() ->
                    presence.locationOf("<script>alert(1)</script>", "stranger-sub", false))
                    .isInstanceOf(PresenceService.PresenceNotFoundException.class)
                    .hasMessageNotContaining("script");
        }
    }

    @Nested
    @DisplayName("the fleet roster")
    class Roster {

        @Test
        void backoffice_sees_every_fleet_when_it_names_none() {
            RiderPresence onDuty = rider(DutyState.ON_DUTY, Duration.ofSeconds(5));
            when(presenceRepo.findByDutyStateOrderByLastSeenAtDesc(DutyState.ON_DUTY))
                    .thenReturn(List.of(onDuty));

            assertThat(presence.roster("backoffice-sub", true, null, true)).hasSize(1);
        }

        /**
         * A carrier cannot name a company — the same rule Order Manager applies to a carrier's job
         * list. A carrierId in the query string from a carrier is ignored outright, so there is no
         * request shape that reads a competitor's fleet.
         */
        @Test
        void a_carrier_is_scoped_to_their_own_fleet_whatever_they_ask_for() {
            employs(DISPATCHER, CARRIER, CarrierMembership.Kind.STAFF);

            presence.roster(DISPATCHER, false, OTHER_CARRIER, true);

            verify(presenceRepo).findByCarrierIdAndDutyStateOrderByLastSeenAtDesc(
                    CARRIER, DutyState.ON_DUTY);
            verify(presenceRepo, never()).findByCarrierIdAndDutyStateOrderByLastSeenAtDesc(
                    eq(OTHER_CARRIER), any(DutyState.class));
        }

        /**
         * A provisioning mistake rather than an empty fleet, and it has to read as one — an empty
         * list looks exactly like a company that has never been given any work.
         */
        @Test
        void a_carrier_who_belongs_to_no_company_is_told_so_rather_than_shown_an_empty_list() {
            assertThatThrownBy(() -> presence.roster(DISPATCHER, false, null, true))
                    .isInstanceOf(PresenceService.NoCarrierException.class);
        }

        /**
         * Riders who declared duty and then went quiet stay on the roster, marked STALE. Filtering
         * them out would hide precisely the problem a dispatcher opened the screen to find.
         */
        @Test
        void keeps_riders_who_have_gone_quiet_on_it_and_marks_them() {
            RiderPresence goneQuiet = rider(DutyState.ON_DUTY, Duration.ofMinutes(45));
            when(presenceRepo.findByDutyStateOrderByLastSeenAtDesc(DutyState.ON_DUTY))
                    .thenReturn(List.of(goneQuiet));

            assertThat(presence.roster("backoffice-sub", true, null, true))
                    .singleElement()
                    .satisfies(view -> assertThat(view.state()).isEqualTo(PresenceState.STALE));
        }
    }
}
