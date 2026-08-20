package com.delivery.connector.corebanking;

import java.math.BigDecimal;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.slf4j.MDC;
import org.springframework.amqp.AmqpException;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.core.RabbitTemplate;

import com.delivery.connector.corebanking.provider.BankClient;
import com.delivery.platform.notifications.ActiveProviderRegistry;
import com.delivery.platform.notifications.DeadLetterPublisher;
import com.delivery.platform.notifications.DeliveryOutcome;
import com.delivery.platform.notifications.IdempotentCommand;
import com.delivery.platform.notifications.ResilientDispatcher;
import com.fasterxml.jackson.databind.ObjectMapper;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The connector's obligation to always answer.
 *
 * <p>The accounting saga blocks on this. A transaction whose result never comes back sits at
 * PENDING forever, and the state that leaves behind — a customer debited with nothing crediting the
 * merchant — is the worst one this system can reach. So the property under test is not "does it post
 * correctly" (that is {@link com.delivery.connector.corebanking.provider.SimulatorBankClientTest})
 * but "does the saga always hear back, including on every path where something went wrong".
 *
 * <p>The other half is that it never rethrows. This is a queue consumer, and a redelivery loop
 * against a bank is the one failure mode nobody wants.
 */
class BankPostingListenerTest {

    private BankClient bank;
    private ActiveProviderRegistry registry;
    private ResilientDispatcher dispatcher;
    private DeadLetterPublisher deadLetters;
    private RabbitTemplate rabbit;
    private ObjectMapper objectMapper;
    private BankPostingListener listener;

    @BeforeEach
    void setUp() {
        bank = mock(BankClient.class);
        registry = mock(ActiveProviderRegistry.class);
        dispatcher = mock(ResilientDispatcher.class);
        deadLetters = mock(DeadLetterPublisher.class);
        rabbit = mock(RabbitTemplate.class);
        objectMapper = new ObjectMapper()
                .registerModule(new com.fasterxml.jackson.datatype.jsr310.JavaTimeModule());

        when(bank.name()).thenReturn("SIMULATOR");
        when(registry.activeProvider()).thenReturn("SIMULATOR");

        listener = new BankPostingListener(List.of(bank), registry, dispatcher, deadLetters,
                rabbit, objectMapper, "delivery.events");
        MDC.clear();
    }

    /** Runs the real send function so the client is genuinely exercised through the dispatcher. */
    @SuppressWarnings("unchecked")
    private void dispatcherRunsTheSend() {
        when(dispatcher.dispatch(any(), any(), any())).thenAnswer(call -> {
            IdempotentCommand command = call.getArgument(0);
            java.util.function.Function<IdempotentCommand, DeliveryOutcome> send =
                    call.getArgument(1);
            return send.apply(command);
        });
    }

    @SuppressWarnings("unchecked")
    private void dispatcherReturns(DeliveryOutcome outcome) {
        when(dispatcher.dispatch(any(), any(), any())).thenReturn(outcome);
    }

    private String payload() {
        return payloadWithCorrelation("corr-1");
    }

    private String payloadWithCorrelation(String correlationId) {
        try {
            return objectMapper.writeValueAsString(new BankPostingCommand(
                    "txn-1", "ACC-1", BankPostingCommand.DEBIT, new BigDecimal("42.50"),
                    "USD", "Order 123", correlationId));
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private BankPostingResult reportedResult() {
        ArgumentCaptor<Message> captor = ArgumentCaptor.forClass(Message.class);
        verify(rabbit).send(anyString(), eq(BankPostingResult.ROUTING_KEY), captor.capture());
        try {
            return objectMapper.readValue(captor.getValue().getBody(), BankPostingResult.class);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    @Nested
    @DisplayName("a posting the bank accepts")
    class Accepted {

        @Test
        void is_reported_back_as_a_success_with_the_bank_reference() {
            when(bank.post(any())).thenReturn(new BankClient.Response(
                    DeliveryOutcome.sent("SIMULATOR", "posting-99"), "{req}", "{res}"));
            dispatcherRunsTheSend();

            listener.onPosting(payload());

            BankPostingResult result = reportedResult();
            assertThat(result.success()).isTrue();
            assertThat(result.transactionId()).isEqualTo("txn-1");
            assertThat(result.coreBankingRef()).isEqualTo("posting-99");
        }

        /** The sync log cannot reconstruct these from a status code after the fact. */
        @Test
        void carries_both_payloads_for_the_sync_log() {
            when(bank.post(any())).thenReturn(new BankClient.Response(
                    DeliveryOutcome.sent("SIMULATOR", "posting-99"), "{req}", "{res}"));
            dispatcherRunsTheSend();

            listener.onPosting(payload());

            assertThat(reportedResult().requestPayload()).isEqualTo("{req}");
            assertThat(reportedResult().responsePayload()).isEqualTo("{res}");
        }

        /** The transaction id keys the result so the saga can match it to its own row. */
        @Test
        void is_keyed_on_the_transaction_id() {
            when(bank.post(any())).thenReturn(new BankClient.Response(
                    DeliveryOutcome.sent("SIMULATOR", "p"), null, null));
            dispatcherRunsTheSend();

            listener.onPosting(payload());

            ArgumentCaptor<Message> captor = ArgumentCaptor.forClass(Message.class);
            verify(rabbit).send(anyString(), anyString(), captor.capture());
            assertThat(captor.getValue().getMessageProperties().getMessageId()).isEqualTo("txn-1");
        }

        @Test
        void is_not_dead_lettered() {
            when(bank.post(any())).thenReturn(new BankClient.Response(
                    DeliveryOutcome.sent("SIMULATOR", "p"), null, null));
            dispatcherRunsTheSend();

            listener.onPosting(payload());

            verify(deadLetters, never()).park(any(), anyString());
        }
    }

    @Nested
    @DisplayName("a posting the bank refuses")
    class Refused {

        /**
         * The distinction the saga acts on: a permanent refusal means compensate, a retryable one
         * means the leg stays open and it waits.
         */
        @Test
        void a_permanent_refusal_is_reported_as_not_retryable() {
            dispatcherReturns(DeliveryOutcome.permanentFailure("SIMULATOR", "INSUFFICIENT_FUNDS"));

            listener.onPosting(payload());

            BankPostingResult result = reportedResult();
            assertThat(result.success()).isFalse();
            assertThat(result.retryable()).isFalse();
            assertThat(result.failureReason()).contains("INSUFFICIENT_FUNDS");
        }

        @Test
        void a_transient_failure_is_reported_as_retryable() {
            dispatcherReturns(DeliveryOutcome.transientFailure("SIMULATOR", "bank unreachable"));

            listener.onPosting(payload());

            BankPostingResult result = reportedResult();
            assertThat(result.success()).isFalse();
            assertThat(result.retryable()).isTrue();
        }
    }

    @Nested
    @DisplayName("when something is wrong with the connector itself")
    class ConnectorProblems {

        /**
         * Connector Settings naming a provider this build has no client for. Permanent and loud —
         * the settings and the deployed connector disagree about what exists.
         */
        @Test
        void an_unknown_active_provider_is_reported_and_parked() {
            when(registry.activeProvider()).thenReturn("SOME_FUTURE_BANK");

            listener.onPosting(payload());

            BankPostingResult result = reportedResult();
            assertThat(result.success()).isFalse();
            assertThat(result.retryable()).isFalse();
            assertThat(result.failureReason()).contains("no client for provider");
            verify(deadLetters).park(any(), anyString());
        }

        @Test
        void an_unknown_provider_never_reaches_the_bank() {
            when(registry.activeProvider()).thenReturn("SOME_FUTURE_BANK");

            listener.onPosting(payload());

            verify(bank, never()).post(any());
        }

        /** A thrown exception still has to produce an answer, or the saga waits forever. */
        @Test
        void an_unexpected_exception_is_still_reported_back() {
            when(dispatcher.dispatch(any(), any(), any()))
                    .thenThrow(new IllegalStateException("bug in the connector"));

            listener.onPosting(payload());

            BankPostingResult result = reportedResult();
            assertThat(result.success()).isFalse();
            assertThat(result.failureReason()).contains("connector error");
            verify(deadLetters).park(any(), anyString());
        }

        /** A redelivery loop against a bank is the one failure mode nobody wants. */
        @Test
        void nothing_is_ever_rethrown_to_the_broker() {
            when(dispatcher.dispatch(any(), any(), any()))
                    .thenThrow(new IllegalStateException("bug in the connector"));

            assertThatCode(() -> listener.onPosting(payload())).doesNotThrowAnyException();
        }

        /**
         * A message that will not parse has no transaction id, so there is nothing to report the
         * failure against and nothing useful to park. Dropped, loudly, rather than looped.
         */
        @Test
        void an_unreadable_command_is_dropped_without_a_report() {
            assertThatCode(() -> listener.onPosting("{not json")).doesNotThrowAnyException();

            verify(rabbit, never()).send(anyString(), anyString(), any(Message.class));
            verify(deadLetters, never()).park(any(), anyString());
        }

        /**
         * The report itself failing is the worst case, and it must not take the consumer down with
         * it — the row is left PENDING and an operator has a log line naming the transaction.
         */
        @Test
        void a_broker_failure_while_reporting_does_not_rethrow() {
            dispatcherReturns(DeliveryOutcome.sent("SIMULATOR", "p"));
            doThrow(new AmqpException("broker down"))
                    .when(rabbit).send(anyString(), anyString(), any(Message.class));

            assertThatCode(() -> listener.onPosting(payload())).doesNotThrowAnyException();
        }
    }

    @Nested
    @DisplayName("tracing")
    class Tracing {

        /** The bank hop is the far end of a trace that started at the Gateway. */
        @Test
        void the_correlation_id_is_in_scope_while_the_posting_is_made() {
            java.util.concurrent.atomic.AtomicReference<String> seen =
                    new java.util.concurrent.atomic.AtomicReference<>();
            when(dispatcher.dispatch(any(), any(), any())).thenAnswer(call -> {
                seen.set(MDC.get("correlationId"));
                return DeliveryOutcome.sent("SIMULATOR", "p");
            });

            listener.onPosting(payloadWithCorrelation("corr-abc"));

            assertThat(seen.get()).isEqualTo("corr-abc");
        }

        /** Consumer threads are pooled; a leftover id would mislabel the next posting. */
        @Test
        void the_correlation_id_is_cleared_afterwards() {
            dispatcherReturns(DeliveryOutcome.sent("SIMULATOR", "p"));

            listener.onPosting(payloadWithCorrelation("corr-abc"));

            assertThat(MDC.get("correlationId")).isNull();
        }

        @Test
        void it_is_cleared_even_when_the_posting_blows_up() {
            when(dispatcher.dispatch(any(), any(), any()))
                    .thenThrow(new IllegalStateException("boom"));

            listener.onPosting(payloadWithCorrelation("corr-abc"));

            assertThat(MDC.get("correlationId")).isNull();
        }

        /** A posting raised outside any request carries no id, and that must not throw. */
        @Test
        void a_command_with_no_correlation_id_is_handled() {
            dispatcherReturns(DeliveryOutcome.sent("SIMULATOR", "p"));

            assertThatCode(() -> listener.onPosting(payloadWithCorrelation(null)))
                    .doesNotThrowAnyException();
            assertThat(reportedResult().success()).isTrue();
        }
    }
}
