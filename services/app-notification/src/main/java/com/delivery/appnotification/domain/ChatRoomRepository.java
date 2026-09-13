package com.delivery.appnotification.domain;

import java.util.Optional;
import java.util.UUID;

import jakarta.persistence.LockModeType;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ChatRoomRepository extends JpaRepository<ChatRoom, UUID> {

    Optional<ChatRoom> findByZoneId(UUID zoneId);

    /**
     * Creates the zone's room unless it exists, without failing when two neighbours arrive at once.
     *
     * <p>A find-then-save would let both first arrivals insert, and the loser's transaction would
     * die on {@code uq_chat_room_zone} — in Postgres a failed statement poisons the whole
     * transaction, so there is no catching it and reading the winner's row afterwards. {@code ON
     * CONFLICT DO NOTHING} makes the race a no-op; the caller then reads whichever row won.
     */
    @Modifying(flushAutomatically = true)
    @Query(value = "insert into chat_rooms (id, zone_id, name, created_at, next_sequence, version) "
            + "values (:id, :zoneId, :name, now(), 1, 0) on conflict (zone_id) do nothing",
            nativeQuery = true)
    int insertIfAbsent(@Param("id") UUID id, @Param("zoneId") UUID zoneId, @Param("name") String name);

    /**
     * The row lock that serialises posts to a room, exactly as {@code ChatConversationRepository}
     * takes one: a sequence derived from {@code max + 1} gives two simultaneous posts the same number
     * and loses one of them to the unique constraint.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select r from ChatRoom r where r.id = :id")
    Optional<ChatRoom> lockById(@Param("id") UUID id);

    /**
     * The room's delivery area as a bare value, not a loaded room.
     *
     * <p>Posting needs the area before it takes the lock above (the proof of living there may be a
     * network call, which must not happen under a lock). Loading the room entity for it would let
     * {@link #lockById} hand back that same already-read instance, carrying a sequence number a
     * neighbour's post may have moved on since.
     */
    @Query("select r.zoneId from ChatRoom r where r.id = :id")
    Optional<UUID> zoneOf(@Param("id") UUID id);
}
