package com.delivery.appnotification.domain;

import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import jakarta.persistence.LockModeType;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ChatShopThreadRepository extends JpaRepository<ChatShopThread, UUID> {

    /**
     * Opens the customer's thread with a shop unless it exists — the idempotent half of
     * get-or-create. An upsert so a double tap on the chat button cannot race to the unique
     * constraint and fail the second request.
     */
    @Modifying(flushAutomatically = true)
    @Query(value = "insert into chat_shop_threads (id, store_id, customer_id, customer_name, store_name, "
            + "opened_at, closes_at, next_sequence, version) "
            + "values (:id, :storeId, :customerId, :customerName, :storeName, now(), :closesAt, 1, 0) "
            + "on conflict (store_id, customer_id) do nothing",
            nativeQuery = true)
    int insertIfAbsent(@Param("id") UUID id,
                       @Param("storeId") UUID storeId,
                       @Param("customerId") String customerId,
                       @Param("customerName") String customerName,
                       @Param("storeName") String storeName,
                       @Param("closesAt") Instant closesAt);

    /**
     * The thread between a shop and a customer, under its row lock: what an open changes once the
     * upsert has made sure the row exists.
     *
     * <p>The lock {@link #lockById} takes for a post, reached by the other key. Without it, two opens
     * of one thread, or an open racing a post, would load the same version, and the second to commit
     * would fail its version check — a 500 for its caller. Under the lock the second waits for the
     * first and reads what it wrote. Take it before anything else loads the thread in the same
     * transaction, for the reason given at {@link #partiesOf}.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select t from ChatShopThread t where t.storeId = :storeId and t.customerId = :customerId")
    Optional<ChatShopThread> lockByStoreIdAndCustomerId(@Param("storeId") UUID storeId,
                                                        @Param("customerId") String customerId);

    /**
     * The two facts access is decided on, without loading the entity.
     *
     * <p>A projection on purpose: deciding access with {@code findById} and then posting under
     * {@link #lockById} would put a possibly stale entity in the persistence context before the lock,
     * and the lock query would hand back that stale instance instead of the row it locked.
     */
    @Query("select t.storeId as storeId, t.customerId as customerId from ChatShopThread t where t.id = :id")
    Optional<Parties> partiesOf(@Param("id") UUID id);

    /** Serialises posts to one thread; the same reasoning as {@code ChatConversationRepository.lockById}. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select t from ChatShopThread t where t.id = :id")
    Optional<ChatShopThread> lockById(@Param("id") UUID id);

    /** The merchant inbox: threads with something in them, for the caller's shops, newest first. */
    @Query("select t from ChatShopThread t where t.storeId in :storeIds and t.lastMessageAt is not null "
            + "order by t.lastMessageAt desc")
    List<ChatShopThread> inboxFor(@Param("storeIds") Collection<UUID> storeIds, Pageable pageable);

    interface Parties {
        UUID getStoreId();

        String getCustomerId();
    }
}
