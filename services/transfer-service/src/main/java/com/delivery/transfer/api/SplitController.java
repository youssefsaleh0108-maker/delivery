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

import com.delivery.platform.security.CurrentUser;
import com.delivery.transfer.domain.Money;
import com.delivery.transfer.domain.SplitPlan;
import com.delivery.transfer.domain.SplitShare;
import com.delivery.transfer.service.SplitService;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;

/**
 * Group split payment (Figma frames 83:*): the host creates a plan, invitees answer their own
 * shares, the host covers the flakes, and the rider reads the cash checklist.
 *
 * <p>Invitees are addressed by USERNAME — the {@code preferred_username} in their own token is
 * what matches them to their shares, so an order id or plan id in a request buys nothing without
 * being the host or an invitee (or, for the plan behind an order, its rider or back office). A plan
 * the caller may not read answers 404, exactly like one that does not exist.
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

    /**
     * {@code @Valid} on the element, not just the list: validation does not descend into a
     * collection unless it is asked to, so a share with no {@code amountUsd} satisfied every
     * constraint here and was then summed with {@code BigDecimal::add} — a 500 over a field the
     * caller left out.
     */
    public record CreateRequest(@NotNull SplitPlan.Mode mode, @NotNull BigDecimal totalUsd,
                                String storeName, @NotNull List<@Valid ShareRequest> shares) {
    }

    @PostMapping
    @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> create(@AuthenticationPrincipal Jwt jwt,
                                      @Valid @RequestBody CreateRequest request) {
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

    /**
     * How an invitee may answer a share right now: cash at the door, plus a wallet only where the
     * dev simulator stands in for it, flagged {@code simulated} so the app can say so. Not the
     * checkout's {@code /api/transfers/methods}: a connector that carries an order's payment cannot
     * take a share's money.
     */
    @GetMapping("/methods")
    @PreAuthorize("hasRole('CUSTOMER')")
    public List<Map<String, Object>> methods() {
        return service.shareMethods().stream().map(m -> {
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("method", m.method());
            out.put("simulated", m.simulated());
            return out;
        }).toList();
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
                                      @Valid @RequestBody AnswerRequest request) {
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
                                      @Valid @RequestBody AttachRequest request) {
        return payload(service.attachOrder(id, jwt.getSubject(), request.orderId()));
    }

    /**
     * The plan behind an order: the rider's cash checklist, the members' summary, support's view.
     *
     * <p>Only the host, an invitee, back office and the order's own rider are answered; anybody
     * else gets the 404 an order with no plan gets (RECON-02). The rider is shown
     * {@link #riderPayload the amounts only}.
     */
    @GetMapping("/for-order/{orderId}")
    @PreAuthorize("hasAnyRole('DELIVERY', 'CUSTOMER', 'BACKOFFICE')")
    public Map<String, Object> forOrder(@AuthenticationPrincipal Jwt jwt,
                                        @PathVariable UUID orderId) {
        SplitService.OrderPlan read = service.forOrder(orderId, jwt.getSubject(), username(jwt),
                CurrentUser.hasRole("BACKOFFICE"));
        return read.reader() == SplitService.Reader.RIDER
                ? riderPayload(read.plan(), read.cashOrder())
                : payload(read.plan());
    }

    private static String username(Jwt jwt) {
        String name = jwt.getClaimAsString("preferred_username");
        return name != null ? name : jwt.getSubject();
    }

    private static String displayName(Jwt jwt) {
        String name = jwt.getClaimAsString("name");
        return name != null && !name.isBlank() ? name : username(jwt);
    }

    /**
     * What the order's rider is shown: each share's amount and the name to call at the door, and
     * nothing that identifies an account — no usernames, no host, no store, nothing of the plan's
     * life before the order.
     *
     * <p>Each share's {@code method} is how THIS door receives it. On a cash order every share is
     * handed over here — the host's own slice and a simulated wallet share included, since neither
     * moved any money — so each reads CASH_AT_DOOR, and a rider app from before RECON-01, which
     * added up only the CASH_AT_DOOR shares, asks for the order's whole total too. On a card or
     * wallet order the order's own payment carried everything, so each reads HOST_ORDER and the
     * door owes nothing. {@code simulated} stays, with the wallet it stood in for as
     * {@code simulatedMethod}, so a stand-in payment is still called one, by name.
     */
    private static Map<String, Object> riderPayload(SplitPlan plan, boolean cashOrder) {
        SplitShare.Method atTheDoor = cashOrder
                ? SplitShare.Method.CASH_AT_DOOR
                : SplitShare.Method.HOST_ORDER;
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("id", plan.getId());
        out.put("orderId", plan.getOrderId());
        out.put("mode", plan.getMode());
        out.put("status", plan.getStatus());
        out.put("totalUsd", Money.usd(plan.getTotalUsd()));
        out.put("rateUsed", Money.lbp(plan.getRateUsed()));
        out.put("shares", plan.getShares().stream().map(s -> {
            Map<String, Object> share = new LinkedHashMap<>();
            share.put("id", s.getId());
            share.put("name", s.getPayeeName());
            share.put("amountUsd", Money.usd(s.getAmountUsd()));
            share.put("status", s.getStatus());
            share.put("method", atTheDoor);
            share.put("simulated", s.isSimulated());
            if (s.isSimulated()) {
                share.put("simulatedMethod", s.getMethod());
            }
            return share;
        }).toList());
        return out;
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
        out.put("totalUsd", Money.usd(plan.getTotalUsd()));
        out.put("rateUsed", Money.lbp(plan.getRateUsed()));
        out.put("expiresAt", plan.getExpiresAt());
        out.put("createdAt", plan.getCreatedAt());
        out.put("shares", plan.getShares().stream().map(s -> {
            Map<String, Object> share = new LinkedHashMap<>();
            share.put("id", s.getId());
            share.put("username", s.getPayeeUsername());
            share.put("name", s.getPayeeName());
            share.put("amountUsd", Money.usd(s.getAmountUsd()));
            share.put("itemsCount", s.getItemsCount());
            share.put("status", s.getStatus());
            share.put("method", s.getMethod());
            share.put("simulated", s.isSimulated());
            share.put("paidAt", s.getPaidAt());
            return share;
        }).toList());
        return out;
    }
}
