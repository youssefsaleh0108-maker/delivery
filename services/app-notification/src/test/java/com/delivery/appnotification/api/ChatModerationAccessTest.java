package com.delivery.appnotification.api;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.RequestBuilder;

import com.delivery.appnotification.domain.ChatRoomMember;
import com.delivery.appnotification.domain.ChatRoomMessage;
import com.delivery.appnotification.service.RoomModerationService;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Only Backoffice moderates, always as itself, and never without a reason.
 */
@DisplayName("moderation endpoints")
class ChatModerationAccessTest {

    private static final String MODERATOR = "backoffice-sub";

    private RoomModerationService moderation;
    private MockMvc mvc;
    private ChatRoomMessage message;
    private String base;

    @BeforeEach
    void setUp() {
        moderation = mock(RoomModerationService.class);
        mvc = SecuredMvc.of(new ChatModerationController(moderation));
        UUID room = UUID.randomUUID();
        message = new ChatRoomMessage(room, 1L, new ChatRoomMember(room, "author-sub", "Hadi S.", Instant.now()),
                "spam spam", null, Instant.now());
        base = "/api/chat/backoffice/moderation/messages/" + message.getId();
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private List<RequestBuilder> everyEndpoint() {
        return List.of(
                get("/api/chat/backoffice/moderation/reports"),
                post(base + "/hide").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"reason\":\"posted a phone number\"}"),
                post(base + "/dismiss").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"reason\":\"not a violation\"}"),
                post(base + "/mute-author").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"hours\":24,\"reason\":\"repeated spam\"}"),
                post(base + "/unmute-author").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"reason\":\"appeal upheld\"}"));
    }

    @Nested
    @DisplayName("refuses")
    class Refuses {

        @Test
        @DisplayName("a caller without a token, with a 401 on every endpoint")
        void no_token() throws Exception {
            for (RequestBuilder request : everyEndpoint()) {
                mvc.perform(request).andExpect(status().isUnauthorized());
            }
            verifyNoInteractions(moderation);
        }

        /** A member moderating their own neighbourhood is the one thing this must not allow. */
        @Test
        @DisplayName("customers, merchants, riders and carriers, with a 403 on every endpoint")
        void everyone_but_backoffice() throws Exception {
            for (String role : List.of("CUSTOMER", "MERCHANT", "RIDER", "CARRIER")) {
                SecuredMvc.signedInAs("someone-sub", role);
                for (RequestBuilder request : everyEndpoint()) {
                    mvc.perform(request).andExpect(status().isForbidden());
                }
            }
            verifyNoInteractions(moderation);
        }
    }

    @Nested
    @DisplayName("as Backoffice")
    class AsBackoffice {

        @BeforeEach
        void signIn() {
            SecuredMvc.signedInAs(MODERATOR, "BACKOFFICE");
        }

        @Test
        @DisplayName("reads the queue")
        void reads_the_queue() throws Exception {
            when(moderation.openQueue()).thenReturn(List.of());

            mvc.perform(get("/api/chat/backoffice/moderation/reports")).andExpect(status().isOk());
        }

        @Test
        @DisplayName("hides as the token's subject with the stated reason")
        void hides() throws Exception {
            message.hide(MODERATOR, Instant.now());
            when(moderation.hide(eq(message.getId()), eq(MODERATOR), eq("posted a phone number"), any()))
                    .thenReturn(message);

            mvc.perform(post(base + "/hide").contentType(MediaType.APPLICATION_JSON)
                            .content("{\"reason\":\"  posted a phone number \"}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.hiddenAt").exists());
        }

        @Test
        @DisplayName("mutes for the hours asked, as the token's subject")
        void mutes() throws Exception {
            when(moderation.muteAuthor(eq(message.getId()), eq(MODERATOR), eq(Duration.ofHours(168)),
                    eq("repeated spam"), any())).thenReturn(Instant.now().plus(Duration.ofDays(7)));

            mvc.perform(post(base + "/mute-author").contentType(MediaType.APPLICATION_JSON)
                            .content("{\"hours\":168,\"reason\":\"repeated spam\"}"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.mutedUntil").exists());
        }

        @Test
        @DisplayName("dismisses and unmutes, each as the token's subject")
        void dismisses_and_unmutes() throws Exception {
            mvc.perform(post(base + "/dismiss").contentType(MediaType.APPLICATION_JSON)
                            .content("{\"reason\":\"not a violation\"}"))
                    .andExpect(status().isNoContent());
            mvc.perform(post(base + "/unmute-author").contentType(MediaType.APPLICATION_JSON)
                            .content("{\"reason\":\"appeal upheld\"}"))
                    .andExpect(status().isNoContent());

            verify(moderation).dismiss(eq(message.getId()), eq(MODERATOR), eq("not a violation"), any());
            verify(moderation).unmuteAuthor(eq(message.getId()), eq(MODERATOR), eq("appeal upheld"), any());
        }

        @Test
        @DisplayName("refuses an action with no reason, and a mute of no time or of more than a year")
        void refuses_unreasoned_or_unbounded_actions() throws Exception {
            mvc.perform(post(base + "/hide").contentType(MediaType.APPLICATION_JSON).content("{}"))
                    .andExpect(status().isBadRequest());
            mvc.perform(post(base + "/mute-author").contentType(MediaType.APPLICATION_JSON)
                            .content("{\"hours\":0,\"reason\":\"repeated spam\"}"))
                    .andExpect(status().isBadRequest());
            mvc.perform(post(base + "/mute-author").contentType(MediaType.APPLICATION_JSON)
                            .content("{\"hours\":9000,\"reason\":\"repeated spam\"}"))
                    .andExpect(status().isBadRequest());
            verifyNoInteractions(moderation);
        }
    }
}
