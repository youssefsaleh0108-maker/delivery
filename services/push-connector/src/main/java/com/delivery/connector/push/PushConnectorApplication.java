package com.delivery.connector.push;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Outbound push notifications (Section 7).
 *
 * <p>Firebase Cloud Messaging covers Android and iOS through one API, which is why the brief fixes
 * the provider rather than making it a runtime choice like SMS.
 *
 * <p>It ships with a second, dev-only provider. Section 7's environment matrix assumes a real dev
 * Firebase project; where there isn't one, a connector whose only provider refuses every message
 * would make the rest of the push path — worker, resilience, receipts, device-token handling —
 * untestable. {@code DEV_LOG} keeps that path exercised, and switching to Firebase is the same
 * Backoffice dropdown the SMS connector uses.
 */
@SpringBootApplication
public class PushConnectorApplication {

    public static void main(String[] args) {
        SpringApplication.run(PushConnectorApplication.class, args);
    }
}
