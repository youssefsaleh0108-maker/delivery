package com.delivery.platform.outbox;

import java.nio.charset.StandardCharsets;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.amqp.AmqpException;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageDeliveryMode;
import org.springframework.amqp.core.MessageProperties;
import org.springframework.amqp.rabbit.core.RabbitTemplate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The relay: committed rows onto the bus, and what happens when the bus will not take them.
 *
 * <p>Delivery is deliberately at-least-once, so the properties worth pinning are the ones a
 * consumer relies on to cope with that — a stable dedupe key on every message, and the correlation
 * id surviving the hop — plus the failure handling, where one bad row must not take the batch with
 * it.
 */
class OutboxRelayTest {

    private OutboxEventRepository repository;
    private RabbitTemplate rabbit;
    private OutboxProperties properties;
    private OutboxRelay relay;

    @BeforeEach
    void setUp() {
        repository = mock(OutboxEventRepository.class);
        rabbit = mock(RabbitTemplate.class);
        properties = new OutboxProperties();
        relay = new OutboxRelay(repository, rabbit, properties);
    }

    private static OutboxEvent event(String type, String payload) {
        return new OutboxEvent("Order", "order-1", type, payload, "corr-1");
    }

    @Nested
    @DisplayName("the happy path")
    class Publishing {

        @Test
        void does_nothing_when_there_is_nothing_pending() {
            when(repository.claimPendingBatch(anyInt())).thenReturn(List.of());

            relay.publishPending();

            verify(rabbit, never()).send(anyString(), anyString(), any(Message.class));
            verify(repository, never()).saveAll(any());
        }

        @Test
        void publishes_each_claimed_row_and_marks_it() {
            OutboxEvent first = event("order.placed", "{\"id\":1}");
            OutboxEvent second = event("order.delivered", "{\"id\":2}");
            when(repository.claimPendingBatch(anyInt())).thenReturn(List.of(first, second));

            relay.publishPending();

            verify(rabbit).send(eq("delivery.events"), eq("order.placed"), any(Message.class));
            verify(rabbit).send(eq("delivery.events"), eq("order.delivered"), any(Message.class));
            assertThat(first.getStatus()).isEqualTo(OutboxEvent.Status.PUBLISHED);
            assertThat(second.getStatus()).isEqualTo(OutboxEvent.Status.PUBLISHED);
            verify(repository).saveAll(List.of(first, second));
        }

        /** The event type doubles as the routing key, so a consumer's binding depends on it. */
        @Test
        void routes_on_the_event_type() {
            when(repository.claimPendingBatch(anyInt()))
                    .thenReturn(List.of(event("catalog.product.published", "{}")));

            relay.publishPending();

            verify(rabbit).send(anyString(), eq("catalog.product.published"), any(Message.class));
        }
    }

    @Nested
    @DisplayName("the message a consumer receives")
    class MessageShape {

        private Message published(OutboxEvent event) {
            when(repository.claimPendingBatch(anyInt())).thenReturn(List.of(event));
            relay.publishPending();

            ArgumentCaptor<Message> captor = ArgumentCaptor.forClass(Message.class);
            verify(rabbit).send(anyString(), anyString(), captor.capture());
            return captor.getValue();
        }

        /**
         * At-least-once delivery is only survivable if consumers can dedupe, and the outbox row id
         * is the key they are told to use. Losing it turns every relay republish into a duplicate
         * order event with nothing to detect it by.
         */
        @Test
        void carries_the_outbox_row_id_as_the_dedupe_key() {
            OutboxEvent event = event("order.placed", "{}");

            assertThat(published(event).getMessageProperties().getMessageId())
                    .isEqualTo(event.getId().toString());
        }

        @Test
        void carries_the_correlation_id_so_a_trace_survives_the_hop() {
            MessageProperties props = published(event("order.placed", "{}")).getMessageProperties();

            assertThat(props.getCorrelationId()).isEqualTo("corr-1");
            assertThat(props.<String>getHeader(CorrelationId.HEADER)).isEqualTo("corr-1");
        }

        /** An event recorded outside any request has no correlation id; that must not throw. */
        @Test
        void tolerates_an_event_recorded_without_a_correlation_id() {
            OutboxEvent orphan = new OutboxEvent("Order", "order-1", "order.placed", "{}", null);

            MessageProperties props = published(orphan).getMessageProperties();

            assertThat(props.getCorrelationId()).isNull();
            assertThat(orphan.getStatus()).isEqualTo(OutboxEvent.Status.PUBLISHED);
        }

        /** A non-persistent message is lost on a broker restart, defeating the whole outbox. */
        @Test
        void is_persistent_json_with_the_routing_metadata_a_consumer_filters_on() {
            MessageProperties props = published(event("order.placed", "{}")).getMessageProperties();

            assertThat(props.getDeliveryMode()).isEqualTo(MessageDeliveryMode.PERSISTENT);
            assertThat(props.getContentType()).isEqualTo(MessageProperties.CONTENT_TYPE_JSON);
            assertThat(props.<String>getHeader("eventType")).isEqualTo("order.placed");
            assertThat(props.<String>getHeader("aggregateType")).isEqualTo("Order");
            assertThat(props.<String>getHeader("aggregateId")).isEqualTo("order-1");
        }

        @Test
        void carries_the_payload_verbatim() {
            Message message = published(event("order.placed", "{\"total\":19.50}"));

            assertThat(new String(message.getBody(), StandardCharsets.UTF_8))
                    .isEqualTo("{\"total\":19.50}");
        }
    }

    @Nested
    @DisplayName("when the broker refuses")
    class Failures {

        @Test
        void records_the_failure_and_leaves_the_row_pending_for_a_later_tick() {
            OutboxEvent event = event("order.placed", "{}");
            when(repository.claimPendingBatch(anyInt())).thenReturn(List.of(event));
            doThrow(new AmqpException("connection refused"))
                    .when(rabbit).send(anyString(), anyString(), any(Message.class));

            relay.publishPending();

            assertThat(event.getStatus()).isEqualTo(OutboxEvent.Status.PENDING);
            assertThat(event.getAttempts()).isEqualTo(1);
            assertThat(event.getLastError()).contains("connection refused");
            verify(repository).saveAll(List.of(event));
        }

        /**
         * One unroutable message must not stall everything queued behind it. The catch is
         * per-event for this reason, and it is easy to "simplify" back into a single try around
         * the loop.
         */
        @Test
        void one_poison_row_does_not_block_the_rest_of_the_batch() {
            OutboxEvent poison = event("order.broken", "{}");
            OutboxEvent healthy = event("order.placed", "{}");
            when(repository.claimPendingBatch(anyInt())).thenReturn(List.of(poison, healthy));
            doThrow(new AmqpException("rejected"))
                    .when(rabbit).send(anyString(), eq("order.broken"), any(Message.class));

            relay.publishPending();

            assertThat(poison.getStatus()).isEqualTo(OutboxEvent.Status.PENDING);
            assertThat(healthy.getStatus()).isEqualTo(OutboxEvent.Status.PUBLISHED);
        }

        /**
         * A broker outage must cost the row a delay, not its whole attempt budget. This is the
         * regression guard for the defect the backoff was added to fix.
         */
        @Test
        void a_failure_defers_the_next_attempt_rather_than_burning_the_budget() {
            OutboxEvent event = event("order.placed", "{}");
            when(repository.claimPendingBatch(anyInt())).thenReturn(List.of(event));
            doThrow(new AmqpException("unreachable"))
                    .when(rabbit).send(anyString(), anyString(), any(Message.class));

            relay.publishPending();

            assertThat(event.getNextAttemptAt()).isAfter(event.getCreatedAt().plusSeconds(5));
            assertThat(event.getAttempts()).isLessThan(properties.getMaxAttempts());
        }

        @Test
        void dead_letters_only_after_the_configured_attempts() {
            properties.setMaxAttempts(2);
            OutboxEvent event = event("order.placed", "{}");
            when(repository.claimPendingBatch(anyInt())).thenReturn(List.of(event));
            doThrow(new AmqpException("unreachable"))
                    .when(rabbit).send(anyString(), anyString(), any(Message.class));

            relay.publishPending();
            assertThat(event.getStatus()).isEqualTo(OutboxEvent.Status.PENDING);

            relay.publishPending();
            assertThat(event.getStatus()).isEqualTo(OutboxEvent.Status.DEAD_LETTERED);
        }

        /**
         * The batch is saved even when every row in it failed — otherwise the attempt counts roll
         * back with the transaction and the row is retried forever with {@code attempts} stuck at
         * zero.
         */
        @Test
        void persists_attempt_counts_even_when_nothing_published() {
            OutboxEvent event = event("order.placed", "{}");
            when(repository.claimPendingBatch(anyInt())).thenReturn(List.of(event));
            doThrow(new AmqpException("down"))
                    .when(rabbit).send(anyString(), anyString(), any(Message.class));

            relay.publishPending();

            verify(repository).saveAll(List.of(event));
        }
    }
}
