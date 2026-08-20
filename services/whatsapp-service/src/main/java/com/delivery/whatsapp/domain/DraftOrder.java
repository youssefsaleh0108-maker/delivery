package com.delivery.whatsapp.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;

/**
 * What a merchant is building out of a conversation, before it becomes an order.
 *
 * <p>The whole design of this feature is in the gap between this and an {@code Order}. A message is
 * a request; a draft is a merchant's reading of that request; an order is a commitment. Skipping the
 * middle step means "hi" and "are you open?" become purchases, and a mis-parsed quantity becomes
 * money the customer pays.
 *
 * <p>So nothing here is binding. It has no prices the platform will honour, no rider, no settlement.
 * It becomes real only when the merchant confirms it, at which point it goes through Order Manager
 * exactly like an order from the app.
 */
@Entity
@Table(name = "wa_draft_orders")
public class DraftOrder {

    public enum Status {
        /** Being built. Exactly one of these may exist per conversation. */
        OPEN,
        /** Confirmed by the merchant and now a real order. */
        PLACED,
        /** The merchant decided this was not an order after all. */
        DISCARDED
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "conversation_id", nullable = false, updatable = false)
    private UUID conversationId;

    @Column(name = "merchant_ref", nullable = false, updatable = false, length = 64)
    private String merchantRef;

    /** What the customer actually wrote. Verbatim — see the migration for why. */
    @Column(name = "request_text", columnDefinition = "text")
    private String requestText;

    @Column(name = "delivery_address", length = 500)
    private String deliveryAddress;

    @Column(name = "delivery_zone_id")
    private UUID deliveryZoneId;

    @Column(name = "contact_phone", length = 32)
    private String contactPhone;

    @Column(name = "notes", length = 500)
    private String notes;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status = Status.OPEN;

    @Column(name = "order_id")
    private UUID orderId;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt = Instant.now();

    /**
     * Eagerly fetched, unlike most collections here.
     *
     * <p>A draft is never listed without its lines — the merchant's whole reason for opening one is
     * to see what is in it — and a lazy collection on a screen that always needs it is how a GET
     * ends up throwing outside the transaction. That exact bug cost a day on the product options
     * work; it is not worth repeating for a collection that holds four rows.
     */
    @OneToMany(cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.EAGER)
    @JoinColumn(name = "draft_id", nullable = false)
    @OrderBy("productName ASC")
    private List<DraftLine> lines = new ArrayList<>();

    protected DraftOrder() {
        // for JPA
    }

    public DraftOrder(UUID conversationId, String merchantRef, String requestText) {
        this.id = UUID.randomUUID();
        this.conversationId = conversationId;
        this.merchantRef = merchantRef;
        this.requestText = requestText;
    }

    @PreUpdate
    void touch() {
        this.updatedAt = Instant.now();
    }

    // ---------------------------------------------------------------- building it

    /**
     * Adds an item, or increases the one already there.
     *
     * <p>"Already there" means the same product <em>with the same options</em>. A merchant typing
     * from a chat says "and another one" constantly, so a plain repeat must become a quantity — but
     * a large pizza and a small one are two different things, and merging them would quietly change
     * what the customer gets.
     */
    public void addLine(UUID productId, String productName, BigDecimal unitPrice, int qty,
                        List<UUID> optionIds, List<DraftLineOption> options) {
        requireOpen();
        for (DraftLine line : lines) {
            if (line.matches(productId, optionIds)) {
                line.addQty(qty);
                return;
            }
        }
        lines.add(new DraftLine(productId, productName, unitPrice, qty, options));
    }

    /**
     * Removes a line.
     *
     * <p>By line id rather than by product: with options a product can legitimately be in the basket
     * twice, and removing "the pizza" would be ambiguous about which one.
     */
    public boolean removeLine(UUID lineId) {
        requireOpen();
        return lines.removeIf(line -> line.getId().equals(lineId));
    }

    public void setDelivery(String address, UUID zoneId, String contactPhone, String notes) {
        requireOpen();
        this.deliveryAddress = address;
        this.deliveryZoneId = zoneId;
        this.contactPhone = contactPhone;
        this.notes = notes;
    }

    // ---------------------------------------------------------------- resolving it

    /**
     * Records that this draft became a real order.
     *
     * <p>Called only after Order Manager has accepted it. The order is the source of truth from
     * here; this link exists so the merchant can find the order from the conversation.
     */
    public void placedAs(UUID orderId) {
        requireOpen();
        this.status = Status.PLACED;
        this.orderId = orderId;
    }

    public void discard() {
        requireOpen();
        this.status = Status.DISCARDED;
    }

    /**
     * Whether this draft is complete enough to place.
     *
     * <p>Two things, and only two: something to deliver and somewhere to deliver it. Deliberately
     * not a full validation — the catalog will reject a bad product and the shop will reject a
     * basket under its minimum, and duplicating those rules here would mean two places to keep in
     * step and one of them silently wrong.
     */
    public boolean isPlaceable() {
        return status == Status.OPEN
                && !lines.isEmpty()
                && deliveryAddress != null && !deliveryAddress.isBlank();
    }

    /**
     * What the lines add up to at the prices captured when they were added.
     *
     * <p>An estimate the merchant can read back to the customer, not a price the platform honours.
     * The catalog prices the real order — see {@code OrderService.place}.
     */
    public BigDecimal estimatedSubtotal() {
        return lines.stream()
                .map(DraftLine::lineTotal)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
    }

    private void requireOpen() {
        if (status != Status.OPEN) {
            throw new IllegalStateException(
                    "This request has already been " + status.name().toLowerCase());
        }
    }

    public UUID getId() {
        return id;
    }

    public UUID getConversationId() {
        return conversationId;
    }

    public String getMerchantRef() {
        return merchantRef;
    }

    public String getRequestText() {
        return requestText;
    }

    public String getDeliveryAddress() {
        return deliveryAddress;
    }

    public UUID getDeliveryZoneId() {
        return deliveryZoneId;
    }

    public String getContactPhone() {
        return contactPhone;
    }

    public String getNotes() {
        return notes;
    }

    public Status getStatus() {
        return status;
    }

    public UUID getOrderId() {
        return orderId;
    }

    public List<DraftLine> getLines() {
        return lines;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }
}
