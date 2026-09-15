package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.CounterpartyKind;
import com.delivery.accounting.domain.RiderLedgerRepository;
import com.delivery.accounting.domain.StatementDispatchRepository;

/**
 * Statements after a delivery company takes custody of its riders' cash.
 *
 * <p>The balance property of every statement still holds — the lines sum to the ledger, or the
 * statement is refused — and this file is about both sides of a hand-over reading truthfully. The
 * rider's cash left their pocket, so their statement is square on it; it did not reach the platform,
 * so the line says it went to their company and not "banked". The company's statement shows the
 * cash it took and what it paid, so a company holding the platform's money reads as owing it.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("statements under carrier custody")
class CustodyStatementTest {

    private static final String RIDER = "rider-sub-1";
    private static final String COMPANY = "provider-77";

    @Mock
    private AccountingTransactionRepository transactions;
    @Mock
    private CashFloatRepository floatEntries;
    @Mock
    private RiderLedgerRepository riderLedger;
    @Mock
    private StatementDispatchRepository dispatches;
    @Mock
    private CounterpartyDirectory directory;

    private StatementService service;
    private StatementRange october;

    @BeforeEach
    void setUp() {
        service = new StatementService(transactions, floatEntries, riderLedger, dispatches,
                directory, new BigDecimal("12.5"), "USD", "UTC");
        october = StatementRange.of(LocalDate.parse("2026-10-01"), LocalDate.parse("2026-10-24"),
                ZoneId.of("UTC"));
        lenient().when(transactions.findByOrderIdIn(anyCollection())).thenReturn(List.of());
        lenient().when(directory.nameOf(any(), any())).thenReturn("Somebody");
    }

    @Nested
    @DisplayName("a delivery company's rider")
    class Rider {

        @BeforeEach
        void rows() {
            lenient().when(transactions.legsForCounterparty(eq(CounterpartyKind.RIDER), eq(RIDER),
                    any(), any())).thenReturn(List.of());
            lenient().when(riderLedger.between(eq(RIDER), any(), any())).thenReturn(List.of());
            // 485.00 on the company's jobs, 20.00 on a platform-fleet shift.
            when(floatEntries.forHolderBetween(eq(RIDER), eq(CashFloatEntry.HolderKind.RIDER),
                    eq(CashFloatEntry.Kind.COLLECTED),
                    any(), any())).thenReturn(List.of(
                    CashFloatEntry.collected(RIDER, CashFloatEntry.HolderKind.RIDER,
                            UUID.randomUUID(), new BigDecimal("485.00"), "USD", COMPANY),
                    CashFloatEntry.collected(RIDER, CashFloatEntry.HolderKind.RIDER,
                            UUID.randomUUID(), new BigDecimal("20.00"), "USD")));
            when(floatEntries.totalForHolderBetween(eq(RIDER), eq(CashFloatEntry.HolderKind.RIDER),
                    eq(CashFloatEntry.Kind.REMITTED),
                    any(), any())).thenReturn(new BigDecimal("20.00"));
            lenient().when(floatEntries.outstandingTotalFor(RIDER, CashFloatEntry.HolderKind.RIDER))
                    .thenReturn(BigDecimal.ZERO);
        }

        @Test
        @DisplayName("is square once they hand the company its cash, and the line says to whom")
        void squareAfterHandingOver() {
            when(floatEntries.handedOverBetween(eq(RIDER), any(), any()))
                    .thenReturn(new BigDecimal("485.00"));

            Statement statement = service.build(CounterpartyKind.RIDER, RIDER, october);

            assertThat(statement.net().direction()).isEqualTo(Statement.Direction.SETTLED);
            assertThat(statement.lines()).anySatisfy(line -> {
                assertThat(line.label()).isEqualTo("Cash handed to your delivery company");
                assertThat(line.amount()).isEqualByComparingTo("485.00");
                assertThat(line.direction()).isEqualTo(Statement.Sign.CREDIT);
            });
            // And "banked" is only what reached the platform.
            assertThat(statement.lines()).anySatisfy(line -> {
                assertThat(line.label()).isEqualTo("Cash banked");
                assertThat(line.amount()).isEqualByComparingTo("20.00");
            });
        }

        @Test
        @DisplayName("before handing over still holds it, and is told the company is who to pay")
        void holdingForTheCompany() {
            when(floatEntries.handedOverBetween(eq(RIDER), any(), any()))
                    .thenReturn(BigDecimal.ZERO);

            Statement statement = service.build(CounterpartyKind.RIDER, RIDER, october);

            assertThat(statement.net().amount()).isEqualByComparingTo("485.00");
            assertThat(statement.net().direction()).isEqualTo(Statement.Direction.THEY_OWE);
            assertThat(statement.lines())
                    .noneMatch(line -> line.label().startsWith("Cash handed to"));
            assertThat(statement.note()).contains("485.00 USD")
                    .contains("jobs for your delivery company")
                    .contains("owed to your company");
        }
    }

    /**
     * The path V50 must not have moved: a rider of the platform's own fleet, whose cash is owed to
     * the platform and banked with it.
     */
    @Nested
    @DisplayName("a rider on the platform's own fleet")
    class PlatformRider {

        @Test
        @DisplayName("reads exactly as before: banked cash squares it, and no company is mentioned")
        void unchanged() {
            when(transactions.legsForCounterparty(eq(CounterpartyKind.RIDER), eq(RIDER), any(),
                    any())).thenReturn(List.of());
            when(riderLedger.between(eq(RIDER), any(), any())).thenReturn(List.of());
            when(floatEntries.forHolderBetween(eq(RIDER), eq(CashFloatEntry.HolderKind.RIDER),
                    eq(CashFloatEntry.Kind.COLLECTED),
                    any(), any())).thenReturn(List.of(
                    CashFloatEntry.collected(RIDER, CashFloatEntry.HolderKind.RIDER,
                            UUID.randomUUID(), new BigDecimal("20.00"), "USD")));
            when(floatEntries.totalForHolderBetween(eq(RIDER), eq(CashFloatEntry.HolderKind.RIDER),
                    eq(CashFloatEntry.Kind.REMITTED),
                    any(), any())).thenReturn(new BigDecimal("20.00"));
            when(floatEntries.handedOverBetween(eq(RIDER), any(), any()))
                    .thenReturn(BigDecimal.ZERO);
            when(floatEntries.outstandingTotalFor(RIDER, CashFloatEntry.HolderKind.RIDER))
                    .thenReturn(BigDecimal.ZERO);

            Statement statement = service.build(CounterpartyKind.RIDER, RIDER, october);

            assertThat(statement.net().direction()).isEqualTo(Statement.Direction.SETTLED);
            assertThat(statement.lines()).extracting(Statement.Line::label)
                    .containsExactly("Cash collected from customers", "Cash banked");
            assertThat(statement.note()).isNull();
        }
    }

    @Nested
    @DisplayName("the delivery company")
    class Company {

        @BeforeEach
        void fees() {
            UUID job = UUID.randomUUID();
            when(transactions.legsForCounterparty(eq(CounterpartyKind.CARRIER), eq(COMPANY),
                    any(), any())).thenReturn(List.of(Legs.providerCredit(job, "5.85", COMPANY)));
        }

        @Test
        @DisplayName("shows the cash it took and what it paid, and owes the difference")
        void custodyLines() {
            when(floatEntries.custodyReceivedBetween(eq(COMPANY), any(), any()))
                    .thenReturn(new BigDecimal("485.00"));
            when(floatEntries.carrierPaidBetween(eq(COMPANY), any(), any()))
                    .thenReturn(new BigDecimal("400.00"));
            when(floatEntries.outstandingTotalFor(COMPANY, CashFloatEntry.HolderKind.PROVIDER))
                    .thenReturn(new BigDecimal("85.00"));

            Statement statement = service.build(CounterpartyKind.CARRIER, COMPANY, october);

            // 5.85 in fees, 485.00 taken into custody, 400.00 paid: the company owes 79.15.
            assertThat(statement.net().amount()).isEqualByComparingTo("79.15");
            assertThat(statement.net().direction()).isEqualTo(Statement.Direction.THEY_OWE);
            assertThat(statement.lines()).extracting(Statement.Line::label).containsExactly(
                    "Delivery fees", "Cash handed over by your riders",
                    "Cash paid to the platform");
            // What it holds is exactly this period's difference, so there is nothing more to say.
            assertThat(statement.note() == null ? "" : statement.note())
                    .doesNotContain("is holding");
        }

        @Test
        @DisplayName("says so when it still holds cash from before the period")
        void olderCustodyIsNoted() {
            when(floatEntries.custodyReceivedBetween(eq(COMPANY), any(), any()))
                    .thenReturn(new BigDecimal("485.00"));
            when(floatEntries.carrierPaidBetween(eq(COMPANY), any(), any()))
                    .thenReturn(new BigDecimal("485.00"));
            when(floatEntries.outstandingTotalFor(COMPANY, CashFloatEntry.HolderKind.PROVIDER))
                    .thenReturn(new BigDecimal("120.00"));

            Statement statement = service.build(CounterpartyKind.CARRIER, COMPANY, october);

            assertThat(statement.net().amount()).isEqualByComparingTo("5.85");
            assertThat(statement.note()).contains("holding 120.00 USD");
        }

        @Test
        @DisplayName("a company that never took custody reads exactly as before")
        void noCustodyNoChange() {
            Statement statement = service.build(CounterpartyKind.CARRIER, COMPANY, october);

            assertThat(statement.lines()).extracting(Statement.Line::label)
                    .containsExactly("Delivery fees");
            assertThat(statement.net().amount()).isEqualByComparingTo("5.85");
            assertThat(statement.net().direction()).isEqualTo(Statement.Direction.WE_OWE);
        }
    }
}
