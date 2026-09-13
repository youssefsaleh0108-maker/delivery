package com.delivery.tracking.event;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

import java.time.Instant;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.delivery.tracking.service.MembershipPeriodRecorder;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Reading Order Manager's {@code carrier.member_joined} / {@code carrier.member_left} events.
 *
 * <p>The instant recorded is the change's own, however it was written; a payload that cannot be
 * read is dropped rather than left to block the queue; and a payload that was read but could not be
 * stored goes back to the broker, so a period is never silently lost.
 */
@DisplayName("reading Order Manager's membership events")
class CarrierMembershipEventListenerTest {

    private static final UUID SWIFT = UUID.fromString("5857ac51-0000-4000-8000-000000000001");

    private MembershipPeriodRecorder recorder;
    private CarrierMembershipEventListener listener;

    @BeforeEach
    void setUp() {
        recorder = mock(MembershipPeriodRecorder.class);
        listener = new CarrierMembershipEventListener(recorder, new ObjectMapper());
    }

    private static String event(String change, String at) {
        return "{\"riderRef\":\"rider-a\",\"providerId\":\"" + SWIFT + "\""
                + (change == null ? "" : ",\"change\":\"" + change + "\"")
                + ",\"at\":" + at + "}";
    }

    @Test
    @DisplayName("a join is recorded at the instant of the change")
    void a_join_is_recorded() {
        listener.onMembershipEvent(event("JOINED", "\"2026-09-01T08:00:00.123456Z\""),
                "carrier.member_joined");

        verify(recorder).joined("rider-a", SWIFT, Instant.parse("2026-09-01T08:00:00.123456Z"));
    }

    @Test
    @DisplayName("a leave written as epoch seconds is read to the same instant")
    void a_leave_in_epoch_seconds_is_read() {
        listener.onMembershipEvent(event("LEFT", "1788249600.5"), "carrier.member_left");

        verify(recorder).left("rider-a", SWIFT, Instant.ofEpochSecond(1788249600L, 500_000_000));
    }

    @Test
    @DisplayName("the event-type header stands in for a payload that does not say which")
    void the_header_names_the_change_when_the_payload_does_not() {
        listener.onMembershipEvent(event(null, "\"2026-09-01T08:00:00Z\""), "carrier.member_left");

        verify(recorder).left("rider-a", SWIFT, Instant.parse("2026-09-01T08:00:00Z"));
    }

    @Test
    @DisplayName("a payload that cannot be read is dropped, not requeued in front of everything else")
    void an_unreadable_payload_is_dropped() {
        listener.onMembershipEvent("not json at all", "carrier.member_joined");
        listener.onMembershipEvent("{\"riderRef\":\"rider-a\"}", "carrier.member_left");
        listener.onMembershipEvent("{\"riderRef\":\"rider-a\",\"providerId\":\"not-a-uuid\","
                + "\"change\":\"JOINED\",\"at\":\"2026-09-01T08:00:00Z\"}", null);
        listener.onMembershipEvent(event("JOINED", "\"yesterday\""), null);

        verifyNoInteractions(recorder);
    }

    @Test
    @DisplayName("a change that could not be stored goes back to the broker instead of vanishing")
    void a_failure_to_store_is_redelivered() {
        doThrow(new IllegalStateException("database unavailable"))
                .when(recorder).joined(any(), any(), any());

        assertThatThrownBy(() -> listener.onMembershipEvent(
                event("JOINED", "\"2026-09-01T08:00:00Z\""), "carrier.member_joined"))
                .isInstanceOf(IllegalStateException.class);
    }
}
