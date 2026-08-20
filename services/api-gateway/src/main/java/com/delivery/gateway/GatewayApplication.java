package com.delivery.gateway;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * The single entry point for all three Flutter clients (Section 2).
 *
 * <p>Validates the Keycloak JWT once at the edge and forwards claims downstream, generates the
 * correlation id that follows a request through every service it touches, and applies rate limiting
 * before any domain service spends work on a request.
 *
 * <p>Note that edge validation does not make downstream validation optional: each service is its own
 * resource server and re-validates, so a service reached inside the cluster is never implicitly
 * trusted (Section 2).
 */
@SpringBootApplication
public class GatewayApplication {

    public static void main(String[] args) {
        SpringApplication.run(GatewayApplication.class, args);
    }
}
