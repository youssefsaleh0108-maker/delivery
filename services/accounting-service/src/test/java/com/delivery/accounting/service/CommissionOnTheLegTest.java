package com.delivery.accounting.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransaction.Leg;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.CounterpartyKind;
import com.delivery.accounting.domain.RiderLedgerRepository;
import com.delivery.accounting.domain.StatementDispatchRepository;

/**
 * RECON-05: what the platform charged is recorded on the leg it came out of, and read back.
 *
 * <p>{@link MerchantStatementBreakdownTest} pins the shop's half. This pins the rest of the
 * contract: that settlement writes the figure on every payee credit, that a carrier's statement can
 * therefore show its fees and the cut on an ordinary catalog order — where the platform's residue
 * holds the goods commission too, and nothing could be said before — and that an errand's rider is
 * charged on the fee and never on the goods they fronted.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("RECON-05: the commission is recorded where it was charged")
class CommissionOnTheLegTest {

    private static final String SHOP = "merchant-1";
    private static final String COMPANY = "provider-77";
    private static final String RIDER = "rider-1";

    @Mock
    private AccountingTransactionRepository transactions;
    @Mock
    private CashFloatRepository floats;
    @Mock
    private RiderLedgerRepository riderLedger;
    @Mock
    private StatementDispatchRepository dispatches;
    @Mock
    private CounterpartyDirectory directory;
    @Mock
    private BankPostingPublisher postings;

    private SettlementService settlement;
    private StatementService statements;

    @BeforeEach
    void setUp() {
        when(transactions.existsByOrderId(any())).thenReturn(false);
        when(floats.existsByOrderIdAndEntryKind(any(), any())).thenReturn(false);
        settlement = new SettlementService(transactions, floats, riderLedger, postings,
                new BigDecimal("12.5"), new BigDecimal("10"), "", "ACC-PLATFORM", "USD",
                SettlementService.SettlementMode.LEDGER_ONLY);
        statements = new StatementService(transactions, floats, riderLedger, dispatches, directory,
                new BigDecimal("12.5"), new BigDecimal("10"), "USD", "Asia/Beirut");
    }

    /** A catalog order a delivery company carried: 40.00 of goods and a 5.00 delivery fee. */
    private List<AccountingTransaction> catalogOrder() {
        return settlement.settle(UUID.randomUUID(), new BigDecimal("45.00"),
                new BigDecimal("40.00"), "ACC-CUSTOMER", "ACC-MERCHANT", "ACC-CARRIER",
                new SettlementService.CashHolder(RIDER, CashFloatEntry.HolderKind.RIDER, COMPANY),
                "corr",
                new SettlementService.Waivers(new BigDecimal("5.00"), false, false, false, null),
                new SettlementService.Rider(RIDER, "ACC-RIDER", COMPANY, "customer-1"),
                Instant.parse("2026-09-19T16:48:00Z"),
                new SettlementService.Parties(SHOP, COMPANY), null);
    }

    private static Map<Leg, AccountingTransaction> byLeg(List<AccountingTransaction> legs) {
        return legs.stream().collect(Collectors.toMap(AccountingTransaction::getLeg, l -> l));
    }

    @Test
    @DisplayName("each payee credit says what the platform charged it, and the legs are unchanged")
    void everyPayeeCreditCarriesItsCharge() {
        Map<Leg, AccountingTransaction> legs = byLeg(catalogOrder());

        // 12.5% of the goods, and 10% of the delivery fee — each beside the credit it came out of.
        assertThat(legs.get(Leg.MERCHANT_CREDIT).getAmount()).isEqualByComparingTo("35.00");
        assertThat(legs.get(Leg.MERCHANT_CREDIT).getCommissionAmount())
                .isEqualByComparingTo("5.00");
        assertThat(legs.get(Leg.PROVIDER_CREDIT).getAmount()).isEqualByComparingTo("4.50");
        assertThat(legs.get(Leg.PROVIDER_CREDIT).getCommissionAmount())
                .isEqualByComparingTo("0.50");
        // And the order still balances on its legs alone: 45.00 collected, 45.00 paid out.
        assertThat(legs.get(Leg.CASH_COLLECTED).getAmount()).isEqualByComparingTo("45.00");
        assertThat(legs.get(Leg.PLATFORM_COMMISSION).getAmount()).isEqualByComparingTo("5.50");
        assertThat(legs.get(Leg.CASH_COLLECTED).getCommissionAmount()).isNull();
        assertThat(legs.get(Leg.PLATFORM_COMMISSION).getCommissionAmount()).isNull();
    }

    @Test
    @DisplayName("a waived commission is a recorded zero, not an unanswered question")
    void aWaiverRecordsZero() {
        List<AccountingTransaction> legs = settlement.settle(UUID.randomUUID(),
                new BigDecimal("45.00"), new BigDecimal("40.00"), "ACC-CUSTOMER", "ACC-MERCHANT",
                "ACC-CARRIER", null, "corr",
                new SettlementService.Waivers(new BigDecimal("5.00"), false, true, true, null),
                null, Instant.parse("2026-09-19T16:48:00Z"),
                new SettlementService.Parties(SHOP, COMPANY), new BigDecimal("3.00"));

        Map<Leg, AccountingTransaction> byLeg = byLeg(legs);
        assertThat(byLeg.get(Leg.MERCHANT_CREDIT).getCommissionAmount())
                .isEqualByComparingTo("0.00");
        assertThat(byLeg.get(Leg.PROVIDER_CREDIT).getCommissionAmount())
                .isEqualByComparingTo("0.00");
        // Wrapping is never commissioned, and says so rather than staying silent.
        assertThat(byLeg.get(Leg.GIFT_WRAP_CREDIT).getCommissionAmount())
                .isEqualByComparingTo("0.00");
    }

    @Test
    @DisplayName("an errand's rider is charged on the fee, never on the goods they fronted")
    void anErrandIsChargedOnItsFee() {
        // 20.00 of goods the rider bought plus a 3.50 errand fee: the platform takes 12.5% of the
        // fee, and the rider is reimbursed in full.
        List<AccountingTransaction> legs = settlement.settleErrand(UUID.randomUUID(),
                new BigDecimal("23.50"), new BigDecimal("20.00"), "ACC-CUSTOMER", "ACC-RIDER",
                null, "corr", new SettlementService.Rider(RIDER, "ACC-RIDER", null, "customer-1"),
                Instant.parse("2026-09-19T16:48:00Z"));

        Map<Leg, AccountingTransaction> byLeg = byLeg(legs);
        assertThat(byLeg.get(Leg.RIDER_CREDIT).getAmount()).isEqualByComparingTo("23.06");
        assertThat(byLeg.get(Leg.RIDER_CREDIT).getCommissionAmount()).isEqualByComparingTo("0.44");
    }

    @Test
    @DisplayName("a carrier's statement shows its fees and the cut on an ordinary catalog order")
    void theCarrierStatementReadsItBack() {
        List<AccountingTransaction> legs = catalogOrder();
        List<AccountingTransaction> own = legs.stream()
                .filter(t -> t.getCounterpartyKind() == CounterpartyKind.CARRIER)
                .toList();
        when(transactions.legsForCounterparty(eq(CounterpartyKind.CARRIER), eq(COMPANY), any(),
                any())).thenReturn(own);
        when(transactions.findByOrderIdIn(anyCollection())).thenReturn(legs);
        LocalDate day = LocalDate.parse("2026-09-19");

        Statement statement = statements.build(CounterpartyKind.CARRIER, COMPANY,
                StatementRange.of(day, day, ZoneId.of("Asia/Beirut")));

        Map<String, BigDecimal> lines = statement.lines().stream()
                .collect(Collectors.toMap(Statement.Line::label, Statement.Line::amount));
        // A shop was paid on this order too, so nothing could be said about the cut before.
        assertThat(lines).containsEntry("Delivery fees", new BigDecimal("5.00"))
                .containsEntry("Platform commission (10%)", new BigDecimal("0.50"));
        assertThat(statement.net().amount()).isEqualByComparingTo("4.50");
        assertThat(statement.note() == null ? "" : statement.note())
                .doesNotContain("cannot be split");
        assertThat(statement.entries().get(0).gross()).isEqualByComparingTo("5.00");
        assertThat(statement.entries().get(0).commission()).isEqualByComparingTo("0.50");
    }
}
