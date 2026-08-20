package com.delivery.platform.notifications;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;
import org.springframework.amqp.rabbit.core.RabbitTemplate;

import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Parks a message that will never be delivered, so an operator can find it (Section 10).
 *
 * <p>Published to the default exchange with the queue name as the routing key, which puts it
 * straight on a durable queue nothing consumes. The alternative — logging and dropping — loses the
 * recipient and body, and those are exactly what someone needs to resend by hand.
 *
 * <p>The reason is attached as a header rather than folded into the body so the original command
 * can be replayed onto a dispatch queue unchanged once the underlying problem is fixed.
 */
public class DeadLetterPublisher {

    private static final Logger log = LoggerFactory.getLogger(DeadLetterPublisher.class);

    private final RabbitTemplate rabbit;
    private final ObjectMapper objectMapper;
    private final String queue;

    public DeadLetterPublisher(RabbitTemplate rabbit, ObjectMapper objectMapper, String queue) {
        this.rabbit = rabbit;
        this.objectMapper = objectMapper;
        this.queue = queue;
    }

    public void park(IdempotentCommand command, String reason) {
        try {
            MessageProperties props = new MessageProperties();
            props.setContentType(MessageProperties.CONTENT_TYPE_JSON);
            props.setMessageId(command.idempotencyKey());
            props.setHeader("x-dead-letter-reason", reason);
            props.setHeader("x-dead-lettered-at", Instant.now().toString());
            if (command instanceof NotificationCommand notification) {
                props.setHeader("channel", notification.channel());
            }
            if (command.correlationId() != null) {
                props.setCorrelationId(command.correlationId());
            }

            Map<String, Object> envelope = new LinkedHashMap<>();
            envelope.put("command", command);
            envelope.put("reason", reason);

            // Default exchange (""), routing key = queue name: a direct put onto the DLQ.
            rabbit.send("", queue, new Message(objectMapper.writeValueAsBytes(envelope), props));
            log.warn("Dead-lettered {}: {}", command.idempotencyKey(), reason);

        } catch (Exception e) {
            // Last resort. If even the DLQ is unreachable the body still reaches the log, which is
            // the only remaining place to recover the message from.
            log.error("Could not dead-letter {} ({}). Command was: {}",
                    command.idempotencyKey(), reason, command, e);
        }
    }
}
