package com.delivery.notifications.domain;

import java.util.Collection;
import java.util.Set;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface SuppressedAddressRepository
        extends JpaRepository<SuppressedAddress, SuppressedAddress.Key> {

    /**
     * Which of these addresses are suppressed, in one round trip.
     *
     * <p>Resolving a recipient produces up to four addresses at once, and checking them one at a
     * time would put four queries in front of every notification the platform sends.
     */
    @Query("""
            select s.address from SuppressedAddress s
             where s.channel = :channel and s.address in :addresses
            """)
    Set<String> suppressedAmong(@Param("channel") String channel,
                                @Param("addresses") Collection<String> addresses);
}
