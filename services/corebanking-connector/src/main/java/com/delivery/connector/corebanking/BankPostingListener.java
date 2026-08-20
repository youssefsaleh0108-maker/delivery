package com.delivery.connector.corebanking;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.delivery.connector.corebanking.provider.BankClient;
import com.delivery.platform.notifications.ActiveProviderRegistry;
import com.delivery.platform.notifications.DeadLetterPublisher;
import com.delivery.platform.notifications.DeliveryOutcome;
import com.delivery.platform.notifications.ResilientDispatcher;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Consumes postings off the bus, posts them to whichever bank is live, and reports back.
 *
 * <p>Queue-driven rather than an HTTP endpoint, unlike the three notification connectors. Section
 * 10 requires the bank to be an asynchronous saga so a slow bank never holds up an order, and a
 * queue makes that structural rather than a convention someone can later call synchronously.
 *
 * <p>Never rethrows. A rejected posting is a business outcome the saga has to act on, not a message
 * to redeliver — and a redelivery loop against a bank is the one failure mode nobody wants.
 */
@Component
public class BankPostingListener {

    private static final Logger log = LoggerFactory.getLogger(BankPostingListener.class);

    private final Map<String, BankClient> clients = new LinkedHashMap<>();
    private final ActiveProviderRegistry registry;
    private final ResilientDispatcher dispatcher;
    private final DeadLetterPublisher deadLetters;
    private final RabbitTemplate rabbit;
    private final ObjectMapper objectMapper;
    private final String exchange;

    public BankPostingListener(List<BankClient> bankClients,
                               ActiveProviderRegistry registry,
                               ResilientDispatcher bankDispatcher,
                               DeadLetterPublisher deadLetterPublisher,
                               RabbitTemplate rabbit,
                               ObjectMapper objectMapper,
                               @Value("${delivery.outbox.exchange:delivery.events}") String exchange) {
        bankClients.forEach(client -> this.clients.put(client.name(), client));
        this.registry = registry;
        this.dispatcher = bankDispatcher;
        this.deadLetters = deadLetterPublisher;
        this.rabbit = rabbit;
        this.objectMapper = objectMapper;
        this.exchange = exchange;
    }

    @RabbitListener(queues = "#{bankPostingQueue.name}")
    public void onPosting(String payload) {
        BankPostingCommand command;
        try {
            command = objectMapper.readValue(payload, BankPostingCommand.class);
        } catch (Exception e) {
            // No transaction id means nothing to report against and nothing useful to dead-letter.
            log.error("Unreadable posting command, dropping: {}", payload, e);
            return;
        }

        boolean correlated = command.correlationId() != null;
        if (correlated) {
            MDC.put("correlationId", command.correlationId());
        }

        try {
            String provider = registry.activeProvider();
            BankClient client = clients.get(provider);

            if (client == null) {
                // Settings name a provider this build has no client for. Permanent, and loud:
                // Connector Settings and the deployed connector disagree about what exists.
                log.error("No bank client for active provider {} (have {})", provider, clients.keySet());
                report(BankPostingResult.from(command,
                        DeliveryOutcome.permanentFailure(provider, "no client for provider " + provider),
                        null, null));
                deadLetters.park(command, "no client for provider " + provider);
                return;
            }

            // Captured across the retry so the payloads that reach the sync log are the ones from
            // the attempt that actually decided the outcome.
            java.util.concurrent.atomic.AtomicReference<BankClient.Response> last =
                    new java.util.concurrent.atomic.AtomicReference<>();

            DeliveryOutcome outcome = dispatcher.dispatch(
                    command,
                    toSend -> {
                        BankClient.Response response = client.post(toSend);
                        last.set(response);
                        return response.outcome();
                    },
                    deadLetters::park);

            BankClient.Response response = last.get();
            report(BankPostingResult.from(command, outcome,
                    response == null ? null : response.requestPayload(),
                    response == null ? null : response.responsePayload()));

        } catch (Exception e) {
            log.error("Core banking connector failed on {}", command.transactionId(), e);
            report(BankPostingResult.from(command,
                    DeliveryOutcome.permanentFailure("connector error: " + e.getMessage()), null, null));
            deadLetters.park(command, "connector error: " + e.getMessage());

        } finally {
            if (correlated) {
                MDC.remove("correlationId");
            }
        }
    }

    /**
     * Tells the accounting saga what happened.
     *
     * <p>Without this the transaction row sits at PENDING and the settlement never completes or
     * compensates — money debited from a customer with nothing crediting the merchant is the worst
     * state this system can be in, so a lost result is worse than a failed posting.
     */
    private void report(BankPostingResult result) {
        try {
            MessageProperties props = new MessageProperties();
            props.setContentType(MessageProperties.CONTENT_TYPE_JSON);
            props.setMessageId(result.transactionId());

            rabbit.send(exchange, BankPostingResult.ROUTING_KEY,
                    new Message(objectMapper.writeValueAsBytes(result), props));

        } catch (Exception e) {
            log.error("Could not report the outcome of posting {} - the saga will be left waiting",
                    result.transactionId(), e);
        }
    }
}
