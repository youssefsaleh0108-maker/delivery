package com.delivery.appnotification.service;

import java.time.Instant;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import com.delivery.appnotification.client.ProductDirectory;
import com.delivery.appnotification.domain.ChatStoreOwner;
import com.delivery.appnotification.domain.ChatStoreOwnerRepository;

/**
 * Which merchant may read and answer a shop's threads — resolved on the server, never from anything
 * the client says.
 *
 * <p>The storefront a customer's app holds exposes no merchant id, on purpose, so the client could
 * not say even if it were asked. The only authority is Product Service answering
 * {@code /api/stores/mine} for the merchant's own token. That answer is kept briefly in
 * {@code chat_store_owners} so an inbox being worked does not cost a cross-service call per message,
 * and it is trusted from there only while it is fresh and only for the merchant it names.
 *
 * <p><strong>Product Service is never asked inside a transaction this class begins.</strong> Its
 * answer can take seconds to come, or to time out, and a transaction waiting on it holds one of the
 * pool's few connections all that while. So the question is asked first and the confirmations are
 * written after it, in a short transaction of their own, or in the caller's when this is called inside
 * one. A merchant opening a thread for an order checks ownership before any transaction has begun
 * ({@code ShopChatService#openForOrder}), which a transaction here would undo.
 *
 * <p><strong>Call these only with the caller's own id.</strong> The Product Service question is asked
 * with the current request's token; passing any other id would record that person as the owner of
 * the caller's shops.
 */
@Component
public class ShopOwnership {

    private final ProductDirectory directory;
    private final ChatStoreOwnerRepository owners;
    private final ShopChatProperties properties;
    private final TransactionTemplate writes;

    public ShopOwnership(ProductDirectory directory, ChatStoreOwnerRepository owners,
                         ShopChatProperties properties, PlatformTransactionManager transactionManager) {
        this.directory = directory;
        this.owners = owners;
        this.properties = properties;
        this.writes = new TransactionTemplate(transactionManager);
    }

    /** The calling merchant's shops, fresh from Product Service, recording each confirmation. */
    public Set<UUID> storesOf(String callerId) {
        Set<UUID> stores = directory.storesOwnedByCaller();
        if (!stores.isEmpty()) {
            Instant now = Instant.now();
            writes.executeWithoutResult(status ->
                    stores.forEach(storeId -> owners.confirm(storeId, callerId, now)));
        }
        return stores;
    }

    /** Whether the calling merchant owns this shop: a fresh confirmation for them, or Product Service. */
    public boolean owns(String callerId, UUID storeId) {
        Instant freshSince = Instant.now().minus(properties.getOwnerConfirmationTtl());
        boolean confirmedRecently = owners.findById(storeId)
                .filter(owner -> owner.getMerchantId().equals(callerId))
                .filter(owner -> owner.getConfirmedAt().isAfter(freshSince))
                .isPresent();
        return confirmedRecently || storesOf(callerId).contains(storeId);
    }

    /**
     * Whom a customer's message should be pushed to live: the merchant Product Service confirmed as
     * the shop's owner within {@link ShopChatProperties#getOwnerConfirmationTtl()}, or nobody.
     *
     * <p><strong>The same freshness rule as {@link #owns}, for the same reason.</strong> A live frame
     * carries the customer's words. A confirmation hours old may name somebody who has since sold the
     * shop or lost it, and pushing to them would hand a former owner every new message the moment it
     * is written — the one thing reading through {@link #owns} is careful never to allow. So a stale
     * confirmation sends nothing: the message waits in the inbox, which asks Product Service again
     * before it shows anything, and a merchant whose app reads the inbox keeps the confirmation fresh.
     */
    @Transactional(readOnly = true)
    public Optional<String> freshOwnerOf(UUID storeId) {
        Instant freshSince = Instant.now().minus(properties.getOwnerConfirmationTtl());
        return owners.findById(storeId)
                .filter(owner -> owner.getConfirmedAt().isAfter(freshSince))
                .map(ChatStoreOwner::getMerchantId);
    }
}
