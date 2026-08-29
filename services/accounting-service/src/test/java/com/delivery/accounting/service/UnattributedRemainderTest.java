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
import com.delivery.accounting.domain.CounterpartyKind;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.RiderLedgerRepository;
import com.delivery.accounting.domain.StatementDispatch;
import com.delivery.accounting.domain.StatementDispatchRepository;

/**
 * The money that belongs to nobody, reported rather than quietly dropped.
 *
 * <p>This is the honest half of the change. Every leg written before attribution shipped has no
 * counterparty and no migration can give it one — the identity survives only in Order Manager's
 * schema, which this service's database role may not even be able to read. A counterparties listing
 * that showed two shops and a few hundred dollars while the ledger held two and a half thousand
 * would be read as the platform having done almost no business.
 *
 * <p>So the listing carries the number. It is closed and can only shrink: no new order joins it.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("the counterparties listing")
class UnattributedRemainderTest {

    private static final String SHOP = "merchant-sub-1";

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
    }

    private void unattributed(String amount, long orders) {
        when(transactions.unattributedTotal(
                eq(AccountingTransactionRepository.PAYEE_LEGS), any(), any()))
                .thenReturn(List.<Object[]>of(new Object[] {new BigDecimal(amount), orders}));
    }

    @Test
    @DisplayName("names the amount and the order count that cannot be assigned")
    void reportsTheRemainder() {
        when(transactions.activeCounterparties(any(), any())).thenReturn(List.of());
        // The production database tonight: 45 delivered orders, 2121.80 of merchant credits, and
        // not one of them attributable to a shop.
        unattributed("2121.80", 45);

        StatementService.Counterparties listing = service.list(august);

        assertThat(listing.counterparties()).isEmpty();
        assertThat(listing.unattributed().amount()).isEqualByComparingTo("2121.80");
        assertThat(listing.unattributed().orders()).isEqualTo(45);
        assertThat(listing.unattributed().note())
                .contains("cannot be assigned")
                .contains("Order Manager");
    }

    @Test
    @DisplayName("says so plainly when everything in the period is attributed")
    void aClearRemainderIsStated() {
        when(transactions.activeCounterparties(any(), any())).thenReturn(List.of());
        unattributed("0.00", 0);

        StatementService.Counterparties listing = service.list(august);

        assertThat(listing.unattributed().amount()).isEqualByComparingTo("0.00");
        assertThat(listing.unattributed().orders()).isZero();
        // Silence would be ambiguous: no note reads the same as no data.
        assertThat(listing.unattributed().note()).contains("attributed to a counterparty");
    }

    @Test
    @DisplayName("counts only legs that pay somebody, so the figure can reach zero")
    void onlyPayeeLegsCount() {
        when(transactions.activeCounterparties(any(), any())).thenReturn(List.of());
        unattributed("0.00", 0);

        service.list(august);

        // A CUSTOMER_DEBIT has no counterparty by design. Counting it would leave a number that is
        // supposed to fall to zero permanently above it, and a number that never improves is one
        // nobody looks at twice.
        assertThat(AccountingTransactionRepository.PAYEE_LEGS)
                .doesNotContain(com.delivery.accounting.domain.AccountingTransaction.Leg.CUSTOMER_DEBIT)
                .doesNotContain(com.delivery.accounting.domain.AccountingTransaction.Leg.CASH_COLLECTED);
    }

    @Test
    @DisplayName("carries each party's headline figure and when they were last sent one")
    void rowsCarryTheHeadlineAndTheLastSend() {
        UUID order = UUID.randomUUID();
        when(transactions.activeCounterparties(any(), any()))
                .thenReturn(List.<Object[]>of(new Object[] {CounterpartyKind.MERCHANT, SHOP}));
        when(transactions.legsForCounterparty(eq(CounterpartyKind.MERCHANT), eq(SHOP), any(), any()))
                .thenReturn(List.of(Legs.merchantCredit(order, "87.50", SHOP)));
        Mockito.lenient().when(transactions.findByOrderIdIn(anyCollection())).thenReturn(List.of(
                Legs.merchantCredit(order, "87.50", SHOP),
                Legs.commission(order, "12.50")));
        when(directory.nameOf(CounterpartyKind.MERCHANT, SHOP))
                .thenReturn("Rose & Crust Pizzeria");
        when(directory.recipientOf(CounterpartyKind.MERCHANT, SHOP))
                .thenReturn("shop@example.com");
        unattributed("0.00", 0);

        StatementDispatch previous = new StatementDispatch(CounterpartyKind.MERCHANT, SHOP,
                LocalDate.parse("2026-07-01"), LocalDate.parse("2026-07-31"), "EMAIL",
                "shop@example.com", new BigDecimal("10.00"), "WE_OWE", "USD", "notif-1", "op-1");
        when(dispatches.recentFor(anyCollection())).thenReturn(List.of(previous));

        StatementService.Counterparties listing = service.list(august);

        assertThat(listing.counterparties()).hasSize(1);
        StatementService.Summary row = listing.counterparties().get(0);
        assertThat(row.kind()).isEqualTo(CounterpartyKind.MERCHANT);
        assertThat(row.ref()).isEqualTo(SHOP);
        assertThat(row.name()).isEqualTo("Rose & Crust Pizzeria");
        assertThat(row.net()).isEqualByComparingTo("87.50");
        assertThat(row.direction()).isEqualTo(Statement.Direction.WE_OWE);
        assertThat(row.orders()).isEqualTo(1);
        assertThat(row.recipient()).isEqualTo("shop@example.com");
        assertThat(row.lastSentAt()).isNotNull().isBeforeOrEqualTo(Instant.now());
    }

    @Test
    @DisplayName("leaves lastSentAt null for somebody who has never been sent one")
    void neverSentReadsAsNull() {
        UUID order = UUID.randomUUID();
        when(transactions.activeCounterparties(any(), any()))
                .thenReturn(List.<Object[]>of(new Object[] {CounterpartyKind.MERCHANT, SHOP}));
        when(transactions.legsForCounterparty(eq(CounterpartyKind.MERCHANT), eq(SHOP), any(), any()))
                .thenReturn(List.of(Legs.merchantCredit(order, "87.50", SHOP)));
        Mockito.lenient().when(transactions.findByOrderIdIn(anyCollection())).thenReturn(List.of(
                Legs.merchantCredit(order, "87.50", SHOP)));
        when(directory.nameOf(CounterpartyKind.MERCHANT, SHOP)).thenReturn("Rose & Crust");
        when(dispatches.recentFor(anyCollection())).thenReturn(List.of());
        unattributed("0.00", 0);

        StatementService.Counterparties listing = service.list(august);

        assertThat(listing.counterparties().get(0).lastSentAt()).isNull();
        // No email on file is also a legitimate answer, and the send endpoint refuses on it.
        assertThat(listing.counterparties().get(0).recipient()).isNull();
    }
}
