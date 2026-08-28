package com.delivery.onboarding.service;

import java.time.Duration;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.domain.ContactVerification;
import com.delivery.onboarding.domain.ContactVerification.Channel;
import com.delivery.onboarding.domain.ContactVerification.Purpose;
import com.delivery.onboarding.domain.ContactVerificationRepository;
import com.delivery.onboarding.service.VerificationService.TooManyRequestsException;
import com.delivery.onboarding.service.VerificationService.VerificationException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * "Forgot password", tested through a real {@link VerificationService} rather than a mocked one,
 * because the properties worth proving live in the seam between the two: the same abuse limits,
 * a purpose that cannot be crossed with sign-up, and — above everything — that nothing observable
 * differs between an address that has an account and one that does not.
 */
class PasswordResetServiceTest {

    private static final String EMAIL = "sam@example.test";
    private static final String USER_REF = "keycloak-sub-sam";

    private ContactVerificationRepository verifications;
    private PlatformClient platform;
    private KeycloakAdminClient keycloak;
    private PasswordResetService service;
    private VerificationService verificationService;

    @BeforeEach
    void setUp() {
        verifications = mock(ContactVerificationRepository.class);
        platform = mock(PlatformClient.class);
        keycloak = mock(KeycloakAdminClient.class);
        verificationService = new VerificationService(
                verifications, platform, Duration.ofSeconds(60), 8, "+961");
        service = new PasswordResetService(verificationService, keycloak);

        when(verifications.findFirstByChannelAndDestinationOrderByCreatedAtDesc(any(), anyString()))
                .thenReturn(Optional.empty());
        when(verifications.findFirstByChannelAndDestinationAndPurposeOrderByCreatedAtDesc(
                any(), anyString(), any())).thenReturn(Optional.empty());
        when(verifications.countByDestinationAndCreatedAtAfter(anyString(), any())).thenReturn(0L);
        when(verifications.saveAndFlush(any(ContactVerification.class)))
                .thenAnswer(call -> call.getArgument(0));
        when(verifications.save(any(ContactVerification.class)))
                .thenAnswer(call -> call.getArgument(0));
    }

    /** A confirmed-but-unspent reset challenge for the address, wired into the mocked repository. */
    private ContactVerification.Issued issuedResetFor(String destination) {
        ContactVerification.Issued issued =
                ContactVerification.issue(Channel.EMAIL, destination, Purpose.PASSWORD_RESET);
        when(verifications.findFirstByChannelAndDestinationAndPurposeOrderByCreatedAtDesc(
                eq(Channel.EMAIL), eq(destination), eq(Purpose.PASSWORD_RESET)))
                .thenReturn(Optional.of(issued.verification()));
        when(verifications.findByToken(issued.verification().getToken()))
                .thenReturn(Optional.of(issued.verification()));
        return issued;
    }

    @Nested
    @DisplayName("asking for a code")
    class Requesting {

        @Test
        void an_address_with_an_account_is_sent_a_reset_code() {
            when(keycloak.findUserIdByEmail(EMAIL)).thenReturn(Optional.of(USER_REF));

            service.request(EMAIL);

            ArgumentCaptor<String> body = ArgumentCaptor.forClass(String.class);
            verify(platform).notifyDirect(eq("EMAIL"), eq(EMAIL), anyString(), body.capture(),
                    eq("onboarding.password-reset"));
            assertThat(body.getValue()).containsPattern("\\d{6}").contains("reset");
        }

        /** The challenge is recorded under its own purpose, or the confirm step could not find it. */
        @Test
        void the_challenge_is_recorded_as_a_password_reset_before_it_is_sent() {
            when(keycloak.findUserIdByEmail(EMAIL)).thenReturn(Optional.of(USER_REF));

            service.request(EMAIL);

            ArgumentCaptor<ContactVerification> saved =
                    ArgumentCaptor.forClass(ContactVerification.class);
            org.mockito.InOrder order = org.mockito.Mockito.inOrder(verifications, platform);
            order.verify(verifications).saveAndFlush(saved.capture());
            order.verify(platform).notifyDirect(anyString(), anyString(), any(), anyString(),
                    anyString());
            assertThat(saved.getValue().getPurpose()).isEqualTo(Purpose.PASSWORD_RESET);
        }

        /**
         * The property the whole endpoint hangs on: an unknown address gets no message, but
         * everything a caller could observe — the outcome, and the challenge row the limits count
         * — is identical to the known-address case. "Nothing was sent" is not observable.
         */
        @Test
        void an_unknown_address_records_the_challenge_but_sends_nothing() {
            when(keycloak.findUserIdByEmail(EMAIL)).thenReturn(Optional.empty());

            assertThatCode(() -> service.request(EMAIL)).doesNotThrowAnyException();

            verify(verifications).saveAndFlush(any(ContactVerification.class));
            verify(platform, never()).notifyDirect(anyString(), anyString(), any(), anyString(),
                    anyString());
        }

        /** Keycloak being down must look like "no account", not become a distinguishable error. */
        @Test
        void a_failed_account_lookup_is_treated_as_no_account() {
            when(keycloak.findUserIdByEmail(anyString()))
                    .thenThrow(new IllegalStateException("keycloak down"));

            assertThatCode(() -> service.request(EMAIL)).doesNotThrowAnyException();

            verify(platform, never()).notifyDirect(anyString(), anyString(), any(), anyString(),
                    anyString());
        }

        /**
         * A send can only fail for an address that has an account, so reporting it would answer
         * exactly the question the endpoint must not answer.
         */
        @Test
        void a_failed_send_is_swallowed_rather_than_revealing_the_account_exists() {
            when(keycloak.findUserIdByEmail(EMAIL)).thenReturn(Optional.of(USER_REF));
            doThrow(new IllegalStateException("relay down")).when(platform)
                    .notifyDirect(anyString(), anyString(), any(), anyString(), anyString());

            assertThatCode(() -> service.request(EMAIL)).doesNotThrowAnyException();
        }

        /** The sign-up path still reports the same failure honestly — only the reset path swallows. */
        @Test
        void the_signup_path_still_reports_a_failed_send() {
            doThrow(new IllegalStateException("relay down")).when(platform)
                    .notifyDirect(anyString(), anyString(), any(), anyString(), anyString());

            assertThatThrownBy(() -> verificationService.request(Channel.EMAIL, EMAIL))
                    .isInstanceOf(VerificationException.class)
                    .hasMessageContaining("could not send");
        }
    }

    @Nested
    @DisplayName("the abuse limits, shared with sign-up")
    class Limits {

        /**
         * The refusal comes before the account lookup, so the limits shield Keycloak from a spray
         * — and so the refusal itself cannot differ between known and unknown addresses.
         */
        @Test
        void the_cooldown_refuses_before_the_account_is_even_looked_up() {
            ContactVerification recent = ContactVerification
                    .issue(Channel.EMAIL, EMAIL, Purpose.PASSWORD_RESET).verification();
            setCreatedAt(recent, java.time.Instant.now().minusSeconds(5));
            when(verifications.findFirstByChannelAndDestinationOrderByCreatedAtDesc(
                    eq(Channel.EMAIL), eq(EMAIL))).thenReturn(Optional.of(recent));

            assertThatThrownBy(() -> service.request(EMAIL))
                    .isInstanceOf(TooManyRequestsException.class);

            verify(keycloak, never()).findUserIdByEmail(anyString());
            verify(platform, never()).notifyDirect(anyString(), anyString(), any(), anyString(),
                    anyString());
        }

        /** A recent SIGNUP code counts too: the cooldown protects the inbox, not the purpose. */
        @Test
        void a_recent_signup_code_to_the_same_address_also_triggers_the_cooldown() {
            ContactVerification recent =
                    ContactVerification.issue(Channel.EMAIL, EMAIL).verification();
            setCreatedAt(recent, java.time.Instant.now().minusSeconds(5));
            when(verifications.findFirstByChannelAndDestinationOrderByCreatedAtDesc(
                    eq(Channel.EMAIL), eq(EMAIL))).thenReturn(Optional.of(recent));

            assertThatThrownBy(() -> service.request(EMAIL))
                    .isInstanceOf(TooManyRequestsException.class);
        }

        @Test
        void the_daily_cap_per_destination_is_enforced() {
            when(verifications.countByDestinationAndCreatedAtAfter(eq(EMAIL), any()))
                    .thenReturn(8L);

            assertThatThrownBy(() -> service.request(EMAIL))
                    .isInstanceOf(TooManyRequestsException.class)
                    .hasMessageContaining("too many codes today");

            verify(keycloak, never()).findUserIdByEmail(anyString());
        }

        private void setCreatedAt(ContactVerification verification, java.time.Instant at) {
            try {
                java.lang.reflect.Field field =
                        ContactVerification.class.getDeclaredField("createdAt");
                field.setAccessible(true);
                field.set(verification, at);
            } catch (ReflectiveOperationException e) {
                throw new IllegalStateException(e);
            }
        }
    }

    @Nested
    @DisplayName("answering the code")
    class Confirming {

        @Test
        void the_right_code_sets_the_new_passcode_through_keycloak() {
            ContactVerification.Issued issued = issuedResetFor(EMAIL);
            when(keycloak.findUserIdByEmail(EMAIL)).thenReturn(Optional.of(USER_REF));

            service.confirm(EMAIL, issued.code(), "654321");

            verify(keycloak).resetPassword(USER_REF, "654321");
        }

        @Test
        void a_wrong_code_is_refused_in_the_verification_machinerys_own_words() {
            ContactVerification.Issued issued = issuedResetFor(EMAIL);
            String wrong = issued.code().equals("000000") ? "111111" : "000000";

            assertThatThrownBy(() -> service.confirm(EMAIL, wrong, "654321"))
                    .isInstanceOf(VerificationException.class)
                    .hasMessageContaining("not right");

            verify(keycloak, never()).resetPassword(anyString(), anyString());
        }

        /** One code, one reset. The proof is spent inside the confirm, so a replay finds it dead. */
        @Test
        void the_code_is_single_use() {
            ContactVerification.Issued issued = issuedResetFor(EMAIL);
            when(keycloak.findUserIdByEmail(EMAIL)).thenReturn(Optional.of(USER_REF));

            service.confirm(EMAIL, issued.code(), "654321");

            assertThatThrownBy(() -> service.confirm(EMAIL, issued.code(), "999999"))
                    .isInstanceOf(VerificationException.class)
                    .hasMessageContaining("already been used");
            verify(keycloak, times(1)).resetPassword(anyString(), anyString());
        }

        /**
         * The crossing the purpose column exists to prevent: a code sent to confirm a sign-up
         * must be worthless on the reset form, in the same words as a wrong code.
         */
        @Test
        void a_signup_code_cannot_reset_a_passcode() {
            ContactVerification.Issued signup =
                    ContactVerification.issue(Channel.EMAIL, EMAIL, Purpose.SIGNUP);
            when(verifications.findFirstByChannelAndDestinationAndPurposeOrderByCreatedAtDesc(
                    eq(Channel.EMAIL), eq(EMAIL), eq(Purpose.SIGNUP)))
                    .thenReturn(Optional.of(signup.verification()));
            // The reset-purpose lookup finds nothing — that IS the mechanism.

            assertThatThrownBy(() -> service.confirm(EMAIL, signup.code(), "654321"))
                    .isInstanceOf(VerificationException.class)
                    .hasMessageContaining("not right, or it has expired");

            verify(keycloak, never()).resetPassword(anyString(), anyString());
        }

        /** And the reverse: a reset code answered on the sign-up confirm finds no challenge. */
        @Test
        void a_reset_code_cannot_confirm_a_signup() {
            ContactVerification.Issued reset = issuedResetFor(EMAIL);

            assertThatThrownBy(() -> verificationService.confirm(Channel.EMAIL, EMAIL, reset.code()))
                    .isInstanceOf(VerificationException.class)
                    .hasMessageContaining("not right, or it has expired");
        }

        /**
         * Only reachable by guessing the code of a challenge that was recorded but never sent, so
         * the refusal deliberately reveals nothing about the address having no account.
         */
        @Test
        void a_right_code_for_an_address_without_an_account_is_refused_like_a_wrong_code() {
            ContactVerification.Issued issued = issuedResetFor(EMAIL);
            when(keycloak.findUserIdByEmail(EMAIL)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.confirm(EMAIL, issued.code(), "654321"))
                    .isInstanceOf(VerificationException.class)
                    .hasMessageContaining("not right, or it has expired");

            verify(keycloak, never()).resetPassword(anyString(), anyString());
        }

        @Test
        void a_keycloak_refusal_propagates_so_the_transaction_returns_the_proof() {
            ContactVerification.Issued issued = issuedResetFor(EMAIL);
            when(keycloak.findUserIdByEmail(EMAIL)).thenReturn(Optional.of(USER_REF));
            doThrow(new KeycloakAdminClient.ProvisioningException("keycloak said no"))
                    .when(keycloak).resetPassword(anyString(), anyString());

            assertThatThrownBy(() -> service.confirm(EMAIL, issued.code(), "654321"))
                    .isInstanceOf(KeycloakAdminClient.ProvisioningException.class);
        }

        /** The address is normalised before the challenge is looked up, like everywhere else. */
        @Test
        void the_address_is_normalised_before_the_challenge_is_looked_up() {
            ContactVerification.Issued issued = issuedResetFor(EMAIL);
            when(keycloak.findUserIdByEmail(EMAIL)).thenReturn(Optional.of(USER_REF));

            service.confirm("  Sam@Example.TEST ", issued.code(), "654321");

            verify(keycloak).resetPassword(USER_REF, "654321");
        }
    }
}
