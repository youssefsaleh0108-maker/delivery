package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.util.UUID;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransaction.Direction;
import com.delivery.accounting.domain.AccountingTransaction.Leg;
import com.delivery.accounting.domain.CounterpartyKind;

/**
 * Ledger legs for the statement tests, written the way settlement writes them.
 *
 * <p>Shared rather than repeated in each file so that all four kinds of statement are tested against
 * the SAME shape of row. A fixture that drifted between test files would let a statement pass
 * against legs settlement does not actually produce.
 */
final class Legs {

    private Legs() {
    }

    static AccountingTransaction of(UUID orderId, Leg leg, String amount, Direction direction,
                                    CounterpartyKind kind, String ref) {
        return new AccountingTransaction(orderId, leg, "ACC-" + leg, new BigDecimal(amount),
                "USD", direction, "corr")
                .attributedTo(kind, ref);
    }

    static AccountingTransaction merchantCredit(UUID orderId, String amount, String merchantRef) {
        return of(orderId, Leg.MERCHANT_CREDIT, amount, Direction.CREDIT,
                CounterpartyKind.MERCHANT, merchantRef);
    }

    static AccountingTransaction commission(UUID orderId, String amount) {
        return of(orderId, Leg.PLATFORM_COMMISSION, amount, Direction.CREDIT,
                CounterpartyKind.PLATFORM, CounterpartyKind.PLATFORM_REF);
    }

    static AccountingTransaction subsidy(UUID orderId, String amount) {
        return of(orderId, Leg.PLATFORM_SUBSIDY, amount, Direction.DEBIT,
                CounterpartyKind.PLATFORM, CounterpartyKind.PLATFORM_REF);
    }

    static AccountingTransaction providerCredit(UUID orderId, String amount, String carrierRef) {
        return of(orderId, Leg.PROVIDER_CREDIT, amount, Direction.CREDIT,
                CounterpartyKind.CARRIER, carrierRef);
    }

    static AccountingTransaction riderCredit(UUID orderId, String amount, String riderRef) {
        return of(orderId, Leg.RIDER_CREDIT, amount, Direction.CREDIT,
                CounterpartyKind.RIDER, riderRef);
    }

    static AccountingTransaction cashCollected(UUID orderId, String amount, String riderRef) {
        return AccountingTransaction.obligation(orderId, Leg.CASH_COLLECTED, riderRef,
                        new BigDecimal(amount), "USD", Direction.DEBIT, "corr")
                .attributedTo(CounterpartyKind.RIDER, riderRef);
    }

    /** A merchant credit from before attribution existed — the 45 rows already in the database. */
    static AccountingTransaction unattributedMerchantCredit(UUID orderId, String amount) {
        return of(orderId, Leg.MERCHANT_CREDIT, amount, Direction.CREDIT, null, null);
    }
}
