package com.delivery.connector.email;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Outbound email (Section 7).
 *
 * <p>Talks to an SMTP relay rather than a vendor HTTP API. That choice is what makes this the one
 * connector with a fixed provider list: swapping the relay is a host and credential change in the
 * Config Server, not a new client implementation, so there is nothing here for the Backoffice
 * provider dropdown to choose between.
 */
@SpringBootApplication
public class EmailConnectorApplication {

    public static void main(String[] args) {
        SpringApplication.run(EmailConnectorApplication.class, args);
    }
}
