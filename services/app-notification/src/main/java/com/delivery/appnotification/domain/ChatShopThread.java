package com.delivery.appnotification.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

/**
 * One customer's conversation with one shop.
 *
 * <p>The customer side is a column; the shop side is not. Who may answer for the shop is decided per
 * request from Product Service's answer about the caller ({@code ShopOwnership}), because a shop's
 * owner is Product Service's fact and the storefront deliberately does not publish it.
 *
 * <p><strong>Closing policy.</strong> A thread accepts posts until {@link #getClosesAt()}, which is
 * the customer's last activity plus an idle window. Only the customer moves it: opening the chat
 * from the shop page, or saying something. The shop's replies do not, so a shop cannot keep a
 * customer's thread alive to message them long after they stopped asking — once idle, only the
 * customer can start it again.
 */
@Entity
@Table(name = "chat_shop_threads")
public class ChatShopThread {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "store_id", nullable = false, updatable = false)
    private UUID storeId;

    @Column(name = "customer_id", nullable = false, updatable = false, length = 64)
    private String customerId;

    @Column(name = "customer_name", length = 80)
    private String customerName;

    @Column(name = "store_name", nullable = false, length = 160)
    private String storeName;

    /** Reserved for a verified order or booking reference; never written from a client. */
    @Column(name = "order_id")
    private UUID orderId;

    @Column(name = "opened_at", nullable = false, updatable = false)
    private Instant openedAt;

    @Column(name = "closes_at", nullable = false)
    private Instant closesAt;

    @Column(name = "next_sequence", nullable = false)
    private long nextSequence;

    @Column(name = "last_message_at")
    private Instant lastMessageAt;

    @Version
    @Column(name = "version", nullable = false)
    private long version;

    protected ChatShopThread() {
        // for JPA
    }

    /** For tests; production inserts go through the repository's upsert. */
    public ChatShopThread(UUID storeId, String customerId, String customerName, String storeName,
                          Instant closesAt) {
        this.id = UUID.randomUUID();
        this.storeId = storeId;
        this.customerId = customerId;
        this.customerName = customerName;
        this.storeName = storeName;
        this.openedAt = Instant.now();
        this.closesAt = closesAt;
        this.nextSequence = 1L;
    }

    public boolean isOpenAt(Instant now) {
        return now.isBefore(closesAt);
    }

    /** Pushes the closing time out, never in: a later, shorter window must not shut a live thread. */
    public void keepOpenUntil(Instant until) {
        if (until.isAfter(closesAt)) {
            closesAt = until;
        }
    }

    /** Follows a renamed shop, and a customer whose token now carries a name. */
    public void refresh(String currentStoreName, String currentCustomerName) {
        if (currentStoreName != null && !currentStoreName.isBlank()) {
            storeName = currentStoreName;
        }
        if (currentCustomerName != null) {
            customerName = currentCustomerName;
        }
    }

    /** Only safe under the row lock; see {@code ChatShopThreadRepository.lockById}. */
    public long claimSequence(Instant at) {
        long claimed = nextSequence;
        nextSequence = claimed + 1;
        lastMessageAt = at;
        return claimed;
    }

    public UUID getId() {
        return id;
    }

    public UUID getStoreId() {
        return storeId;
    }

    public String getCustomerId() {
        return customerId;
    }

    public String getCustomerName() {
        return customerName;
    }

    public String getStoreName() {
        return storeName;
    }

    public UUID getOrderId() {
        return orderId;
    }

    public Instant getOpenedAt() {
        return openedAt;
    }

    public Instant getClosesAt() {
        return closesAt;
    }

    public long getNextSequence() {
        return nextSequence;
    }

    public Instant getLastMessageAt() {
        return lastMessageAt;
    }
}
