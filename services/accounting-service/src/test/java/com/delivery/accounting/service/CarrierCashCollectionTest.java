package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.RiderLedgerRepository;
import com.delivery.accounting.event.OrderEventListener;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Which company a cash order's notes are owed to, decided once, at collection.
 *
 * <p>The owner's rule is that a delivery company holds its riders' cash, and everything on the
 * carrier's reconciliation page is scoped by the company stamped on the float row here. A row
 * stamped wrong is cash the company is never asked for, or cash another company is asked for. The
 * platform's own riders, and every errand, must stay exactly as they were: owed to the platform.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("whose cash a collection is")
class CarrierCashCollectionTest {

    private static final String COMPANY = "provider-77";

    @Mock
    private AccountingTransactionRepository transactions;
    @Mock
    private CashFloatRepository floatEntries;
    @Mock
    private RiderLedgerRepository riderLedger;
    @Mock
    private BankPostingPublisher postings;

    private SettlementService settlements;

    @BeforeEach
    void setUp() {
        settlements = new SettlementService(transactions, floatEntries, riderLedger, postings,
                new BigDecimal("12.5"), new BigDecimal("10"), "", "ACC-PLATFORM", "USD",
                SettlementService.SettlementMode.LEDGER_ONLY);
    }

    private CashFloatEntry floatRowWritten() {
        ArgumentCaptor<CashFloatEntry> saved = ArgumentCaptor.forClass(CashFloatEntry.class);
        verify(floatEntries).save(saved.capture());
        return saved.getValue();
    }

    @Nested
    @DisplayName("settlement")
    class Settlement {

        @Test
        @DisplayName("stamps a delivery company's job with the company")
        void carrierJob() {
            settlements.settle(UUID.randomUUID(), new BigDecimal("50.00"), new BigDecimal("45.00"),
                    "ACC-CUSTOMER", "ACC-MERCHANT", "ACC-CARRIER",
                    new SettlementService.CashHolder("rider-1", CashFloatEntry.HolderKind.RIDER,
                            COMPANY),
                    "corr", new SettlementService.Waivers(new BigDecimal("5.00"), false, false,
                            false),
                    new SettlementService.Rider("rider-1", "ACC-RIDER", COMPANY, "customer-1"),
                    Instant.now(), new SettlementService.Parties("merchant-1", COMPANY));

            CashFloatEntry row = floatRowWritten();
            assertThat(row.getHolderRef()).isEqualTo("rider-1");
            assertThat(row.getHolderKind()).isEqualTo(CashFloatEntry.HolderKind.RIDER);
            assertThat(row.getCarrierRef()).isEqualTo(COMPANY);
            // Still the rider's to hand over: collection does not move custody, a hand-over does.
            assertThat(row.getAmount()).isEqualByComparingTo("50.00");
        }

        @Test
        @DisplayName("leaves the platform's own riders owing the platform")
        void ownFleet() {
            settlements.settle(UUID.randomUUID(), new BigDecimal("50.00"), new BigDecimal("45.00"),
                    "ACC-CUSTOMER", "ACC-MERCHANT", null,
                    new SettlementService.CashHolder("rider-1", CashFloatEntry.HolderKind.RIDER),
                    "corr");

            assertThat(floatRowWritten().getCarrierRef()).isNull();
        }

        @Test
        @DisplayName("never hands an errand's cash to a company, whoever the rider rides for")
        void errand() {
            settlements.settleErrand(UUID.randomUUID(), new BigDecimal("30.00"),
                    new BigDecimal("25.00"), "ACC-CUSTOMER", "ACC-RIDER",
                    new SettlementService.CashHolder("rider-1", CashFloatEntry.HolderKind.RIDER,
                            COMPANY),
                    "corr");

            assertThat(floatRowWritten().getCarrierRef()).isNull();
        }
    }

    @Nested
    @DisplayName("the order.delivered listener")
    class Listener {

        private SettlementService settlementsMock;
        private OrderEventListener listener;

        @BeforeEach
        void wire() {
            settlementsMock = mock(SettlementService.class);
            AccountDirectory accounts = mock(AccountDirectory.class);
            lenient().when(accounts.forUser(any())).thenReturn("ACC-X");
            listener = new OrderEventListener(settlementsMock, accounts,
                    mock(PointsService.class), mock(RiderEarningsService.class),
                    new ObjectMapper());
        }

        private String event(String kind, boolean carrier) {
            return """
                    {"orderId":"%s","customerId":"customer-1","merchantId":"merchant-1",
                     "riderId":"rider-1","totalAmount":50.00,"subtotal":45.00,"deliveryFee":5.00,
                     "paymentMethod":"CASH","paymentStatus":"COLLECTED","kind":"%s"%s}
                    """.formatted(UUID.randomUUID(), kind, carrier
                    ? ",\"deliveryProviderAccount\":\"ACC-CARRIER\",\"deliveryProviderId\":\""
                            + COMPANY + "\""
                    : "");
        }

        private SettlementService.CashHolder holderSettled() {
            ArgumentCaptor<SettlementService.CashHolder> holder =
                    ArgumentCaptor.forClass(SettlementService.CashHolder.class);
            verify(settlementsMock).settle(any(), any(), any(), any(), any(), any(),
                    holder.capture(), any(), any(), any(), any(), any());
            return holder.getValue();
        }

        @Test
        @DisplayName("names the company on a delivery company's catalog order")
        void carrierCatalogOrder() {
            listener.onOrderEvent(event("CATALOG", true), "order.delivered", null, null);

            SettlementService.CashHolder holder = holderSettled();
            assertThat(holder.ref()).isEqualTo("rider-1");
            assertThat(holder.carrierRef()).isEqualTo(COMPANY);
        }

        @Test
        @DisplayName("names nobody on the platform's own fleet")
        void ownFleetOrder() {
            listener.onOrderEvent(event("CATALOG", false), "order.delivered", null, null);

            assertThat(holderSettled().carrierRef()).isNull();
        }

        @Test
        @DisplayName("names nobody on an errand, even one a company's rider ran")
        void errandOrder() {
            listener.onOrderEvent(event("BUTLER_BUY", true), "order.delivered", null, null);

            ArgumentCaptor<SettlementService.CashHolder> holder =
                    ArgumentCaptor.forClass(SettlementService.CashHolder.class);
            verify(settlementsMock).settleErrand(any(), any(), any(), any(), any(),
                    holder.capture(), any(), any(), any());
            assertThat(holder.getValue().carrierRef()).isNull();
        }
    }
}
