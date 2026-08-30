package com.delivery.transfer.api;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.transfer.domain.SplitPlan;
import com.delivery.transfer.domain.SplitShare;
import com.delivery.transfer.service.SplitService;

import jakarta.validation.constraints.NotNull;

/**
 * Group split payment (Figma frames 83:*): the host creates a plan, invitees answer their own
 * shares, the host covers the flakes, and the rider reads the cash checklist.
 *
 * <p>Invitees are addressed by USERNAME — the {@code preferred_username} in their own token is
 * what matches them to their shares, so an order id or plan id in a request buys nothing without
 * being the host or an invitee.
 */
@RestController
@RequestMapping("/api/transfers/splits")
public class SplitController {

    private final SplitService service;

    public SplitController(SplitService service) {
        this.service = service;
    }

    public record ShareRequest(String username, @NotNull String name,
                               @NotNull BigDecimal amountUsd, Integer itemsCount) {
    }

    public record CreateRequest(@NotNull SplitPlan.Mode mode, @NotNull BigDecimal totalUsd,
                                String storeName, @NotNull List<ShareRequest> shares) {
    }

    @PostMapping
    @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> create(@AuthenticationPrincipal Jwt jwt,
                                      @RequestBody CreateRequest request) {
        SplitPlan plan = service.create(
                jwt.getSubject(), username(jwt), displayName(jwt), request.storeName(),
                request.mode(), request.totalUsd(),
                request.shares().stream()
                        .map(s -> new SplitService.NewShare(
                                s.username(), s.name(), s.amountUsd(), s.itemsCount()))
                        .toList());
        return payload(plan);
    }

    @GetMapping("/mine")
    @PreAuthorize("hasRole('CUSTOMER')")
    public List<Map<String, Object>> mine(@AuthenticationPrincipal Jwt jwt) {
        return service.mine(jwt.getSubject()).stream().map(SplitController::payload).toList();
    }

    /** The invitations waiting on the calling user — what the home banner polls. */
    @GetMapping("/requests")
    @PreAuthorize("hasRole('CUSTOMER')")
    public List<Map<String, Object>> requests(@AuthenticationPrincipal Jwt jwt) {
        return service.requestsFor(username(jwt)).stream()
                .map(SplitController::payload).toList();
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> read(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id) {
        return payload(service.read(id, jwt.getSubject(), username(jwt)));
    }

    public record AnswerRequest(@NotNull Boolean accept, SplitShare.Method method) {
    }

    /** An invitee pays or declines their own share. */
    @PostMapping("/{id}/answer")
    @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> answer(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id,
                                      @RequestBody AnswerRequest request) {
        return payload(service.answer(id, jwt.getSubject(), username(jwt),
                request.accept(), request.method()));
    }

    @PostMapping("/{id}/cover")
    @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> cover(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id) {
        return payload(service.cover(id, jwt.getSubject()));
    }

    @PostMapping("/{id}/remind")
    @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> remind(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id) {
        return payload(service.remind(id, jwt.getSubject()));
    }

    @PostMapping("/{id}/cancel")
    @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> cancel(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id) {
        return payload(service.cancel(id, jwt.getSubject()));
    }

    public record AttachRequest(@NotNull UUID orderId) {
    }

    @PostMapping("/{id}/attach-order")
    @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> attach(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id,
                                      @RequestBody AttachRequest request) {
        return payload(service.attachOrder(id, jwt.getSubject(), request.orderId()));
    }

    /**
     * The rider's cash checklist for a split order. DELIVERY reads it to collect; the customer
     * roles read it for the completion summary.
     */
    @GetMapping("/for-order/{orderId}")
    @PreAuthorize("hasAnyRole('DELIVERY', 'CUSTOMER')")
    public Map<String, Object> forOrder(@PathVariable UUID orderId) {
        return payload(service.forOrder(orderId));
    }

    private static String username(Jwt jwt) {
        String name = jwt.getClaimAsString("preferred_username");
        return name != null ? name : jwt.getSubject();
    }

    private static String displayName(Jwt jwt) {
        String name = jwt.getClaimAsString("name");
        return name != null && !name.isBlank() ? name : username(jwt);
    }

    private static Map<String, Object> payload(SplitPlan plan) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("id", plan.getId());
        out.put("hostUsername", plan.getHostUsername());
        out.put("hostName", plan.getHostName());
        out.put("storeName", plan.getStoreName());
        out.put("orderId", plan.getOrderId());
        out.put("mode", plan.getMode());
        out.put("status", plan.getStatus());
        out.put("totalUsd", plan.getTotalUsd());
        out.put("rateUsed", plan.getRateUsed());
        out.put("expiresAt", plan.getExpiresAt());
        out.put("createdAt", plan.getCreatedAt());
        out.put("shares", plan.getShares().stream().map(s -> {
            Map<String, Object> share = new LinkedHashMap<>();
            share.put("id", s.getId());
            share.put("username", s.getPayeeUsername());
            share.put("name", s.getPayeeName());
            share.put("amountUsd", s.getAmountUsd());
            share.put("itemsCount", s.getItemsCount());
            share.put("status", s.getStatus());
            share.put("method", s.getMethod());
            share.put("paidAt", s.getPaidAt());
            return share;
        }).toList());
        return out;
    }
}
