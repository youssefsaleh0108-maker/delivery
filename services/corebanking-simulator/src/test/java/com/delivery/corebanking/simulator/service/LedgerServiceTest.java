package com.delivery.corebanking.simulator.service;

import java.lang.reflect.Field;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;

import com.delivery.corebanking.simulator.domain.BankAccount;
import com.delivery.corebanking.simulator.domain.BankAccountRepository;
import com.delivery.corebanking.simulator.domain.BankPosting;
import com.delivery.corebanking.simulator.domain.BankPostingRepository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The simulator's ledger — the oracle the whole settlement saga is tested against.
 *
 * <p>This service exists to be wrong in the same ways a real bank is, and right in the one way that
 * matters most: a retried debit must return the original posting rather than move money a second
 * time. The saga's correctness is only as good as that guarantee, so it is checked here rather than
 * assumed.
 *
 * <p>The rejection codes are load-bearing too. The connector decides whether to retry from the
 * classification, so a frozen account (never going to work) and a bank outage (might) must not come
 * back looking alike.
 */
class LedgerServiceTest {

    private static final String CURRENCY = "USD";

    private BankAccountRepository accounts;
    private BankPostingRepository postings;
    private LedgerService ledger;

    @BeforeEach
    void setUp() {
        accounts = mock(BankAccountRepository.class);
        postings = mock(BankPostingRepository.class);
        ledger = new LedgerService(accounts, postings);

        when(postings.findByClientReference(anyString())).thenReturn(Optional.empty());
        when(postings.save(any(BankPosting.class))).thenAnswer(call -> call.getArgument(0));
    }

    /** The entity is seeded by migration, so a test builds one directly. */
    private BankAccount account(long balanceMinor, BankAccount.Status status, String currency) {
        try {
            var constructor = BankAccount.class.getDeclaredConstructor();
            constructor.setAccessible(true);
            BankAccount account = constructor.newInstance();
            set(account, "accountRef", "ACC-1");
            set(account, "holderName", "Test Holder");
            set(account, "balanceMinor", balanceMinor);
            set(account, "currency", currency);
            set(account, "status", status);
            when(accounts.findByIdForUpdate("ACC-1")).thenReturn(Optional.of(account));
            return account;
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException(e);
        }
    }

    private BankAccount activeAccountWith(long balanceMinor) {
        return account(balanceMinor, BankAccount.Status.ACTIVE, CURRENCY);
    }

    private static void set(Object target, String name, Object value)
            throws ReflectiveOperationException {
        Field field = BankAccount.class.getDeclaredField(name);
        field.setAccessible(true);
        field.set(target, value);
    }

    private LedgerService.Result debit(String reference, long amountMinor) {
        return ledger.post(reference, "ACC-1", BankPosting.Direction.DEBIT, amountMinor,
                CURRENCY, "test debit");
    }

    private LedgerService.Result credit(String reference, long amountMinor) {
        return ledger.post(reference, "ACC-1", BankPosting.Direction.CREDIT, amountMinor,
                CURRENCY, "test credit");
    }

    @Nested
    @DisplayName("moving money")
    class Posting {

        @Test
        void a_debit_reduces_the_balance_and_records_it() {
            BankAccount account = activeAccountWith(10_000);

            LedgerService.Result result = debit("ref-1", 2_500);

            assertThat(account.getBalanceMinor()).isEqualTo(7_500);
            assertThat(result.posting().getStatus()).isEqualTo(BankPosting.Status.POSTED);
            assertThat(result.replayed()).isFalse();
        }

        @Test
        void a_credit_increases_the_balance() {
            BankAccount account = activeAccountWith(10_000);

            credit("ref-1", 2_500);

            assertThat(account.getBalanceMinor()).isEqualTo(12_500);
        }

        /** The running balance on the posting is what makes a statement reconstructable. */
        @Test
        void the_posting_records_the_balance_it_left_behind() {
            activeAccountWith(10_000);

            assertThat(debit("ref-1", 2_500).posting().getBalanceAfterMinor()).isEqualTo(7_500);
        }

        /** A debit that empties an account exactly is legitimate, not an overdraft. */
        @Test
        void a_debit_of_the_entire_balance_is_allowed() {
            BankAccount account = activeAccountWith(2_500);

            assertThat(debit("ref-1", 2_500).posting().getStatus())
                    .isEqualTo(BankPosting.Status.POSTED);
            assertThat(account.getBalanceMinor()).isZero();
        }

        /** A credit does not need funds, so a zero-balance account can still be paid into. */
        @Test
        void an_empty_account_can_still_be_credited() {
            BankAccount account = activeAccountWith(0);

            assertThat(credit("ref-1", 5_000).posting().getStatus())
                    .isEqualTo(BankPosting.Status.POSTED);
            assertThat(account.getBalanceMinor()).isEqualTo(5_000);
        }
    }

    @Nested
    @DisplayName("idempotency")
    class Idempotency {

        /**
         * The single most important behaviour in this service. A connector that retries after a
         * timeout must not take the money twice, and this is the guarantee the whole settlement
         * saga's correctness rests on.
         */
        @Test
        void a_retried_posting_returns_the_original_without_moving_money_again() {
            BankAccount account = activeAccountWith(10_000);
            BankPosting first = debit("ref-1", 2_500).posting();
            when(postings.findByClientReference("ref-1")).thenReturn(Optional.of(first));

            LedgerService.Result replay = debit("ref-1", 2_500);

            assertThat(replay.replayed()).isTrue();
            assertThat(replay.posting()).isSameAs(first);
            assertThat(account.getBalanceMinor()).isEqualTo(7_500);
        }

        /** Idempotency is checked before anything else, including whether the account exists. */
        @Test
        void a_replay_is_answered_without_touching_the_account_at_all() {
            BankPosting existing = BankPosting.posted("ref-1", "ACC-1",
                    BankPosting.Direction.DEBIT, 2_500, CURRENCY, "n", 7_500);
            when(postings.findByClientReference("ref-1")).thenReturn(Optional.of(existing));

            assertThat(debit("ref-1", 2_500).replayed()).isTrue();

            verify(accounts, never()).findByIdForUpdate(anyString());
        }

        /**
         * A rejection is an answer too. Replaying the same reference must return that same answer
         * rather than re-deciding it — the saga issues a new transaction id when it wants a retry.
         */
        @Test
        void replaying_a_rejected_reference_returns_the_rejection() {
            BankPosting rejection = BankPosting.rejected("ref-1", "ACC-1",
                    BankPosting.Direction.DEBIT, 2_500, CURRENCY, "n", "INSUFFICIENT_FUNDS: no");
            when(postings.findByClientReference("ref-1")).thenReturn(Optional.of(rejection));
            BankAccount account = activeAccountWith(1_000_000);

            LedgerService.Result replay = debit("ref-1", 2_500);

            assertThat(replay.posting().getStatus()).isEqualTo(BankPosting.Status.REJECTED);
            assertThat(account.getBalanceMinor()).isEqualTo(1_000_000);
        }

        /** Different references are different postings, even for an identical debit. */
        @Test
        void two_distinct_references_both_move_money() {
            BankAccount account = activeAccountWith(10_000);

            debit("ref-1", 2_500);
            debit("ref-2", 2_500);

            assertThat(account.getBalanceMinor()).isEqualTo(5_000);
        }

        /**
         * The check-then-insert window is real, and the unique constraint is what actually closes
         * it. Losing this exception would turn a concurrent retry into a double posting.
         */
        @Test
        void a_concurrent_replay_is_surfaced_rather_than_becoming_a_second_posting() {
            activeAccountWith(10_000);
            when(postings.save(any(BankPosting.class)))
                    .thenThrow(new DataIntegrityViolationException("duplicate key"));

            assertThatThrownBy(() -> debit("ref-1", 2_500))
                    .isInstanceOf(LedgerService.ConcurrentReplayException.class)
                    .hasMessageContaining("ref-1");
        }
    }

    @Nested
    @DisplayName("refusals")
    class Refusals {

        /** Retrying will never help, so the code has to say so rather than look transient. */
        @Test
        void an_unknown_account_is_refused() {
            when(accounts.findByIdForUpdate("ACC-1")).thenReturn(Optional.empty());

            LedgerService.Result result = debit("ref-1", 2_500);

            assertThat(result.posting().getStatus()).isEqualTo(BankPosting.Status.REJECTED);
            assertThat(result.posting().getRejectionReason()).contains("UNKNOWN_ACCOUNT");
        }

        /**
         * The one refusal that is not persisted: bank_postings has a foreign key to bank_accounts,
         * so a row against an account that does not exist cannot be written. Keeping the key is
         * right, so this case answers without saving.
         */
        @Test
        void an_unknown_account_refusal_is_not_written_to_the_ledger() {
            when(accounts.findByIdForUpdate("ACC-1")).thenReturn(Optional.empty());

            debit("ref-1", 2_500);

            verify(postings, never()).save(any(BankPosting.class));
        }

        @Test
        void a_frozen_account_is_refused_and_the_balance_untouched() {
            BankAccount frozen = account(10_000, BankAccount.Status.FROZEN, CURRENCY);

            LedgerService.Result result = debit("ref-1", 2_500);

            assertThat(result.posting().getRejectionReason()).contains("ACCOUNT_FROZEN");
            assertThat(frozen.getBalanceMinor()).isEqualTo(10_000);
        }

        @Test
        void a_closed_account_is_refused() {
            account(10_000, BankAccount.Status.CLOSED, CURRENCY);

            assertThat(debit("ref-1", 2_500).posting().getRejectionReason())
                    .contains("ACCOUNT_CLOSED");
        }

        /** A frozen account cannot be paid into either — the refusal is not debit-only. */
        @Test
        void a_frozen_account_cannot_be_credited_either() {
            BankAccount frozen = account(10_000, BankAccount.Status.FROZEN, CURRENCY);

            assertThat(credit("ref-1", 2_500).posting().getStatus())
                    .isEqualTo(BankPosting.Status.REJECTED);
            assertThat(frozen.getBalanceMinor()).isEqualTo(10_000);
        }

        @Test
        void a_debit_beyond_the_balance_is_refused_rather_than_overdrawn() {
            BankAccount account = activeAccountWith(2_499);

            LedgerService.Result result = debit("ref-1", 2_500);

            assertThat(result.posting().getRejectionReason()).contains("INSUFFICIENT_FUNDS");
            assertThat(account.getBalanceMinor()).isEqualTo(2_499);
        }

        /** Posting into an account held in another currency would silently mis-state the balance. */
        @Test
        void a_currency_mismatch_is_refused() {
            BankAccount account = account(10_000, BankAccount.Status.ACTIVE, "EUR");

            LedgerService.Result result = debit("ref-1", 2_500);

            assertThat(result.posting().getRejectionReason()).contains("CURRENCY_MISMATCH");
            assertThat(account.getBalanceMinor()).isEqualTo(10_000);
        }

        @Test
        void a_zero_or_negative_amount_is_refused() {
            activeAccountWith(10_000);

            assertThat(debit("ref-1", 0).posting().getRejectionReason())
                    .contains("AMOUNT_NOT_POSITIVE");
            assertThat(debit("ref-2", -500).posting().getRejectionReason())
                    .contains("AMOUNT_NOT_POSITIVE");
        }

        /** A negative amount must be caught before the account is even looked at. */
        @Test
        void an_invalid_amount_is_refused_without_consulting_the_account() {
            debit("ref-1", -500);

            verify(accounts, never()).findByIdForUpdate(anyString());
        }

        /**
         * "We sent it, they say they never got it" is unanswerable if a refused posting leaves no
         * trace, so every refusal that can be written is written.
         */
        @Test
        void refusals_are_recorded_rather_than_discarded() {
            activeAccountWith(100);

            debit("ref-1", 2_500);

            verify(postings).save(any(BankPosting.class));
        }

        /** Each refusal carries its own code, since the connector's retry decision is driven off it. */
        @Test
        void each_refusal_carries_a_distinguishable_code() {
            activeAccountWith(100);
            String insufficient = debit("ref-1", 2_500).posting().getRejectionReason();

            account(10_000, BankAccount.Status.FROZEN, CURRENCY);
            String frozen = debit("ref-2", 2_500).posting().getRejectionReason();

            assertThat(insufficient).isNotEqualTo(frozen);
        }
    }

    @Nested
    @DisplayName("locking")
    class Locking {

        /**
         * Two credits to the platform account arriving together is the normal case here. Reading
         * the account without the lock would let one update overwrite the other and lose money
         * silently — the one bug a bank simulator cannot have if it is to be trusted as an oracle.
         */
        @Test
        void the_account_row_is_locked_for_the_duration_of_a_posting() {
            activeAccountWith(10_000);

            debit("ref-1", 2_500);

            verify(accounts).findByIdForUpdate("ACC-1");
            verify(accounts, never()).findById(anyString());
        }
    }
}
