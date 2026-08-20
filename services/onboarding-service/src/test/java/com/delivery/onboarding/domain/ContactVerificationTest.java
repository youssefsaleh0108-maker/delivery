package com.delivery.onboarding.domain;

import java.lang.reflect.Field;
import java.time.Instant;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.onboarding.domain.ContactVerification.Channel;
import com.delivery.onboarding.domain.ContactVerification.Outcome;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * The one-time code, and the three things that make six digits worth anything.
 *
 * <p>The code is not the security. It expires, wrong guesses are capped, and the proof it produces
 * is single-use — take any of those away and a six-digit secret over a public endpoint is a
 * formality. Each is pinned here, along with the one that was missing: that answering an
 * already-answered challenge still requires the code.
 */
class ContactVerificationTest {

    /**
     * The code is deliberately unreachable from the entity, so a test that needs to know it has to
     * take it from {@link ContactVerification#issue} the way the service does.
     */
    private static ContactVerification.Issued issued() {
        return ContactVerification.issue(Channel.EMAIL, "sam@example.test");
    }

    /** Ages a challenge past its lifetime without waiting ten real minutes. */
    private static void expire(ContactVerification verification) throws Exception {
        Field field = ContactVerification.class.getDeclaredField("expiresAt");
        field.setAccessible(true);
        field.set(verification, Instant.now().minusSeconds(1));
    }

    private static String wrongCodeFor(String realCode) {
        return realCode.equals("000000") ? "111111" : "000000";
    }

    @Nested
    @DisplayName("issuing")
    class Issuing {

        @Test
        void produces_a_six_digit_code() {
            assertThat(issued().code()).hasSize(6).containsOnlyDigits();
        }

        /** Trimming a leading zero would make some codes five digits and shrink the space. */
        @Test
        void keeps_leading_zeros_so_every_code_is_the_same_length() {
            for (int i = 0; i < 500; i++) {
                assertThat(ContactVerification.issue(Channel.EMAIL, "a@b.test").code()).hasSize(6);
            }
        }

        @Test
        void produces_a_different_code_and_token_each_time() {
            ContactVerification.Issued first = issued();
            ContactVerification.Issued second = issued();

            assertThat(first.verification().getToken())
                    .isNotEqualTo(second.verification().getToken());
            assertThat(first.verification().getId()).isNotEqualTo(second.verification().getId());
        }

        /**
         * This table is the one place a leak would otherwise hand somebody a working code for every
         * address mid-verification. There must be no way to read the code back off the entity.
         */
        @Test
        void the_entity_never_exposes_the_code() {
            assertThat(ContactVerification.class.getDeclaredMethods())
                    .filteredOn(m -> java.lang.reflect.Modifier.isPublic(m.getModifiers()))
                    .filteredOn(m -> m.getParameterCount() == 0)
                    .noneMatch(m -> m.getName().toLowerCase(java.util.Locale.ROOT).contains("code"));
        }

        /** Two challenges for the same code must not hash alike, or the salt is doing nothing. */
        @Test
        void the_same_code_hashes_differently_under_different_salts() throws Exception {
            ContactVerification.Issued first = issued();
            ContactVerification.Issued second = issued();

            Field hash = ContactVerification.class.getDeclaredField("codeHash");
            Field salt = ContactVerification.class.getDeclaredField("salt");
            hash.setAccessible(true);
            salt.setAccessible(true);

            assertThat(salt.get(first.verification())).isNotEqualTo(salt.get(second.verification()));
            // Only meaningful when the two codes happen to collide, which is why the salt matters.
            if (first.code().equals(second.code())) {
                assertThat(hash.get(first.verification()))
                        .isNotEqualTo(hash.get(second.verification()));
            }
        }

        @Test
        void starts_unusable_until_it_has_been_answered() {
            assertThat(issued().verification().isUsable()).isFalse();
        }
    }

    @Nested
    @DisplayName("answering the code")
    class Confirming {

        @Test
        void the_right_code_confirms() {
            ContactVerification.Issued issued = issued();

            assertThat(issued.verification().confirm(issued.code())).isEqualTo(Outcome.CONFIRMED);
            assertThat(issued.verification().isUsable()).isTrue();
            assertThat(issued.verification().getConfirmedAt()).isNotNull();
        }

        @Test
        void a_wrong_code_is_refused_and_counted() {
            ContactVerification.Issued issued = issued();

            assertThat(issued.verification().confirm(wrongCodeFor(issued.code())))
                    .isEqualTo(Outcome.WRONG);
            assertThat(issued.verification().getAttempts()).isEqualTo((short) 1);
            assertThat(issued.verification().isUsable()).isFalse();
        }

        /** One in a million per attempt is one in a thousand over a thousand attempts. */
        @Test
        void guessing_is_capped() {
            ContactVerification.Issued issued = issued();
            String wrong = wrongCodeFor(issued.code());

            for (int i = 0; i < ContactVerification.MAX_ATTEMPTS; i++) {
                assertThat(issued.verification().confirm(wrong)).isEqualTo(Outcome.WRONG);
            }

            assertThat(issued.verification().confirm(wrong)).isEqualTo(Outcome.TOO_MANY_ATTEMPTS);
        }

        /** Exhausting the cap must kill the code, not merely pause it — including for the real one. */
        @Test
        void the_right_code_no_longer_works_once_the_cap_is_hit() {
            ContactVerification.Issued issued = issued();
            String wrong = wrongCodeFor(issued.code());
            for (int i = 0; i < ContactVerification.MAX_ATTEMPTS; i++) {
                issued.verification().confirm(wrong);
            }

            assertThat(issued.verification().confirm(issued.code()))
                    .isEqualTo(Outcome.TOO_MANY_ATTEMPTS);
            assertThat(issued.verification().isUsable()).isFalse();
        }

        @Test
        void an_expired_code_is_refused() throws Exception {
            ContactVerification.Issued issued = issued();
            expire(issued.verification());

            assertThat(issued.verification().confirm(issued.code())).isEqualTo(Outcome.EXPIRED);
            assertThat(issued.verification().isUsable()).isFalse();
        }
    }

    @Nested
    @DisplayName("answering a challenge that was already answered")
    class RepeatConfirmation {

        /**
         * The regression test for an authentication bypass.
         *
         * <p>The confirm endpoint is public, takes {@code (destination, code)} and answers with the
         * proof token. While an already-confirmed challenge returned CONFIRMED without looking at
         * the code, anyone who could name an address that had just been verified — and not yet
         * spent — could send any six digits, collect the token earned for it, and submit an
         * application in that person's name.
         */
        @Test
        void a_wrong_code_cannot_collect_the_proof_somebody_else_earned() {
            ContactVerification.Issued issued = issued();
            issued.verification().confirm(issued.code());
            assertThat(issued.verification().isUsable()).isTrue();

            Outcome attacker = issued.verification().confirm(wrongCodeFor(issued.code()));

            assertThat(attacker).isEqualTo(Outcome.WRONG);
        }

        /** Guessing against an already-confirmed challenge is capped like any other guessing. */
        @Test
        void guessing_against_a_confirmed_challenge_is_capped_too() {
            ContactVerification.Issued issued = issued();
            issued.verification().confirm(issued.code());
            String wrong = wrongCodeFor(issued.code());

            for (int i = 1; i < ContactVerification.MAX_ATTEMPTS; i++) {
                issued.verification().confirm(wrong);
            }

            assertThat(issued.verification().confirm(wrong)).isEqualTo(Outcome.TOO_MANY_ATTEMPTS);
        }

        /** The allowance the shortcut existed for still has to work: a retry with the right code. */
        @Test
        void the_right_code_still_confirms_a_second_time() {
            ContactVerification.Issued issued = issued();
            Instant firstConfirmedAt = null;

            assertThat(issued.verification().confirm(issued.code())).isEqualTo(Outcome.CONFIRMED);
            firstConfirmedAt = issued.verification().getConfirmedAt();

            assertThat(issued.verification().confirm(issued.code())).isEqualTo(Outcome.CONFIRMED);
            assertThat(issued.verification().getConfirmedAt()).isEqualTo(firstConfirmedAt);
            assertThat(issued.verification().isUsable()).isTrue();
        }

        /**
         * Expiry closes the window for answering a code, not the proof already given. An applicant
         * who verified their address and then spent ten minutes on the rest of the form has done
         * nothing wrong, and re-submitting must not fail.
         */
        @Test
        void a_confirmed_challenge_survives_the_codes_expiry() throws Exception {
            ContactVerification.Issued issued = issued();
            issued.verification().confirm(issued.code());

            expire(issued.verification());

            assertThat(issued.verification().confirm(issued.code())).isEqualTo(Outcome.CONFIRMED);
            assertThat(issued.verification().isUsable()).isTrue();
        }
    }

    @Nested
    @DisplayName("spending the proof")
    class Consuming {

        @Test
        void a_confirmed_proof_can_be_spent_once() {
            ContactVerification.Issued issued = issued();
            issued.verification().confirm(issued.code());

            issued.verification().consume();

            assertThat(issued.verification().getConsumedAt()).isNotNull();
            assertThat(issued.verification().isUsable()).isFalse();
        }

        /** One verified address must not underwrite an endless stream of applications. */
        @Test
        void it_cannot_be_spent_twice() {
            ContactVerification.Issued issued = issued();
            issued.verification().confirm(issued.code());
            issued.verification().consume();

            assertThatThrownBy(issued.verification()::consume)
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining("already been used");
        }

        @Test
        void an_unanswered_challenge_cannot_be_spent() {
            assertThatThrownBy(issued().verification()::consume)
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining("not been verified");
        }

        /** Once spent, re-answering must not mint a fresh proof from the same challenge. */
        @Test
        void a_spent_challenge_reports_itself_used_rather_than_confirming_again() {
            ContactVerification.Issued issued = issued();
            issued.verification().confirm(issued.code());
            issued.verification().consume();

            assertThat(issued.verification().confirm(issued.code())).isEqualTo(Outcome.ALREADY_USED);
        }
    }
}
