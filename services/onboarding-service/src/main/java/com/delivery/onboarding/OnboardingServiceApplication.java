package com.delivery.onboarding;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;
import org.springframework.retry.annotation.EnableRetry;

/**
 * Joining the platform.
 *
 * <p>A shop or a delivery company applies, somebody at the platform reads it, and if they say yes
 * an account and a domain record are created. Riders and customers never come through here — they
 * sign themselves up in the mobile app and are trading a minute later, because they bring no menu,
 * take no payouts and agree no commercial terms.
 *
 * <p>Its own deployable for two reasons that do not apply to any other service: it is the only one
 * with a write endpoint reachable by somebody with no account at all, and it is the only one
 * carrying a workflow engine.
 *
 * <p>The scans below are widened from this service's own package to {@code com.delivery} because
 * the {@code file_metadata} entity and its repository ship inside the {@code platform-storage} jar,
 * which is what holds the pointers to applicants' uploaded documents. The library deliberately does
 * not declare these annotations itself: {@code @EnableJpaRepositories} anywhere on the classpath
 * switches off Boot's default scan and would hide this service's own repositories.
 */
@SpringBootApplication
@EntityScan(basePackages = "com.delivery")
@EnableJpaRepositories(basePackages = "com.delivery")
@EnableRetry
public class OnboardingServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(OnboardingServiceApplication.class, args);
    }
}
