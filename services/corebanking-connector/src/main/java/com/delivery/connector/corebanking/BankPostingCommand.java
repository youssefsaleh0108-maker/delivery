package com.delivery.connector.corebanking;

import java.math.BigDecimal;
import java.math.RoundingMode;

import com.delivery.platform.notifications.IdempotentCommand;

/**
 * One movement the accounting saga wants made against one account.
 *
 * <p>The contract between the accounting service and this connector. Note what is absent: no order,
 * no commission rate, no notion of a settlement. The saga has already decided what should happen;
 * this connector only decides how to say it to whichever bank is live. That is what lets the
 * credential-holding process stay ignorant of the business rules.
 *
 * @param transactionId the accounting transaction row this came from — also the idempotency key
 *                      end to end, so a retried posting is one posting at the bank
 * @param amount        in major units; converted to minor units at the boundary, once
 */
public record BankPostingCommand(
        String transactionId,
        String accountRef,
        String direction,
        BigDecimal amount,
        String currency,
        String narrative,
        String correlationId) implements IdempotentCommand {

    public static final String ROUTING_KEY = "accounting.posting.requested";

    public static final String DEBIT = "DEBIT";
    public static final String CREDIT = "CREDIT";

    @Override
    public String idempotencyKey() {
        return transactionId;
    }

    /**
     * Minor units, rounded half-up, as a long.
     *
     * <p>Converted here at the edge rather than anywhere else, and never carried as a double. The
     * bank's ledger is in minor units; doing the conversion once, in the one place that talks to
     * it, is what stops two components disagreeing about what 12.345 means.
     *
     * <p>Assumes a two-decimal currency, which is true of every currency this platform handles.
     * A three-decimal currency (KWD, BHD) would need the exponent from the account, and this is
     * where that would go.
     */
    public long amountMinor() {
        return amount.setScale(2, RoundingMode.HALF_UP).movePointRight(2).longValueExact();
    }
}
