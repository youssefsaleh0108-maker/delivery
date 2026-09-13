package com.delivery.appnotification.api;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
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

import com.delivery.appnotification.domain.ChatBlock;
import com.delivery.appnotification.domain.ChatRoom;
import com.delivery.appnotification.domain.ChatRoomMember;
import com.delivery.appnotification.domain.ChatRoomMessage;
import com.delivery.appnotification.domain.ChatRoomReport;
import com.delivery.appnotification.service.NeighbourhoodRoomService;
import com.delivery.appnotification.service.RoomModerationService;
import com.delivery.appnotification.service.RoomExceptions.MemberMutedException;
import com.delivery.appnotification.service.RoomExceptions.NoNeighbourhoodException;
import com.delivery.appnotification.service.RoomExceptions.NoRoomReason;
import com.delivery.appnotification.service.RoomExceptions.RoomNotFoundException;
import com.delivery.appnotification.service.RoomExceptions.SendRateLimitedException;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Who may reach a neighbourhood room at all, and what every refusal looks like to the app.
 *
 * <p>Two layers are pinned. The role: rooms are for customers, so a missing token is a 401 and a
 * rider's or a merchant's work account is a 403. The caller: every endpoint acts as the token's
 * subject, and a room the caller is not in answers exactly as a room that does not exist.
 */
@DisplayName("neighbourhood room endpoints")
class NeighbourhoodChatAccessTest {

    private static final String CUSTOMER = "customer-sub";
    private static final UUID ZONE = UUID.randomUUID();

    private NeighbourhoodRoomService rooms;
    private RoomModerationService moderation;
    private MockMvc mvc;
    private ChatRoom room;
    private ChatRoomMember member;

    @BeforeEach
    void setUp() {
        rooms = mock(NeighbourhoodRoomService.class);
        moderation = mock(RoomModerationService.class);
        mvc = SecuredMvc.of(new NeighbourhoodChatController(rooms, moderation));
        room = new ChatRoom(ZONE, "Mar Mikhael");
        member = new ChatRoomMember(room.getId(), CUSTOMER, "Tania K.", Instant.now());
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private String messagesPath() {
        return "/api/chat/rooms/" + room.getId() + "/messages";
    }

    private List<RequestBuilder> everyEndpoint() {
        return List.of(
                get("/api/chat/rooms/mine").param("zoneId", ZONE.toString()),
                get(messagesPath()),
                post(messagesPath()).contentType(MediaType.APPLICATION_JSON).content("{\"text\":\"hello\"}"),
                post("/api/chat/rooms/messages/" + UUID.randomUUID() + "/report")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"reason\":\"SPAM\"}"),
                post("/api/chat/rooms/messages/" + UUID.randomUUID() + "/block-author"),
                get("/api/chat/rooms/blocks"),
                delete("/api/chat/rooms/blocks/" + UUID.randomUUID()));
    }

    @Nested
    @DisplayName("by role")
    class ByRole {

        @Test
        @DisplayName("without a token, every endpoint is a 401 and the service is never asked")
        void no_token() throws Exception {
            for (RequestBuilder request : everyEndpoint()) {
                mvc.perform(request).andExpect(status().isUnauthorized());
            }
            verifyNoInteractions(rooms, moderation);
        }

        @Test
        @DisplayName("a RIDER, MERCHANT or CARRIER account without CUSTOMER is a 403 everywhere")
        void work_accounts_are_refused() throws Exception {
            for (String role : List.of("RIDER", "MERCHANT", "CARRIER", "BACKOFFICE")) {
                SecuredMvc.signedInAs("work-sub", role);
                for (RequestBuilder request : everyEndpoint()) {
                    mvc.perform(request).andExpect(status().isForbidden());
                }
            }
            verifyNoInteractions(rooms, moderation);
        }
    }

    @Nested
    @DisplayName("as a customer")
    class AsACustomer {

        @BeforeEach
        void signIn() {
            SecuredMvc.signedInAs(CUSTOMER,
                    Map.of("given_name", "Tania", "family_name", "Khoury",
                            "preferred_username", "96171123456"),
                    "CUSTOMER");
        }

        @Test
        @DisplayName("is placed by the token's subject and name, and gets the room without anybody's account id")
        void placed_as_themselves() throws Exception {
            when(rooms.place(CUSTOMER, ZONE, "Tania K."))
                    .thenReturn(new NeighbourhoodRoomService.Placement(room, member, 12L, null, null));

            mvc.perform(get("/api/chat/rooms/mine").param("zoneId", ZONE.toString()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.name").value("Mar Mikhael"))
                    .andExpect(jsonPath("$.memberCount").value(12))
                    .andExpect(jsonPath("$.yourHandle").value(member.getHandle().toString()))
                    .andExpect(jsonPath("$.userId").doesNotExist())
                    .andExpect(jsonPath("$.mutedUntil").doesNotExist());
        }

        @Test
        @DisplayName("with no area is told why, so the app can ask them to choose one")
        void no_area_is_a_404_with_a_reason() throws Exception {
            when(rooms.place(eq(CUSTOMER), isNull(), anyString()))
                    .thenThrow(new NoNeighbourhoodException(NoRoomReason.NO_ZONE));

            mvc.perform(get("/api/chat/rooms/mine"))
                    .andExpect(status().isNotFound())
                    .andExpect(jsonPath("$.reason").value("NO_ZONE"));
        }

        @Test
        @DisplayName("reading another neighbourhood's room is the same 404 as a room that does not exist")
        void another_rooms_history_is_a_404() throws Exception {
            UUID elsewhere = UUID.randomUUID();
            when(rooms.history(eq(elsewhere), eq(CUSTOMER), any(), any()))
                    .thenThrow(new RoomNotFoundException(elsewhere));

            mvc.perform(get("/api/chat/rooms/" + elsewhere + "/messages"))
                    .andExpect(status().isNotFound());
        }

        @Test
        @DisplayName("posting into another neighbourhood's room is a 404")
        void posting_elsewhere_is_a_404() throws Exception {
            UUID elsewhere = UUID.randomUUID();
            when(rooms.post(eq(elsewhere), eq(CUSTOMER), anyString(), any(), any()))
                    .thenThrow(new RoomNotFoundException(elsewhere));

            mvc.perform(post("/api/chat/rooms/" + elsewhere + "/messages")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"text\":\"hello\"}"))
                    .andExpect(status().isNotFound());
        }

        @Test
        @DisplayName("reads history as themselves, with no author account ids in it")
        void reads_history() throws Exception {
            ChatRoomMessage message = new ChatRoomMessage(room.getId(), 1L, member, "hi", null, Instant.now());
            when(rooms.history(room.getId(), CUSTOMER, null, null))
                    .thenReturn(new NeighbourhoodRoomService.HistoryPage(List.of(message), false));

            mvc.perform(get(messagesPath()))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.messages[0].authorName").value("Tania K."))
                    .andExpect(jsonPath("$.messages[0].mine").value(true))
                    .andExpect(jsonPath("$.messages[0].senderId").doesNotExist())
                    .andExpect(jsonPath("$.more").value(false));
        }

        @Test
        @DisplayName("posts as themselves and gets 201 with the stored message")
        void posts() throws Exception {
            ChatRoomMessage message = new ChatRoomMessage(room.getId(), 3L, member, "hello", "c-1", Instant.now());
            when(rooms.post(eq(room.getId()), eq(CUSTOMER), eq("hello"), eq("c-1"), any())).thenReturn(message);

            mvc.perform(post(messagesPath())
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"text\":\"hello\",\"clientMessageId\":\"c-1\"}"))
                    .andExpect(status().isCreated())
                    .andExpect(jsonPath("$.sequence").value(3));
            verify(rooms).post(eq(room.getId()), eq(CUSTOMER), eq("hello"), eq("c-1"), any());
        }

        @Test
        @DisplayName("while muted gets a 403 that says until when")
        void muted_is_a_403_with_the_end() throws Exception {
            Instant until = Instant.parse("2026-09-20T10:00:00Z");
            when(rooms.post(any(), eq(CUSTOMER), anyString(), any(), any()))
                    .thenThrow(new MemberMutedException(until));

            mvc.perform(post(messagesPath()).contentType(MediaType.APPLICATION_JSON).content("{\"text\":\"hello\"}"))
                    .andExpect(status().isForbidden())
                    .andExpect(jsonPath("$.mutedUntil").exists());
        }

        @Test
        @DisplayName("sending too fast gets a 429 with Retry-After")
        void rate_limited_is_a_429() throws Exception {
            when(rooms.post(any(), eq(CUSTOMER), anyString(), any(), any()))
                    .thenThrow(new SendRateLimitedException(Duration.ofMinutes(1)));

            mvc.perform(post(messagesPath()).contentType(MediaType.APPLICATION_JSON).content("{\"text\":\"spam\"}"))
                    .andExpect(status().isTooManyRequests())
                    .andExpect(header().string("Retry-After", "60"));
        }

        @Test
        @DisplayName("an empty body is refused before the service is asked")
        void blank_text_is_a_400() throws Exception {
            mvc.perform(post(messagesPath()).contentType(MediaType.APPLICATION_JSON).content("{\"text\":\"\"}"))
                    .andExpect(status().isBadRequest());
            verifyNoInteractions(rooms);
        }

        @Test
        @DisplayName("reports a message as themselves and gets 204")
        void reports() throws Exception {
            UUID message = UUID.randomUUID();

            mvc.perform(post("/api/chat/rooms/messages/" + message + "/report")
                            .contentType(MediaType.APPLICATION_JSON).content("{\"reason\":\"PERSONAL_INFO\"}"))
                    .andExpect(status().isNoContent());
            verify(moderation).report(message, CUSTOMER, ChatRoomReport.Reason.PERSONAL_INFO);
        }

        @Test
        @DisplayName("a report with a reason the app does not offer is a 400")
        void an_unknown_reason_is_a_400() throws Exception {
            mvc.perform(post("/api/chat/rooms/messages/" + UUID.randomUUID() + "/report")
                            .contentType(MediaType.APPLICATION_JSON).content("{\"reason\":\"BECAUSE\"}"))
                    .andExpect(status().isBadRequest());
            verifyNoInteractions(moderation);
        }

        @Test
        @DisplayName("reporting a message from another neighbourhood is a 404")
        void reporting_elsewhere_is_a_404() throws Exception {
            UUID message = UUID.randomUUID();
            doThrow(new RoomNotFoundException(message))
                    .when(moderation).report(message, CUSTOMER, ChatRoomReport.Reason.ABUSE);

            mvc.perform(post("/api/chat/rooms/messages/" + message + "/report")
                            .contentType(MediaType.APPLICATION_JSON).content("{\"reason\":\"ABUSE\"}"))
                    .andExpect(status().isNotFound());
        }

        @Test
        @DisplayName("blocks an author through their message and learns a name, never an account id")
        void blocks_an_author() throws Exception {
            UUID message = UUID.randomUUID();
            ChatBlock block = new ChatBlock(CUSTOMER, "author-sub", "Hadi S.", Instant.now());
            when(moderation.blockAuthor(message, CUSTOMER)).thenReturn(block);

            mvc.perform(post("/api/chat/rooms/messages/" + message + "/block-author"))
                    .andExpect(status().isCreated())
                    .andExpect(jsonPath("$.id").value(block.getId().toString()))
                    .andExpect(jsonPath("$.name").value("Hadi S."))
                    .andExpect(content().string(not(containsString("author-sub"))));
        }

        @Test
        @DisplayName("lists and lifts their own blocks")
        void lists_and_lifts_blocks() throws Exception {
            ChatBlock block = new ChatBlock(CUSTOMER, "author-sub", "Hadi S.", Instant.now());
            when(moderation.blocksOf(CUSTOMER)).thenReturn(List.of(block));

            mvc.perform(get("/api/chat/rooms/blocks"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[0].name").value("Hadi S."))
                    .andExpect(content().string(not(containsString("author-sub"))));
            mvc.perform(delete("/api/chat/rooms/blocks/" + block.getId()))
                    .andExpect(status().isNoContent());
            verify(moderation).unblock(block.getId(), CUSTOMER);
        }

        @Test
        @DisplayName("lifting somebody else's block is a 404")
        void lifting_another_persons_block_is_a_404() throws Exception {
            UUID theirs = UUID.randomUUID();
            doThrow(new RoomNotFoundException(theirs)).when(moderation).unblock(theirs, CUSTOMER);

            mvc.perform(delete("/api/chat/rooms/blocks/" + theirs))
                    .andExpect(status().isNotFound());
        }
    }
}
