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
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.CounterpartyKind;
import com.delivery.accounting.domain.RiderLedgerRepository;
import com.delivery.accounting.domain.StatementDispatchRepository;

/**
 * The two kinds whose arithmetic runs differently from a shop's.
 *
 * <p>A carrier is paid delivery fees on jobs whose goods it never touched, and the leg it is paid on
 * is already net of the platform's cut. The platform's own statement runs the other way round from
 * all three of the others: its commission is money owed TO it, so the same sign convention that
 * makes a merchant statement {@code WE_OWE} makes the platform's {@code THEY_OWE} without a special
 * case anywhere.
 */
@ExtendWith(MockitoExtension.class)
class CarrierAndPlatformStatementTest {

    private static final String CARRIER = "provider-uuid-1";
    private static final String MERCHANT = "merchant-sub-1";

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
    private StatementRange august;

    @BeforeEach
    void setUp() {
        service = new StatementService(transactions, floatEntries, riderLedger, dispatches,
                directory, new BigDecimal("12.5"), "USD", "UTC");
        august = StatementRange.of(LocalDate.parse("2026-08-01"), LocalDate.parse("2026-08-29"),
                ZoneId.of("UTC"));
        Mockito.lenient().when(transactions.findByOrderIdIn(anyCollection()))
                .thenReturn(List.of());
    }

    private void own(CounterpartyKind kind, String ref, List<AccountingTransaction> legs) {
        when(transactions.legsForCounterparty(eq(kind), eq(ref), any(), any())).thenReturn(legs);
        Mockito.lenient().when(directory.nameOf(kind, ref)).thenReturn(ref);
    }

    @Nested
    @DisplayName("a delivery company's statement")
    class Carrier {

        @Test
        @DisplayName("owes the company its delivery fees, already net of the platform's cut")
        void feesAreNetOfTheCut() {
            UUID one = UUID.randomUUID();
            UUID two = UUID.randomUUID();
            own(CounterpartyKind.CARRIER, CARRIER, List.of(
                    Legs.providerCredit(one, "2.25", CARRIER),
                    Legs.providerCredit(two, "3.60", CARRIER)));
            when(transactions.findByOrderIdIn(anyCollection())).thenReturn(List.of(
                    Legs.merchantCredit(one, "35.00", MERCHANT),
                    Legs.providerCredit(one, "2.25", CARRIER),
                    Legs.commission(one, "5.25"),
                    Legs.merchantCredit(two, "5.25", MERCHANT),
                    Legs.providerCredit(two, "3.60", CARRIER),
                    Legs.subsidy(two, "2.85")));

            Statement statement = service.build(CounterpartyKind.CARRIER, CARRIER, august);

            assertThat(statement.net().amount()).isEqualByComparingTo("5.85");
            assertThat(statement.net().direction()).isEqualTo(Statement.Direction.WE_OWE);
            assertThat(statement.lines()).hasSize(1);
            assertThat(statement.lines().get(0).label()).isEqualTo("Delivery fees");
            assertThat(statement.lines().get(0).note()).isEqualTo("2 jobs");
            // Both orders also paid a shop, so the platform's leg cannot be split between goods and
            // delivery — and the statement says so rather than showing an invented commission line.
            assertThat(statement.note()).contains("cannot be split");
        }

        @Test
        @DisplayName("does show the platform's cut on a job the company alone was paid for")
        void aDeliveryOnlyJobCanBeSplit() {
            UUID solo = UUID.randomUUID();
            own(CounterpartyKind.CARRIER, CARRIER, List.of(
                    Legs.providerCredit(solo, "4.50", CARRIER)));
            when(transactions.findByOrderIdIn(anyCollection())).thenReturn(List.of(
                    Legs.cashCollected(solo, "5.00", "rider-1"),
                    Legs.providerCredit(solo, "4.50", CARRIER),
                    Legs.commission(solo, "0.50")));

            Statement statement = service.build(CounterpartyKind.CARRIER, CARRIER, august);

            assertThat(statement.lines()).hasSize(2);
            assertThat(statement.lines().get(0).amount()).isEqualByComparingTo("5.00");
            assertThat(statement.lines().get(1).amount()).isEqualByComparingTo("0.50");
            assertThat(statement.net().amount()).isEqualByComparingTo("4.50");
        }
    }

    @Nested
    @DisplayName("the platform's own statement")
    class Platform {

        @BeforeEach
        void noCash() {
            Mockito.lenient()
                    .when(floatEntries.totalBetween(any(CashFloatEntry.Kind.class), any(), any()))
                    .thenReturn(BigDecimal.ZERO);
            Mockito.lenient().when(floatEntries.outstandingTotal()).thenReturn(BigDecimal.ZERO);
        }

        @Test
        @DisplayName("is owed its commission, less what it gave away")
        void commissionLessSubsidies() {
            UUID one = UUID.randomUUID();
            UUID two = UUID.randomUUID();
            own(CounterpartyKind.PLATFORM, CounterpartyKind.PLATFORM_REF, List.of(
                    Legs.commission(one, "12.50"),
                    Legs.subsidy(two, "2.85")));

            Statement statement = service.build(
                    CounterpartyKind.PLATFORM, CounterpartyKind.PLATFORM_REF, august);

            // THEY_OWE: everybody else owes the platform its cut, which on a cash platform is
            // literally true — the money is in riders' pockets.
            assertThat(statement.net().amount()).isEqualByComparingTo("9.65");
            assertThat(statement.net().direction()).isEqualTo(Statement.Direction.THEY_OWE);
            assertThat(statement.lines()).hasSize(2);
            assertThat(statement.lines().get(0).direction()).isEqualTo(Statement.Sign.DEBIT);
            assertThat(statement.lines().get(1).direction()).isEqualTo(Statement.Sign.CREDIT);
        }

        @Test
        @DisplayName("says a loss-making period the right way round")
        void aSubsidisedPeriodIsWeOwe() {
            UUID one = UUID.randomUUID();
            own(CounterpartyKind.PLATFORM, CounterpartyKind.PLATFORM_REF, List.of(
                    Legs.commission(one, "1.00"),
                    Legs.subsidy(one, "10.00")));

            Statement statement = service.build(
                    CounterpartyKind.PLATFORM, CounterpartyKind.PLATFORM_REF, august);

            assertThat(statement.net().amount()).isEqualByComparingTo("9.00");
            assertThat(statement.net().direction()).isEqualTo(Statement.Direction.WE_OWE);
        }
    }

    @Test
    @DisplayName("reports outstanding cash without adding it to what the platform is owed")
    void outstandingCashIsStatedNotAdded() {
        UUID one = UUID.randomUUID();
        own(CounterpartyKind.PLATFORM, CounterpartyKind.PLATFORM_REF,
                List.of(Legs.commission(one, "12.50")));
        when(floatEntries.totalBetween(eq(CashFloatEntry.Kind.COLLECTED), any(), any()))
                .thenReturn(new BigDecimal("2425.00"));
        when(floatEntries.totalBetween(eq(CashFloatEntry.Kind.REMITTED), any(), any()))
                .thenReturn(BigDecimal.ZERO);
        when(floatEntries.outstandingTotal()).thenReturn(new BigDecimal("2425.00"));

        Statement statement = service.build(
                CounterpartyKind.PLATFORM, CounterpartyKind.PLATFORM_REF, august);

        // The commission is INSIDE the notes the riders are holding. Adding both would overstate
        // what the platform is owed by its own commission on every unbanked order.
        assertThat(statement.net().amount()).isEqualByComparingTo("12.50");
        assertThat(statement.note()).contains("2425.00").contains("count the same money twice");
    }
}
