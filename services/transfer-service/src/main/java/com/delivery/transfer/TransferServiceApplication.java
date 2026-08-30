package com.delivery.transfer;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;

/**
 * Money movement for the Lebanese market.
 *
 * <p>Owns the {@code transfer} schema. One service in the ESB with the provider CONNECTORS inside
 * it behind one SPI — cash today, a simulator standing in for Whish and OMT until the commercial
 * integrations exist. The manager records intent with the platform rate locked at quote time;
 * connectors only carry.
 */
@SpringBootApplication
@EntityScan(basePackages = "com.delivery")
@EnableJpaRepositories(basePackages = "com.delivery")
public class TransferServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(TransferServiceApplication.class, args);
    }
}
