package com.delivery.accounting.event;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

import org.junit.jupiter.api.BeforeEach;
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
import com.delivery.accounting.domain.RiderLedgerEntry;
import com.delivery.accounting.domain.RiderLedgerRepository;
import com.delivery.accounting.service.AccountDirectory;
import com.delivery.accounting.service.BankPostingPublisher;
import com.delivery.accounting.service.PointsService;
import com.delivery.accounting.service.RiderEarningsService;
import com.delivery.accounting.service.SettlementService;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * RECON-10, the accounting half: an order closed after the rider had picked it up.
 *
 * <p>Back Office can close a PICKED_UP order that will never arrive, with two decisions on it: pay
 * the shop its share, and pay the delivery fee. The customer pays nothing, so whatever is paid comes
 * out of the platform. Order Manager says which on the event; this consumes it.
 *
 * <p>Driven through the real {@link SettlementService}, because what matters is the legs: the shop
 * and the carrier get exactly what a delivery would have paid them, nothing is collected from
 * anybody, and the order still balances — with the platform's own loss on its own account.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("RECON-10: an order closed after pickup")
class CancelledAfterPickupTest {

    private static final UUID ORDER = UUID.fromString("7f000001-0000-4000-8000-00000000000a");
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
    private BankPostingPublisher postings;
    @Mock
    private AccountDirectory accounts;
    @Mock
    private PointsService points;
    @Mock
    private RiderEarningsService riderEarnings;

    private OrderEventListener listener;

    @BeforeEach
    void setUp() {
        when(transactions.existsByOrderId(any())).thenReturn(false);
        when(accounts.forUser(any())).thenReturn("ACC-UNMAPPED");
        SettlementService settlements = new SettlementService(transactions, floats, riderLedger,
                postings, new BigDecimal("12.5"), new BigDecimal("10"), "", "ACC-PLATFORM",
                "ACC-PLATFORM-LOSS", "USD", SettlementService.SettlementMode.LEDGER_ONLY);
        listener = new OrderEventListener(settlements, accounts, points, riderEarnings,
                new ObjectMapper());
    }

    /**
     * The event Order Manager publishes when Back Office closes a picked-up order: 40.00 of goods
     * carried by a delivery company for 5.00, nothing collected from the customer.
     */
    private void cancel(String stage, boolean merchant, boolean carrier) {
        String payload = """
                {"orderId":"%s","kind":"CATALOG","customerId":"customer-1","merchantId":"%s",
                 "riderId":"%s","deliveryProviderId":"%s","deliveryProviderAccount":"ACC-CARRIER",
                 "status":"CANCELLED"%s,"compensateMerchant":%s,"compensateCarrier":%s,
                 "totalAmount":45.00,"subtotal":40.00,"deliveryFee":5.00,"discountAmount":0.00,
                 "deliveryFeeWaived":false,"merchantFeeWaived":false,"carrierFeeWaived":false,
                 "paymentMethod":"CASH","paymentStatus":"FAILED","fulfilment":"DELIVERY",
                 "cancelReason":"the customer never answered","occurredAt":"2026-09-19T16:48:00Z"}
                """.formatted(ORDER, SHOP, RIDER, COMPANY,
                stage == null ? "" : ",\"stage\":\"" + stage + "\"", merchant, carrier);
        listener.onOrderEvent(payload, "order.cancelled", null, "corr-1");
    }

    /**
     * The legs the cancellation wrote. Saved twice, as a settlement's are: once as they are built
     * and once more when they are marked discharged, there being no bank to ask.
     */
    private Map<Leg, AccountingTransaction> written() {
        ArgumentCaptor<List<AccountingTransaction>> saved = ArgumentCaptor.captor();
        verify(transactions, org.mockito.Mockito.atLeastOnce()).saveAll(saved.capture());
        return saved.getValue().stream()
                .collect(Collectors.toMap(AccountingTransaction::getLeg, leg -> leg));
    }

    @Test
    @DisplayName("pays the shop its share and the carrier its fee, and the platform bears it")
    void bothCompensated() {
        cancel("AFTER_PICKUP", true, true);

        Map<Leg, AccountingTransaction> legs = written();
        // Exactly what a delivery would have paid them: 40.00 less 12.5%, and 5.00 less 10%.
        assertThat(legs.get(Leg.MERCHANT_CREDIT).getAmount()).isEqualByComparingTo("35.00");
        assertThat(legs.get(Leg.MERCHANT_CREDIT).getCounterpartyRef()).isEqualTo(SHOP);
        assertThat(legs.get(Leg.MERCHANT_CREDIT).getCommissionAmount())
                .isEqualByComparingTo("5.00");
        assertThat(legs.get(Leg.PROVIDER_CREDIT).getAmount()).isEqualByComparingTo("4.50");
        assertThat(legs.get(Leg.PROVIDER_CREDIT).getCounterpartyRef()).isEqualTo(COMPANY);
        // Nothing was collected from anybody, so there is no collection leg and no cash float row.
        assertThat(legs).doesNotContainKeys(Leg.CASH_COLLECTED, Leg.CUSTOMER_DEBIT,
                Leg.PLATFORM_COMMISSION);
        verify(floats, org.mockito.Mockito.never()).save(any());
        // The platform is what is left, on its own account, and the order balances.
        AccountingTransaction loss = legs.get(Leg.PLATFORM_LOSS);
        assertThat(loss.getDirection()).isEqualTo(Direction.DEBIT);
        assertThat(loss.getAmount()).isEqualByComparingTo("39.50");
        assertThat(loss.getAccountRef()).isEqualTo("ACC-PLATFORM-LOSS");
        assertThat(loss.getCounterpartyKind()).isEqualTo(CounterpartyKind.PLATFORM);
        BigDecimal credits = legs.values().stream()
                .filter(leg -> leg.getDirection() == Direction.CREDIT)
                .map(AccountingTransaction::getAmount)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
        assertThat(loss.getAmount()).isEqualByComparingTo(credits);
        // The rider's own record of a job they did: their company's, as on a delivery.
        ArgumentCaptor<RiderLedgerEntry> row = ArgumentCaptor.captor();
        verify(riderLedger).saveAndFlush(row.capture());
        assertThat(row.getValue().getEntryType()).isEqualTo(RiderLedgerEntry.EntryType.JOB_EARNING);
        assertThat(row.getValue().getPayableBy()).isEqualTo(RiderLedgerEntry.PayableBy.CARRIER);
        assertThat(row.getValue().getAmount()).isEqualByComparingTo("4.50");
    }

    @Test
    @DisplayName("pays only the shop when only the shop was to be paid")
    void onlyTheShop() {
        cancel("AFTER_PICKUP", true, false);

        Map<Leg, AccountingTransaction> legs = written();
        assertThat(legs.get(Leg.MERCHANT_CREDIT).getAmount()).isEqualByComparingTo("35.00");
        assertThat(legs).doesNotContainKey(Leg.PROVIDER_CREDIT);
        assertThat(legs.get(Leg.PLATFORM_LOSS).getAmount()).isEqualByComparingTo("35.00");
        verifyNoInteractions(riderLedger);
    }

    @Test
    @DisplayName("pays only the delivery when only the delivery was to be paid")
    void onlyTheCarrier() {
        cancel("AFTER_PICKUP", false, true);

        Map<Leg, AccountingTransaction> legs = written();
        assertThat(legs).doesNotContainKey(Leg.MERCHANT_CREDIT);
        assertThat(legs.get(Leg.PROVIDER_CREDIT).getAmount()).isEqualByComparingTo("4.50");
        assertThat(legs.get(Leg.PLATFORM_LOSS).getAmount()).isEqualByComparingTo("4.50");
    }

    @Test
    @DisplayName("a cancellation before pickup, or with no stage at all, does nothing")
    void everyOtherCancellationIsUnchanged() {
        cancel("BEFORE_PICKUP", false, false);
        cancel(null, true, true);
        cancel("AFTER_PICKUP", false, false);

        verifyNoInteractions(riderLedger, floats, postings, points);
        verify(transactions, org.mockito.Mockito.never()).saveAll(any());
        verify(transactions, org.mockito.Mockito.never()).save(any());
    }

    @Test
    @DisplayName("an order that already has legs is never compensated on top of them")
    void anAlreadySettledOrderIsLeftAlone() {
        when(transactions.existsByOrderId(ORDER)).thenReturn(true);

        cancel("AFTER_PICKUP", true, true);

        verify(transactions, org.mockito.Mockito.never()).saveAll(any());
    }
}
