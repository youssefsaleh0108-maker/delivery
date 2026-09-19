package com.delivery.accounting.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.lenient;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Instant;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransaction.Direction;
import com.delivery.accounting.domain.AccountingTransaction.Leg;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.RiderLedgerRepository;

/**
 * The settlement invariants of MONEY-MODEL.md (I1 to I5), over thousands of generated orders.
 *
 * <p>Each order is priced by order-manager's own rule — {@code total = subtotal + charged fee +
 * express − discount + wrap}, the discount clamped to the bill before the wrap — and settled the way
 * {@code OrderEventListener} settles a catalog order, on either fleet, paid in cash or by card, with
 * any mix of waivers and promotions. Whatever the combination, the books must balance to the cent,
 * the collection must be exactly what the customer paid, and every payee must get exactly the
 * published formula: the shop its goods less 12.5% and its wrapping in full, the carrier or rider the
 * fee less 10%. The platform is whatever is left, and that residue is allowed to go negative.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("settlement invariants over generated orders (reconciliation deep test)")
class SettlementInvariantsTest {

    private static final BigDecimal GOODS_RATE = new BigDecimal("12.5");
    private static final BigDecimal DELIVERY_RATE = new BigDecimal("10");

    @Mock
    private AccountingTransactionRepository transactions;
    @Mock
    private CashFloatRepository floats;
    @Mock
    private RiderLedgerRepository riderLedger;
    @Mock
    private BankPostingPublisher postings;

    private SettlementService settlement;

    @BeforeEach
    void setUp() {
        lenient().when(transactions.existsByOrderId(any())).thenReturn(false);
        lenient().when(floats.existsByOrderIdAndEntryKind(any(), any())).thenReturn(false);
        settlement = new SettlementService(transactions, floats, riderLedger, postings,
                GOODS_RATE, DELIVERY_RATE, "", "ACC-PLATFORM", "USD",
                SettlementService.SettlementMode.LEDGER_ONLY);
    }

    private static BigDecimal cents(long cents) {
        return BigDecimal.valueOf(cents, 2);
    }

    private static BigDecimal pct(BigDecimal amount, BigDecimal rate) {
        return amount.multiply(rate).divide(BigDecimal.valueOf(100), 2, RoundingMode.HALF_UP);
    }

    @Test
    @DisplayName("I1-I5: every generated order balances and pays each party its formula")
    void everyOrderBalancesAndPaysTheFormula() {
        Random random = new Random(20260919L);
        int checked = 0;
        for (int i = 0; i < 4000; i++) {
            BigDecimal subtotal = cents(1 + random.nextInt(25_000));
            BigDecimal fee = random.nextInt(4) == 0 ? BigDecimal.ZERO.setScale(2)
                    : cents(random.nextInt(900));
            BigDecimal express = random.nextBoolean() ? cents(200) : BigDecimal.ZERO.setScale(2);
            BigDecimal wrap = random.nextInt(5) == 0 ? cents(300) : BigDecimal.ZERO.setScale(2);
            boolean feeWaived = random.nextInt(6) == 0;
            boolean merchantWaived = random.nextInt(6) == 0;
            boolean carrierWaived = random.nextInt(6) == 0;
            boolean carrierFleet = random.nextBoolean();
            boolean cash = random.nextBoolean();

            // Order-manager's pricing, including both clamps.
            BigDecimal chargeable = subtotal.add(feeWaived ? BigDecimal.ZERO : fee).add(express);
            BigDecimal discount = switch (random.nextInt(4)) {
                case 0 -> BigDecimal.ZERO.setScale(2);
                case 1 -> cents(1 + random.nextInt(1_000)).min(chargeable);
                case 2 -> pct(subtotal, BigDecimal.valueOf(5 + random.nextInt(60)));
                default -> chargeable; // a code worth the whole bill
            };
            BigDecimal total = chargeable.subtract(discount).add(wrap);

            UUID orderId = UUID.randomUUID();
            String rider = "rider-" + i;
            SettlementService.CashHolder holder = cash
                    ? new SettlementService.CashHolder(rider, CashFloatEntry.HolderKind.RIDER,
                            carrierFleet ? "carrier-1" : null)
                    : null;
            List<AccountingTransaction> legs = settlement.settle(orderId, total, subtotal,
                    "ACC-CUSTOMER", "ACC-MERCHANT", carrierFleet ? "ACC-CARRIER" : null, holder,
                    "corr", new SettlementService.Waivers(fee, feeWaived, merchantWaived,
                            carrierWaived, discount.signum() > 0 ? discount : null),
                    new SettlementService.Rider(rider, "ACC-RIDER",
                            carrierFleet ? "carrier-1" : null, "customer-1"),
                    Instant.parse("2026-09-19T10:00:00Z"),
                    new SettlementService.Parties("merchant-1", carrierFleet ? "carrier-1" : null),
                    wrap);

            String label = "order " + i + " (subtotal " + subtotal + ", fee " + fee + ", express "
                    + express + ", wrap " + wrap + ", discount " + discount + ", waived "
                    + feeWaived + "/" + merchantWaived + "/" + carrierWaived + ", "
                    + (carrierFleet ? "carrier" : "own fleet") + ", " + (cash ? "cash" : "card")
                    + ", total " + total + ")";

            Map<Leg, BigDecimal> byLeg = new EnumMap<>(Leg.class);
            BigDecimal debits = BigDecimal.ZERO;
            BigDecimal credits = BigDecimal.ZERO;
            for (AccountingTransaction leg : legs) {
                assertThat(leg.getAmount().signum()).as(label + " " + leg.getLeg()).isPositive();
                assertThat(leg.getAmount().scale()).as(label + " scale").isEqualTo(2);
                assertThat(byLeg.put(leg.getLeg(), leg.getAmount()))
                        .as(label + " one " + leg.getLeg()).isNull();
                if (leg.getDirection() == Direction.DEBIT) {
                    debits = debits.add(leg.getAmount());
                } else {
                    credits = credits.add(leg.getAmount());
                }
            }

            // I1: the books balance.
            assertThat(debits).as(label + " I1 debits = credits").isEqualByComparingTo(credits);

            // I2: the collection is what the customer paid, in the form they paid it.
            Leg collection = cash ? Leg.CASH_COLLECTED : Leg.CUSTOMER_DEBIT;
            if (total.signum() > 0) {
                assertThat(byLeg.get(collection)).as(label + " I2 collection").isEqualByComparingTo(total);
            } else {
                assertThat(byLeg).as(label + " I2 no collection on a zero bill")
                        .doesNotContainKeys(Leg.CASH_COLLECTED, Leg.CUSTOMER_DEBIT);
            }

            // I3: the shop gets its goods less commission, and its wrapping in full.
            BigDecimal merchant = merchantWaived ? subtotal : subtotal.subtract(pct(subtotal, GOODS_RATE));
            assertThat(byLeg.getOrDefault(Leg.MERCHANT_CREDIT, BigDecimal.ZERO))
                    .as(label + " I3 merchant credit").isEqualByComparingTo(merchant);
            assertThat(byLeg.getOrDefault(Leg.GIFT_WRAP_CREDIT, BigDecimal.ZERO))
                    .as(label + " I3 wrap credit").isEqualByComparingTo(wrap);

            // I4: whoever carried it gets the fee less the platform's cut, whatever the customer paid.
            BigDecimal carried = fee.signum() == 0 ? BigDecimal.ZERO
                    : (carrierWaived ? fee : fee.subtract(pct(fee, DELIVERY_RATE)));
            Leg carrierLeg = carrierFleet ? Leg.PROVIDER_CREDIT : Leg.RIDER_CREDIT;
            assertThat(byLeg.getOrDefault(carrierLeg, BigDecimal.ZERO))
                    .as(label + " I4 " + carrierLeg).isEqualByComparingTo(carried);

            // I5: the platform keeps exactly the rest, which may be a subsidy.
            BigDecimal payees = merchant.add(wrap).add(carried);
            BigDecimal kept = byLeg.getOrDefault(Leg.PLATFORM_COMMISSION, BigDecimal.ZERO)
                    .subtract(byLeg.getOrDefault(Leg.PLATFORM_SUBSIDY, BigDecimal.ZERO));
            assertThat(kept).as(label + " I5 platform residue")
                    .isEqualByComparingTo(total.subtract(payees));
            checked++;
        }
        assertThat(checked).isEqualTo(4000);
    }
}
