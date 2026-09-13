package com.delivery.product.service;

import java.time.Duration;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;

import com.delivery.platform.security.CurrentUser;
import com.fasterxml.jackson.databind.JsonNode;

/**
 * Whether the merchant making this request applied to offer services, asked of Onboarding.
 *
 * <p>It exists for one decision. {@link StoreService#requireStoreFor} opens a published restaurant
 * called "My Store" for a merchant who adds a first product with no shop yet. That is right for a
 * shop and wrong for a print shop or a tailor, whose shop has to be a SERVICES store filed under its
 * category — and a shop never moves into SERVICES afterwards, so a restaurant opened by mistake is a
 * mistake for good. The provider's app opens the services shop itself from the application
 * (docs/figma-services-designs.md, slice 3); this is what stops every other path from getting there
 * first with a restaurant.
 *
 * <p>This service keeps no record of what anybody applied to be. Onboarding does, and shows it on the
 * applicant's own receipt ({@code GET /api/onboarding/applications/mine}), whose {@code service} block
 * is present exactly for an application to offer services.
 *
 * <p><strong>The caller's own token is forwarded</strong>, as accounting-service's
 * {@code CarrierCompanyClient} forwards a carrier's. The question is "what did THIS account apply to
 * be", Onboarding answers it from the token's subject, and no account id can be put to it by anybody.
 * It also means this service needs no credential of its own.
 *
 * <p>Asked only when a merchant has no shop at all, so it is one call per merchant, once.
 */
@Component
public class OnboardingApplicationClient {

    private static final Logger log = LoggerFactory.getLogger(OnboardingApplicationClient.class);

    private final RestClient onboarding;

    @Autowired
    public OnboardingApplicationClient(
            RestClient.Builder builder,
            @Value("${delivery.services.onboarding-service:http://localhost:8117}")
            String onboardingUrl) {
        this(builder.clone().baseUrl(onboardingUrl).requestFactory(boundedWait()).build());
    }

    /**
     * Over a client that is already built — for tests, which bind a mock server to their own builder.
     * The public constructor has to set its own request factory for the timeouts, and that would
     * replace a mock bound to the builder it was given.
     */
    OnboardingApplicationClient(RestClient onboarding) {
        this.onboarding = onboarding;
    }

    /**
     * Bounded, because this is asked inside the transaction that would open a merchant's first shop,
     * and the default request factory waits for an unresponsive Onboarding for ever.
     */
    private static SimpleClientHttpRequestFactory boundedWait() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(Duration.ofSeconds(2));
        factory.setReadTimeout(Duration.ofSeconds(3));
        return factory;
    }

    /**
     * Onboarding could not say. Never to be read as "not a services applicant": that answer opens a
     * restaurant, and nothing can turn it into a services shop afterwards.
     */
    public static class OnboardingUnavailableException extends RuntimeException {
        public OnboardingUnavailableException(String message, Throwable cause) {
            super(message, cause);
        }
    }

    /**
     * Whether the caller's own application is one to offer services.
     *
     * <p>False for an account with no application at all (Onboarding's 404) — the realm's seeded
     * merchants and anybody given the role by hand — and for any application that is not a services
     * one.
     *
     * @throws OnboardingUnavailableException when there is no caller token to ask with, when
     *         Onboarding cannot be reached or answers anything but the receipt or a 404, and when the
     *         receipt cannot be read
     */
    public boolean appliedToOfferServices() {
        String token = CurrentUser.jwt().map(Jwt::getTokenValue).orElseThrow(() ->
                new OnboardingUnavailableException(
                        "There is no caller token to ask Onboarding with", null));
        JsonNode receipt;
        try {
            receipt = onboarding.get()
                    .uri("/api/onboarding/applications/mine")
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + token)
                    .retrieve()
                    .body(JsonNode.class);
        } catch (RestClientResponseException e) {
            if (e.getStatusCode().value() == 404) {
                return false;
            }
            log.error("Onboarding could not say what this merchant applied to be: {} {}",
                    e.getStatusCode(), e.getMessage());
            throw new OnboardingUnavailableException(
                    "Could not ask Onboarding what this account applied to be", e);
        } catch (RestClientException e) {
            // Refused, timed out, or unreadable. For the reason above, never "not a services
            // applicant".
            log.error("Onboarding could not say what this merchant applied to be: {}",
                    e.getMessage());
            throw new OnboardingUnavailableException(
                    "Could not ask Onboarding what this account applied to be", e);
        }
        if (receipt == null || !receipt.isObject()) {
            throw new OnboardingUnavailableException(
                    "Onboarding answered with something that is not an application", null);
        }
        return receipt.path("service").isObject();
    }
}
