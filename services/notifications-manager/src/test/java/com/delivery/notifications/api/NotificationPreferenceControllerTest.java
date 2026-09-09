package com.delivery.notifications.api;

import java.util.List;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import com.delivery.notifications.service.NotificationPreferenceService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * What the settings screen is told when a preference change is refused.
 *
 * <p>The observed failure: three unrelated mistakes — a category that does not exist, a channel
 * that does not exist, and an attempt to silence security notices — all came back as the same
 * empty 400. The controller authors a different sentence for each, and each sends the user to a
 * different fix, so a body that carries none of them is a screen that can only say "no".
 *
 * <p>Standalone MockMvc: the controller and its advice, no application context, because what is
 * under test is what Spring MVC renders rather than anything about wiring.
 */
@DisplayName("a refused preference change")
class NotificationPreferenceControllerTest {

    private final NotificationPreferenceService preferences =
            mock(NotificationPreferenceService.class);

    private final MockMvc mvc = MockMvcBuilders
            .standaloneSetup(new NotificationPreferenceController(preferences))
            .setControllerAdvice(new NotificationPreferenceExceptionHandler())
            .build();

    /** The endpoint reads the caller from the token, so there has to be one. */
    @BeforeEach
    void authenticate() {
        Jwt token = Jwt.withTokenValue("token").header("alg", "none").subject("user-1").build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(token));
        when(preferences.settingsFor(anyString())).thenReturn(List.of());
    }

    @AfterEach
    void forget() {
        SecurityContextHolder.clearContext();
    }

    private static String change(String category, String channel) {
        return "{\"changes\":[{\"category\":\"" + category + "\",\"channel\":\"" + channel
                + "\",\"enabled\":false}]}";
    }

    private String detailOf(String category, String channel) throws Exception {
        return mvc.perform(put("/api/notification-preferences/mine")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(change(category, channel)))
                .andExpect(status().isBadRequest())
                .andReturn().getResponse().getContentAsString();
    }

    @Nested
    @DisplayName("names the reason")
    class Reason {

        @Test
        void an_unknown_category_says_so() throws Exception {
            mvc.perform(put("/api/notification-preferences/mine")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(change("CAT_PHOTOS", "PUSH")))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.detail").value("unknown notification category"));
        }

        @Test
        void an_unknown_channel_says_so() throws Exception {
            mvc.perform(put("/api/notification-preferences/mine")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(change("PROMOTIONS", "PIGEON")))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.detail").value("unknown channel"));
        }

        /**
         * The one refusal a user can act on by giving up rather than by correcting a typo, so it
         * matters most that the sentence survives.
         */
        @Test
        void a_category_that_cannot_be_silenced_says_so() throws Exception {
            doThrow(new IllegalArgumentException(
                    "security and account notifications cannot be turned off"))
                    .when(preferences).apply(anyString(), any());

            mvc.perform(put("/api/notification-preferences/mine")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(change("ACCOUNT", "EMAIL")))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.detail")
                            .value("security and account notifications cannot be turned off"));
        }
    }

    @Nested
    @DisplayName("is not interchangeable with the other refusals")
    class Distinct {

        /** The reported symptom: three mistakes, three byte-identical bodies. */
        @Test
        void three_different_mistakes_produce_three_different_bodies() throws Exception {
            doThrow(new IllegalArgumentException(
                    "security and account notifications cannot be turned off"))
                    .when(preferences).apply(anyString(), any());

            assertThat(detailOf("CAT_PHOTOS", "PUSH"))
                    .contains("unknown notification category")
                    .doesNotContain("unknown channel", "cannot be turned off");
            assertThat(detailOf("PROMOTIONS", "PIGEON"))
                    .contains("unknown channel")
                    .doesNotContain("unknown notification category", "cannot be turned off");
            assertThat(detailOf("ACCOUNT", "EMAIL"))
                    .contains("security and account notifications cannot be turned off")
                    .doesNotContain("unknown notification category", "unknown channel");
        }
    }

    @Nested
    @DisplayName("is rendered by an advice the running service will find")
    class Wiring {

        /**
         * The standalone setup above registers the advice by hand, so it would keep passing if the
         * annotation that makes Spring register it went missing — and that is the exact shape of the
         * reported failure: the reason was authored, and nothing put it in the body. There is no
         * Spring context in this module to prove it end to end, so the annotation is asserted
         * directly.
         */
        @Test
        void the_advice_is_declared_for_this_controller() {
            RestControllerAdvice advice = NotificationPreferenceExceptionHandler.class
                    .getAnnotation(RestControllerAdvice.class);

            assertThat(advice).as("@RestControllerAdvice on the handler").isNotNull();
            assertThat(advice.assignableTypes()).contains(NotificationPreferenceController.class);
        }
    }

    @Nested
    @DisplayName("leaks nothing")
    class Safe {

        /** An error body is rendered somewhere by somebody sooner or later. */
        @Test
        void does_not_repeat_the_string_the_caller_sent() throws Exception {
            assertThat(detailOf("CAT_PHOTOS", "PUSH")).doesNotContain("CAT_PHOTOS");
            assertThat(detailOf("PROMOTIONS", "PIGEON")).doesNotContain("PIGEON");
        }

        @Test
        void does_not_name_our_classes_or_the_framework() throws Exception {
            doThrow(new IllegalArgumentException(
                    "security and account notifications cannot be turned off"))
                    .when(preferences).apply(anyString(), any());

            assertThat(detailOf("ACCOUNT", "EMAIL"))
                    .doesNotContain("com.delivery", "Exception", "org.springframework");
        }
    }
}
