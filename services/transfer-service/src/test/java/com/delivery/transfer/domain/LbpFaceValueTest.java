package com.delivery.transfer.domain;

import java.math.BigDecimal;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The lira figure a customer approves must be the figure the rider is told to collect.
 *
 * <p>It was not. The quote rounded to the nearest 1,000-lira note while the stored record simply
 * multiplied, so the two agreed only when the product already happened to be a multiple of 1,000 —
 * which is why every round demo number hid it. An end-to-end run caught it at $10.01, where the
 * customer approved 1,000 LBP and the record said 900.
 */
class LbpFaceValueTest {

    private static final BigDecimal RATE = new BigDecimal("90000");
    private static final BigDecimal NOTE = new BigDecimal("1000");

    @ParameterizedTest(name = "${0} settles as {1} LBP")
    @CsvSource({
            // The figures the end-to-end run reported, plus the halfway case where the rounding
            // has to make a choice, and zero.
            "10.00, 900000",
            "10.01, 901000",
            "10.02, 902000",
            "10.05, 905000",
            "0.00,       0",
            // 450 lira: below half a note, so it settles at nothing. That is the honest
            // consequence of a notes-only currency, and the quote now says the same.
            "0.005,       0",
    })
    @DisplayName("a split always settles on a note that exists")
    void roundsToACirculatingNote(String usd, String expected) {
        BigDecimal face = MoneyTransfer.lbpFaceOf(new BigDecimal(usd), RATE);

        assertThat(face).isEqualByComparingTo(new BigDecimal(expected));
        // Nobody can hand over 900 lira: the smallest circulating note is 1,000 and there is no
        // coinage to settle a remainder with.
        assertThat(face.remainder(NOTE))
                .as("%s LBP cannot be paid in notes", face)
                .isEqualByComparingTo(BigDecimal.ZERO);
    }
}
