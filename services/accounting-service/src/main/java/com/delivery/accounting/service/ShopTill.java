package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Collection;
import java.util.HashMap;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransaction.Leg;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CounterpartyKind;

/**
 * A shop's till: the cash its counter took for pickup orders and has not yet settled with the
 * platform, split into whose it is (V52).
 *
 * <p><strong>The shop keeps its share and pays the platform only what is the platform's.</strong> A
 * pickup is paid in full at the counter of the shop that did the work, so the notes for the shop's
 * own share — its goods less commission, and any gift wrapping — are in its hands the moment the
 * customer pays. Having it hand the whole till over and wait to be paid its share back would move
 * the same notes twice. Worse, a till that could only be cleared whole left a shop that paid exactly
 * what its statement asked for overdue for ever, while an operator who cleared the whole till
 * recorded the share the shop had kept as money the platform still owed it. So what a shop owes out
 * of its till is the rest: the platform's commission, and any other part of the order that was the
 * platform's.
 *
 * <p><strong>Per order, never across orders.</strong> On an order a promotion discounted below the
 * shop's share, the shop keeps all of that order's cash and no more. One order's shortfall is never
 * quietly taken out of another order's commission, and what the platform still owes the shop on it
 * stays on the shop's statement as the platform's debt.
 *
 * <p>The share is read off the shop's own credit legs — the ones attributed to it, which are the ones
 * its statement is built from — so the figure an operator records and the figure the shop's
 * statement asks for are one rule applied to the same rows.
 *
 * @param held     every note still in the till from these orders
 * @param retained the shop's own share of them, which it keeps
 * @param owed     the platform's part, which the shop pays: {@code held - retained}
 */
public record ShopTill(BigDecimal held, BigDecimal retained, BigDecimal owed) {

    /**
     * The till these collections make up.
     *
     * @param rows the shop's outstanding collections, one per pickup
     * @param legs the legs on those orders; legs on any other order are ignored
     */
    static ShopTill of(String shopRef, Collection<CashFloatEntry> rows,
                       Collection<AccountingTransaction> legs) {
        Map<UUID, BigDecimal> shares = sharesOf(shopRef, legs);
        BigDecimal held = BigDecimal.ZERO;
        BigDecimal retained = BigDecimal.ZERO;
        for (CashFloatEntry row : rows) {
            held = held.add(row.getAmount());
            retained = retained.add(keptOf(row.getAmount(),
                    shares.getOrDefault(row.getOrderId(), BigDecimal.ZERO)));
        }
        return new ShopTill(money(held), money(retained), money(held.subtract(retained)));
    }

    /**
     * The shop's own credits on each order: its goods share and its wrapping.
     *
     * <p>Only legs attributed to this shop. An unattributed credit might be the shop's, but "might"
     * is no basis for letting it keep money: such a till is owed whole, and the shop's statement,
     * which reads the same attributed legs, asks for the same figure.
     */
    static Map<UUID, BigDecimal> sharesOf(String shopRef, Collection<AccountingTransaction> legs) {
        Map<UUID, BigDecimal> shares = new HashMap<>();
        for (AccountingTransaction leg : legs) {
            if ((leg.getLeg() == Leg.MERCHANT_CREDIT || leg.getLeg() == Leg.GIFT_WRAP_CREDIT)
                    && leg.getCounterpartyKind() == CounterpartyKind.MERCHANT
                    && Objects.equals(shopRef, leg.getCounterpartyRef())) {
                shares.merge(leg.getOrderId(), leg.getAmount(), BigDecimal::add);
            }
        }
        return shares;
    }

    /** What a shop keeps of one order's cash: its share, and never more than the customer paid. */
    static BigDecimal keptOf(BigDecimal cash, BigDecimal share) {
        return cash.min(share.max(BigDecimal.ZERO));
    }

    private static BigDecimal money(BigDecimal amount) {
        return amount.setScale(2, RoundingMode.HALF_UP);
    }
}
