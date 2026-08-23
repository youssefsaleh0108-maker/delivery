package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
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
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransaction.Direction;
import com.delivery.accounting.domain.AccountingTransaction.Leg;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatRepository;

/**
 * The arithmetic that decides how much everyone gets, and the ordering that decides when.
 *
 * <p>The money property worth stating outright: <strong>the legs must sum to the total exactly</strong>.
 * The obvious implementation computes the merchant's share as its own percentage, and then a
 * rounding remainder goes unaccounted for on every order — a cent at a time, invisibly, forever.
 */
@ExtendWith(MockitoExtension.class)
class SettlementServiceTest {

    private static final String CUSTOMER = "ACC-CUSTOMER";
    private static final String MERCHANT = "ACC-MERCHANT";
    private static final String PLATFORM = "ACC-PLATFORM";

    @Mock
    private AccountingTransactionRepository transactions;
    @Mock
    private CashFloatRepository floatEntries;
    @Mock
    private BankPostingPublisher postings;

    private UUID orderId;

    /** A rider holding notes, for the cash cases. */
    private static final SettlementService.CashHolder RIDER_HOLDING =
            new SettlementService.CashHolder("rider-1", CashFloatEntry.HolderKind.RIDER);

    @BeforeEach
    void setUp() {
        orderId = UUID.randomUUID();
    }

    private SettlementService serviceAt(String commissionPercentage) {
        return new SettlementService(transactions, floatEntries, postings,
                new BigDecimal(commissionPercentage), new BigDecimal("10"), PLATFORM, "USD",
                // BANK explicitly: everything below asserts the bank path — legs opening PENDING,
                // the posting sequence, the compensation on a refusal. Under LEDGER_ONLY every leg
                // is terminal at birth and none of it would run.
                SettlementService.SettlementMode.BANK);
    }

    /** An order with no delivery fee: the whole total is goods, so the base equals the total. */
    private List<AccountingTransaction> settle(String commissionPercentage, String total) {
        return settle(commissionPercentage, total, total);
    }

    /**
     * Card unless a test says otherwise: these cases are about the arithmetic, and the split is the
     * same however the customer paid. The cash-specific behaviour has its own group.
     */
    private List<AccountingTransaction> settle(String commissionPercentage, String total,
                                               String merchantBase) {
        return serviceAt(commissionPercentage).settle(orderId, new BigDecimal(total),
                merchantBase == null ? null : new BigDecimal(merchantBase),
                CUSTOMER, MERCHANT, null, null, "corr-1");
    }

    private static BigDecimal amountOf(List<AccountingTransaction> legs, Leg which) {
        return legs.stream()
                .filter(t -> t.getLeg() == which)
                .map(AccountingTransaction::getAmount)
                .findFirst()
                .orElse(null);
    }

    @Nested
    @DisplayName("the delivery fee")
    class DeliveryFee {

        /**
         * The rule this whole change exists for. The fee pays for the delivery; it is not the
         * shop's revenue, so the shop must not be credited it and the platform must not take a
         * commission on it.
         */
        @Test
        void the_merchant_is_paid_on_goods_only() {
            // 40.00 of goods plus a 2.50 delivery fee.
            List<AccountingTransaction> legs = settle("12.5", "42.50", "40.00");

            assertThat(amountOf(legs, Leg.CUSTOMER_DEBIT)).isEqualByComparingTo("42.50");
            // 12.5% of 40.00, not of 42.50 — which would have been 5.31.
            assertThat(amountOf(legs, Leg.MERCHANT_CREDIT)).isEqualByComparingTo("35.00");
            // Commission 5.00 plus the 2.50 fee.
            assertThat(amountOf(legs, Leg.PLATFORM_COMMISSION)).isEqualByComparingTo("7.50");
        }

        @Test
        void the_legs_still_sum_to_the_total_exactly() {
            List<AccountingTransaction> legs = settle("12.5", "42.50", "40.00");

            BigDecimal credited = legs.stream()
                    .filter(t -> t.getLeg() != Leg.CUSTOMER_DEBIT)
                    .map(AccountingTransaction::getAmount)
                    .reduce(BigDecimal.ZERO, BigDecimal::add);

            assertThat(credited).isEqualByComparingTo(amountOf(legs, Leg.CUSTOMER_DEBIT));
        }

        /** A rounding remainder on the goods must land with the platform, never go unaccounted. */
        @Test
        void an_awkward_split_still_balances() {
            List<AccountingTransaction> legs = settle("12.5", "19.98", "19.99");

            BigDecimal credited = legs.stream()
                    .filter(t -> t.getLeg() != Leg.CUSTOMER_DEBIT)
                    .map(AccountingTransaction::getAmount)
                    .reduce(BigDecimal.ZERO, BigDecimal::add);
            assertThat(credited).isEqualByComparingTo("19.98");
        }

        /**
         * A free-delivery order behaves exactly as it did before the fee existed — worth pinning,
         * because it is the case that proves the change is additive.
         */
        @Test
        void a_zero_fee_settles_as_it_always_did() {
            assertThat(settle("12.5", "40.00", "40.00"))
                    .extracting(AccountingTransaction::getAmount)
                    .containsExactlyElementsOf(
                            settle("12.5", "40.00").stream()
                                    .map(AccountingTransaction::getAmount).toList());
        }

        /**
         * Events published before the breakdown existed carry no subtotal. Treating the whole
         * total as goods is what those orders actually were.
         */
        @Test
        void a_missing_base_falls_back_to_the_whole_total() {
            List<AccountingTransaction> legs = settle("12.5", "40.00", null);

            assertThat(amountOf(legs, Leg.MERCHANT_CREDIT)).isEqualByComparingTo("35.00");
            assertThat(amountOf(legs, Leg.PLATFORM_COMMISSION)).isEqualByComparingTo("5.00");
        }

        /** A base above the total would pay the merchant money the customer never handed over. */
        @Test
        void a_base_larger_than_the_total_is_clamped() {
            List<AccountingTransaction> legs = settle("12.5", "40.00", "99.00");

            assertThat(amountOf(legs, Leg.MERCHANT_CREDIT)).isEqualByComparingTo("35.00");
            assertThat(amountOf(legs, Leg.CUSTOMER_DEBIT)).isEqualByComparingTo("40.00");
        }

        /** An entirely-delivery order (nothing but a fee) credits the shop nothing, not a negative. */
        @Test
        void a_zero_goods_order_pays_the_merchant_nothing() {
            List<AccountingTransaction> legs = settle("12.5", "5.00", "0.00");

            assertThat(amountOf(legs, Leg.MERCHANT_CREDIT)).isEqualByComparingTo("0.00");
            assertThat(amountOf(legs, Leg.PLATFORM_COMMISSION)).isEqualByComparingTo("5.00");
        }
    }

    @Nested
    @DisplayName("the split")
    class Split {

        @Test
        void commission_is_the_configured_percentage() {
            List<AccountingTransaction> legs = settle("12.5", "40.00");

            assertThat(amountOf(legs, Leg.CUSTOMER_DEBIT)).isEqualByComparingTo("40.00");
            assertThat(amountOf(legs, Leg.PLATFORM_COMMISSION)).isEqualByComparingTo("5.00");
            assertThat(amountOf(legs, Leg.MERCHANT_CREDIT)).isEqualByComparingTo("35.00");
        }

        /**
         * The reason the merchant's share is derived by subtraction rather than computed from its
         * own percentage. 12.5% of 10.01 is 1.25125, which rounds to 1.25; 87.5% of 10.01 is
         * 8.75875, which rounds to 8.76. Computed independently those sum to 10.01 by luck, and at
         * other totals they do not.
         */
        @ParameterizedTest(name = "{0} splits exactly")
        @ValueSource(strings = {
            "0.01", "0.03", "10.01", "10.03", "33.33", "99.99", "0.07", "1234.56", "7.77"
        })
        void the_legs_always_sum_to_the_total(String total) {
            List<AccountingTransaction> legs = settle("12.5", total);

            BigDecimal credits = legs.stream()
                    .filter(t -> t.getDirection() == Direction.CREDIT)
                    .map(AccountingTransaction::getAmount)
                    .reduce(BigDecimal.ZERO, BigDecimal::add);

            assertThat(credits).isEqualByComparingTo(amountOf(legs, Leg.CUSTOMER_DEBIT));
        }

        @ParameterizedTest(name = "at {0}% the legs still sum exactly")
        @ValueSource(strings = {"0", "1", "7.5", "12.5", "33.333", "50", "100"})
        void at_any_commission_rate(String percentage) {
            List<AccountingTransaction> legs = settle(percentage, "19.99");

            BigDecimal credits = legs.stream()
                    .filter(t -> t.getDirection() == Direction.CREDIT)
                    .map(AccountingTransaction::getAmount)
                    .reduce(BigDecimal.ZERO, BigDecimal::add);

            assertThat(credits).isEqualByComparingTo("19.99");
        }

        @Test
        void a_total_with_more_than_two_decimals_is_rounded_before_anything_is_split() {
            // Splitting first and rounding after would put a fraction of a cent in a leg the bank
            // cannot post.
            List<AccountingTransaction> legs = settle("12.5", "40.005");

            assertThat(amountOf(legs, Leg.CUSTOMER_DEBIT)).isEqualByComparingTo("40.01");
            assertThat(amountOf(legs, Leg.CUSTOMER_DEBIT).scale()).isEqualTo(2);
        }
    }

    @Nested
    @DisplayName("degenerate amounts")
    class Degenerate {

        /** The bank rejects a zero-value posting, and that rejection would look like a real failure. */
        @Test
        void a_zero_commission_produces_no_commission_leg_at_all() {
            List<AccountingTransaction> legs = settle("0", "40.00");

            assertThat(legs).hasSize(2);
            assertThat(amountOf(legs, Leg.PLATFORM_COMMISSION)).isNull();
            assertThat(amountOf(legs, Leg.MERCHANT_CREDIT)).isEqualByComparingTo("40.00");
        }

        @Test
        void a_commission_that_rounds_to_zero_also_produces_no_leg() {
            // 1% of 0.01 is 0.0001, which is zero at two decimals.
            List<AccountingTransaction> legs = settle("1", "0.01");

            assertThat(amountOf(legs, Leg.PLATFORM_COMMISSION)).isNull();
            assertThat(amountOf(legs, Leg.MERCHANT_CREDIT)).isEqualByComparingTo("0.01");
        }

        @Test
        void a_zero_total_settles_nothing() {
            List<AccountingTransaction> legs = settle("12.5", "0.00");

            assertThat(legs).isEmpty();
            verify(transactions, never()).saveAll(any());
            verifyNoInteractions(postings);
        }

        @Test
        void a_negative_total_settles_nothing() {
            List<AccountingTransaction> legs = settle("12.5", "-5.00");

            assertThat(legs).isEmpty();
            verifyNoInteractions(postings);
        }
    }

    @Nested
    @DisplayName("settling twice")
    class Idempotency {

        /**
         * Bus delivery is at-least-once, so {@code order.delivered} can arrive twice. Settling
         * twice would really move money twice.
         */
        @Test
        void an_order_that_already_has_legs_is_not_settled_again() {
            when(transactions.existsByOrderId(orderId)).thenReturn(true);

            List<AccountingTransaction> legs = settle("12.5", "40.00");

            assertThat(legs).isEmpty();
            verify(transactions, never()).saveAll(any());
            verifyNoInteractions(postings);
        }
    }

    @Nested
    @DisplayName("sequencing")
    class Sequencing {

        /**
         * Only the debit is asked for up front. The credits wait until it has actually posted —
         * this is what stops the platform crediting a merchant for money it failed to collect.
         */
        @Test
        void only_the_debit_is_published_when_the_settlement_opens() {
            settle("12.5", "40.00");

            ArgumentCaptor<AccountingTransaction> published =
                    ArgumentCaptor.forClass(AccountingTransaction.class);
            verify(postings).request(published.capture());
            assertThat(published.getValue().getLeg()).isEqualTo(Leg.CUSTOMER_DEBIT);
        }

        @Test
        void the_merchant_credit_goes_next_once_the_debit_has_posted() {
            List<AccountingTransaction> legs = legsWithPostedDebit();
            when(transactions.findByOrderIdOrderByCreatedAt(orderId)).thenReturn(legs);

            serviceAt("12.5").releaseNextLeg(orderId);

            ArgumentCaptor<AccountingTransaction> published =
                    ArgumentCaptor.forClass(AccountingTransaction.class);
            verify(postings).request(published.capture());
            assertThat(published.getValue().getLeg()).isEqualTo(Leg.MERCHANT_CREDIT);
        }

        @Test
        void the_commission_goes_last_once_the_merchant_has_been_paid() {
            List<AccountingTransaction> legs = legsWithPostedDebit();
            legs.get(1).markPosted("merchant-ref");
            when(transactions.findByOrderIdOrderByCreatedAt(orderId)).thenReturn(legs);

            serviceAt("12.5").releaseNextLeg(orderId);

            ArgumentCaptor<AccountingTransaction> published =
                    ArgumentCaptor.forClass(AccountingTransaction.class);
            verify(postings).request(published.capture());
            assertThat(published.getValue().getLeg()).isEqualTo(Leg.PLATFORM_COMMISSION);
        }

        @Test
        void nothing_is_published_once_every_leg_has_posted() {
            List<AccountingTransaction> legs = legsWithPostedDebit();
            legs.get(1).markPosted("merchant-ref");
            legs.get(2).markPosted("commission-ref");
            when(transactions.findByOrderIdOrderByCreatedAt(orderId)).thenReturn(legs);

            serviceAt("12.5").releaseNextLeg(orderId);

            verifyNoInteractions(postings);
        }

        /** The saga is unwinding, not progressing — asking for the next leg would pay it out. */
        @Test
        void nothing_is_published_when_an_earlier_leg_has_failed() {
            List<AccountingTransaction> legs = legsWithPostedDebit();
            legs.get(1).markFailed("ACCOUNT_FROZEN");
            when(transactions.findByOrderIdOrderByCreatedAt(orderId)).thenReturn(legs);

            serviceAt("12.5").releaseNextLeg(orderId);

            verifyNoInteractions(postings);
        }

        @Test
        void nothing_is_published_when_an_earlier_leg_was_abandoned() {
            List<AccountingTransaction> legs = legsWithPostedDebit();
            legs.get(1).markAbandoned("unwound");
            when(transactions.findByOrderIdOrderByCreatedAt(orderId)).thenReturn(legs);

            serviceAt("12.5").releaseNextLeg(orderId);

            verifyNoInteractions(postings);
        }

        /** A zero-commission order has no third leg; the sequence must end rather than stall. */
        @Test
        void a_settlement_with_no_commission_leg_completes_after_the_merchant_credit() {
            List<AccountingTransaction> legs = new ArrayList<>(List.of(
                    transaction(Leg.CUSTOMER_DEBIT, CUSTOMER, "40.00", Direction.DEBIT),
                    transaction(Leg.MERCHANT_CREDIT, MERCHANT, "40.00", Direction.CREDIT)));
            legs.get(0).markPosted("debit-ref");
            legs.get(1).markPosted("merchant-ref");
            when(transactions.findByOrderIdOrderByCreatedAt(orderId)).thenReturn(legs);

            serviceAt("0").releaseNextLeg(orderId);

            verifyNoInteractions(postings);
        }

        private AccountingTransaction transaction(Leg which, String account, String amount,
                                                  Direction direction) {
            return new AccountingTransaction(
                    orderId, which, account, new BigDecimal(amount), "USD", direction, "corr-1");
        }

        private List<AccountingTransaction> legsWithPostedDebit() {
            List<AccountingTransaction> legs = new ArrayList<>(List.of(
                    transaction(Leg.CUSTOMER_DEBIT, CUSTOMER, "40.00", Direction.DEBIT),
                    transaction(Leg.MERCHANT_CREDIT, MERCHANT, "35.00", Direction.CREDIT),
                    transaction(Leg.PLATFORM_COMMISSION, PLATFORM, "5.00", Direction.CREDIT)));
            legs.get(0).markPosted("debit-ref");
            return legs;
        }
    }

    @Nested
    @DisplayName("what ends up on the row")
    class RowContents {

        @Test
        void the_correlation_id_is_carried_onto_every_leg() {
            List<AccountingTransaction> legs = settle("12.5", "40.00");

            // This is what makes one customer action followable across all three schemas it
            // touches (Section 10).
            assertThat(legs).allMatch(t -> "corr-1".equals(t.getCorrelationId()));
        }

        @Test
        void every_leg_belongs_to_the_same_order() {
            List<AccountingTransaction> legs = settle("12.5", "40.00");

            assertThat(legs).allMatch(t -> orderId.equals(t.getOrderId()));
        }

        @Test
        void the_money_goes_to_the_accounts_it_was_told_to() {
            List<AccountingTransaction> legs = settle("12.5", "40.00");

            assertThat(legs).filteredOn(t -> t.getLeg() == Leg.CUSTOMER_DEBIT)
                    .allMatch(t -> CUSTOMER.equals(t.getAccountRef()));
            assertThat(legs).filteredOn(t -> t.getLeg() == Leg.MERCHANT_CREDIT)
                    .allMatch(t -> MERCHANT.equals(t.getAccountRef()));
            assertThat(legs).filteredOn(t -> t.getLeg() == Leg.PLATFORM_COMMISSION)
                    .allMatch(t -> PLATFORM.equals(t.getAccountRef()));
        }

        @Test
        void everything_starts_pending() {
            List<AccountingTransaction> legs = settle("12.5", "40.00");

            assertThat(legs).allMatch(
                    t -> t.getStatus() == AccountingTransaction.Status.PENDING);
        }

        @Test
        void each_leg_gets_its_own_id_because_it_is_the_bank_idempotency_key() {
            List<AccountingTransaction> legs = settle("12.5", "40.00");

            assertThat(legs.stream().map(AccountingTransaction::getId).distinct())
                    .hasSize(legs.size());
        }
    }

    @Nested
    @DisplayName("a carrier that is not the platform")
    class Carrier {

        private static final String SWIFT = "ACC-SWIFT";

        private List<AccountingTransaction> carriedBy(String carrierAccount, String total,
                                                      String goods) {
            return serviceAt("12.5").settle(orderId, new BigDecimal(total), new BigDecimal(goods),
                    CUSTOMER, MERCHANT, carrierAccount, null, "corr-1");
        }

        @Test
        void the_delivery_fee_goes_to_whoever_delivered_it() {
            // 40.00 of goods plus a 2.50 fee, carried by a company. The fee is what delivery cost,
            // not platform revenue — the platform only ever earned its take rate on it.
            List<AccountingTransaction> legs = carriedBy(SWIFT, "42.50", "40.00");

            assertThat(amountOf(legs, Leg.MERCHANT_CREDIT)).isEqualByComparingTo("35.00");
            // 2.50 less 10% = 2.25 to the carrier.
            assertThat(amountOf(legs, Leg.PROVIDER_CREDIT)).isEqualByComparingTo("2.25");
            // 5.00 goods commission plus 0.25 delivery take rate.
            assertThat(amountOf(legs, Leg.PLATFORM_COMMISSION)).isEqualByComparingTo("5.25");
        }

        @Test
        void the_legs_still_sum_to_the_total_exactly() {
            List<AccountingTransaction> legs = carriedBy(SWIFT, "42.50", "40.00");

            BigDecimal credited = legs.stream()
                    .filter(t -> t.getDirection() == Direction.CREDIT)
                    .map(AccountingTransaction::getAmount)
                    .reduce(BigDecimal.ZERO, BigDecimal::add);
            assertThat(credited).isEqualByComparingTo(amountOf(legs, Leg.CUSTOMER_DEBIT));
        }

        /**
         * The property that makes this change safe to ship: an order the platform's own riders
         * carried settles byte for byte as it did before carriers could be anybody else.
         */
        @Test
        void the_in_house_fleet_changes_nothing() {
            List<AccountingTransaction> inHouse = carriedBy(null, "42.50", "40.00");

            assertThat(amountOf(inHouse, Leg.PROVIDER_CREDIT)).isNull();
            assertThat(amountOf(inHouse, Leg.MERCHANT_CREDIT)).isEqualByComparingTo("35.00");
            // The whole fee stays with the platform, as it always did.
            assertThat(amountOf(inHouse, Leg.PLATFORM_COMMISSION)).isEqualByComparingTo("7.50");
        }

        @Test
        void a_free_delivery_pays_the_carrier_nothing_rather_than_a_zero_posting() {
            // The bank rejects a zero posting, and that rejection would read as a real failure.
            List<AccountingTransaction> legs = carriedBy(SWIFT, "40.00", "40.00");

            assertThat(amountOf(legs, Leg.PROVIDER_CREDIT)).isNull();
            assertThat(amountOf(legs, Leg.PLATFORM_COMMISSION)).isEqualByComparingTo("5.00");
        }

        @Test
        void the_merchant_is_unaffected_by_who_carried_it() {
            // A shop's payout must not depend on which carrier the platform happened to pick.
            assertThat(amountOf(carriedBy(SWIFT, "42.50", "40.00"), Leg.MERCHANT_CREDIT))
                    .isEqualByComparingTo(
                            amountOf(carriedBy(null, "42.50", "40.00"), Leg.MERCHANT_CREDIT));
        }

        @ParameterizedTest
        @ValueSource(strings = {"0.01", "1.00", "3.33", "7.77", "19.99"})
        void whatever_the_fee_the_legs_balance(String fee) {
            BigDecimal goods = new BigDecimal("29.99");
            BigDecimal total = goods.add(new BigDecimal(fee));

            List<AccountingTransaction> legs = serviceAt("12.5").settle(orderId, total, goods,
                    CUSTOMER, MERCHANT, SWIFT, null, "corr-1");

            BigDecimal credited = legs.stream()
                    .filter(t -> t.getDirection() == Direction.CREDIT)
                    .map(AccountingTransaction::getAmount)
                    .reduce(BigDecimal.ZERO, BigDecimal::add);
            assertThat(credited).isEqualByComparingTo(amountOf(legs, Leg.CUSTOMER_DEBIT));
        }

        @Test
        void a_cash_order_pays_the_carrier_the_same_way() {
            List<AccountingTransaction> legs = serviceAt("12.5").settle(orderId,
                    new BigDecimal("42.50"), new BigDecimal("40.00"),
                    CUSTOMER, MERCHANT, SWIFT, RIDER_HOLDING, "corr-1");

            assertThat(amountOf(legs, Leg.CASH_COLLECTED)).isEqualByComparingTo("42.50");
            assertThat(amountOf(legs, Leg.PROVIDER_CREDIT)).isEqualByComparingTo("2.25");
        }
    }

    @Nested
    @DisplayName("cash, which no bank ever sees")
    class Cash {

        private List<AccountingTransaction> settleCash(String total, String goods) {
            return serviceAt("12.5").settle(orderId, new BigDecimal(total), new BigDecimal(goods),
                    CUSTOMER, MERCHANT, null, RIDER_HOLDING, "corr-1");
        }

        @Test
        void the_customers_bank_account_is_not_touched() {
            // The heart of it. The customer handed over notes; claiming their account was debited
            // is a statement about a bank that never saw this order.
            List<AccountingTransaction> legs = settleCash("42.50", "40.00");

            assertThat(amountOf(legs, Leg.CUSTOMER_DEBIT)).isNull();
            assertThat(amountOf(legs, Leg.CASH_COLLECTED)).isEqualByComparingTo("42.50");
        }

        @Test
        void the_collection_is_recorded_against_whoever_took_the_money() {
            List<AccountingTransaction> legs = settleCash("42.50", "40.00");

            AccountingTransaction collection = legs.stream()
                    .filter(t -> t.getLeg() == Leg.CASH_COLLECTED).findFirst().orElseThrow();
            assertThat(collection.getAccountRef()).isEqualTo("rider-1");
        }

        @Test
        void it_is_never_sent_to_the_bank() {
            // The previous attempt sent it and every posting was refused for want of funds, taking
            // the merchant leg down with it. Nothing about a cash collection goes to the bank.
            List<AccountingTransaction> legs = settleCash("42.50", "40.00");

            AccountingTransaction collection = legs.stream()
                    .filter(t -> t.getLeg() == Leg.CASH_COLLECTED).findFirst().orElseThrow();
            assertThat(collection.isPostingRequired()).isFalse();
            assertThat(collection.getStatus())
                    .isEqualTo(AccountingTransaction.Status.SETTLED_IN_CASH);
        }

        @Test
        void it_does_not_stall_the_legs_behind_it() {
            // An obligation is terminal at birth. If it were left PENDING the merchant would never
            // be paid, because the sequence waits for each leg before releasing the next.
            List<AccountingTransaction> legs = settleCash("42.50", "40.00");

            assertThat(legs.get(0).isTerminal()).isTrue();
            assertThat(legs.get(0).isSettled()).isTrue();
        }

        @Test
        void a_float_entry_records_who_owes_the_platform() {
            settleCash("42.50", "40.00");

            ArgumentCaptor<CashFloatEntry> saved = ArgumentCaptor.forClass(CashFloatEntry.class);
            verify(floatEntries).save(saved.capture());
            assertThat(saved.getValue().getHolderRef()).isEqualTo("rider-1");
            assertThat(saved.getValue().getAmount()).isEqualByComparingTo("42.50");
            assertThat(saved.getValue().isOutstanding()).isTrue();
        }

        @Test
        void the_same_order_arriving_twice_does_not_book_the_debt_twice() {
            when(floatEntries.existsByOrderIdAndEntryKind(orderId, CashFloatEntry.Kind.COLLECTED))
                    .thenReturn(true);

            settleCash("42.50", "40.00");

            verify(floatEntries, never()).save(any());
        }

        @Test
        void the_merchant_and_platform_are_paid_exactly_as_on_a_card_order() {
            // Who holds the notes changes nothing about who is owed what. If this ever diverged,
            // a shop's payout would depend on how its customer happened to pay.
            List<AccountingTransaction> cash = settleCash("42.50", "40.00");
            List<AccountingTransaction> card = settle("12.5", "42.50", "40.00");

            assertThat(amountOf(cash, Leg.MERCHANT_CREDIT))
                    .isEqualByComparingTo(amountOf(card, Leg.MERCHANT_CREDIT));
            assertThat(amountOf(cash, Leg.PLATFORM_COMMISSION))
                    .isEqualByComparingTo(amountOf(card, Leg.PLATFORM_COMMISSION));
        }

        @Test
        void the_legs_still_sum_to_what_the_customer_handed_over() {
            List<AccountingTransaction> legs = settleCash("42.50", "40.00");

            BigDecimal credited = legs.stream()
                    .filter(t -> t.getDirection() == Direction.CREDIT)
                    .map(AccountingTransaction::getAmount)
                    .reduce(BigDecimal.ZERO, BigDecimal::add);
            assertThat(credited).isEqualByComparingTo(amountOf(legs, Leg.CASH_COLLECTED));
        }

        @Test
        void a_cash_errand_records_the_float_too() {
            serviceAt("12.5").settleErrand(orderId, new BigDecimal("25.90"),
                    new BigDecimal("22.40"), CUSTOMER, "ACC-RIDER", RIDER_HOLDING, "corr-1");

            verify(floatEntries).save(any(CashFloatEntry.class));
        }
    }

    @Nested
    @DisplayName("an errand, where there is no merchant")
    class Errand {

        private static final String RIDER = "ACC-RIDER";

        private List<AccountingTransaction> settleErrand(String commissionPercentage,
                                                         String total, String goods) {
            return serviceAt(commissionPercentage).settleErrand(orderId, new BigDecimal(total),
                    new BigDecimal(goods), CUSTOMER, RIDER, null, "corr-1");
        }

        @Test
        void the_rider_is_reimbursed_the_goods_in_full_and_commission_comes_off_the_fee_alone() {
            // Goods 22.40 the rider paid out of pocket, plus a 3.50 errand fee. The platform sold
            // the errand, not the goods, so 12.5% applies to 3.50 and nothing else.
            List<AccountingTransaction> legs = settleErrand("12.5", "25.90", "22.40");

            assertThat(amountOf(legs, Leg.CUSTOMER_DEBIT)).isEqualByComparingTo("25.90");
            // 22.40 back, plus 3.50 - 0.44 of the fee.
            assertThat(amountOf(legs, Leg.RIDER_CREDIT)).isEqualByComparingTo("25.46");
            assertThat(amountOf(legs, Leg.PLATFORM_COMMISSION)).isEqualByComparingTo("0.44");
            assertThat(amountOf(legs, Leg.MERCHANT_CREDIT)).isNull();
        }

        @Test
        void commission_is_never_taken_from_money_the_rider_merely_fronted() {
            // The trap this guards: charging 12.5% of 25.90 would take 3.24 from someone who spent
            // 22.40 of their own money to earn 3.50, leaving them worse off for having done the job.
            List<AccountingTransaction> legs = settleErrand("12.5", "25.90", "22.40");

            BigDecimal riderNet = amountOf(legs, Leg.RIDER_CREDIT).subtract(new BigDecimal("22.40"));
            assertThat(riderNet).isEqualByComparingTo("3.06");
            assertThat(riderNet.signum()).isPositive();
        }

        @Test
        void a_pickup_bought_nothing_so_it_is_a_straight_fee_split() {
            List<AccountingTransaction> legs = settleErrand("12.5", "3.50", "0.00");

            assertThat(amountOf(legs, Leg.CUSTOMER_DEBIT)).isEqualByComparingTo("3.50");
            assertThat(amountOf(legs, Leg.RIDER_CREDIT)).isEqualByComparingTo("3.06");
            assertThat(amountOf(legs, Leg.PLATFORM_COMMISSION)).isEqualByComparingTo("0.44");
        }

        @ParameterizedTest
        @ValueSource(strings = {"0.01", "3.50", "7.77", "12.99", "100.00"})
        void the_legs_always_sum_to_what_the_customer_paid(String fee) {
            BigDecimal goods = new BigDecimal("19.99");
            BigDecimal total = goods.add(new BigDecimal(fee));

            List<AccountingTransaction> legs = serviceAt("12.5")
                    .settleErrand(orderId, total, goods, CUSTOMER, RIDER, null, "corr-1");

            BigDecimal credited = legs.stream()
                    .filter(t -> t.getDirection() == Direction.CREDIT)
                    .map(AccountingTransaction::getAmount)
                    .reduce(BigDecimal.ZERO, BigDecimal::add);
            assertThat(credited).isEqualByComparingTo(amountOf(legs, Leg.CUSTOMER_DEBIT));
        }

        @Test
        void a_fee_too_small_to_round_a_commission_produces_no_commission_leg() {
            // The bank rejects a zero posting, and that rejection would read as a real failure.
            List<AccountingTransaction> legs = settleErrand("12.5", "20.03", "20.00");

            assertThat(amountOf(legs, Leg.PLATFORM_COMMISSION)).isNull();
            assertThat(amountOf(legs, Leg.RIDER_CREDIT)).isEqualByComparingTo("20.03");
        }

        @Test
        void goods_above_the_total_are_clamped_rather_than_crediting_money_nobody_paid() {
            List<AccountingTransaction> legs = settleErrand("12.5", "10.00", "99.00");

            assertThat(amountOf(legs, Leg.RIDER_CREDIT)).isEqualByComparingTo("10.00");
            assertThat(amountOf(legs, Leg.PLATFORM_COMMISSION)).isNull();
        }

        @Test
        void only_the_debit_is_asked_for_first_so_nobody_is_paid_from_uncollected_money() {
            settleErrand("12.5", "25.90", "22.40");

            ArgumentCaptor<AccountingTransaction> asked =
                    ArgumentCaptor.forClass(AccountingTransaction.class);
            verify(postings).request(asked.capture());
            assertThat(asked.getValue().getLeg()).isEqualTo(Leg.CUSTOMER_DEBIT);
        }

        @Test
        void an_errand_already_settled_is_not_settled_again() {
            when(transactions.existsByOrderId(orderId)).thenReturn(true);

            assertThat(settleErrand("12.5", "25.90", "22.40")).isEmpty();
            verifyNoInteractions(postings);
        }
    }
}
