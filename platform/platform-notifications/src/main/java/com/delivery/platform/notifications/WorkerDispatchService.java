package com.delivery.platform.notifications;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;
import org.springframework.amqp.rabbit.core.RabbitTemplate;

import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * The body of every channel worker: prepare, dispatch, report.
 *
 * <p>All three workers run exactly this sequence and differ only in their {@link ChannelPreparer}.
 * Keeping the sequence in one place is what guarantees that a message rejected by the SMS worker
 * produces the same log row, the same receipt and the same dead-letter behaviour as one rejected by
 * the mail worker — three copies would drift, and the drift would surface as "this channel's
 * notifications just stay PENDING".
 *
 * <p>Never throws back to the listener. A worker that rethrows makes the broker redeliver, and a
 * message that fails deterministically then loops forever and blocks its channel. Anything
 * unsendable is dead-lettered and reported instead.
 */
public class WorkerDispatchService {

    private static final Logger log = LoggerFactory.getLogger(WorkerDispatchService.class);

    private final String channel;
    private final ChannelPreparer preparer;
    private final ConnectorClient connector;
    private final ResilientDispatcher dispatcher;
    private final DeadLetterPublisher deadLetters;
    private final RabbitTemplate rabbit;
    private final ObjectMapper objectMapper;
    private final String exchange;

    public WorkerDispatchService(String channel, ChannelPreparer preparer, ConnectorClient connector,
                                 ResilientDispatcher dispatcher, DeadLetterPublisher deadLetters,
                                 RabbitTemplate rabbit, ObjectMapper objectMapper, String exchange) {
        this.channel = channel;
        this.preparer = preparer;
        this.connector = connector;
        this.dispatcher = dispatcher;
        this.deadLetters = deadLetters;
        this.rabbit = rabbit;
        this.objectMapper = objectMapper;
        this.exchange = exchange;
    }

    public void handle(String payload) {
        NotificationCommand command;
        try {
            command = objectMapper.readValue(payload, NotificationCommand.class);
        } catch (Exception e) {
            // No notificationId means there is nothing to report a receipt against and nothing to
            // dead-letter usefully. Log the raw payload and ack, rather than poison the queue.
            log.error("Unreadable {} command, dropping: {}", channel, payload, e);
            return;
        }

        // Puts the correlation id back into the logging context on this side of the bus, so the
        // worker's lines join the same trace as the request that caused them.
        boolean correlated = command.correlationId() != null;
        if (correlated) {
            MDC.put(CORRELATION_MDC_KEY, command.correlationId());
        }

        try {
            ChannelPreparer.Prepared prepared = preparer.prepare(command);

            if (prepared.rejected()) {
                // Caught before any provider was contacted, which is the cheap place to catch it.
                log.warn("{} rejected {}: {}", channel, command.notificationId(), prepared.rejection());
                deadLetters.park(command, prepared.rejection());
                report(DeliveryReceipt.from(command, channel + "-worker",
                        DeliveryOutcome.permanentFailure(prepared.rejection())));
                return;
            }

            NotificationCommand toSend = prepared.command();
            DeliveryOutcome outcome = dispatcher.dispatch(toSend, connector::send, deadLetters::park);

            report(DeliveryReceipt.from(command, unreachedProvider(), outcome));

        } catch (Exception e) {
            // A bug in a preparer must not take the channel down with it.
            log.error("{} worker failed on {}", channel, command.notificationId(), e);
            deadLetters.park(command, "worker error: " + e.getMessage());
            report(DeliveryReceipt.from(command, channel + "-worker",
                    DeliveryOutcome.permanentFailure("worker error: " + e.getMessage())));

        } finally {
            if (correlated) {
                MDC.remove(CORRELATION_MDC_KEY);
            }
        }
    }

    /**
     * Sends the outcome back to Notifications Manager.
     *
     * <p>Without this the notification_log row stays PENDING forever and the operator view of
     * "what is stuck" fills with messages that actually went out.
     */
    private void report(DeliveryReceipt receipt) {
        try {
            MessageProperties props = new MessageProperties();
            props.setContentType(MessageProperties.CONTENT_TYPE_JSON);
            props.setMessageId(receipt.notificationId());
            if (receipt.providerMessageId() != null) {
                props.setHeader("providerMessageId", receipt.providerMessageId());
            }

            rabbit.send(exchange, DeliveryReceipt.ROUTING_KEY,
                    new Message(objectMapper.writeValueAsBytes(receipt), props));

        } catch (Exception e) {
            // The message itself was already delivered or dead-lettered; only the bookkeeping is
            // lost. Loud, because a silently missing receipt is what makes the log lie.
            log.error("Could not report the outcome of {}", receipt.notificationId(), e);
        }
    }

    /**
     * Attributed to the worker, not a vendor: this is the label used when the outcome carries no
     * provider, which means no provider was ever reached.
     */
    private String unreachedProvider() {
        return channel.toLowerCase(java.util.Locale.ROOT) + "-worker";
    }

    static final String CORRELATION_MDC_KEY = "correlationId";
}
