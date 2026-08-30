package com.delivery.accounting.api;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.accounting.domain.PointsEntry;
import com.delivery.accounting.domain.PointsEntry.OwnerKind;
import com.delivery.accounting.domain.PointsRedemption;
import com.delivery.accounting.service.PointsService;

/**
 * Points and redemptions.
 *
 * <p><strong>Whose points you see is decided by your token, not by a path parameter.</strong> The
 * owner is derived from the caller's roles and subject, so there is no id to tamper with — a
 * merchant asking for a balance can only ever be asking for their own. The Backoffice endpoints are
 * the exception and are role-gated separately.
 *
 * <p>A carrier is identified by their delivery-provider id, which is not the same as their user id.
 * That mapping lives in Order Manager, and until it is exposed the carrier endpoints take the
 * provider id explicitly — see the note on {@link #carrierBalance}.
 */
@RestController
@RequestMapping("/api/points")
public class PointsController {

    private static final int MAX_HISTORY = 200;

    private final PointsService points;

    public PointsController(PointsService points) {
        this.points = points;
    }

    /** The caller's own balance, as a merchant, a platform rider — or a customer. */
    @GetMapping("/balance")
    @PreAuthorize("hasAnyRole('MERCHANT', 'DELIVERY', 'CUSTOMER')")
    public Map<String, Object> myBalance(@AuthenticationPrincipal Jwt jwt) {
        OwnerKind kind = kindFor(jwt);
        return balancePayload(kind, jwt.getSubject());
    }

    @GetMapping("/history")
    @PreAuthorize("hasAnyRole('MERCHANT', 'DELIVERY', 'CUSTOMER')")
    public List<Map<String, Object>> myHistory(@AuthenticationPrincipal Jwt jwt,
                                               @RequestParam(defaultValue = "50") int limit) {
        OwnerKind kind = kindFor(jwt);
        return points.history(kind, jwt.getSubject(), Math.min(limit, MAX_HISTORY)).stream()
                .map(PointsController::entryPayload)
                .toList();
    }

    /**
     * A carrier's balance, and what each of their riders earned toward it.
     *
     * <p>The breakdown is the reason this endpoint exists rather than reusing {@code /balance}. A
     * delivery company's riders earn into the company's balance, so without an attribution the
     * company has one number and no way to work out who to pay — the platform would have handed
     * them a settlement problem with none of the data needed to solve it.
     *
     * <p>{@code providerId} is taken from the path rather than the token because the rider-to-fleet
     * mapping is Order Manager's, not this service's. That makes this endpoint authorising on role
     * alone, so a carrier can currently read another carrier's totals. It is CARRIER-gated rather
     * than open, and closing it properly needs the provider id on the token or a lookup here —
     * recorded rather than left to be discovered.
     */
    @GetMapping("/carriers/{providerId}/balance")
    @PreAuthorize("hasRole('CARRIER')")
    public Map<String, Object> carrierBalance(@PathVariable String providerId) {
        Map<String, Object> payload = balancePayload(OwnerKind.CARRIER, providerId);
        payload.put("riders", points.riderBreakdown(providerId).stream()
                .map(r -> Map.<String, Object>of(
                        "riderRef", r.riderRef(),
                        "points", r.points(),
                        "value", points.valueOf(r.points())))
                .toList());
        return payload;
    }

    /** Asks to convert points into money. The points are held immediately. */
    @PostMapping("/redemptions")
    @PreAuthorize("hasAnyRole('MERCHANT', 'DELIVERY', 'CARRIER')")
    public ResponseEntity<?> request(@AuthenticationPrincipal Jwt jwt,
                                     @RequestBody RedemptionRequest body) {
        OwnerKind kind = body.ownerKind() != null ? body.ownerKind() : kindFor(jwt);
        String ref = kind == OwnerKind.CARRIER ? body.ownerRef() : jwt.getSubject();

        if (kind == OwnerKind.CARRIER && (ref == null || ref.isBlank())) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "A carrier redemption must name the provider"));
        }

        try {
            PointsRedemption redemption =
                    points.request(kind, ref, body.points(), body.payoutNote(), jwt.getSubject());
            return ResponseEntity.ok(redemptionPayload(redemption));
        } catch (IllegalArgumentException | IllegalStateException e) {
            // 400, not 500: every one of these is the caller asking for something that is not
            // allowed — too few points, too many, or one request already open.
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }

    @GetMapping("/redemptions")
    @PreAuthorize("hasAnyRole('MERCHANT', 'DELIVERY', 'CARRIER')")
    public List<Map<String, Object>> myRedemptions(@AuthenticationPrincipal Jwt jwt,
                                                   @RequestParam(required = false) String ownerRef) {
        OwnerKind kind = kindFor(jwt);
        String ref = kind == OwnerKind.CARRIER && ownerRef != null ? ownerRef : jwt.getSubject();
        return points.requestsFor(kind, ref).stream()
                .map(PointsController::redemptionPayload)
                .toList();
    }

    /** Withdrawing your own request before anybody has decided on it. */
    @PostMapping("/redemptions/{id}/cancel")
    @PreAuthorize("hasAnyRole('MERCHANT', 'DELIVERY', 'CARRIER')")
    public ResponseEntity<?> cancel(@PathVariable UUID id, @AuthenticationPrincipal Jwt jwt) {
        return decide(() -> points.cancel(id, jwt.getSubject()));
    }

    // ---------------------------------------------------------------------------- Backoffice

    /**
     * Everything waiting on somebody, oldest first.
     *
     * <p>Oldest first because the oldest request is the one a merchant has been waiting on longest,
     * and a queue sorted any other way quietly starves whoever is least likely to chase it.
     */
    @GetMapping("/redemptions/queue")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public List<Map<String, Object>> queue() {
        return points.queue().stream().map(PointsController::redemptionPayload).toList();
    }

    @PostMapping("/redemptions/{id}/approve")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ResponseEntity<?> approve(@PathVariable UUID id, @AuthenticationPrincipal Jwt jwt,
                                     @RequestBody(required = false) Decision body) {
        return decide(() -> points.approve(id, jwt.getSubject(), noteOf(body)));
    }

    @PostMapping("/redemptions/{id}/reject")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ResponseEntity<?> reject(@PathVariable UUID id, @AuthenticationPrincipal Jwt jwt,
                                    @RequestBody(required = false) Decision body) {
        return decide(() -> points.reject(id, jwt.getSubject(), noteOf(body)));
    }

    /**
     * Records that the money was handed over.
     *
     * <p>Only from APPROVED. Nothing here moves money — an operator pays outside this system and
     * this is where they say so, with a reference somebody can check later.
     */
    @PostMapping("/redemptions/{id}/paid")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ResponseEntity<?> markPaid(@PathVariable UUID id, @AuthenticationPrincipal Jwt jwt,
                                      @RequestBody(required = false) Decision body) {
        return decide(() -> points.markPaid(id, jwt.getSubject(), noteOf(body)));
    }

    // ---------------------------------------------------------------------------- plumbing

    public record RedemptionRequest(OwnerKind ownerKind, String ownerRef, long points,
                                    String payoutNote) {
    }

    public record Decision(String note) {
    }

    private static String noteOf(Decision body) {
        return body == null ? null : body.note();
    }

    private ResponseEntity<?> decide(java.util.function.Supplier<PointsRedemption> action) {
        try {
            return ResponseEntity.ok(redemptionPayload(action.get()));
        } catch (IllegalArgumentException | IllegalStateException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * Which balance a token owns.
     *
     * <p>MERCHANT before DELIVERY: an account carrying both is a shop that also delivers, and its
     * points belong to the shop. Guessing the other way round would move a merchant's earnings into
     * a rider balance they never see.
     */
    private OwnerKind kindFor(Jwt jwt) {
        List<String> roles = realmRoles(jwt);
        if (roles.contains("MERCHANT")) {
            return OwnerKind.MERCHANT;
        }
        if (roles.contains("CARRIER")) {
            return OwnerKind.CARRIER;
        }
        // DELIVERY before CUSTOMER: a rider who also shops holds a rider balance — their earnings
        // — and their shopping loyalty rides the same account. Earnings beat perks on a tie.
        if (roles.contains("DELIVERY")) {
            return OwnerKind.RIDER;
        }
        if (roles.contains("CUSTOMER")) {
            return OwnerKind.CUSTOMER;
        }
        return OwnerKind.RIDER;
    }

    @SuppressWarnings("unchecked")
    private static List<String> realmRoles(Jwt jwt) {
        Object realmAccess = jwt.getClaim("realm_access");
        if (realmAccess instanceof Map<?, ?> map && map.get("roles") instanceof List<?> roles) {
            return (List<String>) roles;
        }
        return List.of();
    }

    private Map<String, Object> balancePayload(OwnerKind kind, String ref) {
        long balance = points.balanceOf(kind, ref);
        Map<String, Object> payload = new java.util.LinkedHashMap<>();
        payload.put("ownerKind", kind);
        payload.put("ownerRef", ref);
        payload.put("points", balance);
        payload.put("value", points.valueOf(balance));
        payload.put("openRequest", points.openRequestFor(kind, ref)
                .map(PointsController::redemptionPayload)
                .orElse(null));
        // The loyalty ladder rides along for a customer — tier, the next one, and the distance to
        // it, judged on lifetime earnings so redeeming never demotes. Absent for the working
        // kinds, whose points are earnings, not standing.
        if (kind == OwnerKind.CUSTOMER) {
            PointsService.LoyaltyStanding standing = points.standingOf(kind, ref);
            Map<String, Object> loyalty = new java.util.LinkedHashMap<>();
            loyalty.put("lifetimeEarned", standing.lifetimeEarned());
            loyalty.put("ordersCompleted", standing.ordersCompleted());
            loyalty.put("tier", standing.tier());
            loyalty.put("tierFloor", standing.tier().floor());
            loyalty.put("nextTier", standing.nextTier());
            loyalty.put("nextTierAt", standing.nextTier() == null
                    ? null : standing.nextTier().floor());
            loyalty.put("pointsToNextTier", standing.pointsToNextTier());
            loyalty.put("cashbackValue", standing.cashbackValue());
            loyalty.put("currency", standing.currency());
            payload.put("loyalty", loyalty);
        }
        return payload;
    }

    private static Map<String, Object> entryPayload(PointsEntry entry) {
        Map<String, Object> payload = new java.util.LinkedHashMap<>();
        payload.put("id", entry.getId());
        payload.put("points", entry.getPoints());
        payload.put("reason", entry.getReason());
        payload.put("orderId", entry.getOrderId());
        payload.put("earnedByRiderRef", entry.getEarnedByRiderRef());
        payload.put("createdAt", entry.getCreatedAt());
        return payload;
    }

    private static Map<String, Object> redemptionPayload(PointsRedemption r) {
        Map<String, Object> payload = new java.util.LinkedHashMap<>();
        payload.put("id", r.getId());
        payload.put("ownerKind", r.getOwnerKind());
        payload.put("ownerRef", r.getOwnerRef());
        payload.put("points", r.getPoints());
        payload.put("amount", r.getAmount());
        payload.put("currency", r.getCurrency());
        payload.put("status", r.getStatus());
        payload.put("payoutNote", r.getPayoutNote());
        payload.put("requestedBy", r.getRequestedBy());
        payload.put("requestedAt", r.getRequestedAt());
        payload.put("decidedBy", r.getDecidedBy());
        payload.put("decidedAt", r.getDecidedAt());
        payload.put("decisionNote", r.getDecisionNote());
        return payload;
    }
}
