package com.delivery.settings;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;

/**
 * Business-user-managed connector configuration (Section 8).
 *
 * <p>Owns the {@code settings} schema. Deliberately separate from the Spring Cloud Config Server:
 * that holds ops-managed values changed through a Git commit and a pipeline, while this holds the
 * few a non-engineer changes from a Backoffice screen — primarily which SMS provider is live.
 *
 * <p>Never stores secrets. Only the Vault path they can be read from, so the UI can show a masked
 * value and a rotation date without a credential reaching a browser.
 */
@SpringBootApplication
@EntityScan(basePackages = "com.delivery")
@EnableJpaRepositories(basePackages = "com.delivery")
public class ConnectorSettingsApplication {

    public static void main(String[] args) {
        SpringApplication.run(ConnectorSettingsApplication.class, args);
    }
}
