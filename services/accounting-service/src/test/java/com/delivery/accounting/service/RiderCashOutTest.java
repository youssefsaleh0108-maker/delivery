package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.RiderCashOut;
import com.delivery.accounting.domain.RiderCashOutRepository;
import com.delivery.accounting.domain.RiderLedgerEntry;
import com.delivery.accounting.domain.RiderLedgerEntry.EntryType;
import com.delivery.accounting.domain.RiderLedgerRepository;
import com.delivery.accounting.payout.ManualPayoutProvider;
import com.delivery.accounting.payout.RiderPayoutProviders;

/**
 * Taking money out.
 *
 * <p>Two properties, and both of them are about money leaving. <strong>A rider cannot take out more
 * than they have</strong>, including when they are still carrying the platform's cash. And
 * <strong>two simultaneous taps of the button settle to one payout</strong> — the balance check is
 * a read followed by a write, and the window between them is exactly wide enough to pay somebody
 * twice.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("taking money out")
class RiderCashOutTest {

    private static final String RIDER = "rider-1";

    @Mock
    private RiderLedgerRepository ledger;
    @Mock
    private CashFloatRepository floatEntries;

    /**
     * A cash-out repository that behaves like the real table's unique partial index.
     *
     * <p>Hand-written rather than mocked, because the property under test IS the constraint: a
     * Mockito stub would answer whatever it was told and prove nothing about two threads. This
     * accepts the first {@code REQUESTED} row for a rider and refuses every later one with the
     * exception Postgres raises, which is the behaviour of
     * {@code uq_cash_out_one_open ON rider_cash_out (rider_ref) WHERE status = 'REQUESTED'}.
     *
     * <p>What this cannot prove is that the index exists and is spelled correctly — only a database
     * can, and {@code SettlementHealthQueryTest} is the pattern for that when one is available.
     * What it does prove is the half that lives in this codebase: that the service serialises on
     * the insert, writes no hold when it loses, and surfaces the loss as a refusal rather than
     * swallowing it.
     */
    private static final class FakeCashOuts implements java.lang.reflect.InvocationHandler {

        private final Map<String, RiderCashOut> open = new ConcurrentHashMap<>();
        private final Map<UUID, RiderCashOut> all = new ConcurrentHashMap<>();
        private final CountDownLatch bothHaveReadTheBalance;

        FakeCashOuts(CountDownLatch bothHaveReadTheBalance) {
            this.bothHaveReadTheBalance = bothHaveReadTheBalance;
        }

        @Override
        public Object invoke(Object proxy, java.lang.reflect.Method method, Object[] args) {
            switch (method.getName()) {
                case "saveAndFlush", "save" -> {
                    RiderCashOut request = (RiderCashOut) args[0];
                    if (bothHaveReadTheBalance != null) {
                        // Hold every writer until both have passed the balance check, so the race
                        // this test is about is guaranteed to happen rather than hoped for.
                        bothHaveReadTheBalance.countDown();
                        try {
                            bothHaveReadTheBalance.await(5, TimeUnit.SECONDS);
                        } catch (InterruptedException e) {
                            Thread.currentThread().interrupt();
                        }
                    }
                    if (request.isOpen()
                            && open.putIfAbsent(request.getRiderRef(), request) != null) {
                        throw new org.springframework.dao.DataIntegrityViolationException(
                                "uq_cash_out_one_open");
                    }
                    all.put(request.getId(), request);
                    return request;
                }
                case "findById" -> {
                    return Optional.ofNullable(all.get((UUID) args[0]));
                }
                case "findFirstByRiderRefAndStatus" -> {
                    return Optional.ofNullable(open.get((String) args[0]));
                }
                case "equals" -> {
                    return proxy == args[0];
                }
                case "hashCode" -> {
                    return System.identityHashCode(proxy);
                }
                case "toString" -> {
                    return "FakeCashOuts";
                }
                default -> {
                    return null;
                }
            }
        }

        static RiderCashOutRepository proxying(FakeCashOuts handler) {
            return (RiderCashOutRepository) java.lang.reflect.Proxy.newProxyInstance(
                    RiderCashOutRepository.class.getClassLoader(),
                    new Class<?>[]{RiderCashOutRepository.class}, handler);
        }
    }

    private RiderEarningsService serviceWith(RiderCashOutRepository cashOuts) {
        return new RiderEarningsService(ledger, cashOuts, floatEntries,
                new RiderPayoutProviders(List.of(new ManualPayoutProvider()), "MANUAL"),
                new BigDecimal("5.00"), new BigDecimal("100.00"), true, "UTC", "USD");
    }

    private void hasEarned(String balance) {
        when(ledger.balanceOf(RIDER)).thenReturn(new BigDecimal(balance));
    }

    private void isCarrying(String cash) {
        when(floatEntries.outstandingTotalFor(RIDER)).thenReturn(new BigDecimal(cash));
    }

    @Nested
    @DisplayName("what a rider is allowed to ask for")
    class Limits {

        @Mock
        private RiderCashOutRepository cashOuts;

        private RiderEarningsService service;

        @BeforeEach
        void setUp() {
            service = serviceWith(cashOuts);
        }

        @Test
        void a_request_within_the_balance_holds_the_money_immediately() {
            // The hold is written in the same transaction as the request. If it were not, a slow
            // payout would leave the money spendable and the platform could owe it twice.
            hasEarned("40.00");
            isCarrying("0.00");
            when(cashOuts.saveAndFlush(any(RiderCashOut.class))).thenAnswer(i -> i.getArgument(0));

            RiderCashOut request = service.requestCashOut(RIDER, new BigDecimal("25.00"), "wallet");

            assertThat(request.getAmount()).isEqualByComparingTo("25.00");
            assertThat(request.getStatus()).isEqualTo(RiderCashOut.Status.REQUESTED);

            ArgumentCaptor<RiderLedgerEntry> hold =
                    ArgumentCaptor.forClass(RiderLedgerEntry.class);
            verify(ledger).save(hold.capture());
            assertThat(hold.getValue().getEntryType()).isEqualTo(EntryType.CASHOUT_HELD);
            // Negative, so the balance falls the moment the request is made.
            assertThat(hold.getValue().getAmount()).isEqualByComparingTo("-25.00");
        }

        @Test
        void a_request_for_more_than_the_balance_is_refused_and_holds_nothing() {
            hasEarned("40.00");
            isCarrying("0.00");

            assertThatThrownBy(() ->
                    service.requestCashOut(RIDER, new BigDecimal("40.01"), "wallet"))
                    .isInstanceOf(IllegalArgumentException.class);

            verify(ledger, never()).save(any());
            verify(cashOuts, never()).saveAndFlush(any());
        }

        @Test
        void cash_the_rider_is_still_carrying_is_netted_off_first() {
            // The expensive case. On a cash order the rider takes the whole total at the door and
            // owes it until they bank it, while the platform separately owes them their share of
            // the fee. Paying the second out while the first is outstanding hands money to somebody
            // already holding more of the platform's.
            hasEarned("40.00");
            isCarrying("35.00");

            assertThat(service.availableFor(RIDER)).isEqualByComparingTo("5.00");

            assertThatThrownBy(() ->
                    service.requestCashOut(RIDER, new BigDecimal("20.00"), "wallet"))
                    .isInstanceOf(IllegalArgumentException.class);
        }

        @Test
        void a_rider_who_owes_the_platform_more_than_it_owes_them_sees_a_negative_figure() {
            // Shown rather than clamped to zero. A zero would read as having earned nothing, which
            // is a different and more alarming statement than owing money.
            hasEarned("10.00");
            isCarrying("35.00");

            assertThat(service.availableFor(RIDER)).isEqualByComparingTo("-25.00");
        }

        @Test
        void a_request_below_the_minimum_is_refused() {
            assertThatThrownBy(() ->
                    service.requestCashOut(RIDER, new BigDecimal("1.00"), "wallet"))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("smallest");
        }

        @Test
        void a_negative_request_cannot_be_used_to_credit_a_balance() {
            assertThatThrownBy(() ->
                    service.requestCashOut(RIDER, new BigDecimal("-50.00"), "wallet"))
                    .isInstanceOf(IllegalArgumentException.class);
        }
    }

    @Nested
    @DisplayName("two requests at once")
    class Concurrency {

        @Test
        void settle_to_exactly_one_payout() throws Exception {
            // Both threads read the same balance and both decide they can afford it — the
            // check-then-act, forced to happen by the latch rather than left to chance. What must
            // hold from there is that only one request exists and only one hold was written.
            hasEarned("40.00");
            isCarrying("0.00");

            CountDownLatch bothHaveRead = new CountDownLatch(2);
            FakeCashOuts handler = new FakeCashOuts(bothHaveRead);
            RiderEarningsService service = serviceWith(FakeCashOuts.proxying(handler));

            AtomicInteger accepted = new AtomicInteger();
            AtomicInteger refused = new AtomicInteger();

            ExecutorService pool = Executors.newFixedThreadPool(2);
            try {
                List<Future<?>> runs = List.of(
                        pool.submit(() -> attempt(service, accepted, refused)),
                        pool.submit(() -> attempt(service, accepted, refused)));
                for (Future<?> run : runs) {
                    run.get(10, TimeUnit.SECONDS);
                }
            } finally {
                pool.shutdownNow();
            }

            assertThat(accepted.get()).isEqualTo(1);
            assertThat(refused.get()).isEqualTo(1);
            // One hold, not two. The loser must not reduce a balance it never got to spend.
            verify(ledger, org.mockito.Mockito.times(1)).save(any(RiderLedgerEntry.class));
        }

        private void attempt(RiderEarningsService service, AtomicInteger accepted,
                             AtomicInteger refused) {
            try {
                service.requestCashOut(RIDER, new BigDecimal("40.00"), "wallet");
                accepted.incrementAndGet();
            } catch (IllegalStateException e) {
                // The loser: refused because a request is already open, which is exactly what the
                // unique partial index produces.
                refused.incrementAndGet();
            }
        }
    }

    @Nested
    @DisplayName("the state machine")
    class StateMachine {

        @Mock
        private RiderCashOutRepository cashOuts;

        private RiderEarningsService service;
        private RiderCashOut request;

        @BeforeEach
        void setUp() {
            service = serviceWith(cashOuts);
            request = new RiderCashOut(RIDER, new BigDecimal("25.00"), "USD", "wallet");
        }

        @Test
        void paying_records_the_provider_and_the_reference_it_gave_back() {
            when(cashOuts.findById(request.getId())).thenReturn(Optional.of(request));

            RiderCashOut paid = service.payCashOut(request.getId(), "ops-1", "BANK-REF-99");

            assertThat(paid.getStatus()).isEqualTo(RiderCashOut.Status.PAID);
            assertThat(paid.getPaymentRef()).isEqualTo("BANK-REF-99");
            // So nobody reading the row can mistake a hand-typed reference for an automated
            // transfer.
            assertThat(paid.getPaidVia()).isEqualTo(ManualPayoutProvider.NAME);
        }

        @Test
        void paying_does_not_take_the_money_out_of_the_balance_a_second_time() {
            // It already fell when the hold was written. The row here is for the history.
            when(cashOuts.findById(request.getId())).thenReturn(Optional.of(request));

            service.payCashOut(request.getId(), "ops-1", "BANK-REF-99");

            ArgumentCaptor<RiderLedgerEntry> captor =
                    ArgumentCaptor.forClass(RiderLedgerEntry.class);
            verify(ledger).save(captor.capture());
            assertThat(captor.getValue().getEntryType()).isEqualTo(EntryType.CASHOUT_PAID);
            assertThat(captor.getValue().getAmount()).isEqualByComparingTo("0.00");
        }

        @Test
        void a_provider_that_refuses_leaves_the_request_open_and_the_money_still_held() {
            // The correct state for something an operator will retry. Marking it paid and then
            // asking the provider would leave a rider recorded as paid when they were not.
            when(cashOuts.findById(request.getId())).thenReturn(Optional.of(request));

            assertThatThrownBy(() -> service.payCashOut(request.getId(), "ops-1", "  "))
                    .isInstanceOf(IllegalStateException.class);

            assertThat(request.getStatus()).isEqualTo(RiderCashOut.Status.REQUESTED);
            verify(ledger, never()).save(any());
        }

        @Test
        void a_request_cannot_be_paid_twice() {
            // The transition that costs real money when it fires twice.
            when(cashOuts.findById(request.getId())).thenReturn(Optional.of(request));
            service.payCashOut(request.getId(), "ops-1", "BANK-REF-99");

            assertThatThrownBy(() -> service.payCashOut(request.getId(), "ops-2", "BANK-REF-100"))
                    .isInstanceOf(IllegalStateException.class);
        }

        @Test
        void refusing_a_request_gives_the_held_money_back() {
            when(cashOuts.findById(request.getId())).thenReturn(Optional.of(request));

            RiderCashOut rejected = service.rejectCashOut(request.getId(), "ops-1", "no account");

            assertThat(rejected.getStatus()).isEqualTo(RiderCashOut.Status.REJECTED);
            ArgumentCaptor<RiderLedgerEntry> captor =
                    ArgumentCaptor.forClass(RiderLedgerEntry.class);
            verify(ledger).save(captor.capture());
            assertThat(captor.getValue().getEntryType()).isEqualTo(EntryType.CASHOUT_RELEASED);
            assertThat(captor.getValue().getAmount()).isEqualByComparingTo("25.00");
        }

        @Test
        void a_paid_request_cannot_then_be_refused() {
            when(cashOuts.findById(request.getId())).thenReturn(Optional.of(request));
            service.payCashOut(request.getId(), "ops-1", "BANK-REF-99");

            assertThatThrownBy(() -> service.rejectCashOut(request.getId(), "ops-2", "changed mind"))
                    .isInstanceOf(IllegalStateException.class);
        }
    }
}
