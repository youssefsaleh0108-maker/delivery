package com.delivery.onboarding.domain;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatExceptionOfType;
import static org.assertj.core.api.Assertions.assertThatNoException;

/**
 * The mod-97 check on a payout account number.
 *
 * <p>The guarantee being pinned is narrow and worth stating plainly: an IBAN with two digits the
 * wrong way round is the right length, starts with the right country code, and looks correct to
 * everybody who reads it — including the applicant who typed it and the reviewer who approved them.
 * The only thing that catches it before the first payout run is the arithmetic, so the arithmetic
 * has to be right, and it has to be right for every country the platform pays into rather than for
 * whichever example was to hand when it was written.
 */
class IbanTest {

    @Nested
    @DisplayName("a well-formed account number")
    class WellFormed {

        /**
         * Published example IBANs from the countries YouDrop pays into, plus three European ones
         * because the check has to be about the algorithm rather than about a length that happens
         * to suit the Gulf.
         */
        @ParameterizedTest
        @ValueSource(strings = {
                "EG380019000500000000263180002",   // Egypt
                "SA0380000000608010167519",        // Saudi Arabia
                "AE070331234567890123456",         // United Arab Emirates
                "QA58DOHB00001234567890ABCDEFG",   // Qatar — letters in the account part
                "KW81CBKU0000000000001234560101",  // Kuwait
                "JO94CBJO0010000000000131000302",  // Jordan
                "BH67BMAG00001299123456",          // Bahrain
                "GB82WEST12345698765432",          // United Kingdom
                "DE89370400440532013000",          // Germany
                "FR1420041010050500013M02606"      // France — a letter mid-account
        })
        @DisplayName("is accepted")
        void is_accepted(String candidate) {
            assertThatNoException().isThrownBy(() -> Iban.parse(candidate));
        }

        /** Printed IBANs are grouped in fours and people paste them that way. */
        @Test
        void survives_the_spaces_and_lower_case_somebody_pasted_it_with() {
            Iban iban = Iban.parse("  eg38 0019 0005 0000 0000 2631 80002 ");

            assertThat(iban.value()).isEqualTo("EG380019000500000000263180002");
            assertThat(iban.country()).isEqualTo("EG");
            assertThat(iban.lastFour()).isEqualTo("0002");
        }

        /** Nothing that renders an Iban by default may render the whole number. */
        @Test
        void never_prints_itself_in_full() {
            Iban iban = Iban.parse("EG380019000500000000263180002");

            assertThat(iban.toString())
                    .doesNotContain("EG380019000500000000263180002")
                    .isEqualTo("EG••••0002");
        }
    }

    @Nested
    @DisplayName("a number with two digits the wrong way round")
    class Transposed {

        /**
         * Every adjacent transposition of two different digits in one valid Egyptian IBAN. This is
         * the mistake the checksum exists to catch and the reason it is worth implementing rather
         * than trusting the form: each of these is 29 characters, starts with EG, and is wrong.
         */
        @ParameterizedTest
        @ValueSource(strings = {
                "EG830019000500000000263180002",
                "EG308019000500000000263180002",
                "EG380109000500000000263180002",
                "EG380091000500000000263180002",
                "EG380010900500000000263180002",
                "EG380019005000000000263180002",
                "EG380019000050000000263180002",
                "EG380019000500000002063180002",
                "EG380019000500000000623180002",
                "EG380019000500000000236180002",
                "EG380019000500000000261380002",
                "EG380019000500000000263810002",
                "EG380019000500000000263108002",
                "EG380019000500000000263180020"
        })
        @DisplayName("is refused, with a message that says a digit is wrong")
        void is_refused(String transposed) {
            assertThatExceptionOfType(Iban.InvalidIbanException.class)
                    .isThrownBy(() -> Iban.parse(transposed))
                    .withMessageContaining("check digits");
        }

        /** The check digits themselves are as transposable as the rest of the number. */
        @Test
        void including_when_the_two_that_moved_are_the_check_digits() {
            assertThatExceptionOfType(Iban.InvalidIbanException.class)
                    .isThrownBy(() -> Iban.parse("GB28WEST12345698765432"));
        }
    }

    @Nested
    @DisplayName("a number that is not an IBAN at all")
    class Malformed {

        @Test
        void is_refused_when_it_is_blank() {
            assertThatExceptionOfType(Iban.InvalidIbanException.class)
                    .isThrownBy(() -> Iban.parse("   "));
            assertThatExceptionOfType(Iban.InvalidIbanException.class)
                    .isThrownBy(() -> Iban.parse(null));
        }

        @Test
        void is_refused_when_it_does_not_start_with_a_country_and_two_check_digits() {
            assertThatExceptionOfType(Iban.InvalidIbanException.class)
                    .isThrownBy(() -> Iban.parse("1234567890123456"))
                    .withMessageContaining("two letters");
        }

        /**
         * A digit dropped on paste, rather than mistyped. Roughly one in ninety-seven of these
         * passes the checksum on its own, which is why the registered length is checked as well.
         */
        @Test
        void is_refused_when_the_country_says_it_should_be_longer() {
            assertThatExceptionOfType(Iban.InvalidIbanException.class)
                    .isThrownBy(() -> Iban.parse("EG38001900050000000026318000"))
                    .withMessageContaining("29 characters");
        }

        /**
         * A country the registered-length map has simply not been updated for still gets the
         * checksum. Refusing it outright would be a rule about this codebase rather than about the
         * number — and the IBAN registry gains entries.
         */
        @Test
        void still_gets_the_checksum_when_the_country_is_not_in_the_length_map() {
            // Norway: valid, and deliberately absent from REGISTERED_LENGTHS.
            assertThatNoException().isThrownBy(() -> Iban.parse("NO9386011117947"));
            assertThatExceptionOfType(Iban.InvalidIbanException.class)
                    .isThrownBy(() -> Iban.parse("NO9386011117974"))
                    .withMessageContaining("check digits");
        }
    }
}
