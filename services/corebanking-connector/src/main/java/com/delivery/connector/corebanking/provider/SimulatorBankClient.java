package com.delivery.connector.corebanking.provider;

import java.util.LinkedHashMap;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import com.delivery.connector.corebanking.BankPostingCommand;
import com.delivery.platform.notifications.DeliveryOutcome;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Talks to the dev Core Banking Simulator.
 *
 * <p>Deliberately written as a real HTTP client with real error classification, not a shortcut.
 * The simulator answers with the statuses a bank answers with, so this class is doing the same work
 * {@link RealBankClient} will do — which means the saga's behaviour under a rejection or an outage
 * is genuinely exercised in dev rather than first observed in staging.
 */
@Component
public class SimulatorBankClient implements BankClient {

    public static final String NAME = "SIMULATOR";

    private static final Logger log = LoggerFactory.getLogger(SimulatorBankClient.class);

    private final RestClient client;
    private final ObjectMapper objectMapper;
    private final String apiKey;

    public SimulatorBankClient(
            RestClient.Builder builder,
            ObjectMapper objectMapper,
            @Value("${delivery.corebanking.simulator.base-url:http://localhost:8114}") String baseUrl,
            @Value("${delivery.corebanking.simulator.api-key:simulator-dev-key}") String apiKey) {
        this.client = builder.baseUrl(baseUrl).build();
        this.objectMapper = objectMapper;
        this.apiKey = apiKey;
    }

    @Override
    public String name() {
        return NAME;
    }

    @Override
    public Response post(BankPostingCommand command) {
        Map<String, Object> body = new LinkedHashMap<>();
        // The accounting transaction id, used as the bank's client reference. This is what makes
        // a retry idempotent all the way through to the ledger.
        body.put("clientReference", command.transactionId());
        body.put("accountRef", command.accountRef());
        body.put("direction", command.direction());
        body.put("amountMinor", command.amountMinor());
        body.put("currency", command.currency());
        body.put("narrative", command.narrative());

        String requestPayload = write(body);

        try {
            ResponseEntity<JsonNode> response = client.post()
                    .uri("/api/core-banking/postings")
                    .header(BANK_API_KEY_HEADER, apiKey)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(body)
                    .retrieve()
                    .onStatus(HttpStatusCode::isError, (req, res) -> {
                        // Classified below from the status, rather than thrown as a generic error
                        // the dispatcher would have to guess about.
                    })
                    .toEntity(JsonNode.class);

            return classify(command, response, requestPayload);

        } catch (Exception e) {
            // Transport-level. Treated as retryable because the posting may well have been made
            // before the connection dropped - and the client reference is what makes retrying that
            // safe rather than a second debit.
            log.warn("Core banking call failed for {}: {}", command.transactionId(), e.getMessage());
            return new Response(
                    DeliveryOutcome.transientFailure(NAME, "bank unreachable: " + e.getMessage()),
                    requestPayload,
                    null);
        }
    }

    @Override
    public AccountCheck lookup(String accountRef) {
        try {
            ResponseEntity<JsonNode> response = client.get()
                    .uri("/api/core-banking/accounts/{ref}", accountRef)
                    .header(BANK_API_KEY_HEADER, apiKey)
                    .retrieve()
                    .onStatus(HttpStatusCode::isError, (req, res) -> {
                        // Classified below. A 404 here is an answer, not a transport failure.
                    })
                    .toEntity(JsonNode.class);

            int status = response.getStatusCode().value();
            JsonNode body = response.getBody();

            if (status == 404) {
                return AccountCheck.refused(accountRef, "no such account at the bank");
            }
            if (status == 401 || status == 403) {
                // Our key, not their account. Refusing a carrier because this connector is
                // misconfigured would blame the wrong party for the wrong thing.
                log.error("Core banking rejected our credentials on an account lookup");
                return AccountCheck.unknown(accountRef, "the bank rejected our credentials");
            }
            if (!response.getStatusCode().is2xxSuccessful() || body == null) {
                return AccountCheck.unknown(accountRef, "HTTP " + status);
            }

            String accountStatus = body.path("status").asText("UNKNOWN");
            if (!"ACTIVE".equals(accountStatus)) {
                // Exists, but money cannot land in it. Every bit as unpayable as a typo, and far
                // more confusing to discover after a delivery.
                return AccountCheck.refused(accountRef, "the account is " + accountStatus);
            }
            return AccountCheck.usable(accountRef, body.path("holderName").asText(null));

        } catch (Exception e) {
            log.warn("Could not look up account {}: {}", accountRef, e.getMessage());
            return AccountCheck.unknown(accountRef, "bank unreachable: " + e.getMessage());
        }
    }

    /**
     * Maps HTTP status to retryable or not.
     *
     * <p>The distinction decides whether the saga waits or compensates. A 422 is the bank saying no
     * with certainty — insufficient funds, frozen account — and retrying it moves nothing. A 5xx or
     * a 429 is the bank saying not now.
     */
    private Response classify(BankPostingCommand command, ResponseEntity<JsonNode> response,
                              String requestPayload) {
        JsonNode body = response.getBody();
        String responsePayload = body == null ? null : body.toString();
        int status = response.getStatusCode().value();

        if (response.getStatusCode().is2xxSuccessful() && body != null) {
            if (body.path("replayed").asBoolean(false)) {
                // The bank recognised our reference and did not move money again. Exactly the
                // behaviour the idempotency key exists to produce; a success, not a warning.
                log.info("Bank replayed posting for {}", command.transactionId());
            }
            return new Response(
                    DeliveryOutcome.sent(NAME, body.path("postingId").asText(null)),
                    requestPayload, responsePayload);
        }

        String reason = body == null
                ? "HTTP " + status
                : body.path("rejectionReason").asText(body.path("detail").asText("HTTP " + status));

        if (status == 422) {
            return new Response(DeliveryOutcome.permanentFailure(NAME, reason),
                    requestPayload, responsePayload);
        }
        if (status == 401 || status == 403) {
            // Our credentials are wrong. Permanent: no amount of retrying fixes a bad key, and
            // hammering a bank with unauthenticated requests is its own problem.
            log.error("Core banking rejected our credentials - no posting will succeed");
            return new Response(DeliveryOutcome.permanentFailure(NAME, "bank rejected our credentials"),
                    requestPayload, responsePayload);
        }
        if (status == 400 || status == 404) {
            return new Response(DeliveryOutcome.permanentFailure(NAME, reason),
                    requestPayload, responsePayload);
        }
        return new Response(DeliveryOutcome.transientFailure(NAME, reason),
                requestPayload, responsePayload);
    }

    private String write(Object value) {
        try {
            return objectMapper.writeValueAsString(value);
        } catch (Exception e) {
            return String.valueOf(value);
        }
    }

    /** Matches the simulator's expected header; the real bank's will differ. */
    static final String BANK_API_KEY_HEADER = "X-Bank-Api-Key";
}
