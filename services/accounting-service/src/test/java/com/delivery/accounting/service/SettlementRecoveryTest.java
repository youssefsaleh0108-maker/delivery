package com.delivery.accounting.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.event.OrderEventListener;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * RECON-04: finding the delivered orders the ledger never saw, and settling them.
 *
 * <p>The two on dev are the shape here: delivered, paid in cash at the door, and absent from the
 * ledger because the settlement of the day refused them and the message was acknowledged. Nothing
 * inside this service can notice that, so the check asks Order Manager and compares.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("RECON-04: delivered orders with no ledger rows")
class SettlementRecoveryTest {

    private static final String TOKEN = "operator-token";
    private static final UUID STUCK = UUID.fromString("9576be97-0000-4000-8000-000000000001");
    private static final UUID SETTLED = UUID.fromString("dcb4f889-0000-4000-8000-000000000002");
    private static final UUID UNPAID = UUID.fromString("0a1b2c3d-0000-4000-8000-000000000003");

    private final ObjectMapper mapper = new ObjectMapper();

    @Mock
    private OrderManagerOrdersClient orderManager;
    @Mock
    private AccountingTransactionRepository transactions;
    @Mock
    private OrderEventListener settlements;
    @Mock
    private SettlementFailures failures;

    private SettlementRecovery recovery() {
        return new SettlementRecovery(orderManager, transactions, settlements, failures, mapper,
                "ACC-UNMAPPED");
    }

    /** The dev shape: an order carrying no payout account, as Order Manager answered before. */
    private JsonNode order(UUID id, String paymentStatus) throws Exception {
        return order(id, paymentStatus, null);
    }

    /**
     * @param providerAccount where the carrier company is paid, as Order Manager now tells the
     *                        back office, or null for an order that carries none
     */
    private JsonNode order(UUID id, String paymentStatus, String providerAccount) throws Exception {
        return mapper.readTree("""
                {"id":"%s","kind":"CATALOG","customerId":"customer-1","merchantId":"merchant-1",
                 "riderId":"rider-1","deliveryProviderId":"provider-77",%s"status":"DELIVERED",
                 "totalAmount":0.00,"subtotal":13.11,"deliveryFee":4.72,"expressSurcharge":0.00,
                 "deliveryFeeWaived":false,"merchantFeeWaived":false,"carrierFeeWaived":false,
                 "discountAmount":17.83,"paymentMethod":"CASH","paymentStatus":"%s",
                 "fulfilment":"DELIVERY","deliveredAt":"2026-09-08T21:16:14Z",
                 "gift":{"wrap":true,"wrapFee":3.00}}
                """.formatted(id,
                providerAccount == null
                        ? ""
                        : "\"deliveryProviderAccount\":\"" + providerAccount + "\",",
                paymentStatus));
    }

    private void orderManagerHas(boolean complete, JsonNode... orders) {
        when(orderManager.delivered(eq(TOKEN), org.mockito.ArgumentMatchers.anyInt()))
                .thenReturn(new OrderManagerOrdersClient.Delivered(List.of(orders), complete));
    }

    @Test
    @DisplayName("lists a delivered order with no legs, and not one that has them")
    void listsOnlyWhatIsMissing() throws Exception {
        orderManagerHas(true, order(STUCK, "COLLECTED"), order(SETTLED, "COLLECTED"));
        AccountingTransaction leg = new AccountingTransaction(SETTLED,
                AccountingTransaction.Leg.MERCHANT_CREDIT, "ACC-MERCHANT",
                new java.math.BigDecimal("11.47"), "USD",
                AccountingTransaction.Direction.CREDIT, "corr");
        when(transactions.findByOrderIdIn(anyCollection())).thenReturn(List.of(leg));

        SettlementRecovery.Check check = recovery().unsettledDeliveries(TOKEN, 1000);

        assertThat(check.missing()).extracting(SettlementRecovery.Missing::orderId)
                .containsExactly(STUCK);
        assertThat(check.missing().get(0).settleable()).isTrue();
        assertThat(check.missing().get(0).reason()).isNull();
        // What was looked at, beside what was found.
        assertThat(check.scanned()).isEqualTo(2);
        assertThat(check.complete()).isTrue();
    }

    @Test
    @DisplayName("only legs count as settled: points from a failed run do not")
    void onlyLegsCountAsSettled() throws Exception {
        // The two orders stuck on dev: their loyalty points were awarded by the run that failed in
        // September and their legs never written. The ledger is the only thing asked.
        orderManagerHas(true, order(STUCK, "COLLECTED"));
        when(transactions.findByOrderIdIn(anyCollection())).thenReturn(List.of());

        SettlementRecovery.Check check = recovery().unsettledDeliveries(TOKEN, 1000);

        assertThat(check.missing()).extracting(SettlementRecovery.Missing::orderId)
                .containsExactly(STUCK);
        verify(transactions).findByOrderIdIn(anyCollection());
    }

    @Test
    @DisplayName("a scan that stopped at the cap does not read as a clean ledger")
    void anIncompleteScanSaysSo() throws Exception {
        orderManagerHas(false, order(SETTLED, "COLLECTED"));
        AccountingTransaction leg = new AccountingTransaction(SETTLED,
                AccountingTransaction.Leg.MERCHANT_CREDIT, "ACC-MERCHANT",
                new java.math.BigDecimal("11.47"), "USD",
                AccountingTransaction.Direction.CREDIT, "corr");
        when(transactions.findByOrderIdIn(anyCollection())).thenReturn(List.of(leg));

        SettlementRecovery.Check check = recovery().unsettledDeliveries(TOKEN, 1000);

        assertThat(check.missing()).isEmpty();
        assertThat(check.complete()).isFalse();
    }

    @Test
    @DisplayName("an order whose money was never collected is listed, with why it cannot be settled")
    void saysWhyAnUnpaidOrderIsNotSettleable() throws Exception {
        orderManagerHas(true, order(UNPAID, "AUTHORIZATION_PENDING"));
        when(transactions.findByOrderIdIn(anyCollection())).thenReturn(List.of());

        SettlementRecovery.Check check = recovery().unsettledDeliveries(TOKEN, 1000);

        assertThat(check.missing()).singleElement().satisfies(row -> {
            assertThat(row.settleable()).isFalse();
            assertThat(row.reason()).contains("never collected");
        });
    }

    @Test
    @DisplayName("settling one replays Order Manager's record through the listener's own rules")
    void settlesThroughTheSameRules() throws Exception {
        when(transactions.existsByOrderId(STUCK)).thenReturn(false);
        when(orderManager.order(TOKEN, STUCK)).thenReturn(order(STUCK, "COLLECTED"));
        when(settlements.settleDelivered(any(), any())).thenReturn(OrderEventListener.Outcome.ok());
        when(transactions.findByOrderIdOrderByCreatedAt(STUCK)).thenReturn(List.of(
                new AccountingTransaction(STUCK, AccountingTransaction.Leg.MERCHANT_CREDIT,
                        "ACC-MERCHANT", new java.math.BigDecimal("11.47"), "USD",
                        AccountingTransaction.Direction.CREDIT, "corr")));

        SettlementRecovery.Settled settled = recovery().settle(TOKEN, STUCK, "op-1");

        assertThat(settled.settled()).isTrue();
        assertThat(settled.legs()).isEqualTo(1);
        ArgumentCaptor<JsonNode> event = ArgumentCaptor.forClass(JsonNode.class);
        verify(settlements).settleDelivered(event.capture(), any());
        // The event the listener would have received: the same field names, the wrap fee lifted out
        // of the gift, and a company named so the fee is the company's and not the rider's.
        assertThat(event.getValue().path("orderId").asText()).isEqualTo(STUCK.toString());
        assertThat(event.getValue().path("subtotal").decimalValue())
                .isEqualByComparingTo("13.11");
        assertThat(event.getValue().path("discountAmount").decimalValue())
                .isEqualByComparingTo("17.83");
        assertThat(event.getValue().path("giftWrapFee").decimalValue()).isEqualByComparingTo("3.00");
        // This order carries no payout account, so the placeholder still stands in — see below.
        assertThat(event.getValue().path("deliveryProviderAccount").asText())
                .isEqualTo("ACC-UNMAPPED");
        assertThat(event.getValue().path("deliveredAt").asText())
                .isEqualTo("2026-09-08T21:16:14Z");
        verify(failures).resolve(eq(STUCK), eq("op-1"), any());
    }

    @Test
    @DisplayName("a re-driven settlement credits the company where it is actually paid")
    void booksToTheCompanysOwnAccount() throws Exception {
        // Order Manager exposes deliveryProviderAccount to the back office, and this is the back
        // office's token. Before it did, the company's PROVIDER_CREDIT went to the placeholder: a
        // re-driven settlement and a settlement that worked first time did not land in the same
        // place, and only the amount and the counterparty said so.
        when(transactions.existsByOrderId(STUCK)).thenReturn(false);
        when(orderManager.order(TOKEN, STUCK)).thenReturn(order(STUCK, "COLLECTED", "ACC-FLEET-7"));
        when(settlements.settleDelivered(any(), any())).thenReturn(OrderEventListener.Outcome.ok());

        recovery().settle(TOKEN, STUCK, "op-1");

        ArgumentCaptor<JsonNode> event = ArgumentCaptor.forClass(JsonNode.class);
        verify(settlements).settleDelivered(event.capture(), any());
        assertThat(event.getValue().path("deliveryProviderAccount").asText())
                .isEqualTo("ACC-FLEET-7");
    }

    @Test
    @DisplayName("an order the platform's own riders carried names no company at all")
    void namesNoCompanyForAnOwnFleetOrder() throws Exception {
        // The account's PRESENCE is what decides whether the fee is a company's or the rider's own,
        // so an order with no fleet must carry none — not the placeholder, which would pay a
        // company that does not exist and leave the rider's own credit unwritten.
        JsonNode ownFleet = mapper.readTree(order(STUCK, "COLLECTED", "ACC-FLEET-7").toString()
                .replace("\"deliveryProviderId\":\"provider-77\"",
                        "\"deliveryProviderId\":null")
                .replace("\"deliveryProviderAccount\":\"ACC-FLEET-7\"",
                        "\"deliveryProviderAccount\":null"));
        when(transactions.existsByOrderId(STUCK)).thenReturn(false);
        when(orderManager.order(TOKEN, STUCK)).thenReturn(ownFleet);
        when(settlements.settleDelivered(any(), any())).thenReturn(OrderEventListener.Outcome.ok());

        recovery().settle(TOKEN, STUCK, "op-1");

        ArgumentCaptor<JsonNode> event = ArgumentCaptor.forClass(JsonNode.class);
        verify(settlements).settleDelivered(event.capture(), any());
        assertThat(event.getValue().has("deliveryProviderAccount")).isFalse();
    }

    @Test
    @DisplayName("an order already in the ledger is left alone, and its failure row closed")
    void anAlreadySettledOrderIsLeftAlone() {
        when(transactions.existsByOrderId(SETTLED)).thenReturn(true);

        SettlementRecovery.Settled settled = recovery().settle(TOKEN, SETTLED, "op-1");

        assertThat(settled.settled()).isFalse();
        assertThat(settled.reason()).contains("already in the ledger");
        verify(settlements, never()).settleDelivered(any(), any());
        verify(failures).resolve(eq(SETTLED), eq("op-1"), any());
    }

    @Test
    @DisplayName("only a delivered order Order Manager has may be settled")
    void refusesWhatItMayNotSettle() throws Exception {
        when(transactions.existsByOrderId(any())).thenReturn(false);
        when(orderManager.order(TOKEN, STUCK)).thenReturn(null);
        assertThatThrownBy(() -> recovery().settle(TOKEN, STUCK, "op-1"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("no order");

        JsonNode cancelled = mapper.readTree(
                "{\"id\":\"%s\",\"status\":\"CANCELLED\"}".formatted(UNPAID));
        when(orderManager.order(TOKEN, UNPAID)).thenReturn(cancelled);
        assertThatThrownBy(() -> recovery().settle(TOKEN, UNPAID, "op-1"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("CANCELLED");
    }

    @Test
    @DisplayName("a refusal is recorded where the Back Office can see it, not swallowed")
    void aRefusalIsRecorded() throws Exception {
        when(transactions.existsByOrderId(UNPAID)).thenReturn(false);
        when(orderManager.order(TOKEN, UNPAID)).thenReturn(order(UNPAID, "AUTHORIZATION_PENDING"));
        when(settlements.settleDelivered(any(), any())).thenReturn(
                OrderEventListener.Outcome.refused("The money was never collected"));

        SettlementRecovery.Settled settled = recovery().settle(TOKEN, UNPAID, "op-1");

        assertThat(settled.settled()).isFalse();
        verify(failures).record(eq(UNPAID), eq("order.delivered"),
                eq("The money was never collected"), any(), any());
    }
}
