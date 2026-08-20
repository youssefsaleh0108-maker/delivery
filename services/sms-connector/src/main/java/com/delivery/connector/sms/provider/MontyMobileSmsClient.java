package com.delivery.connector.sms.provider;

import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import com.delivery.platform.notifications.DeliveryOutcome;
import com.delivery.platform.notifications.NotificationCommand;
import com.delivery.platform.notifications.ProviderClient;
import com.fasterxml.jackson.databind.JsonNode;

/**
 * MontyMobile's bulk SMS API.
 *
 * <p>The other half of Section 12's open decision #6. Built alongside {@link TwilioSmsClient} so
 * the commercial choice can be made after launch without a code change either way.
 *
 * <p><strong>Contract caveat:</strong> the request and response shapes below follow MontyMobile's
 * published v1 SendSMS endpoint. The base URL and both field names are configurable rather than
 * hard-coded precisely because that spec has to be confirmed against the account's own
 * documentation when credentials are provisioned — a vendor API that was integrated against a
 * guessed contract fails on the first real send, which is the worst time to discover it.
 */
@Component
public class MontyMobileSmsClient implements ProviderClient {

    public static final String NAME = "MONTYMOBILE";

    private static final Logger log = LoggerFactory.getLogger(MontyMobileSmsClient.class);

    private final RestClient client;
    private final String apiKey;
    private final String senderId;
    private final String sendPath;

    public MontyMobileSmsClient(
            RestClient.Builder builder,
            @Value("${delivery.sms.montymobile.base-url:https://api.montymobile.com}") String baseUrl,
            @Value("${delivery.sms.montymobile.send-path:/api/v1/SMS/Send}") String sendPath,
            @Value("${delivery.sms.montymobile.api-key:}") String apiKey,
            @Value("${delivery.sms.montymobile.sender-id:DELIVERY}") String senderId) {
        this.client = builder.baseUrl(baseUrl).build();
        this.sendPath = sendPath;
        this.apiKey = apiKey;
        this.senderId = senderId;
    }

    @Override
    public String name() {
        return NAME;
    }

    @Override
    public DeliveryOutcome send(NotificationCommand command) {
        if (apiKey.isBlank()) {
            return DeliveryOutcome.permanentFailure(NAME,
                    "MontyMobile API key is not provisioned in Vault");
        }

        try {
            JsonNode response = client.post()
                    .uri(sendPath)
                    .header("ApiKey", apiKey)
                    // The notification id is the platform's idempotency key end to end; passing it
                    // as the client message reference is what lets a retry be recognised as the
                    // same message rather than billed as a second one.
                    .header("X-Client-Message-Id", command.notificationId())
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(Map.of(
                            "senderName", senderId,
                            "mobileNumbers", command.recipient(),
                            "smsBody", command.body(),
                            "clientMessageId", command.notificationId()))
                    .retrieve()
                    .onStatus(HttpStatusCode::isError, (req, res) -> {
                        // Classified from the body below rather than thrown.
                    })
                    .body(JsonNode.class);

            if (response == null) {
                return DeliveryOutcome.transientFailure(NAME, "empty response from MontyMobile");
            }

            if (response.path("isSuccess").asBoolean(false)) {
                return DeliveryOutcome.sent(NAME,
                        response.path("messageId").asText(command.notificationId()));
            }

            String code = response.path("statusCode").asText("UNKNOWN");
            String message = response.path("message").asText("MontyMobile rejected the message");
            return classify(code, message);

        } catch (Exception e) {
            log.warn("MontyMobile call failed for {}: {}", command.notificationId(), e.getMessage());
            return DeliveryOutcome.transientFailure(NAME, e.getMessage());
        }
    }

    /** Invalid numbers and blocked destinations never succeed; anything else may. */
    private DeliveryOutcome classify(String statusCode, String message) {
        boolean permanent = switch (statusCode) {
            case "INVALID_MOBILE_NUMBER", "BLACKLISTED", "INVALID_SENDER_ID", "UNSUPPORTED_DESTINATION"
                    -> true;
            default -> false;
        };
        return permanent
                ? DeliveryOutcome.permanentFailure(NAME, statusCode + ": " + message)
                : DeliveryOutcome.transientFailure(NAME, statusCode + ": " + message);
    }
}
