package com.delivery.accounting;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;

/**
 * Owns the settlement saga and the {@code accounting} schema (Section 4, Phase 4).
 *
 * <p><strong>A deviation from the brief worth stating plainly.</strong> Section 7 says Order
 * Manager "triggers the Core Banking Connector for accounting as an async saga", which reads as
 * Order Manager owning the saga. It does not here, for two reasons. The {@code accounting} schema
 * has its own database role from Phase 0 and Order Manager physically cannot write to it — that
 * boundary is enforced by Postgres grants, not convention. And a saga that spans a bank's
 * availability window has a lifetime measured in minutes, which does not belong in the service on
 * the order-placement hot path.
 *
 * <p>What the brief actually requires is preserved: Order Manager publishes {@code order.delivered}
 * through its outbox and knows nothing about accounting, and the bank is never called synchronously
 * from the order path. This service consumes that event, exactly as the notification layer does.
 */
@SpringBootApplication
@EntityScan(basePackages = "com.delivery")
@EnableJpaRepositories(basePackages = "com.delivery")
public class AccountingServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(AccountingServiceApplication.class, args);
    }
}
