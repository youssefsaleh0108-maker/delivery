package com.delivery.tracking;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;

/**
 * Live rider location and delivery status (Section 7).
 *
 * <p>Owns the {@code tracking} schema, backed by PostGIS for geo-queries and Redis for the
 * "where is my rider right now" hot path. Authorisation is answered from a local projection built
 * from {@code order.*} events off the bus, so the busiest read in the platform never makes a
 * synchronous call to another service.
 *
 * <p>Note this service does NOT depend on platform-outbox: it currently consumes events rather than
 * producing them. Publishing tracking events for the notification layer is a Phase 3 concern.
 */
@SpringBootApplication
@EntityScan(basePackages = "com.delivery")
@EnableJpaRepositories(basePackages = "com.delivery")
// For TrackingPartitionMaintenance. This service writes the platform's highest-volume table, and
// the partition maintenance that keeps it bounded is a scheduled job (Section 10).
@org.springframework.scheduling.annotation.EnableScheduling
public class OrderTrackingApplication {

    public static void main(String[] args) {
        SpringApplication.run(OrderTrackingApplication.class, args);
    }
}
