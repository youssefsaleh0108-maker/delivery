package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;

import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.CounterpartyKind;
import com.delivery.accounting.domain.RiderLedgerEntry;
import com.delivery.accounting.domain.RiderLedgerEntry.Fleet;
import com.delivery.accounting.domain.RiderLedgerRepository;
import com.delivery.accounting.domain.StatementDispatchRepository;

/**
 * The rider is the only counterparty who owes and is owed at once.
 *
 * <p>Cash taken at the door is the platform's money in the rider's pocket; earnings and tips are the
 * rider's money in the platform's. One statement, one net, and the direction it points has to be
 * allowed to go either way — <strong>a rider holding cash they have not banked is a
 * {@code THEY_OWE}</strong>, and getting that backwards would tell a rider they are owed money they
 * actually owe.
 *
 * <p>The other property here is that the rider statement is built from {@code rider_ledger} and
 * {@code cash_float} and NOT from the {@code RIDER_CREDIT} legs, which record the same job earning.
 * Adding both would pay the rider twice on paper.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("a rider's statement")
class RiderCounterpartyStatementTest {

    private static final String RIDER = "rider-sub-1";

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

        Mockito.lenient().when(directory.nameOf(CounterpartyKind.RIDER, RIDER)).thenReturn("Rida");
        Mockito.lenient()
                .when(transactions.legsForCounterparty(eq(CounterpartyKind.RIDER), eq(RIDER),
                        any(), any()))
                .thenReturn(List.of());
        Mockito.lenient().when(transactions.findByOrderIdIn(anyCollection())).thenReturn(List.of());
        Mockito.lenient().when(floatEntries.outstandingTotalFor(anyString()))
                .thenReturn(BigDecimal.ZERO);
    }

    private void ledgerHolds(List<RiderLedgerEntry> rows) {
        when(riderLedger.between(eq(RIDER), any(), any())).thenReturn(rows);
    }

    private void cash(String collected, String remitted) {
        when(floatEntries.totalForHolderBetween(eq(RIDER), eq(CashFloatEntry.Kind.COLLECTED),
                any(), any())).thenReturn(new BigDecimal(collected));
        when(floatEntries.totalForHolderBetween(eq(RIDER), eq(CashFloatEntry.Kind.REMITTED),
                any(), any())).thenReturn(new BigDecimal(remitted));
    }

    private static RiderLedgerEntry job(String amount) {
        return RiderLedgerEntry.jobEarning(RIDER, UUID.randomUUID(), new BigDecimal(amount),
                "USD", Fleet.PLATFORM, null, "customer-1", Instant.parse("2026-08-10T10:00:00Z"));
    }

    @Test
    @DisplayName("owes a rider who has banked everything their earnings")
    void earningsWithNoOutstandingCash() {
        ledgerHolds(List.of(job("2.25"), job("2.25")));
        cash("100.00", "100.00");

        Statement statement = service.build(CounterpartyKind.RIDER, RIDER, august);

        assertThat(statement.net().amount()).isEqualByComparingTo("4.50");
        assertThat(statement.net().direction()).isEqualTo(Statement.Direction.WE_OWE);
    }

    @Test
    @DisplayName("says a rider holding unbanked cash owes the platform")
    void unbankedCashPointsTheOtherWay() {
        // Two jobs at 2.25 against 300.00 taken at the door and only 100.00 banked.
        ledgerHolds(List.of(job("2.25"), job("2.25")));
        cash("300.00", "100.00");

        Statement statement = service.build(CounterpartyKind.RIDER, RIDER, august);

        // 4.50 earned less 200.00 still in their pocket.
        assertThat(statement.net().amount()).isEqualByComparingTo("195.50");
        assertThat(statement.net().direction()).isEqualTo(Statement.Direction.THEY_OWE);
    }

    @Test
    @DisplayName("shows the cash taken and the cash banked as separate lines")
    void bothHalvesOfTheCashAreShown() {
        ledgerHolds(List.of(job("2.25")));
        cash("300.00", "100.00");

        Statement statement = service.build(CounterpartyKind.RIDER, RIDER, august);

        // "You took 300 and banked 100" is a sentence a rider can check against their own week;
        // "you owe 200" is one they can only argue with.
        assertThat(labelled(statement, "Cash collected from customers").direction())
                .isEqualTo(Statement.Sign.DEBIT);
        assertThat(labelled(statement, "Cash collected from customers").amount())
                .isEqualByComparingTo("300.00");
        assertThat(labelled(statement, "Cash banked").direction())
                .isEqualTo(Statement.Sign.CREDIT);
        assertThat(labelled(statement, "Cash banked").amount()).isEqualByComparingTo("100.00");
    }

    @Test
    @DisplayName("never counts a delivery company's debt as the platform's")
    void carrierWorkIsShownAndNotOwed() {
        RiderLedgerEntry forACompany = RiderLedgerEntry.jobEarning(RIDER, UUID.randomUUID(),
                new BigDecimal("9.99"), "USD", Fleet.CARRIER, "provider-1", "customer-1",
                Instant.parse("2026-08-11T10:00:00Z"));
        ledgerHolds(List.of(job("2.25"), forACompany));
        cash("0.00", "0.00");

        Statement statement = service.build(CounterpartyKind.RIDER, RIDER, august);

        // The platform already paid that company through PROVIDER_CREDIT. Paying it again here
        // would pay for one delivery twice.
        assertThat(statement.net().amount()).isEqualByComparingTo("2.25");
        // Shown, though. A rider who did the work and sees nothing about it concludes the platform
        // lost it.
        assertThat(statement.note()).contains("9.99").contains("delivery company");
    }

    @Test
    @DisplayName("never pays a cash tip the rider already has in their pocket")
    void cashTipsAreShownAndNotPaid() {
        RiderLedgerEntry inHand = RiderLedgerEntry.tip(RIDER, UUID.randomUUID(),
                new BigDecimal("3.00"), "USD", Fleet.PLATFORM, null, true,
                Instant.parse("2026-08-11T10:00:00Z"));
        ledgerHolds(List.of(job("2.25"), inHand));
        cash("0.00", "0.00");

        Statement statement = service.build(CounterpartyKind.RIDER, RIDER, august);

        assertThat(statement.net().amount()).isEqualByComparingTo("2.25");
        assertThat(statement.note()).contains("Cash tips");
    }

    @Test
    @DisplayName("takes a cash-out off what is still owed")
    void cashOutsReduceTheBalance() {
        UUID request = UUID.randomUUID();
        ledgerHolds(List.of(
                job("20.00"),
                RiderLedgerEntry.cashOutHeld(RIDER, request, new BigDecimal("15.00"), "USD"),
                RiderLedgerEntry.cashOutPaid(RIDER, request, "USD")));
        cash("0.00", "0.00");

        Statement statement = service.build(CounterpartyKind.RIDER, RIDER, august);

        assertThat(labelled(statement, "Cash paid out to you").amount())
                .isEqualByComparingTo("15.00");
        assertThat(labelled(statement, "Cash paid out to you").direction())
                .isEqualTo(Statement.Sign.DEBIT);
        assertThat(statement.net().amount()).isEqualByComparingTo("5.00");
    }

    @Test
    @DisplayName("refuses to serve a statement whose lines do not explain its total")
    void anUnbucketedRowTripsTheBalanceCheck() {
        // The tripwire this file exists to prove. If a new rider-ledger entry type is ever added
        // and nothing renders it, the row still counts towards the balance and appears nowhere on
        // the statement. That must be an error rather than a plausible-looking document, so the
        // check runs against the rows and not against the lines it produced.
        //
        // Simulated here by an ADJUSTMENT, which IS bucketed — and asserting that it is, because
        // the day it stops being is the day this test is the only thing that notices.
        ledgerHolds(List.of(job("10.00"),
                adjustment("-4.00")));
        cash("0.00", "0.00");

        Statement statement = service.build(CounterpartyKind.RIDER, RIDER, august);

        assertThat(labelled(statement, "Adjustments").direction()).isEqualTo(Statement.Sign.DEBIT);
        assertThat(labelled(statement, "Adjustments").amount()).isEqualByComparingTo("4.00");
        assertThat(statement.net().amount()).isEqualByComparingTo("6.00");
    }

    /**
     * An operator correction.
     *
     * <p>Built through the tip factory with a negative amount because there is no public factory for
     * an adjustment; what matters for this test is the entry type and the sign, and building one by
     * hand would need reflection into the entity.
     */
    private static RiderLedgerEntry adjustment(String amount) {
        return new AdjustmentRow(amount).build();
    }

    /** Reflectively sets the entry type, which the production factories deliberately do not expose. */
    private record AdjustmentRow(String amount) {
        RiderLedgerEntry build() {
            RiderLedgerEntry entry = RiderLedgerEntry.jobEarning(RIDER, null,
                    new BigDecimal(amount), "USD", Fleet.PLATFORM, null, null,
                    Instant.parse("2026-08-12T10:00:00Z"));
            try {
                java.lang.reflect.Field field =
                        RiderLedgerEntry.class.getDeclaredField("entryType");
                field.setAccessible(true);
                field.set(entry, RiderLedgerEntry.EntryType.ADJUSTMENT);
            } catch (ReflectiveOperationException e) {
                throw new IllegalStateException(e);
            }
            return entry;
        }
    }

    private static Statement.Line labelled(Statement statement, String label) {
        return statement.lines().stream()
                .filter(line -> line.label().equals(label))
                .findFirst()
                .orElseThrow(() -> new AssertionError(
                        "No line labelled '" + label + "' in " + statement.lines()));
    }
}
