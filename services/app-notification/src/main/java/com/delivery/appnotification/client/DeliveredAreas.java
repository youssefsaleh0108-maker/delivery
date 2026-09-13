package com.delivery.appnotification.client;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.HttpHeaders;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import com.delivery.appnotification.service.RoomExceptions.ProofUnavailableException;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/**
 * Where the caller's own orders have been delivered, as Order Manager answers for their token — the
 * evidence a neighbourhood room asks for before a customer may speak in it.
 *
 * <p><strong>Always the caller's own token</strong>, forwarded exactly as {@link ProductDirectory}
 * forwards it. There is no service identity here that could read anybody else's orders, so the
 * answer can only ever be about the person asking. <strong>Call it only with the caller's own
 * id</strong>: the id keys the cache while the token decides whose orders are read, and a different
 * id would file the caller's deliveries under somebody else.
 *
 * <p><strong>Cached briefly, per caller.</strong> A neighbour trading a few quick messages would
 * otherwise cost Order Manager a request per message. The time to live is minutes — long enough to
 * cover a conversation, short enough that a first delivery opens the composer soon after it lands.
 * Only answers are kept: a failure is asked again next time, never remembered as "no deliveries".
 *
 * <p><strong>Fails closed.</strong> Order Manager unreachable, slow past the timeout, or refusing is
 * a {@link ProofUnavailableException}, never an empty answer and never a yes.
 */
public class DeliveredAreas {

    private static final Logger log = LoggerFactory.getLogger(DeliveredAreas.class);

    /** Far more customers than post in any few minutes; past it, the expired answers go first. */
    static final int MAX_CACHED_CALLERS = 10_000;

    private final RestClient rest;
    private final Duration cacheTtl;
    private final Clock clock;
    private final Map<String, Answer> answers = new ConcurrentHashMap<>();

    public DeliveredAreas(RestClient rest, Duration cacheTtl) {
        this(rest, cacheTtl, Clock.systemUTC());
    }

    DeliveredAreas(RestClient rest, Duration cacheTtl, Clock clock) {
        this.rest = rest;
        this.cacheTtl = cacheTtl;
        this.clock = clock;
    }

    /**
     * When the caller last had an order delivered in this area, if that was at or after
     * {@code since}.
     *
     * @throws ProofUnavailableException when Order Manager cannot say
     */
    public Optional<Instant> lastDeliveryIn(String callerId, UUID zoneId, Instant since) {
        Instant last = answerFor(callerId, since).lastDeliveries().get(zoneId);
        return last == null || last.isBefore(since) ? Optional.empty() : Optional.of(last);
    }

    private Answer answerFor(String callerId, Instant since) {
        Instant now = clock.instant();
        Answer cached = answers.get(callerId);
        // An answer asked with a later window start than this call's could be missing deliveries
        // this call counts. One asked with an earlier start only holds extras, filtered above.
        if (cached != null && now.isBefore(cached.fetchedAt().plus(cacheTtl))
                && !cached.since().isAfter(since)) {
            return cached;
        }
        Answer fresh = fetch(since, now);
        remember(callerId, fresh, now);
        return fresh;
    }

    private Answer fetch(Instant since, Instant now) {
        List<DeliveredZone> zones;
        try {
            zones = rest.get()
                    .uri("/api/orders/mine/delivered-zones?since={since}", since.toString())
                    .header(HttpHeaders.AUTHORIZATION, ProductDirectory.bearer())
                    .retrieve()
                    .body(new ParameterizedTypeReference<List<DeliveredZone>>() {
                    });
        } catch (RestClientException e) {
            log.warn("Could not read the caller's delivered areas from Order Manager", e);
            throw new ProofUnavailableException("Deliveries cannot be checked right now", e);
        }

        Map<UUID, Instant> latest = new HashMap<>();
        if (zones != null) {
            for (DeliveredZone zone : zones) {
                if (zone != null && zone.zoneId() != null && zone.lastDeliveredAt() != null) {
                    latest.merge(zone.zoneId(), zone.lastDeliveredAt(), (a, b) -> a.isAfter(b) ? a : b);
                }
            }
        }
        return new Answer(Map.copyOf(latest), since, now);
    }

    private void remember(String callerId, Answer answer, Instant now) {
        if (answers.size() >= MAX_CACHED_CALLERS) {
            answers.values().removeIf(old -> !now.isBefore(old.fetchedAt().plus(cacheTtl)));
            if (answers.size() >= MAX_CACHED_CALLERS) {
                answers.clear();
            }
        }
        answers.put(callerId, answer);
    }

    /** Only the fields chat needs from Order Manager's {@code DeliveredZone}. */
    @JsonIgnoreProperties(ignoreUnknown = true)
    record DeliveredZone(UUID zoneId, Instant lastDeliveredAt) {
    }

    private record Answer(Map<UUID, Instant> lastDeliveries, Instant since, Instant fetchedAt) {
    }
}
