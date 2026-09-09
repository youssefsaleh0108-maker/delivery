package com.delivery.transfer.domain;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * The scale every money figure this service prints must already be in.
 *
 * <p>A BigDecimal remembers the scale it was built with, so one rate reached clients as
 * {@code 90000} straight after a POST (it came from configuration) and {@code 90000.00} on the
 * following GET (it came back off a {@code numeric(12,2)} column). A client comparing the quote
 * it approved against the record it reads then sees two figures that are the same money and do
 * not match. Normalising at the edge is what makes the two paths agree.
 *
 * @see MoneyTransfer#lbpFaceOf the separate rule that puts a lira figure on a note that exists
 */
public final class Money {

    private Money() {
    }

    /** Dollars carry cents — always both of them, whichever path the figure arrived by. */
    public static BigDecimal usd(BigDecimal amount) {
        return amount == null ? null : amount.setScale(2, RoundingMode.HALF_UP);
    }

    /**
     * Lira carry no fraction. There is no sub-note denomination to express one in, so a decimal
     * place on a lira figure is not precision, it is a number nobody can hand over.
     */
    public static BigDecimal lbp(BigDecimal amount) {
        return amount == null ? null : amount.setScale(0, RoundingMode.HALF_UP);
    }
}
