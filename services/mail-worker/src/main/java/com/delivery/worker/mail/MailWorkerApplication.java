package com.delivery.worker.mail;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * The email channel (Section 7).
 *
 * <p>Consumes {@code notification.dispatch.email} and nothing else. Its own deployable rather than
 * a package in a shared notification service so that a bad release here stops email and only
 * email — the deploy blast radius is one channel, not all three.
 */
@SpringBootApplication
public class MailWorkerApplication {

    public static void main(String[] args) {
        SpringApplication.run(MailWorkerApplication.class, args);
    }
}
