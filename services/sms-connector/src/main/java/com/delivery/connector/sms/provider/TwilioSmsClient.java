package com.delivery.connector.sms.provider;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestClient;

import com.delivery.platform.notifications.DeliveryOutcome;
import com.delivery.platform.notifications.NotificationCommand;
import com.delivery.platform.notifications.ProviderClient;
import com.fasterxml.jackson.databind.JsonNode;

/**
 * Twilio's Programmable Messaging API.
 *
 * <p>Built in Phase 3 but not expected to be live at launch (Section 12, open decision #6). It ships
 * anyway so the cutover is a Backoffice dropdown rather than a development project — which is the
 * whole justification for the provider abstraction.
 *
 * <p>Credentials come from Vault through the Config Server and are never read from the settings
 * table or logged. If the account SID is blank this client refuses every message permanently rather
 * than calling Twilio unauthenticated: an unconfigured vendor that fails loudly is far better than
 * one that half-works.
 */
@Component
public class TwilioSmsClient implements ProviderClient {

    public static final String NAME = "TWILIO";

    private static final Logger log = LoggerFactory.getLogger(TwilioSmsClient.class);

    private final RestClient client;
    private final String accountSid;
    private final String authToken;
    private final String fromNumber;

    public TwilioSmsClient(RestClient.Builder builder,
                           @Value("${delivery.sms.twilio.base-url:https://api.twilio.com}") String baseUrl,
                           @Value("${delivery.sms.twilio.account-sid:}") String accountSid,
                           @Value("${delivery.sms.twilio.auth-token:}") String authToken,
                           @Value("${delivery.sms.twilio.from:}") String fromNumber) {
        this.client = builder.baseUrl(baseUrl).build();
        this.accountSid = accountSid;
        this.authToken = authToken;
        this.fromNumber = fromNumber;
    }

    @Override
    public String name() {
        return NAME;
    }

    @Override
    public DeliveryOutcome send(NotificationCommand command) {
        if (accountSid.isBlank() || authToken.isBlank()) {
            return DeliveryOutcome.permanentFailure(NAME,
                    "Twilio credentials are not provisioned in Vault");
        }

        MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("To", command.recipient());
        form.add("From", fromNumber);
        form.add("Body", command.body());

        try {
            JsonNode response = client.post()
                    .uri("/2010-04-01/Accounts/{sid}/Messages.json", accountSid)
                    .headers(headers -> headers.setBasicAuth(accountSid, authToken))
                    .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                    .body(form)
                    .retrieve()
                    .onStatus(HttpStatusCode::isError, (req, res) -> {
                        // Swallowed so the status can be classified below rather than thrown as a
                        // generic exception the dispatcher would have to guess about.
                    })
                    .body(JsonNode.class);

            if (response == null) {
                return DeliveryOutcome.transientFailure(NAME, "empty response from Twilio");
            }

            // Twilio reports application errors in the body with an HTTP error status; `sid` is
            // present only on success.
            if (response.hasNonNull("sid")) {
                return DeliveryOutcome.sent(NAME, response.get("sid").asText());
            }

            int code = response.path("code").asInt();
            String message = response.path("message").asText("Twilio rejected the message");
            return classify(code, message);

        } catch (Exception e) {
            log.warn("Twilio call failed for {}: {}", command.notificationId(), e.getMessage());
            return DeliveryOutcome.transientFailure(NAME, e.getMessage());
        }
    }

    /**
     * Maps Twilio error codes to retryable or not.
     *
     * <p>The distinction is what stops the platform paying to re-send to a number that will never
     * accept it: 21211 is "not a valid phone number", and no amount of backoff changes that.
     */
    private DeliveryOutcome classify(int code, String message) {
        boolean permanent = switch (code) {
            case 21211,  // invalid 'To' number
                 21408,  // permission to send to this region not enabled
                 21610,  // recipient has unsubscribed
                 21614 -> true;  // 'To' number is not SMS-capable
            default -> false;
        };
        return permanent
                ? DeliveryOutcome.permanentFailure(NAME, code + ": " + message)
                : DeliveryOutcome.transientFailure(NAME, code + ": " + message);
    }
}
