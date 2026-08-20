package com.delivery.appnotification;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;

/**
 * In-app messages, persisted and delivered live (Section 7).
 *
 * <p>The one notification service that is stateful: it holds open WebSocket connections, so it
 * scales on concurrent users rather than on message throughput. That is the opposite profile to the
 * stateless workers, and the reason it is a separate deployable rather than a package inside one of
 * them.
 *
 * <p>Owns {@code in_app_messages} in the shared {@code notification} schema — see
 * {@code V20__in_app_messages.sql} for why the schema is shared and how the two Flyway histories
 * are kept apart.
 */
@SpringBootApplication
@EntityScan(basePackages = "com.delivery")
@EnableJpaRepositories(basePackages = "com.delivery")
public class AppNotificationApplication {

    public static void main(String[] args) {
        SpringApplication.run(AppNotificationApplication.class, args);
    }
}
