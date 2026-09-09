package com.delivery.transfer.service;

import java.math.BigDecimal;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import com.delivery.transfer.client.OrderManagerClient;
import com.delivery.transfer.client.OrderManagerClient.OrderSummary;
import com.delivery.transfer.client.OrderManagerClient.OrderUnavailableException;
import com.delivery.transfer.connector.CashOnDeliveryConnector;
import com.delivery.transfer.connector.ConnectorRegistry;
import com.delivery.transfer.domain.MoneyTransfer;
import com.delivery.transfer.domain.MoneyTransferRepository;
import com.delivery.transfer.domain.TransferMethod;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class TransferServiceTest {

    private static final String PAYER = "customer-sub";
    private static final String SOMEONE_ELSE = "other-customer-sub";
    private static final UUID ORDER = UUID.randomUUID();

    @Mock private MoneyTransferRepository transfers;
    @Mock private ConnectorRegistry registry;
    @Mock private OrderManagerClient orders;

    private TransferService service;

    @BeforeEach
    void setUp() {
        service = new TransferService(transfers, registry, orders,
                new BigDecimal("90000"), new BigDecimal("100000"));
        when(registry.forMethod(any())).thenReturn(Optional.of(new CashOnDeliveryConnector()));
        when(transfers.findByOrderId(any())).thenReturn(Optional.empty());
        when(transfers.save(any())).thenAnswer(call -> call.getArgument(0));
        when(orders.fetch(ORDER)).thenReturn(new OrderSummary(ORDER, PAYER, "PLACED"));
    }

    /**
     * The order id in the request is a UUID and nothing else until Order Manager speaks for it.
     * An end-to-end run recorded an intent, connector reference and all, against an id that
     * existed in no service at all.
     */
    @Nested
    class TheOrderBehindTheMoney {

        @Test
        @DisplayName("an order nobody placed records nothing")
        void unknownOrderIsRefused() {
            UUID ghost = UUID.randomUUID();
            when(orders.fetch(ghost)).thenThrow(
                    new OrderUnavailableException("That order does not exist, or is not yours"));

            assertThatThrownBy(() -> service.record(ghost, PAYER, TransferMethod.CASH_ON_DELIVERY,
                    new BigDecimal("10.00"), null))
                    .isInstanceOf(OrderUnavailableException.class)
                    .hasMessageContaining("does not exist");

            verify(transfers, never()).save(any());
        }

        /**
         * One order holds one intent, so recording against somebody else's order does not merely
         * add a row — it takes the only one the genuine customer could have used.
         */
        @Test
        @DisplayName("someone else's order records nothing")
        void anotherCustomersOrderIsRefused() {
            when(orders.fetch(ORDER))
                    .thenReturn(new OrderSummary(ORDER, SOMEONE_ELSE, "PLACED"));

            assertThatThrownBy(() -> service.record(ORDER, PAYER, TransferMethod.CASH_ON_DELIVERY,
                    new BigDecimal("10.00"), null))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasFieldOrPropertyWithValue("statusCode", HttpStatus.FORBIDDEN);

            verify(transfers, never()).save(any());
        }

        @Test
        @DisplayName("the customer's own order records")
        void ownOrderIsRecorded() {
            MoneyTransfer transfer = service.record(ORDER, PAYER,
                    TransferMethod.CASH_ON_DELIVERY, new BigDecimal("10.01"),
                    new BigDecimal("10.00"));

            assertThat(transfer.getOrderId()).isEqualTo(ORDER);
            assertThat(transfer.getPayerRef()).isEqualTo(PAYER);
            verify(transfers).save(any());
        }
    }

    /**
     * The quote and the POST behind it must refuse the same numbers. They did not: the quote
     * priced a negative amount and a USD part larger than the whole and answered 200, so the
     * customer learned the transfer was impossible only at the last screen.
     */
    @Nested
    class TheSameRulesBothWays {

        @Test
        @DisplayName("a negative amount is refused by the quote too")
        void quoteRefusesNegativeAmount() {
            assertThatThrownBy(() -> service.quote(new BigDecimal("-5.00"), null))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasFieldOrPropertyWithValue("statusCode", HttpStatus.UNPROCESSABLE_ENTITY)
                    .hasMessageContaining("amountUsd must be positive");
        }

        @Test
        @DisplayName("a split larger than the total is refused by the quote too")
        void quoteRefusesOversizedSplit() {
            assertThatThrownBy(
                    () -> service.quote(new BigDecimal("10.00"), new BigDecimal("25.00")))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasFieldOrPropertyWithValue("statusCode", HttpStatus.UNPROCESSABLE_ENTITY)
                    .hasMessageContaining("splitUsd must be between 0 and amountUsd");
        }

        @Test
        @DisplayName("a negative split is refused by the quote too")
        void quoteRefusesNegativeSplit() {
            assertThatThrownBy(
                    () -> service.quote(new BigDecimal("10.00"), new BigDecimal("-1.00")))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasFieldOrPropertyWithValue("statusCode", HttpStatus.UNPROCESSABLE_ENTITY);
        }

        /**
         * Rounding runs before the checks: the columns hold cents, so a third decimal is already
         * gone by the time the row is written and must not be allowed to pass as a positive
         * amount and record an obligation for $0.00.
         */
        @Test
        @DisplayName("an amount that rounds away to nothing is refused")
        void quoteRefusesSubCentAmount() {
            assertThatThrownBy(() -> service.quote(new BigDecimal("0.001"), null))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasMessageContaining("amountUsd must be positive");
        }

        @Test
        @DisplayName("a legal split prices the lira part at the locked rate")
        void quotePricesTheLiraPart() {
            TransferService.Quote quote =
                    service.quote(new BigDecimal("10.01"), new BigDecimal("10.00"));

            assertThat(quote.amountUsd()).isEqualByComparingTo("10.01");
            assertThat(quote.splitUsd()).isEqualByComparingTo("10.00");
            assertThat(quote.splitLbpInUsd()).isEqualByComparingTo("0.01");
            assertThat(quote.splitLbpFace()).isEqualByComparingTo("1000");
        }

        /** The record must be able to store exactly what the quote showed. */
        @Test
        @DisplayName("what the quote priced is what the record holds")
        void recordStoresTheQuotedFigures() {
            TransferService.Quote quote =
                    service.quote(new BigDecimal("10.01"), new BigDecimal("10.00"));

            MoneyTransfer transfer = service.record(ORDER, PAYER,
                    TransferMethod.CASH_ON_DELIVERY, new BigDecimal("10.01"),
                    new BigDecimal("10.00"));

            assertThat(transfer.getAmountUsd()).isEqualByComparingTo(quote.amountUsd());
            assertThat(transfer.getSplitUsd()).isEqualByComparingTo(quote.splitUsd());
            assertThat(transfer.lbpFaceValue()).isEqualByComparingTo(quote.splitLbpFace());
        }
    }

    /**
     * The rate is one number however the operator wrote it in configuration; a client that reads
     * it twice must not see two.
     */
    @Test
    @DisplayName("the rate is a whole number of lira whatever config said")
    void rateIsNormalised() {
        TransferService configuredWithCents = new TransferService(transfers, registry, orders,
                new BigDecimal("90000.00"), new BigDecimal("100000.00"));

        assertThat(configuredWithCents.rate().scale()).isZero();
        assertThat(configuredWithCents.riderChangeLimitLbp().scale()).isZero();
    }
}
