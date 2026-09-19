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
import java.util.ArrayList;
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
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.CounterpartyKind;
import com.delivery.accounting.domain.RiderLedgerRepository;
import com.delivery.accounting.domain.StatementDispatchRepository;

/**
 * RECON-05: a shop's statement calls the platform's whole residue "commission".
 *
 * <p>The two orders are the ones placed on dev on 2026-09-19 (B1 and B2 of the deep test), settled
 * here by the real {@link SettlementService} and read back by the real {@link StatementService}:
 *
 * <ul>
 *   <li>8.25 of goods, EXPRESS (+2.00, platform revenue), a 1.00 code: the customer paid 9.25, the
 *       shop is owed 7.22, the platform kept 2.03 — its 1.03 commission, plus the 2.00 premium, less
 *       the 1.00 it gave away.</li>
 *   <li>8.25 of goods and a code worth the whole bill: the customer paid nothing, the shop is still
 *       owed 7.22, and the platform paid 7.22 in.</li>
 * </ul>
 *
 * <p>On each order the shop sold 8.25 of goods and was charged 12.5% of it, 1.03. The statement's
 * net (7.22) is right, but its breakdown is not read from the goods: {@code
 * StatementService.platformTake} uses COMMISSION − SUBSIDY on the order, so the express premium the
 * customer paid and the promotion the platform funded are both presented to the shop as its
 * commission, and "Goods sold" becomes net + that residue. On dev the September statement said
 * "Goods sold 311.71, Platform commission (12.5%) 19.45" while the shop sold 332.63 of goods and was
 * charged 40.37 of commission.
 *
 * <p>Fails until the statement reads goods and commission from what the order was — for instance by
 * settling the goods commission into a leg of its own, apart from express and promotions.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("RECON-05: a shop's statement shows its goods and the commission it was charged")
class MerchantStatementBreakdownTest {

    private static final String SHOP = "09e87c60-93e5-4654-ad4b-69310cdab8fe";

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
    private final List<AccountingTransaction> ledger = new ArrayList<>();

    @BeforeEach
    void setUp() {
        when(transactions.existsByOrderId(any())).thenReturn(false);
        when(floats.existsByOrderIdAndEntryKind(any(), any())).thenReturn(false);
        settlement = new SettlementService(transactions, floats, riderLedger, postings,
                new BigDecimal("12.5"), new BigDecimal("10"), "", "ACC-PLATFORM", "USD",
                SettlementService.SettlementMode.LEDGER_ONLY);
        statements = new StatementService(transactions, floats, riderLedger, dispatches, directory,
                new BigDecimal("12.5"), "USD", "UTC");
    }

    /** An own-fleet catalog order with no delivery fee, paid in cash to the rider, as on dev. */
    private void settle(String total, String subtotal, String discount) {
        ledger.addAll(settlement.settle(UUID.randomUUID(), new BigDecimal(total),
                new BigDecimal(subtotal), "ACC-CUSTOMER", "ACC-MERCHANT", null,
                new SettlementService.CashHolder("rider-1", CashFloatEntry.HolderKind.RIDER),
                "corr", new SettlementService.Waivers(BigDecimal.ZERO.setScale(2), false, false,
                        false, new BigDecimal(discount)),
                new SettlementService.Rider("rider-1", "ACC-RIDER", null, "customer-1"),
                Instant.parse("2026-09-19T16:48:00Z"),
                new SettlementService.Parties(SHOP, null), null));
    }

    private Statement statement() {
        List<AccountingTransaction> own = ledger.stream()
                .filter(t -> t.getCounterpartyKind() == CounterpartyKind.MERCHANT)
                .toList();
        when(transactions.legsForCounterparty(eq(CounterpartyKind.MERCHANT), eq(SHOP), any(), any()))
                .thenReturn(own);
        when(transactions.findByOrderIdIn(anyCollection())).thenReturn(ledger);
        when(floats.heldBy(SHOP, CashFloatEntry.HolderKind.MERCHANT)).thenReturn(List.of());
        LocalDate day = LocalDate.parse("2026-09-19");
        return statements.build(CounterpartyKind.MERCHANT, SHOP,
                StatementRange.of(day, day, ZoneId.of("UTC")));
    }

    private static Map<String, BigDecimal> lines(Statement statement) {
        return statement.lines().stream()
                .collect(Collectors.toMap(Statement.Line::label, Statement.Line::amount));
    }

    @Test
    @DisplayName("an express order with a code: goods sold 8.25, commission 1.03")
    void expressAndACode() {
        settle("9.25", "8.25", "1.00");

        Statement statement = statement();

        assertThat(statement.net().amount()).isEqualByComparingTo("7.22");
        // What the shop sold, and the 12.5% it was charged on it.
        assertThat(lines(statement)).as("statement lines")
                .containsEntry("Goods sold", new BigDecimal("8.25"))
                .containsEntry("Platform commission (12.5%)", new BigDecimal("1.03"));
    }

    @Test
    @DisplayName("an order a code paid in full: goods sold 8.25, commission 1.03, no contribution")
    void aCodeWorthTheWholeBill() {
        settle("0.00", "8.25", "8.25");

        Statement statement = statement();

        assertThat(statement.net().amount()).isEqualByComparingTo("7.22");
        assertThat(lines(statement)).as("statement lines")
                .containsEntry("Goods sold", new BigDecimal("8.25"))
                .containsEntry("Platform commission (12.5%)", new BigDecimal("1.03"))
                .doesNotContainKey("Platform contribution");
        // And the order's own row says the same: 8.25 sold, 1.03 commission, 7.22 to the shop.
        Statement.Entry row = statement.entries().get(0);
        assertThat(row.gross()).as("row gross").isEqualByComparingTo("8.25");
        assertThat(row.commission()).as("row commission").isEqualByComparingTo("1.03");
    }
}
