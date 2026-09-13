package com.delivery.tracking.event;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.delivery.tracking.domain.OrderParticipants;
import com.delivery.tracking.domain.OrderParticipantsRepository;
import com.delivery.tracking.service.MembershipPeriodRecorder;
import com.delivery.tracking.service.PresenceService;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * An order naming a rider and a fleet, weighed against what Order Manager has said about the rider.
 *
 * <p>Until membership events existed an order was the only evidence of whose rider somebody was.
 * It still is for a rider the record knows nothing about; it is not once the record says the rider
 * works elsewhere — or nowhere — because a late or replayed order would otherwise put a rider back
 * on the roster of a company that let them go.
 */
@DisplayName("an order naming a rider's fleet, against what Order Manager has said")
class OrderEventListenerMembershipTest {

    private static final UUID SWIFT = UUID.fromString("5857ac51-0000-4000-8000-000000000001");

    private OrderParticipantsRepository participants;
    private PresenceService presence;
    private MembershipPeriodRecorder periods;
    private OrderEventListener listener;

    @BeforeEach
    void setUp() {
        participants = mock(OrderParticipantsRepository.class);
        presence = mock(PresenceService.class);
        periods = mock(MembershipPeriodRecorder.class);
        when(participants.findById(any())).thenReturn(Optional.empty());
        when(participants.save(any(OrderParticipants.class))).thenAnswer(call -> call.getArgument(0));
        listener = new OrderEventListener(participants, presence, new ObjectMapper(), periods);
    }

    private static String orderCarriedBy(String rider, UUID fleet) {
        return "{\"orderId\":\"" + UUID.randomUUID() + "\",\"customerId\":\"customer-sub\","
                + "\"merchantId\":\"merchant-sub\",\"riderId\":\"" + rider + "\","
                + "\"status\":\"PICKED_UP\",\"deliveryProviderId\":\"" + fleet + "\"}";
    }

    @Test
    @DisplayName("an order still teaches the fleet of a rider the record has not placed")
    void an_order_teaches_an_unrecorded_riders_fleet() {
        when(periods.mayInferFromOrder("rider-a", SWIFT)).thenReturn(true);

        listener.onOrderEvent(orderCarriedBy("rider-a", SWIFT), null);

        verify(presence).learnCarrier("rider-a", SWIFT);
    }

    @Test
    @DisplayName("a late order for a company the rider has left does not put them back on its roster")
    void a_late_order_does_not_reattach_a_departed_rider() {
        when(periods.mayInferFromOrder("rider-a", SWIFT)).thenReturn(false);

        listener.onOrderEvent(orderCarriedBy("rider-a", SWIFT), null);

        verify(presence, never()).learnCarrier(anyString(), any());
        // The order itself is still recorded: who may watch that delivery is a separate question.
        verify(participants).save(any(OrderParticipants.class));
    }
}
