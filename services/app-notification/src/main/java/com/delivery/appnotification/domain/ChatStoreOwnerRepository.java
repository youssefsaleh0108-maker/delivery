package com.delivery.appnotification.domain;

import java.time.Instant;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ChatStoreOwnerRepository extends JpaRepository<ChatStoreOwner, UUID> {

    /** Records Product Service's answer: this merchant owns this shop, as of now. */
    @Modifying(flushAutomatically = true)
    @Query(value = "insert into chat_store_owners (store_id, merchant_id, confirmed_at) "
            + "values (:storeId, :merchantId, :at) "
            + "on conflict (store_id) do update "
            + "set merchant_id = excluded.merchant_id, confirmed_at = excluded.confirmed_at",
            nativeQuery = true)
    int confirm(@Param("storeId") UUID storeId,
                @Param("merchantId") String merchantId,
                @Param("at") Instant at);
}
