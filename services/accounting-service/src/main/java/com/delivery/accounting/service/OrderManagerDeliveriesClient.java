package com.delivery.accounting.service;

import java.time.Duration;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.LinkedHashMap;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * Counts a delivery company's delivered orders per rider for a pay run, from Order Manager.
 *
 * <p>{@code GET /api/orders/riders/delivered?from&to}, with the carrier's own token forwarded — the way
 * {@link CarrierCompanyClient} and the attendance read ask — so Order Manager resolves the company
 * from the token, counts only the orders carried for it, and this service never names one.
 *
 * <h2>The endpoint this relies on</h2>
 * <p>It belongs with the rider performance reads on Order Manager's carrier-riders branch,
 * {@code feat/rider-performance-daily}, whose {@code RiderPerformanceController} already answers
 * {@code /api/orders/riders/delivered-today} for the caller's company from the same {@code orders}
 * rows. <strong>It is not on that branch yet</strong>: what is there counts one rider's last 1–30 days
 * back from today, which cannot answer a month's pay run. Until it is added this reads
 * {@code NOT_DEPLOYED}, and pay runs count from the ledger and say so. What it must answer:
 * <pre>
 * CARRIER only; the company from the token, never the request. from/to: inclusive days in the
 * platform zone, at most 31 of them.
 * 200 {"carrierId":"&lt;provider uuid&gt;","zone":"Asia/Beirut","from":"2026-10-01","to":"2026-10-31",
 *      "asOf":"&lt;instant&gt;","riders":[{"riderId":"&lt;keycloak sub&gt;","delivered":17}]}
 * delivered: orders with status DELIVERED, delivery_provider_id the caller's company, and delivered_at
 * from the start of `from` to the start of the day after `to` in the zone — counted once each, whatever
 * the fee or the payment; riders with none are left out.
 * 400 for a malformed, reversed or longer period.
 * </pre>
 *
 * <p><strong>Checked before it is believed.</strong> The answer must be about the company, the zone and
 * the period asked, and every count a whole number, once per rider; anything else is refused rather
 * than paid on. <strong>Bounded</strong> by a timeout, because a pay run waits on it.
 */
@Component
public class OrderManagerDeliveriesClient implements RiderDeliveriesSource {

    private static final Logger log = LoggerFactory.getLogger(OrderManagerDeliveriesClient.class);

    private final RestClient orders;

    @Autowired
    public OrderManagerDeliveriesClient(
            RestClient.Builder builder,
            @Value("${delivery.services.order-manager:http://localhost:8101}") String orderManagerUrl,
            @Value("${delivery.accounting.payroll.deliveries-timeout:10s}") Duration timeout) {
        this(builder.clone().requestFactory(requestFactory(timeout)), orderManagerUrl);
    }

    /** For tests, which bind the builder to a mock server and must keep its request factory. */
    OrderManagerDeliveriesClient(RestClient.Builder builder, String orderManagerUrl) {
        this.orders = builder.clone().baseUrl(orderManagerUrl).build();
    }

    private static SimpleClientHttpRequestFactory requestFactory(Duration timeout) {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(Duration.ofSeconds(Math.min(3, Math.max(1, timeout.toSeconds()))));
        factory.setReadTimeout(timeout);
        return factory;
    }

    @Override
    public DeliveriesRead fleet(String bearerToken, String carrierRef, ZoneId zone, LocalDate from,
                                LocalDate to) {
        JsonNode body;
        try {
            body = orders.get()
                    .uri(uri -> uri.path("/api/orders/riders/delivered")
                            .queryParam("from", from.toString())
                            .queryParam("to", to.toString())
                            .build())
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + bearerToken)
                    .retrieve()
                    .body(JsonNode.class);
        } catch (RestClientResponseException e) {
            int status = e.getStatusCode().value();
            log.warn("Deliveries for {} {}..{} refused by Order Manager: {}", carrierRef, from, to,
                    status);
            return DeliveriesRead.unavailable(switch (status) {
                // No such route: the count is not deployed where this runs.
                case 404 -> "NOT_DEPLOYED";
                case 401, 403 -> "REFUSED";
                case 400 -> "PERIOD_REFUSED";
                default -> "UNREACHABLE";
            });
        } catch (RestClientException e) {
            // Refused connection, timeout, or a body that is not JSON.
            log.warn("Deliveries for {} {}..{} could not be read: {}", carrierRef, from, to,
                    e.getMessage());
            return DeliveriesRead.unavailable("UNREACHABLE");
        }

        if (body == null || !body.path("riders").isArray()) {
            return DeliveriesRead.unavailable("UNREADABLE");
        }
        if (!carrierRef.equals(body.path("carrierId").asText(null))
                || !zone.getId().equals(body.path("zone").asText(null))
                || !from.toString().equals(body.path("from").asText(null))
                || !to.toString().equals(body.path("to").asText(null))) {
            log.error("Deliveries answered about another company, zone or period than asked: "
                    + "wanted {} {} {}..{}, got {} {} {}..{}", carrierRef, zone, from, to,
                    body.path("carrierId").asText(null), body.path("zone").asText(null),
                    body.path("from").asText(null), body.path("to").asText(null));
            return DeliveriesRead.unavailable("MISMATCH");
        }

        Map<String, Integer> riders = new LinkedHashMap<>();
        for (JsonNode rider : body.path("riders")) {
            String id = rider.path("riderId").asText(null);
            JsonNode delivered = rider.path("delivered");
            // A count that is missing, fractional, negative or given twice is not a count to pay on.
            if (id == null || id.isBlank() || riders.containsKey(id)
                    || !delivered.isIntegralNumber() || !delivered.canConvertToInt()
                    || delivered.asInt() < 0) {
                return DeliveriesRead.unavailable("UNREADABLE");
            }
            riders.put(id, delivered.asInt());
        }
        return DeliveriesRead.of(riders);
    }
}
