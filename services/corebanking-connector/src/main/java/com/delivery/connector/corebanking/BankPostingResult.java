package com.delivery.connector.corebanking;

import java.time.Instant;

import com.delivery.platform.notifications.DeliveryOutcome;

/**
 * What the bank did, reported back to the accounting saga.
 *
 * <p>Carries the full request and response payloads because the accounting service writes them to
 * {@code core_banking_sync_log} (Section 4). "What exactly did we send and what exactly came back"
 * is the first question in any reconciliation dispute, and it cannot be reconstructed later from a
 * status code.
 */
public record BankPostingResult(
        String transactionId,
        boolean success,
        boolean retryable,
        String provider,
        String coreBankingRef,
        String failureReason,
        String requestPayload,
        String responsePayload,
        Instant occurredAt) {

    public static final String ROUTING_KEY = "accounting.posting.result";

    public static BankPostingResult from(BankPostingCommand command, DeliveryOutcome outcome,
                                         String requestPayload, String responsePayload) {
        return new BankPostingResult(
                command.transactionId(),
                outcome.success(),
                // A failure the saga may see resolve on its own, versus one it must compensate for.
                !outcome.success() && outcome.retryable(),
                outcome.provider(),
                outcome.providerMessageId(),
                outcome.failureReason(),
                requestPayload,
                responsePayload,
                Instant.now());
    }
}
