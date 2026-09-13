package com.delivery.tracking.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.stubbing.Answer;

import com.delivery.tracking.domain.CarrierMembership;
import com.delivery.tracking.domain.CarrierMembershipPeriod;
import com.delivery.tracking.domain.CarrierMembershipPeriodRepository;
import com.delivery.tracking.domain.CarrierMembershipRepository;
import com.delivery.tracking.domain.RiderPresence;
import com.delivery.tracking.domain.RiderPresenceRepository;

/**
 * Keeping when each rider was each company's, from Order Manager's membership events.
 *
 * <p>The bus delivers at least once and not always in order, so the record must come out the same
 * however the events arrive: a repeat changes nothing, a leave that overtakes its join leaves
 * nothing open, and a move is one boundary whichever half lands first.
 */
@DisplayName("keeping when each rider was each company's")
class MembershipPeriodRecorderTest {

    private static final String RIDER = "rider-sub";
    private static final UUID SWIFT = UUID.fromString("5857ac51-0000-4000-8000-000000000001");
    private static final UUID RAPID = UUID.fromString("5857ac51-0000-4000-8000-000000000002");
    private static final Instant T1 = Instant.parse("2026-09-01T08:00:00Z");
    private static final Instant T2 = Instant.parse("2026-09-05T08:00:00Z");
    private static final Instant T3 = Instant.parse("2026-09-09T08:00:00Z");

    /** The table, as the recorder's queries would find it. */
    private final List<CarrierMembershipPeriod> table = new ArrayList<>();

    private CarrierMembershipPeriodRepository periods;
    private RiderPresenceRepository presence;
    private CarrierMembershipRepository memberships;
    private MembershipPeriodRecorder recorder;

    @BeforeEach
    void setUp() {
        periods = mock(CarrierMembershipPeriodRepository.class);
        presence = mock(RiderPresenceRepository.class);
        memberships = mock(CarrierMembershipRepository.class);
        when(presence.findById(anyString())).thenReturn(Optional.empty());
        when(presence.save(any(RiderPresence.class))).thenAnswer(call -> call.getArgument(0));
        when(memberships.findById(anyString())).thenReturn(Optional.empty());

        Answer<CarrierMembershipPeriod> keep = call -> {
            CarrierMembershipPeriod period = call.getArgument(0);
            if (table.stream().noneMatch(row -> row == period)) {
                table.add(period);
            }
            return period;
        };
        when(periods.save(any(CarrierMembershipPeriod.class))).thenAnswer(keep);
        when(periods.saveAndFlush(any(CarrierMembershipPeriod.class))).thenAnswer(keep);
        when(periods.findByRiderIdOrderByJoinedAtAsc(anyString()))
                .thenAnswer(call -> rowsOf(call.getArgument(0)));
        when(periods.findByRiderIdAndLeftAtIsNull(anyString()))
                .thenAnswer(call -> rowsOf(call.getArgument(0)).stream()
                        .filter(CarrierMembershipPeriod::isOpen)
                        .findFirst());
        when(periods.existsByRiderIdAndCarrierIdAndJoinedAt(anyString(), any(), any()))
                .thenAnswer(call -> rowsOf(call.getArgument(0)).stream()
                        .anyMatch(row -> row.getCarrierId().equals(call.getArgument(1))
                                && row.getJoinedAt().equals(call.getArgument(2))));
        when(periods.existsByRiderIdAndCarrierIdAndLeftAt(anyString(), any(), any()))
                .thenAnswer(call -> rowsOf(call.getArgument(0)).stream()
                        .anyMatch(row -> row.getCarrierId().equals(call.getArgument(1))
                                && call.getArgument(2).equals(row.getLeftAt())));

        recorder = new MembershipPeriodRecorder(periods, presence, memberships);
    }

    private List<CarrierMembershipPeriod> rowsOf(String rider) {
        return table.stream()
                .filter(row -> row.getRiderId().equals(rider))
                .sorted(Comparator.comparing(CarrierMembershipPeriod::getJoinedAt))
                .toList();
    }

    /** The record for the rider, one "fleet from until" line per period, oldest first. */
    private List<String> record() {
        return rowsOf(RIDER).stream()
                .map(row -> line(row.getCarrierId(), row.getJoinedAt(), row.getLeftAt()))
                .toList();
    }

    private static String line(UUID carrier, Instant from, Instant until) {
        return (SWIFT.equals(carrier) ? "swift" : "rapid") + " " + from + " " + until;
    }

    @Test
    @DisplayName("a join and then a leave are one period, from the one until the other")
    void a_join_and_a_leave_are_one_period() {
        recorder.joined(RIDER, SWIFT, T1);
        recorder.left(RIDER, SWIFT, T2);

        assertThat(record()).containsExactly(line(SWIFT, T1, T2));
    }

    @Test
    @DisplayName("the same join delivered twice is still one period")
    void a_redelivered_join_changes_nothing() {
        recorder.joined(RIDER, SWIFT, T1);
        recorder.joined(RIDER, SWIFT, T1);

        assertThat(record()).containsExactly(line(SWIFT, T1, null));
    }

    @Test
    @DisplayName("the same leave delivered twice leaves the period as the first one closed it")
    void a_redelivered_leave_changes_nothing() {
        recorder.joined(RIDER, SWIFT, T1);
        recorder.left(RIDER, SWIFT, T2);
        recorder.left(RIDER, SWIFT, T2);

        assertThat(record()).containsExactly(line(SWIFT, T1, T2));
    }

    @Test
    @DisplayName("a move ends the old period where the new one starts, whichever half arrives first")
    void a_move_is_one_boundary() {
        recorder.joined(RIDER, SWIFT, T1);
        recorder.joined(RIDER, RAPID, T2);
        // The move's own leave, arriving second.
        recorder.left(RIDER, SWIFT, T2);

        assertThat(record()).containsExactly(line(SWIFT, T1, T2), line(RAPID, T2, null));
    }

    @Test
    @DisplayName("a leave that overtook its join leaves nothing open behind it")
    void a_leave_ahead_of_its_join_opens_nothing() {
        recorder.left(RIDER, SWIFT, T2);
        recorder.joined(RIDER, SWIFT, T1);

        assertThat(record()).containsExactly(line(SWIFT, T2, T2));
        assertThat(rowsOf(RIDER)).noneMatch(CarrierMembershipPeriod::isOpen);
    }

    @Test
    @DisplayName("a join older than the record's latest change is ignored")
    void a_stale_join_is_ignored() {
        recorder.joined(RIDER, SWIFT, T1);
        recorder.left(RIDER, SWIFT, T3);
        recorder.joined(RIDER, RAPID, T2);

        assertThat(record()).containsExactly(line(SWIFT, T1, T3));
    }

    @Test
    @DisplayName("a rider who comes back gets a second period, and the time away stays out")
    void a_return_is_a_new_period() {
        recorder.joined(RIDER, SWIFT, T1);
        recorder.left(RIDER, SWIFT, T2);
        recorder.joined(RIDER, SWIFT, T3);

        assertThat(record()).containsExactly(line(SWIFT, T1, T2), line(SWIFT, T3, null));
    }

    @Test
    @DisplayName("joining points the roster at the new fleet, with the event's authority")
    void a_join_links_the_rider() {
        recorder.joined(RIDER, SWIFT, T1);

        ArgumentCaptor<CarrierMembership> membership = ArgumentCaptor.forClass(CarrierMembership.class);
        verify(memberships).save(membership.capture());
        assertThat(membership.getValue().getCarrierId()).isEqualTo(SWIFT);
        // Outranks an order event's inference, so a late order for another fleet cannot move it.
        assertThat(membership.getValue().getSource()).isEqualTo(CarrierMembership.Source.MEMBERSHIP);
        ArgumentCaptor<RiderPresence> presenceRow = ArgumentCaptor.forClass(RiderPresence.class);
        verify(presence).save(presenceRow.capture());
        assertThat(presenceRow.getValue().getCarrierId()).isEqualTo(SWIFT);
    }

    @Test
    @DisplayName("leaving unlinks the rider from that company, and only from that company")
    void a_leave_unlinks_the_rider_from_the_company_named() {
        RiderPresence onRoster = RiderPresence.firstSeen(RIDER, T1);
        onRoster.attachCarrier(SWIFT, T1);
        CarrierMembership inferred = new CarrierMembership(RIDER, SWIFT,
                CarrierMembership.Kind.RIDER, CarrierMembership.Source.ORDER_EVENT);
        when(presence.findById(RIDER)).thenReturn(Optional.of(onRoster));
        when(memberships.findById(RIDER)).thenReturn(Optional.of(inferred));

        // A leave from a company the rider is not linked to touches nothing.
        recorder.left(RIDER, RAPID, T2);
        assertThat(onRoster.getCarrierId()).isEqualTo(SWIFT);
        verify(memberships, never()).delete(any(CarrierMembership.class));

        recorder.left(RIDER, SWIFT, T2);
        assertThat(onRoster.getCarrierId()).isNull();
        verify(memberships).delete(inferred);
    }

    @Test
    @DisplayName("an order may only confirm the fleet the record holds, once the record holds any")
    void orders_confirm_only_the_recorded_fleet() {
        // Nothing on record: the order is the best evidence there is, as it always was.
        assertThat(recorder.mayInferFromOrder(RIDER, SWIFT)).isTrue();

        recorder.joined(RIDER, SWIFT, T1);
        assertThat(recorder.mayInferFromOrder(RIDER, SWIFT)).isTrue();
        assertThat(recorder.mayInferFromOrder(RIDER, RAPID)).isFalse();

        recorder.left(RIDER, SWIFT, T2);
        assertThat(recorder.mayInferFromOrder(RIDER, SWIFT)).isFalse();
    }
}
