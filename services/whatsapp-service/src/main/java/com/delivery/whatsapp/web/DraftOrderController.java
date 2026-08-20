package com.delivery.whatsapp.web;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.security.CurrentUser;
import com.delivery.whatsapp.client.OrderClient;
import com.delivery.whatsapp.client.ProductClient;
import com.delivery.whatsapp.client.ProductClient.OptionGroup;
import com.delivery.whatsapp.service.DraftOrderService;
import com.delivery.whatsapp.web.dto.DraftDtos.AddLineRequest;
import com.delivery.whatsapp.web.dto.DraftDtos.DeliveryRequest;
import com.delivery.whatsapp.web.dto.DraftDtos.DraftView;
import com.delivery.whatsapp.web.dto.DraftDtos.OpenDraftRequest;

import jakarta.validation.Valid;

/**
 * The merchant turning a conversation into an order.
 *
 * <p>Deliberately several steps rather than one "create order from message" call. The merchant is
 * reading a chat and deciding what it means, and every step here is one they can get wrong and fix
 * — which is the entire safety argument for the feature.
 */
@RestController
@RequestMapping("/api/whatsapp/drafts")
@PreAuthorize("hasRole('MERCHANT')")
public class DraftOrderController {

    private final DraftOrderService drafts;

    public DraftOrderController(DraftOrderService drafts) {
        this.drafts = drafts;
    }

    /** Everything still waiting to become an order. */
    @GetMapping
    public List<DraftView> open() {
        return drafts.open(CurrentUser.requireId()).stream().map(DraftView::of).toList();
    }

    @GetMapping("/{id}")
    public ResponseEntity<DraftView> one(@PathVariable UUID id) {
        return drafts.find(id, CurrentUser.requireId())
                .map(DraftView::of)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    /**
     * Opens a draft against a conversation, or hands back the one already open.
     *
     * <p>201 either way. The merchant asked for a draft and now has one; distinguishing "created"
     * from "you already had this" would only tempt a client into treating the second as an error.
     */
    @PostMapping("/conversations/{conversationId}")
    public ResponseEntity<DraftView> openFor(@PathVariable UUID conversationId,
                                             @Valid @RequestBody(required = false) OpenDraftRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED).body(DraftView.of(
                drafts.openFor(conversationId, CurrentUser.requireId(),
                        request == null ? null : request.requestText())));
    }

    /** Every draft this conversation has produced, including the ones already placed. */
    @GetMapping("/conversations/{conversationId}")
    public List<DraftView> forConversation(@PathVariable UUID conversationId) {
        return drafts.forConversation(conversationId, CurrentUser.requireId()).stream()
                .map(DraftView::of)
                .toList();
    }

    @PostMapping("/{id}/lines")
    public DraftView addLine(@PathVariable UUID id, @Valid @RequestBody AddLineRequest request) {
        return DraftView.of(drafts.addLine(id, CurrentUser.requireId(),
                request.productId(), request.qty(), request.optionIds()));
    }

    /**
     * Removes a line by its own id, not by product.
     *
     * <p>With options the same product is legitimately in the basket twice — a large and a small —
     * so "remove the pizza" is ambiguous in a way that would delete the wrong one.
     */
    @DeleteMapping("/{id}/lines/{lineId}")
    public DraftView removeLine(@PathVariable UUID id, @PathVariable UUID lineId) {
        return DraftView.of(drafts.removeLine(id, CurrentUser.requireId(), lineId));
    }

    /** What the merchant picks from when a product has options. */
    @GetMapping("/products/{productId}/options")
    public List<ProductClient.OptionGroup> options(@PathVariable UUID productId) {
        return drafts.optionsFor(productId, CurrentUser.requireId());
    }

    @PutMapping("/{id}/delivery")
    public DraftView setDelivery(@PathVariable UUID id, @Valid @RequestBody DeliveryRequest request) {
        return DraftView.of(drafts.setDelivery(id, CurrentUser.requireId(),
                request.deliveryAddress(), request.deliveryZoneId(),
                request.contactPhone(), request.notes()));
    }

    /** The confirmation. This is the step that costs money, and the only one that does. */
    @PostMapping("/{id}/place")
    public DraftView place(@PathVariable UUID id) {
        return DraftView.of(drafts.place(id, CurrentUser.requireId()));
    }

    @PostMapping("/{id}/discard")
    public DraftView discard(@PathVariable UUID id) {
        return DraftView.of(drafts.discard(id, CurrentUser.requireId()));
    }

    // ---------------------------------------------------------------- refusals

    /** 422: the merchant asked for something this draft cannot do, and can fix it. */
    @ExceptionHandler(DraftOrderService.DraftRuleViolationException.class)
    public ResponseEntity<Map<String, String>> rule(DraftOrderService.DraftRuleViolationException e) {
        return ResponseEntity.unprocessableEntity().body(Map.of("message", e.getMessage()));
    }

    @ExceptionHandler(ProductClient.ProductLookupException.class)
    public ResponseEntity<Map<String, String>> lookup(ProductClient.ProductLookupException e) {
        return ResponseEntity.unprocessableEntity().body(Map.of("message", e.getMessage()));
    }

    /**
     * Order Manager's refusal, in its own words.
     *
     * <p>It knows things this service does not — that the shop is closed, that the basket is under
     * its minimum, that the area is not served. Flattening those to "could not place order" would
     * leave the merchant with nothing to act on while a customer waits.
     */
    @ExceptionHandler(OrderClient.OrderRefusedException.class)
    public ResponseEntity<Map<String, String>> refused(OrderClient.OrderRefusedException e) {
        HttpStatus status = e.getStatus() >= 400 && e.getStatus() < 500
                ? HttpStatus.UNPROCESSABLE_ENTITY
                : HttpStatus.BAD_GATEWAY;
        return ResponseEntity.status(status).body(Map.of("message", e.getMessage()));
    }

    /** A draft resolved out from under the caller — placed on another device, say. */
    @ExceptionHandler(IllegalStateException.class)
    public ResponseEntity<Map<String, String>> conflict(IllegalStateException e) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("message", e.getMessage()));
    }
}
