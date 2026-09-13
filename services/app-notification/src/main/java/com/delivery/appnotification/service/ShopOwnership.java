package com.delivery.appnotification.service;

import java.time.Instant;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

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
 * <p><strong>Call these only with the caller's own id.</strong> The Product Service question is asked
 * with the current request's token; passing any other id would record that person as the owner of
 * the caller's shops.
 */
@Component
public class ShopOwnership {

    private final ProductDirectory directory;
    private final ChatStoreOwnerRepository owners;
    private final ShopChatProperties properties;

    public ShopOwnership(ProductDirectory directory, ChatStoreOwnerRepository owners,
                         ShopChatProperties properties) {
        this.directory = directory;
        this.owners = owners;
        this.properties = properties;
    }

    /** The calling merchant's shops, fresh from Product Service, recording each confirmation. */
    @Transactional
    public Set<UUID> storesOf(String callerId) {
        Set<UUID> stores = directory.storesOwnedByCaller();
        Instant now = Instant.now();
        stores.forEach(storeId -> owners.confirm(storeId, callerId, now));
        return stores;
    }

    /** Whether the calling merchant owns this shop: a fresh confirmation for them, or Product Service. */
    @Transactional
    public boolean owns(String callerId, UUID storeId) {
        Instant freshSince = Instant.now().minus(properties.getOwnerConfirmationTtl());
        boolean confirmedRecently = owners.findById(storeId)
                .filter(owner -> owner.getMerchantId().equals(callerId))
                .filter(owner -> owner.getConfirmedAt().isAfter(freshSince))
                .isPresent();
        return confirmedRecently || storesOf(callerId).contains(storeId);
    }

    /**
     * Whom a customer's message should be pushed to live. A hint only: a stale or missing answer
     * costs a live frame, never access — the merchant still reads the thread through {@link #owns}.
     */
    @Transactional(readOnly = true)
    public Optional<String> lastConfirmedOwnerOf(UUID storeId) {
        return owners.findById(storeId).map(ChatStoreOwner::getMerchantId);
    }
}
