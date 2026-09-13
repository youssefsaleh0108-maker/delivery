package com.delivery.appnotification.client;

import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.HttpHeaders;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import com.delivery.appnotification.service.RoomExceptions.DirectoryUnavailableException;
import com.delivery.platform.security.CurrentUser;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/**
 * The questions chat has to ask Product Service: is this delivery area real, does this shop exist,
 * which shops does this merchant own.
 *
 * <p><strong>Every call forwards the caller's own bearer token</strong> — the rule Order Manager's
 * {@code StoreClient} follows, and for the same reason. There is no service account here that could
 * read more than the person asking may read: a merchant learns which shops are theirs from
 * {@code /api/stores/mine} answered for their own token, so "which shop's threads may I read" is
 * Product Service's answer about the caller, never a store id the client supplied.
 *
 * <p>Failures are {@link DirectoryUnavailableException} (503), never a guess. See that exception for
 * why neither "yes" nor "no" is a safe default.
 */
public class ProductDirectory {

    private static final Logger log = LoggerFactory.getLogger(ProductDirectory.class);

    private final RestClient rest;

    public ProductDirectory(RestClient rest) {
        this.rest = rest;
    }

    /**
     * The zone with this id, if the address picker offers it today.
     *
     * <p>Read from the picker list rather than a by-id lookup because that list is exactly the set a
     * customer's address can legitimately name: active zones only. A retired area has no room to
     * join, just as it can no longer be chosen for a new address.
     */
    public Optional<Zone> activeZone(UUID zoneId) {
        if (zoneId == null) {
            return Optional.empty();
        }
        List<Zone> zones;
        try {
            zones = rest.get()
                    .uri("/api/delivery-zones")
                    .header(HttpHeaders.AUTHORIZATION, bearer())
                    .retrieve()
                    .body(new ParameterizedTypeReference<List<Zone>>() {
                    });
        } catch (RestClientException e) {
            log.warn("Could not read delivery zones from Product Service", e);
            throw new DirectoryUnavailableException("Delivery areas are temporarily unavailable", e);
        }
        if (zones == null) {
            return Optional.empty();
        }
        return zones.stream()
                .filter(zone -> zoneId.equals(zone.id()) && zone.active())
                .findFirst();
    }

    /**
     * The shop as its storefront shows it to the caller, or empty if it is not there for them.
     *
     * <p>Asked with the customer's token, so a draft or suspended shop — which Product Service does
     * not show a customer — cannot be opened as a chat either.
     */
    public Optional<Storefront> storefront(UUID storeId) {
        try {
            return Optional.ofNullable(rest.get()
                    .uri("/api/stores/{id}", storeId)
                    .header(HttpHeaders.AUTHORIZATION, bearer())
                    .retrieve()
                    .body(Storefront.class));
        } catch (HttpClientErrorException e) {
            int status = e.getStatusCode().value();
            if (status == 404 || status == 400) {
                return Optional.empty();
            }
            log.warn("Product Service refused a storefront read ({})", status);
            throw new DirectoryUnavailableException("Shops are temporarily unavailable", e);
        } catch (RestClientException e) {
            log.warn("Could not read a storefront from Product Service", e);
            throw new DirectoryUnavailableException("Shops are temporarily unavailable", e);
        }
    }

    /**
     * The shops the calling merchant owns, as Product Service answers {@code /api/stores/mine} for
     * their own token — the only place a shop's owner is known, since the storefront deliberately
     * does not publish it.
     *
     * <p>A 403 is "not a merchant as Product Service sees it" and owns nothing; any other failure is
     * unavailable rather than an empty answer, which would silently empty a real merchant's inbox.
     */
    public Set<UUID> storesOwnedByCaller() {
        try {
            OwnedStores page = rest.get()
                    .uri("/api/stores/mine?size={size}", MAX_OWNED_STORES)
                    .header(HttpHeaders.AUTHORIZATION, bearer())
                    .retrieve()
                    .body(OwnedStores.class);
            if (page == null || page.content() == null) {
                return Set.of();
            }
            return page.content().stream()
                    .map(Storefront::id)
                    .filter(Objects::nonNull)
                    .collect(Collectors.toUnmodifiableSet());
        } catch (HttpClientErrorException.Forbidden e) {
            return Set.of();
        } catch (RestClientException e) {
            log.warn("Could not read a merchant's shops from Product Service", e);
            throw new DirectoryUnavailableException("Your shops are temporarily unavailable", e);
        }
    }

    /** Far above any real merchant's shop count; one page is the whole answer. */
    static final int MAX_OWNED_STORES = 100;

    static String bearer() {
        String token = CurrentUser.jwt()
                .map(Jwt::getTokenValue)
                .orElseThrow(() -> new IllegalStateException(
                        "No bearer token to forward - is this call outside a request?"));
        return "Bearer " + token;
    }

    /** Only the fields chat needs from {@code ZoneResponse}. */
    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Zone(UUID id, String name, String region, boolean active) {
    }

    /** Only the fields chat needs from {@code StoreResponse}. */
    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Storefront(UUID id, String name) {
    }

    /** Product Service's page envelope, reduced to its content. */
    @JsonIgnoreProperties(ignoreUnknown = true)
    record OwnedStores(List<Storefront> content) {
    }
}
