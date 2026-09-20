package com.delivery.accounting.api;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.math.BigDecimal;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.delivery.accounting.domain.AccountingTransaction.Direction;
import com.delivery.accounting.domain.AccountingTransaction.Status;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CoreBankingSyncLogRepository;
import com.delivery.accounting.service.CarrierCashService;
import com.delivery.accounting.service.CashFloatService;
import com.delivery.accounting.service.SettlementFailures;
import com.delivery.accounting.service.SettlementRecovery;

/**
 * RECON-13: the landing view's figures do not add debits to credits.
 *
 * <p>An order's two sides are the same money described twice (I1), so a total that summed both
 * reported every unfinished settlement at double its worth — dev's "amountAtRisk 331.26" was two
 * banked hand-overs worth 331.26 between them, counted once as the collection and once as the
 * payment.
 */
@DisplayName("RECON-13: the reconciliation summary")
class ReconciliationSummaryTest {

    private AccountingTransactionRepository transactions;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        transactions = mock(AccountingTransactionRepository.class);
        mvc = MockMvcBuilders.standaloneSetup(new ReconciliationController(transactions,
                        mock(CashFloatService.class), mock(CoreBankingSyncLogRepository.class),
                        mock(CarrierCashService.class), mock(SettlementFailures.class),
                        mock(SettlementRecovery.class)))
                .build();
    }

    private static Object[] row(Status status, Direction direction, long count, String amount) {
        return new Object[] {status, direction, count, new BigDecimal(amount)};
    }

    @Test
    @DisplayName("reports each side of a status apart, and the money at risk once")
    void bothSidesApart() throws Exception {
        when(transactions.summariseByStatusAndDirection()).thenReturn(List.of(
                // A settled day: 500.00 collected, 500.00 paid out across the payees.
                row(Status.SETTLED_IN_CASH, Direction.DEBIT, 20, "500.00"),
                row(Status.SETTLED_IN_CASH, Direction.CREDIT, 60, "500.00"),
                // Two settlements stuck: 165.63 of collections against their 165.63 of credits.
                row(Status.PENDING, Direction.DEBIT, 2, "165.63"),
                row(Status.PENDING, Direction.CREDIT, 5, "165.63"),
                row(Status.FAILED, Direction.CREDIT, 1, "35.00")));

        mvc.perform(get("/api/accounting/summary"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.byStatus.SETTLED_IN_CASH.count").value(80))
                .andExpect(jsonPath("$.byStatus.SETTLED_IN_CASH.debits").value(500.00))
                .andExpect(jsonPath("$.byStatus.SETTLED_IN_CASH.credits").value(500.00))
                .andExpect(jsonPath("$.byStatus.PENDING.count").value(7))
                .andExpect(jsonPath("$.byStatus.FAILED.credits").value(35.00))
                .andExpect(jsonPath("$.byStatus.FAILED.debits").value(0))
                .andExpect(jsonPath("$.unsettledCount").value(8))
                // 165.63 + 35.00 on the credit side against 165.63 on the debit side: the larger,
                // never the 366.26 the two sides added up to.
                .andExpect(jsonPath("$.amountAtRisk").value(200.63))
                .andExpect(jsonPath("$.atRiskDebits").value(165.63))
                .andExpect(jsonPath("$.atRiskCredits").value(200.63));
    }

    @Test
    @DisplayName("a clean ledger is zero at risk, not an empty answer")
    void aCleanLedger() throws Exception {
        when(transactions.summariseByStatusAndDirection()).thenReturn(List.of(
                row(Status.SETTLED_IN_CASH, Direction.DEBIT, 20, "500.00"),
                row(Status.SETTLED_IN_CASH, Direction.CREDIT, 60, "500.00")));

        mvc.perform(get("/api/accounting/summary"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.unsettledCount").value(0))
                .andExpect(jsonPath("$.amountAtRisk").value(0))
                .andExpect(jsonPath("$.byStatus.PENDING").doesNotExist());
        // Nothing else is read for this view.
        org.mockito.Mockito.verify(transactions, org.mockito.Mockito.never())
                .findUnsettled(any());
    }
}
