package com.delivery.onboarding.api;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.service.PasswordResetService;
import com.delivery.onboarding.service.VerificationService;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * The HTTP contract of "Forgot password": the statuses the sign-in screen keys its states off.
 *
 * <p>The properties themselves — nothing observable differs by account existence, codes are
 * single-use, the limits hold — are proved in {@code PasswordResetServiceTest}; this file pins the
 * status codes and the validation floor, because the client wave builds against exactly these.
 */
class PasswordResetApiTest {

    private PasswordResetService resets;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        resets = mock(PasswordResetService.class);
        mvc = MockMvcBuilders.standaloneSetup(new PasswordResetController(resets)).build();
    }

    @Nested
    @DisplayName("asking for a code")
    class Requesting {

        /** 202 is the only success answer, for known and unknown addresses alike. */
        @Test
        void a_well_formed_address_is_accepted_with_202_and_no_body() throws Exception {
            mvc.perform(post("/api/onboarding/password-reset")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"email\": \"sam@example.test\"}"))
                    .andExpect(status().isAccepted());

            verify(resets).request("sam@example.test");
        }

        @Test
        void an_address_that_is_not_one_is_a_400_before_the_service_is_asked() throws Exception {
            mvc.perform(post("/api/onboarding/password-reset")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"email\": \"not an address\"}"))
                    .andExpect(status().isBadRequest());

            verify(resets, never()).request(anyString());
        }

        @Test
        void a_limit_refusal_is_a_429_so_the_screen_stops_retrying() throws Exception {
            doThrow(new VerificationService.TooManyRequestsException("Wait a moment"))
                    .when(resets).request(anyString());

            mvc.perform(post("/api/onboarding/password-reset")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"email\": \"sam@example.test\"}"))
                    .andExpect(status().isTooManyRequests())
                    .andExpect(jsonPath("$.message").value("Wait a moment"));
        }
    }

    @Nested
    @DisplayName("answering the code")
    class Confirming {

        @Test
        void a_successful_reset_is_a_204_with_nothing_to_say() throws Exception {
            mvc.perform(post("/api/onboarding/password-reset/confirm")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"email\": \"sam@example.test\","
                                    + " \"code\": \"123456\", \"newPassword\": \"654321\"}"))
                    .andExpect(status().isNoContent());

            verify(resets).confirm("sam@example.test", "123456", "654321");
        }

        /** The same floor account creation enforces: fewer than six characters never leaves the API. */
        @Test
        void a_passcode_below_the_floor_is_a_400_before_the_service_is_asked() throws Exception {
            mvc.perform(post("/api/onboarding/password-reset/confirm")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"email\": \"sam@example.test\","
                                    + " \"code\": \"123456\", \"newPassword\": \"12345\"}"))
                    .andExpect(status().isBadRequest());

            verify(resets, never()).confirm(anyString(), anyString(), anyString());
        }

        @Test
        void a_wrong_code_is_the_verification_machinerys_422_in_its_own_words() throws Exception {
            doThrow(new VerificationService.VerificationException(
                    "That code is not right, or it has expired. Ask for a new one."))
                    .when(resets).confirm(anyString(), anyString(), anyString());

            mvc.perform(post("/api/onboarding/password-reset/confirm")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"email\": \"sam@example.test\","
                                    + " \"code\": \"000000\", \"newPassword\": \"654321\"}"))
                    .andExpect(status().isUnprocessableEntity())
                    .andExpect(jsonPath("$.message").value(
                            "That code is not right, or it has expired. Ask for a new one."));
        }

        /** Keycloak refusing is our failure, not the caller's — a 502 with a retry message. */
        @Test
        void a_keycloak_failure_is_a_502_rather_than_blaming_the_caller() throws Exception {
            doThrow(new KeycloakAdminClient.ProvisioningException(
                    "The passcode could not be updated just now. Please try again in a moment."))
                    .when(resets).confirm(anyString(), anyString(), anyString());

            mvc.perform(post("/api/onboarding/password-reset/confirm")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"email\": \"sam@example.test\","
                                    + " \"code\": \"123456\", \"newPassword\": \"654321\"}"))
                    .andExpect(status().isBadGateway())
                    .andExpect(jsonPath("$.message").exists());
        }

        @Test
        void a_missing_code_is_a_400() throws Exception {
            mvc.perform(post("/api/onboarding/password-reset/confirm")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"email\": \"sam@example.test\","
                                    + " \"newPassword\": \"654321\"}"))
                    .andExpect(status().isBadRequest());

            verify(resets, never()).confirm(any(), any(), any());
        }
    }
}
