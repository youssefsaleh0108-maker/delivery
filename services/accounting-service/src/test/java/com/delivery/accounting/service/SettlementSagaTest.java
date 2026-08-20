package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.junit.jupiter.api.extension.ExtendWith;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransaction.Direction;
import com.delivery.accounting.domain.AccountingTransaction.Leg;
import com.delivery.accounting.domain.AccountingTransaction.Status;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CoreBankingSyncLog;
import com.delivery.accounting.domain.CoreBankingSyncLogRepository;

/**
 * The compensation branches — the highest-consequence logic in the platform.
 *
 * <p>Every case here is a way money can end up in the wrong place, and until now each was covered
 * only by a smoke suite that needs twenty-four healthy containers and ten minutes of cold start.
 * That is a fine integration proof and a poor way to check a branch, which is why the branch that
 * must NOT refund had to be found by a smoke test failing rather than by reading the code.
 *
 * <p>No Spring context: the saga is a plain object over two repositories and two collaborators.
 * Note that {@code afterCommit} runs its action immediately when no transaction synchronisation is
 * active, which is exactly the case here — so the deferred calls are directly verifiable.
 */
@ExtendWith(MockitoExtension.class)
class SettlementSagaTest {

    private static final String CUSTOMER_ACCOUNT = "ACC-CUSTOMER";
    private static final String MERCHANT_ACCOUNT = "ACC-MERCHANT";
    private static final String PLATFORM_ACCOUNT = "ACC-PLATFORM";

    @Mock
    private AccountingTransactionRepository transactions;
    @Mock
    private CoreBankingSyncLogRepository syncLog;
    @Mock
    private SettlementService settlements;
    @Mock
    private BankPostingPublisher postings;

    private SettlementSaga saga;
    private UUID orderId;

    @BeforeEach
    void setUp() {
        saga = new SettlementSaga(transactions, syncLog, settlements, postings);
        orderId = UUID.randomUUID();
    }

    // ------------------------------------------------------------------ fixtures

    private AccountingTransaction leg(Leg which, String account, String amount, Direction direction) {
        return new AccountingTransaction(
                orderId, which, account, new BigDecimal(amount), "USD", direction, "corr-1");
    }

    /** A settlement of 40.00 at 12.5%: debit 40.00, merchant 35.00, commission 5.00. */
    private List<AccountingTransaction> threeLegs() {
        return new ArrayList<>(List.of(
                leg(Leg.CUSTOMER_DEBIT, CUSTOMER_ACCOUNT, "40.00", Direction.DEBIT),
                leg(Leg.MERCHANT_CREDIT, MERCHANT_ACCOUNT, "35.00", Direction.CREDIT),
                leg(Leg.PLATFORM_COMMISSION, PLATFORM_ACCOUNT, "5.00", Direction.CREDIT)));
    }

    /**
     * Loads a settlement into the repositories.
     *
     * <p>Lenient because this stubs every leg while a test exercises one — the alternative is each
     * test naming the leg it is about twice, once to stub and once to act on, which makes the
     * interesting line harder to find than the setup.
     */
    private void given(List<AccountingTransaction> legs) {
        org.mockito.Mockito.lenient()
                .when(transactions.findByOrderIdOrderByCreatedAt(orderId)).thenReturn(legs);
        for (AccountingTransaction t : legs) {
            org.mockito.Mockito.lenient()
                    .when(transactions.findById(t.getId())).thenReturn(Optional.of(t));
        }
    }

    private void succeed(AccountingTransaction t) {
        saga.onResult(t.getId(), true, false, "SIMULATOR", "bank-ref", null, "{}", "{}");
    }

    private void failPermanently(AccountingTransaction t, String reason) {
        saga.onResult(t.getId(), false, false, "SIMULATOR", null, reason, "{}", "{}");
    }

    private AccountingTransaction refundRaised() {
        ArgumentCaptor<AccountingTransaction> saved =
                ArgumentCaptor.forClass(AccountingTransaction.class);
        verify(transactions, org.mockito.Mockito.atLeastOnce()).save(saved.capture());
        return saved.getAllValues().stream()
                .filter(t -> t.getLeg() == Leg.CUSTOMER_REFUND)
                .findFirst()
                .orElse(null);
    }

    // ------------------------------------------------------------------ tests

    @Nested
    @DisplayName("the happy path advances one leg at a time")
    class HappyPath {

        @Test
        void a_posted_debit_releases_the_next_leg() {
            List<AccountingTransaction> legs = threeLegs();
            given(legs);

            succeed(legs.get(0));

            assertThat(legs.get(0).getStatus()).isEqualTo(Status.POSTED);
            // Sequenced, not fanned out. Firing both credits together allows a state where the
            // platform keeps commission on an order it then refunds.
            verify(settlements).releaseNextLeg(orderId);
        }

        @Test
        void the_last_posted_leg_does_not_ask_for_another() {
            List<AccountingTransaction> legs = threeLegs();
            legs.get(0).markPosted("a");
            legs.get(1).markPosted("b");
            given(legs);

            succeed(legs.get(2));

            verifyNoInteractions(postings);
            verify(settlements, never()).releaseNextLeg(any());
        }

        @Test
        void the_bank_reference_is_recorded_because_it_is_what_a_dispute_quotes() {
            List<AccountingTransaction> legs = threeLegs();
            given(legs);

            succeed(legs.get(0));

            assertThat(legs.get(0).getCoreBankingRef()).isEqualTo("bank-ref");
        }
    }

    @Nested
    @DisplayName("a refused debit pays nobody")
    class DebitRefused {

        /**
         * The bug a naive implementation ships: crediting a merchant for money that was never
         * collected. Nothing was taken from the customer, so nothing may be paid out.
         */
        @Test
        void every_pending_credit_is_abandoned() {
            List<AccountingTransaction> legs = threeLegs();
            given(legs);

            failPermanently(legs.get(0), "INSUFFICIENT_FUNDS");

            assertThat(legs.get(1).getStatus()).isEqualTo(Status.ABANDONED);
            assertThat(legs.get(2).getStatus()).isEqualTo(Status.ABANDONED);
        }

        @Test
        void and_no_refund_is_raised_because_nothing_was_taken() {
            List<AccountingTransaction> legs = threeLegs();
            given(legs);

            failPermanently(legs.get(0), "INSUFFICIENT_FUNDS");

            assertThat(refundRaised()).isNull();
            verifyNoInteractions(postings);
        }

        @Test
        void abandoned_rather_than_left_pending_so_they_leave_the_chase_this_view() {
            List<AccountingTransaction> legs = threeLegs();
            given(legs);

            failPermanently(legs.get(0), "ACCOUNT_FROZEN");

            // They are not stuck, they are cancelled — and the reconciliation view counts PENDING
            // as money at risk.
            assertThat(legs.get(1).getStatus()).isNotEqualTo(Status.PENDING);
            assertThat(legs.get(1).getFailureReason()).contains("ACCOUNT_FROZEN");
        }
    }

    @Nested
    @DisplayName("a refused merchant credit refunds the customer")
    class MerchantCreditRefused {

        private List<AccountingTransaction> settledDebit() {
            List<AccountingTransaction> legs = threeLegs();
            legs.get(0).markPosted("debit-ref");
            return legs;
        }

        @Test
        void a_refund_is_raised_for_what_was_actually_collected() {
            List<AccountingTransaction> legs = settledDebit();
            given(legs);

            failPermanently(legs.get(1), "ACCOUNT_FROZEN");

            AccountingTransaction refund = refundRaised();
            assertThat(refund).isNotNull();
            // The full debit, not the merchant's share: the customer paid 40.00 and gets 40.00.
            assertThat(refund.getAmount()).isEqualByComparingTo("40.00");
            assertThat(refund.getAccountRef()).isEqualTo(CUSTOMER_ACCOUNT);
            assertThat(refund.getDirection()).isEqualTo(Direction.CREDIT);
        }

        @Test
        void the_refund_is_actually_sent_to_the_bank() {
            List<AccountingTransaction> legs = settledDebit();
            given(legs);

            failPermanently(legs.get(1), "ACCOUNT_FROZEN");

            // A refund row nobody asks the bank for is money the platform still holds.
            verify(postings).request(any(AccountingTransaction.class));
        }

        @Test
        void the_debit_is_marked_compensated_not_left_looking_successful() {
            List<AccountingTransaction> legs = settledDebit();
            given(legs);

            failPermanently(legs.get(1), "ACCOUNT_FROZEN");

            assertThat(legs.get(0).getStatus()).isEqualTo(Status.COMPENSATED);
        }

        @Test
        void the_commission_is_abandoned_along_with_it() {
            List<AccountingTransaction> legs = settledDebit();
            given(legs);

            failPermanently(legs.get(1), "ACCOUNT_FROZEN");

            assertThat(legs.get(2).getStatus()).isEqualTo(Status.ABANDONED);
        }

        /**
         * Both credits can fail. One refund is enough; a second would return the money twice.
         */
        @Test
        void a_second_failure_does_not_raise_a_second_refund() {
            List<AccountingTransaction> legs = settledDebit();
            AccountingTransaction existingRefund =
                    leg(Leg.CUSTOMER_REFUND, CUSTOMER_ACCOUNT, "40.00", Direction.CREDIT);
            legs.add(existingRefund);
            given(legs);

            failPermanently(legs.get(2), "ACCOUNT_FROZEN");

            assertThat(legs.stream().filter(t -> t.getLeg() == Leg.CUSTOMER_REFUND)).hasSize(1);
            verifyNoInteractions(postings);
        }

        @Test
        void nothing_is_refunded_if_the_debit_never_posted() {
            // Defensive: sequencing should make this unreachable, but refunding money that was
            // never collected is worse than doing nothing.
            List<AccountingTransaction> legs = threeLegs();
            given(legs);

            failPermanently(legs.get(1), "ACCOUNT_FROZEN");

            assertThat(refundRaised()).isNull();
            verifyNoInteractions(postings);
        }
    }

    @Nested
    @DisplayName("a refused commission does NOT refund")
    class CommissionRefused {

        /**
         * The branch a smoke test had to find. Because the legs are sequenced, reaching here means
         * the customer was debited and the merchant was paid — the order is correct from both their
         * points of view and only the platform's own cut is missing. Refunding now would claw money
         * back from a merchant who has already been paid.
         */
        @Test
        void the_customer_is_not_refunded_because_the_merchant_was_already_paid() {
            List<AccountingTransaction> legs = threeLegs();
            legs.get(0).markPosted("debit-ref");
            legs.get(1).markPosted("merchant-ref");
            given(legs);

            failPermanently(legs.get(2), "ACCOUNT_FROZEN");

            assertThat(refundRaised()).isNull();
            verifyNoInteractions(postings);
        }

        @Test
        void the_merchant_credit_is_left_posted() {
            List<AccountingTransaction> legs = threeLegs();
            legs.get(0).markPosted("debit-ref");
            legs.get(1).markPosted("merchant-ref");
            given(legs);

            failPermanently(legs.get(2), "ACCOUNT_FROZEN");

            assertThat(legs.get(1).getStatus()).isEqualTo(Status.POSTED);
            assertThat(legs.get(0).getStatus()).isEqualTo(Status.POSTED);
        }

        @Test
        void it_is_left_failed_so_an_operator_can_re_post_it() {
            List<AccountingTransaction> legs = threeLegs();
            legs.get(0).markPosted("debit-ref");
            legs.get(1).markPosted("merchant-ref");
            given(legs);

            failPermanently(legs.get(2), "ACCOUNT_FROZEN");

            // FAILED, not ABANDONED: this is revenue the platform should still collect, and the
            // reconciliation view distinguishes the two.
            assertThat(legs.get(2).getStatus()).isEqualTo(Status.FAILED);
        }
    }

    @Nested
    @DisplayName("a retryable failure is not a failure")
    class Retryable {

        @Test
        void the_leg_stays_pending_while_the_connector_retries() {
            List<AccountingTransaction> legs = threeLegs();
            legs.get(0).markPosted("debit-ref");
            given(legs);

            saga.onResult(legs.get(1).getId(), false, true, "SIMULATOR", null, "timeout", "{}", "{}");

            // Treating a slow bank as a failed one would compensate a settlement that was about to
            // succeed.
            assertThat(legs.get(1).getStatus()).isEqualTo(Status.PENDING);
            assertThat(legs.get(1).getFailureReason()).isEqualTo("timeout");
        }

        @Test
        void and_nothing_is_compensated() {
            List<AccountingTransaction> legs = threeLegs();
            legs.get(0).markPosted("debit-ref");
            given(legs);

            saga.onResult(legs.get(1).getId(), false, true, "SIMULATOR", null, "timeout", "{}", "{}");

            assertThat(refundRaised()).isNull();
            verifyNoInteractions(postings);
            assertThat(legs.get(2).getStatus()).isEqualTo(Status.PENDING);
        }
    }

    @Nested
    @DisplayName("redelivery cannot re-trigger anything")
    class Idempotency {

        /** Bus delivery is at-least-once, and a re-run compensation would refund twice. */
        @Test
        void a_result_for_an_already_posted_leg_is_ignored() {
            List<AccountingTransaction> legs = threeLegs();
            legs.get(0).markPosted("debit-ref");
            given(legs);

            failPermanently(legs.get(0), "late failure");

            assertThat(legs.get(0).getStatus()).isEqualTo(Status.POSTED);
            assertThat(legs.get(1).getStatus()).isEqualTo(Status.PENDING);
        }

        @Test
        void a_result_for_an_abandoned_leg_is_ignored() {
            List<AccountingTransaction> legs = threeLegs();
            legs.get(1).markAbandoned("earlier unwind");
            given(legs);

            succeed(legs.get(1));

            assertThat(legs.get(1).getStatus()).isEqualTo(Status.ABANDONED);
            verify(settlements, never()).releaseNextLeg(any());
        }

        @Test
        void a_result_for_an_unknown_transaction_is_survivable() {
            UUID unknown = UUID.randomUUID();
            when(transactions.findById(unknown)).thenReturn(Optional.empty());

            saga.onResult(unknown, true, false, "SIMULATOR", "ref", null, "{}", "{}");

            // Should be impossible — the row is committed before the posting is published — so it
            // must not throw and take the listener down with it.
            verifyNoInteractions(syncLog);
            verifyNoInteractions(postings);
        }
    }

    @Nested
    @DisplayName("the sync log records the conversation, not just the good half")
    class SyncLogging {

        @Test
        void a_success_is_logged_as_posted() {
            List<AccountingTransaction> legs = threeLegs();
            given(legs);

            succeed(legs.get(0));

            assertThat(capturedOutcome()).isEqualTo(CoreBankingSyncLog.Outcome.POSTED);
        }

        @Test
        void a_permanent_failure_is_logged_as_rejected() {
            List<AccountingTransaction> legs = threeLegs();
            given(legs);

            failPermanently(legs.get(0), "ACCOUNT_FROZEN");

            assertThat(capturedOutcome()).isEqualTo(CoreBankingSyncLog.Outcome.REJECTED);
        }

        @Test
        void a_retryable_failure_is_logged_as_retryable() {
            List<AccountingTransaction> legs = threeLegs();
            given(legs);

            saga.onResult(legs.get(0).getId(), false, true, "SIMULATOR", null, "429", "{}", "{}");

            assertThat(capturedOutcome()).isEqualTo(CoreBankingSyncLog.Outcome.RETRYABLE);
        }

        /**
         * Written even for a leg whose result is then ignored as a redelivery — the fact that the
         * bank said something twice is itself worth having in a dispute.
         */
        @Test
        void a_redelivered_result_is_still_logged() {
            List<AccountingTransaction> legs = threeLegs();
            legs.get(0).markPosted("debit-ref");
            given(legs);

            succeed(legs.get(0));

            verify(syncLog).save(any(CoreBankingSyncLog.class));
        }

        @Test
        void the_payloads_are_kept_because_a_status_code_cannot_answer_what_did_we_send() {
            List<AccountingTransaction> legs = threeLegs();
            given(legs);

            saga.onResult(legs.get(0).getId(), false, false, "SIMULATOR", null, "rejected",
                    "{\"accountRef\":\"ACC-FROZEN\"}", "{\"status\":\"REJECTED\"}");

            ArgumentCaptor<CoreBankingSyncLog> saved =
                    ArgumentCaptor.forClass(CoreBankingSyncLog.class);
            verify(syncLog).save(saved.capture());
            assertThat(saved.getValue().getRequestPayload()).contains("ACC-FROZEN");
            assertThat(saved.getValue().getResponsePayload()).contains("REJECTED");
        }

        private CoreBankingSyncLog.Outcome capturedOutcome() {
            ArgumentCaptor<CoreBankingSyncLog> saved =
                    ArgumentCaptor.forClass(CoreBankingSyncLog.class);
            verify(syncLog).save(saved.capture());
            return saved.getValue().getOutcome();
        }
    }
}
