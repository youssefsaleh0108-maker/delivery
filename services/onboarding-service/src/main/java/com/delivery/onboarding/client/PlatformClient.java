package com.delivery.onboarding.client;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestClient;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * Creating the domain record behind a newly approved partner.
 *
 * <p>This service calls the platform's own APIs rather than writing to their tables, because those
 * tables belong to other services and a cross-schema insert is exactly the coupling
 * schema-per-service exists to prevent. Registering a delivery company through Order Manager also
 * means the payout account is verified at the bank on the way in, which a direct insert would skip.
 *
 * <p><strong>It acts as the platform.</strong> Registering a fleet is a BACKOFFICE action, so the
 * service account carries that role and its client id has to be on
 * {@code delivery.security.allowed-client-ids} — which is a deliberate change: until now the
 * allow-list held only interactive clients, and the service accounts on it called Keycloak's admin
 * API rather than ours. This one calls ours, and it is the only one that does.
 *
 * <p>It also reads two lists from Product Service for somebody applying to offer services: which
 * service categories are open, and the curated delivery zones they pick their area from. Product
 * Service owns both — the category switch is its configuration, read per call — so asking it is what
 * keeps this service from holding a second copy that drifts the first time a category opens. The
 * service token is used because the open application form has no caller token to forward.
 *
 * <p>And one list from Order Manager, for a rider applying to a delivery company: who is hiring, and
 * each company's region, which the application records in place of an area the rider would otherwise
 * choose. See {@link #hiringCompanies()}.
 */
@Component
public class PlatformClient {

    private static final Logger log = LoggerFactory.getLogger(PlatformClient.class);

    private final RestClient orderManager;
    private final RestClient notifications;
    private final RestClient productService;
    /** Order Manager again, for the one read on the application path, with its bounded wait. */
    private final RestClient orderManagerReads;
    private final RestClient keycloak;
    private final String realm;
    private final String clientId;
    private final String clientSecret;

    private volatile Cached token = new Cached(null, Instant.EPOCH);

    public PlatformClient(
            RestClient.Builder builder,
            @Value("${delivery.services.order-manager:http://localhost:8101}") String orderManagerUrl,
            @Value("${delivery.services.notifications-manager:http://localhost:8104}")
            String notificationsUrl,
            @Value("${delivery.services.product-service:http://localhost:8103}")
            String productServiceUrl,
            @Value("${delivery.keycloak.base-url:http://localhost:8180}") String baseUrl,
            @Value("${delivery.keycloak.realm:delivery-platform}") String realm,
            @Value("${delivery.keycloak.client-id:onboarding-service}") String clientId,
            @Value("${delivery.keycloak.client-secret:}") String clientSecret) {
        this.orderManager = builder.clone().baseUrl(orderManagerUrl).build();
        this.notifications = builder.clone().baseUrl(notificationsUrl).build();
        this.productService = builder.clone().baseUrl(productServiceUrl)
                .requestFactory(boundedWait()).build();
        this.orderManagerReads = builder.clone().baseUrl(orderManagerUrl)
                .requestFactory(boundedWait()).build();
        this.keycloak = builder.clone().baseUrl(baseUrl).build();
        this.realm = realm;
        this.clientId = clientId;
        this.clientSecret = clientSecret;
    }

    private record Cached(String value, Instant expiresAt) {
        boolean usable() {
            return value != null && Instant.now().isBefore(expiresAt);
        }
    }

    /**
     * Registers a delivery company and puts the new account in charge of it.
     *
     * @return the provider id, so the application can record what it created
     */
    public UUID registerCarrier(String name, String contactName, String contactPhone,
                                String staffUserRef) {
        String bearer = serviceToken();
        String slug = slugify(name);

        JsonNode created = orderManager.post()
                .uri("/api/delivery-providers")
                .header("Authorization", "Bearer " + bearer)
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "slug", slug,
                        "name", name,
                        "contactName", contactName == null ? "" : contactName,
                        "contactPhone", contactPhone == null ? "" : contactPhone))
                .retrieve()
                .body(JsonNode.class);

        if (created == null || !created.hasNonNull("id")) {
            throw new KeycloakAdminClient.ProvisioningException(
                    "The delivery company could not be registered");
        }
        UUID providerId = UUID.fromString(created.path("id").asText());

        // Staff, not riders. Staff are the people who RUN the company and get the portal; riders
        // are who carries for it. Attaching the owner as a rider would give them a job board and no
        // way to manage their own fleet.
        orderManager.post()
                .uri("/api/delivery-providers/{id}/staff", providerId)
                .header("Authorization", "Bearer " + bearer)
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("riderRef", staffUserRef))
                .retrieve()
                .toBodilessEntity();

        log.info("Registered delivery company {} ({}) for {}", name, providerId, staffUserRef);
        return providerId;
    }

    /**
     * Puts a newly approved rider on a company's rider list.
     *
     * <p>{@code /riders}, not {@code /staff}, and the two are not interchangeable. Staff run the
     * company and see its portal; riders carry for it and see the job board. Only the rider list is
     * consulted when work is dispatched or a job is claimed — so attaching somebody to the wrong
     * one produces an account that looks attached, accepts the sign-in, and is never offered a
     * single delivery.
     */
    public void attachRider(UUID providerId, String riderRef) {
        orderManager.post()
                .uri("/api/delivery-providers/{id}/riders", providerId)
                .header("Authorization", "Bearer " + serviceToken())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("riderRef", riderRef))
                .retrieve()
                .toBodilessEntity();
        log.info("Attached rider {} to company {}", riderRef, providerId);
    }

    /**
     * Whether this account actually runs that company.
     *
     * <p>The carrier portal sends the company id it believes is its own, and that belief is not
     * evidence: the id names both the queue of people applying and the fleet they would be hired
     * into, so a carrier who edited it could read a competitor's applicants and attach them to
     * their own company. Order Manager holds the record of who runs what, so it is asked.
     *
     * <p>Staff, not riders. Riders carry for a company; staff run it, and hiring is something you
     * do because you run the place.
     */
    public boolean isStaffOf(UUID providerId, String userRef) {
        try {
            JsonNode staff = orderManager.get()
                    .uri("/api/delivery-providers/{id}/staff", providerId)
                    .header("Authorization", "Bearer " + serviceToken())
                    .retrieve()
                    .body(JsonNode.class);
            if (staff == null || !staff.has("riders")) {
                return false;
            }
            for (JsonNode member : staff.path("riders")) {
                if (userRef.equals(member.asText())) {
                    return true;
                }
            }
            return false;
        } catch (Exception e) {
            // An unknown company, or Order Manager being unreachable. Either way this is not a
            // proven claim, and the safe answer to "may I decide this person's application" is no.
            log.warn("Could not confirm whether {} runs company {}", userRef, providerId, e);
            return false;
        }
    }

    /**
     * Sends one message to somebody who has no account.
     *
     * <p>A one-time code, or the decision that follows an application. Both go through Notifications
     * Manager rather than an SMTP client of this service's own: that service owns the templates, the
     * provider credentials, the retries and the delivery log, and a second sending path would mean a
     * class of message nobody can answer "did it arrive" about.
     *
     * <p>Failures are thrown, not swallowed. The caller has to know, because "we have sent you a
     * code" is a promise — a screen that says it while the send failed leaves somebody waiting for
     * a message that is not coming, and no amount of patience will fix it.
     */
    public void notifyDirect(String channel, String recipient, String subject, String body,
                             String purpose) {
        notifications.post()
                .uri("/api/notifications/direct")
                .header("Authorization", "Bearer " + serviceToken())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "channel", channel,
                        "recipient", recipient,
                        "subject", subject == null ? "" : subject,
                        "body", body,
                        "purpose", purpose))
                .retrieve()
                .toBodilessEntity();
    }

    /**
     * Pushes to somebody who has an account and an app on a phone.
     *
     * <p>Addressed by account, not by device token: Notifications Manager resolves the device from
     * the same directory the order events use, so this service never has to hold one.
     *
     * <p>Quiet when there is no device on file — that is a 204 and not a failure. Somebody who
     * applied from a browser has no token, and the decision they are being told about has already
     * been made.
     */
    public void notifyDirectPush(String recipientId, String subject, String body, String purpose) {
        notifications.post()
                .uri("/api/notifications/direct/push")
                .header("Authorization", "Bearer " + serviceToken())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "recipientId", recipientId,
                        "subject", subject == null ? "" : subject,
                        "body", body,
                        "purpose", purpose))
                .retrieve()
                .toBodilessEntity();
    }

    /**
     * Product Service could not say what is open. Never a refusal of the application: nothing about
     * it was judged, so the applicant is told to try again rather than that their answer was wrong.
     */
    public static class CatalogUnavailableException extends RuntimeException {

        /** What the 503 carries, so the app says "try again" in the reader's own language. */
        public static final String CODE = "service-catalog-unavailable";

        public CatalogUnavailableException(String message, Throwable cause) {
            super(message, cause);
        }
    }

    /** A curated delivery zone, as a services applicant picks their area from it. */
    public record ServiceArea(UUID zoneId, String name) {
    }

    /**
     * The service categories open right now, as Product Service's wire names ({@code PRINTING}).
     *
     * <p>Read per call, as Product Service reads its own switch, so a category opened there is
     * accepted here on the very next application.
     *
     * @throws CatalogUnavailableException when Product Service cannot be asked or answers nonsense
     */
    public List<String> openServiceCategories() {
        JsonNode body = readProductService("/api/stores/service-categories", "service categories");
        List<String> open = new ArrayList<>();
        for (JsonNode name : body) {
            if (name.isTextual()) {
                open.add(name.asText());
            }
        }
        return List.copyOf(open);
    }

    /**
     * The areas a services applicant may pick: the same live delivery zones a customer picks from.
     *
     * @throws CatalogUnavailableException when Product Service cannot be asked or answers nonsense
     */
    public List<ServiceArea> serviceAreas() {
        JsonNode body = readProductService("/api/delivery-zones", "delivery zones");
        List<ServiceArea> areas = new ArrayList<>();
        for (JsonNode zone : body) {
            // The picker already hides retired zones; a zone marked inactive is skipped anyway,
            // because an application filed under an area nobody delivers to is not a real area.
            if (!zone.hasNonNull("id") || !zone.hasNonNull("name")
                    || !zone.path("active").asBoolean(true)) {
                continue;
            }
            try {
                areas.add(new ServiceArea(UUID.fromString(zone.path("id").asText()),
                        zone.path("name").asText()));
            } catch (IllegalArgumentException notAnId) {
                log.warn("Product Service listed a delivery zone whose id is not a UUID; skipped");
            }
        }
        return List.copyOf(areas);
    }

    private JsonNode readProductService(String path, String what) {
        JsonNode body;
        try {
            body = productService.get()
                    .uri(path)
                    .header("Authorization", "Bearer " + serviceToken())
                    .retrieve()
                    .body(JsonNode.class);
        } catch (RuntimeException e) {
            // A refused connection, a timeout, a 5xx, or no service token to ask with. All the same
            // to the applicant: nothing was judged, so this is "try again", never "not offered".
            log.warn("Could not read the {} from Product Service: {}", what, e.getMessage());
            throw new CatalogUnavailableException(
                    "We could not check the services on offer just now. Please try again in a "
                            + "moment.", e);
        }
        if (body == null || !body.isArray()) {
            log.warn("Product Service answered the {} with something that is not a list", what);
            throw new CatalogUnavailableException(
                    "We could not check the services on offer just now. Please try again in a "
                            + "moment.", null);
        }
        return body;
    }

    /**
     * Order Manager could not say which delivery companies are hiring. Never a refusal, exactly as
     * {@link CatalogUnavailableException} is not: nothing about the application was judged, so the
     * applicant is told to try again rather than to choose another company.
     */
    public static class CompaniesUnavailableException extends RuntimeException {

        /** What the 503 carries, so the app says "try again" in the reader's own language. */
        public static final String CODE = "hiring-companies-unavailable";

        public CompaniesUnavailableException(String message, Throwable cause) {
            super(message, cause);
        }
    }

    /**
     * A delivery company taking riders, as Order Manager's public list describes it.
     *
     * @param regions the names of the company's active coverage zones; empty when it has drawn none
     */
    public record HiringCompany(UUID id, String name, List<String> regions) {
    }

    /**
     * The delivery companies taking riders right now, each with its region.
     *
     * <p>Order Manager's public list ({@code GET /api/delivery-providers/hiring}) — the one the app
     * shows a rider — so a company is judged hiring by the rule that put it on their screen, and the
     * region recorded on the application is the region they were shown. Read per call, never
     * remembered: a company suspended a minute ago must not take one more application.
     *
     * <p>Asked with no token, as the app asks. The list is open to anybody, and a service token would
     * only add a way to fail: a Keycloak hiccup refusing an application that needed no authority.
     *
     * <p>A company listed without a {@code regions} field comes from an Order Manager older than this
     * service, and the whole answer is treated as no answer rather than as companies with no region.
     * Recording an empty region for a company that has one would record something untrue, and the
     * rider can simply try again once Order Manager is up to date — which is why Order Manager
     * deploys first.
     *
     * @throws CompaniesUnavailableException when Order Manager cannot be asked or answers nonsense
     */
    public List<HiringCompany> hiringCompanies() {
        JsonNode body;
        try {
            body = orderManagerReads.get()
                    .uri("/api/delivery-providers/hiring")
                    .retrieve()
                    .body(JsonNode.class);
        } catch (RuntimeException e) {
            // A refused connection, a timeout, a 5xx. All the same to the applicant: nothing was
            // judged, so this is "try again", never "that company is not hiring".
            log.warn("Could not read the hiring delivery companies from Order Manager: {}",
                    e.getMessage());
            throw companiesUnavailable(e);
        }
        if (body == null || !body.isArray()) {
            log.warn("Order Manager answered the hiring delivery companies with something that is "
                    + "not a list");
            throw companiesUnavailable(null);
        }
        List<HiringCompany> companies = new ArrayList<>();
        for (JsonNode company : body) {
            if (!company.path("regions").isArray()) {
                log.warn("Order Manager listed a hiring company without its regions: it is older than "
                        + "this service, and has to be deployed first");
                throw companiesUnavailable(null);
            }
            UUID id;
            try {
                id = UUID.fromString(company.path("id").asText());
            } catch (IllegalArgumentException notAnId) {
                log.warn("Order Manager listed a hiring company whose id is not a UUID; skipped");
                continue;
            }
            List<String> regions = new ArrayList<>();
            for (JsonNode region : company.path("regions")) {
                if (region.isTextual() && !region.asText().isBlank()) {
                    regions.add(region.asText().trim());
                }
            }
            companies.add(new HiringCompany(id, company.path("name").asText(""),
                    List.copyOf(regions)));
        }
        return List.copyOf(companies);
    }

    private static CompaniesUnavailableException companiesUnavailable(Throwable cause) {
        return new CompaniesUnavailableException(
                "We could not check that delivery company just now. Please try again in a moment.",
                cause);
    }

    /**
     * Timeouts for the reads on the application path — Product Service's two lists and Order
     * Manager's list of who is hiring — which the provisioning calls above do without.
     *
     * <p>These sit on the application path itself — an applicant is waiting, and the open signup form
     * asks them too — and the default request factory has no timeout at all, so a service that
     * stopped answering would hold a request thread for as long as it liked. They are asked before
     * the application's transaction opens (see ApplicationIntake), so the wait holds no database
     * connection.
     */
    private static SimpleClientHttpRequestFactory boundedWait() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(Duration.ofSeconds(2));
        factory.setReadTimeout(Duration.ofSeconds(3));
        return factory;
    }

    /**
     * A handle for the company, derived from its name.
     *
     * <p>Suffixed with a short random tail because two businesses genuinely can share a name, and a
     * collision here would fail the whole provisioning step for a reason the applicant cannot fix.
     */
    private static String slugify(String name) {
        String base = name.toLowerCase(java.util.Locale.ROOT)
                .replaceAll("[^a-z0-9]+", "-")
                .replaceAll("(^-|-$)", "");
        if (base.isBlank()) {
            base = "carrier";
        }
        return base.substring(0, Math.min(40, base.length()))
                + "-" + UUID.randomUUID().toString().substring(0, 6);
    }

    private String serviceToken() {
        Cached current = token;
        if (current.usable()) {
            return current.value();
        }
        if (clientSecret == null || clientSecret.isBlank()) {
            throw new KeycloakAdminClient.ProvisioningException(
                    "No service-account secret is configured, so nothing can be registered");
        }

        MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("grant_type", "client_credentials");
        form.add("client_id", clientId);
        form.add("client_secret", clientSecret);

        JsonNode response = keycloak.post()
                .uri("/realms/{realm}/protocol/openid-connect/token", realm)
                .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                .body(form)
                .retrieve()
                .body(JsonNode.class);

        if (response == null || !response.hasNonNull("access_token")) {
            throw new KeycloakAdminClient.ProvisioningException(
                    "Keycloak refused a service-account token");
        }
        long seconds = response.path("expires_in").asLong(60);
        Cached fresh = new Cached(response.path("access_token").asText(),
                Instant.now().plus(Duration.ofSeconds(Math.max(10, seconds - 30))));
        token = fresh;
        return fresh.value();
    }
}
