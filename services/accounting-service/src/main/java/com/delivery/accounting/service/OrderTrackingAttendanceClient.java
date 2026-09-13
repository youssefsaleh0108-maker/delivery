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
 * Reads a fleet's attendance from order-tracking, for a pay run.
 *
 * <p>{@code GET /api/tracking/carrier/attendance?from&to}, with the carrier's own token forwarded —
 * the way {@link CarrierCompanyClient} asks Order Manager — so order-tracking applies its own
 * CARRIER scoping and this service is never trusted to name a fleet.
 *
 * <p><strong>Checked before it is believed.</strong> The answer must be about the company the run is
 * for, in the zone the run's days are in, over exactly the period asked; anything else is refused as
 * a mismatch rather than paid on. Order-tracking's display hours are never read — only its exact
 * seconds.
 *
 * <p><strong>Bounded.</strong> A pay run waits on this, and a draft is recomputed on every edit, so a
 * slow order-tracking must cost seconds and then an honest "hours unavailable", not a request thread
 * held for as long as the socket stays open.
 */
@Component
public class OrderTrackingAttendanceClient implements RiderAttendanceSource {

    private static final Logger log = LoggerFactory.getLogger(OrderTrackingAttendanceClient.class);

    private final RestClient tracking;

    @Autowired
    public OrderTrackingAttendanceClient(
            RestClient.Builder builder,
            @Value("${delivery.services.order-tracking:http://localhost:8102}") String trackingUrl,
            @Value("${delivery.accounting.payroll.attendance-timeout:10s}") Duration timeout) {
        this(builder.clone().requestFactory(requestFactory(timeout)), trackingUrl);
    }

    /** For tests, which bind the builder to a mock server and must keep its request factory. */
    OrderTrackingAttendanceClient(RestClient.Builder builder, String trackingUrl) {
        this.tracking = builder.clone().baseUrl(trackingUrl).build();
    }

    private static SimpleClientHttpRequestFactory requestFactory(Duration timeout) {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(Duration.ofSeconds(Math.min(3, Math.max(1, timeout.toSeconds()))));
        factory.setReadTimeout(timeout);
        return factory;
    }

    @Override
    public AttendanceRead fleet(String bearerToken, String carrierRef, ZoneId zone, LocalDate from,
                                LocalDate to) {
        JsonNode body;
        try {
            body = tracking.get()
                    .uri(uri -> uri.path("/api/tracking/carrier/attendance")
                            .queryParam("from", from.toString())
                            .queryParam("to", to.toString())
                            .build())
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + bearerToken)
                    .retrieve()
                    .body(JsonNode.class);
        } catch (RestClientResponseException e) {
            int status = e.getStatusCode().value();
            log.warn("Attendance for {} {}..{} refused by order-tracking: {}", carrierRef, from, to,
                    status);
            return AttendanceRead.unavailable(switch (status) {
                // No such route: attendance is not deployed where this runs.
                case 404 -> "NOT_DEPLOYED";
                case 401, 403 -> "REFUSED";
                // Order-tracking refuses a period it cannot judge (older than its retention).
                case 400 -> "PERIOD_REFUSED";
                default -> "UNREACHABLE";
            });
        } catch (RestClientException e) {
            // Refused connection, timeout, or a body that is not JSON.
            log.warn("Attendance for {} {}..{} could not be read: {}", carrierRef, from, to,
                    e.getMessage());
            return AttendanceRead.unavailable("UNREACHABLE");
        }

        if (body == null || !body.path("riders").isArray()) {
            return AttendanceRead.unavailable("UNREADABLE");
        }
        if (!carrierRef.equals(body.path("carrierId").asText(null))
                || !zone.getId().equals(body.path("zone").asText(null))
                || !from.toString().equals(body.path("from").asText(null))
                || !to.toString().equals(body.path("to").asText(null))) {
            log.error("Attendance answered about another fleet, zone or period than asked: "
                    + "wanted {} {} {}..{}, got {} {} {}..{}", carrierRef, zone, from, to,
                    body.path("carrierId").asText(null), body.path("zone").asText(null),
                    body.path("from").asText(null), body.path("to").asText(null));
            return AttendanceRead.unavailable("MISMATCH");
        }

        Map<String, PayslipCalculator.RiderHours> riders = new LinkedHashMap<>();
        Map<String, String> unreadable = new LinkedHashMap<>();
        for (JsonNode rider : body.path("riders")) {
            String id = rider.path("riderId").asText(null);
            if (id == null || id.isBlank()) {
                // Figures belonging to nobody. If that rider is on the run, their payslip says
                // attendance did not list them, which is exactly true.
                log.warn("Attendance for {} {}..{} listed a rider with no id", carrierRef, from, to);
                continue;
            }
            JsonNode totals = rider.path("totals");
            // One rider's figures not to be believed — or listed twice, so neither is — cost that
            // rider's hours, not everybody's.
            if (riders.containsKey(id) || unreadable.containsKey(id) || !totals.isObject()
                    || !whole(totals, "workedSeconds") || !whole(totals, "manualSeconds")
                    || !whole(totals, "overtimeSeconds") || !whole(totals, "lates")
                    || !whole(totals, "absences")) {
                log.warn("Attendance for {} {}..{} gave figures for {} that cannot be paid on",
                        carrierRef, from, to, id);
                riders.remove(id);
                unreadable.put(id, "UNREADABLE");
                continue;
            }
            riders.put(id, new PayslipCalculator.RiderHours(
                    totals.path("workedSeconds").asLong(),
                    totals.path("manualSeconds").asLong(),
                    totals.path("overtimeSeconds").asLong(),
                    totals.path("lates").asInt(),
                    totals.path("absences").asInt()));
        }
        return AttendanceRead.of(riders, unreadable);
    }

    /** A present, whole, non-negative number: anything else is not a figure to pay on. */
    private static boolean whole(JsonNode totals, String field) {
        JsonNode value = totals.path(field);
        return value.isIntegralNumber() && value.asLong() >= 0;
    }
}
