package com.delivery.accounting.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransaction.Direction;
import com.delivery.accounting.domain.AccountingTransaction.Leg;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatRepository;

/**
 * Settlement when the platform has given a fee away.
 *
 * <p>Two properties carry this whole feature, and both are about somebody not being cheated:
 *
 * <ul>
 *   <li><strong>Nobody is ever paid less than they are owed.</strong> A customer with free delivery
 *       still has a carrier who did the work and must be paid in full. The platform absorbs it.
 *   <li><strong>The legs still balance.</strong> Whatever the platform gives away, what was
 *       collected plus what the platform paid in must equal what everyone was credited.
 * </ul>
 */
@ExtendWith(MockitoExtension.class)
class SettlementWaiverTest {

    private static final String CUSTOMER = "ACC-CUSTOMER";
    private static final String MERCHANT = "ACC-MERCHANT";
    private static final String CARRIER = "ACC-CARRIER";
    private static final String PLATFORM = "ACC-PLATFORM";

    @Mock
    private AccountingTransactionRepository transactions;
    @Mock
    private CashFloatRepository floatEntries;
    @Mock
    private BankPostingPublisher postings;
    @Mock
    private com.delivery.accounting.domain.RiderLedgerRepository riderLedger;

    private UUID orderId;

    @BeforeEach
    void setUp() {
        orderId = UUID.randomUUID();
    }

    private SettlementService service() {
        // 12.5% on goods, 10% of the delivery fee — the platform's real rates.
        return new SettlementService(transactions, floatEntries, riderLedger, postings,
                new BigDecimal("12.5"), new BigDecimal("10"), "", PLATFORM, "USD",
                // BANK: these assert the leg arithmetic as it reaches the bank path.
                SettlementService.SettlementMode.BANK);
    }

    /**
     * @param total what the customer actually paid — excludes a waived delivery fee
     * @param fee   what delivery cost, which is what the carrier is owed either way
     */
    private List<AccountingTransaction> settle(String total, String goods, String fee,
                                               boolean customerWaived, boolean merchantWaived,
                                               boolean carrierWaived, String carrierAccount) {
        when(transactions.existsByOrderId(any())).thenReturn(false);
        return service().settle(orderId, new BigDecimal(total), new BigDecimal(goods),
                CUSTOMER, MERCHANT, carrierAccount, null, "corr-1",
                new SettlementService.Waivers(
                        new BigDecimal(fee), customerWaived, merchantWaived, carrierWaived));
    }

    private static BigDecimal amountOf(List<AccountingTransaction> legs, Leg which) {
        return legs.stream()
                .filter(t -> t.getLeg() == which)
                .map(AccountingTransaction::getAmount)
                .findFirst()
                .orElse(null);
    }

    /** Collected plus paid in, against everything credited out. */
    private static void assertBalances(List<AccountingTransaction> legs, String collected) {
        BigDecimal credited = legs.stream()
                .filter(t -> t.getDirection() == Direction.CREDIT)
                .map(AccountingTransaction::getAmount)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
        BigDecimal subsidy = legs.stream()
                .filter(t -> t.getLeg() == Leg.PLATFORM_SUBSIDY)
                .map(AccountingTransaction::getAmount)
                .reduce(BigDecimal.ZERO, BigDecimal::add);

        assertThat(new BigDecimal(collected).add(subsidy))
                .as("what was collected plus what the platform paid in must equal what went out")
                .isEqualByComparingTo(credited);
    }

    @Nested
    @DisplayName("free delivery for the customer")
    class CustomerWaiver {

        @Test
        void the_carrier_is_still_paid_in_full() {
            // 40.00 of goods, a 2.50 delivery fee the customer does not pay. They are debited 40.00.
            List<AccountingTransaction> legs =
                    settle("40.00", "40.00", "2.50", true, false, false, CARRIER);

            assertThat(amountOf(legs, Leg.CUSTOMER_DEBIT)).isEqualByComparingTo("40.00");
            // 2.50 less the platform's 10% cut — exactly what they would have got if the customer
            // had paid. The promotion is the platform's to fund, not the carrier's.
            assertThat(amountOf(legs, Leg.PROVIDER_CREDIT)).isEqualByComparingTo("2.25");
        }

        @Test
        void the_merchant_is_unaffected() {
            List<AccountingTransaction> legs =
                    settle("40.00", "40.00", "2.50", true, false, false, CARRIER);

            // 40.00 less 12.5%. A promotion aimed at customers must not quietly cost the shop.
            assertThat(amountOf(legs, Leg.MERCHANT_CREDIT)).isEqualByComparingTo("35.00");
        }

        @Test
        void the_platform_absorbs_the_fee_out_of_its_commission() {
            List<AccountingTransaction> legs =
                    settle("40.00", "40.00", "2.50", true, false, false, CARRIER);

            // Commission 5.00 less the 2.25 paid to the carrier.
            assertThat(amountOf(legs, Leg.PLATFORM_COMMISSION)).isEqualByComparingTo("2.75");
            assertBalances(legs, "40.00");
        }

        @Test
        void a_fee_bigger_than_the_commission_makes_the_platform_pay_in() {
            // A 6.00 basket with a 4.00 delivery fee: commission is 0.75, the carrier is owed 3.60.
            // The platform is 2.85 out of pocket. This is the offer working — it is buying the
            // order — and it is exactly what the budget exists to bound.
            List<AccountingTransaction> legs =
                    settle("6.00", "6.00", "4.00", true, false, false, CARRIER);

            assertThat(amountOf(legs, Leg.PLATFORM_COMMISSION))
                    .as("nothing was kept, so no commission leg is posted")
                    .isNull();
            assertThat(amountOf(legs, Leg.PLATFORM_SUBSIDY)).isEqualByComparingTo("2.85");
            assertBalances(legs, "6.00");
        }

        @Test
        void the_subsidy_is_a_debit_so_the_direction_says_which_way_it_went() {
            List<AccountingTransaction> legs =
                    settle("6.00", "6.00", "4.00", true, false, false, CARRIER);

            AccountingTransaction subsidy = legs.stream()
                    .filter(t -> t.getLeg() == Leg.PLATFORM_SUBSIDY)
                    .findFirst().orElseThrow();
            // Positive amount, DEBIT direction. A negative "commission" would make a report have to
            // read the sign to notice a loss.
            assertThat(subsidy.getAmount().signum()).isPositive();
            assertThat(subsidy.getDirection()).isEqualTo(Direction.DEBIT);
        }
    }

    @Nested
    @DisplayName("no commission for the merchant")
    class MerchantWaiver {

        @Test
        void the_merchant_keeps_the_whole_goods_amount() {
            List<AccountingTransaction> legs =
                    settle("42.50", "40.00", "2.50", false, true, false, CARRIER);

            assertThat(amountOf(legs, Leg.MERCHANT_CREDIT)).isEqualByComparingTo("40.00");
        }

        @Test
        void the_customer_still_pays_their_delivery_fee() {
            List<AccountingTransaction> legs =
                    settle("42.50", "40.00", "2.50", false, true, false, CARRIER);

            // A merchant promotion is between the platform and the shop. The customer is not part
            // of it and must not be charged differently because of it.
            assertThat(amountOf(legs, Leg.CUSTOMER_DEBIT)).isEqualByComparingTo("42.50");
            assertThat(amountOf(legs, Leg.PROVIDER_CREDIT)).isEqualByComparingTo("2.25");
        }

        @Test
        void the_platform_keeps_only_its_delivery_cut() {
            List<AccountingTransaction> legs =
                    settle("42.50", "40.00", "2.50", false, true, false, CARRIER);

            // No commission at all; only the 0.25 cut of the delivery fee.
            assertThat(amountOf(legs, Leg.PLATFORM_COMMISSION)).isEqualByComparingTo("0.25");
            assertBalances(legs, "42.50");
        }
    }

    @Nested
    @DisplayName("no platform cut for the delivery company")
    class CarrierWaiver {

        @Test
        void the_carrier_keeps_the_whole_delivery_fee() {
            List<AccountingTransaction> legs =
                    settle("42.50", "40.00", "2.50", false, false, true, CARRIER);

            assertThat(amountOf(legs, Leg.PROVIDER_CREDIT)).isEqualByComparingTo("2.50");
        }

        @Test
        void the_platform_keeps_only_its_goods_commission() {
            List<AccountingTransaction> legs =
                    settle("42.50", "40.00", "2.50", false, false, true, CARRIER);

            assertThat(amountOf(legs, Leg.PLATFORM_COMMISSION)).isEqualByComparingTo("5.00");
            assertBalances(legs, "42.50");
        }

        @Test
        void it_means_nothing_when_the_platforms_own_riders_carried_it() {
            // No carrier account: there is no delivery company to waive a cut for, and the fee
            // stays with the platform exactly as it always did.
            List<AccountingTransaction> legs =
                    settle("42.50", "40.00", "2.50", false, false, true, null);

            assertThat(amountOf(legs, Leg.PROVIDER_CREDIT)).isNull();
            assertThat(amountOf(legs, Leg.PLATFORM_COMMISSION)).isEqualByComparingTo("7.50");
        }
    }

    @Nested
    @DisplayName("all three at once")
    class Everything {

        @Test
        void the_platform_funds_the_lot_and_the_books_still_balance() {
            // 40.00 of goods, 2.50 of delivery, everything waived. The customer pays 40.00, the
            // merchant keeps 40.00, the carrier keeps 2.50 — so the platform pays in 2.50.
            List<AccountingTransaction> legs =
                    settle("40.00", "40.00", "2.50", true, true, true, CARRIER);

            assertThat(amountOf(legs, Leg.CUSTOMER_DEBIT)).isEqualByComparingTo("40.00");
            assertThat(amountOf(legs, Leg.MERCHANT_CREDIT)).isEqualByComparingTo("40.00");
            assertThat(amountOf(legs, Leg.PROVIDER_CREDIT)).isEqualByComparingTo("2.50");
            assertThat(amountOf(legs, Leg.PLATFORM_SUBSIDY)).isEqualByComparingTo("2.50");
            assertBalances(legs, "40.00");
        }
    }

    /**
     * A promo code, which is the platform buying the order out of its own margin.
     *
     * <p>Order Manager states the rule on the event itself: {@code totalAmount} is already net of
     * the discount, the merchant is still owed the whole {@code subtotal} and the carrier the whole
     * {@code deliveryFee}. Nothing here should be paid a penny less because the platform ran a
     * promotion.
     *
     * <p>The case that actually broke is the last one. A discount big enough to take the total below
     * the goods subtotal made the merchant base look impossible, and the sanity clamp reduced it to
     * the total — silently charging the shop for the platform's own offer, on the discounts most
     * worth running.
     */
    @Nested
    @DisplayName("a promo code the customer typed")
    class PromoDiscount {

        private List<AccountingTransaction> settleDiscounted(String total, String goods,
                                                             String fee, String discount) {
            when(transactions.existsByOrderId(any())).thenReturn(false);
            return service().settle(orderId, new BigDecimal(total), new BigDecimal(goods),
                    CUSTOMER, MERCHANT, CARRIER, null, "corr-1",
                    new SettlementService.Waivers(new BigDecimal(fee), false, false, false,
                            new BigDecimal(discount)));
        }

        @Test
        @DisplayName("comes out of the platform's share, not the merchant's")
        void the_merchant_is_paid_on_the_full_subtotal() {
            // Goods 40, delivery 2.50, five off: the customer pays 37.50.
            List<AccountingTransaction> legs = settleDiscounted("37.50", "40.00", "2.50", "5.00");

            // 12.5% of 40 is 5.00, so the shop keeps 35.00 — exactly what an undiscounted order
            // would have paid them.
            assertThat(amountOf(legs, Leg.MERCHANT_CREDIT)).isEqualByComparingTo("35.00");
            assertThat(amountOf(legs, Leg.PROVIDER_CREDIT)).isEqualByComparingTo("2.25");
            assertBalances(legs, "37.50");
        }

        @Test
        @DisplayName("shrinks the platform leg by exactly what it gave away")
        void the_platform_absorbs_it() {
            List<AccountingTransaction> legs = settleDiscounted("37.50", "40.00", "2.50", "5.00");

            // Undiscounted this order leaves the platform 5.25 (see the Unchanged case below).
            // Five pounds off leaves 0.25.
            assertThat(amountOf(legs, Leg.PLATFORM_COMMISSION)).isEqualByComparingTo("0.25");
            assertThat(amountOf(legs, Leg.PLATFORM_SUBSIDY)).isNull();
        }

        @Test
        @DisplayName("larger than the platform's margin is posted as a subsidy, and still balances")
        void a_discount_beyond_the_margin_is_paid_in() {
            // Ten off a 42.50 order: the platform's 5.25 margin cannot cover it.
            List<AccountingTransaction> legs = settleDiscounted("32.50", "40.00", "2.50", "10.00");

            assertThat(amountOf(legs, Leg.MERCHANT_CREDIT)).isEqualByComparingTo("35.00");
            assertThat(amountOf(legs, Leg.PROVIDER_CREDIT)).isEqualByComparingTo("2.25");
            assertThat(amountOf(legs, Leg.PLATFORM_SUBSIDY)).isEqualByComparingTo("4.75");
            assertBalances(legs, "32.50");
        }

        @Test
        @DisplayName("that takes the total below the goods still pays the shop what they sold")
        void the_merchant_base_is_not_clamped_to_a_discounted_total() {
            // Twenty off: the customer pays 22.50 for 40.00 of goods. The subtotal is legitimately
            // larger than the total, which is exactly the shape the clamp used to mistake for a
            // malformed event.
            List<AccountingTransaction> legs = settleDiscounted("22.50", "40.00", "2.50", "20.00");

            assertThat(amountOf(legs, Leg.MERCHANT_CREDIT))
                    .as("the shop sold 40.00 of goods and is owed 35.00 of it, discount or not")
                    .isEqualByComparingTo("35.00");
            assertThat(amountOf(legs, Leg.PROVIDER_CREDIT)).isEqualByComparingTo("2.25");
            assertThat(amountOf(legs, Leg.PLATFORM_SUBSIDY)).isEqualByComparingTo("14.75");
            assertBalances(legs, "22.50");
        }
    }

    @Nested
    @DisplayName("orders that predate offers")
    class Unchanged {

        @Test
        void settle_exactly_as_they_always_did() {
            when(transactions.existsByOrderId(any())).thenReturn(false);
            // No explicit fee and no waivers — the shape of every event published before this
            // feature. The fee is derived from the total, as it was.
            List<AccountingTransaction> legs = service().settle(orderId,
                    new BigDecimal("42.50"), new BigDecimal("40.00"),
                    CUSTOMER, MERCHANT, CARRIER, null, "corr-1",
                    SettlementService.Waivers.none());

            assertThat(amountOf(legs, Leg.MERCHANT_CREDIT)).isEqualByComparingTo("35.00");
            assertThat(amountOf(legs, Leg.PROVIDER_CREDIT)).isEqualByComparingTo("2.25");
            assertThat(amountOf(legs, Leg.PLATFORM_COMMISSION)).isEqualByComparingTo("5.25");
            assertThat(amountOf(legs, Leg.PLATFORM_SUBSIDY)).isNull();
        }
    }
}
