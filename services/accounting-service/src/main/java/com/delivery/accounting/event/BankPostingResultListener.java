package com.delivery.accounting.event;

import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

import com.delivery.accounting.service.SettlementSaga;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Feeds the bank's answers back into the saga.
 *
 * <p>Without this every leg would sit at PENDING: the connector is a separate process and the
 * saga never learns anything synchronously. A lost result is worse than a failed posting, because
 * a failure is visible and a silence looks like progress.
 */
@Component
public class BankPostingResultListener {

    private static final Logger log = LoggerFactory.getLogger(BankPostingResultListener.class);

    private final SettlementSaga saga;
    private final ObjectMapper objectMapper;

    public BankPostingResultListener(SettlementSaga saga, ObjectMapper objectMapper) {
        this.saga = saga;
        this.objectMapper = objectMapper;
    }

    @RabbitListener(queues = "${delivery.accounting.results-queue:accounting.posting-results}")
    public void onResult(String payload) {
        try {
            JsonNode result = objectMapper.readTree(payload);

            saga.onResult(
                    UUID.fromString(result.path("transactionId").asText()),
                    result.path("success").asBoolean(false),
                    result.path("retryable").asBoolean(false),
                    result.path("provider").asText(null),
                    result.path("coreBankingRef").asText(null),
                    result.path("failureReason").asText(null),
                    result.path("requestPayload").asText(null),
                    result.path("responsePayload").asText(null));

        } catch (Exception e) {
            // Acked regardless. A result that cannot be parsed leaves its leg PENDING, which the
            // reconciliation view surfaces — far better than a redelivery loop that blocks every
            // other settlement's results behind it.
            log.error("Could not apply posting result: {}", payload, e);
        }
    }
}
