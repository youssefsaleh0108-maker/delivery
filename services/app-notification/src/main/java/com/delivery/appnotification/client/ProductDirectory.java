package com.delivery.appnotification.client;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.HttpHeaders;
import org.springframework.security.oauth2.jwt.Jwt;
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
}
