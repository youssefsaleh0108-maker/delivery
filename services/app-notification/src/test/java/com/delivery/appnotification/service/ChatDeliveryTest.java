package com.delivery.appnotification.service;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.messaging.simp.user.SimpSession;
import org.springframework.messaging.simp.user.SimpSubscription;
import org.springframework.messaging.simp.user.SimpUser;
import org.springframework.messaging.simp.user.SimpUserRegistry;

import com.delivery.appnotification.domain.ChatMessageRepository;
import com.delivery.appnotification.domain.ChatParticipantRole;
import com.delivery.platform.notifications.ChatEvents;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.json.JsonMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Getting a stored message in front of the person it is for.
 *
 * <p>Two routes and one rule: whichever is taken, the message is already committed, so the worst a
 * failure here can do is make the recipient wait until their app next fetches the thread. What these
 * tests pin down is that the choice between the routes is made on whether a frame actually has
 * somewhere to land, and that the sender's own text cannot break either payload on the way out.
 */
class ChatDeliveryTest {

    private static final UUID ORDER = UUID.randomUUID();
    private static final UUID CONVERSATION = UUID.randomUUID();
    private static final String RECIPIENT = "rider-sub";
    private static final String EXCHANGE = "delivery.events";

    private SimpMessagingTemplate websocket;
    private SimpUserRegistry connectedUsers;
    private ChatMessageRepository messages;
    private RabbitTemplate rabbit;
    private ChatProperties properties;
    private ChatDelivery delivery;

    /** Boot's own mapper registers this module; without it an Instant is not serialisable at all. */
    private final ObjectMapper objectMapper =
            JsonMapper.builder().addModule(new JavaTimeModule()).build();

    @BeforeEach
    void setUp() {
        websocket = mock(SimpMessagingTemplate.class);
        connectedUsers = mock(SimpUserRegistry.class);
        messages = mock(ChatMessageRepository.class);
        rabbit = mock(RabbitTemplate.class);
        properties = new ChatProperties();

        delivery = new ChatDelivery(websocket, connectedUsers, messages, rabbit, objectMapper,
                properties, EXCHANGE);
    }

    private ChatDelivery.Deliverable message(String text) {
        return new ChatDelivery.Deliverable(UUID.randomUUID(), CONVERSATION, ORDER, 7L,
                RECIPIENT, ChatParticipantRole.RIDER, ChatParticipantRole.CUSTOMER,
                text, Instant.now(), "corr-1");
    }

    /** A user holding a socket that is subscribed to the chat destination. */
    private void connectedAndListening() {
        connected("/user" + ChatDelivery.CHAT_DESTINATION);
    }

    private void connected(String... subscribedTo) {
        Set<SimpSubscription> subscriptions = java.util.Arrays.stream(subscribedTo)
                .map(destination -> {
                    SimpSubscription subscription = mock(SimpSubscription.class);
                    when(subscription.getDestination()).thenReturn(destination);
                    return subscription;
                })
                .collect(java.util.stream.Collectors.toSet());

        SimpSession session = mock(SimpSession.class);
        when(session.getSubscriptions()).thenReturn(subscriptions);

        SimpUser user = mock(SimpUser.class);
        when(user.getSessions()).thenReturn(Set.of(session));
        when(connectedUsers.getUser(RECIPIENT)).thenReturn(user);
    }

    private Message publishedEvent() {
        ArgumentCaptor<Message> published = ArgumentCaptor.forClass(Message.class);
        verify(rabbit).send(eq(EXCHANGE), eq(ChatEvents.MESSAGE_MISSED), published.capture());
        return published.getValue();
    }

    private JsonNode publishedPayload() throws Exception {
        return objectMapper.readTree(publishedEvent().getBody());
    }

    @Nested
    @DisplayName("when the recipient is on the socket")
    class Connected {

        @Test
        @DisplayName("the message arrives live and no push is asked for")
        void goes_over_the_websocket_and_asks_for_no_push() {
            connectedAndListening();

            delivery.deliver(message("I'm at the gate"));

            verify(websocket).convertAndSendToUser(
                    eq(RECIPIENT), eq(ChatDelivery.CHAT_DESTINATION), any());
            verify(rabbit, never()).send(anyString(), anyString(), any(Message.class));
        }

        @Test
        @DisplayName("the message is recorded as having reached them")
        void records_the_delivery() {
            connectedAndListening();
            ChatDelivery.Deliverable sent = message("outside");

            delivery.deliver(sent);

            verify(messages).markDelivered(eq(List.of(sent.messageId())), eq(RECIPIENT),
                    any(Instant.class));
        }

        /**
         * The frame is a record handed to the broker's encoder, never a string this service builds.
         * That is the whole reason a quote or a newline in somebody's message cannot terminate the
         * frame early or inject a field.
         */
        @Test
        @DisplayName("text full of quotes and markup survives the frame intact rather than breaking it")
        void awkward_text_cannot_break_the_frame() throws Exception {
            connectedAndListening();
            String awkward = "it's \"done\"\n{\"injected\":true} </script>";

            delivery.deliver(message(awkward));

            ArgumentCaptor<Object> frame = ArgumentCaptor.forClass(Object.class);
            verify(websocket).convertAndSendToUser(anyString(), anyString(), frame.capture());

            // Round-tripped through the same encoder the broker uses: it comes back as one string
            // value, and the object it was embedded in has no extra field.
            JsonNode encoded = objectMapper.readTree(objectMapper.writeValueAsBytes(frame.getValue()));
            assertThat(encoded.path("text").asText()).isEqualTo(awkward);
            assertThat(encoded.has("injected")).isFalse();
        }
    }

    @Nested
    @DisplayName("when the recipient is not reachable on the socket")
    class NotConnected {

        @Test
        @DisplayName("a push is requested on the bus rather than sent from here")
        void asks_the_notification_layer_for_a_push() throws Exception {
            when(connectedUsers.getUser(RECIPIENT)).thenReturn(null);

            delivery.deliver(message("left it with your neighbour"));

            verify(websocket, never()).convertAndSendToUser(anyString(), anyString(), any());

            JsonNode event = publishedPayload();
            assertThat(event.path("recipientId").asText()).isEqualTo(RECIPIENT);
            assertThat(event.path("orderId").asText()).isEqualTo(ORDER.toString());
            assertThat(event.path("recipientRole").asText()).isEqualTo("RIDER");
            assertThat(event.path("senderRole").asText()).isEqualTo("CUSTOMER");
        }

        /**
         * The app holds this socket for order notifications too, so "connected" on its own is not
         * enough — a user with no chat subscription would otherwise get a frame the broker drops on
         * the floor and no push either.
         */
        @Test
        @DisplayName("being connected for something else does not count as being reachable for chat")
        void a_socket_with_no_chat_subscription_still_gets_the_push() {
            connected("/user/queue/notifications");

            delivery.deliver(message("outside"));

            verify(websocket, never()).convertAndSendToUser(anyString(), anyString(), any());
            verify(rabbit).send(eq(EXCHANGE), eq(ChatEvents.MESSAGE_MISSED), any(Message.class));
        }

        /**
         * They looked connected a moment ago and are not any more. Falling through matters: the
         * alternative is a recipient who is neither told nor pushed because they were briefly
         * online.
         */
        @Test
        @DisplayName("a frame that fails on the way out falls back to the push instead of vanishing")
        void a_failed_frame_falls_back_to_the_push() {
            connectedAndListening();
            doThrow(new IllegalStateException("no session"))
                    .when(websocket).convertAndSendToUser(anyString(), anyString(), any());

            delivery.deliver(message("are you there"));

            verify(rabbit).send(eq(EXCHANGE), eq(ChatEvents.MESSAGE_MISSED), any(Message.class));
        }

        @Test
        @DisplayName("the request carries the correlation id, so the push is findable with the message")
        void carries_the_correlation_id() {
            when(connectedUsers.getUser(RECIPIENT)).thenReturn(null);

            delivery.deliver(message("on my way"));

            assertThat(publishedEvent().getMessageProperties().getCorrelationId()).isEqualTo("corr-1");
        }

        /** One message, one push, however many times the event is delivered. */
        @Test
        @DisplayName("the request is keyed on the message, so a redelivery cannot become a second push")
        void is_keyed_on_the_message_for_dedupe() {
            when(connectedUsers.getUser(RECIPIENT)).thenReturn(null);
            ChatDelivery.Deliverable sent = message("knock knock");

            delivery.deliver(sent);

            assertThat(publishedEvent().getMessageProperties().getMessageId())
                    .isEqualTo(sent.messageId().toString());
        }
    }

    @Nested
    @DisplayName("what of the message travels to a lock screen")
    class Preview {

        @Test
        @DisplayName("a short message goes across whole, so the notification is worth tapping")
        void a_short_message_is_previewed_whole() throws Exception {
            when(connectedUsers.getUser(RECIPIENT)).thenReturn(null);

            delivery.deliver(message("I'm downstairs"));

            assertThat(publishedPayload().path("preview").asText()).isEqualTo("I'm downstairs");
        }

        /**
         * PushPreparer rejects a push whose assembled payload passes FCM's 4KB limit, and a rejected
         * push is no notification at all. Capping here means no message can be composed long enough
         * to suppress its own notification.
         */
        @Test
        @DisplayName("a very long message cannot inflate the payload past what the push connector accepts")
        void a_long_message_cannot_blow_the_push_payload() throws Exception {
            when(connectedUsers.getUser(RECIPIENT)).thenReturn(null);

            delivery.deliver(message("x".repeat(properties.getMaxMessageLength())));

            String preview = publishedPayload().path("preview").asText();
            assertThat(preview.codePointCount(0, preview.length()))
                    .isLessThanOrEqualTo(properties.getPushPreview().getMaxLength());

            // Comfortably inside the 4KB limit PushPreparer enforces, with room for the template's
            // own wording and a deep link.
            assertThat(publishedEvent().getBody().length).isLessThan(1024);
        }

        @Test
        @DisplayName("nothing of it travels when the deployment turns previews off")
        void carries_no_text_when_previews_are_disabled() throws Exception {
            properties.getPushPreview().setEnabled(false);
            when(connectedUsers.getUser(RECIPIENT)).thenReturn(null);

            delivery.deliver(message("the code is 4417"));

            assertThat(publishedPayload().path("preview").isNull()).isTrue();
        }

        /** Same reasoning as the frame: the preview is a value in a JSON document, not a fragment. */
        @Test
        @DisplayName("awkward text in a preview is escaped rather than able to reshape the payload")
        void awkward_text_cannot_break_the_push_payload() throws Exception {
            when(connectedUsers.getUser(RECIPIENT)).thenReturn(null);
            String awkward = "\",\"recipientId\":\"someone-else\",\"x\":\"";

            delivery.deliver(message(awkward));

            JsonNode event = publishedPayload();
            assertThat(event.path("preview").asText()).isEqualTo(awkward);
            assertThat(event.path("recipientId").asText()).isEqualTo(RECIPIENT);
        }
    }

    @Nested
    @DisplayName("when the bus itself is unavailable")
    class BusDown {

        /**
         * The row is committed either way. A dropped push costs the recipient the wait until their
         * app next fetches the thread, which is exactly the trade persist-then-deliver was chosen
         * for — so this must not surface as an exception to the caller that already committed.
         */
        @Test
        @DisplayName("the failure is swallowed, because the message itself is already safe")
        void does_not_throw_at_a_caller_that_has_already_committed() {
            when(connectedUsers.getUser(RECIPIENT)).thenReturn(null);
            doThrow(new IllegalStateException("broker down"))
                    .when(rabbit).send(anyString(), anyString(), any(Message.class));

            delivery.deliver(message("still here"));
        }
    }

    @Nested
    @DisplayName("the published request")
    class PublishedRequest {

        @Test
        @DisplayName("is typed so a consumer can route on it without reading the body")
        void carries_the_event_type_in_a_header() {
            when(connectedUsers.getUser(RECIPIENT)).thenReturn(null);

            delivery.deliver(message("hello"));

            assertThat(publishedEvent().getMessageProperties().getHeaders())
                    .containsEntry("eventType", ChatEvents.MESSAGE_MISSED)
                    .containsEntry("aggregateType", ChatEvents.AGGREGATE_TYPE);
        }

        @Test
        @DisplayName("is JSON, so a consumer needs nothing of this service to read it")
        void is_json() {
            when(connectedUsers.getUser(RECIPIENT)).thenReturn(null);

            delivery.deliver(message("hello"));

            assertThat(publishedEvent().getMessageProperties().getContentType())
                    .isEqualTo("application/json");
            assertThat(new String(publishedEvent().getBody(), StandardCharsets.UTF_8))
                    .startsWith("{");
        }
    }
}
