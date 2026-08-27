package com.delivery.appnotification.domain;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import jakarta.persistence.LockModeType;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ChatConversationRepository extends JpaRepository<ChatConversation, UUID> {

    /**
     * The live conversation for an order, if there is one.
     *
     * <p>{@code closesAt is null} is the definition of "still in flight" — see V21 for why closing
     * is an instant rather than a status. The partial unique index guarantees this returns at most
     * one row, so there is no ordering to get wrong.
     */
    @Query("select c from ChatConversation c where c.orderId = :orderId and c.closesAt is null")
    Optional<ChatConversation> findLiveByOrderId(@Param("orderId") UUID orderId);

    /**
     * Takes the row lock that makes sequence assignment safe.
     *
     * <p>Serialising posts to one conversation is cheap here in a way it would not be in a group
     * chat: there are two participants, so contention is two people typing at once. The alternative
     * — deriving the sequence from {@code max(sequence_no) + 1} without a lock — gives two
     * simultaneous posts the same number, and the unique constraint then fails one of them, so the
     * customer's message is lost to a 500 rather than merely ordered second.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select c from ChatConversation c where c.id = :id")
    Optional<ChatConversation> lockById(@Param("id") UUID id);

    /**
     * Every conversation this person is in, either side, most recently active first.
     *
     * <p>Closed ones included: the thread stays readable after the order ends, and a customer
     * looking for what the rider said yesterday should find it where they left it.
     */
    @Query("select c from ChatConversation c "
            + "where c.customerId = :userId or c.riderId = :userId "
            + "order by coalesce(c.lastMessageAt, c.openedAt) desc")
    List<ChatConversation> findAllForParticipant(@Param("userId") String userId);

    /** The threads for one order, newest first — more than one only after a rider reassignment. */
    List<ChatConversation> findByOrderIdOrderByOpenedAtDesc(UUID orderId);
}
