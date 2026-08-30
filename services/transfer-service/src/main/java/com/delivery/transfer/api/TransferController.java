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

import com.delivery.transfer.domain.MoneyTransfer;
import com.delivery.transfer.domain.TransferMethod;
import com.delivery.transfer.service.TransferService;

import jakarta.validation.constraints.NotNull;

/**
 * The checkout's money surface.
 *
 * <p>{@code /rate} and {@code /methods} paint the screen (the locked-rate banner, the method
 * list); {@code /quote} turns a proposed USD split into the exact lira face value at the locked
 * rate; {@code POST /} records the approved intent and hands it to a connector. Everything is
 * scoped to the calling token — an order id in a request buys nothing without ownership.
 */
@RestController
@RequestMapping("/api/transfers")
public class TransferController {

    private final TransferService service;

    public TransferController(TransferService service) {
        this.service = service;
    }

    /** The platform rate and the rider-change promise: the two numbers the banner prints. */
    @GetMapping("/rate")
    @PreAuthorize("isAuthenticated()")
    public Map<String, Object> rate() {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("lbpPerUsd", service.rate());
        payload.put("riderChangeLimitLbp", service.riderChangeLimitLbp());
        return payload;
    }

    @GetMapping("/methods")
    @PreAuthorize("isAuthenticated()")
    public List<TransferMethod> methods() {
        return service.availableMethods();
    }

    public record QuoteRequest(@NotNull BigDecimal amountUsd, BigDecimal splitUsd) {
    }

    /** The split arithmetic, done once, server-side, at the rate that will bind. */
    @PostMapping("/quote")
    @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> quote(@RequestBody QuoteRequest request) {
        BigDecimal amount = request.amountUsd();
        BigDecimal usdPart = request.splitUsd() == null ? amount : request.splitUsd();
        BigDecimal lbpInUsd = amount.subtract(usdPart);

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("lbpPerUsd", service.rate());
        payload.put("amountUsd", amount);
        payload.put("splitUsd", usdPart);
        payload.put("splitLbpFace", service.lbpFaceFor(lbpInUsd.max(BigDecimal.ZERO)));
        payload.put("riderChangeLimitLbp", service.riderChangeLimitLbp());
        return payload;
    }

    public record InitiateRequest(@NotNull UUID orderId, @NotNull TransferMethod method,
                                  @NotNull BigDecimal amountUsd, BigDecimal splitUsd) {
    }

    @PostMapping
    @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> initiate(@AuthenticationPrincipal Jwt jwt,
                                        @RequestBody InitiateRequest request) {
        MoneyTransfer transfer = service.record(
                request.orderId(), jwt.getSubject(), request.method(),
                request.amountUsd(), request.splitUsd());
        return payload(transfer);
    }

    @GetMapping("/order/{orderId}")
    @PreAuthorize("hasRole('CUSTOMER')")
    public Map<String, Object> forOrder(@AuthenticationPrincipal Jwt jwt,
                                        @PathVariable UUID orderId) {
        return payload(service.mineForOrder(orderId, jwt.getSubject()));
    }

    @GetMapping("/mine")
    @PreAuthorize("hasRole('CUSTOMER')")
    public List<Map<String, Object>> mine(@AuthenticationPrincipal Jwt jwt) {
        return service.mine(jwt.getSubject(), 20).stream()
                .map(TransferController::payload)
                .toList();
    }

    private static Map<String, Object> payload(MoneyTransfer t) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("id", t.getId());
        payload.put("orderId", t.getOrderId());
        payload.put("method", t.getMethod());
        payload.put("status", t.getStatus());
        payload.put("amountUsd", t.getAmountUsd());
        payload.put("splitUsd", t.getSplitUsd());
        payload.put("splitLbpInUsd", t.getSplitLbpInUsd());
        payload.put("splitLbpFace", t.lbpFaceValue());
        payload.put("rateUsed", t.getRateUsed());
        payload.put("connector", t.getConnector());
        payload.put("connectorRef", t.getConnectorRef());
        payload.put("createdAt", t.getCreatedAt());
        return payload;
    }
}
