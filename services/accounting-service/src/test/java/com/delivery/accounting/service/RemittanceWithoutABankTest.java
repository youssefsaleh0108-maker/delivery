package com.delivery.accounting.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatRepository;

/**
 * RECON-06: under LEDGER_ONLY every banked hand-over stays PENDING for ever.
 *
 * <p>Settlement knows there is no bank ({@code SettlementMode.LEDGER_ONLY}, the deployed default)
 * and records every leg as {@code SETTLED_IN_CASH}. The remittance does not: {@link
 * CashFloatService#remit} writes its {@code CASH_REMITTANCE} leg PENDING and asks the Core Banking
 * connector for it, and nothing consumes {@code accounting.posting.requested} on any environment. So
 * the leg never leaves PENDING. On dev, two remittances recorded in the deep test (76.39 from the
 * delivery company, 254.87 from the platform rider) turned {@code /api/accounting/summary} into
 * "amountAtRisk 331.26, unsettledCount 2", put both on the Back Office's unsettled work list, and set
 * {@code delivery_settlement_stuck_legs} to 2 — the SettlementLegsStuck alert condition, now true for
 * good.
 *
 * <p>Fails until a remittance, like every other leg, is recorded as discharged when there is no
 * bank to wait for.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("RECON-06: a remittance recorded with no bank does not wait for one")
class RemittanceWithoutABankTest {

    private static final String RIDER = "b37151c5-f948-4ad7-a4ba-0e9315a7e8f4";

    @Mock
    private CashFloatRepository floats;
    @Mock
    private AccountingTransactionRepository transactions;
    @Mock
    private BankPostingPublisher postings;

    @Test
    @DisplayName("the rider's banked takings are a terminal leg, not a posting at risk")
    void theRemittanceLegIsTerminal() {
        CashFloatEntry first = CashFloatEntry.collected(RIDER, CashFloatEntry.HolderKind.RIDER,
                UUID.randomUUID(), new BigDecimal("19.50"), "USD");
        CashFloatEntry second = CashFloatEntry.collected(RIDER, CashFloatEntry.HolderKind.RIDER,
                UUID.randomUUID(), new BigDecimal("9.25"), "USD");
        when(floats.outstandingFor(RIDER, CashFloatEntry.HolderKind.RIDER))
                .thenReturn(List.of(first, second));
        when(floats.save(any())).thenAnswer(call -> call.getArgument(0));
        when(transactions.save(any())).thenAnswer(call -> call.getArgument(0));

        CashFloatService service = new CashFloatService(floats, transactions, postings,
                "ACC-PLATFORM", "USD");
        service.remit(RIDER, "corr", new BigDecimal("28.75"),
                new CashFloatEntry.Recorded("backoffice-1", CashFloatEntry.Method.CASH, null, null),
                CashFloatEntry.HolderKind.RIDER);

        ArgumentCaptor<AccountingTransaction> leg = ArgumentCaptor.forClass(AccountingTransaction.class);
        verify(transactions).save(leg.capture());
        assertThat(leg.getValue().getLeg()).isEqualTo(AccountingTransaction.Leg.CASH_REMITTANCE);
        assertThat(leg.getValue().getAmount()).isEqualByComparingTo("28.75");
        // What /api/accounting/summary counts as "at risk" and the stuck-legs alert counts as stuck.
        assertThat(leg.getValue().getStatus())
                .as("status of a remittance leg when no bank is deployed")
                .isNotIn(AccountingTransaction.Status.PENDING, AccountingTransaction.Status.FAILED);
    }
}
