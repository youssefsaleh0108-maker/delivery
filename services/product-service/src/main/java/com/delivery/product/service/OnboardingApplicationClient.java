package com.delivery.product.service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;

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
 * <p>Asked only for a merchant with no shop at all ({@link StoreService#firstShopFor}), before the
 * request's transaction begins, and a yes is remembered for a minute — see
 * {@link #SERVICES_APPLICANT_REMEMBERED_FOR}.
 */
@Component
public class OnboardingApplicationClient {

    private static final Logger log = LoggerFactory.getLogger(OnboardingApplicationClient.class);

    /**
     * How long a "yes, this account applied to offer services" is remembered.
     *
     * <p>Only a yes. A yes is what a services applicant who is still waiting gets on every "add
     * product" and every first scan: refused each time and never given a shop, so nothing stops them
     * sending it again, and each one was a call to Onboarding holding a request thread. A no is
     * followed at once by the restaurant it opens, after which the merchant has a shop and is never
     * asked again, so remembering one would save nothing. Nothing that happens to an application
     * turns a services one into a shop's, and a minute bounds how long a yes can outlive anything
     * else.
     */
    static final Duration SERVICES_APPLICANT_REMEMBERED_FOR = Duration.ofMinutes(1);

    /** More accounts than this remembered at once, and the memory simply starts again. */
    private static final int MOST_REMEMBERED = 10_000;

    private final RestClient onboarding;
    private final Clock clock;

    /** Accounts Onboarding said applied to offer services, by token subject, and when it said so. */
    private final ConcurrentMap<String, Instant> servicesApplicants = new ConcurrentHashMap<>();

    @Autowired
    public OnboardingApplicationClient(
            RestClient.Builder builder,
            @Value("${delivery.services.onboarding-service:http://localhost:8117}")
            String onboardingUrl,
            Clock clock) {
        this(builder.clone().baseUrl(onboardingUrl).requestFactory(boundedWait()).build(), clock);
    }

    /**
     * Over a client that is already built — for tests, which bind a mock server to their own builder.
     * The public constructor has to set its own request factory for the timeouts, and that would
     * replace a mock bound to the builder it was given.
     */
    OnboardingApplicationClient(RestClient onboarding) {
        this(onboarding, Clock.systemUTC());
    }

    /** As above, with a clock the test moves. */
    OnboardingApplicationClient(RestClient onboarding, Clock clock) {
        this.onboarding = onboarding;
        this.clock = clock;
    }

    /**
     * Bounded, because a merchant's request waits on it, and the default request factory waits for an
     * unresponsive Onboarding for ever. It no longer holds a database connection while it waits — it
     * is asked before the transaction (see {@link StoreService#firstShopFor}) — but a request thread
     * is still a thing to give back.
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
        Jwt caller = CurrentUser.jwt().orElseThrow(() ->
                new OnboardingUnavailableException(
                        "There is no caller token to ask Onboarding with", null));
        String account = caller.getSubject();
        Instant now = clock.instant();
        if (account != null && remembersServicesApplicant(account, now)) {
            return true;
        }

        JsonNode receipt;
        try {
            receipt = onboarding.get()
                    .uri("/api/onboarding/applications/mine")
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + caller.getTokenValue())
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
        boolean servicesApplicant = receipt.path("service").isObject();
        if (servicesApplicant && account != null) {
            if (servicesApplicants.size() >= MOST_REMEMBERED) {
                servicesApplicants.clear();
            }
            servicesApplicants.put(account, now);
        }
        return servicesApplicant;
    }

    /** Whether Onboarding said yes about this account within the last minute. */
    private boolean remembersServicesApplicant(String account, Instant now) {
        Instant saidAt = servicesApplicants.get(account);
        if (saidAt == null) {
            return false;
        }
        if (now.isBefore(saidAt.plus(SERVICES_APPLICANT_REMEMBERED_FOR))) {
            return true;
        }
        servicesApplicants.remove(account, saidAt);
        return false;
    }
}
