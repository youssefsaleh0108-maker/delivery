package com.delivery.appnotification.event;

import java.time.Duration;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.appnotification.service.ChatProperties;
import com.delivery.appnotification.service.ChatService;
import com.fasterxml.jackson.databind.ObjectMapper;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Conversations are opened and closed by the order's own history, never by a client.
 *
 * <p>That is the point of this listener and of these tests: membership has to be exactly the order's
 * customer and the order's assigned rider, so it is derived from the event that establishes the
 * pairing. There is no endpoint that starts a chat, because a caller who can name the participants
 * can name the wrong ones.
 */
class OrderChatLifecycleListenerTest {

    private static final UUID ORDER = UUID.randomUUID();

    private ChatService chat;
    private ChatProperties properties;
    private OrderChatLifecycleListener listener;

    @BeforeEach
    void setUp() {
        chat = mock(ChatService.class);
        properties = new ChatProperties();
        listener = new OrderChatLifecycleListener(chat, properties, new ObjectMapper());

        when(chat.openForRider(any(UUID.class), anyString(), anyString()))
                .thenReturn(Optional.empty());
    }

    private static String snapshot(String status) {
        return """
                {"orderId":"%s","customerId":"customer-sub","riderId":"rider-sub",
                 "status":"%s","totalAmount":12.50}
                """.formatted(ORDER, status);
    }

    private void deliver(String eventType, String payload) {
        listener.onOrderEvent(payload, eventType, eventType, "corr-1");
    }

    @Nested
    @DisplayName("a rider being assigned")
    class RiderAssigned {

        @Test
        @DisplayName("opens the conversation between that order's customer and that order's rider")
        void opens_the_conversation() {
            deliver("order.rider_assigned", snapshot("ASSIGNED"));

            verify(chat).openForRider(ORDER, "customer-sub", "rider-sub");
        }
    }

    @Nested
    @DisplayName("an order ending")
    class OrderEnds {

        /**
         * The conversation a customer needs after a delivery starts when they unpack the bag, not
         * when they take it.
         */
        @Test
        @DisplayName("leaves the line open for the configured window after a delivery")
        void a_delivery_starts_the_grace_window() {
            deliver("order.delivered", snapshot("DELIVERED"));

            verify(chat).closeAfter(ORDER, properties.getCloseAfterDelivery());
        }

        /** No delivery to ask about, and usually a rider who never reached the address. */
        @Test
        @DisplayName("shuts the line at once when the order is cancelled")
        void a_cancellation_closes_it_immediately() {
            deliver("order.cancelled", snapshot("CANCELLED"));

            verify(chat).closeAfter(ORDER, Duration.ZERO);
        }
    }

    @Nested
    @DisplayName("events this service has no business acting on")
    class Ignored {

        /** A status change does not alter who is in the conversation. */
        @Test
        @DisplayName("a plain status change neither opens nor closes anything")
        void a_status_change_changes_nothing() {
            deliver("order.status_changed", snapshot("PREPARING"));

            verify(chat, never()).openForRider(any(UUID.class), anyString(), anyString());
            verify(chat, never()).closeAfter(any(UUID.class), any(Duration.class));
        }

        @Test
        @DisplayName("an event type nobody has taught this listener about is simply left alone")
        void an_unknown_type_is_left_alone() {
            deliver("order.reheated", snapshot("MYSTERY"));

            verify(chat, never()).openForRider(any(UUID.class), anyString(), anyString());
        }
    }

    @Nested
    @DisplayName("a message this listener cannot make sense of")
    class Malformed {

        /**
         * Acked rather than requeued. A message that throws out of a listener comes straight back
         * and stalls every later event behind it — a poison pill that would stop conversations
         * opening for every order after it.
         */
        @Test
        @DisplayName("is swallowed rather than allowed to become a poison pill on the queue")
        void does_not_throw_back_at_the_broker() {
            assertThatCode(() -> deliver("order.rider_assigned", "this is not json"))
                    .doesNotThrowAnyException();
            assertThatCode(() -> deliver("order.rider_assigned", "{\"noOrderId\":true}"))
                    .doesNotThrowAnyException();
            assertThatCode(() -> deliver(null, snapshot("ASSIGNED")))
                    .doesNotThrowAnyException();
        }

        @Test
        @DisplayName("does not open a conversation on the strength of a payload it could not read")
        void opens_nothing_from_an_unreadable_payload() {
            deliver("order.rider_assigned", "{\"orderId\":\"not-a-uuid\"}");

            verify(chat, never()).openForRider(any(UUID.class), anyString(), anyString());
        }
    }

    @Nested
    @DisplayName("an order with no rider on it")
    class NoRider {

        /**
         * An errand or a snapshot published before assignment. The service refuses to open a
         * one-sided conversation; the listener's job is only to not crash on the way there.
         */
        @Test
        @DisplayName("is passed through with a null rider rather than guessed at")
        void passes_the_null_through() {
            String noRider = """
                    {"orderId":"%s","customerId":"customer-sub","riderId":null,"status":"PLACED"}
                    """.formatted(ORDER);
            when(chat.openForRider(any(UUID.class), anyString(), eq(null)))
                    .thenReturn(Optional.empty());

            deliver("order.rider_assigned", noRider);

            verify(chat).openForRider(ORDER, "customer-sub", null);
        }
    }
}
