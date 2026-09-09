package com.delivery.appnotification.api;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.appnotification.domain.InAppMessage;
import com.delivery.appnotification.service.InAppMessageService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * How much of the inbox one request returns.
 *
 * <p>The observed failure: {@code page} and {@code size} were accepted and ignored, and the reply
 * was a bare array of everything up to the limit — twenty-seven kilobytes for an account two days
 * old, with nothing in the response saying whether there was more. Every other list on the platform
 * answers with a {@code content/page/size/totalElements/totalPages} envelope.
 *
 * <p>The shipped app asks with {@code limit} and parses a list, so that request keeps its old shape;
 * the tests below hold both halves of that promise at once.
 */
@DisplayName("the in-app inbox")
class InAppNotificationControllerTest {

    private static final String USER = "user-1";

    private final InAppMessageService messages = mock(InAppMessageService.class);

    private final MockMvc mvc = MockMvcBuilders
            .standaloneSetup(new InAppNotificationController(messages))
            .build();

    @BeforeEach
    void authenticate() {
        Jwt token = Jwt.withTokenValue("token").header("alg", "none").subject(USER).build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(token));
    }

    @AfterEach
    void forget() {
        SecurityContextHolder.clearContext();
    }

    private static InAppMessage message() {
        return new InAppMessage(USER, UUID.randomUUID(), UUID.randomUUID(),
                "order.status_changed", "On its way", "Your order has left the store",
                Map.of("orderId", "1"));
    }

    /** One row of a much larger inbox, so totalElements has something to disagree with. */
    private static Page<InAppMessage> onePageOf(int page, int size, long total) {
        return new PageImpl<>(List.of(message()), PageRequest.of(page, size), total);
    }

    @Nested
    @DisplayName("asked for a page")
    class Paged {

        @Test
        void asks_the_service_for_the_page_the_caller_named() throws Exception {
            when(messages.inbox(anyString(), anyInt(), anyInt())).thenReturn(onePageOf(2, 5, 42));

            mvc.perform(get("/api/notifications?page=2&size=5")).andExpect(status().isOk());

            ArgumentCaptor<Integer> page = ArgumentCaptor.forClass(Integer.class);
            ArgumentCaptor<Integer> size = ArgumentCaptor.forClass(Integer.class);
            verify(messages).inbox(eq(USER), page.capture(), size.capture());
            assertThat(page.getValue()).isEqualTo(2);
            assertThat(size.getValue()).isEqualTo(5);
        }

        /** The envelope, so a client can tell "that was all" from "ask again". */
        @Test
        void answers_with_the_same_envelope_as_every_other_list() throws Exception {
            when(messages.inbox(anyString(), anyInt(), anyInt())).thenReturn(onePageOf(2, 5, 42));

            mvc.perform(get("/api/notifications?page=2&size=5"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.content").isArray())
                    .andExpect(jsonPath("$.content[0].title").value("On its way"))
                    .andExpect(jsonPath("$.page").value(2))
                    .andExpect(jsonPath("$.size").value(5))
                    .andExpect(jsonPath("$.totalElements").value(42))
                    .andExpect(jsonPath("$.totalPages").value(9));
        }

        @Test
        void defaults_to_a_screenful_of_the_first_page() throws Exception {
            when(messages.inbox(anyString(), anyInt(), anyInt())).thenReturn(onePageOf(0, 20, 42));

            mvc.perform(get("/api/notifications")).andExpect(status().isOk());

            verify(messages).inbox(USER, 0, 20);
        }

        /**
         * A size of ten thousand is either a typo or someone probing; either way it must not become
         * one query for the whole table.
         */
        @Test
        void a_size_beyond_the_cap_is_capped() throws Exception {
            when(messages.inbox(anyString(), anyInt(), anyInt())).thenReturn(onePageOf(0, 100, 42));

            mvc.perform(get("/api/notifications?size=10000")).andExpect(status().isOk());

            verify(messages).inbox(USER, 0, 100);
        }

        /** PageRequest refuses a negative page, so the controller has to not pass one on. */
        @Test
        void a_negative_page_is_the_first_page() throws Exception {
            when(messages.inbox(anyString(), anyInt(), anyInt())).thenReturn(onePageOf(0, 20, 42));

            mvc.perform(get("/api/notifications?page=-3")).andExpect(status().isOk());

            verify(messages).inbox(USER, 0, 20);
        }
    }

    @Nested
    @DisplayName("asked the way the shipped app asks")
    class Legacy {

        /**
         * The app in people's pockets reads this response as a JSON array. An envelope here would
         * be a crash on the inbox screen for everyone who has not updated.
         */
        @Test
        void still_answers_with_a_bare_array() throws Exception {
            when(messages.inbox(USER, 50)).thenReturn(List.of(message()));

            mvc.perform(get("/api/notifications?limit=50"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$").isArray())
                    .andExpect(jsonPath("$[0].title").value("On its way"));
        }

        @Test
        void honours_the_limit_it_was_given() throws Exception {
            when(messages.inbox(USER, 3)).thenReturn(List.of(message()));

            mvc.perform(get("/api/notifications?limit=3")).andExpect(status().isOk());

            verify(messages).inbox(USER, 3);
        }
    }
}
