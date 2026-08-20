package com.delivery.accounting.service;

import java.util.LinkedHashMap;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.delivery.accounting.domain.AccountingTransaction;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Hands one leg to the Core Banking Connector.
 *
 * <p>Over the bus rather than an HTTP call, which is what makes Section 10's "never a blocking call
 * in the order path" structural: there is no synchronous path from here to the bank for anyone to
 * accidentally use.
 *
 * <p>The message carries no commission rate, no order total and no notion of a settlement — only
 * the movement to make. The connector holds bank credentials and should stay ignorant of the
 * business rules that produced the number.
 */
@Component
public class BankPostingPublisher {

    private static final Logger log = LoggerFactory.getLogger(BankPostingPublisher.class);

    /** Must match {@code BankPostingCommand.ROUTING_KEY} in the connector. */
    static final String ROUTING_KEY = "accounting.posting.requested";

    private final RabbitTemplate rabbit;
    private final ObjectMapper objectMapper;
    private final String exchange;

    public BankPostingPublisher(RabbitTemplate rabbit, ObjectMapper objectMapper,
                                @Value("${delivery.outbox.exchange:delivery.events}") String exchange) {
        this.rabbit = rabbit;
        this.objectMapper = objectMapper;
        this.exchange = exchange;
    }

    public void request(AccountingTransaction leg) {
        try {
            Map<String, Object> command = new LinkedHashMap<>();
            // The transaction row id, which becomes the bank's client reference. This is what
            // makes a retried posting one posting in the ledger.
            command.put("transactionId", leg.getId().toString());
            command.put("accountRef", leg.getAccountRef());
            command.put("direction", leg.getDirection().name());
            command.put("amount", leg.getAmount());
            command.put("currency", leg.getCurrency());
            command.put("narrative", narrativeFor(leg));
            command.put("correlationId", leg.getCorrelationId());

            MessageProperties props = new MessageProperties();
            props.setContentType(MessageProperties.CONTENT_TYPE_JSON);
            props.setMessageId(leg.getId().toString());
            if (leg.getCorrelationId() != null) {
                props.setCorrelationId(leg.getCorrelationId());
            }

            rabbit.send(exchange, ROUTING_KEY,
                    new Message(objectMapper.writeValueAsBytes(command), props));

        } catch (Exception e) {
            // The row survives at PENDING, so the reconciliation view shows it as unsettled and an
            // operator can replay it. Loud, because a settlement that was never asked for looks
            // identical to one the bank never answered.
            log.error("Could not request posting for transaction {}", leg.getId(), e);
        }
    }

    /** What appears on the account statement. Written for a human reading it months later. */
    private static String narrativeFor(AccountingTransaction leg) {
        String shortOrder = leg.getOrderId().toString().substring(0, 8).toUpperCase(java.util.Locale.ROOT);
        return switch (leg.getLeg()) {
            case CUSTOMER_DEBIT -> "Delivery order #" + shortOrder;
            // Never reaches a statement — a cash collection is not sent to the bank at all. Named
            // anyway so that if one ever is, the line says what happened rather than being blank.
            case CASH_COLLECTED -> "Cash taken for order #" + shortOrder;
            case CASH_REMITTANCE -> "Takings banked, ref #" + shortOrder;
            case MERCHANT_CREDIT -> "Payout for order #" + shortOrder;
            // Named as an errand rather than a payout: on a BUY most of this is the rider's own
            // money coming back, and a statement line reading "payout" would make a reimbursement
            // look like earnings at tax time.
            case RIDER_CREDIT -> "Errand reimbursement and fee for order #" + shortOrder;
            case PROVIDER_CREDIT -> "Delivery of order #" + shortOrder;
            case PLATFORM_COMMISSION -> "Commission on order #" + shortOrder;
            // Named as what it is. A promotion the platform paid for should be legible as such on
            // the statement months later, not disguised as a negative commission that an accountant
            // has to reverse-engineer.
            case PLATFORM_SUBSIDY -> "Promotion funded on order #" + shortOrder;
            case CUSTOMER_REFUND -> "Refund for order #" + shortOrder;
        };
    }
}
