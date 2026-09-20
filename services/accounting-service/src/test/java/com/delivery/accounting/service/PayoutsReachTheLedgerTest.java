package com.delivery.accounting.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransaction.Direction;
import com.delivery.accounting.domain.AccountingTransaction.Leg;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.CounterpartyKind;
import com.delivery.accounting.domain.PointsEntry.OwnerKind;
import com.delivery.accounting.domain.PointsEntryRepository;
import com.delivery.accounting.domain.PointsRedemption;
import com.delivery.accounting.domain.PointsRedemptionRepository;
import com.delivery.accounting.domain.RiderCashOut;
import com.delivery.accounting.domain.RiderCashOutRepository;
import com.delivery.accounting.domain.RiderLedgerRepository;
import com.delivery.accounting.domain.StatementDispatchRepository;
import com.delivery.accounting.payout.ManualPayoutProvider;
import com.delivery.accounting.payout.RiderPayoutProviders;

/**
 * RECON-11: money the platform hands over reaches the ledger, and the statements show it.
 *
 * <p>A redemption paid and a cash-out paid both moved real money and appeared nowhere in the books:
 * a shop's statement went on reporting the whole amount owed after it had been paid, and the
 * platform's own statement showed what it earned with nothing for what it gave out.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("RECON-11: payouts on the ledger")
class PayoutsReachTheLedgerTest {

    private static final String SHOP = "merchant-1";
    private static final String RIDER = "rider-1";
    private static final String PLATFORM = "ACC-PLATFORM";

    @Mock
    private PointsEntryRepository points;
    @Mock
    private PointsRedemptionRepository redemptions;
    @Mock
    private AccountingTransactionRepository transactions;
    @Mock
    private RiderLedgerRepository riderLedger;
    @Mock
    private RiderCashOutRepository cashOuts;
    @Mock
    private CashFloatRepository floats;
    @Mock
    private StatementDispatchRepository dispatches;
    @Mock
    private CounterpartyDirectory directory;

    private PointsService pointsService() {
        return new PointsService(points, redemptions, transactions, PLATFORM,
                new BigDecimal("5"), new BigDecimal("10"), new BigDecimal("5"),
                new BigDecimal("0.01"), 1000L, "USD");
    }

    private RiderEarningsService riderEarnings() {
        return new RiderEarningsService(riderLedger, cashOuts, floats, transactions,
                new RiderPayoutProviders(List.of(new ManualPayoutProvider()), "MANUAL"), PLATFORM,
                new BigDecimal("5.00"), new BigDecimal("100.00"), true, "Asia/Beirut", "USD");
    }

    private StatementService statements() {
        return new StatementService(transactions, floats, riderLedger, dispatches, directory,
                new BigDecimal("12.5"), new BigDecimal("10"), "USD", "Asia/Beirut");
    }

    private AccountingTransaction savedLeg() {
        ArgumentCaptor<AccountingTransaction> saved =
                ArgumentCaptor.forClass(AccountingTransaction.class);
        verify(transactions).save(saved.capture());
        return saved.getValue();
    }

    @Test
    @DisplayName("a redemption paid to a shop is a debit against that shop")
    void aRedemptionPaidIsRecorded() {
        PointsRedemption redemption = new PointsRedemption(OwnerKind.MERCHANT, SHOP, 1000L,
                new BigDecimal("10.00"), "USD", "IBAN ...", SHOP);
        redemption.approve("op-1", "ok");
        when(redemptions.findById(redemption.getId())).thenReturn(java.util.Optional.of(redemption));

        pointsService().markPaid(redemption.getId(), "op-1", "BANK-REF-0919");

        AccountingTransaction leg = savedLeg();
        assertThat(leg.getLeg()).isEqualTo(Leg.PAYOUT);
        assertThat(leg.getDirection()).isEqualTo(Direction.DEBIT);
        assertThat(leg.getAmount()).isEqualByComparingTo("10.00");
        assertThat(leg.getCounterpartyKind()).isEqualTo(CounterpartyKind.MERCHANT);
        assertThat(leg.getCounterpartyRef()).isEqualTo(SHOP);
        assertThat(leg.getAccountRef()).isEqualTo(PLATFORM);
        // The money has already left: nothing is waiting on a bank that is not deployed.
        assertThat(leg.getStatus()).isEqualTo(AccountingTransaction.Status.SETTLED_IN_CASH);
        assertThat(leg.isPostingRequired()).isFalse();
        // The payout's own id, as a remittance carries its own: the unique (order_id, leg) is what
        // stops one redemption being recorded twice.
        assertThat(leg.getOrderId()).isEqualTo(redemption.getId());
    }

    @Test
    @DisplayName("a customer's redemption is recorded with no counterparty, and still counted")
    void aCustomersRedemptionHasNoCounterparty() {
        PointsRedemption redemption = new PointsRedemption(OwnerKind.CUSTOMER, "customer-1", 1000L,
                new BigDecimal("10.00"), "USD", null, "customer-1");
        redemption.approve("op-1", "ok");
        when(redemptions.findById(redemption.getId())).thenReturn(java.util.Optional.of(redemption));

        pointsService().markPaid(redemption.getId(), "op-1", "CASH");

        AccountingTransaction leg = savedLeg();
        assertThat(leg.getLeg()).isEqualTo(Leg.PAYOUT);
        assertThat(leg.getAmount()).isEqualByComparingTo("10.00");
        assertThat(leg.getCounterpartyKind()).isNull();
    }

    @Test
    @DisplayName("a cash-out paid is a debit against the rider it went to")
    void aCashOutPaidIsRecorded() {
        RiderCashOut request = new RiderCashOut(RIDER, new BigDecimal("40.00"), "USD", "wallet 123");
        when(cashOuts.findById(request.getId())).thenReturn(java.util.Optional.of(request));

        riderEarnings().payCashOut(request.getId(), "op-1", "BANK-REF-0919");

        AccountingTransaction leg = savedLeg();
        assertThat(leg.getLeg()).isEqualTo(Leg.PAYOUT);
        assertThat(leg.getDirection()).isEqualTo(Direction.DEBIT);
        assertThat(leg.getAmount()).isEqualByComparingTo("40.00");
        assertThat(leg.getCounterpartyKind()).isEqualTo(CounterpartyKind.RIDER);
        assertThat(leg.getCounterpartyRef()).isEqualTo(RIDER);
        assertThat(leg.getOrderId()).isEqualTo(request.getId());
    }

    @Test
    @DisplayName("a shop's statement shows what it has been paid, and asks for that much less")
    void theShopsStatementShowsThePayment() {
        UUID order = UUID.randomUUID();
        AccountingTransaction goods = new AccountingTransaction(order, Leg.MERCHANT_CREDIT,
                "ACC-MERCHANT", new BigDecimal("35.00"), "USD", Direction.CREDIT, "corr")
                .attributedTo(CounterpartyKind.MERCHANT, SHOP)
                .commissionCharged(new BigDecimal("5.00"));
        AccountingTransaction paid = AccountingTransaction.paidOut(UUID.randomUUID(), PLATFORM,
                        new BigDecimal("10.00"), "USD", null)
                .attributedTo(CounterpartyKind.MERCHANT, SHOP);
        when(transactions.legsForCounterparty(eq(CounterpartyKind.MERCHANT), eq(SHOP), any(), any()))
                .thenReturn(List.of(goods, paid));
        when(transactions.findByOrderIdIn(anyCollection())).thenReturn(List.of(goods, paid));
        when(floats.heldBy(SHOP, com.delivery.accounting.domain.CashFloatEntry.HolderKind.MERCHANT))
                .thenReturn(List.of());
        LocalDate day = LocalDate.parse("2026-09-19");

        Statement statement = statements().build(CounterpartyKind.MERCHANT, SHOP,
                StatementRange.of(day, day, ZoneId.of("Asia/Beirut")));

        Map<String, BigDecimal> lines = statement.lines().stream()
                .collect(Collectors.toMap(Statement.Line::label, Statement.Line::amount));
        assertThat(lines).containsEntry("Goods sold", new BigDecimal("40.00"))
                .containsEntry("Platform commission (12.5%)", new BigDecimal("5.00"))
                .containsEntry("Paid to you", new BigDecimal("10.00"));
        // 35.00 owed for the goods, less the 10.00 already paid.
        assertThat(statement.net().amount()).isEqualByComparingTo("25.00");
        assertThat(statement.net().direction()).isEqualTo(Statement.Direction.WE_OWE);
    }

    @Test
    @DisplayName("the platform's own statement counts everything it paid out, to anybody")
    void thePlatformsStatementCountsItsPayouts() {
        UUID order = UUID.randomUUID();
        AccountingTransaction commission = new AccountingTransaction(order,
                Leg.PLATFORM_COMMISSION, PLATFORM, new BigDecimal("5.00"), "USD",
                Direction.CREDIT, "corr")
                .attributedTo(CounterpartyKind.PLATFORM, CounterpartyKind.PLATFORM_REF);
        when(transactions.legsForCounterparty(eq(CounterpartyKind.PLATFORM), any(), any(), any()))
                .thenReturn(List.of(commission));
        when(transactions.findByOrderIdIn(anyCollection())).thenReturn(List.of(commission));
        // Paid to a shop and to a rider: attributed to them, so the platform cannot find these
        // among its own legs — which is why the figure is read across counterparties.
        when(transactions.sumOfLegBetween(eq(Leg.PAYOUT), any(), any()))
                .thenReturn(new BigDecimal("50.00"));
        when(floats.totalBetween(any(), any(), any())).thenReturn(BigDecimal.ZERO);
        when(floats.outstandingTotal()).thenReturn(BigDecimal.ZERO);
        LocalDate day = LocalDate.parse("2026-09-19");

        Statement statement = statements().build(CounterpartyKind.PLATFORM,
                CounterpartyKind.PLATFORM_REF, StatementRange.of(day, day,
                        ZoneId.of("Asia/Beirut")));

        Map<String, BigDecimal> lines = statement.lines().stream()
                .collect(Collectors.toMap(Statement.Line::label, Statement.Line::amount));
        assertThat(lines).containsEntry("Commission earned", new BigDecimal("5.00"))
                .containsEntry("Paid out", new BigDecimal("50.00"));
        // 50.00 handed out against 5.00 earned: the platform is 45.00 down on the period.
        assertThat(statement.net().amount()).isEqualByComparingTo("45.00");
        assertThat(statement.net().direction()).isEqualTo(Statement.Direction.WE_OWE);
    }
}
