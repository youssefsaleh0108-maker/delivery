package com.delivery.product;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;

/**
 * Catalog and pricing, product images in MinIO, catalog-change events on the bus (Section 7).
 *
 * <p>Owns the {@code product} schema and nothing else — the per-schema database role means it
 * physically cannot read another service's tables.
 *
 * <p>The scans below are widened from this service's own package to {@code com.delivery} because
 * the {@code outbox_event} and {@code file_metadata} entities and repositories ship inside the
 * {@code platform-outbox} and {@code platform-storage} jars. Every service using those libraries
 * needs these two annotations; the libraries deliberately do not declare them, because
 * {@code @EnableJpaRepositories} anywhere on the classpath disables Boot's default scan and would
 * hide this service's own repositories.
 */
@SpringBootApplication
@EntityScan(basePackages = "com.delivery")
@EnableJpaRepositories(basePackages = "com.delivery")
public class ProductServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(ProductServiceApplication.class, args);
    }

    /**
     * The clock store availability is derived against.
     *
     * <p>A bean rather than {@code Instant.now()} scattered through the service so "is this shop
     * open" can be tested at a chosen moment. Availability depends entirely on the current time, and
     * logic that can only be exercised by waiting for the right hour is logic that will not be
     * tested at all.
     */
    @org.springframework.context.annotation.Bean
    public java.time.Clock clock() {
        return java.time.Clock.systemUTC();
    }
}
