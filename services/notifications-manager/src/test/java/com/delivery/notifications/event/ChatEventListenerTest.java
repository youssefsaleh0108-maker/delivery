package com.delivery.notifications.event;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import com.delivery.notifications.service.NotificationDispatchService;
import com.delivery.notifications.service.RecipientDirectory;
import com.delivery.platform.notifications.ChatEvents;
import com.fasterxml.jackson.databind.ObjectMapper;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The consumer half of the chat contract, which had no consumer at all until the integration pass.
 *
 * <p>Three things are worth pinning. The dedupe key must be the MESSAGE, because keying a
 * conversation's notifications on its order is how a customer gets a push for the rider's first
 * message and silence for the rest of the thread. The recipient must come from the event, because
 * either participant may be the offline one. And neither participant's name may reach the other's
 * lock screen — the event deliberately carries roles instead, and this is where that stays true.
 */
@DisplayName("a chat message that reached nobody")
class ChatEventListenerTest {

    private static final UUID ORDER = UUID.randomUUID();
    private static final UUID CONVERSATION = UUID.randomUUID();
    private static final String RECIPIENT = "customer-sub";

    private NotificationDispatchService dispatch;
    private RecipientDirectory recipients;
    private ChatEventListener listener;

    @BeforeEach
    void setUp() {
        dispatch = mock(NotificationDispatchService.class);
        recipients = mock(RecipientDirectory.class);
        when(recipients.contactsFor(anyString())).thenReturn(Map.of("PUSH", "device-token"));
        ObjectMapper objectMapper = new ObjectMapper()
                .registerModule(new com.fasterxml.jackson.datatype.jsr310.JavaTimeModule());
        listener = new ChatEventListener(dispatch, recipients, objectMapper);
    }

    private String payload(UUID messageId, String senderRole, String preview) throws Exception {
        ChatEvents.MessageMissed event = new ChatEvents.MessageMissed(
                ORDER, CONVERSATION, messageId, RECIPIENT, "CUSTOMER", senderRole, preview,
                Instant.parse("2026-08-27T09:00:00Z"), "corr-1");
        return new ObjectMapper()
                .registerModule(new com.fasterxml.jackson.datatype.jsr310.JavaTimeModule())
                .writeValueAsString(event);
    }

    private void deliver(String body) {
        listener.onChatEvent(body, ChatEvents.MESSAGE_MISSED, ChatEvents.MESSAGE_MISSED, "corr-1");
    }

    @Test
    @DisplayName("becomes a push addressed to whoever was offline")
    void dispatches_to_the_named_recipient() throws Exception {
        UUID messageId = UUID.randomUUID();

        deliver(payload(messageId, "RIDER", "I'm at the gate"));

        verify(dispatch).dispatch(eq(ChatEvents.MESSAGE_MISSED), eq(ORDER), eq(RECIPIENT),
                any(), any(), eq("corr-1"), eq(messageId.toString()));
    }

    @Test
    @DisplayName("is deduplicated on the message, not on the order")
    void the_dedupe_key_is_the_message() throws Exception {
        // The property that matters: a second message on the SAME order must arrive with a
        // different key, or the dispatch path suppresses it as a redelivery of the first.
        UUID first = UUID.randomUUID();
        UUID second = UUID.randomUUID();

        deliver(payload(first, "RIDER", "I'm at the gate"));
        deliver(payload(second, "RIDER", "Which floor?"));

        ArgumentCaptor<String> keys = ArgumentCaptor.forClass(String.class);
        verify(dispatch, org.mockito.Mockito.times(2)).dispatch(anyString(), any(), anyString(),
                any(), any(), anyString(), keys.capture());

        assertThat(keys.getAllValues())
                .containsExactly(first.toString(), second.toString())
                .doesNotContain(ORDER.toString(), CONVERSATION.toString());
    }

    @Test
    @DisplayName("carries the conversation so the tap opens the thread, not the order")
    void the_values_carry_the_conversation() throws Exception {
        deliver(payload(UUID.randomUUID(), "RIDER", "I'm at the gate"));

        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, String>> values =
                ArgumentCaptor.forClass((Class<Map<String, String>>) (Class<?>) Map.class);
        verify(dispatch).dispatch(anyString(), any(), anyString(), any(), values.capture(),
                anyString(), anyString());

        // CONVERSATION is the template's declared link target and it reads its id from here.
        assertThat(values.getValue()).containsEntry("conversationId", CONVERSATION.toString());
    }

    @Test
    @DisplayName("names a role, never a person")
    void no_participant_is_named_to_the_other() throws Exception {
        deliver(payload(UUID.randomUUID(), "RIDER", "I'm at the gate"));

        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, String>> values =
                ArgumentCaptor.forClass((Class<Map<String, String>>) (Class<?>) Map.class);
        verify(dispatch).dispatch(anyString(), any(), anyString(), any(), values.capture(),
                anyString(), anyString());

        assertThat(values.getValue().get("sender")).isEqualTo("your rider");
        assertThat(values.getValue().values()).doesNotContain(RECIPIENT);
    }

    @Test
    @DisplayName("with previews off renders an empty string, not the word null")
    void an_absent_preview_is_empty() throws Exception {
        deliver(payload(UUID.randomUUID(), "RIDER", null));

        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, String>> values =
                ArgumentCaptor.forClass((Class<Map<String, String>>) (Class<?>) Map.class);
        verify(dispatch).dispatch(anyString(), any(), anyString(), any(), values.capture(),
                anyString(), anyString());

        assertThat(values.getValue()).containsEntry("preview", "");
    }

    @Test
    @DisplayName("missing its recipient is acked, not retried forever")
    void an_event_naming_nobody_is_dropped() {
        deliver("{\"orderId\":\"" + ORDER + "\",\"messageId\":\"" + UUID.randomUUID() + "\"}");

        verify(dispatch, never()).dispatch(anyString(), any(), anyString(), any(), any(),
                anyString(), anyString());
    }

    @Test
    @DisplayName("of an unrecognised chat type is ignored rather than guessed at")
    void an_unknown_chat_event_is_ignored() {
        listener.onChatEvent("{\"orderId\":\"" + ORDER + "\"}", "chat.thread_archived",
                "chat.thread_archived", "corr-1");

        verify(dispatch, never()).dispatch(anyString(), any(), anyString(), any(), any(),
                anyString(), anyString());
    }

    @Test
    @DisplayName("that is unparseable does not become a poison pill")
    void malformed_json_is_swallowed() {
        deliver("not json at all");

        verify(dispatch, never()).dispatch(anyString(), any(), anyString(), any(), any(),
                anyString(), anyString());
        assertThat(List.of()).isEmpty();
    }
}
