package com.delivery.configserver;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.config.server.EnableConfigServer;

/**
 * Every backend microservice pulls its configuration from here at bootstrap (Section 6).
 *
 * <p>Two backends are composited: Git for business parameters and environment variables, Vault for
 * secrets. A client makes one call and receives one merged property set — it never learns that
 * Vault exists, which is the point: Vault credentials stay confined to this service.
 */
@SpringBootApplication
@EnableConfigServer
public class ConfigServerApplication {

    public static void main(String[] args) {
        SpringApplication.run(ConfigServerApplication.class, args);
    }
}
