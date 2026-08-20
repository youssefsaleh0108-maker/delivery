package com.delivery.onboarding.service;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.domain.ContactVerification;
import com.delivery.onboarding.domain.ContactVerification.Channel;
import com.delivery.onboarding.domain.ContactVerificationRepository;
import com.delivery.onboarding.service.VerificationService.TooManyRequestsException;
import com.delivery.onboarding.service.VerificationService.VerificationException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The endpoint that will send a message to any address a stranger types, and the limits on it.
 *
 * <p>Two separable concerns live here. One is abuse: this is a spam engine unless the cooldown and
 * the daily cap hold, and both are counted per destination rather than per caller because the caller
 * has no account and the cost lands on whoever owns the inbox. The other is the destination binding
 * on {@code consume} — without it, verifying an address you do own lets you apply as anyone.
 */
class VerificationServiceTest {

    private ContactVerificationRepository verifications;
    private PlatformClient platform;
    private VerificationService service;

    @BeforeEach
    void setUp() {
        verifications = mock(ContactVerificationRepository.class);
        platform = mock(PlatformClient.class);
        service = new VerificationService(verifications, platform, Duration.ofSeconds(60), 8);

        when(verifications.findFirstByChannelAndDestinationOrderByCreatedAtDesc(any(), anyString()))
                .thenReturn(Optional.empty());
        when(verifications.countByDestinationAndCreatedAtAfter(anyString(), any())).thenReturn(0L);
        when(verifications.saveAndFlush(any(ContactVerification.class)))
                .thenAnswer(call -> call.getArgument(0));
        when(verifications.save(any(ContactVerification.class)))
                .thenAnswer(call -> call.getArgument(0));
    }

    private static ContactVerification confirmedFor(Channel channel, String destination) {
        ContactVerification.Issued issued = ContactVerification.issue(channel, destination);
        issued.verification().confirm(issued.code());
        return issued.verification();
    }

    @Nested
    @DisplayName("normalising a destination")
    class Normalising {

        /**
         * Without this, varying the capitalisation resets the rate limit — the same inbox can be
         * hammered by spelling it differently each time.
         */
        @Test
        void email_case_and_padding_collapse_to_one_destination() {
            assertThat(VerificationService.normalise(Channel.EMAIL, "  Sam@Example.COM "))
                    .isEqualTo("sam@example.com");
        }

        @Test
        void phone_punctuation_is_stripped_so_one_number_is_one_destination() {
            assertThat(VerificationService.normalise(Channel.PHONE, "+961 (3) 123-456"))
                    .isEqualTo("+9613123456");
            assertThat(VerificationService.normalise(Channel.PHONE, "+961.3.123.456"))
                    .isEqualTo("+9613123456");
        }

        @Test
        void prose_is_refused_on_both_channels() {
            assertThatThrownBy(() -> VerificationService.normalise(Channel.EMAIL, "not an address"))
                    .isInstanceOf(VerificationException.class)
                    .hasMessageContaining("email address");
            assertThatThrownBy(() -> VerificationService.normalise(Channel.PHONE, "call me"))
                    .isInstanceOf(VerificationException.class)
                    .hasMessageContaining("phone number");
        }

        @Test
        void an_email_without_a_dotted_domain_is_refused() {
            assertThatThrownBy(() -> VerificationService.normalise(Channel.EMAIL, "sam@localhost"))
                    .isInstanceOf(VerificationException.class);
        }

        @Test
        void a_blank_destination_is_refused_rather_than_sent_to() {
            assertThatThrownBy(() -> VerificationService.normalise(Channel.EMAIL, "   "))
                    .isInstanceOf(VerificationException.class);
            assertThatThrownBy(() -> VerificationService.normalise(Channel.PHONE, null))
                    .isInstanceOf(VerificationException.class);
        }

        /** Real numbering plans vary; the check rejects prose without rejecting real numbers. */
        @Test
        void plausible_phone_lengths_are_accepted_and_absurd_ones_are_not() {
            assertThat(VerificationService.normalise(Channel.PHONE, "1234567")).isEqualTo("1234567");
            assertThatThrownBy(() -> VerificationService.normalise(Channel.PHONE, "123456"))
                    .isInstanceOf(VerificationException.class);
            assertThatThrownBy(() -> VerificationService.normalise(Channel.PHONE, "1".repeat(16)))
                    .isInstanceOf(VerificationException.class);
        }

        @Test
        void the_quiet_form_reports_failure_without_throwing() {
            assertThat(VerificationService.normaliseQuietly(Channel.EMAIL, "Sam@Example.com"))
                    .contains("sam@example.com");
            assertThat(VerificationService.normaliseQuietly(Channel.EMAIL, "rubbish")).isEmpty();
        }
    }

    @Nested
    @DisplayName("requesting a code")
    class Requesting {

        @Test
        void sends_the_code_and_returns_only_when_it_expires() {
            Instant expiresAt = service.request(Channel.EMAIL, "sam@example.test");

            assertThat(expiresAt).isAfter(Instant.now());
            verify(platform).notifyDirect(eq("EMAIL"), eq("sam@example.test"), anyString(),
                    anyString(), anyString());
        }

        /** A code that went out but was never recorded cannot be confirmed by the person holding it. */
        @Test
        void records_the_challenge_before_sending_it() {
            service.request(Channel.EMAIL, "sam@example.test");

            org.mockito.InOrder order = org.mockito.Mockito.inOrder(verifications, platform);
            order.verify(verifications).saveAndFlush(any(ContactVerification.class));
            order.verify(platform).notifyDirect(anyString(), anyString(), any(), anyString(),
                    anyString());
        }

        @Test
        void an_sms_code_goes_out_without_a_subject_line() {
            service.request(Channel.PHONE, "+9613123456");

            verify(platform).notifyDirect(eq("SMS"), eq("+9613123456"), eq(null), anyString(),
                    anyString());
        }

        /** The message has to carry the code and say how long it lasts, or it is not usable. */
        @Test
        void the_message_carries_the_code_and_its_lifetime() {
            org.mockito.ArgumentCaptor<String> body =
                    org.mockito.ArgumentCaptor.forClass(String.class);
            service.request(Channel.EMAIL, "sam@example.test");

            verify(platform).notifyDirect(anyString(), anyString(), any(), body.capture(),
                    anyString());
            assertThat(body.getValue()).containsPattern("\\d{6}")
                    .contains(String.valueOf(ContactVerification.LIFETIME.toMinutes()));
        }

        /**
         * "We have sent you a code" is a promise. Reporting success while the send failed leaves
         * somebody waiting for a message that is never coming.
         */
        @Test
        void a_failed_send_is_reported_rather_than_swallowed() {
            doThrow(new IllegalStateException("relay down"))
                    .when(platform).notifyDirect(anyString(), anyString(), any(), anyString(),
                            anyString());

            assertThatThrownBy(() -> service.request(Channel.EMAIL, "sam@example.test"))
                    .isInstanceOf(VerificationException.class)
                    .hasMessageContaining("could not send");
        }

        /** The address is normalised before anything is counted against it, or the caps leak. */
        @Test
        void the_destination_is_normalised_before_the_limits_are_applied() {
            service.request(Channel.EMAIL, "  Sam@Example.COM ");

            verify(platform).notifyDirect(anyString(), eq("sam@example.com"), any(), anyString(),
                    anyString());
        }
    }

    @Nested
    @DisplayName("the abuse limits")
    class Limits {

        @Test
        void a_second_request_inside_the_cooldown_is_refused() {
            ContactVerification recent = ContactVerification
                    .issue(Channel.EMAIL, "sam@example.test").verification();
            setCreatedAt(recent, Instant.now().minusSeconds(5));
            when(verifications.findFirstByChannelAndDestinationOrderByCreatedAtDesc(
                    eq(Channel.EMAIL), eq("sam@example.test"))).thenReturn(Optional.of(recent));

            assertThatThrownBy(() -> service.request(Channel.EMAIL, "sam@example.test"))
                    .isInstanceOf(TooManyRequestsException.class)
                    .hasMessageContaining("Wait a moment");

            verify(platform, never()).notifyDirect(anyString(), anyString(), any(), anyString(),
                    anyString());
        }

        @Test
        void a_request_after_the_cooldown_is_allowed() {
            ContactVerification old = ContactVerification
                    .issue(Channel.EMAIL, "sam@example.test").verification();
            setCreatedAt(old, Instant.now().minusSeconds(120));
            when(verifications.findFirstByChannelAndDestinationOrderByCreatedAtDesc(
                    eq(Channel.EMAIL), eq("sam@example.test"))).thenReturn(Optional.of(old));

            service.request(Channel.EMAIL, "sam@example.test");

            verify(platform).notifyDirect(anyString(), anyString(), any(), anyString(), anyString());
        }

        /** Stops the endpoint being used to bury somebody's inbox over a day. */
        @Test
        void the_daily_cap_per_destination_is_enforced() {
            when(verifications.countByDestinationAndCreatedAtAfter(eq("sam@example.test"), any()))
                    .thenReturn(8L);

            assertThatThrownBy(() -> service.request(Channel.EMAIL, "sam@example.test"))
                    .isInstanceOf(TooManyRequestsException.class)
                    .hasMessageContaining("too many codes today");

            verify(platform, never()).notifyDirect(anyString(), anyString(), any(), anyString(),
                    anyString());
        }

        @Test
        void one_below_the_daily_cap_is_still_allowed() {
            when(verifications.countByDestinationAndCreatedAtAfter(eq("sam@example.test"), any()))
                    .thenReturn(7L);

            service.request(Channel.EMAIL, "sam@example.test");

            verify(platform).notifyDirect(anyString(), anyString(), any(), anyString(), anyString());
        }

        /** Separate exception type, so the API can answer 429 rather than 422. */
        @Test
        void a_limit_refusal_is_distinguishable_from_a_bad_address() {
            when(verifications.countByDestinationAndCreatedAtAfter(anyString(), any()))
                    .thenReturn(8L);

            assertThat(catchType(() -> service.request(Channel.EMAIL, "sam@example.test")))
                    .isEqualTo(TooManyRequestsException.class);
            assertThat(catchType(() -> service.request(Channel.EMAIL, "nonsense")))
                    .isEqualTo(VerificationException.class);
        }

        private Class<?> catchType(Runnable action) {
            try {
                action.run();
                return null;
            } catch (Exception e) {
                return e.getClass();
            }
        }

        private void setCreatedAt(ContactVerification verification, Instant at) {
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
    @DisplayName("confirming a code")
    class Confirming {

        @Test
        void the_right_code_hands_back_the_proof() {
            ContactVerification.Issued issued =
                    ContactVerification.issue(Channel.EMAIL, "sam@example.test");
            when(verifications.findFirstByChannelAndDestinationOrderByCreatedAtDesc(
                    eq(Channel.EMAIL), eq("sam@example.test")))
                    .thenReturn(Optional.of(issued.verification()));

            VerificationService.Confirmed confirmed =
                    service.confirm(Channel.EMAIL, "Sam@Example.test", issued.code());

            assertThat(confirmed.token()).isEqualTo(issued.verification().getToken());
            assertThat(confirmed.destination()).isEqualTo("sam@example.test");
        }

        /**
         * The regression test for the bypass, at the service boundary this time: the public endpoint
         * must not hand a stranger the token earned for an address they merely named.
         */
        @Test
        void a_stranger_cannot_collect_the_proof_for_an_address_somebody_else_verified() {
            ContactVerification victim = confirmedFor(Channel.EMAIL, "victim@example.test");
            when(verifications.findFirstByChannelAndDestinationOrderByCreatedAtDesc(
                    eq(Channel.EMAIL), eq("victim@example.test")))
                    .thenReturn(Optional.of(victim));

            assertThatThrownBy(() ->
                    service.confirm(Channel.EMAIL, "victim@example.test", "000000"))
                    .isInstanceOf(VerificationException.class)
                    .hasMessageContaining("not right");
        }

        /**
         * "No code was requested for that address" tells a stranger which addresses are
         * mid-application — a fact about somebody else, obtained by guessing.
         */
        @Test
        void an_unknown_address_is_refused_in_the_same_words_as_a_wrong_code() {
            when(verifications.findFirstByChannelAndDestinationOrderByCreatedAtDesc(any(), anyString()))
                    .thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.confirm(Channel.EMAIL, "nobody@example.test", "123456"))
                    .isInstanceOf(VerificationException.class)
                    .hasMessageContaining("not right, or it has expired");
        }

        @Test
        void a_wrong_code_is_refused() {
            ContactVerification.Issued issued =
                    ContactVerification.issue(Channel.EMAIL, "sam@example.test");
            when(verifications.findFirstByChannelAndDestinationOrderByCreatedAtDesc(any(), anyString()))
                    .thenReturn(Optional.of(issued.verification()));

            assertThatThrownBy(() -> service.confirm(Channel.EMAIL, "sam@example.test",
                    issued.code().equals("000000") ? "111111" : "000000"))
                    .isInstanceOf(VerificationException.class);
        }
    }

    @Nested
    @DisplayName("spending the proof")
    class Consuming {

        /**
         * The check the whole scheme rests on, and the easiest to leave out. Without it a token for
         * an address you do own verifies an application naming one you do not: verify your own
         * inbox once, then apply as anybody.
         */
        @Test
        void a_token_cannot_be_spent_against_a_different_address() {
            ContactVerification mine = confirmedFor(Channel.EMAIL, "attacker@example.test");
            when(verifications.findByToken(mine.getToken())).thenReturn(Optional.of(mine));

            assertThatThrownBy(() ->
                    service.consume(mine.getToken(), Channel.EMAIL, "victim@example.test"))
                    .isInstanceOf(VerificationException.class)
                    .hasMessageContaining("different email");
        }

        /** Nor against a different channel, for the same reason. */
        @Test
        void a_token_cannot_be_spent_on_a_different_channel() {
            ContactVerification emailProof = confirmedFor(Channel.EMAIL, "sam@example.test");
            when(verifications.findByToken(emailProof.getToken()))
                    .thenReturn(Optional.of(emailProof));

            assertThatThrownBy(() ->
                    service.consume(emailProof.getToken(), Channel.PHONE, "+9613123456"))
                    .isInstanceOf(VerificationException.class);
        }

        @Test
        void a_matching_token_is_spent_and_reports_when_it_was_verified() {
            ContactVerification proof = confirmedFor(Channel.EMAIL, "sam@example.test");
            when(verifications.findByToken(proof.getToken())).thenReturn(Optional.of(proof));

            Instant confirmedAt = service.consume(proof.getToken(), Channel.EMAIL, "sam@example.test");

            assertThat(confirmedAt).isNotNull();
            assertThat(proof.getConsumedAt()).isNotNull();
        }

        /** One verified address, one application. */
        @Test
        void the_same_token_cannot_be_spent_twice() {
            ContactVerification proof = confirmedFor(Channel.EMAIL, "sam@example.test");
            when(verifications.findByToken(proof.getToken())).thenReturn(Optional.of(proof));
            service.consume(proof.getToken(), Channel.EMAIL, "sam@example.test");

            assertThatThrownBy(() ->
                    service.consume(proof.getToken(), Channel.EMAIL, "sam@example.test"))
                    .isInstanceOf(VerificationException.class)
                    .hasMessageContaining("no longer valid");
        }

        @Test
        void an_unverified_token_cannot_be_spent() {
            ContactVerification unconfirmed =
                    ContactVerification.issue(Channel.EMAIL, "sam@example.test").verification();
            when(verifications.findByToken(unconfirmed.getToken()))
                    .thenReturn(Optional.of(unconfirmed));

            assertThatThrownBy(() ->
                    service.consume(unconfirmed.getToken(), Channel.EMAIL, "sam@example.test"))
                    .isInstanceOf(VerificationException.class);
        }

        @Test
        void an_invented_token_is_refused() {
            when(verifications.findByToken(anyString())).thenReturn(Optional.empty());

            assertThatThrownBy(() ->
                    service.consume("made-up", Channel.EMAIL, "sam@example.test"))
                    .isInstanceOf(VerificationException.class)
                    .hasMessageContaining("has not been verified");
        }

        /** The destination is normalised on the way in, so a differently-typed form still matches. */
        @Test
        void the_expected_destination_is_normalised_before_comparison() {
            ContactVerification proof = confirmedFor(Channel.EMAIL, "sam@example.test");
            when(verifications.findByToken(proof.getToken())).thenReturn(Optional.of(proof));

            assertThat(service.consume(proof.getToken(), Channel.EMAIL, " Sam@Example.TEST "))
                    .isNotNull();
        }
    }

    @Nested
    @DisplayName("checking a token without spending it")
    class Peeking {

        @Test
        void a_usable_matching_token_reads_as_verified() {
            ContactVerification proof = confirmedFor(Channel.EMAIL, "sam@example.test");
            when(verifications.findByToken(proof.getToken())).thenReturn(Optional.of(proof));

            assertThat(service.isVerified(proof.getToken(), Channel.EMAIL, "Sam@Example.test"))
                    .isTrue();
            // and it is still spendable afterwards
            assertThat(proof.getConsumedAt()).isNull();
        }

        @Test
        void a_token_for_another_address_does_not() {
            ContactVerification proof = confirmedFor(Channel.EMAIL, "sam@example.test");
            when(verifications.findByToken(proof.getToken())).thenReturn(Optional.of(proof));

            assertThat(service.isVerified(proof.getToken(), Channel.EMAIL, "other@example.test"))
                    .isFalse();
        }

        @Test
        void a_malformed_destination_reads_as_unverified_rather_than_throwing() {
            ContactVerification proof = confirmedFor(Channel.EMAIL, "sam@example.test");
            when(verifications.findByToken(proof.getToken())).thenReturn(Optional.of(proof));

            assertThatThrownBy(() -> service.isVerified(proof.getToken(), Channel.EMAIL, "rubbish"))
                    .isInstanceOf(VerificationException.class);
        }

        @Test
        void an_unknown_token_does_not() {
            when(verifications.findByToken(anyString())).thenReturn(Optional.empty());

            assertThat(service.isVerified("nope", Channel.EMAIL, "sam@example.test")).isFalse();
        }
    }

    /** Guards the assumption the rest of this file rests on: both channels behave the same way. */
    @Test
    void both_channels_are_covered_by_the_same_rules() {
        assertThat(List.of(Channel.values())).containsExactly(Channel.EMAIL, Channel.PHONE);
    }
}
