package com.delivery.notifications;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;

/**
 * The business half of the notification layer (Section 7).
 *
 * <p>Owns the {@code notification} schema — templates, rendering and the log — and decides who
 * should hear about a domain event. It never talks to a provider and holds no provider credentials:
 * it publishes one rendered command per channel and the matching worker takes it from there.
 *
 * <p>That split is what makes the notification log trustworthy. The row is written here, before
 * anything is dispatched, and updated from the worker's receipt; a log written by whoever happened
 * to send the message would have a gap exactly where the interesting failures are.
 */
@SpringBootApplication
@EntityScan(basePackages = "com.delivery")
@EnableJpaRepositories(basePackages = "com.delivery")
public class NotificationsManagerApplication {

    public static void main(String[] args) {
        SpringApplication.run(NotificationsManagerApplication.class, args);
    }
}
