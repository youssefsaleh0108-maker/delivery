package com.delivery.connector.sms;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Outbound SMS (Section 7).
 *
 * <p>The only process in the platform that holds SMS vendor credentials, and it holds nothing else
 * — no database, no template store, no order data. That is the reason it is its own deployable
 * rather than a package inside the SMS worker: the blast radius of a compromised or misbehaving
 * credential-holding process should be as small as the code that needs the credential.
 *
 * <p>Which vendor is live is decided by Connector Settings at runtime, not here. All three clients
 * are built and deployed from Phase 3 so the eventual MontyMobile-or-Twilio decision (Section 12,
 * open decision #6) is a dropdown in the Backoffice rather than a release.
 */
@SpringBootApplication
public class SmsConnectorApplication {

    public static void main(String[] args) {
        SpringApplication.run(SmsConnectorApplication.class, args);
    }
}
